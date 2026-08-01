# Typed serializer design

This document defines the proposed general data-exchange profile for a future
typed NIF serializer. It is deliberately separate from compiler NIF ASTs:
compiler-specific tags, line information, and symbol indexes are not part of
this profile.

## Status and API

This is a design, not an implementation commitment. Its eventual API is:

```nim
proc toNif*[T](value: T): string
proc fromNif*[T](source: string; _: typedesc[T]): T
proc toBif*[T](value: T): string
proc fromBif*[T](source: string; _: typedesc[T]): T
```

All decoding APIs will accept `CodecLimits`; no typed decoder may bypass the
bounded NIF/BIF codec.

## Canonical profile

The root is `(nifkit-data 1 value)`. Version `1` identifies these mapping
rules. Writers emit UTF-8 byte strings in canonical NIF escaping, fields in
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
| variant object | object form plus `(case "discriminant" value)` |
| `ref object` | `nil` or `(ref object-value)`; cycles are rejected |
| `Table[K,V]` | `(table (entry key value)...)` |
| `distinct T` | `(distinct "TypeName" value)` |
| `nil` | `nil` |

Field names are strings, not NIF identifiers, so Nim identifiers that require
escaping remain lossless. Tuples are positional and objects are named; the two
are never inferred from each other.

## Compatibility rules

Decoders reject unknown fields by default. An opt-in pragma may permit unknown
fields for forward compatibility. Missing object fields use a declared default
only when one exists; otherwise they are an error. Enum decoding uses member
names, never ordinal values, to avoid silently changing meaning when source
order changes. Schema changes require a new root version or an explicitly
declared migration.

`Option.none`, `nil`, and an absent object field are distinct states. A
non-`ref` value cannot decode from `nil`. Reference identity and cycles are out
of scope for profile version 1; ref values are tree-shaped.

## Error model

Syntax and resource failures propagate `NifKitError`. Typed shape/type failures
will add a separate structured error kind with a NIF byte offset and a logical
field path. Callers must never parse error message text.
