## Repeated ARC paths intended to run under Valgrind in CI.
import ../src/nifkit
import ../src/nifkit/document
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
  doAssert nifToBif("(record 0xFF 1_000u \"key: #value\")") ==
    nifToBif("(record 255 1000u \"key\\3A\\20\\23value\")")
  rejects do (): discard nifToBif("0x1_0000_0000_0000_0000u")
  rejects do (): discard nifToBif("1__2")
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

  let document = parseNif(validNif)
  let root = document[0]
  root.add document.newInt(7)
  for node in document.walk():
    if node.kind == nfInt: node.intValue = 8
  let detached = root.remove(root.len - 1)
  root.insert(0, detached)
  let copy = document.cloneSubtree(root)
  document.add copy
  copy[0].intValue = 9
  doAssert root[0].intValue == 8
  for child in root:
    discard child.kind
    for index in 0 ..< 8: discard document.newInt(index)
  let editedBif = document.renderBif()
  doAssert parseBifTree(editedBif).renderNif() == document.renderNif()
  rejects do (): root.add document[1]
  rejects do (): discard root[-1]
  rejects do (): discard document.renderBif(outputLimits)

# Flush ORC's retained cycle-candidate buffer after all per-iteration owners
# have been released, so allocator-based leak checks observe final cleanup.
when defined(gcOrc):
  GC_fullCollect()
