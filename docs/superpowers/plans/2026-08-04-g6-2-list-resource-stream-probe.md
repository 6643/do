# G6.2 List-Owned Resource Stream Canonical ABI Probe Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove or reject one bounded private `stream<list<resource-entry>>`
ABI before any Do compiler lowering is considered.

**Architecture:** Keep the compiler on its current explicit rejection path while
a hand-written Core/WIT/Rust Component probe establishes the canonical list
layout and ownership transfer. The probe owns at most three `ticket` handles in
one list item and exercises one stream read plus one completion future; a later
plan may consume its recorded ABI facts but may not infer them.

**Tech Stack:** Zig `0.16.0`, Rust `1.97.1`, `wasm-tools 1.254.0`, Wasmtime
`47.0.2`, WIT, WAT, and Bash.

## Global Constraints

- Preserve the dirty worktree; do not reset, clean, checkout, commit, or push.
- Do not change public Do syntax or add `own<T>`, `borrow<T>`, `ref<T>`,
  pointers, references, generic list-resource lowering, or generic async calls.
- Use only private `do:record-resource-list-stream-probe@0.1.0` WIT and the
  single `read-via-stream` operation described below.
- Admit only one stream item with list lengths `0`, `1`, or `3`; reject length
  `4`, malformed pointer/length, duplicate cleanup, nested containers, variants,
  borrowed elements, and unregistered descriptors.
- Do not edit `src/build/codegen_component_record_stream.zig`,
  `src/build/p3_async_manifest.zig`, or `src/build/p3_async_registry.json` in
  this probe plan. A separate approved lowering plan is required after the ABI
  facts and negative cases are green.

---

### Task 1: Freeze WIT and the Current Do Rejection

**Files:**
- Create: `examples/p3-runtime/wit/record-resource-list-stream-probe.wit`
- Create: `examples/p3-runtime/record-resource-list-stream-probe-component.do`
- Create: `examples/p3-runtime/test_do_record_resource_list_stream_boundary.sh`

**Interfaces:**
- Consumes the existing `Ticket = @wasi_resource("do:record-resource-list-stream-probe/source/ticket", { .id i64 })` resource-shell pattern.
- Produces a private WIT world `record-resource-list-stream-probe` whose source
  operation returns `tuple<stream<list<resource-entry>>, future<result<_, error-code>>>`.

- [x] **Step 1: Write the private WIT world.**

```wit
package do:record-resource-list-stream-probe@0.1.0;

interface types { enum error-code { io } }

interface source {
  use types.{error-code};
  resource ticket {}
  record resource-entry { ticket: own<ticket> }
  read-via-stream: func() -> tuple<
    stream<list<resource-entry>>,
    future<result<_, error-code>>,
  >;
}

interface probe {
  use types.{error-code};
  run: async func() -> result<_, error-code>;
}

world record-resource-list-stream-probe {
  import types;
  import source;
  export probe;
}
```

- [x] **Step 2: Add the red Do source fixture.**

```do
probe_read = @host_func("do:record-resource-list-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<[ResourceEntry]>, Future<Result<nil, ProbeError>>>)
Ticket = @wasi_resource("do:record-resource-list-stream-probe/source/ticket", { .id i64 })

ResourceEntry { .ticket Ticket }
ProbeError error = Io

async run() -> Result<nil, ProbeError> {
    handles Tuple<Stream<[ResourceEntry]>, Future<Result<nil, ProbeError>>> = probe_read()
    reader Stream<[ResourceEntry]> = @get(handles, 0)
    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
    pending Future<Result<[ResourceEntry], nil>> = @next(reader)
    item Result<[ResourceEntry], nil> = await(pending)
    _ = item
    completed Result<nil, ProbeError> = await(completion)
    if @is(completed, Err) return completed
    return Ok()
}

start() {}
```

- [x] **Step 3: Run the red boundary gate.**

Run:

```bash
TMPDIR="$PWD/.tmp/do-tmp" \
  bash examples/p3-runtime/test_do_record_resource_list_stream_boundary.sh
```

Expected: `wasm-tools component embed` of the WIT world exits `0`; `do build
--p3-async-component` exits nonzero and contains the explicit
`UnknownP3AsyncHostDescriptor` rejection because this private locator is not
registered. The shell script must fail if either condition changes, so WIT
acceptance cannot be mistaken for Do lowering. A later registered descriptor
probe may reach `UnsupportedP3RecordStreamComponent`, but that is outside this
plan and must not be inferred here.

---

### Task 2: Establish the Canonical List ABI in a Hand-Written Component

**Files:**
- Create: `examples/p3-runtime/record-resource-list-stream-canonical.wat`
- Create: `examples/p3-runtime/test_record_resource_list_stream_abi.sh`
- Create: `examples/p3-runtime/wit/record-resource-list-stream-canonical.wit`

**Interfaces:**
- Consumes Task 1's `resource-entry { ticket: own<ticket> }` and list stream
  world.
- Produces an embedded Component whose Core module exports memory and
  `cabi_realloc`, calls the pinned `stream-read` and completion-future imports,
  and traps before a malformed result can be consumed.

- [x] **Step 1: Write a failing ABI assertion script before the Core fixture.**

The script must parse the Core WAT, embed the private WIT, create a component,
and invoke its Rust runner for `ready-empty`, `ready-one`, and `ready-three`.
It must require these literal markers:

```text
entries=[] resource-created=0 resource-drops=0 table-empty=true
entries=[111] resource-created=1 resource-drops=1 table-empty=true
entries=[111,222,333] resource-created=3 resource-drops=3 table-empty=true
```

Expected before the Core fixture exists: the script fails because the WAT or
runner binary is absent; it must not pass by grepping a source file.

- [x] **Step 2: Write the Core WAT around one result area.**

The module must reserve a result area, call the registered
`[async-lower][stream-read-0]read-via-stream` import once, and retain the raw
list pointer and list length long enough to validate all of the following before
reading an element handle:

```text
length == 0 || length == 1 || length == 3
pointer is zero iff length is zero
nonempty pointer is aligned to the probed element alignment
each element handle is nonzero before it becomes guest-owned
```

After validation, copy the handles into three fixed frame slots, clear the raw
ownership locations, and route completion/error/early-drop through one release
helper. That helper must clear each slot before calling `[resource-drop]ticket`;
therefore invoking it twice cannot drop a ticket twice. Export `cabi_realloc`
only for the list storage protocol observed by this probe; any other allocation,
alignment, resize, or duplicate free must `unreachable`.

- [x] **Step 3: Record the observed ABI facts in the script assertions.**

The WAT must contain stable comments for `list-result-pointer`,
`list-result-length`, `list-element-stride`, and `list-ticket-offset`. The shell
test extracts each marker's immediate `i32.const` value from generated output
and compares it to the Rust runner's observed list layout. A disagreement must
fail before runtime ownership assertions execute.

- [x] **Step 4: Run the green ABI gate.**

Run:

```bash
TMPDIR="$PWD/.tmp/do-tmp" \
  bash examples/p3-runtime/test_record_resource_list_stream_abi.sh
```

Expected: parse, embed, component creation, and the three ready lengths pass;
every created ticket is dropped once and no `ResourceTable` entry remains.

---

### Task 3: Add Pending, Terminal, and Negative Ownership Modes

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/record_resource_list_stream_abi.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Modify: `examples/p3-runtime/test_record_resource_list_stream_abi.sh`

**Interfaces:**
- Consumes the component produced by Task 2 and imports
  `source.read-via-stream` from Task 1's WIT world.
- Produces mode-specific counters for stream reads/drops, completion polls/drops,
  ticket creation/drop, and `ResourceTable` emptiness.

- [x] **Step 1: Extend the red script with all non-ready modes.**

Add these invocations before implementing the Rust runner:

```text
pending       -> resource-created=3 resource-drops=3 stream-drops=1 future-drops=1 table-empty=true
completion-error -> resource-created=3 resource-drops=3 stream-drops=1 future-drops=1 result=Err(io) table-empty=true
early-drop    -> resource-created=3 resource-drops=3 stream-drops=1 future-drops=1 table-empty=true
malformed-len -> expected trap=true resource-drops=0
duplicate-drop -> expected trap=true resource-drops=3 table-empty=true
```

Expected before the runner supports them: script failure due to an unknown mode.

- [x] **Step 2: Add one dedicated Wasmtime runner binary.**

Use `wasmtime::component::bindgen!` with
`record-resource-list-stream-canonical.wit` if the pinned macro can generate
the package. If it fails because the private `do:...` package name becomes the
Rust keyword `do`, retain the package identity and use the low-level `Linker`
API used by the neighboring record-stream runner; do not rename the WIT package
only to satisfy generated Rust identifiers. The host source must return one
`Vec<Resource<Ticket>>` item containing `[111]` or `[111, 222, 333]` for the
normal nonempty modes, and create all ticket resources through the store's
`ResourceTable`. Track every `Drop` callback in a shared `Stats` value. The
runner must invoke one component export through `Store::run_concurrent` and
return nonzero when any expected counter differs.

- [x] **Step 3: Implement malformed and duplicate probes below the WIT boundary.**

For `malformed-len`, make the hand-written Core result decoder see length `4`
before it owns any ticket; the component must trap before resource cleanup. For
`duplicate-drop`, call the Core release helper twice after three slots are
owned; the first call drops `[111,222,333]`, and the second must trap because
all slots were already cleared. These modes are not represented as normal WIT
values and must never be accepted by the public Rust binding.

- [x] **Step 4: Format and run the complete probe matrix.**

Run:

```bash
rustfmt --edition 2024 --check \
  examples/p3-runtime/rust-host-runner/src/bin/record_resource_list_stream_abi.rs
bash -n examples/p3-runtime/test_record_resource_list_stream_abi.sh
TMPDIR="$PWD/.tmp/do-tmp" \
  bash examples/p3-runtime/test_record_resource_list_stream_abi.sh
```

Expected: every positive mode has exact cleanup counts and an empty table;
malformed/duplicate modes trap only at their pinned boundary.

---

### Task 4: Record the Result Without Enabling Lowering

**Files:**
- Modify: `doc/design/2026-08-03-g6-2-general-resource-ownership.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `docs/superpowers/specs/2026-08-04-g6-2-list-resource-stream-design.md`

**Interfaces:**
- Consumes the exact offsets, stride, ownership order, and runtime counters from
  Tasks 2 and 3.
- Produces a pinned ABI record and an explicit statement that Do lowering is
  still rejected until a separate plan is approved.

- [x] **Step 1: Record only measured values.**

Document the actual pointer offset, length offset, element stride, ticket
offset, allocation/free call shape, and each mode's counters. Do not copy a
value from a different record, list<u8>, or resource-result probe.

- [x] **Step 2: Retain every boundary.**

State that public ownership syntax, generic list-resource lowering, a second
stream read, length above `3`, nested list/variant elements, borrowed fields,
and unregistered descriptors remain unsupported.

- [x] **Step 3: Run the probe and repository integrity checks.**

Run:

```bash
TMPDIR="$PWD/.tmp/do-tmp" \
  bash examples/p3-runtime/test_do_record_resource_list_stream_boundary.sh
TMPDIR="$PWD/.tmp/do-tmp" \
  bash examples/p3-runtime/test_record_resource_list_stream_abi.sh
git diff --check
```

Expected: the Do fixture remains rejected, the hand-written ABI matrix passes,
and the worktree has no whitespace errors. A production lowering plan may be
written only after these commands pass and the recorded facts are reviewed.

## Plan Self-Review

- The plan covers WIT acceptance, current Do rejection, raw canonical ABI,
  positive list lengths, terminal/negative cleanup, and evidence recording.
- It does not modify compiler lowering files or public syntax.
- All resource names, world names, test paths, modes, and expected counters are
  defined in this document; no step relies on an implicit generic list path.
