# G6.2 WASI HTTP Error Payload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve every payload-bearing `error-code` variant from the pinned `wasi:http/client.send` descriptor through the Do Component boundary.

**Architecture:** Extend the registered descriptor's measured error-variant facts and the dedicated HTTP error-result lowering. Keep admission tied to the pinned package, descriptor signature, discriminants, layout, and field kinds. Do not add generic WIT payload lowering or new source matching syntax.

**Tech Stack:** Zig compiler, pinned WIT/CANONICAL ABI fixtures, WAT Component lowering, Rust/Wasmtime runtime harness.

**Spec:** `docs/superpowers/specs/2026-11-21-g6-2-http-error-payload-completeness-design.md`

## Global Constraints

- Support only the pinned `wasi:http@0.3.0-rc-2025-09-16` `client.send` `error-code` descriptor.
- Preserve the exact discriminant and payload for every supported case; unknown cases fail closed or trap.
- Derive layout from canonical probe evidence, not WIT source syntax alone.
- Preserve existing `DNS-error`, `internal-error`, success, cancellation, and payload-discard behavior.
- Keep lifecycle cleanup exactly once for every lifted string/record payload.

## Review Focus

- An absent optional payload must not read uninitialized payload storage; pin None/Some behavior in the ABI/runtime gate.
- Nested optional record fields must not overlap or overwrite each other; pin all-None, all-Some, and single-field-Some layouts.
- Unknown variant/tag or changed descriptor/layout must fail closed; pin negative admission/lowering coverage.
- Payload strings must be copied and released exactly once; pin runtime resource and allocation cleanup.
- Existing DNS/internal payloads and pending/ready/cancel routes must remain stable; pin regression coverage.

## File Map

- Modify `src/build/p3_async_registry.json` with canonical variant discriminants and payload layouts.
- Modify `src/build/codegen_component_wasi_http.zig` to validate and lower the registered payload families.
- Add focused canonical WIT/Core WAT fixtures under `examples/p3-runtime/` for payload combinations and invalid layouts.
- Extend the existing Rust/Wasmtime G6.2 gates and `src/build/test/test_harness.zig` for exact values and cleanup.
- [x] Update `doc/wit/wasi_p3_lowering.md`, `examples/p3-runtime/README.md`, and G6.2 status documents after the corresponding runtime gates passed.

### Task 1: Canonical Payload ABI Inventory

**Interfaces:** Record all 15 payload-bearing variants from the pinned WIT, including discriminant, core completion words, payload byte span, and each field offset/kind. Existing emitter consumes registry `error_variants` entries with `variant`, `discriminant`, `byte_size`, and field facts.

- [x] Capture canonical Core WAT/WIT evidence for each payload family and validate the Component form.
- [x] Add registry facts only where evidence establishes the exact layout; leave unsupported facts rejected.
- [x] Check the inventory against the pinned `types.wit` and descriptor WIT hash.

### Task 2: Scalar and Optional Payload Families

**Interfaces:** Extend the HTTP result emitter in `src/build/codegen_component_wasi_http.zig` to lower optional integer and optional string payload cases using the registered facts. Preserve the existing `render_http_error_variant_lowering` entry point.

- [x] Cover `option<u64>`, `option<u32>`, `option<u8>`, and `option<string>` payload families.
- [x] Validate absent/present tags before reading payload words; copy present strings and release their lifted storage exactly once.
- [x] Reject malformed option tags and any mismatched field offsets or core-word shape.
- [x] Preserve existing DNS/internal cases byte-for-byte where their emitted ABI is unchanged.

### Task 3: Nested Optional Record Families

**Interfaces:** Add measured layouts and lowering for `field-size-payload`, `DNS-error-payload`, and `TLS-alert-received-payload`, including optional nested fields.

- [x] Lower all-None, all-Some, and single-field-Some combinations using the measured record offsets and padding.
- [x] Ensure absent fields do not load or release stale pointers.
- [x] Reject layout drift, invalid nested option tags, and missing required record fields.

### Task 4: Runtime Lifecycle and Bounded Closeout

**Interfaces:** Keep the current pinned client-send WIT world and Wasmtime runner architecture; expose exact returned Do error variant/payload values to the existing runtime assertions.

- [x] Exercise every payload variant through the runtime gate, including pending and ready completion paths.
- [x] Verify exactly-once string/payload cleanup, no leaked response resource, and empty `ResourceTable` after terminal paths.
- [x] Keep unknown and non-payload variant behavior explicit and fail-closed.
- [x] Update capability docs and G6.2 status only after all gates pass; state the pinned-version boundary precisely.

## Plan Self-Review

- Spec coverage: all listed scalar, string, nested record, negative drift, runtime lifecycle, and closeout requirements map to Tasks 1-4.
- Type/interface consistency: registry facts feed the existing HTTP lowering; runtime gates exercise the generated component without changing source type syntax.
- Review focus: all five uncovered input classes are assigned to Tasks 2-4.
- Scope: implementation remains limited to the current pinned `client.send` error type; no generic WIT lowering or source pattern-matching feature is introduced.
