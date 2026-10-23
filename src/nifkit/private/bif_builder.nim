## Shared token emission for text parsing and the editable document API.
import std/[tables, strutils]
import ../[bif_decoder, line_info, codec_limits]
import ./bif_tokens

type TokenBuilder* = object of RootObj
  pos*: int
  limits*: CodecLimits
  poolBytes*: int
  doc*: BifDocument
  tags*, strings*, syms*, files*: Table[string, int]

proc fail(message: string) {.noreturn.} =
  raise newException(BifError, message)

proc poolId*[T](e: var T; pool: var seq[string]; ids: var Table[string, int];
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

proc addToken*[T](e: var T; word: uint32) =
  if e.doc.tokens.len >= e.limits.maxTokens:
    raiseCodecError(nkeTokenLimit, "NIF token count exceeds configured limit", e.pos)
  e.doc.tokens.add word

proc emit*[T](e: var T; kind: uint32; value: uint64) =
  e.addToken (uint32(value and Mask28) shl 4) or kind
  var rest = value shr 28
  while rest > 0:
    e.addToken (uint32(rest and Mask28) shl 4) or KindExtended
    rest = rest shr 28

proc emitLineInfo*[T](e: var T; value: LineInfo) =
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

proc emitSigned*[T](e: var T; value: int64) =
  let bits =
    if value >= -(1'i64 shl 27) and value < (1'i64 shl 27): 28
    elif value >= -(1'i64 shl 55) and value < (1'i64 shl 55): 56
    else: 84
  let encoded = if bits == 84: uint64(value)
                else: uint64(value) and ((1'u64 shl bits) - 1)
  e.emit(KindInt, encoded)

proc emitText*[T](e: var T; kind: uint32; value: string; symbol = false) =
  if value.len > e.limits.maxStringBytes:
    raiseCodecError(nkeStringLimit, "NIF string exceeds configured limit", e.pos)
  if value.len <= 3 and not (kind == KindSymbolDef and value.count('.') >= 2):
    var packed = 1'u64 or (uint64(value.len) shl 1)
    for i, c in value: packed = packed or (uint64(ord(c)) shl (3 + i * 8))
    e.emit(kind, packed)
  else:
    let id = if symbol: e.poolId(e.doc.syms, e.syms, value)
             else: e.poolId(e.doc.strings, e.strings, value)
    e.emit(kind, uint64(id) shl 1)
