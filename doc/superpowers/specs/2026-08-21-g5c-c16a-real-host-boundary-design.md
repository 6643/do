# G5c C16-A: real `@host_func` boundary for the managed-text lower probe

## Status

Implemented and verified on 2026-08-21 after the C15-D standalone/private
compiler gates and the C16-A negative/default-route gate passed. This design is
a bounded promotion of the C15-D probe. It does not change the default
host/WIT route, admit arbitrary aggregate lowering, or close G5c.

## Goal

Make the private GC/WIT lower entry point consume a real `.do`
`@host_func` declaration before it emits the already-pinned C15-D Component
module. The compiler must prove that the declaration and the checked-in WIT
descriptor identify the same host function and the same bounded
`{u32, text, text}` shape. The generated canonical import, host observation,
cleanup counters, and ARC/GC equivalence must remain the C15-D contract.

The selected compiler invocation remains explicit:

```text
do build <fixture.do> \
  --gc-wit-marshal \
  demo:marshal-record-managed-lower-multi/api.write@1.0.0/lower \
  -o <core.wat>
```

The option is a migration gate, not a new default backend selector.

## Context and alternatives

Before C16-A, the C15-C/D path loaded the manifest and emitted a private module,
but the compiler gate did not consume a source-level host declaration. The
normal `@host_func` path remains ARC-backed. This is the exact gap this design
closes.

### A: declaration-checked private adapter (selected)

Keep `--gc-wit-marshal <descriptor>` as an opt-in target. Pass the loaded entry
tokens to the adapter, locate one top-level synchronous `@host_func`, and
validate its locator, member, result, parameter type, and local record shape
against the manifest-backed descriptor. Then reuse the existing parser-backed
manifest route and C15-D emitter.

This is selected because it proves the compiler boundary with a small,
reversible surface while preserving the existing ABI and default route.

### B: generalize the normal Component host pipeline first

Teach the ordinary Component pipeline to lower arbitrary `@host_func` aggregate
parameters and then remove the private adapter. This would better match the
long-term architecture, but it expands the change into normal body lowering,
general aggregate planning, and the current ARC fallback boundary before one
new managed shape has a compiler gate.

### C: switch default host/WIT lowering to GC

Route ordinary `@host_func` declarations through GC immediately. Current
inventory rows still leave general aggregate, async/resource, and default
route work pending, so this would mix an unproven cutover with the C15-D
promotion and would not be safely reversible.

## Boundary contract

### Input declaration

The positive fixture contains one top-level declaration equivalent to:

```do
write = @host_func("demo:marshal-record-managed-lower-multi/api@1.0.0", "write", (Writing) -> nil)

Writing {
    code u32
    label text
    note text
}

start() {}
```

The host import appears before the record because the current parser requires
top-level imports before ordinary declarations.

The exact fixture is a dedicated `compile_ok` case; its declaration is the
source-level contract under test. The adapter does not infer a WIT descriptor
from an arbitrary locator. The descriptor id supplied on the command line is
still required and is the only accepted identity selector.

### Identity and shape checks

Before any WAT slice is returned, the adapter must validate, in this order:

1. The descriptor id is admitted by the private C15-D allowlist.
2. The manifest loader verifies repository-relative paths, source hash,
   package, world, interface, member, direction, signature, canonical import,
   and measured layout.
3. The entry program contains exactly one top-level host declaration for this
   private target. It must be `@host_func`, not `@host_async_func`. The
   token-level validator returns `AsyncGcWitHostDeclaration`; the full CLI
   reaches the existing frontend registry guard first and reports
   `UnknownP3AsyncHostDescriptor` for the negative async fixture.
4. The locator equals the descriptor canonical Component module
   `demo:marshal-record-managed-lower-multi/api@1.0.0`; the member equals
   `write`; and the result is `nil`.
5. The Do parameter is one named record whose fields, in declaration order,
   are `code: u32`, `label: text`, and `note: text`. The adapter must reject a
   missing type, extra or reordered field, a different scalar, a non-text
   managed field, a list/variant/option/result/resource, or a second parameter.
6. No other top-level host declaration is silently dropped by this private
   target. An additional host declaration is a fail-closed error rather than
   an implicit ARC fallback.

The check is source/shape validation only. It does not add `own<T>`,
`borrow<T>`, `ref<T>`, Option/Result syntax, async lowering, resource
ownership, or a general Do-to-WIT type mapper.

### Generated module and ABI

After the checks pass, the adapter reuses the manifest-backed C15-D plan and
emitter. The canonical import remains:

```wat
(type $canonical_lower (func (param i32 i32 i32 i32 i32)))
```

The parameters remain `code`, `label.ptr`, `label.len`, `note.ptr`, and
`note.len`. The measured root is 20 bytes with alignment 4 and field offsets
`code@0`, `label@4`, and `note@12`. Each text value is copied to a temporary
linear-memory span, the host call happens once, and the two spans are freed in
reverse declaration order. The canonical import must contain no GC reference.

The private adapter may continue to construct the fixed probe value
`{ code: 7, label: "hello", note: "world" }`; it must not claim that the
ordinary Do function body has been lowered through the GC path. Body lowering
and arbitrary call-site expressions are a later, separately gated task.

## Data flow

```mermaid
flowchart LR
  A[.do @host_func declaration] --> B[entry-token boundary validator]
  B --> C[descriptor manifest and WIT resolver]
  C --> D[measured C15-D marshal plan]
  D --> E[GC text copy and canonical lower]
  E --> F[Component embed/new/validate]
  F --> G[Rust Wasmtime host]
  G --> H[ARC/GC equivalence]
```

The default route is outside this flow and remains the existing ARC-backed
`compile_program_wat` path.

## Failure and rollback contract

The following failures must occur before returning WAT and must not fall back
to ARC: unknown descriptor, missing/duplicate host declaration, async marker,
locator/member/result mismatch, record signature mismatch, source/hash/WIT
drift, measured layout drift, unsupported child shape, and an additional host
declaration that this private target cannot represent. Error names may follow
the existing diagnostic taxonomy, but each failure must retain a distinct
testable condition.

Rollback is limited to the C16-A fixture, adapter validation, and its gates.
The C15-A through C15-D standalone evidence, the default ARC route, and all
existing synchronous GC gates remain untouched if any new gate fails.

## Verification gates

The implementation plan must provide independently observable gates:

1. A pinned `wasm-tools 1.255.0 (76e20611d 2026-07-30)` ABI check starts from
   the compiler-produced C15-D WAT and confirms the five-`i32` import, 20-byte
   record shape, no GC reference at the canonical boundary, and call-before-
   free ordering.
2. Focused Zig tests cover positive declaration matching and negative
   locator, member, marker, arity, field order/type, duplicate, and extra-host
   cases. They assert that failed admission returns no WAT slice.
3. The generated Core module passes `parse`, `component embed`, `component
   new`, `validate`, and `component wit` with the pinned toolchain.
4. The Rust/Wasmtime host gate observes `code=7`, `label=hello`,
   `note=world`, `write-calls=1`, `allocations=2`, and `frees=2`.
5. The ARC/GC equivalence gate observes identical fields and
   `allocations=2/2`, `frees=2/2`, `write-calls=1/1`.
6. The ordinary build of the same fixture without `--gc-wit-marshal` remains
   on the ARC path; the existing full regression, ReleaseSmall build,
   residual gate, and migration inventory keep their current results.
7. `test_gc_marshal_record_managed_lower_multi_compiler_boundary_negative.sh`
   proves async/mismatch rejection, no WAT artifact, the default ARC route,
   the existing C15-B/C15-D compiler gates, and the residual baseline.

## Exit criteria and non-goals

C16-A is closed only when all six gates pass and the docs record the exact
fixture, descriptor, ABI, and private opt-in boundary. It does not close the
`host_wit_marshalling` or `host_wit_marshalling_managed_record_lower`
inventory rows, general aggregate lower, ordinary host/WIT wiring, async or
resource lowering, or G5c cutover. Those remain separate targets requiring
their own design and gates.
