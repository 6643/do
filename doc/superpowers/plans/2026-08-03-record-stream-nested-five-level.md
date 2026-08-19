# Five-Level Nested Owned Resource Record Stream Implementation Plan

> **For agentic workers:** Execute the steps inline with focused checkpoints. Do not widen public ownership syntax or general async-call lowering.

**Goal:** Admit exactly one five-level nested owned-resource record path and
retain rejection of the sixth level and all unsupported shapes.

**Architecture:** Raise the named manifest recursion ceiling from four to five
and reuse the existing descriptor-driven recursive WIT, Core decode, and
frame-owned release emitters. Add a private registry descriptor plus matching
Do/WIT/Component and Rust/Wasmtime fixtures; no generic resource-shape or async
call lowering is introduced.

**Tech Stack:** Zig compiler, JSON manifest, WAT/WIT Component assembly, Rust
2024, Wasmtime P3 legacy async runtime.

## Global Constraints

- No public `own<T>`, `borrow<T>`, or `ref<T>` syntax.
- Admit one single-child nested path only, with five container levels.
- Keep sixth-level, multi-child, mixed scalar/nested, borrow/list/variant, and
  resource-escape shapes rejected.
- Preserve exactly-once resource, stream, and future cleanup.
- Keep the pinned `wasm-tools 1.254.0` Component toolchain unchanged.

### Task 1: Red tests

**Files:** `src/build/p3_async_manifest.zig`,
`src/build/codegen_component_record_stream.zig`

- [x] Add a five-level parser/registry shape test and a sixth-level rejection
  test.
- [x] Add a five-level emitter WIT/decode/release assertion and run the focused
  tests before production changes; the new acceptance test must fail at the
  current depth ceiling.

### Task 2: Manifest and registry implementation

**Files:** `src/build/p3_async_manifest.zig`, `src/build/p3_async_registry.json`

- [x] Change only `max_nested_container_depth` from `4` to `5`.
- [x] Add `do:record-resource-stream-nested-five-level@0.1.0` with the exact
  `inner -> deep -> deeper -> deepest -> ultra -> own<ticket>` source metadata,
  canonical `ticket` slot at offset zero, and one resource drop import.
- [x] Run the parser and manifest tests, confirming sixth-level and malformed
  child metadata still reject.

### Task 3: Component and runtime fixtures

**Files:** `examples/p3-runtime/record-resource-stream-nested-five-level-probe-component.do`,
`examples/p3-runtime/wit/record-resource-stream-nested-five-level-probe.wit`,
`examples/p3-runtime/test_do_record_resource_stream_nested_five_level_probe_lowering.sh`,
`examples/p3-runtime/test_rust_record_resource_stream_nested_five_level_probe.sh`,
Rust probe runner variant files.

- [x] Mirror the four-level fixture with the additional `ultra-entry` record.
- [x] Assert generated WIT, Core imports/layout, Component validation, and no
  helper export drift.
- [x] Run pending/ready/error modes and require two resource drops, one stream
  drop, one future drop, and `table-empty=true`.

### Task 4: Documentation and full verification

**Files:** `doc/host_abi_blockers.md`, `doc/pending_blocked.md`,
`doc/roadmap_status.md`, `doc/start_here.md`, `README.md`, `CHANGELOG.md`,
`doc/async-design.md`

- [x] Record the accepted five-level boundary and retain sixth-level/general
  resource exclusions.
- [x] Run focused Zig tests, the two Component/Rust gates, default and WASM
  regression, ReleaseSmall smoke, targeted Rustfmt, shell syntax, and diff
  checks.
