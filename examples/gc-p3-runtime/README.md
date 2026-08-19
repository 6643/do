# Core Wasm GC probe

This directory contains standalone Core Wasm GC probes and a small bounded
Component/WIT marshal probes for the future do runtime. The probes cover one
fixed synchronous `text` lower/copy/call path, a scalar-record result lift, and fixed synchronous
`list<u32>` lower/copy/call plus lift/result-area/copy paths with
Rust/Wasmtime hosts, plus a matching
fixed text and `list<u32>` ARC/GC observations. They do not imply general Component Model,
WIT, WASI, P3, resource, cancellation, general lift, or default compiler-route
support.

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
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_u32_equivalence.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_host.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_equivalence.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_component.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_lower_component.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_lower_host.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_marshal_record_lower_equivalence.sh
WASM_TOOLS_BIN="$(command -v wasm-tools)" bash examples/gc-p3-runtime/test_gc_wasi_random_list_lift_equivalence.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_f64_list_literal.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_f64_list_set.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_bool_list_set.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_remaining_scalar_lists.sh
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_imported_text_identity.sh
```

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
General tuples/storage, nested paths deeper than the admitted one-/two-/three-level
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

The current focused counts are `158/158` for `codegen_gc_sync.zig` and `52/52`
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
one-/two-/three-level managed-struct field paths, and
resource-containing structs remain outside this slice.

`three-level-nested-field-path.do` extends the same immutable rebuild shape to
three direct managed struct segments. Its probe checks the leaf scalar update,
the unchanged leaf byte payload, all intermediate scalar fields, and the outer
scalar field. The `wasm-tools 1.255.0`/Wasmtime GC probe and compiled-test
ARC/GC equivalence row both require the `27815` oracle. A fourth managed
segment, arbitrary producers, async/resource paths, and host/WIT remain
fail-closed.

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

### Bounded synchronous `list<u32>` ARC/GC equivalence

`test_gc_marshal_u32_equivalence.sh` assembles the fixed `list<u32>` lower
probe twice: once with the GC array path and once with the linear-memory
ARC-style path. The shared Rust/Wasmtime runner observes `[10, 20, 30]` from
both Components and checks exactly one allocation and one free on each path.
This closes equivalence for this one measured synchronous list shape only; it
does not wire the plan into `do build`, prove arbitrary records or lists, or
close the `host_wit_marshalling`/G5c inventory rows.

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
and Tuple Wasmtime probes, and the ARC/GC matrix with 23 green rows and zero
pending admitted rows. The matrix includes backend-neutral compiled fixtures
for the bounded payload-union construction, resolved generic managed identity,
and the direct `[u8]`/`text` call producers. The imported text identity row uses
a file-backed module graph in both the normal fixture and the GC probe; host/WIT
imports remain outside this equivalence slice, while admitted synchronous
normal builds use typed GC and unconverted paths retain the ARC transition
fallback. The bounded resource Result cancellation gate separately compares
the generated GC Component with a hand-authored linear Component and requires
identical terminal observations.

The default-route build/parse gate is
`src/build/test/check_gc_default_build_gate.sh`. It checks the exact 62-file
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
