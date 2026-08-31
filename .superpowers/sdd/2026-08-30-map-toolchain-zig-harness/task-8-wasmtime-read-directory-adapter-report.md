# Wasmtime and read-directory current-only adapter report

## Scope

Migrated and verified these two non-GC entrypoints:

- `examples/p3-runtime/test_wasmtime_p3_assembly.sh`
- `examples/p3-runtime/test_do_wasi_filesystem_read_directory_abi.sh`

The requested `examples/gc-p3-runtime/test_do_wasi_filesystem_read_directory_abi.sh`
path does not exist in this checkout; the existing same-named entrypoint is the
`examples/p3-runtime` path above and was used. No other files were intentionally
changed by this batch.

`test_wasmtime_p3_assembly.sh` now uses typed `parse-core`, `validate-component`,
and `print-component`, while its assembly helper uses typed embed/new/validate.
It preserves marker checks, component checks, Rust runner invocation, and the
negative unpinned-tool test. It exports the absolute lock path so root and
unrelated-cwd runs resolve the same pinned toolchain.

`test_do_wasi_filesystem_read_directory_abi.sh` now uses
`embed-component-template`, `parse-core`, `new-component`, explicit
`validate-component --features component-async`, and `component-wit`. The
template adapter retains the prior dummy-name and async-callback behavior; the
explicit validation preserves the old validation gate after `new-component`.

## Verification

All commands below were run from `/home/_/._/_/do` unless noted:

```text
bash -n examples/p3-runtime/test_wasmtime_p3_assembly.sh examples/p3-runtime/test_do_wasi_filesystem_read_directory_abi.sh
exit=0

bash examples/p3-runtime/test_wasmtime_p3_assembly.sh
exit=0
bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_abi.sh
exit=0

unrelated_cwd=$(mktemp -d); cd "$unrelated_cwd"; bash /home/_/._/_/do/examples/p3-runtime/test_wasmtime_p3_assembly.sh; bash /home/_/._/_/do/examples/p3-runtime/test_do_wasi_filesystem_read_directory_abi.sh
exit=0 for both commands

cd /home/_/._/_/do; bash examples/p3-runtime/test_wasm_tools_current_only.sh
exit=0

if rg -n '^[[:space:]]*(wasm-tools|wasmtime)([[:space:]]|$)' examples/p3-runtime/test_wasmtime_p3_assembly.sh examples/p3-runtime/test_do_wasi_filesystem_read_directory_abi.sh; then exit 1; fi
exit=0 (no direct invocations)

git diff --check -- examples/p3-runtime/test_wasmtime_p3_assembly.sh examples/p3-runtime/test_do_wasi_filesystem_read_directory_abi.sh .superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-wasmtime-read-directory-adapter-report.md
exit=0
```

The initial unrelated-cwd run of `test_wasmtime_p3_assembly.sh` failed with
`error[ToolchainAdapter]: load lock: FileNotFound`, proving the missing lock
export. Adding the absolute `DO_TOOLCHAIN_LOCK` export fixed that failure; the
fresh unrelated-cwd rerun passed.

## Residuals and verdict

No Critical, Important, or Minor blocker remains within these two entrypoints.
The repository still contains 127 residual direct-tool gates from the prior
record-resource batch inventory; this batch does not claim all current-only
migrations, Task 8 completion, or map runtime completion.
