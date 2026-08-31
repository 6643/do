# Task 8 Node validator adapter report

## Scope

Migrated only the `--component-wasm` assembly path in
`src/build/test/validate_wasi_bind_manifest.mjs` and the required assertions in
`src/build/test/test_wasi_bind_manifest_tool.mjs`.

The validator now invokes `DO_TOOLCHAIN_BIN` (defaulting to the repository
`bin/do-toolchain`) for typed `embed-component`, `new-component`, and
`validate-component` operations. `DO_TOOLCHAIN_LOCK` is passed through to the
adapter and defaults to the repository lock path. The former raw
`WASM_TOOLS` executable is not read by the validator. The old commands did not
pass a feature flag, so the typed calls explicitly pass `--features none`; the
adapter consequently emits no underlying wasm-tools `--features` argument and
preserves the previous feature semantics. Existing `wasm-tools ... failed`
error labels remain unchanged.

The test's fake executable now records the exact typed argv, rejects any other
operation shape, and forces `validate-component` to exit nonzero. The test
asserts all three operations, explicit `none` profiles, failure propagation,
and the existing error prefix. The previous direct `wasm-tools component wit`
directory check was replaced with typed `component-wit` against the generated
Component, preserving the package-output assertions.

## TDD evidence

RED was observed before the production change: the updated fake test failed
with the old invocation shape, reporting `component embed ...` to the fake
adapter instead of the required `embed-component ...` operation.

GREEN was observed after the validator migration:

```text
node src/build/test/test_wasi_bind_manifest_tool.mjs \
  src/build/test/validate_wasi_bind_manifest.mjs <tmp-dir>
  -> ok: wasi-bind manifest tool

DO_TOOLCHAIN_BIN=.../bin/do-toolchain \
DO_TOOLCHAIN_LOCK=.../toolchain/toolchain.lock.json \
node src/build/test/test_wasi_bind_manifest_tool.mjs \
  src/build/test/validate_wasi_bind_manifest.mjs <tmp-dir>
  -> ok: wasi-bind manifest tool
```

The first command exercises the repository-default adapter paths; the second
explicitly exercises `DO_TOOLCHAIN_BIN` and `DO_TOOLCHAIN_LOCK` overrides. Both
the real assembly/validation path and the fake failure/argv path passed.

Additional checks:

```text
bun build --target=node --no-bundle src/build/test/validate_wasi_bind_manifest.mjs --outdir /tmp/do-node-syntax-check  -> passed
bun build --target=node --no-bundle src/build/test/test_wasi_bind_manifest_tool.mjs --outdir /tmp/do-node-syntax-check  -> passed
git diff --check -- src/build/test/validate_wasi_bind_manifest.mjs src/build/test/test_wasi_bind_manifest_tool.mjs  -> passed
```

`run_tests.sh` and unrelated dirty files were not modified. The report itself
is the only additional file in this batch.

## Concerns

- This validator still labels adapter errors with the historical `wasm-tools`
  prefix for compatibility; the executable path and argv are fully typed and
  no raw wasm-tools fallback remains in the validator.
- The integration portion of the Node test remains conditional on the
  resolved adapter existing, matching the former conditional external-tool
  test. CI should provide `bin/do-toolchain` and the lock file to exercise it.
