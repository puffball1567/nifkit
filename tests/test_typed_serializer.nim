import std/[unittest, options, strutils, tables, sets, math]
import ../src/nifkit

type
  State = enum stOpen, stClosed
  Record = object
    title: string
    count: int
    enabled: bool
    state: State
    note: Option[string]
    items: seq[int]
  RefRecord = ref object
    name: string
  Cycle = ref object
    next {.cursor.}: Cycle
  UserId = distinct uint64
  SmallCount = range[3..7]
  VariantKind = enum vkText, vkCount
  VariantRecord = object
    id: string
    case kind: VariantKind
    of vkText:
      text: string
    of vkCount:
      count: int
  RefChain = ref object
    child: RefChain
  BinaryRecord = object
    name: string
    content: NifBytes

suite "typed serializer profiles":
  test "round-trips primitive boundaries and canonical BIF":
    check fromNif(toNif(false), bool) == false
    check fromBif(toBif(true), bool) == true
    check fromNif(toNif(low(int8)), int8) == low(int8)
    check fromNif(toNif(high(int8)), int8) == high(int8)
    check fromNif(toNif(low(int64)), int64) == low(int64)
    check fromNif(toNif(high(int64)), int64) == high(int64)
    check fromNif(toNif(low(uint8)), uint8) == low(uint8)
    check fromNif(toNif(high(uint8)), uint8) == high(uint8)
    check fromNif(toNif(high(uint64)), uint64) == high(uint64)
    check fromNif(toNif(-12.5'f32), float32) == -12.5'f32
    check fromBif(toBif(1.25), float64) == 1.25
    let value = "こんにちは\n\0\\\""
    let nif = toNif(value)
    check fromNif(nif, string) == value
    check bifToNif(toBif(value)) == nif

  test "round-trips chars, options, arrays, and tuples distinctly":
    check fromNif(toNif('x'), char) == 'x'
    check fromNif(toNif('\0'), char) == '\0'
    check fromBif(toBif('x'), char) == 'x'
    check fromNif(toNif(none(string)), Option[string]).isNone
    check fromBif(toBif(some("value")), Option[string]) == some("value")
    let arrayValue = [1, 2, 3]
    check fromNif(toNif(arrayValue), array[3, int]) == arrayValue
    check fromBif(toBif(arrayValue), array[3, int]) == arrayValue
    let tupleValue = (name: "nif", count: 2, enabled: true)
    check fromNif(toNif(tupleValue), type(tupleValue)) == tupleValue
    check fromBif(toBif(tupleValue), type(tupleValue)) == tupleValue
    try:
      discard fromNif("(nifkit\\2Ddata 1 (array 1 2))", array[3, int])
      fail()
    except NifKitError as error:
      check error.kind == nkeArrayLengthMismatch
    try:
      discard fromNif("(nifkit\\2Ddata 1 (tuple 1 2 true))", type(tupleValue))
      fail()
    except NifKitError as error:
      check error.kind == nkeTypeMismatch

  test "rejects non-finite floats and unknown enum members":
    for value in [NaN, Inf, NegInf]:
      try:
        discard toNif(value)
        fail()
      except NifKitError as error:
        check error.kind == nkeNonFiniteFloat
    try:
      discard fromNif("(nifkit\\2Ddata 1 (enum \"State\" \"stMissing\"))", State)
      fail()
    except NifKitError as error:
      check error.kind == nkeUnknownEnumMember

  test "round-trips a nested data profile value":
    let value = Record(title: "NIF\n\0", count: -12, enabled: true,
      state: stOpen, note: some("hello"), items: @[1, 2, 3])
    let nif = toNif(value)
    check nif.startsWith("(nifkit\\2Ddata 2 ")
    check fromNif(nif, Record) == value
    let bif = toBif(value)
    check fromBif(bif, Record) == value
    check bifToNif(bif) == nif

  test "distinguishes missing and unknown fields":
    expect NifKitError:
      discard fromNif("(nifkit\\2Ddata 1 (object \"Record\" (field \"title\" \"x\")))", Record)
    expect NifKitError:
      discard fromNif("(nifkit\\2Ddata 1 (object \"Record\" (field \"title\" \"x\") (field \"count\" 1) (field \"enabled\" true) (field \"state\" (enum \"State\" \"stOpen\")) (field \"note\" none) (field \"items\" (seq)) (field \"extra\" 1)))", Record)
    let source = "(nifkit\\2Ddata 1 (object \"Record\" (field \"title\" \"x\") (field \"count\" 1) (field \"enabled\" true) (field \"state\" (enum \"State\" \"stOpen\")) (field \"note\" none) (field \"items\" (seq)) (field \"extra\" 1)))"
    let decoded = fromNif(source, Record, options = TypedCodecOptions(allowUnknownFields: true, requireTypeNames: true))
    check decoded.title == "x"

  test "accepts v1 data and rejects incompatible profile versions":
    check fromNif("(nifkit\\2Ddata 1 true)", bool)
    try:
      discard fromNif("(nifkit\\2Ddata 3 true)", bool)
      fail()
    except NifKitError as error:
      check error.kind == nkeUnsupportedDataProfile

  test "round-trips nil and non-nil ref objects":
    let empty: RefRecord = nil
    check fromBif(toBif(empty), RefRecord).isNil
    let value = RefRecord(name: "child")
    let decoded = fromNif(toNif(value), RefRecord)
    check not decoded.isNil
    check decoded.name == "child"

  test "rejects cyclic ref objects":
    let value = Cycle()
    value.next = value
    try:
      discard toNif(value)
      fail()
    except NifKitError as error:
      check error.kind == nkeCyclicReference

  test "round-trips distinct values with their declared type name":
    let value = UserId(42)
    let nif = toNif(value)
    check nif == "(nifkit\\2Ddata 2 (distinct \"UserId\" 42u))"
    check uint64(fromNif(nif, UserId)) == uint64(value)
    check uint64(fromBif(toBif(value), UserId)) == uint64(value)
    expect NifKitError:
      discard fromNif("(nifkit\\2Ddata 1 (distinct \"OtherId\" 42u))", UserId)

  test "round-trips ranges and rejects values outside their bounds":
    let value: SmallCount = 5
    check fromNif(toNif(value), SmallCount) == value
    check fromBif(toBif(value), SmallCount) == value
    expect NifKitError:
      discard fromNif("(nifkit\\2Ddata 1 2)", SmallCount)
    expect NifKitError:
      discard fromNif("(nifkit\\2Ddata 1 8)", SmallCount)

  test "rejects out-of-range integers before narrowing":
    check fromNif("(nifkit\\2Ddata 1 127)", int8) == 127'i8
    check fromNif("(nifkit\\2Ddata 1 255u)", uint8) == 255'u8
    for source in ["(nifkit\\2Ddata 1 128)", "(nifkit\\2Ddata 1 -129)"]:
      expect NifKitError:
        discard fromNif(source, int8)
    expect NifKitError:
      discard fromNif("(nifkit\\2Ddata 1 256u)", uint8)

  test "rejects invalid UTF-8 strings and cstring":
    let invalid = "\xFF"
    try:
      discard toNif(invalid)
      fail()
    except NifKitError as error:
      check error.kind == nkeInvalidUtf8
    try:
      discard fromNif("(nifkit\\2Ddata 1 \"\\FF\")", string)
      fail()
    except NifKitError as error:
      check error.kind == nkeInvalidUtf8
    let unsupported: cstring = "nifkit"
    try:
      discard toNif(unsupported)
      fail()
    except NifKitError as error:
      check error.kind == nkeUnsupportedType

  test "round-trips arbitrary byte payloads without UTF-8 or base64":
    let bytes = initNifBytes("\x89PNG\r\n\x1a\n\0\xff")
    let nif = toNif(bytes)
    check nif.startsWith("(nifkit\\2Ddata 2 (bytes ")
    check fromNif(nif, NifBytes) == bytes
    let bif = toBif(bytes)
    check fromBif(bif, NifBytes) == bytes
    check bifToNif(bif) == nif
    check bytes.toSeq == @[0x89'u8, 0x50'u8, 0x4e'u8, 0x47'u8, 0x0d'u8,
      0x0a'u8, 0x1a'u8, 0x0a'u8, 0x00'u8, 0xff'u8]

  test "rejects byte payloads in profile v1 and enforces byte limits":
    expect NifKitError:
      discard fromNif("(nifkit\\2Ddata 1 (bytes \"x\"))", NifBytes)
    var limits = defaultCodecLimits()
    limits.maxStringBytes = 2
    expect NifKitError:
      discard toBif(initNifBytes("abc"), limits)
    var poolLimits = defaultCodecLimits()
    poolLimits.maxPoolBytes = 2
    expect NifKitError:
      discard toBif(initNifBytes("abc"), poolLimits)

  test "round-trips binary fields inside typed objects":
    let value = BinaryRecord(
      name: "preview.png",
      content: initNifBytes("\x89PNG\r\n\x1a\n\0\xff")
    )
    let nif = toNif(value)
    check fromNif(nif, BinaryRecord) == value
    check fromBif(toBif(value), BinaryRecord) == value
    let v1 = "(nifkit\\2Ddata 1 (object \"BinaryRecord\" (field \"name\" \"preview.png\") (field \"content\" (bytes \"x\"))))"
    expect NifKitError:
      discard fromNif(v1, BinaryRecord)

  test "round trips every active branch of a variant object":
    let textValue = VariantRecord(id: "a", kind: vkText, text: "hello")
    let countValue = VariantRecord(id: "b", kind: vkCount, count: 12)
    for value in [textValue, countValue]:
      let nif = toNif(value)
      let decoded = fromNif(nif, VariantRecord)
      check decoded.id == value.id
      check decoded.kind == value.kind
      case value.kind
      of vkText: check decoded.text == value.text
      of vkCount: check decoded.count == value.count
      let bifDecoded = fromBif(toBif(value), VariantRecord)
      check bifDecoded.id == value.id
      check bifDecoded.kind == value.kind
      case value.kind
      of vkText: check bifDecoded.text == value.text
      of vkCount: check bifDecoded.count == value.count

  test "validates variant discriminants and active fields":
    try:
      discard fromNif("(nifkit\\2Ddata 1 (object \"VariantRecord\" (field \"id\" \"a\") (field \"text\" \"hello\")))", VariantRecord)
      fail()
    except NifKitError as error:
      check error.kind == nkeMissingField
      check error.path == "$.kind"
    try:
      discard fromNif("(nifkit\\2Ddata 1 (object \"VariantRecord\" (field \"id\" \"a\") (field \"kind\" (enum \"VariantKind\" \"vkText\")) (field \"count\" 12)))", VariantRecord)
      fail()
    except NifKitError as error:
      check error.kind == nkeMissingField
      check error.path == "$.text"
    try:
      discard fromNif("(nifkit\\2Ddata 1 (object \"VariantRecord\" (field \"id\" \"a\") (field \"kind\" (enum \"VariantKind\" \"vkText\")) (field \"kind\" (enum \"VariantKind\" \"vkText\")) (field \"text\" \"hello\")))", VariantRecord)
      fail()
    except NifKitError as error:
      check error.kind == nkeUnknownField
      check error.path == "$.kind"

  test "normalizes Table and OrderedTable entries by key representation":
    var first, second: Table[string, int]
    first["z"] = 1
    first["a"] = 2
    second["a"] = 2
    second["z"] = 1
    check toNif(first) == toNif(second)
    check fromNif(toNif(first), Table[string, int]) == first
    check fromBif(toBif(first), Table[string, int]) == first

    var ordered: OrderedTable[string, int]
    ordered["z"] = 1
    ordered["a"] = 2
    let decodedOrdered = fromNif(toNif(ordered), OrderedTable[string, int])
    check decodedOrdered["a"] == 2
    check decodedOrdered["z"] == 1
    check toNif(decodedOrdered) == toNif(ordered)

  test "normalizes HashSet and OrderedSet members":
    let first = ["z", "a"].toHashSet
    let second = ["a", "z"].toHashSet
    check toNif(first) == toNif(second)
    check fromNif(toNif(first), HashSet[string]) == first
    check fromBif(toBif(first), HashSet[string]) == first

    var ordered: OrderedSet[string]
    ordered.incl "z"
    ordered.incl "a"
    let decodedOrdered = fromNif(toNif(ordered), OrderedSet[string])
    check "a" in decodedOrdered
    check "z" in decodedOrdered
    check toNif(decodedOrdered) == toNif(ordered)

  test "rejects duplicate set members and enforces set limits":
    expect NifKitError:
      discard fromNif("(nifkit\\2Ddata 1 (set \"a\" \"a\"))", HashSet[string])
    let value = ["a"].toHashSet
    expect NifKitError:
      discard toNif(value, CodecLimits(maxContainerItems: 0))

  test "rejects duplicate table keys and enforces table limits":
    expect NifKitError:
      discard fromNif("(nifkit\\2Ddata 1 (table (entry \"a\" 1) (entry \"a\" 2)))", Table[string, int])
    var value: Table[string, int]
    value["a"] = 1
    expect NifKitError:
      discard toNif(value, CodecLimits(maxContainerItems: 0))

  test "enforces typed container and object field limits at boundaries":
    let values = @[1, 2]
    var containerLimit = defaultCodecLimits()
    containerLimit.maxContainerItems = 2
    check fromNif(toNif(values, containerLimit), seq[int]) == values
    containerLimit.maxContainerItems = 1
    expect NifKitError:
      discard toNif(values, containerLimit)

    let value = Record(title: "x", count: 1, enabled: true, state: stOpen,
      note: none(string), items: @[])
    var objectLimit = defaultCodecLimits()
    objectLimit.maxObjectFields = 6
    check fromNif(toNif(value, objectLimit), Record) == value
    objectLimit.maxObjectFields = 5
    expect NifKitError:
      discard toNif(value, objectLimit)

  test "enforces typed string, output, and reference tracking limits":
    var stringLimit = defaultCodecLimits()
    stringLimit.maxStringBytes = 3
    check fromNif(toNif("abc", stringLimit), string) == "abc"
    expect NifKitError:
      discard toNif("abcd", stringLimit)
    var outputLimit = defaultCodecLimits()
    outputLimit.maxOutputBytes = 3
    expect NifKitError:
      discard toNif("abc", outputLimit)

    let chain = RefChain(child: RefChain())
    var referenceLimit = defaultCodecLimits()
    referenceLimit.maxTrackedReferences = 1
    expect NifKitError:
      discard toNif(chain, referenceLimit)

  test "typed failures do not poison later BIF conversions":
    expect NifKitError:
      discard fromBif("not a BIF", Record)
    let value = Record(title: "ok", count: 1, enabled: false, state: stClosed,
      note: some("done"), items: @[2])
    check fromBif(toBif(value), Record).title == "ok"

  test "typed NIF and BIF truncation return structured errors":
    let value = Record(title: "truncation", count: 7, enabled: true,
      state: stOpen, note: some("value"), items: @[1, 2])
    let nif = toNif(value)
    for length in 0 ..< nif.len:
      try:
        discard fromNif(nif[0 ..< length], Record)
        checkpoint "truncated typed NIF was accepted at " & $length
        fail()
      except NifKitError:
        discard
    let bif = toBif(value)
    for length in 0 ..< bif.len:
      try:
        discard fromBif(bif[0 ..< length], Record)
        checkpoint "truncated typed BIF was accepted at " & $length
        fail()
      except NifKitError:
        discard
    check fromBif(toBif(value), Record) == value

  test "typed BIF rejects malformed token content without poisoning conversion":
    let value = Record(title: "valid", count: 1, enabled: true, state: stClosed,
      note: none(string), items: @[])
    var malformed = toBif(value)
    malformed[^1] = char(0xff)
    try:
      discard fromBif(malformed, Record)
      fail()
    except NifKitError:
      discard
    check fromNif(toNif(value), Record) == value
