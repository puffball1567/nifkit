# Codec release readiness

The bounded codec release is ready to tag only when all of the following are
true:

- `CodecLimits` boundary tests cover each field at the limit and one over it.
- Truncation, malformed varint, tag jump, index, pool, version, endianness,
  magic, trailing-byte, and fuzz corpus cases run in CI.
- C ABI contract tests cover both existing and limits-aware entry points.
- Linux ARC Valgrind reports zero errors and no bytes in use at exit.
- The full Linux/macOS/Windows matrix passes on Nim 2.2.0 and stable.
- The release PR is merged from `devel` to `main`; the version is tagged from
  `main`, never from a feature branch.
