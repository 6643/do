# Task 8 GC scalar core parse migration report

Date: 2026-08-31

## Changes

- Migrated `examples/gc-p3-runtime/test_do_gc_scalar_call_graph.sh` and `test_do_gc_scalar_control_flow.sh` to the absolute repo-root `bin/do-toolchain parse-core` adapter.
- Exported the absolute repo-root `DO_TOOLCHAIN_LOCK` in both scripts.
- Removed direct `wasm-tools` lookup and the obsolete 1.255.0 version guard.
- Preserved the existing WAT markers, ARC prohibition checks, temporary cleanup, output checks, and shell exit semantics.

## Verification

- `bash -n examples/gc-p3-runtime/test_do_gc_scalar_call_graph.sh examples/gc-p3-runtime/test_do_gc_scalar_control_flow.sh`: PASS.
- Root execution of both scripts: PASS.
- Execution of both scripts from an unrelated temporary cwd: PASS.
- Current-only/direct scan: PASS; neither script contains `wasm-tools`, `WASM_TOOLS_BIN`, `command -v wasm-tools`, or a legacy version guard, and both use `"$toolchain_bin" parse-core`.
- `bash examples/p3-runtime/test_wasm_tools_current_only.sh`: PASS.
- Scoped `git diff --check` for the two scripts and this report: PASS.

## Concerns

- No Critical, Important, or Minor concerns found in this narrow migration.
- This batch only migrates two GC scalar core-parse gates; it does not claim broader GC or Task 8 completion.
