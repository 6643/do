# D2 Socket And G6.2 Next Shape Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a compiler-generated Component target and real Rust/Wasmtime smoke gate for the already-lowered WASI socket `create/bind/drop` slice, then select and independently gate one additional bounded G6.2 producer/resource shape.

**Architecture:** Keep the public Do surface value-oriented (`T | E`) and keep socket resource/variant lowering private to a pinned Component target. The socket target will reuse the existing G6.3 source contract, emit only the measured `create/bind/drop` imports and resource cleanup path, and reject all wider socket operations. G6.2 expansion remains a separate evidence-first gate: a shape enters the registry only after its canonical probe, compiler fixtures, Component assembly, and Rust/Wasmtime ownership matrix are green.

**Tech Stack:** Zig 0.16 compiler, Do fixtures, WAT/WIT, pinned `wasm-tools 1.254.0`, Rust 2024, Wasmtime `47.0.2`, local loopback TCP/UDP resources.

## Global Constraints

- Preserve the existing dirty worktree; do not reset, clean, revert, stage, commit, or push unrelated changes.
- Public Do APIs use `T | E`; do not add public `Result<T,E>`, `own<T>`, `borrow<T>`, or `ref<T>` syntax.
- The socket target admits only `tcp/udp create`, `bind`, and resource `drop`; do not add listen, connect, accept, send, receive, or general socket async lowering.
- Pin the checked-in WASI sockets WIT source by package revision and SHA-256 before using it for lowering; do not invent a Git commit for an uncommitted source file.
- Use one Component and one Wasmtime Store per real-host invocation; assert exact poll/drop/ownership counts and an empty `ResourceTable`.
- Real-host tests use loopback and temporary local resources only; no external network, shared project directory, or irreversible host write.
- Cancellation semantics remain completion-oriented: cancellation ends the task/future and does not roll back an already-issued OS side effect.
- Keep unknown WIT members, malformed variants, unsupported resource shapes, and unmeasured layouts as explicit compiler errors.
- Run the project regression entrypoint `./src/build/test/run_tests.sh`; do not treat a hand-written WAT, Core GC probe, or generic async probe as P3/WASI completion.

---

### Task 1: Reconcile the phase evidence and freeze the baseline

**Files:**
- Modify: `docs/superpowers/specs/2026-08-05-a-g6-2-d2-next-phase-design.md`
- Modify: `doc/start_here.md`
- Modify: `doc/pending_blocked.md`
- Modify: `examples/p3-runtime/d2-real-host-matrix.md`
- Test: repository status and documentation consistency checks

**Interfaces:**
- Consumes: current G6.2 private `variant-resource-stream` gate and current D2 matrix.
- Produces: one consistent statement that G6.2 variant-resource-stream and the bounded D2 socket generated target are green, while broad borrowed/list/async expansion remains out of scope.

- [x] **Step 1: Record the current evidence before editing.**

  Confirm the current statements at `doc/pending_blocked.md:28,78,112,154-155` and `examples/p3-runtime/d2-real-host-matrix.md:12-16`. Preserve the exact distinction between controlled adapter evidence and real-host evidence.

- [x] **Step 2: Remove the stale variant status from the phase design.**

  Change the design text that says `variant-resource-stream` has not entered the registry/compiler. State that the private slice is already green and that the next G6.2 shape requires a new pinned probe.

- [x] **Step 3: Keep A as a maintenance guard, not a new implementation stream.**

  Document that public Result migration is complete; retain `T | E` fixtures and private ABI Result probes without reopening the public syntax.

- [x] **Step 4: Validate the documentation-only change.**

  Run:

  ```bash
  rg -n "not yet.*registry|not.*entered.*compiler|socket create/bind/drop|D2" \
    docs/superpowers/specs/2026-08-05-a-g6-2-d2-next-phase-design.md \
    doc/start_here.md doc/pending_blocked.md examples/p3-runtime/d2-real-host-matrix.md
  git diff --check
  ```

  Expected: no stale claim that the already-green private variant is unregistered; socket create/bind/drop is green while wider socket operations remain blocked.

### Task 2: Pin the socket WIT and Component contract

**Files:**
- Create: `src/build/p3_sockets_wit_manifest.zig`
- Create: `examples/p3-runtime/wit/wasi-sockets-create-bind-drop.wit`
- Create: `examples/p3-runtime/wasi-sockets-create-bind-drop-component.do`
- Test: `src/build/p3_sockets_wit_manifest.zig` unit tests and pinned source validation

**Interfaces:**
- Consumes: `src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/sockets/types.wit` and `src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/deps/sockets/world.wit`.
- Produces: source hash constants, exact operation names, resource names, address layout, error mapping, and a minimal world used by the generated target and Rust bindgen.

- [x] **Step 1: Measure and pin the checked-in WIT source.**

  Record package revision `wasi:sockets@0.3.0-rc-2025-09-16`, `types.wit` SHA-256, and `world.wit` SHA-256 in `p3_sockets_wit_manifest.zig`. Validate the files with `@embedFile` and reject drift with `error.InvalidPinnedSocketsWit`.

- [x] **Step 2: Pin only the admitted operations.**

  Expose facts for `tcp-socket.create`, `udp-socket.create`, `tcp-socket.bind`, `udp-socket.bind`, `[resource-drop]tcp-socket`, and `[resource-drop]udp-socket`. Pin the existing G6.3 mapping: family `4/6`, dual `V4/V6` address payload, and coarse `TcpError`/`UdpError` branches.

- [x] **Step 3: Write the minimal Component world.**

  The WIT fixture must import only the two socket resources and the admitted methods, export a synchronous `run` entry, and contain no stream, future, borrowed resource, listen, connect, accept, send, or receive member.

- [x] **Step 4: Add source-drift and contract tests.**

  Assert the pinned hashes, operation names, resource names, and absence of wider operations. Run:

  ```bash
  cd src && zig test build/p3_sockets_wit_manifest_test.zig
  ```

  Expected: all manifest tests pass and a modified operation signature is rejected.

### Task 3: Add the compiler-generated socket Component target

**Files:**
- Create: `src/build/codegen_component_wasi_sockets.zig`
- Create: `examples/p3-runtime/wasi-tcp-create-bind-drop.core.wat`
- Create: `examples/p3-runtime/wasi-udp-create-bind-drop.core.wat`
- Modify: `src/build/cli.zig`
- Modify: `src/build/run.zig`
- Modify: `src/build/codegen_model.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `src/build/codegen_api.zig`
- Create: `examples/p3-runtime/wasi-sockets-create-bind-drop-negative.do`
- Create: `examples/p3-runtime/wasi-udp-sockets-create-bind-drop-component.do`
- Test: `src/build/cli.zig`, `src/build/codegen_component_wasi_sockets.zig`, target fixtures

**Interfaces:**
- Consumes: the pinned manifest from Task 2 and the existing G6.3 host declarations in `lib/tcp.do` and `lib/udp.do`.
- Produces: `--p3-wasi-sockets-create-bind-drop-component`, `emit_p3_wasi_sockets_create_bind_drop_wit`, and a generated Core WAT with exact socket imports and cleanup.

- [x] **Step 1: Add the special-target CLI plumbing.**

  Add one boolean field and flag, include it in the mutually-exclusive target count, allow `--p3-wit-output`, pass it through `run.zig` and `EmitOptions`, and add parser tests for acceptance, duplicate special targets, and invalid `--component-core` combinations.

- [x] **Step 2: Implement strict source-shape matching.**

  `codegen_component_wasi_sockets.zig` must require the exact host imports, resource declarations, address constructors, and `create -> bind -> drop` control flow from the positive fixture. Return `error.UnsupportedP3WasiSocketsCreateBindDropComponent` for extra operations, missing drop, wrong result arms, unknown address variants, async functions, or unsupported resources.

- [x] **Step 3: Emit only measured WAT/WIT.**

  Emit imports using the pinned canonical names and the manifest's result/resource layout. Keep handles as the existing resource ABI uses them, write/read only the measured result slots, transfer a successful resource exactly once, and drop every owned socket exactly once on both success and forced-error paths.

- [x] **Step 4: Add red/green compiler fixtures.**

  The positive fixture must create one TCP socket, bind an IPv4 loopback address with port `0`, explicitly drop it, and return; the standalone gate will use the same target with an equivalent UDP fixture. The negative fixture must add one unsupported operation (for example `tcp-socket.connect`) and assert the dedicated diagnostic substring.

- [x] **Step 5: Run front-end and codegen tests before runtime work.**

  ```bash
  cd src && zig test main.zig
  ./src/build/test/run_tests.sh
  ```

  Expected: the new positive fixture emits the target markers and the negative fixture fails with the socket-target diagnostic; no existing fixture changes behavior.

### Task 4: Add the Component assembly and validation gate

**Files:**
- Create: `examples/p3-runtime/test_do_wasi_sockets_create_bind_drop.sh`
- Test: generated WAT/WIT, Core Wasm, embedded Component, and Component validation

**Interfaces:**
- Consumes: Task 3's CLI flag and `examples/p3-runtime/wit/wasi-sockets-create-bind-drop.wit`.
- Produces: a reproducible component artifact accepted by pinned `wasm-tools` and ready for Rust bindgen/Wasmtime.

- [x] **Step 1: Build the fixture and emit WIT.**

  Use `DO_LIB_ROOT="$repo_root/lib" "$repo_root/bin/do" build ... --p3-wasi-sockets-create-bind-drop-component --p3-wit-output ...` and fail if the output does not contain the expected socket imports.

- [x] **Step 2: Assemble with pinned tools.**

  Run `wasm-tools parse`, `wasm-tools component embed`, `wasm-tools component new`, and `wasm-tools validate`; assert `wasm-tools --version` is `1.254.0` and pass the exact WIT world name.

- [x] **Step 3: Add negative assembly assertions.**

  Ensure a WIT/source mismatch, missing resource drop import, or unsupported operation fails before the Rust runner is invoked.

- [x] **Step 4: Run the standalone gate.**

  ```bash
  ./examples/p3-runtime/test_do_wasi_sockets_create_bind_drop.sh
  ```

  Expected: Core WAT parse, Component embed/new, and validation all pass; no external host is contacted.

### Task 5: Execute real loopback TCP/UDP host smoke

**Files:**
- Create: `examples/p3-runtime/rust-host-runner/src/bin/wasi_sockets_real.rs`
- Modify: `examples/p3-runtime/rust-host-runner/Cargo.toml`
- Create: `examples/p3-runtime/test_rust_wasi_sockets_real.sh`
- Test: Rust/Wasmtime real-host matrix

**Interfaces:**
- Consumes: the Task 4 Component and its pinned WIT world.
- Produces: `do-p3-wasi-sockets-real` with success and deterministic forced-error modes.

- [x] **Step 1: Add bindgen and host state.**

  Bindgen the generated WIT world. Store `ResourceTable`, TCP/UDP resource values, and counters for `create`, `bind`, `drop`, and errors. Implement only the admitted interfaces; do not add a generic socket adapter.

- [x] **Step 2: Use actual loopback OS resources.**

  On `bind`, create `std::net::TcpListener` or `std::net::UdpSocket` on `127.0.0.1:0` (or `[::1]:0` for the IPv6 fixture) and retain it in the resource table. Dropping the component resource must close the OS socket and remove the table entry.

- [x] **Step 3: Add deterministic error paths.**

  A runner environment flag must force `create` or `bind` to return the pinned coarse error without leaking a resource. The guest path must explicitly drop a successfully-created socket after a bind error.

- [x] **Step 4: Assert exact cleanup.**

  For each protocol, success requires `create=1, bind=1, drop=1, errors=0, table-empty=true`. Forced create error requires `create=1, bind=0, drop=0, table-empty=true`; forced bind error requires `create=1, bind=1, drop=1, table-empty=true`. The runner must fail on any remaining table entry or counter mismatch.

- [x] **Step 5: Run both host modes.**

  ```bash
  ./examples/p3-runtime/test_rust_wasi_sockets_real.sh
  ```

  The script must set the existing Zig linker environment used by other real-host gates, build both TCP and UDP components first, run the Rust binary for each protocol in success and both error modes, and grep exact markers.

### Task 6: Select and pin one additional bounded G6.2 shape

**Files:**
- Create: `docs/superpowers/specs/2026-08-05-g6-2-next-shape-design.md`
- Create: `examples/p3-runtime/g6-2-next-shape-canonical.wat`
- Create: `examples/p3-runtime/wit/g6-2-next-shape.wit`
- Modify: `src/build/p3_async_registry.json` only after the runtime gate is green
- Create: `src/build/codegen_component_g6_2_next_shape.zig`
- Create: `examples/p3-runtime/g6-2-next-shape-component.do`
- Create: `examples/p3-runtime/rust-host-runner/src/bin/g6_2_next_shape.rs`
- Create: `examples/p3-runtime/test_rust_g6_2_next_shape.sh`
- Create: `src/build/test/compile_ok/367_g6_2_next_shape_component.do`
- Create: `src/build/test/compile_ok/367_g6_2_next_shape_component.expect`
- Create: `src/build/test/compile_err/368_g6_2_next_shape_unknown_descriptor.do`
- Create: `src/build/test/compile_err/368_g6_2_next_shape_unknown_descriptor.expect`
- Create: `src/build/test/compile_err/369_g6_2_next_shape_malformed_tag.do`
- Create: `src/build/test/compile_err/369_g6_2_next_shape_malformed_tag.expect`
- Create: `src/build/test/compile_err/370_g6_2_next_shape_duplicate_release.do`
- Create: `src/build/test/compile_err/370_g6_2_next_shape_duplicate_release.expect`
- Test: pinned canonical probe, positive/negative fixtures, Component assembly, cleanup matrix

**Interfaces:**
- Consumes: the current G6.2 capability matrix and existing pinned probe conventions.
- Produces: either one registered, fully gated shape or an explicit blocked record with evidence and recovery conditions; it must never silently widen generic lowering.

- [x] **Step 1: Probe the two admitted candidates in order.**

  First probe a payload-bearing completion error with a bounded string/integer payload. If its canonical tag/payload layout, discard path, and exactly-once cleanup cannot be proven, stop it and probe a second independent list/resource shape. Do not raise forwarding depth, nesting depth, or generic producer expression support as the objective.

- [ ] **Step 2: Write the selected shape's design and stop conditions.**

  Define the exact WIT member, frame/result offsets, ownership transitions, valid/invalid tags, pending/ready/error/early-drop behavior, and the conditions that cause an explicit `Unsupported...` diagnostic.

- [ ] **Step 3: Add red/green compiler coverage.**

  Add one exact positive Do fixture and negative fixtures for an unknown descriptor, malformed tag, duplicate release, unsupported borrow/list/variant field, and any extra operation outside the selected slice.

- [ ] **Step 4: Add the runtime matrix before registry admission.**

  Require one Component/Store per run, pending and ready paths, completion error and early drop, exact resource/future/stream drops, and `ResourceTable::is_empty()` at the end. Keep the registry entry disabled until all assertions pass.

- [x] **Step 5: Stop cleanly when evidence is insufficient.**

  If neither candidate meets the probe criteria, update `doc/pending_blocked.md` with the failed command, observed mismatch, recovery condition, and `can_skip=true`; leave existing green shapes unchanged and do not modify generic lowering.

  Current decision: `can_skip=true`. The payload-error candidate is already a
  bounded HTTP-specific descriptor, and the independent record/list candidate
  already has a registry and runtime gate. A new shape requires a new pinned
  WIT/WAT probe before implementation.

### Task 7: Close the phase with regression and documentation gates

**Files:**
- Modify: `doc/start_here.md`
- Modify: `doc/pending_blocked.md`
- Modify: `examples/p3-runtime/d2-real-host-matrix.md`
- Modify: `doc/master_plan.md`
- Modify: `doc/roadmap_status.md`
- Modify: `CHANGELOG.md`
- Test: complete repository matrix

**Interfaces:**
- Consumes: Task 5's socket real-host result and Task 6's selected-shape result or blocked record.
- Produces: an auditable phase status that does not claim complete WASI/Component support.

- [x] **Step 1: Update the D2 matrix precisely.**

  Change socket `create/bind/drop` from blocked to passed only after Task 5. Keep general filesystem async and external-network HTTP blocked. Do not restore unrelated skips.

- [x] **Step 2: Record the G6.2 boundary.**

  Task 6 is explicitly blocked with `can_skip=true` because no new pinned
  candidate exists; retain the exact private variant-resource-stream green
  descriptor and the recovery condition in `doc/pending_blocked.md`.

- [x] **Step 3: Run the complete verification set.**

  ```bash
  cd src && zig test main.zig
  ./src/build/test/run_tests.sh
  ./examples/p3-runtime/test_do_wasi_sockets_create_bind_drop.sh
  ./examples/p3-runtime/test_rust_wasi_sockets_real.sh
  RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  ./src/build/test/run_release_smoke.sh
  git diff --check
  ```

  Expected: no regression failures, existing WASM smoke remains green, release smoke passes, and all new standalone gates are reproducible.

- [x] **Step 4: Report residual risk explicitly.**

  The final status must still say that public ownership syntax, generic async lowering, broad borrowed/list/variant lowering, complete WASI, and external-network runtime support are not implemented.

## Execution Order

Tasks 1-5 are the recommended D2 socket path and must run in order. Task 6 may begin its probe design after Task 1, but registry/codegen admission is gated independently and must not delay socket work. Task 7 is the final handoff gate and runs only after Task 5 and the Task 6 decision (green or explicitly blocked).

## Verification Evidence Required Before Claiming Completion

1. Pinned WIT package revision, source hashes, and manifest unit tests.
2. Positive and negative Do compiler fixtures.
3. Generated WAT markers plus `wasm-tools 1.254.0` Component assembly/validation.
4. Rust/Wasmtime loopback success and deterministic error output with exact cleanup counters.
5. Full Zig, default regression, WASM regression, release smoke, and `git diff --check` results.
