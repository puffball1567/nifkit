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
    nkeIndexLimit,
    nkeTypeMismatch,
    nkeUnknownField,
    nkeMissingField,
    nkeUnknownEnumMember,
    nkeArrayLengthMismatch,
    nkeUnsupportedType,
    nkeUnsupportedDataProfile,
    nkeCyclicReference,
    nkeNonFiniteFloat
    nkeInvalidUtf8

  ## Kept as the public compatibility base exception.
  BifError* = object of ValueError

  ## Every public codec failure has a machine-readable category and byte offset.
  NifKitError* = object of BifError
    kind*: NifKitErrorKind
    offset*: int
    path*: string

  CodecLimits* = object
    maxInputBytes*: int
    maxOutputBytes*: int
    maxNestingDepth*: int
    maxTokens*: int
    maxPoolEntries*: int
    maxPoolBytes*: int
    maxStringBytes*: int
    maxIndexEntries*: int
    maxContainerItems*: int
    maxObjectFields*: int
    maxTrackedReferences*: int

const
  SupportedBifVersion* = 5

proc unlimitedCodecLimits*(): CodecLimits =
  ## No application-level resource policy. Limits remain bounded by the
  ## platform's `int` range and available resources.
  CodecLimits(
    maxInputBytes: high(int),
    maxOutputBytes: high(int),
    maxNestingDepth: high(int),
    maxTokens: high(int),
    maxPoolEntries: high(int),
    maxPoolBytes: high(int),
    maxStringBytes: high(int),
    maxIndexEntries: high(int),
    maxContainerItems: high(int),
    maxObjectFields: high(int),
    maxTrackedReferences: high(int)
  )

proc defaultCodecLimits*(): CodecLimits =
  ## Backward-compatible no-policy default. Network-facing callers must pass
  ## explicit limits chosen for their own trust boundary.
  unlimitedCodecLimits()

proc raiseCodecError*(kind: NifKitErrorKind; message: string; offset = -1;
                      path = "$") {.noreturn.} =
  var error = newException(NifKitError, message)
  error.kind = kind
  error.offset = offset
  error.path = path
  raise error

proc validLimits*(limits: CodecLimits) =
  if limits.maxInputBytes < 0 or limits.maxOutputBytes < 0 or
      limits.maxNestingDepth < 0 or limits.maxTokens < 0 or
      limits.maxPoolEntries < 0 or limits.maxPoolBytes < 0 or
      limits.maxStringBytes < 0 or limits.maxIndexEntries < 0 or
      limits.maxContainerItems < 0 or limits.maxObjectFields < 0 or
      limits.maxTrackedReferences < 0:
    raiseCodecError(nkeMalformedInput, "codec limits must not be negative")

proc boundedAdd*(destination: var string; value: string; limits: CodecLimits) =
  if value.len > limits.maxOutputBytes - destination.len:
    raiseCodecError(nkeOutputTooLarge, "codec output exceeds configured limit")
  destination.add value

proc boundedAdd*(destination: var string; value: char; limits: CodecLimits) =
  if destination.len >= limits.maxOutputBytes:
    raiseCodecError(nkeOutputTooLarge, "codec output exceeds configured limit")
  destination.add value
