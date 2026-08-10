# Typed serializer design

This document defines the general data-exchange profile implemented by the
typed NIF serializer in NIFKit v0.3. It is deliberately separate from compiler NIF ASTs:
compiler-specific tags, line information, and symbol indexes are not part of
this profile.

## Status and API

The profile is implemented in the v0.3.0 release. Its public API is:

```nim
proc toNif*[T](value: T; limits = defaultCodecLimits()): string
proc fromNif*[T](source: string; _: typedesc[T];
                 limits = defaultCodecLimits();
                 options = defaultTypedCodecOptions()): T
proc toBif*[T](value: T; limits = defaultCodecLimits()): string
proc fromBif*[T](source: string; _: typedesc[T];
                 limits = defaultCodecLimits();
                 options = defaultTypedCodecOptions()): T
```

All encoding and decoding APIs accept `CodecLimits`; no typed conversion may
bypass the bounded NIF/BIF codec.

`defaultCodecLimits()` supplies finite baseline limits, but applications that
receive untrusted data should define a fixed `CodecLimits` policy for each
trust boundary. The application—not the peer—chooses the input/output byte,
depth, string, pool, and container budgets appropriate for that endpoint.
Typed serializer calls use the supplied limits just as raw NIF/BIF calls do.

`fromBif` reads the validated BIF token stream directly and does not construct
an intermediate NIF text string. `toBif` constructs BIF directly while
preserving the same canonical profile representation as `toNif`.

## Canonical profile

The root is `(nifkit\2Ddata 1 value)`. The escaped hyphen is required by NIF
tag grammar; its decoded tag name is `nifkit-data`. Version `1` identifies
these mapping rules. Writers emit UTF-8 byte strings in canonical NIF escaping, fields in
declaration order, and `Table` entries sorted by their canonical encoded key.

| Nim value | NIF representation |
| --- | --- |
| `bool` | `true` or `false` |
| signed integer | decimal signed integer |
| unsigned integer | decimal integer with `u` suffix |
| `float32`, `float64` | canonical finite decimal float; non-finite values are rejected initially |
| `string` | NIF string |
| `char` | NIF character |
| `enum` | `(enum "TypeName" "MemberName")` |
| `Option[T]` | `(some value)` or `none` |
| `seq[T]`, `array` | `(seq value...)` or `(array value...)` |
| tuple | `(tuple value...)` |
| object | `(object "TypeName" (field "name" value)...)` |
| variant object | `(object "TypeName" (field "discriminant" value) (field "activeBranch" value)...)`; the discriminant is decoded first |
| `ref object` | `nil` or `(ref object-value)`; cycles are rejected |
| `Table[K,V]`, `OrderedTable[K,V]` | `(table (entry key value)...)` |
| `HashSet[T]`, `OrderedSet[T]` | `(set value...)` |
| `distinct T` | `(distinct "TypeName" value)` |
| `range[A..B]` | underlying ordinal representation, constrained to `A..B` on decode |
| `nil` | `nil` |

Field names are strings, not NIF identifiers, so Nim identifiers that require
escaping remain lossless. Tuples are positional and objects are named; the two
are never inferred from each other.

Both table kinds are written with entries sorted by the canonical encoded key.
`OrderedTable` therefore preserves key/value pairs but is decoded in canonical
key order rather than its original insertion order.
Sets follow the same canonical member ordering; `OrderedSet` is decoded in that
canonical order rather than its original insertion order.

## Compatibility rules

Decoders reject unknown fields by default; set
`TypedCodecOptions.allowUnknownFields` to permit them for forward compatibility.
Missing object fields are errors in profile v1. Enum decoding uses member
names, never ordinal values, to avoid silently changing meaning when source
order changes. Type names are required by default; set
`TypedCodecOptions.requireTypeNames` to `false` only for an explicitly managed
compatibility boundary. Schema changes require a new root version or an
explicitly declared migration.

`Option.none`, `nil`, and an absent object field are distinct states. A
non-`ref` value cannot decode from `nil`. Reference identity and cycles are out
of scope for profile version 1; ref values are tree-shaped.

## Error model

All failures propagate `NifKitError`. `kind` distinguishes syntax/resource
errors from typed failures including `nkeTypeMismatch`, `nkeUnknownField`,
`nkeMissingField`, `nkeUnknownEnumMember`, `nkeArrayLengthMismatch`,
`nkeUnsupportedType`, `nkeUnsupportedDataProfile`, `nkeCyclicReference`, and
`nkeNonFiniteFloat`. `offset` identifies the input location where applicable;
`path` identifies the logical value path such as `$.items[3].price`. Callers
must never parse error message text.
