# Nested Owned Resource Record-Stream Implementation Plan

> **For agentic workers:** Execute this plan inline with focused red/green verification. Steps use checkbox syntax.

**Goal:** Add one private one-level nested record field containing one owned resource to the generic record-stream consumer.

**Architecture:** Extend manifest metadata with a bounded `nested_fields` list, validate exactly one nested owned `i32` resource child, and recurse only through that one shape in WIT generation, decode, and release. Reuse the existing frame cleanup and descriptor-specific runtime harness.

**Global constraints:** No public `own<T>`, `borrow<T>`, or `ref<T>` syntax; no arbitrary nested records, lists, variants, borrowed fields, resource escape, producer changes, or general async lowering.

## Task 1: Red manifest and emitter tests

- [x] Add a manifest JSON fixture for `resource-entry.inner.ticket` and assert the nested metadata shape.
- [x] Add a record-stream emitter fixture asserting nested WIT and a nested resource-drop marker; verify the pre-implementation failure and the green implementation.

## Task 2: Implement bounded nested metadata

- [x] Add `RecordNestedField` metadata with explicit storage, ownership, resource, and drop import facts.
- [x] Parse and free `nested_fields`; accept only one parent nested field with exactly one owned resource child, aligned Core `i32` storage, and no parent storage slot.
- [x] Register `do:record-resource-stream-nested@0.1.0` with the canonical nested Core record layout and nested source metadata.

## Task 3: Implement nested lowering

- [x] Generate the private nested WIT record and outer record field.
- [x] Reserve one frame-owned slot, load the nested handle, emit nested field markers, and release/clear the handle exactly once.
- [x] Add the private Do fixture and WIT sidecar comparison.

## Task 4: Verify runtime and docs

- [x] Add pending/ready/error Rust/Wasmtime assertions for nested records, one drop per record, and an empty resource table.
- [x] Run focused Zig tests, Component lowering, Rust runtime, full regression, `RUN_WASM=1`, ReleaseSmall smoke, formatting, shell syntax, and `git diff --check`.
- [x] Update `doc/pending_blocked.md`, `doc/host_abi_blockers.md`, `doc/start_here.md`, `doc/roadmap_status.md`, and `CHANGELOG.md` with the exact accepted boundary and the pinned borrowed-type rejection evidence.

## Bounded Two-Level Extension (2026-08-03)

The accepted follow-up extends the same plan by one private descriptor,
`do:record-resource-stream-nested-two-level@0.1.0`, with exactly one path:
`ResourceEntry -> InnerEntry -> DeepEntry -> own<ticket>`. Intermediate
containers have no storage or ownership metadata; the leaf remains one aligned
Core `i32` slot and is released exactly once from the existing frame cleanup.

The recursive manifest parser, WIT declaration emitter, decode marker/body,
drop-import collection, and release helper are covered by focused Zig tests.
`test_do_record_resource_stream_nested_two_level_probe_lowering.sh` and
`test_rust_record_resource_stream_nested_two_level_probe.sh` cover Component
assembly plus pending/ready/error Wasmtime execution. A third level, multiple
paths, borrowed/list/variant fields, and resource escape remain outside scope.
