## Repeated ARC paths intended to run under Valgrind in CI.
import ../src/nifkit
import std/options

type
  MemoryRecord = object
    title: string
    count: int
    note: Option[string]
  MemoryCycle = ref object
    next {.cursor.}: MemoryCycle

proc rejects(body: proc()) =
  try:
    body()
    raise newException(ValueError, "expected codec failure")
  except BifError:
    discard

let validNif = "(record :pkg.0.public \"value\")"
let validBif = nifToBif(validNif)
let deeplyNested = "(a (b (c x)))"
let typedValue = MemoryRecord(title: "typed", count: 7, note: some("value"))
let typedBif = toBif(typedValue)

for _ in 0 ..< 300:
  doAssert bifToNif(nifToBif(validNif)) == validNif
  rejects do (): validateBif("not-bif")

  var depthLimits = defaultCodecLimits()
  depthLimits.maxNestingDepth = 2
  rejects do (): discard nifToBif(deeplyNested, depthLimits)

  var outputLimits = defaultCodecLimits()
  outputLimits.maxOutputBytes = 1
  rejects do (): discard bifToNif(validBif, outputLimits)

  var poolLimits = defaultCodecLimits()
  poolLimits.maxPoolEntries = 0
  rejects do (): discard nifToBif("long-value", poolLimits)
  rejects do (): discard nifToBif("(broken")

  doAssert fromNif(toNif(typedValue), MemoryRecord).title == "typed"
  doAssert fromBif(typedBif, MemoryRecord).count == 7
  rejects do (): discard fromNif("(nifkit\\2Ddata 1 (object \"MemoryRecord\"))", MemoryRecord)
  rejects do (): discard fromNif("(nifkit\\2Ddata 1 (object \"MemoryRecord\" (field \"title\" \"x\") (field \"count\" 1) (field \"note\" none) (field \"extra\" 1)))", MemoryRecord)
  rejects do (): discard fromBif("not-bif", MemoryRecord)

  let cycle = MemoryCycle()
  cycle.next = cycle
  rejects do (): discard toNif(cycle)

  var typedOutputLimits = defaultCodecLimits()
  typedOutputLimits.maxOutputBytes = 1
  rejects do (): discard toNif(typedValue, typedOutputLimits)

  var typedReferenceLimits = defaultCodecLimits()
  typedReferenceLimits.maxTrackedReferences = 0
  rejects do (): discard toNif(MemoryCycle(), typedReferenceLimits)
