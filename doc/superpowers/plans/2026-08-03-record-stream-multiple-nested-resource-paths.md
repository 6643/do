# Multiple Nested Owned Resource Paths Implementation Plan

> **For agentic workers:** Execute this plan inline with focused red/green verification. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Admit multiple bounded nested owned-resource paths in the private generic record-stream consumer.

**Architecture:** Relax only the top-level manifest cardinality from one nested path to multiple all-nested paths. Reuse the existing recursive one-/two-level metadata and emitter helpers, making each leaf consume one frame-owned `i32` slot in source order. Add a separate pinned descriptor and runtime fixture so the existing one-path probes remain unchanged.

**Tech Stack:** Zig compiler and unit tests, JSON async registry, Do/WIT Component fixture, pinned `wasm-tools 1.254.0`, Rust Wasmtime 47.0.2 runner.

## Global Constraints

- Do not add public `own<T>`, `borrow<T>`, or `ref<T>` syntax.
- Keep one child per nested container and one final `own<ticket>` leaf per path.
- Reject third-level paths, multiple children, mixed top-level scalar/nested fields, borrow/list/variant fields, and resource escape.
- Preserve frame-owned exactly-once cleanup and deduplicated resource/drop imports.
- Preserve the existing one-level and two-level single-path descriptors and fixtures.
- Do not commit, push, reset, clean, or revert unrelated dirty worktree changes.

### Task 1: Manifest and emitter red tests

**Files:**
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/codegen_component_record_stream.zig`

- [x] Add a two-path manifest JSON test with `left-ticket` at offset 0 and
  `right-ticket` at offset 4; assert both nested paths and final resources.
- [x] Add an invalid mixed top-level scalar/nested shape and a multi-child
  nested container to the rejection table.
- [x] Add an emitter test for two nested paths using the new descriptor name;
  assert two field/release markers, offsets 0 and 4, one WIT `resource ticket`,
  and `left`/`right` nested records.
- [x] Run focused tests and confirm they fail because the registry is absent or
  current top-level cardinality rejects the shape.

### Task 2: Recursive multi-path manifest validation

**Files:**
- Modify: `src/build/p3_async_manifest.zig:779-820,1000-1070`

- [x] Permit `nested_count == source_fields.len` when any nested path exists;
  retain rejection of mixed scalar/nested top-level fields.
- [x] Replace direct `nested.storage[0]` collision checks with a recursive
  collector that validates every leaf storage name without indexing empty
  intermediate containers.
- [x] Keep `valid_nested_resource_fields_for_parse` and depth limits unchanged;
  run manifest unit tests before touching the emitter.

### Task 3: Multi-path emitter lowering

**Files:**
- Modify: `src/build/codegen_component_record_stream.zig:205-540`

- [x] Iterate every top-level nested path in marker and decode emitters.
- [x] Iterate every path in release generation, advancing the owned cursor per
  leaf and clearing each handle exactly once.
- [x] Retain deepest-first nested WIT declarations and resource/drop dedup;
  assert both leaf offsets and one shared drop import.
- [x] Run the complete `codegen_component_record_stream.zig` test suite.

### Task 4: Registry and Component/Rust/Wasmtime fixture

**Files:**
- Modify: `src/build/p3_async_registry.json`
- Create: `examples/p3-runtime/record-resource-stream-multiple-nested-probe-component.do`
- Create: `examples/p3-runtime/wit/record-resource-stream-multiple-nested-probe.wit`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/record_resource_stream_probe.rs`
- Create: `examples/p3-runtime/test_do_record_resource_stream_multiple_nested_probe_lowering.sh`
- Create: `examples/p3-runtime/test_rust_record_resource_stream_multiple_nested_probe.sh`

- [x] Register a private descriptor with two nested paths and Core fields
  `left-ticket`/`right-ticket` at offsets 0/4.
- [x] Add the Do/WIT sidecar and compare generated WIT byte-for-byte.
- [x] Add a Rust producer that creates two tickets per entry and binds both
  nested paths to the same `ticket` resource destructor.
- [x] Run pending/ready/error Component probes and require four resource drops,
  one stream drop, one future drop, and an empty table.

### Task 5: Documentation and verification

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/start_here.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/master_plan.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [x] Record the accepted multiple-path boundary and remaining exclusions.
- [x] Run focused Zig tests, both new Component/Rust scripts, `zig test main.zig`,
  default and `RUN_WASM=1` regression, ReleaseSmall smoke, formatting, shell
  syntax, JSON validation, and `git diff --check`.
