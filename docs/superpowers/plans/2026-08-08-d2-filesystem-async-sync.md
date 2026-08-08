# D2 Bounded Filesystem Async `descriptor.sync` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove and privately promote one adjacent WASI filesystem async method, `descriptor.sync`, without generalizing the already-closed `descriptor.get-type` slice.

**Architecture:** The phase measures `wasi:filesystem/types@0.3.0-rc-2025-09-16` `descriptor.sync: async func() -> result<_, error-code>` independently, then runs a local Rust/Wasmtime matrix before touching the compiler registry. The compiler admits one straight-line Do shape with a resource receiver, one `Future<nil | SyncError>`, and one `@await`; it reuses existing async frame/cleanup contracts through a separate descriptor target and remains fail-closed for every other filesystem method or payload shape.

**Tech Stack:** Zig 0.16.0, Do compiler, WIT/Core WAT, `wasm-tools` 1.255.0 capability probe plus pinned legacy 1.254.0 async assembly, Rust/Cargo 1.97.1, Wasmtime 47.0.2, Bash regression harness.

## Global Constraints

- Keep ordinary Do result APIs as `T | E` or `nil | E`; `Result<T, E>` remains private to WIT/Component probes.
- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, or lifetime syntax.
- Admit exactly one new method: `wasi:filesystem/types@0.3.0-rc-2025-09-16 / descriptor.sync`.
- Keep `descriptor.get-type` behavior and registry validation unchanged; do not merge the two methods into an unbounded generic filesystem emitter.
- Use one Component and one Wasmtime Store per runtime mode, with a temporary local file supplied through `DO_D2_FILESYSTEM_ROOT`.
- Cancellation ends the guest task/future and releases live Component resources; it never rolls back a filesystem sync already issued to the host.
- Do not change ordinary `do build` dispatch. The new lowering remains behind the existing `--p3-async-component` profile and a private descriptor.
- Unknown descriptors, borrowed/list/variant payloads, multiple children, second awaits, branches, loops, `defer`, and arbitrary producer expressions remain fail-closed.
- If either pinned toolchain rejects the measured ABI, stop before registry/codegen changes and record the exact diagnostic and recovery condition in `doc/pending_blocked.md`.

## Decision and Alternatives

`descriptor.sync` is the recommended next shape because it is the smallest adjacent method that adds a new semantic dimension: a resource receiver plus a unit-success/error Result. It has no stream, list, record, option, or owned payload, and its host effect is observable through call/poll/completion counters without requiring external networking.

The following alternatives remain explicitly deferred:

| Candidate | Decision | Reason |
| --- | --- | --- |
| `descriptor.get-flags` | Defer | Scalar-looking, but WIT `flags` representation and width need a separate canonical ABI measurement; it adds no receiver/cleanup coverage beyond the current method. |
| `descriptor.stat` | Defer | `descriptor-stat` contains multiple scalar fields and three `option<datetime>` fields; this is a new record/option payload design, not a small follow-up. |
| `read-via-stream` / `write-via-stream` | Defer | Requires stream handles, producer/consumer lease rules, list/record cleanup, and a larger cancellation state machine. |
| G6.2 producer/resource residual | Separate track | It has independent ownership and producer topology gates; mixing it into D2 would make the phase non-atomic. |

## File Map

### Design and probe

- Create: `docs/superpowers/specs/2026-08-08-d2-filesystem-async-sync-design.md`
- Create: `examples/p3-runtime/wit/wasi-filesystem-sync.wit`
- Create: `examples/p3-runtime/wasi-filesystem-sync.core.wat`
- Create: `examples/p3-runtime/wit/wasi-filesystem-sync-cancel.wit`
- Create: `examples/p3-runtime/wasi-filesystem-sync-cancel.core.wat`
- Create: `examples/p3-runtime/test_d2_wasi_filesystem_sync_abi.sh`

### Runtime

- Create: `examples/p3-runtime/rust-host-runner/src/bin/wasi_filesystem_sync.rs`
- Create: `examples/p3-runtime/test_rust_wasi_filesystem_sync.sh`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml` with one binary entry only.

### Conditional compiler promotion

- Modify: `src/build/p3_async_registry.json`
- Modify: `src/build/p3_async_manifest.zig`
- Modify: `src/build/sema_imports.zig`
- Create: `src/build/codegen_component_wasi_filesystem_sync.zig`
- Create: `src/build/wasi_filesystem_sync_component_template.wat`
- Modify: `src/build/codegen_component_async.zig`
- Create: `src/build/test/compile_ok/462_wasi_filesystem_sync_component.do`
- Create: `src/build/test/compile_ok/462_wasi_filesystem_sync_component.expect`
- Create: `src/build/test/compile_err/462_wasi_filesystem_sync_unregistered.do`
- Create: `src/build/test/compile_err/462_wasi_filesystem_sync_unregistered.expect`
- Create: `src/build/test/compile_err/463_wasi_filesystem_sync_wrong_result.do`
- Create: `src/build/test/compile_err/463_wasi_filesystem_sync_wrong_result.expect`
- Create: `src/build/test/compile_err/464_wasi_filesystem_sync_borrowed_payload.do`
- Create: `src/build/test/compile_err/464_wasi_filesystem_sync_borrowed_payload.expect`
- Create: `src/build/test/compile_err/465_wasi_filesystem_sync_second_await.do`
- Create: `src/build/test/compile_err/465_wasi_filesystem_sync_second_await.expect`

### Status synchronization after green gates

- Modify only after Tasks 2-4 pass: `doc/host_abi_blockers.md`, `doc/pending_blocked.md`, `doc/start_here.md`, `doc/roadmap_status.md`, `doc/master_plan.md`, `CHANGELOG.md`.

## Task 1: Freeze the source contract and baseline

**Interfaces:** Consumes the completed private `descriptor.get-type` probe and the pinned filesystem WIT source. Produces an exact sync signature and a clean baseline; it does not add a registry entry.

- [x] **Step 1: Confirm the pinned source declaration.**

```bash
rg -n -A3 -B3 'sync: async func' \
  src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit
```

Require the source line `sync: async func() -> result<_, error-code>;` under the pinned `descriptor` resource. Record the existing upstream source hash `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`; do not use the mirror hash as the package hash.

- [x] **Step 2: Write the design contract.**

The spec must freeze the package/version, `types` interface, `descriptor.sync` signature, receiver ownership in WIT, the unit-success/error result representation, pending/ready/error/cancel behavior, exactly-once cleanup counters, and the no-rollback cancellation rule. It must state that public Do source remains `nil | SyncError` and that no registry entry exists until Tasks 2 and 3 pass.

- [x] **Step 3: Run the baseline gates.**

```bash
bash examples/p3-runtime/test_d2_wasi_filesystem_get_type_abi.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_get_type.sh
cd src && zig test main.zig
cd ..
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
```

Record fresh counts. A failure blocks this plan before any sync files are added.

## Task 2: Measure the canonical sync ABI

**Interfaces:** Consumes the source contract from Task 1. Produces a hand-authored WIT/Core component probe and a machine-readable record of the exact async import, task-return completion words, unit/error result tag, receiver handle, and descriptor drop.

- [x] **Step 1: Write the minimal WIT world.**

Use the pinned `error-code` member order from `examples/p3-runtime/wit/wasi-filesystem-get-type.wit`, and replace the method and world with this exact private shape:

```wit
package wasi:filesystem@0.3.0-rc-2025-09-16;

interface types {
  enum error-code {
    access,
    already,
    bad-descriptor,
    busy,
    deadlock,
    quota,
    exist,
    file-too-large,
    illegal-byte-sequence,
    in-progress,
    interrupted,
    invalid,
    io,
    is-directory,
    loop,
    too-many-links,
    message-size,
    name-too-long,
    no-device,
    no-entry,
    no-lock,
    insufficient-memory,
    insufficient-space,
    not-directory,
    not-empty,
    not-recoverable,
    unsupported,
    no-tty,
    no-such-device,
    overflow,
    not-permitted,
    pipe,
    read-only,
    invalid-seek,
    text-file-busy,
    cross-device,
  }
  resource descriptor {
    sync: async func() -> result<_, error-code>;
  }
}

interface probe {
  use types.{descriptor, error-code};
  run: async func(file: own<descriptor>) -> result<_, error-code>;
}

world sync-probe {
  import types;
  export probe;
}
```

`own<descriptor>` exists only in WIT and generated Component metadata.

- [x] **Step 2: Generate and freeze the Core fixture from the tool output.**

Run the current and legacy `wasm-tools component embed --dummy-names legacy --async-callback --features cm-async,cm-more-async-builtins -t` commands against the probe. Assert the exact import name `[async-lower][method]descriptor.sync`, the `[resource-drop]descriptor` import, the root `[task-return]run`, and every measured function type used by the sync method. Do not copy get-type completion offsets or parameter counts without measuring them.

- [x] **Step 3: Assemble and validate both toolchain paths.**

```bash
bash examples/p3-runtime/test_d2_wasi_filesystem_sync_abi.sh
```

The script must pin both tool versions and binary hashes, distinguish upstream WIT hash from mirror hash, parse/embed/new/validate the hand-authored Component, print its WIT, and fail on method/package/import/result/drop drift. No compiler registry or positive Do fixture is allowed before this command is green.

- [x] **Step 4: Stop on a pinned ABI no-go.** No no-go condition was
  triggered: current `wasm-tools 1.255.0` and legacy `1.254.0` both assembled
  and validated the measured sync ABI.

If `component embed`, `component new`, or validation rejects the sync result, append the complete command, diagnostic, tool hashes, and recovery condition to `doc/pending_blocked.md`; leave all compiler files and registry entries unchanged.

## Task 3: Run the isolated Rust/Wasmtime matrix

**Interfaces:** Consumes the validated hand-authored sync Component. Produces ready/pending/error/cancel evidence with exactly-once task/future/descriptor cleanup and an empty `ResourceTable`.

- [x] **Step 1: Implement temporary local-file host state.**

The Rust runner must carry a descriptor `PathBuf`, call the host sync operation only for the admitted descriptor, and expose counters for host calls, polls, external wakes, completions, pending-future drops, descriptor drops, and `table-empty`. Use one Component and one Store per mode.

- [x] **Step 2: Implement the four drive modes.**

`ready` completes a regular temporary file immediately; `pending` returns `Poll::Pending` once and wakes exactly once before success; `error` returns an explicit `io` or `no-entry` error without defaulting to success; `cancel` uses a test-only async control endpoint because dropping a Wasmtime `call_concurrent` future does not hard-cancel a guest task. The cancel component must share the measured sync method and invoke `[subtask-cancel]` before normal cleanup.

- [x] **Step 3: Run the focused runtime gate.**

```bash
bash examples/p3-runtime/test_rust_wasi_filesystem_sync.sh
```

Require `host-calls=1`, the documented poll/wake count for each mode, one completion or one pending-future drop as appropriate, one descriptor drop, no duplicate completion, and `table-empty=true`. Cancellation must document that an already-issued host sync is not rolled back.

## Task 4: Promote only the measured private Do slice

**Interfaces:** Consumes the Task 2 ABI record and Task 3 cleanup order. Produces one opt-in `--p3-async-component` target; ordinary source and all existing targets remain unchanged.

- [x] **Step 1: Add manifest and sema admission tests first.**

Register exactly `descriptor.sync` with its measured canonical fields and pinned WIT hash. Add tests for package/version drift, wrong `Result<nil,error-code>` shape, missing receiver/drop metadata, wrong async import, and unknown locator. Sema must accept only the exact host signature:

```do
sync_descriptor = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.sync", (Dir) -> nil | SyncError)
```

- [x] **Step 2: Add the isolated analyzer and emitter.**

Admit only this source topology:

```do
sync_descriptor = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.sync", (Dir) -> nil | SyncError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
SyncError error = Io | NoEntry

run(file Dir) -> nil {
    pending Future<nil | SyncError> = sync_descriptor(file)
    result nil | SyncError = @await(pending)
}

start() {}
```

The analyzer must require exactly two top-level functions, one host binding, one resource declaration, one child, one await, and an empty `start`; it must reject all other filesystem members, `Result<T,E>` source spelling, second awaits, branches/loops/defer, borrowed/list/variant payloads, and arbitrary calls. The emitter must use the measured sync frame/cleanup facts and must not infer them from `descriptor.get-type`.

- [x] **Step 3: Add positive and negative compiler fixtures.**

The positive fixture must emit only the registered sync import, task-return/result completion imports, and descriptor drop. Fixtures `462`–`465` must fail before WAT for an unregistered locator, wrong result, borrowed payload, and second await with stable diagnostics.

- [x] **Step 4: Run the compiler-generated Component gate.**

Extend `test_rust_wasi_filesystem_sync.sh` to build the positive Do fixture with `--p3-async-component`, emit the WIT sidecar, parse/embed/new/validate it with the pinned tools, and run the generated ready/pending/error modes against the same Rust runner. Compare generated cleanup counters with the hand-authored component; keep cancellation covered by the hand-authored test-only cancel component unless a generated cancel fixture is explicitly added and measured.

## Task 5: Close the phase and preserve the boundary

**Interfaces:** Consumes the complete probe/runtime/compiler evidence. Produces a truthful D2 checkpoint and leaves all broader work as pending.

- [x] **Step 1: Run focused, neighboring, and full gates.**

```bash
bash examples/p3-runtime/test_d2_wasi_filesystem_sync_abi.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_sync.sh
bash examples/p3-runtime/test_d2_wasi_filesystem_get_type_abi.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_get_type.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_real.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_read_directory_real.sh
bash examples/p3-runtime/test_rust_cli_stream_stdin_real.sh
bash examples/p3-runtime/test_rust_wasi_sockets_real.sh
cd src && zig test main.zig
cd ..
./src/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh
git diff --check
```

- [x] **Step 2: Update status only after all gates are green.**

Record the upstream/mirror hashes, measured sync ABI, fixture numbers, runtime counters, and fresh regression totals in `doc/host_abi_blockers.md`, `doc/pending_blocked.md`, `doc/start_here.md`, `doc/roadmap_status.md`, `doc/master_plan.md`, and `CHANGELOG.md`. Mark only private `descriptor.sync` verified.

- [x] **Step 3: Verify explicit non-goals.**

Keep `descriptor.get-flags`, `descriptor.stat`, `read-via-stream`, `write-via-stream`, other filesystem async methods, generic producer expressions, borrowed payloads, independent guest tasks, external HTTP, and public `own<T>`/`borrow<T>`/`ref<T>` pending. Do not add a generic `filesystem_async` fallback.

## Acceptance and Recovery

The phase is complete only when Tasks 1-5 are green and the generated and hand-authored sync Components agree on ABI and cleanup. A probe-only green result closes no compiler capability. Any pinned ABI/toolchain failure is a recorded no-go; the recovery condition is a newer pinned toolchain or a separately measured WIT shape, not a guessed signature or a compatibility alias.
