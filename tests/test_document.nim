import std/[unittest, strutils, sequtils, math, options]
import ../src/nifkit

template expectKind(expected: NifKitErrorKind; body: untyped) =
  block:
    var caught = false
    try:
      body
    except NifKitError as error:
      caught = true
      check error.kind == expected
    check caught

suite "editable NIF/BIF documents":
  test "both formats expose every node kind without a typed data profile":
    let source = "(.nif27)\n(record . 'A' \"bytes\\00\\FF\" -9223372036854775808 18446744073709551615u -0.0 thing.0.mod :thing.1.mod name)"
    let text = parseNif(source)
    let binary = parseBifTree(nifToBif(source))
    check text.len == 2
    check text[0].tag == ".nif27"
    check text[1].tag == "record"
    check text[1].len == 9
    check text[1][0].kind == nfEmpty
    check text[1][1].charValue == 'A'
    check text[1][2].text == "bytes\0\xff"
    check text[1][3].intValue == int64.low
    check text[1][4].uintValue == uint64.high
    check cast[uint64](text[1][5].floatValue) == cast[uint64](-0.0)
    check text[1][6].kind == nfSymbol
    check text[1][7].kind == nfSymbolDef
    check text[1][8].kind == nfIdentifier
    check binary.renderNif() == bifToNif(nifToBif(source))
    check text.renderBif() == nifToBif(source)

  test "current NIF spellings retain the existing canonical bytes":
    let source = "(numbers 0xFF 0o377 0b1111_1111 1_000 1_2.5E+0_1 \"key: #value\")"
    let document = parseNif(source)
    check document.renderBif() == nifToBif(source)
    check document.renderNif() == bifToNif(nifToBif(source))

  test "raw non-UTF-8 identifiers strings and characters survive both formats":
    let source = "(record \xffname \"\x80\xff\" '\xff')"
    let document = parseNif(source)
    check document[0][0].text == "\xffname"
    check document[0][1].text == "\x80\xff"
    check document[0][2].charValue == '\xff'
    check parseBifTree(document.renderBif()).renderNif() == source

  test "quoted multiline text and escaped leading digits preserve node kinds":
    let document = parseNif("(tag \\31abc \"a\nb\" \\31.0.x)")
    check document[0][0].kind == nfIdentifier
    check document[0][1].text == "a\nb"
    check document[0][2].kind == nfSymbol
    check parseBifTree(document.renderBif()).renderBif() == document.renderBif()

  test "empty documents and adjacent roots round trip":
    let empty = parseNif("")
    check empty.len == 0
    check empty.renderNif() == ""
    check parseBifTree(empty.renderBif()).len == 0
    let dots = parseNif("...")
    check dots.len == 3
    check dots.renderNif() == ".\n.\n."

  test "low-level document APIs keep their existing representation":
    let source = "(record :name.0.module 7)"
    let tokens: BifDocument = parseNifTokens(source)
    let existing: BifDocument = parseBif(nifToBif(source))
    check tokens.tokens == existing.tokens
    check tokens.index == existing.index
    check renderBifDocument(tokens) == source
    check encodeBifDocument(tokens) == nifToBif(source)

  test "parent handles subtree traversal and self replacement preserve structure":
    let document = parseNif("(root (child 1) 2)")
    check document[0].parent.isNone
    check document[0][0].parent.get == document[0]
    var kinds: seq[NifNodeKind]
    for node in document[0][0].walk(): kinds.add node.kind
    check kinds == @[nfCompound, nfInt]
    document[0] = document[0]
    document[0][0] = document[0][0]
    check document.renderNif() == "(root (child 1) 2)"
    let detached = document[0].remove(0)
    check detached.parent.isNone

  test "standalone NIF validation shares parser and resource errors":
    validateNif("(root 0xFF)")
    var limits = defaultCodecLimits()
    limits.maxContainerItems = 0
    expectKind(nkeTokenLimit): validateNif("x", limits)
    expectKind(nkeMalformedInput): validateNif("(broken")

  test "documents support construction and typed scalar edits":
    let document = newNifDocument()
    let root = document.newCompound("record")
    document.add root
    root.add document.newEmpty()
    root.add document.newChar('A')
    root.add document.newString("old")
    root.add document.newInt(-1)
    root.add document.newUInt(1)
    root.add document.newFloat(1.25)
    root.add document.newIdentifier("name")
    root.add document.newSymbol("name.0.mod")
    root.add document.newSymbolDef("name.1.mod")
    root.tag = "changed"
    root[1].charValue = '\0'
    root[2].text = "new"
    root[3].intValue = int64.low
    root[4].uintValue = uint64.high
    root[5].floatValue = -2.5
    root[6].text = "with space"
    check parseBifTree(document.renderBif()).renderNif() == document.renderNif()
    check document.renderNif().startsWith("(changed . '\\00' \"new\" -9223372036854775808")
    check document.renderNif().contains("with\\20space")
    document.validateDocument()

  test "insert remove replace and detach preserve order and old handles":
    let document = parseNif("(root 1 2) (other)")
    let second = document[0][1]
    let first = document[0].remove(0)
    document[1].add first
    document[0].insert(0, document.newInt(3))
    document[0][1] = document.newString("replaced")
    second.intValue = 20 # Detached by replacement, still valid.
    document[1].add second
    let moved = document.remove(1)
    document.insert(0, moved)
    check document.renderNif() == "(other 1 20)\n(root 3 \"replaced\")"
    moved.detach()
    moved.detach() # Already detached is a no-op.
    document.add moved
    check document[1].tag == "other"

  test "handles stay valid as the arena grows and retain their owner":
    var retained: NifNode
    block:
      let document = parseNif("(root \"kept\")")
      retained = document[0][0]
      for index in 0 ..< 5000: discard document.newInt(index)
    retained.text = "alive"
    check retained.text == "alive"

  test "child iteration remains valid when detached-node creation grows the arena":
    let document = parseNif("(root 1 2 3)")
    var sum = 0'i64
    for child in document[0]:
      for index in 0 ..< 1000: discard document.newInt(index)
      sum += child.intValue
    check sum == 6

  test "cross-document attachment and double attachment fail atomically":
    let document = parseNif("(root 1)")
    let foreign = parseNif("(foreign)")
    let before = document.renderBif()
    expectKind(nkeMalformedInput): document[0].add foreign[0]
    expectKind(nkeMalformedInput): document.add document[0][0]
    expectKind(nkeMalformedInput): document[0][0] = foreign[0]
    check document.renderBif() == before

  test "cycle checks also apply to detached subtrees":
    let document = parseNif("(root (child))")
    let root = document.remove(0)
    expectKind(nkeCyclicReference): root[0].add root
    check root.len == 1
    document.add root
    check document.renderNif() == "(root (child))"
    let single = document.newCompound("self")
    expectKind(nkeCyclicReference): single.add single

  test "invalid handles indexes and wrong scalar access use structured errors":
    let document = parseNif("(root 1)")
    expectKind(nkeMalformedInput): discard document[-1]
    expectKind(nkeMalformedInput): discard document[1]
    expectKind(nkeMalformedInput): discard document[0][2]
    expectKind(nkeMalformedInput): document[0].insert(-1, document.newEmpty())
    expectKind(nkeTypeMismatch): discard document[0].intValue
    expectKind(nkeTypeMismatch): document[0][0].text = "wrong"
    expectKind(nkeTypeMismatch): document[0][0].add document.newEmpty()
    expectKind(nkeMalformedInput): discard NifNode().kind
    expectKind(nkeMalformedInput): discard NifDocument(nil).len

  test "invalid names and positions fail without corrupting a document":
    let document = parseNif("(root name sym.0.mod)")
    expectKind(nkeMalformedInput): document[0].tag = "."
    expectKind(nkeMalformedInput): document[0][0].text = ""
    expectKind(nkeMalformedInput): document[0][1].text = "withoutDot"
    expectKind(nkeMalformedInput): document[0].lineInfo = LineInfo(column: 1024)
    expectKind(nkeMalformedInput): discard document.newCompound(".1bad")
    expectKind(nkeMalformedInput): discard document.newIdentifier("")
    expectKind(nkeMalformedInput): discard document.newSymbol(".bad")
    check document.renderNif() == "(root name sym.0.mod)"

  test "preorder traversal permits scalar edits":
    let document = parseNif("(root 1 (child 2)) 3")
    var visited: seq[NifNodeKind]
    for node in document.walk():
      visited.add node.kind
      if node.kind == nfInt: node.intValue = node.intValue + 10
    check visited == @[nfCompound, nfInt, nfCompound, nfInt, nfInt]
    check document.renderNif() == "(root 11 (child 12))\n13"
    check toSeq(document).len == 2
    check toSeq(document[0]).len == 2

  test "structural changes during iteration are detected":
    let document = parseNif("(root 1 2)")
    expectKind(nkeMalformedInput):
      for node in document.walk():
        if node.kind == nfCompound: node.add document.newEmpty()
    expectKind(nkeMalformedInput):
      for node in document[0]: node.detach()
    expectKind(nkeMalformedInput):
      for node in document: node.detach()

  test "subtrees can be cloned within and between documents":
    let source = parseNif("(root@1,2,file#note# (child \"old\"))")
    let destination = newNifDocument()
    let copy = destination.cloneSubtree(source[0])
    destination.add copy
    source[0][0][0].text = "new"
    check destination[0][0][0].text == "old"
    check destination[0].lineInfo.comment == "note"
    let second = destination.cloneSubtree(copy)
    destination.add second
    copy[0][0].text = "first"
    check second[0][0].text == "old"
    check destination.len == 2

  test "explicit metadata round trips and comments do not inherit":
    let source = "(root@5,3,file.nim#root# child (nested@1,2#nested# \"value\"@2,0#leaf#))"
    let document = parseNif(source)
    check document[0].hasLineInfo
    check not document[0][0].hasLineInfo
    check document[0][0].lineInfo.column == 5
    check document[0][0].lineInfo.line == 3
    check document[0][0].lineInfo.comment == ""
    check document.renderBif() == nifToBif(source)
    check document.renderNif() == source
    document[0].lineInfo = LineInfo(column: 2, line: 10, filename: "other", comment: "updated")
    check document[0][0].lineInfo.line == 10
    check document[0][1].lineInfo.line == 5 # Explicit absolute position retained.
    document[0][1].clearLineInfo()
    check document[0][1].lineInfo.line == 10

  test "symbol indexes are rebuilt after metadata and structural edits":
    let document = parseNif("(defs :name.0.mod@1,0 . :other.0.mod value)")
    let initial = parseBif(document.renderBif())
    check initial.index.len == 2
    check initial.index[0].visibility == 0
    document[0][0].text = "renamed.0.mod"
    document[0].insert(0, document.newString("shift tokens"))
    discard document[0].remove(4)
    let encoded = document.renderBif()
    let indexed = parseBif(encoded)
    check indexed.index.len == 2
    check indexed.syms[int(indexed.index[0].symbolId) - 1] == "renamed.0.mod"
    check (indexed.tokens[int(indexed.index[0].tokenPos)] and 15'u32) == 7'u32
    validateBif(encoded)

  test "short global symbol definitions are pooled for their index":
    let document = newNifDocument()
    document.add document.newSymbolDef("a..")
    let indexed = parseBif(document.renderBif())
    check indexed.index.len == 1
    check indexed.syms[int(indexed.index[0].symbolId) - 1] == "a.."

  test "BIF-only metadata is retained without silently changing NIF positions":
    let document = parseNif("(root@1,2,file child)")
    document[0][0].lineInfo = LineInfo(column: 1, line: 2)
    let encoded = document.renderBif()
    check parseBifTree(encoded)[0][0].lineInfo.filename == ""
    expectKind(nkeMalformedInput): discard document.renderNif()

  test "input and container limits accept their exact boundary":
    let source = "(root 1 2)"
    var limits = defaultCodecLimits()
    limits.maxInputBytes = source.len
    limits.maxContainerItems = 2
    limits.maxNestingDepth = 1
    check parseNif(source, limits)[0].len == 2
    limits.maxInputBytes = source.len - 1
    expectKind(nkeInputTooLarge): discard parseNif(source, limits)
    limits = defaultCodecLimits()
    limits.maxContainerItems = 1
    expectKind(nkeTokenLimit): discard parseNif(source, limits)
    limits = defaultCodecLimits()
    limits.maxNestingDepth = 0
    expectKind(nkeNestingTooDeep): discard parseNif(source, limits)
    check parseNif("1", limits).len == 1

  test "parsing does not consume an intermediate output budget":
    var limits = defaultCodecLimits()
    limits.maxOutputBytes = 0
    let document = parseNif("(root 1)", limits)
    check document[0][0].intValue == 1
    check parseBifTree(nifToBif("(root 1)"), limits).len == 1
    expectKind(nkeOutputTooLarge): discard document.renderNif(limits)
    expectKind(nkeOutputTooLarge): discard document.renderBif(limits)

  test "output token pool string and index budgets apply after edits":
    let document = parseNif("(root \"abcd\" :name.0.mod)")
    let encoded = document.renderBif()
    var limits = defaultCodecLimits()
    limits.maxOutputBytes = encoded.len
    check document.renderBif(limits) == encoded
    dec limits.maxOutputBytes
    expectKind(nkeOutputTooLarge): discard document.renderBif(limits)
    limits = defaultCodecLimits()
    limits.maxTokens = 1
    expectKind(nkeTokenLimit): discard document.renderBif(limits)
    limits = defaultCodecLimits()
    limits.maxPoolEntries = 0
    expectKind(nkePoolLimit): discard document.renderBif(limits)
    limits = defaultCodecLimits()
    limits.maxPoolBytes = 0
    expectKind(nkePoolLimit): discard document.renderBif(limits)
    limits = defaultCodecLimits()
    limits.maxIndexEntries = 0
    expectKind(nkeIndexLimit): discard document.renderBif(limits)
    expectKind(nkeIndexLimit): discard parseNif("(root :name.0.mod)", limits)
    limits = defaultCodecLimits()
    limits.maxStringBytes = 0
    expectKind(nkeStringLimit): discard parseNif("\"a\"", limits)
    expectKind(nkeStringLimit): discard parseNif("\"a\"").renderBif(limits)
    expectKind(nkeStringLimit): discard parseBifTree(nifToBif("\"a\""), limits)

  test "low-level rendering and encoding honor pool and inline string limits":
    let tokens = parseNifTokens("\"long value\"")
    var limits = defaultCodecLimits()
    limits.maxPoolBytes = 0
    expectKind(nkePoolLimit): discard renderBifDocument(tokens, limits)
    expectKind(nkePoolLimit): discard encodeBifDocument(tokens, limits)
    limits = defaultCodecLimits()
    limits.maxPoolEntries = 0
    expectKind(nkePoolLimit): discard renderBifDocument(tokens, limits)
    expectKind(nkePoolLimit): discard encodeBifDocument(tokens, limits)
    limits = defaultCodecLimits()
    limits.maxStringBytes = 0
    expectKind(nkeStringLimit): discard nifToBif("\"a\"", limits)
    expectKind(nkeStringLimit): discard bifToNif(nifToBif("\"a\""), limits)

  test "invalid limits and extreme line info produce recoverable errors":
    var limits = defaultCodecLimits()
    limits.maxTokens = -1
    expectKind(nkeMalformedInput): discard parseNif("x", limits)
    expectKind(nkeMalformedInput): discard parseBifTree("", limits)
    expectKind(nkeMalformedInput): discard parseNif("(root)").renderNif(limits)
    expectKind(nkeMalformedInput): discard parseNif("(root@" & repeat('z', 50) & ")")
    check parseNif("(root)").renderNif() == "(root)"

  test "non-finite BIF floats remain binary data and fail text rendering":
    let document = newNifDocument()
    document.add document.newFloat(Inf)
    let encoded = document.renderBif()
    check parseBifTree(encoded)[0].floatValue == Inf
    check parseBifTree(encoded).renderBif() == encoded
    expectKind(nkeNonFiniteFloat): discard document.renderNif()

  test "high extension bits and wide characters cannot silently truncate":
    for tokenKind in [2'u32, 4'u32, 5'u32, 7'u32]:
      let tokens = BifDocument(
        tokens: @[(2'u32 shl 4) or tokenKind, 10'u32, (256'u32 shl 4) or 10'u32],
        strings: @["value"], syms: @["name.0.mod"])
      let encoded = encodeBifDocument(tokens)
      expectKind(nkeMalformedInput): discard parseBifTree(encoded)
      expectKind(nkeMalformedInput): validateBif(encoded)
    let character = encodeBifDocument(BifDocument(tokens: @[(256'u32 shl 4) or 1'u32]))
    expectKind(nkeMalformedInput): discard parseBifTree(character)
    expectKind(nkeMalformedInput): validateBif(character)
    let negative = encodeBifDocument(BifDocument(tokens: @[
      (0xfffffff'u32 shl 4) or 3'u32,
      (0xfffffff'u32 shl 4) or 10'u32,
      (0xfffffff'u32 shl 4) or 10'u32]))
    check parseBifTree(negative)[0].intValue == -1

  test "truncation and single-byte mutation do not escape structured errors":
    let encoded = nifToBif("(root :name.0.mod \"value\" 0xFF)")
    for length in 0 ..< encoded.len:
      expectKind(nkeMalformedInput): discard parseBifTree(encoded[0 ..< length])
    for index in 0 ..< encoded.len:
      var changed = encoded
      changed[index] = char(ord(changed[index]) xor 0x5a)
      try:
        let document = parseBifTree(changed)
        discard parseBifTree(document.renderBif())
      except NifKitError: discard

  test "deep documents parse traverse clone and render without recursive stacks":
    const Depth = 10_000
    let source = repeat("(a ", Depth) & "1" & repeat(")", Depth)
    let document = parseNif(source)
    var visited = 0
    for node in document.walk():
      discard node.kind
      inc visited
    check visited == Depth + 1
    check document.renderNif() == source
    let copy = newNifDocument()
    copy.add copy.cloneSubtree(document[0])
    check parseBifTree(copy.renderBif()).renderNif() == source
    var limits = defaultCodecLimits()
    limits.maxNestingDepth = Depth
    check parseNif(source, limits).len == 1
    dec limits.maxNestingDepth
    expectKind(nkeNestingTooDeep): discard parseNif(source, limits)
    expectKind(nkeNestingTooDeep): discard document.renderBif(limits)

  test "wide tag jumps preserve binary representation at the extension boundary":
    for count in [524287, 524288]:
      let source = "(a " & repeat(". ", count - 1) & ".)"
      let document = parseNif(source)
      check document[0].len == count
      let encoded = document.renderBif()
      check encoded == nifToBif(source)
      check parseBifTree(encoded)[0].len == count
