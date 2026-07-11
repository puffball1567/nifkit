## Stable C ABI for the NIF/BIF codec.

import nifkit

var lastError {.threadvar.}: string

proc setError(message: string): cint =
  lastError = message
  1

proc copyInput(data: pointer; length: csize_t): string =
  if length > csize_t(high(int)):
    raise newException(ValueError, "input exceeds supported size")
  if length > 0 and data == nil:
    raise newException(ValueError, "input pointer is nil")
  result = newString(int(length))
  if result.len > 0:
    copyMem(addr result[0], data, result.len)

proc copyOutput(value: string; outData: ptr pointer; outLen: ptr csize_t) =
  if outData == nil or outLen == nil:
    raise newException(ValueError, "output pointers are required")
  let buffer = if value.len == 0: nil else: alloc(value.len)
  if value.len > 0 and buffer == nil:
    raise newException(ValueError, "allocation failed")
  if value.len > 0:
    copyMem(buffer, unsafeAddr value[0], value.len)
  outData[] = buffer
  outLen[] = csize_t(value.len)

proc resetOutput(outData: ptr pointer; outLen: ptr csize_t) =
  if outData == nil or outLen == nil:
    raise newException(ValueError, "output pointers are required")
  outData[] = nil
  outLen[] = 0

proc nifkit_nif_to_bif*(nifData: pointer; nifLen: csize_t;
                        outBif: ptr pointer; outLen: ptr csize_t): cint
                        {.exportc, dynlib.} =
  try:
    resetOutput(outBif, outLen)
    copyOutput(nifToBif(copyInput(nifData, nifLen)), outBif, outLen)
    lastError.setLen(0)
    0
  except CatchableError:
    setError(getCurrentExceptionMsg())

proc nifkit_bif_to_nif*(bifData: pointer; bifLen: csize_t;
                        outNif: ptr pointer; outLen: ptr csize_t): cint
                        {.exportc, dynlib.} =
  try:
    resetOutput(outNif, outLen)
    copyOutput(bifToNif(copyInput(bifData, bifLen)), outNif, outLen)
    lastError.setLen(0)
    0
  except CatchableError:
    setError(getCurrentExceptionMsg())

proc nifkit_validate_bif*(bifData: pointer; bifLen: csize_t): cint
                         {.exportc, dynlib.} =
  try:
    validateBif(copyInput(bifData, bifLen))
    lastError.setLen(0)
    0
  except CatchableError:
    setError(getCurrentExceptionMsg())

proc nifkit_free*(buffer: pointer) {.exportc, dynlib.} =
  if buffer != nil: dealloc(buffer)

proc nifkit_last_error*(): cstring {.exportc, dynlib.} =
  lastError.cstring
