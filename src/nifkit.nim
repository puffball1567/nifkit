import nifkit/bif_decoder
import nifkit/nif_encoder
import nifkit/codec_limits
import nifkit/typed_serializer

export bif_decoder
export nif_encoder
export codec_limits
export typed_serializer

proc codecInfo*(): string =
  "nifkit: spec-based NIF/BIF v5 codec"
