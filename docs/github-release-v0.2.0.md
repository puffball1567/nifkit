# nifkit v0.2.0

## Highlights

- Add finite `CodecLimits` to all Nim conversion and validation APIs.
- Add structured `NifKitError` categories with byte offsets, and expose the
  supported BIF version.
- Add limits-aware C ABI entry points without changing existing symbols.
- Bound BIF-to-NIF rendering, pool allocation, token/index counts, input, and
  output sizes for untrusted data.
- Add ARC/Valgrind coverage, malformed-input regression tests, and a typed
  serializer mapping design.

## Verification

- Linux/macOS/Windows CI on Nim 2.2.0 and stable passed.
- ARC Valgrind reports zero bytes in use at exit and zero errors.
- Existing C ABI contract tests remain green, including the limits-aware API.

## Upgrade notes

Existing one-argument Nim and C APIs remain compatible and now use finite safe
defaults. Applications processing larger trusted payloads may supply explicit
`CodecLimits` rather than relying on unbounded allocation.
