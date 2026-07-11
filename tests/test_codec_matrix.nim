import std/unittest
import ../src/nifkit

type CodecCase = object
  name: string
  source: string
  expected: string
  indexedSymbols: int

const Cases = [
  CodecCase(name: "basic record",
            source: "(record title \"NIF\" -5 12u)",
            expected: "(record title \"NIF\" -5 12u)",
            indexedSymbols: 0),
  CodecCase(name: "directives and suffix comments",
            source: "(.nif27)\n(.lang \"json\" (oconstr#metadata# (kv title \"NIF\")))",
            expected: "(.nif27)\n(.lang \"json\" (oconstr#metadata# (kv title \"NIF\")))",
            indexedSymbols: 0),
  CodecCase(name: "escaped string and char",
            source: "(record text \"line\\nquote\\^slash\\|\" char 'A')",
            expected: "(record text \"line\\nquote\\^slash\\|\" char 'A')",
            indexedSymbols: 0),
  CodecCase(name: "visible global symbol definition",
            source: "(record :thing.0.module value)",
            expected: "(record :thing.0.module value)",
            indexedSymbols: 1),
  CodecCase(name: "hidden global symbol definition",
            source: "(record :thing.0.module .)",
            expected: "(record :thing.0.module .)",
            indexedSymbols: 1),
  CodecCase(name: "nested tags",
            source: "(root (child name \"one\") (child name \"two\"))",
            expected: "(root (child name \"one\") (child name \"two\"))",
            indexedSymbols: 0),
  CodecCase(name: "short and wide line-info",
            source: "(record@5,3,file.nim title@2,0#field# \"NIF\"@4,0#literal#)",
            expected: "(record@5,3,file.nim title@2,0#field# \"NIF\"@4,0#literal#)",
            indexedSymbols: 0)
]

suite "NIF/BIF codec matrix":
  for item in Cases:
    test item.name:
      let bif = nifToBif(item.source)
      validateBif(bif)
      check bifToNif(bif) == item.expected
      check parseBif(bif).index.len == item.indexedSymbols

  test "empty document is valid and round-trips as empty BIF token stream":
    let bif = nifToBif("")
    validateBif(bif)
    check bifToNif(bif) == ""
    check parseBif(bif).tokens.len == 0
