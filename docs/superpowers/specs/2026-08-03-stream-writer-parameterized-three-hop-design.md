# Parameterized Stream-Writer Three-Hop Design

## Goal

Admit one private parameterized producer chain with three forwarding edges:

`produce -> entry_stream -> forward_stream -> middle_stream -> finish_stream`

The final helper keeps the existing `(StreamWriter<u8>, u64, u8)` countdown
producer behavior and closes the transferred writer exactly once.

## Boundary

- Every forwarding helper passes `(writer, count, value)` in the callee's
  declared semantic order and awaits exactly one same-typed result.
- Forwarding helpers perform no write, close, stream creation, branch, or
  second call.
- Only `produce` is exported in the Component; frame offsets remain 52 and 60.
- A fourth forwarding edge, reordered/literal forwarding arguments, arbitrary
  async calls, dynamic producer expressions, and borrowed/nested/variant
  resources remain rejected.
- This gate does not add public `own<T>`, `borrow<T>`, or `ref<T>` syntax.

## Implementation

The descriptor-specific parameterized helper resolver raises its explicit
forwarding-edge ceiling from two to three. The existing countdown parser,
frame emitter, WIT shape, and runtime cleanup protocol are reused unchanged.

## Verification

The gate includes plan/emitter positive tests, a fourth-hop negative test, an
exact WIT sidecar comparison, Core/Component validation, and Rust/Wasmtime
pending/ready/error probes for `count=0/1/3` and `value=90`. Each runtime mode
must observe one host callback, ordered bytes, and one stream drop.
