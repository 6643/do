# D2 `descriptor.sync` Async Filesystem Design

**Status:** Tasks 1-4 complete and Task 5 is closed. The ABI, isolated
Rust/Wasmtime runtime, compiler admission, generated Component, neighboring
gates, and full regression gates are green for this private bounded method.

## Goal

Measure and, only after a green runtime gate, privately promote this one pinned
WASI filesystem method:

```wit
descriptor.sync: async func() -> result<_, error-code>
```

The method is a resource-receiver async call with a unit success arm and an
`error-code` arm. It is intentionally adjacent to the completed private
`descriptor.get-type` slice, but its task-return and result layout must be
measured independently.

## Pinned Source and Tools

- Source: `src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit`
- Source commit: `90fed3c6adf53f112c4dea56851728557bb73799`
- Upstream `types.wit` SHA-256: `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`
- Current capability probe: `wasm-tools 1.255.0 (76e20611d 2026-07-30)`
- Legacy async assembler: `wasm-tools 1.254.0 (bb58fdf91 2026-07-20)`
- Rust/Cargo: `1.97.1`
- Wasmtime: `47.0.2`

The measured async method ABI is `(i32, i32) -> i32` under
`[async-lower][method]descriptor.sync`, with `(i32) -> nil` resource drop and
the same waitable/subtask/context imports as the pinned dummy. The unit/error
completion uses the canonical component variant `result<_, error-code>`;
`[task-return]run` receives the component task-return pair. The test-only
cancel component uses `[async-lower][subtask-cancel]` and
`[task-return]cancel`.

The hand-authored WIT mirror must preserve the pinned package/version,
interface, resource receiver, and complete `error-code` member order. Its own
mirror hash is recorded separately and must never replace the upstream hash.

The focused ABI gate records current `wasm-tools 1.255.0` SHA-256
`6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`, legacy
`1.254.0` SHA-256
`cc1f862d69363aac2d4a88f01c414a2dcf10858632d0c0a45e93ff60503979d6`, the
regular mirror hash
`18ce7dc9efb991cd8e5f945797aea73edeed79f0cfc51ea664cb81537e54e719`, and the
test-only cancel mirror hash
`9898cd734708a2ab14760da706d69063e5cd6262a5e03d07d8eedd8074745f36`.

## Private WIT Shape

The probe world contains only `types` and `probe`:

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

`own<descriptor>` is WIT/Component metadata only. It does not add public Do
ownership syntax.

## Do Admission Shape

After the ABI and runtime gates pass, the only admitted source is:

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

Do keeps the ordinary `nil | SyncError` union. `Result<_, error-code>` is
private to the generated WIT/Component side. The analyzer rejects other
filesystem members, `Result<T,E>` source spelling, second awaits, branches,
loops, `defer`, arbitrary calls, borrowed/list/variant payloads, and multiple
children.

## Runtime and Cancellation

The Rust host uses a temporary local regular file, one Component and one
Wasmtime Store per mode, and an opaque descriptor carrying its `PathBuf`. The
matrix covers:

| Mode | Required observation |
| --- | --- |
| `ready` | one sync call, immediate unit success |
| `pending` | one pending poll, one external wake, one completion, unit success |
| `error` | explicit `io` or `no-entry`, never an implicit success |
| `cancel` | pending child cancellation, no duplicate completion, exact cleanup |

Every mode ends with one descriptor drop and `table-empty=true`. Cancellation
ends the guest task/future and does not undo a host sync already issued.
Because dropping a Wasmtime `call_concurrent` future does not hard-cancel a
guest task, the cancel row uses a test-only async control endpoint that invokes
the measured `[subtask-cancel]` path. That endpoint is not a Do surface or
registry descriptor.

The focused Rust gate observes, for hand-authored `ready`/`pending`/`error`/
`cancel` and generated `ready`/`pending`/`error`, respectively:

- ready: `host-calls=1`, `completion-polls=1`, `external-wakes=0`,
  `completions=1`, `future-drops=1`, `pending-future-drops=0`,
  `descriptor-drops=1`;
- pending: `host-calls=1`, `completion-polls=2`, `external-wakes=1`,
  `completions=1`, `future-drops=1`, `pending-future-drops=0`,
  `descriptor-drops=1`;
- error: the same one-poll/one-completion cleanup as ready, with `Err(no-entry)`;
- cancel: `host-calls=1`, `completion-polls=1`, `external-wakes=0`,
  `completions=0`, `future-drops=1`, `pending-future-drops=1`,
  `descriptor-drops=1`.

## Stop Conditions

The pinned no-go branch was not triggered: both toolchain paths accepted the
measured WIT/Core shape. For any future expansion, stop before registry/codegen
changes if the pinned tools reject the new WIT, the async import/task-return
contract is unstable, or the Rust matrix observes duplicate completion,
missing cleanup, or a non-empty resource table. Record the full diagnostic,
tool identity, and recovery condition in `doc/pending_blocked.md`.
