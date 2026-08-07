import std/[unittest, options, strutils, tables, sets]
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

suite "typed serializer v1":
  test "round-trips a nested data profile value":
    let value = Record(title: "NIF\n\0", count: -12, enabled: true,
      state: stOpen, note: some("hello"), items: @[1, 2, 3])
    let nif = toNif(value)
    check nif.startsWith("(nifkit\\2Ddata 1 ")
    check fromNif(nif, Record) == value
    let bif = toBif(value)
    check fromBif(bif, Record) == value
    check bifToNif(bif) == nif

  test "distinguishes missing and unknown fields":
    expect NifKitError:
      discard fromNif("(nifkit\\2Ddata 1 (object \"Record\" (field \"title\" \"x\")))", Record)
    expect NifKitError:
      discard fromNif("(nifkit\\2Ddata 1 (object \"Record\" (field \"title\" \"x\") (field \"count\" 1) (field \"enabled\" true) (field \"state\" (enum \"State\" \"stOpen\")) (field \"note\" none) (field \"items\" (seq)) (field \"extra\" 1)))", Record)

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
    check nif == "(nifkit\\2Ddata 1 (distinct \"UserId\" 42u))"
    check uint64(fromNif(nif, UserId)) == uint64(value)
    check uint64(fromBif(toBif(value), UserId)) == uint64(value)
    expect NifKitError:
      discard fromNif("(nifkit\\2Ddata 1 (distinct \"OtherId\" 42u))", UserId)

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
