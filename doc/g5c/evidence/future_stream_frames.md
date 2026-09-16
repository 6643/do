Verification Status: verified

# G5c `future_stream_frames` Row Evidence

## Scope

- Row: `future_stream_frames`
- Task: 15
- Profile: `A` (Future/resource)
- Run: `.tmp/g5c-full-cutover/task-15-future-stream-frames-verify-20260916-0aBMee`
- Gate HEAD: `21f6ed16f5f90023e4b930c8f534262cd8b0d07f`
- Branch: `main`
- Admitted shape: the bounded `--p3-wait-for-component` path for two sequential
  `Future<nil>` awaits, with a GC-traced frame/table and a linear-memory oracle.

The frozen rejection boundary remains ordinary GC sync async admission
(`UnsupportedGcSyncAsync`), generic async lowering, general `Stream` shapes,
host-future cancellation, and G5c cutover beyond this row. The bounded frame
gate does not authorize public ownership/reference syntax or any other async
producer shape.

## Verification

The row gate command was:

```text
bash src/build/test/check_gc_g5c_row.sh --row future_stream_frames --profile A --evidence-dir .tmp/g5c-full-cutover/task-15-future-stream-frames-verify-20260916-0aBMee
```

All expected outcomes matched the actual outcomes in the run's
`commands.log`:

- `check_gc_arc_inventory.sh --post-cutover`: expected `0`, actual `0`
- `check_gc_default_build_gate.sh`: expected `0`, actual `0`
- `check_gc_migration_evidence_test.sh`: expected `0`, actual `0`
- `check_gc_migration_inventory.sh`: expected `1`, actual `1`, pre-closure summary `complete_rows=15 pending_rows=2`
- `test_gc_async_frame_component.sh`: expected `0`, actual `0`
- `test_gc_async_frame_equivalence.sh`: expected `0`, actual `0`
- Positive artifacts passed GC-only, no-ARC, and artifact-boundary checks;
  both GC and linear Component chains passed validation.

The ordinary build rejection was also captured in the same run directory:

```text
DO_LIB_ROOT=./lib ./bin/do build examples/p3-runtime/async-call-component.do -o ordinary-async.wat
ordinary_async_expected_exit=nonzero actual_exit=1
error[AsyncLoweringUnavailable]: async 声明已通过前端检查，但 resumable lowering 尚未实现
```

No ordinary async WAT was produced. This preserves the default fail-closed
boundary while the explicit Component target remains available.

## GC Frame And Boundary Markers

The generated `two-await.wat` contains the following GC frame/table markers:

```text
(type $async-frame (struct ...))
(table $async-frames 0 (ref null $async-frame))
table.get $async-frames
struct.get $async-frame $waitable-set
```

The generated path has no `global $frame-next` linear-memory frame allocator,
and the Component boundary contains no GC reference payload. The linear oracle
uses the same WIT contract and is used only for backend-neutral observations.

## Lifecycle And Equivalence Observations

The GC and linear backends produced identical records for every admitted case:

| Case | Observation |
| --- | --- |
| `pending` | `pending-polls=4 external-wakes=4 completions=4` |
| `error` | `host-errors=1 completions=0` |
| `cancel` | `host-calls=1 cancelled=1` |
| `early-drop` | `host-calls=0 cancelled=1` |
| `repeat` | `runs=2 pending-polls=8 external-wakes=8 completions=8` |
| `ready` | `status=unsupported-sync-completion` for both GC and linear backends |

The equivalence gate ended with:

```text
GC/linear Future frame equivalence passed rows=1 ready=unsupported-sync-completion pending-polls=4 external-wakes=4 completions=4
```

The ready case intentionally rejects synchronous completion for this bounded
resumable path; it is not silently treated as a normal synchronous call.

## Resolved Commands

```text
examples/gc-p3-runtime/test_gc_async_frame_component.sh
examples/gc-p3-runtime/test_gc_async_frame_equivalence.sh
```

The individual G5a/G5b logs, printed WAT artifacts, artifact manifests,
negative checks, and toolchain probe remain under the run directory.

## Source Hashes

```text
cf1dc8004429334279dfa520da5ac7d980e860f07ccc19228f1425a3382b26c4  examples/p3-runtime/two-await-component.do
acac12d41ea369f92e2fa64d78c1a18f84cf78a73050d85860f15fa230d7e310  examples/gc-p3-runtime/async-frame-linear-oracle.wat
```

## Toolchain

The run used the pinned entries in `toolchain/toolchain.lock.json`:

- `wasm-tools 1.258.0`, SHA-256 `282e0014d38daf233cb10fb92815813b339e2b7f8b4734f6698f0176c7d99424`
- `wasmtime 48.0.1`, SHA-256 `5a61e28214e31c2a52154103407bae5265a36732b3af502609e5ffe19f249463`
- `zig 0.16.0`, SHA-256 `2317bbb91798556d9d0f38aabdac23db83f0979b25f767259ae474546724087c`
- `rustc 1.97.1`, SHA-256 `d3a664c970a9fd8361b64194861bebc1ae37b9054e5ee3400dc1c9e691797eea`
- `cargo 1.97.1`, SHA-256 `828980723df339d62434390e9fb8ef8831036583343ae2316b7ab5646b5c1953`

The complete lock snapshot and probe output remain in `commands.log` and
`toolchain-probe.json`.

## Closure Decision

The A-profile frame/table gate, GC/linear lifecycle equivalence, explicit ready
rejection boundary, ordinary-build `AsyncLoweringUnavailable` guard, and
preserved rejection boundary all passed. This evidence authorizes only this
row's G5c inventory field to move from `pending` to `complete`; it does not
authorize generic async, general Stream, host-future cancellation, resources,
ownership, `Option`/`Result`, or any other row. The next independent row is
`resource_terminal_cleanup` (Task 16).
