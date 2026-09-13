# G6.2 Final Fix Report

Date: 2026-09-13
Scope: final review fixes for the private direct owned-record producer pilot

## Findings closed

1. `codegen_component_producer_emitter.zig` no longer embeds or names the
   route WAT template. `PilotInput.template_wat` is the explicit assembly
   source supplied by the route adapter. `golden_wat` is used only for the
   final byte-for-byte parity comparison. ARC and canonical-GC guards inspect
   assembled output, so a mutated golden cannot self-certify.
2. `CanonicalFrameMap` validation now requires each ownership fact's
   `state_offset` to identify a frame field with role `.ownership_state`.
   Record payloads additionally require field-level binding offsets, widths,
   payload sizes, frame coverage, owned source-field topology, resource/drop
   identity, and ownership-leaf counts to match. These checks are borrowed,
   bounded, allocation-free, and do not add route admission or public syntax.
3. The adapter/probe regression now uses `facts.route_facts_equal`, covering
   identity, frame fields, ownership facts, bindings, lifecycle anchors, and
   markers rather than counts only.

## Changed files

- `src/build/codegen_component_producer_emitter.zig`
- `src/build/codegen_component_owned_record_stream_producer.zig`
- `src/build/codegen_component_producer_emitter_test.zig`
- `src/build/codegen_component_producer_state_ir.zig`
- `src/build/codegen_component_producer_state_ir_test.zig`
- `.superpowers/sdd/2026-09-13-g6-2-shared-emitter-state-ir-pilot/final-fix-report.md`

## Verification

All commands were run from the repository checkout with the local Zig cache
paths used by the G6.2 focused tests.

```text
zig test main.zig --test-filter "producer shared emitter pilot"
All 20 tests passed.

zig test main.zig --test-filter "owned record producer"
All 15 tests passed.

zig test main.zig --test-filter "producer canonical frame map"
All 16 tests passed.

zig test main.zig
All 1728 tests passed.

zig fmt <five changed Zig files>
completed with exit 0

zig fmt --check <five changed Zig files>
completed with exit 0

git diff --check
completed with exit 0
```

Source-ownership scan confirmed `owned_record_stream_producer_template.wat`
and `@embedFile` occur in the adapter only; the emitter contains only the
explicit `template_wat` input and the `golden_wat` parity comparison. The pilot
parity test still compares pilot bytes with the unchanged default emitter
bytes exactly.

## Residuals

- The private pilot remains direct-route-only; default dispatch and the old
  emitter remain unchanged. No public ownership syntax or promotion was added.
- Existing ARC/list-frame runtime residual statuses from Task 6 remain as
  previously recorded; this fix does not claim runtime counters that the
  runner does not emit.
- The full integration harness and its pre-existing ARC inventory mismatch
  remain outside this code fix and are not reclassified by these focused
  compiler tests.
