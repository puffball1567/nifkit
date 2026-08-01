# Contributing to NIFKit

NIFKit accepts untrusted NIF/BIF input, so decoder changes must preserve
bounded allocation, structured errors, and C ABI compatibility.

## Branch and Release Workflow

- Create feature and fix branches from `devel`.
- Open feature and fix pull requests against `devel`; they do not target
  `main`.
- Keep `devel` green with the codec, malformed-input, and C ABI tests.
- For a release, open a pull request from `devel` to `main` and merge it with
  a merge commit after release checks pass. Do not squash or rebase that
  release pull request, so `devel` remains an ancestor of `main`.
- Create release tags from `main` only after the release merge. Direct
  development commits and feature merges do not land on `main`.
- Repository Rulesets require pull requests for both protected branches. The
  source-policy check accepts pull requests to `main` only from this
  repository's `devel` or `hotfix/*` branches.
- Use `hotfix/*` only for urgent corrections to a released version. Cut it
  from `main`, then merge or cherry-pick the correction back into `devel`.

## Verification

Run `nimble test` and `nimble cabiContract` before opening a pull request.
Changes to bounds checking or decoder allocation also require focused boundary
tests; ARC-sensitive changes require the project's Valgrind check once added.
