Verification Status: verified

# G5c `other_lists` Row Evidence

## Scope

- Row: `other_lists`
- Profile: `S` (synchronous GC)
- Run: `.tmp/g5c-full-cutover/task-4-other-lists-verify-20260916-173916-2346492`
- Commit: `d7cdb55d698593bf6cec925dea4ec7484a5855a9`
- Branch: `main`
- Current implementation boundary: `scalar list literal/fixed-index update and one-value @put slices for all registered scalar list types, bounded managed-element text-list @put, bounded inferred [u8]/[u32] body storage @put, and the bounded [[u8]] nested-list @put are admitted as G5a; spread/multi-value @put, dynamic producers, and other producer lists remain UnsupportedGcSyncType or UnsupportedGcSyncExpression`

The frozen row scope contains 25 fixtures and 20 probe scripts covering the
registered scalar lists, text lists, nested byte lists, scalar-list `@put`, and
inferred list storage. The exact fixture and probe lists remain in the TSV row
of `src/build/test/check_gc_migration_inventory.sh`.

The row gate did not widen this boundary or modify any route implementation.

## Verification

The row gate command was:

```text
bash src/build/test/check_gc_g5c_row.sh --row other_lists --profile S --evidence-dir .tmp/g5c-full-cutover/task-4-other-lists-verify-20260916-173916-2346492
```

All expected outcomes matched the actual outcomes in
`.tmp/g5c-full-cutover/task-4-other-lists-verify-20260916-173916-2346492/commands.log`:

- `check_gc_arc_inventory.sh --post-cutover`: expected `0`, actual `0`
- `check_gc_default_build_gate.sh`: expected `0`, actual `0`
- `check_gc_migration_evidence_test.sh`: expected `0`, actual `0`
- `check_gc_migration_inventory.sh`: expected `1`, actual `1`
- All 20 listed G5a probes: expected `0`, actual `0`
- `check_gc_semantic_equivalence.sh`: expected `0`, actual `0`, 26 rows passed, 0 pending

The pre-closure inventory summary was `complete_rows=15 pending_rows=13` with
the deliberate exit code `1`.

## Toolchain

The run used the pinned entries in `toolchain/toolchain.lock.json` and recorded
the complete probe and lock snapshot in `commands.log` and
`toolchain-probe.json`:

- `wasm-tools 1.258.0`, SHA-256 `282e0014d38daf233cb10fb92815813b339e2b7f8b4734f6698f0176c7d99424`
- `wasmtime 48.0.1`, SHA-256 `5a61e28214e31c2a52154103407bae5265a36732b3af502609e5ffe19f249463`
- `zig 0.16.0`, SHA-256 `2317bbb91798556d9d0f38aabdac23db83f0979b25f767259ae474546724087c`
- `rustc 1.97.1`, SHA-256 `d3a664c970a9fd8361b64194861bebc1ae37b9054e5ee3400dc1c9e691797eea`
- `cargo 1.97.1`, SHA-256 `828980723df339d62434390e9fb8ef8831036583343ae2316b7ab5646b5c1953`

## Closure decision

The S-profile gates, default GC route checks, equivalence check, and the
preserved rejection boundary all passed. This evidence authorizes only the
`other_lists` G5c inventory field to move from `pending` to `complete`; it does
not authorize spread or multi-value producers, dynamic producers, arbitrary
list shapes, host/WIT, async/resource, ownership, `Option`/`Result`, or any
other row.
