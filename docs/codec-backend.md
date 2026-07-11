# Codec Backend Contract

`nifkit` exposes NIF/BIF conversion through a stable public surface:

```nim
nifToBif(nifText)
bifToNif(bifBytes)
validateBif(bifBytes)
codecInfo()
```

The current backend is an internal implementation of the published NIF/BIF
specification. It must not depend on Nimony or any other compiler
implementation at runtime, build time, or in its conformance contract.

Fixtures and property tests are derived from the published NIF/BIF
specification. Interoperability checks against any independent implementation
may be run externally, but they are not a dependency or a release requirement.

If an official standalone NIF/BIF library is published later, an
`official_backend` may implement the same boundary. The public Nim API and C ABI
must remain unchanged.

The implementation rejects unsupported BIF versions and malformed containers
with recoverable errors. It must never terminate the host process for malformed
payload bytes.

## Conformance Target

The target is full conformance with NIF 2027 text and BIF v5 binary payloads.
Release candidates should not be described as "partial" or "subset"
implementations. If a spec feature is not implemented yet, it must be tracked as
a release blocker before publishing a stable tag.

The codec currently verifies:

- raw byte-oriented NIF parsing without requiring UTF-8 validation
- canonical `\xx` escapes and short escapes `\n`, `\t`, `\r`, `\|`, `\^`
- escaped identifiers, symbols, filenames, and comments
- identifier, symbol, and tag grammar validation, including rejection of
  unescaped raw control-like characters in bare atoms
- rejection of unescaped raw NIF control characters inside strings, character
  literals, suffix comments, and line-info filenames/comments
- `.` empty nodes, including adjacent empty nodes such as `...`
- signed integers, unsigned integers, and floating point numbers with `.` or
  `E`
- compound nodes, directives, and language nesting as regular NIF tags
- suffix line information, base62 diffs, negative `~` shorthand, filenames, and
  comments
- suffix comments without line information
- rejection of standalone comments, because NIF 2027 comments are suffix
  metadata and must attach directly to an atom or tag head
- BIF v5 magic/version, little-endian token words, pools, global symbol index,
  and tag jumps
- malformed BIF rejection for bad magic, invalid offsets, non-zero alignment
  padding, invalid pool references, unsupported token kinds, invalid index
  entries, oversized values, truncated pools, trailing bytes, and excessive
  nesting

The public API returns canonical NIF text when decoding BIF. It preserves the
semantic AST and suffix metadata, but it does not promise byte-for-byte source
formatting preservation. Whitespace outside literals is ignored during parsing.
Standalone comments are rejected: comments in NIF 2027 are suffix metadata, not
free-floating syntax nodes.

Canonical rendering is token-kind aware. For example, a BIF `Ident` whose bytes
contain `.` is rendered with an escaped dot so that a later NIF parser still sees
an identifier, not a symbol. The same rule applies to leading digits in
identifiers and invalid raw bytes in identifiers, symbols, and tag names.

Public codec failures are normalized to `BifError` at the `nifToBif`,
`bifToNif`, and `validateBif` API boundary. Lower-level helper modules may use
ordinary catchable exceptions internally, but callers should not need to depend
on those internal error classes.

## C ABI Contract

The C ABI is part of the conformance surface:

- all inputs are `(pointer, length)` byte slices
- NUL termination is never required for inputs or outputs
- `NULL` with non-zero length is rejected
- conversion outputs are reset before work begins
- success returns `0`
- failure returns non-zero and stores a thread-local error string
- every successful output buffer must be released with `nifkit_free`
- `nifkit_validate_bif` validates BIF without allocating a returned payload

Memory safety contract:

- The package is built with Nim ARC via `config.nims`.
- Codec internals use owned Nim values and do not keep borrowed pointers to
  caller-owned memory.
- C ABI entry points copy input bytes before parsing.
- C ABI success outputs are allocated with Nim `alloc` and must be released
  with `nifkit_free`.
- C ABI failure paths reset output pointers to `nil` and lengths to `0`.
- zero-length inputs and zero-length outputs are represented explicitly:
  `NULL` is valid only when the corresponding length is `0`.
- returned BIF/NIF buffers are byte slices and may contain NUL bytes; callers
  must use the returned length, not C string termination.
- Malformed BIF count, offset, nesting-depth, and trailing-data cases are
  covered by tests so hostile payloads are rejected before unsafe allocation or
  ambiguous decoding.
