# GC Core-parse residual adapter batch report

## Scope

Migrated only these eight GC scripts to the repo-root `bin/do-toolchain
parse-core` operation:

- `test_async_frame_table.sh`
- `test_cabi_realloc_budget.sh`
- `test_do_gc_managed_struct_preserve_field.sh`
- `test_do_gc_managed_struct_renamed.sh`
- `test_do_gc_managed_struct_set.sh`
- `test_do_gc_scalar_leaf.sh`
- `test_do_gc_text_identity.sh`
- `test_do_gc_text_identity_renamed.sh`

Each script now exports `DO_TOOLCHAIN_LOCK` from the repository root. Existing
WAT markers, GC runtime probes, expected values, quota trap, and exit-code
semantics remain unchanged. The scalar-leaf script no longer carries the old
`wasm-tools 1.255.0` identity guard. Runtime Wasmtime and Zig probe calls are
outside this Core-parse-only batch and were retained.

## Red evidence

Before editing, the scoped scan found direct `wasm-tools parse` calls in seven
scripts, the `WASM_TOOLS_BIN` override and `1.255.0` guard in scalar leaf, and
all eight scripts passed `bash -n`. This established the migration gap without
changing unrelated gates.

## Verification

- `bash -n <all eight scripts>`: PASS.
- `if rg -n 'wasm-tools|WASM_TOOLS|1\\.255\\.0|[^[:alnum:]_]wasm_tools' <all eight scripts>; then exit 1; else echo 'legacy/direct scan clean'; fi`: PASS, no output except `legacy/direct scan clean`.
- `git diff --check -- <all eight scripts>`: PASS.
- Each script run from the repository root: 8/8 PASS.
- Each script run from unrelated `/tmp` cwd: 8/8 PASS.

Observed runtime markers/results remained successful: async frame table
`27815` with budgets `1/1`, realloc usage `4` with rollback verified and quota
trap, managed struct/text probes `27815`, and scalar-leaf Core output non-empty.

## Residual concerns

This closes only the eight named GC Core-parse gates. Other GC scripts still
contain direct tool calls and are outside this commit. The retained direct
Wasmtime/Zig calls are runtime/probe behavior, not Core parsing, and require a
separate typed operation/runtime migration decision.
