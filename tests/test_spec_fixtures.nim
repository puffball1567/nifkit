import std/unittest
import ../src/nifkit

type SpecFixture = object
  name: string
  source: string
  canonical: string

const Fixtures = [
  SpecFixture(
    name: "json tag vocabulary shape",
    source: "(.nif27)\n(.lang \"json\" (oconstr (kv name \"nifkit\") (kv ok (true))))",
    canonical: "(.nif27)\n(.lang \"json\" (oconstr (kv name \"nifkit\") (kv ok (true))))"),
  SpecFixture(
    name: "suffix comments and line info",
    source: "(module@1,0,file.nim#root# (proc#declaration# name@2,0 \"main\"))",
    canonical: "(module@1,0,file.nim#root# (proc#declaration# name@2,0 \"main\"))"),
  SpecFixture(
    name: "escaped atom data",
    source: "(record key\\20with\\20spaces value\\23with\\23hash thing\\2E0.module)",
    canonical: "(record key\\20with\\20spaces value\\23with\\23hash thing.0.module)"),
  SpecFixture(
    name: "numeric atoms",
    source: "(numbers -1 -34359738368 0u 18446744073709551615u 1.5 1E3)",
    canonical: "(numbers -1 -34359738368 0u 18446744073709551615u 1.5 1000.0)"),
  SpecFixture(
    name: "adjacent empty nodes and nested tags",
    source: "(root ... (child . . .))",
    canonical: "(root . . . (child . . .))"),
  SpecFixture(
    name: "visible and hidden symbol definitions",
    source: "(defs :pkg.0.public :pkg.0.hidden .)",
    canonical: "(defs :pkg.0.public :pkg.0.hidden .)")
]

suite "NIF/BIF spec fixtures":
  for fixture in Fixtures:
    test fixture.name:
      let bif = nifToBif(fixture.source)
      validateBif(bif)
      check bifToNif(bif) == fixture.canonical

  test "global index is derived from symbol definitions":
    let doc = parseBif(nifToBif("(defs :pkg.0.public :pkg.0.hidden . local)"))
    check doc.index.len == 2
    check doc.index[0].visibility == 1
    check doc.index[1].visibility == 0
