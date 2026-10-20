import std/[unittest, strutils]
import ../src/nifkit

suite "NIF to BIF v5 encoder":
  test "reports codec information":
    check codecInfo().contains("NIF/BIF v5")

  test "encodes a basic compound and round-trips through the decoder":
    let source = "(record title \"NIF\" -5 12u)"
    check bifToNif(nifToBif(source)) == source

  test "emits canonical little-endian BIF fixed-width fields":
    let bif = nifToBif("1u")
    check bif[0 ..< 8] == "NIFBIN\0\5"
    check bif[8 ..< 16] == "\x1c\0\0\0\0\0\0\0"
    check bif[24 ..< 28] == "\x14\0\0\0"
    check bifToNif(bif) == "1u"

  test "encodes wide signed integers and a large pooled string":
    let longText = repeat("x", 300)
    let source = "(record -34359738368 \"" & longText & "\")"
    check bifToNif(nifToBif(source)) == source

  test "builds a global symbol index":
    let document = parseBif(nifToBif("(record :thing.0.module x)"))
    check document.index.len == 1
    check document.index[0].visibility == 1

  test "rejects standalone comments because comments are suffixes":
    let source = "(.nif27)\n(.lang \"json\" (oconstr #metadata# (kv title \"NIF\")))"
    expect BifError:
      discard nifToBif(source)

  test "preserves suffix comments on tag heads":
    let source = "(.nif27)\n(.lang \"json\" (oconstr#metadata# (kv title \"NIF\")))"
    check bifToNif(nifToBif(source)) == source

  test "preserves common line-info positions and filenames through BIF":
    let source = "(record@5,3,file.nim title@2,0 \"NIF\"@4,0)"
    check bifToNif(nifToBif(source)) == source

  test "preserves negative relative line-info deltas through BIF":
    let source = "(record@5,3,file.nim title@~2,1)"
    check bifToNif(nifToBif(source)) == source

  test "preserves line-info comments through wide BIF line-info":
    let source = "(record@5,3,file.nim title@2,0#field# \"NIF\"@4,0#literal#)"
    check bifToNif(nifToBif(source)) == source

  test "preserves comment-only suffixes on atoms and tag heads":
    let source = "(add#operator# lhs#left# rhs#right#)"
    check bifToNif(nifToBif(source)) == source

  test "parses escaped identifiers, symbols, filenames, and comments":
    let source = "(call@1,1,file\\20name.nim escaped\\20ident thing\\2E0.mod#has\\23hash# :def\\2E0.mod)"
    check bifToNif(nifToBif(source)) ==
      "(call@1,1,file\\20name.nim escaped\\20ident thing.0.mod#has\\23hash# :def.0.mod)"

  test "parses adjacent empty nodes":
    check bifToNif(nifToBif("...")) == ".\n.\n."

  test "parses exponent-only floating point numbers":
    check bifToNif(nifToBif("1E3")) == "1000.0"

  test "parses signed exponent floating point numbers":
    check bifToNif(nifToBif("1E-3")) == "0.001"
    check bifToNif(nifToBif("1E+3")) == "1000.0"

  test "new numeric spellings produce the existing decimal BIF bytes":
    for (source, decimal) in [
        ("0xFF", "255"), ("0xff", "255"), ("0o377", "255"),
        ("0b1111_1111", "255"), ("-0xFF", "-255"),
        ("0xDEAD_BEEFu", "3735928559u"), ("1_000_000", "1000000"),
        ("1_234.5_6E+0_2", "1234.56E+02"), ("1_0E-0_2", "0.1"),
        ("0x1E3", "483"), ("0x1e3", "483"), ("012", "12"),
        ("-0o377", "-255"), ("-0b1111_1111", "-255"),
        ("0o377u", "255u"), ("0b1111_1111u", "255u"),
        ("1_000u", "1000u"), ("-0x0", "0"), ("-0_0.0", "-0.0")]:
      let bif = nifToBif(source)
      validateBif(bif)
      check bif == nifToBif(decimal)

  test "numeric bases retain the BIF integer widths at boundaries":
    for value in [0'u64, 1'u64, (1'u64 shl 27) - 1, 1'u64 shl 27,
                  (1'u64 shl 55) - 1, 1'u64 shl 55,
                  uint64(int64.high), 1'u64 shl 63, uint64.high]:
      for source in ["0x" & value.toHex(16), "0o" & cast[int64](value).toOct(22),
                     "0b" & cast[int64](value).toBin(64)]:
        check nifToBif(source & "u") == nifToBif($value & "u")
        if value <= uint64(int64.high):
          check nifToBif(source) == nifToBif($value)
          check nifToBif("-" & source) == nifToBif("-" & $value)
    check nifToBif("-0x8000_0000_0000_0000") == nifToBif($int64.low)
    check nifToBif("-0o1000000000000000000000") == nifToBif($int64.low)
    check nifToBif("-0b1" & repeat('0', 63)) == nifToBif($int64.low)

  test "rejects invalid bases separators and overflowing integers":
    for source in ["0x", "0o", "0b", "0o8", "0b102", "0xG", "0XFF",
                   "0x_FF", "0o_77", "0b_11", "1_", "1__2", "1_.0",
                   "1._0", "1E_2", "1E+_2", "1E-_2", "1_u", "1u_",
                   "0xFF_u", "0xF__Fu", "0x1.0", "0o1E3", "0b1.0",
                   "0xFF.0u", "+0xFF", "-1u", "-0x1u", "-0o1u", "-0b1u",
                   "9223372036854775808", "-9223372036854775809",
                   "18446744073709551616u", "0x8000000000000000",
                   "-0x8000000000000001", "0x1_0000_0000_0000_0000u",
                   "0o2000000000000000000000u", "0b1" & repeat('0', 64) & "u"]:
      expect BifError:
        discard nifToBif(source)
    check bifToNif(nifToBif("0xFF")) == "255"

  test "quoted string punctuation retains existing canonical escaping":
    for (source, escaped) in [
        ("\"a#b:c;d\"", "\"a\\23b\\3Ac;d\""),
        ("\"2026-10-11T12:00:00Z\"", "\"2026-10-11T12\\3A00\\3A00Z\""),
        ("\"#:\"", "\"\\23\\3A\""),
        ("\"key: value; # text\"#comment#", "\"key\\3A value; \\23 text\"#comment#")]:
      let bif = nifToBif(source)
      check bif == nifToBif(escaped)
      check bifToNif(bif) == escaped

  test "new number syntax does not reinterpret escaped identifiers or symbols":
    for source in ["\\30xFF", "\\31_000", "x.1_000", "(\\30xFF\\2Ename x)"]:
      let bif = nifToBif(source)
      validateBif(bif)
      check nifToBif(bifToNif(bif)) == bif

  test "core top-level atoms keep their existing interpretation":
    check bifToNif(nifToBif("info 12")) == "info\n12"

  test "rejects invalid unescaped identifiers and symbols":
    for source in ["foo-bar", "1abc", "thing.-0.mod", "(bad-tag x)",
                   "(. x)", "(.123 x)"]:
      expect BifError:
        discard nifToBif(source)

  test "rejects malformed numeric literals":
    for source in ["-", "--1", "1.", "1E", "1E+", "1.0E", "1.0E-", "+1"]:
      expect BifError:
        discard nifToBif(source)

  test "rejects deeply nested NIF before stack exhaustion":
    var limits = defaultCodecLimits()
    limits.maxNestingDepth = 8
    var source = "x"
    for _ in 0 ..< 8:
      source = "(tag " & source & ")"
    check nifToBif(source, limits).len > 0
    source = "(tag " & source & ")"
    try:
      discard nifToBif(source, limits)
      fail()
    except NifKitError as error:
      check error.kind == nkeNestingTooDeep

  test "treats escaped leading digits as identifiers, not numbers":
    check bifToNif(nifToBif("\\31abc")) == "\\31abc"
    check bifToNif(nifToBif("\\31")) == "\\31"

  test "rejects raw control characters inside escaped-data contexts":
    for source in ["\"a(b\"", "'('", "'#'", "':'", "(record#bad:comment# value)",
                   "(record@1,0,file:name value)"]:
      expect BifError:
        discard nifToBif(source)

  test "accepts escaped control characters inside escaped-data contexts":
    check bifToNif(nifToBif("\"a\\23b\"")) == "\"a\\23b\""
    check bifToNif(nifToBif("'\\28'")) == "'\\28'"
    check bifToNif(nifToBif("(record#bad\\3Acomment# value)")) ==
      "(record#bad\\3Acomment# value)"
    check bifToNif(nifToBif("(record@1,0,file\\3Aname value)")) ==
      "(record@1,0,file\\3Aname value)"
