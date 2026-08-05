# G6.2 Variant-Owned Ticket Stream Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove or reject one private `stream<event>` Component ABI where only
`event.ticket` carries `own<ticket>`, before considering any Do compiler
lowering.

**Architecture:** Add a hand-written WIT/Core WAT/Wasmtime probe beside the
existing private list-owned-resource probe. The Core guest owns one decoded
ticket in a frame slot, and one release helper controls all terminal paths. A
dedicated low-level Wasmtime `Linker` runner supplies the event stream and
records every endpoint/resource action; a shell gate builds normal and
Core-mutated variants.

**Tech Stack:** WIT Component Model async, Core WAT, `wasm-tools 1.254.0`,
Rust `1.97.1`, Wasmtime `47.0.2`, Bash, and the repository's Zig toolchain
`0.16.0`.

## Global Constraints

- Pin `wasm-tools 1.254.0`, Wasmtime `47.0.2`, Rust `1.97.1`, and Zig `0.16.0`;
  a toolchain change requires a fresh probe.
- The only WIT source shape is `stream<event>` with
  `ticket(own<ticket>)`, `idle`, and `failed(error-code)`, plus
  `future<result<_, error-code>>` completion.
- Do not modify `src/build/`, parser, sema, registry, manifests, standard
  library declarations, or public Do syntax.
- A Core candidate layout becomes an ABI fact only after all Component/Rust
  modes pass. Never import constants from the list or resource-Result probes
  merely because their payload is also a handle.
- The WIT package remains `do:variant-resource-stream-canonical@0.1.0`. Keep
  the low-level `Linker` runner if `bindgen!` cannot emit a usable private
  `do:...` package module.
- All temporary Component artifacts live under `${TMPDIR:-$PWD/.tmp/do-tmp}`.
- The active worktree is dirty. Do not reset, clean, revert, stage, or commit
  unrelated work. This plan has no commit step unless the user separately
  authorizes a history change.

## File Structure

| File | Responsibility |
| --- | --- |
| `examples/p3-runtime/wit/variant-resource-stream-canonical.wit` | Private WIT package and world used only by the probe. |
| `examples/p3-runtime/variant-resource-stream-canonical.wat` | Hand-written Core guest: async stream/future coordination, event decoding, and exact-once cleanup. |
| `examples/p3-runtime/rust-host-runner/src/bin/variant_resource_stream_abi.rs` | Wasmtime source implementation, `ResourceTable` ownership counters, and mode assertions. |
| `examples/p3-runtime/rust-host-runner/Cargo.toml` | Explicit binary target for the runner. |
| `examples/p3-runtime/test_variant_resource_stream_abi.sh` | End-to-end parse/embed/new/validate/runtime gate and Core-only mutation builder. |
| `docs/superpowers/specs/2026-08-05-g6-2-variant-owned-ticket-stream-design.md` | Records measured ABI facts and changes status only after the green gate. |
| `doc/design/2026-08-03-g6-2-general-resource-ownership.md` | Updates the capability matrix without granting compiler support. |
| `doc/pending_blocked.md` | Retains generic variant/resource lowering as blocked after the private probe passes. |

---

### Task 1: Establish The Private WIT Contract

**Files:**
- Create: `examples/p3-runtime/wit/variant-resource-stream-canonical.wit`
- Test: `wasm-tools component wit` against that exact file

**Interfaces:**
- Produces world `variant-resource-stream-canonical`.
- Imports `source.read-via-stream: func() -> tuple<stream<event>, future<result<_, error-code>>>`.
- Exports `probe.run: async func() -> result<_, error-code>`.

- [x] **Step 1: Run the missing-WIT check first.**

  Run:

  ```bash
  wasm-tools component wit examples/p3-runtime/wit/variant-resource-stream-canonical.wit
  ```

  Expected: failure because the WIT file does not yet exist.

- [x] **Step 2: Add the exact private WIT package.**

  ```wit
  package do:variant-resource-stream-canonical@0.1.0;

  interface types {
    enum error-code { io }
  }

  interface source {
    use types.{error-code};
    resource ticket {}

    variant event {
      ticket(own<ticket>),
      idle,
      failed(error-code),
    }

    read-via-stream: func() -> tuple<
      stream<event>,
      future<result<_, error-code>>,
    >;
  }

  interface probe {
    use types.{error-code};
    run: async func() -> result<_, error-code>;
  }

  world variant-resource-stream-canonical {
    import types;
    import source;
    export probe;
  }
  ```

- [x] **Step 3: Prove WIT parsing and canonical spelling.**

  Run:

  ```bash
  wasm-tools component wit examples/p3-runtime/wit/variant-resource-stream-canonical.wit
  ```

  Expected: exit `0`, and normalized output contains all three `event` cases,
  `own<ticket>`, `stream<event>`, and the async completion future.

- [x] **Step 4: Check the isolated file for formatting damage.**

  Run:

  ```bash
  ! rg -n '[[:blank:]]+$' examples/p3-runtime/wit/variant-resource-stream-canonical.wit
  ```

  Expected: exit `0` and no output.

### Task 2: Build The Core Candidate And Component Validation Gate

**Files:**
- Create: `examples/p3-runtime/variant-resource-stream-canonical.wat`
- Create: `examples/p3-runtime/test_variant_resource_stream_abi.sh`
- Uses: `examples/p3-runtime/wit/variant-resource-stream-canonical.wit`

**Interfaces:**
- Imports exactly these source-side Core symbols from
  `do:variant-resource-stream-canonical/source@0.1.0`:
  `read-via-stream`, `[async-lower][stream-read-0]read-via-stream`,
  `[stream-drop-readable-0]read-via-stream`,
  `[async-lower][future-read-1]read-via-stream`,
  `[future-drop-readable-1]read-via-stream`, and `[resource-drop]ticket`.
- Exports `[async-lift]do:variant-resource-stream-canonical/probe@0.1.0#run`
  and its matching callback export.
- Produces a component that imports `source` and exports `probe.run`; the
  source implementation remains supplied by the Rust runner.

- [x] **Step 1: Write the red Component-build gate before the WAT exists.**

  Create a Bash script using the existing
  `test_record_resource_list_stream_abi.sh` directory/trap pattern. It must
  create a private temporary directory, define these paths, and stop on the
  first absent required file:

  ```bash
  wat="$repo_root/examples/p3-runtime/variant-resource-stream-canonical.wat"
  wit="$repo_root/examples/p3-runtime/wit/variant-resource-stream-canonical.wit"
  runner_dir="$repo_root/examples/p3-runtime/rust-host-runner"
  core_wasm="$tmp_dir/canonical.core.wasm"
  embedded="$tmp_dir/canonical.embedded.wasm"
  component="$tmp_dir/canonical.component.wasm"

  test -f "$wat"
  test -f "$wit"
  wasm-tools parse "$wat" -o "$core_wasm"
  wasm-tools component embed "$wit" "$core_wasm" \
    --world variant-resource-stream-canonical \
    --features cm-async,cm-more-async-builtins -o "$embedded"
  wasm-tools component new --skip-validation "$embedded" -o "$component"
  wasm-tools validate --features cm-async,cm-more-async-builtins "$component"
  ```

  Run:

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_variant_resource_stream_abi.sh
  ```

  Expected: failure at the missing WAT assertion.

- [x] **Step 2: Add the bounded async Core guest.**

  Start from the list probe's proven async callback/waitable structure, but
  use exactly one frame-owned ticket rather than list storage. Keep these frame
  fields and no dynamic allocation:

  ```text
  +0  waitable-set handle
  +4  readable stream handle
  +8  readable completion future handle
  +12 phase: 0 active, 2 released
  +16 owned ticket handle
  +20 ticket state: 0 absent, 1 owned, 2 released
  +64 stream event result buffer
  +80 completion Result buffer
  ```

  Emit layout comments adjacent to executable constants. The initial Core
  candidate is an eight-byte, four-byte-aligned event buffer at frame `+64`:

  ```wat
  (func $event-layout-markers
    ;; [event-result-pointer]
    i32.const 64
    drop
    ;; [event-tag-offset]
    i32.const 0
    drop
    ;; [event-payload-offset]
    i32.const 4
    drop
    ;; [event-size]
    i32.const 8
    drop
    ;; [event-alignment]
    i32.const 4
    drop
  )
  ```

  Call the stream read import once with the address `frame + 64` and capacity
  `1`. `consume-event` loads the tag before the payload. It accepts logical
  tags `0`, `1`, and `2` in WIT declaration order:

  ```wat
  ;; tag 0: validate nonzero ticket, move to frame +16, clear raw payload +4
  ;; tag 1: leave ticket state at 0 and begin completion
  ;; tag 2: validate error-code 0, set Result Err(io), then cleanup without a future poll
  ;; any other tag: unreachable before reading the payload
  ```

  The candidate constants are valid only if Task 3's high-level Rust cases
  decode the intended branches. A failing branch observation rejects the
  candidate; it does not authorize a fallback layout.

  Implement the ticket release helper with this ordering: validate state,
  load the frame handle, clear the frame handle, call `[resource-drop]ticket`,
  then store state `2`. State `0` returns; state `2` traps. The cleanup helper
  drops a nonzero future, drops a nonzero stream, calls the ticket release
  helper, drops the waitable set, calls `[task-return]run`, clears context, and
  recycles the sole frame. It never examines an idle or failed payload as a
  resource handle.

- [x] **Step 3: Add mutation anchors and a strict allocator boundary.**

  Surround the normal post-decode continuation with these exact comments:

  ```wat
  ;; [mode-before-event-consume]
  ;; [mode-after-event-consume]
  ```

  Export `cabi_realloc` only as a function that traps. This WIT has neither a
  string nor list payload, so a request for allocation is outside this probe.
  Export `_initialize` and retain the exact async-lift callback structure used
  by the list probe.

- [x] **Step 4: Run parse, embed, construction, and validation.**

  Run:

  ```bash
  TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_variant_resource_stream_abi.sh
  ```

  Expected: parse/embed/new/validate pass. A malformed Core module, wrong
  import name, or mismatched async export must fail before runtime execution.

### Task 3: Add The Wasmtime Event Source And Positive Runtime Matrix

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/variant_resource_stream_abi.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Modify: `examples/p3-runtime/test_variant_resource_stream_abi.sh`

**Interfaces:**
- Defines host `Ticket`, WIT `Event`, and `ErrorCode` Rust component types.
- Defines `EventStream: StreamProducer<State, Item = Event, Buffer = VecBuffer<Event>>`.
- Defines `Completion: Future<Output = wasmtime::Result<Result<(), ErrorCode>>>`.
- Executes `probe.run` with low-level `Linker` lookup under
  `do:variant-resource-stream-canonical/probe@0.1.0`.

- [x] **Step 1: Extend the shell gate with red positive assertions.**

  After Component validation, make the script invoke the declared runner and
  require these outputs:

  ```text
  ticket-ready      event=ticket resource-created=1 resource-drops=1 stream-drops=1 future-drops=1 completion-polls=1 table-empty=true result=Ok trap=false
  idle-ready        event=idle resource-created=0 resource-drops=0 stream-drops=1 future-drops=1 completion-polls=1 table-empty=true result=Ok trap=false
  failed-ready      event=failed(io) resource-created=0 resource-drops=0 stream-drops=1 future-drops=1 completion-polls=0 table-empty=true result=Err(io) trap=false
  ticket-pending    event=ticket resource-created=1 resource-drops=1 stream-drops=1 future-drops=1 completion-polls=2 table-empty=true result=Ok trap=false
  completion-error  event=ticket resource-created=1 resource-drops=1 stream-drops=1 future-drops=1 completion-polls=1 table-empty=true result=Err(io) trap=false
  ```

  Also extract `event-result-pointer`, `event-tag-offset`,
  `event-payload-offset`, `event-size`, and `event-alignment` from WAT markers
  using the existing `awk` helper. Require the runner's printed
  `observed-event-*` values to equal those five extracted values.

  Run the script before adding the runner.

  Expected: failure because Cargo has no `do-p3-variant-resource-stream-abi`
  binary target.

- [x] **Step 2: Register the runner and define Component types.**

  Add this binary entry to `Cargo.toml`:

  ```toml
  [[bin]]
  name = "do-p3-variant-resource-stream-abi"
  path = "src/bin/variant_resource_stream_abi.rs"
  ```

  In the new runner, use these type definitions and annotations:

  ```rust
  pub struct Ticket {
      _value: u32,
  }

  #[derive(
      Clone,
      Copy,
      Debug,
      PartialEq,
      wasmtime::component::ComponentType,
      wasmtime::component::Lift,
      wasmtime::component::Lower,
  )]
  #[component(enum)]
  #[repr(u8)]
  enum ErrorCode {
      #[component(name = "io")]
      Io,
  }

  #[derive(
      Debug,
      wasmtime::component::ComponentType,
      wasmtime::component::Lift,
      wasmtime::component::Lower,
  )]
  #[component(variant)]
  enum Event {
      #[component(name = "ticket")]
      Ticket(Resource<Ticket>),
      #[component(name = "idle")]
      Idle,
      #[component(name = "failed")]
      Failed(ErrorCode),
  }
  ```

  Keep `State { table: ResourceTable, stats: Arc<Mutex<Stats>> }`. The
  resource destructor increments `resource_drops`, reconstructs an owning
  `Resource<Ticket>`, and deletes it from the table; failure to delete is a
  Wasmtime error, never ignored.

- [x] **Step 3: Implement deterministic event and completion sources.**

  Define these modes in the runner: `TicketReady`, `IdleReady`, `FailedReady`,
  `TicketPending`, `CompletionError`, `EarlyDrop`, `MalformedTag`, and
  `DuplicateRelease`. The first five are positive in this task. The latter
  three emit `Event::Ticket` with value `111` and are consumed by Core variants
  in Task 4.

  `EventStream::poll_produce` must produce exactly one element, increment
  `stream_read_calls`, and record `ticket`, `idle`, or `failed(io)` in stats.
  It creates a `Resource<Ticket>` only for `Event::Ticket`; `Idle` and
  `Failed(ErrorCode::Io)` must not call `ResourceTable::push`. Its `Drop`
  implementation increments `stream_drops`.

  `Completion` must increment `completion_polls`; `TicketPending` returns one
  `Poll::Pending` after scheduling the waker and then `Ok(Ok(()))`;
  `CompletionError` returns `Ok(Err(ErrorCode::Io))`; all other completion
  modes return `Ok(Ok(()))`. Its `Drop` increments `future_drops`.

- [x] **Step 4: Call the private Component world and assert the matrix.**

  Configure:

  ```rust
  config.wasm_component_model(true);
  config.wasm_component_model_async(true);
  config.wasm_component_model_more_async_builtins(true);
  config.concurrency_support(true);
  ```

  Use `linker.instance("do:variant-resource-stream-canonical/source@0.1.0")`
  for the source imports and retrieve `probe.run` through export indices, then
  call it via `Store::run_concurrent`. The typed export is:

  ```rust
  TypedFunc<(), (std::result::Result<(), ErrorCode>,)>
  ```

  Each positive mode must compare the complete `Stats` snapshot and
  `ResourceTable::is_empty()` against the Step 1 text. Print one stable line
  containing mode, event, all counters, table state, five observed marker
  values, result, and trap state. Do not treat a host or component trap as an
  acceptable result in these five modes.

- [x] **Step 5: Format and run the positive green gate.**

  Run:

  ```bash
  rustfmt --edition 2024 --check examples/p3-runtime/rust-host-runner/src/bin/variant_resource_stream_abi.rs
  bash -n examples/p3-runtime/test_variant_resource_stream_abi.sh
  TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_variant_resource_stream_abi.sh
  ```

  Expected: the five positive modes pass, including `failed(io)` without any
  ticket allocation/drop and the pending completion's exactly two polls.

### Task 4: Add Negative Core Mutations And Record The Measured Boundary

**Files:**
- Modify: `examples/p3-runtime/variant-resource-stream-canonical.wat`
- Modify: `examples/p3-runtime/test_variant_resource_stream_abi.sh`
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/variant_resource_stream_abi.rs`
- Modify: `docs/superpowers/specs/2026-08-05-g6-2-variant-owned-ticket-stream-design.md`
- Modify: `doc/design/2026-08-03-g6-2-general-resource-ownership.md`
- Modify: `doc/pending_blocked.md`

**Interfaces:**
- Core-only variants are never represented by Rust WIT values; they are
  produced by `sed` mutation of the otherwise-valid canonical WAT.
- `MalformedTag` and `DuplicateRelease` must be reported as `trap=true` by the
  runner. `EarlyDrop` remains `Ok` and has no completion poll.

- [x] **Step 1: Extend the gate with red terminal and trap assertions.**

  Add a `build_variant` function that parses, embeds, builds, and validates one
  mutated WAT. Add these substitutions around Task 2's anchors:

  ```bash
  malformed-tag)
    sed '/;; \[mode-before-event-consume\]/,+3 c\
    ;; [mode-before-event-consume]\
    local.get $frame\
    i32.const 64\
    i32.add\
    i32.const 3\
    i32.store\
    local.get $frame\
    call $consume-event' "$wat" >"$variant"
    ;;
  duplicate-release)
    sed '/;; \[mode-after-event-consume\]/,+3 c\
    ;; [mode-after-event-consume]\
    local.get $frame\
    call $release-ticket\
    local.get $frame\
    call $release-ticket\
    i32.const 0' "$wat" >"$variant"
    ;;
  early-drop)
    sed '/;; \[mode-after-event-consume\]/,+3 c\
    ;; [mode-after-event-consume]\
    local.get $frame\
    call $cleanup' "$wat" >"$variant"
    ;;
  ```

  Invoke the runner with expectations:

  ```text
  early-drop         event=ticket resource-created=1 resource-drops=1 stream-drops=1 future-drops=1 completion-polls=0 table-empty=true result=Ok trap=false
  malformed-tag      event=ticket resource-created=1 resource-drops=0 table-empty=false result=none trap=true
  duplicate-release  event=ticket resource-created=1 resource-drops=1 table-empty=true result=none trap=true
  ```

  Run the gate before adding the three runner expectations.

  Expected: failure because those modes are not yet parsed or asserted by the
  runner.

- [x] **Step 2: Complete the runner's terminal and trap handling.**

  For `EarlyDrop`, expect the normal `Ok(())` result but zero completion polls.
  For `MalformedTag` and `DuplicateRelease`, run the Component call and accept
  only an engine or component error; a successful `Ok` or `Err(io)` export is a
  test failure. The malformed case expects no resource destructor and a
  nonempty table because the invalid tag traps before payload ownership. The
  duplicate case expects one resource destructor and an empty table because
  the first helper cleared its only owner before the second helper trapped.

- [x] **Step 3: Run the complete private ABI matrix.**

  Run:

  ```bash
  rustfmt --edition 2024 --check examples/p3-runtime/rust-host-runner/src/bin/variant_resource_stream_abi.rs
  bash -n examples/p3-runtime/test_variant_resource_stream_abi.sh
  TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_variant_resource_stream_abi.sh
  ```

  Expected: all eight modes pass. The full Component construction path is used
  for every Core mutation; no malformed value crosses a normal WIT host
  boundary.

- [x] **Step 4: Record only the green-gate facts.**

  Update the design spec's status and add a measured-ABI table using the five
  marker values emitted by the passing gate, its observed branch behavior, and
  exact cleanup counters. Update the general ownership matrix entry at
  `doc/design/2026-08-03-g6-2-general-resource-ownership.md:41` from
  tool-accepted/no-runtime-evidence to private-probe-verified/Do-lowering-
  unavailable. Amend G6.2 in `doc/pending_blocked.md:23` to say this private
  variant probe has evidence while generic variant/resource lowering remains
  blocked. Do not add a registry row or relax an unsupported descriptor.

- [x] **Step 5: Run final repository-facing verification.**

  Run:

  ```bash
  wasm-tools --version
  wasmtime --version
  rustfmt --edition 2024 --check examples/p3-runtime/rust-host-runner/src/bin/variant_resource_stream_abi.rs
  bash -n examples/p3-runtime/test_variant_resource_stream_abi.sh
  TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_variant_resource_stream_abi.sh
  ./src/build/test/run_tests.sh
  git diff --check
  ```

  Expected: pinned versions report the planned values; the private ABI matrix
  and compiler regression suite pass; `git diff --check` reports no whitespace
  errors. Inspect the diff to confirm it only touches the listed private probe
  and evidence files, plus the explicit Cargo binary target.
