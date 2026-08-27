# G5c Manifest-Driven Bounded Compiler Route

## Status

Approved direction for the next private G5c compiler slice. This design is
opt-in and bounded. It removes duplicated C15/C16 host-shape and measured
layout tables from the compiler route; it does not enable the default GC
host/WIT path or close the migration inventory.

## Context And Evidence

The checked-in descriptor manifest already owns the WIT source paths, source
hash, package/version, world, interface, member, direction, signature claims,
and canonical import. The manifest loader verifies those claims against the
resolved WIT model before the existing synchronous marshal planner runs.

The real compiler route currently has a second source of truth:
`codegen_gc_wit_host_boundary.zig` keeps fixed Do record field tables for the
C15-B, C15-D, C16-C, and C16-D descriptors, while
`codegen_gc_wit_marshal.zig` keeps fixed measured `MeasuredNode` constructors
for the same descriptors. This duplication is the next architecture boundary
to remove. The current C16-D gates provide the latest concrete ABI evidence:
the `Reading { code: u32, label: text, note: text }` result area is 20 bytes,
the canonical lift import is `(func (param i32))`, and no GC reference crosses
the import.

## Goal

Make one validated manifest-backed descriptor request the source of truth for
the private synchronous compiler route:

```text
Do tokens -> descriptor id -> manifest/WIT resolver -> measured request
       -> source-boundary validator -> canonical GC marshal emitter
```

The route must continue to accept only an explicit
`--gc-wit-marshal <descriptor-id>` selection. The first migration set is the
four existing direct managed-record descriptors:

```text
demo:marshal-record-managed-lower/api.write@1.0.0/lower
demo:marshal-record-managed-lower-multi/api.write@1.0.0/lower
demo:marshal-record-managed-lift/api.read@1.0.0/lift
demo:marshal-record-managed-lift-multi/api.read@1.0.0/lift
```

Their emitted canonical ABI and host observations must remain unchanged.

## Non-Goals

- Do not change ordinary `@host_func` compilation; it remains ARC-backed.
- Do not switch the default host/WIT route to GC.
- Do not infer arbitrary Do types or accept a caller-supplied WIT source,
  signature, layout, or canonical import.
- Do not admit async functions, `future`, `stream`, resources, `own`, `borrow`,
  `option`, `result`, variants, tuples, producer expressions, or unmeasured
  list/aggregate shapes.
- Do not add `own<T>`, `borrow<T>`, `ref<T>`, `Option`, `Result`, or syntax.
- Do not close or edit the 15-row GC migration inventory.
- Do not alter test-only probe values or treat a probe wrapper as a public ABI.

## Descriptor Measurement Data

The manifest remains schema 1. A private descriptor may add a
`measured_layout` object. Existing descriptors without that object continue
through their existing standalone manifest probes and are not admitted by
this compiler route.

The object is a serialized `MeasuredNode` with a deliberately small schema:

```json
{
  "measured_layout": {
    "kind": "record",
    "byte_size": 20,
    "alignment": 4,
    "fields": [
      {"name": "code", "offset": 0, "byte_size": 4, "alignment": 4},
      {"name": "label", "offset": 4, "byte_size": 8, "alignment": 4},
      {"name": "note", "offset": 12, "byte_size": 8, "alignment": 4}
    ],
    "children": [
      {"kind": "scalar", "offset": 0, "byte_size": 4,
       "alignment": 4, "core_type": "i32"},
      {"kind": "text", "pointer_offset": 0, "length_offset": 4,
       "byte_size": 8, "alignment": 4,
       "allocation": "cabi_realloc", "free": "cabi_realloc"},
      {"kind": "text", "pointer_offset": 0, "length_offset": 4,
       "byte_size": 8, "alignment": 4,
       "allocation": "cabi_realloc", "free": "cabi_realloc"}
    ]
  }
}
```

The loader validates object kinds, field order, offsets, sizes, alignments,
child count, scalar core types, and allocation/free names before constructing a
`MeasuredNode`. A missing, malformed, or inconsistent measurement produces a
named error before WAT emission. The WIT source hash continues to cover the
concatenated source bytes; measurement data is not trusted as a replacement
for WIT type resolution.

## Source Boundary Contract

The loader returns one owned request containing the resolved WIT member,
direction, canonical import, source hash, and measured layout. The source
validator receives that request rather than a descriptor-id switch or a
hard-coded field table.

For the first migration set, the validator applies these guards:

1. The resolved member is synchronous and has the manifest direction.
2. For `lower`, exactly one `@host_func` has one Do record parameter and a
   `nil` result. For `lift`, exactly one `@host_func` has zero parameters and
   one Do record result.
3. The Do record has the same field count, field order, field names, and
   scalar/string shapes as the resolved WIT record. WIT `string` maps to Do
   `text`; scalar names map one-to-one through the existing scalar table.
4. There is exactly one target declaration and no unrelated host declaration.
   Async markers, locator/member drift, duplicates, extra declarations, and
   shape drift fail closed before the emitter is called.
5. The measured root fields match the resolved WIT field order and the
   measured child nodes. The resulting canonical ABI contains only core
   scalar words and linear-memory pointer/length pairs; a GC reference is a
   hard error.

The validator may use the Do record's local name (`Reading`, `Writing`, or a
future private name) independently from the WIT type name. WIT names and
resolved member identity remain the authority for shape and ABI.

## Component And Emitter Contract

The compiler route performs these steps in order:

1. Parse and semantically check the Do source as today.
2. Load and hash-check the descriptor manifest entry.
3. Resolve the WIT world/member and derive the canonical import.
4. Decode and validate `measured_layout`.
5. Validate the Do host declaration against the resolved member.
6. Build the existing synchronous marshal plan from the resolved type and
   measured layout.
7. Emit Core WAT with the same canonical import and GC-owned result/lower
   operations as the current C15/C16 route.

The emitter no longer selects a measurement by comparing descriptor-id
strings. The private test probe wrapper may still be selected by a separate
probe recipe after the core marshal module is built; that recipe is test
scaffolding, is not part of the host ABI, and must not affect the source
validator or canonical import.

## Error And Rollback Contract

Manifest schema errors, source hash drift, WIT resolution drift, missing or
invalid measurement data, source-shape mismatch, unsupported WIT shape, and
GC-reference ABI attempts all fail before writing the output WAT file. No
error path falls back to the default ARC route after the explicit option has
been selected.

Because the route remains opt-in, rollback is limited to removing the new
`measured_layout` entries and the private route wiring; ordinary builds and
the 15-row inventory remain unaffected. No compatibility branch or alternate
measurement source is introduced.

## Verification Gates

Focused Zig tests must cover:

- valid measurement decoding for all four descriptors;
- malformed/missing measurements, child-count drift, field-order drift, and
  source-hash drift;
- WIT-derived Do boundary acceptance for lower and lift;
- async, locator/member mismatch, duplicate/extra declaration, field-order,
  and field-type rejection;
- canonical import and no-GC-reference validation.

The existing four descriptor compiler host/equivalence gates remain the
behavioral contract. They must observe the existing values and counters,
including C16-D `value=17` and ARC/GC `17/17`. The negative/default gates must
still prove no WAT artifact on rejection and ARC output without opt-in.

Before the slice is considered complete, run the focused tests, all three
C16-D gates, all existing C15/C16 compiler gates, full Zig tests, the full
integration harness, ReleaseSmall/release smoke, `git diff --check`, and the
migration inventory command. The expected inventory result remains
`complete_rows=15 pending_rows=15` with its documented non-zero status.
