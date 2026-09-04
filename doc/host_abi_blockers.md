# Host ABI Blockers

> **Superseded by GC-first (2026-08-11):** `doc/memory.md` and
> `doc/design/2026-08-11-gc-first-memory-decision.md` select Wasm GC as the
> v1 managed-memory target. ARC statements below remain historical evidence
> for the current transition implementation, not the active runtime contract.
> Source value semantics remain unchanged; future backend work targets GC, and
> Component/WIT resource ownership and drop remain explicit non-GC contracts.

### Current toolchain and harness boundary (2026-09-02)

The active Component toolchain is current-only through `bin/do-toolchain`, pinned
by `toolchain/toolchain.lock.json` to `wasm-tools 1.258.0` and Wasmtime `48.0.1`.
Task 9 Step 1's adapter gate and negative scans pass from the repository root and
an unrelated `/tmp` cwd. Task 8 Step 3 Rust host adapter batches are closed by
their scoped reports; Task 8 Steps 4/5 are closed by the thin `run_tests.sh`
wrapper, the entrypoint contract check, and the parity report. Task 9 Step 2
active documentation is synchronized. Task 9 Steps 3/5 are also closed:
default and both opt-in thin-entry runs report 14/14 steps and 50/50 tests,
ReleaseSmall/release smoke and the adapter/entrypoint gates pass, and the
workspace review found no generated target/cache artifacts. Rust Cargo tests
pass with the repository `zig-cc.sh` linker environment because this host has no
`cc`; the plain-command failure is an environment prerequisite, not an ABI
failure. Historical `wasm-tools 1.255.0` references below are evidence only and
are not active tool invocations.

WIT `map<K,V>` parser/model/manifest metadata is represented as a pair-list ABI
shape. `wit_abi_types` and the bounded Core WAT probe cover `u32` keys with
`u32`/`text` values in both lower and lift directions, and pass the current
toolchain's parse/validate checks. Generic Component/WIT map lowering,
synchronous lift, async input copy, and Stream cross-poll owned-buffer cleanup
are not implemented. Unsupported map marshal shapes must remain fail-closed
until those lifecycle paths have a real ABI emitter and focused runtime gates.

### G5c scalar-list internal route parameterization (2026-08-23)

The synchronous bounded record lower path now normalizes manifest `byte_list`
and `list<u32>` measurements into one internal `ManagedScalarListField` and
one parameterized WAT emitter. The only selected differences are GC array
kind, load/store instruction, measured stride, and measured capacity:
`u8 -> $do_bytes / array.get_s $do_bytes / i32.store8 / 1 / 4` and
`u32 -> $do_u32 / array.get $do_u32 / i32.store / 4 / 3`. The external
manifest kinds, canonical ABI, synchronous `@host_func` boundary, linear-span
guard, and exactly-once free contract are unchanged. This closes an internal
duplication debt only; general list/record shapes, list lift, async/resource,
ownership syntax, and full G5c cutover remain blocked.

### G5c bounded default host/WIT promotion (2026-08-23)

The ordinary `do build` path now admits only the eleven manifest-verified
synchronous managed-record descriptors: C14 lift/lower, C15-B/C15-D lower,
and C16-C/C16-D lift, plus the bounded mixed scalar-record lower and bounded
byte-list and `list<u32>` record lower/lift, including the fixed byte-list
record lift descriptor. C14 uses the
inline scalar bridge with canonical `(i32)` lift and
`(i32, i64, i64, i64, i64)` lower imports; mixed lower uses `(i32, i64, i64)`.
The default GC outputs,
canonical no-GC-reference boundary, host/equivalence gates, and negative gates
pass. The focused emitter tests remain green. General aggregates,
async/resource lowering, ownership syntax, and the full migration inventory
remain unadmitted. This is a bounded route promotion, not a complete G5c
cutover.

### G5c private `list<u32>` record lift descriptor (2026-08-23)

The explicit compiler route and ordinary default route now have independent
evidence for
`demo:marshal-record-u32-list-lift/api.read@1.0.0/lift`. Admission is limited
to one synchronous `@host_func` and the ordered record
`Reading { code: u32, payload: [u32] }`; the manifest measures a 12-byte
result area, list capacity `3`, accepted lengths `0..3`, and canonical
`(i32)` result-area input. The generated lift copies the linear `u32` payload
into `$do_u32`, frees it exactly once, and constructs the GC record without
crossing the canonical import with a GC reference.

The pinned `wasm-tools 1.255.0` host gate passes with `code=7`,
`payload=[10,20,30]`, `result=67`, one callback, and one allocation/free pair.
The ARC/GC equivalence gate passes with `67/67`, `17/17`, and `1/1`; fixtures
609-614 reject before WAT. This is a fixed-shape promotion only; general
list-record lift, async/resource lowering, ownership syntax, and full G5c
cutover remain blocked.

### G5c private byte-list record lower descriptor (2026-08-22)

The explicit compiler route now has independent evidence for
`demo:marshal-record-byte-list-lower/api.write@1.0.0/lower`. Admission is
limited to one synchronous `@host_func` and the ordered record
`Writing { code: u32, payload: [u8] }`; the manifest measures a 12-byte root
and derives canonical `(i32, i32, i32)` parameters. The generated lower path
copies the byte list into temporary linear memory, performs one host call, and
frees that buffer afterward. No GC reference crosses the canonical import.

The pinned `wasm-tools 1.255.0` host gate passes with
`code=7`, `payload=[10,20,5]`, `result=42`, one callback, and one
allocation/free pair. The ARC/GC equivalence gate passes with result `42/17`,
stats `17/17`, and allocation/free `1/1`; six async/locator/member/shape
negative fixtures reject before WAT. This is a fixed-shape default promotion
only; general list-record lower, async/resource lowering, ownership syntax,
and full G5c cutover remain blocked.

### G5c private `list<u32>` record lower descriptor (2026-08-22)

The explicit compiler route and ordinary default route now have independent
evidence for
`demo:marshal-record-u32-list-lower/api.write@1.0.0/lower`. Admission is
limited to one synchronous `@host_func` and the ordered record
`Writing { code: u32, payload: [u32] }`; the manifest measures a 12-byte root,
capacity `3`, accepted lengths `0..3`, and canonical `(i32, i32, i32)` lower
parameters. The generated path copies the GC `u32` array into temporary linear
memory, performs one host call, and frees that span afterward. No GC reference
crosses the canonical import.

The pinned `wasm-tools 1.255.0` host gate passes with `code=7`,
`payload=[10,20,30]`, `result=42`, one callback, and one allocation/free pair.
The ARC/GC equivalence gate passes with `42/17` and `1/1`; six async/locator/
member/shape negative fixtures reject before WAT. This is a fixed-shape
promotion only; general list-record lowering, async/resource lowering,
ownership syntax, and full G5c cutover remain blocked.

### G5c C14 default four-level synchronous host/WIT route (2026-08-22)

The ordinary synchronous `@host_func` compiler route now admits the exact C14
lift and lower descriptors for the four-level scalar tree. Before WAT emission,
the adapter recursively validates the Do record children, ordered scalar
fields, synchronous host declaration, and exact WIT locator/member. The
canonical imports remain `(i32)` for lift and `(i32, i64, i64, i64, i64)` for
lower, so no GC reference crosses the Component boundary. The explicit
`--gc-wit-marshal` route remains private measured coverage.

The default host/equivalence/negative gates are green, with focused C14 emitter
tests `3/3`. Async, locator/member, and nested-shape drift fail before WAT.
Arbitrary aggregates, async/resource lowering, ownership syntax, and full G5c
cutover remain unadmitted.

### G5c bounded mixed scalar-record lower default route (2026-08-22)

The ordinary synchronous `@host_func` route now admits the exact
`demo:marshal-record-mixed-lower/api.write@1.0.0/lower` descriptor for
`Writing { code: u32, count: u64, status: i64 }`. The measured record is
24 bytes with alignment 8; its canonical import is `(i32, i64, i64)` and no
GC reference crosses the boundary. Host execution and compiler-vs-ARC
equivalence both observe `result=42` and `write-calls=1/1`; async, shape, and
member drift reject before WAT, and unadmitted host imports retain ARC.

This is a fixed bounded promotion only. General aggregates, text/list record
lower, async/resource lowering, ownership syntax, and full G5c cutover remain
unadmitted.

## Core Wasm GC Runtime Probe

**Status:** Core GC representation: GO. G5a parsed fixed-index and
parameterized `[u8] @set`, single-value `[u8] @put`, direct `[u8]`/`[bool]`/`[u32]`/`[i16]`/`[i32]`/`[i64]`/`[f32]`/`[f64]`
managed-field payload, direct text/list/producer slices, and one bounded pure payload-union
carrier are GO.
Full GC compiler/runtime
migration: NO-GO; the default `do build` route now uses typed GC for the
70-file admitted synchronous fixture manifest and the eight exact manifest
host/WIT descriptors above, while unconverted shapes still use the ARC
transition path. This is not a Component Model or WASI compatibility result.

**Evidence:** `examples/gc-p3-runtime/gc-frame.wat` uses an immutable
`struct` for a source value, mutable `struct` fields for a runtime-private
frame, and a mutable `array` queue. `run-wasmtime.sh` runs that fixture with
`/home/_/Public/wasmtime/bin/wasmtime compile -W gc=y` (compile-or-validate)
followed by
`-W gc=y --invoke probe`. The guest traps unless its encoded result is `27815`,
which the script also asserts. The fixture deliberately has no imports and
cannot exercise host ABI behavior.

**Boundary:** passing this probe shows only that the selected Wasmtime accepts
and executes this Core GC instruction subset. It does not establish P3 async
ABI support, canonical ABI lowering, general resource cleanup, cancellation,
Component Model assembly, or complete WASI support. The bounded resource
terminal Component gate is recorded below as a separate G5a slice.

**Unblock condition:** complete every G5a managed-value and root slice, then
run G5b executable ARC/GC equivalence for each path, then satisfy the G5c
one-backend cutover residual gates. Current ARC implementation debt can then
be retired. The separate C embedder experiment is not a GC or compiler gate.

### G5b ARC/GC semantic equivalence checkpoint (2026-08-14)

**Status:** GO for the currently admitted synchronous rows. At this checkpoint
there were eleven rows. The checker
`src/build/test/check_gc_semantic_equivalence.sh` executes the normal compiled
test and the parsed GC probe as separate artifacts, then compares Do-level
observable success and the GC `27815` old/new-value oracle. It intentionally
does not compare WAT bytes, backend symbol names, or allocation identity.

The green rows cover `[u8]`, text, nested managed struct, managed Tuple,
`[u32]`/`[i16]`/`[f32]`/`[f64]` list updates, and file-backed imported text
identity. The migration inventory links the checker as G5b evidence for these
rows.

G5b async/resource executable coverage ledger: `doc/g5b_async_resource_coverage.md`.

The parsed GC probe also now covers the fixed-index `[bool]` update shape. Its
independent probe checks that the copied result changes the selected element
while the original typed GC array remains unchanged; `wasm-tools 1.255.0` and
Wasmtime `-W gc=y` return `27815`. This is G5a evidence only and is not an
additional ARC/GC equivalence row.

The parsed GC probe also covers direct managed-struct `[bool]`, `[u32]`,
`[i16]`, `[i32]`, `[i64]`, `[f32]`, and `[f64]` field replacement. The fixtures rebuild distinct `Box` objects,
preserve the original arrays and `tag == 7`, and store replacement arrays.
`wasm-tools 1.255.0` parsing and Wasmtime `-W gc=y` execution return `27815`.
This is an additional G5a managed-struct slice only; it does not close G5b or
widen the default route to unsupported struct shapes. The focused unit totals
at this checkpoint are `codegen_gc_sync.zig` `140/140` and
`gc_sync_probe.zig` `50/50`.

The bounded `Unit | Bytes([u8])` carrier remains G5a-only because the normal
ARC test entry rejects its managed payload declaration before test emission
with `NoMatchingCall`. The resolved generic managed GC slice remains G5a-only
because the normal ARC entry rejects an unconstrained generic managed field
update with `InvalidTypeRef`. These are confirmed current boundaries, not
silently skipped rows; each must gain an admitted ARC fixture before its G5b
cell can be marked complete.

**Boundary:** this is not a full G5b pass. Text outside the admitted slices,
general tuple/storage, host/WIT marshalling, async frames, general resource
terminal cleanup, and every pending producer/control-flow row still lack an
equivalence fixture. A bounded resource Result terminal Component gate now
exists as G5a evidence, but the admitted synchronous `do build` route still
uses typed GC only for its registered shapes;
unsupported shapes still remain on the ARC transition path. G5c cutover is
blocked until the remaining inventory cells have independent evidence.

### G5a bounded resource terminal cleanup (2026-08-18)

**Status:** GO for one private `Future<Result<response, error-code>>` resource
descriptor at the Component boundary. The gate
`examples/gc-p3-runtime/test_gc_resource_terminal_cleanup.sh` builds the
registered `async-resource-result-component.do` fixture, requires the pinned
`wasm-tools 1.255.0` toolchain, rejects `__arc_` and the linear-memory frame
allocator, and checks the GC `$async-frame` table, canonical Result buffer,
error terminal marker, frame release, and request/response resource-drop
imports. The generated guest Core contains no direct call to those drop
imports, preserving Component/WIT drop authority.

The gate parses, compiles with Wasmtime `-W gc=y`, embeds/creates/validates the
Component, and runs the existing Rust/Wasmtime pending, immediate, error,
cancel, and invalid-terminal-shape probes. The valid paths observe exactly-once
request/response cleanup and an empty resource table; invalid duplicate/drop
after-terminal shapes remain rejected.

**Boundary:** this is bounded G5a evidence, not general resource or async
admission. G5b ARC/GC equivalence for this row, G5c default routing, arbitrary
resource aggregates, and public ownership syntax remain pending. The normal
`do build` path for the async fixture currently returns
`error[AsyncLoweringUnavailable]`, so no ARC artifact exists for direct G5b
comparison; a separate async oracle or ordinary lowering admission is required.

### G5b payload-union and resolved-generic equivalence evidence (2026-08-16)

The two previously pending admitted rows now have backend-neutral compiled
fixtures: `compiled_ok/95_compiled_test_payload_union_gc_migration.do` covers
the bounded `Unit | Bytes([u8])` construction, and
`compiled_ok/96_compiled_test_generic_managed_gc_migration.do` covers resolved
generic managed identity through a concrete `Box`. The normal compiled test
artifacts and the independent `test_do_gc_payload_union.sh` and
`test_do_gc_generic_managed_identity.sh` probes pass with
`wasm-tools 1.255.0` and Wasmtime `-W gc=y`.

`NODE_BIN=/home/_/.local/bin/bun WASM_TOOLS_BIN=/home/_/.local/bin/wasm-tools
WASMTIME_BIN=/home/_/.local/bin/wasmtime bash
src/build/test/check_gc_semantic_equivalence.sh` now reports 18 green rows and
zero pending rows. This closes G5b for every currently admitted synchronous
slice; it does not admit general unions, generic layout instantiation,
host/WIT marshalling, async frames, resources, or any G5c default cutover.

### G5c host/WIT residual boundary (2026-08-16)

`src/build/test/compile_ok/274_wasi_preopens_list_tuple_lower.do` is the
current host/WIT managed-boundary residual checked by
`src/build/test/check_gc_g5c_residual_gate.sh baseline`. Its generated output
must retain the `wasi-bind` manifest record (`entry` / `host_preopens`) and the
canonical `cm32p2` import for `wasi:filesystem/preopens` / `get-directories`.
It must also retain the `__arc_` marker and must not contain the `gc-sync`
marker. The output is parsed with the pinned `wasm-tools 1.255.0`; these
assertions preserve the current residual routing and are not GC marshalling
evidence.

The `host_wit_marshalling` inventory row remains `pending`. The design gate is
`doc/superpowers/specs/2026-08-16-gc-canonical-marshal-plan-design.md`; it can
be promoted only after all of the following are independently evidenced: a
typed canonical-ABI marshal plan covering the currently measured `text`,
record, and bounded `list<u32>`/`list<u8>` shapes; an explicit boundary rule and
negative check that no Wasm GC reference crosses a Component/WIT ABI boundary;
and a separate ARC/GC semantic-equivalence runner for the same host/WIT
fixture. The fixed `list<u32>` lower/lift and ARC/GC equivalence gates are now
green. A separate scalar-record result-lift gate is also green: the measured
record plan emits a single result-area pointer import, checks the eight-byte
record span, loads both `u32` fields, constructs a GC record, and the pinned
Rust/Wasmtime runner observes their sum. General aggregate coverage and
parser-backed default compiler wiring remain open. Until those gates are green,
host/WIT output remains on the ARC residual path and G5c full cutover remains
blocked.

The bounded WAT unit now has a separate implementation in
`src/build/codegen_component_marshal_wat.zig`. It emits and unit-tests a core
function fragment for measured `text` and `list<u8>` lower/lift: 64-bit span
guards, `cabi_realloc`, GC byte copy/construction, canonical call, and cleanup.
A representative lower and lift shell parses with pinned `wasm-tools 1.255.0`.
This is not Component assembly or host execution evidence, and it does not
change the ARC residual route or close the inventory row.

Descriptor admission now has an explicit fail-closed unit: malformed
`sha256:` values and package/world/member/revision/hash drift are rejected by
`build_sync_value_plan_with_registry`, and `codegen_component_marshal_ops` runs
a recursive GC-reference boundary check before producing an operation plan.
The bounded parser-backed adapter is now available through
`build_sync_value_plan_from_wit_source`: it resolves the source with the WIT
parser/resolver, locates one value-only interface member, derives the package,
world, canonical member path, and resolver content hash, and then binds the
owned ABI type to measured `wit_abi_layout` facts. The binding-based helper is
private, so callers cannot bypass parser provenance with a fabricated
`BindingModel`. General Component execution and ARC/GC equivalence remain
separate blockers; the bounded text host probe is recorded below and the
inventory row is still pending.

The bounded synchronous text plan now also has a standalone Core-module
assembly checkpoint. `src/build/codegen_component_marshal_module.zig` wraps
the parser-backed plan with the measured `$do_bytes`/`$do_text` declarations,
linear memory, a typed `cabi_realloc`, and a descriptor-checked canonical
import. `examples/gc-p3-runtime/test_gc_marshal_text_component.sh` runs the
exact pinned `wasm-tools 1.255.0` sequence (`parse`, `component embed`,
`component new`, `validate`, and `component wit`) against
`marshal-text-assembly.wit` and `marshal-text-core.wat`. It also rejects a
renamed WIT member and a synthetic canonical import containing a GC reference.
This closes only Core/WIT assembly validation for one synchronous `string`
lowering shape; it does not provide host execution, ARC/GC equivalence, list
or record Component coverage, or G5c cutover. The inventory row remains
`pending` and the default host/WIT route remains ARC-backed.

The separate `examples/gc-p3-runtime/test_gc_marshal_text_host.sh` gate now
assembles `marshal-text-host.wit` and `marshal-text-host.core.wat`, then runs
the Component with the Rust/Wasmtime `gc_marshal_text` host runner. The guest
constructs a fixed GC text value and the host observes exactly one canonical
`hello` string argument. This is the first bounded host-driven lower/copy/call
evidence; it is not compiler default-route evidence and does not establish
lift, general WIT shapes, or ARC/GC semantic equivalence. Those gates and the
`host_wit_marshalling` inventory row remain pending.
The gate supplies the repository's `rust-host-runner/zig-cc.sh` as the
default Rust C compiler and linker (override with `RUST_RUNNER_CC` when
needed), so it does not depend on a system `cc` being present.

`examples/gc-p3-runtime/test_gc_marshal_text_equivalence.sh` now supplies the
matching bounded equivalence gate. It executes a GC fixture and a separate
linear-memory ARC-style fixture under the same WIT world, compares the
observed `hello` value, and requires one allocation and one free in each
path. The result is evidence for this fixed text shape only; default compiler
routing, text lift, aggregate shapes, and broader host/WIT equivalence remain
pending. The equivalence gate uses the same runner linker configuration as the
host gate.

The fixed `list<u32>` slice now has independent lower and result-area lift
host gates in `examples/gc-p3-runtime/test_gc_marshal_u32_host.sh` and
`test_gc_marshal_u32_lift_host.sh`, plus
`test_gc_marshal_u32_equivalence.sh`. The pinned runner observes
`[10, 20, 30]` on both GC and ARC-style paths, with one allocation and one
free per path. This closes only the measured scalar-list boundary; arbitrary
lists, parser-backed compiler wiring, and the inventory row remain pending.

The bounded scalar-record result-lift gate in
`examples/gc-p3-runtime/test_gc_marshal_record_host.sh` parses and validates
`marshal-record-host.core.wat`, embeds `marshal-record-host.wit`, and runs the
component with `gc_marshal_record.rs`. The host returns `{code: 20, count: 22}`
through the canonical result area and the guest verifies `sum=42`. This closes
only scalar record `lift`; record `lower`, nested/text/list fields, arbitrary
aggregates, compiler default-route wiring, and G5c remain pending.

The paired `examples/gc-p3-runtime/test_gc_marshal_record_equivalence.sh` gate
runs the GC record-result path and a linear-memory result-area path under the
same WIT world. Both pinned Wasmtime executions observe the same `sum=42`;
this is semantic equivalence for this fixed record lift only, not a general
aggregate or compiler-route equivalence result.

The parser-backed assembly gate in
`examples/gc-p3-runtime/test_gc_marshal_record_component.sh` now generates
the record Core module through `src/build/gc_marshal_record_probe.zig` and
validates it with the pinned `wasm-tools 1.255.0` parse/embed/new/validate/
component-wit sequence. It rejects a renamed `read` member and a synthetic
canonical import containing a GC reference. This closes only the
parser-backed Core/WIT assembly checkpoint; the host runner remains a separate
execution fixture, default compiler-route wiring is still absent, and the
`host_wit_marshalling`/G5c rows remain pending.

### 2026-08-18 parser-backed record route execution

`src/build/codegen_component_marshal_route.zig` is now the private bounded
route from WIT source to measured marshal plan, canonical import derivation,
and Core module emission. The record probe consumes this route rather than
hard-coding a package/member identity. The record host gate now generates the
Core WAT with that route, assembles it against `marshal-record-host.wit`, and
the pinned Wasmtime runner observes `sum=42`. The paired equivalence gate also
generates its GC artifact through the same route and observes `42/42` against
the linear-memory path.

This closes the generated-path evidence for the bounded scalar-record `lift`
slice only. The normal `do build` host/WIT route remains ARC-backed; the
bounded indirect record lower probe is tracked separately below. Nested/text/list
aggregates, arbitrary WIT shapes, async/resource paths, and G5c default cutover
remain pending. The inventory split keeps the
managed-struct list append G5b residual separate from the other-list row. The
inventory now records `host_wit_marshalling` as G5a/G5b complete and G5c
pending; this is bounded evidence, not a full host/WIT or default-GC closure.

### 2026-08-18 parser-backed scalar-record lower

The lower probe resolves `write(value: writing)` through the parser-backed
route and binds two measured `u32` fields. Pinned `wasm-tools 1.255.0` requires
the Core canonical import `(i32, i32) -> nil` for this flat record; the
Component-level Wasmtime callback receives one `Record` value with fields
`code=7` and `count=35`. The generated Component assembly, host execution, and
GC/flat equivalence gates pass with guest result `42` and exactly one callback
per path. No GC reference crosses the boundary and this shape allocates no
temporary linear span.

This closes only flat scalar-record `lower`. Indirect records outside the
pinned shape, nested/text/list fields, arbitrary aggregate shapes, default
host/WIT compiler routing, async/resource paths, and G5c cutover remain
pending.

### 2026-08-18 parser-backed mixed scalar-record lower

The private parser-backed route also covers a measured three-field record:
`code: u32`, `count: u64`, and `status: s64`. With the pinned
`wasm-tools 1.255.0`, the canonical Core import is the flat shape
`(i32, i64, i64)`; the measured record span is 24 bytes with fields at offsets
`0`, `8`, and `16`. The generated Component host gate observes
`7,35,-5`, returns `42`, and invokes the host callback exactly once. The
paired linear-memory reference path returns `42` with the same callback count.

The gate rejects GC references at the canonical import boundary and validates
the generated Component with the current toolchain. This is still bounded
flat scalar evidence: the pinned indirect record shape is tracked by the
separate checkpoint below; nested/text/list fields, arbitrary aggregates,
default host/WIT compiler routing, async/resource paths, and G5c cutover remain
pending.

### 2026-08-18 parser-backed indirect scalar-record lower

The private parser-backed route now covers one measured indirect record: a WIT
record with 17 `u64` fields. Pinned `wasm-tools 1.255.0` requires one `(i32)`
canonical Core import parameter; `wit_abi_layout` measures a 136-byte span with
8-byte alignment. The GC emitter allocates that span with `cabi_realloc`, writes
the fields at measured offsets, calls the host, and frees the span. No GC
reference crosses the canonical boundary.

`examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_host.sh` passes
Core parse/embed/new/validate and Rust/Wasmtime execution with `result=42` and
`write-calls=1`. The paired
`test_gc_marshal_record_indirect_lower_equivalence.sh` passes the GC/flat
comparison with `results=42/42` and `write-calls=1/1`. This closes only the
pinned 17-field indirect lower/equivalence slice; arbitrary indirect layouts,
nested/text/list aggregates, default host/WIT compiler routing, async/resource
paths, and G5c cutover remain pending.

### G5a body-only managed-struct storage routing (2026-08-16)

The ordinary synchronous route now admits a bounded body-only storage shape:
`start()` may construct a managed struct local, rebuild it with a scalar field
`@set`, and read a managed child with `@get`. The new
`examples/gc-p3-runtime/managed-struct-storage.do` probe and
`compiled_ok/98_compiled_test_managed_struct_storage_gc_migration.do` fixture
verify that the old object remains observable while the rebuilt object carries
the changed field. The GC locals boundary filters the generic collector's
legacy `__storage_*` and `__struct_literal_tmp` compiler locals; the dedicated
gate also rejects `__arc_`, parses with `wasm-tools 1.255.0`, and executes with
Wasmtime GC enabled. This is one G5a/Task 3 storage slice only; inferred lists,
nested/general producers, host/WIT marshalling, async frames, resource cleanup,
and G5c remain pending.

After the corresponding GC expectation migration, the full compiler harness is
`pass=1260 fail=0 skip=3`; with `RUN_WASM=1` it is `pass=1262 fail=0 skip=3`.
These gates include the typed-array prelude fix for start-local scalar lists
and the fail-closed `recv(...)` loop guard.

### G5a inferred managed list storage routing (2026-08-16)

The ordinary synchronous route now admits bounded inferred scalar-list storage
shapes: an explicit `[u8]` or `[u32]` seed followed by
`values = @put(seed, 2)` and a no-result return. The collector marks `values`
as a fresh managed root; the typed GC emitter copies the published typed array
before append and emits no ARC or legacy storage compiler locals.
`inferred-list-storage.do` and `inferred-u32-list-storage.do`, with their
dedicated gates, pass the pinned `wasm-tools 1.255.0` parse and Wasmtime GC
run. Dynamic producers, inferred non-scalar lists, multi-value/spread `@put`,
other storage control flow, host/WIT marshalling, async frames, resource
cleanup, and G5c remain pending.

### G5a managed-struct list append routing (2026-08-16)

`managed-struct-list.do` now also covers one-value
`@put(boxes, value)` for a managed `[Box]` list. The dedicated probe checks
source-list preservation, the appended element, typed
`array.copy $do_list_box $do_list_box`/`array.set $do_list_box` lowering, and
the `27815` Wasmtime GC oracle after `wasm-tools 1.255.0` parsing. The default
GC build manifest remains 58 fixtures and passes.

This remains G5a-only: the normal compiled/ARC entry rejects `[Box]` list
shapes with `NoMatchingCall`, so the semantic-equivalence matrix stays at 18
green rows and no G5b row is claimed. Nested-list producers, host/WIT
marshalling, async frames, resource cleanup, and G5c remain pending.

### G5b bounded nested byte-list producer evidence (2026-08-16)

`examples/gc-p3-runtime/nested-byte-list-put.do` now covers the exact direct
producer `append(rows [[u8]], row [u8]) -> [[u8]]` with `@put(rows, row)`. The
independent probe checks that the source outer array and its original inner row
remain unchanged, the result has length two, and the appended row contains
`4, 5`. `wasm-tools 1.255.0` parsing and Wasmtime `-W gc=y` execution pass the
`27815` oracle. The same fixture runs through the ordinary compiled test entry
without `__arc_`, so the equivalence checker reports 18 green rows.

This is a single bounded nested-list producer shape. General nested producer
expressions, managed-struct/nested-list combinations beyond `[[u8]]`,
spread/multi-value `@put`, host/WIT marshalling, async frames, resource cleanup,
and G5c full cutover remain pending.

### G5b managed-struct list append equivalence (2026-08-18)

`compiled_ok/100_compiled_test_managed_struct_list_append_gc_migration.do`
now exercises the same managed `[Box]` one-value `@put` through the normal
compiled-test entry with a real `ModuleGraph`. The route emits typed
`$do_list_box` GC storage, `array.copy $do_list_box $do_list_box`, and
`array.set $do_list_box` without `__arc_` markers. Its nested length guards
preserve the source list and verify the appended list; the paired
`managed-struct-list.do` probe returns the pinned `27815` oracle after
`wasm-tools 1.255.0` parsing and Wasmtime GC execution.

`src/build/test/check_gc_semantic_equivalence.sh` now reports 19 green rows
and zero pending rows. This closes the bounded managed-struct list append G5b
cell only. Spread/multi-value and dynamic producers, general nested producer
expressions, host/WIT marshalling, async/resource paths, and G5c remain
pending; unsupported shapes still use the ARC transition route.

### G5a bounded Future frame/table evidence (2026-08-18)

`examples/gc-p3-runtime/test_gc_async_frame_component.sh` now records a
bounded async-frame slice using `examples/p3-runtime/two-await-component.do`
through the existing `--p3-wait-for-component` entry. The generated Core WAT
contains a GC-traced `$async-frame` table and `struct.get` waitable access, has
no `__arc_` marker or linear-memory `$frame-next` allocator, and passes pinned
`wasm-tools 1.255.0` parsing, Wasmtime `-W gc=y` compilation, and Component
assembly/validation.

This is G5a evidence for two sequential `Future<nil>` awaits only. It does not
admit the ordinary GC sync entry (which still rejects async with
`UnsupportedGcSyncAsync`), `Stream<T>`, general async-call lowering, resource
terminal cleanup, G5b ARC/GC equivalence, or G5c default cutover. The inventory
therefore marks `future_stream_frames` G5a complete while its G5b/G5c cells stay
pending.

### G5b remaining scalar-list equivalence evidence (2026-08-15)

The checker now adds a backend-neutral compiled fixture for `[i8]`, `[u16]`,
`[u64]`, `[isize]`, and `[usize]` fixed-index updates, paired with the ten
independent probes in `test_do_gc_remaining_scalar_lists.sh`. The normal test
artifact and all ten GC artifacts pass with the `27815` oracle. The fresh
matrix result is `14` green rows and two explicit pending rows
(`payload-union` and `generic-managed-identity`). This remains bounded G5b
evidence and does not change the default ARC fallback or G5c cutover gate.

The new scalar-list `@put` slice is separately proven by the `[u32]`/`[f64]`
compiled fixture and `test_do_gc_scalar_list_put.sh`; the emitter copies the
source into a typed `length + 1` array and rejects spread, multi-value, indexed,
and producer forms. A bounded `[text]` managed-element append is covered by
`text-list-put.do`, `test_do_gc_text_list_put.sh`, and the new equivalence row;
managed-struct/nested-list append remains outside admission.

### 2026-08-14 compiled-test GC bridge checkpoint

The compiled-test entry now attempts the typed GC emitter for admitted
synchronous test bodies. Its output carries typed GC locals, explicit
`gc-root` markers, `__test_N` exports and the `_start` test dispatcher without
ARC symbols. Test shapes outside the parsed admission still use the current
ARC transition implementation; this fallback is temporary migration routing,
not evidence for G5c.

The bridge is covered by the pipeline unit
`compiled test route emits admitted managed test bodies with GC` and
`compiled_ok/91_compiled_test_gc_sync_bridge`. Current gates are green:
`zig test main.zig` `405/405`, the full harness
`pass=1253 fail=0 skip=3`, and `RUN_WASM=1` `pass=1255 fail=0 skip=3`.
The executable equivalence matrix at this checkpoint remained `11` green rows and `2` pending
ARC-admission rows.

### 2026-08-14 G5a aggregate/import and G5b nested checkpoint

**Status:** GO for the bounded direct-local nested managed-struct replacement,
the single `Tuple<text, [u8]>` rewrite, and the reachable imported managed
identity on the private synchronous GC route. Their fixtures and executable
probes are linked by `src/build/test/check_gc_migration_inventory.sh`.

The normal ARC and parsed GC paths now have eleven independently executable
equivalence rows, including nested managed-struct, managed-Tuple, scalar list
old/new-value preservation, and the imported text identity through a
file-backed module graph. Host/WIT marshalling, general tuple/storage, async
frames, resources, and G5c default routing remain blocked.

### G5a Bounded Pure Payload-Union Slice (2026-08-13)

**Status:** GO only for a parsed payload enum with exactly one unit arm and one
`[u8]` arm, for example `Message = Empty | Bytes([u8])`. The GC carrier is a
typed immutable struct containing an `i32` tag and nullable `do_bytes`
reference. `Empty` constructs a null payload; `Bytes(bytes)` stores the direct
`[u8]` reference; rewriting allocates a distinct union object and leaves the
input union unchanged.

**Evidence:** `src/build/codegen_gc_sync.zig` passed `95/95`,
`src/build/gc_sync_probe.zig` passed `31/31`, and
`examples/gc-p3-runtime/test_do_gc_payload_union.sh` passed `wasm-tools parse`,
Wasmtime `47.0.2` `-W gc=y` compilation, and execution with result `27815`.
The generated WAT has no `__arc_` symbol. The wrapper checks old/new object
identity, unit/managed tags, null preservation, direct payload identity, and
all replacement bytes.

**Boundary:** more than two arms, two managed arms, non-`[u8]` payloads
(including resources and unresolved types), scalar-plus-managed multi-slot
payloads, nested unions, Tuple/storage payloads, generic/imported/async values,
Component/WIT marshalling, and default GC routing remain rejected before WAT.
This is a Core Wasm GC carrier probe, not a WIT `variant`/resource or
`Result`/`Option` admission, and it does not alter the default ARC route.

### GC migration admission ledger (2026-08-13)

`src/build/test/check_gc_migration_inventory.sh` freezes the default managed
path inventory (14 rows, with the managed-struct list append residual split
into its own row). It validates that a `complete` G5a row links source
fixtures and bash-invokable probe scripts, and it exits non-zero while any
G5a/G5b/G5c row remains pending. The evidence-backed parsed G5a rows include
the four `[u8]` slices (fixed/parameterized `@set`, numeric literal, and
single-value `@put`), direct `[u8]` managed-field payload rebuild, one bounded
pure payload-union carrier, and resolved generic managed identity/field update.
The pending boundary values are current implementation records, not verified
negative probes.

### G5a Resolved Generic Managed Calls (2026-08-14)

**Status:** GO only for a resolved generic call whose type binding is an
existing concrete GC-managed type. `identity(value T) -> T` preserves the
typed GC reference, and `update(box T, next [u8]) -> T` resolves to a concrete
`Box` layout and rebuilds the managed field while preserving the scalar field.
Unresolved, resource, and payload-union bindings fail before WAT with named
`UnsupportedGcSyncGeneric*` errors.

**Evidence:** `src/build/codegen_gc_sync.zig` passed `126/126`,
`src/build/gc_sync_probe.zig` passed `36/36`, and
`examples/gc-p3-runtime/test_do_gc_generic_managed_identity.sh` passed
`wasm-tools 1.255.0` parsing, Wasmtime `47.0.2 -W gc=y` compilation, no
`__arc_` symbol, and execution result `27815`.

**Boundary:** generic struct layout instantiation, generic tuples, resources,
imports, WIT/Component marshalling, async frames, G5b ARC/GC equivalence, and
G5c default routing remain pending. The normal `do build` route remains ARC.

All other default paths remain pending with their current fail-closed parsed
entry boundary: unsupported expressions/types/aggregates for text, other
lists, nested aggregate shapes beyond direct-local child `@set` and direct child
`@get`, and Tuple/storage shapes beyond the direct `Tuple<text,[u8]>` rewrite;
`UnsupportedGcSyncGeneric*` for unresolved/resource/union bindings and generic
layout instantiation; `UnsupportedGcSyncModuleGraph` for unsupported import
graphs and host/WIT marshalling; `UnsupportedGcSyncControl` or
`UnsupportedGcSyncStatement` for unproven control flow;
`UnsupportedGcSyncAsync` for Future/Stream frames; and
`UnsupportedGcSyncAggregate` or `UnsupportedGcSyncType` for resource terminal
shapes outside the bounded Component gate. These are not default Component ABI
admissions and do not alter the default
ARC route.

### G5a parsed text/list/producer boundary (2026-08-13)

The non-CLI parsed entry admits direct `text` identity/string rebuild, direct
text-field replacement, list literals through typed locals, one direct call
returning a classified managed value, direct-local nested managed child
replacement, and direct nested child `@get`. It rejects nested managed
producers, non-`u8` list updates, multi-value `@put`, and call-produced
managed-field replacement before WAT. `gc_sync_probe.zig` now validates exact parsed function
bodies and obtains struct/field names, order, and types from declarations rather
than assuming `$box` or parameter counts.

Focused evidence: `zig test build/codegen_gc_sync.zig` (`90/90`),
`zig test build/gc_sync_probe.zig` (`30/30`), focused emitter/root suites, and
the eight parsed GC probes all passed. `check_gc_migration_evidence_test.sh`
rejects evidence files without an explicit verification marker. This does not alter default ARC routing
or establish G5b/G5c.

The later aggregate-closure checkpoint extends the focused guard suite to
`codegen_gc_sync.zig` (`109/109`), `gc_sync_probe.zig` (`36/36`), and
`runtime_gc_prelude_wat.zig` (`18/18`). The full compiler suite is `404/404`
and the repository harness is `pass=1243 fail=0 skip=3`. These counts cover
typed layout guards only; they do not widen the migration ledger or establish
G5b/G5c.

### G5a Typed Aggregate Layout Checkpoint (2026-08-13)

The pure GC prelude emits nested managed struct types in dependency order and
fails closed for missing children, direct cycles, resource fields, and names
that collide after lowering. A source containing a standalone
`@wasi_resource` declaration is also rejected by the pure GC entry before WAT
emission; WIT resource handles never become GC children. The existing
direct-local nested-child and `Tuple<text, [u8]>` slices remain the only
admitted aggregate forms.

Evidence is recorded in
`.superpowers/sdd/2026-08-13-gc-g5a-aggregate-closure/task-3-report.md`.
General tuples/storage, nested paths, list-of-managed-struct values, generic
managed calls, imports, Component/WIT marshalling, async frames, and arbitrary
producers remain pending. The default `do build` route remains ARC.

### G5a Nested Managed Struct Checkpoint (2026-08-13)

**Status:** GO only for `@set(outer, .child, child_local) -> Outer` when
`child` is a declared GC-managed struct field and `child_local` has that exact
declared type. Direct `@get(outer, .child)` returns the same declared child
reference type. The lowering constructs a new outer GC struct, copies unchanged
fields, preserves the old outer and child, and stores the exact direct child
reference in the new outer. It does not mutate either source value.

**Evidence:** `src/build/codegen_gc_sync.zig` (`86/86`),
`src/build/gc_sync_probe.zig` (`27/27`), and
`examples/gc-p3-runtime/test_do_gc_nested_managed_struct.sh` passed
`wasm-tools parse`, Wasmtime `-W gc=y` compilation, and execution with result
`27815`.

**Boundary:** nested paths, list-of-managed-struct updates, nested child
construction or call producers, generic child types, recursive/cyclic layouts,
and aggregates containing WIT resources remain outside this slice and fail
closed before WAT. This does not make `nested_structs` complete in the migration
ledger and does not alter the default ARC route.

### G5a Managed Tuple Checkpoint (2026-08-13)

**Status:** GO only for one parsed immutable rewrite:
`rewrite(pair Tuple<text, [u8]>) -> Tuple<text, [u8]> { return
Tuple<text, [u8]>{@get(pair, 0), @set(@get(pair, 1), 0, 65)} }`. The GC sync
backend treats this source tuple as one `(ref null $tuple_text_bytes)` rather
than applying the normal ARC pipeline's scalar multi-result ABI. It preserves
the text reference, copies the byte array before its sole `array.set`, and
constructs a distinct tuple without ARC calls.

**Evidence:** `src/build/codegen_gc_sync.zig` (`90/90`),
`src/build/gc_sync_probe.zig` (`30/30`), and
`examples/gc-p3-runtime/test_do_gc_managed_tuple_text_bytes.sh` passed
`wasm-tools parse`, Wasmtime `-W gc=y` compilation, and execution with result
`27815`. The shell oracle invokes the parsed GC probe wrapper, not
`do build --gc-core`.

**Boundary:** this does not admit general Tuple constructors, arbitrary tuple
indexing or updates, tuple storage, nested tuples, resource-containing tuples,
generic tuples, calls, imports, async, G5b equivalence, or the default GC
route. `tuple_storage` remains pending in the migration ledger.

### G5a Parsed Byte-List Checkpoint (2026-08-13)

**Evidence:** `codegen_gc_sync.zig` parses both the fixed
`@set(input, 0, 65)` and parameterized `@set(bytes, offset, next)` function
shapes and emits typed GC WAT with `array.len`, `array.copy`, and `array.set`.
`codegen_gc_core.zig` no longer matches either byte-list update as a token
profile. The backing copy is made before `array.set`, so the original and
updated arrays are checked separately. `src/build/gc_sync_probe.zig` is a
test-only wrapper around the non-CLI `emit_gc_wat_for_supported_program` entry.
It constructs an input, calls the parsed function, and proves the original
element remains unchanged while the returned element is `65`.

`zig test build/codegen_pipeline.zig` (`102/102`),
`zig test build/codegen_gc_core.zig` (`48/48`), and
`zig test build/gc_sync_probe.zig` (`26/26`) passed. The current `wasm-tools`
and Wasmtime Core-GC oracle gate passed all twelve probes with `27815`; its two
parameterized probes use the parsed test entry.

### G5a Parsed Byte-List Literal Slice (2026-08-13)

**Status:** the next parsed synchronous `[u8]` slice is green in the
non-CLI GC entry. `.{7, 12, 17}` and `.{}` lower to typed GC arrays; the
focused Wasmtime probe makes two calls, keeps the first result rooted, proves
the second allocation is a distinct array, and checks the first array's length
and all three bytes. Values outside `u8` (`256` and `-1`) fail closed with
`GcSyncTypeMismatch` before WAT emission.

**Evidence:** `src/build/codegen_pipeline.zig` byte-list literal tests pass,
`zig test build/gc_sync_probe.zig` passes, and
`WASMTIME_BIN="$(command -v wasmtime)" bash
examples/gc-p3-runtime/test_do_gc_list_literal.sh` passes after
`wasm-tools parse` and Wasmtime `-W gc=y` compilation, returning `27815`.

**Boundary:** this admits a numeric inferred aggregate literal expression in
an otherwise admitted synchronous GC program when its expected type is `[u8]`.
The focused fixture uses a zero-parameter producer. It does not admit `@put` in
this literal gate; the separate `@put` gate below covers one append shape.
Other non-`u8` list elements, nested or non-literal elements, new call/producer
admission, imports, host/Component marshalling, async, or default GC routing.
The test-only probe is separate from the temporary `--gc-core` token-profile
oracle; no mixed ARC/GC module is produced.

**The separate `@set` boundary:** this admits only the exact synchronous
fixed-index and parameterized `[u8]` persistent-update function shapes,
including renamed parameters. It does not admit `@put`, other list element
types, managed-field updates, Tuple/storage, unions, generics, module graphs,
imports, host calls, resources, async, Component ABI, or default GC routing.
There is no mixed ARC/GC module and no new source ownership or reference
syntax. This is a non-CLI parsed-emitter boundary; the temporary `--gc-core`
target continues to expose only its remaining token profiles until G5 removes
that oracle entirely.

### G5a Parsed Byte-List `@put` Slice (2026-08-13)

**Status:** GO for one synchronous `[u8]` append shape in the non-CLI parsed GC
entry. `@put(input, value)` allocates `length + 1`, copies the source payload,
and writes one `u8` at the old length. The source list remains unchanged,
including for an empty source; the focused probe also proves distinct results
from two calls.

**Evidence:** `src/build/codegen_pipeline.zig` passed `102/102`,
`src/build/gc_sync_probe.zig` passed `26/26`, and
`examples/gc-p3-runtime/test_do_gc_list_put.sh` passed `wasm-tools parse`,
Wasmtime `-W gc=y` compilation, and execution with result `27815`.

**Boundary:** only one `[u8]` receiver and one `u8` value are admitted. `256`
and `-1` fail with `GcSyncTypeMismatch`; multi-value, spread, non-`u8`, nested
or general producer expressions, imports, host/Component marshalling, async,
and default GC routing remain rejected. This is not ARC/GC equivalence and
does not switch the normal `do build` backend.

### G5a Parsed Managed-Field Payload Slice (2026-08-13)

**Status:** GO for direct `[u8]` payload replacement in the non-CLI parsed GC
entry. `@set(box, .value, value)` rebuilds the outer struct, selects the
replacement local's GC reference, and preserves old object/payload contents and
unchanged scalar fields.

**Evidence:** `src/build/codegen_pipeline.zig` passed `102/102`,
`src/build/gc_sync_probe.zig` passed `26/26`, and both
`examples/gc-p3-runtime/test_do_gc_managed_struct_payload.sh` and its renamed
field-order variant passed `wasm-tools parse`, Wasmtime `-W gc=y` compilation,
and execution with result `27815`.

**Boundary:** the selected field must be exactly one `[u8]` field, the
replacement must be one direct `[u8]` local, and the result must be the same
managed struct type. The lowering rebuilds every unchanged field from the old
struct; the current executable probe exercises a two-field struct with one
`[u8]` field and one `i32` field, including renamed type/field/function and
reversed declaration order. Text or nested managed-field replacements,
general producers, resource fields, imports, async, Component marshalling,
and default GC routing remain rejected. This is not ARC/GC equivalence and
does not switch normal `do build`.

This file records blockers discovered while implementing the generic
`--host-export` Core Wasm ABI. It is intentionally evidence-based: a blocker
does not become a supported fallback merely because the compiler can emit a
partial signature.

**Active Component toolchain:** `wasm-tools 1.255.0 (76e20611d 2026-07-30)`
with SHA-256 `6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`.
The 1.254.0 binary is historical evidence only and is not an executable
dependency. The current tool's `--dummy-names legacy` value names its async
callback mangling mode; it does not select a legacy toolchain.

## D2 General Filesystem/HTTP Recovery Boundary (2026-08-09)

**Status:** the private `descriptor.get-type`, `descriptor.sync`,
`descriptor.get-flags`, `descriptor.stat`, `descriptor.sync-data`,
`descriptor.metadata-hash`, `descriptor.metadata-hash-at`, `descriptor.stat-at`,
and `descriptor.open-at` methods remain green as separate bounded descriptors.
General filesystem async and arbitrary HTTP remain blocked; this checkpoint
does not add a registry entry or widen code generation.

**Evidence:** the method-specific ABI scripts and their Rust/Wasmtime runtime gates pass
with the pinned filesystem WIT (`types.wit` SHA-256
`8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`) and the
current `wasm-tools 1.255.0` binary. Each closed row has its own measured
`(i32,i32) -> i32` method import, Component Result/payload layout, descriptor
drop, ready/pending/error/cancel observations, and empty `ResourceTable`.
The exact signatures and method-by-method recovery requirements are recorded
in [`doc/superpowers/specs/2026-08-09-d2-general-filesystem-async-boundary-design.md`](../doc/superpowers/specs/2026-08-09-d2-general-filesystem-async-boundary-design.md).

**Unadmitted filesystem rows:** `read-via-stream` carries both
`stream<u8>` and `future<result<_, error-code>>`; `write-via-stream` and
`append-via-stream` consume producer streams; `read-directory` carries a
`stream<directory-entry>` plus a completion future; `stat`/`stat-at` and
`metadata-hash`/`metadata-hash-at` return records; path mutation methods issue
external effects; and
`link-at`/`rename-at`/`is-same-object` carry `borrow<descriptor>`. None of
these shapes may be inferred from the four scalar/unit Result rows.
The private `descriptor.open-at` shape is recorded as a separate bounded row
below and does not widen this general boundary.

**Unadmitted HTTP rows:** the pinned service world imports `client.send:
async func(request) -> result<response, error-code>` and exports
`handler.handle` with the same signature. A service-world gate must cover
request transfer, response/resource drops, body streams, optional payload
errors, repeated calls, and cancellation. Existing fixed `client.send` slices
are not generic HTTP support.

**Recovery condition:** create a new exact-method design, canonical WIT/Core
probe, positive/negative fixtures, Component validation, and Rust/Wasmtime
ready/pending/error/cancel cleanup matrix before changing `p3_async_registry`
or filesystem/HTTP lowering. Cancellation releases live guest/Component state
and never rolls back an effect already issued to the host.

## D2 Bounded Filesystem Async `descriptor.stat` Early-Drop Boundary (2026-08-10)

**Status:** the private `descriptor.stat` WIT/ABI probe, the exact opt-in Do
compiler slice, and the terminal, explicit-cancel, and repeat Rust/Wasmtime
rows are green with only `wasm-tools 1.255.0`. Generic filesystem async and
generic host-future-drop cancellation remain closed; this probe scopes
early-drop to whole-Store disposal only.

**Evidence:**
`bash examples/p3-runtime/test_d2_wasi_filesystem_stat_abi.sh`,
`bash examples/p3-runtime/test_do_wasi_filesystem_stat.sh`, and
`bash examples/p3-runtime/test_rust_wasi_filesystem_stat.sh` pass with
`wasm-tools 1.255.0 (76e20611d 2026-07-30)` and SHA-256
`6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`.
The canonical result area is `frame+8` with tag `+8`, aligned payload `+16`,
option presence/payload offsets through `+104`, status `+112`, and callback
subtask handle `+116`; the allocated frame is 128 bytes. The runtime output
includes ready, pending, error, explicit `[async-lower][subtask-cancel]`,
early-drop(Store disposal), and repeat rows.

The compiler target is `--p3-wasi-filesystem-stat-component`. Fixture `498`
passes `do check`, the default `do build` fails closed with
`AsyncLoweringUnavailable`, and the opt-in Core WAT is byte-identical to the
canonical template (SHA-256
`b7aee0221318c857817859c5e849fa98da9909c2151b09c6dea9b964c986a69a`). The
generated WIT hash is
`4a2e5055c2ec06c772660b211c3e3ab3e3e15d8b5931c8e7def804e56d5175da`.
Fixtures `499`-`510` reject before WAT. Generated regular Component rows
`ready`, `pending`, `error`, and `repeat` match the hand-authored record and
exactly-once cleanup matrix; cancel and Store-disposal early-drop stay on the
hand-authored cancel-world oracle because the Do source has no cancel export.

Wasmtime 47 documents that dropping a `TypedFunc::call_concurrent` future does
not cancel an already-started guest task. The early-drop row therefore drops
the call future and then the whole Store, reporting one pending host-future
drop, `descriptor-drops=0`, and `table-empty=not-applicable`. The explicit
cancel row remains the only Component-level proof for subtask cancellation,
descriptor drop, and an empty `ResourceTable`. Do not infer generic host-future
drop cancellation or add a compiler lowering for it.

**Recovery condition:** if Wasmtime exposes per-task cancellation for
`call_concurrent`, add a new pinned probe and runtime matrix before changing
the generic cancellation boundary. Until then, keep generic host-future-drop
cancellation and general filesystem async unadmitted; the exact private stat
target remains limited to its pinned source shape and generated regular
Component path.

## D2 Bounded Filesystem Async `descriptor.sync-data` (2026-08-10)

**Status:** one additional private filesystem async method is verified; the
method-specific early-drop and repeat rows are green, while generic
filesystem async and generic host-future-drop cancellation remain blocked.

**Evidence:**
`bash examples/p3-runtime/test_d2_wasi_filesystem_sync_data_abi.sh` and
`bash examples/p3-runtime/test_rust_wasi_filesystem_sync_data.sh` pass with
`wasm-tools 1.255.0 (76e20611d 2026-07-30)` and SHA-256
`6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`.
The upstream filesystem WIT hash is
`8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`;
the regular and cancel probe WIT mirror hashes are
`ffc10164efb9a457637d56df111bb92844eef7b3258fec5dfb075b8e68dff8bb` and
`2107a6283e8ae2b6f2cea296d91269c65d543456e39376ef4e70b0b69fd974e3`.
The measured import is
`[async-lower][method]descriptor.sync-data: (i32,i32) -> i32`, task-return
uses two `i32` words, the Result is `unit | error-code`, and the descriptor
drop is `[resource-drop]descriptor (i32) -> nil`.

The private `--p3-async-component` adapter admits only fixture `511` with
one `Dir` receiver, one `Future<nil | SyncDataError>`, and one await. The
opt-in Core WAT equals the canonical template (SHA-256
`3269e6f8c61a34dbea99f2637a257d582d79ab860f812d6ddfc46392e4fc3e7b`), and
the generated WIT hash is
`df3c055bab6ecff3d3b77435ba67df6c4d207eb786e243d41f1301873fabfed9`.
Fixtures `512`-`515` reject before WAT. Hand-authored and generated Components
pass ready, pending, error, and repeat; the hand-authored cancel Component
passes explicit cancellation with exactly-once Future/descriptor cleanup and
`table-empty=true`.

The early-drop row drops the started call future and then the whole Store,
reporting one pending host-future drop, `descriptor-drops=0`, and
`table-empty=not-applicable`, matching the Wasmtime 47 task-drop boundary.
Cancellation only releases live Component state and never rolls back a
filesystem effect already issued to the host.

**Boundary:** this does not admit generic filesystem async, arbitrary
producer expressions, stream/list/borrowed/record payloads, `stat-at`, path
mutation, external HTTP, or public
`own<T>`/`borrow<T>`/`ref<T>` syntax. Each additional method needs its own
pinned WIT/Core probe, positive/negative fixtures, Component validation, and
Rust/Wasmtime cleanup matrix.

## D2 Bounded Filesystem Async `descriptor.metadata-hash` (2026-08-10)

**Status:** the private metadata-hash method is verified. The independent
`metadata-hash-at` compiler and local-host runtime slice is also verified;
generic filesystem async and generic host-future-drop cancellation remain
blocked.

**Evidence:**
`bash examples/p3-runtime/test_d2_wasi_filesystem_metadata_hash_abi.sh` and
`bash examples/p3-runtime/test_rust_wasi_filesystem_metadata_hash.sh` pass with
`wasm-tools 1.255.0 (76e20611d 2026-07-30)` and SHA-256
`6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`.
The upstream filesystem WIT hash is
`8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`;
regular and cancel probe WIT mirror hashes are
`6976359b3a4813d6771b3ef9a7fdcfb2ee9323e70c33b9ac7d6b628519fecfed` and
`b6e98cf2ae6f76e105f53c7ea09666b1c5684d33edb9838d034862a27b09f5c3`.
The measured import is
`[async-lower][method]descriptor.metadata-hash: (i32,i32) -> i32`, task-return
is `(i32,i64,i64)`, the Result payload is
`metadata-hash-value { lower: u64, upper: u64 } | error-code`, and descriptor
drop is `[resource-drop]descriptor (i32) -> nil`.

The private `--p3-async-component` adapter admits only fixture `516` with one
`Dir` receiver, one `Future<MetadataHash | HashError>`, and one direct await.
The opt-in Core template hash is
`f51c82887174a7ed1adf95a1cbe0e333f80a487962a2a8478334ca9750933b6b`;
fixtures `517`-`519` reject before WAT. Generated ready/pending/error/repeat
and hand-authored cancel/Store-disposal early-drop Rust/Wasmtime rows pass.
Cancellation only releases live Component state and never claims rollback of
host work already issued.

**Boundary:** this does not admit generic filesystem async, arbitrary producer
expressions, stream/list/borrowed/record payloads, external
HTTP, or public `own<T>`/`borrow<T>`/`ref<T>` syntax. Each additional method
needs its own pinned WIT/Core probe, positive/negative fixtures, Component
validation, and Rust/Wasmtime cleanup matrix.

## D2 Bounded Filesystem Async `descriptor.metadata-hash-at` (2026-08-11)

**Status:** the pinned ABI, exact opt-in Do compiler slice, generated regular
Component, and Rust/Wasmtime path-copy and cleanup matrix are green. Generic
filesystem async, generic host-future-drop cancellation, and public ownership
syntax remain blocked.

**Evidence:**
`bash examples/p3-runtime/test_d2_wasi_filesystem_metadata_hash_at_abi.sh` and
`bash examples/p3-runtime/test_rust_wasi_filesystem_metadata_hash_at.sh` pass
with `wasm-tools 1.255.0 (76e20611d 2026-07-30)` and SHA-256
`6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`.
The upstream filesystem WIT hash is
`8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`;
regular/cancel oracle mirrors are
`95e24b70eeed89407706c18a6e4cd13a8bc4dce72d1e56638436b03287d23412` /
`aca9c5933786a00a2dd20b1ad1ddbb6d0a79ab5b3bdbd5bd61e14b100a3b6e0a`.

The admitted source is exactly one `@host_async_func`
`(Dir, u32, text) -> MetadataHash | HashError`, one direct await, one exact
descriptor/resource shell, and a synchronous root with an empty `start`.
Fixture `520` is admitted; `521`-`529` reject before WAT for unregistered,
signature, second-await, branch, loop, extra-host, record, and async-root drift.
The measured import is
`[async-lower][method]descriptor.metadata-hash-at:
(i32,i32,i32,i32,i32) -> i32`, ordered as descriptor, path-flags, UTF-8 path
pointer, UTF-8 path length, and result-area pointer. Task-return is
`(i32,i64,i64)` and descriptor drop is `[resource-drop]descriptor (i32) -> nil`.
The compiler template hash is
`6056d1e6f42d6ab4edce60e2bb1ef61f358bfd6d03e6aa1e3c35daf08672713f`.

The generated WIT/Core Component embeds and validates. The Rust host copies
the UTF-8 path into an owned `String` before returning its future; the pending
row observes the exact non-ASCII path after a delayed wake. Ready, pending,
error, cancel, whole-Store early-drop, and repeat rows pass with exactly-once
future/descriptor cleanup. Early-drop reports
`pending-future-drops=1 descriptor-drops=0 table-empty=not-applicable`, matching
the Wasmtime 47 Store-disposal boundary. Cancellation is cleanup-only and never
rolls back a filesystem effect already issued to the host.

Full gates also pass: `./src/build/test/run_tests.sh` reports
`pass=1209 fail=0 skip=3`, `cd src && zig test main.zig` reports `351/351`, and
`cd src && zig build -Doptimize=ReleaseSmall` succeeds.

**Boundary:** this remains a private method-specific target. It does not admit
generic filesystem or HTTP async, arbitrary producer expressions,
stream/list/borrowed/record payloads, path mutation, or
public `own<T>`/`borrow<T>`/`ref<T>` syntax. Each additional method needs its
own pinned WIT/Core probe, positive/negative fixtures, Component validation,
and Rust/Wasmtime cleanup matrix.

## D2 Bounded Filesystem Async `descriptor.stat-at` (2026-08-11)

**Status:** the pinned ABI, exact opt-in Do compiler slice, generated regular
Component, and Rust/Wasmtime path-copy and cleanup matrix are green. Generic
filesystem async, generic host-future-drop cancellation, and public ownership
syntax remain blocked.

**Evidence:**
`bash examples/p3-runtime/test_d2_wasi_filesystem_stat_at_abi.sh` and
`bash examples/p3-runtime/test_rust_wasi_filesystem_stat_at.sh` pass with
`wasm-tools 1.255.0 (76e20611d 2026-07-30)` and SHA-256
`6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`.
The upstream filesystem WIT hash is
`8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`;
regular/cancel oracle mirrors are
`92afa427efedc960fd60ce2edbd3ced26521225ae8857377554956646a1059bd` /
`420fb95fae7505e568414e55f19dc2f89f5b32e015e8d999166e38b48e4a4a49`.

The admitted source is exactly one `@host_async_func`
`(Dir, u32, text) -> DescriptorStat | StatError`, one direct await, one exact
descriptor/resource shell, and a synchronous root with an empty `start`.
Fixture `530` is admitted; `531`-`539` reject before WAT for unregistered,
signature, second-await, branch, loop, extra-host, and async-root drift. The
measured method import is
`[async-lower][method]descriptor.stat-at:
(i32,i32,i32,i32,i32) -> i32`, ordered as descriptor, path-flags, UTF-8 path
pointer, UTF-8 path length, and result-area pointer. Task-return is
`(i32,i32,i64,i64,i32,i64,i32,i32,i64,i32,i32,i64,i32)` and descriptor drop is
`[resource-drop]descriptor (i32) -> nil`. The compiler template hash is
`4503fa7634560c66463f96ac142bcc7cfb7b90cca93a8b705c1d1eb05040ddef`.

The two-page Core memory is required for the canonical UTF-8 path allocation
at the heap boundary; the frame and result-area offsets remain the measured
ABI. Generated WIT/Core embeds and validates. The Rust host observes an owned
path copy and `symlink-follow` flag after a delayed pending poll. Ready,
pending, error, cancel, whole-Store early-drop, and repeat rows pass with
exactly-once future/descriptor cleanup. Early-drop reports
`pending-future-drops=1 descriptor-drops=0 table-empty=not-applicable`, matching
the Wasmtime 47 Store-disposal boundary. Cancellation is cleanup-only and
never rolls back a filesystem effect already issued to the host.

**Boundary:** this remains a private method-specific target. It does not admit
generic filesystem or HTTP async, arbitrary producer expressions,
stream/list/borrowed/record payloads, path mutation, or public
`own<T>`/`borrow<T>`/`ref<T>` syntax. Each additional method needs its own
pinned WIT/Core probe, positive/negative fixtures, Component validation, and
Rust/Wasmtime cleanup matrix.

## D2 Bounded Filesystem Async `descriptor.open-at` (2026-08-11)

**Status:** the pinned ABI, exact opt-in Do compiler slice, generated regular
Component, and Rust/Wasmtime ownership and cancellation matrix are green.
Generic filesystem async, generic host-future-drop cancellation, and public
ownership syntax remain blocked.

**Evidence:**
`bash examples/p3-runtime/test_d2_wasi_filesystem_open_at_abi.sh`,
`bash examples/p3-runtime/test_d2_wasi_filesystem_open_at_compiler.sh`, and
`bash examples/p3-runtime/test_rust_wasi_filesystem_open_at.sh` pass with
`wasm-tools 1.255.0 (76e20611d 2026-07-30)` and SHA-256
`6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`.
The upstream filesystem WIT hash is
`8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`;
regular/cancel probe WIT mirror hashes are
`1e5f9131387015c4e650a64e02bb9f112d8266f4755aa6b605af038407ef807a` /
`1c48fba03b569d91617efd834232fcccc553ca3001ffb0e0834b4134f93e4f52`.

The admitted source is exactly one `@host_async_func`
`(Dir, u32, text, u32, u32) -> File | OpenError`, one direct await, two exact
descriptor resource shells, and a synchronous root with an empty `start`.
Fixture `540` is admitted; `541`-`551` reject before WAT for unregistered,
flag/signature, ownership, await/topology, extra-host, and async-root drift.
The measured method import is
`[async-lower][method]descriptor.open-at: (i32,i32) -> i32` with an indirect
six-word parameter block (`descriptor`, `path-flags`, `path-ptr`, `path-len`,
`open-flags`, `descriptor-flags`); task-return is `(i32,i32)` and the Result is
`descriptor | error-code`. Descriptor drop is
`[resource-drop]descriptor (i32) -> nil`. The compiler template hash is
`a05a8e90cfb553658a8a5337e026a0fa1304aa42f0b33558a3d6ecfc17623201`.

The generated WIT/Core Components embed and validate. The Rust host copies the
UTF-8 path before returning its future, creates and drops a child descriptor
only on `Ok`, and observes ready, pending, error, cancel, Store-disposal
early-drop, and repeat rows with exactly-once live-Store cleanup. The cancel
probe leaves the borrowed parent descriptor for the unified termination path;
dropping it immediately after `[async-lower][subtask-cancel]` fails with
Wasmtime's `cannot remove owned resource while borrowed` check. Cancellation is
cleanup-only and never rolls back an `open-at` effect already issued to the
host.

The full repository gates after rebuilding `bin/do` also pass:
`NODE_BIN=/home/_/.local/bin/bun ./src/build/test/run_tests.sh` reports
`pass=1231 fail=0 skip=3`, `cd src && zig test main.zig` reports `355/355`,
and `cd src && zig build -Doptimize=ReleaseSmall` succeeds.

**Boundary:** this remains a private method-specific target. It does not admit
generic filesystem or HTTP async, arbitrary producer expressions,
stream/list/borrowed/record payloads, path mutation, or public
`own<T>`/`borrow<T>`/`ref<T>` syntax. Each additional method needs its own
pinned WIT/Core probe, positive/negative fixtures, Component validation, and
Rust/Wasmtime cleanup matrix.

## D2 Bounded Filesystem Async `descriptor.get-type` (2026-08-08)

**Status:** one private filesystem async method is verified; general filesystem
async remains blocked and is not inferred from this result.

**Evidence:** `bash examples/p3-runtime/test_d2_wasi_filesystem_get_type_abi.sh`
passes the pinned current `wasm-tools 1.255.0 (76e20611d 2026-07-30)` binary
(SHA-256 `6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`).
The upstream WIT hash is
`8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`.
The measured method import is
`[async-lower][method]descriptor.get-type: (i32,i32) -> i32`, completion uses
two `i32` task-return values, the result is the
`descriptor-type | error-code` component variant, and the descriptor resource
drop is `(i32) -> nil`.

The private `--p3-async-component` adapter admits only the exact
`Dir -> DescriptorType | FileError` source shape in fixture `459`. Fixtures
`459`-`461` cover unregistered, wrong-result, and borrowed-payload rejection
before WAT. `bash examples/p3-runtime/test_rust_wasi_filesystem_get_type.sh`
assembles both hand-authored and compiler-generated Components. The hand-authored
Component passes ready-directory, ready-regular, pending, error, and
cancellation; the generated Component passes ready-directory, ready-regular,
pending, and error with matching exactly-once future/descriptor cleanup and
`table-empty=true`.

**Boundary:** this does not admit `read`, `write`, `stat`, directory
mutation, stream/list/borrowed payloads, arbitrary producer expressions,
generic async calls, external HTTP, rollback of host side effects, or public
`own<T>`/`borrow<T>`/`ref<T>` syntax. Each additional method needs its own pinned
WIT/Core probe and Component/Rust/Wasmtime gate.

## D2 Bounded Filesystem Async `descriptor.sync` (2026-08-08)

**Status:** one additional private filesystem async method is verified; general
filesystem async remains blocked and is not inferred from either bounded method.

**Evidence:** `bash examples/p3-runtime/test_d2_wasi_filesystem_sync_abi.sh`
passes current `wasm-tools 1.255.0 (76e20611d 2026-07-30)` (SHA-256
`6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`). The
upstream WIT hash is
`8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`; the
regular/cancel mirror hashes are
`18ce7dc9efb991cd8e5f945797aea73edeed79f0cfc51ea664cb81537e54e719` and
`9898cd734708a2ab14760da706d69063e5cd6262a5e03d07d8eedd8074745f36`.
The measured method import is
`[async-lower][method]descriptor.sync: (i32,i32) -> i32`, task-return uses
the measured two-word component Result completion, the Result is
`unit | error-code`, and descriptor drop is `(i32) -> nil`.

The private `--p3-async-component` adapter admits only
`Dir -> nil | SyncError` in fixture `462`. Fixtures `462`-`465` reject an
unregistered locator, wrong Result shape, borrowed payload, and a second await
before WAT. `bash examples/p3-runtime/test_rust_wasi_filesystem_sync.sh`
assembles and validates both hand-authored and generated Components. The
hand-authored Component passes `ready`, `pending`, `error`, and test-only
`cancel`; the generated Component passes `ready`, `pending`, and `error`.
Every admitted row has `host-calls=1`, one descriptor drop, and
`table-empty=true`. Ready/error use one completion poll; pending uses two polls
and one external wake; cancel drops one pending future with zero completion.
Fresh repository gates are `zig test main.zig` `308/308`, default regression
`pass=1149 fail=0 skip=3`, WASM regression `pass=1151 fail=0 skip=3` with smoke
`6/6`, ReleaseSmall smoke passed, and `git diff --check` passed.

**Boundary:** this does not admit other filesystem methods, stream/list/record/
borrowed/variant payloads, arbitrary producer expressions, independent guest
tasks, external HTTP, rollback of host side effects, or public
`own<T>`/`borrow<T>`/`ref<T>` syntax. Each additional method needs its own pinned
WIT/Core probe and Component/Rust/Wasmtime gate.

## D2 Bounded Filesystem Async `descriptor.get-flags` (2026-08-08)

**Status:** one additional private filesystem async method is verified; general
filesystem async remains blocked and is not inferred from this bounded slice.

**Evidence:** `bash examples/p3-runtime/test_d2_wasi_filesystem_get_flags_abi.sh`
passes current `wasm-tools 1.255.0 (76e20611d 2026-07-30)` (SHA-256
`6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`). The
upstream WIT hash is
`8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`; the
WIT mirror hash is
`12afdb48b07d7160c76f04231fb8da4862350d42f6170174e6e27264b7307be9`. The
measured method import is
`[async-lower][method]descriptor.get-flags: (i32,i32) -> i32`. Its canonical
result-area payload is one `u8` byte, while the flat `task.return` payload is
one promoted `i32` word; the Component Result is
`descriptor-flags | error-code`, and descriptor drop is
`[resource-drop]descriptor (i32) -> nil`.

The private `--p3-async-component` adapter admits only
`Dir -> u8 | FlagsError` in fixture `471`. Fixtures `472`-`474` reject an
unregistered locator, wrong result shape, and borrowed payload before WAT.
`bash examples/p3-runtime/test_rust_wasi_filesystem_get_flags.sh` assembles
both hand-authored and compiler-generated Components. Hand-authored ready,
pending, error, and test-only cancel rows, plus generated ready/pending/error
rows, pass with `host-calls=1`, one descriptor drop, an empty `ResourceTable`,
and exactly-once future cleanup. Pending uses two completion polls and one
external wake; cancel drops one pending future and performs zero completion.

Fresh repository gates are `zig test main.zig` `308/308`, default regression
`pass=1149 fail=0 skip=3`, WASM regression `pass=1151 fail=0 skip=3` with smoke
`6/6`, and ReleaseSmall smoke passed.

**Boundary:** this does not admit `read`, `write`, `stat`, directory
mutation, other filesystem methods, stream/list/record/borrowed/variant
payloads, arbitrary producer expressions, generic async calls, external HTTP,
rollback of host side effects, or public `own<T>`/`borrow<T>`/`ref<T>` syntax.
Each additional method needs its own pinned WIT/Core probe and
Component/Rust/Wasmtime gate.

## P3 Task-Return Scalar Type Identity

**Status:** unsigned/narrow scalar `Future<Result<T, E>>` payloads remain
blocked in the pinned async runtime; signed `s32` payloads are verified.

**Evidence:** a descriptor-driven `Result<u8,u8>` probe with the same flat core
signature as the verified `Result<i32,i32>` probe compiles, assembles, and
validates with `wasm-tools 1.254.0` and Wasmtime `47.0.2`. The Rust host future
is invoked and returns `Ok(43)`/`Err(199)`, but completion traps at
`task.return` with `invalid \`task.return\` signature and/or options for
current task` (`TaskReturnInvalid`). Replacing the WIT result with
`result<s32,s32>` while keeping the same core frame makes the pending and
immediate executions pass.

**Boundary:** this is not evidence that Do's source-to-core mapping is wrong;
`u8` maps to one `i32` word correctly. It is a pinned Wasmtime/WIT task-return
type-identity limitation. The compiler therefore keeps the source scalar
mapping and WIT type generator tested, but does not register or lower a
runtime-facing narrow/unsigned Result descriptor until a standalone probe
passes.

**Unblock condition:** rerun the same probe against a toolchain revision where
`result<u8,u8>` (and then `bool`, `u16`, `u32`, and signed narrow variants) has
matching import/export task-return type identity and pending/immediate
execution. Do not silently substitute `s32` for the public WIT type.

## Callback Parameters On Host Exports

**Status:** permanently unsupported by the public host-export surface.

**Evidence:** Do function types are parameter-only constraints. They cannot be
stored, returned, or made into public first-class values, and a lambda cannot
capture an outer local binding. A foreign host therefore cannot construct a Do
function value for a public `--host-export` parameter. This is not a missing
closure lifetime mechanism.

**Current protection:** `--host-export` rejects a public function with a
callback parameter using `HostExportCallbackParamUnsupported`.

**Resolution:** redesign that public API as concrete exported functions plus
explicit resources, polling, future/stream delivery, or host-managed static
event registration. Do not add public `funcref`, pointer, reference, or closure
syntax to make this signature appear supported.

## Guest-To-Host Static Callbacks

**Status:** design and implementation blocked; this is distinct from host
exports accepting a callback.

**Evidence:** the target host-binding design declares `@host_func`, but the
current parser accepts only `@host` host imports. Its host parameter grammar
does not accept `FuncType`, so it cannot currently describe a host function
such as `(Button, (ClickEvent) -> nil) -> Subscription`.

**Target contract:** an `@host_func` parameter may contain an inline function
signature only in that host declaration. The compiler lowers the non-capturing
callback to a private per-instance static callback id and emits a typed
dispatcher. `callback_id` is not a Do type, resource, or manifest value.

**Required decisions before implementation:**

- v1 callback result is `nil`; no synchronous result is returned through an
  event callback.
- Callback inputs and outputs use only already-defined canonical copied value
  shapes; no raw ARC handle, pointer, or host object crosses the dispatcher.
- A host must not re-enter the same instance through the dispatcher before the
  registration call returns; later reentrancy requires an explicit runtime
  rule and test suite.
- Callback ids are valid only for the creating instance and must not be reused
  by a disposed instance without an adapter-side instance generation check.

**Unblock condition:** implement `@host_func`, add the restricted inline
callback parameter grammar, freeze dispatcher argument/error/reentrancy ABI,
and add WAT plus host-adapter lifecycle fixtures.

### Adapter Lifecycle Probe

**Status:** the JavaScript-side subscription registry is verified in isolation;
end-to-end Wasm callback delivery remains blocked by the items above.

**Evidence:** `examples/ui-signal/host-runtime.test.ts` verifies dispatch while
live, explicit unsubscribe, a host-retained late listener after unsubscribe,
idempotent instance disposal, disposal of every listener, and rejection of a
new subscription after disposal. The registry identifies subscriptions by an
opaque token object and checks both per-subscription liveness and an
instance-generation value before calling the dispatcher.

**Boundary:** this probe uses fake event targets and a fake static dispatcher.
Its event payload is still an adapter-local `unknown` value, not the canonical
copied JS/Wasm value ABI. It does not claim that `@host_func`, generic
resources, generated callback ids, or a real Wasm instance are implemented.

### Event Pump Probe

**Status:** the adapter has a verified host queue plus scheduled-drain primitive
that does not require a guest async stack or a guest callback value.

**Evidence:** `examples/ui-signal/host-runtime.test.ts` verifies that an idle
pump schedules no work, a synchronous event batch produces one drain, an event
enqueued by a drain runs in a later microtask instead of re-entering the
dispatcher, and instance disposal drops a queued event before its drain runs.

**Boundary:** this is an adapter-local event loop primitive. Its `drain` target
is a fixed host-held function plus `instance_id`; it is not yet a generated
Wasm export, and `nextEvent()` does not yet use the canonical copied value ABI.
It does not implement WIT `stream<T>`, `future<T>`, `pollable`, cancellation,
or TCP/UDP stream lowering.

## G6.2 General Resource Ownership

**Status:** bounded private general-resource design is pending; public `own<T>`/`borrow<T>`/`ref<T>` syntax remains out of scope.

**Evidence:** the current plan records a green StreamMirror closeout, the latest
`pass=1149 fail=0 skip=3` default and `pass=1151 fail=0 skip=3` WASM regressions
with `pass=6 fail=0` smoke, ReleaseSmall smoke, and the pinned negative gates
for sixth forwarding, arbitrary producer expressions, and borrowed stream
rejection. The capability matrix still treats general producer lease,
borrowed/list/variant fields, and the wider async/resource gates as blocked
until a separate positive plan is authorized.

**Boundary:** cancellation releases live Component resources and does not compensate external effects. The current plan does not add an operation-id or rollback protocol.

**Unblock condition:** finish the matrix/design/fixture gate in `doc/superpowers/plans/2026-08-03-g6-2-general-resource-ownership.md` and keep the later general async/D2 host I/O tracks on their own design gates.

## Generic Host Resources

**Status:** blocked by missing executable generic host resource declaration.

**Evidence:** `doc/host-binding-design.md` specifies `@host_resource`, but the
current grammar implements only the WASI-specific `@wasi_resource`. A browser
`Button` and a returned `Subscription` therefore cannot honestly be declared
as generic opaque host resources today.

**Required contract:** `Button` and `Subscription` are opaque host resource
handles, never JS object references or numeric values that source code can
fabricate. `unsubscribe(subscription)` explicitly destroys the host listener;
the host removes all remaining subscriptions before instance disposal.

**Unblock condition:** implement the documented `@host_resource` declaration,
its private handle representation, ownership validation, explicit destructor
mapping, and adapter-side disposal behavior. Do not use deferred `@host_ref`
or raw `externref` as a shortcut for v1.

## Generic Struct Parameters

**Status:** concrete generic struct field expansion is supported for the
current unmanaged/managed-scalar/union field shapes.

**Evidence:** `Box<i32>` is accepted by the host-export collector. Its
post-monomorphization field substitution produces one `i32` WAT parameter and
the host manifest reports the same `"wasm_params":["i32"]` sequence in
`src/build/test/compile_ok/341_host_export_generic_struct.*` and the nested
`342_host_export_nested_generic_struct.*` fixture. The shared collector tests
also cover a managed scalar handle, a payload-plus-tag union, and unresolved
generic rejection.

**Current protection:** generic templates and unresolved bindings remain
rejected with `HostExportGenericStructAbiUnsupported`. Managed concrete fields
continue to use their single `i32` ABI value, and union fields use the normal
payload slots followed by an `i32` tag.

**Remaining work:** extend the same record matrix to additional multiword and
resource-shaped fields only after their ownership/host-handle contract is
specified. Canonical JS values and ownership protocols remain outside this
ABI.

## Canonical JS Values

**Status:** not yet designed; it is not a Core Wasm manifest defect.

**Evidence:** `text` is currently an ARC-managed `i32` handle. Lists and
managed structs also use runtime-owned memory layouts. A browser host cannot
safely fabricate, retain, or release these handles from the Core value type
alone.

**Current protection:** the manifest reports both source and Core Wasm value
types, but does not claim a JavaScript object/value conversion or ownership
transfer rule.

**Unblock condition:** freeze the generic JS/Wasm value ABI with allocation,
copy/borrow/transfer ownership, error, and cleanup semantics before adding
`lib/ui.do` host imports.

## WASI HTTP Client ABI

**Status:** fixed executable Component slices exist for the pinned HTTP service,
empty request construction, one finite CLI-stdin request body, response status,
a bounded response-body probe, and a trailers-future read/discard probe; general
canonical lowering and a standard-library binding remain unavailable.

**Evidence:** the compiler vendors the checked upstream `wasi-http` snapshot
`7c678c4c10238a4bf4db91a0e27023d680ff65fe` under
`src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16`. Its manifest test fixes the
`worlds.wit`, `types.wit`, and dependency lock hashes before any future
descriptor can consume the input. The snapshot defines
`wasi:http@0.3.0-rc-2025-09-16/client.send` as
`async func(request: request) -> result<response, error-code>` in
`wit-0.3.0-draft/worlds.wit`. Both `request` and `response` are resources.
`src/build/resource_abi_registry.json` records this exact package/interface
member with an `own` request input and an owned response Result payload; the
registry represents their distinct resource paths without exposing
`own<T>`/`borrow<T>` as Do source types. In particular, `response` exposes
resource methods such as `get-status-code` and `consume-body`; the latter
moves the response and returns a `stream<u8>` plus a trailers `future`.
`request` has the corresponding resource/body ownership rules.

`src/build/p3_async_registry.json` additionally pins the corresponding
`@host_func` source declaration to the WIT `service` world and its exact
`[async-lower]send` import name and records the canonical completion words as
`i32 i32 i32 i64 i32 i32 i32 i32`, including the `i64` payload word emitted by
the pinned toolchain. The `--p3-async-component` target accepts the
exact `handle(request HttpRequest) -> Result<HttpResponse, HttpError>`
shape where the async host binding `send(request)` returns a Future and is
immediately returned from `@await`, either directly or through an identically
typed Result binding. It
emits the service export, consumes and drops the request, and
returns either an owned response or a no-payload `error-code`. The regression
at `examples/p3-runtime/test_http_service_abi_surface.sh` compiles, assembles,
validates, and invokes that Component concurrently in the Rust Wasmtime host.
`do check` also rejects a second transfer of the async `HttpRequest` parameter.
The async host-import semantic gate accepts only this exact pinned descriptor
shape and defers its service-specific validation to `HttpServicePlan`; an
unknown or otherwise unlowerable descriptor still fails the generic async gate.
Ordinary `do build` and every other async HTTP source form remain guarded.

The service plan now validates the complete nominal resource graph before it is
selected: `fields` (the WIT `headers`/`trailers` alias), `request-options`,
`request`, and `response`, plus the pinned `request.new`, both `consume-body`
operations, and `client.send` signatures. The required Do shells are
`HttpHeaders`, `HttpRequestOptions`, `HttpRequest`, and `HttpResponse`; a source
program with only copied request/response records or an incomplete graph is
rejected. `examples/p3-runtime/test_do_wasi_http_request_shape.sh` covers the
check/build boundary, while `test_http_service_abi_surface.sh` covers the
generated Component ABI and Rust/Wasmtime adapter. This is a shape gate only:
it does not lower request construction, body/trailer streams, or arbitrary HTTP
resource operations.

**Boundary:** `doc/wit/wasi_registry.json` currently records the unversioned
`http/client/send` shape, while `lib/http.client.do` declares copied
`HttpRequest` and `HttpResponse` records. Those records cannot represent the
WIT resource identity, ownership transfer, headers, body stream, trailers, or
async result. Mapping `response` to `{ status u16, body [u8] }` would silently
change the ABI and lose required lifecycle behavior.

**Empty-request checkpoint (2026-08-02):** the compiler now admits one bounded
constructor shape under `--p3-async-component`. It creates empty `fields`, passes
`none` for the request body and options, writes an immediate `Ok(None)` trailers
future, and calls the pinned static `request.new`. The returned request is stored
in the async frame and may be transferred exactly once to the fixed `client.send`
probe. The transmission future and trailers future are explicitly read or
dropped before terminal cleanup. `examples/p3-runtime/test_do_http_request_empty_lowering.sh`
verifies Core/Component assembly, while
`test_rust_http_request_empty.sh` and
`test_rust_http_service_empty_request.sh` verify two independent calls, success
and no-payload `DNS-timeout`, exactly-once lifecycle handling, and an empty
Wasmtime `ResourceTable`.

The standalone minimal HTTP sidecar is intentionally not the composition path:
its shortened `error-code` definition does not match the pinned task-return
shape. The authoritative combined request-to-`client.send` check therefore uses
`--p3-wit-package-output`, which emits the complete pinned types package. This is
a packaging boundary, not a relaxation of the ABI.

**Request-body stream checkpoint (2026-08-02):** one further executable slice
now admits a finite `wasi:cli/stdin.read-via-stream` `Stream<u8>` as the
`request.new` body. The source form is fixed: acquire one reader/future pair,
pass the reader once as `option<stream<u8>>`, transfer the constructed request
once to `client.send`, and release the independent source completion future at
the send terminal callback. The host runner supplies `[65,66]` and exercises
two calls, one successful and one `DnsTimeout`; it observes both body payloads,
two source stream drops, two source future drops, one response, and an empty
`ResourceTable`.

The ABI gate is `examples/p3-runtime/test_do_http_request_body_abi.sh`; the
compiler/component gate is `test_do_http_request_body_lowering.sh`; and the
Wasmtime ownership gate is `test_rust_http_request_body.sh`. The probe also
asserts that an unregistered indexed stream import is rejected by
`component new`. This is an internal WIT/manifest boundary: it does not expose
`own<T>`, `borrow<T>`, `ref<T>`, pointers, or references in Do source.

**Request-body boundary:** only the pinned CLI `Stream<u8>` source and the
linear finite sequence are admitted. Dynamic producers, source-level loops,
arbitrary stream descriptors, dynamic trailers, trailer payload lifting,
unregistered/general payload-bearing error codes, and general HTTP lowering
remain rejected. The separately registered `internal-error` and `DNS-error`
payloads are admitted only by the pending compiler-service gate described
below.

**Guest-produced request-body checkpoint (2026-08-02):** the dedicated producer
probe admits one guest-created `new_stream<u8>(1)`, transfers its readable
endpoint through `request.new`, starts `client.send`, then performs at most
three literal `u8` writes with one await per write, closes the writer exactly
once, and awaits the transmission future. Component streams are rendezvous
operations, so a write before `request.new`/`send` is rejected rather than
treated as an implicit guest buffer. The ABI, lowering, and Rust/Wasmtime gates
are `test_do_http_request_body_producer_abi.sh`,
`test_do_http_request_body_producer_lowering.sh`, and
`test_rust_http_request_body_producer.sh`; the runner observes `[65,66]`, one
pending write, one success and one no-payload error, exactly-once endpoint and
future cleanup, and an empty `ResourceTable`.

This is still a bounded compiler probe. Dynamic producer loops, arbitrary
stream element types or endpoints, producer error mapping, dynamic trailers,
unregistered/general payload-bearing error codes, and public
`own<T>`/`borrow<T>`/`ref<T>` syntax remain outside the admitted surface.

**Remaining boundary:** extend canonical lift/lower for dynamic/general request
bodies, dynamic trailers, trailer payloads, general payload-bearing error-codes,
ready completion delivery outside the registered shapes, general async control
flow, cancellation interaction, and broader resource methods/drop semantics with
component execution fixtures.
Only then may a Do HTTP wrapper choose a copied convenience API above the
resource ABI; it must not replace that ABI.

**Payload error checkpoint (2026-08-04):** the pinned registry now admits only
the descriptor-validated `internal-error(option<string>)` and
`DNS-error(rcode: option<string>, info-code: option<u16>)` shapes. The canonical
ABI probe preserves `InternalError(Some("x"))` and
`DnsError(rcode=Some("EAI"),info-code=Some(7))`; the host-lowered candidate's
`Some -> None` mismatch remains explicitly blocked. The compiler-generated WAT
and Component pending gate now preserve both InternalError values and the DNS
payload, with request consumption, zero response creation, and
`table-empty=true` across pending and ready delivery; the combined entry point is
`examples/p3-runtime/test_do_http_payload_error_lowering.sh all`.
The ready immediate-return path now branches on `Status::Returned` before
extracting a waitable handle, so the former `unknown handle index 0` failure is
closed without weakening payload assertions or silently dropping payload data.
General ready delivery outside the registered shapes and cancellation interaction
remain outside this bounded checkpoint.
`examples/p3-runtime/test_do_http_payload_error_boundary.sh` continues to
verify that every unregistered payload tag retains an explicit trap.

**Payload cancellation discard ABI probe (2026-08-04):** an isolated
`http-payload-cancel` Core module now proves the canonical ownership hand-off
for the pinned immediate
`DNS-error(rcode: Some("EAI"), info-code: Some(7))` path. Component lowering
calls guest `cabi_realloc(0, 0, 1, 3)` for the `rcode` string in the fixed
`[64,128)` result area; the probe validates the result layout and byte payload,
then calls `cabi_realloc(pointer, 3, 1, 0)` exactly once before terminal task
return. Its reallocator traps on a missing, duplicate, or differently-shaped
allocation/release, and the Rust/Wasmtime gate observes one ready-future
poll/drop, zero response resources, and `table-empty=true`. The subsequent
compiler lowering consumes only this string protocol: its private reallocator
permits one nonempty `rcode` allocation in `[128,65536)` at a time, validates
the returned pointer/length on release, and returns the slot to idle for a
later sequential call in the same component instance. It accepts `DNS-error`
with either `info-code` option state. Component/Rust gates cover
`Some("EAI"), Some(7)`, the distinct length/option case
`Some("dns-error-long"), None`, the no-payload `rcode=None, info-code=None`
case, and two sequential `Some("EAI")` calls in one instance. For `Some`, the
string is released exactly once; for `None`, lowering validates only the option
discriminant and does not read or release pointer/length fields. The same
bounded protocol now covers
`InternalError(Some("no"))` and `InternalError(None)`. This is not generic
payload destruction: empty strings, other variants, record/resource payloads,
and unregistered tags retain an explicit trap.

**Response body stream checkpoint (2026-08-01):** the unified Component target
now admits the pinned `response.consume-body` operation for a bounded linear
sequence of one to three successful `stream<u8>` reads or a terminal
`Err(nil)` EOF result. The emitter stores a read index in the async frame,
starts the next read only after an `Ok(u8)` completion, and either cancels the
independent trailers future or performs one explicit `future.read-2` before
exactly-once stream/future/frame cleanup. The one-read, two-read, and three-read fixtures are
`examples/p3-runtime/http-response-consume-body-read.do` and
`examples/p3-runtime/http-response-consume-body-two-read.do` and
`examples/p3-runtime/http-response-consume-body-three-read.do`; their assembly
and Wasmtime checks are
`test_rust_http_response_consume_body_read.sh` and
`test_rust_http_response_consume_body_two_read.sh` and
`test_rust_http_response_consume_body_three_read.sh` and
`test_rust_http_response_consume_body_eof.sh`. The trailers await fixture is
`examples/p3-runtime/http-response-consume-body-await-trailers.do`, with
`test_rust_http_response_consume_body_await_trailers.sh` covering both pending
and ready future delivery. The host runner observes
one response consumption, one stream drop, one trailers-future drop, and an
empty resource table for each admitted length.

**Response body boundary:** this slice does not admit conditional or dynamic
EOF iteration, trailer payload lifting (the future result is currently discarded), request
construction, payload-bearing error-code lowering, or general `client.send`.
Those remain separate blockers and must not be inferred from the bounded
successful-read probe.

## Stream Endpoint Surface

**Status:** the public source contract is selected and parser/sema validation
is implemented. The pinned CLI stdin `u8` Stream slice now has canonical
Component lowering and Rust/Wasmtime execution; generic Stream lowering,
backpressure, and arbitrary stream-producing interfaces remain blocked.

**Evidence:** the vendored pinned WIT tree already supplies a real small
WASI stream boundary: `wasi:cli/stdin.read-via-stream` returns
`tuple<stream<u8>, future<result<_, error-code>>>`. The installed
`wasm-tools 1.255.0` also recognizes the current `stream.*` and `future.*` Core
operations. The admitted source form is `pending Future<Result<T, nil>> =
@next(reader)`: it retains the caller-owned `Stream<T>`/`StreamReader<T>`,
uses `Ok` for an item and `Err(nil)` for EOF, and leaves an imported completion
`Future<Result<nil, E>>` as a separate explicit future. `recv` remains a
finite `[T]` loop operation and is not reused for a stream.

**Evidence:** `test_do_cli_stream_stdin_lowering.sh` validates the generated
Core/WIT artifacts. `test_rust_cli_stream_stdin.sh` runs the same Component
through Wasmtime twice: once with a pending host Future and once with an
already-ready host Future. The unread completion is released directly with
`future.drop-readable`; neither run polls or calls `future.cancel-read`. Both
runs consume two items, observe EOF, and release the stream and future exactly
once.

The reproducible sidecar is
`examples/p3-runtime/wit/cli-stream-stdin.wit` with SHA-256
`c12c40df23a0ad562e743487b907113dbc9daadafa347d65d151d210d1292fc7`.
The compiler command is `do build --p3-async-component --p3-wit-output`;
`test_do_cli_stream_stdin_lowering.sh` then runs `wasm-tools parse`,
`component embed`, `component new`, and Component validation. The runtime
command is `bash examples/p3-runtime/test_rust_cli_stream_stdin.sh`, which
executes the same Component once with a pending completion and once with an
already-ready completion; both assert items `[97, 98]`, EOF, and exactly-once
stream/Future disposal.

The same descriptor-driven lowering is exercised with a private custom package:
`do:stream-probe@0.1.0` / `source.read-via-stream`. Its explicit registry entry
supplies the canonical module and operation names; the compiler does not infer
them from a locator or member string. `test_do_stream_reader_descriptor.sh`
checks the custom WAT/WIT artifacts, and
`test_rust_stream_reader_descriptor.sh` assembles and executes the Component
with Wasmtime. The host records two items `[97, 98]`, EOF, no completion-future
poll, and exactly one drop for both the stream and completion future.

**Current boundary:** the consumer lifecycle is now generalized to one
registered non-filesystem record stream, and the bounded scalar producer path
is separately verified. The generic consumer admits a validated record layout,
a dynamic `@next`/`await` loop, pending/ready completion, a completion error,
and exactly-once stream/future/resource cleanup. The producer gate admits only
two literal `u8` writes through a capacity-one `StreamWriter<u8>` pump and
selects the registered `do:stream-probe/sink@0.1.0` host instance by descriptor.
General producer leases, general dynamic producer loops, arbitrary element layouts, borrowed/list/variant
resource fields, seventh-level or more general nested resource layouts, and arbitrary WIT stream-producing interfaces remain
outside this runtime path.

**2026-08-02 read-directory ABI checkpoint:**
`examples/p3-runtime/test_do_wasi_filesystem_read_directory_abi.sh` generates
the pinned `wasi:filesystem/imports` world with current `wasm-tools 1.255.0` and checks
the exact `[async-lower][method]descriptor.read-directory` import, stream index
`0`, future index `1`, indexed stream/future drops, and the `(i32, i32) -> i32`
method/future-read callback shape. The embedded component type confirms
`directory-entry { type: descriptor-type, name: string }`. This fixed slice now
has compiler lowering, Component assembly, and Rust/Wasmtime execution gates
for one read and for a statically visible two-entry sequence plus EOF probe.
The bounded runner observes `alpha`, `beta`, three stream reads including EOF,
both pending-once and immediately-ready completion futures, exactly-once
stream/future/resource cleanup, and an empty resource table. The fixed slice
remains independently verified; its remaining boundary is arbitrary filesystem
async methods and payload-bearing completion errors.

**2026-08-02 record-layout checkpoint:** the pinned async manifest now carries
validated `directory-entry` Core field facts (`type@0`, `name-ptr@4`,
`name-len@8`). The bounded emitter consumes these registry-owned offsets while
preserving the `frame+64` result-area base and all cleanup transitions. Missing,
unaligned, overlapping, or non-scalar layout facts reject the descriptor; this
does not admit generic record layouts, general dynamic iteration, or arbitrary
filesystem async methods.

**2026-08-02 record-source checkpoint:** `src/build/p3_filesystem_wit_manifest.zig`
now verifies the pinned filesystem WIT source hashes and the source declaration
of `directory-entry` (`%type: descriptor-type`, `name: string`). The async
manifest records the matching `types.wit` hash, and both `@host` and
`@host_func` declarations for the admitted record-stream descriptor reject a
wrong `@wasi_record` target, field order, or Do-side field type. This closes
source/manifest drift for the fixed descriptor only; it does not admit generic
record definitions, dynamic streams, payload-bearing completion errors, or
other filesystem async methods.

**2026-08-02 generic record-stream consumer checkpoint:**
`src/build/codegen_component_record_stream.zig` now emits a descriptor-driven
consumer for the registered `do:record-stream-probe@0.1.0` record stream. The
probe accepts `ProbeEntry { id: u32, label: string }`, drives a dynamic
`@next`/`await` loop with one read in flight, lifts scalar and UTF-8 fields,
awaits the independent completion future, and emits tag/payload completion
results. `test_do_record_stream_probe_lowering.sh` validates the generated
Core module and Component; `test_rust_record_stream_probe.sh` validates
pending, immediately-ready, and `Err(io)` completion modes. The runner observes
`[(1, alpha), (2, beta)]`, EOF, one pending wake only in pending mode, one drop
each for stream and future, and an empty `ResourceTable` after every call.

This closes the generic **consumer** slice of G6.2. A bounded scalar producer
gate and a narrower helper-mediated lease gate are recorded below; general
producer leases, borrowed/nested/variant resource-valued
record fields, payload-bearing completion errors beyond the admitted error
shape, and arbitrary filesystem async methods remain outside this slice.

**2026-08-02 multiple owned resource-field checkpoint:** the same descriptor
driven consumer now admits a private `resource-entry` with two
`own<ticket>` fields. Manifest validation reserves one aligned `i32` slot per
field; WIT declares `ticket` once and the Core module imports
`[resource-drop]ticket` once. The generated release helper keeps the record
active bit around the whole field loop, then checks, drops, and clears every
handle before clearing the bit. `test_do_record_resource_stream_multi_probe_lowering.sh`
and `test_rust_record_resource_stream_multi_probe.sh` validate WAT/WIT assembly
and pending/ready/error Wasmtime execution with four resource drops and an
empty `ResourceTable`. Borrowed, nested/list/variant fields and resource
escape remain rejected.

**2026-08-02 generic stream-writer producer checkpoint:** the bounded guest
`StreamWriter<u8>` pump is now exercised through the registered private
`do:stream-probe@0.1.0/sink.write-via-stream` descriptor instead of the pinned
stdout package. `stream-probe-guest-producer-component.do` performs exactly two
literal writes with capacity one, closes the writer once, transfers the stream
once, and awaits the no-payload result. The custom Rust/Wasmtime runner variant
selects `do:stream-probe/sink@0.1.0` and export `produce`, and its pending,
ready, and `Err(pipe)` probes observe `[65, 66]`, one host callback, and one
stream drop; the error marker explicitly requires `result=err:pipe` together
with `stream-dropped=true`. `test_do_stream_writer_guest_producer_descriptor.sh`
and `test_rust_stream_writer_guest_producer_descriptor.sh` are the lowering and
runtime gates. This proves descriptor-driven producer wiring and bounded
backpressure only; general dynamic producer loops, general producer leases, and arbitrary
element layouts remain unadmitted.

**2026-08-03 helper-mediated producer-lease checkpoints:** a bounded guest
producer may transfer its `StreamWriter<u8>` once at the root level to a
same-typed async helper. The helper may directly call the registered
`do:stream-probe/sink.write-via-stream` descriptor or perform a bounded linear
`u8` write sequence before that call, and the final helper closes its lease
with `defer close(writer)`. The adjacent two-hop and three-hop shapes permit
private forwarding helpers to pass the still-open lease to the final helper;
each forwarder performs no write and no close. The descriptor-specific emitter
folds the fixed helper shape into the `produce` root; generated WIT exports
only the root. The original forwarding, helper-owned sequence
(`397_stream_writer_helper_owned_writes.do`), two-hop, and three-hop fixtures are covered
by Component lowering plus pending/ready/`Err(pipe)` Rust/Wasmtime gates,
observing `[65, 66]`, one host callback, and one stream drop. A sixth hop,
general async function calls, general dynamic producer loops, arbitrary element
layouts, borrowed/nested/variant resource fields, and broader completion-error
payloads remain outside G6.2.

**2026-08-03 bounded dynamic producer checkpoint:** the registered
`do:stream-probe/sink.write-via-stream` path now also admits one explicit
countdown shape: `produce(count u64)` creates a capacity-one `StreamWriter<u8>`,
writes literal `65` once per iteration, awaits each write, closes once, and
awaits the sink. The emitter stores `remaining` as `i64` at frame offset 52 and
starts the sink before pumping, so `count=0` is a valid empty stream. The
Component gate and Rust/Wasmtime runner cover `count=0/1/3` in pending, ready,
and `Err(pipe)` modes, observing ordered bytes, one host callback, and one
stream drop. This remains a bounded descriptor-specific gate: arbitrary loops,
dynamic byte values, general async calls, producer leases beyond the admitted
helper shapes, and borrowed/nested/variant resource fields remain blocked.

**2026-08-03 parameterized helper producer checkpoint:** the same registered
`do:stream-probe/sink.write-via-stream` path now admits one private helper with
the exact `(StreamWriter<u8>, u64, u8)` parameter shape. The root transfers the
writer, count, and value directly; the descriptor-specific emitter folds the
helper countdown into the single `produce(count, value)` Component export and
reuses frame offsets 52 and 60. The lowering gate and
`test_rust_stream_writer_guest_producer_parameterized_helper.sh` cover
`count=0/1/3`, `value=90`, pending/ready/`Err(pipe)`, one host callback, and one
stream drop. This is still a private source-shape adapter: arbitrary async
calls, additional helper hops, arbitrary producer expressions, and
borrowed/nested/variant resource fields remain outside G6.2.

**2026-08-03 parameterized five-hop forwarding helper producer checkpoint:**
the same registered shape now admits exactly
`produce -> outer_stream -> entry_stream -> forward_stream -> middle_stream -> inner_stream -> finish_stream`.
All five private forwarding helpers pass `(writer, count, value)` unchanged and
only await the next same-typed helper; the final helper remains the existing
countdown/close/sink shape. Component lowering still emits only the root export
and reuses frame offsets 52 and 60. The dedicated Component and Rust/Wasmtime
gates cover `count=0/1/3`, `value=90`, pending/ready/`Err(pipe)`, one host
callback, and one stream drop. A sixth forwarding edge, crossed or literal
arguments, general async calls, arbitrary producer expressions, and
borrowed/nested/variant resource fields remain outside G6.2.

**2026-08-03 parameterized forwarding helper producer checkpoint:** the same
registered `do:stream-probe/sink.write-via-stream` shape now admits one private
parameterized forwarding helper. `produce` transfers `(writer, count, value)`
to `forward_stream`, which transfers the same three direct parameters to the
already verified countdown helper. The descriptor-specific emitter still emits
only the root export and reuses frame offsets 52 and 60. The new Component and
Rust/Wasmtime gates cover `count=0/1/3`, `value=90`, pending/ready/`Err(pipe)`,
one host callback, and one stream drop. A sixth forwarding edge, crossed or
literal arguments, general async calls, arbitrary producer expressions, and
borrowed/nested/variant resource fields remain outside G6.2.

**2026-08-03 reordered parameterized helper checkpoint:** the same registered
shape now accepts the three private helper parameters in any declaration order,
provided the call supplies exactly one `StreamWriter<u8>`, one `u64`, and one
`u8` source identifier in that declaration order. The sema ownership pass finds
the writer argument by its typed formal slot, so a reordered forwarding helper
still transfers and closes the lease exactly once. The descriptor-specific
Component emitter keeps the `(i64, i32)` root export and frame offsets 52/60;
the new Component and Rust/Wasmtime gates cover count `0/1/3`, value `90`,
pending/ready/`Err(pipe)`, one callback, and one stream drop. Literal, duplicate,
missing, extra, or arbitrary expression arguments, a sixth forwarding edge, and general
producer/resource shapes remain rejected.

**2026-08-03 branch-selected terminal checkpoint:** the same private
`do:stream-probe/sink.write-via-stream` descriptor now admits one helper-mediated
terminal branch: normal completion calls `close(writer)`, while the registered
`pipe` path calls `abort(writer, 2)`. Component lowering keeps one root export and
routes both arms through the same exactly-once writer/task/waitable cleanup
epilogue. `test_do_stream_writer_guest_producer_branch_terminal.sh` and
`test_rust_stream_writer_guest_producer_branch_terminal.sh` cover pending/ready
normal completion and the abort result, observing one host callback, one stream
drop, and one terminal completion. This producer-only runner has no
`ResourceTable`, so its evidence does not claim `table-empty=true`; sixth
forwarding, dynamic abort codes, arbitrary producer expressions, and general
async composition remain rejected.

**2026-08-03 parameterized two-hop forwarding helper producer checkpoint:** the
same registered shape now admits exactly
`produce -> forward_stream -> middle_stream -> finish_stream`. Both private
forwarders pass `(writer, count, value)` unchanged and only await the next
same-typed helper; the final helper remains the existing countdown/close/sink
shape. Component lowering still emits only the root export and reuses frame
offsets 52 and 60. Component plus Rust/Wasmtime pending/ready/`Err(pipe)` gates
cover `count=0/1/3`, `value=90`, one host callback, and one stream drop. A third
forwarding edge, crossed or literal arguments, general async calls, arbitrary
producer expressions, and borrowed/nested/variant resource fields remain
outside G6.2.

**2026-08-03 parameterized three-hop forwarding helper producer checkpoint:**
the same registered shape now admits exactly
`produce -> entry_stream -> forward_stream -> middle_stream -> finish_stream`.
All three private forwarding helpers pass `(writer, count, value)` unchanged
and only await the next same-typed helper; the final helper remains the existing
countdown/close/sink shape. Component lowering still emits only the root export
and reuses frame offsets 52 and 60. The dedicated Component and Rust/Wasmtime
gates cover `count=0/1/3`, `value=90`, pending/ready/`Err(pipe)`, one host
callback, and one stream drop. A sixth forwarding edge, crossed or literal
arguments, general async calls, arbitrary producer expressions, and
borrowed/nested/variant resource fields remain outside G6.2.

**2026-08-03 parameterized four-hop forwarding helper producer checkpoint:**
the same registered shape now admits exactly
`produce -> outer_stream -> entry_stream -> forward_stream -> middle_stream -> finish_stream`.
All four private forwarding helpers pass `(writer, count, value)` unchanged and
only await the next same-typed helper; the final helper remains the existing
countdown/close/sink shape. Component lowering still emits only the root export
and reuses frame offsets 52 and 60. The dedicated Component and Rust/Wasmtime
gates cover `count=0/1/3`, `value=90`, pending/ready/`Err(pipe)`, one host
callback, and one stream drop. A sixth forwarding edge, crossed or literal
arguments, general async calls, arbitrary producer expressions, and
borrowed/nested/variant resource fields remain outside G6.2.

**2026-08-03 nested owned-resource record checkpoints:** the private
`do:record-resource-stream-nested@0.1.0` descriptor admits one nested
`inner-entry` record, and the private
`do:record-resource-stream-nested-two-level@0.1.0` descriptor admits one
bounded `inner-entry -> deep-entry` path. Both contain one `own<ticket>` leaf.
The generated WIT keeps ownership private, the Core layout uses the canonical
nested handle slot at offset zero, and the frame-owned release helper clears
that slot after `[resource-drop]ticket`. Component lowering plus
pending/ready/error Rust/Wasmtime gates observe two records, two resource
drops, one stream drop, one future drop, and an empty resource table for each
descriptor. Borrowed, list, variant, a seventh level, and resource escape remain
rejected; multiple nested paths are covered by the bounded checkpoint below.

The pinned validator also supplies a hard boundary for borrowed fields:
`wasm-tools component embed` with `borrow<ticket>` fails with
`function read-via-stream returns a type which contains a borrow<T> which is
not supported`. This is a Component/WIT toolchain limitation, not a reason to
add public `borrow<T>` syntax to Do.

The accepted synchronous list shape has a separate oracle:
`examples/p3-runtime/test_list_borrow_canonical_abi.sh` uses
`wasm-tools 1.255.0 (76e20611d 2026-07-30)` and Wasmtime `47.0.2` to call
`read(values: list<borrow<ticket>>)` with lengths `0`, `1`, and `3`. The Core
fixture records `ptr=64` and a four-byte handle stride; the Rust host confirms
that the borrow callback can read the still-live owner and that exactly one
`[resource-drop]ticket` occurs after the call. This proves only the measured
synchronous private shape. It is not a generic borrowed-list lowering and does
not change the public no-reference Do model or the fail-closed stream/future
boundary.

**2026-08-07 owned-future canonical checkpoint:**
`examples/p3-runtime/test_future_owned_canonical_abi.sh` independently assembles
and executes the private WIT shape `read: func() -> future<own<ticket>>` with
`wasm-tools 1.255.0` and Wasmtime `47.0.2`. The Core probe stores the canonical
future payload at frame `+12`, transfers the ticket representation to `+16`,
and tracks ownership at `+20` because representation `0` is valid in an empty
Wasmtime `ResourceTable`. Ready, pending-once, and pending-then-cancel modes
observe one host call, one future drop, and an empty table; resource creation
and `[resource-drop]ticket` occur exactly once only for the two successful
modes. The callback consumes the frame payload and treats callback value `2` as
the cancellation `ReturnCode`, rather than treating that code as a pointer.
This is one private canonical/runtime slice only: generic owned async lowering,
borrowed async values, producer leases, and public ownership syntax remain
blocked; compiler registry admission is bounded to the isolated target below.

The measured slice is now promoted behind the isolated compiler target
`--p3-owned-future-component`. The compiler analyzer requires the exact
registered descriptor, one `Future<Ticket>` local, one `@await`, and the
declared `Ticket` resource; its emitter keeps the `+12/+16/+20` frame protocol
and the generated WIT `future<own<ticket>>` spelling private. The combined
gate `examples/p3-runtime/test_do_future_owned_component.sh` passes current
`wasm-tools 1.255.0` parsing and current async assembler, and the
Wasmtime ready/pending/cancel cleanup matrix. This does not generalize
`Future<T>`, add owned streams or borrowed async values, or add public
`own<T>`/`borrow<T>`/`ref<T>` syntax.

The manifest parser recursively validates the admitted paths and rejects a
seventh nested level, multiple children, mixed scalar/nested top-level fields,
or any unsupported child metadata at validation rather than silently lowering
it as a shallower record.

**2026-08-03 multiple nested owned-resource path checkpoint:** the private
`do:record-resource-stream-multiple-nested@0.1.0` descriptor admits two
top-level nested paths, `resource-entry.left -> left-entry.ticket` and
`resource-entry.right -> right-entry.ticket`. Each path has one final
`own<ticket>` leaf and one aligned Core `i32` slot at offsets zero and four.
The emitter walks both paths for WIT declarations, decode, and release; the
shared `ticket` resource declaration and `[resource-drop]ticket` import remain
deduplicated. The Component lowering gate and Rust/Wasmtime pending/ready/error
gates observe entries `[(1,111,222),(2,333,444)]`, four resource drops, one
stream drop, one future drop, and an empty resource table. Fifth-level paths,
multiple children, mixed top-level scalar/nested fields, borrow/list/variant
fields, and resource escape remain rejected.

**2026-08-03 three-level nested owned-resource checkpoint:** the private
`do:record-resource-stream-nested-three-level@0.1.0` descriptor admits one
`resource-entry.inner -> deep-entry -> deeper-entry -> own<ticket>` path. The
manifest ceiling is now four container levels; recursive WIT declaration, Core
decode/release, and the canonical frame-owned handle slot are reused without
adding public ownership syntax. Component lowering and Rust/Wasmtime
pending/ready/error gates observe `[111,222]`, two resource creates/drops, one
stream drop, one future drop, and an empty resource table. Fifth-level paths,
multiple children, mixed scalar/nested fields, borrow/list/variant fields, and
resource escape remain rejected. The exact gates are
`test_do_record_resource_stream_nested_three_level_probe_lowering.sh` and
`test_rust_record_resource_stream_nested_three_level_probe.sh`.

**2026-08-03 four-level nested owned-resource checkpoint:** the private
`do:record-resource-stream-nested-four-level@0.1.0` descriptor admits one
`resource-entry.inner -> deep-entry -> deeper-entry -> deepest-entry -> own<ticket>`
path. The recursive WIT declaration, Core decode/release, and canonical
frame-owned handle slot remain descriptor-driven; no public ownership syntax is
added. Component lowering and Rust/Wasmtime pending/ready/error gates observe
`[111,222]`, two resource creates/drops, one stream drop, one future drop, and
an empty resource table. Fifth-level paths, multiple children, mixed
scalar/nested fields, borrow/list/variant fields, and resource escape remain
rejected. The exact gates are
`test_do_record_resource_stream_nested_four_level_probe_lowering.sh` and
`test_rust_record_resource_stream_nested_four_level_probe.sh`.

**2026-08-03 five-level nested owned-resource checkpoint:** the private
`do:record-resource-stream-nested-five-level@0.1.0` descriptor admits one
`resource-entry.inner -> deep-entry -> deeper-entry -> deepest-entry -> ultra-entry -> own<ticket>`
path. The recursive WIT declaration, Core decode/release, and canonical
frame-owned handle slot remain descriptor-driven; no public ownership syntax
is added. Component lowering and Rust/Wasmtime pending/ready/error gates
observe `[111,222]`, two resource creates/drops, one stream drop, one future
drop, and an empty resource table. Seventh-level paths, multiple children, mixed
scalar/nested fields, borrow/list/variant fields, and resource escape remain
rejected. The exact gates are
`test_do_record_resource_stream_nested_five_level_probe_lowering.sh` and
`test_rust_record_resource_stream_nested_five_level_probe.sh`.

**2026-08-03 six-level nested owned-resource checkpoint:** the private
`do:record-resource-stream-nested-six-level@0.1.0` descriptor admits one
`resource-entry.inner -> deep-entry -> deeper-entry -> deepest-entry -> ultra-entry -> hyper-entry -> own<ticket>`
path. The recursive WIT declaration, Core decode/release, canonical
frame-owned handle slot, and deduplicated resource drop remain
descriptor-driven. Component lowering and Rust/Wasmtime pending/ready/error
gates observe `[111,222]`, two resource creates/drops, one stream drop, one
future drop, and an empty resource table. Seventh-level paths, multiple
children, mixed scalar/nested fields, borrow/list/variant fields, and resource
escape remain rejected. The exact gates are
`test_do_record_resource_stream_nested_six_level_probe_lowering.sh` and
`test_rust_record_resource_stream_nested_six_level_probe.sh`.

**2026-08-01 writer-frame evidence:** the pinned
`wasi:cli/stdout.write-via-stream` descriptor now emits a fixed `u8` writer
frame with queue head/count/capacity, pending-producer, terminal/error, and
pending pointer/length slots. The Core helper path contains explicit
`stream-write` promotion and backpressure transitions, while the Zig
`StreamWriterQueue` model covers FIFO, capacity-zero rendezvous, transfer,
close, abort, and wake flags. The completion frame follows the pinned compact
canonical Result layout: tag byte at offset 0 and `error-code` payload byte at
offset 1, each loaded with `i32.load8_u` before the two-word `task-return`.
`test_do_cli_stream_stdout_lowering.sh` and `test_rust_stream_writer.sh` pass
for the existing forwarding probe, including pending, immediately-ready, and
host `Err(pipe)` callbacks.

The generated writer frame now carries `[async-frame-budget-bytes] 64` and uses
the same instance-local checked counter as the GC frame emitters: it reserves
before `$frame-alloc`, releases before `$frame-free`, and exposes the Core-only
`[async-config]byte-budget-limit` hook with the `-1` unlimited default. The
writer's generated `cabi_realloc` is now covered by the shared transactional
realloc path described below. The external Component scheduler still has no
byte-budget owner or admission call site.

**2026-08-02 stdin-frame evidence:** the fixed scalar-u8
`wasi:cli/stdin.read-via-stream` lowering now carries
`[async-frame-budget-bytes] 32` and uses the same instance-local checked counter
and Core-only `[async-config]byte-budget-limit` hook. The generated
`$frame-alloc` reserves 32 bytes before either a fresh allocation or freelist
reuse, and `$frame-free` releases the charge exactly once before recycling the
frame. The 99-case Zig emitter suite, Core/WIT ABI and lowering scripts, and
Rust/Wasmtime stdin runner pass with this accounting present. The stdin
stream/future endpoint storage and generic scheduler admission remain outside
this boundary.

The pinned CLI stdin host runner now also exercises the 32-byte frame charge
through the host-only `BudgetGate`: a 31-byte limit rejects before the provider
is called, a second 32-byte admission is rejected while the first call is
live, and the released permit admits the next call. The same fixture augments
the temporary Component world with the private `byte-budget-limit` alias and
verifies 32-byte success plus 31-byte Component-side rejection before the
provider callback. This remains descriptor-specific evidence; stream/future
endpoint storage and generic scheduler policy are still outside the boundary.

**2026-08-02 cabi-realloc evidence:**
`src/build/codegen_component_cabi_realloc.zig` now owns the common generated
Core realloc contract. It reserves only `size - old_size` on growth, releases
`old_size - size` on shrink, leaves the byte counter unchanged for an equal
size, and releases the growth delta before trapping when `memory.grow` fails.
The `-1` limit remains unlimited. The rewrite is idempotent for templates that
already contain the budget helper and injects the instance-local limit,
reserve, release, and heap owner for older templates.

The path is exercised through the async component and special-target pipeline
for the pinned stream writer/stdin, HTTP response body/request/status, private
resource Result, wait-for, resource-probe, and filesystem-preopen templates.
The helper unit tests, component async Zig suite, WAT lowering scripts, and
relevant Rust/Wasmtime runners pass. This accounts allocation bytes only; it
does not claim external scheduler admission, general canonical buffer
ownership, or a complete host-configured quota API.

The standalone `examples/gc-p3-runtime/test_cabi_realloc_budget.sh` probe now
executes the shared transaction directly: an 8-byte grow followed by a 4-byte
shrink leaves usage at 4; a grow that exceeds the memory maximum returns the
failure sentinel after releasing its reservation and leaves both usage and the
heap owner unchanged; and a 4-byte limit rejects an 8-byte grow by trapping.
This is an allocator rollback probe only, not evidence that the external
Component scheduler or every canonical ABI allocation consumes the budget.

The fixed guest-producer probe is also executable: it creates a guest-owned
capacity-one `stream<u8>`, writes `65`, `66`, and `67`, and passes the writer to
the pinned stdout host function. `test_rust_guest_stream_writer.sh` observes
`[65, 66, 67]`, consumer early-drop after `[65]`, and host `Err(pipe)`; all three
paths close/drop the writer and reader exactly once. The later bounded producer
gates also exercise a source-level countdown operation plus one-, two-, three-,
and five-hop private helpers, including pending/ready/error runtime cases. None of these
gates claims arbitrary element layout or a mapping of Do `abort(writer, err)` to
an external WIT error payload.

**Writer boundary:** the admitted producer shapes use a descriptor-specific
writable queue pump and explicit frame-owned cleanup. They are intentionally
not a general producer language: arbitrary producer expressions, reordered or
literal helper arguments, a seventh forwarding hop, borrowed/list/variant
resource fields, and broader filesystem async methods remain rejected. A
general writable endpoint with unrestricted resumable reader-to-writer
composition is still outside the current gate.

## Component Model Delivery

**Status:** bounded slices delivered; general Component Model lowering remains
deferred.

**Evidence:** the existing Component pipeline has verified bounded scalar,
record, resource, stream, and future slices. General resource/stream/future
lowering remains deferred. WIT resources have `own`/`borrow`, but the
temporary Core callback id is not a WIT function value and must not be emitted
into a WIT interface.

**Required mapping:** `Subscription` maps to a WIT resource with an explicit
destructor. Long-lived event delivery maps to a stream or future/poll API, not
to the Core callback id.

**Unblock condition:** keep component planning rejected for host callback
imports until stream/future lowering, cancellation, and resource destruction
are executable and validated.

## Wasmtime 47 C Embedder Experiment

**Status:** an optional custom-host embedding experiment is blocked. It is not
a compiler, WIT, Component assembly, or general WASI P3 blocker.

**2026-07-28 generic async evidence:**
`examples/p3-runtime/test.sh` compiles and runs a local C embed runner against
Wasmtime 47.0.2. It creates one component call future, enters one host callback
registered through `wasmtime_component_linker_instance_add_func_async`, yields
once, and completes on the second continuation poll with result `27815`. The
fixture uses custom `do:component-async-probe@0.1.0`, not a P3 package, and its
WIT function is synchronous while the C host continuation supplies the async
boundary. A second fixture performs the same sequence with a Core GC `struct`
wholly inside the embedded core module; it does not enable component-model GC
or pass a GC ref over the component ABI. This proves the generic C API
mechanism, the core-GC/component coexistence boundary, and one-future Store
discipline only; it does not prove P3 async lowering or host binding.

**Evidence:** the locally installed Wasmtime is `47.0.2 (90fed3c6a,
2026-07-21)`. Its C API exposes
`wasmtime_component_func_call_async`, `wasmtime_call_future_poll`, and
`wasmtime_component_linker_instance_add_func_async`, so a C host can execute
and manually link a controlled async component fixture. The same headers expose
`wasmtime_component_linker_add_wasip2_async`, but no
`wasmtime_component_linker_add_wasip3*` helper. The CLI does expose `-S p3=y`.

**2026-07-28 exact P3 probe:** `examples/p3-runtime/async-wait-for-component.wat`
imports the pinned `wasi:clocks/monotonic-clock@0.3.0.wait-for` as
`async func(u64)`, lowers it through a minimal core wrapper, and returns through
`task.return`. `wasmtime_component_new` accepts that component. The runner then
registers `wait-for` with `wasmtime_component_linker_instance_add_func_async`,
but async instantiation rejects it with `instance export wait-for has the wrong
type`, caused by `type mismatch with async`. The C API name means that its host
callback may yield through a continuation; it does not expose a way to declare
the provider's Component Model function type as WIT `async`. The probe asserts
this exact failure and will fail loudly if a later Wasmtime revision links it,
requiring a new real suspend/resume success assertion.

**2026-07-29 Rust WIT async evidence:**
`examples/p3-runtime/test_rust_wait_for.sh` runs a separate Rust Wasmtime
47.0.2 adapter against the same `async-wait-for-component.wat` fixture. Its
checked-in Cargo manifest and lockfile pin `wasmtime = 47.0.2`. The adapter
enables component model async, more async builtins, and concurrency support;
it registers the exact `wasi:clocks/monotonic-clock@0.3.0` `wait-for` import
with `Linker::instance(...).func_wrap_concurrent`. One `Store::run_concurrent`
call invokes exported async `run` with `27815`. The host Future records the
argument, returns `Pending` exactly once, then uses `Accessor::spawn` to run a
host completion task in that Store's event loop. The task sends a one-shot
completion; only then does the Future complete. The test asserts one call, one
pending poll, one external wake, and one completion. The initial host poll uses
a noop Waker, so an embedder must use the Store event-loop API rather than
retaining that initial Waker for an external thread.

**2026-07-29 pinned compiler lowering evidence:**
`examples/p3-runtime/test_do_wait_for_lowering.sh` compiles
the `wait-for`, alias, and `wait-until` component fixtures with the unified
`do build --p3-async-component` target. The target classifies the pinned
scalar/unit descriptor, then emits Core WAT carrying
the legacy async ABI; the script explicitly embeds the pinned WIT metadata
with `wasm-tools component embed` and then runs `wasm-tools component new`
before giving the resulting Component binary to the Rust adapter. It exercises
two same-shape descriptors,
`wasi:clocks@0.3.0/monotonic-clock.wait-for` and `wait-until`; each fixture
uses one async `run(u64)` export, one `[async-lower]` subtask handle, a
task-local waitable-set `WAIT`, and one
`task.return` after `SUBTASK/RETURNED`; and one async lift/callback shape. The
Rust adapter verifies the `27815` argument, one Pending poll, one Store-loop
host wake, and one completion.

The CLI unit-Result probe still keeps task-local state in a linear-memory
frame: resume state at offset 0, waitable-set handle at offset 4, cleanup
flags at offset 8, and a completion value slot at offset 12. By contrast, the
selected P3 clocks and cancellation lowering now constructs `$async-frame` GC
structs, roots them in `$async-frames`, and exposes only an `i32` table handle
through `context-set-0`/`context-get-0`. Terminal cleanup clears the table root
before the handle enters the GC-private free-slot list. `codegen_async_model.zig`
still owns the source live-slot model; `codegen_gc_async_frame.zig` defines the
GC representation used by those selected P3 templates.

The target can write the assembly WIT sidecar with
`--p3-wit-output out.wit`; the supported assembly sequence is:

```bash
do build wait-for-component.do --p3-async-component \
  --p3-wit-output out.wit -o out.wat
wasm-tools component embed out.wit out.wat --world probe -o embedded.wasm
wasm-tools component new embedded.wasm -o component.wasm
```

**2026-08-01 immediate async completion evidence:** Wasmtime `47.0.2` returns
the pinned `Status::Returned` value as the bare Core word `2`; only
`Status::Started` encodes a subtask handle for `waitable-join`. The selected
clock unit, CLI unit-Result, scalar `Result<i32,i32>`, private resource
`Result<resource,error>`, and the pinned cancellation wrapper now branch on `2`
before shifting or joining/cancelling.
Each wrapper is exercised twice by its Rust/Wasmtime fixture: once with a
pending host future and once with an immediately-ready host future. The
multi-await/loop templates, arbitrary stream payloads, and HTTP resource
wrapper remain separate boundaries and are not implied by these checks.

**2026-07-31 sequential scalar evidence:**
`examples/p3-runtime/test_do_three_await_lowering.sh` compiles a single async
function that invokes `wait-for`, `wait-until`, then `wait-for` again. The
descriptor-driven plan emits one Core import/call site and one resume state per
invocation while de-duplicating the repeated WIT `wait-for` declaration. The
script validates Component assembly and runs two concurrent calls through the
Rust adapter; it observes six pending polls, six Store-loop wakes, and six
completions. This proves straight-line scalar/unit sequencing in the registered
clocks world. The separate `if-await-component.do` probe proves one restricted
two-way branch: `if @eq(input, u64-literal)` with one registered scalar await
and terminal return in each arm. It does not prove nested branches, joins,
general loops, payload, list, Stream, HTTP, or generic resource lowering.

For a scalar/unit function returning `nil`, the accepted straight-line terminal
forms are the final `await(future)` and `await(future)` followed immediately by
a bare `return`. A bare `return` with trailing source remains rejected; this
does not add general control-flow lowering.

Each registered scalar/unit operation may use the entry parameter (including a
straight-line alias) or a typed `u64` literal local. Literal values are emitted
at each host call, including after a resume; general scalar expressions and
mutable local-state lowering remain rejected. The only pure expression admitted
in this probe is `@add(parameter-or-alias, non-negative-u64-literal)`, which is
re-emitted at the initial and resumed call as `i64.add`.

The branch probe emits the selected operation's resume state before issuing its
subtask. Its callback accepts either terminal state and performs the same frame
cleanup and `task.return`. The separate if-join probe maps state 1 or 2 to the
same state-3 subtask, and only state 3 reaches cleanup. Neither probe lowers
arbitrary source CFG edges.

The separate countdown probes admit exactly one loop shape: a `u64` counter
before the loop initialized by a non-zero literal, the entry parameter, or
`@add(parameter, u64-literal)`; one registered scalar `Future<nil>` binding
and `await` in the body; `counter = @sub(counter, 1)`; and
`if @eq(counter, 0) { break }`. Its `$async-frame` contains the input and the
mutable counter. Each completion decrements the rooted counter, returns at
zero, or reissues state-1 `wait-for` with the stored input. The literal test
drives two calls through two iterations each and observes four Pending polls,
wakes, and completions. The parameter and parameter-add tests each observe five
for two calls with effective counts 2 and 3, proving the counter is initialized
and resumed per call. Parameter callers must supply a positive effective count;
this source shape underflows after its first await for zero. This proves only
that explicit form, not arbitrary loop CFG, `continue`, other assignments, or
non-zero break conditions.

The countdown await argument may be the entry parameter or the mutable counter.
The counter-argument fixture runs calls with initial counts 2 and 3 and the
Rust adapter observes five host calls with argument frequencies `{3: 1, 2: 2,
1: 2}`. That proves both the initial call and each resumed call load the rooted
counter rather than retaining the entry value.

An exact top-of-loop guard, `if @eq(counter, 0) { break }`, is also admitted.
It permits a literal zero initial count and changes the generated async lift to
release the frame and `task.return` before the first host call. The companion
probe invokes the export with 0 and 2 concurrently; only the latter produces
the two `wait-for` calls with arguments 2 and 1. This does not generalize to
arbitrary guard conditions or arbitrary break placement.

**Boundary:** this is an intentionally narrow source-to-Component probe, not
generic compiler lowering or a generic P3/WASI adapter. The explicit target
derives its Core import, ABI shape, async export names, and WIT sidecar from a
registered descriptor. It currently selects only scalar/unit clocks, the
no-payload CLI Result tag, or the private two-word resource Result probe. The
checked-in clocks execution fixture proves `wait-for` and `wait-until`; the
separate CLI/resource fixtures prove their respective layouts. The fixed
`@cancel` companion probe additionally validates Component subtask
cancellation. These probes do not add arbitrary resource cleanup, `Future<T>`
or `Stream<T>` lowering, frame serialization, scheduler lowering, or host-drive
semantics. The ordinary `do build` path keeps `AsyncLoweringUnavailable`.

**Boundary:** this fixture only proves or disproves a particular Wasmtime C
embedder API. A do build produces a standard Component artifact through the
pinned `wasm-tools` assembly path; it neither links Wasmtime nor calls this C
API. A runtime supplies the selected standard WASI imports when it loads that
artifact. `wasmtime_component_new` consumes an existing component binary; it
is not a component encoder for compiler-generated core WAT.

**Current input:** `examples/p3-runtime/p3-clocks-manifest.json` pins the
Wasmtime `v47.0.2` source snapshot (`90fed3c6adf53f112c4dea56851728557bb73799`)
for `wasi:clocks@0.3.0/monotonic-clock.wait-for`, an `async func(u64)` with no
result. `verify_p3_wit.sh` verifies the vendored WIT SHA-256 before every P3
probe run.

**Unblock condition:** an embedder that uses Wasmtime's C API still needs a C
API extension; the Rust `func_wrap_concurrent` route is a separate available
adapter surface. A runtime compatibility report must identify its API, pinned
WIT subset, and tested ownership/cancellation contract. Neither adapter result
makes the compiler artifact invalid or by itself proves its full execution.

## Component Task Cancellation

**Status:** verified for the fixed `wasi:clocks@0.3.0/monotonic-clock.wait-for`
P3 probe; it is not yet generic Future lowering.

**Evidence:** `examples/p3-runtime/test_rust_cancel_wait_for.sh` assembles the
legacy callback ABI fixture and runs it with Wasmtime `47.0.2`. The host async
function remains pending. `subtask.cancel` reaches `RETURN_CANCELLED (4)`, the
host future is dropped once, and `subtask.drop` then succeeds. The compiler
fixture `test_do_cancel_wait_for_lowering.sh` verifies the same sequence from
Do source through Component assembly.

The scalar Result companion extends this evidence without introducing a
source-level `Cancelled` value: `test_rust_scalar_result.sh` runs a host
`Result<i32, i32>` operation from a `nil`-returning async root, observes exactly
one committed external-effect marker and one host-future drop, and observes no
rollback marker. A root function with a non-`nil` result after bare `@cancel` is
rejected because the cancellation terminal has no result payload.

**Contract:** `@cancel(future)` consumes the Future and lowers directly to the
pinned `subtask.cancel` operation. The compiler does not create an operation
ID, host broker, cancellation acknowledgement, descriptor cancellation
capability, or public `Cancelled` result branch.

**Boundary:** Component task cancellation only ends the guest/host task
lifecycle. It does not prove an already-issued SQL update, HTTP request, or
other external side effect was rolled back, compensated, or made idempotent.
Those guarantees belong to the selected host API and business protocol.

## Task 8 Step 3 Runtime Baseline (2026-08-05)

**Status:** all currently admitted descriptor-specific runtime gates are
green; generic async lowering remains blocked by `AsyncLoweringUnavailable`.

**Evidence:** `examples/p3-runtime/test_task8_step3_baseline.sh` passed the
cancel-wait-for, scalar Result, resource Result, stream reader, stream writer,
filesystem preopen, and real TCP/UDP socket gates with Zig 0.16.0,
`wasm-tools 1.255.0`, Wasmtime 47.0.2, and Rust 1.97.1. The socket gate also
covers create and bind failures and verifies an empty resource table.

The first baseline run rejected the socket fixture with
`InvalidPinnedSocketsWit` because the manifest's embedded `types.wit` hash was
stale after whitespace normalization. The manifest now records the checked-in
source hash and the socket unit suite passes `36/36`; no runtime implementation
was added to bypass the validation.

**Boundary:** this closes the Task 8 Step 3 baseline only. It does not prove
generic `Future<T>`/`Stream<T>` lowering, arbitrary async function lowering,
public ownership syntax, or a scheduler. Those shapes must continue to fail
with `AsyncLoweringUnavailable` until the generic resumable slice is admitted
and independently gated.

## Wasmtime Store Async Serialization

**Status:** this is a constraint of the current Wasmtime C embedder experiment,
not a do compiler constraint or a universal WASI P3 property.

**Evidence:** `wasmtime/async.h` states that all parameters and the Store must
remain alive while a `wasmtime_call_future_t` exists, and that another function
must not be called on that Store while it is alive. The header also states that
only one future can be alive for a Store at a time. A do instance hosted in one
Store therefore cannot drive 1024 independent C API call futures concurrently.

**Required contract:** a runtime adapter using this C API uses one active
component future per Store. The compiler does not encode this rule into the
Component ABI; another conforming runtime may use a different host scheduling
strategy while preserving the Component's observable behavior.

**2026-08-02 checkpoint:** `examples/p3-runtime/test_c_api_host_drive_queue.sh`
now compiles the C runner and submits two logical tasks to one local host drive
queue. The drive loop polls the first future to completion, deletes it, and only
then starts the second. The probe passes with
`tasks=2 completed=2 calls=2 queued=1 active-futures-max=1
nested-call-attempts=0`, proving the adapter-side serialization rule and the
absence of nested C API calls. `examples/p3-runtime/test.sh` runs this probe as
part of the p3-runtime gate.

**Remaining boundary:** this is an adapter-specific queue proof, not a generic
Component scheduler, operation-ID protocol, or concurrent Store capability. It
does not remove the pinned P3 WIT/linker blocker or establish complete WASI
execution.

## Component Assembly Tooling

**Status:** v1 path verified with one active toolchain. The repository's
standard external tooling path produces the `wasmtime-p3` target; it is not a
complete-WASI claim.

**Evidence:** `src/run/run.zig` already resolves `wasm-tools` and reports a
missing-tool diagnostic. The regression runner validates generated WAT and
Component WIT using that tool. The active local binary is
`wasm-tools 1.255.0 (76e20611d, 2026-07-30)`, SHA-256
`6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`.
It provides `component embed` and `component new`; its current async callback
metadata uses the `--dummy-names legacy` naming mode.

**Decision:** pin this binary as the only v1 Component assembly tool. No Rust
toolchain is required at build time, and no 1.254.0 compatibility path is
supported. The `legacy` value below is only the async callback naming mode
provided by the current binary.

**Verified path:**
`examples/p3-runtime/assemble_async_component.sh` is the canonical assembly
entrypoint. It rejects a missing, version-mismatched, or hash-mismatched
`wasm-tools`, runs current `component embed`/`component new`, and validates with
`cm-async,cm-more-async-builtins`. `examples/p3-runtime/test_wasmtime_p3_assembly.sh`
builds the real `wait-for-component.do` Core WAT, asserts the current tool
version/hash and current async naming mode, assembles and validates the
Component, and executes it twice through the Rust/Wasmtime clock host. The
current-only guard rejects any active 1.254.0 selector, legacy binary variable,
or removed assembler path.

## Runtime Drive Boundary

**Status:** runtime-specific scheduling remains out of the compiler ABI. The
fixed Rust adapter uses Wasmtime's `run_concurrent` API; this is sufficient for
the wait-for and cancellation probes but does not establish a generic scheduler
or complete WASI execution model.

**Boundary:** Do emits the pinned Component operations only. A runtime chooses
how to poll and cancel its host futures while obeying its own Store re-entry
rules. Do does not define `HostDrive`, operation queues, IDs, acknowledgements,
or a cross-runtime event protocol for this purpose.

## Resource Admission And OOM

**Status:** blocked. Count-only quotas do not make the promised
`TaskExit.Failed(QuotaExceeded)` behavior true for variable-sized GC values.

**Evidence:** the current v1 memory specification represents `text`, `[T]`, and
managed structs as dynamically allocated ARC payloads (`doc/memory.md`); the
planned GC replacement retains variable-sized text/list/frame/ABI buffers.
Limits such as 65536 tasks or waiters do not bound their byte size. A Wasm GC
allocation failure can trap the instance before the guest has storage to record
a task-local error or unwind cleanup.

**Required contract:** every countable allocation has a byte-cost formula and
is admitted before it mutates a channel, Scope, or wait list. Admission denial
uses the normal task cleanup path. Backend allocations whose cost cannot be
preflighted are explicitly instance failure/host error, not a falsely
recoverable per-task quota result.

**Unblock condition:** define the v1 byte budget owner, accounting points, and
transactional admission tests for channel slots, TaskFrames, text/list backing,
and canonical ABI buffers. The default GC backend cannot claim deterministic
quota behavior before this exists.

**2026-08-02 contract checkpoint:** `src/build/async_byte_budget.zig` now
defines the instance-owned `ByteBudget` model with committed and in-flight
reservation bytes. `reserve` must succeed before a state mutation; `commit`
creates an allocation token, `rollback` releases an in-flight reservation, and
`release` returns committed bytes exactly once. Checked formulas cover TaskFrame
payloads, queue slots, text backing, list backing, and canonical ABI buffers;
overflow is an explicit `ByteSizeOverflow`, never a wrapped quota value.
`src/build/async_byte_budget_test.zig` covers the five formulas, overflow,
commit/rollback, capacity restoration, and duplicate finalization. The selected
generated frame, canonical-buffer, and `cabi_realloc` helpers now consume the
same checked counter, while generic channel/endpoint storage, text/list
backing, scheduler policy, and the current ARC transition allocator or GC
backend integration still do not. The resource-admission blocker and full GC
migration NO-GO status therefore remain unchanged.

**2026-08-02 variable-backing checkpoint:** `TextBackingPool` and
`ListBackingPool` in `src/build/async_byte_budget.zig` now consume the checked
text/list formulas through one transactional variable-allocation model. Focused
tests cover capacity-based charges, overflow, budget rejection without state
mutation, foreign allocation tokens, and exactly-once release. This advances
the compiler-side accounting model only; generated text/list allocation call
sites, generic endpoint storage, scheduler policy, and GC backend admission
remain outside the runtime contract; the current ARC transition allocator is
implementation debt rather than an alternative runtime contract.

The first model consumer is now `StreamWriterQueue.init_with_budget` in
`src/build/codegen_component_stream_writer.zig`. Accepted and pending queue
entries carry one committed allocation token; `pop` releases accepted slots,
and `close`/`abort` release pending slots. A budget failure occurs before the
queue mutates and is covered by the queue's focused tests. This is still a
compiler-side queue model, not a runtime scheduler or GC allocator call site.

The TaskFrame boundary now has the same compiler-side model in
`src/build/codegen_gc_async_frame.zig`. `bytes_for_frame_layout` accounts the
fixed 16-byte frame header plus the layout payload, `TaskFramePool` admits and
releases one allocation token per live frame, and emitted frame metadata records
`[async-frame-bytes]`. This connects the generated frame layout to the checked
budget contract. Generated Component frame allocators now carry the layout byte
count into an instance-local checked i64 counter before `table.grow`, and release
it from `$frame-free`; counter overflow or an impossible release traps before a
bad handle can escape. The generated allocator now also owns an explicit
instance-local limit: it starts at `-1` (unlimited) and exposes the Core-only
`[async-config]byte-budget-limit(i64) -> i32` hook. The hook accepts `-1` or a
non-negative limit, rejects a limit below current committed/reserved usage, and
leaves state unchanged on rejection. This is a runtime configuration boundary,
not a Do source API; a Component host still needs an adapter that invokes it
before admission. Scheduler admission policy and a configured default remain
open.

**Component visibility check (2026-08-02):** assembling the generated scalar
Result probe and running `wasm-tools component wit` exposes only the registered
`run` import/export; `[async-config]byte-budget-limit` remains an internal Core
module export and is not present in the Component world. An external scheduler
therefore cannot configure this limit through the current Component interface.
The generated budget owners now also carry the WIT-safe Core alias
`byte-budget-limit`, but the normal Do-generated sidecar still omits it. The
private adapter runner `examples/p3-runtime/test_rust_scalar_result_budget_adapter.sh`
augments that sidecar only at host assembly, calls the alias before the async
entry, and verifies both admission (`limit=20`, one 20-byte frame) and
pre-admission rejection (`limit=19`). This proves a host adapter boundary, not
generic Component scheduler admission; no public WIT API is inferred from the
Core hook.

**2026-08-02 host admission checkpoint:** the scalar Result Rust/Wasmtime
runner now places a `BudgetGate` before `run_concurrent`. It holds one 20-byte
permit for the first call, rejects a second call before entering the Store,
releases the permit after completion, and then admits the second call. The
gate has checked-add overflow and no-mutation-on-rejection unit coverage. This
is the first executable host admission call site, but it is still bound to the
private scalar Result frame charge; it does not define a generic scheduler,
queue policy, or canonical ownership protocol.

**2026-08-02 stream-writer admission checkpoint:** the pinned
`wasi:cli/stdout.write-via-stream` host runner now exercises the same
host-only `BudgetGate` with the generated 64-byte stream-writer frame charge.
With a 63-byte limit, admission is rejected before the Component call and the
host callback count remains zero. With a 64-byte limit, a second admission is
rejected while the first permit is held; after the first `run_concurrent`
completes, the permit is released, the second call is admitted, and both stream
readers are dropped exactly once. The executable gate is
`examples/p3-runtime/test_rust_cli_stream_stdout_scheduler.sh`. The bounded
guest-producer runner applies the same 64-byte gate and covers two sequential
producer calls plus the 63-byte pre-call rejection; its existing FIFO and
exactly-once cleanup assertions remain green. These remain descriptor-specific
host probes. A separate private sidecar run configures the generated
`byte-budget-limit` alias at 64 and verifies a 63-byte Component-side rejection
before the callback for both forwarding and guest-producer fixtures. None of
these probes defines a generic scheduler or makes arbitrary stream endpoint
storage quota-aware.

The canonical result-buffer boundary now has a matching fixed-slot model in
`src/build/async_byte_budget.zig`. `CanonicalBufferPool` computes one slot from
the checked canonical-buffer formula, reserves before admitting it, and releases
the committed token exactly once. The HTTP service emitter consumes that formula
for its 64-byte per-handle result slot and emits `[canonical-buffer-bytes] 64`
metadata. Its generated result-buffer helper now reserves those 64 bytes before
`memory.grow`, rolls back when grow fails, and releases the committed bytes after
`task-return` on the shared terminal path. This is checked accounting only: the
counter has no configured quota, and non-HTTP canonical allocations remain
outside this boundary.

The private two-word resource Result emitter now applies the same checked
accounting to its fixed 8-byte result slot. It emits `[canonical-buffer-bytes] 8`,
reserves before its result-buffer `memory.grow`, rolls back on grow failure, and
releases after immediate, resumed-success, and ready-error `task-return` paths.
This remains a probe-specific boundary; it does not make arbitrary resource
Result payloads or other canonical allocations quota-aware.

The Core GC probe `examples/gc-p3-runtime/async-frame-table.wat` now executes
the same admission ordering for its frame table and a canonical buffer: a fixed
16-byte budget admits two 8-byte frames or one frame plus one 8-byte buffer,
rejects the next allocation before `table.grow`/`memory.grow`, and releases bytes
on cleanup. `test_async_frame_table.sh` verifies both rejection paths and zero
post-cleanup usage. This is a standalone runtime probe; the generated HTTP
result-buffer helper now uses the same checked counter and limit hook, while the
Component scheduler and non-HTTP canonical allocators remain outside this gate.

## Async Host Descriptor Resolution

**Status:** partial. The compiler validates pinned descriptors in
`src/build/p3_async_registry.json`, including
`wasi:clocks@0.3.0/monotonic-clock.wait-for` and `wait-until`, both `async`,
`(u64) -> nil`, and without resources. `do check` accepts their `@host_func`
declarations and rejects an unknown member or signature drift. Their descriptor records retain
the same scalar/unit canonical shape
(`core_params: [i64]`, no core results, `completion: task-return`); the
operation token is explicitly absent. The same canonical record explicitly
stores the verified Core import module
`wasi:clocks/monotonic-clock@0.3.0` and import name
`[async-lower]wait-for` and `[async-lower]wait-until`; the compiler does not
derive either ABI string from the locator or member spelling. Their sibling
`wit` records explicitly store the
package, interface, operation, and world used for the WIT sidecar; those names
and the WIT parameter label are likewise not derived from locator/member or
source-local text.

Default compilation uses this as descriptor identity validation only. The
explicit `--p3-async-component` target classifies and consumes the verified
scalar/unit, unit Result-tag, or private two-word resource Result descriptor
to generate its Core import and WIT sidecar. It rejects every other descriptor;
it does not identify a complete reproducible P3 async ABI for arbitrary
descriptors.

**Evidence:** the current host-binding design uses only locator/member/do
signature and still documents two incompatible async source forms (`async (...)`
and `Future<T>`). The active Core-Wasm collector is explicitly an env import
collector (`src/build/codegen_host_imports.zig`), not a P3 world resolver. A do
signature cannot establish which WIT revision supplies the import, whether it
is async, its canonical lifting/lowering shape, which resource is owned, or
which Component task/subtask operations apply to its async lowering.

**Required contract:** a pinned P3 world/interface/member manifest is a compiler
input for every async descriptor. It records WIT revision/hash, canonical ABI
shape including Core import module/name and WIT package/interface/operation/
world/parameter names, async effect, resource ownership/drop function, and the
applicable pinned task/subtask ABI operations. Sema resolves `@host_func` against that
manifest; it does not infer ABI semantics from a member spelling or permit an
unregistered async descriptor.

**Remaining unblock condition:** the registry now classifies the two verified
canonical shapes: scalar/unit (`core_params: [scalar]`, no result words) and
the private two-word resource `Result`. The component probes consume their
registered Core import strings rather than deriving them from source-local
names. Additional descriptors still require generated canonical result layout,
resource transfer/drop behavior, cancellation cleanup, WIT sidecar generation,
and host execution coverage before they can lower. This is required before
accepting `@host_call` as a portable P3 source operation.

### P3 Result Descriptor Candidate

**Status:** host ABI and explicit compiler probe passed. The pinned Wasmtime
`90fed3c6adf53f112c4dea56851728557bb73799` P3 WIT tree contains
`wasi:cli@0.3.0/run.run`, declared as `async func() -> result`. It is the next
non-resource shape after the two verified clocks operations.

**Evidence:** `examples/p3-runtime/test_cli_result_probe.sh` assembles a Core
WAT probe against its matching WIT, then runs it through the pinned Rust
Wasmtime adapter. The host `run` Future is Pending once and completed by an
`Accessor::spawn` Store wake. Both `Ok(())` and `Err(())` are written through
the canonical result pointer, read by the resumed guest, and passed to the
typed `task.return`. This freezes the no-payload `result` representation as
one `i32` tag for this probe.

**Compiler evidence:** `examples/p3-runtime/test_do_cli_result_lowering.sh`
compiles `cli-run-result-component.do` through the unified
`--p3-async-component` target, assembles its generated Core WAT and WIT
sidecar, and runs its exact source Result branch through the Rust adapter. The
compiler accepts only the fixed no-parameter `Future<Result<nil, nil>>` source
form: either direct `return await(pending)`, or binding that await followed by
`if @is(replied, Ok) { return Err() }` and a final `return Ok()`. The latter
emits `i32.eqz` over the verified canonical tag before typed `task.return`.
The adapter invokes that export twice concurrently in one Store, returns
`Ok(())` from both host futures, and requires both guest results to be
`Err(())`; this makes source-level Result consumption observable.

**Remaining unblock condition:** generalize from this fixed descriptor without
losing descriptor-bound ABI ownership. The current path does not implement
arbitrary `Future<Result<T, E>>`, resources, lists, or generic task-return
lowering. Ordinary `do build` must keep `AsyncLoweringUnavailable` for all
other async programs.

**2026-08-02 scalar Result frame-accounting checkpoint:** the registered
private `Future<Result<i32, i32>>` lowering now derives its fixed 20-byte
linear frame charge from `bytes_for_task_frame(16, 4)`. Generated WAT emits
`[async-frame-budget-bytes] 20`, reserves the charge before frame allocation,
releases it from `frame-free`, and rolls it back before trapping on frame
pointer overflow or a memory boundary failure. The generated Core-only
`[async-config]byte-budget-limit(i64) -> i32` hook is shared by this probe;
the scalar Result pending, immediate, and cancellation adapters plus the
compiler lowering test pass. This remains a descriptor-specific accounting
boundary: it does not admit arbitrary Result payloads, resource ownership,
general canonical allocations, or external Component scheduler admission.

**2026-07-31 bounded payload checkpoint:** the registry now admits one private
scalar `Future<Result<i32, i32>>` descriptor. Its tag and shared payload use
descriptor-defined result-area words; normal completion and direct
`@cancel` cleanup are assembled and validated through the pinned Component
ABI. This does not admit lists, text, nested variants, payload-bearing
`error-code`, or arbitrary resources.

The registered scalar-u8 `wasi:cli/stdin.read-via-stream` probe now derives a
bounded one-to-three read plan, EOF/cancel/drop lifecycle, and canonical WIT
export names. A bounded internal writer FIFO/lease model is tested. The pinned
WIT/toolchain also generates the stdout `write-via-stream` async ABI, including
stream creation, read/write, cancel, and readable/writable drop imports. The
ABI is now copied into `p3_async_registry.json`. The descriptor forwarding
wrapper and fixed guest-producer Rust/Wasmtime fixtures now pass pending and
immediate host callback execution, normal three-item FIFO delivery, consumer
early-drop, and host `Err(pipe)`; each guest-producer scenario observes one
pending write and exactly-once writer close/reader drop. The writer WIT renderer consumes the
descriptor selected by the registry, with a private writer descriptor unit
probe and Component assembly script guarding against a stdout-package
fallback. General queue-to-stream codegen and external writable-endpoint
execution remain deferred. B1 is limited to the registered stdout `stream<u8>`
descriptor and a compile-time bounded source sequence; general dynamic iteration,
arbitrary payloads, and abort-to-WIT-error mapping remain deferred.

The Zig `StreamWriterQueuePump` model now covers bounded scalar source sequences,
pending-value advancement, capacity-zero rendezvous, FIFO preservation, and
delayed close. The fixed guest-producer WAT now routes its resumable entry and
callback through one `writer-pump-step` helper. This is still bounded scaffolding,
not evidence of a generic source-level Component pump or an externally writable
WIT endpoint.

`src/build/codegen_async_model.zig` now records the Core storage class for each
binding visible at an await (`i32`, `i64`, `f32`, `f64`, or `unsupported`). It
is frame-planning metadata only: it neither allocates a frame nor serializes a
binding, and `unsupported` values remain an explicit lowering boundary for
resources, managed values, containers, and generic futures.

**2026-08-01 single-await resumable checkpoint:** the pinned scalar/unit clock
path now consumes one narrow body shape with a local `u64` value live across
`await` and a scalar computation after resume. The plan records the post-await
operation, the Core emitter stores the live local in the GC frame, dispatches
the callback resume state, and runs the shared terminal cleanup on both pending
and immediately-ready completion. The fixture
`examples/p3-runtime/test_do_single_await_post_compute_lowering.sh` assembles
and validates the generated Component, then the Rust/Wasmtime adapter observes
one pending poll/wake/completion and the immediate path with zero polls/wakes.
The same fixture verifies that ordinary `do build` still returns
`AsyncLoweringUnavailable`.

This is still a pinned `wasi:clocks@0.3.0/monotonic-clock.wait-for` contract,
not general async body lowering. Result payloads, Stream operations, resources,
multiple arbitrary control-flow shapes, and unregistered descriptors remain
outside the admitted lowering boundary.

## G6.2 StreamMirror Runtime Closeout (2026-08-03)

The private `do:stream-probe` descriptor now has a complete bounded
`StreamMirror` runtime gate. The guest reads at most three `u8` values from the
registered source stream, forwards them through a capacity-one
`StreamWriter<u8>`, transfers the readable endpoint to the registered sink, and
cancels the independent source completion future. Core WAT/WIT lowering and
Component validation pass, and `test_rust_stream_mirror.sh` passes
`pending`, `ready`, `source-eof`, `error`, `cancel`, and `early-drop`.

The normal terminal failure was `resource has children`: the generated
`mirror-complete` path dropped the waitable set while the completed sink
subtask was still its child. The emitter now drops that subtask exactly once,
handles the immediate-completion marker, clears the frame slot, and only then
drops the waitable set. The runtime assertions observe one source stream drop,
one source future drop, one sink callback/drop, and `table-empty=true` in every
mode. This remains a private descriptor-specific gate; general producer leases,
arbitrary async calls, borrowed/list/variant resource fields, and public
`own<T>`/`borrow<T>`/`ref<T>` syntax remain blocked.

## Full WASI Compatibility Scope

**Status:** not started. The current implementation and P3 plan only cover a
small, explicit subset; that does not satisfy the long-term goal of do being a
first-class WASI language.

**Evidence:** current lowering is limited to selected Core-Wasm imports and the
first async plan intentionally starts from one waitable/future/byte-stream
subset. WIT package availability, type layouts, resource ownership and async
semantics vary by registry revision, so a growing hand-written host function
list cannot prove full coverage.

**Required contract:** define “complete WASI support” as all public
world/interface/member entries in a version/hash-pinned WIT registry, with a
generated world manifest and execution matrix. The compiler must use one common
type/resource/async lowering path rather than interface-specific compiler
special cases. Each registry upgrade is a separately versioned compatibility
release.

**Unblock condition:** after the P3 subset is executable, implement the
generated manifest, universal canonical ABI lowering and per-interface
Wasmtime execution/ownership/cancellation fixtures. Only a fully passing matrix
permits the corresponding complete-WASI release claim.
# Host ABI Blockers

## Verified Private Resource Probe

The private `do:resource-probe@0.1.0` `ledger.ticket` fixture is verified with
descriptor-bound `own`/`borrow` sema, Core WAT component assembly, and a
Wasmtime 47 `ResourceTable` host runner.

The separate `http.send` private fixture now additionally verifies the hard
async resource crossing: `async func(request: request) -> result<response,
error-code>`. `examples/p3-runtime/test_rust_async_resource_result.sh` builds
the component from the do fixture, runs pending and immediate success plus
ready-error exports in one Store, and proves that each request is consumed once
when `send` starts; success creates and drops one owned response per call, while
`Err(failed)` creates and drops no response. The `ResourceTable` is empty at the
end. Its explicit Core ABI is `(request-handle, result-pointer) ->
subtask-handle`, with a result tag and resource/error payload stored in an
8-byte canonical buffer. The private frame itself is an `$async-frame` GC
struct rooted in the `$async-frames` table; it stores only the `i32` canonical
result pointer and the runtime-private state. A host retains the table handle
across suspension, and terminal cleanup clears that GC root before recycling
the handle.

The same registered descriptor now has a bounded explicit cancellation source
shape: `Future<Result<HttpResponse, HttpError>>` must be consumed by
`@cancel(completion)` from a nil-returning async root. The compiler emits the
pinned `subtask.cancel` status check followed by exactly one `subtask.drop` and
`[task-return]cancel`; the generated Component and the hand-written ABI probe
both pass the Wasmtime pending-future-drop and empty-`ResourceTable` checks.
Negative fixtures cover implicit scope-drop, double cancellation, and
cancellation after terminal consumption. This is still a private descriptor
slice, not general resource cancellation or public ownership syntax.

The separate private owned-error descriptor also verifies
`result<response, error-resource>`: a ready `Err` transfers and releases exactly
one error-resource handle, while creating and releasing no response resource.
The generated and hand-written Components agree on pending `Ok`, immediate
`Ok`, ready `Err`, and explicit cancellation. This remains a registry-bound
result layout and does not generalize error payloads or resource ownership
syntax.

This is a private, pinned ABI probe, not generic WASI HTTP support. It does not
yet lower `wasi:http/client@0.3.0-rc-2025-09-16/send` in ordinary `do build`,
and it does not unblock generic WASI resources, arbitrary Future/Stream async
composition, generic resource cancellation, or Component-GC/ARC migration.
The selected clocks `@cancel` Component probe remains separate evidence;
neither probe generalizes this resource result ABI.

The pinned real HTTP WIT has separately verified the import signature
`[async-lower]send: (i32 request-handle, i32 result-pointer) -> i32
subtask-handle`; this exact shape is recorded in `p3_async_registry.json`.
It is not ABI-equivalent to the private probe: when the complete
`wasi:http/types.error-code` variant is present, the generated
`[task-return]run` takes eight `i32` parameters and the component imports the
full HTTP types surface. Real HTTP lowering therefore requires descriptor-led
result-layout generation and a complete types adapter, rather than changing
the private two-word completion-frame emitter.

## HTTP Payload Cancellation Slice (2026-08-04)

The real pinned HTTP package now has one additional private cancellation slice.
`examples/p3-runtime/http-payload-cancel.do` starts the versioned
`wasi:http/client.send` operation with an owned `HttpRequest`, stores the
`Future<Result<HttpResponse, HttpError>>`, and explicitly consumes it with
`@cancel(completion)`. The checked-in service-world fragment is copied into a
temporary package directory; the pinned package files are not modified.

The generated Core WAT imports the exact `[async-lower]send`, request-drop, and
response-drop symbols. Its nil-returning root passes the fixed `[64,128)`
canonical Result scratch to `send`; `Status::Returned` decodes the Result tag,
drops the owned response at offset `8` for `Ok`, and accepts the no-payload
`DnsTimeout` error tag. Both compiler-generated and hand-written Components
assemble and validate. The Rust/Wasmtime runner observes:

```text
request consumed=1
pending future drops=1
response create=0
response drop=0
table-empty=true

mode=ready-ok
request consumed=1
pending future drops=0
ready future polls=1
ready future drops=1
response create=1
response drop=1
table-empty=true

mode=ready-dns-timeout
request consumed=1
pending future drops=0
ready future polls=1
ready future drops=1
response create=0
response drop=0
table-empty=true
```

This closes pending, immediate `Ok(response)`, immediate `Err(DnsTimeout)`, the
bounded immediate `Err(DNS-error)` path with `rcode=None` or a nonempty `rcode`
string, and the same-layout `InternalError(None)` / `InternalError(Some(nonempty
string))` paths. Empty strings and every other payload/error shape remain
runtime traps. It does not add implicit
scope cancellation, cancellation after terminal completion, double
cancellation, rollback/compensation, arbitrary HTTP payload/error shapes,
general HTTP resource methods, or public `own<T>`/`borrow<T>`/`ref<T>` syntax.

**2026-08-04 HTTP service emitter hardening checkpoint:** the generic handler
and request-construction/send lowering paths both expand the shared
`[body-future-event-handler]` template slot to the normal no-body waitable
completion result. Before this checkpoint, the marker leaked into generated
WAT and failed `wasm-tools parse` for the service and empty-request fixtures.
The pinned `test_http_service_abi_surface.sh` assembly gate, the empty-request
Rust/Wasmtime runner, and all 189 `codegen_component_wasi_http` tests now pass.
This fixes template completeness only; it does not admit arbitrary HTTP body
methods, unregistered/general payload-bearing completion errors, general async
calls, or public `own<T>`/`borrow<T>`/`ref<T>` syntax.

`examples/p3-runtime/test_http_service_abi_surface.sh` characterizes that
adapter surface directly from the pinned WIT with `wasm-tools` async-callback
dummy generation. It verifies the `client.send` async-lower import, request and
response resource drops, the eight-word handler task-return signature, and
successful Component assembly/validation with the HTTP types and client
imports. Its minimal Core fixture also proves that the Component retains the
high-level HTTP types interface without importing every unused fields/request
method into Core; a future lowering may therefore emit a descriptor-reachable
subset, beginning with `send` and resource drops. This is an ABI baseline only;
it does not by itself make arbitrary `client.send` shapes lowerable. The
registered descriptor-backed payload slice is covered separately by the payload
error checkpoint above; general type adapters, error layouts, and resource/stream
cleanup paths remain bounded and explicit.

## HTTP Request Body Stream Slice (2026-08-02)

The executable body slice admits only the pinned
`wasi:cli/stdin@0.3.0-rc-2025-09-16/read-via-stream` descriptor as a finite
`Stream<u8>` source. The HTTP plan rejects other registered stream-reader
descriptors at its admission boundary, including a descriptor with a spoofed
canonical import under the same locator/member. The Rust/Wasmtime runner
executes ready and one-poll-pending source-completion configurations for the
cancellation path, two calls with `[65,66]`, success and no-payload
`DnsTimeout`, exactly-once source cleanup, and an empty `ResourceTable`.

The baseline `http-request-body.do` remains a fixed cancellation path: its
source completion is dropped after the send terminal callback. The companion
`http-request-body-await-completion.do` fixture now performs one serialized
source-completion await before `request.new`; it uses the registered
`[async-lower][future-read-1]read-via-stream` operation and executes both
pending-once and immediately-ready host futures through the Component callback.
The await path accepts only a successful no-payload completion and does not
introduce a send/source-completion concurrent state machine. Dynamic body
producers, source loops, trailer payload lifting, payload-bearing error-code
variants, and public `own<T>`/`borrow<T>`/`ref<T>` syntax remain unsupported.

The await lowering gate is
`examples/p3-runtime/test_do_http_request_body_await_completion_lowering.sh`;
the execution gate is
`examples/p3-runtime/test_rust_http_request_body_await_completion.sh`.

## G6.2 Bounded List-Owned Resource Stream Lowering (2026-08-04)

The registered private descriptor
`do:record-resource-list-stream-probe@0.1.0/source.read-via-stream` now lowers
one exact `stream<list<resource-entry>>` source shape. Every element contains
one WIT-internal `own<ticket>`; Do source still has no public
`Option<T>`/`own<T>`/`borrow<T>`/`ref<T>` syntax. The compiler admits one
`@next(reader)`, one await of that read, ignores the received list, awaits the
completion, and returns its `Err(io)` or `Ok()`. The seven internal bindings may
be renamed, but their types, data flow, order, and single-read count remain
pinned.

The compiler emits the private WIT world and a Core component using the verified
result area `ptr@64,len@68`. Each element is a four-byte handle with `ticket@0`
and alignment four. Only `len=0/1/3` is accepted: nonempty storage is exactly
`cabi_realloc(0,0,4,4|12)`, then released once by
`cabi_realloc(ptr,len*4,4,0)`. Validated tickets move to the three private frame
slots, are cleared before their `[resource-drop]ticket`, and all terminal paths
drop stream, future, tickets, storage, waitable, and frame exactly once.

`examples/p3-runtime/test_do_record_resource_list_stream_lowering.sh` builds the
Do fixture, emits its WIT sidecar, parses, embeds, creates, and validates the
generated Component, then executes it through the Rust/Wasmtime runner. The
matrix covers ready `0/1/3`, pending-once completion, `Err(io)`, and early
cleanup. It also derives malformed-length and duplicate-release WAT variants
from stable markers: `len=4` traps before ticket ownership
(`resource-drops=0`, table nonempty), while the second release traps after the
first has dropped exactly three tickets and cleared the table. The gate also
requires the compiler-owned template to be byte-identical to the hand-written
canonical ABI oracle. `examples/p3-runtime/test_record_resource_list_stream_abi.sh`
keeps that oracle independently executable.

The same generated Component and Store also execute 6000 sequential
`ready-three` calls. The terminal frame and the validated last list backing
allocation both rewind their private bump pointers only after exactly-once
cleanup; the stress observation is 18,000 ticket creates/drops, 6,000 stream
and future drops, 6,000 reads, and an empty table. This proves sequential reuse
for the admitted single-active-frame shape, not concurrent invocation support.

`examples/p3-runtime/record-resource-list-stream-unregistered-component.do`
remains a negative fixture and
`examples/p3-runtime/test_do_record_resource_list_stream_boundary.sh` requires
`UnknownP3AsyncHostDescriptor`. Generic list-resource lowering, a second stream
read, length `2` or `4+`, nested or variant elements, borrowed fields, public
ownership/Option syntax, and every unregistered descriptor remain blocked.
Pinned Wasmtime `47.0.2` `bindgen!` cannot generate this `do:...` package because
it emits the Rust keyword `do`; the runner therefore uses the established low-
level Linker API rather than renaming the private WIT package.

## G6.2 C-min List/Resource Producer Canonical ABI Probe (2026-08-07)

The independent private producer probe
`do:g6-2-c-min-producer@0.1.0` now passes
`bash examples/p3-runtime/test_g6_2_c_min_list_resource_producer_abi.sh` with
`wasm-tools 1.255.0 (76e20611d 2026-07-30)`, Wasmtime `47.0.2`, and Rust
`1.97.1`. The WIT package also parses through
`wasm-tools component wit`; its source hash is
`8decd27aeca4a1f1863544860caec230a1fc50259336a893de79413c6f9ec3f7`.

The hand-authored Core WAT establishes producer-side list facts independently
of the consumer probe: pointer `64`, length `68`, element stride `4`, ticket
offset `0`, and stream capacity `1`. The runtime matrix covers empty/one/three
entries, pending, sink error, early drop, invalid mode, cancellation before and
after transfer, malformed length, and duplicate release. Valid modes produce
`[]`, `[1]`, and `[1,2,3]`; invalid mode allocates no ticket; every admitted
terminal path leaves an empty `ResourceTable`; malformed length and duplicate
release trap with the expected unknown-handle diagnostics.

The cancellation rows are deliberately ownership-boundary probes: pre-transfer
cleanup is guest-side subtask cancellation and post-transfer cleanup is host
child-drop. Wasmtime dropping a `call_concurrent` future is not claimed to
cancel an in-store guest task. The pure `ListLayoutPlan` slice is green (`6/6`
focused, `19/19` full layout, `5/5` ABI types), its `ListProducerOwnershipPlan`
is green (`6/6` focused, `17/17` full ownership), and the
`ListProducerFramePlan` is green (`4/4` focused, `13/13` full async). The
descriptor/manifest/sema admission is green (`79/79` and `122/122`) and only
`StreamWriter<[ResourceEntry]> -> Result<nil, ErrorCode>` is accepted. The
compiler promotion is now also closed for this exact private shape:
`codegen_component_list_resource_producer.zig` passes `139/139`, unified
`codegen_component_async.zig` passes `438/438`,
`test_do_g6_2_c_min_list_resource_producer.sh` passes Do WAT/WIT assembly, and
`test_rust_g6_2_c_min_list_resource_producer.sh` passes the generated
Component/Rust/Wasmtime ready/pending/error/early-drop/invalid-mode and
transfer-boundary cancellation matrix with an empty `ResourceTable`.
Generic producer/list lowering, arbitrary producer expressions, borrowed
payloads, public ownership syntax, and root hard-cancel remain blocked.
## G6.2 Variant Resource Stream Closeout (2026-08-05)

The private `do:variant-resource-stream-canonical@0.1.0` descriptor is now
registered and lowered only for the exact `Stream<Ticket | nil | EventError>`
source shape. The compiler-generated Component and Rust/Wasmtime gate cover
`ticket(own<ticket>)`, `idle`, `failed(io)`, pending, completion error, and
exactly-once stream/future/ticket cleanup. The measured event layout remains
`tag@0`, `payload@4`, `size=8`, `alignment=4`; canonical early-drop,
malformed-tag, and duplicate-release probes remain negative gates.

This does not admit generic variants, borrowed fields, arbitrary producer
expressions, or public `own<T>`/`borrow<T>`/`ref<T>` syntax.

## Generic Async Runtime Slice (2026-08-05)

**Status:** the registered unit-payload runtime slice is verified; generic
async lowering remains guarded outside this exact Component target.

**Evidence:** `examples/p3-runtime/test_do_generic_async_runtime.sh` builds
`examples/p3-runtime/generic-async-runtime.do`, embeds its WIT world, validates
the Component with current `wasm-tools 1.255.0`, and runs the Rust/Wasmtime `47.0.2`
host in pending, immediate-ready, and cancel modes. The observations are two
external wakes/two completions/one drop for pending, three completions and no
external wake for immediate-ready, and cancel-before-completion with two
completed host calls for cancellation. The component async unit suite and the
latest full compiler matrix are green (`pass=1108 fail=0 skip=3`).

**Source boundary:** the public model is colorless: ordinary function
declarations plus `@async`, `@await`, and `@cancel`. A WIT `async func` binding
already yields `Future<T>` and is not wrapped in `@async`; `async name(...) -> T`
is deprecated and normal semantic analysis reports `DeprecatedAsyncFunctionDecl`
before lowering. The generic target retains a dedicated negative async-root
fixture and rejects it with
`AsyncLoweringUnavailable`/`UnsupportedGenericAsyncShape` rather than adding
new capability to the legacy spelling.

**Remaining blocker:** arbitrary Future/Stream payloads, resources, aggregate
await, timeout, multi-root scheduling, public `own<T>`/`borrow<T>`/`ref<T>`, and
ordinary `do build` async programs still require independent admission plans
and runtime gates. The remaining negative legacy-declaration fixtures are
intentional regression coverage, not an additional migration blocker for this
bounded runtime slice.

## D2 Bounded Filesystem Async `descriptor.set-size` (2026-08-11)

**Status:** the private `descriptor.set-size` WIT/ABI probe, exact opt-in Do
compiler slice, generated Component validation, and Rust/Wasmtime mutation and
cancellation matrix are green. General filesystem async, arbitrary producer
expressions, borrowed payload/resource lowering, external HTTP, and public
ownership syntax remain blocked.

**Evidence:**
`bash examples/p3-runtime/test_d2_wasi_filesystem_set_size_abi.sh` passes with
`wasm-tools 1.255.0 (76e20611d 2026-07-30)` and SHA-256
`6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`. The
upstream filesystem WIT hash is
`8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`; regular
and cancel mirror hashes are
`f09241f8fcf4b94e1a684553b439b592f254c83c7d23a3708930040a2324c3f4` /
`7030161e35a18fe40220cb2701864141a00a6c8d897cdfc8291839f2b742cc67`.

The measured method import is
`[async-lower][method]descriptor.set-size: (i32,i64,i32) -> i32` in the order
`descriptor, size, result-area`; the task-return is `(i32,i32)`, the result is
`unit | error-code`, and descriptor cleanup is
`[resource-drop]descriptor (i32) -> nil`. The compiler template hash is
`db09b4c2fe6f1f0a8c26f582759e9937249e352b6c852c40dc88ff753ce29385`; the
generated WIT hash is
`201038081bc51c5aeae77eca36fc4f873522e2357c2ec25c222e3ce31f486bef`.

The opt-in `--p3-async-component` compiler admits only fixture `552`, rejects
fixtures `553`-`563` before WAT, and the planner requires the declared host
binding name to be the call target even when another name has the same
signature. The default build remains fail-closed with
`AsyncLoweringUnavailable`. `bash examples/p3-runtime/test_rust_wasi_filesystem_set_size.sh`
passes hand-authored ready/pending/error/cancel/early-drop/repeat and generated
ready/pending/error/repeat rows. The ready row records one host call, one
mutation, one poll, one completion, one Future drop, and one descriptor drop;
pending records one wake and two polls; error records zero mutation; cancel
records one issued mutation, zero completion, one pending-future drop, and the
mutated size preserved; early-drop records Store disposal with descriptor drop
`0` and `table-empty=not-applicable`; repeat records two calls and sizes
`4096,4097` with exactly-once cleanup per invocation.

Cancellation is cleanup-only: it releases guest/Component state and never
rolls back a file-size mutation already issued to the host. This is a private
method-specific recovery row, not generic filesystem async or generic
host-future-drop cancellation.

### G5c A gate: WASI random `list<u8>` GC lift (2026-08-20)

The bounded A gate is verified by
`examples/gc-p3-runtime/test_gc_wasi_random_list_lift.sh`. It uses the checked-
in `wasi:random` source and the existing registry signature
`random/random/get-random-bytes: u64 -> list<u8>`, emits a fixed-length 16-byte
GC lift, assembles it with the versioned WIT package, and executes the host
callback through the pinned Rust/Wasmtime runner. The gate rejects GC
references at the canonical import and observes the returned length and bytes.

This does not promote the `host_wit_marshalling` row or close G5c. The
`cm32p2|wasi:*` strings used by the legacy host-core lowering are intentionally
not reused as the Component WIT import name; the latter is versioned. The
default compiler route remains ARC-backed. B, the descriptor-manifest route,
starts next and must close source/hash drift plus same-fixture ARC/GC
equivalence before any default cutover.

### G5c B gate: descriptor manifest provenance (2026-08-20)

The bounded B route is now implemented by
`src/build/codegen_component_descriptor_manifest.zig`. It reads the checked-in
`doc/wit/gc_descriptor_manifest.json`, accepts only repository-relative paths,
hashes the exact `source + newline + world_source + newline` bytes, resolves
the selected member through the WIT parser, and rejects package/version,
world/member, signature, canonical-import, hash, and unsupported-shape drift
before marshal planning. The current parser input uses a package-less world
fragment because duplicate package declarations are outside this gate.

Focused loader drift tests, the full `zig test main.zig` suite (`532/532`),
`./src/build/test/run_tests.sh`, and the residual baseline gate pass. The A
random Component gate now selects the descriptor by id and includes a negative
mutated-source check that fails with `SourceHashMismatch` before assembly.
This closes descriptor provenance for the bounded A slice only; the default
host/WIT route remains ARC-backed and `host_wit_marshalling`/G5c cutover stay
pending until broader inventory and ARC/GC equivalence are complete.

### G5c C1 gate: manifest-backed WASI random ARC/GC equivalence (2026-08-20)

`examples/gc-p3-runtime/test_gc_wasi_random_list_lift_equivalence.sh` now
assembles the manifest-generated GC lift together with a hand-authored
linear-memory ARC reference under the same versioned
`wasi:random/random@0.3.0-rc-2025-09-16` WIT package. The shared
Rust/Wasmtime runner observes one callback and the same 16-byte value from both
Components: `lengths=16/16`, `bytes=16/16`, `calls=1/1`.

This is one canonical-boundary equivalence row and is recorded in
`src/build/test/check_gc_migration_inventory.sh`. It does not prove
same-Do-source default-route equivalence, does not change the `cm32p2|wasi:*`
legacy route, and does not close the broader `host_wit_marshalling` or G5c
cutover rows.

### G5c C2 gate: private manifest-backed compiler route (2026-08-20)

`src/build/codegen_component_manifest_route.zig` now provides the private
compiler-side entry point for the bounded manifest slice. The caller supplies
only the descriptor id; `codegen_component_descriptor_manifest.zig` remains the
single authority for source/world loading, SHA-256 provenance, WIT signature,
canonical import, and measured-plan validation before the existing emitter is
called. The focused tests prove the pinned random lift is emitted and an
unknown descriptor returns `DescriptorNotFound` before WAT generation.

This closes only the private parser-backed route wiring for one measured
`wasi:random` lift. It does not wire ordinary `do build` host/WIT lowering to
GC, broaden the host/WIT shape inventory, or close G5c default cutover.

### G5c C3 gate: private manifest-backed text lower (2026-08-20)

The descriptor manifest now includes a second measured shape,
`demo:marshal-equivalence/api.send@1.0.0/lower`, backed by a package/interface
source fragment plus a package-less `probe` world fragment. The loader checks
the exact concatenated source hash and WIT signature before the private route
emits a GC `text` lower module with canonical `(i32, i32)` parameters.
`gc_marshal_text_probe.zig` adds only probe-local `cabi_realloc` counters; the
canonical import remains linear-memory words and never accepts a GC reference.

`test_gc_marshal_text_equivalence.sh` generates that module from the manifest,
assembles it beside the ARC reference under the same Component WIT world, and
the Rust/Wasmtime runner observes `hello` plus one allocation/free per path.
This closes the measured text-lower equivalence row only. The ordinary
`do build` host/WIT route remains ARC-backed; broader WIT shapes, default GC
routing, async/resource paths, and G5c cutover remain pending.

### G5c C4 gate: private manifest-backed `list<u32>` lower (2026-08-20)

The descriptor manifest now includes
`demo:marshal-u32-equivalence/api.send@1.0.0/lower`, backed by a package and
interface fragment plus a package-less `probe` world fragment. The loader
checks the exact concatenated source hash and `list<u32>` signature before
`gc_marshal_u32_probe.zig` emits the typed GC-array lower module. Its canonical
import is `(i32, i32)` and the import boundary contains no GC reference.

`test_gc_marshal_u32_equivalence.sh` generates the GC module through this
manifest route, assembles it with the hand-authored linear-memory ARC
reference, and runs both through the pinned Rust/Wasmtime runner. The gate
observes `[10, 20, 30]` and exactly one allocation/free on each path. This is
one private measured compiler/provenance/equivalence row; ordinary `do build`
host/WIT lowering remains ARC-backed, and arbitrary lists/aggregates,
async/resource paths, and G5c cutover remain pending.

### G5c C5 gate: private manifest-backed `list<u32>` lift (2026-08-20)

The descriptor manifest now includes
`demo:marshal-u32-lift-host/api.receive@1.0.0/lift`, backed by a package and
interface fragment plus a package-less `probe` world fragment. The loader
checks the exact concatenated source hash and `list<u32>` lift signature before
`gc_marshal_u32_lift_probe.zig` emits the typed GC-array result-area copy
module. Its canonical import is `(i32)` and the import boundary contains no
GC reference.

`test_gc_marshal_u32_lift_host.sh` verifies manifest-backed Component assembly
and Rust/Wasmtime host execution. The paired
`test_gc_marshal_u32_lift_equivalence.sh` runs the generated GC Component next
to the linear-memory ARC reference; both return checksum `60`. This is one
private measured compiler/provenance/equivalence row; ordinary `do build`
host/WIT lowering remains ARC-backed, and arbitrary lift/aggregate,
async/resource, and G5c cutover remain pending.

### G5c C6 gate: private manifest-backed scalar-record lower (2026-08-20)

The descriptor manifest now includes
`demo:marshal-record-lower/api.write@1.0.0/lower`, backed by a package and
interface fragment plus a package-less `probe` world fragment. The loader
checks the exact concatenated source hash and `writing` record signature before
`gc_marshal_record_lower_probe.zig` emits the typed GC record lower module.
The canonical import is `(i32, i32)` and the import boundary contains no GC
reference.

`test_gc_marshal_record_lower_manifest_host.sh` verifies Component assembly,
source-hash drift rejection, and Rust/Wasmtime host execution with
`result=42 write-calls=1`. The paired
`test_gc_marshal_record_lower_manifest_equivalence.sh` compares the generated
GC Component with the flat linear-memory reference and observes `42/42` with
one callback per path. This is a private measured record-lower row only;
ordinary host/WIT routing, nested/general aggregates, async/resource paths, and
G5c cutover remain pending.

### G5c C7 gate: private manifest-backed scalar-record lift (2026-08-20)

The descriptor manifest now includes
`demo:marshal-record-host/api.read@1.0.0/lift`, backed by a package and
interface fragment plus a package-less `probe` world fragment. The loader
checks the exact concatenated source hash and `reading` record signature before
`gc_marshal_record_lift_probe.zig` emits the typed GC result-area lift module.
The canonical import is `(i32)` and the import boundary contains no GC
reference.

`test_gc_marshal_record_lift_manifest_host.sh` verifies Component assembly,
source-hash drift rejection, and Rust/Wasmtime host execution with `sum=42`.
The paired `test_gc_marshal_record_lift_manifest_equivalence.sh` compares the
generated GC Component with a linear-memory reference under the same WIT
package and observes `42/42`. This is a private measured record-lift row only;
ordinary host/WIT routing, nested/general aggregates, async/resource paths, and
G5c cutover remain pending.

### G5c C8 gate: private manifest-backed mixed scalar-record lift (2026-08-20)

The descriptor manifest now includes
`demo:marshal-record-mixed-host/api.read@1.0.0/lift`, backed by a package and
interface fragment plus a package-less `probe` world fragment. The loader
checks the exact concatenated source hash and
`reading { code: u32, count: u64, status: s64 }` signature before
`gc_marshal_record_mixed_lift_probe.zig` emits the typed GC result-area lift
module. The measured record is 24 bytes with alignment 8 and field offsets
`0/8/16`; the canonical import is `(i32)` and the import boundary contains no
GC reference.

`test_gc_marshal_record_mixed_lift_manifest_host.sh` verifies Component
assembly, source-hash drift rejection, and Rust/Wasmtime host execution with
`sum=37` from `{7, 35, -5}`. The paired
`test_gc_marshal_record_mixed_lift_manifest_equivalence.sh` compares the
generated GC Component with a linear-memory reference and observes `37/37`.
This is a private measured mixed-record lift row only; ordinary host/WIT
routing, nested/general aggregates, async/resource paths, and G5c cutover
remain pending.

### G5c C9 gate: private manifest-backed indirect scalar-record lower (2026-08-20)

The descriptor manifest now includes
`demo:marshal-record-indirect-lower/api.write@1.0.0/lower`, backed by a
package/interface fragment plus a package-less `probe` world fragment. The
loader checks the exact concatenated source hash and the 17-field `u64`
`writing` record signature before
`gc_marshal_record_indirect_lower_manifest_probe.zig` emits the typed GC
indirect lower module. The measured record is 136 bytes with alignment 8;
the canonical import is a single `(i32)` pointer to the canonical record area
and the import boundary contains no GC reference.

`test_gc_marshal_record_indirect_lower_manifest_host.sh` verifies Component
assembly, source-hash drift rejection, and the Rust/Wasmtime host adapter with
`result=42 write-calls=1`. The paired
`test_gc_marshal_record_indirect_lower_manifest_equivalence.sh` compares the
generated GC Component with the linear-memory reference and observes `42/42`
and `1/1` callback counts. This is a private measured indirect-record lower
row only; layouts beyond the pinned 17-field shape, ordinary host/WIT routing,
nested/general aggregates, async/resource paths, and G5c cutover remain
pending.

### G5c C10 gate: private manifest-backed nested scalar-record lift (2026-08-20)

The descriptor manifest now includes
`demo:marshal-record-nested-host/api.read@1.0.0/lift`, backed by a package and
interface fragment plus a package-less `probe` world fragment. The loader
checks the exact concatenated source hash and nested `reading { header: header,
status: s64 }` signature before
`gc_marshal_record_nested_lift_probe.zig` emits recursive GC record
construction. The measured inner `header` is 16 bytes/alignment 8 with field
offsets `0/8`; the outer `reading` is 32 bytes/alignment 8 with `status` at
offset `16`. The canonical import is one `(i32)` result-area pointer and the
import boundary contains no GC reference.

`test_gc_marshal_record_nested_lift_manifest_host.sh` verifies Component
assembly, source-hash drift rejection, and Rust/Wasmtime host execution with
`sum=37`. The paired
`test_gc_marshal_record_nested_lift_manifest_equivalence.sh` compares the
recursive GC Component with the linear-memory reference and observes `37/37`.
This is a private measured nested-lift row only; deeper/general aggregates,
nested lower, ordinary host/WIT routing, async/resource paths, and G5c cutover
remain pending.

### G5c C11 gate: private manifest-backed nested scalar-record lower (2026-08-20)

The descriptor manifest now also pins
`demo:marshal-record-nested-lower/api.write@1.0.0/lower`, backed by a
package/interface fragment plus a package-less `probe` world fragment. The
loader checks the exact concatenated source hash and nested
`writing { header: header, status: s64 }` signature before
`gc_marshal_record_nested_lower_probe.zig` emits recursive GC record field
flattening. The measured inner `header` is 16 bytes/alignment 8 with field
offsets `0/8`; the outer `writing` is 32 bytes/alignment 8 with `status` at
offset `16`. The WIT-derived canonical import is `(i32, i64, i64)` and no GC
reference crosses the Component boundary.

`test_gc_marshal_record_nested_lower_manifest_host.sh` verifies Component
assembly, source-hash drift rejection, measured child-count rejection through
the route tests, and Rust/Wasmtime host execution (`result=42`,
`write-calls=1`). The paired
`test_gc_marshal_record_nested_lower_manifest_equivalence.sh` compares the
generated recursive GC flattening with the linear-memory reference and
observes `42/42` and `1/1` callback counts. This closes only the pinned
two-level nested scalar lower compiler/provenance/equivalence row; deeper or
general aggregates, indirect nested layouts, default host/WIT routing,
async/resource paths, and G5c cutover remain pending.

### G5c C12 gate: private manifest-backed three-level nested scalar-record lower (2026-08-20)

The descriptor manifest now also pins
`demo:marshal-record-nested-lower-deep/api.write@1.0.0/lower`, backed by a
package/interface fragment plus a package-less `probe` world fragment. The
loader checks the exact concatenated source hash and nested
`writing { detail: detail, tail: s64 }` signature, with
`detail { header: header, status: s64 }` and
`header { code: u32, count: u64 }`, before
`gc_marshal_record_nested_lower_deep_probe.zig` emits recursive GC record field
flattening. The measured layouts are `header=16`, `detail=32`, and
`writing=48` bytes with `status@16` and `tail@32`; the WIT-derived canonical
import is `(i32, i64, i64, i64)` and no GC reference crosses the Component
boundary.

`test_gc_marshal_record_nested_lower_deep_manifest_host.sh` verifies Component
assembly, source-hash and measured-shape checks, and Rust/Wasmtime host
execution (`result=42`, `write-calls=1`). The paired
`test_gc_marshal_record_nested_lower_deep_manifest_equivalence.sh` compares
the generated recursive GC flattening with the linear-memory reference and
observes `42/42` and `1/1` callback counts. This is private measured evidence:
deeper/general aggregates, indirect nested layouts beyond this shape, ordinary
host/WIT routing, async/resource paths, and G5c cutover remain pending.

### G5c C13 gate: private manifest-backed three-level nested scalar-record lift (2026-08-20)

The descriptor manifest now also pins
`demo:marshal-record-nested-lift-deep/api.read@1.0.0/lift`, backed by a
package/interface fragment plus a package-less `probe` world fragment. The
parser-backed route binds `reading { detail: detail, tail: s64 }`, where
`detail { header: header, status: s64 }` and
`header { code: u32, count: u64 }`. The pinned toolchain-backed result-area
measurement is `header=16`, `detail=24`, and `reading=32` bytes, with leaf
offsets `code@0`, `count@8`, `status@16`, and `tail@24`; the canonical import
is one `(i32)` result-area pointer and no GC reference crosses the Component
boundary.

`test_gc_marshal_record_nested_lift_deep_manifest_host.sh` covers Component
assembly, source-hash and measured-shape checks, and Rust/Wasmtime host
execution (`sum=42`). The paired
`test_gc_marshal_record_nested_lift_deep_manifest_equivalence.sh` compares the
generated recursive GC construction with the linear-memory reference and
observes `42/42`. This is private measured evidence: deeper/general
aggregates, indirect nested layouts beyond this shape, ordinary host/WIT
routing, async/resource paths, and G5c cutover remain pending.

### G5c C15-A gate: private manifest-backed scalar-plus-text record lift (2026-08-20)

The descriptor manifest now pins
`demo:marshal-record-managed-lift/api.read@1.0.0/lift` for the parser-backed
`reading { code: u32, label: string }` record. The measured result area is 12
bytes with `code@0`, `label.ptr@4`, and `label.len@8`; canonical lift remains a
single `(i32)` result-area pointer. The private GC emitter copies the measured
text span into `$do_bytes`, constructs `$do_text`, and then constructs the
record. The canonical import contains no GC reference.

`test_gc_marshal_record_managed_lift_manifest_host.sh` passes pinned Core and
Component assembly, source-hash drift rejection, and Rust/Wasmtime execution
with `value=12`. The paired
`test_gc_marshal_record_managed_lift_manifest_equivalence.sh` passes the
linear-memory reference comparison with `values=12/12`; the route suite also
rejects measured child-count drift. This is private scalar-plus-text lift
evidence only. Text/list record lower, arbitrary managed aggregates, default
host/WIT routing, async/resource paths, and G5c cutover remain pending.

### G5c C15-B gate: private manifest-backed scalar-plus-text record lower (2026-08-21)

The descriptor manifest pins
`demo:marshal-record-managed-lower/api.write@1.0.0/lower` for the
parser-backed `writing { code: u32, label: string }` record. The measured
record layout is 12 bytes with `code@0`, `label.ptr@4`, and `label.len@8`;
the pinned canonical lower import is `(i32, i32, i32)` and carries only
`code`, `label.ptr`, and `label.len`. No GC reference crosses the
Component boundary.

The GC lower emitter checks the text length against the GC byte array, calls
`cabi_realloc(0, 0, 1, len)` once, copies the bytes, invokes the host once,
then calls `cabi_realloc(ptr, len, 1, 0)` once after the host call. The
Rust/Wasmtime host gate observes `code=7`, `label=hello`,
`write-calls=1`, `allocations=1`, and `frees=1`; the ARC/GC equivalence
gate observes the same fields, call count, and cleanup counts on both paths.

This is private fixed-shape evidence only. General managed-record lower,
multiple managed fields, text/list record lower, default host/WIT routing,
async/resource paths, and G5c cutover remain pending. The migration inventory
therefore keeps this row G5c-pending even though its independent host and
equivalence evidence is green.
### G5c C15-C explicit compiler host/WIT wiring (2026-08-21)

The real compiler entry point now has a private, explicit opt-in:
`do build <input.do> --gc-wit-marshal demo:marshal-record-managed-lower/api.write@1.0.0/lower`.
The option is fail-closed for missing/duplicate values, conflicting special
targets, and unknown descriptor ids. It reuses the descriptor manifest loader
and measured C15-B plan rather than accepting caller-provided WIT identity or
layout facts.

The compiler-generated Core WAT passed `wasm-tools 1.255.0` validation and
Component assembly. Its import is `(i32, i32, i32)` with no GC reference at the
boundary; the temporary string span is allocated, copied, passed to the host,
and freed after the call. The compiler-output host and ARC/GC equivalence gates
are green with `code=7`, `label=hello`, `write-calls=1`, `allocations=1`, and
`frees=1`, plus `1/1` equivalence counters.

This is not default host/WIT migration. Ordinary `@host` remains ARC-backed,
and general aggregate, async/resource, ownership syntax, and G5c full cutover
remain pending. The residual inventory must continue to report those rows.

### G5c C15-D private multi-managed-text lower status (2026-08-21)

The private descriptor
`demo:marshal-record-managed-lower-multi/api.write@1.0.0/lower` is closed for
the exact `writing { code: u32, label: string, note: string }` shape. Its
measured root is 20 bytes/alignment 4 with `code@0`, `label.ptr@4`,
`label.len@8`, `note.ptr@12`, and `note.len@16`; the canonical lower import is
`(i32, i32, i32, i32, i32)` and no GC reference crosses the boundary.

The standalone and real compiler gates pass pinned `wasm-tools 1.255.0`
assembly, source-hash/shape checks, host execution, and GC/ARC equivalence.
The host observes `code=7`, `label=hello`, `note=world`, one callback, and
two allocations/two frees; equivalence observes `2/2` allocations, `2/2`
frees, and `1/1` callbacks. The exact gates are:

```bash
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_manifest_host.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_manifest_equivalence.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_host.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_managed_lower_multi_compiler_equivalence.sh
```

This closes only private explicit evidence for one direct-root multi-text
record. General managed-record/text-list marshalling, default host/WIT
routing, async/resource lowering, public ownership syntax, and G5c full
cutover remain blockers.

### G5c C16-A real source-level host boundary status (2026-08-21)

The explicit adapter now validates the host declaration in
`src/build/test/compile_ok/564_gc_wit_managed_record_host_boundary.do` before
emitting the C15-D descriptor
`demo:marshal-record-managed-lower-multi/api.write@1.0.0/lower`. The fixture
places the import before `Writing` because the parser requires top-level
imports before ordinary declarations. Admission is limited to one
`@host_func`, the exact locator/member, `nil` result, and the ordered fields
`code: u32`, `label: text`, `note: text`.

The canonical boundary remains five `i32` parameters, with a 20-byte root and
offsets `code@0`, `label@4`, and `note@12`; no GC reference crosses it. The
compiler host/equivalence gates and the negative/default gate are green. The
host observes `code=7`, `label=hello`, `note=world`, one callback, and
`allocations=2`, `frees=2`; equivalence is `2/2`, `2/2`, and `1/1`. Async and
locator-mismatch fixtures fail before WAT, and the ordinary build remains
ARC-backed.

This closes only C16-A's private declaration boundary. General managed-record
or text/list marshalling, default host/WIT routing, async/resource lowering,
public ownership syntax, G5c cutover, and the corresponding inventory rows
remain pending.

### G5c C16-B fixed-descriptor host validator expansion (2026-08-21)

The source-level validator is now shared by two private explicit descriptors:
C15-B `Writing { code: u32, label: text }` and C16-A
`Writing { code: u32, label: text, note: text }`. A descriptor-specific
specification supplies the locator, member, record name, and ordered fields;
there is no general Do-to-WIT inference. Unknown descriptors, async markers,
locator/member drift, duplicate or extra host declarations, and record-shape
drift fail before WAT.

The C15-B compiler host and ARC/GC equivalence gates pass with one callback and
one allocation/free on each path. The C16-B negative/default gate verifies
rejection leaves no WAT and that default `@host` remains ARC-backed. This
expands only the private fixed-descriptor validator and does not close general
aggregate marshalling, default host/WIT GC routing, async/resource lowering,
public ownership syntax, G5c cutover, or the related inventory rows.

### G5c C16-C private managed-record lift compiler boundary

C16-C promotes the already measured C15-A lift into the real compiler through
the explicit descriptor
`demo:marshal-record-managed-lift/api.read@1.0.0/lift`. The source boundary is
strictly one synchronous `@host_func` with zero parameters and `Reading` result;
`Reading` must contain ordered `code: u32` and `label: text` fields. The
manifest-backed emitter uses the 12-byte result area and canonical
`(func (param i32))`, constructs managed GC text, and exports the fixed `run`
probe. No GC reference crosses the canonical import.

The compiler host gate returns `value=12`, and the ARC/GC equivalence gate
returns `12/12`. Async and locator-mismatch declarations fail before WAT and
the default build remains on the ARC route. This is private opt-in evidence;
general aggregate lowering, default host/WIT GC wiring, async/resource
lowering, ownership syntax, and G5c cutover remain blocked/pending.

### G5c C16-D private multi-managed-field lift compiler boundary

The explicit compiler adapter now validates the exact host-first fixture
`src/build/test/compile_ok/581_gc_wit_managed_record_lift_multi_host_boundary.do`
against `demo:marshal-record-managed-lift-multi/api.read@1.0.0/lift`. Admission
is limited to one synchronous `@host_func`, zero parameters, and the ordered
`Reading { code: u32, label: text, note: text }` result. The canonical lift
remains one `i32` result-area pointer with the measured 20-byte layout; no GC
reference crosses the import, and the two managed text fields are copied into
typed GC values.

Pinned `wasm-tools 1.255.0` Component assembly/validation and compiler host
execution pass with `value=17`; ARC/GC equivalence passes `17/17`. Async and
locator-mismatch fixtures fail before WAT with no artifact, while the default
fixture remains ARC-backed. This is private explicit evidence only and does
not close general aggregate/text-list marshalling, default host/WIT routing,
async/resource lowering, public ownership syntax, or G5c cutover.

### G5c manifest-driven bounded compiler route closeout (2026-08-21)

The four private synchronous managed-record compiler routes are now backed by
the checked-in descriptor manifest for measured layout and by resolved WIT plus
Do-token validation for the host boundary. The explicit opt-in route passed all
eight compiler host/equivalence gates and four negative/default gates; full Zig
passed `598/598`, repository regression passed `pass=1279 fail=0 skip=3`, and
ReleaseSmall/release smoke passed with `wasm-tools 1.255.0`. Default `@host`
remains ARC-backed, canonical ABI crossings contain no GC references, and the
inventory remains `complete_rows=15 pending_rows=15` with its documented exit 1.
This is not general host/WIT GC routing or full G5c cutover; aggregate,
async/resource, and ownership paths remain pending.

### G5c C15-D/C16-D default multi-managed-text route closeout (2026-08-22)

The ordinary default route now admits the exact C15-D lower and C16-D lift
descriptors in addition to the earlier C15-B/C16-C rows. The default host and
equivalence gates build without `--gc-wit-marshal`, validate with pinned
`wasm-tools 1.255.0`, and run the existing Rust/Wasmtime adapters. C15-D
observes `code=7`, `label=hello`, `note=world`, with `allocations=2` and
`frees=2`; the paired equivalence gate observes `2/2` cleanup and one callback.
C16-D observes `value=17` and the paired equivalence gate observes `17/17`.

Both routes emit `;; gc-sync`, contain no `__arc_` marker, and keep GC
references out of canonical imports. Async and locator drift fail before WAT
and leave no artifact. The executable fixtures use a temporary gate-local
wrapper from compiler `_start` to probe `run`; this adapts the current CLI
entry shape without changing compiler semantics, while the host callback and
generated lower/lift instructions remain real.

This closes only the two fixed default promotion rows. General aggregates,
generic async/producer and Stream lowering, async/resource host/WIT paths,
ownership syntax, and full GC cutover remain pending. The migration inventory
intentionally remains `complete_rows=15 pending_rows=15` with exit 1.

### G6.2 parameterized six-hop forwarding (2026-08-26)

The bounded parameterized `StreamWriter<u8>` producer now admits exactly six
static helper forwarding edges for the existing
`do:stream-probe@0.1.0/write-via-stream` descriptor. The Do fixture keeps the
same `(writer, count, value)` parameters, exports only `produce`, and uses the
existing countdown/write/close sequence; no descriptor, WIT member, or public
syntax was added. The analyzer bound is the single change from five to six;
arbitrary producer expressions, literal/reordered arguments, loops, borrowed,
list, and variant payloads remain rejected.

The positive Component gate and the seventh-hop negative pass with pinned
`wasm-tools 1.255.0`. Rust/Wasmtime covers `count=0/1/3`, `value=90`,
pending/ready/`Err(pipe)`, early drop, and cancel-after-transfer. Each row
observes one host callback, one stream drop, expected payload, and an empty
`ResourceTable`; cancellation reports no successful external effect. The
canonical boundary remains free of Wasm GC references and cleanup is
exactly-once. This closes only the sixth-hop bounded capability; general
producer/resource lowering, seventh-hop forwarding, and full GC cutover remain
pending.
