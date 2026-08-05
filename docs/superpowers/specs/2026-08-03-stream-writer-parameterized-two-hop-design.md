# Parameterized Stream-Writer Two-Hop Design

## Goal

Extend the private `do:stream-probe@0.1.0` producer adapter to accept exactly
two parameterized forwarding edges before the already verified countdown
helper:

`produce -> forward_stream -> middle_stream -> finish_stream`

## Boundary

- Every forwarding edge passes the direct parameters `(writer, count, value)`
  in that order and awaits exactly one same-typed result.
- `forward_stream` and `middle_stream` perform no write, close, stream
  creation, branch, or second call.
- `finish_stream` remains the existing zero-pre-guarded `(u64, u8)` countdown
  helper with `defer close(writer)` and the registered sink call.
- The Component exports only `produce`; frame offsets remain 52 (`count`) and
  60 (`value`).
- A third forwarding edge, reordered/literal arguments, general async calls,
  arbitrary producer expressions, and borrowed/nested/variant resources remain
  rejected.

## Implementation

The source-shape parser resolves the helper chain iteratively with a maximum
of two forwarding hops. It reuses the existing final-helper countdown parser,
so the emitter and runtime protocol remain unchanged.

## Verification

The gate includes parser/emitter positive and negative tests, a WIT sidecar
comparison, Core/Component validation, and Rust/Wasmtime pending/ready/error
probes for `count=0/1/3` and `value=90`. Each mode must observe one host
callback, one stream drop, and the expected ordered bytes.
