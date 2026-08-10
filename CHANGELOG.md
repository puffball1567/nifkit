# Changelog

## Unreleased

- Clarify that the C ABI is a C/C++ compatibility interface, while new
  integrations in other languages should be language-native implementations or
  ports.
- Add the initial Nim-only typed serializer v1 API with strict object decoding
  and bounded NIF/BIF round trips.
- Add canonical `Table` and `OrderedTable` typed serialization with duplicate
  key rejection and container limits.
- Add canonical `distinct T` typed serialization with strict type-name checks.
- Add canonical `HashSet` and `OrderedSet` typed serialization with duplicate
  item rejection and container limits.
- Reject typed integer narrowing overflow, invalid UTF-8 strings, and `cstring`.
- Reject variant objects with `nkeUnsupportedType` rather than risking a Nim
  case-object branch-transition failure.
- Decode typed BIF values directly from validated BIF tokens without an
  intermediate NIF text allocation.
- Add typed `Range` support with explicit boundary validation on decode.
- Build BIF output incrementally within `maxOutputBytes` and correctly account
  for multi-byte BIF header varints.

## 0.2.0 - 2026-08-01

- Add finite, caller-configurable `CodecLimits` to Nim and C codec APIs.
- Add structured `NifKitError` categories and BIF v5 version reporting.
- Bound BIF-to-NIF rendering and NIF/BIF pool, token, depth, and index paths.
- Add ARC/Valgrind CI coverage and the typed serializer mapping design.

## 0.1.1

- Add BIF byte-order fixture coverage.
