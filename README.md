# nifkit

`nifkit` is a spec-based NIF/BIF toolkit for making NIF usable from multiple
programming languages. It provides a Nim API and a stable C ABI for converting,
validating, and inspecting NIF text and BIF binary payloads.

## Scope

- `nifToBif`: NIF text to BIF bytes
- `bifToNif`: BIF bytes to canonical NIF text
- `validateBif`: BIF validation without semantic interpretation
- C ABI for `NIF text -> BIF bytes`, `BIF bytes -> NIF text`, and BIF
  validation

`nifkit` is intentionally a library, not a standalone user-facing CLI. It is
designed to be embedded by databases, drivers, adapters, language bindings, and
other tools that need NIF/BIF support.

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

RocheDB can use nifkit for NIF/BIF payload conversion, but nifkit itself is
general-purpose and does not know about RocheDB rings, placement, or storage
metadata.

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
```

Applications should call the Nim API or C ABI directly. Applications may store
BIF however they want; semantic interpretation belongs to the embedding
application, nifkit, or another NIF/BIF implementation.

## C ABI

`include/nifkit.h` exposes byte-length APIs for C, C++, Rust, Node native
addons, and FFI consumers. BIF is binary data, so neither input nor output uses
NUL termination. Every successful output buffer must be released with
`nifkit_free`.

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
