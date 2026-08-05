# Generic Record-Stream Multiple Owned Resource Fields Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admit multiple internal `own` resource fields in a registered record-stream consumer with deduplicated WIT/drop imports and exactly-once cleanup.

**Architecture:** Reuse `RecordSourceField` and the existing frame-owned slot loop. Relax only the single-resource cardinality guard, generate each distinct resource declaration/import once, and exercise two handles per record through a private Component/Rust/Wasmtime probe.

**Tech Stack:** Zig compiler and WAT templates, pinned `wasm-tools 1.254.0`, Rust/Wasmtime `47.0.2`, existing regression scripts.

## Global Constraints

- Do source does not expose `own<T>`, `borrow<T>`, `ref<T>`, pointers, or references.
- Only owned resource fields with one aligned Core `i32` slot are admitted.
- Resource fields may not escape the record body or participate in producer operations.
- Existing scalar/string record streams and the one-resource probe remain green.
- Preserve unrelated dirty-worktree changes; do not commit or push.

### Task 1: Manifest And Emitter Tests

**Files:** `src/build/p3_async_manifest.zig`, `src/build/codegen_component_record_stream.zig`

- [x] Add tests for two owned fields, including duplicate resource identity, and assertions for two frame slots plus one drop import.
- [x] Run focused Zig tests and confirm they fail because the manifest still rejects the second resource field and the registry has no multi-resource descriptor.

### Task 2: Multi-Resource Lowering

**Files:** `src/build/p3_async_manifest.zig`, `src/build/p3_async_registry.json`, `src/build/codegen_component_record_stream.zig`

- [x] Permit multiple validated `.own` source fields while preserving unique names/storage and rejecting `.borrow`.
- [x] Deduplicate resource declarations and `[resource-drop]` imports by resource/drop identity.
- [x] Keep one four-byte frame slot per resource and release every active slot exactly once.
- [x] Run manifest/emitter tests and the existing one-resource probe.

### Task 3: Runtime Probe

**Files:** new private Do/WIT fixtures and Rust runner/script under `examples/p3-runtime/`

- [x] Register a record with `id`, `left`, and `right`, where both resource fields are `own<ticket>`.
- [x] Exercise pending/ready/error completion and assert four resource drops plus empty resource table.
- [x] Run lowering and Rust/Wasmtime gates.

### Task 4: Closure

**Files:** `doc/host_abi_blockers.md`, `doc/pending_blocked.md`, `doc/roadmap_status.md`, `doc/start_here.md`, `README.md`, `CHANGELOG.md`

- [x] Record that multiple owned consumer fields are verified while borrowed/nested/producer shapes remain pending.
- [x] Run full regression, ReleaseSmall smoke, focused probes, and `git diff --check`.
