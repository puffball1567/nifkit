import std/unittest
import ../src/nifkit

proc expectKind(kind: NifKitErrorKind; body: proc()) =
  try:
    body()
    fail()
  except NifKitError as error:
    check error.kind == kind

suite "codec limits and structured errors":
  test "omitted limits do not impose an application policy":
    let limits = defaultCodecLimits()
    check limits == unlimitedCodecLimits()
    check limits.maxInputBytes == high(int)
    check limits.maxOutputBytes == high(int)
    check limits.maxNestingDepth == high(int)
    check limits.maxTokens == high(int)
    check limits.maxPoolEntries == high(int)
    check limits.maxPoolBytes == high(int)
    check limits.maxStringBytes == high(int)
    check limits.maxIndexEntries == high(int)
    check limits.maxContainerItems == high(int)
    check limits.maxObjectFields == high(int)
    check limits.maxTrackedReferences == high(int)

  test "NIF input accepts the exact limit and rejects one byte more":
    var limits = defaultCodecLimits()
    limits.maxInputBytes = 3
    check nifToBif("abc", limits).len > 0
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
    check nifToBif("a", tokenLimits).len > 0
    expectKind(nkeTokenLimit):
      discard nifToBif("a b", tokenLimits)
    var poolLimits = defaultCodecLimits()
    poolLimits.maxPoolEntries = 1
    check nifToBif("longvalue", poolLimits).len > 0
    expectKind(nkePoolLimit):
      discard nifToBif("longvalue anotherlongvalue", poolLimits)

  test "NIF string and pool bytes accept the boundary and reject one more":
    var stringLimits = defaultCodecLimits()
    stringLimits.maxStringBytes = 6
    check nifToBif("\"abcdef\"", stringLimits).len > 0
    stringLimits.maxStringBytes = 5
    expectKind(nkeStringLimit):
      discard nifToBif("\"abcdef\"", stringLimits)
    var poolLimits = defaultCodecLimits()
    poolLimits.maxPoolBytes = 6
    check nifToBif("\"abcdef\"", poolLimits).len > 0
    poolLimits.maxPoolBytes = 5
    expectKind(nkePoolLimit):
      discard nifToBif("\"abcdef\"", poolLimits)

  test "NIF BIF output accepts the exact limit and rejects one more":
    let encoded = nifToBif("x")
    var limits = defaultCodecLimits()
    limits.maxOutputBytes = encoded.len
    check nifToBif("x", limits) == encoded
    limits.maxOutputBytes = encoded.len - 1
    expectKind(nkeOutputTooLarge):
      discard nifToBif("x", limits)

  test "BIF headers remain valid when pool counts use multi-byte varints":
    var source = ""
    for i in 0 ..< 241:
      if source.len > 0: source.add ' '
      source.add "\"value" & $i & "\""
    let encoded = nifToBif(source)
    validateBif(encoded)
    check nifToBif(bifToNif(encoded)) == encoded
    var limits = defaultCodecLimits()
    limits.maxOutputBytes = encoded.len
    check nifToBif(source, limits) == encoded
    limits.maxOutputBytes = encoded.len - 1
    expectKind(nkeOutputTooLarge):
      discard nifToBif(source, limits)

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

  test "BIF pool, string, token, and index limits have separate kinds":
    let stringBif = nifToBif("\"abcdef\"")
    var stringLimits = defaultCodecLimits()
    stringLimits.maxStringBytes = 6
    validateBif(stringBif, stringLimits)
    stringLimits.maxStringBytes = 5
    expectKind(nkeStringLimit):
      validateBif(stringBif, stringLimits)
    var poolLimits = defaultCodecLimits()
    poolLimits.maxPoolBytes = 6
    validateBif(stringBif, poolLimits)
    poolLimits.maxPoolBytes = 5
    expectKind(nkePoolLimit):
      validateBif(stringBif, poolLimits)
    var tokenLimits = defaultCodecLimits()
    tokenLimits.maxTokens = 1
    validateBif(stringBif, tokenLimits)
    tokenLimits.maxTokens = 0
    expectKind(nkeTokenLimit):
      validateBif(stringBif, tokenLimits)
    let indexedBif = nifToBif("(defs :pkg.0.public)")
    var indexLimits = defaultCodecLimits()
    indexLimits.maxIndexEntries = 1
    validateBif(indexedBif, indexLimits)
    indexLimits.maxIndexEntries = 0
    expectKind(nkeIndexLimit):
      validateBif(indexedBif, indexLimits)

  test "BIF input and nesting accept the exact limit and reject one more":
    let bif = nifToBif("(a (b x))")
    var inputLimits = defaultCodecLimits()
    inputLimits.maxInputBytes = bif.len
    validateBif(bif, inputLimits)
    inputLimits.maxInputBytes = bif.len - 1
    expectKind(nkeInputTooLarge):
      validateBif(bif, inputLimits)
    var depthLimits = defaultCodecLimits()
    depthLimits.maxNestingDepth = 2
    check bifToNif(bif, depthLimits) == "(a (b x))"
    depthLimits.maxNestingDepth = 1
    expectKind(nkeNestingTooDeep):
      discard bifToNif(bif, depthLimits)

  test "magic and endianness remain malformed input":
    var magic = nifToBif("")
    magic[0] = 'X'
    expectKind(nkeMalformedInput):
      validateBif(magic)
    var endian = nifToBif("")
    endian[6] = char(1)
    expectKind(nkeMalformedInput):
      validateBif(endian)

  test "limit errors do not poison a following conversion":
    var limits = defaultCodecLimits()
    limits.maxOutputBytes = 1
    expectKind(nkeOutputTooLarge):
      discard bifToNif(nifToBif("\"x\""), limits)
    check bifToNif(nifToBif("x")) == "x"
