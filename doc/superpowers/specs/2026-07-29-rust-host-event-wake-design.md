# Rust Host Event Wake Design

## Goal

Extend the pinned Rust Wasmtime 47.0.2 `wait-for` probe so its first host
Future poll parks until an independently scheduled host event wakes it.

## Design

The component and WIT contract remain unchanged. `wait-for` records its
duration and returns a Future. On its first poll, the Future records one
pending poll and waits on a one-shot completion. The host callback uses the
provided `Accessor::spawn` API to enqueue a host completion task in the same
Store event loop. That task records one external wake and sends the one-shot
completion; the Future then records completion and returns success.

The runner asserts one invocation, one pending poll, one external wake, and
one completion. This proves that `Store::run_concurrent` resumes the guest
after a host-originated readiness event rather than an in-place self wake. The
initial host poll receives a noop Waker and cannot be resumed by retaining that
Waker on another thread.

## Boundaries

- Retain the exact pinned `wait-for` component and one Store.
- Do not link or duplicate Zig `AsyncRuntime`; it is a compiler-side pure
  model, not a published Rust runtime ABI.
- Do not alter compiler lowering, WIT imports, cancellation, resources, or
  the `AsyncLoweringUnavailable` gate.
