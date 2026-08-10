## Deterministic malformed-input coverage for the typed profile.
import std/[unittest, options]
import ../src/nifkit

type
  FuzzRecord = object
    title: string
    count: int
    note: Option[string]

proc onlyRaisesTypedError(body: proc()) =
  try:
    body()
  except NifKitError:
    discard
  except CatchableError:
    fail()

suite "typed serializer malformed-input fuzz":
  let value = FuzzRecord(title: "fuzz\n\0", count: -7, note: some("value"))
  let nif = toNif(value)
  let bif = toBif(value)

  test "truncated typed NIF and BIF never escape structured errors":
    for length in 0 ..< nif.len:
      onlyRaisesTypedError do:
        discard fromNif(nif[0 ..< length], FuzzRecord)
    for length in 0 ..< bif.len:
      onlyRaisesTypedError do:
        discard fromBif(bif[0 ..< length], FuzzRecord)

  test "single-byte mutations cannot crash typed decoding":
    for index in 0 ..< nif.len:
      var mutated = nif
      mutated[index] = char((ord(mutated[index]) xor 0x5a) and 0xff)
      onlyRaisesTypedError do:
        discard fromNif(mutated, FuzzRecord)
    for index in 0 ..< bif.len:
      var mutated = bif
      mutated[index] = char((ord(mutated[index]) xor 0xa5) and 0xff)
      onlyRaisesTypedError do:
        discard fromBif(mutated, FuzzRecord)

  test "typed malformed-input failures leave later conversions usable":
    onlyRaisesTypedError do:
      discard fromNif("(nifkit\\2Ddata 1 (object", FuzzRecord)
    onlyRaisesTypedError do:
      discard fromBif("not a BIF", FuzzRecord)
    check fromNif(toNif(value), FuzzRecord) == value
    check fromBif(toBif(value), FuzzRecord) == value
