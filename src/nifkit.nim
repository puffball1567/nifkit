import nifkit/bif_decoder
import nifkit/nif_encoder

export bif_decoder
export nif_encoder

proc codecInfo*(): string =
  "nifkit: spec-based NIF/BIF v5 codec"
