# Generic Record-Stream Owned Resource Field Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one validated, executable `own<ticket>` field to a generic record-stream consumer while preserving Do's ownership-free public syntax and exactly-once cleanup.

**Architecture:** Extend the async manifest's record source-field metadata with explicit ownership, resource identity, and drop import facts. The existing descriptor-driven record-stream emitter will lift one owned `i32` resource representation into a frame slot, emit the private WIT resource/drop import, and clear/drop the slot after the admitted entry is discarded. A private Rust/Wasmtime probe supplies two resource-bearing records and checks the resource table after pending, ready, and error completion paths.

**Tech Stack:** Zig compiler and WAT templates, pinned `wasm-tools 1.254.0`, Rust/Wasmtime `47.0.2`, existing `do` regression harness.

## Global Constraints

- Do source does not expose `own<T>`, `borrow<T>`, `ref<T>`, pointers, or references.
- Only one registered record descriptor is admitted: `do:record-resource-stream-probe@0.1.0/source.read-via-stream`.
- The record has exactly one resource field, `ticket: own<ticket>`, backed by one aligned `i32` slot.
- The admitted source discards each record after decode; resource fields may not escape, be copied, or be passed to another operation.
- Drop import identity is explicit metadata and must be `[resource-drop]ticket`; no drop-name inference from arbitrary source text is allowed.
- Existing scalar/text record streams, fixed read-directory lowering, resource probes, and ordinary async rejection behavior remain unchanged.
- Preserve the dirty worktree; do not reset, clean, stage, commit, or modify unrelated files.

---

### Task 1: Add Explicit Resource Metadata To The Async Manifest

**Files:**
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/p3_async_registry.json`
- Test: `src/build/p3_async_manifest.zig`

**Interfaces:**
- `RecordSourceField` gains `ownership: RecordOwnership`, `resource: ?[]const u8`, and `drop_import: ?[]const u8`.
- Existing scalar/text entries default to `.none` with null resource/drop fields.
- A resource field is valid only when `ownership == .own`, `resource` is non-empty, `drop_import` is `[resource-drop]` plus the resource name, storage has one slot, and that slot is aligned Core `i32`.

- [x] **Step 1: Add failing metadata tests.**

Add manifest JSON fixtures in the existing in-memory test helper and assert that
this source field parses as an owned resource:

```json
{
  "name": "ticket",
  "source_type": "ticket",
  "storage": ["ticket"],
  "ownership": "own",
  "resource": "ticket",
  "drop_import": "[resource-drop]ticket"
}
```

Add rejection cases for `borrow`, a missing `drop_import`, a non-`i32` slot,
an unaligned slot, a second resource field, and a duplicate storage name.
Run:

```bash
cd src && zig test build/p3_async_manifest.zig --test-filter 'generic record resource metadata'
```

Expected: the new tests fail because ownership/resource metadata is not parsed.

- [x] **Step 2: Implement owned metadata parsing and validation.**

Add a private `RecordOwnership` enum and parse the optional JSON ownership,
resource, and drop-import values. Keep old scalar/text JSON valid by defaulting
omitted ownership to `.none`. Free every duplicated optional string in
`RecordLayout` teardown. Extend `valid_record_stream_layout` with a guarded
resource-field validator that rejects all resource shapes except the exact
single owned `i32` field admitted by this plan.

- [x] **Step 3: Add the private resource-stream registry descriptor.**

Register `do:record-resource-stream-probe@0.1.0` with the same canonical
stream/future operation shapes as the existing record probe, but set its record
layout to:

```json
{
  "name": "resource-entry",
  "byte_size": 8,
  "fields": [
    {"name":"id", "core_type":"i32", "offset":0},
    {"name":"ticket", "core_type":"i32", "offset":4}
  ],
  "source_fields": [
    {"name":"id", "source_type":"u32", "storage":["id"]},
    {"name":"ticket", "source_type":"ticket", "storage":["ticket"], "ownership":"own", "resource":"ticket", "drop_import":"[resource-drop]ticket"}
  ]
}
```

Use a distinct package/interface/world name so the existing probe remains an
independent regression.

- [x] **Step 4: Run manifest tests green.**

Run:

```bash
cd src && zig test build/p3_async_manifest.zig
```

Expected: all existing tests plus the resource metadata and descriptor tests
pass.

### Task 2: Emit Resource-Field WIT And Exactly-Once Drop

**Files:**
- Modify: `src/build/codegen_component_record_stream.zig`
- Test: `src/build/codegen_component_record_stream.zig`

**Interfaces:**
- `record_owned_size` reserves four bytes for an owned resource field.
- `build_record_decode_body` stores the validated handle into the frame-owned
  slot and emits `[record-resource-field-ticket]`.
- The generated module imports `[resource-drop]ticket` and exposes an internal
  `$release-record` helper that clears the slot before calling the drop import.

- [x] **Step 1: Add red emitter assertions.**

Add a source fixture using the new descriptor and assert that generated WAT/WIT
contains:

```text
resource ticket {}
ticket: own<ticket>
import "[resource-drop]ticket"
[record-resource-field-ticket]
call $release-record
```

Also assert that a borrowed resource field and a source that keeps the entry
after the loop are rejected with `UnsupportedP3RecordStreamComponent`.

- [x] **Step 2: Implement resource-aware WIT generation.**

Generate the resource and resource-bearing record once in the private source
interface, keep the error enum in `interface types`, and map the resource
source field to `own<ticket>` while retaining scalar/text mappings. Keep all
generated WIT ownership qualifiers internal to the sidecar.

- [x] **Step 3: Implement frame decode and idempotent release.**

Extend the generated replacement set with the descriptor's resource drop
imports. For each admitted resource field, load the record-area `i32` into its
frame-owned slot. Emit `$release-record` with this order:

```wat
local.get $frame
i32.const <slot-offset>
i32.add
i32.load
local.tee $handle
i32.eqz
if
else
  local.get $handle
  call $resource-drop-ticket
  local.get $frame
  i32.const <slot-offset>
  i32.add
  i32.const 0
  i32.store
end
```

Call `$release-record` immediately after the admitted `_ = entry` decode and
again from terminal cleanup as a harmless idempotent fallback. Do not release
stream or completion handles from this helper.

- [x] **Step 4: Run focused emitter tests and preserve old probes.**

Run:

```bash
cd src && zig test build/codegen_component_record_stream.zig
```

Expected: all record-stream unit tests pass, including the old scalar/text
probe markers and the new resource drop marker.

### Task 3: Add The Private Do/WIT Resource Probe

**Files:**
- Create: `examples/p3-runtime/record-resource-stream-probe-component.do`
- Create: `examples/p3-runtime/wit/record-resource-stream-probe.wit`
- Create: `examples/p3-runtime/test_do_record_resource_stream_probe_lowering.sh`

**Interfaces:**
- The Do fixture uses `Ticket = @wasi_resource(...)` and a `ResourceEntry`
  record with `id u32` and `ticket Ticket`.
- The static WIT sidecar must match compiler output byte-for-byte.

- [x] **Step 1: Add the source and sidecar fixtures.**

Use this source shape:

```do
probe_read = @host_func("do:record-resource-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>>)
Ticket = @wasi_resource("do:record-resource-stream-probe/ledger/ticket", { .id i64 })

ResourceEntry {
    .id u32
    .ticket Ticket
}

ProbeError error = Io | NoEntry

async run() -> Result<nil, ProbeError> {
    handles Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>> = probe_read()
    reader Stream<ResourceEntry> = @get(handles, 0)
    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
    loop {
        pending Future<Result<ResourceEntry, nil>> = @next(reader)
        item Result<ResourceEntry, nil> = await(pending)
        if @is(item, Ok) {
            entry ResourceEntry = item
            _ = entry
        } else {
            break
        }
    }
    completed Result<nil, ProbeError> = await(completion)
    if @is(completed, Err) return completed
    return Ok()
}

start() {}
```

The WIT sidecar declares `resource ticket {}`, `resource-entry.ticket:
own<ticket>`, the source stream/future, and the async probe export.

- [x] **Step 2: Add lowering assertions.**

Copy the existing record-stream lowering gate structure and require the new
package/import names, resource declaration, resource field, drop import, and
resource release markers. Run `wasm-tools parse`, `component embed`,
`component new`, and Component validation.

### Task 4: Execute Resource Ownership In Wasmtime

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/record_resource_stream_probe.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/p3-runtime/test_rust_record_resource_stream_probe.sh`

**Interfaces:**
- `ResourceEntry` derives `ComponentType`, `Lift`, and `Lower` with
  `ticket: Resource<Ticket>`.
- `ProbeStream` pushes one fresh `Ticket` for each record into the
  `ResourceTable` before setting the stream buffer.
- The resource drop callback removes the table entry and increments a counter.

- [x] **Step 1: Add pending/ready/error host modes.**

Reuse the existing `ProbeCompletion` state machine. Supply records
`(1,111)` and `(2,222)`, then EOF. Assert that each mode observes three reads,
the two IDs in order, and one completion error only in error mode.

- [x] **Step 2: Assert exactly-once resource cleanup.**

Require `resource-created=2`, `resource-drops=2`, `stream-drops=1`,
`future-drops=1`, and `ResourceTable::is_empty()` after every call. Pending
mode must have two completion polls and one wake; ready/error modes must have
one poll and zero wakes.

- [x] **Step 3: Run the runtime gate.**

Run:

```bash
bash examples/p3-runtime/test_do_record_resource_stream_probe_lowering.sh
bash examples/p3-runtime/test_rust_record_resource_stream_probe.sh
```

Expected: all three modes pass without a leaked or double-dropped resource.

### Task 5: Documentation And Full Regression Closure

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [x] **Step 1: Record the bounded resource-field boundary.**

Document the descriptor, source field, drop ordering, and runtime evidence.
Move only the single owned-resource consumer slice out of the G6.2 pending
description. Keep borrowed fields, multiple/nested resources, producer leases,
broader completion payloads, and arbitrary filesystem async methods pending.

- [x] **Step 2: Run all release gates.**

Run:

```bash
./src/build/test/run_tests.sh
bash src/build/test/run_release_smoke.sh
git diff --check
```

Also rerun both old record-stream probes and the new resource probe after the
ReleaseSmall build. Record exact counts and any intentionally skipped cases.

## Exit Criteria

- The new private WIT package validates and contains one `own<ticket>` record
  field while Do source remains ownership-syntax-free.
- Two resource-bearing records reach the generated consumer in order.
- Each record's resource drops exactly once, including pending, ready, error,
  EOF, and terminal cleanup paths.
- The existing scalar/text record probe, bounded filesystem slice, full
  regression, ReleaseSmall smoke, and diff checks remain green.
- The docs state this is a single owned-resource consumer slice, not arbitrary
  resource-field or producer-lease support.
