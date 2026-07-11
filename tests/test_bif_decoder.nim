import std/unittest
import ../src/nifkit

proc addLe64(dest: var string; value: uint64) =
  for shift in countup(0, 56, 8): dest.add char((value shr shift) and 0xff)

proc inlineStringBif(value: string): string =
  doAssert value.len <= 3
  var payload = 1'u32 or (uint32(value.len) shl 1)
  for i, c in value: payload = payload or (uint32(ord(c)) shl (3 + i * 8))
  let token = (payload shl 4) or 2'u32
  result = "NIFBIN\0\5"
  result.addLe64(28) # header 16 + five one-byte counts + 3-byte pad + token
  result.add char(1) # token count
  result.add "\0\0\0\0" # tags, strings, symbols, filenames
  result.add "\0\0\0" # alignment padding
  for shift in countup(0, 24, 8): result.add char((token shr shift) and 0xff)
  result.add '\0' # empty index

proc addLe32(dest: var string; value: uint32) =
  for shift in countup(0, 24, 8): dest.add char((value shr shift) and 0xff)

proc specificationBif(tokens: openArray[uint32]; tags, strings, syms,
                      files: openArray[string]; index = "\0"): string =
  doAssert tokens.len < 241 and tags.len < 241 and strings.len < 241
  doAssert syms.len < 241 and files.len < 241
  var pools = ""
  for pool in [tags, strings, syms, files]:
    for item in pool:
      doAssert item.len < 241
      pools.add char(item.len)
      pools.add item
  let beforePad = 16 + 5
  let pad = (4 - (beforePad and 3)) and 3
  let indexOffset = beforePad + pad + tokens.len * 4 + pools.len
  result = "NIFBIN\0\5"
  result.addLe64(uint64(indexOffset))
  result.add char(tokens.len)
  result.add char(tags.len)
  result.add char(strings.len)
  result.add char(syms.len)
  result.add char(files.len)
  for _ in 0 ..< pad: result.add '\0'
  for token in tokens: result.addLe32(token)
  result.add pools
  result.add index

proc token(kind, payload: uint32): uint32 = (payload shl 4) or kind

suite "BIF v5 decoder":
  test "decodes a specification-shaped inline string":
    let bytes = inlineStringBif("hi")
    check bifToNif(bytes) == "\"hi\""
    validateBif(bytes)

  test "rejects an incompatible magic":
    expect BifError:
      validateBif("not-bif")

  test "decodes tag, pool string, numeric atoms, and line info":
    let tag = token(9, 1 or (6 shl 9)) # tag id 1, six body tokens
    let pooledString = token(2, 2) # strings pool id 1 (id << 1)
    let signedMinusFive = token(3, (1'u32 shl 28) - 5)
    let unsignedTwelve = token(4, 12)
    let extendedUIntHead = token(4, 1)
    let extendedUIntTail = token(10, 1)
    let lineInfo = token(11, 0)
    let bytes = specificationBif(
      [tag, pooledString, signedMinusFive, unsignedTwelve,
       extendedUIntHead, extendedUIntTail, lineInfo],
      ["record"], ["longer value"], [], [])
    check bifToNif(bytes) == "(record \"longer value\" -5 12u 268435457u@0,0)"

  test "rejects a tag jump beyond the token block":
    let badTag = token(9, 1 or (2 shl 9))
    expect BifError:
      discard bifToNif(specificationBif([badTag], ["record"], [], [], []))

  test "decodes char, symbol, float, and escaped strings":
    let charA = token(1, uint32(ord('A')))
    let symbol = token(6, 2) # symbol pool id 1
    let floatBits = cast[uint64](1.5)
    let floatHead = token(5, uint32(floatBits and 0x0fffffff'u64))
    let floatTail1 = token(10, uint32((floatBits shr 28) and 0x0fffffff'u64))
    let floatTail2 = token(10, uint32(floatBits shr 56))
    let escaped = inlineStringBif("a\\b")
    check bifToNif(specificationBif([charA, symbol, floatHead, floatTail1, floatTail2],
      [], [], ["thing.0.module"], [])) == "'A'\nthing.0.module\n1.5"
    check bifToNif(escaped) == "\"a\\|b\""

  test "renders BIF identifiers without changing them into symbols or numbers":
    let dottedIdent = token(8, 2) # strings pool id 1
    let digitIdent = token(8, 4) # strings pool id 2
    let hyphenIdent = token(8, 6) # strings pool id 3
    check bifToNif(specificationBif([dottedIdent, digitIdent, hyphenIdent],
      [], ["foo.bar", "1abc", "foo-bar"], [], [])) ==
      "foo\\2Ebar\n\\31abc\nfoo\\2Dbar"

  test "renders BIF symbols with escaped non-symbol bytes":
    let symbol = token(6, 2) # symbol pool id 1
    check bifToNif(specificationBif([symbol], [], [], ["thing.-0.module"], [])) ==
      "thing.\\2D0.module"

  test "rejects BIF identifiers and symbols that cannot form NIF atoms":
    let emptyIdent = token(8, 2) # strings pool id 1
    expect BifError:
      discard bifToNif(specificationBif([emptyIdent], [], [""], [], []))
    let symbolWithoutSeparator = token(6, 2) # symbol pool id 1
    expect BifError:
      discard bifToNif(specificationBif([symbolWithoutSeparator], [], [], ["abc"], []))

  test "renders BIF tag names without changing tag grammar":
    let normalTag = token(9, 1) # tag id 1, no children
    check bifToNif(specificationBif([normalTag], ["foo.bar"], [], [], [])) ==
      "(foo\\2Ebar)"
    check bifToNif(specificationBif([normalTag], [".nif27"], [], [], [])) ==
      "(.nif27)"
    expect BifError:
      discard bifToNif(specificationBif([normalTag], ["."], [], [], []))
    expect BifError:
      discard bifToNif(specificationBif([normalTag], [".123"], [], [], []))

  test "rejects invalid index references":
    let oneSymbol = token(6, 2)
    # nIndex=1, symbol id=2 (out of range), token position=0, visibility=0.
    expect BifError:
      validateBif(specificationBif([oneSymbol], [], [], ["x.0.module"], [],
                                    "\1\2\0\0"))

  test "rejects index counts that cannot fit in the remaining bytes":
    let oneSymbol = token(6, 2)
    expect BifError:
      validateBif(specificationBif([oneSymbol], [], [], ["x.0.module"], [],
                                    "\10"))

  test "rejects trailing bytes after the BIF index":
    var bytes = inlineStringBif("hi")
    bytes.add "extra"
    expect BifError:
      validateBif(bytes)

  test "rejects non-zero alignment padding":
    var bytes = inlineStringBif("hi")
    bytes[21] = '\1'
    expect BifError:
      validateBif(bytes)

  test "rejects truncated pool strings":
    let oneString = token(2, 2)
    var bytes = specificationBif([oneString], [], ["abcdef"], [], [])
    bytes.setLen(bytes.len - 3)
    expect BifError:
      validateBif(bytes)

  test "rejects unsupported token kinds":
    let unsupported = token(12, 0)
    expect BifError:
      discard bifToNif(specificationBif([unsupported], [], [], [], []))

  test "rejects line-info filename references outside the filename pool":
    # Short line-info format: file id is bits 7..13. file id 1 is invalid here
    # because the filename pool is empty.
    let lineInfoWithMissingFile = token(11, 1'u32 shl 7)
    expect BifError:
      discard bifToNif(specificationBif([lineInfoWithMissingFile], [], [], [], []))

  test "rejects values wider than 64 bits":
    let tooWideInt = token(3, 1)
    let ext = token(10, 1)
    expect BifError:
      discard bifToNif(specificationBif([tooWideInt, ext, ext, ext], [], [], [], []))
