# P3 CLI Stdin Stream Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make one pinned `wasi:cli/stdin.read-via-stream` import produce a Do `Stream<u8>` and completion Future, then lower one `@next(reader)` operation through a legacy async Component and execute it in the Rust Wasmtime host.

**Architecture:** The public entry remains a normal `@host` declaration whose result is `Tuple<Stream<u8>, Future<Result<nil, StdinError>>>`; `@next` remains the only reader operation and does not consume the reader. A dedicated Component target recognizes only this pinned descriptor and straight-line `async run() -> nil` fixture, emits the exact legacy `stream.read` and unread-Future `drop-readable` canonical operations, and keeps ordinary `do build` guarded. The Rust runner provides a host-originating `StreamReader<u8>` and `FutureReader<Result<nil, StdinError>>`, so it verifies byte delivery, EOF, completion, and disposal without depending on terminal input.

**Tech Stack:** Zig compiler/WAT, pinned WIT under `src/build/p3_wit`, `wasm-tools 1.254.0` legacy async mode, Rust Wasmtime `47.0.2` component-model-async.

## Global Constraints

- The only admitted WIT operation is `wasi:cli/stdin@0.3.0-rc-2025-09-16/read-via-stream`; filesystem and HTTP stream paths remain rejected.
- Source exposes no pointer, reference, `own<T>`, or `borrow<T>` types.
- The source acquisition shape is `stdin_read = @host("wasi:cli/stdin@0.3.0-rc-2025-09-16", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, StdinError>>>)`.
- `StdinError error = Io | IllegalByteSequence | Pipe` exactly represents WIT `error-code`.
- `@next(reader)` maps an item to `Ok(u8)` and a closed readable end to `Err(nil)`; the separate completion Future is not folded into EOF.
- The Component target accepts only straight-line acquisition, one or two `@next` calls, explicit completion-Future cleanup, and a single `async run() -> nil` export.
- Do not introduce an operation ID, host broker, global completion slot, or special stdin language intrinsic.
- Keep ordinary `do build` returning `AsyncLoweringUnavailable`; only the explicit P3 Component target may lower this fixture.
- No staged, committed, reset, clean, or pushed changes in the shared dirty worktree.

---

### Task 1: Pin The Stdin Stream ABI Surface

**Files:**
- Create: `examples/p3-runtime/wit/cli-stream-stdin.wit`
- Create: `examples/p3-runtime/test_cli_stream_stdin_abi_surface.sh`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`

**Interfaces:** The WIT package defines `wasi:cli/types.error-code`, `wasi:cli/stdin.read-via-stream`, and a `stream-stdin-probe` world importing stdin and exporting `async run()`. The shell test emits a legacy dummy Core module and proves the toolchain's import and async builtins before compiler code depends on them.

- [x] **Step 1: Write the failing ABI surface test**

```bash
output=$(wasm-tools component embed "$wit" --world stream-stdin-probe \
  --dummy-names legacy --async-callback -t)
grep -Fq '"wasi:cli/stdin@0.3.0-rc-2025-09-16" "read-via-stream"' <<<"$output"
grep -Fq '(param i32)' <<<"$output"
grep -Fq '"$root" "[waitable-set-new]"' <<<"$output"
grep -Fq '"[export]$root" "[task-return]run"' <<<"$output"
```

- [x] **Step 2: Verify red**

Run: `bash examples/p3-runtime/test_cli_stream_stdin_abi_surface.sh`

Expected: fail because the pinned CLI stream WIT fixture and test do not exist.

- [x] **Step 3: Add the pinned WIT and test script**

```wit
package wasi:cli@0.3.0-rc-2025-09-16;

interface types { enum error-code { io, illegal-byte-sequence, pipe } }
interface stdin {
  use types.{error-code};
  read-via-stream: func() -> tuple<stream<u8>, future<result<_, error-code>>>;
}
world stream-stdin-probe { import stdin; export run: async func(); }
```

The script must run only `wasm-tools component embed` with `--dummy-names legacy --async-callback`; it must not accept standard32 names or substitute an unversioned import.

- [x] **Step 4: Verify green**

Run: `bash examples/p3-runtime/test_cli_stream_stdin_abi_surface.sh`

Expected: exit zero and print the pinned import plus waitable/task ABI markers.

### Task 2: Prove Rust Host Stream/Future Ownership

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/cli_stream_stdin.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/p3-runtime/test_rust_cli_stream_stdin.sh`

**Interfaces:** The runner uses `wasmtime::component::bindgen!` against `cli-stream-stdin.wit`; the `wasi:cli/stdin` host implementation is typed to return `StreamReader<u8>` backed by `vec![0x61, 0x62]` and `FutureReader<Result<(), ErrorCode>>` resolving `Ok(())`. This task proves the host API compiles; guest byte/EOF assertions belong to Task 4 after a callable lowering exists.

- [x] **Step 1: Write the failing Rust runner assertion**

```rust
assert!(host_provider_typechecks);
assert!(stream_reader_and_future_reader_are_explicitly_guarded);
```

- [x] **Step 2: Verify red**

Run: `bash examples/p3-runtime/test_rust_cli_stream_stdin.sh`

Expected: fail because no runner binary or Component fixture is available.

- [x] **Step 3: Implement the typed host binding**

```rust
let reader = accessor.with(|store| StreamReader::new(store, vec![0x61_u8, 0x62]));
let completion = accessor.with(|store| FutureReader::new(store, std::future::ready(Ok(()))));
stdin.func_wrap_concurrent("read-via-stream", move |accessor, ()| {
    Box::pin(async move { Ok((reader?, completion?)) })
})?;
```

Use generated `ErrorCode` rather than `u8`, and use `GuardedStreamReader`/`GuardedFutureReader` when consuming guest-returned handles. Do not claim cleanup from Store destruction.

- [x] **Step 4: Verify green**

Run: `bash examples/p3-runtime/test_rust_cli_stream_stdin.sh`

Expected: `cargo check` succeeds with typed `StreamReader<u8>` and `FutureReader<Result<(), ErrorCode>>` providers; no runtime byte/EOF claim is made until Task 4.

### Task 3: Admit The Generic Host Acquisition Shape

**Files:**
- Modify: `src/build/codegen_component_async.zig`
- Modify: `src/build/sema_imports.zig`
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/codegen_component_async_plan.zig`
- Create: `src/build/test/check/381_cli_stdin_stream_acquire.do`
- Create: `src/build/test/compile_err/381_cli_stdin_stream_build_guard.do`
- Create: `src/build/test/compile_err/381_cli_stdin_stream_build_guard.expect`

**Interfaces:** `Target.stream_reader` is selected only for the exact versioned locator/member and exact nested Tuple return. `ComponentAsyncFunctionPlan` records `stream_u8_acquire` separately from `@next`, preserving the stream binding and completion-Future binding as distinct affine values.

- [x] **Step 1: Write the failing source fixtures**

```do
StdinError error = Io | IllegalByteSequence | Pipe
stdin_read = @host("wasi:cli/stdin@0.3.0-rc-2025-09-16", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, StdinError>>>)

async run() -> nil {
    handles Tuple<Stream<u8>, Future<Result<nil, StdinError>>> = stdin_read()
    reader Stream<u8> = @get(handles, 0)
    completion Future<Result<nil, StdinError>> = @get(handles, 1)
    pending Future<Result<u8, nil>> = @next(reader)
    item Result<u8, nil> = await(pending)
    _ = item
    @cancel(completion)
}
start() {}
```

- [x] **Step 2: Verify red**

Run: `./bin/do check src/build/test/check/381_cli_stdin_stream_acquire.do`

Expected: source checking accepts the generic host declaration, while the explicit P3 Component build target still reports `UnsupportedP3AsyncComponent`.

- [x] **Step 3: Implement descriptor and plan validation**

Add a manifest descriptor with WIT package `wasi:cli@0.3.0-rc-2025-09-16`, interface `stdin`, operation `read-via-stream`, empty parameter list, and a canonical result-area `i32` pointer. Reject another version, another interface, a non-`u8` stream, omitted completion Future, implicit completion discard, branch/loop bodies, or an untyped tuple binding with `UnsupportedP3AsyncComponent`.

- [x] **Step 4: Verify green**

Run: `cd src && zig test build/codegen_component_async.zig && zig test build/codegen_component_async_plan.zig && cd .. && ./bin/do check src/build/test/check/381_cli_stdin_stream_acquire.do && ./bin/do build --p3-async-component src/build/test/compile_err/381_cli_stdin_stream_build_guard.do -o /tmp/stream.wat`

Expected: `do check` accepts the admitted source form; normal `do build` returns `AsyncLoweringUnavailable`.

### Task 4: Emit And Execute `@next` For The Admitted Stream

**Files:**
- Modify: `src/build/codegen_p3_wait_for.zig`
- Modify: `src/build/codegen_component_async.zig`
- Create: `examples/p3-runtime/cli-stream-stdin-component.do`
- Create: `examples/p3-runtime/test_do_cli_stream_stdin_lowering.sh`
- Modify: `doc/host_abi_blockers.md`

**Interfaces:** The Component emitter writes stream/future handles from the `read-via-stream` result area into task-local frame slots. Each `@next(reader)` emits the registered `stream.read` canonical function for `u8`, writes one item as `Ok`, maps readable-end closure to `Err(nil)`, and never transfers the reader. Because the source explicitly uses `@cancel(completion)` while the completion Future is unread, completion cleanup uses `future.drop-readable` directly; a separately pending Future read would use `future.cancel-read` before the same drop operation.

- [x] **Step 1: Write the failing emitted-WAT assertions**

```bash
grep -Fq '[stream-acquire]read-via-stream' "$wat"
grep -Fq 'stream.read' "$wat"
if grep -Fq 'future-cancel-read' "$wat"; then exit 1; fi
grep -Fq '[stream-eof]Err(nil)' "$wat"
grep -Fq '[stream-drop-readable]' "$wat"
grep -Fq 'future-drop-readable' "$wat"
if grep -Fq '__stream_completion_global' "$wat"; then exit 1; fi
```

- [x] **Step 2: Verify red**

Run: `bash examples/p3-runtime/test_do_cli_stream_stdin_lowering.sh`

Expected: fail with `UnsupportedP3AsyncComponent` or missing stream/future canonical markers.

- [x] **Step 3: Implement the narrow frame-state emitter**

Reuse the existing async frame header and task return path. Allocate no global completion state. Emit a canonical `stream.read` definition for the pinned WIT stream type and call it from the resume state, then emit the unread `future.drop-readable` path for the completion Future. Admit at most three explicit, straight-line `@next` sites so the fixed fixture can prove two bytes followed by EOF; reject loops, branches, and every other source shape.

- [x] **Step 4: Verify Component assembly and host execution**

Run: `bash examples/p3-runtime/test_do_cli_stream_stdin_lowering.sh && bash examples/p3-runtime/test_rust_cli_stream_stdin.sh`

Expected: `wasm-tools component new` and validate succeed; the Rust runner observes `0x61`, `0x62`, then EOF, completion `Ok`, and explicit stream/future cleanup.

**Runtime resolution (2026-08-01):** `future.cancel-read` is not an operation that cancels an unread Future. The emitter now calls `future.drop-readable` directly for the unread completion Future; it emits no `future.read` or `future.cancel-read` for this source shape. Wasmtime 47.0.2 accepts the direct drop, and the Rust runner covers both pending and already-ready host Futures with zero completion polls and exactly one drop.

### Task 5: Close The Source-To-Component Boundary

**Files:**
- Modify: `doc/host_abi_blockers.md`
- Modify: `docs/superpowers/plans/2026-07-31-p3-cli-stream-stdin.md`

**Interfaces:** Documentation records the verified CLI stdin fixture and retains filesystem, HTTP bodies/trailers, batch reads, backpressure policy beyond the admitted component, arbitrary Stream payloads, and general async lowering as blocked.

- [x] **Step 1: Record the executable evidence**

Document the pinned WIT file/hash, exact Component target, Rust runner command, byte/EOF/completion assertions, and reader/Future cleanup ownership.

- [x] **Step 2: Preserve the exclusion boundary**

State that `descriptor.read-via-stream`, HTTP response bodies, and generic `Stream<T>` are not admitted by this fixture, and normal `do build` remains guarded.

- [x] **Step 3: Run final verification**

Run: `cd src && zig test build/codegen_component_async.zig && zig test build/codegen_component_async_plan.zig && zig test build/codegen_p3_wait_for.zig && cd .. && bash examples/p3-runtime/test_cli_stream_stdin_abi_surface.sh && bash examples/p3-runtime/test_do_cli_stream_stdin_lowering.sh && bash examples/p3-runtime/test_rust_cli_stream_stdin.sh && ./src/build/test/run_tests.sh && git diff --check`

Expected: all commands exit zero; the stream fixture is executable only through the explicit P3 Component target.

## Plan Self-Review

- Task 1 pins toolchain-visible ABI before compiler work.
- Task 2 proves the Wasmtime host owns and explicitly closes concrete stream/future handles.
- Task 3 admits only a normal `@host` acquisition declaration and preserves the generic source model.
- Task 4 owns the pinned canonical `stream.read`/unread `drop-readable` Core lowering and no broader stream shape.
- Task 5 prevents this one fixture from being misreported as generic Stream, filesystem, HTTP, or ordinary-build support.
