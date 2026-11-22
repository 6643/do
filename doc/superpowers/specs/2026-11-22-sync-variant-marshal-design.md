# Synchronous Recursive Variant Marshal Design

## Goal

Add a measured, recursive Component canonical ABI route for synchronous value
types `option<T>`, `result<T, E>`, and general `variant` values. The route must
reuse the existing scalar, text, list, map, and record nodes, never pass a Wasm
GC reference through a canonical import, and reject unmeasured or unsupported
shapes before WAT emission.

This is the next step after the bounded scalar/list/record routes. It is not a
claim that every WIT type is supported.

## Approaches

### Selected: recursive measured plan

Represent every value as a recursive marshal node. A variant node owns the
ordered case metadata, the canonical discriminant facts, and one child node for
each payload case. `option<T>` and `result<T, E>` are normalized to variant
nodes with source-kind metadata preserved for diagnostics and Do binding.

The canonical function signature is derived from the measured node tree. The
emitter consumes that signature and the same tree for both lift and lower. This
keeps tag width, payload offsets, flattening, indirect result areas, temporary
allocations, and cleanup in one data flow.

### Rejected: fixed descriptor promotion

Adding one exact implementation for `option<u32>`, another for
`result<u32, u32>`, and so on would produce evidence quickly, but it would
repeat the current bounded-shape checks and would not solve nested payloads.

### Rejected: generic string-based ABI inference

Inferring the canonical signature from a type name or a `(i32,i32)` string
would make the signature drift from the measured WIT layout. It also cannot
represent flattened variants or inactive payload storage safely.

## Scope

Included:

- synchronous `option<T>`, `result<T, E>`, and `variant` values;
- recursive payloads composed from already measured value nodes;
- scalar, text, admitted scalar list, admitted map, and record payloads;
- both lift and lower directions;
- canonical flat core slots and indirect result-area/payload layouts when the
  descriptor supplies them;
- active-case-only copy and cleanup;
- exact descriptor identity and measured-layout validation.

Excluded:

- `tuple` lowering, which has a separate flattening contract;
- resources, `own`, `borrow`, `future`, `stream`, and async calls;
- arbitrary list/map element layouts without measurements;
- public ownership syntax or GC backend cutover;
- source-level automatic conversion between Do unions and WIT variants beyond
  the existing registered binding path.

## Source and WIT Semantics

The WIT case metadata is authoritative. Case names and measured tags are
matched by name and tag; source order alone cannot repair a mismatch.

The normalized cases are:

| Source kind | Case 0 | Case 1 |
| --- | --- | --- |
| `option<T>` | `none`, no payload | `some`, payload `T` |
| `result<T,E>` | `ok`, payload when present | `err`, payload when present |
| `variant` | WIT declared cases | WIT declared cases |

The planner preserves whether a case has no payload. A payload-bearing case
must have a recursively measured child node. A no-payload case must not carry
payload storage facts.

Invalid runtime discriminants are a trap before the canonical call or before
constructing a lifted GC value. The invalid path must not allocate or free a
payload span.

## Plan Model

`codegen_component_marshal_plan.zig` remains the public planner boundary.

`NodeKind` gains `option`, `result`, and `variant` nodes. Variant metadata is a
separate owned collection so the node does not encode case identity in child
position alone. Each case stores:

- source case name;
- measured canonical tag;
- whether the case has a payload;
- the payload child index, if any;
- payload placement facts supplied by the measured layout.

`MeasuredLayout` gains a recursive variant layout. The variant measurement
contains discriminant offset/size/alignment, total byte size/alignment, and
case payload measurements. Payload measurements may themselves contain a
`MeasuredNode`; a shallow scalar payload remains expressible without an extra
child allocation.

The planner validates the following before creating a `SyncValuePlan`:

1. the source kind and measured layout kind match;
2. case count, names, tags, and payload presence match exactly;
3. discriminant and every active payload region are aligned and within the
   measured container;
4. nested payload nodes validate recursively;
5. the resulting canonical signature has no GC reference;
6. resources, futures, streams, and unsupported nested layouts fail closed.

`option` and `result` are normalized during node construction, but their
source kind remains available for diagnostics and registry checks.

## Canonical Signature

The plan owns a structured canonical signature, rather than deriving a WAT
type string in `canonical_type_name`.

The signature records:

- direction;
- flat core parameter/result words, in canonical order;
- whether the value is passed indirectly through a pointer;
- result-area size and alignment when lifting;
- the location of the discriminant;
- each case payload's flat slots or memory region;
- temporary linear-memory requirements.

Existing scalar/list/map/record emitters are adapted to provide this signature
through the same node tree. The old string helper may remain as a formatting
helper for tests, but it is not allowed to decide ABI admission.

For a variant with a flat canonical representation, the signature lists the
discriminant and the joined payload slots required by the canonical ABI. For a
variant with an indirect representation, the signature contains the pointer
slot and measured result-area layout. The planner does not choose between
these representations from a hardcoded size threshold; the measured
descriptor must provide the representation and the validator checks it.

## Lowering

Lowering receives a GC value and produces the canonical call arguments.

1. Read and validate the GC variant tag.
2. Select the active case.
3. Emit only the active payload conversion.
4. Allocate and copy active text/list payloads to linear memory.
5. Write an indirect payload area when the signature requires it.
6. Call the canonical import.
7. Free every temporary span exactly once in reverse allocation order.

No inactive case payload is read, allocated, copied, or freed. If a canonical
call fails by trapping, the generated cleanup structure must still be the
normal structured cleanup path available to the current WAT route.

## Lifting

Lifting calls the canonical import with the measured result area when required.

1. Call the canonical import.
2. Read and validate the discriminant.
3. Select the active case.
4. Copy only the active payload into a GC scalar/text/list/record value.
5. Construct the GC variant with the measured source tag mapping.
6. Free canonical temporary spans exactly once in reverse order.

An inactive payload region is ignored. Invalid canonical tags trap before a GC
value is returned.

## Boundary Invariants

- No canonical import parameter or result contains `(ref ...)`.
- Text and list payloads cross the boundary as linear pointer/length data and
  are copied into GC arrays on lift or copied out on lower.
- The same measured offsets drive WAT loads, stores, allocation sizes, and
  cleanup.
- Descriptor identity and source hash remain mandatory.
- Unsupported shapes fail before module emission, with the existing
  `UnsupportedMarshalShape` family or a more specific measured-layout error.

## Tests and Evidence

The implementation is accepted only when the following tests exist.

### Planner tests

- `option<u32>` with none/some cases;
- `result<text, u32>` with both payload cases;
- a three-case variant containing a scalar, a text payload, and a no-payload
  case;
- nested `result<option<u32>, text>`;
- duplicate tag, missing payload, case-name drift, case-order drift, invalid
  offset, and child-count failures;
- resource, future, stream, tuple, and unmeasured nested payload rejection.

### WAT emitter tests

- lower dispatches on the active tag and emits only that payload;
- lift dispatches on the canonical tag and constructs only that payload;
- canonical import types match the measured flat or indirect signature;
- text/list payload allocation and reverse cleanup are visible and counted;
- generated WAT contains no canonical GC reference.

### Component gates

At least one parser-backed WIT case must pass Component validation and a host
execution gate for each of:

- option with scalar payload;
- result with text and scalar alternatives;
- variant with a no-payload and payload-bearing alternative.

The host/equivalence gates must observe active-case values and exactly-once
linear cleanup. Negative fixtures must fail before WAT emission.

## Files and Responsibilities

- `src/build/codegen_component_marshal_plan.zig`: recursive node construction,
  measured variant binding, canonical signature, and planner errors.
- `src/build/wit_abi_layout.zig`: recursive variant measurement validation and
  layout facts.
- `src/build/codegen_component_marshal_module.zig`: canonical import type
  emission from the structured signature.
- `src/build/codegen_component_marshal_wat.zig`: variant lift/lower dispatch,
  payload copy, and cleanup.
- `src/build/codegen_component_marshal_route.zig`: parser-backed route tests.
- `src/build/codegen_component_marshal_*_test.zig` and
  `src/build/test/compile_{ok,err}`: regression and negative fixtures.
- `doc/roadmap_status.md` and `doc/start_here.md`: update only after the
  independent planner, WAT, and Component gates pass.

## Exit Criteria

This design slice is complete when synchronous measured
`option/result/variant` values pass planner, WAT, Component validation, host
execution, and cleanup/equivalence gates, while tuple, resource, async, and
unmeasured arbitrary aggregate shapes still fail closed.
