# D2 `descriptor.open-at` Async Filesystem Design

**Status:** approved bounded promotion direction. This document defines one
private, opt-in `descriptor.open-at` compiler/runtime slice. It does not widen
general filesystem async, generic producer lowering, or Do ownership syntax.

## Goal

Measure and admit the pinned WASI operation:

```wit
descriptor.open-at: async func(
    path-flags: path-flags,
    path: string,
    open-flags: open-flags,
    descriptor-flags: descriptor-flags,
) -> result<descriptor, error-code>
```

The operation creates or opens a child descriptor relative to an opaque parent
directory. The Do source remains value-oriented and uses ordinary union
syntax; `own<descriptor>` is generated only at the Component boundary.

## Fixed Boundary

The only admitted Do source shape is:

```do
open_at_descriptor = @host_async_func(
    "wasi:filesystem/types@0.3.0-rc-2025-09-16",
    "descriptor.open-at",
    (Dir, u32, text, u32, u32) -> File | OpenError
)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
File = @wasi_resource("filesystem/types/descriptor", { .id i64 })
OpenError error = Io | NoEntry

run(root Dir, path_flags u32, path text, open_flags u32, descriptor_flags u32) -> File | OpenError {
    pending Future<File | OpenError> = open_at_descriptor(root, path_flags, path, open_flags, descriptor_flags)
    return @await(pending)
}

start() {}
```

The target remains opt-in under `--p3-async-component`. The default emitter
continues to reject it with `AsyncLoweringUnavailable`. The planner rejects an
unregistered or wrong-version member, wrong arity or scalar types, a borrowed
or non-resource result, `Result<T,E>` source spelling, a second await,
branches, loops, defer, extra host bindings, a different resource declaration,
or an async root.

No public `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, lifetime, or
generic filesystem syntax is added.

## Pinned Inputs and ABI Probe

The source of truth is:

- `src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit`
- SHA-256 `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`
- `wasm-tools 1.255.0 (76e20611d 2026-07-30)`
- Tool SHA-256 `6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`
- Regular WIT mirror SHA-256 `1e5f9131387015c4e650a64e02bb9f112d8266f4755aa6b605af038407ef807a`
- Cancel WIT mirror SHA-256 `1c48fba03b569d91617efd834232fcccc553ca3001ffb0e0834b4134f93e4f52`

The hand-authored WIT mirrors are checked by hash and must contain only the
flags, error-code, descriptor resource, and probe world needed by this slice.
The ABI script runs `component embed --dummy-names legacy --async-callback -t`
with `cm-async,cm-more-async-builtins`, parses and validates both regular and
cancel Core probes, and assembles Components before compiler admission.

The current tool lowers the method to an indirect async ABI because the
receiver plus four logical parameters exceed the pinned four-flat-parameter
limit:

```text
[async-lower][method]descriptor.open-at:
  (params-ptr, result-area) -> i32
```

The indirect parameter block contains the receiver, the two flags records, and
the UTF-8 path pointer/length using the canonical memory layout. The result
area contains the `result<descriptor,error-code>` tag and payload. The task
return is two `i32` values: the result tag and the owned descriptor handle or
error discriminant. The probe, rather than an assumed compatibility rule,
records all offsets and discriminant meanings. Any mismatch is a stop
condition.

## Ownership and Cancellation

The parent `Dir` is owned by the Do `run` parameter and is released exactly
once on every terminal path. A successful `open-at` result transfers one child
descriptor to the result arm; the caller then owns that `File`. An error result
returns no child resource. The result-area is read before dropping the parent,
and the generated Component result owns the child handle until its post-return
cleanup.

The host adapter copies the UTF-8 path and flag values before returning its
future. The future never retains a guest pointer. Cancellation is cleanup-only:
guest waitables, subtasks, copied path storage, and descriptor handles are
released, while an already-issued host open is not rolled back. Whole-Store
early-drop is measured separately because the pinned Wasmtime boundary does not
turn it into a Component task cancellation.

## Compiler Shape

Add a distinct registry `filesystem_open_at` lowering shape, a method-specific
target, and `codegen_component_wasi_filesystem_open_at.zig` with a fixed WIT and
Core template. Reuse only the path lowering and resource cleanup helpers that
are already measured by `metadata-hash-at` and `stat-at`; do not make either
existing shape accept extra arguments.

The planner validates the exact host declaration, opaque `Dir`/`File` resource
shells, the one direct `@await`, synchronous empty `start`, and linear control
flow. The emitter returns the fixed template only after the manifest row and
planner both match.

## Runtime Matrix

The Rust/Wasmtime runner uses one temporary directory and a host state with a
`ResourceTable`, copied paths, counters, and exactly-once drop assertions:

| Mode | Required observation |
| --- | --- |
| ready | existing file returns `Ok(File)` and the parent is dropped once |
| pending | non-ASCII path survives one delayed wake and returns `Ok(File)` |
| error | missing path returns `Err(no-entry)` with no child descriptor |
| cancel | test-only subtask cancellation has no completion and one pending future drop |
| early-drop | whole-Store disposal drops the pending future; table status is not applicable |
| repeat | two independent opens complete and child/parent drops are exactly once |

The regular generated Component covers ready, pending, error, and repeat. A
hand-authored cancel Component covers explicit cancel and Store-disposal
early-drop, matching the existing Wasmtime 47 oracle boundary.

## Acceptance and Stop Conditions

Acceptance requires the ABI script, focused Zig manifest/planner tests, all new
compile fixtures, generated WIT/Core Component validation, the Rust matrix, and
the full `src/build/test/run_tests.sh` suite to pass with the pinned tools.

Stop before registration if the pinned tool changes the method/task-return
shape, the result-area cannot preserve owned-resource/error distinction, path
copy is not proven, or any runtime row observes duplicate/missing cleanup.
No neighboring filesystem method is admitted as a compatibility fallback.
