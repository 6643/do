Verification Status: verified

# G5c `host_wit_marshalling` Row Evidence

## Scope

- Row: `host_wit_marshalling`
- Task: 13
- Profile: `H` (synchronous host/WIT)
- Run: `.tmp/g5c-full-cutover/task-13-host-wit-marshalling-verify-20260916-wYWVzu`
- Gate HEAD: `8c903425b61a775bfa62bee2aa735146d8555c03`
- Runner fix commit: `3f52870` (accept WIT package-directory sources in the H-chain parser)
- Branch: `main`
- Current implementation boundary: `manifest-backed WASI random list<u8> lift, text lower, list<u32> lower/lift, flat scalar-record lower/lift, mixed scalar-record lift, scalar-plus-text managed-field record lift, 17-field indirect scalar-record lower, two-level nested scalar-record lift/lower, three-level nested scalar-record lower/lift, and four-level nested scalar-record lower/lift have pinned Component gates and independent GC/ARC or GC/flat canonical-boundary equivalence; bounded parser-backed mixed scalar-record lower also has measured canonical ABI, no-GC-reference boundary checks, pinned Component assembly, generated host execution, and GC/flat equivalence`

The frozen rejection boundary remains arbitrary/deeper/general aggregates,
nested aggregate shapes beyond these scalar records, indirect layouts beyond the
pinned 17-field shape, text/list record lower beyond the private managed-field
descriptors, general aggregates, async/resource paths, and G5c cutover beyond
this row.

The row gate did not widen a compiler matcher or add a public type. The H-chain
parser fix only recognizes the two forms accepted by `embed-component`: a
`.wit` file or an existing WIT package directory.

## Verification

The row gate command was:

```text
bash src/build/test/check_gc_g5c_row.sh --row host_wit_marshalling --profile H --evidence-dir .tmp/g5c-full-cutover/task-13-host-wit-marshalling-verify-20260916-wYWVzu
```

All expected outcomes matched the actual outcomes in
`.tmp/g5c-full-cutover/task-13-host-wit-marshalling-verify-20260916-wYWVzu/commands.log`:

- `check_gc_arc_inventory.sh --post-cutover`: expected `0`, actual `0`
- `check_gc_default_build_gate.sh`: expected `0`, actual `0`
- `check_gc_migration_evidence_test.sh`: expected `0`, actual `0`
- `check_gc_migration_inventory.sh`: expected `1`, actual `1`, pre-closure summary `complete_rows=15 pending_rows=4`
- 21 G5a host/component probes: expected `0`, actual `0` for every command
- 18 G5b equivalence probes: expected `0`, actual `0` for every command
- H artifact checks: all generated WAT/Wasm/Component artifacts passed GC-only, no-ARC, and canonical-boundary checks
- H Component chains: parse-core -> embed-component -> new-component -> validate-component passed for every positive chain, including the package-directory WIT source

The captured manifests contain 417 checked artifact paths and 1,541 emitted
artifact paths. The run retained 257 binary artifacts, 133 WAT artifacts, 32
generated WIT artifacts, and 104 printed WAT files. The complete paths and
per-command output remain in `artifact-check.log`, `artifact-paths.log`, and
the individual G5a/G5b logs under the run directory.

## Measured ABI And Boundary Layouts

The printed GC WAT contains these managed layouts:

```text
$do_u8  = (array (mut i8))
$do_text   = (struct (field $length i32) (field $bytes (ref null $do_u8)))
$do_record = (struct (field $field0 i32) (field $field1 i32))
```

The observed canonical signatures are scalar-only at the Component boundary:

```text
canonical_lift  (param i32)
canonical_lower (param i32)
canonical_lower (param i32 i32)
canonical_lower (param i32 i64 i64)
canonical_lower (param i32 i64 i64 i64 i64)
canonical_lower (param i32 i32 i32)
canonical_lower (param i32 i32 i32 i32 i32)
canonical_lower (param i32 i32 i32 i32 i32 i32 i32)
```

The H checker found no admitted canonical import containing `(ref`. The two
printed `(ref null $do_record)` imports in the component-assembly logs are
intentional negative injections; those artifacts were rejected and classified
as negative evidence.

## Host And Equivalence Observations

| Shape | GC host observation | Equivalence observation |
| --- | --- | --- |
| WASI random `list<u8>` lift | `length=16 bytes=16` | `lengths=16/16 bytes=16/16 calls=1/1` |
| Scalar record lift | `sum=42` | `sums=42/42` |
| Scalar record lower | `result=42 write-calls=1` | `results=42/42 write-calls=1/1` |
| Indirect scalar record lower | `result=42 write-calls=1` | `results=42/42 write-calls=1/1` |
| Mixed scalar record lift | `sum=37` | `sums=37/37` |
| Nested scalar record lift | `sum=37` | `sums=37/37` |
| Three-level nested scalar record lift | `sum=42` | `sums=42/42` |
| Four-level nested scalar record lift | `sum=42` | `sums=42/42` |
| Nested scalar record lower | `result=42 write-calls=1` | `results=42/42 write-calls=1/1` |
| Three-level nested scalar record lower | `result=42 write-calls=1` | `results=42/42 write-calls=1/1` |
| Four-level nested scalar record lower | `result=42 write-calls=1` | `results=42/42 write-calls=1/1` |
| Managed-field record lift | `value=12` | `values=12/12` |
| Multi-managed-field record lower | `code=7 label=hello note=world write-calls=1 allocations=2 frees=2` | `allocations=2/2 frees=2/2 write-calls=1/1` |
| Default mixed text/byte/u32 lower | `result=42 write-calls=1` | `results=42/42 write-calls=1/1` |

The negative default-route probe also passed, preserving rejection of an async
marker (`UnknownP3AsyncHostDescriptor`), record shape drift
(`GcWitHostRecordMismatch`), member drift (`GcWitHostMemberMismatch`), and an
unadmitted module graph (`UnsupportedGcSyncModuleGraph`).

## Resolved G5a Commands

The runner resolved and executed each command below with `bash -x`; each has a
matching log with `expected_exit=0 actual_exit=0` in the run directory:

```text
examples/gc-p3-runtime/test_gc_wasi_random_list_lift.sh
examples/gc-p3-runtime/test_gc_marshal_record_component.sh
examples/gc-p3-runtime/test_gc_marshal_record_host.sh
examples/gc-p3-runtime/test_gc_marshal_record_lower_component.sh
examples/gc-p3-runtime/test_gc_marshal_record_lower_host.sh
examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_host.sh
examples/gc-p3-runtime/test_gc_marshal_record_lower_manifest_host.sh
examples/gc-p3-runtime/test_gc_marshal_record_lift_manifest_host.sh
examples/gc-p3-runtime/test_gc_marshal_record_mixed_lift_manifest_host.sh
examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_manifest_host.sh
examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_manifest_host.sh
examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deep_manifest_host.sh
examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deeper_manifest_host.sh
examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_manifest_host.sh
examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deep_manifest_host.sh
examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deeper_manifest_host.sh
examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_manifest_host.sh
examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_manifest_host.sh
examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_host.sh
examples/gc-p3-runtime/test_gc_default_host_route_mixed_lower_host.sh
examples/gc-p3-runtime/test_gc_default_host_route_mixed_lower_negative.sh
```

## Resolved G5b Commands

```text
examples/gc-p3-runtime/test_gc_wasi_random_list_lift_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_lower_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_lower_manifest_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_lift_manifest_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_mixed_lift_manifest_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_manifest_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_manifest_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deep_manifest_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deeper_manifest_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_manifest_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deep_manifest_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deeper_manifest_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_manifest_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_manifest_equivalence.sh
examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_equivalence.sh
examples/gc-p3-runtime/test_gc_default_host_route_mixed_lower_equivalence.sh
```

## WIT Source Hashes

SHA-256 values were computed from the tracked WIT inputs listed by the row
inventory. The descriptor manifest and `.do` source are also recorded because
they drive the generated default route.

```text
8773e0bdef9004c226623707a3046ad35ac693ba6e3805640fcb73dbf6c3d220  doc/wit/gc_descriptor_manifest.json
0b5f05d4b4f1536fbc6acedf9a8679c7232e1f4429d78a7023697736c3525a9c  examples/gc-p3-runtime/ordinary-host-mixed-lower-call.do
a9e201e03a5f4fe0602e0eb19544b480fe4925861cdc1e94ba436a116cc58fa0  examples/gc-p3-runtime/wasi-random-gc-lift-package/worlds.wit
66f5805b28c5ce0a17855d57f68ffe99179844549b6bcbf818e4260ce21159b8  examples/gc-p3-runtime/marshal-record-assembly.wit
efb53cc29fb3db871ba06ab774be81dbcedb35e7fa47eb7c10e229ce348c0ebc  examples/gc-p3-runtime/marshal-record-host.wit
092161359ac92385418a340a54aeb1362573b54b29a46a7d634017de1917c287  examples/gc-p3-runtime/marshal-record-lower-assembly.wit
5213f40b86389f4954aa41e94a18a7816b1881d3573a05db52bca158416a8967  examples/gc-p3-runtime/marshal-record-indirect-lower-assembly.wit
baaa5e884f684cfcf4db24b3e09e37d797ee7f413f47e1d248bddfbc9b58698a  examples/gc-p3-runtime/marshal-record-lower-manifest-source.wit
8fbe5b6b6f0308c342315a7408cd544bb093c521d6e5abbfa69b272f30d01495  doc/wit/gc_marshal_record_lower_imports.wit
a9a0a42770b3fe89da9516bd662931e67174f3933fd449cf0c14ecb82c27e063  examples/gc-p3-runtime/marshal-record-lift-manifest-source.wit
8fbe5b6b6f0308c342315a7408cd544bb093c521d6e5abbfa69b272f30d01495  doc/wit/gc_marshal_record_lift_imports.wit
b46bc0ba6a5350b937282f60692452ef7abb65d271db5a9e42dc1ff2e375958d  examples/gc-p3-runtime/marshal-record-mixed-lift-manifest-source.wit
8fbe5b6b6f0308c342315a7408cd544bb093c521d6e5abbfa69b272f30d01495  doc/wit/gc_marshal_record_mixed_lift_imports.wit
72db200dfcd650a474801c206c2dd1bca3683eb4bee27d4ba3f9b6418a0109fc  examples/gc-p3-runtime/marshal-record-mixed-lift-assembly.wit
a695a96b915150112a3d1fcba63a4c117ede365212201c247fbb2321571c4776  examples/gc-p3-runtime/marshal-record-mixed-lower-manifest-source.wit
8fbe5b6b6f0308c342315a7408cd544bb093c521d6e5abbfa69b272f30d01495  doc/wit/gc_marshal_record_mixed_lower_imports.wit
ae80bdf15e880e10deb83b4f8e69182900e2e711663f7f5229f59627ca70f3cc  examples/gc-p3-runtime/marshal-record-mixed-lower-assembly.wit
341600856f7b55b862d198cfea3fa4175eab7c64350c92a90f7559a439bdf7ef  examples/gc-p3-runtime/marshal-record-indirect-lower-manifest-source.wit
8fbe5b6b6f0308c342315a7408cd544bb093c521d6e5abbfa69b272f30d01495  doc/wit/gc_marshal_record_indirect_lower_imports.wit
1317b61a362379f9d9e3723c96a5ae1463ce5f22d74ddd634173ce4c2b238364  examples/gc-p3-runtime/marshal-record-nested-lift-manifest-source.wit
8fbe5b6b6f0308c342315a7408cd544bb093c521d6e5abbfa69b272f30d01495  doc/wit/gc_marshal_record_nested_lift_imports.wit
8c2a12c8da22429f68577a11219ab65b1e1e1d711eac9abe481b770179e10b15  examples/gc-p3-runtime/marshal-record-nested-lift-assembly.wit
160ba6780bbaea421f5ec15c330f611d2e315202b90a1057f0d57c15e6c620b9  examples/gc-p3-runtime/marshal-record-nested-lift-deep-manifest-source.wit
8fbe5b6b6f0308c342315a7408cd544bb093c521d6e5abbfa69b272f30d01495  doc/wit/gc_marshal_record_nested_lift_deep_imports.wit
719231b4211e727973045dd024449d36cb708d2a0d1178776fa5eb7aa673c484  examples/gc-p3-runtime/marshal-record-nested-lift-deep-assembly.wit
cae79c1ac14270b33d33143302995cc0c411a9e99acfe12b78caaa9e3384e20e  examples/gc-p3-runtime/marshal-record-nested-lift-deeper-manifest-source.wit
8fbe5b6b6f0308c342315a7408cd544bb093c521d6e5abbfa69b272f30d01495  doc/wit/gc_marshal_record_nested_lift_deeper_imports.wit
5c6187ed5ab6833ae10ec3933dca5105132377162edc1625e1770c817fccb5c2  examples/gc-p3-runtime/marshal-record-nested-lift-deeper-assembly.wit
f6ba335318798448e16e37ced278cc653def286d5627dc97d50fa56172cad488  examples/gc-p3-runtime/marshal-record-nested-lower-manifest-source.wit
8fbe5b6b6f0308c342315a7408cd544bb093c521d6e5abbfa69b272f30d01495  doc/wit/gc_marshal_record_nested_lower_imports.wit
039ae15864589e804c153188f7fb725b2480bd0e974c7018b3724c5c26cac49a  examples/gc-p3-runtime/marshal-record-nested-lower-assembly.wit
c632f520d3f746d7557c27e2aac6d997212d8babd6226106e14cfb897cb1bf5e  examples/gc-p3-runtime/marshal-record-nested-lower-deep-manifest-source.wit
8fbe5b6b6f0308c342315a7408cd544bb093c521d6e5abbfa69b272f30d01495  doc/wit/gc_marshal_record_nested_lower_deep_imports.wit
7fc931510d5956cbbaf063d533f35593eb2c08ccd1b62e248eb5f8a5961d313a  examples/gc-p3-runtime/marshal-record-nested-lower-deep-assembly.wit
3decb68376ff896363d1e232f7d39b70c1eca4b88f9dc127298af37f0e1ad0a8  examples/gc-p3-runtime/marshal-record-nested-lower-deeper-manifest-source.wit
8fbe5b6b6f0308c342315a7408cd544bb093c521d6e5abbfa69b272f30d01495  doc/wit/gc_marshal_record_nested_lower_deeper_imports.wit
e9b30efa076e66d066950b755a51cb3c0c4b1befd934b86559ac61ce15abee9b  examples/gc-p3-runtime/marshal-record-nested-lower-deeper-assembly.wit
a25d65f1dfc59686782f58732b5e15e9f33c7b30151c4a881595746018f87682  examples/gc-p3-runtime/marshal-record-managed-lift-manifest-source.wit
8fbe5b6b6f0308c342315a7408cd544bb093c521d6e5abbfa69b272f30d01495  doc/wit/gc_marshal_record_managed_lift_imports.wit
a2ef2e80d4ced3fdfb7895799a989c7573d09f5cb49d81f4d465e39c78749448  examples/gc-p3-runtime/marshal-record-managed-lift-assembly.wit
aaebd8fba91d18670ce0af1740acac8e36fd9dc3928b7e715284e24559e5a202  examples/gc-p3-runtime/marshal-record-managed-lower-multi-manifest-source.wit
8fbe5b6b6f0308c342315a7408cd544bb093c521d6e5abbfa69b272f30d01495  doc/wit/gc_marshal_record_managed_lower_multi_imports.wit
5298a69c43b2993fc1a694544bcf45a934d42061dee19b0e82b658d9681bab06  examples/gc-p3-runtime/marshal-record-managed-lower-multi-assembly.wit
```

## Toolchain

The run used the pinned entries in `toolchain/toolchain.lock.json` and recorded
the complete probe and lock snapshot in `commands.log` and
`toolchain-probe.json`:

- `wasm-tools 1.258.0`, SHA-256 `282e0014d38daf233cb10fb92815813b339e2b7f8b4734f6698f0176c7d99424`
- `wasmtime 48.0.1`, SHA-256 `5a61e28214e31c2a52154103407bae5265a36732b3af502609e5ffe19f249463`
- `zig 0.16.0`, SHA-256 `2317bbb91798556d9d0f38aabdac23db83f0979b25f767259ae474546724087c`
- `rustc 1.97.1`, SHA-256 `d3a664c970a9fd8361b64194861bebc1ae37b9054e5ee3400dc1c9e691797eea`
- `cargo 1.97.1`, SHA-256 `828980723df339d62434390e9fb8ef8831036583343ae2316b7ab5646b5c1953`

## Closure Decision

The H-profile gates, default GC route checks, component assembly/validation,
host payload observations, equivalence checks, and preserved rejection boundary
all passed. This evidence authorizes only the `host_wit_marshalling` G5c
inventory field to move from `pending` to `complete`; it does not authorize
general aggregates, arbitrary layouts, generic async, resources, ownership,
`Option`/`Result`, or any other row. The next independent row is
`host_wit_marshalling_managed_record_lower` (Task 14).

### G5c measured indirect Tuple byte-list lift (2026-11-23)

The exact descriptor
`demo:marshal-tuple-list-lift/api.receive@1.0.0/lift` is now registered in
`doc/wit/gc_descriptor_manifest.json` with source/WIT provenance and a measured
12-byte Tuple layout: `u32@0`, `list<u8>@4`, and one indirect `i32` result word.
The ordinary Do host declaration is checked against `Tuple<u32, [u8]>`; a
`Tuple<u32, [u32]>` drift case is rejected before WAT emission.

`examples/gc-p3-runtime/test_gc_marshal_tuple_list_lift_host.sh` now generates
Core WAT through `codegen_gc_wit_marshal.emit_module`, then runs the embedded
Component with Wasmtime. The host callback returns `(7, [10,20,30])`; the
exported result is `770` and the callback count is one. This closes only this
measured indirect Tuple byte-list lift descriptor. Other Tuple/list child
combinations, arbitrary indirect layouts, async/resource payloads, and full
G5c cutover remain unproven.

### G5c measured indirect Tuple u32-list lift (2026-11-23)

The adjacent exact descriptor
`demo:marshal-tuple-u32-list-lift/api.receive@1.0.0/lift` is also registered.
Its measured root is the same 12-byte Tuple shape, with `u32@0` and a direct
`list<u32>@4`; the list uses 4-byte element size, stride, and alignment and
one indirect `i32` result word. The compiler rejects a corresponding
`Tuple<u32, [u8]>` declaration before WAT emission.

The Component gate returns `(7, [10,20,30])` from the host callback and observes
`result=770` with one callback. The generated module emits `$do_u32` exactly
once even though both the scalar field and list child use that type. This closes
only the pinned `Tuple<u32, list<u32>>` lift shape; arbitrary Tuple/list layouts
and async/resource payloads remain unproven.

### Tuple scalar-list emitter generalization (2026-11-23)

The compiler-side synchronous Tuple emitter now accepts every scalar list
element layout represented by the current typed-array table: `bool`, `u8`,
`u16`, `u32`, `u64`, `i8`, `i16`, `i32`, `i64`, `f32`, and `f64`. It also
collects multiple list children in source order and traverses list children
inside nested Tuples. Each list keeps its measured stride, alignment, result-area
offsets, and independent linear allocation/free sequence. Lift frees all copied
linear spans before constructing and publishing the GC Tuple.

The focused Zig emitter suite covers a non-byte `list<f64>` Tuple and the
operation-order regression. This is compiler/WAT evidence only; it does not add
a new manifest-backed Component host descriptor, and it does not authorize
`list<list<T>>`, list of records/Tuples/text, map children, async/resource
payloads, arbitrary indirect layouts, or full G5c cutover.
