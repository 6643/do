# G5c C16-A Real Host Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the private GC/WIT managed-text lower route validate a real source-level `@host_func` declaration before emitting the pinned C15-D Component module.

**Architecture:** Add a small token-level admission validator for the one private C16-A descriptor. `run.zig` passes the already loaded entry tokens to the explicit `--gc-wit-marshal` adapter; the adapter validates the declaration and then reuses the existing manifest-backed C15-D emitter. The ordinary `@host_func` compiler path remains ARC-backed.

**Tech Stack:** Zig compiler, checked-in WIT descriptor manifest, `.do` compile fixtures, `wasm-tools 1.255.0`, Rust/Wasmtime host runners, shell gates.

**Spec:** `doc/superpowers/specs/2026-08-21-g5c-c16a-real-host-boundary-design.md`

**Execution note:** The implementation and verification are being performed in
the existing dirty `main` checkout. Commits and pushes remain deferred until
the user explicitly requests delivery.

## Global Constraints

- The only C16-A descriptor is `demo:marshal-record-managed-lower-multi/api.write@1.0.0/lower`.
- The admitted source declaration is synchronous `@host_func`, locator `demo:marshal-record-managed-lower-multi/api@1.0.0`, member `write`, one `Writing` parameter, and `nil` result.
- `Writing` must have exactly `code: u32`, `label: text`, and `note: text` in declaration order.
- The canonical lower import remains `(i32, i32, i32, i32, i32)` with no GC reference crossing the boundary.
- Unknown, mismatched, duplicate, asynchronous, or unsupported declarations fail before WAT is returned and never fall back to ARC.
- The C15-B descriptor remains supported by its existing private path; C16-A validation is required only for the C15-D promotion descriptor.
- Default `@host`, async/resource lowering, general aggregate lowering, public ownership syntax, and G5c cutover remain unchanged.
- Use the checked-in `wasm-tools 1.255.0 (76e20611d 2026-07-30)` only; do not add compatibility branches.
- Preserve unrelated dirty changes and do not push during this implementation unit.

---

### Task 1: Add the positive C16-A source fixture

**Files:**
- Create: `src/build/test/compile_ok/564_gc_wit_managed_record_host_boundary.do`

**Produces:** A valid `.do` source containing `Writing`, the exact synchronous `@host_func`, and `start() {}` for compiler and shell gates.

- [x] Add:

```do
write = @host_func("demo:marshal-record-managed-lower-multi/api@1.0.0", "write", (Writing) -> nil)

Writing {
    code u32
    label text
    note text
}

start() {}
```

- [x] Run the compiler and normal compile checks; the fixture parses and the ordinary route accepts it.
- [x] Record the fixture-only commit subject `Add C16-A host boundary fixture`; the commit itself is deferred by the execution note.

### Task 2: Lock the declaration validator with red tests

**Files:**
- Create: `src/build/codegen_gc_wit_host_boundary.zig`
- Modify: `src/main.zig` to import the unit-test module

**Interfaces:**
- `pub const managed_record_lower_multi_descriptor: []const u8`
- `pub fn validate(tokens: []const lexer.Token, descriptor_id: []const u8) !void`

- [x] Add inline-token tests for positive declaration, unknown descriptor, missing host, `@host_async_func`, locator mismatch, member mismatch, non-`nil` result, wrong arity, non-record parameter, reordered field, wrong field type, duplicate target declaration, and unrelated extra host declaration.
- [x] Run the focused filter; every validator negative case returns before WAT generation.
- [x] Implement top-level brace-depth scanning, exact host-call token parsing, and the fixed record-field check without general Do-to-WIT inference.
- [x] Record the validator commit subject `Validate C16-A real host declarations`; the commit itself is deferred by the execution note.

### Task 3: Connect validation to the explicit compiler adapter

**Files:**
- Modify: `src/build/codegen_gc_wit_marshal.zig`
- Modify: `src/build/run.zig`

**Interfaces:**
- `emit_module(io, allocator, repository_root, descriptor_id, entry_tokens) ![]u8`
- `run` passes `loaded.tokens` only in the `gc_wit_marshal_descriptor` branch.
- The validator runs for the C15-D descriptor; C15-B keeps its existing private behavior.

- [x] Add and run the dispatch rejection test proving C15-D rejects the generic `01_start_entry_valid.do` input.
- [x] Thread entry tokens through `run.zig` and call the validator before `emit_sync_marshal_module_from_manifest_with_options`.
- [x] Keep `compile_program_wat` and all ordinary CLI paths unchanged.
- [x] Run `cd src && zig test main.zig`; the positive fixture emits and the generic input returns an error without WAT.
- [x] Record the adapter wiring commit subject `Wire C16-A host validation into GC marshal route`; the commit itself is deferred by the execution note.

### Task 4: Add compiler-generated Component ABI and host gates

**Files:**
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_host.sh`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_equivalence.sh`
- Modify: `src/build/test/check_gc_migration_inventory.sh` only if the inventory contract changes; current rows remain pending

**Interfaces:**
- Both scripts invoke `./bin/do build` with fixture `564_gc_wit_managed_record_host_boundary.do` and descriptor `demo:marshal-record-managed-lower-multi/api.write@1.0.0/lower`.
- Host output contains `code=7 label=hello note=world write-calls=1 allocations=2 frees=2`.
- Equivalence output contains `allocations=2/2 frees=2/2 write-calls=1/1`.

- [x] Build Debug, generate/parse WAT, assert the five-`i32` type, no `(ref` canonical import, two byte-copy paths, four `cabi_realloc` calls, and call-before-free ordering.
- [x] Embed the checked-in C15-D WIT, run `component new`, `validate`, `component wit`, and the existing Rust host runner.
- [x] Assemble compiler-generated GC and checked-in ARC modules and invoke the existing Rust equivalence runner.
- [x] Run both with the pinned `wasm-tools 1.255.0`; inventory rows correctly remain pending for general capability/cutover.

### Task 5: Add fail-closed and default-route regression gates

**Files:**
- Create: `src/build/test/compile_err/575_gc_wit_managed_record_host_boundary_async.do`
- Create: `src/build/test/compile_err/575_gc_wit_managed_record_host_boundary_async.expect`
- Create: `src/build/test/compile_err/576_gc_wit_managed_record_host_boundary_mismatch.do`
- Create: `src/build/test/compile_err/576_gc_wit_managed_record_host_boundary_mismatch.expect`
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_boundary_negative.sh`

- [x] Invoke the explicit descriptor with the async-marker and mismatched-locator fixtures; require non-zero exit and no output WAT. The async fixture is rejected earlier by the existing frontend as `UnknownP3AsyncHostDescriptor`; the focused adapter test retains `AsyncGcWitHostDeclaration` coverage.
- [x] Build the positive fixture without `--gc-wit-marshal`; the existing ARC helper marker remains and the C16-A canonical import is absent.
- [x] Run existing C15-B/C15-D compiler gates and `bash src/build/test/check_gc_g5c_residual_gate.sh baseline`; preserve their current outcomes.
- [x] Record the gate commit subject `Gate C16-A failures and default route`; the commit itself is deferred by the execution note.

### Task 6: Synchronize documentation and run full verification

**Files:**
- Modify: `doc/start_here.md`, `doc/roadmap_status.md`, `doc/host_abi_blockers.md`, `doc/pending_blocked.md`, `examples/gc-p3-runtime/README.md`, `CHANGELOG.md`
- Modify: this plan to mark completed steps

- [x] Record the fixture, descriptor, validator boundary, five-`i32` ABI, host counters, equivalence counters, and private opt-in status.
- [x] State that default `@host` remains ARC-backed and general aggregate/async/resource/G5c cutover remain pending.
- [x] Run `./src/build/test/run_tests.sh` and record the final result in the handoff.
- [x] Run `cd src && zig build -Doptimize=ReleaseSmall` and `cd src && zig test main.zig`.
- [x] Run `bash src/build/test/check_gc_migration_inventory.sh`; retain expected pending-row exit status.
- [x] Run `git diff --check` and inspect `git status --short`.
- [x] Record the documentation commit subject `Document C16-A host boundary evidence`; the commit itself is deferred by the execution note.

## Completion Evidence

C16-A is closed only when Tasks 1-6 are checked, compiler-generated host and ARC/GC equivalence gates pass, all negative cases fail before WAT emission, the ordinary route remains ARC-backed, and full regression/build/inventory evidence is recorded. This plan does not authorize closing either host/WIT inventory row or switching the default backend.
