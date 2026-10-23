# Changelog

## Unreleased

- Add an editable, language-neutral document API for NIF and BIF, including
  stable node handles, typed scalar access, root/child editing, parent lookup,
  subtree cloning, preorder traversal, source information, and canonical output.
- Add direct NIF token parsing, token-document rendering, and NIF validation
  without an intermediate serialized BIF payload. Preserve existing Nim APIs,
  typed profiles, and the C ABI for independently updated downstream users.
- Use explicit work stacks for core text parsing and rendering and for tree
  operations. Enforce configured tree/container budgets, reject invalid edits
  and cycles, and regenerate BIF pools, jumps, and symbol indexes after edits.
- Reject overflowing line-information values with recoverable errors and fix
  hidden-symbol indexing when a definition carries suffix metadata.
- Reject out-of-range BIF characters and overflowing extension bits instead of
  silently truncating them; retain valid signed 84-bit carrier sign extension.
- Release typed-serializer reference-tracking scratch storage after successful
  and failed conversions, and track allocator-backed memory in Valgrind CI.
- Exercise editable documents under the ARC/ORC memory-safety checks, including
  deep trees, wide tag jumps, malformed inputs, and legacy codec compatibility.

## 0.4.1 - 2026-10-21

- Track the NIF specification at `a31513c` (2026-10-13): accept hexadecimal,
  octal, and binary integers, digit separators, and literal `#` and `:` in
  quoted strings. Preserve public APIs, C ABI, BIF v5 bytes for equivalent
  values, and existing canonical output. Reject overflowing integers without
  truncation or signed reinterpretation.
- Keep the BIF decoder fixtures compatible with Nim 2.2.12.

## 0.4.0 - 2026-08-11

- Add typed data profile v2 and `NifBytes`, an opaque bounded byte sequence for
  images, media, encrypted payloads, and other binary data without Base64
  expansion.
- Preserve UTF-8 validation for `string` and keep typed profile v1 decoding for
  existing values.
- Document the boundary between in-memory binary values and application-level
  streaming multipart transfers for large attachments.

## 0.3.1 - 2026-08-10

- Make omitted `CodecLimits` unbounded at the application-policy level;
  network-facing integrations now choose and pass their own limits explicitly.
- Add Linux/macOS Clang and Windows MSVC AddressSanitizer coverage for both
  ARC and ORC repeated codec and typed-serializer paths.
- Document how embedding applications should choose fixed `CodecLimits` at
  each untrusted-data boundary.
## 0.3.0 - 2026-08-10

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
- Add safe, strict typed serialization for variant objects by decoding the
  discriminant before their active branch fields.
- Decode typed BIF values directly from validated BIF tokens without an
  intermediate NIF text allocation.
- Add typed `Range` support with explicit boundary validation on decode.
- Build BIF output incrementally within `maxOutputBytes` and correctly account
  for multi-byte BIF header varints.
- Add strict typed error paths and malformed/truncation recovery coverage.

## 0.2.0 - 2026-08-01

- Add finite, caller-configurable `CodecLimits` to Nim and C codec APIs.
- Add structured `NifKitError` categories and BIF v5 version reporting.
- Bound BIF-to-NIF rendering and NIF/BIF pool, token, depth, and index paths.
- Add ARC/Valgrind CI coverage and the typed serializer mapping design.

## 0.1.1

- Add BIF byte-order fixture coverage.
