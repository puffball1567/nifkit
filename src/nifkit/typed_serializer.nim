## Typed NIF data profile v1.  This module is intentionally Nim-only.

import std/[options, strutils, typetraits, math, tables, sets, algorithm, unicode, macros]
import ./[codec_limits, nif_encoder, bif_decoder]

const
  DataRootTag = "nifkit\\2Ddata"
  DataRootName = "nifkit-data"
  BifKindChar = 1'u32
  BifKindString = 2'u32
  BifKindInt = 3'u32
  BifKindUInt = 4'u32
  BifKindFloat = 5'u32
  BifKindIdent = 8'u32
  BifKindTag = 9'u32
  BifKindExtended = 10'u32

type
  TypedCodecOptions* = object
    allowUnknownFields*: bool
    requireTypeNames*: bool

  DataKind = enum dkAtom, dkString, dkChar, dkCompound
  DataNode = ref object
    kind: DataKind
    text: string
    children: seq[DataNode]
    offset: int

var activeReferences {.threadvar.}: seq[pointer]

proc containsRecCase(node: NimNode): bool {.compileTime.} =
  if node.kind == nnkRecCase:
    return true
  for child in node:
    if containsRecCase(child):
      return true

macro isVariantObject(T: typedesc): untyped =
  var impl = T.getTypeImpl
  if impl.kind == nnkBracketExpr and impl[0].eqIdent("typeDesc"):
    impl = impl[1].getTypeImpl
  while impl.kind in {nnkSym, nnkTypeDef}:
    if impl.kind == nnkSym:
      impl = impl.getImpl
    else:
      impl = impl[2]
  newLit(containsRecCase(impl))

proc defaultTypedCodecOptions*(): TypedCodecOptions =
  TypedCodecOptions(requireTypeNames: true)

proc typedFail(kind: NifKitErrorKind; message, path: string; offset = -1) {.noreturn.} =
  raiseCodecError(kind, message, offset, path)

proc require(node: DataNode; tag, path: string): seq[DataNode] =
  if node.kind != dkCompound or node.children.len == 0 or
      node.children[0].kind != dkAtom or
      (node.children[0].text != tag and
        not (tag == DataRootTag and node.children[0].text == DataRootName)):
    typedFail(nkeTypeMismatch, "expected " & tag, path, node.offset)
  result = node.children

proc quote(value: string; limits: CodecLimits; path: string): string =
  if value.len > limits.maxStringBytes:
    typedFail(nkeStringLimit, "string exceeds configured limit", path)
  if validateUtf8(value) >= 0:
    typedFail(nkeInvalidUtf8, "string is not valid UTF-8", path)
  result = "\""
  for c in value:
    let b = ord(c)
    if c == '"': result.boundedAdd("\\^", limits)
    elif c == '\\': result.boundedAdd("\\|", limits)
    elif c == '\n': result.boundedAdd("\\n", limits)
    elif c == '\t': result.boundedAdd("\\t", limits)
    elif c == '\r': result.boundedAdd("\\r", limits)
    elif b < 32 or c in {'(', ')', '[', ']', '{', '}', '~', '#', '\'', ':', '@'}:
      result.boundedAdd("\\" & "0123456789ABCDEF"[b shr 4] & "0123456789ABCDEF"[b and 15], limits)
    else: result.boundedAdd(c, limits)
  result.boundedAdd('"', limits)

proc render(node: DataNode; destination: var string; limits: CodecLimits; path: string) =
  case node.kind
  of dkAtom: destination.boundedAdd(node.text, limits)
  of dkString: destination.boundedAdd(quote(node.text, limits, path), limits)
  of dkChar:
    destination.boundedAdd('\'', limits)
    destination.boundedAdd(quote(node.text, limits, path)[1 .. ^2], limits)
    destination.boundedAdd('\'', limits)
  of dkCompound:
    destination.boundedAdd('(', limits)
    for i, child in node.children:
      if i > 0: destination.boundedAdd(' ', limits)
      child.render(destination, limits, path)
    destination.boundedAdd(')', limits)

proc skipSpace(source: string; pos: var int) =
  while pos < source.len and source[pos] in {' ', '\t', '\r', '\n'}: inc pos

proc hex(c: char): int =
  if c in {'0'..'9'}: ord(c) - ord('0')
  elif c in {'A'..'F'}: ord(c) - ord('A') + 10
  else: -1

proc parseEscaped(source: string; pos: var int; terminator: char; path: string): string =
  while pos < source.len and source[pos] != terminator:
    if source[pos] != '\\':
      result.add source[pos]
      inc pos
    else:
      inc pos
      if pos >= source.len: typedFail(nkeMalformedInput, "truncated escape", path, pos)
      let c = source[pos]
      inc pos
      case c
      of 'n': result.add '\n'
      of 't': result.add '\t'
      of 'r': result.add '\r'
      of '^': result.add '"'
      of '|': result.add '\\'
      of '0'..'9', 'A'..'F':
        if pos >= source.len: typedFail(nkeMalformedInput, "truncated hex escape", path, pos)
        let lo = hex(source[pos]); let hi = hex(c); inc pos
        if hi < 0 or lo < 0: typedFail(nkeMalformedInput, "invalid hex escape", path, pos)
        result.add char((hi shl 4) or lo)
      else: typedFail(nkeMalformedInput, "unsupported escape", path, pos)
  if pos >= source.len: typedFail(nkeMalformedInput, "unterminated literal", path, pos)

proc parseNode(source: string; pos: var int; limits: CodecLimits; depth: int): DataNode =
  if depth > limits.maxNestingDepth: typedFail(nkeNestingTooDeep, "typed NIF nesting exceeds limit", "$", pos)
  skipSpace(source, pos)
  if pos >= source.len: typedFail(nkeMalformedInput, "expected typed NIF value", "$", pos)
  result = DataNode(offset: pos)
  case source[pos]
  of '(':
    result.kind = dkCompound; inc pos
    while true:
      skipSpace(source, pos)
      if pos >= source.len: typedFail(nkeMalformedInput, "unterminated compound", "$", pos)
      if source[pos] == ')': inc pos; break
      if result.children.len >= limits.maxContainerItems: typedFail(nkeTokenLimit, "container exceeds configured limit", "$", pos)
      result.children.add parseNode(source, pos, limits, depth + 1)
  of '"':
    result.kind = dkString; inc pos; result.text = parseEscaped(source, pos, '"', "$"); inc pos
  of '\'':
    result.kind = dkChar; inc pos; result.text = parseEscaped(source, pos, '\'', "$"); inc pos
    if result.text.len != 1: typedFail(nkeTypeMismatch, "character must contain one byte", "$", result.offset)
  else:
    result.kind = dkAtom
    let start = pos
    while pos < source.len and source[pos] notin {' ', '\t', '\r', '\n', '(', ')'}: inc pos
    if start == pos: typedFail(nkeMalformedInput, "expected atom", "$", pos)
    result.text = source[start ..< pos]

proc bifKind(token: uint32): uint32 {.inline.} = token and 0x0f'u32

proc bifWidePayload(document: BifDocument; pos: int): tuple[value: uint64, next: int] =
  if pos >= document.tokens.len:
    typedFail(nkeMalformedInput, "invalid BIF token position", "$")
  result.value = uint64(document.tokens[pos] shr 4)
  result.next = pos + 1
  var shift = 28
  while result.next < document.tokens.len and bifKind(document.tokens[result.next]) == BifKindExtended:
    if shift >= 64:
      typedFail(nkeMalformedInput, "BIF value exceeds supported width", "$")
    result.value = result.value or (uint64(document.tokens[result.next] shr 4) shl shift)
    shift += 28
    inc result.next

proc bifString(document: BifDocument; value: uint64; offset: int): string =
  if (value and 1) == 1:
    let count = int((value shr 1) and 3)
    for i in 0 ..< count:
      result.add char((value shr (3 + i * 8)) and 0xff)
  else:
    let id = int(value shr 1)
    if id <= 0 or id > document.strings.len:
      typedFail(nkeMalformedInput, "invalid BIF string pool id", "$", offset)
    result = document.strings[id - 1]

proc parseBifNode(document: BifDocument; pos: var int; limit, depth: int;
                  limits: CodecLimits): DataNode =
  if depth > limits.maxNestingDepth:
    typedFail(nkeNestingTooDeep, "typed BIF nesting exceeds limit", "$", pos)
  if pos >= limit:
    typedFail(nkeMalformedInput, "BIF node exceeds parent boundary", "$", pos)
  result = DataNode(offset: pos)
  let tokenPos = pos
  let tokenKind = bifKind(document.tokens[pos])
  let wide = bifWidePayload(document, pos)
  pos = wide.next
  case tokenKind
  of BifKindChar:
    if wide.value > 0xff:
      typedFail(nkeMalformedInput, "invalid BIF character", "$", tokenPos)
    result.kind = dkChar
    result.text = $char(wide.value)
  of BifKindString:
    result.kind = dkString
    result.text = bifString(document, wide.value, tokenPos)
  of BifKindIdent:
    result.kind = dkAtom
    result.text = bifString(document, wide.value, tokenPos)
  of BifKindInt:
    result.kind = dkAtom
    let bits = min(64, 28 * (wide.next - tokenPos))
    let signed = if bits == 64: cast[int64](wide.value) else:
      let sign = 1'u64 shl (bits - 1)
      if (wide.value and sign) == 0: int64(wide.value)
      else: int64(wide.value) - (1'i64 shl bits)
    result.text = $signed
  of BifKindUInt:
    result.kind = dkAtom
    result.text = $wide.value & "u"
  of BifKindFloat:
    result.kind = dkAtom
    result.text = $cast[float64](wide.value)
  of BifKindTag:
    let tagId = int(wide.value and 0x1ff)
    let jump64 = wide.value shr 9
    if tagId <= 0 or tagId > document.tags.len or jump64 > uint64(high(int)):
      typedFail(nkeMalformedInput, "invalid BIF tag", "$", tokenPos)
    let bodyEnd = pos + int(jump64)
    if bodyEnd > limit or bodyEnd > document.tokens.len:
      typedFail(nkeMalformedInput, "invalid BIF tag jump", "$", tokenPos)
    result.kind = dkCompound
    result.children.add DataNode(kind: dkAtom, text: document.tags[tagId - 1])
    while pos < bodyEnd:
      if result.children.len >= limits.maxContainerItems:
        typedFail(nkeTokenLimit, "container exceeds configured limit", "$", pos)
      result.children.add parseBifNode(document, pos, bodyEnd, depth + 1, limits)
    if pos != bodyEnd:
      typedFail(nkeMalformedInput, "invalid BIF tag body", "$", tokenPos)
  else:
    typedFail(nkeMalformedInput, "unsupported BIF token in typed data", "$", tokenPos)

proc nodeAtom(value: string): DataNode = DataNode(kind: dkAtom, text: value)
proc nodeString(value: string): DataNode = DataNode(kind: dkString, text: value)
proc compound(tag: string; values: varargs[DataNode]): DataNode =
  DataNode(kind: dkCompound, children: @[nodeAtom(tag)] & @values)

proc encodeValue[T](value: T; limits: CodecLimits; path: string): DataNode

proc encodeTable[T](value: T; limits: CodecLimits; path: string): DataNode =
  var entries: seq[(string, DataNode)]
  if value.len > limits.maxContainerItems:
    typedFail(nkeTokenLimit, "table exceeds configured limit", path)
  for key, item in value.pairs:
    let keyNode = encodeValue(key, limits, path & ".<key>")
    var keyText = ""
    keyNode.render(keyText, limits, path & ".<key>")
    entries.add (keyText, compound("entry", keyNode,
      encodeValue(item, limits, path & "[" & keyText & "]")))
  entries.sort(proc(a, b: (string, DataNode)): int = cmp(a[0], b[0]))
  var values = @[nodeAtom("table")]
  for entry in entries:
    values.add entry[1]
  DataNode(kind: dkCompound, children: values)

proc encodeSet[T](value: T; limits: CodecLimits; path: string): DataNode =
  var entries: seq[(string, DataNode)]
  if value.len > limits.maxContainerItems:
    typedFail(nkeTokenLimit, "set exceeds configured limit", path)
  for item in value:
    let itemNode = encodeValue(item, limits, path & ".<item>")
    var itemText = ""
    itemNode.render(itemText, limits, path & ".<item>")
    entries.add (itemText, itemNode)
  entries.sort(proc(a, b: (string, DataNode)): int = cmp(a[0], b[0]))
  var values = @[nodeAtom("set")]
  for entry in entries:
    values.add entry[1]
  DataNode(kind: dkCompound, children: values)

proc encodeValue[T](value: T; limits: CodecLimits; path: string): DataNode =
  when T is cstring:
    typedFail(nkeUnsupportedType, "cstring is unsupported by the typed data profile", path)
  elif T is distinct:
    type Base = distinctBase(T)
    compound("distinct", nodeString(name(T)), encodeValue(Base(value), limits, path))
  elif T is bool:
    nodeAtom(if value: "true" else: "false")
  elif T is SomeUnsignedInt:
    nodeAtom($value & "u")
  elif T is SomeSignedInt:
    nodeAtom($value)
  elif T is SomeFloat:
    if classify(value) in {fcNan, fcInf, fcNegInf}:
      typedFail(nkeNonFiniteFloat, "non-finite float is unsupported", path)
    nodeAtom($value)
  elif T is string:
    nodeString(value)
  elif T is char:
    DataNode(kind: dkChar, text: $value)
  elif T is enum:
    compound("enum", nodeString(name(T)), nodeString($value))
  elif T is Option:
    if value.isSome: compound("some", encodeValue(value.get, limits, path)) else: nodeAtom("none")
  elif T is Table:
    encodeTable(value, limits, path)
  elif T is OrderedTable:
    encodeTable(value, limits, path)
  elif T is HashSet:
    encodeSet(value, limits, path)
  elif T is OrderedSet:
    encodeSet(value, limits, path)
  elif T is seq:
    var values = @[nodeAtom("seq")]
    if value.len > limits.maxContainerItems: typedFail(nkeTokenLimit, "sequence exceeds configured limit", path)
    for i, item in value: values.add encodeValue(item, limits, path & "[" & $i & "]")
    DataNode(kind: dkCompound, children: values)
  elif T is array:
    var values = @[nodeAtom("array")]
    for i, item in value: values.add encodeValue(item, limits, path & "[" & $i & "]")
    DataNode(kind: dkCompound, children: values)
  elif T is tuple:
    var values = @[nodeAtom("tuple")]
    for name, item in fieldPairs(value): values.add encodeValue(item, limits, path & "." & name)
    DataNode(kind: dkCompound, children: values)
  elif T is ref:
    if value.isNil:
      nodeAtom("nil")
    else:
      let address = cast[pointer](value)
      for active in activeReferences:
        if active == address:
          typedFail(nkeCyclicReference, "cyclic ref object is unsupported", path)
      if activeReferences.len >= limits.maxTrackedReferences:
        typedFail(nkeTokenLimit, "reference tracking exceeds configured limit", path)
      activeReferences.add address
      defer: activeReferences.setLen(activeReferences.len - 1)
      compound("ref", encodeValue(value[], limits, path))
  elif T is object:
    when isVariantObject(T):
      typedFail(nkeUnsupportedType, "variant object support is not available yet", path)
    else:
      var values = @[nodeAtom("object"), nodeString(name(T))]
      var count = 0
      for fieldName, fieldValue in fieldPairs(value):
        inc count
        if count > limits.maxObjectFields: typedFail(nkeTokenLimit, "object exceeds configured field limit", path)
        values.add compound("field", nodeString(fieldName), encodeValue(fieldValue, limits, path & "." & fieldName))
      DataNode(kind: dkCompound, children: values)
  else:
    typedFail(nkeUnsupportedType, "unsupported typed NIF value: " & name(T), path)

proc toNif*[T](value: T; limits = defaultCodecLimits()): string =
  validLimits(limits)
  if activeReferences.len != 0:
    activeReferences.setLen(0)
  let root = compound(DataRootTag, nodeAtom("1"), encodeValue(value, limits, "$"))
  root.render(result, limits, "$")

proc toBif*[T](value: T; limits = defaultCodecLimits()): string =
  nifToBif(toNif(value, limits), limits)

proc decodeValue[T](node: DataNode; limits: CodecLimits; options: TypedCodecOptions;
                    path: string): T

proc decodeTableEntry[K, V](target: var Table[K, V]; entry: DataNode;
                            limits: CodecLimits; options: TypedCodecOptions;
                            path: string) =
  if entry.kind != dkCompound or entry.children.len != 3 or
      entry.children[0].kind != dkAtom or entry.children[0].text != "entry":
    typedFail(nkeTypeMismatch, "invalid table entry", path, entry.offset)
  let key = decodeValue[K](entry.children[1], limits, options, path & ".<key>")
  if target.hasKey(key):
    typedFail(nkeTypeMismatch, "duplicate table key", path, entry.offset)
  target[key] = decodeValue[V](entry.children[2], limits, options, path & "[key]")

proc decodeOrderedTableEntry[K, V](target: var OrderedTable[K, V]; entry: DataNode;
                                   limits: CodecLimits; options: TypedCodecOptions;
                                   path: string) =
  if entry.kind != dkCompound or entry.children.len != 3 or
      entry.children[0].kind != dkAtom or entry.children[0].text != "entry":
    typedFail(nkeTypeMismatch, "invalid table entry", path, entry.offset)
  let key = decodeValue[K](entry.children[1], limits, options, path & ".<key>")
  if target.hasKey(key):
    typedFail(nkeTypeMismatch, "duplicate table key", path, entry.offset)
  target[key] = decodeValue[V](entry.children[2], limits, options, path & "[key]")

proc decodeSetItem[E](target: var HashSet[E]; node: DataNode;
                      limits: CodecLimits; options: TypedCodecOptions; path: string) =
  let item = decodeValue[E](node, limits, options, path)
  if item in target:
    typedFail(nkeTypeMismatch, "duplicate set item", path, node.offset)
  target.incl item

proc decodeOrderedSetItem[E](target: var OrderedSet[E]; node: DataNode;
                             limits: CodecLimits; options: TypedCodecOptions; path: string) =
  let item = decodeValue[E](node, limits, options, path)
  if item in target:
    typedFail(nkeTypeMismatch, "duplicate set item", path, node.offset)
  target.incl item

proc decodeValue[T](node: DataNode; limits: CodecLimits; options: TypedCodecOptions;
                    path: string): T =
  when T is distinct:
    let values = require(node, "distinct", path)
    if values.len != 3 or values[1].kind != dkString:
      typedFail(nkeTypeMismatch, "invalid distinct value", path, node.offset)
    if options.requireTypeNames and values[1].text != name(T):
      typedFail(nkeTypeMismatch, "distinct type name mismatch", path, values[1].offset)
    type Base = distinctBase(T)
    result = T(decodeValue[Base](values[2], limits, options, path))
  elif T is bool:
    if node.kind != dkAtom or node.text notin ["true", "false"]:
      typedFail(nkeTypeMismatch, "expected bool", path, node.offset)
    result = node.text == "true"
  elif T is SomeUnsignedInt:
    if node.kind != dkAtom or node.text.len < 2 or node.text[^1] != 'u':
      typedFail(nkeTypeMismatch, "expected unsigned integer", path, node.offset)
    try:
      let parsed = parseBiggestUInt(node.text[0 .. ^2])
      if parsed > BiggestUInt(high(T)):
        typedFail(nkeTypeMismatch, "unsigned integer is outside the target type range", path, node.offset)
      result = T(parsed)
    except ValueError: typedFail(nkeTypeMismatch, "invalid unsigned integer", path, node.offset)
  elif T is SomeSignedInt:
    if node.kind != dkAtom or node.text.endsWith("u"):
      typedFail(nkeTypeMismatch, "expected signed integer", path, node.offset)
    try:
      let parsed = parseBiggestInt(node.text)
      if parsed < BiggestInt(low(T)) or parsed > BiggestInt(high(T)):
        typedFail(nkeTypeMismatch, "signed integer is outside the target type range", path, node.offset)
      result = T(parsed)
    except ValueError: typedFail(nkeTypeMismatch, "invalid signed integer", path, node.offset)
  elif T is SomeFloat:
    if node.kind != dkAtom:
      typedFail(nkeTypeMismatch, "expected float", path, node.offset)
    try:
      result = T(parseFloat(node.text))
      if classify(result) in {fcNan, fcInf, fcNegInf}:
        typedFail(nkeNonFiniteFloat, "non-finite float is unsupported", path, node.offset)
    except ValueError: typedFail(nkeTypeMismatch, "invalid float", path, node.offset)
  elif T is string:
    if node.kind != dkString: typedFail(nkeTypeMismatch, "expected string", path, node.offset)
    if node.text.len > limits.maxStringBytes: typedFail(nkeStringLimit, "string exceeds configured limit", path, node.offset)
    if validateUtf8(node.text) >= 0: typedFail(nkeInvalidUtf8, "string is not valid UTF-8", path, node.offset)
    result = node.text
  elif T is char:
    if node.kind != dkChar: typedFail(nkeTypeMismatch, "expected char", path, node.offset)
    result = node.text[0]
  elif T is enum:
    let values = require(node, "enum", path)
    if values.len != 3 or values[1].kind != dkString or values[2].kind != dkString:
      typedFail(nkeTypeMismatch, "invalid enum", path, node.offset)
    if options.requireTypeNames and values[1].text != name(T):
      typedFail(nkeTypeMismatch, "enum type name mismatch", path, values[1].offset)
    for item in T:
      if $item == values[2].text: return item
    typedFail(nkeUnknownEnumMember, "unknown enum member", path, values[2].offset)
  elif T is Option:
    if node.kind == dkAtom and node.text == "none": return none(typeof(default(T).get))
    let values = require(node, "some", path)
    if values.len != 2: typedFail(nkeTypeMismatch, "invalid Option", path, node.offset)
    result = some(decodeValue[typeof(default(T).get)](values[1], limits, options, path))
  elif T is Table:
    let values = require(node, "table", path)
    if values.len - 1 > limits.maxContainerItems:
      typedFail(nkeTokenLimit, "table exceeds configured limit", path, node.offset)
    for i in 1 ..< values.len:
      decodeTableEntry(result, values[i], limits, options, path & "[" & $(i - 1) & "]")
  elif T is OrderedTable:
    let values = require(node, "table", path)
    if values.len - 1 > limits.maxContainerItems:
      typedFail(nkeTokenLimit, "table exceeds configured limit", path, node.offset)
    for i in 1 ..< values.len:
      decodeOrderedTableEntry(result, values[i], limits, options, path & "[" & $(i - 1) & "]")
  elif T is HashSet:
    let values = require(node, "set", path)
    if values.len - 1 > limits.maxContainerItems:
      typedFail(nkeTokenLimit, "set exceeds configured limit", path, node.offset)
    for i in 1 ..< values.len:
      decodeSetItem(result, values[i], limits, options, path & "[" & $(i - 1) & "]")
  elif T is OrderedSet:
    let values = require(node, "set", path)
    if values.len - 1 > limits.maxContainerItems:
      typedFail(nkeTokenLimit, "set exceeds configured limit", path, node.offset)
    for i in 1 ..< values.len:
      decodeOrderedSetItem(result, values[i], limits, options, path & "[" & $(i - 1) & "]")
  elif T is seq:
    let values = require(node, "seq", path)
    if values.len - 1 > limits.maxContainerItems: typedFail(nkeTokenLimit, "sequence exceeds configured limit", path, node.offset)
    type Elem = typeof(default(T)[0])
    result = newSeqOfCap[Elem](values.len - 1)
    for i in 1 ..< values.len: result.add decodeValue[Elem](values[i], limits, options, path & "[" & $(i - 1) & "]")
  elif T is array:
    let values = require(node, "array", path)
    if values.len - 1 != result.len: typedFail(nkeArrayLengthMismatch, "array length mismatch", path, node.offset)
    for i in 0 ..< result.len:
      result[i] = decodeValue[typeof(result[i])](values[i + 1], limits, options, path & "[" & $i & "]")
  elif T is tuple:
    let values = require(node, "tuple", path)
    var index = 1
    for fieldName, field in fieldPairs(result):
      if index >= values.len: typedFail(nkeArrayLengthMismatch, "tuple length mismatch", path, node.offset)
      field = decodeValue[typeof(field)](values[index], limits, options, path & "." & fieldName)
      inc index
    if index != values.len: typedFail(nkeArrayLengthMismatch, "tuple length mismatch", path, node.offset)
  elif T is ref:
    if node.kind == dkAtom and node.text == "nil":
      return nil
    let values = require(node, "ref", path)
    if values.len != 2: typedFail(nkeTypeMismatch, "invalid ref object", path, node.offset)
    new(result)
    result[] = decodeValue[typeof(result[])](values[1], limits, options, path)
  elif T is object:
    when isVariantObject(T):
      typedFail(nkeUnsupportedType, "variant object support is not available yet", path, node.offset)
    else:
      let values = require(node, "object", path)
      if values.len < 2 or values[1].kind != dkString: typedFail(nkeTypeMismatch, "invalid object", path, node.offset)
      if options.requireTypeNames and values[1].text != name(T):
        typedFail(nkeTypeMismatch, "object type name mismatch", path, values[1].offset)
      if values.len - 2 > limits.maxObjectFields: typedFail(nkeTokenLimit, "object exceeds configured field limit", path, node.offset)
      var consumed = newSeq[bool](values.len)
      for fieldName, field in fieldPairs(result):
        var match = -1
        for i in 2 ..< values.len:
          let entry = values[i]
          if entry.kind != dkCompound or entry.children.len != 3 or entry.children[0].kind != dkAtom or
              entry.children[0].text != "field" or entry.children[1].kind != dkString:
            typedFail(nkeTypeMismatch, "invalid object field", path, entry.offset)
          if entry.children[1].text == fieldName:
            if match >= 0: typedFail(nkeUnknownField, "duplicate object field", path & "." & fieldName, entry.offset)
            match = i
        if match < 0: typedFail(nkeMissingField, "missing object field", path & "." & fieldName, node.offset)
        consumed[match] = true
        field = decodeValue[typeof(field)](values[match].children[2], limits, options, path & "." & fieldName)
      if not options.allowUnknownFields:
        for i in 2 ..< values.len:
          if not consumed[i]: typedFail(nkeUnknownField, "unknown object field", path & "." & values[i].children[1].text, values[i].offset)
  else:
    typedFail(nkeUnsupportedType, "unsupported typed NIF value: " & name(T), path, node.offset)

proc fromNif*[T](source: string; _: typedesc[T]; limits = defaultCodecLimits();
                 options = defaultTypedCodecOptions()): T =
  validLimits(limits)
  discard nifToBif(source, limits) # validate syntax and all generic codec limits first
  var pos = 0
  let root = parseNode(source, pos, limits, 0)
  skipSpace(source, pos)
  if pos != source.len: typedFail(nkeMalformedInput, "trailing typed NIF data", "$", pos)
  let values = require(root, DataRootTag, "$")
  if values.len != 3 or values[1].kind != dkAtom or values[1].text != "1":
    typedFail(nkeUnsupportedDataProfile, "unsupported NIFKit data profile", "$", root.offset)
  result = decodeValue[T](values[2], limits, options, "$")

proc fromBif*[T](source: string; _: typedesc[T]; limits = defaultCodecLimits();
                 options = defaultTypedCodecOptions()): T =
  validLimits(limits)
  let document = parseBif(source, limits)
  var pos = 0
  let root = parseBifNode(document, pos, document.tokens.len, 0, limits)
  if pos != document.tokens.len:
    typedFail(nkeMalformedInput, "trailing typed BIF data", "$", pos)
  let values = require(root, DataRootTag, "$")
  if values.len != 3 or values[1].kind != dkAtom or values[1].text != "1":
    typedFail(nkeUnsupportedDataProfile, "unsupported NIFKit data profile", "$", root.offset)
  result = decodeValue[T](values[2], limits, options, "$")
