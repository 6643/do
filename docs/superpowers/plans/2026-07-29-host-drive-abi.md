# Superseded: Host Drive ABI

This historical plan was superseded by the direct Component cancellation
decision on 2026-07-30. Do does not implement a `HostDrive`, operation IDs,
terminal acknowledgements, or a host-operation cancellation protocol.

`@cancel(Future<T>)` is lowered directly through the pinned Component async
task/subtask ABI. Runtime polling and the effect of cancellation on external
systems are runtime and host-API responsibilities. See
`2026-07-30-component-cancellation-lowering.md` for the active, verified
implementation record.
