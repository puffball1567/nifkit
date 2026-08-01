## Bounds and structured errors for NIF/BIF codecs handling untrusted input.

type
  NifKitErrorKind* = enum
    nkeMalformedInput,
    nkeUnsupportedVersion,
    nkeInputTooLarge,
    nkeOutputTooLarge,
    nkeNestingTooDeep,
    nkeTokenLimit,
    nkePoolLimit,
    nkeStringLimit,
    nkeIndexLimit

  ## Kept as the public compatibility base exception.
  BifError* = object of ValueError

  ## Every public codec failure has a machine-readable category and byte offset.
  NifKitError* = object of BifError
    kind*: NifKitErrorKind
    offset*: int

  CodecLimits* = object
    maxInputBytes*: int
    maxOutputBytes*: int
    maxNestingDepth*: int
    maxTokens*: int
    maxPoolEntries*: int
    maxPoolBytes*: int
    maxStringBytes*: int
    maxIndexEntries*: int

const
  SupportedBifVersion* = 5

proc defaultCodecLimits*(): CodecLimits =
  ## Finite defaults suitable for processing network input.
  CodecLimits(
    maxInputBytes: 16 * 1024 * 1024,
    maxOutputBytes: 64 * 1024 * 1024,
    maxNestingDepth: 256,
    maxTokens: 4 * 1024 * 1024,
    maxPoolEntries: 1_000_000,
    maxPoolBytes: 32 * 1024 * 1024,
    maxStringBytes: 4 * 1024 * 1024,
    maxIndexEntries: 1_000_000
  )

proc raiseCodecError*(kind: NifKitErrorKind; message: string; offset = -1) {.noreturn.} =
  var error = newException(NifKitError, message)
  error.kind = kind
  error.offset = offset
  raise error

proc validLimits*(limits: CodecLimits) =
  if limits.maxInputBytes < 0 or limits.maxOutputBytes < 0 or
      limits.maxNestingDepth < 0 or limits.maxTokens < 0 or
      limits.maxPoolEntries < 0 or limits.maxPoolBytes < 0 or
      limits.maxStringBytes < 0 or limits.maxIndexEntries < 0:
    raiseCodecError(nkeMalformedInput, "codec limits must not be negative")

proc boundedAdd*(destination: var string; value: string; limits: CodecLimits) =
  if value.len > limits.maxOutputBytes - destination.len:
    raiseCodecError(nkeOutputTooLarge, "codec output exceeds configured limit")
  destination.add value

proc boundedAdd*(destination: var string; value: char; limits: CodecLimits) =
  if destination.len >= limits.maxOutputBytes:
    raiseCodecError(nkeOutputTooLarge, "codec output exceeds configured limit")
  destination.add value
