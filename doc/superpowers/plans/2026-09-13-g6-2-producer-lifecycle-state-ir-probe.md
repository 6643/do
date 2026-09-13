# G6.2 Producer Lifecycle State-IR Probe Implementation Plan

**Status:** Completed on 2026-09-13. Tasks 1-4 are implemented; Task 5 release evidence is
recorded below. This completion applies only to this state-IR probe plan/spec.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为现有 12 条 G6.2 producer route 增加一个 test-only、无分配、失败关闭的生命周期 state-IR probe，验证 ownership transfer、list backing release、cancel、反向清理和 exactly-once 约束，同时不改变任何生产产物。

**Architecture:** 新模块只消费 `ProducerContract` 和 `TemplateFact` 的既有事实，并在固定 64-asset 上限内运行纯状态机。测试模块负责最小 route identity table、registry contract 转换和 scenario event trace；生产 compiler 不导入该 probe，模板逐指令真实性继续由现有 runtime audit、Component 和 Rust/Wasmtime gate 证明。

**Tech Stack:** Zig 0.16 std library、现有 `codegen_component_producer_contract.zig`、`codegen_component_producer_mapping_probe.zig`、`p3_async_manifest.zig`、仓库 Zig test harness。

**Spec:** `doc/superpowers/specs/2026-09-13-g6-2-producer-lifecycle-state-ir-probe-design.md`

## Global Constraints

- 只创建 `src/build/codegen_component_producer_lifecycle_state_probe.zig` 及其 test module；不得修改 producer emitter、WAT/WIT template、route matcher 或公开语言能力。
- `ProducerContract` 是 asset topology 和 logical `TerminalContract.cleanup_order` 的唯一来源；`TemplateFact` 是 frame ownership group/encoding 的唯一来源；不得复制 WIT hash、offset、ownership bit 或 cleanup order 到 identity table。
- probe 不读取 lexer、registry、文件或模板，不生成 WAT，不安装 codegen hook，不分配堆内存。
- resource asset 的 transfer disposition 是 `transfer_to_host`；list allocation/payload-list backing 的 disposition 是 `release_after_copy`。
- `0` 是合法资源 handle；absence 只能由 probe 内部显式状态表示，不能以 handle 值作 sentinel。
- 资产实例化顺序固定为 resource leaves、list allocations、payload-list backing；每个 batch group 状态互不别名。
- 64 asset/group bitset 是 test-only 有界上限；超限必须返回 `UnsupportedProbeBound`，不得静默截断或 fallback。
- lifecycle probe 的 logical cleanup order 不等于模板函数体文本调用顺序；模板真实性不在本计划中重复证明。
- 取消只改变生命周期状态，不回滚已经发出的 host side effect，也不把 host-owned resource 改回 guest-owned。
- 所有错误必须 fail closed；不得 catch 后继续主路径，不得把非法 trace 转换为成功 observation。

---

### Task 1: Define lifecycle probe API and RED contract tests

**Files:**
- Create: `src/build/codegen_component_producer_lifecycle_state_probe.zig`
- Create: `src/build/codegen_component_producer_lifecycle_state_probe_test.zig`
- Modify: `src/main.zig: test root imports`

**Interfaces:**
- Consumes: `producer_contract.ProducerContract` and `mapping_probe.TemplateFact` as borrowed values.
- Produces: the public enums/records and `validate_program` signature used by Tasks 2-5.

Required public declarations:

```zig
pub const LifecycleError = error{
    InvalidIdentity,
    InvalidContract,
    InvalidMapping,
    UnsupportedProbeBound,
    InvalidGroupCount,
    InvalidAsset,
    DuplicateAcquire,
    AcquireAfterCancel,
    WriteAfterCancel,
    WriteIncomplete,
    TransferBeforeWrite,
    DuplicateTransfer,
    TransferAfterCancel,
    AssetNotOwned,
    GuestReleaseAfterTransfer,
    DuplicateRelease,
    InvalidReleaseOrder,
    CleanupBeforeAssets,
    CleanupStageMismatch,
    CleanupAfterTerminal,
    DuplicateCancel,
    CancelAfterTerminal,
    TerminalBeforeAssets,
    TerminalBeforeCleanup,
    DuplicateTerminal,
    TraceIncomplete,
};

pub const AssetKind = enum { resource, list_backing };
pub const Disposition = enum { transfer_to_host, release_after_copy };
pub const AssetState = enum { absent, guest_owned, transferred, released };
pub const TerminalState = enum { active, cancel_requested, completed };

pub const AssetId = struct { group_index: u32, asset_index: u32 };

pub const LifecycleEvent = union(enum) {
    acquire: AssetId,
    write_complete: u32,
    transfer_commit: u32,
    cancel: void,
    release: AssetId,
    cleanup_stage: producer_contract.CleanupStage,
    terminal: void,
};

pub const LifecycleProgram = struct {
    route_id: []const u8,
    contract: producer_contract.ProducerContract,
    mapping: mapping_probe.TemplateFact,
    events: []const LifecycleEvent,
};

pub const ProgramReport = struct {
    route_id: []const u8,
    group_count: u32,
    assets_per_group: u32,
    asset_count: u32,
};

pub const TraceObservation = struct {
    acquired_count: u32,
    transferred_count: u32,
    released_count: u32,
    cleanup_stage_count: u32,
    group_count: u32,
    asset_count: u32,
    terminal_state: TerminalState,
};

pub fn validate_program(program: LifecycleProgram) LifecycleError!ProgramReport;
pub fn run(program: LifecycleProgram) LifecycleError!TraceObservation;
```

- [ ] **Step 1: Write failing API tests and register the test root**

  In the test module define a minimal scalar `ProducerContract` and `TemplateFact`, then assert that a valid `LifecycleProgram` returns a `ProgramReport` with route identity and counts. Add tests named exactly:

  - `producer lifecycle state probe accepts a valid program shell`
  - `producer lifecycle state probe rejects an empty route`
  - `producer lifecycle state probe rejects mismatched mapping identity`
  - `producer lifecycle state probe rejects invalid contract`

  Add exactly one test-root import in `src/main.zig` beside the existing producer audit/mapping imports:

  ```zig
  _ = @import("build/codegen_component_producer_lifecycle_state_probe_test.zig");
  ```

  The tests must import the new module and call `validate_program`; before implementation the compile must fail because the module/API does not exist.

- [ ] **Step 2: Run the focused test and capture the expected failure**

  Run:

  ```bash
  cd src
  TMPDIR="$PWD/../.tmp/do-tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" \
  zig test main.zig --test-filter "producer lifecycle state probe"
  ```

  Expected result: compilation/test failure caused by the intentionally missing lifecycle probe declarations. Do not weaken the tests to make this step pass.

- [ ] **Step 3: Add the minimal borrowed API and validation shell**

  Implement the declarations above. `validate_program` must:

  1. reject an empty `route_id` or a route/mapping `route_id` mismatch with `InvalidIdentity`;
  2. call `producer_contract.validate_contract(program.contract)` and map any error to `InvalidContract`;
  3. call `mapping_probe.validate_facts(program.mapping)` and map any error to `InvalidMapping`;
  4. reject an empty mapping ownership table and a zero frame-derived program with `InvalidGroupCount`;
  5. return a `ProgramReport` containing only borrowed identity slices, with no allocation or mutation.

  Keep `run` as a guarded stub returning `TraceIncomplete` until Task 3 defines the transition engine; this makes the API compile without silently accepting events.

- [ ] **Step 4: Re-run the focused tests**

  Run the same focused command. Expected: all four API/validation tests pass, while no production module imports the new probe.

- [ ] **Step 5: Commit the API slice**

  ```bash
  git add src/build/codegen_component_producer_lifecycle_state_probe.zig \
    src/build/codegen_component_producer_lifecycle_state_probe_test.zig
  git diff --cached --check
  git commit -m "Add lifecycle state probe contract"
  ```

### Task 2: Derive the bounded asset model from existing facts

**Files:**
- Modify: `src/build/codegen_component_producer_lifecycle_state_probe.zig`
- Modify: `src/build/codegen_component_producer_lifecycle_state_probe_test.zig`

**Interfaces:**
- Consumes: `LifecycleProgram`, `ProgramReport`, existing contract/mapping validators from Task 1.
- Produces: test-visible fixed-size `AssetSpec[64]`, `Model`, `derive_model_for_test`, `asset_bit`, and deterministic group/schema derivation for Task 3.

The test-visible fixed model is:

```zig
pub const AssetSpec = struct {
    kind: AssetKind,
    disposition: Disposition,
    path: []const []const u8,
};

pub const Model = struct {
    assets: [64]AssetSpec,
    asset_count: u32,
    group_count: u32,
    assets_per_group: u32,
};

pub fn derive_model_for_test(program: LifecycleProgram) LifecycleError!Model;
pub fn asset_bit(model: Model, id: AssetId) LifecycleError!u8;
```

- [ ] **Step 1: Write failing asset derivation tests**

  Add tests that construct the checked-in contracts and mappings and assert:

  - direct owned record: one resource asset with `transfer_to_host`;
  - list-owned record: one resource plus one list-backing asset;
  - nested owned record: one resource asset with the `inner.ticket` path retained;
  - scalar list: one list-backing asset despite zero ownership leaves;
  - batched list: two groups with independent asset ranges;
  - a synthetic 65-asset contract returns `UnsupportedProbeBound`.

  The helper returns the fixed model by value, borrows all path slices, and is not imported by production compiler code. Assert the resource/list disposition and nested path through this view; do not add a route or emitter API.

- [ ] **Step 2: Run the focused tests and verify RED**

  ```bash
  cd src
  TMPDIR="$PWD/../.tmp/do-tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" \
  zig test main.zig --test-filter "producer lifecycle state probe asset"
  ```

  Expected result: failures because model derivation is not implemented.

- [ ] **Step 3: Implement deterministic model derivation**

  Add `build_model(program) LifecycleError!Model` and make `validate_program` call it. The implementation must:

  1. require exactly one mapping ownership group unless `contract.batch_count` is present;
  2. when `batch_count` is present, require it to equal `mapping.ownership.len`;
  3. append one resource `AssetSpec` for each contract ownership leaf in leaf order;
  4. append one `list_backing` `AssetSpec` for each `contract.list_allocations` entry in allocation order;
  5. append one payload-list backing asset for `.payload.list` unless an existing allocation has identical pointer offset, length offset, stride, and max-items;
  6. replicate the schema for each group without aliasing state bits;
  7. reject zero assets, more than 64 total assets, or more than 64 groups;
  8. use only borrowed paths and fixed local arrays.

  `asset_bit(model, AssetId)` must guard both indices and return `InvalidAsset` on out-of-range input. It must never use a handle value as an absence check.

- [ ] **Step 4: Run the focused asset tests**

  Re-run the asset filter. Expected: all derivation, group isolation, scalar-list and bound tests pass; Task 1 tests remain green.

- [ ] **Step 5: Commit the model slice**

  ```bash
  git add src/build/codegen_component_producer_lifecycle_state_probe.zig \
    src/build/codegen_component_producer_lifecycle_state_probe_test.zig
  git diff --cached --check
  git commit -m "Derive bounded producer lifecycle assets"
  ```

### Task 3: Implement the fail-closed lifecycle event runner

**Files:**
- Modify: `src/build/codegen_component_producer_lifecycle_state_probe.zig`
- Modify: `src/build/codegen_component_producer_lifecycle_state_probe_test.zig`

**Interfaces:**
- Consumes: `Model`/`asset_bit` from Task 2 and `LifecycleEvent`/`LifecycleProgram` from Task 1.
- Produces: `run(program) LifecycleError!TraceObservation` and all state transition errors listed in Task 1.

- [ ] **Step 1: Write RED transition tests**

  Add focused tests with fixed event slices for:

  - success: acquire all, write-complete, transfer, logical cleanup stages, terminal;
  - transfer-before-write -> `TransferBeforeWrite`;
  - incomplete pair/triple write -> `WriteIncomplete`;
  - duplicate acquire -> `DuplicateAcquire`;
  - release order swap -> `InvalidReleaseOrder`;
  - guest release after transfer -> `GuestReleaseAfterTransfer`;
  - duplicate release -> `DuplicateRelease`;
  - duplicate transfer -> `DuplicateTransfer`;
  - transfer-before cancel and transfer-after cancel behavior;
  - acquire/write/transfer after cancel -> `AcquireAfterCancel`/`WriteAfterCancel`/`TransferAfterCancel`;
  - release of an absent asset -> `AssetNotOwned`;
  - duplicate/late cancel -> `DuplicateCancel`/`CancelAfterTerminal`;
  - cleanup before asset finalization -> `CleanupBeforeAssets`;
  - cleanup order drift -> `CleanupStageMismatch`;
  - terminal with guest assets -> `TerminalBeforeAssets`;
  - cleanup after terminal -> `CleanupAfterTerminal`;
  - early/duplicate terminal -> `TerminalBeforeCleanup`/`DuplicateTerminal`;
  - out-of-range asset id -> `InvalidAsset`;
  - missing terminal at end -> `TraceIncomplete`.

  Assert observation semantics explicitly: `transferred_count` counts resource assets entering `transferred`; `released_count` counts any asset entering `released`, including list backing on a successful transfer and resource/list release on a pre-transfer failure.

- [ ] **Step 2: Run transition tests and verify RED**

  ```bash
  cd src
  TMPDIR="$PWD/../.tmp/do-tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" \
  zig test main.zig --test-filter "producer lifecycle state probe transition"
  ```

  Expected result: failures because `run` still returns `TraceIncomplete`.

- [ ] **Step 3: Implement the fixed-size state machine**

  In `run`, build the model, then keep local fixed-size state:

  ```zig
  var acquired_mask: u64 = 0;
  var transferred_mask: u64 = 0;
  var released_mask: u64 = 0;
  var written_groups: u64 = 0;
  var transferred_groups: u64 = 0;
  var acquisition_order: [64]u8 = undefined;
  var acquisition_len: u8 = 0;
  var cleanup_cursor: usize = 0;
  var terminal_state: TerminalState = .active;
  ```

  Implement each event with guards in this order:

  1. `acquire`: require active lifecycle, absent asset bit, and unwritten group; set acquired bit and append the global asset bit to acquisition order.
  2. `write_complete`: require active lifecycle and every asset in the group to be guest-owned; set the group bit. A scalar list succeeds because its payload-list backing asset is modeled.
  3. `transfer_commit`: require active lifecycle, written group, and every group asset guest-owned; first validate the whole group, then atomically mark resource assets transferred and list backing assets released. Set the transferred group bit only after all checks pass.
  4. `cancel`: allow once before terminal, set `cancel_requested`, and forbid later acquire/write/transfer. Do not alter transferred/released asset masks.
  5. `release`: require guest-owned asset and require it to be the last still-guest-owned asset in `acquisition_order`; mark released. Return the dedicated transferred/released errors for those states.
  6. `cleanup_stage`: reject terminal state, reject any remaining guest-owned asset, and require the stage to equal `contract.terminal.cleanup_order[cleanup_cursor]`; advance exactly once.
  7. `terminal`: reject duplicate, remaining guest-owned assets, unfinished group transfers/releases, or incomplete cleanup cursor; set `.completed`.

  `release` reverse-order checking must skip assets already finalized by an atomic transfer, but must never allow a newer still-guest-owned asset to remain while an older one is released. Keep all masks and counters local; no heap allocation and no fallback path.

- [ ] **Step 4: Run transition tests and verify GREEN**

  Re-run the transition filter and then the complete focused probe filter:

  ```bash
  cd src
  TMPDIR="$PWD/../.tmp/do-tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" \
  zig test main.zig --test-filter "producer lifecycle state probe"
  ```

  Expected result: all API, model and transition tests pass.

- [ ] **Step 5: Commit the runner slice**

  ```bash
  git add src/build/codegen_component_producer_lifecycle_state_probe.zig \
    src/build/codegen_component_producer_lifecycle_state_probe_test.zig
  git diff --cached --check
  git commit -m "Implement producer lifecycle state runner"
  ```

### Task 4: Add the checked-in 12-route scenario and negative matrix

**Files:**
- Modify: `src/build/codegen_component_producer_lifecycle_state_probe_test.zig`

**Interfaces:**
- Consumes: `run`, `validate_program`, `ProgramReport`, `LifecycleEvent`, and `TraceObservation` from Tasks 1-3; `p3_async_manifest.Registry` and `producer_contract.producer_contract_from_descriptor` from existing modules.
- Produces: test-only `RouteIdentity` table and scenario helpers; no production API or route admission.

- [ ] **Step 1: Write the route identity and scenario RED tests**

  Define this test-only identity shape:

  ```zig
  const RouteIdentity = struct {
      route_id: []const u8,
      descriptor_id: []const u8,
      member: []const u8,
  };
  ```

  Include exactly these 12 rows, each with member `consume-via-stream`:

  ```text
  owned-record-direct       do:g6-2-owned-record-producer@0.1.0
  owned-record-list         do:g6-2-owned-record-list-producer@0.1.0
  owned-record-two-list     do:g6-2-owned-record-two-list-producer@0.1.0
  owned-record-pair         do:g6-2-owned-record-pair-producer@0.1.0
  owned-record-triple       do:g6-2-owned-record-triple-producer@0.1.0
  owned-record-nested       do:g6-2-owned-record-nested-producer@0.1.0
  owned-record-mixed        do:g6-2-owned-record-mixed-producer@0.1.0
  owned-record-parameterized-pair do:g6-2-owned-record-pair-parameterized-producer@0.1.0
  c-min-list                do:g6-2-c-min-producer@0.1.0
  c-min-dynamic-list        do:g6-2-c-min-dynamic-producer@0.1.0
  scalar-list               do:g6-2-scalar-list-producer@0.1.0
  c-min-batched-list        do:g6-2-batched-list-producer@0.1.0
  ```

  Add tests named:

  - `producer lifecycle state probe covers twelve checked-in routes`
  - `producer lifecycle state probe covers transfer-before-failure cleanup`
  - `producer lifecycle state probe covers transfer-after-cancel`
  - `producer lifecycle state probe isolates batched groups`
  - `producer lifecycle state probe doubles observations for repeat`
  - `producer lifecycle state probe rejects incomplete pair and triple groups`

  Before helper implementation, the route filter must fail because the event builders and matrix assertions are absent.

- [ ] **Step 2: Implement test-only scenario builders**

  Use a fixed `[256]LifecycleEvent` buffer and a length counter, not a production allocator. Build these traces from `ProgramReport` and `contract.terminal.cleanup_order`:

  1. `success_trace`: acquire each asset in group order, write-complete each group, transfer each group, emit every logical cleanup stage once, then terminal;
  2. `pre_transfer_failure_trace`: acquire every asset in deterministic asset order, release the still-owned assets in strict reverse order, emit cleanup stages, then terminal;
  3. `post_transfer_cancel_trace`: acquire/write/transfer every group, emit one cancel, cleanup stages, terminal;
  4. `batched_mixed_trace`: complete and transfer group 0, acquire group 1, release group 1 in reverse order, cleanup, terminal.

  Construct each `LifecycleProgram` only while its registry remains alive; all contract/mapping slices must remain borrowed for the call.

- [ ] **Step 3: Implement route assertions**

  Load `@embedFile("p3_async_registry.json")` through `p3_async_manifest.Registry.load(std.testing.allocator, ...)`, find each identity descriptor, convert it with `producer_contract.producer_contract_from_descriptor`, and pair it with `mapping_probe.fact_for_route(route_id)`.

  Assert for every row:

  - `validate_program` succeeds and `report.route_id` equals the identity route;
  - success trace reaches `.completed` with counts derived from the model's resource/list dispositions;
  - pre-transfer failure has zero transfers and releases every acquired asset exactly once;
  - post-transfer cancel has no guest release of transferred resource assets;
  - a second run on a fresh local state returns identical observation values, not a reused state.

  For pair/triple, add partial acquisition followed by `write_complete` and assert `WriteIncomplete`. For the batched route, assert group 0 transfer does not make group 1 assets transferred or released before its own trace events.

- [ ] **Step 4: Run the route and negative matrix**

  ```bash
  cd src
  TMPDIR="$PWD/../.tmp/do-tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" \
  zig test main.zig --test-filter "producer lifecycle state probe"
  ```

  Expected result: all 12 route positive scenarios and dedicated negative scenarios pass. The test must not invoke a producer emitter or compare generated WAT.

- [ ] **Step 5: Commit the matrix slice**

  ```bash
  git add src/build/codegen_component_producer_lifecycle_state_probe_test.zig
  git diff --cached --check
  git commit -m "Cover producer lifecycle routes"
  ```

### Task 5: Document evidence and run release gates

**Files:**
- Modify: `doc/superpowers/specs/2026-09-13-g6-2-producer-lifecycle-state-ir-probe-design.md`
- Modify: `doc/superpowers/plans/2026-09-13-g6-2-producer-lifecycle-state-ir-probe.md`

**Interfaces:**
- Consumes: the complete lifecycle probe and 12-route test matrix from Tasks 1-4.
- Produces: test-root registration, actual evidence counts, and a completed plan/spec closeout; no capability matrix promotion.

- [x] **Step 1: Verify test-root isolation and format**

  Confirm the Task 1 import is present exactly once in `src/main.zig`. Do not import the implementation into production compiler code. Run `zig fmt` only on the new implementation/test files and `src/main.zig`.

- [x] **Step 2: Run the focused gate**

  ```bash
  cd src
  TMPDIR="$PWD/../.tmp/do-tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" \
  zig test main.zig --test-filter "producer lifecycle state probe"
  ```

  Record the exact test count and zero exit status in both the spec and plan.

- [x] **Step 3: Run all repository gates**

  ```bash
  cd src
  TMPDIR="$PWD/../.tmp/do-tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" \
  zig test main.zig

  TMPDIR="$PWD/../.tmp/do-tmp" \
  ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" \
  ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" \
  zig build -Doptimize=ReleaseSmall

  cd ..
  ./src/build/test/run_tests.sh
  git diff --check
  ```

  Expected: focused lifecycle probe green, full Zig suite green, ReleaseSmall exit `0`, integration harness green, and no whitespace errors. Preserve any failed command and mark its evidence as unverified; do not bypass or delete tests.

- [x] **Step 4: Update closeout documentation**

  Mark only this state-IR probe plan/spec as completed with exact observed counts. State explicitly that:

  - the probe validates a reusable logical state model and rejects invalid traces;
  - it does not parse WAT or prove template instruction equivalence;
  - production shared emitter, state IR consumption, route migration, semantic parity, generic producer admission, public ownership syntax, and D2 async expansion remain deferred;
  - `doc/master_plan.md` and capability inventory must not be promoted by this test-only slice.

- [x] **Step 5: Commit the verified closeout**

  ```bash
  git add src/main.zig \
    src/build/codegen_component_producer_lifecycle_state_probe.zig \
    src/build/codegen_component_producer_lifecycle_state_probe_test.zig \
    doc/superpowers/specs/2026-09-13-g6-2-producer-lifecycle-state-ir-probe-design.md \
    doc/superpowers/plans/2026-09-13-g6-2-producer-lifecycle-state-ir-probe.md
  git diff --cached --check
  git commit -m "Verify G6.2 lifecycle state probe"
  ```

#### Observed release evidence (2026-09-13)

- `zig fmt src/main.zig src/build/codegen_component_producer_lifecycle_state_probe.zig src/build/codegen_component_producer_lifecycle_state_probe_test.zig`: exit `0`, empty output.
- Focused `zig test main.zig --test-filter "producer lifecycle state probe"`: `43/43`, exact final line `All 43 tests passed.`, exit `0`. This includes `main.test_0` and 42 probe tests.
- Full `zig test main.zig`: `1654/1654`, exact final line `All 1654 tests passed.`, exit `0`.
- `zig build -Doptimize=ReleaseSmall`: empty output, exit `0`.
- `./src/build/test/run_tests.sh`: `Build Summary: 14/14 steps succeeded; 53/53 tests passed`, `test success`, exit `0`.
- `git diff --check`: empty output, exit `0`.

The probe validates a reusable logical state model and rejects invalid traces. It does not parse
WAT or prove template instruction equivalence. Production shared emitter, state IR consumption,
route migration, semantic parity, generic producer admission, public ownership syntax, and D2
async expansion remain deferred. This test-only slice does not promote `doc/master_plan.md` or
the capability inventory.

## Self-review checklist

- Spec section 3 facts ownership is implemented by the existing contract/mapping inputs and the test-only identity table.
- Spec section 4 asset dispositions, deterministic ordering, 64-bit bound, state transitions, cancellation, cleanup cursor and terminal guards are covered by Tasks 2-3.
- Spec section 5 all 12 routes and dedicated pair/triple/nested/list/batched/scalar scenarios are covered by Task 4.
- Spec section 6 each named fail-closed error has a test in Tasks 1, 3 or 4.
- Spec section 7 proof boundary and existing runtime gate responsibility are recorded in Task 5.
- No task creates a production emitter, imports the probe into codegen dispatch, changes WAT/WIT bytes, or expands public syntax.
- All later task interfaces use the exact names and types introduced earlier; no step relies on an undefined helper.

## Task 5 Self-Review and Concerns

- Facts ownership remains in `ProducerContract`/`TemplateFact`; the test-only identity table only
  connects route, descriptor, and member identities.
- The 64-bit bound, deterministic asset ordering, state transitions, cancellation, cleanup cursor,
  terminal guards, all 12 routes, and named negative cases remain covered by Tasks 1-4.
- No production emitter, codegen dispatch import, WAT/WIT byte change, route migration, semantic
  parity claim, generic admission, public ownership syntax, or D2 expansion was added.
- The logical cleanup order is not a claim about template function-body call order; existing
  Component/Rust/Wasmtime and runtime audit gates retain that responsibility.
- No release gate failed; the failed zsh status-capture wrapper is documented as unverified and
  is not release-gate evidence. The report is at
  `.superpowers/sdd/2026-09-13-g6-2-producer-lifecycle-state-ir-probe/task-5-report.md`.
