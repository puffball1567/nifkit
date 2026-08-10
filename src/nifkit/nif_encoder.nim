## Initial NIF text -> BIF v5 encoder, implemented from the public spec.

import std/[tables, strutils]
import ./bif_decoder
import ./line_info

const
  Mask28 = 0x0fffffff'u64
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

type Encoder = object
  input: string
  pos: int
  limits: CodecLimits
  depth: int
  poolBytes: int
  doc: BifDocument
  tags: Table[string, int]
  strings: Table[string, int]
  syms: Table[string, int]
  files: Table[string, int]

type BareAtom = object
  text: string
  escaped: seq[bool]
  rawInvalid: bool

proc fail(message: string) {.noreturn.} =
  raise newException(BifError, message)

proc skipSpace(e: var Encoder) =
  while e.pos < e.input.len:
    if e.input[e.pos] in {' ', '\t', '\r', '\n'}: inc e.pos
    else: break

proc isAsciiLetter(c: char): bool =
  c in {'A'..'Z'} or c in {'a'..'z'}

proc isIdentStartByte(c: char): bool =
  isAsciiLetter(c) or c == '_' or ord(c) >= 128

proc isIdentCharByte(c: char): bool =
  isIdentStartByte(c) or c in {'0'..'9'}

proc isSymbolText(atom: BareAtom): bool =
  let value = atom.text
  let dot = value.find('.')
  if dot <= 0:
    return false
  if not atom.escaped[0] and not isIdentStartByte(value[0]):
    return false
  var hasSeparator = false
  for i, c in value:
    if c == '.' and not atom.escaped[i]:
      if i == 0:
        return false
      hasSeparator = true
    elif atom.escaped[i] or isIdentCharByte(c):
      discard
    else:
      return false
  hasSeparator

proc isIdentText(atom: BareAtom): bool =
  let value = atom.text
  if value.len == 0 or not isIdentStartByte(value[0]):
    if value.len == 0 or not atom.escaped[0]:
      return false
  for i, c in value:
    if not (atom.escaped[i] or isIdentCharByte(c)):
      return false
  true

proc isDirectiveTagText(atom: BareAtom): bool =
  let value = atom.text
  if value.len <= 1 or value[0] != '.' or atom.escaped[0]:
    return false
  if not (atom.escaped[1] or isIdentStartByte(value[1])):
    return false
  for i in 2 ..< value.len:
    if not (atom.escaped[i] or isIdentCharByte(value[i])):
      return false
  true

proc hasEscapedBytes(atom: BareAtom): bool =
  for value in atom.escaped:
    if value: return true

proc scanDigits(value: string; pos: var int): int =
  while pos < value.len and value[pos] in {'0'..'9'}:
    inc pos
    inc result

proc isUIntLiteral(value: string): bool =
  if value.len < 2 or value[^1] != 'u': return false
  for i in 0 ..< value.len - 1:
    if value[i] notin {'0'..'9'}: return false
  true

proc isSignedIntLiteral(value: string): bool =
  var pos = 0
  if pos < value.len and value[pos] == '-': inc pos
  let digits = scanDigits(value, pos)
  digits > 0 and pos == value.len

proc isFloatLiteral(value: string): bool =
  var pos = 0
  if pos < value.len and value[pos] == '-': inc pos
  if scanDigits(value, pos) == 0: return false
  if pos < value.len and value[pos] == '.':
    inc pos
    if scanDigits(value, pos) == 0: return false
    if pos < value.len and value[pos] == 'E':
      inc pos
      if pos < value.len and value[pos] in {'+', '-'}: inc pos
      if scanDigits(value, pos) == 0: return false
    return pos == value.len
  if pos < value.len and value[pos] == 'E':
    inc pos
    if pos < value.len and value[pos] in {'+', '-'}: inc pos
    if scanDigits(value, pos) == 0: return false
    return pos == value.len
  false

proc bare(e: var Encoder): BareAtom =
  let start = e.pos
  while e.pos < e.input.len and e.input[e.pos] notin
      {' ', '\t', '\r', '\n', '(', ')', '[', ']', '{', '}', '~', '#', '\'', '"', ':', '@'}:
    if e.input[e.pos] == '\\':
      result.text.add readNifEscape(e.input, e.pos)
      result.escaped.add true
    else:
      let c = e.input[e.pos]
      if not (isIdentCharByte(c) or c == '.'):
        result.rawInvalid = true
      result.text.add c
      result.escaped.add false
      inc e.pos
  if e.pos == start: fail("expected NIF atom")

proc poolId(e: var Encoder; pool: var seq[string]; ids: var Table[string, int];
            value: string): int =
  if value in ids: return ids[value]
  if value.len > e.limits.maxStringBytes:
    raiseCodecError(nkeStringLimit, "NIF string exceeds configured limit", e.pos)
  if pool.len >= e.limits.maxPoolEntries or
      value.len > e.limits.maxPoolBytes - e.poolBytes:
    raiseCodecError(nkePoolLimit, "NIF pools exceed configured limit", e.pos)
  result = pool.len + 1
  pool.add value
  e.poolBytes += value.len
  ids[value] = result

proc addToken(e: var Encoder; word: uint32) =
  if e.doc.tokens.len >= e.limits.maxTokens:
    raiseCodecError(nkeTokenLimit, "NIF token count exceeds configured limit", e.pos)
  e.doc.tokens.add word

proc emit(e: var Encoder; kind: uint32; value: uint64) =
  e.addToken (uint32(value and Mask28) shl 4) or kind
  var rest = value shr 28
  while rest > 0:
    e.addToken (uint32(rest and Mask28) shl 4) or KindExtended
    rest = rest shr 28

proc emitLineInfo(e: var Encoder; value: LineInfo) =
  if value.column < 0 or value.column > 1023:
    fail("NIF line-info column exceeds the supported BIF layout")
  if value.line < 0 or value.line > uint32.high.int64:
    fail("NIF line-info line exceeds the supported BIF layout")
  let fileId =
    if value.filename.len == 0: 0
    else: e.poolId(e.doc.filenames, e.files, value.filename)
  if fileId > 16383:
    fail("NIF line-info filename pool id exceeds the supported BIF layout")
  if value.comment.len == 0 and value.column <= 127 and value.line <= 16383 and fileId <= 127:
    let packed = uint64(value.column) or
      (uint64(fileId) shl 7) or
      (uint64(value.line) shl 14)
    e.emit(KindLineInfo, packed)
  else:
    let commentId =
      if value.comment.len == 0: 0
      else: e.poolId(e.doc.strings, e.strings, value.comment)
    if commentId > int(Mask28):
      fail("NIF line-info comment pool id exceeds the supported BIF layout")
    let packed = uint64(value.column) or
      (uint64(fileId) shl 10) or
      (uint64(value.line) shl 24)
    e.addToken (uint32(packed and Mask28) shl 4) or KindLineInfo
    e.addToken (uint32((packed shr 28) and Mask28) shl 4) or KindExtended
    if commentId > 0:
      e.addToken (uint32(commentId) shl 4) or KindExtended

proc emitSigned(e: var Encoder; value: int64) =
  let bits =
    if value >= -(1'i64 shl 27) and value < (1'i64 shl 27): 28
    elif value >= -(1'i64 shl 55) and value < (1'i64 shl 55): 56
    else: 84
  let encoded = if bits == 84: uint64(value)
                else: uint64(value) and ((1'u64 shl bits) - 1)
  e.emit(KindInt, encoded)

proc emitText(e: var Encoder; kind: uint32; value: string; symbol = false) =
  if value.len <= 3:
    var packed = 1'u64 or (uint64(value.len) shl 1)
    for i, c in value: packed = packed or (uint64(ord(c)) shl (3 + i * 8))
    e.emit(kind, packed)
  else:
    let id = if symbol: e.poolId(e.doc.syms, e.syms, value)
             else: e.poolId(e.doc.strings, e.strings, value)
    e.emit(kind, uint64(id) shl 1)

proc parseNode(e: var Encoder; parent: LineInfo)

proc attachSuffix(e: var Encoder; parent: LineInfo): LineInfo =
  result = parent
  if e.pos < e.input.len and e.input[e.pos] in {'@', '~'}:
    result = parseLineInfo(e.input, e.pos, parent)
    e.emitLineInfo(result)
  elif e.pos < e.input.len and e.input[e.pos] == '#':
    inc e.pos
    result.comment = unescapeNifData(e.input, e.pos, {'#'})
    if e.pos >= e.input.len: fail("unterminated NIF comment suffix")
    inc e.pos
    e.emitLineInfo(result)

proc parseCompound(e: var Encoder; parent: LineInfo) =
  if e.depth >= e.limits.maxNestingDepth:
    raiseCodecError(nkeNestingTooDeep, "NIF nesting exceeds configured depth", e.pos)
  inc e.depth
  defer: dec e.depth
  inc e.pos # '('
  e.skipSpace()
  let tagAtom = e.bare()
  let tag = tagAtom.text
  if tagAtom.rawInvalid or
      (tag.startsWith(".") and not isDirectiveTagText(tagAtom)) or
      (not tag.startsWith(".") and not isIdentText(tagAtom)):
    fail("invalid NIF tag name")
  let tagId = e.poolId(e.doc.tags, e.tags, tag)
  if tagId > 511: fail("NIF has more than 511 BIF tags")
  let head = e.doc.tokens.len
  e.emit(KindTag, uint64(tagId))
  let nodeInfo = e.attachSuffix(parent)
  let bodyStart = e.doc.tokens.len
  e.skipSpace()
  while e.pos < e.input.len and e.input[e.pos] != ')':
    e.parseNode(nodeInfo)
    e.skipSpace()
  if e.pos >= e.input.len: fail("unterminated NIF compound node")
  inc e.pos
  let jump = e.doc.tokens.len - bodyStart
  e.doc.tokens[head] =
    (uint32(uint64(tagId) or (uint64(jump and 0x7ffff) shl 9)) shl 4) or KindTag
  if jump > 524287:
    let high = uint64(jump shr 19)
    if high > Mask28: fail("BIF tag jump exceeds version 5 limit")
    if e.doc.tokens.len >= e.limits.maxTokens:
      raiseCodecError(nkeTokenLimit, "NIF token count exceeds configured limit", e.pos)
    e.doc.tokens.insert((uint32(high) shl 4) or KindExtended, head + 1)

proc parseNode(e: var Encoder; parent: LineInfo) =
  e.skipSpace()
  if e.pos >= e.input.len: fail("expected NIF node")
  case e.input[e.pos]
  of '(':
    e.parseCompound(parent)
  of '.':
    inc e.pos
    e.emit(KindDot, 0)
    discard e.attachSuffix(parent)
  of '"':
    inc e.pos
    e.emitText(KindString, unescapeNifData(e.input, e.pos, {'"'}))
    if e.pos >= e.input.len: fail("unterminated NIF string literal")
    inc e.pos
    discard e.attachSuffix(parent)
  of '\'':
    inc e.pos
    var value: string
    if e.pos >= e.input.len:
      fail("unterminated NIF character literal")
    if e.input[e.pos] == '\\':
      value.add readNifEscape(e.input, e.pos)
    else:
      let c = e.input[e.pos]
      if ord(c) < 32 or isRawNifControl(c):
        fail("NIF character literal contains an unescaped control byte")
      value.add c
      inc e.pos
    if e.pos >= e.input.len or e.input[e.pos] != '\'':
      fail("unterminated NIF character literal")
    inc e.pos
    if value.len != 1: fail("NIF character literal must contain one byte")
    e.emit(KindChar, uint64(ord(value[0])))
    discard e.attachSuffix(parent)
  of ':':
    inc e.pos
    let sym = e.bare()
    if sym.rawInvalid or not isSymbolText(sym):
      fail("invalid NIF symbol definition")
    e.emitText(KindSymbolDef, sym.text, true)
    discard e.attachSuffix(parent)
  else:
    let parsed = e.bare()
    let atom = parsed.text
    if not parsed.hasEscapedBytes and isUIntLiteral(atom):
      e.emit(KindUInt, parseBiggestUInt(atom[0 .. ^2]).uint64)
    elif not parsed.hasEscapedBytes and isFloatLiteral(atom):
      e.emit(KindFloat, cast[uint64](parseFloat(atom)))
    elif not parsed.hasEscapedBytes and isSignedIntLiteral(atom):
      let value = parseBiggestInt(atom)
      e.emitSigned(value)
    elif atom.contains('.'):
      if parsed.rawInvalid or not isSymbolText(parsed):
        fail("invalid NIF symbol")
      e.emitText(KindSymbol, atom, true)
    else:
      if parsed.rawInvalid or not isIdentText(parsed):
        fail("invalid NIF identifier")
      e.emitText(KindIdent, atom)
    discard e.attachSuffix(parent)

proc addLe64(dest: var string; value: uint64; limits: CodecLimits) =
  for shift in countup(0, 56, 8): dest.boundedAdd(char((value shr shift) and 0xff), limits)

proc addLe32(dest: var string; value: uint32; limits: CodecLimits) =
  for shift in countup(0, 24, 8): dest.boundedAdd(char((value shr shift) and 0xff), limits)

proc varintLen(value: uint64): int =
  if value <= 240:
    1
  elif value <= 2287:
    2
  elif value <= 67823:
    3
  else:
    var bytes = 0
    var n = value
    while n > 0:
      inc bytes
      n = n shr 8
    if bytes < 3: bytes = 3
    if bytes > 8: fail("BIF varint exceeds uint64")
    bytes + 1

proc addVarint(dest: var string; value: uint64; limits: CodecLimits) =
  if value <= 240:
    dest.boundedAdd(char(value), limits)
  elif value <= 2287:
    let n = value - 240
    dest.boundedAdd(char(241 + (n div 256)), limits)
    dest.boundedAdd(char(n mod 256), limits)
  elif value <= 67823:
    let n = value - 2288
    dest.boundedAdd(char(249), limits)
    dest.boundedAdd(char(n shr 8), limits)
    dest.boundedAdd(char(n and 0xff), limits)
  else:
    let bytes = varintLen(value) - 1
    dest.boundedAdd(char(247 + bytes), limits)
    for shift in countdown((bytes - 1) * 8, 0, 8):
      dest.boundedAdd(char((value shr shift) and 0xff), limits)

proc addOutputSize(total: var int; amount: int; limits: CodecLimits) =
  if amount < 0 or total > limits.maxOutputBytes - amount:
    raiseCodecError(nkeOutputTooLarge, "BIF output exceeds configured limit")
  total += amount

proc tokenValue(tokens: seq[uint32]; pos: int): tuple[value: uint64, next: int] =
  result.value = uint64(tokens[pos] shr 4)
  result.next = pos + 1
  var shift = 28
  while result.next < tokens.len and (tokens[result.next] and 0x0f'u32) == KindExtended:
    if shift >= 64: fail("BIF value exceeds supported width")
    result.value = result.value or (uint64(tokens[result.next] shr 4) shl shift)
    shift += 28
    inc result.next

proc globalIndex(e: Encoder): seq[tuple[symbolId: uint64, tokenPos: uint64, visibility: uint64]] =
  var pos = 0
  while pos < e.doc.tokens.len:
    let k = e.doc.tokens[pos] and 0x0f'u32
    let value = tokenValue(e.doc.tokens, pos)
    if k == KindSymbolDef:
      let id = value.value shr 1
      if id > 0 and id <= uint64(e.doc.syms.len) and e.doc.syms[int(id) - 1].count('.') >= 2:
        let visibility = if value.next < e.doc.tokens.len and
            (e.doc.tokens[value.next] and 0x0f'u32) == KindDot: 0'u64 else: 1'u64
        result.add (id, uint64(pos), visibility)
    pos = value.next

proc encodeBifDocument*(document: BifDocument; limits = defaultCodecLimits()): string =
  validLimits(limits)
  if document.tokens.len > limits.maxTokens:
    raiseCodecError(nkeTokenLimit, "BIF token count exceeds configured limit")
  var e = Encoder(doc: document)
  var headerSize = 16
  for count in [e.doc.tokens.len, e.doc.tags.len, e.doc.strings.len, e.doc.syms.len, e.doc.filenames.len]:
    headerSize.addOutputSize(varintLen(uint64(count)), limits)
  let pad = (4 - (headerSize and 3)) and 3
  var totalSize = headerSize
  totalSize.addOutputSize(pad, limits)
  if e.doc.tokens.len > limits.maxOutputBytes div 4:
    raiseCodecError(nkeOutputTooLarge, "BIF output exceeds configured limit")
  totalSize.addOutputSize(e.doc.tokens.len * 4, limits)
  for pool in [e.doc.tags, e.doc.strings, e.doc.syms, e.doc.filenames]:
    for value in pool:
      totalSize.addOutputSize(varintLen(uint64(value.len)), limits)
      totalSize.addOutputSize(value.len, limits)
  let indexOffset = totalSize
  let index = e.globalIndex()
  if index.len > limits.maxIndexEntries:
    raiseCodecError(nkeIndexLimit, "NIF index count exceeds configured limit")
  totalSize.addOutputSize(varintLen(uint64(index.len)), limits)
  for entry in index:
    totalSize.addOutputSize(varintLen(entry.symbolId), limits)
    totalSize.addOutputSize(varintLen(entry.tokenPos), limits)
    totalSize.addOutputSize(varintLen(entry.visibility), limits)
  result = newStringOfCap(totalSize)
  result.boundedAdd("NIFBIN\0\5", limits)
  result.addLe64(uint64(indexOffset), limits)
  result.addVarint(uint64(e.doc.tokens.len), limits)
  result.addVarint(uint64(e.doc.tags.len), limits)
  result.addVarint(uint64(e.doc.strings.len), limits)
  result.addVarint(uint64(e.doc.syms.len), limits)
  result.addVarint(uint64(e.doc.filenames.len), limits)
  for _ in 0 ..< pad: result.boundedAdd('\0', limits)
  for token in e.doc.tokens: result.addLe32(token, limits)
  for pool in [e.doc.tags, e.doc.strings, e.doc.syms, e.doc.filenames]:
    for value in pool:
      result.addVarint(uint64(value.len), limits)
      result.boundedAdd(value, limits)
  result.addVarint(uint64(index.len), limits)
  for entry in index:
    result.addVarint(entry.symbolId, limits)
    result.addVarint(entry.tokenPos, limits)
    result.addVarint(entry.visibility, limits)

proc encodeNifToBif(nifText: string; limits: CodecLimits): string =
  validLimits(limits)
  if nifText.len > limits.maxInputBytes:
    raiseCodecError(nkeInputTooLarge, "NIF input exceeds configured limit")
  var e = Encoder(input: nifText, limits: limits)
  e.skipSpace()
  while e.pos < e.input.len:
    e.parseNode(LineInfo())
    e.skipSpace()
  encodeBifDocument(e.doc, limits)

proc nifToBif*(nifText: string; limits = defaultCodecLimits()): string =
  try:
    result = encodeNifToBif(nifText, limits)
    if result.len > limits.maxOutputBytes:
      raiseCodecError(nkeOutputTooLarge, "BIF output exceeds configured limit")
  except BifError:
    raise
  except CatchableError:
    fail(getCurrentExceptionMsg())
