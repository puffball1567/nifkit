# nifkit

`nifkit` is a spec-based NIF/BIF toolkit. It provides a Nim API and a stable C
ABI for converting, validating, and inspecting NIF text and BIF binary
payloads.

## Scope

- `nifToBif`: NIF text to BIF bytes
- `bifToNif`: BIF bytes to canonical NIF text
- `validateBif`: BIF validation without semantic interpretation
- caller-supplied `CodecLimits` and structured `NifKitError` failures for untrusted input
- C ABI compatibility layer for C-compatible consumers

`nifkit` is intentionally a library, not a standalone user-facing CLI. It is
designed to be embedded by databases, drivers, adapters, language bindings, and
other tools that need NIF/BIF support.

## Install

From a local checkout:

```sh
nimble install
```

From a Git repository:

```sh
nimble install https://github.com/<owner>/nifkit
```

After the package is accepted into the Nimble package list, it can be installed
with:

```sh
nimble install nifkit
```

## Format Boundary

The codec backend is implemented against the public NIF/BIF specification. The
specification is the compatibility contract: this package has no dependency on
Nimony or any compiler implementation. This keeps the public API stable if an
official standalone NIF/BIF library becomes available later: the internal
backend can be replaced without changing callers.

The target format is NIF 2027 text and BIF v5 binary data. The codec preserves
the semantic AST shape and renders decoded data as canonical NIF text. It
supports suffix comments, base62 line information, escaped identifiers and
symbols, identifier/symbol/tag grammar checks, directives, pooled
strings/symbols/tags, global symbol indexes, and malformed BIF rejection.
Standalone comments are rejected because NIF 2027 comments are suffix metadata,
not free-floating syntax nodes. Raw NIF control characters inside strings,
character literals, suffix comments, and line-info metadata are rejected unless
they are written with NIF escapes.

BIF decoding renders token-kind-aware canonical NIF. For example, a BIF
identifier containing `.` is printed with an escaped dot so that it remains an
identifier when parsed again, rather than accidentally becoming a symbol.

`nifkit` is not a NIF interpreter, compiler frontend/backend, VM, optimizer, or
dialect normalizer. It does not decide whether callers should use `.s.nif`,
`lengc`, or any other compiler-stage dialect. Applications must choose the
correct NIF dialect or compiler stage for their semantic use case.

RocheDB can use nifkit for NIF/BIF payload conversion, but nifkit itself is
general-purpose and does not know about RocheDB rings, placement, or storage
metadata.

## Acknowledgements

`nifkit` exists because Araq and the Nimony/NIF contributors defined and
documented the NIF/BIF foundation. This project is an independent compatibility
library built on that public specification, with thanks to their work.

## Development

```sh
nimble test
nimble matrixDemo
nimble cabiContract
nimble verify
```

`nimble matrixDemo` runs representative NIF shapes through the codec:
directives, comments, escaped strings, symbols, nested tags, and line-info.

Clang is the recommended C ABI verification compiler. GCC is also supported for
Linux compatibility; replace `clang` with `gcc` in the contract build command.

The package is built with Nim ARC via `config.nims`. Codec internals use Nim
owned `string`, `seq`, and `Table` values; the C ABI copies input bytes into ARC
managed memory and returns explicit output buffers that must be released with
`nifkit_free`.

Use nifkit from Nim:

```nim
import nifkit

let bif = nifToBif("(record title \"NIF\")")
let nif = bifToNif(bif)
validateBif(bif)

var limits = defaultCodecLimits()
limits.maxOutputBytes = 1_048_576
let boundedNif = bifToNif(bif, limits)
```

`NifKitError.kind` distinguishes malformed input, unsupported versions, and
each resource limit without requiring callers to parse messages.

### Choosing limits at an application boundary

The one-argument APIs intentionally impose no application-level resource
policy. `defaultCodecLimits()` is equivalent to `unlimitedCodecLimits()` and
only remains bounded by the platform's `int` range and available resources.
This keeps local conversion and code-generation tools free to process their
own large inputs without selecting arbitrary library defaults.

An application that accepts network data owns the resource policy. It should
create fixed limits for each trust boundary and pass them to every conversion
and validation call. Do not derive limits from peer-controlled data.

```nim
const ApiBodyLimit = 1 * 1024 * 1024

proc apiCodecLimits(): CodecLimits =
  result = defaultCodecLimits()
  result.maxInputBytes = ApiBodyLimit
  result.maxOutputBytes = ApiBodyLimit
  result.maxNestingDepth = 64
  result.maxTokens = 100_000
  result.maxContainerItems = 10_000

let nif = bifToNif(receivedBif, apiCodecLimits())
```

Use separate fixed policies when the workloads differ—for example, a small
public API request and a larger authenticated import. Keep the transport's
request/response byte cap no larger than the relevant NIFKit input or output
budget, and tighten pool, string, and container limits when the data model
permits it. `CodecLimits` is the enforcement mechanism; choosing these values
remains the embedding application's responsibility.

### Typed serializer (v0.4)

NIFKit can encode and decode supported Nim values using the typed data profile
v2. The BIF APIs construct and read BIF directly, so application code need not
allocate intermediate NIF text.

```nim
type CreateRecord = object
  title: string
  count: int
  enabled: bool

let request = CreateRecord(title: "NIF", count: 12, enabled: true)
let payload = toBif(request)
let decoded = fromBif(payload, CreateRecord)
doAssert decoded == request
```

`toNif`, `fromNif`, `toBif`, and `fromBif` accept `CodecLimits`; decoding also
accepts `TypedCodecOptions`. Unknown object fields and type-name mismatches are
rejected by default. See [the typed serializer design](docs/typed-serializer-design.md)
for the profile, supported types, canonicalization, and compatibility rules.

`NifBytes` represents bounded arbitrary bytes such as a small image, encrypted
payload, or document without Base64 expansion. It is intentionally distinct
from UTF-8 `string`.

```nim
let thumbnail = initNifBytes(readFile("thumbnail.png"))
let payload = toBif(thumbnail)
```

Typed conversion materializes the complete `NifBytes` value. For large images,
videos, or other attachments, keep BIF for structured metadata and use the
application's streaming multipart or equivalent transport facility for the raw
file. Apply separate fixed limits to the metadata and streamed attachment.

Nim applications should call the Nim API directly. Applications may store BIF
however they want; semantic interpretation belongs to the embedding application
or another NIF/BIF implementation.

## C ABI

`include/nifkit.h` exposes byte-length APIs for C and C++ consumers. It is a
compatibility interface, not the recommended general integration path for other
languages. When another language needs NIF/BIF support, prefer a native
implementation or port in that language, validated against the NIF/BIF
specification and conformance corpus.

BIF is binary data, so neither input nor output uses NUL termination. Every
successful output buffer must be released with `nifkit_free`.

```c
int nifkit_nif_to_bif(const void *nif_data, size_t nif_len,
                      void **out_bif, size_t *out_len);
int nifkit_bif_to_nif(const void *bif_data, size_t bif_len,
                      void **out_nif, size_t *out_len);
int nifkit_validate_bif(const void *bif_data, size_t bif_len);
void nifkit_free(void *buffer);
const char *nifkit_last_error(void);
```

All conversion functions return `0` on success and non-zero on failure.
`nifkit_last_error()` is thread-local. Inputs are byte slices; passing `NULL`
with a non-zero length is an error. Outputs are always reset before conversion.
Returned buffers may contain NUL bytes, so callers must use the returned length.
