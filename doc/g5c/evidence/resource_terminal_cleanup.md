Verification Status: verified

# G5c `resource_terminal_cleanup` Row Evidence

## Scope

- Row: `resource_terminal_cleanup`
- Task: 16
- Profile: `A` (Future/resource)
- Run: `.tmp/g5c-full-cutover/task-16-resource-terminal-cleanup-verify-20260916-AnWVnQ`
- Gate HEAD: `d7168c125300643c38ea9e72f744bb3f68eabcb2`
- Branch: `main`
- Admitted shape: the bounded async resource `Result` terminal paths for
  `HttpRequest`/`HttpResponse`, including pending, ready, error, cancellation,
  early-drop, and repeat observations, with GC/linear backend-neutral checks.

The frozen rejection boundary remains ordinary GC sync resource admission
(`UnsupportedGcSyncAggregate` or `UnsupportedGcSyncType`), generic resources,
borrowed payloads, and G5c default routing beyond this row. The gate does not
add public `own<T>`, `borrow<T>`, `ref<T>`, `Option`, or `Result` syntax.

## Verification

The row gate command was:

```text
bash src/build/test/check_gc_g5c_row.sh --row resource_terminal_cleanup --profile A --evidence-dir .tmp/g5c-full-cutover/task-16-resource-terminal-cleanup-verify-20260916-AnWVnQ
```

All expected outcomes matched the actual outcomes in the run's
`commands.log`:

- `check_gc_arc_inventory.sh --post-cutover`: expected `0`, actual `0`
- `check_gc_default_build_gate.sh`: expected `0`, actual `0`
- `check_gc_migration_evidence_test.sh`: expected `0`, actual `0`
- `check_gc_migration_inventory.sh`: expected `1`, actual `1`, pre-closure summary `complete_rows=15 pending_rows=1`
- `test_gc_resource_terminal_cleanup.sh`: expected `0`, actual `0`
- `test_rust_resource_cancellation_shape.sh`: expected `0`, actual `0`
- Generated and oracle Component chains parsed, embedded, created, and
  validated with `component-async`.
- Positive artifacts passed GC-only/no-ARC checks; negative boundary artifacts
  remained classified as negative evidence.

## Terminal Lifecycle Observations

The generated GC route and the linear oracle produced identical records:

| Case | Request consumed | Response create | Response drop | Pending polls | Pending future drops | ResourceTable |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `pending` | 2 | 2 | 2 | - | - | `table-empty=true` |
| `ready` | 2 | 2 | 2 | - | - | `table-empty=true` |
| `error` | 2 | 0 | 0 | - | - | `table-empty=true` |
| `repeat` | 4 | 4 | 4 | - | - | `table-empty=true` |
| `cancel` | 1 | 0 | 0 | 1 | 1 | `table-empty=true` |
| `early-drop` | 0 | 0 | 0 | 0 | 0 | `table-empty=true` |

Every case emitted a matching GC and linear record, followed by
`resource lifecycle equivalence case=<case> passed`. The host runner also
reported `Rust P3 async resource cancellation probe passed` and
`pinned resource Result cancellation runtime probe passed`.

The cancellation terminal state is explicit: the pending subtask is canceled,
the pending future is dropped exactly once, resource handles are removed from
the table, and no response is created or dropped after cancellation. Early
drop consumes neither the request nor a pending future and leaves the table
empty.

## No-Rollback Boundary

Cancellation follows the established terminal protocol and does not undo an
external effect. The generated and probe WATs contain the explicit
`[subtask-cancel]`/`[subtask-drop]` and resource-drop imports, but no rollback,
restore, or compensation operation. The gate therefore records cancellation
and cleanup as terminal observations only; it makes no claim that an already
performed host-side effect is reversible.

## Resolved Commands

```text
examples/gc-p3-runtime/test_gc_resource_terminal_cleanup.sh
examples/p3-runtime/test_rust_resource_cancellation_shape.sh
```

The individual G5a/G5b logs, generated and oracle printed WAT, artifact
manifests, negative checks, and toolchain probe remain under the run directory.

## Source Hashes

```text
1e3638548a5f798b7c8b53d448e5a0ae97a539740ff4e25def7db3dd48be73f2  examples/p3-runtime/async-resource-result-component.do
e46a4495ba814722eccc5b304301a8116300fbee6e481e03797d60fb9fb0bdad  examples/p3-runtime/async-resource-result-cancel-component.do
fc6d27c62bc9d92a305c8f917c5a0f458c487721007d51c4a574347f85e9fa2f  src/build/p3_async_resource_probe.wit
fd4af34ecdc446d129c8b824e798e6cc266d00823370dd93acc06fbddceee51a  examples/p3-runtime/resource-result-cancel-probe.wit
fd4ee07a50b94ef77d6c80415e20fb4141f8243e4142202d135dcd41447f0a17  examples/p3-runtime/resource-result-cancel-probe.wat
26171223a40d1fade8a752c616cebdf3598aa37bdc20bb2cce3d2a7b533fc30b  examples/gc-p3-runtime/async-resource-result-linear-oracle.wat
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

The A-profile Component gate, ready/pending/error/repeat terminal observations,
cancellation and early-drop cleanup, exactly-once counters, terminal table
state, no-rollback boundary, and preserved rejection boundary all passed. This
evidence authorizes this row's G5c inventory field to move from `pending` to
`complete`; it does not authorize generic resources, borrowed payloads,
ownership syntax, `Option`/`Result` syntax, or any other capability.
