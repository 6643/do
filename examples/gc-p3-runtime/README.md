# Core Wasm GC probe

This directory contains standalone Core Wasm GC probes and a small bounded
Component/WIT marshal probes for the future do runtime. The probes cover one
fixed synchronous `text` lower/copy/call path, scalar-record lift/lower rows
(including bounded three-level, four-level, and five-level nested rows), and fixed synchronous
`list<u32>` lower/copy/call plus lift/result-area/copy paths, including the
fixed mixed `text` + `list<u32>` lift path, with
Rust/Wasmtime hosts, plus a matching
fixed text and `list<u32>` ARC/GC observations. They do not imply general Component Model,
WIT, WASI, P3, resource, cancellation, general lift, or unrestricted default
compiler-route support. A fixed set of synchronous managed-record descriptors
is separately admitted by the current default route; all other host/WIT shapes
remain outside that route.

### Bounded `list<u32>` record lift

The fixed descriptor
`demo:marshal-record-u32-list-lift/api.read@1.0.0/lift` covers only:

```text
Reading { code: u32, payload: [u32] }
```

Its canonical lift receives one result-area pointer. The measured result area
is 12 bytes (`code@0`, `payload.ptr@4`, `payload.len@8`), with list capacity 3
and accepted lengths 0 through 3. The generated path validates the result area
and linear span, copies the payload into `$do_u32`, frees the temporary span
once, and constructs the GC record. The canonical import carries no GC
reference.

The pinned Component host gate observes `code=7`,
`payload=[10,20,30]`, `result=67`, one callback, and one allocation/free pair.
The ARC/GC equivalence gate observes `67/67`, `17/17`, and `1/1`; six negative
fixtures reject before WAT. This is bounded evidence only: general
list-record lift, async/resource lowering, ownership syntax, and full G5c
cutover remain pending.

`gc-frame.wat` verifies three representation rules:

1. A mutable `struct` can represent runtime-private frame state.
2. A mutable `array` can represent a runtime-private queue.
3. A source value is an immutable GC `struct`; a changed value is rebuilt, so
   the original remains unchanged after assignment/copy.

Run it from the repository root:

```bash
examples/gc-p3-runtime/run-wasmtime.sh
```

The script uses `/home/_/Public/wasmtime/bin/wasmtime` by default and accepts
`WASMTIME_BIN=/path/to/wasmtime` for an explicit override. It enables only
`-W gc=y`, uses Wasmtime's `compile` command to compile-or-validate the WAT,
then invokes `probe`. The guest traps unless its internal representation check
computes `27815`, and the script requires that exact returned value.

Recorded on 2026-07-28:

```text
wasmtime: wasmtime 47.0.2 (90fed3c6a 2026-07-21)
compile-or-validate: ok
run:
warning: using `--invoke` with a function that returns values is experimental and may break in the future
  guest result: 27815
GC probe passed: 27815
```

The feature set for both validation and execution is exactly `-W gc=y`. The
warning is emitted by Wasmtime's CLI; the probe intentionally returns a value
so the script can assert the in-guest result without a host import.

## Restricted compiler lowering

`do build --gc-core` is an experimental, deliberately restricted token-profile
oracle. It does not select the normal compiler backend and it does not accept
arbitrary Do programs. Its remaining executable source forms are independent
fixtures:

```do
identity(value text) -> text {
    return value
}

start() {}
```

```do
Box {
    value [u8]
}

update(box Box) -> Box {
    return @set(box, .value, @set(@get(box, .value), 0, 65))
}

start() {}
```

```do
rewrite(pair Tuple<text, [u8]>) -> Tuple<text, [u8]> {
    return Tuple<text, [u8]>{@get(pair, 0), @set(@get(pair, 1), 0, 65)}
}

start() {}
```

```do
Box {
    value [u8]
    tag i32
}

update(box Box) -> Box {
    return @set(box, .value, @set(@get(box, .value), 0, 65))
}

start() {}
```

Run the source-to-engine checks from the repository root:

```bash
RUN_GC_CORE=1 WASMTIME_BIN="$(command -v wasmtime)" bash src/build/test/check_gc_core_oracles.sh
```

The same oracle suite can be included after the standard compiler regression:

```bash
RUN_GC_CORE=1 WASMTIME_BIN="$(command -v wasmtime)" ./src/build/test/run_tests.sh
```

The individual probes remain available for focused diagnosis:

```bash
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_text_identity.sh
DO_BIN="$(pwd)/bin/do" WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_do_gc_scalar_leaf.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_text_identity_renamed.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_list_set.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_parameterized_list_set.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_list_literal.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_list_put.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_parameterized_list_set_renamed.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_managed_struct_set.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_managed_struct_renamed.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_managed_struct_preserve_field.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_managed_struct_payload.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_managed_struct_payload_renamed.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_managed_text_field_call_producer.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_nested_managed_struct.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_four_level_nested_field_path.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_five_level_nested_field_path.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_managed_struct_list.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_text_list.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_managed_tuple_text_bytes.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_managed_struct_f32_field.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_managed_struct_f64_field.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_managed_struct_i64_field.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_u32_list_literal.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_u32_list_set.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_i16_list_literal.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_i16_list_set.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_i32_list_literal.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_i32_list_set.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_i64_list_literal.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_i64_list_set.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_f32_list_literal.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_f32_list_set.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_u32_host.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_u32_lift_host.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_u32_lift_equivalence.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_u32_equivalence.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_host.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_equivalence.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_component.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_lower_component.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_lower_host.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_lower_equivalence.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_manifest_host.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_manifest_equivalence.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deep_manifest_host.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deep_manifest_equivalence.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deeper_manifest_host.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deeper_manifest_equivalence.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deeper_manifest_host.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deeper_manifest_equivalence.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_wasi_random_list_lift_equivalence.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_f64_list_literal.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_f64_list_set.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_bool_list_set.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_remaining_scalar_lists.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_imported_text_identity.sh
```

### Synchronous scalar-leaf default route

`scalar-leaf.do` is the smallest ordinary `do build` GC admission: every
non-`start` function has only Core Wasm scalar parameters and one scalar result,
and its body is one direct `return` expression. The default route emits
`;; gc-sync` without an `__arc_` marker. Direct self-recursion, loop, defer,
host/WIT bindings, managed values, async, and resources remain outside this
slice and are covered by focused fail-closed tests.

Run the focused gate with the pinned toolchain:

```bash
DO_BIN="$(pwd)/bin/do" \
WASM_TOOLS_BIN="$(command -v wasm-tools)" \
bash examples/gc-p3-runtime/test_do_gc_scalar_leaf.sh
DO_BIN="$(pwd)/bin/do" \
WASM_TOOLS_BIN="$(command -v wasm-tools)" \
bash examples/gc-p3-runtime/test_do_gc_scalar_control_flow.sh
```

The default GC build/parse gate now covers 82 fixtures. This bounded compiler
route does not close a migration inventory row; the ledger remains
`complete_rows=15 pending_rows=15` until the broader G5c evidence is complete.

### Synchronous scalar control-flow default route

`scalar-control-flow.do` extends the scalar-leaf route with exactly three
structured forms: `if/else`, an `else-if` chain with a final `else`, and a
guard-return followed by one unconditional scalar return. Conditions are
limited to scalar atoms or `@eq` over scalar atoms, and branch results are
scalar atoms. The default route emits `;; gc-sync`,
`;; gc-root branch_join`, and `;; gc-root guard_join` without `__arc_`.

Loops, `defer`, recursion, imported module graphs, managed values, host/WIT,
async/resource, arbitrary producer expressions, and unsupported scalar calls
remain fallback/fail-closed. Acyclic same-module scalar helper calls are covered
by the separate call-graph slice below; recursive call graphs remain rejected.
This is an admission slice only: it does not
change grammar or public APIs, close a migration row, or authorize full G5c
cutover.

Run the focused gate with the pinned toolchain:

```bash
DO_BIN="$(pwd)/bin/do" \
WASM_TOOLS_BIN="$(command -v wasm-tools)" \
bash examples/gc-p3-runtime/test_do_gc_scalar_control_flow.sh
```

### Synchronous scalar call-graph boundary

`scalar-call-graph.do` covers a three-level, same-module synchronous helper
chain. The typed GC route preserves `call $leaf` and `call $middle` while the
admission predicate rejects self-recursion, mutual recursion, and longer call
cycles before WAT emission. Imported module graphs, host/WIT bindings, managed
values, async/resource, and arbitrary producer expressions remain outside this
boundary.

Run the focused gate with the pinned toolchain:

```bash
DO_BIN="$(pwd)/bin/do" \
WASM_TOOLS_BIN="$(command -v wasm-tools)" \
bash examples/gc-p3-runtime/test_do_gc_scalar_call_graph.sh
```

The standalone gate and the scalar-focused Zig suite (`130/130`) pass. The
default manifest contains 82 fixtures; the migration ledger remains
`complete_rows=15 pending_rows=15` and this slice does not claim full GC
cutover.

### Parsed text/list/producer migration boundary

The parsed synchronous GC probe covers direct text identity and string rebuild,
direct text-field replacement, a byte-list literal bound through a typed local,
and a direct call returning an already-classified managed value. The probe
wrapper validates exact function bodies and derives struct/field facts from the
parsed source. It also covers direct-local replacement of a declared nested
managed child and direct child `@get`, plus the selected managed-tuple rewrite.
One exact nested producer is admitted for a managed struct `[u8]` field:
`@set(box, .value, @set(@get(box, .value), index, scalar))`. Nested paths,
arbitrary calls, other element types, general Tuple/storage forms, non-`u8`
updates, multi-value put, and other call-produced managed replacements fail
closed before WAT. The separate direct managed-field call producer slice below
admits only a `[u8]` or `text` field with exactly one synchronous single-result
call and an exact field-type match.

### Typed aggregate layout checkpoint

The parsed GC prelude orders nested managed struct types before their parents
and rejects missing children, recursive/cyclic layouts, resource fields, and
lowered-name collisions. A pure GC source containing a standalone
`@wasi_resource` declaration is rejected before WAT; WIT resources never enter
the Core-GC child graph. The admitted aggregate surface remains the direct-local
nested-child replacement, the single `Tuple<text, [u8]>` rewrite, one pure
`Unit | Bytes([u8])` carrier, and resolved generic calls bound to existing
concrete GC layouts described below. Declared managed-struct and `[text]`
element list literal/`@len`/`@get`/collection-loop plus bounded one-value
`@put` slices, including managed-struct `[Box]` append, are also admitted.
General tuples/storage, nested paths deeper than the admitted one-/two-/three-/four-/five-level
managed-struct field paths,
generic layout instantiation, imports,
General Component/WIT marshalling, async frames, and arbitrary producers
remain outside this probe directory's admission boundary. The fixed
`list<u32>` lower/lift probes below are explicit bounded exceptions.

The focused checkpoint report is
`.superpowers/sdd/2026-08-13-gc-g5a-aggregate-closure/task-3-report.md`.

Focused verification:

```bash
cd src && zig test build/codegen_gc_sync.zig
cd src && zig test build/gc_sync_probe.zig
WASMTIME_BIN="$(command -v wasmtime)" WASM_TOOLS_BIN="$(command -v wasm-tools)" bash src/build/test/check_gc_core_oracles.sh
```

The current focused counts are `244/244` for `codegen_gc_sync.zig` and `65/65`
for `gc_sync_probe.zig`. The managed scalar-array field probes pass for
`[bool]`, `[i8]`, `[i16]`, `[i32]`, `[i64]`, `[u16]`, `[u32]`, `[u64]`,
`[isize]`, `[usize]`, `[f32]`, and `[f64]` with `wasm-tools 1.255.0`
parsing and Wasmtime GC execution. `bash src/build/test/check_gc_migration_evidence_test.sh`
verifies the explicit marker required by future G5b/G5c evidence files.

The normal compiler path uses typed GC for the admitted synchronous shapes;
unconverted shapes remain on the ARC transition path until the later G5c
one-backend gate is closed.

### Parsed scalar-list slices

`f32-list-literal.do` and `f64-list-literal.do` cover the typed GC array
literal boundary for floating-point scalar lists. The corresponding
`f32-list-set.do` and `f64-list-set.do` fixtures cover fixed-index immutable
updates by copying the source array before `array.set`. `bool-list-set.do`
adds the fixed-index boolean update boundary with the same copy-before-set
semantics. The shared `test_do_gc_remaining_scalar_lists.sh` probe adds
`[i8]`, `[u16]`, `[u64]`, `[isize]`, and `[usize]` literal/update coverage;
all twenty-three scalar-list probes validate old/new values after
`wasm-tools 1.255.0` parsing and Wasmtime GC execution, returning `27815`.
Float `@put` and producer expressions remain outside this slice. The bounded
nested `[[u8]]` list shape is covered separately below. Declared managed-struct
and `[text]` element list coverage is recorded below.

### Parsed managed-struct element list slice

`managed-struct-list.do` exercises a declared `[Box]` through list literal
construction, `@len`, indexed `@get`, collection-loop lowering, and one-value
`@put(boxes, value)`. Its probe checks the original one-element list, the
appended element's `tag`, and the `[u8]` payload bytes. The typed
`$do_list_box` module is parsed with `wasm-tools 1.255.0` and executed with
Wasmtime `-W gc=y`, and both probe paths require the `27815` oracle.

This is limited to declared managed-struct element lists and one direct local
value for `@put`. General producer expressions, nested-list forms other than
the separately admitted `[[u8]]` case below, and multi-value/spread forms remain
outside admission.

### Default body-only managed-struct storage slice

`managed-struct-storage.do` exercises the ordinary `do build` route when a
managed struct is created and updated entirely inside `start()`. The typed GC
path rebuilds the struct for `@set(box, .tag, 7)`, reads the child `[u8]` field
through `@get`, and keeps the original value observable. The dedicated gate
also rejects legacy `__storage_*`, `__struct_literal_tmp`, and `__arc_`
markers, parses with `wasm-tools 1.255.0`, and executes the Wasm with Wasmtime
GC enabled. This is one bounded storage shape; inferred lists, nested/general
storage producers, and boundary/async/resource storage remain pending.

### Inferred managed list storage slice

`inferred-list-storage.do` and `inferred-u32-list-storage.do` cover bounded
body-only inferred storage bindings: an explicit `[u8]` or `[u32]` seed is
passed to `@put`, and the result is bound without a type annotation. The
default route records the inferred local as a fresh GC root, copies the
published typed array before `array.set`, and does not emit ARC or legacy
storage compiler locals. The dedicated gates build each fixture, parse it with
`wasm-tools 1.255.0`, and run it with Wasmtime GC enabled.

Dynamic producers, inferred non-scalar lists, multi-value/spread `@put`, and
additional storage control flow remain outside this admission.

### Parsed text-element list slice

`text-list.do` exercises a `[text]` list through literal construction, `@len`,
indexed `@get`, and collection-loop lowering. Its probe checks both returned
text values, including their lengths and first bytes. `test_do_gc_text_list.sh`
validates the typed `$do_list_text` module with `wasm-tools 1.255.0` and
Wasmtime `-W gc=y`, requiring the `27815` oracle.

`text-list-put.do` covers one-value managed-element append for `[text]`.
`test_do_gc_text_list_put.sh` verifies the source list remains length one, the
result is length two, the old element reference is reused, and the new text
payload is present.

Producer expressions and managed-struct/nested-list `@put` remain outside
admission.

### Parsed nested byte-list slice

`nested-byte-list.do` exercises one `[[u8]]` value through nested literal
construction, outer `@len`, indexed `@get`, inner `@len`, and a collection loop.
The `test_do_gc_nested_byte_list.sh` probe validates the outer
`$do_list_list_u8` and inner `$do_bytes` GC arrays with `wasm-tools 1.255.0`
and Wasmtime `-W gc=y`, returning the `27815` oracle after checking all inner
bytes.

This evidence covers the bounded nested byte-list shape. The companion
`nested-byte-list-put.do` fixture admits one direct `@put(rows, row)` producer
for `[[u8]]`; its probe checks that the source outer array and inner row remain
unchanged, the result has one appended row, and the appended bytes are `4, 5`.
Both paths are parsed with `wasm-tools 1.255.0` and executed by Wasmtime with
GC enabled. General producers, arbitrary nested aggregate combinations, and
multi-value/spread `@put` remain outside admission.

### Parsed direct managed-field call producer slice

`managed-field-call-producer.do` and `managed-text-field-call-producer.do` admit
one additional producer shape for a `[u8]` or `text` managed struct field: the
replacement is a direct synchronous function call with exactly one result whose
declared type exactly matches the field. The existing typed GC call-result root
marker is reused before the outer struct is rebuilt. Nested calls, multi-result
calls, mismatched results, async/host calls, and arbitrary expressions remain
rejected before WAT.

Its probe verifies that the original object and payload remain unchanged, the
replacement payload is selected, and the scalar field survives. The
`wasm-tools 1.255.0` and Wasmtime GC gate returns `27815`; the compiled-test
equivalence row also passes.

### Parsed managed struct scalar-array field slice

`managed-struct-bool-field.do`, `managed-struct-u32-field.do`,
`managed-struct-i16-field.do`, `managed-struct-i32-field.do`,
`managed-struct-f32-field.do`, `managed-struct-f64-field.do`,
`managed-struct-i64-field.do`, and the shared remaining-scalar-field probe
admit direct immutable replacement of all registered scalar-array field types
(`[bool]`, `[i8]`, `[i16]`, `[i32]`, `[i64]`, `[u16]`, `[u32]`, `[u64]`,
`[isize]`, `[usize]`, `[f32]`, and `[f64]`) while preserving an unchanged scalar field. Their
independent probes construct distinct original and replacement objects, verify
the old arrays remain unchanged, verify the new replacement arrays, and check
`tag == 7`. Each returns `27815` after `wasm-tools 1.255.0` parsing and
Wasmtime GC execution. Managed-field producers other than the separately
admitted direct `[u8]`/`text` single-result call, nested paths outside the admitted
one-/two-/three-/four-/five-level managed-struct field paths, and
resource-containing structs remain outside this slice.

`three-level-nested-field-path.do` extends the same immutable rebuild shape to
three direct managed struct segments. Its probe checks the leaf scalar update,
the unchanged leaf byte payload, all intermediate scalar fields, and the outer
scalar field. `four-level-nested-field-path.do` adds one more direct managed
segment, and `five-level-nested-field-path.do` adds a fifth; each performs the
same terminal-to-root rebuild. The
`wasm-tools 1.255.0`/Wasmtime GC probes and compiled-test ARC/GC equivalence
rows both require the `27815` oracle. A sixth managed segment, deeper paths,
arbitrary producers,
async/resource paths, and host/WIT remain fail-closed.

### G5a five-level nested managed-struct field path (2026-08-22)

The bounded synchronous GC route now admits the direct-local path
`Top -> Outer -> Inner -> Middle -> Leaf -> Core` through
`@get/@set(top, .outer, .inner, .middle, .leaf, .core, ...)`. `@set` rebuilds
`Core`, `Leaf`, `Middle`, `Inner`, `Outer`, and `Top` from terminal to root;
unchanged scalar fields and the original `[u8]` payload reference remain
observable. The standalone probe requires all five managed links and six
constructors, parses with `wasm-tools 1.255.0`, executes with Wasmtime GC, and
returns `27815`. The compiled-test row and ARC/GC semantic-equivalence matrix
also pass (`26` rows, `0` pending). A sixth managed segment, producer
expressions, general aggregates, async/resource paths, and host/WIT general
lowering remain outside admission; the migration inventory stays
`complete_rows=15 pending_rows=15` with exit 1.

### Parsed pure payload-union slice

`gc-payload-union.do` is the bounded G5a union carrier probe. It admits only
`Unit | Bytes([u8])` payload-enum declarations, lowers the carrier to a typed
GC struct `(tag i32, bytes (ref null $do_bytes))`, and preserves source-value
immutability by allocating a new union for `Bytes(bytes)`. The parsed GC route
also supports a typed carrier local and return, while resolved generic `T`
instances use the same carrier after substitution. Its probe checks
old/new identity, tag and null-payload preservation, direct payload identity,
and replacement bytes. `test_do_gc_payload_union.sh` validates the emitted WAT
with `wasm-tools 1.255.0`, compiles/runs it with Wasmtime `47.0.2 -W gc=y`,
and requires `27815`.

This slice rejects additional or mixed payload slots, resource/nested-union/
Tuple/storage payloads, unresolved or mixed generic bindings, imported/async
values, Component/WIT lowering,
and does not change the default ARC route. It is not evidence for general
WIT variants, `Result`, `Option`, or resource ownership.

### Parsed resolved generic managed-call slice

`generic-managed-identity.do` and its probe admit a generic identity and a
managed-field update after `T` is resolved to the existing concrete `Box`
layout. The probe checks old/new object identity, old payload preservation,
replacement bytes, and scalar-field preservation; it returns `27815` after
`wasm-tools 1.255.0` parsing and Wasmtime GC compilation/execution. Unresolved,
resource, and payload-union bindings fail before WAT with named generic guards.
Generic struct layout instantiation and generic tuples remain outside this
slice.

### Parsed byte-list migration slices

The fixed-index and parameterized `[u8] @set` fixtures no longer use the
`--gc-core` token-profile target. They are complete-program G5a slices emitted
by the non-CLI, test-only `src/build/gc_sync_probe.zig` wrapper around
`emit_gc_wat_for_supported_program`:

```do
update(input [u8]) -> [u8] {
    return @set(input, 0, 65)
}

set_at(input [u8], index usize, value u8) -> [u8] {
    return @set(input, index, value)
}

start() {}
```

This keeps the temporary CLI oracle fail-closed while the parsed GC lowering is
admitted one complete-program slice at a time. It adds no public backend flag;
the focused `test_do_gc_list_set*.sh` scripts invoke the test-only wrapper.

The list fixture uses a GC array reference for function transfer, allocates a
fresh array for `@set`, copies the original bytes, and changes only the fresh
array. Its exported probe traps unless the original remains `[1, 2, 3]` and
the returned value is `[65, 2, 3]`. This is a persistent-update semantic check,
not a unique-value reuse optimization.

The parameterized-list fixture takes the index and byte as source parameters.
Its emitted function uses the input's `array.len` for allocation and copies that
entire runtime length before the parameterized `array.set`.

For this parameterized shape, the function and parameter identifiers are not
part of the ABI contract: `replace(bytes [u8], offset usize, next u8)` is also
accepted when its body directly returns `@set(bytes, offset, next)`. Different
types, control flow, or a different data flow remain unsupported.

The text identity shape has the same naming rule: `relay(message text) -> text`
is accepted when its body directly returns `message`. It transfers the internal
GC reference, not a copied text payload.

The managed-struct fixture repeats that check through an immutable outer GC
struct. It copies and updates the nested array, then constructs a distinct
`Box`; the original `Box.value` continues to read as `[1, 2, 3]`.

The nested-managed-struct fixture separately proves the next aggregate boundary:
`@set(outer, .inner, inner_local)` creates a distinct `Outer`, preserves the old
outer and its original `Inner`, carries the exact replacement `Inner` reference
into the new outer, and retains the unrelated scalar field. Direct
`@get(outer, .inner)` is admitted with the declared child type. This is not
general nested-path lowering, list-of-managed-struct support, recursive layout
support, or WIT-resource aggregation.

The field-preserving fixture additionally records a `tag i32`. Updating
`value` retains `tag` in both the old and the new `Box`, proving that an outer
rebuild does not discard unrelated fields.

The managed-tuple fixture is a parsed GC-sync slice, not a `--gc-core` token
profile. It admits only `Tuple<text, [u8]>{@get(pair, 0),
@set(@get(pair, 1), 0, 65)}` for a `Tuple<text, [u8]>` input/output. The tuple
stores text as a typed GC reference, copies and updates the byte array, then
rebuilds the tuple once. The probe reads both the original tuple and returned
tuple, verifies their identities differ, verifies both retain the original text
reference, and checks old/new byte contents separately. General tuple
construction/indexing, tuple storage, nested tuples, and resource aggregates
remain outside this slice.

The parsed literal slice is a separate non-CLI probe. `list-literal.do` returns
`[u8]` from `.{7, 12, 17}`; the focused script calls it twice, proves distinct
GC arrays, and keeps the first result rooted while checking its three bytes.
`.{}` is covered by the emitter test as a zero-length `array.new_default`.
Only numeric `u8` literals are admitted; `@put`, other list element types, and
general producer expressions remain outside this gate.

The parsed `@put` slice is also a separate non-CLI probe. `list-put.do` admits
only `@put(input, value)` for `[u8]` plus one `u8` value. Its probe appends to
an empty list and a three-byte list, checks old-value preservation, and proves
that two results are distinct GC arrays. Multi-value, spread, non-`u8`, and
general producer forms remain rejected before WAT.

The managed-struct shape also accepts renamed struct, function, receiver, and
`[u8]` field bindings. `Packet/bytes/rewrite` uses the same immutable path-copy
lowering as `Box/value/update`; different field types or update data flows stay
outside this experimental target.

The parsed managed-field payload slice is a separate non-CLI probe.
`managed-struct-payload.do` replaces one `[u8]` field from a source parameter by
rebuilding the outer `Box`. The probe checks that the old `Box` and payload stay
unchanged, the new payload is selected, and the scalar `tag` survives the
rebuild. `managed-struct-payload-renamed.do` repeats the same check with
`Packet/version/bytes/rewrite` and reversed field order, so the wrapper does
not depend on source names or declaration order. Nested producers, text
payload replacement, and resource fields remain outside this slice.

### Manifest-backed WASI random `list<u8>` ARC/GC equivalence

`test_gc_wasi_random_list_lift_equivalence.sh` generates the GC lift from the
hash-pinned descriptor manifest, assembles it beside a hand-authored linear
memory ARC reference module under the same versioned `wasi:random` WIT package,
and runs both Components through the same Rust/Wasmtime host callback. Both
routes must observe one 16-byte result, one callback, and identical bytes. This
is one canonical-boundary equivalence row; it does not route the ordinary
`do build` host/WIT path through GC and does not close the broader
`host_wit_marshalling`/G5c inventory row.

### G5c C2 private manifest-backed route

`src/build/codegen_component_manifest_route.zig` is the private compiler-side
entry point for the bounded manifest slice. It accepts only the descriptor id,
loads the hash-pinned source and world through the provenance loader, and then
hands the measured request to the parser-backed marshal route. Unknown
descriptors fail before WAT emission; the ordinary `do build` host/WIT route
remains ARC-backed.

### G5c C3 private manifest-backed text lower

`src/build/gc_marshal_text_probe.zig` selects the second measured descriptor,
`demo:marshal-equivalence/api.send@1.0.0/lower`, and generates the GC
`text` lower/copy/call module through the same provenance-checked route. The
probe-only counter instrumentation reports temporary linear allocation/free
events without changing the canonical `(i32, i32)` Component import.

`test_gc_marshal_text_equivalence.sh` generates that module, assembles it beside
the hand-authored ARC reference, and runs both with the pinned Rust/Wasmtime
runner. Both paths must deliver `hello` and report one allocation/free. This
does not alter ordinary `do build` host/WIT routing or close broader G5c rows.

### Bounded synchronous `list<u32>` ARC/GC equivalence

`test_gc_marshal_u32_equivalence.sh` assembles the fixed `list<u32>` lower
probe twice: once with the GC array path and once with the linear-memory
ARC-style path. The shared Rust/Wasmtime runner observes `[10, 20, 30]` from
both Components and checks exactly one allocation and one free on each path.
This closes equivalence for this one measured synchronous list shape only; it
does not wire the plan into `do build`, prove arbitrary records or lists, or
close the `host_wit_marshalling`/G5c inventory rows.

### G5c bounded record `list<u32>` lower

The fixed record fixture
`ordinary-host-record-u32-list-lower-call.do` covers
`Writing { code: u32, payload: [u32] }` through the manifest-backed descriptor
`demo:marshal-record-u32-list-lower/api.write@1.0.0/lower`. Its 12-byte root
uses canonical `(i32, i32, i32)` lower parameters; the generated GC route
copies up to three `u32` elements to temporary linear memory, calls the host,
and frees the span exactly once. The host gate observes
`code=7`, `payload=[10,20,30]`, `result=42`, one callback, and one
allocation/free pair. The ARC/GC equivalence gate observes `42/17` and `1/1`
cleanup, while six source-level negative fixtures reject before WAT.

This is a fixed synchronous record row, not general `list<T>` or list-record
lowering. Async/resource lowering, ownership syntax, and full G5c cutover
remain outside admission.

### G5c C4 private manifest-backed `list<u32>` lower

`src/build/gc_marshal_u32_probe.zig` selects the hash-pinned
`demo:marshal-u32-equivalence/api.send@1.0.0/lower` descriptor and emits the
typed GC-array lower module through the parser-backed manifest route. The
canonical boundary is `(i32, i32)`; the guest does not pass a GC reference to
the Component import.

`test_gc_marshal_u32_equivalence.sh` now generates that GC module, assembles it
beside the hand-authored ARC reference, and runs both with the pinned
Rust/Wasmtime runner. Both paths must deliver `[10, 20, 30]` and report one
allocation/free. This remains a private measured shape: ordinary `do build`
host/WIT routing, arbitrary list/aggregate shapes, and G5c cutover are still
pending.

### G5c C5 private manifest-backed `list<u32>` lift

`src/build/gc_marshal_u32_lift_probe.zig` selects the hash-pinned
`demo:marshal-u32-lift-host/api.receive@1.0.0/lift` descriptor and emits the
typed GC-array lift through the parser-backed manifest route. The canonical
boundary is `(i32)` result-area input; the Component import never receives a
GC reference.

`test_gc_marshal_u32_lift_host.sh` covers manifest-backed Component assembly
and host execution. `test_gc_marshal_u32_lift_equivalence.sh` runs the
generated GC Component beside the linear-memory ARC reference; both produce
checksum `60`. This remains a private measured shape: arbitrary lifts,
ordinary `do build` host/WIT routing, and G5c cutover are still pending.

### G5c C6 private manifest-backed scalar-record lower

The descriptor manifest now pins
`demo:marshal-record-lower/api.write@1.0.0/lower` to a package/interface
fragment plus a package-less `probe` world fragment. The loader checks the
concatenated source hash and `writing` record signature before
`gc_marshal_record_lower_probe.zig` emits the typed GC record lower module.
Its canonical import is `(i32, i32)` and no GC reference crosses the boundary.

`test_gc_marshal_record_lower_manifest_host.sh` verifies manifest-backed
Component assembly, a source-hash drift negative case, and Rust/Wasmtime host
execution (`result=42`, `write-calls=1`). The paired
`test_gc_marshal_record_lower_manifest_equivalence.sh` compares the generated
GC Component with the flat linear-memory reference and observes `42/42` with
one callback per path. This is one private measured record-lower row only;
ordinary host/WIT routing, nested/general aggregates, async/resource paths,
and G5c cutover remain pending.

### G5c C7 private manifest-backed scalar-record lift

The descriptor manifest now pins
`demo:marshal-record-host/api.read@1.0.0/lift` to a package/interface
fragment plus a package-less `probe` world fragment. The loader checks the
concatenated source hash and `reading` record signature before
`gc_marshal_record_lift_probe.zig` emits the typed GC result-area lift module.
Its canonical import is `(i32)` and no GC reference crosses the boundary.

`test_gc_marshal_record_lift_manifest_host.sh` verifies manifest-backed
Component assembly, a source-hash drift negative case, and Rust/Wasmtime host
execution (`sum=42`). The paired
`test_gc_marshal_record_lift_manifest_equivalence.sh` compares the generated
GC Component with a linear-memory reference under the same WIT package and
observes `42/42`. This is one private measured record-lift row only; ordinary
host/WIT routing, nested/general aggregates, async/resource paths, and G5c
cutover remain pending.

### G5c C8 private manifest-backed mixed scalar-record lift

The descriptor manifest now also pins
`demo:marshal-record-mixed-host/api.read@1.0.0/lift` to a package/interface
fragment plus a package-less `probe` world fragment. The loader verifies the
concatenated source hash and `reading { code: u32, count: u64, status: s64 }`
signature before `gc_marshal_record_mixed_lift_probe.zig` emits the typed GC
result-area lift module. Its measured record is 24 bytes with alignment 8 and
field offsets `0/8/16`; the canonical import is `(i32)` and no GC reference
crosses the boundary.

`test_gc_marshal_record_mixed_lift_manifest_host.sh` verifies Component
assembly, source-hash drift rejection, and Rust/Wasmtime host execution with
`sum=37` from `{7, 35, -5}`. The paired
`test_gc_marshal_record_mixed_lift_manifest_equivalence.sh` compares the
generated GC Component with a linear-memory reference and observes `37/37`.
This is one private measured mixed-record lift row only; ordinary host/WIT
routing, nested/general aggregates, async/resource paths, and G5c cutover
remain pending.

### G5c C9 private manifest-backed indirect scalar-record lower

The descriptor manifest now also pins
`demo:marshal-record-indirect-lower/api.write@1.0.0/lower` to a package/
interface fragment plus a package-less `probe` world fragment. The loader
verifies the concatenated source hash and the 17-field `u64` `writing` record
signature before `gc_marshal_record_indirect_lower_manifest_probe.zig` emits
the typed GC indirect lower module. Its measured record is 136 bytes with
alignment 8; the canonical import is a single `(i32)` pointer to the
canonical record area, and no GC reference crosses the boundary.

`test_gc_marshal_record_indirect_lower_manifest_host.sh` verifies Component
assembly, source-hash drift rejection, and the existing Rust/Wasmtime host
adapter (`result=42`, `write-calls=1`). The paired
`test_gc_marshal_record_indirect_lower_manifest_equivalence.sh` compares the
generated GC Component with the linear-memory reference and observes
`42/42` and `1/1` callback counts. This is one private measured indirect
record-lower row only; layouts beyond the pinned 17-field shape, ordinary
host/WIT routing, nested/general aggregates, async/resource paths, and G5c
cutover remain pending.

### G5c C10 private manifest-backed nested scalar-record lift

The descriptor manifest now also pins
`demo:marshal-record-nested-host/api.read@1.0.0/lift` to a package/interface
fragment plus a package-less `probe` world fragment. The loader verifies the
concatenated source hash and the nested `reading { header: header, status: s64 }`
signature before `gc_marshal_record_nested_lift_probe.zig` emits recursive GC
record construction. The measured `header` is 16 bytes/alignment 8 with field
offsets `0/8`; the outer `reading` is 32 bytes/alignment 8 with `status` at
offset `16`. The canonical import is one `(i32)` result-area pointer and no GC
reference crosses the boundary.

`test_gc_marshal_record_nested_lift_manifest_host.sh` verifies Component
assembly, source-hash drift rejection, and Rust/Wasmtime host execution
(`sum=37`). The paired
`test_gc_marshal_record_nested_lift_manifest_equivalence.sh` compares the
generated recursive GC Component with the linear-memory reference and observes
`37/37`. This is one private measured nested-lift row only; deeper/general
aggregates, broader nested lower, ordinary host/WIT routing, async/resource
paths, and G5c cutover remain pending.

### G5c C11 private manifest-backed nested scalar-record lower

The descriptor manifest now also pins
`demo:marshal-record-nested-lower/api.write@1.0.0/lower` to a package/interface
fragment plus a package-less `probe` world fragment. The parser-backed route
binds a two-level `writing { header: header, status: s64 }` value and the
measured layout: `header` is 16 bytes/alignment 8 with fields at offsets `0`
and `8`, while `writing` is 32 bytes/alignment 8 with `status` at offset `16`.
The WIT-derived canonical import is `(i32, i64, i64)`; recursive GC field
flattening emits no GC reference at the Component boundary.

`test_gc_marshal_record_nested_lower_manifest_host.sh` verifies Component
assembly, source-hash drift rejection, measured child-count rejection through
the route tests, and Rust/Wasmtime host execution (`result=42`,
`write-calls=1`). The paired
`test_gc_marshal_record_nested_lower_manifest_equivalence.sh` compares the
generated recursive GC lower path with the linear-memory reference and
observes `42/42` and `1/1` callback counts. This is one private measured
two-level nested-lower row only; deeper or indirect nested layouts, ordinary
host/WIT routing, async/resource paths, and G5c cutover remain pending.

### G5c C12 private manifest-backed three-level nested scalar-record lower

The descriptor manifest now also pins
`demo:marshal-record-nested-lower-deep/api.write@1.0.0/lower` to a
package/interface fragment plus a package-less `probe` world fragment. The
parser-backed route binds `writing { detail: detail, tail: s64 }`, with
`detail { header: header, status: s64 }` and
`header { code: u32, count: u64 }`, before
`gc_marshal_record_nested_lower_deep_probe.zig` emits the recursive GC field
flattening. The measured layouts are `header=16`, `detail=32`, and
`writing=48` bytes, with offsets `0/8`, `header@0`, `status@16`, and
`tail@32`. The WIT-derived canonical import is
`(i32, i64, i64, i64)` and no GC reference crosses the boundary.

`test_gc_marshal_record_nested_lower_deep_manifest_host.sh` verifies Component
assembly, source-hash and measured-shape route checks, and Rust/Wasmtime host
execution (`result=42`, `write-calls=1`). The paired
`test_gc_marshal_record_nested_lower_deep_manifest_equivalence.sh` compares
the generated three-level GC flattening with the linear-memory reference and
observes `42/42` and `1/1` callback counts. This is one private measured
three-level lower row only; deeper/general aggregates, indirect nested layouts
beyond this shape, ordinary host/WIT routing, async/resource paths, and G5c
cutover remain pending.

### G5c C13 private manifest-backed three-level nested scalar-record lift

The descriptor manifest now also pins
`demo:marshal-record-nested-lift-deep/api.read@1.0.0/lift` to a
package/interface fragment plus a package-less `probe` world fragment. The
parser-backed route binds `reading { detail: detail, tail: s64 }`, with
`detail { header: header, status: s64 }` and
`header { code: u32, count: u64 }`, before
`gc_marshal_record_nested_lift_deep_probe.zig` emits recursive GC record
construction. The measured canonical result-area layout is
`header=16`, `detail=24`, and `reading=32` bytes, with leaf offsets
`code@0`, `count@8`, `status@16`, and `tail@24`. The canonical import remains
one `(i32)` result-area pointer and no GC reference crosses the boundary.

`test_gc_marshal_record_nested_lift_deep_manifest_host.sh` verifies Component
assembly, source-hash and measured-shape checks, and Rust/Wasmtime host
execution (`sum=42`). The paired
`test_gc_marshal_record_nested_lift_deep_manifest_equivalence.sh` compares the
generated three-level GC construction with the linear-memory reference and
observes `42/42`. This is private measured evidence only; deeper/general
aggregates, ordinary host/WIT routing, async/resource paths, and G5c cutover
remain pending.

### G5c C14 private manifest-backed four-level nested scalar-record lift/lower

The descriptor manifest pins
`demo:marshal-record-nested-lift-deeper/api.read@1.0.0/lift` and
`demo:marshal-record-nested-lower-deeper/api.write@1.0.0/lower` for the
four-level `reading.detail.header.leaf` / `writing.detail.header.leaf` scalar
tree. The measured layouts are 16/24/32/40 bytes and the flattened leaf
offsets are `code@0`, `count@8`, `status@16`, `marker@24`, and `tail@32`.
Lower uses canonical `(i32,i64,i64,i64,i64)` and lift uses one `(i32)`
result-area pointer; no GC reference crosses the boundary.

The paired host gates observe `sum=42` and `result=42` with one lower callback;
the equivalence gates observe `42/42` and `1/1` callback counts. Source-hash
and measured-shape drift fail closed. This remains the private measured
provenance for the exact shape; the ordinary synchronous route promotion is
recorded below. Arbitrary/deeper/general aggregates, async/resource paths,
and G5c cutover remain pending.

### G5c C14 default four-level synchronous host/WIT route (2026-08-22)

The ordinary `do build` path now admits only the two exact C14 descriptors
through the manifest-backed synchronous `@host_func` route; no private
selector is required. The source validator recursively checks the ordered
`Reading`/`Writing` -> `Detail` -> `Header` -> `Leaf` record tree, scalar
types, synchronous host shape, and exact WIT locator/member before any WAT is
written. The canonical imports remain `(i32)` for lift and
`(i32, i64, i64, i64, i64)` for lower; no GC reference crosses the boundary.
The explicit `--gc-wit-marshal` route remains available as private measured
coverage for the same descriptors.

The default host, equivalence, and negative gates are green. They observe
`sum=42`, `result=42`, one lower callback, `42/42` equivalence, and fail before
WAT for async, locator/member, or nested-shape drift; the focused C14 emitter
tests are `3/3` green. Arbitrary aggregates, async/resource lowering,
ownership syntax, and G5c cutover remain pending.

### G5c bounded mixed scalar-record lower default route (2026-08-22)

The ordinary synchronous `@host_func` route now admits the exact
`demo:marshal-record-mixed-lower/api.write@1.0.0/lower` descriptor for
`Writing { code: u32, count: u64, status: i64 }`. The measured record is
24 bytes with alignment 8; its canonical import is `(i32, i64, i64)` and no
GC reference crosses the boundary. The compiler-generated route uses the
manifest-backed adapter directly from ordinary `do build`.

Run the bounded default gates with:

```bash
bash examples/gc-p3-runtime/test_gc_default_host_route_mixed_lower_host.sh
bash examples/gc-p3-runtime/test_gc_default_host_route_mixed_lower_equivalence.sh
bash examples/gc-p3-runtime/test_gc_default_host_route_mixed_lower_negative.sh
```

The host and compiler-vs-ARC equivalence gates observe `result=42` and
`write-calls=1/1`. Async, shape, and member drift reject before WAT, while an
unadmitted host fixture retains its ARC route. General aggregates,
async/resource lowering, ownership syntax, and full G5c cutover remain pending.

### G5c C15-B private manifest-backed scalar-plus-text record lower

The descriptor manifest pins
`demo:marshal-record-managed-lower/api.write@1.0.0/lower` for
`writing { code: u32, label: string }`. The measured record layout is 12
bytes: `code@0`, `label.ptr@4`, and `label.len@8`. `wasm-tools 1.255.0`
accepts only the flat canonical import `(i32, i32, i32)` for this WIT shape,
so the GC emitter passes `code`, `label.ptr`, and `label.len` without a GC
reference.

The lower path validates the text length, allocates one temporary linear span
with `cabi_realloc`, copies the GC bytes, performs one host call, and frees
the span once after that call.
`test_gc_marshal_record_managed_lower_manifest_host.sh` observes
`code=7`, `label=hello`, `write-calls=1`, `allocations=1`, and
`frees=1`; the paired
`test_gc_marshal_record_managed_lower_manifest_equivalence.sh` observes the
same fields, call count, and cleanup counts for GC and the linear-memory
reference. Source-hash and measured-child drift fail closed.

This exact root is now also admitted by the ordinary `do build` host/WIT route.
`test_gc_default_host_route_c15b.sh` and the C15-B compiler boundary gate
require the manifest-backed canonical import, `$writing` GC parameter,
call-before-cleanup order, and no ARC marker. General managed-record lower,
multiple managed fields, text/list record lower, async/resource paths, and
full G5c cutover remain pending.

### Bounded scalar-record result lift

`test_gc_marshal_record_host.sh` assembles `marshal-record-host.wit` with the
hand-authored core module, whose canonical `read` import receives one
result-area pointer. The host writes `{code: 20, count: 22}`; the guest checks
the measured eight-byte span, loads both scalar fields into a GC record, and
returns their sum (`42`). The paired `test_gc_marshal_record_equivalence.sh`
compares this GC path with a linear-memory result-area path and requires both
to return `42`. This is a bounded `lift` proof only: flat scalar-record
`lower` is covered by the separate checkpoint below; indirect/nested or managed
fields, arbitrary aggregates, and compiler default-route wiring remain outside
the gate.

`test_gc_marshal_record_component.sh` separately generates the Core module
from the parser-backed WIT registry adapter and measured record plan, then
runs the pinned Core/WIT Component assembly and validation sequence. It also
checks member-identity drift and rejects a synthetic canonical import carrying
a GC reference. This is assembly evidence only; the host runner above remains
the execution evidence and the default host/WIT route remains ARC-backed.

### Bounded scalar-record flat lower

The parser-backed lower probe resolves `write(value: writing)` and emits the
measured flat canonical Core import `(i32, i32)`. The Component-level host
callback still receives one record and verifies `{code: 7, count: 35}` with one
call and guest result `42`. The paired lower equivalence gate compares the GC
record path with a flat Core reference path and observes `42/42`. This slice
does not admit indirect layouts beyond the pinned 17-field shape, nested/text/list
fields, or default compiler routing.

### Bounded indirect scalar-record lower

`test_gc_marshal_record_indirect_lower_host.sh` covers a parser-backed WIT
record with 17 `u64` fields. The pinned `wasm-tools 1.255.0` canonical import
uses one `(i32)` pointer; the measured record span is 136 bytes with 8-byte
alignment. The GC module allocates the span with `cabi_realloc`, stores fields
at measured offsets, calls the host, and frees the span. The Component/Rust/
Wasmtime gate observes `result=42` and one write callback. The paired
`test_gc_marshal_record_indirect_lower_equivalence.sh` observes `42/42` and one
callback per GC/flat path. This is a bounded lower/equivalence proof only;
arbitrary indirect layouts, nested aggregates, and default compiler routing
remain outside the gate.

## GC migration admission ledger

`src/build/test/check_gc_migration_inventory.sh` is the authoritative
machine-readable G5a/G5b/G5c ledger for default managed paths. It now links
the parsed G5a slices above to the direct nested-struct, Tuple, scalar-list,
payload-union, generic, and imported-managed fixtures plus bash-invokable probe
scripts, and
intentionally fails while any remaining G5a, ARC/GC equivalence, or default
cutover cell is pending. Passing one `--gc-core` token-profile probe does not
complete or widen this ledger. Pending boundaries are current implementation
records, not negative-probe claims.

The focused gates pass the imported-managed pipeline tests, the nested-struct
and Tuple Wasmtime probes, and the ARC/GC matrix with 24 green rows and zero
pending admitted rows. The matrix includes backend-neutral compiled fixtures
for the bounded payload-union construction, resolved generic managed identity,
and the direct `[u8]`/`text` call producers plus the private scalar-plus-text
record lower row. The imported text identity row uses
a file-backed module graph in both the normal fixture and the GC probe; host/WIT
imports remain outside this equivalence slice, while admitted synchronous
normal builds use typed GC and unconverted paths retain the ARC transition
fallback. The bounded resource Result cancellation gate separately compares
the generated GC Component with a hand-authored linear Component and requires
identical terminal observations.

The default-route build/parse gate is
`src/build/test/check_gc_default_build_gate.sh`. It checks the exact 69-file
admitted manifest, builds each fixture through ordinary `do build`, requires
the GC lowering markers, rejects `__arc_`, and parses each WAT with
`wasm-tools 1.255.0`. The gate is a syntax and routing check; it does not
replace the Wasmtime execution probes or close G5c.

`async-frame-table.wat` validates the internal async-frame bridge used by the
selected P3 clocks/cancellation lowering. A Core table roots each GC frame
while a host retains only its `i32` slot handle. The probe clears a completed
slot, links that handle through a GC-private free-slot node, then proves the
next frame reuses the same handle. It also holds two frames concurrently to
verify distinct live slots and reuses the first released slot while the second
remains rooted. Saved frame values remain GC struct fields and no GC reference
crosses the Component boundary or shares canonical ABI memory.

## ARC semantic baseline

The active ARC backend remains the semantic baseline for cleanup behavior:

| Fixture | Existing evidence | Task 0 limitation |
| --- | --- | --- |
| `src/build/test/compile_ok/142_defer_lifo_multiple_cleanups_lower.do` | `cleanup_b` lowers before `cleanup_a`, proving LIFO defer order. | Synchronous return only. |
| `src/build/test/compile_ok/150_defer_recv_loop_control_lower.do` | `continue` and `break` lower the loop-local defer before ARC release of `tmp`. | `recv(xs)` is existing loop syntax, not a suspended host receive. |
| `src/build/test/compile_ok/276_wasi_func_do_sig_and_resource.do` | `descriptor.drop` lowers as `[resource-drop]descriptor`. | It does not exercise a pending host operation or cancellation acknowledgement. |

The intended future sequence is fixed as:

```text
cancel request -> host terminal outcome -> LIFO defer -> resource drop -> frame invalidation
```

`Complete` can still win after a cancel request; only the host terminal outcome
decides whether cleanup begins. Task 0 does not dynamically verify that
sequence. Tasks 5 and 8 must execute it against the host-driven P3 runtime.

## Future ownership table

This table is the GC runtime target, not a claim about the active ARC backend.

| Item | Memory owner | Logical owner | Destruction rule |
| --- | --- | --- | --- |
| GC frame | GC heap | Scope while its task is live | Scope invalidates it only after terminal outcome and cleanup; GC reclaims it once unreachable. |
| GC value object | GC heap | Reachable source/runtime values | GC reclaims it once unreachable; no resource drop is attached. |
| Resource handle | Host resource table | Scope | Scope invokes the explicit idempotent drop exactly once; GC never drops it. |
| Defer payload | GC heap if it contains GC values | Scope defer stack | Scope consumes it in LIFO order before frame invalidation, then releases its roots. |
| P3 event buffer | Host before accepted delivery; guest ABI buffer after transfer | Receiving Scope after acceptance | Host frees or cancels an undelivered buffer; the receiving Scope releases an accepted buffer after handling or terminal cleanup. GC refs never cross the component boundary. |

## Future representation matrix

| Source/runtime category | Future Core Wasm representation | Update rule |
| --- | --- | --- |
| Scalar, value enum, small struct without managed fields | Core Wasm value | Copy by value. |
| Large struct, list, text, or value containing managed fields | GC object | Treat source values as immutable; rebuild/clone on update. |
| Private frame, channel queue, runtime cell | Mutable GC `struct` or `array` | `struct.set`/`array.set` are allowed only inside runtime-private ownership. |
| Ordinary source value update | New GC object | Never mutate an aliased source value; proven-unique runtime-private objects are the only later optimization boundary. |

## Task 0 gate

**Core GC representation: GO.** The recorded probe proves this exact Wasmtime
binary accepts and executes the selected Core GC instruction subset.

**Runtime/ARC switch: NO-GO.** It remains blocked on the Task 5
scheduler/byte-admission contract, Task 8 terminal-outcome cleanup, and Task 9
complete GC lowering plus copied ABI migration. The separate Wasmtime C
embedder experiment is neither a compiler nor an ARC/GC gate.

The byte-admission contract has a first executable model in
`src/build/async_byte_budget.zig`. It is instance-owned and transactional:
reserve before mutation, then commit or rollback; committed allocations are
released exactly once. The model covers frame, queue, text/list, and canonical
ABI byte formulas with checked overflow. It is a contract test only; until the
runtime's scheduler and allocation call sites consume it, this Task 0 gate
remains NO-GO.

The compiler-side `StreamWriterQueue` model now has an explicit
`init_with_budget` path. Accepted and pending queue entries retain allocation
tokens, and item consumption or writer finalization releases them exactly
once. The TaskFrame model now accounts the existing 16-byte header plus the
layout payload and emits `[async-frame-bytes]` metadata. The HTTP service model
also accounts its 64-byte per-handle canonical result slot and emits
`[canonical-buffer-bytes]`. These are compiler-side admission boundaries only;
generated frame allocators now carry the frame byte count through a checked
instance-local counter before `table.grow`, and generated HTTP result buffers
reserve their fixed 64-byte slot before `memory.grow` and release it after
terminal `task-return`. The counter detects overflow and returns bytes on
cleanup, but it is not yet a configurable quota or a scheduler admission
policy; non-HTTP canonical allocations remain unbudgeted.

The standalone `async-frame-table.wat` probe now executes a fixed 16-byte
runtime budget as well: two 8-byte frames, or one frame plus one 8-byte
canonical buffer, are admitted; the next allocation is rejected before
`table.grow`/`memory.grow`; and cleanup returns the bytes. This proves only the
isolated allocator ordering; the generated HTTP result-buffer helper now uses
the same counter, while the Component scheduler and non-HTTP canonical
allocators remain outside the gate.

`cabi-realloc-budget.wat` is the matching direct allocator probe. Run
`test_cabi_realloc_budget.sh` to verify grow/shrink usage, failed-growth
rollback (including unchanged heap ownership), and quota rejection. It keeps
the production `cabi_realloc` failure-as-trap behavior; its internal try path
exists only to observe the rollback state after a deliberately failed
`memory.grow`.

Successful output is evidence that this exact Wasmtime binary accepts and runs
the minimal Core GC artifact. It is not evidence of Component Model async,
WASI Preview 3, host linking, structured cancellation, resource cleanup, or
complete WASI support; those require their own probes and acceptance matrix.
## C15-C compiler opt-in

The fixed `{code: u32, label: string}` lower probe is also reachable through
the real compiler with the explicit private target:

```bash
./bin/do build src/build/test/compile_ok/01_start_entry_valid.do \
  --gc-wit-marshal demo:marshal-record-managed-lower/api.write@1.0.0/lower \
  -o /tmp/c15c.wat
```

The compiler path is fail-closed and accepts only that descriptor from
`doc/wit/gc_descriptor_manifest.json`. It emits the same canonical
`(i32, i32, i32)` import and temporary `cabi_realloc` copy/call/free sequence
as the direct C15-B route. The compiler-output gates are:

```bash
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_compiler_host.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_compiler_equivalence.sh
```

The explicit target remains available for probe/component assembly, while the
same manifest-backed C15-B shape is now selected automatically by ordinary
`@host_func` compilation. This does not imply general record, list, async,
resource, or G5c full-cutover support.

## C15-D private multi-managed-text lower

The C15-D descriptor
`demo:marshal-record-managed-lower-multi/api.write@1.0.0/lower` is a private,
explicit route for exactly:

```wit
record writing {
  code: u32,
  label: string,
  note: string,
}
```

The measured root layout is 20 bytes/alignment 4:
`code@0`, `label.ptr@4`, `label.len@8`, `note.ptr@12`, and `note.len@16`.
The canonical lower import is `(i32, i32, i32, i32, i32)` in
`code, label.ptr, label.len, note.ptr, note.len` order. Each text field is
length-checked, copied through one temporary `cabi_realloc` span, and freed
after the host call; GC references never cross the Component boundary.

The standalone and real compiler gates are:

```bash
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_manifest_host.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_manifest_equivalence.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_host.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_equivalence.sh
```

They observe `code=7`, `label=hello`, `note=world`, one `write` callback,
`allocations=2`, and `frees=2`; both equivalence gates report `2/2` allocation
and free counters and `1/1` callback counters. This does not change default
ARC-backed `@host`, and does not admit general managed records, text/list
aggregates, async/resource lowering, ownership syntax, or G5c full cutover.

## C16-A real source-level host boundary

C16-A promotes the C15-D probe only through a private, explicit declaration
adapter. The dedicated fixture is host-first because the parser requires
top-level imports before ordinary declarations:

```do
write = @host_func("demo:marshal-record-managed-lower-multi/api@1.0.0", "write", (Writing) -> nil)

Writing {
    code u32
    label text
    note text
}

start() {}
```

The adapter accepts only the exact locator/member, synchronous `@host_func`,
one `Writing` parameter, `nil` result, and ordered fields `code: u32`,
`label: text`, `note: text`. It then reuses the C15-D measured 20-byte root
and five-`i32` canonical lower. Unknown, mismatched, duplicate, extra, async,
or unsupported declarations fail before WAT and never fall back to ARC.

Run the boundary gate with:

```bash
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_boundary_negative.sh
```

The gate verifies async/mismatch rejection with no WAT artifact, the default
fixture's existing ARC marker and absence of the C16-A import, the C15-B/C15-D
compiler gates, and the G5c residual baseline. The full CLI reports
`UnknownP3AsyncHostDescriptor` for the async fixture because the existing
frontend registry check runs before the private adapter; focused validator
tests retain `AsyncGcWitHostDeclaration` coverage. This does not change default
`@host` routing or admit general aggregate, async/resource, ownership, or G5c
cutover support.

## C16-B fixed-descriptor host validator expansion

C16-B extends the private source-level validator to the earlier C15-B
descriptor as well as C16-A. The explicit adapter selects a fixed
descriptor specification (locator, member, record name, and ordered fields);
it does not infer arbitrary Do-to-WIT shapes. The C15-B host-first fixture is
`src/build/test/compile_ok/565_gc_wit_managed_record_host_boundary.do`:

```do
write = @host_func("demo:marshal-record-managed-lower/api@1.0.0", "write", (Writing) -> nil)

Writing {
    code u32
    label text
}

start() {}
```

Its explicit compiler route remains:

```bash
./bin/do build src/build/test/compile_ok/565_gc_wit_managed_record_host_boundary.do \
  --gc-wit-marshal demo:marshal-record-managed-lower/api.write@1.0.0/lower \
  -o /tmp/c16b-c15b.wat
```

The compiler host and ARC/GC equivalence gates observe `code=7`,
`label=hello`, one callback, and one allocation/free on both paths. The
negative/default gate is:

```bash
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_compiler_boundary_negative.sh
```

It rejects async and locator-mismatch fixtures before WAT emission, verifies
that no WAT artifact remains after rejection, and confirms that the default
C15-B fixture uses the manifest-backed GC route without ARC symbols. C16-B's
multi-managed-field descriptor remains private and opt-in; general aggregate
inference, async/resource lowering, ownership syntax, and G5c cutover remain
pending.

### G5c C16-C private managed-record lift compiler boundary

C16-C wires the measured C15-A lift probe into the real compiler through the
explicit descriptor:

```text
demo:marshal-record-managed-lift/api.read@1.0.0/lift
```

The source fixture is
`src/build/test/compile_ok/566_gc_wit_managed_record_lift_host_boundary.do`:
it contains one synchronous `@host_func` returning
`Reading { code: u32, label: text }`. The manifest-backed emitter uses the
12-byte result area (`code@0`, `label.ptr@4`, `label.len@8`) and canonical
`(func (param i32))`; the generated wrapper copies the host string into
`$do_bytes`/`$do_text` and returns `code + label.length`.

Run the compiler gates with:

```bash
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_compiler_host.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_compiler_equivalence.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_compiler_boundary_negative.sh
```

The host gate observes `value=12`; ARC/GC equivalence observes `12/12`. Async
and locator mismatch fixtures fail before WAT. At this historical C16-C
checkpoint, the ordinary default build used the manifest-backed route, emitted
`;; gc-sync`, and contained no ARC marker; the explicit target remains
available for the private probe. C15-D/C16-D admission was added by the later
2026-08-22 promotion below. General aggregate inference, async/resource
lowering, ownership syntax, and full G5c cutover remain outside this slice.

### Manifest-driven bounded compiler route closeout

The four private synchronous managed-record compiler routes now read their
`measured_layout` from `doc/wit/gc_descriptor_manifest.json` and derive the
source-level host boundary from the resolved WIT member and Do tokens. The
explicit `--gc-wit-marshal` routes remain available, while ordinary `@host`
compilation admits the seven verified C14 lift/lower, C15-B/C15-D lower,
C16-C/C16-D lift, and mixed scalar-record lower
descriptors; other shapes remain ARC-backed. The compiler host/equivalence and
negative/default gates pass, no GC reference crosses a canonical import, and
the focused emitter regression locks compiler root `$writing` with numeric
field indices. The migration inventory remains intentionally pending at
`complete_rows=15 pending_rows=15` with exit 1; general aggregate,
async/resource, ownership, and full G5c cutover support remain pending.

### G5c C16-D private multi-managed-field lift compiler boundary

C16-D wires the measured three-field lift into the real compiler through the
explicit descriptor:

```text
demo:marshal-record-managed-lift-multi/api.read@1.0.0/lift
```

The source fixture is
`src/build/test/compile_ok/581_gc_wit_managed_record_lift_multi_host_boundary.do`:
it contains one synchronous `@host_func` returning
`Reading { code: u32, label: text, note: text }`. The manifest-backed emitter
uses the 20-byte result area (`code@0`, `label.ptr@4`, `label.len@8`,
`note.ptr@12`, `note.len@16`) and canonical `(func (param i32))`; the generated
wrapper copies both host strings into `$do_bytes`/`$do_text` and returns
`code + label.length + note.length`.

Run the compiler gates with:

```bash
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_multi_compiler_host.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_multi_compiler_equivalence.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lift_multi_compiler_boundary_negative.sh
```

The host gate observes `value=17`; ARC/GC equivalence observes `17/17`. Async
and locator mismatch fixtures fail before WAT. This historical explicit gate
remains available, and the same descriptor is now also admitted by the
ordinary default route; general aggregate inference, async/resource lowering,
ownership syntax, and G5c cutover remain pending.

### G5c C15-D/C16-D default multi-managed-text route (2026-08-22)

The ordinary default compiler route now admits the exact C15-D lower and C16-D
lift descriptors in addition to the C14 lift/lower and C15-B/C16-C rows. The default host gates build
without `--gc-wit-marshal`, validate with `wasm-tools 1.255.0`, and run the
existing Rust/Wasmtime adapters. C15-D observes `code=7`, `label=hello`,
`note=world`, `allocations=2`, and `frees=2`; C16-D observes `value=17`.
Their paired equivalence gates observe `2/2` cleanup and `17/17` value.

The generated routes emit `;; gc-sync`, contain no `__arc_` marker, and keep GC
references out of canonical imports. Async and locator mismatch inputs fail
before WAT with no artifact. The executable probe adapts the compiler's
`_start` export to the WIT-required `run` export in a temporary WAT wrapper;
this is gate-local and does not change compiler semantics. General aggregates,
async/resource lowering, ownership syntax, and full G5c cutover remain
pending; inventory remains `complete_rows=15 pending_rows=15` with exit 1.

### G5c mixed text + `list<u32>` record lower default route (2026-08-25)

The ordinary synchronous `@host_func` route now admits one additional exact
descriptor:

```text
demo:marshal-record-mixed-text-u32-list-lower/api.write@1.0.0/lower
```

Its only accepted source shape is:

```text
Writing { code: u32, label: text, payload: [u32] }
```

The measured root is 20 bytes with offsets `code@0`, `label.ptr@4`, and
`payload.ptr@12`. The payload has capacity `3`, element size/alignment/stride
`4`, and the canonical lower import is five scalar `i32` words; no GC reference
crosses that boundary. The generated GC route copies the label and `u32`
payload into temporary linear spans, calls `write` once, and frees payload then
label exactly once. The host gate observes `code=7`, `label=hello`,
`payload=[10,20,5]`, two allocations, two frees, and one callback. The paired
ARC/GC equivalence gate observes `2/2` cleanup and `1/1` callback; eight
negative fixtures reject before WAT.

The default 82-fixture build/parse gate, residual host/equivalence/negative
gate, ReleaseSmall build, and release smoke pass with `wasm-tools 1.255.0`.
This remains fixed-shape evidence only: arbitrary aggregate/list lowering,
async/resource lowering, ownership syntax, and full G5c cutover remain
pending, with the migration ledger at `complete_rows=15 pending_rows=15`.

### G5c mixed text + `list<u32>` record lift default route (2026-08-25)

The ordinary synchronous `@host_func` route now admits one additional exact
descriptor:

```text
demo:marshal-record-mixed-text-u32-list-lift/api.read@1.0.0/lift
```

Its only accepted source shape is:

```text
Reading { code: u32, label: text, payload: [u32] }
```

The measured result area is 20 bytes with offsets `code@0`, `label@4`, and
`payload@12`. The payload has capacity `3`, element size/alignment/stride `4`,
and the canonical lift import is one scalar `i32` result-area pointer; no GC
reference crosses that boundary. The generated GC route validates the result
area and both linear spans, copies the label into `$do_bytes` and the payload
into `$do_u32`, frees payload then label exactly once, and constructs one GC
record. The host gate observes `code=7`, `label=hello`,
`payload=[10,20,5]`, `result=47`, `stats=34`, one callback, two allocations,
and two frees. The paired ARC/GC equivalence gate observes `47/47`, `34/34`,
and `1/1`; fixtures `640–647` reject before WAT.

The default 82-fixture build/parse gate, residual host/equivalence/negative
gate, ReleaseSmall build, and release smoke pass with pinned
`wasm-tools 1.255.0`. This remains fixed-shape evidence only: arbitrary
aggregate/list lifting, async/resource lowering, ownership syntax, and full
G5c cutover remain pending, with the migration ledger at
`complete_rows=15 pending_rows=15`.

### G5c mixed text + byte-list record lift default route (2026-08-25)

The ordinary synchronous `@host_func` route now admits the exact descriptor:

```text
demo:marshal-record-mixed-text-byte-list-lift/api.read@1.0.0/lift
```

Its only accepted source shape is:

```text
Reading { code: u32, label: text, payload: [u8] }
```

The measured result area is 20 bytes with offsets `code@0`, `label@4`, and
`payload@12`. The byte-list has capacity `4`, element size/alignment/stride `1`,
and the canonical lift import is one scalar `i32` result-area pointer; no GC
reference crosses that boundary. The generated GC route validates the result
area and both linear spans, copies the label and payload into `$do_bytes`, frees
payload then label exactly once, and constructs one GC record. The host gate
observes `code=7`, `label=hello`, `payload=[10,20,5]`, `result=47`, `stats=17`,
one callback, two allocations, and two frees. The paired ARC/GC equivalence gate
observes `47/47`, `17/17`, and `1/1`; fixtures `649–656` reject before WAT.

The current 82-fixture build/parse gate, residual host/equivalence/negative
gate, ReleaseSmall build, and release smoke pass with pinned
`wasm-tools 1.255.0`. This remains fixed-shape evidence only: arbitrary
aggregate/list lifting, async/resource lowering, ownership syntax, and full
G5c cutover remain pending, with the migration ledger at
`complete_rows=15 pending_rows=15`.

### G5c two `list<u32>` record lower default route (2026-08-25)

The ordinary synchronous `@host_func` route now admits one exact descriptor:

```text
demo:marshal-record-two-u32-lists-lower/api.write@1.0.0/lower
```

Its only accepted source shape is:

```text
Writing { code: u32, first: [u32], second: [u32] }
```

The measured root is 20 bytes with `code@0`, `first.ptr@4`/
`first.len@8`, and `second.ptr@12`/`second.len@16`. The two lists have
capacities `3` and `2`, element size/alignment/stride `4`, and the canonical
lower import is five scalar `i32` words; no GC reference crosses the boundary.
Both linear spans are range-checked before their copies. The host call occurs
once, and `cabi_realloc` frees `second` before `first`, exactly once each.

The host gate observes `code=7`, `first=[10,20,5]`, `second=[3,4]`, one
callback, two allocations, and two frees. The ARC/GC equivalence gate observes
the same values and `2/2` allocation/free counts; seven descriptor-drift
fixtures reject before WAT. The default 83-fixture build/parse gate and the
G5c residual baseline pass with pinned `wasm-tools 1.255.0`. This remains
fixed-shape evidence only: general aggregate/list lowering, async/resource
lowering, ownership syntax, and full G5c cutover remain pending, with the
migration ledger at `complete_rows=15 pending_rows=15`.

### G5c mixed text + two `list<u32>` record lower default route (2026-08-25)

The ordinary synchronous `@host_func` route now admits one exact descriptor:

```text
demo:marshal-record-mixed-text-two-u32-lists-lower/api.write@1.0.0/lower
```

Its only accepted source shape is:

```text
Writing { code: u32, label: text, first: [u32], second: [u32] }
```

The measured root is 28 bytes with `code@0`, `label.ptr@4`/`label.len@8`,
`first.ptr@12`/`first.len@16`, and `second.ptr@20`/`second.len@24`. Both lists
have capacities `3` and `2`, element size/alignment/stride `4`, and the
canonical lower import is seven scalar `i32` words; no GC reference crosses the
boundary. All three linear spans are range-checked before their copies. The
host call occurs once, and `cabi_realloc` frees `second`, `first`, then `label`,
exactly once each.

The host gate observes `code=7`, `label=hello`, `first=[10,20,5]`,
`second=[3,4]`, three allocations, and three frees. ARC/GC equivalence observes
the same values and `3/3` cleanup; seven descriptor-drift fixtures reject before
WAT. The default `86`-fixture build/parse gate, `run_tests.sh`
`pass=1388 fail=0 skip=3`, `zig test main.zig` `682/682`, residual,
semantic-equivalence, ReleaseSmall, and release smoke all pass with pinned
`wasm-tools 1.255.0`. This remains fixed-shape evidence only: general
aggregate/list lowering, async/resource lowering, ownership syntax, and full
G5c cutover remain pending, with the migration ledger at
`complete_rows=15 pending_rows=15`.

### G5c mixed text + two `list<u32>` record lift default route (2026-08-25)

The ordinary synchronous `@host_func` route now admits one exact descriptor:

```text
demo:marshal-record-mixed-text-two-u32-lists-lift/api.read@1.0.0/lift
```

Its only accepted source shape is:

```text
Reading { code: u32, label: text, first: [u32], second: [u32] }
```

The measured result area is 28 bytes with `code@0`, `label.ptr@4`/`label.len@8`,
`first.ptr@12`/`first.len@16`, and `second.ptr@20`/`second.len@24`. Both lists
have capacities `3` and `2`, element size/alignment/stride `4`, and the
canonical lift import is one scalar `i32` result-area pointer; no GC reference
crosses that boundary. The generated GC route validates all three spans before
copy, constructs `$do_bytes`, `$do_u32`, and `$do_u32`, frees `second`, `first`,
then `label` exactly once, and constructs one GC record.

The host gate observes `code=7`, `label=hello`, `first=[10,20,5]`,
`second=[3,4]`, `result=54`, `stats=51`, one callback, three allocations, and
three frees. The ARC/GC equivalence gate observes `54/54`, `51/51`, and
`1/1`; fixtures `674–681` reject before WAT. The default `86`-fixture
build/parse gate, residual gate, full regression (`pass=1388 fail=0 skip=3`),
Zig unit suite (`682/682`), ReleaseSmall build, and release smoke pass with
`wasm-tools 1.255.0`. This remains fixed-shape evidence only: arbitrary
aggregate/list lifting, async/resource lowering, ownership syntax, and full
G5c cutover remain pending, with the migration ledger at
`complete_rows=15 pending_rows=15`.

### G5c verification refresh (2026-08-26)

The current batch was rerun with focused marshal module/ops/WAT suites at
`90/90`, `43/43`, and `66/66`; lower/lift host execution, ARC/GC equivalence,
and negative gates pass. Full regression is `pass=1388 fail=0 skip=3`, Zig is
`682/682`, the default GC gate covers `86 fixtures`, and residual,
semantic-equivalence, ReleaseSmall, and release smoke pass with pinned
`wasm-tools 1.255.0`. The migration inventory remains intentionally open at
`complete_rows=15 pending_rows=15` with exit `1`.

The residual capability matrix and design gate are now complete in
`doc/superpowers/specs/2026-08-26-g5c-residual-capability-matrix.md`: all 15
rows appear exactly once, with one exact candidate and 14 blocked rows. No
general aggregate/list, async/resource, or ownership syntax is opened by this
gate.

### G5c mixed text + byte/u32-list lower candidate (2026-08-26)

The only admitted candidate is the synchronous, manifest-backed descriptor:

```text
demo:marshal-record-mixed-text-byte-u32-lists-lower/api.write@1.0.0/lower
```

Its source/WIT hash is
`sha256:2d966dfc68f27f42ba7ce5f44c471907cf2ebe922a9af24d3cfc810847cce9c3`.
The exact source shape is:

```text
Writing { code: u32, label: text, bytes: [u8], values: [u32] }
```

The measured root is 28 bytes with field offsets `0/4/12/20`; the canonical
lower import has seven scalar `i32` words and no GC reference. The host gate
observes `code=7`, `label=hello`, `bytes=[10,20,5]`, `values=[3,4]`, one
callback, and `3/3` allocations/frees. ARC/GC equivalence observes `3/3`
cleanup and `1/1` callback; seven descriptor-drift fixtures reject before WAT.
The focused suites (`90/90`, `43/43`, `66/66`), default GC gate (`86
fixtures`), residual/semantic-equivalence, full regression, Zig, ReleaseSmall,
and release smoke all pass with the pinned toolchain.

This remains a fixed-shape promotion. The inventory is still
`complete_rows=15 pending_rows=15` with exit `1`; general aggregate/list,
dynamic producers, async/resource lowering, ownership syntax, and full GC
cutover remain pending.

### 下一阶段计划

The mixed text/two-list lower and lift descriptors, and the exact
byte/u32-list candidate above, are complete and must not be repeated. The next
phase is release-candidate maintenance followed by a fresh admission review:
select at most one new synchronous, manifest-backed, measurable descriptor whose
canonical ABI has no GC reference and can reuse `LoadedRequest`/
`SyncValuePlan`. General aggregate/list, dynamic producers, async/resource
shapes, and `own<T>`/`borrow<T>`/`ref<T>` remain fail-closed until separately
designed and verified. No migration row is closed by these bounded promotions.
