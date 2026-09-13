# G6.2 Shared Emitter and Lifecycle State-IR Pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** 为 `do:g6-2-owned-record-producer@0.1.0 / consume-via-stream` 建立一个私有、可回滚的 shared emitter pilot，以 bounded `CanonicalFrameMap` 和静态 `LifecycleStateIR` 组装出与既有 direct-record WAT 完全相同的字节。

**Architecture:** 将 mapping probe 中的纯事实记录提取到 production leaf module；route adapter 只提供已经验证的 direct route facts、fragment source spans 和 WIT hash。state-IR 与 fragment assembler 均为无堆分配的纯构造/校验，只有最终 WAT buffer 使用调用方 allocator；private pilot 单独调用 shared emitter，默认 `--p3-async-component` dispatch 继续使用旧模板。

**Tech Stack:** Zig 0.16 std library、现有 `ProducerContract`/P3 manifest、WAT template fragments、当前 `wasm-tools`、当前 Wasmtime/Rust runner、仓库 Zig 与 integration harness。

**Spec:** `doc/superpowers/specs/2026-09-13-g6-2-shared-emitter-state-ir-pilot-design.md`

## Global Constraints

- 只迁移一个 direct owned-record route：`do:g6-2-owned-record-producer@0.1.0 / consume-via-stream`，payload 为 `ResourceEntry { ticket: own<ticket> }`，stream capacity 为 `1`。
- 不改变默认 dispatch、既有 WAT/WIT bytes、descriptor/WIT hash、diagnostic、runtime counter、capability inventory 或公开语言能力。
- 不新增或公开 `own<T>`、`borrow<T>`、`ref<T>`、`borrow_mut<T>` 或 lifetime syntax；不实现 generic/arbitrary producer、borrowed/variant payload、通用 filesystem/HTTP async。
- `ProducerContract` 是 ownership/list/terminal facts 的唯一来源；route facts 是 measured frame/binding/marker/lifecycle facts 的唯一来源；emitter 不读取 lexer、registry、文件系统或任意 WAT。
- 所有 map/IR/fragment validation 不分配、不修改借用输入；只有最终输出 WAT 由调用方 allocator 拥有。
- `0` 是合法 canonical offset 与 resource handle；缺失只能用显式空 entry 表示，不能以数值零作 sentinel。
- 每个 pilot admission、mapping、fragment coverage、IR invariant 或 byte-parity 失败都必须 fail closed；不允许静默 fallback 到旧 emitter。
- 本计划的 release 验证使用仓库本地 Zig cache；系统 linker/cache 缺失必须单独记录，不能伪装成源码通过。

## Files and Boundaries

- Create: `src/build/codegen_component_producer_facts.zig` — production-only immutable fact records、identity validation 和与 test probe 的类型兼容层。
- Modify: `src/build/codegen_component_producer_mapping_probe.zig` — 改为复用 facts 类型与 validator，保留现有 12-route test-only table/API。
- Create: `src/build/codegen_component_producer_state_ir.zig` — `CanonicalFrameMap`、bounded lifecycle asset/state records、构造和 invariant validator。
- Create: `src/build/codegen_component_producer_fragments.zig` — named fragment descriptor、coverage/order/marker validator 和 bounded assembly。
- Create: `src/build/codegen_component_producer_emitter.zig` — `PilotFacts`/`PilotInput`、private pilot emitter、hash/admission/parity guards。
- Modify: `src/build/codegen_component_owned_record_stream_producer.zig` — direct route adapter 和仅供 test/compiler 内部使用的 pilot entry；旧 `emit_component_wat` 保持原行为。
- Create: `src/build/codegen_component_producer_state_ir_test.zig` — map/IR positive and negative tests。
- Create: `src/build/codegen_component_producer_fragments_test.zig` — fragment table and assembly tests。
- Create: `src/build/codegen_component_producer_emitter_test.zig` — direct route pilot parity/admission tests。
- Modify: `src/main.zig: test root imports` — 仅导入新增 test modules，不把 pilot 接入默认 CLI dispatch。
- Modify: `doc/superpowers/specs/2026-09-13-g6-2-shared-emitter-state-ir-pilot-design.md` — 记录实际 gate evidence 和 residual boundary。
- Modify: this plan — 标记完成的单元、命令输出和未验证项。

### Task 1: 提取 production immutable facts 并保持 probe 兼容

**Files:**
- Create: `src/build/codegen_component_producer_facts.zig`
- Modify: `src/build/codegen_component_producer_mapping_probe.zig`
- Modify: `src/build/codegen_component_producer_mapping_probe_test.zig`

**Interfaces:**
- Consumes: 现有 `TemplateFact`/`FrameFact`/`BindingFact`/`OwnershipFact`/`LifecycleFact`/`MarkerFact` 字段和 `ProducerContract` identity。
- Produces:

```zig
pub const FactError = error{
    InvalidIdentity,
    InvalidFrameSize,
    InvalidFrame,
    FrameOutside,
    FrameMisaligned,
    FrameOverlap,
    InvalidOwnership,
    OwnershipStateOutsideFrame,
    InvalidBinding,
    BindingOutsidePayload,
    BindingOutsideFrame,
    BindingOverlap,
    MissingLifecycle,
};

pub const FrameRole = enum { result_tag, result_payload, waitable, readable, writable, ownership_state, subtask, pending_write, mode, payload, resource_handle, list_pointer, list_length, list_element_area };
pub const FrameFact = struct { name: []const u8, offset: u32, width: u32, alignment: u32, role: FrameRole };
pub const OwnershipEncoding = enum { scalar, mask, batched_scalar };
pub const OwnershipFact = struct { name: []const u8, encoding: OwnershipEncoding, state_offset: u32, guest_value: u32, transferred_value: u32, released_value: u32 };
pub const CanonicalBinding = struct { name: []const u8, canonical_offset: u32, payload_size: u32, frame_offset: u32, width: u32 };
pub const LifecycleAnchor = struct { name: []const u8, required_text: []const []const u8, ordered_anchors: []const []const u8 };
pub const MarkerBinding = struct { name: []const u8, expected_value: ?[]const u8 = null };
pub const RouteFrameFacts = struct { route_id: []const u8, descriptor_id: []const u8, frame_size: u32, frames: []const FrameFact, ownership: []const OwnershipFact, bindings: []const CanonicalBinding, lifecycle: []const LifecycleAnchor, markers: []const MarkerBinding };

pub fn validate_route_facts(facts: RouteFrameFacts) FactError!void;
```

- [x] **Step 1: Add the production fact declarations and fail-closed interval helpers.**

  `validate_route_facts` must reject empty identities, zero frame/field widths, misalignment, out-of-frame fields, binding ranges outside payload/frame, overlapping intervals, invalid ownership values and empty lifecycle entries. It must accept offset `0` and handle value `0`; no helper may use either as absence.

- [x] **Step 2: Run the mapping probe tests before the compatibility edit.**

  Run:

  ```bash
  cd src
  TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig test main.zig --test-filter "producer canonical frame probe"
  ```

  Expected: the existing route table remains green before the type migration; retain the output as the baseline for this task.

- [x] **Step 3: Make mapping probe reuse the production types and validator.**

  Replace duplicate declarations with aliases/re-exports from `codegen_component_producer_facts.zig`; keep the existing `ProbeError`, marker scanning, decomposition, canonical parity probe, 12-entry table and test-visible field names. Map `FactError` to `ProbeError` at the test-only boundary so existing diagnostics and tests remain stable.

- [x] **Step 4: Add a type-identity and zero-offset regression test.**

  Validate one direct route with frame/binding/ownership entries at offset `0`, assert the fact validator accepts it, and assert `mapping_probe.validate_facts` returns the same report. Mutate one interval and assert both paths fail closed.

- [x] **Step 5: Run focused tests, format, and commit the facts slice.**

  Run the focused command again, then `zig fmt src/build/codegen_component_producer_facts.zig src/build/codegen_component_producer_mapping_probe.zig src/build/codegen_component_producer_mapping_probe_test.zig` and `git diff --check`. Commit only the three task files with subject `Extract G6.2 producer facts`.

### Task 2: Build and validate bounded `CanonicalFrameMap`

**Files:**
- Create: `src/build/codegen_component_producer_state_ir.zig`
- Create: `src/build/codegen_component_producer_state_ir_test.zig`
- Modify: `src/main.zig: test root imports`

**Interfaces:**
- Consumes: `facts.RouteFrameFacts`, `producer_contract.ProducerContract`, and the pilot route facts assembled by the route adapter.
- Produces:

```zig
pub const MapError = error{
    InvalidIdentity,
    InvalidContract,
    InvalidFacts,
    InvalidFrame,
    InvalidBinding,
    BindingOverlap,
    OwnershipStateOverlap,
    InvalidMarker,
    InvalidLifecycle,
    BatchAlias,
    UnsupportedBound,
    ZeroSentinel,
};

pub const CanonicalFrameMap = struct {
    route_id: []const u8,
    descriptor_id: []const u8,
    frame_size: u32,
    fields: []const facts.FrameFact,
    bindings: []const facts.CanonicalBinding,
    ownership: []const facts.OwnershipFact,
    markers: []const facts.MarkerBinding,
    lifecycle: []const facts.LifecycleAnchor,
};

pub const FrameMapInput = struct {
    route_id: []const u8,
    descriptor_id: []const u8,
    contract: producer_contract.ProducerContract,
    frame_facts: facts.RouteFrameFacts,
};

pub fn build_frame_map(input: FrameMapInput) MapError!CanonicalFrameMap;
pub fn validate_frame_map(map: CanonicalFrameMap, contract: producer_contract.ProducerContract) MapError!void;
```

  `FrameMapInput` is the allocation-free, route-local input used by this module. Task 5's `PilotFacts` must construct it by value from its borrowed `contract` and `frame_facts`; it must not introduce a second fact table or make the state-IR module import the emitter module.

- [x] **Step 1: Write RED map tests.**

  Add a valid direct route case plus failures for empty route/descriptor identity, contract descriptor mismatch, frame overlap, binding overlap/out-of-bounds, duplicate ownership state, empty/duplicate marker facts, lifecycle anchor drift, batched pointer alias, a 65-asset/group bound, and a zero absence sentinel. `FrameMapInput` has no template observation by design; expected-vs-observed marker byte mismatch is tested by Task 4/5's fragment/pilot gate. Assert that no map fixture is accepted by silently dropping a field.

- [x] **Step 2: Run the map filter and capture the expected RED result.**

  ```bash
  cd src
  TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig test main.zig --test-filter "producer canonical frame map"
  ```

  Expected: failure because `CanonicalFrameMap` construction and validator are not implemented.

- [x] **Step 3: Implement allocation-free map construction.**

  Call `producer_contract.validate_contract` and `facts.validate_route_facts` before constructing the borrowed view. Require the route id, descriptor id and contract descriptor id to match; verify all frame/binding/marker/lifecycle ranges and ownership bits; preserve canonical offset `0`; and enforce the direct pilot's fixed measured frame size and bounded asset/group limit. The function must return a map by value without creating a second fact table.

- [x] **Step 4: Run the positive and negative map tests.**

  Re-run the filter and require every RED case to pass as a rejection, including explicit `zero sentinel`, `batch alias`, and marker-shape errors. Run `zig fmt` on the new module/test and `git diff --check`.

- [x] **Step 5: Commit the frame-map slice.**

  ```bash
  git add src/build/codegen_component_producer_state_ir.zig src/build/codegen_component_producer_state_ir_test.zig src/main.zig
  git diff --cached --check
  git commit -m "Add bounded G6.2 canonical frame map"
  ```

### Task 3: Construct static `LifecycleStateIR` and enforce cleanup invariants

**Files:**
- Modify: `src/build/codegen_component_producer_state_ir.zig`
- Modify: `src/build/codegen_component_producer_state_ir_test.zig`

**Interfaces:**
- Consumes: `CanonicalFrameMap`, `ProducerContract`, and the bounded ownership/list topology from existing contracts.
- Produces:

```zig
pub const AssetKind = enum { resource, list_backing };
pub const AssetDisposition = enum { transfer_to_host, release_after_copy };
pub const AssetId = struct { group_index: u32, asset_index: u32 };
pub const LifecycleAsset = struct { id: AssetId, kind: AssetKind, disposition: AssetDisposition, path: []const []const u8 };
pub const LifecycleGroup = struct { group_index: u32, asset_start: u32, asset_count: u32 };
pub const AtomicGroupTransfer = struct { group_index: u32, asset_start: u32, asset_count: u32 };
pub const CancelPlan = struct { pre_transfer_state: []const u8, post_transfer_state: []const u8, rolls_back_host_effects: bool };
pub const TerminalPlan = struct { close_action: []const u8, abort_action: ?[]const u8, cancel_action: []const u8 };

pub const LifecycleStateIR = struct {
    assets: [64]LifecycleAsset,
    asset_count: u32,
    groups: [64]LifecycleGroup,
    group_count: u32,
    acquire_order: [64]AssetId,
    acquire_count: u32,
    complete_write_barrier: [64]u32,
    barrier_count: u32,
    transfer_commit: [64]AtomicGroupTransfer,
    transfer_count: u32,
    post_transfer_cancel: CancelPlan,
    reverse_release: [64]AssetId,
    reverse_release_count: u32,
    cleanup_order: [7]producer_contract.CleanupStage,
    cleanup_count: u32,
    terminal: TerminalPlan,
};

pub const LifecycleError = error{
    InvalidGroup,
    InvalidAsset,
    UnsupportedBound,
    TransferBeforeCompleteWrite,
    PartialGroupTransfer,
    InvalidDisposition,
    InvalidReverseRelease,
    CleanupOrderMismatch,
    DuplicateCleanupStage,
    ParentCleanupBeforeChild,
    PostTransferRollback,
    TerminalBeforeCleanup,
};

pub fn build_lifecycle_ir(contract: producer_contract.ProducerContract, map: CanonicalFrameMap) LifecycleError!LifecycleStateIR;
pub fn validate_lifecycle_ir(contract: producer_contract.ProducerContract, map: CanonicalFrameMap, ir: LifecycleStateIR) LifecycleError!void;
```

  The fixed arrays and count fields are intentional: they keep the static plan allocation-free and prevent slices from escaping a stack builder. The cleanup array length must equal the current `CleanupStage` enum field count; if that count changes, update the declaration and its compile-time assertion in the same change.

- [x] **Step 1: Add RED tests for valid state plans and direct failure guards.**

  Assert direct route asset transfer, list-backed release disposition, nested child-before-parent ordering, independent batched group ranges, complete-write barriers, reverse acquisition cleanup, and a post-transfer cancel plan whose `rolls_back_host_effects` is `false`. Add mutations that must reject transfer-before-write, partial group transfer, transfer/release disposition mismatch, reverse-order drift, duplicate cleanup stage, parent-before-child cleanup, terminal-before-cleanup, and post-transfer rollback.

- [x] **Step 2: Implement deterministic topology and static transition plan.**

  Derive resource assets from contract ownership leaves in leaf order; derive list backing assets from list allocations and payload-list identity; replicate the schema per mapping group without aliasing ranges; cap total assets/groups at `64`; emit acquire, write barrier, atomic transfer, post-transfer cancel, reverse release, cleanup and terminal records. The builder must reject half-transfer plans and must not invent a resource asset for a list-only route.

- [x] **Step 3: Implement the invariant validator and make construction fail closed.**

  Validate every count/range, exactly-once cleanup, child-before-parent release, terminal guard, transfer disposition and cancel semantics. A failed validator returns the named `LifecycleError` and never returns a partially initialized IR.

- [x] **Step 4: Run the state-IR filter and inspect the complete failure matrix.**

  ```bash
  cd src
  TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig test main.zig --test-filter "producer lifecycle state IR"
  ```

  Expected: all valid direct/nested/list/batched cases pass and every mutated IR is rejected with the expected error. Format the two task files and run `git diff --check`.

- [x] **Step 5: Commit the lifecycle IR slice.**

  ```bash
  git add src/build/codegen_component_producer_state_ir.zig src/build/codegen_component_producer_state_ir_test.zig
  git diff --cached --check
  git commit -m "Add G6.2 lifecycle state IR"
  ```

### Task 4: Add named fragment coverage and bounded assembly

**Files:**
- Create: `src/build/codegen_component_producer_fragments.zig`
- Create: `src/build/codegen_component_producer_fragments_test.zig`
- Modify: `src/main.zig: test root imports`

**Interfaces:**
- Consumes: immutable template bytes and route-specific `CanonicalFrameMap`/`LifecycleStateIR` marker names.
- Produces:

```zig
pub const FragmentKind = enum { prefix, payload, lifecycle, metadata, suffix };
pub const SourceSpan = struct { start: u32, end: u32 };
pub const Fragment = struct {
    name: []const u8,
    kind: FragmentKind,
    span: SourceSpan,
    required_markers: []const []const u8,
    order: u16,
};

pub const FragmentError = error{
    EmptyTable,
    EmptyName,
    InvalidSpan,
    SpanOutsideTemplate,
    FragmentGap,
    FragmentOverlap,
    OrderDrift,
    InvalidKindOrder,
    WholeTemplateFragment,
    MissingMarker,
};

pub fn validate_fragment_table(template: []const u8, fragments: []const Fragment) FragmentError!void;
pub fn assemble(allocator: std.mem.Allocator, template: []const u8, fragments: []const Fragment) FragmentError![]u8;
```

- [x] **Step 1: Write RED coverage tests.**

  Use a small synthetic module and the direct route's named spans. Require exact contiguous coverage, prefix-first/suffix-last order, marker ownership, and byte-for-byte assembly. Add negative fixtures for empty table/name, out-of-range span, gap, overlap, order drift, invalid kind order, one whole-template fragment, and missing required marker.

- [x] **Step 2: Run the fragment filter to capture RED.**

  ```bash
  cd src
  TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig test main.zig --test-filter "producer fragment"
  ```

  Expected: failure because the fragment descriptor and assembler are not defined.

- [x] **Step 3: Implement span/order/marker validation without parsing or rewriting WAT.**

  Validate that ordered spans cover `[0, template.len)` exactly once; reject a single span covering the whole template; require the first/last kinds to be `prefix`/`suffix`; and scan only each declared marker name within its declared span. The validator must not discover arbitrary fragments or treat the complete template as an opaque fallback fragment.

- [x] **Step 4: Implement allocator-owned assembly and test parity.**

  Append `template[span.start..span.end]` in `order` sequence into one caller-owned buffer. On any validation or append error, return an error and no output artifact. Assert the direct route's assembled bytes equal the old embedded template exactly.

- [x] **Step 5: Run, format, and commit the fragment slice.**

  Re-run the filter, format both new files, run `git diff --check`, then commit with subject `Add G6.2 producer fragments`.

### Task 5: Wire the private direct-route pilot emitter

**Files:**
- Create: `src/build/codegen_component_producer_emitter.zig`
- Create: `src/build/codegen_component_producer_emitter_test.zig`
- Modify: `src/build/codegen_component_owned_record_stream_producer.zig`
- Modify: `src/main.zig: test root imports`

**Interfaces:**
- Consumes: `ProducerContract`, `RouteFrameFacts`, `CanonicalFrameMap`, `LifecycleStateIR`, named fragments and the descriptor's WIT hash.
- Produces:

```zig
pub const PilotError = error{
    InvalidAdmission,
    InvalidIdentity,
    InvalidHash,
    InvalidMap,
    InvalidLifecycle,
    InvalidFragments,
    ByteParityMismatch,
    ArcRuntimeMarker,
    CanonicalGcReference,
};

pub const PilotFacts = struct {
    route_id: []const u8,
    descriptor_id: []const u8,
    contract: producer_contract.ProducerContract,
    frame_facts: facts.RouteFrameFacts,
    fragments: []const fragments_mod.Fragment,
    golden_wat: []const u8,
};

pub const PilotInput = struct {
    facts: PilotFacts,
    canonical_wit_hash: []const u8,
    template_wat: []const u8,
};

pub fn emit_pilot_wat(allocator: std.mem.Allocator, input: PilotInput) PilotError![]u8;
```

  The direct route adapter must expose only a private-by-convention `emit_component_wat_pilot` entry from `OwnedRecordStreamProducerPlan`; it must reject any descriptor/source/sink shape other than the measured direct route. Existing `emit_component_wat` and `emit_component_wit` remain the old route and are not routed through the pilot.

- [x] **Step 1: Add RED pilot parity and admission tests.**

  Analyze the checked-in exact Do source, construct the adapter input, and assert the pilot output equals the old `emit_component_wat` bytes. Add direct failures for wrong route id, descriptor mismatch, empty/hash mismatch, mutated frame fact, invalid lifecycle/fragment table, changed golden byte, `__arc_` output, and a synthetic WAT containing a GC reference crossing the canonical boundary. Assert each failure returns without a WAT buffer being accepted.

- [x] **Step 2: Run the pilot filter before wiring the implementation.**

  ```bash
  cd src
  TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig test main.zig --test-filter "producer shared emitter pilot"
  ```

  Expected: RED until the emitter, route adapter and fragment table exist.

- [x] **Step 3: Implement `emit_pilot_wat` with fail-closed ordering.**

  Check route/descriptor identity and the non-empty canonical WIT hash first; construct `state_ir.FrameMapInput{ .route_id = input.facts.route_id, .descriptor_id = input.facts.descriptor_id, .contract = input.facts.contract, .frame_facts = input.facts.frame_facts }`; then call `build_frame_map`, `build_lifecycle_ir`, `validate_fragment_table`, and `assemble_with_lifecycle(input.template_wat, ...)` in that order. Reject `__arc_` and canonical-boundary GC references in the assembled source; compare assembled bytes to `golden_wat`; free a temporary assembled buffer before returning parity/error failures. Do not catch an error and call the old emitter.

- [x] **Step 4: Add the direct route adapter without changing default dispatch.**

  In `codegen_component_owned_record_stream_producer.zig`, use the adapter-owned immutable direct `RouteFrameFacts` and `owned_record_stream_producer_template.wat` source, construct explicit five-kind fragment spans, pass both the template source and `plan.contract.descriptor_hash` as `canonical_wit_hash`, and call the shared emitter only from `emit_component_wat_pilot`. Keep `emit_component_wat` returning the embedded template and keep all existing exact-source negative admission tests unchanged.

- [x] **Step 5: Run focused pilot tests, old emitter tests, format, and commit.**

  Run both `--test-filter "producer shared emitter pilot"` and the existing `--test-filter "owned record producer"`; require pilot/old byte parity and all old negative cases. Format all changed Zig files, run `git diff --check`, then commit with subject `Add G6.2 shared emitter pilot`.

### Task 6: Execute artifact/runtime/repository gates and close the pilot

**Files:**
- Modify: `doc/superpowers/specs/2026-09-13-g6-2-shared-emitter-state-ir-pilot-design.md`
- Modify: `doc/superpowers/plans/2026-09-13-g6-2-shared-emitter-state-ir-pilot.md`
- Modify: `src/build/codegen_component_producer_emitter_test.zig` only if a gate exposes a confirmed pilot defect.

**Interfaces:**
- Consumes: Tasks 1-5's focused tests and the existing direct route golden/runtime harness.
- Produces: verified gate evidence, updated status/checklists, and no route promotion.

- [x] **Step 1: Run all Zig/unit and build gates with current local caches.**

  Evidence (2026-09-13, Zig 0.16.0): `zig test main.zig` passed `1728/1728`;
  `zig build -Doptimize=ReleaseSmall`, `run_tests.sh` (`14/14 steps; 53/53
  tests`) and `run_release_smoke.sh` all passed; `git diff --check` passed.
  The ARC inventory was then corrected in commit `598f2a0` by classifying the
  pilot guard and test-oracle references. The current inventory is
  `rows=55 matches=492 unclassified=0`; post-cutover also reports
  `normal_route_matches=0` and the production dependency closure reports
  `modules=162 forbidden=0`. The earlier inventory mismatch is retained as
  historical evidence in `task-6-report.md`, but it is no longer an active
  repository gate failure.

  ```bash
  (cd src && TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig test main.zig)
  (cd src && TMPDIR="$PWD/../.tmp/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/zig-gcache" zig build -Doptimize=ReleaseSmall)
  ./src/build/test/run_tests.sh
  ./src/build/test/run_release_smoke.sh
  git diff --check
  ```

  Record expected/actual counts, exit status and cache/tool versions; preserve any failed command and classify it as environment or source evidence before continuing.

  Final-fix follow-up (`b130817 Close G6.2 final review findings`) and the
  inventory classification fix (`598f2a0 Classify G6.2 ARC guard references`)
  re-ran the focused pilot (`20/20`), owned-record producer (`15/15`), state-IR
  map (`16/16`), and full Zig suite (`1728/1728`) with exit `0`. The
  integration harness now exits `0` with `14/14 steps; 53/53 tests`; both
  pre-cutover and post-cutover inventory scans are fully classified. Step 3
  remains unchecked because the host runner still exposes no list/frame runtime
  counters.

- [x] **Step 2: Run current-toolchain Component/WIT artifact gates.**

  A temporary Zig helper called the private
  `producer.emit_component_wat_pilot` API directly (the helper was removed
  after the run). It wrote
  `.tmp/task-6-evidence/private-pilot/pilot.wat`; this exact file, rather than
  a `do build` output, was passed to `wasm-tools parse`, `component embed`,
  `component new`, and `validate --features cm-async,cm-more-async-builtins`,
  all exit `0`. The command was:

  ```bash
  (cd src && TMPDIR="$PWD/../.tmp/task-6-evidence/do-tmp" ZIG_LOCAL_CACHE_DIR="$PWD/../.tmp/task-6-evidence/zig-cache" ZIG_GLOBAL_CACHE_DIR="$PWD/../.tmp/task-6-evidence/zig-gcache" zig run build/task_6_private_pilot_artifact_helper.zig -- "$PWD/../.tmp/task-6-evidence/private-pilot/pilot.wat")
  ```

  Verified with `wasm-tools 1.258.0 (5c6d31c78 2026-08-24)` and `wasmtime
  48.0.1 (7bac2c277 2026-08-24)`. WIT descriptor package/world was
  `do:g6-2-owned-record-producer@0.1.0` / `owned-record-producer`; WIT SHA-256
  was `6c1406962ee4c4e3eec5b3b4a866acfd1d8eb6ee159ce5b4077df113063d1ace` and
  pilot WAT SHA-256 was
  `095da7cd4c131a7318fc4bf5fd87b2d99e2672bff568edc577a553e228f856c5`.
  WAT SHA-256 matched the checked-in direct golden. The artifact contained no
  `__arc_` marker and no canonical-boundary Wasm GC reference.

  Generate the pilot WAT/WIT into a temporary directory, then run the current `wasm-tools` sequence used by the repository: `wasm-tools parse`, `wasm-tools component embed`, `wasm-tools component new`, and `wasm-tools validate --features cm-async,cm-more-async-builtins`. Verify WIT bytes/hash, descriptor identity, no `__arc_` marker and no Wasm GC reference crossing the canonical boundary. Record `wasm-tools --version` and `wasmtime --version` from the live environment.

- [ ] **Step 3: Run the existing Rust/Wasmtime lifecycle matrix for the unchanged direct route.**

  The existing Do Component gate and canonical/generated equivalence runner
  passed for the observed counters. The local-cache rerun covered 10 rows: ready, pending,
  sink-error-before/after, cancel-before/after-transfer,
  early-drop-before/after-transfer, repeat and invalid. Every row reported
  `table-empty=true`; resource, stream and future cleanup were exactly once
  (repeat was exactly twice). The direct contract/static IR evidence separately
  records `contract.list_allocations.len=0` and
  `ir.list_backing_count=0`; the host runner exposes no list/frame counters, so
  runtime list/frame exactly-once remains unverified. The first Rust invocation failed at the linker
  because the default Zig cache lacked `Scrt1.o`, libc and runtime archives;
  this environment failure is retained in `task-6-report.md` and was not used
  as a runtime result.

  Exercise ready, pending, sink error, transfer-before/after cancel, early-drop and repeat rows using the existing runner. Require resource/list/frame exactly-once cleanup and `table-empty=true`; compare pilot artifact observations with the old artifact. Do not add a new runtime behavior or treat the logical state-IR test as a replacement for this gate.

  Status ledger: resource/stream/future runtime observations are verified; list/frame
  runtime counters are unavailable from the host runner and remain unverified. The
  static contract/state-IR evidence is recorded in `task-6-report.md`.

- [x] **Step 4: Verify default-route non-regression and rollback.**

  The ordinary `--p3-async-component` output matched the old direct WAT and WIT
  byte-for-byte (WAT SHA-256
  `095da7cd4c131a7318fc4bf5fd87b2d99e2672bff568edc577a553e228f856c5`, WIT
  SHA-256 as above). Pilot admission negative tests returned named errors with
  no accepted fallback buffer. For rollback, a temporary `git archive HEAD`
  checkout replaced `emit_component_wat_pilot` with an immediate
  `InvalidAdmission`, rebuilt its compiler, and ran
  `DO_BIN=<rollback-copy>/bin/do examples/p3-runtime/test_do_g6_2_owned_record_producer.sh`;
  the build and old-route gate both exited `0`. `doc/gc_arc_inventory.tsv` had
  no diff. See `task-6-report.md` for the exact command set and artifact path.

  Compile the same source through ordinary `--p3-async-component` and assert old WAT/WIT bytes, diagnostics, descriptor/hash and capability inventory are unchanged. Exercise the private pilot with an intentionally invalid fact and assert a named error with no fallback artifact. Remove the private dispatch in a local rollback check and confirm the old route still passes its focused tests.

- [x] **Step 5: Update evidence and close only the pilot scope.**

  This step records the incomplete repository gate above rather than claiming
  a fully green regression run. The pilot remains private and byte-parity
  staged. Twelve-route migration, generic/arbitrary producers, public
  ownership syntax, semantic-parity rewrite and D2 general async remain
  deferred. The capability inventory is unchanged, and the state-IR probe is
  not treated as runtime equivalence.

  Mark only verified steps `[x]`, record exact command outcomes and tool versions in the spec/plan, and state that 12-route migration, generic/arbitrary producers, public ownership syntax, semantic-parity rewrite and D2 general async remain deferred. Do not update the capability inventory as promoted and do not claim runtime equivalence from the state-IR probe alone.

- [x] **Step 6: Commit the verified pilot package.**

  ```bash
  git add src/build/codegen_component_producer_facts.zig \
    src/build/codegen_component_producer_mapping_probe.zig \
    src/build/codegen_component_producer_mapping_probe_test.zig \
    src/build/codegen_component_producer_state_ir.zig \
    src/build/codegen_component_producer_state_ir_test.zig \
    src/build/codegen_component_producer_fragments.zig \
    src/build/codegen_component_producer_fragments_test.zig \
    src/build/codegen_component_producer_emitter.zig \
    src/build/codegen_component_producer_emitter_test.zig \
    src/build/codegen_component_owned_record_stream_producer.zig \
    src/main.zig \
    doc/superpowers/specs/2026-09-13-g6-2-shared-emitter-state-ir-pilot-design.md \
    doc/superpowers/plans/2026-09-13-g6-2-shared-emitter-state-ir-pilot.md
  git diff --cached --check
  git commit -m "Pilot shared G6.2 producer emitter"
  ```

## Self-review checklist

- Every spec target has a task: production facts (Task 1), frame map (Task 2), lifecycle IR (Task 3), fragments (Task 4), pilot/admission/parity (Task 5), and all artifact/runtime/repository gates (Task 6).
- The plan never promotes the pilot to default dispatch and never uses a fallback emitter.
- All public signatures used by later tasks are defined before use; fixed arrays/counts prevent dangling borrowed slices.
- Negative tests cover identity, intervals, markers, bounds, ownership/cleanup invariants, fragment coverage, hash/parity and runtime-marker rejection.
- No step relies on a placeholder or an unspecified edge-case action; failed commands are retained and classified rather than hidden.
- The plan is limited to the approved single route and leaves later route promotion behind a separate design and gate.
