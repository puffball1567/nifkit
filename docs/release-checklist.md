# Release Checklist

This checklist is for publishing a nifkit release.

## Local Verification

Run the full verification suite before tagging:

```sh
nimble verify -y
```

The verification suite covers:

- NIF text to BIF binary encoding
- BIF binary to canonical NIF text decoding
- line-info fixtures, including filename, comment, position, and negative
  deltas
- malformed BIF rejection cases
- deterministic malformed-input fuzz and boundary checks
- specification-derived fixture roundtrips
- C ABI contract behavior
- representative codec matrix examples

## CI Verification

Pushes and pull requests run the same verification entry point on:

- `ubuntu-latest`
- `macos-latest`
- `windows-latest`

The CI job runs:

```sh
nimble verify -y
```

That means every supported CI OS must pass the codec test suite, matrix demo,
and C ABI contract before a release should be treated as ready. The `cabiContract`
task has OS-specific build commands for Linux, macOS, and Windows so the public
C ABI is checked outside Nim code, through `include/nifkit.h` and
`examples/cabi_contract.c`.

## Dependency Boundary

`nifkit` is a generic NIF/BIF toolkit. It must not depend on RocheDB,
rochedb-nif, sodiumkit, or application-specific storage logic.

Check this before release:

```sh
rg -n "rochedb|ceresdb|sodiumkit" src include examples tests
```

No matches should be returned.

## Versioning

Update `version` in `nifkit.nimble`, then create a matching Git tag:

```sh
git tag -a v0.1.0 -m "nifkit v0.1.0"
git push origin main:main
git push origin refs/tags/v0.1.0:refs/tags/v0.1.0
```

## After GitHub Release

After the repository and tag are public, nifkit can be submitted to the Nimble
package list through the standard `nim-lang/packages` pull request flow.
