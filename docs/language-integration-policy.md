# Language integration policy

NIF is deliberately simple enough to be implemented independently. NIFKit's
Nim implementation is the reference codec maintained by this repository; it is
not intended to make a C FFI boundary the universal integration path.

## Preferred integration

- Nim consumers use the public Nim API directly.
- C and C++ consumers may use the stable C ABI in `include/nifkit.h`.
- Other languages should use a native implementation or port in that language
  when direct, high-performance integration is needed.
- A portable component or runtime binding may be appropriate for a specific
  deployment target, but it must expose typed errors and explicit resource
  limits rather than requiring callers to parse C error strings.

Each implementation must follow the NIF/BIF specification and run the shared
conformance and malformed-input corpus. New language support is therefore a
first-class implementation effort, not merely a wrapper around the C ABI.

## C ABI scope

The C ABI remains supported for compatibility. Existing symbols and signatures
are not removed or changed without an ABI-version decision. It should not be
advertised as the default Rust, Node, Python, or general foreign-function
interface solution.
