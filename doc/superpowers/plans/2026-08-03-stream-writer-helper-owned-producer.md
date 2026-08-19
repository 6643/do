# Helper-Owned Stream Writer Producer Implementation Plan

> **For agentic workers:** Execute this plan inline with focused red/green verification. Do not widen the public Do ownership syntax.

**Goal:** Allow the already-admitted same-typed async helper to receive a `StreamWriter<u8>` lease, perform a bounded linear `u8` write sequence, call the registered sink, and finalize the lease.

**Architecture:** Reuse the existing descriptor-specific guest-producer frame pump. Extend source-shape analysis to collect the producer sequence from either the root producer or its one helper, while preserving one root export and one descriptor-selected sink. The helper remains a private source-shape adapter; this is not general async-call lowering.

**Tech Stack:** Zig compiler/WAT, pinned Component async ABI, `wasm-tools`, Rust/Wasmtime runtime gates.

## Global Constraints

- No public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax.
- One capacity-one `StreamWriter<u8>`, at most three literal writes, one await per write, one sink call, and one finalizer.
- The helper must have exactly one `StreamWriter<u8>` parameter and directly call the registered writer descriptor.
- Borrowed record fields remain rejected because the pinned validator rejects recursive result types containing `borrow`.
- Preserve the existing root-owned producer, forwarding helper, and all unrelated dirty-worktree changes.

## Tasks

1. Add a red plan/check fixture where the helper performs the two writes and the root only transfers the writer.
2. Refactor producer-sequence parsing so root-owned and helper-owned sequences produce the same ordered `producer_values` plan.
3. Add lowering and pending/ready/error Rust/Wasmtime assertions for the helper-owned fixture.
4. Update async/WASI blocker docs and run focused tests, full regression, ReleaseSmall smoke, and diff checks.
