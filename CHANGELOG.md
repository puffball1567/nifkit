# Changelog

## Unreleased

- Clarify that the C ABI is a C/C++ compatibility interface, while new
  integrations in other languages should be language-native implementations or
  ports.
- Add the initial Nim-only typed serializer v1 API with strict object decoding
  and bounded NIF/BIF round trips.
- Add canonical `Table` and `OrderedTable` typed serialization with duplicate
  key rejection and container limits.

## 0.2.0 - 2026-08-01

- Add finite, caller-configurable `CodecLimits` to Nim and C codec APIs.
- Add structured `NifKitError` categories and BIF v5 version reporting.
- Bound BIF-to-NIF rendering and NIF/BIF pool, token, depth, and index paths.
- Add ARC/Valgrind CI coverage and the typed serializer mapping design.

## 0.1.1

- Add BIF byte-order fixture coverage.
