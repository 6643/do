Verification Status: verified

# G5c `tuple_storage` Row Evidence

## Scope

- Row: `tuple_storage`
- Profile: `S` (synchronous GC)
- Run: `.tmp/g5c-full-cutover/task-8-tuple-storage-verify-20260916-182148-2449058`
- Commit: `567445056c3dbeb7e27b6a8fd24332ab60dfe564`
- Branch: `main`
- Current implementation boundary: `direct Tuple<text,[u8]> get/rewrite with one byte-list @set is admitted; local tuple bindings fail as UnknownGcSyncLocal and other Tuple/storage shapes fail as UnsupportedGcSyncExpression or UnsupportedGcSyncType`

The frozen row scope is the fixture
`examples/gc-p3-runtime/managed-tuple-text-bytes.do` and its probe
`examples/gc-p3-runtime/test_do_gc_managed_tuple_text_bytes.sh`.

The row gate did not widen this boundary or modify any route implementation.

## Verification

The row gate command was:

```text
bash src/build/test/check_gc_g5c_row.sh --row tuple_storage --profile S --evidence-dir .tmp/g5c-full-cutover/task-8-tuple-storage-verify-20260916-182148-2449058
```

All expected outcomes matched the actual outcomes in
`.tmp/g5c-full-cutover/task-8-tuple-storage-verify-20260916-182148-2449058/commands.log`:

- `check_gc_arc_inventory.sh --post-cutover`: expected `0`, actual `0`
- `check_gc_default_build_gate.sh`: expected `0`, actual `0`
- `check_gc_migration_evidence_test.sh`: expected `0`, actual `0`
- `check_gc_migration_inventory.sh`: expected `1`, actual `1`
- `test_do_gc_managed_tuple_text_bytes.sh`: expected `0`, actual `0`, observed `27815`
- `check_gc_semantic_equivalence.sh`: expected `0`, actual `0`, 26 rows passed, 0 pending

The pre-closure inventory summary was `complete_rows=15 pending_rows=9` with
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
`tuple_storage` G5c inventory field to move from `pending` to `complete`; it
does not authorize local tuple bindings, other Tuple/storage shapes,
host/WIT, async/resource, ownership, `Option`/`Result`, or any other row.
