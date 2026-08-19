# Host Export Field ABI Record Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make host-export WAT signatures and manifests consume one concrete field-ABI record sequence, including nested generic unmanaged structs.

**Architecture:** Add a leaf-domain collector that resolves a parameter into named flat ABI fields. It binds concrete generic struct arguments, recursively expands unmanaged structs, tuples, and union payloads, and keeps managed concrete layouts as one `i32` handle. The host manifest and host-export function emitter both consume the collector; no source references, pointer syntax, or JS ownership semantics are introduced.

**Tech Stack:** Zig compiler, Core Wasm WAT emission, host-export manifest, existing generic binding and union-layout collectors.

## Global Constraints

- WAT and manifest must consume the same ordered `AbiParam` record sequence.
- Concrete generic struct fields use `bind_struct_type_args` and existing type substitution helpers.
- Generic templates, unresolved bindings, callbacks, and invalid field shapes fail closed.
- Managed concrete structs remain one `i32` ABI handle.
- Existing tuple, Result/union, value-enum, and callback behavior must remain unchanged.
- Keep ownership of generated names and union layout allocations explicit and exactly-once.

---

### Task 1: Red Nested Generic Fixture

**Files:**
- Create: `src/build/test/compile_ok/342_host_export_nested_generic_struct.do`
- Create: `src/build/test/compile_ok/342_host_export_nested_generic_struct.host_export.expect`
- Create: `src/build/test/compile_ok/342_host_export_nested_generic_struct.host_manifest.expect`

- [x] **Step 1: Add the nested concrete shape and desired flat ABI.**

The fixture declares `Box<T> { value Pair<T> }` and exports
`accept(box Box<i32>)`. Expectations require `box.value.left` and
`box.value.right`, both `i32`, in that order in WAT and manifest.

- [x] **Step 2: Run the fixture against the current implementation.**

Run:

```bash
DO_LIB_ROOT=lib ./bin/do build src/build/test/compile_ok/342_host_export_nested_generic_struct.do --host-export --host-manifest /tmp/342.host.json -o /tmp/342.wat
```

Expected red evidence: WAT contains only `(param $box.value i32)` while the
manifest already reports two `i32` values.

### Task 2: Add The Shared Collector

**Files:**
- Create: `src/build/codegen_host_abi_fields.zig`
- Modify: `src/build/host_export_abi.zig`
- Modify: `src/build/host_export_manifest.zig`
- Modify: `src/build/codegen_emit_expression.zig`

- [x] **Step 1: Define the owned record list and failing unit assertion.**

Expose `AbiParam { name: []const u8, wasm_type: []const u8 }` and an owned list
with `deinit`. Add a unit test that collects `Box<i32>` and asserts the exact
names/types `box.value.left/i32`, `box.value.right/i32`.

- [x] **Step 2: Implement recursive collection.**

Resolve union layouts before tuples and structs. Flatten tuple elements using
`.0`, `.1` names; flatten unmanaged struct fields using public field names;
bind and substitute generic fields before recursion; append union payloads and
the tag with the existing `.__union_payload_N` and `.__union_tag` names. Keep a
managed concrete struct as one scalar handle and reject unresolved generic
bindings with `HostExportGenericStructAbiUnsupported`.

- [x] **Step 3: Replace duplicate consumers.**

Make `host_export_abi.append_param_wasm_types` project `wasm_type` from the
shared records. Make `codegen_emit_expression.emit_user_func` use the same
records for parameter declarations. Preserve callback rejection and existing
error mapping.

- [x] **Step 4: Run the focused red-green checks.**

Run `cd src && zig test build/codegen_host_abi_fields.zig`, then compile the
342 fixture and confirm both WAT and manifest contain the same two fields.

### Task 3: Boundary Matrix And Regression

**Files:**
- Modify: `src/build/codegen_host_abi_fields.zig`
- Modify: `src/build/test/compile_ok/342_host_export_nested_generic_struct.host_export.expect`
- Modify: `doc/host_abi_blockers.md`

- [x] **Step 1: Add managed and union boundary tests.**

Cover a concrete managed field as one `i32` handle and a union field as payload
scalars followed by an `i32` tag. Keep unresolved generic templates rejected.

- [x] **Step 2: Run the full verification.**

Run `cd src && zig test main.zig`, `cd src && zig build -Doptimize=ReleaseSmall`,
`./src/build/test/run_tests.sh`, and `git diff --check`.
