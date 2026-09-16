Verification Status: verified

# G5c `host_wit_marshalling_managed_record_lower` Row Evidence

## Scope

- Row: `host_wit_marshalling_managed_record_lower`
- Task: 14
- Profile: `H` (synchronous host/WIT)
- Run: `.tmp/g5c-full-cutover/task-14-host-wit-marshalling-managed-record-lower-verify-20260916-scRb3B`
- Gate HEAD: `f0c5a4477b530cf06f5a8f1da7c0abd21dcd680d`
- Branch: `main`
- Admitted shapes: the exact manifest-backed root records `{u32,string}` and
  `{u32,string,string}` through the ordinary GC host/WIT lower route, including
  the pinned multi-record compiler boundary.

The frozen rejection boundary remains general managed-record lower, arbitrary
or unpinned layouts, async/resource paths, borrowed payloads, and G5c cutover
beyond this row. The row gate did not widen a compiler matcher or add a public
type; ARC artifacts are retained only as the equivalence oracle.

## Verification

The row gate command was:

```text
bash src/build/test/check_gc_g5c_row.sh --row host_wit_marshalling_managed_record_lower --profile H --evidence-dir .tmp/g5c-full-cutover/task-14-host-wit-marshalling-managed-record-lower-verify-20260916-scRb3B
```

All expected outcomes matched the actual outcomes in the run's
`commands.log`:

- `check_gc_arc_inventory.sh --post-cutover`: expected `0`, actual `0`
- `check_gc_default_build_gate.sh`: expected `0`, actual `0`
- `check_gc_migration_evidence_test.sh`: expected `0`, actual `0`
- `check_gc_migration_inventory.sh`: expected `1`, actual `1`, pre-closure summary `complete_rows=15 pending_rows=3`
- 3 G5a host/component probes: expected `0`, actual `0` for every command
- 3 G5b equivalence probes: expected `0`, actual `0` for every command
- Positive artifacts passed GC-only, no-ARC, and canonical-boundary checks;
  Component parse/embed/new/validate chains passed.
- No admitted canonical import contains `(ref`; negative injected artifacts
  remained classified as negative evidence.

## Host And Equivalence Observations

| Shape | GC host observation | GC/ARC equivalence observation |
| --- | --- | --- |
| `{u32,string}` managed-field record lower | `code=7 label=hello write-calls=1 allocations=1 frees=1` | `code=7 label=hello allocations=1/1 frees=1/1 write-calls=1/1` |
| `{u32,string,string}` multi-managed record lower (manifest) | `code=7 label=hello note=world write-calls=1 allocations=2 frees=2` | `code=7 label=hello note=world allocations=2/2 frees=2/2 write-calls=1/1` |
| `{u32,string,string}` multi-managed record lower (compiler-generated boundary) | `code=7 label=hello note=world write-calls=1 allocations=2 frees=2` | `code=7 label=hello note=world allocations=2/2 frees=2/2 write-calls=1/1` |

These observations establish that each managed field is lowered through the
canonical scalar boundary and that host writes, allocation counts, and cleanup
counts match the ARC oracle for the admitted shapes.

## Resolved Commands

G5a host/component probes:

```text
examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_manifest_host.sh
examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_manifest_host.sh
examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_host.sh
```

G5b equivalence probes:

```text
examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_manifest_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_manifest_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_equivalence.sh
```

The individual `g5a-*` and `g5b-*` logs, artifact manifests, negative checks,
and toolchain probe are retained under the run directory.

## WIT Source Hashes

```text
25c898f0bebf78a7919c1686e9c54efc881045a7e1a920f010d170b25ba47c49  examples/gc-p3-runtime/marshal-record-managed-lower-manifest-source.wit
dd138009c628207e8208c8b4f4cddff44a66b59bfc55b52d743859a1ff9597a5  examples/gc-p3-runtime/marshal-record-managed-lower-assembly.wit
aaebd8fba91d18670ce0af1740acac8e36fd9dc3928b7e715284e24559e5a202  examples/gc-p3-runtime/marshal-record-managed-lower-multi-manifest-source.wit
8fbe5b6b6f0308c342315a7408cd544bb093c521d6e5abbfa69b272f30d01495  doc/wit/gc_marshal_record_managed_lower_multi_imports.wit
5298a69c43b2993fc1a694544bcf45a934d42061dee19b0e82b658d9681bab06  examples/gc-p3-runtime/marshal-record-managed-lower-multi-assembly.wit
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

The H-profile host gates, Component validation, managed-field payload
observations, GC/ARC equivalence, and preserved rejection boundary all passed.
This evidence authorizes only this row's G5c inventory field to move from
`pending` to `complete`; it does not authorize general managed-record lower,
generic async, resources, ownership, `Option`/`Result`, or any other row.
The next independent row is `future_stream_frames` (Task 15).
