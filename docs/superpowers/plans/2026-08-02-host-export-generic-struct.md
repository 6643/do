# Host Export Generic Struct ABI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow host-export manifests to describe concrete generic struct parameters using the same post-monomorphization field expansion as Core WAT emission.

**Architecture:** Resolve a concrete `Box<i32>` type to its declared generic struct, bind type arguments, substitute each field type, and recursively flatten those fields through the existing ABI type collector. Keep generic templates and unresolved type arguments rejected; do not add source references, pointers, or JS ownership semantics.

**Tech Stack:** Zig compiler, host-export Core WAT/manifest, existing generic type binding helpers.

## Global Constraints

- The manifest and WAT must use the same concrete field sequence.
- Generic templates without concrete type arguments remain unsupported.
- Reuse `bind_struct_type_args` and `substitute_generic_type_owned`; do not parse generic type spelling a second way.
- Preserve callback rejection and all existing host-export ABI behavior.
- Verify red/green fixture, `zig test main.zig`, ReleaseSmall, full regression, and `git diff --check`.

---

### Task 1: Add The Red Generic Struct Fixture

**Files:**
- Create: `src/build/test/compile_ok/341_host_export_generic_struct.do`
- Create: `src/build/test/compile_ok/341_host_export_generic_struct.host_export.expect`
- Create: `src/build/test/compile_ok/341_host_export_generic_struct.host_manifest.expect`

- [x] **Step 1: Add a concrete generic struct export.**

```do
#T
Box {
    value T
}

accept(box Box<i32>) -> i32 {
    return 0
}
```

The expectation files require the `accept` WAT export and a manifest with
`"source_params":["Box<i32>"]` and `"wasm_params":["i32"]`.

- [x] **Step 2: Run the fixture and verify the current rejection.**

Run: `DO_LIB_ROOT=lib ./bin/do build src/build/test/compile_ok/341_host_export_generic_struct.do --host-export --host-manifest /tmp/341.host.json -o /tmp/341.wat`

Expected: failure with `HostExportGenericStructAbiUnsupported`.

### Task 2: Share Concrete Generic Field Expansion With Host ABI

**Files:**
- Modify: `src/build/host_export_abi.zig`

- [x] **Step 1: Add a recursive concrete-struct field helper.**

For a type with `generic_type_args_range`, resolve the base declaration, bind its
arguments, substitute each field type, and recursively call the existing type
collector. Return `HostExportGenericStructAbiUnsupported` for missing or invalid
bindings, and preserve the existing non-generic path.

- [x] **Step 2: Verify the focused host ABI unit test and fixture.**

Run: `cd src && zig test main.zig --test-filter 'generic struct'`; then run the
fixture command from Task 1 and inspect that the manifest and WAT both contain
one `i32` parameter.

### Task 3: Regression And Boundary Record

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `docs/superpowers/plans/2026-08-02-host-export-generic-struct.md`

- [x] **Step 1: Record the newly admitted concrete shape.**

Document that concrete generic struct field expansion is now admitted for the
host manifest and matches the current WAT output, while generic templates,
unresolved bindings, canonical JS values, and ownership protocols remain
outside the ABI. A shared field-ABI record is still future work.

- [x] **Step 2: Run all verification.**

Run `cd src && zig test main.zig && zig build -Doptimize=ReleaseSmall`, then
`./src/build/test/run_tests.sh` and `git diff --check`.
