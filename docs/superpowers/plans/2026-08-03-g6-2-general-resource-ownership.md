# G6.2 General Resource Ownership and Host ABI Implementation Plan

> Refreshed 2026-08-07: this is the next-stage handoff plan. The current
> private owned-future/list-borrow/runtime probes are green; this plan still
> stops before public ownership syntax or general async lowering.

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` (or `superpowers:subagent-driven-development`) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a bounded, evidence-backed design for general producer leases and WIT resource ownership before widening the private async/component lowering.

**Architecture:** Reuse the existing path-sensitive `StreamWriter<T>` lease analysis, resource ownership checker, descriptor registry, and private Component emitters. First record the runtime/toolchain capability boundary and define a single ownership state machine that covers producer leases, host resources, async completion, cancellation, and nested cleanup; only then select one small implementation slice. Public `own<T>`, `borrow<T>`, and `ref<T>` syntax remain out of scope.

**Tech Stack:** Zig 0.16 compiler/tests, Do fixtures, WAT/WIT Component assembly,
legacy `wasm-tools 1.254.0` plus capability `wasm-tools 1.255.0`, Rust 2024,
Wasmtime `47.0.2` legacy async runner, Bash regression harness.

## Global Constraints

- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax.
- Do not enable general async-call lowering, arbitrary producer expressions, or general filesystem async methods in this phase.
- Preserve value semantics and the existing internal WIT/manifest ownership metadata.
- Preserve cancellation semantics: stop guest work and release live resources; never roll back an external side effect.
- Keep the legacy assembler on hash-pinned `wasm-tools 1.254.0 (bb58fdf91 2026-07-20)`; use `wasm-tools 1.255.0 (76e20611d 2026-07-30)` only for the current capability probes. Record toolchain rejection as a boundary, not as a compiler workaround.
- Do not extend the current supported runtime gates beyond six nested owned-resource levels or five forwarding hops until the design gate is reviewed.
- Preserve unrelated dirty worktree changes; do not reset, clean, checkout, commit, or push.

---

## Entry Gate: Close the Current StreamMirror Phase

The next phase starts only after the descriptor-bounded StreamMirror closeout is independently green. The current implementation already has focused Zig and Rust/Wasmtime evidence; the remaining full-matrix check must use a workspace `TMPDIR` so Node's `os.tmpdir()` does not hit the `/tmp` quota.

### Task 1: Freeze the verified baseline

**Files:**

- Verify: `docs/superpowers/plans/2026-08-03-g6-2-stream-mirror-runtime-closeout.md`
- Verify: `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/start_here.md`
- Test: existing compiler and runtime gates below

**Interfaces:**

- Consumes: current `StreamMirror` lowering and Rust/Wasmtime six-mode matrix.
- Produces: a fresh baseline for this plan; no implementation changes.

- [x] **Step 1: Run the default regression.**

```bash
mkdir -p .tmp/do-tmp/default-tmp .tmp/do-tmp/debug-zig-cache .tmp/do-tmp/debug-zig-gcache
TMPDIR="$PWD/.tmp/do-tmp/default-tmp" \
ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/debug-zig-cache" \
ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/debug-zig-gcache" \
NODE_BIN="$(command -v bun)" \
./src/build/test/run_tests.sh
```

Expected: `fail=0`; use the repository's Node-compatible runner explicitly so
the installed `/snap/bin/node` cannot produce the known silent wasm false
failures. The current reference run is `NODE_BIN=$(command -v bun)` with
`pass=1109 fail=0 skip=3`; record the fresh count rather than assuming it.

- [x] **Step 2: Run the WASM regression with workspace temporary storage.**

```bash
mkdir -p .tmp/do-tmp/wasm-tmp .tmp/do-tmp/wasm-zig-cache .tmp/do-tmp/wasm-zig-gcache
TMPDIR="$PWD/.tmp/do-tmp/wasm-tmp" \
ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/wasm-zig-cache" \
ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/wasm-zig-gcache" \
NODE_BIN="$(command -v bun)" \
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
```

Expected: `fail=0` and a complete WASM run summary; record the fresh counts and
the exact `RUN_WASM=1` environment used.

- [x] **Step 3: Run ReleaseSmall smoke with workspace caches.**

```bash
mkdir -p .tmp/do-tmp/release-tmp .tmp/do-tmp/release-zig-cache .tmp/do-tmp/release-zig-gcache
TMPDIR="$PWD/.tmp/do-tmp/release-tmp" \
ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/release-zig-cache" \
ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/release-zig-gcache" \
NODE_BIN="$(command -v bun)" \
./src/build/test/run_release_smoke.sh
```

Expected: `release smoke passed`.

- [x] **Step 4: Re-run the focused StreamMirror and artifact checks.**

```bash
legacy_wasm_tools=/home/_/.local/share/Trash/files/wasm-tools-1.254.0-x86_64-linux/wasm-tools
mkdir -p .tmp/do-tmp/focused-tmp
PATH="$(dirname "$legacy_wasm_tools"):$PATH" \
WASM_TOOLS="$legacy_wasm_tools" \
TMPDIR="$PWD/.tmp/do-tmp/focused-tmp" \
  bash examples/p3-runtime/test_do_stream_mirror_lowering.sh
PATH="$(dirname "$legacy_wasm_tools"):$PATH" \
WASM_TOOLS="$legacy_wasm_tools" \
TMPDIR="$PWD/.tmp/do-tmp/focused-tmp" \
  bash examples/p3-runtime/test_rust_stream_mirror.sh
(cd src && zig test build/codegen_component_stream_writer.zig && zig test build/codegen_component_async_plan.zig)
rustfmt --edition 2024 --check examples/p3-runtime/rust-host-runner/src/bin/stream_probe_stream_mirror.rs
bash -n examples/p3-runtime/test_do_stream_mirror_lowering.sh examples/p3-runtime/test_rust_stream_mirror.sh
python3 -m json.tool src/build/p3_async_registry.json >/dev/null
git diff --check
```

Expected: all commands exit zero; the runtime matrix reports `pending`, `ready`, `source-eof`, `error`, `cancel`, and `early-drop`, with one source future drop, one source stream drop, one sink drop, and `table-empty=true`.

**Stop condition:** If a failure is a compiler/runtime assertion rather than temporary storage, stop this phase and repair the StreamMirror closeout before starting Task 2. A storage failure is recorded with its `TMPDIR` and cache paths and does not change the ownership design.

### Task 2: Publish the handoff boundary

**Files:**

- Modify: `doc/roadmap_status.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/start_here.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `CHANGELOG.md`

**Interfaces:**

- Consumes: Task 1 command output.
- Produces: explicit status separating verified StreamMirror runtime cleanup from the still-blocked general resource gates.

- [x] **Step 1: Record only fresh counts and commands.**

The status text must say that descriptor-bounded StreamMirror is verified for six modes, while general producer lease, borrowed/list/variant resource fields, sixth forwarding, seventh nesting, arbitrary producer expressions, and general async calls remain blocked.

- [x] **Step 2: Keep cancellation language aligned.**

State that cancellation releases live Component resources and does not compensate external effects; do not add an operation-id or rollback protocol.

- [x] **Step 3: Verify documentation consistency.**

```bash
git diff --check
```

Expected: zero output and no status document claiming that the general gate is complete.

---

## Feasibility and Design Stage

### Task 3: Build the pinned capability matrix without compiler changes

**Files:**

- Create: `doc/design/2026-08-03-g6-2-general-resource-ownership.md`
- Verify: `src/build/p3_async_registry.json`
- Verify: `src/build/resource_abi_registry.json`
- Verify: `src/build/p3_wit/`
- Test: existing `examples/p3-runtime/test_*` probes and direct pinned-tool commands

**Interfaces:**

- Consumes: pinned WIT snapshots, descriptor registry metadata, current Rust/Wasmtime runner behavior, and `wasm-tools` diagnostics.
- Produces: a table that marks each shape `verified`, `rejected by compiler`, `rejected by wasm-tools`, `runtime-unknown`, or `deferred`.

- [x] **Step 1: Inventory the current verified shapes.**

Record exact evidence for direct owned resource fields, scalar/string record consumers, one through six nested owned-resource levels, multiple top-level nested paths, bounded `StreamWriter<u8>` producers, parameterized `u64` producers, helper forwarding through five hops, helper parameter reorder, and StreamMirror six-mode cleanup.

- [x] **Step 2: Probe the remaining shapes against the pinned toolchain.**

Use minimal WIT/Component inputs, not new compiler lowering, for:

```text
borrow<T> in a stream record
list<T> and variant payloads containing resources
seventh nested owned-resource level
sixth producer forwarding edge
producer expressions other than the registered bounded forms
two independent async calls sharing one producer lease
```

Record the exact command, diagnostic, and whether the rejection is frontend, Component assembly, validation, or Wasmtime runtime.

- [x] **Step 3: Define the first implementation candidate from evidence.**

The candidate must use only shapes accepted by the pinned toolchain and must fit the existing private descriptor/registry model. Do not select borrowed/list/variant stream fields merely because the source syntax can be parsed; a `borrow<T>` rejection at Component embed is a hard boundary.

- [x] **Step 4: Review the matrix for scope creep.**

The design document must explicitly keep `own<T>`, `borrow<T>`, `ref<T>`, general async-call composition, and D2 real host I/O outside the implementation candidate.

### Task 4: Specify one ownership state machine and its invariants

**Files:**

- Modify: `doc/design/2026-08-03-g6-2-general-resource-ownership.md`
- Reference: `src/build/sema_stream_lease.zig`
- Reference: `src/build/sema_resource_ownership.zig`
- Reference: `src/build/codegen_async_cleanup.zig`
- Reference: `src/build/codegen_component_stream_writer.zig`

**Interfaces:**

- Consumes: Task 3 capability matrix and existing `LeaseState`/resource ownership behavior.
- Produces: a language-independent transition contract that a later sema and Component emitter can implement without adding public ownership syntax.

- [x] **Step 1: Define resource/lease states.**

The contract must distinguish at least `owned`, `owned-deferred`, `borrowed-use`, `transferred`, `in-flight`, `finalized`, `cancelled`, and `maybe`; document which states may be observed at a branch or loop join.

- [x] **Step 2: Define legal transitions and rejection points.**

Specify transfer, helper call, borrow observation, write, close/abort, await completion, cancellation, return, `break`, `continue`, and defer registration. A consumed or finalized owner must reject later use; a `maybe` owner must reject exit until paths converge.

- [x] **Step 3: Define nested cleanup ordering.**

For a parent resource with child resources, state the required reverse-acquisition order and the rule that a waitable-set or subtask cannot be dropped while it still owns a child endpoint. Include the StreamMirror fix as a concrete invariant, not as a special-case exception.

- [x] **Step 4: Define cancellation terminal behavior.**

Cancellation must transition the private frame to a terminal state, cancel/drop live Component tasks and endpoints exactly once, and leave already-issued external operations untouched. No rollback callback is part of the compiler ABI.

- [x] **Step 5: Add proof obligations for a future implementation.**

List the minimum unit and runtime assertions: no use-after-transfer, no double finalization, no leaked owner on every exit, no child-before-parent drop, stable branch/loop joins, and `ResourceTable::is_empty()` after each supported terminal path.

### Task 5: Add negative boundary fixtures before widening codegen

**Files:**

- Create: `examples/p3-runtime/stream-probe-guest-producer-sixth-forwarding.do`
- Create: `examples/p3-runtime/stream-probe-guest-producer-arbitrary.do`
- Create: `examples/p3-runtime/test_do_g6_general_boundary_rejection.sh`
- Create: `src/build/test/check/412_stream_writer_shared_lease.do`
- Create: `src/build/test/check/412_stream_writer_shared_lease.expect`
- Create: `examples/p3-runtime/wit/record-resource-stream-borrowed-probe.wit`
- Create: `examples/p3-runtime/test_do_borrowed_resource_rejection.sh`
- Verify: `src/build/p3_async_manifest.zig` seventh-level rejection test
- Modify: `doc/pending_blocked.md` only if the diagnostic wording or boundary changes

**Interfaces:**

- Consumes: Task 3 exact rejection diagnostics and the existing `run_tests.sh` layer conventions.
- Produces: layer-correct regression locks proving that unsupported expansion remains explicit and is not silently lowered.

- [x] **Step 1: Write the two compile-mode rejection fixtures.**

The sixth-hop and arbitrary-producer fixtures stay under `examples/p3-runtime`, because the standard `compile_err` harness intentionally invokes ordinary `do build` and cannot select `--p3-async-component`. The dedicated shell gate must invoke the P3 target and require `UnsupportedP3AsyncComponent` for both fixtures.

- [x] **Step 2: Write the sema shared-lease fixture and pinned WIT gate.**

The shared writer fixture belongs under `check` and must contain `StreamWriterAlreadyFinalized`. The WIT fixture and shell script must run pinned `wasm-tools component embed` and require `contains a \`borrow<T>\` which is not supported` in stderr. The existing `p3_async_manifest.zig` test remains the seventh-level gate and must not be duplicated as a source fixture that silently reuses another descriptor's registry layout.

- [x] **Step 3: Run the focused boundary gates.**

```bash
./bin/do check src/build/test/check/412_stream_writer_shared_lease.do
(cd src && zig test build/p3_async_manifest.zig)
bash examples/p3-runtime/test_do_g6_general_boundary_rejection.sh
bash examples/p3-runtime/test_do_borrowed_resource_rejection.sh
```

Expected: the check command fails with `StreamWriterAlreadyFinalized`, manifest tests pass `63/63`, the P3 boundary script confirms both `UnsupportedP3AsyncComponent` failures, and the pinned WIT gate confirms only the expected borrowed-type diagnostic.

- [x] **Step 4: Run the complete default regression.**

```bash
ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/debug-zig-cache" \
ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/debug-zig-gcache" \
NODE_BIN="$(command -v bun)" \
./src/build/test/run_tests.sh
```

Expected: zero failures; the skip set remains unchanged.

---

## Implementation Authorization Gate

### Task 6: Choose and scope the first positive expansion

**Files:**

- Modify: `doc/design/2026-08-03-g6-2-general-resource-ownership.md`
- Modify: `doc/pending_blocked.md`
- Create: `docs/superpowers/plans/2026-08-03-g6-2-first-positive-resource-slice.md`

**Interfaces:**

- Consumes: Tasks 3–5 and their command evidence.
- Produces: a separately reviewable implementation plan with one positive shape, exact files, and exact runtime assertions.

- [x] **Step 1: Prefer the smallest shape that exercises a new invariant.**

The recommended candidate is a private descriptor-bounded producer operation sequence with one explicit lease transfer and one terminal completion, reusing the existing `StreamWriter<T>` lease states and no borrowed/list/variant/nested resource payloads. It must add a real capability, not merely raise the forwarding-depth or nesting constant.

- [x] **Step 2: Reject candidates that require a new product decision.**

Do not authorize public ownership syntax, general async-call lowering, arbitrary producer expressions, borrowed/list/variant stream records, or real WASI/D2 host I/O in the same plan.

- [x] **Step 3: Define the stopping gate.**

The positive implementation plan is not started until the capability matrix, ownership state machine, negative fixtures, and full regression are green and the pinned toolchain accepts the selected shape.

---

## Completion Criteria

This planning phase is complete when:

- the StreamMirror closeout has fresh default, WASM, ReleaseSmall, focused runtime, and artifact evidence;
- the capability matrix contains exact diagnostics and tool versions for every rejected shape;
- one ownership state machine covers producer leases, resources, nested cleanup, async completion, and cancellation;
- negative fixtures lock the current sixth-hop, seventh-level, and borrowed-field boundaries;
- a separate positive implementation plan exists, or the evidence proves no positive expansion is currently safe;
- status documents distinguish `已验`, `未验`, `待验证`, and residual risks.

The phase must stop before public `own<T>`/`borrow<T>`/`ref<T>` syntax, general async lowering, or D2 host runtime work. Those are separate decisions, not hidden consequences of this plan.
