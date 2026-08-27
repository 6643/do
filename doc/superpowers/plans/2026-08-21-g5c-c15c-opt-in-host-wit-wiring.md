# G5c C15-C Opt-In Host/WIT Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Keep each checkbox tied to a testable change.

**Goal:** Connect the already verified C15-B fixed `{u32, string}` lower route to the real `do build` entry point behind an explicit, fail-closed opt-in without changing default `@host` behavior.

**Architecture:** `cli.Args` carries one optional descriptor id. `run.zig` dispatches that option to a small GC/WIT adapter which owns the pinned descriptor, measured `{code:u32,label:string}` layout, and the existing manifest-backed route. The normal `codegen.emit_wat_with_options` path is unchanged; no implicit descriptor inference or fallback to ARC is added.

**Tech Stack:** Zig compiler sources and tests, checked-in WIT descriptor manifest, WAT, `wasm-tools 1.255.0`, Rust/Wasmtime host runners, shell regression gates.

**Spec:** `doc/superpowers/specs/2026-08-20-g5c-managed-field-record-lower-design.md` and `doc/superpowers/specs/2026-08-20-g5c-wit-descriptor-manifest.md`.

## Global Constraints

- The only admitted descriptor in this slice is `demo:marshal-record-managed-lower/api.write@1.0.0/lower`.
- The canonical lower import remains `(i32, i32, i32)` in the order `code`, `label.ptr`, `label.len`.
- The generated sequence remains `cabi_realloc -> byte copy -> host call -> cabi_realloc free`.
- Unknown ids, source/hash/WIT/layout drift, and unsupported shapes fail before WAT is emitted.
- Default `@host`, ARC-backed host/WIT lowering, async/resource lowering, and G5c full cutover remain unchanged.
- Do not add `own<T>`, `borrow<T>`, `ref<T>`, Option/Result syntax, or compatibility branches for older wasm-tools.
- Work remains on the current `main` checkout; preserve unrelated dirty changes and do not push in this phase.

### Task 1: CLI descriptor option and conflict contract

**Files:**
- Modify: `src/build/cli.zig` (`Args`, `parse_build`, parser tests)
- Test: `src/build/cli.zig` unit tests

**Interfaces:**
- Produces `Args.gc_wit_marshal_descriptor: ?[]const u8`.
- Accepts `--gc-wit-marshal <descriptor-id>` exactly once.
- Uses `MissingGcWitMarshalDescriptor` for a missing value and `DuplicateGcWitMarshal` for a second occurrence.
- Treats this option as a special target and rejects it with `--component-core`, `--host-export`, `--gc-core`, every `--p3-*` target, `--p3-wit-output`, and `--p3-wit-package-output`.

- [x] Add failing tests named `parse_build accepts the explicit GC WIT marshal descriptor`, `parse_build rejects a missing GC WIT marshal descriptor`, `parse_build rejects duplicate GC WIT marshal descriptors`, and `parse_build rejects GC WIT marshal target combinations`.
- [x] Run `cd src && zig test build/cli.zig`; the new tests failed because the field and flag did not exist.
- [x] Add the field, parse branch, error cases, special-target count, conflict checks, and returned field with the exact descriptor string preserved.
- [x] Run `cd src && zig test build/cli.zig`; all 43 CLI tests passed.

### Task 2: Build dispatch for the explicit route

**Files:**
- Create: `src/build/codegen_gc_wit_marshal.zig`
- Modify: `src/build/run.zig` (`run`, `compile_program_wat`, `compile_program_wat_parts` or a dedicated dispatch helper)
- Test: `src/build/codegen_gc_wit_marshal.zig` and `src/build/run.zig` unit tests

**Interfaces:**
- `codegen_gc_wit_marshal.emit_module(io, allocator, repository_root, descriptor_id) ![]u8` calls `codegen_component_manifest_route.emit_sync_marshal_module_from_manifest_with_options` with `doc/wit/gc_descriptor_manifest.json`, the pinned descriptor, the C15-B measured layout, `canonical_u64_arg = null`, and `emit_realloc_counters = true`.
- `run` selects this emitter only when `parsed_cli.gc_wit_marshal_descriptor` is non-null; otherwise it calls the existing `compile_program_wat` path with the same arguments as before.
- The adapter appends the existing C15-B `run` export that constructs `{code: 7, label: "hello"}` and calls `$marshal`, so the CLI output is executable by the existing host gate.

- [x] Add a unit test that `emit_module` emits the pinned module marker, `(type $canonical_lower (func (param i32 i32 i32)))`, and `(export "run" (func $run))`.
- [x] Add a dispatch test proving the manifest adapter is selected when the option is present; the null option retains the existing `compile_program_wat` call site.
- [x] Run the focused test first and observe the expected missing-symbol failure before implementation.
- [x] Implement the adapter by reusing the existing manifest route; do not call the probe `main` from compiler dispatch.
- [x] Thread the optional descriptor through `run.zig`, preserving normal output and error handling.
- [x] Build the compiler and run `cd src && zig test main.zig`; all 560 tests passed. Direct single-file adapter testing remains invalid because its existing `../wit` imports are outside that root module.

### Task 3: Admission and fail-closed descriptor checks

**Files:**
- Modify: `src/build/codegen_gc_wit_marshal.zig` only if adapter-level id admission is needed
- Test: `src/build/codegen_component_manifest_route_test.zig`, adapter tests
- Data: `doc/wit/gc_descriptor_manifest.json` and the existing C15-B WIT source files remain the source of truth

**Interfaces:**
- The adapter accepts only `demo:marshal-record-managed-lower/api.write@1.0.0/lower`; any other id returns the manifest loader's named error before output allocation is returned.
- Existing loader validation remains authoritative for repository-relative paths, source SHA-256, package/world/interface/member/direction/signature, canonical import, and measured layout.

- [x] Add negative tests for an unknown id, a child-count/layout drift, and an unsupported descriptor id; each returns an error and no WAT slice. The adapter covers unknown/unsupported ids, and existing manifest-route tests cover measured child-count drift.
- [x] Run the negative tests and confirm the CLI unknown-id path fails before output emission.
- [x] Implement only the exact-id admission needed by this one target; route all source/hash/WIT/layout checks through the existing loader.
- [x] Run the repository manifest-route tests; the full `main.zig` suite passed 560/560 without default-route changes.

### Task 4: Generated WAT and wasm-tools gate

**Files:**
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_compiler_host.sh`
- Test: generated WAT and checked-in expected fragments

**Interfaces:**
- The command under test is `tmp_wat="$(mktemp)" && ./bin/do build src/build/test/compile_ok/01_start_entry_valid.do --gc-wit-marshal demo:marshal-record-managed-lower/api.write@1.0.0/lower -o "$tmp_wat"`.
- The output must contain the versioned import, canonical `(i32 i32 i32)`, no `(ref` in the canonical import type, one `$cabi_realloc` allocation and one post-call free, and the `run` export.

- [x] Add `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_compiler_host.sh` and run it against the compiler opt-in path.
- [x] Build the compiler in that gate with `zig build -Doptimize=Debug`; the release build remains in Task 6.
- [x] Run `tmp_wat="$(mktemp)" && ./bin/do build src/build/test/compile_ok/01_start_entry_valid.do --gc-wit-marshal demo:marshal-record-managed-lower/api.write@1.0.0/lower -o "$tmp_wat"` and inspect it with `wasm-tools 1.255.0` parse/embed/new/validate/component wit.
- [x] Assert the exact import signature and allocation/copy/call/free order; reject any GC reference crossing the import. Host output was `code=7 label=hello write-calls=1 allocations=1 frees=1`.

### Task 5: Real host and ARC/GC equivalence gate

**Files:**
- Create: `examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_compiler_equivalence.sh`
- Reuse: `examples/p3-runtime/rust-host-runner/src/bin/gc_marshal_record_managed_lower_host_equivalence.rs`

**Interfaces:**
- The gate starts with `do build`, not the direct Zig probe emitter.
- Host observations remain `code=7`, `label=hello`, `write-calls=1`, `allocations=1`, `frees=1`.
- The ARC/GC comparison remains `allocations=1/1`, `frees=1/1`, `write-calls=1/1`.

- [x] Add and run the compiler-output equivalence invocation after the dispatch was implemented.
- [x] Generate the GC Core WAT with `do build --gc-wit-marshal` and assemble it beside the checked-in ARC Core WAT.
- [x] Feed both Components to the existing Rust/Wasmtime equivalence runner without changing host ABI expectations.
- [x] Run both compiler-output host and equivalence gates; equivalence reported `allocations=1/1`, `frees=1/1`, and `write-calls=1/1`.

### Task 6: Documentation and full verification

**Files:**
- Modify: `doc/roadmap_status.md`, `doc/start_here.md`, `doc/host_abi_blockers.md`, `doc/pending_blocked.md`, `examples/gc-p3-runtime/README.md`, `CHANGELOG.md`
- Modify: the plan file checkbox state

**Interfaces:**
- Documentation states that `--gc-wit-marshal` is private and explicit, supports one descriptor, and does not change default `@host` or close G5c.
- The migration inventory remains pending for general managed record lowering/default host/WIT routing.

- [x] Update each document with the exact command and admitted descriptor after the runtime gate is green.
- [x] Run `cd src && zig test main.zig`.
- [x] Run `./src/build/test/run_tests.sh`.
- [x] Run `cd src && zig build -Doptimize=ReleaseSmall`.
- [x] Run `cargo fmt --check --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml`.
- [x] Run `git diff --check` and the existing migration/residual gates; retain any expected pending exit status instead of weakening the gate.
- [x] Review `git diff --stat` and `git status --short` to ensure only this phase's files were intentionally touched.

## Phase Gate

C15-C is complete only when every task above is checked, the real `do build` output passes the host and equivalence gates, all default-path regressions are green, and the documentation accurately records the private opt-in boundary. A direct probe-only pass is insufficient evidence.
