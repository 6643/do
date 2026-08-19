# Parameterized Stream Writer Helper Reordered Arguments

## Goal

Extend the private `do:stream-probe` guest-producer checkpoint so a
parameterized async helper may declare the existing three parameters in any
order and receive the corresponding source values by name. The public
language remains unchanged and the Component emitter remains descriptor
specific.

## Accepted Shape

The helper has exactly one parameter of each type:

- `StreamWriter<u8>`: the affine writer lease;
- `u64`: the countdown;
- `u8`: the byte value.

The call must pass exactly those three source identifiers, once each. The
argument order follows the helper declaration, so both declaration and call
may be reordered. The helper body still has the existing bounded countdown,
one host sink call, and `defer close(writer)` shape. A private forwarding helper
uses the same rule for its call to the next helper.

## Rejected Shape

The analyzer continues to reject literal arguments, duplicate or missing
arguments, extra arguments, unsupported parameter types, third forwarding
hops, arbitrary async calls, arbitrary producer expressions, and all existing
borrowed/list/variant/nested-resource exclusions. Root `produce` parameters
remain `(count u64, value u8)` in that order.

## Implementation

`codegen_component_async_plan.zig` parses the three helper parameter slots into
an explicit type-kind order, then validates each call argument against the
source identifier corresponding to that kind. It stores the semantic names
already consumed by the emitter; no frame offsets or WIT signatures change.

## Verification

Add unit tests for accepted reordered direct and forwarding helpers and for a
literal rejection. Add a reordered forwarding Do fixture and WIT comparison,
then run the existing pending/ready/error Rust/Wasmtime producer modes. Verify
the full Zig, default/Wasm regression, ReleaseSmall, formatting, shell, JSON,
and diff checks. Update the G6.2 boundary documentation with the exact shape.
