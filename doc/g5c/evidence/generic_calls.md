Verification Status: verified

# G5c `generic_calls` Row Evidence

## Scope

- Row: `generic_calls`
- Profile: `S` (synchronous GC)
- Run: `.tmp/g5c-full-cutover/task-10-generic-calls-verify-20260916-183524-2478919`
- Commit: `bf2189c838bbae8fddbac9bc944ca185c71708db`
- Branch: `main`
- Current implementation boundary: `resolved generic managed identity has typed GC and compiled-test equivalence evidence; generic field-update, layout instantiation, resources, and unresolved bindings remain outside admission`

The frozen row scope is the fixture
`examples/gc-p3-runtime/generic-managed-identity.do` and its probe
`examples/gc-p3-runtime/test_do_gc_generic_managed_identity.sh`.

The row gate did not widen this boundary or modify any route implementation.

## Verification

The row gate command was:

```text
bash src/build/test/check_gc_g5c_row.sh --row generic_calls --profile S --evidence-dir .tmp/g5c-full-cutover/task-10-generic-calls-verify-20260916-183524-2478919
```

All expected outcomes matched the actual outcomes in
`.tmp/g5c-full-cutover/task-10-generic-calls-verify-20260916-183524-2478919/commands.log`:

- `check_gc_arc_inventory.sh --post-cutover`: expected `0`, actual `0`
- `check_gc_default_build_gate.sh`: expected `0`, actual `0`
- `check_gc_migration_evidence_test.sh`: expected `0`, actual `0`
- `check_gc_migration_inventory.sh`: expected `1`, actual `1`
- `test_do_gc_generic_managed_identity.sh`: expected `0`, actual `0`, observed `27815`
- `check_gc_semantic_equivalence.sh`: expected `0`, actual `0`, 26 rows passed, 0 pending

The pre-closure inventory summary was `complete_rows=15 pending_rows=7` with
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
`generic_calls` G5c inventory field to move from `pending` to `complete`; it
does not authorize generic field updates, layout instantiation, resources,
unresolved bindings, host/WIT, async/resource, ownership, `Option`/`Result`,
or any other row.
