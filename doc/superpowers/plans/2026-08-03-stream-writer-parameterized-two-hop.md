# Parameterized Stream-Writer Two-Hop Implementation Plan

> Bounded G6.2 follow-up. Do not widen public ownership syntax or general
> async-call lowering.

## Tasks

- [x] Add positive parser/emitter tests for
  `produce -> forward_stream -> middle_stream -> finish_stream` and preserve
  rejection of a third forwarding edge and reordered parameters.
- [x] Extend parameterized helper analysis to resolve at most two forwarding
  hops and reuse the existing final countdown metadata.
- [x] Add the private Do fixture, WIT sidecar, Component lowering script, and
  Rust/Wasmtime pending/ready/error script.
- [x] Verify focused parser/emitter tests and Component/Rust/Wasmtime gates.
- [x] Run full regression, `RUN_WASM=1`, ReleaseSmall smoke, formatting,
  shell syntax, and `git diff --check`.
- [x] Synchronize roadmap, blocker, async design, README, and changelog while
  retaining the third-hop/general-resource rejection boundary.
