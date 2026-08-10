# D2 `descriptor.metadata-hash-at` Private Promotion Design

Date: 2026-08-10  
Status: proposed bounded promotion; compiler admission remains unchanged until
the gates in this document pass

## Goal

Privately promote the independently measured WASI filesystem method
`descriptor.metadata-hash-at` through the existing `--p3-async-component`
route. The promotion must prove one exact mixed-input async shape, its path
lifetime boundary, and terminal cleanup in Rust/Wasmtime. It must not reopen
generic async lowering.

The pinned WIT operation is:

```wit
descriptor.metadata-hash-at: async func(
    path-flags: path-flags,
    path: string,
) -> result<metadata-hash-value, error-code>
```

## Decision

Use a new `filesystem_metadata_hash_at` manifest shape and a new
method-specific planner/emitter/template. Do not infer this operation from
`descriptor.metadata-hash`, `descriptor.stat`, or any generic string
lowering. Keep it behind the already existing `--p3-async-component` opt-in.
Ordinary `do build` and all generic async targets continue to reject async
lowering with `AsyncLoweringUnavailable` where they do today.

The Do source remains opaque resource handles plus ordinary union spelling. The
WIT `own<descriptor>` and `result<metadata-hash-value, error-code>` forms
are generated Component contract details only. This design adds no public
`Result<T,E>`, `own<T>`, `borrow<T>`, `ref<T>`, pointer, reference, or
lifetime syntax.

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

The already verified ABI probe freezes these additional identities:

```text
regular WIT mirror sha256: 95e24b70eeed89407706c18a6e4cd13a8bc4dce72d1e56638436b03287d23412
cancel WIT mirror sha256: aca9c5933786a00a2dd20b1ad1ddbb6d0a79ab5b3bdbd5bd61e14b100a3b6e0a
method import: [async-lower][method]descriptor.metadata-hash-at
method core type: (i32, i32, i32, i32, i32) -> i32
task return: (i32, i64, i64)
resource drop: [resource-drop]descriptor (i32) -> nil
string lowering: UTF-8 pointer/length
```

Any change to the pinned source, tool identity, method import, parameter order,
task-return words, record field order, or drop import is a no-go before
registry or compiler changes.

## Private Do Source Contract

The only admitted source shape is:

```do
metadata_hash_at = @host_async_func(
    "wasi:filesystem/types@0.3.0-rc-2025-09-16",
    "descriptor.metadata-hash-at",
    (Dir, u32, text) -> MetadataHash | HashError
)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
MetadataHash = @wasi_record("filesystem/types/metadata-hash-value", { lower u64, upper u64 })
HashError error = Io | NoEntry

run(file Dir, path_flags u32, path text) -> MetadataHash | HashError {
    pending Future<MetadataHash | HashError> = metadata_hash_at(file, path_flags, path)
    return @await(pending)
}

start() {}
```

Names of the binding, parameters, root, and pending local may vary. Types,
argument order, one host binding, and the straight-line operation sequence may
not. The planner rejects:

- `@host_func`, an unknown locator/member, or a second matching host binding;
- a receiver other than the exact `Dir` resource shell;
- path-flags other than `u32` or path other than `text`;
- any result other than `MetadataHash | HashError` with the exact record/error
  declarations;
- a second await, branch, loop, defer, child task, arbitrary producer
  expression, or async root;
- borrowed/owned path or resource payloads, lists, streams, variants, or any
  additional host operation.

The source union remains `MetadataHash | HashError`; `Result<...>` is never a
public Do type.

## Manifest Shape

The registry entry is separate from the existing
`filesystem_metadata_hash` entry and must validate every pinned fact:

```text
locator: wasi:filesystem/types@0.3.0-rc-2025-09-16
member: descriptor.metadata-hash-at
effect: async
params: descriptor, path-flags, string
result: Result<metadata-hash-value,error-code>
resource: null
canonical.core_params: i32, i32, i32, i32, i32
canonical.core_results: i32
canonical.completion_params: i32, i64, i64
canonical.completion: task-return
canonical.record_layout: metadata-hash-value, 16 bytes
  lower: i64 at 0
  upper: i64 at 8
canonical.async_import_name: [async-lower][method]descriptor.metadata-hash-at
```

The shape carries the receiver, path-flags source type, path source type,
record layout, result identity, and descriptor-drop import. The shape matcher
must fail closed if any canonical field or WIT identity drifts.

## Architecture and Data Flow

```mermaid
flowchart LR
  R[registry exact ABI] --> S[sema exact source shape]
  S --> P[metadata-hash-at planner]
  P --> F[frame WAT adapter]
  F --> C[Component assembly]
  C --> H[Rust/Wasmtime matrix]
```

The compiler changes are limited to:

- `p3_async_registry.json` and `p3_async_manifest.zig` for the exact shape;
- `sema_imports.zig` for the exact `(Dir, u32, text)` signature;
- a new `codegen_component_wasi_filesystem_metadata_hash_at.zig` adapter and
  `wasi_filesystem_metadata_hash_at_component_template.wat`;
- `codegen_component_async.zig` target dispatch and focused unit tests;
- positive and negative compile fixtures.

The adapter emits a fixed Component WIT world containing `types` and
`probe`. It does not emit unrelated filesystem methods and does not change
the generic target classifier for other descriptors.

## Frame and Path Lifetime

The private Core template uses the measured frame offsets:

```text
frame+0   waitable:i32
frame+4   descriptor:i32
frame+8   path-flags:i32
frame+12  path-ptr:i32
frame+16  path-len:i32
frame+20  status:i32
frame+24  result-tag:u8
frame+32  lower:u64
frame+40  upper:u64
frame+48  callback-subtask:i32
```

`start` passes descriptor, path-flags, path pointer, path length, and result
area in that order. The host async binding must copy the UTF-8 bytes into its
host-owned `String` before returning the future. The guest frame retains the
pointer and length as immutable call metadata and never reads the input after
the import has accepted it. The guest does not allocate a second arbitrary-size
path buffer and does not claim ownership of the caller's text storage.

The Rust runtime gate must include a pending future that reads the path only
after its first wake. The observed path must still be exact, including a
non-ASCII UTF-8 case. If the host cannot establish this copy boundary, compiler
promotion stops and the ABI-only probe remains the highest closed state.

The result area is read before any cleanup. `Ok` reads `lower` and `upper`;
an `Err` reads the canonical error byte/word and clears the unused second
return word. The descriptor is dropped exactly once on every live-Store
terminal row.

## Cancellation and Cleanup

The regular compiler target has no public cancel declaration. Cancellation is
covered by a test-only WIT/Core mirror that exports `cancel: async func()` and
uses the measured `[async-lower][subtask-cancel]` operation.

Terminal order is fixed:

1. observe the final result and drop the completed subtask when present;
2. release the owned descriptor exactly once;
3. drop the frame waitable and clear the async context;
4. invoke `[task-return]run` with the measured flat words;
5. finish the frame.

For explicit cancellation, the control endpoint cancels the pending subtask,
drops it only when the canonical status is terminal, and returns its own task
result. This is cleanup-only semantics. No filesystem operation is undone and
no rollback result is synthesized.

If a host-side future is dropped while pending, the runner records the known
Wasmtime 47 behavior as whole-Store disposal and marks `table-empty` as
`not-applicable`; it must not claim guest cancellation from future drop alone.

## Runtime Matrix

The Rust/Wasmtime runner must cover:

| Mode | Required evidence |
| --- | --- |
| `ready` | one call, immediate `Ok`, exact flags and UTF-8 path |
| `pending` | one wake, one completion, path copied before the delayed poll |
| `error` | explicit `Err(no-entry)` with no fabricated record |
| `cancel` | one subtask cancel, one pending future drop, one descriptor drop, no completion |
| `early-drop` | whole-Store disposal, pending future drop, `table-empty=not-applicable` |
| `repeat` | two independent calls with exact path/flags and exactly-once cleanup |

Every live-Store terminal row must end with one host future drop, one descriptor
drop, no duplicate task return, and an empty `ResourceTable`.

## Verification Gates

Promotion is complete only if all gates pass in order:

1. The existing ABI script still passes with pinned tool and hashes.
2. The Rust/Wasmtime matrix passes for the hand-authored regular and cancel
   components before compiler admission is changed.
3. Positive fixture `520` and negative fixtures `521`-`529` fail/accept at
   the intended sema/planner boundary, including second await, branch, loop,
   borrowed path, and async-root cases.
4. Registry, manifest, sema, target classification, adapter, WAT markers, and
   WIT output tests pass.
5. The compiler-generated Component embeds, assembles, validates, and matches
   the hand-authored ABI and runtime cleanup counters.
6. The full compiler regression, WASM regression, ReleaseSmall build, and
   documentation consistency checks pass.

Any failed gate retains `metadata-hash-at` as ABI-only and records the exact
failure in `doc/host_abi_blockers.md` and `doc/pending_blocked.md`.

## Alternatives

### A. Independent bounded promotion (recommended)

This keeps the mixed input shape, path copy boundary, and result layout
explicit. It has a finite file/test surface and a clear rollback path: remove
the new shape, adapter, fixtures, and runner without affecting existing
filesystem methods.

### B. Admission with borrowed pointer/length and no host-copy gate

This is smaller but leaves the async input lifetime unproved. A delayed host
future could observe released or mutated guest memory. It is acceptable only as
an ABI probe, not as compiler promotion.

### C. Generic filesystem async/string lowering

This would cover more methods but requires a general async frame allocator,
string ownership model, arbitrary result-area decoding, host-future cancellation,
and error/timeout policy. Those capabilities remain behind
`AsyncLoweringUnavailable` and are outside this slice.

## Non-Goals

This design does not authorize `stat-at`, arbitrary path APIs, generic
filesystem or HTTP async, arbitrary async-call lowering, borrowed descriptor
methods, public ownership syntax, pointer/reference/lifetime syntax, or host
rollback. Each additional WIT method requires its own pinned ABI, source shape,
runtime matrix, and dated design.
