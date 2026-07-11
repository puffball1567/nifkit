## BIF v5 decoder implemented from the published NIF/BIF specification.

import ./line_info

type
  BifError* = object of ValueError

  BifDocument* = object
    tokens*: seq[uint32]
    tags*: seq[string]
    strings*: seq[string]
    syms*: seq[string]
    filenames*: seq[string]
    index*: seq[tuple[symbolId: uint64, tokenPos: uint64, visibility: uint64]]

const
  BifMagic = "NIFBIN\0\5"
  MaxRenderDepth = 4096
  KindDot = 0'u32
  KindChar = 1'u32
  KindString = 2'u32
  KindInt = 3'u32
  KindUInt = 4'u32
  KindFloat = 5'u32
  KindSymbol = 6'u32
  KindSymbolDef = 7'u32
  KindIdent = 8'u32
  KindTag = 9'u32
  KindExtended = 10'u32
  KindLineInfo = 11'u32

proc fail(message: string) {.noreturn.} =
  raise newException(BifError, message)

proc byteAt(data: string; pos: var int): uint8 =
  if pos >= data.len: fail("truncated BIF")
  result = uint8(ord(data[pos]))
  inc pos

proc readLe32(data: string; pos: var int): uint32 =
  for shift in countup(0, 24, 8):
    result = result or (uint32(byteAt(data, pos)) shl shift)

proc readLe64(data: string; pos: var int): uint64 =
  for shift in countup(0, 56, 8):
    result = result or (uint64(byteAt(data, pos)) shl shift)

proc readVarint(data: string; pos: var int): uint64 =
  let a = uint64(byteAt(data, pos))
  if a <= 240: return a
  if a <= 248: return (a - 241) * 256 + uint64(byteAt(data, pos)) + 240
  if a == 249:
    return 2288 + uint64(byteAt(data, pos)) * 256 + uint64(byteAt(data, pos))
  let count = int(a - 247)
  for _ in 0 ..< count:
    result = (result shl 8) or uint64(byteAt(data, pos))

proc readString(data: string; pos: var int): string =
  let n = readVarint(data, pos)
  if n > uint64(data.len - pos): fail("truncated BIF string pool")
  result = data[pos ..< pos + int(n)]
  pos += int(n)

proc parseBif*(data: string): BifDocument =
  if data.len < 16 or data[0 ..< 8] != BifMagic:
    fail("invalid BIF magic, endianness, or version")
  var pos = 8
  let indexOffset = readLe64(data, pos)
  let tokenCount = readVarint(data, pos)
  let tagCount = readVarint(data, pos)
  let stringCount = readVarint(data, pos)
  let symCount = readVarint(data, pos)
  let fileCount = readVarint(data, pos)
  let pad = (4 - (pos and 3)) and 3
  for _ in 0 ..< pad:
    if byteAt(data, pos) != 0: fail("invalid BIF alignment padding")
  if tokenCount > uint64((data.len - pos) div 4): fail("truncated BIF token block")
  result.tokens = newSeq[uint32](int(tokenCount))
  for i in 0 ..< result.tokens.len: result.tokens[i] = readLe32(data, pos)
  template readPool(target: untyped; count: uint64) =
    if count > uint64(data.len): fail("invalid BIF pool count")
    target = newSeq[string](int(count))
    for i in 0 ..< target.len: target[i] = readString(data, pos)
  readPool(result.tags, tagCount)
  readPool(result.strings, stringCount)
  readPool(result.syms, symCount)
  readPool(result.filenames, fileCount)
  if indexOffset != uint64(pos) or indexOffset >= uint64(data.len):
    fail("invalid BIF index offset")
  var indexPos = int(indexOffset)
  let indexCount = readVarint(data, indexPos)
  if indexCount > uint64((data.len - indexPos) div 3):
    fail("invalid BIF index count")
  result.index = newSeq[tuple[symbolId: uint64, tokenPos: uint64, visibility: uint64]](int(indexCount))
  for i in 0 ..< int(indexCount):
    let symbolId = readVarint(data, indexPos)
    let tokenPos = readVarint(data, indexPos)
    let visibility = readVarint(data, indexPos)
    if symbolId == 0 or symbolId > uint64(result.syms.len):
      fail("invalid BIF index symbol id")
    if tokenPos >= uint64(result.tokens.len):
      fail("invalid BIF index token position")
    if visibility > 1: fail("invalid BIF index visibility")
    result.index[i] = (symbolId, tokenPos, visibility)
  if indexPos != data.len:
    fail("unexpected trailing BIF data")

proc kind(word: uint32): uint32 {.inline.} = word and 0x0f'u32
proc payload(word: uint32): uint64 {.inline.} = uint64(word shr 4)

proc widePayload(doc: BifDocument; pos: int): tuple[value: uint64, next: int] =
  if pos >= doc.tokens.len: fail("invalid BIF token position")
  result.value = payload(doc.tokens[pos])
  result.next = pos + 1
  var shift = 28
  while result.next < doc.tokens.len and kind(doc.tokens[result.next]) == KindExtended:
    if shift >= 64: fail("BIF value exceeds supported width")
    result.value = result.value or (payload(doc.tokens[result.next]) shl shift)
    shift += 28
    inc result.next

proc escapeString(value: string): string =
  const Hex = "0123456789ABCDEF"
  for c in value:
    let b = ord(c)
    if c == '"': result.add "\\^"
    elif c == '\\': result.add "\\|"
    elif b == 10: result.add "\\n"
    elif b == 9: result.add "\\t"
    elif b == 13: result.add "\\r"
    elif b < 32 or c in {'(', ')', '[', ']', '{', '}', '~', '#', '\'', ':', '@'}:
      result.add '\\'
      result.add Hex[b shr 4]
      result.add Hex[b and 15]
    else: result.add c

proc isAsciiLetter(c: char): bool =
  c in {'A'..'Z'} or c in {'a'..'z'}

proc isIdentStartByte(c: char): bool =
  isAsciiLetter(c) or c == '_' or ord(c) >= 128

proc isIdentCharByte(c: char): bool =
  isIdentStartByte(c) or c in {'0'..'9'}

proc addEscapedByte(dest: var string; c: char) =
  const Hex = "0123456789ABCDEF"
  let b = ord(c)
  dest.add '\\'
  dest.add Hex[b shr 4]
  dest.add Hex[b and 15]

proc renderIdentifier(value: string): string =
  if value.len == 0: fail("invalid empty BIF identifier")
  for i, c in value:
    if (i == 0 and isIdentStartByte(c)) or (i > 0 and isIdentCharByte(c)):
      result.add c
    else:
      result.addEscapedByte c

proc renderSymbolName(value: string): string =
  let separator = value.find('.')
  if separator <= 0: fail("invalid BIF symbol")
  for i, c in value:
    if i == separator:
      result.add '.'
    elif i < separator:
      if (i == 0 and isIdentStartByte(c)) or (i > 0 and isIdentCharByte(c)):
        result.add c
      else:
        result.addEscapedByte c
    elif c == '.' or isIdentCharByte(c):
      result.add c
    else:
      result.addEscapedByte c

proc renderTagName(value: string): string =
  if value.len == 0: fail("invalid empty BIF tag")
  if value[0] == '.':
    if value.len == 1: fail("invalid empty BIF directive tag")
    if not isIdentStartByte(value[1]):
      fail("invalid BIF directive tag")
    result.add '.'
    for i in 1 ..< value.len:
      let c = value[i]
      if isIdentCharByte(c):
        result.add c
      else:
        result.addEscapedByte c
  else:
    result = renderIdentifier(value)

proc textValue(doc: BifDocument; value: uint64; symbols: bool): string =
  if (value and 1) == 1:
    let n = int((value shr 1) and 3)
    for i in 0 ..< n: result.add char((value shr (3 + i * 8)) and 0xff)
  else:
    let id = int(value shr 1)
    let pool = if symbols: doc.syms else: doc.strings
    if id <= 0 or id > pool.len: fail("invalid BIF string pool id")
    result = pool[id - 1]

proc takeLineInfo(doc: BifDocument; pos: var int; parent: LineInfo):
    tuple[present: bool, value: LineInfo] =
  if pos >= doc.tokens.len or kind(doc.tokens[pos]) != KindLineInfo:
    return (false, parent)
  result.present = true
  let first = payload(doc.tokens[pos])
  var fileId: int
  if pos + 1 < doc.tokens.len and kind(doc.tokens[pos + 1]) == KindExtended:
    let second = payload(doc.tokens[pos + 1])
    let packed = first or (second shl 28)
    result.value.column = int64(packed and 0x3ff)
    fileId = int((packed shr 10) and 0x3fff)
    result.value.line = int64((packed shr 24) and 0xffffffff'u64)
    pos += 2
    if pos < doc.tokens.len and kind(doc.tokens[pos]) == KindExtended:
      let commentId = int(payload(doc.tokens[pos]))
      inc pos
      if commentId <= 0 or commentId > doc.strings.len:
        fail("invalid BIF line-info comment id")
      result.value.comment = doc.strings[commentId - 1]
  else:
    fileId = int((first shr 7) and 0x7f)
    result.value.column = int64(first and 0x7f)
    result.value.line = int64((first shr 14) and 0x3fff)
    inc pos
  if fileId > doc.filenames.len:
    fail("invalid BIF line-info filename id")
  result.value.filename =
    if fileId == 0: ""
    else: doc.filenames[fileId - 1]

proc render(doc: BifDocument; pos: int; limit: int; parent: LineInfo; depth: int): tuple[text: string, next: int]

proc render(doc: BifDocument; pos: int; limit: int; parent: LineInfo; depth: int): tuple[text: string, next: int] =
  if depth > MaxRenderDepth: fail("BIF nesting exceeds supported depth")
  if pos >= limit: fail("BIF node exceeds parent boundary")
  let k = kind(doc.tokens[pos])
  let wide = doc.widePayload(pos)
  var next = wide.next
  case k
  of KindDot: result.text = "."
  of KindChar: result.text = "'" & escapeString($char(wide.value and 0xff)) & "'"
  of KindString: result.text = "\"" & escapeString(doc.textValue(wide.value, false)) & "\""
  of KindIdent: result.text = renderIdentifier(doc.textValue(wide.value, false))
  of KindSymbol: result.text = renderSymbolName(doc.textValue(wide.value, true))
  of KindSymbolDef: result.text = ":" & renderSymbolName(doc.textValue(wide.value, true))
  of KindInt:
    let bits = min(64, 28 * (wide.next - pos))
    let signed = if bits == 64: cast[int64](wide.value) else:
      let sign = 1'u64 shl (bits - 1)
      if (wide.value and sign) == 0: int64(wide.value)
      else: int64(wide.value) - (1'i64 shl bits)
    result.text = $signed
  of KindUInt: result.text = $wide.value & "u"
  of KindFloat: result.text = $cast[float64](wide.value)
  of KindTag:
    let tagId = int(wide.value and 0x1ff)
    if tagId <= 0 or tagId > doc.tags.len: fail("invalid BIF tag id")
    let jump = int(wide.value shr 9)
    let lineInfo = doc.takeLineInfo(next, parent)
    let childParent = if lineInfo.present: lineInfo.value else: parent
    let bodyEnd = next + jump
    if bodyEnd > limit or bodyEnd > doc.tokens.len: fail("invalid BIF tag jump")
    result.text = "(" & renderTagName(doc.tags[tagId - 1])
    if lineInfo.present: result.text.add renderLineInfo(lineInfo.value, parent)
    while next < bodyEnd:
      let child = doc.render(next, bodyEnd, childParent, depth + 1)
      result.text.add " " & child.text
      next = child.next
    if next != bodyEnd: fail("invalid BIF tag body")
    result.text.add ")"
  else: fail("unsupported BIF token kind")
  let lineInfo = doc.takeLineInfo(next, parent)
  if lineInfo.present: result.text.add renderLineInfo(lineInfo.value, parent)
  result.next = next

proc bifToNif*(bifBytes: string): string =
  let document = parseBif(bifBytes)
  var pos = 0
  while pos < document.tokens.len:
    let value = document.render(pos, document.tokens.len, LineInfo(), 0)
    if result.len > 0: result.add '\n'
    result.add value.text
    pos = value.next

proc validateBif*(bifBytes: string) =
  discard bifToNif(bifBytes)
