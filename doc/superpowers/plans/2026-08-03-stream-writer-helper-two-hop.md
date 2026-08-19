# Two-Hop Stream Writer Lease Implementation Plan

> Bounded G6.2 follow-up. Do not widen public ownership syntax or claim general async call lowering.

**Goal:** Allow a guest producer to transfer its `StreamWriter<u8>` lease through one private async forwarding helper before a final same-typed helper performs the admitted bounded write sequence, sink call, and close.

**Boundary:** The root has one `new_stream<u8>(1)`; the lease is transferred once per call edge; the forwarding helper performs no write and no close; the final helper performs at most three literal `u8` writes, one await per write, one registered sink call, and `defer close(writer)`. A third forwarding hop, dynamic producer loop, arbitrary element type, or general async function call remains rejected.

## Tasks

1. Add red/green plan tests and a check fixture for the two-hop source shape.
2. Extend helper-shape analysis with one guarded forwarding hop while preserving final-helper result/close validation.
3. Reuse the existing descriptor-specific writer frame emitter; add Component lowering and Rust/Wasmtime pending/ready/`Err(pipe)` scripts.
4. Update blocker, roadmap, README, async design, and changelog evidence.
5. Run focused Zig tests, descriptor/runtime gates, full regression, `RUN_WASM=1`, ReleaseSmall smoke, format and shell checks.
