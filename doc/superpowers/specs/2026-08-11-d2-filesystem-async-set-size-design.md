# D2 `descriptor.set-size` Async Filesystem Design

**Status:** approved bounded promotion direction. This document defines one
private, opt-in `descriptor.set-size` compiler/runtime slice. It does not widen
general filesystem async, generic producer lowering, or Do ownership syntax.

## Goal

Measure and admit the pinned WASI operation:

```wit
descriptor.set-size: async func(size: filesize) -> result<_, error-code>
```

The operation mutates the size of an already-open descriptor. The Do source
keeps the value-oriented union surface and represents the `filesize` argument
as `u64`; `own<descriptor>` exists only in generated WIT/Component metadata.

## Fixed Boundary

The only admitted Do source shape is:

```do
set_size_descriptor = @host_async_func(
    "wasi:filesystem/types@0.3.0-rc-2025-09-16",
    "descriptor.set-size",
    (File, u64) -> nil | SetSizeError
)
File = @wasi_resource("filesystem/types/descriptor", { .id i64 })
SetSizeError error = Io | NoEntry

run(file File, size u64) -> nil | SetSizeError {
    pending Future<nil | SetSizeError> = set_size_descriptor(file, size)
    return @await(pending)
}

start() {}
```

The target remains opt-in under `--p3-async-component`. The default emitter
continues to reject the method with `AsyncLoweringUnavailable`. Admission
requires one exact async host binding, one direct `@await`, a synchronous
empty `start`, and no branch, loop, defer, second await, extra host binding,
async root, borrowed payload, or arbitrary producer expression.

No public `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, lifetime, or
generic filesystem syntax is added. Do source spelling remains `nil | E`; the
private generated WIT uses `result<_, error-code>`.

## Pinned Inputs and ABI Probe

The source of truth is:

- `src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit`
- upstream `types.wit` SHA-256
  `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`
- `wasm-tools 1.255.0 (76e20611d 2026-07-30)`
- tool SHA-256
  `6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`
- Rust `1.97.1`, Wasmtime `47.0.2`, and Zig `0.16.0`

The hand-authored regular and cancel WIT mirrors contain only `filesize`, the
complete `error-code` enum, the descriptor resource, and the probe world. The
ABI script must hash the upstream source and both mirrors, run the current
`wasm-tools component embed --dummy-names legacy --async-callback` path with
`cm-async,cm-more-async-builtins`, parse the Core modules, assemble Components,
and validate that only `descriptor.set-size` is present.

The pinned probe measured the flat method shape as:

```text
[async-lower][method]descriptor.set-size:
  (i32, i64, i32) -> i32
```

The arguments are `descriptor:i32`, `size:i64`, and `result-area:i32`. The
unit/error completion uses the same two-word task-return convention as the
other unit Result slices. The regular mirror hash is
`f09241f8fcf4b94e1a684553b439b592f254c83c7d23a3708930040a2324c3f4`, the
cancel mirror hash is
`7030161e35a18fe40220cb2701864141a00a6c8d897cdfc8291839f2b742cc67`, and the
hand-authored Core template hashes are
`4a7a81286781abb7eabb7da30155f92bd330d5f8d9b5dfad371b09570bc05775` /
`b655945c0243a44c85c3e23919332b1fe64f4338526980a4dfe61525db170c7e`.
The script also validates the exact async callback, resource-drop,
subtask-cancel, and task-return imports. Any future mismatch is a no-go for
compiler admission and must be recorded with the tool identity and recovery
condition.

## Compiler Shape

Add a distinct `filesystem_set_size` registry row, analyzer, target, and fixed
WAT/WIT template. Do not make `filesystem_sync` or another existing target
accept extra arguments. The planner validates the exact locator/version,
`(File, u64) -> nil | SetSizeError` source types, descriptor resource identity,
one-await topology, and the measured ABI fields.

The generated Component exposes an owned descriptor receiver and `filesize`
argument at the WIT boundary. The Core template copies the `u64` size into the
frame before the host call, retains the receiver until unified termination,
reads the canonical unit/error result, and performs exactly-once subtask,
future, descriptor, and frame cleanup on ready, error, pending, cancel, and
Store-disposal paths.

Cancellation is cleanup-only. If the host mutation was issued before the
cancel signal, cancellation does not roll it back; the runtime gate must make
that boundary explicit.

## Runtime Matrix

The Rust/Wasmtime runner uses one temporary file descriptor per mode and
counts host calls, size values, polls, wakes, completions, future drops,
pending future drops, and descriptor drops:

| Row | Required observation |
| --- | --- |
| `ready` | one set-size call reaches the expected size and returns unit success |
| `pending` | the `u64` size survives one delayed wake and the host observes it unchanged |
| `error` | an invalid descriptor/path state returns an explicit `error-code` without fabricated success |
| `cancel` | test-only subtask cancellation drops the pending future once; no rollback is claimed |
| `early-drop` | Store disposal drops the pending host future once and leaves no live table entry |
| `repeat` | two independent size mutations complete with exactly-once cleanup |

The generated regular Component covers `ready`, `pending`, `error`, and
`repeat`; the hand-authored cancel Component covers explicit cancellation and
Store-disposal early drop, matching the established Wasmtime boundary.

## Stop Conditions

Stop before registry or codegen changes if the pinned tool rejects the WIT,
changes the method/task-return contract, cannot preserve the `u64` argument or
unit/error result area, or the Rust matrix observes duplicate completion,
missing cleanup, stale size data, a non-empty resource table, or an
unexplained mutation after cancellation. A green set-size gate authorizes only
this exact private shape and does not authorize neighboring filesystem methods
or generic lowering.
