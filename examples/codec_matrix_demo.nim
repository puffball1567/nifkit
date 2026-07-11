## Small NIFKit codec matrix demo.

import nifkit

const Cases = [
  "(record title \"NIF\" -5 12u)",
  "(.nif27)\n(.lang \"json\" (oconstr#metadata# (kv title \"NIF\")))",
  "(record text \"line\\nquote\\^slash\\|\" char 'A')",
  "(record :thing.0.module value)",
  "(root (child name \"one\") (child name \"two\"))",
  "(record@5,3,file.nim title@2,0#field# \"NIF\"@4,0#literal#)"
]

when isMainModule:
  for i, source in Cases:
    let bif = nifToBif(source)
    validateBif(bif)
    echo "case=", i, " bytes=", bif.len, " nif=", bifToNif(bif)
