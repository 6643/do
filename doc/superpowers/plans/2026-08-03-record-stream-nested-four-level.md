# Four-Level Nested Owned Resource Record Stream Plan

> Bounded G6.2 follow-up. Do not widen public ownership syntax or general
> async-call lowering.

## Tasks

### 1. Manifest and emitter boundary

- [x] Add fourth-level positive parser, registry, and emitter tests.
- [x] Raise the recursive admission ceiling to four container levels.
- [x] Keep the fifth-level rejection, multi-child, mixed-shape, and borrow
  validation tests.

### 2. Component and runtime gates

- [x] Add the private four-level registry descriptor and WIT sidecar.
- [x] Add Do lowering and Component assembly/validation gates.
- [x] Add the Rust/Wasmtime pending/ready/error runner variant.
- [x] Verify exactly-once resource, stream, future cleanup and empty table.

### 3. Documentation and regression

- [x] Synchronize the G6.2 blocker and roadmap entry.
- [x] Run focused tests, full default/WASM regression, ReleaseSmall smoke,
  targeted formatting, shell syntax, and diff checks.
- [ ] Full `cargo fmt --check` remains noisy because unrelated pre-existing
  dirty Rust files in the shared worktree use a different formatter version;
  the changed `record_resource_stream_probe.rs` passes `rustfmt --check`.
