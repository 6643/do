# G6.2 Private Resource Result Terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a bounded `Err(failed)` terminal path to the existing private async resource Result probe, with exactly-once resource and frame cleanup.

**Architecture:** Keep `do:resource-probe/http@0.1.0` and its fixed two-word result buffer. Extend the resource-result Core callback so ready error tags finish through the same task-return epilogue as success, writing a zero response payload and the error tag. Extend only the Rust host probe to exercise error completion; no new public language syntax or generic async lowering is introduced.

**Tech Stack:** Zig 0.16, Do compiler WAT/WIT emitter, pinned `wasm-tools 1.254.0`, Rust 2024, Wasmtime `47.0.2`, Bash regression harness.

## Global Constraints

- Keep the WIT `send: async func(request: request) -> result<response, error-code>` unchanged.
- Keep `Result<HttpResponse, HttpError>` private to the registered descriptor; do not generalize resource Result payloads.
- Do not add `own<T>`, `borrow<T>`, `ref<T>`, pointer/reference syntax, arbitrary async-call lowering, or payload-bearing errors.
- Cancellation remains outside this source shape until an explicit `@cancel` operation is designed and tested.
- Keep `wasm-tools 1.254.0` and Wasmtime `47.0.2` pinned.
- Preserve unrelated dirty worktree changes; do not reset, clean, checkout, commit, or push.

## File Map

- Modify: `src/build/codegen_component_resource_async.zig` — resource-result callback terminal branch and emitter assertion.
- Modify: `examples/p3-runtime/rust-host-runner/src/bin/async_resource_result.rs` — error host mode and cleanup counters.
- Modify: `examples/p3-runtime/test_rust_async_resource_result.sh` — pending/immediate/error runtime assertions.
- Modify: `examples/p3-runtime/test_do_async_resource_result.sh` — WAT marker for the error terminal path.
- Modify: `doc/roadmap_status.md`, `doc/pending_blocked.md`, `doc/host_abi_blockers.md`, `README.md`, `CHANGELOG.md` — evidence and boundary wording.
- Test: `src/build/codegen_component_resource_async.zig` — red/green WAT assertion.

## Task 1: Add red tests before production changes

**Interfaces:** The existing `emit_resource_async_core_wat` output and Rust probe remain the inputs. The tests require a distinct error terminal marker and runtime modes that current code does not satisfy.

- [x] **Step 1: Add the Zig failing assertion.**

In the existing resource emitter test, require both a named error terminal marker and a zero-payload store:

```zig
try std.testing.expect(std.mem.indexOf(u8, wat, "[resource-result-error-terminal]") != null);
try std.testing.expect(std.mem.indexOf(u8, wat, "i32.const 0\n      i32.store") != null);
```

- [x] **Step 2: Add host error mode and shell expectations.**

Make `DO_P3_ASYNC_RESOURCE_ERROR=1` return `Err(failed)` from the host callback and assert:

```text
Rust P3 async resource Result error adapter passed
request consumed=2
response create=0
response drop=0
```

The current emitter must fail this test because its callback treats the error tag as still pending.

- [x] **Step 3: Run the red tests.**

Run:

```bash
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_do_async_resource_result.sh
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_rust_async_resource_result.sh
```

Expected: the existing pending/immediate checks pass while the new error marker fails. Cancellation is intentionally not part of this source shape; do not change production WAT until this red failure is observed.

## Task 2: Implement the fixed error terminal

**Interfaces:** Consume the existing `$frame-ref`, `$slot-result-ptr`, `$task-return`, and canonical-buffer release sequence. Produce one terminal path for error tags without creating a response resource.

- [x] **Step 1: Add a named WAT marker and error branch.**

In the callback function, retain the ready-success condition `(status == 1 && tag == 2)`. Add the sibling condition `(status == 1 && tag == 1)` and emit:

```wat
;; [resource-result-error-terminal]
local.get $frame-ref
struct.get $async-frame $slot-result-ptr
i32.const 0
i32.store
local.get $frame-ref
struct.get $async-frame $slot-result-ptr
i32.const 4
i32.add
local.get 2
i32.store
```

Then load both words and call the same `$task-return`, canonical-buffer release, context clear, and frame-free epilogue used by success.

- [x] **Step 2: Preserve non-ready behavior.**

When `status != 1`, or when the callback has no registered terminal tag, return the existing waitable token without writing the result area or freeing the frame.

- [x] **Step 3: Run focused Zig tests.**

```bash
cd src
zig test build/codegen_component_resource_async.zig
zig test build/codegen_component_async.zig
```

Expected: the new error marker assertion and all existing resource/HTTP async tests pass.

## Task 3: Implement and verify host error mode

**Interfaces:** Consume the fixed component ABI. Produce runtime observations for error completion without claiming cancellation or rollback.

- [x] **Step 1: Complete error mode.**

In `async_resource_result.rs`, return `(Err(ErrorCode::Failed),)` when `DO_P3_ASYNC_RESOURCE_ERROR` is set. Run two requests and assert both requests are consumed, no response is created or dropped, and the component calls return `Err(failed)`.

- [x] **Step 2: Run the runtime gate.**

```bash
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_rust_async_resource_result.sh
```

Expected: pending, immediate, and error markers all pass; error has zero response create/drop. Cancellation remains a separate source-shape design.

## Task 4: Run Component lowering and full verification

**Interfaces:** Consume the updated private emitter and host runner. Produce stable WIT/WAT and regression evidence.

- [x] **Step 1: Run the lowering gate.**

```bash
TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_do_async_resource_result.sh
```

Expected: unchanged WIT snapshot, both request/response drop imports, the task-return marker, and `[resource-result-error-terminal]`; no cancellation marker is asserted.

- [x] **Step 2: Run focused tooling checks.**

```bash
(cd src && zig fmt --check build/codegen_component_resource_async.zig)
rustfmt --edition 2024 --check examples/p3-runtime/rust-host-runner/src/bin/async_resource_result.rs
CC="$PWD/examples/p3-runtime/rust-host-runner/zig-cc.sh" \
CXX="$PWD/examples/p3-runtime/rust-host-runner/zig-cc.sh" \
CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$PWD/examples/p3-runtime/rust-host-runner/zig-cc.sh" \
  cargo check --locked --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml
```

- [x] **Step 3: Run the complete regression.**

```bash
TMPDIR="$PWD/.tmp/do-tmp/resource-result-default" \
ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/resource-result-zig-cache" \
ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/resource-result-zig-gcache" \
  ./src/build/test/run_tests.sh
TMPDIR="$PWD/.tmp/do-tmp/resource-result-wasm" \
ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/resource-result-zig-cache" \
ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/resource-result-zig-gcache" \
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
```

Expected: default `pass=1068 fail=0 skip=3`, WASM `pass=1070 fail=0 skip=3` with six smoke cases, ReleaseSmall smoke passes, and no unrelated boundary changes.

## Task 5: Update evidence and retain blocked boundaries

- [x] **Step 1:** Record the private error gate and separate cancellation boundary in `doc/roadmap_status.md` and `doc/host_abi_blockers.md`.
- [x] **Step 2:** Keep `doc/pending_blocked.md` explicit that arbitrary producer leases, payload-bearing errors, borrowed/list/variant fields, sixth forwarding, seventh nesting, and public ownership syntax remain blocked.
- [x] **Step 3:** Add one dated `CHANGELOG.md` entry with exact fresh counts and the new runtime markers.

## Exit Criteria

This plan is complete only when the red test was observed before the emitter change, the pending/immediate/error runtime modes pass under pinned Wasmtime, all existing G6.2 gates remain green, and the documented boundary still excludes cancellation without an explicit `@cancel` source shape, public ownership syntax, and general async composition.
