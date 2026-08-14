# Core Wasm GC probe

This directory is a standalone capability probe for the Core Wasm GC
instructions intended for the future do runtime. It has no Component Model,
WIT, WASI, P3, host import, resource, or cancellation behavior.

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
WASMTIME_BIN="$(command -v wasmtime)" bash examples/gc-p3-runtime/test_do_gc_nested_managed_struct.sh
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
Nested child producers, nested paths, general Tuple/storage forms, non-`u8`
updates, multi-value put, and call-produced managed replacements fail closed
before WAT.

### Typed aggregate layout checkpoint

The parsed GC prelude orders nested managed struct types before their parents
and rejects missing children, recursive/cyclic layouts, resource fields, and
lowered-name collisions. A pure GC source containing a standalone
`@wasi_resource` declaration is rejected before WAT; WIT resources never enter
the Core-GC child graph. The admitted aggregate surface remains the direct-local
nested-child replacement, the single `Tuple<text, [u8]>` rewrite, one pure
`Unit | Bytes([u8])` carrier, and resolved generic calls bound to existing
concrete GC layouts described below. General tuples/storage, nested paths,
list-of-managed-struct values, generic layout instantiation, imports,
Component/WIT marshalling, async frames, and arbitrary producers remain
outside this probe directory's admission boundary.

The focused checkpoint report is
`.superpowers/sdd/2026-08-13-gc-g5a-aggregate-closure/task-3-report.md`.

Focused verification:

```bash
cd src && zig test build/codegen_gc_sync.zig
cd src && zig test build/gc_sync_probe.zig
WASMTIME_BIN="$(command -v wasmtime)" WASM_TOOLS_BIN="$(command -v wasm-tools)" bash src/build/test/check_gc_core_oracles.sh
```

The current focused counts are `142/142` for `codegen_gc_sync.zig` and `52/52`
for `gc_sync_probe.zig`. The managed scalar-array field probes pass for
`[bool]`, `[i8]`, `[i16]`, `[i32]`, `[i64]`, `[u16]`, `[u32]`, `[u64]`,
`[isize]`, `[usize]`, `[f32]`, and `[f64]` with `wasm-tools 1.255.0`
parsing and Wasmtime GC execution. `bash src/build/test/check_gc_migration_evidence_test.sh`
verifies the explicit marker required by future G5b/G5c evidence files.

The normal compiler path remains ARC until the later G5b equivalence and G5c
default-routing gates are closed.

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
Float `@put`, producer expressions, nested lists, and managed-element lists
remain outside this slice.

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
Wasmtime GC execution. Managed-field producers, nested paths, and
resource-containing structs remain outside this slice.

### Parsed pure payload-union slice

`gc-payload-union.do` is the bounded G5a union carrier probe. It admits only
`Unit | Bytes([u8])` payload-enum declarations, lowers the carrier to a typed
GC struct `(tag i32, bytes (ref null $do_bytes))`, and preserves source-value
immutability by allocating a new union for `Bytes(bytes)`. Its probe checks
old/new identity, tag and null-payload preservation, direct payload identity,
and replacement bytes. `test_do_gc_payload_union.sh` validates the emitted WAT
with `wasm-tools 1.255.0`, compiles/runs it with Wasmtime `47.0.2 -W gc=y`,
and requires `27815`.

This slice rejects additional or mixed payload slots, resource/nested-union/
Tuple/storage payloads, generic/imported/async values, Component/WIT lowering,
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

The 2026-08-14 focused gates pass the imported-managed pipeline tests, the
nested-struct and Tuple Wasmtime probes, and the ARC/GC matrix with eleven green
rows. The imported text identity row now uses a file-backed module graph in
both the normal ARC fixture and the GC probe; host/WIT imports remain outside
this equivalence slice and the normal build remains ARC.

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
