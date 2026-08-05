# Record-Stream Layout Metadata Implementation Plan

**Status:** completed and verified on 2026-08-02.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Move the pinned `directory-entry` record-area offsets into the validated async manifest and make the bounded read-directory emitter consume those facts without widening source-level stream support.

**Architecture:** Add an optional canonical `record_layout` containing a record name and ordered Core scalar fields with explicit byte offsets. The registry validator will require this layout for the admitted record-stream descriptor and reject malformed or missing layout facts. The existing bounded emitter will resolve the three directory-entry fields through the descriptor layout, while dynamic loops, arbitrary record types, and unregistered descriptors remain rejected.

**Tech Stack:** Zig manifest parser/tests, checked-in JSON registry, WAT template replacement, existing read-directory Component regression scripts.

## Global Constraints

- Keep `wasi:filesystem/types@0.3.0-rc-2025-09-16` `descriptor.read-directory` as the only admitted record-stream descriptor.
- Keep the bounded one-to-three static `@next(reader)` source contract and the existing EOF, cancellation, and exactly-once cleanup behavior.
- Do not admit arbitrary record layouts, source loops, public `own<T>`, `borrow<T>`, `ref<T>`, pointers, or references.
- Preserve the pinned WIT/Core import names and the existing result-area offsets outside the directory-entry record fields.

---

### Task 1: Parse And Validate Record Layout Facts

**Files:**
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/p3_async_registry.json`
- Test: `src/build/p3_async_manifest.zig`

**Interfaces:**
- Consumes: the existing `Canonical` JSON object and `record-stream-reader` descriptor validation.
- Produces: `Canonical.record_layout: ?RecordLayout`, `RecordLayout.field_offset(name) ?u32`, and a lowerable pinned descriptor only when the layout is valid.

- [x] **Step 1: Add failing manifest assertions.**

Add a checked-in registry test that expects `directory-entry` to expose fields
`type@0`, `name-ptr@4`, and `name-len@8`. Add a malformed in-memory descriptor
case with a missing layout and assert `lowering_shape` returns null.

- [x] **Step 2: Run the focused tests and verify RED.**

Run:

```bash
cd src && zig test build/p3_async_manifest.zig --test-filter 'record layout'
```

Expected: compilation fails because `RecordLayout` and the registry metadata do
not exist yet.

- [x] **Step 3: Implement owned layout parsing and validation.**

Add `RecordField { name, core_type, offset }` and `RecordLayout { name, fields }`.
Parse `canonical.record_layout`, duplicate owned strings, reject empty names,
non-Core-scalar field types, duplicate names, unaligned offsets, and overlapping
four-byte fields. Free the layout from `free_canonical`. Require the pinned
record-stream descriptor to have the exact record name `directory-entry` and
the three current fields before returning `LoweringShape.record_stream_reader`.

- [x] **Step 4: Add the observed directory-entry layout to the registry and run green tests.**

Add the explicit `record_layout` object to the pinned descriptor and run:

```bash
cd src && zig test build/p3_async_manifest.zig --test-filter 'record layout'
```

Expected: valid layout assertions and malformed-layout rejection pass.

### Task 2: Consume Layout Facts In The Bounded Emitter

**Files:**
- Modify: `src/build/codegen_component_wasi_filesystem_read_directory.zig`
- Test: `src/build/codegen_component_wasi_filesystem_read_directory.zig`

**Interfaces:**
- Consumes: `RecordStreamReaderShape` and `RecordLayout.field_offset` from Task 1.
- Produces: WAT with registry-derived directory-entry field offsets and the same single reusable stream-read call site.

- [x] **Step 1: Add a failing emitter assertion.**

Assert that the bounded WAT contains explicit layout replacement markers for the
three record fields and that changing the test registry layout changes those
markers without changing frame-owned handle offsets.

- [x] **Step 2: Verify the assertion is RED.**

Run:

```bash
cd src && zig test build/codegen_component_wasi_filesystem_read_directory.zig --test-filter 'record layout emitter'
```

Expected: the test fails because `consume-entry` still embeds `64`, `68`, and
`72` directly in the WAT template.

- [x] **Step 3: Replace hardcoded record offsets with layout lookups.**

Resolve `type`, `name-ptr`, and `name-len` offsets from the descriptor shape,
replace only the corresponding WAT template markers, and return
`UnsupportedP3WasiReadDirectoryComponent` if the shape cannot provide them.
Keep frame slots, status codes, and stream/future cleanup unchanged.

- [x] **Step 4: Run focused emitter and Component checks.**

Run:

```bash
cd src && zig test build/codegen_component_wasi_filesystem_read_directory.zig
bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_bounded_lowering.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_read_directory_bounded.sh
```

Expected: all focused tests and both pending/ready runtime modes pass.

### Task 3: Record The Narrow Boundary And Regression Closure

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/pending_blocked.md`
- Modify: `docs/superpowers/specs/2026-08-02-wasi-read-directory-bounded-multiread-design.md`
- Modify: this plan

- [x] **Step 1: Document the layout checkpoint.**

State that the pinned bounded emitter now consumes registry-owned
`directory-entry` layout facts, while generic record-stream layouts, dynamic
iteration, payload-bearing completion errors, and arbitrary filesystem async
methods remain unsupported.

- [x] **Step 2: Run the release verification matrix.**

Run:

```bash
cd src && zig test build/p3_async_manifest.zig
cd src && zig test build/codegen_component_wasi_filesystem_read_directory.zig
cd .. && SKIP_BUILD=1 ./src/build/test/run_tests.sh
bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_abi.sh
bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_lowering.sh
bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_bounded_lowering.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_read_directory.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_read_directory_bounded.sh
bash src/build/test/run_release_smoke.sh
git diff --check
```

Verified: `zig test main.zig` `191/191`, default regression
`pass=1049 fail=0 skip=3`, ABI/lowering/runtime gates, ReleaseSmall smoke, and `git diff --check`
all pass; no new descriptor or source shape is admitted.

## Phase Exit Criteria

- The pinned record-stream descriptor carries validated explicit layout facts.
- The bounded emitter consumes those facts instead of hardcoded record offsets.
- Existing ABI, lowering, runtime, default regression, and ReleaseSmall gates pass.
- G6.2 generic record-stream and arbitrary filesystem async support remain
  explicitly blocked rather than silently claimed complete.
