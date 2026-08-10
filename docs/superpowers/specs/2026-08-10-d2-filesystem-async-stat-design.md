# D2 descriptor.stat Async Filesystem Design

**Status:** the latest pinned Component ABI, the hand-authored terminal/cancel
oracle, and the exact private compiler slice are green. The compiler target is
opt-in and method-specific; generic filesystem async and host-future-drop
cancellation remain closed. Wasmtime 47 does not propagate a dropped host
`call_concurrent` future into a running guest task, so `early-drop` is measured
only as whole-Store disposal.

## Goal

Measure one private, method-specific async WASI filesystem operation:

~~~wit
descriptor.stat: async func() -> result<descriptor-stat, error-code>
~~~

The operation observes an existing descriptor and returns a record. It does not
perform a filesystem mutation. This slice is intentionally larger than the
completed scalar/unit methods because it exercises a record result, an enum
field, two 64-bit fields, three optional datetime records, a Result variant,
resource ownership, and cancellation cleanup.

This design does not add public Do own<T>, borrow<T>, ref<T>, lifetime,
pointer, or reference syntax. WIT own<descriptor> and
result<descriptor-stat, error-code> exist only in the generated Component
contract. The Do source remains an opaque resource handle plus ordinary record,
option, and nil | error-union types.

## Pinned Inputs

- Upstream source:
  src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/filesystem/types.wit
- Upstream source SHA-256:
  8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f
- WASI package/version:
  wasi:filesystem@0.3.0-rc-2025-09-16
- Method locator:
  wasi:filesystem/types@0.3.0-rc-2025-09-16
- Current tool:
  wasm-tools 1.255.0 (76e20611d 2026-07-30)
- Current tool SHA-256:
  6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013
- Rust:
  rustc 1.97.1 (8bab26f4f 2026-07-14)
- Wasmtime:
  wasmtime 47.0.2 (90fed3c6a 2026-07-21)
- Component features:
  cm-async,cm-more-async-builtins
- Regular WIT mirror SHA-256:
  4f5ee39cad9280cdcd308550978ba0006503f5952d61304fc5130a74df5ea121
- Cancel WIT mirror SHA-256:
  caf50d3fb78cca697ed05cbe02aa86794359ba1e8d576ba5156857d2ffb5af28
- Wall-clock WIT mirror SHA-256:
  6c6d8706c22c3f7548cfddf87cd176d37a6accc4eb8cc03d7b4fb2eaa06019e6

The upstream hash and both tool hashes are source/tool identity gates. A
hand-authored WIT mirror has a separate hash and cannot replace the upstream
source hash.

## WIT Shape

The probe mirrors the pinned types.wit definitions needed to preserve
canonical order:

- descriptor-type enum with all eight upstream members:
  unknown, block-device, character-device, directory, fifo,
  symbolic-link, regular-file, socket.
- descriptor-stat record fields in this exact order:
  %type: descriptor-type, link-count: link-count, size: filesize,
  data-access-timestamp: option<datetime>,
  data-modification-timestamp: option<datetime>,
  status-change-timestamp: option<datetime>.
- filesize = u64, link-count = u64, and the complete ordered upstream
  error-code enum.
- types.descriptor.stat as the only imported filesystem method.
- probe.run as:
  async func(file: own<descriptor>) -> result<descriptor-stat, error-code>.
- A cancel-only probe world adds cancel: async func() so the measured
  root `[subtask-cancel]` path can be exercised. It does not add a
  second filesystem method.

The WIT mirror also imports the pinned wall-clock datetime record required by
the filesystem source. The ABI gate rejects a mirror with omitted members,
reordered enum/record fields, or a different package/version.

## Measurement Contract

The ABI gate runs the current tool before admitting either hand-authored Core
template:

~~~bash
WASM_TOOLS_EXPECT_VERSION='wasm-tools 1.255.0 (76e20611d 2026-07-30)' \
  bash examples/p3-runtime/test_d2_wasi_filesystem_stat_abi.sh
~~~

The dummy Core metadata from `wasm-tools 1.255.0` is:

- `[async-lower][method]descriptor.stat`: `(i32, i32) -> i32`.
- `[resource-drop]descriptor`: `(i32) -> nil`.
- `[task-return]run`: `(i32, i32, i64, i64, i32, i64, i32, i32, i64, i32, i32, i64, i32)`.
- The callback for `run`: `(i32, i32, i32) -> i32`.
- The cancel world adds `[task-return]cancel: () -> nil` and root
  `[subtask-cancel]: (i32) -> i32`.

The task-return flat order is fixed as follows:

~~~text
result-tag,
descriptor-type,
link-count,
size,
access-presence, access-seconds, access-nanoseconds,
modification-presence, modification-seconds, modification-nanoseconds,
change-presence, change-seconds, change-nanoseconds
~~~

The method context/result-area pointer is the hand-authored frame address plus
8. The canonical result area is not a flat `i32` tuple: its result tag is a
`u8` at `frame+8`, and the aligned payload starts at `frame+16`. The enum
discriminants in the payload are `u8` values (`regular-file=6`; `no-entry=19`).
The three option presence bits are also `u8`; their datetime payloads are
aligned as `u64` seconds followed by `u32` nanoseconds. For an error result,
the error code is at `frame+16` and record payload bytes are cleared. For a
success result, all three option payloads are returned.

The probe frame is deliberately explicit and stable:

~~~text
0 waitable:i32, 4 descriptor:i32,
8 result-tag:u8, 16 descriptor-type:u8, 24 link-count:u64, 32 size:u64,
40/48/56 access option (presence:u8, seconds:u64, nanoseconds:u32),
64/72/80 modification option,
88/96/104 change option,
112 status:i32, 116 callback-subtask-handle:i32.
~~~

The frame allocation is 128 bytes. `status` stores the method readiness code;
the callback's second argument is the real subtask handle and is saved at
`frame+116`. The callback's third argument is a runtime status such as
`Returned`, not an `error-code` payload. On the explicit-cancel callback path,
the cancel template may copy that status only into the cleanup task-return
payload; it is never exposed as a business error result. Both templates carry markers for the
call, result area, option presence, ready, pending, error, descriptor drop, and
cancellation paths. The gate parses and validates both Core modules, embeds
each with its matching WIT world, creates a Component, validates it with
`cm-async,cm-more-async-builtins`, and checks the printed Component/WIT for the
exact method set. Only `wasm-tools 1.255.0` is supported; an ABI change requires
updating the probe and compiler together, not retaining an older compatibility
path.

## Do Admission Shape

Only after the ABI and runtime gates are green, the private compiler target may
admit this exact source shape:

~~~do
stat_descriptor = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.stat", (Dir) -> DescriptorStat | StatError)
Datetime = @wasi_record("clocks/wall-clock/datetime", { seconds i64, nanoseconds u32 })
DescriptorStat = @wasi_record("filesystem/types/descriptor-stat", { .type i32, link_count u64, size u64, data_access_timestamp option<Datetime>, data_modification_timestamp option<Datetime>, status_change_timestamp option<Datetime> })
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
StatError error = Io | NoEntry

run(file Dir) -> DescriptorStat | StatError {
    pending Future<DescriptorStat | StatError> = stat_descriptor(file)
    return @await(pending)
}

start() {}
~~~

The field names/types/order above are fixed. If the measured WIT record cannot
map to this Do record without widening generic record/option lowering, the
compiler admission remains closed and the hand-authored probe is the terminal
deliverable.

The default compiler path continues to reject this source before WAT. The
opt-in target is method-specific and rejects extra host bindings, another
filesystem member, Result<T,E> source spelling, a borrowed result, a second
await, branches, loops, defer, an async root, or a nonmatching resource
declaration.

## Runtime Oracle

The Rust/Wasmtime runner uses a temporary regular file below
DO_D2_FILESYSTEM_ROOT and one Component/Store per mode.

| Mode | Host behavior | Required observation |
| --- | --- | --- |
| ready | immediate stat | regular-file record, all expected scalar fields |
| pending | one pending poll then one external wake | one completion and exact record decode |
| error | invalid/closed descriptor path | Err(no-entry), no fabricated payload |
| cancel | pending future followed by test-only subtask cancel | no completion, pending future dropped once |
| early-drop | abandon a live call, then dispose the whole Wasmtime Store | one pending future drop; `table-empty` and Component resource-drop are not applicable |
| repeat | two sequential stats over known files | independent result cleanup and no stale fields |

Every terminal/cancel/repeat row must report host-calls, completion-polls,
external-wakes, completions, future-drops, pending-future-drops,
descriptor-drops, decoded record fields, option presence bits, and
table-empty=true. The early-drop row reports `result=store-discarded` and
`table-empty=not-applicable` because the Store is intentionally destroyed.

## Observed Runtime Output

Fresh gates on 2026-08-10 used only:

~~~text
wasm-tools 1.255.0 (76e20611d 2026-07-30)
sha256=6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013
mode=ready result=Ok descriptor-type=regular-file link-count=1 size=4096 access=Some(100,1) modification=Some(101,2) change=Some(102,3) host-calls=1 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true
mode=pending result=Ok descriptor-type=regular-file link-count=1 size=4096 access=Some(100,1) modification=Some(101,2) change=Some(102,3) host-calls=1 completion-polls=2 external-wakes=1 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true
mode=error result=Err(no-entry) options=none host-calls=1 completion-polls=1 external-wakes=0 completions=1 future-drops=1 pending-future-drops=0 descriptor-drops=1 table-empty=true
mode=cancel result=cancelled host-calls=1 completion-polls=1 external-wakes=0 completions=0 future-drops=1 pending-future-drops=1 descriptor-drops=1 table-empty=true
mode=early-drop result=store-discarded host-calls=1 completion-polls=2 external-wakes=0 completions=0 future-drops=1 pending-future-drops=1 descriptor-drops=0 table-empty=not-applicable
mode=repeat results=Ok,Ok host-calls=2 completion-polls=2 external-wakes=0 completions=2 future-drops=2 pending-future-drops=0 descriptor-drops=2 table-empty=true
~~~

## Compiler Promotion Evidence

The exact Do slice is admitted only through
`--p3-wasi-filesystem-stat-component`:

~~~bash
bash examples/p3-runtime/test_do_wasi_filesystem_stat.sh
~~~

The default build of fixture `498` fails with `AsyncLoweringUnavailable` and
does not write WAT. The opt-in generated Core WAT is byte-identical to the
checked-in template, SHA-256
`b7aee0221318c857817859c5e849fa98da9909c2151b09c6dea9b964c986a69a`, and the
generated WIT emitted by the compiler is pinned at SHA-256
`4a2e5055c2ec06c772660b211c3e3ab3e3e15d8b5931c8e7def804e56d5175da`.
The generated WIT is embedded with the pinned wall-clock dependency, assembled
with `wasm-tools component new --skip-validation`, validated with
`cm-async,cm-more-async-builtins`, and checked for the exact stat method,
descriptor drop, task-return, record, enum, and option metadata. Fixtures
`499`-`510` reject before WAT for locator/version, signature, layout, ownership,
topology, and async-root drift.

The generated regular Component passes the Rust/Wasmtime `ready`, `pending`,
`error`, and `repeat` rows with the same decoded record, option presence,
completion, future-drop, descriptor-drop, and `table-empty=true` observations
as the hand-authored oracle. The cancel and whole-Store early-drop rows remain
the hand-authored cancel-world oracle because the admitted Do source has no
cancel export; this does not widen the compiler contract or prove generic
host-future cancellation.

The ownership invariant is:

1. run receives one owned descriptor resource.
2. The async method borrows the receiver according to the measured WIT ABI.
3. The result record contains no resource handles.
4. Terminal and explicit-cancel paths drop the owned descriptor exactly once.
5. Explicit Component cancellation drops live async state exactly once and
   never rolls back the already-issued observational stat operation.
6. A dropped `call_concurrent` future alone is not a cancellation mechanism in
   Wasmtime 47; the hard-cancel probe must destroy the whole Store and must not
   claim Component-level descriptor cleanup.

### Early-drop boundary

Wasmtime 47 documents that dropping the future returned by
`TypedFunc::call_concurrent` relinquishes the result but leaves the guest task
running. The only hard-cancel operation available to this host API is dropping
the Store. The runner therefore uses a separate `early-drop` mode that starts
the pending stat, drops the call future, destroys the Store, and observes one
pending host future drop. The regular `cancel` Component remains the proof for
`[async-lower][subtask-cancel]`, descriptor drop, and an empty `ResourceTable`.
No compiler or runtime contract may infer guest cancellation from a host future
drop until Wasmtime exposes task cancellation for `call_concurrent`.

## Stop Conditions

Stop before registry, sema, planner, or emitter changes when any condition holds:

- Either pinned wasm-tools version/hash differs from the expected identity.
- Either pinned tool rejects the WIT or produces incompatible method/task-return
  metadata.
- The result record layout is rejected or unstable in the pinned current tool.
- The measured optional datetime layout cannot be represented by the bounded Do
  record contract.
- Rust/Wasmtime observes duplicate completion, missing terminal/cancel cleanup,
  a non-empty `ResourceTable` after a terminal/cancel row, a duplicate
  descriptor drop, or a cancellation semantic that fabricates a result.
- The early-drop row reports anything other than one pending host-future drop
  after Store disposal, or is mistaken for Component-level resource cleanup.
- Generated output imports a filesystem method other than descriptor.stat.

A no-go record must preserve the command, tool identity, stderr, hashes, impact,
and recovery condition in doc/pending_blocked.md. A green probe authorizes only
the separate private compiler promotion tasks; it does not authorize general
filesystem async, arbitrary producer expressions, public ownership syntax,
borrowed futures/streams, or external HTTP lowering.
