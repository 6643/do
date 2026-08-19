# D2 descriptor.stat-at Async Filesystem Design

**Status:** approved bounded promotion direction. This document defines one
private, opt-in `descriptor.stat-at` compiler/runtime slice. It does not widen
general filesystem async, generic producer lowering, or Do ownership syntax.

## Goal

Measure and admit the exact WASI operation:

```wit
descriptor.stat-at: async func(
    path-flags: path-flags,
    path: string,
) -> result<descriptor-stat, error-code>
```

The operation is observational and returns the already-proven
`descriptor-stat` record. The new capability combines the path/string lowering
from `descriptor.metadata-hash-at` with the record/result lowering from
`descriptor.stat`, while keeping one direct await and one owned descriptor.

## Fixed Boundary

The Do source admission is one exact private shape:

```do
stat_at_descriptor = @host_async_func(
    "wasi:filesystem/types@0.3.0-rc-2025-09-16",
    "descriptor.stat-at",
    (Dir, u32, text) -> DescriptorStat | StatError
)
Datetime = @wasi_record("clocks/wall-clock/datetime", { seconds i64, nanoseconds u32 })
DescriptorStat = @wasi_record("filesystem/types/descriptor-stat", {
    .type i32,
    link_count u64,
    size u64,
    data_access_timestamp option<Datetime>,
    data_modification_timestamp option<Datetime>,
    status_change_timestamp option<Datetime>
})
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
StatError error = Io | NoEntry

run(file Dir, path_flags u32, path text) -> DescriptorStat | StatError {
    pending Future<DescriptorStat | StatError> =
        stat_at_descriptor(file, path_flags, path)
    return @await(pending)
}

start() {}
```

The target remains opt-in under `--p3-async-component`. The default emitter
continues to reject it with `AsyncLoweringUnavailable`. The planner rejects
unregistered or wrong-version members, non-`u32` flags, non-`text` paths,
record/layout drift, borrowed results, a second await, branch/loop/defer
topology, extra host bindings, a different resource, and an async root.

No `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, lifetime, or public
`Result<T,E>` syntax is added. WIT `own<descriptor>` remains a generated
Component boundary only.

## ABI Contract

The probe must pin the upstream filesystem source hash and the current
`wasm-tools 1.255.0` executable/hash before compiler admission. The expected
method shape is the five-argument async import used by `metadata-hash-at`:

```text
[async-lower][method]descriptor.stat-at:
  (i32, i32, i32, i32, i32) -> i32
```

The arguments are `descriptor`, `path-flags`, UTF-8 path pointer, UTF-8 path
length, and result-area pointer. The completion callback must be measured from
the current tool and must carry the same thirteen flat values as `descriptor.stat`:

```text
result-tag, descriptor-type, link-count, size,
access-presence, access-seconds, access-nanoseconds,
modification-presence, modification-seconds, modification-nanoseconds,
change-presence, change-seconds, change-nanoseconds
```

The exact frame offsets, result-area alignment, WIT mirror hashes, and Core
template hash are probe outputs, not assumed compatibility data. Any mismatch
stops promotion and records a no-go entry.

## Compiler Shape

Add a distinct registry lowering shape and target, rather than making
`filesystem_stat` accept extra arguments. The planner owns source token shape
validation and returns only the names needed by the fixed template. The WIT
emitter produces the `stat-at` method and a root `run` that owns the descriptor
and receives `path-flags` and `path: string`.

The generated Core template stores the path pointer/length until completion,
reads the canonical `descriptor-stat | error-code` result area, forwards all
thirteen completion values, and performs exactly-once subtask, descriptor, and
waitable cleanup. Cancellation is cleanup-only and never rolls back host work.

## Runtime Matrix

The Rust/Wasmtime runner owns the UTF-8 path in a `String` before returning its
future. It exercises one temporary directory descriptor and these rows:

| Row | Required observation |
| --- | --- |
| ready | known file path returns the full record and all option payloads |
| pending | non-ASCII path survives one delayed wake and decodes identically |
| error | missing path returns `Err(no-entry)` without fabricated record data |
| cancel | test-only subtask cancellation drops the pending future once |
| early-drop | whole-Store disposal drops the pending host future once |
| repeat | two paths complete independently with exactly-once cleanup |

The generated regular Component covers ready/pending/error/repeat. The
hand-authored cancel Component covers explicit cancel and Store-disposal
early-drop, matching the established Wasmtime 47 boundary.

## Stop Conditions

Stop before compiler registration if the pinned tool rejects the WIT, changes
the method/completion layout, cannot preserve the record result area, or the
Rust/Wasmtime matrix observes duplicate completion, stale option data, missing
future/resource cleanup, or a path ownership failure. A green method-specific
gate does not authorize any neighboring filesystem method or generic lowering.
