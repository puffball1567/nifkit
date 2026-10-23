## Shared binary token details; not a public integration boundary.
import ../[line_info, codec_limits]

const
  KindDot* = 0'u32
  KindChar* = 1'u32
  KindString* = 2'u32
  KindInt* = 3'u32
  KindUInt* = 4'u32
  KindFloat* = 5'u32
  KindSymbol* = 6'u32
  KindSymbolDef* = 7'u32
  KindIdent* = 8'u32
  KindTag* = 9'u32
  KindExtended* = 10'u32
  KindLineInfo* = 11'u32

const Mask28* = 0x0fffffff'u64

proc fail(message: string; offset = -1) {.noreturn.} =
  raiseCodecError(nkeMalformedInput, message, offset)

proc kind*(word: uint32): uint32 {.inline.} = word and 0x0f'u32
proc payload*(word: uint32): uint64 {.inline.} = uint64(word shr 4)

proc widePayload*[T](doc: T; pos: int): tuple[value: uint64, next: int] =
  if pos >= doc.tokens.len: fail("invalid BIF token position")
  result.value = payload(doc.tokens[pos])
  result.next = pos + 1
  var shift = 28
  while result.next < doc.tokens.len and kind(doc.tokens[result.next]) == KindExtended:
    if shift >= 64: fail("BIF value exceeds supported width")
    let chunk = payload(doc.tokens[result.next])
    if shift == 56 and chunk > 255:
      # The 84-bit signed carrier may sign-extend an int64. Other high bits
      # would be silently discarded by a uint64 shift and must be rejected.
      if kind(doc.tokens[pos]) != KindInt or (chunk shr 8) != 0xfffff or
          (chunk and 0x80) == 0:
        fail("BIF value exceeds supported width")
    result.value = result.value or (chunk shl shift)
    shift += 28
    inc result.next

proc isAsciiLetter*(c: char): bool =
  c in {'A'..'Z'} or c in {'a'..'z'}

proc isIdentStartByte*(c: char): bool =
  isAsciiLetter(c) or c == '_' or ord(c) >= 128

proc isIdentCharByte*(c: char): bool =
  isIdentStartByte(c) or c in {'0'..'9'}

proc validatePools*[T](doc: T; limits: CodecLimits) =
  var totalBytes = 0
  for pool in [doc.tags, doc.strings, doc.syms, doc.filenames]:
    if pool.len > limits.maxPoolEntries:
      raiseCodecError(nkePoolLimit, "BIF pool entry count exceeds configured limit")
    for value in pool:
      if value.len > limits.maxStringBytes:
        raiseCodecError(nkeStringLimit, "BIF string exceeds configured limit")
      if value.len > limits.maxPoolBytes - totalBytes:
        raiseCodecError(nkePoolLimit, "BIF pools exceed configured byte limit")
      totalBytes += value.len

proc textValue*[T](doc: T; value: uint64; symbols: bool;
                   limits = defaultCodecLimits()): string =
  if (value and 1) == 1:
    let n = int((value shr 1) and 3)
    for i in 0 ..< n: result.add char((value shr (3 + i * 8)) and 0xff)
  else:
    let id = value shr 1
    let pool = if symbols: doc.syms else: doc.strings
    if id == 0 or id > uint64(pool.len): fail("invalid BIF string pool id")
    result = pool[int(id) - 1]
  if result.len > limits.maxStringBytes:
    raiseCodecError(nkeStringLimit, "BIF string exceeds configured limit")

proc takeLineInfo*[T](doc: T; pos: var int; parent: LineInfo):
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
