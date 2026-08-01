## Repeated ARC paths intended to run under Valgrind in CI.
import ../src/nifkit

proc rejects(body: proc()) =
  try:
    body()
    raise newException(ValueError, "expected codec failure")
  except BifError:
    discard

let validNif = "(record :pkg.0.public \"value\")"
let validBif = nifToBif(validNif)
let deeplyNested = "(a (b (c x)))"

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
