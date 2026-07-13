# nifkit v0.1.1

This patch release adds a byte-level encoder fixture for canonical BIF
little-endian output.

## Changed

- Bumped package metadata to `0.1.1`.
- Set package author metadata to `puffball1567`.

## Fixed / Hardened

- Added a direct fixture test proving that fixed-width BIF fields are emitted in
  canonical little-endian byte order.
- The new test checks the BIF magic/version, `indexOffset=28` as
  `1c 00 00 00 00 00 00 00`, and the `1u` token word as `14 00 00 00`.

## Verification

- `nimble test -y`
- `nimble check`

## Notes

nifkit still has not been tested on real big-endian hardware. The codec
boundary is designed to avoid host-native integer layout by using explicit
little-endian encode/decode routines.
