import std/unittest
import ../src/nifkit

proc addLe64(dest: var string; value: uint64) =
  for shift in countup(0, 56, 8):
    dest.add char((value shr shift) and 0xff)

proc addLe32(dest: var string; value: uint32) =
  for shift in countup(0, 24, 8):
    dest.add char((value shr shift) and 0xff)

proc addVarint(dest: var string; value: uint64) =
  if value <= 240:
    dest.add char(value)
  elif value <= 2287:
    let n = value - 240
    dest.add char(241 + (n div 256))
    dest.add char(n mod 256)
  elif value <= 67823:
    let n = value - 2288
    dest.add char(249)
    dest.add char(n shr 8)
    dest.add char(n and 0xff)
  else:
    var bytes = 0
    var n = value
    while n > 0:
      inc bytes
      n = n shr 8
    dest.add char(247 + bytes)
    for shift in countdown((bytes - 1) * 8, 0, 8):
      dest.add char((value shr shift) and 0xff)

proc tinyValidBif(): string =
  result = "NIFBIN\0\5"
  result.addLe64(24) # header 16 + five counts + 3-byte pad
  result.add "\0\0\0\0\0"
  result.add "\0\0\0"
  result.add '\0' # empty index

proc token(kind, payload: uint32): uint32 =
  (payload shl 4) or kind

proc wideToken(kind: uint32; payload: uint64): seq[uint32] =
  result.add token(kind, uint32(payload and 0x0fffffff'u64))
  var rest = payload shr 28
  while rest > 0:
    result.add token(10, uint32(rest and 0x0fffffff'u64))
    rest = rest shr 28

proc bifWithTokens(tokens: openArray[uint32]; index = "\0"): string =
  var counts = ""
  counts.addVarint(uint64(tokens.len))
  counts.add "\0\0\0\0"
  let beforePad = 16 + counts.len
  let pad = (4 - (beforePad and 3)) and 3
  let indexOffset = beforePad + pad + tokens.len * 4
  result = "NIFBIN\0\5"
  result.addLe64(uint64(indexOffset))
  result.add counts
  for _ in 0 ..< pad:
    result.add '\0'
  for word in tokens:
    result.addLe32(word)
  result.add index

proc mustReject(payload: string) =
  try:
    validateBif(payload)
    fail()
  except BifError:
    discard

suite "malformed BIF fuzz and boundary checks":
  test "single-byte truncations fail with recoverable errors":
    let valid = tinyValidBif()
    for n in 0 ..< valid.len:
      mustReject(valid[0 ..< n])

  test "single-byte mutations do not crash":
    let valid = tinyValidBif()
    for i in 0 ..< valid.len:
      var mutated = valid
      mutated[i] = char((ord(mutated[i]) + 17) and 0xff)
      try:
        validateBif(mutated)
      except BifError:
        discard

  test "extended token without a preceding wide token is rejected":
    mustReject(bifWithTokens([token(10, 1)]))

  test "line-info comment extension without a valid comment pool is rejected":
    mustReject(bifWithTokens([token(11, 0), token(10, 1)]))

  test "deep nesting beyond render limit is rejected":
    var tokens: seq[uint32]
    for _ in 0 .. 4097:
      tokens.add wideToken(9, 1'u64 or (1'u64 shl 9))
    tokens.add token(0, 0)
    mustReject(bifWithTokens(tokens))

  test "oversized count varints are rejected before allocation":
    var payload = "NIFBIN\0\5"
    payload.addLe64(16)
    payload.add char(255)
    for _ in 0 ..< 8:
      payload.add char(255)
    mustReject(payload)
