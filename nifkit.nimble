version       = "0.1.0"
author        = "Nifkit contributors"
description   = "Spec-based NIF/BIF toolkit for multiple languages"
license       = "MIT"
srcDir        = "src"

requires "nim >= 2.2.0"

task test, "Run the NIF/BIF codec test suite":
  exec "nim c --nimcache:nimcache/test_nif_encoder -r tests/test_nif_encoder.nim"
  exec "nim c --nimcache:nimcache/test_bif_decoder -r tests/test_bif_decoder.nim"
  exec "nim c --nimcache:nimcache/test_line_info -r tests/test_line_info.nim"
  exec "nim c --nimcache:nimcache/test_codec_matrix -r tests/test_codec_matrix.nim"
  exec "nim c --nimcache:nimcache/test_spec_fixtures -r tests/test_spec_fixtures.nim"
  exec "nim c --nimcache:nimcache/test_malformed_fuzz -r tests/test_malformed_fuzz.nim"

task cabiContract, "Build and run the NIFKit C ABI contract":
  when defined(windows):
    exec "nim c --app:lib -d:release --hints:off --warnings:off --nimcache:nimcache/nifkit-capi -o:nifkit.dll src/nifkit_capi.nim"
    exec "clang -std=c11 -Wall -Wextra -DNIFKIT_DYNAMIC_LOAD -Iinclude examples/cabi_contract.c -o nifkit_cabi_contract.exe"
    exec "nifkit_cabi_contract.exe"
  elif defined(macosx):
    exec "nim c --app:lib -d:release --hints:off --warnings:off --nimcache:/tmp/nifkit-capi -o:/tmp/libnifkit.dylib src/nifkit_capi.nim"
    exec "clang -std=c11 -Wall -Wextra -Iinclude examples/cabi_contract.c /tmp/libnifkit.dylib -o /tmp/nifkit_cabi_contract"
    exec "DYLD_LIBRARY_PATH=/tmp /tmp/nifkit_cabi_contract"
  else:
    exec "nim c --app:lib -d:release --hints:off --warnings:off --nimcache:/tmp/nifkit-capi -o:/tmp/libnifkit.so src/nifkit_capi.nim"
    exec "clang -std=c11 -Wall -Wextra -Iinclude examples/cabi_contract.c -L/tmp -lnifkit -Wl,-rpath,/tmp -o /tmp/nifkit_cabi_contract"
    exec "/tmp/nifkit_cabi_contract"

task verify, "Run the full NIFKit verification suite":
  exec "nimble test -y"
  exec "nimble matrixDemo -y"
  exec "nimble cabiContract -y"

task matrixDemo, "Run the NIFKit codec matrix demo":
  exec "nim c --nimcache:nimcache/codec_matrix_demo -r examples/codec_matrix_demo.nim"
