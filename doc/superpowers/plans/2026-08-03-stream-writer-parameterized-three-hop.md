# Parameterized Stream-Writer Three-Hop Implementation Plan

> Bounded G6.2 follow-up. Do not widen public ownership syntax or general
> async-call lowering.

**Goal:** Admit exactly three parameterized forwarding edges while preserving
the fourth-hop and general-resource rejection boundaries.

**Architecture:** Reuse the descriptor-specific `StreamWriterPlan` parser and
existing countdown emitter. Only the explicit forwarding-hop ceiling changes;
the Component export, frame layout, WIT contract, and cleanup protocol remain
unchanged.

**Tech Stack:** Zig compiler, WAT/WIT Component assembly, Rust 2024,
Wasmtime P3 legacy async runtime.

## Global Constraints

- No public `own<T>`, `borrow<T>`, or `ref<T>` syntax.
- No general async-call lowering or arbitrary producer expressions.
- Fourth forwarding hop remains rejected.
- All accepted runtime paths must close the producer stream exactly once.

## Tasks

### Task 1: Red tests

**Files:** `src/build/codegen_component_async_plan.zig`,
`src/build/codegen_component_stream_writer.zig`

- [x] Add positive third-hop plan and emitter tests.
- [x] Add a fourth-hop plan rejection test.
- [x] Run focused tests and observe the expected failure before changing
  production code.

### Task 2: Bounded parser extension

**File:** `src/build/codegen_component_async_plan.zig`

- [x] Replace the hard-coded two-hop loop bound with the named three-hop
  admission constant.
- [x] Run plan and emitter focused tests; verify both third-hop acceptance and
  fourth-hop rejection.

### Task 3: Component and runtime gates

**Files:** `examples/p3-runtime/stream-probe-guest-producer-parameterized-three-hop.do`,
`examples/p3-runtime/wit/stream-probe-guest-producer-parameterized-three-hop.wit`,
`examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_three_hop.sh`,
`examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_three_hop.sh`,
`examples/p3-runtime/rust-host-runner/src/bin/stream_probe_guest_producer_dynamic.rs`

- [x] Add the exact three-hop source and WIT sidecar.
- [x] Validate generated Core/Component shape and reject helper exports.
- [x] Add an explicit runner shape and verify pending/ready/error behavior for
  `count=0/1/3`.

### Task 4: Documentation and full verification

**Files:** `doc/host_abi_blockers.md`, `doc/pending_blocked.md`,
`doc/roadmap_status.md`, `doc/start_here.md`, `README.md`, `CHANGELOG.md`,
`doc/async-design.md`, this plan and its design spec.

- [ ] Record the accepted three-hop boundary and retain fourth-hop/general
  resource exclusions.
- [ ] Run focused gates, full default/WASM regression, ReleaseSmall smoke,
  formatting, shell syntax, and diff checks.
