import std/[unittest, options, strutils]
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
