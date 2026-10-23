# Editable NIF/BIF documents

The document API reads NIF text and BIF v5 into the same language-neutral tree.
It supports inspection, preorder traversal, editing, cloning, and canonical
output. It does not interpret tags, resolve program symbols, or compile code.

```nim
import nifkit/document

let doc = parseNif("(record title \"before\" count 1)")
let record = doc[0]
record[1].text = "after"

for node in doc.walk():
  if node.kind == nfInt:
    node.intValue = node.intValue + 1

record.add doc.newString("added")
doAssert doc.renderNif() == "(record title \"after\" count 2 \"added\")"

let binary = doc.renderBif()
let loaded = parseBifTree(binary)
doAssert loaded.renderNif() == doc.renderNif()
```

Import `nifkit/document` to opt into the tree API. Add `import nifkit` when the
existing codec or typed APIs are also needed. The legacy `nifkit` umbrella does
not re-export the new node operations, preserving its existing namespace.
The existing `parseBif` still returns `BifDocument`, the low-level token/pool
representation. `parseBifTree` is the new editable-tree entry point.

## Node access

`document.len` is the number of roots; `document[index]` returns a root handle.
`node.len` is the number of children, or zero for an atom. `node[index]` accesses
a compound's children. Both `for root in document` and `for child in node` keep
document order. `document.walk()` visits all roots and descendants in preorder;
`node.walk()` visits that node and its descendants.

| Kind | Value access | Detached-node constructor |
| --- | --- | --- |
| `nfEmpty` | No value | `document.newEmpty()` |
| `nfChar` | `charValue` | `document.newChar(value)` |
| `nfString` | `text` | `document.newString(value)` |
| `nfInt` | `intValue` (`int64`) | `document.newInt(value)` |
| `nfUInt` | `uintValue` (`uint64`) | `document.newUInt(value)` |
| `nfFloat` | `floatValue` (`float64`) | `document.newFloat(value)` |
| `nfIdentifier` | `text` | `document.newIdentifier(value)` |
| `nfSymbol` | `text` | `document.newSymbol(value)` |
| `nfSymbolDef` | `text` | `document.newSymbolDef(value)` |
| `nfCompound` | `tag` and indexed children | `document.newCompound(tag)` |

Values and tags have matching setters. Reading or writing the wrong value kind
raises `NifKitError` with `nkeTypeMismatch`. Empty identifiers, invalid symbol
or directive names, invalid handles, and out-of-range indexes raise structured
errors. A node's kind is fixed; replace the node to change its kind.

Strings, names, and character values are bytes, with no UTF-8 requirement.
Characters contain exactly one byte. Escaped source spellings are decoded on
input and escaped as needed on output. Integers retain signed/unsigned kind
and their full 64-bit range. NIFKit's separate typed data profiles and their
UTF-8 rules are unchanged.

## Ownership and edits

`NifDocument` is an owning reference. Assigning it or a `NifNode` handle shares
the same document; it does not clone the tree. Handles remain valid when other
nodes are inserted, replaced, or removed. A handle also keeps its owning
document alive.

New nodes are detached. Use `document.add(node)` to attach a root, or
`parent.add(node)` to attach a child. `insert(index, node)` selects the position.
The same node cannot be attached twice. Use `remove(index)` or `node.detach()`
before moving it. Removal returns the detached handle. Indexed assignment
replaces a root or child and detaches the previous node. Self replacement is
a no-op. Tree edits cannot introduce a cycle.

```nim
let doc = parseNif("(first 1) (second)")
let moved = doc[0].remove(0)
doc[1].add moved
doc[0] = doc.newCompound("replacement")
```

`node.parent` returns `Option[NifNode]`; roots and detached nodes have no node
parent. Import `std/options` to inspect it with `isSome`, `isNone`, or `get`.
To attach a node from another document, use
`destination.cloneSubtree(sourceNode)`. It returns a detached deep copy, also
usable for independent duplication inside one document.

Detached nodes retain storage in their document. Releasing all references to
the document and its handles releases the arena. For long-lived editing
sessions, copy reachable roots into a fresh document to discard detached data:

```nim
let compacted = newNifDocument()
for root in doc:
  compacted.add compacted.cloneSubtree(root)
```

Scalar and line-information edits are allowed during traversal. Structural
changes during `walk` or root/child iteration raise a structured error when
iteration resumes. Collect handles first when a traversal should remove or
move nodes. Documents are mutable and are not internally synchronized; callers
must synchronize access when sharing them between threads.

## Source information and output

`hasLineInfo` reports whether a node has an explicit source-information suffix.
`lineInfo` returns its effective absolute position. Positions inherit from the
parent when no explicit suffix is present; comments do not inherit.
`node.lineInfo = value` sets an explicit absolute position and optional comment.
`clearLineInfo()` restores inheritance. Explicit positions are retained when a
subtree moves; inherited positions follow its new parent.

`renderNif` emits canonical NIF, preserving node kinds and representable suffix
metadata. Original whitespace, numeric bases, and escape spellings are not
retained. `renderBif` rebuilds pools, tag jumps, and global symbol indexes from
the reachable tree, so callers never repair token offsets after editing.
An unknown directive remains an ordinary compound node for the application to
inspect; the document API does not implement a dialect's semantics.

Some BIF values cannot be faithfully expressed in core NIF text: non-finite
IEEE-754 floats and an explicit empty filename beneath an inherited nonempty
filename. `renderBif` preserves these values. `renderNif` rejects them with a
structured error rather than silently changing their meaning.

## Validation and resource limits

`parseNif`, `parseBifTree`, `renderNif`, `renderBif`, `validateNif`, and
`validateDocument` accept `CodecLimits`. Existing codec defaults and the C ABI
are unchanged: omitted limits impose no application-level policy. Choose fixed
limits at untrusted-input boundaries.

```nim
var limits = defaultCodecLimits()
limits.maxInputBytes = 1_048_576
limits.maxOutputBytes = 2_097_152
limits.maxNestingDepth = 128
limits.maxTokens = 100_000
limits.maxContainerItems = 10_000
limits.maxStringBytes = 65_536
limits.maxPoolEntries = 10_000
limits.maxPoolBytes = 1_048_576
limits.maxIndexEntries = 10_000

let bounded = parseNif("(record 1)", limits)
bounded.validateDocument(limits)
```

Parsing checks input, token, pool, string, container, index, and nesting budgets
where applicable. `maxContainerItems` bounds roots and each compound's children.
The tree depth counts compound ancestors including the compound itself; a
top-level atom has depth zero. Parsing produces no serialized output, so
`maxOutputBytes` is enforced on rendering, not on an intermediate conversion.
`validateNif` uses the same parser; `validateDocument` verifies BIF output and its
resource budget. The typed-profile field/reference budgets retain their
existing meanings and do not count arena handles.

Factories and edits operate on caller-provided in-memory values. Output
validation checks the resulting reachable tree against the selected limits.
Text parsing, BIF tree loading, traversal, cloning, and rendering use explicit
work stacks instead of recursive owning nodes. Errors remain recoverable
`NifKitError` instances derived from the existing `BifError` base.

## Compatibility

The document API is additive. Existing `nifToBif`, `bifToNif`, `parseBif`,
`validateBif`, typed serializers, and C entry points remain available with their
existing signatures. Existing core NIF/BIF documents and typed data profiles
remain readable. Downstream applications can adopt the new API independently;
they do not need a coordinated update merely because NIFKit is upgraded.
The editable API lives in its own opt-in module, so existing imports do not
acquire additional general-purpose node constructors and editing operations.

Low-level integrations can also use `parseNifTokens` and `renderBifDocument`
with `BifDocument`, avoiding intermediate binary serialization. These do not
replace the original `parseBif` or `encodeBifDocument` entry points.
