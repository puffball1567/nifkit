import std/[unittest, strutils]
import ../src/nifkit

suite "NIF to BIF v5 encoder":
  test "reports codec information":
    check codecInfo().contains("NIF/BIF v5")

  test "encodes a basic compound and round-trips through the decoder":
    let source = "(record title \"NIF\" -5 12u)"
    check bifToNif(nifToBif(source)) == source

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

  test "rejects invalid unescaped identifiers and symbols":
    for source in ["foo-bar", "1abc", "thing.-0.mod", "(bad-tag x)",
                   "(. x)", "(.123 x)"]:
      expect BifError:
        discard nifToBif(source)

  test "rejects malformed numeric literals":
    for source in ["-", "--1", "1.", "1E", "1E+", "1.0E", "1.0E-", "+1"]:
      expect BifError:
        discard nifToBif(source)

  test "treats escaped leading digits as identifiers, not numbers":
    check bifToNif(nifToBif("\\31abc")) == "\\31abc"
    check bifToNif(nifToBif("\\31")) == "\\31"

  test "rejects raw control characters inside escaped-data contexts":
    for source in ["\"a#b\"", "\"a(b\"", "'('", "(record#bad:comment# value)",
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
