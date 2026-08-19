# G6.2 Producer Lease Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the token-order-only `StreamWriter<T>` ownership check with a
path-sensitive affine lease analysis while preserving every existing bounded
producer/runtime boundary.

**Architecture:** Add a leaf `sema_stream_lease.zig` module containing the
lease state machine, flow environments, and control-flow join helpers. Keep
`sema_async.zig` as the async-range scanner and adapter from tokens to lease
events. The existing descriptor-specific Component emitter remains unchanged;
this phase improves semantic acceptance/rejection only and does not add public
ownership syntax or general async-call lowering.

**Tech Stack:** Zig 0.16 compiler sources, Do semantic fixtures, existing WAT /
WIT / Component regression scripts, pinned `wasm-tools 1.254.0`, Rust 2024 /
Wasmtime legacy runner.

## Global Constraints

- Do not add public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax.
- Do not implement general async-call lowering, arbitrary producer expressions,
  arbitrary stream element layouts, or unrestricted producer leases.
- Do not add a sixth forwarding hop or a seventh nested resource level.
- Preserve the existing descriptor-specific producer Component output byte-for-byte
  where the current tests compare artifacts.
- Preserve exactly-once writer close/abort, stream drop, future cleanup, and
  cancellation behavior in all existing runtime gates.
- Keep `wasm-tools 1.254.0` and the legacy Wasmtime runner unchanged.
- Preserve all unrelated dirty worktree changes; do not reset, clean, commit, or
  push during this phase.
- Every parser/sema change must pass `./src/build/test/run_tests.sh` before handoff.

---

### Task 1: Establish the semantic red-test matrix

**Files:**

- Create: `src/build/sema_stream_lease.zig`
- Create: `src/build/test/err/405_stream_writer_branch_join.do`
- Create: `src/build/test/err/405_stream_writer_branch_join.expect`
- Create: `src/build/test/err/406_stream_writer_loop_exit.do`
- Create: `src/build/test/err/406_stream_writer_loop_exit.expect`
- Create: `src/build/test/err/407_stream_writer_nested_defer_mismatch.do`
- Create: `src/build/test/err/407_stream_writer_nested_defer_mismatch.expect`
- Create: `src/build/test/check/408_stream_writer_both_branch_finalize.do`
- Test: `src/build/sema_stream_lease.zig`

**Interfaces:**

- The new module will expose `LeaseState`, `LeaseEvent`, `LeaseEnv`, and
  `LeaseError` for the later token adapter.
- The initial public API is deliberately small:

```zig
pub const LeaseState = enum { owned, owned_deferred, moved, finalized, maybe };

pub const LeaseEvent = union(enum) {
    write: u32,
    transfer: struct { source: u32, target: u32 },
    helper_transfer: u32,
    finalize: u32,
    register_defer: u32,
};

pub const LeaseEnv = struct {
    states: []LeaseState,

    pub fn apply(self: *LeaseEnv, event: LeaseEvent) LeaseError!void;
    pub fn join(allocator: std.mem.Allocator, left: LeaseEnv, right: LeaseEnv) !LeaseEnv;
    pub fn can_exit(self: *const LeaseEnv) LeaseError!void;
    pub fn deinit(self: *LeaseEnv, allocator: std.mem.Allocator) void;
};
```

- `join` must return `maybe` for any unequal state or defer disposition at the
  same lease slot; it must not silently choose one incoming path.

- [x] **Step 1: Add the failing Do fixtures**

```do
async produce(stop bool, writer StreamWriter<i32>) -> nil {
    if stop {
        close(writer)
    }
}

test "a conditional finalizer must cover every path" {}
```

The fixture expects a path-sensitive lease diagnostic. Add a positive counterpart
where both `if` and `else` call `close` and assert that `do check` succeeds.
Add a loop fixture where a `break` path leaves the writer open and a nested
`defer close(writer)` fixture whose other branch has no defer; both must fail.

- [x] **Step 2: Run the new fixtures before implementing the analyzer**

Run:

```bash
cd src && zig build
cd ..
./bin/do check src/build/test/err/405_stream_writer_branch_join.do
./bin/do check src/build/test/err/406_stream_writer_loop_exit.do
./bin/do check src/build/test/err/407_stream_writer_nested_defer_mismatch.do
./bin/do check src/build/test/check/408_stream_writer_both_branch_finalize.do
```

Expected: the new negative cases fail with the old conservative diagnostic; the
positive two-branch case is the red test for the new behavior. The negative
`.expect` files currently lock that old diagnostic and will be updated only if
Task 4 introduces a more precise error.

- [x] **Step 3: Add unit-test cases for the state table**

The new Zig test file must include executable assertions for these exact
transitions:

```zig
test "writer lease transfer consumes only the source" {
    var states = [_]LeaseState{.owned, .finalized};
    var env = LeaseEnv{ .states = &states };
    try env.apply(.{ .transfer = .{ .source = 0, .target = 1 } });
    try std.testing.expectEqual(LeaseState.moved, env.states[0]);
    try std.testing.expectEqual(LeaseState.owned, env.states[1]);
}

test "writer lease finalization is exactly once" {
    var states = [_]LeaseState{.owned};
    var env = LeaseEnv{ .states = &states };
    try env.apply(.{ .finalize = 0 });
    try std.testing.expectError(error.AlreadyFinalized, env.apply(.{ .finalize = 0 }));
}

test "deferred owner remains writable before scope exit" {
    var states = [_]LeaseState{.owned};
    var env = LeaseEnv{ .states = &states };
    try env.apply(.{ .register_defer = 0 });
    try env.apply(.{ .write = 0 });
}

test "join rejects one-sided finalization" {
    var left_states = [_]LeaseState{.finalized};
    var right_states = [_]LeaseState{.owned};
    const joined = try LeaseEnv.join(std.testing.allocator,
        .{ .states = &left_states }, .{ .states = &right_states });
    var owned_join = joined;
    defer owned_join.deinit(std.testing.allocator);
    try std.testing.expectEqual(LeaseState.maybe, owned_join.states[0]);
}

test "join accepts equal finalized branches" {
    var left_states = [_]LeaseState{.finalized};
    var right_states = [_]LeaseState{.finalized};
    const joined = try LeaseEnv.join(std.testing.allocator,
        .{ .states = &left_states }, .{ .states = &right_states });
    var owned_join = joined;
    defer owned_join.deinit(std.testing.allocator);
    try std.testing.expectEqual(LeaseState.finalized, owned_join.states[0]);
}
```

Run `cd src && zig test build/sema_stream_lease.zig`; before implementation it
failed on the missing `LeaseState` API, which confirmed the red test.

### Task 2: Implement the pure lease state machine

**Files:**

- Modify: `src/build/sema_stream_lease.zig`
- Test: `src/build/sema_stream_lease.zig`

**Interfaces:**

- `LeaseEnv.apply` enforces the following table:

| Event | Required state | Result |
| --- | --- | --- |
| `write` | `owned` or `owned_deferred` | unchanged |
| `transfer` | `owned` | source `moved`, target `owned` |
| `helper_transfer` | `owned` | source `moved` |
| `finalize` | `owned` | `finalized` |
| `register_defer` | `owned` | `owned_deferred` |

- `LeaseError` must include `AlreadyFinalized`, `InvalidState`, `JoinConflict`,
  `Unfinalized`, and `InvalidDeferTransfer`. Existing semantic diagnostics are
  mapped by the token adapter; the pure module must not import `diag.zig`.
- `LeaseEnv.can_exit` accepts `owned_deferred`, `moved`, and `finalized`; it
  rejects `owned` and `maybe`. It also rejects `owned_deferred` if the defer
  scope was already left without running its registration.
- `join` allocates a fresh state slice, checks equal lengths, and copies equal
  states. A differing pair becomes `maybe` and does not mutate either input.

- [x] **Step 1: Implement the state/event types and guarded transitions**

Use an explicit guard before every mutation:

```zig
fn require_owned(state: LeaseState) LeaseError!void {
    return switch (state) {
        .owned => {},
        .owned_deferred => error.InvalidDeferTransfer,
        .moved, .finalized => error.AlreadyFinalized,
        .maybe => error.InvalidState,
    };
}
```

The actual `apply` implementation must preserve the source state when it
returns an error.

- [x] **Step 2: Implement join and exit checks**

`join` must be a pure operation over cloned state slices. `can_exit` must scan
all states and return the first stable error without partially mutating the
environment.

- [x] **Step 3: Run the focused Zig tests**

Run:

```bash
cd src && zig test build/sema_stream_lease.zig
```

Expected: every state transition test passes, including repeated finalization,
one-sided joins, equal finalized joins, and no-mutation-on-error.

### Task 3: Build the token-to-flow adapter and wire the async checker

**Files:**

- Modify: `src/build/sema_stream_lease.zig`
- Modify: `src/build/sema_async.zig`
- No change: `src/build/sema.zig` already calls `sema_async.check_async_ownership`.
- Modify: `src/build/sema_tokens.zig` only when an existing shared
  statement/range helper is genuinely required by the adapter.
- Test: `src/build/sema_stream_lease.zig`

**Interfaces:**

- Add one adapter entry point:

```zig
pub fn check_async_writer_body(
    allocator: std.mem.Allocator,
    tokens: []const lexer.Token,
    params_start: usize,
    params_end: usize,
    body_start: usize,
    body_end: usize,
    helper_transfer: HelperTransferFn,
) !bool;
```

- `HelperTransferFn` only recognizes the existing registered descriptor-specific
  helper shapes. It returns `true` for an approved transfer and `false` for all
  other calls; `false` must not consume a lease.
- `sema_async.check_async_ownership` continues to discover async function/body
  ranges. It delegates writer analysis once per body, while its Future and
  StreamReader checks stay on the existing path.

- [x] **Step 1: Extract lexical statements without changing parser syntax**

Use the existing token matching helpers for `{}`, `()`, and `<>`. Recognize only
the statements already supported by the frontend: block, `if`/`else`, `loop`,
`break`, `continue`, `return`, `defer close(writer)`, `close`, `abort`,
same-typed writer binding, approved helper transfer, and ordinary non-lease
statements.

- [x] **Step 2: Evaluate each block into `Continue`/`Return`/`Break`/`ContinueLoop`**

For an `if` without `else`, join the analyzed branch with the incoming
environment. For a loop, analyze the body once with the incoming environment,
join `continue` with the loop header, and require every `break`/fallthrough
path to satisfy `can_exit` before leaving the loop. Do not infer arbitrary
loop invariants; a conflicting state is `maybe` and is rejected.

- [x] **Step 3: Apply lexical defer scopes in LIFO order**

Register `defer close(writer)` in the current scope. On normal scope exit and
all terminating flows, apply the registration exactly once. A writer moved out
of a scope that owns its defer registration must report `InvalidDeferTransfer`;
the adapter must not silently transfer cleanup to a different scope.

- [x] **Step 4: Replace the old writer-only scan**

Remove the `block_depth`/`has_prior_return` writer decisions from
`check_async_body` and delegate to the new adapter. Keep the existing reader and
Future binding loops intact. Preserve the current helper classification and all
existing unsupported-form errors.

- [x] **Step 5: Run focused semantic checks**

Run:

```bash
cd src && zig test build/sema_stream_lease.zig
cd .. && zig build
./bin/do check src/build/test/check/351_stream_writer_close_finalizes_lease.do
./bin/do check src/build/test/check/352_stream_writer_defer_close_finalizes_lease.do
./bin/do check src/build/test/check/353_stream_writer_transfer_finalizes_new_owner.do
./bin/do check src/build/test/check/408_stream_writer_both_branch_finalize.do
./bin/do check src/build/test/err/405_stream_writer_branch_join.do
./bin/do check src/build/test/err/406_stream_writer_loop_exit.do
./bin/do check src/build/test/err/407_stream_writer_nested_defer_mismatch.do
```

Expected: all existing positive lease fixtures and the new both-branch fixture
pass; every new negative fixture fails with its stable lease diagnostic; no
fixture generates a synchronous artifact as a fallback.

### Task 4: Freeze diagnostics and compatibility fixtures

**Files:**

- Modify: `src/build/diag.zig`
- Modify: `src/build/test/err/350_stream_writer_conditional_finalization.expect`
- Modify: `src/build/test/err/405_stream_writer_branch_join.expect`
- Modify: `src/build/test/err/406_stream_writer_loop_exit.expect`
- Modify: `src/build/test/err/407_stream_writer_nested_defer_mismatch.expect`
- Create: `src/build/test/err/409_stream_writer_deferred_transfer.do`
- Create: `src/build/test/err/409_stream_writer_deferred_transfer.expect`
- Create: `src/build/test/err/410_stream_writer_maybe_use.do`
- Create: `src/build/test/err/410_stream_writer_maybe_use.expect`
- Test: `src/build/test/run_tests.sh`

**Interfaces:**

- Add stable diagnostics only for states that cannot be represented by the
  existing errors:

  - `StreamWriterLeasePathConflict`: branch/loop join does not prove one
    cleanup state for every reachable path.
  - `StreamWriterDeferredTransfer`: a writer carrying a lexical defer cleanup
    is moved outside that cleanup scope.

- Reuse `StreamWriterAlreadyFinalized` for `moved`/`finalized` operand use and
  `StreamWriterLeaseDropped` for an `owned` lease at an exit. A conflicting
  `maybe` join uses `StreamWriterLeasePathConflict`; fixture 350 is refined to
  that diagnostic while unrelated legacy diagnostic substrings remain stable.

- [x] **Step 1: Add the diagnostic enum/text mappings**

Update both diagnostic rendering tables in `src/build/diag.zig`, then run one
negative fixture per new diagnostic to freeze the `.expect` substring.

- [x] **Step 2: Add deferred-transfer and maybe-use fixtures**

```do
async produce(writer StreamWriter<i32>) -> nil {
    defer close(writer)
    next StreamWriter<i32> = writer
}

test "a deferred writer cannot leave its cleanup scope" {}
```

The second fixture must use a writer after a branch join whose states differ;
it must fail at the writer operand, not at an unrelated return statement.

- [x] **Step 3: Run the complete default regression**

Run the standard regression with explicit cache paths in quota-constrained
environments:

```bash
ZIG_LOCAL_CACHE_DIR=/home/_/._/do/.tmp/do-tmp/debug-zig-cache \
ZIG_GLOBAL_CACHE_DIR=/home/_/._/do/.tmp/do-tmp/debug-zig-gcache \
  ./src/build/test/run_tests.sh
```

Expected: `pass=1065 fail=0 skip=3`, with all new `.expect` files matched.

### Task 5: Prove lowering stability and update project status

**Files:**

- No production change expected: `src/build/codegen_component_stream_writer.zig`.
- Modify: `src/build/test/run_tests.sh`; it discovers numbered fixtures and
  now honors explicit Zig cache directory overrides.
- Modify: `doc/spec_rules.md`
- Modify: `doc/async-design.md`
- Modify: `doc/pending_blocked.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/start_here.md`
- Modify: `CHANGELOG.md`

**Interfaces:**

- Documentation must state that path-sensitive producer-lease analysis is
  complete for the phase, while general producer leases, arbitrary async calls,
  arbitrary producer expressions, borrowed resource fields, and broader
  runtime shapes remain pending.
- Do not mark G6.2 fully closed and do not remove the pinned borrowed-resource
  validator blocker.

- [x] **Step 1: Run existing producer Component/Rust gates**

Run the already verified gates without changing their scripts:

```bash
bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_five_hop.sh
bash examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_five_hop.sh
bash examples/p3-runtime/test_do_record_resource_stream_nested_six_level_probe_lowering.sh
bash examples/p3-runtime/test_rust_record_resource_stream_nested_six_level_probe.sh
```

Expected: all pass with the same WAT/WIT export counts, frame offsets, cleanup
counts, and empty resource tables as the current baseline.

- [x] **Step 2: Update status documents from evidence only**

Record the new semantic gate and leave the following explicit: no public
ownership syntax, no general async-call lowering, no arbitrary producer
expression, and no claim of real P3 host runtime completion.

- [x] **Step 3: Check documentation and source boundaries**

Run:

```bash
rg -n 'own<T>|borrow<T>|ref<T>|general async|producer lease|StreamWriter' \
  doc README.md CHANGELOG.md src/build/sema_async.zig src/build/sema_stream_lease.zig
git diff --check
```

Expected: every new mention agrees with the design and no public ownership
syntax is added to grammar or source examples.

### Task 6: Full verification and handoff

**Files:**

- Verify: all files touched by Tasks 1-5

- [x] **Step 1: Run focused Zig tests**

```bash
cd src
zig test build/sema_stream_lease.zig
zig test main.zig
```

Expected: the new lease tests and the full Zig unit suite pass.

- [x] **Step 2: Run default and WASM regressions**

```bash
cd ..
ZIG_LOCAL_CACHE_DIR=/home/_/._/do/.tmp/do-tmp/debug-zig-cache \
ZIG_GLOBAL_CACHE_DIR=/home/_/._/do/.tmp/do-tmp/debug-zig-gcache \
  ./src/build/test/run_tests.sh
ZIG_LOCAL_CACHE_DIR=/home/_/._/do/.tmp/do-tmp/debug-zig-cache \
ZIG_GLOBAL_CACHE_DIR=/home/_/._/do/.tmp/do-tmp/debug-zig-gcache \
RUN_WASM=1 ./src/build/test/run_tests.sh
```

Expected: both report `fail=0`; the existing skip count is unchanged.

- [x] **Step 3: Run release smoke and syntax checks**

```bash
ZIG_LOCAL_CACHE_DIR=/home/_/._/do/.tmp/do-tmp/zig-cache \
ZIG_GLOBAL_CACHE_DIR=/home/_/._/do/.tmp/do-tmp/zig-gcache \
DO_RELEASE_SMOKE_TMP_DIR=/home/_/._/do/.tmp/do-tmp/release-smoke \
  bash src/build/test/run_release_smoke.sh
for script in \
  examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_five_hop.sh \
  examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_five_hop.sh; do
  bash -n "$script"
done
git diff --check
```

Expected: ReleaseSmall smoke, shell syntax, and whitespace checks pass.

- [x] **Step 4: Record residual risk**

The handoff must explicitly list the next separate design gate: a general
producer runtime shape requires ownership-state semantics, resumable async-call
lowering, cancellation interaction, and Component/Rust/Wasmtime cleanup proof.
Do not describe this phase as complete G6.2 or complete WASI.

## Deferred After This Plan

- General producer-lease runtime lowering and arbitrary async-call composition.
- Public `own<T>`, `borrow<T>`, `ref<T>`, pointer, or reference syntax.
- Borrowed/list/variant resource fields and arbitrary nested resource layouts.
- Payload-bearing completion errors blocked by the pinned task-return runtime.
- D2 real host I/O and host scheduler work.
