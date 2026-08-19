# G6.2 Bounded Follow-Up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Extend the private G6.2 descriptor-driven async gates by one bounded
parameterized forwarding hop and one bounded nested owned-resource level,
while preserving explicit rejection of the next level and all general shapes.

**Architecture:** Reuse the existing `StreamWriterPlan` and recursive
record-layout/WIT/Core emitters. Raise only the named recursion ceilings, add
private registry descriptors and matching Component/Rust/Wasmtime fixtures, and
keep public ownership syntax, general async-call lowering, and general host
runtime work out of scope.

**Tech Stack:** Zig compiler/tests, Do/WAT/WIT fixtures, pinned
`wasm-tools 1.254.0`, Rust 2024, Wasmtime legacy async runner, shell regression
harness.

## Global Constraints

- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax.
- Do not implement general async-call lowering, arbitrary producer expressions,
  borrowed/list/variant resource fields, or unrestricted producer leases.
- Keep the parameterized producer chain single-path and same-typed at every
  forwarding edge.
- Keep the nested resource record single-child at every container level with a
  canonical `own<ticket>` leaf at Core offset zero.
- Preserve exactly-once resource, stream, and future cleanup in pending, ready,
  and error runtime modes.
- Keep `wasm-tools 1.254.0` and the existing Wasmtime legacy async runner
  unchanged.

---

### Task 1: Refresh the verified baseline and write red tests

**Files:**

- Modify: `doc/start_here.md` baseline counts to match the current verified
  values (`zig test main.zig` 219/219, default 1059/0/3, WASM 1061/0/3).
- Test: `src/build/codegen_component_async_plan.zig`
- Test: `src/build/codegen_component_stream_writer.zig`
- Test: `src/build/p3_async_manifest.zig`

- [x] Record the current focused counts before production changes:

  ```bash
  cd src && zig test build/codegen_component_async_plan.zig
  cd src && zig test build/codegen_component_stream_writer.zig
  cd src && zig test build/p3_async_manifest.zig
  ```

- [x] Add a positive parser test for exactly five parameterized forwarding
  edges and a negative parser test for a sixth edge.

- [x] Add a positive record-layout/registry test for exactly six nested
  container levels and retain a seventh-level rejection test.

- [x] Add emitter assertions for the new accepted shapes before changing the
  ceilings; confirm the positive tests fail with the current bounded errors.

### Task 2: Admit the fifth parameterized forwarding edge

**Files:**

- Modify: `src/build/codegen_component_async_plan.zig`
- Modify: `src/build/codegen_component_stream_writer.zig`
- Create: `examples/p3-runtime/stream-probe-guest-producer-parameterized-five-hop.do`
- Create: `examples/p3-runtime/wit/stream-probe-guest-producer-parameterized-five-hop.wit`
- Create: `examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_five_hop.sh`
- Create: `examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_five_hop.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/stream_probe_guest_producer_dynamic.rs`
  variant dispatch only

- [x] Change only `max_parameterized_forwarding_hops` from `4` to `5`.

- [x] Mirror the four-hop fixture with one additional private helper. The
  chain must be:

  ```text
  produce -> outer_stream -> entry_stream -> forward_stream -> middle_stream
  -> inner_stream -> finish_stream
  ```

  Each helper transfers `(writer, count, value)` unchanged and awaits exactly
  one same-typed helper result; only `finish_stream` writes, closes, and calls
  the registered sink.

- [x] Assert that Component lowering exports only `produce`, retains frame
  offsets 52/60, and emits no helper exports.

- [x] Run both new gates with `count=0/1/3`, `value=90`, pending/ready/
  `Err(pipe)`, one host callback, one stream drop, and an empty resource table.

- [x] Confirm a sixth forwarding edge, reordered arguments, literal arguments,
  and arbitrary async calls remain rejected.

### Task 3: Admit the sixth nested owned-resource level

**Files:**

- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/codegen_component_record_stream.zig`
- Modify: `src/build/p3_async_registry.json`
- Create: `examples/p3-runtime/record-resource-stream-nested-six-level-probe-component.do`
- Create: `examples/p3-runtime/wit/record-resource-stream-nested-six-level-probe.wit`
- Create: `examples/p3-runtime/test_do_record_resource_stream_nested_six_level_probe_lowering.sh`
- Create: `examples/p3-runtime/test_rust_record_resource_stream_nested_six_level_probe.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/record_resource_stream_probe.rs`
  variant dispatch only

- [x] Change only `max_nested_container_depth` from `5` to `6`.

- [x] Add private descriptor
  `do:record-resource-stream-nested-six-level@0.1.0` with the exact path
  `inner -> deep -> deeper -> deepest -> ultra -> hyper -> own<ticket>`.

- [x] Reuse descriptor-driven recursive WIT declaration, Core decode/release,
  canonical ticket slot offset zero, and one deduplicated resource drop import.

- [x] Assert Component lowering and Rust/Wasmtime pending/ready/error behavior:
  entries `[111,222]`, two resource creates/drops, one stream drop, one future
  drop, and `table-empty=true`.

- [x] Confirm a seventh level, multiple children, mixed scalar/nested fields,
  borrow/list/variant fields, and resource escape remain rejected.

### Task 4: Feasibility gates for borrowed resources and general producer leases

**Files:**

- Modify: `doc/pending_blocked.md`, `doc/host_abi_blockers.md`
- Verify: pinned WIT/component embed behavior and existing negative fixtures

- [x] Run the pinned validator against a `borrow<ticket>` stream record and
  record the exact rejection. Do not add a public `borrow<T>` syntax workaround.

- [x] Keep general producer lease, arbitrary producer expression, and broader
  resource shapes blocked until a separate design specifies ownership state,
  async call lowering, cancellation, and terminal cleanup invariants.

- [x] Treat D2 real host smoke as a separate blocked track until a pinned P3
  WIT revision and host linker/runtime entry points are available.

### Task 5: Documentation and complete verification

**Files:**

- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `doc/master_plan.md`
- Modify: `doc/async-design.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: this plan file

- [x] Record fifth-hop and sixth-level accepted boundaries and retain sixth-hop
  and seventh-level/general-shape rejection statements.

- [x] Run focused Zig tests, both new Component/Rust gates, the default
  regression, `RUN_WASM=1` regression, ReleaseSmall smoke, targeted Rustfmt,
  shell syntax checks, JSON/WIT parsing, and `git diff --check`.

- [x] Update the verified counts only from fresh command output. Preserve all
  unrelated dirty worktree changes; do not reset, clean, commit, or push.

## Explicitly Deferred

- General `own<T>` / `borrow<T>` / `ref<T>` source syntax.
- General async function-call lowering and unrestricted resumable composition.
- Borrowed/list/variant resource lowering after the pinned validator rejects
  the current borrowed stream shape.
- D1 full ownership IR, D2 real host I/O, D3 JSON expansion, D4/D5 LSP/fmt
  expansion, D6 direct wasm binary emission, and D8 package management.
