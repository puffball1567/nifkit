import std/unittest
import ../src/nifkit

proc expectKind(kind: NifKitErrorKind; body: proc()) =
  try:
    body()
    fail()
  except NifKitError as error:
    check error.kind == kind

suite "codec limits and structured errors":
  test "input limit is checked before parsing":
    var limits = defaultCodecLimits()
    limits.maxInputBytes = 2
    expectKind(nkeInputTooLarge):
      discard nifToBif("abc", limits)

  test "NIF nesting accepts the boundary and rejects one more":
    var limits = defaultCodecLimits()
    limits.maxNestingDepth = 2
    check nifToBif("(a (b x))", limits).len > 0
    expectKind(nkeNestingTooDeep):
      discard nifToBif("(a (b (c x)))", limits)

  test "NIF token and pool limits are independent":
    var tokenLimits = defaultCodecLimits()
    tokenLimits.maxTokens = 1
    expectKind(nkeTokenLimit):
      discard nifToBif("a b", tokenLimits)
    var poolLimits = defaultCodecLimits()
    poolLimits.maxPoolEntries = 1
    expectKind(nkePoolLimit):
      discard nifToBif("longvalue anotherlongvalue", poolLimits)

  test "BIF output is bounded while rendering":
    let bif = nifToBif("\"abcdef\"")
    var limits = defaultCodecLimits()
    limits.maxOutputBytes = 8
    check bifToNif(bif, limits) == "\"abcdef\""
    limits.maxOutputBytes = 7
    expectKind(nkeOutputTooLarge):
      discard bifToNif(bif, limits)

  test "version failures are distinguishable from malformed data":
    var bif = nifToBif("")
    bif[7] = char(4)
    expectKind(nkeUnsupportedVersion):
      validateBif(bif)

  test "limit errors do not poison a following conversion":
    var limits = defaultCodecLimits()
    limits.maxOutputBytes = 1
    expectKind(nkeOutputTooLarge):
      discard bifToNif(nifToBif("\"x\""), limits)
    check bifToNif(nifToBif("x")) == "x"
