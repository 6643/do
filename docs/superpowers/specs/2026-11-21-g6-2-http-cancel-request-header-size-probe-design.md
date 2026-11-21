# G6.2 HTTP Cancellation Request Header Size Probe

**Status:** Closed as a bounded ABI probe; no compiler cancellation admission.

## Decision

2026-11-21: Keep `HTTP-request-header-size` probe-only. Do not promote it to
the generated cancellation emitter. Revisit only with a separately selected
requirement and a complete optional-field and fail-closed test matrix.

## Goal

Establish the canonical discard protocol for the pinned immediate error
`HTTP-request-header-size(Some(field-size-payload))` returned by
`wasi:http/client.send`. The payload contains `field-name: option<string>` and
`field-size: option<u32>`. The probe must prove that the string allocated while
lifting the immediate result is released exactly once before cancellation
returns.

## Approaches

1. Extend the production cancellation emitter immediately. This risks relying
   on unverified canonical offsets and mixes ABI discovery with compiler
   admission.
2. Add a hand-authored Core WAT and typed Rust/Wasmtime host probe. This
   independently checks the pinned result layout and exact string release;
   it is selected because it adds evidence without widening production code.
3. Generalize cancellation cleanup for every `error-code` payload. This has a
   larger ABI and lifecycle surface than the current evidence supports.

## Probe Contract

- Pin `wasi:http@0.3.0-rc-2025-09-16` and use its `HTTP-request-header-size`
  typed variant with `Some(FieldSizePayload { field_name: Some("content-type"),
  field_size: Some(42) })`.
- Use the existing private cancellation service world and canonical result
  scratch `[64,128)`.
- Independently assert result discriminant `Err=1`, error discriminant `22`,
  outer option `Some=1`, field-name option `Some=1`, string bytes and length,
  and field-size option/value `Some(42)`.
- The probe allocator accepts only one allocation of 12 bytes at alignment 1
  and one matching release. Any extra, missing, duplicate, or mismatched call
  traps.
- The Rust/Wasmtime host must observe one consumed request, one ready future
  poll/drop, no response resource, and an empty `ResourceTable`.

## Boundaries

This is a test-only ABI probe. It does not modify compiler admission or the
`@cancel` emitter, does not support other error variants, and does not prove
production HTTP provider behavior. The current decision is to keep this
variant probe-only; a passing probe does not authorize compiler promotion.

## Verification

Run `bash examples/p3-runtime/test_rust_http_payload_cancellation_request_header_size_probe.sh`.
The gate must assemble and validate the Component, execute the immediate typed
error, verify exactly one canonical string allocation/release, and observe the
resource and Future counts above.
