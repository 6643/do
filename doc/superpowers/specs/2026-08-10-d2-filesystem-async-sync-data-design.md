# D2 `descriptor.sync-data` Async Filesystem Design

Date: 2026-08-10  
Status: bounded method-specific design; no generic filesystem async lowering

## Goal

Measure and, only if every pinned ABI and runtime cleanup gate is green,
privately promote one additional WASI filesystem async method:

```wit
descriptor.sync-data: async func() -> result<_, error-code>
```

The method synchronizes file data already issued to the host. Cancellation
ends the live Component task and releases still-owned guest values; it never
rolls back a filesystem effect that reached the host.

## Decision

Use a separate `filesystem-sync-data` manifest shape, source planner, WAT
template, and opt-in compiler target inside the existing
`--p3-async-component` route. The shape is intentionally separate from
`descriptor.sync`, even though both currently have a unit-success/error
result, so a future ABI drift cannot silently reuse the wrong descriptor.

The Do source remains ordinary opaque resource handles and a `nil | error`
union. WIT `own<descriptor>` and Component `result<_, error-code>` are
generated contract details only. This design adds no public `own<T>`,
`borrow<T>`, `ref<T>`, pointer, reference, lifetime, or generic `Future<T>`
syntax.

## Pinned Inputs

```text
filesystem package: wasi:filesystem@0.3.0-rc-2025-09-16
types source: src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit
types source sha256: 8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f
wasm-tools: 1.255.0 (76e20611d 2026-07-30)
wasm-tools sha256: 6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013
Rust: 1.97.1
Wasmtime: 47.0.2
Zig: 0.16.0
```

The probe must use the complete pinned `error-code` order. A changed source
hash, package revision, or method signature is a no-go before registry or
compiler changes.

## Private Source Contract

The only accepted source shape is:

```do
sync_data_descriptor = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.sync-data", (Dir) -> nil | SyncDataError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
SyncDataError error = Io | NoEntry

run(file Dir) -> nil {
    pending Future<nil | SyncDataError> = sync_data_descriptor(file)
    result nil | SyncDataError = @await(pending)
}

start() {}
```

The planner rejects an unregistered member, `@host_func`, any receiver other
than the exact `Dir` resource, any result other than `nil | SyncDataError`, a
second await, branches, loops, extra host bindings, an async root declaration,
or any payload/borrow/list/stream shape before WAT emission.

## ABI Probe Contract

The hand-authored regular and cancellation worlds contain only the pinned
`types.descriptor.sync-data` method and a private `probe.run` export. The
current tool must measure and the checked-in assertions must freeze:

- method import `[async-lower][method]descriptor.sync-data`;
- resource drop import `[resource-drop]descriptor`;
- root task-return/callback endpoints and the waitable/subtask/context imports;
- the receiver handle and completion-context core words;
- the unit-success/error-code Result tag and payload representation;
- source-order markers `[sync-data-call]`, `[sync-data-ready]`,
  `[sync-data-pending]`, `[sync-data-error]`, `[descriptor-drop]`.

The promotion contract expects the measured flat method shape
`(i32, i32) -> i32`, task-return `(i32, i32)`, and a Result payload with an
`i32` tag, no Ok payload, and one `i32` Err payload. If the current tool
measures anything else, retain the probe evidence as a no-go and do not add a
compiler descriptor.

## Runtime Matrix

The Rust/Wasmtime oracle and generated Component gate cover:

- ready unit success;
- pending with one external wake and one completion;
- terminal `Err(io)` without fabricated success;
- explicit Component subtask cancellation;
- started-future early drop, represented as whole-Store disposal because
  Wasmtime 47 does not cancel a guest task when only the host future is dropped;
- two independent ready calls on one live Store.

Every live-Store terminal row must observe exactly one host Future drop, one
descriptor drop, no duplicate completion, and an empty `ResourceTable`.
The Store-disposal row records `table-empty=not-applicable` and is not claimed
as guest cancellation evidence.

## Scope Boundary

This slice does not authorize `stat-at`, stream read/write/append, borrowed
descriptor methods, owned descriptor results, HTTP service worlds, arbitrary
producer expressions, generic async-call lowering, or public ownership syntax.
Each future method requires its own dated design, pinned WIT hash, canonical
WAT, positive/negative fixtures, Component validation, and Rust/Wasmtime
cleanup matrix.

## Acceptance

The slice is complete only when the ABI and Rust probes, compiler planner and
manifest tests, positive fixture `511`, negative fixtures `512`-`515`,
generated Component gate, full compiler/WASM/ReleaseSmall regression, docs,
`git diff --check`, and delivery checks are green. Existing bounded targets
must remain byte- and behavior-stable.
