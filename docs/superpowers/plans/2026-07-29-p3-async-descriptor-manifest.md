# Superseded: P3 Async Descriptor Manifest Experiment

The registry parser and pinned descriptor identity work remain relevant, but
the operation-broker portion of this historical plan is superseded. Do does
not expose operation IDs, `request_cancel`, `CancelledAck`, terminal events,
or a descriptor-level cancellation capability.

For the active cancellation contract, `@cancel(Future<T>)` directly lowers to
the pinned Component `subtask.cancel` operation and drops the subtask only
after the ABI terminal status. The compiler does not promise rollback or
compensation of external effects. See
`2026-07-30-component-cancellation-lowering.md`.
