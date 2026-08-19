# GC-First One-Pass Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将当前 `do` 编译器所有已经对外准入的 managed-memory 编译路径统一迁移到 Wasm GC，使普通 `do build` 和 `do test --compiled` 不再依赖 ARC，同时保持现有 Do 值语义、colorless async 和 WIT/Component 资源终态契约。

**Architecture:** 沿用已批准的 GC-first 架构：源码仍是无指针、无引用和值语义；`text`、list、大结构和含 managed 字段的结构在内部使用 Wasm GC reference；更新通过重建或已证明唯一时的私有 storage reuse 保持旧逻辑值。迁移按 G5a complete-program slices、G5b ARC/GC executable equivalence、G5c default cutover 三个严格门禁连续推进；单个模块内不得混合 ARC handle 与 GC reference，WIT resource ownership/drop 继续由独立 `ResourcePlan` 负责。

**Tech Stack:** Zig 0.16, Core Wasm GC WAT, `wasm-tools 1.255.0`, Wasmtime GC execution probes, 当前 `do` compiler regression harness, Rust/Wasmtime Component runners。

**Spec:** `doc/superpowers/specs/2026-08-11-gc-backend-architecture-design.md`, `doc/design/2026-08-11-gc-first-memory-decision.md`, `doc/memory.md`。

## Global Constraints

- Wasm GC 是唯一 managed-memory backend；ARC 不保留为用户可选后端。
- `--gc-core` 仅是迁移期间的受限 oracle，G5c 后必须删除。
- 不新增公开 `ref<T>`、`own<T>`、`borrow<T>`、`Result<T,E>` 或 `Option<T>` 类型。
- 源码值语义不变：只读传参、赋值和返回不得复制 managed payload；`@set`、`@put` 和字段更新产生新的逻辑值，旧逻辑值仍可观察。
- GC 只追踪 Do allocation，不隐式执行 WIT resource close/drop/cancel。
- Wasm GC reference 不得跨 Component/WIT canonical ABI boundary；边界必须显式 lift/lower 或 marshal。
- 任何不支持的形状必须在 WAT emission 前 fail closed，不能偷偷回退 ARC。
- 不在同一个 emitted Core module 的 source-value data flow 中混合 ARC handle 与 GC reference。
- 不扩展通用 async、任意 producer、通用 filesystem async、外部 HTTP 或新的 WIT shape admission；这些在迁移完成后按各自 capability plan 继续。
- 修改必须保持当前 dirty worktree 的用户差分；每个阶段独立验证并保留可回滚提交。
- 统一使用 `./src/build/test/run_tests.sh` 作为完整回归入口；Wasm gate 使用当前 `wasm-tools` 与 Wasmtime，不使用历史工具版本。

## Current Baseline

当前已验证的 G5a slices：

1. 固定索引和参数化 `[u8] @set`。
2. 数字 `[u8]` literal（含空 literal）。
3. 单值 `[u8] @put`。
4. 直接 `[u8]` managed-field payload rebuild。

当前仍为迁移债务的 ARC 入口：

- `src/build/runtime_arc_wat.zig`
- `src/build/runtime_prelude_wat.zig`
- `src/build/codegen_ownership.zig`
- `src/build/codegen_model.zig` 中的 `EmitOptions.gc_core`
- `src/build/run.zig` / `src/build/cli.zig` 中的 `gc_core` routing

当前事实不是“GC migration 已完成”：普通 `do build` 仍通过 ARC pipeline；G5a parsed entry 仍拒绝 module graph、generic layout instantiation、async、resource、host call、multi-result passthrough/aggregate 以及未准入的 managed expression shapes。bounded scalar-only multi-result direct-return 已单独接入 typed GC route，不能外推为一般 multi-result 支持。

The normal pipeline now has a private `EmitOptions.gc_sync` migration route
for already admitted parsed GC shapes. It is deliberately not a CLI selector,
does not change the default `.{} ` route, and is covered by managed-field,
payload-union (including typed carrier locals), and resolved-generic pipeline
tests. Resolved generic payload-union instances now use the same bounded GC
carrier, including a `T`-typed local after substitution. This is a bridge for
G5b, not a default cutover.

## File Map

| 文件 | 本计划中的职责 |
| --- | --- |
| `src/build/codegen_gc_representation.zig` | source type 到 `inline_value`、`gc_managed`、`resource_handle` 的纯分类 |
| `src/build/codegen_gc_layout.zig` | GC struct/array layout、managed field、嵌套布局和布局校验 |
| `src/build/codegen_gc_roots.zig` | 同步局部、控制流和 suspendable frame 的 root/liveness facts |
| `src/build/codegen_gc_emit.zig` | GC allocation、array/struct access、copy/rebuild 的小 WAT fragment |
| `src/build/runtime_gc_wat.zig` | typed GC struct/array declarations 和 runtime primitives |
| `src/build/runtime_gc_prelude_wat.zig` | GC type/prelude assembly |
| `src/build/codegen_gc_sync.zig` | parsed complete-program synchronous GC lowering |
| `src/build/codegen_gc_sync_adapter.zig` / `codegen_gc_model_adapter.zig` | parser/model 到 GC facts 的单向适配 |
| `src/build/codegen_pipeline.zig` / `codegen_api.zig` | normal pipeline 的 backend entry 和统一 error propagation |
| `src/build/codegen_component_abi_plan.zig` | canonical ABI lift/lower facts，不持有 GC reference |
| `src/build/codegen_component_resource_plan.zig` | own/borrow/drop、terminal cleanup、cancel liveness |
| `src/build/codegen_component_async*.zig` / `codegen_component_future_owned*.zig` | 已准入 Future/Stream frame 的 GC root consumption |
| `src/build/codegen_emit_*.zig` | 逐模块移除 ARC release/clone emission，改用 GC root/storage helpers |
| `src/build/cli.zig` / `src/build/run.zig` / `src/build/codegen_model.zig` | G5c 删除临时 selector 并路由默认 GC |
| `src/build/test/` | backend-neutral behavior fixtures、GC output guards、CLI residual tests |
| `examples/gc-p3-runtime/` | Wasm-tools/Wasmtime GC oracle probes |
| `doc/memory.md` / `doc/roadmap_status.md` / `doc/host_abi_blockers.md` | 当前状态、边界、失败证据和恢复条件 |

## Execution Rules

每个任务都按 `失败测试 -> 最小实现 -> focused test -> aggregate gate -> commit` 执行。任务之间必须串行，因为它们改变共享 compiler contracts；可以在同一连续工作链中执行，但任何 gate 失败都必须停在该任务、记录失败来源，并保留前一阶段可运行状态。G5a、G5b、G5c 不允许跳过或合并 gate。

### Task 0: Freeze Baseline And Admission Ledger

**Files:**
- Modify: `doc/roadmap_status.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `examples/gc-p3-runtime/README.md`
- Create: `src/build/test/check_gc_migration_inventory.sh`
- Test: existing default and `RUN_GC_CORE=1` harnesses

**Interfaces:**
- Consumes: current parsed G5a entry, `check_gc_core_oracles.sh`, `run_tests.sh`.
- Produces: a machine-readable inventory of every default managed path and its G5a/G5b evidence status.

- [ ] **Step 1: Add the failing inventory assertion.**

  Create `check_gc_migration_inventory.sh` with explicit rows for `text`, `[u8]`, other lists, managed structs, nested structs, Tuple/storage, unions, generic calls, imports, host/WIT marshalling, sync control flow, Future/Stream frames, and resource terminal cleanup. The script must fail if a row has no status or if a row is marked complete without a linked fixture.

- [ ] **Step 2: Run the inventory before implementation.**

  Run:

  ```bash
  bash src/build/test/check_gc_migration_inventory.sh
  ```

  Expected: it reports the known missing G5a/G5b/G5c rows and exits non-zero. Preserve this output in the task notes; do not weaken the assertion.

- [ ] **Step 3: Populate only evidence-backed rows.**

  Link the four current G5a slices to their exact source fixtures and probes. Mark all other rows `pending` with the exact rejection/error boundary currently emitted by `codegen_gc_sync.zig`.

- [ ] **Step 4: Run baseline gates.**

  ```bash
  cd src && zig build -Doptimize=ReleaseSmall
  cd src && zig test main.zig
  ./src/build/test/run_tests.sh
  RUN_GC_CORE=1 WASMTIME_BIN="$(command -v wasmtime)" WASM_TOOLS_BIN="$(command -v wasm-tools)" ./src/build/test/run_tests.sh
  ```

  Expected: existing baseline remains green; the inventory alone remains red for incomplete rows.

- [ ] **Step 5: Commit the baseline ledger.**

  ```bash
  git add doc/roadmap_status.md doc/host_abi_blockers.md examples/gc-p3-runtime/README.md src/build/test/check_gc_migration_inventory.sh
  git commit -m "Record GC migration admission ledger"
  ```

### Task 1: Close G5a Scalar, Text, List And Producer Boundaries

**Files:**
- Modify: `src/build/codegen_gc_sync.zig`
- Modify: `src/build/codegen_gc_sync_adapter.zig`
- Modify: `src/build/codegen_gc_model_adapter.zig`
- Modify: `src/build/codegen_gc_representation.zig`
- Modify: `src/build/codegen_gc_layout.zig`
- Modify: `src/build/codegen_gc_roots.zig`
- Modify: `src/build/codegen_gc_emit.zig`
- Modify: `src/build/runtime_gc_wat.zig`
- Modify: `src/build/runtime_gc_prelude_wat.zig`
- Modify: `src/build/gc_sync_probe.zig`
- Test: `src/build/codegen_gc_sync.zig`, `src/build/codegen_gc_emit_test.zig`, `examples/gc-p3-runtime/`

**Interfaces:**
- Consumes: `ValueRep`, `GcStructLayout`, `RootPlan` and parsed `FuncDecl` facts.
- Produces: complete-program GC lowering for all currently supported synchronous `text`/list shapes, with explicit producer admission and no token-profile guesswork.

- [ ] **Step 1: Add negative tests for the current gaps.**

  Add parsed fixtures for `text` payload replacement, nested list/struct producer, non-`u8` list update, multi-value `@put`, and a call-produced replacement. Each must assert a specific `UnsupportedGcSync*` error before WAT emission.

- [ ] **Step 2: Add positive tests for the next closed shapes.**

  Add one shape at a time: direct text identity/rebuild, text field replacement, list literal through a local, and one direct call whose return type is already classified `GcManaged`. Assert typed GC locals, `array.len`/`array.copy` or typed struct rebuild, and absence of `__arc_`.

- [ ] **Step 3: Implement parsed expression admission.**

  Extend the adapter to classify expressions by parsed declaration and expected type. Accept only the exact positive forms in the tests; reject nested calls, module/import references, generics, resource values, and unsupported element types before emitter invocation. Do not infer a managed struct from parameter count or capitalization.

- [ ] **Step 4: Implement GC text/list fragments.**

  Add runtime-private text array allocation/copy/rebuild and list element operations. Every update must allocate separated backing unless the root plan proves the old value cannot escape. Keep source values rooted through allocation and copy; never emit ARC retain/release calls.

- [ ] **Step 5: Update the probe wrapper from parsed layout facts.**

  Make `gc_sync_probe.zig` derive type names, function names, field order and field types from the parsed program. A non-exact probe shape must fail closed instead of constructing a hard-coded `$box` wrapper.

- [ ] **Step 6: Run the focused G5a gate.**

  ```bash
  cd src && zig test build/codegen_gc_sync.zig
  cd src && zig test build/codegen_gc_emit_test.zig
  cd src && zig test build/codegen_gc_roots.zig
  WASM_TOOLS_BIN="$(command -v wasm-tools)" WASMTIME_BIN="$(command -v wasmtime)" bash src/build/test/check_gc_core_oracles.sh
  ```

  Expected: all admitted probes parse, validate and execute; every neighboring unsupported shape fails before WAT.

- [ ] **Step 7: Update the ledger and commit.**

  Update `doc/roadmap_status.md`, `doc/host_abi_blockers.md` and the GC example README with exact admitted/rejected rows, then commit:

  ```bash
  git add src/build/codegen_gc_*.zig src/build/runtime_gc_*.zig examples/gc-p3-runtime doc/roadmap_status.md doc/host_abi_blockers.md
  git commit -m "Complete parsed GC value slices"
  ```

### Task 2: Close G5a Managed Aggregates, Tuple, Union And Generic Paths

**Files:**
- Modify: `src/build/codegen_gc_layout.zig`
- Modify: `src/build/codegen_gc_roots.zig`
- Modify: `src/build/codegen_gc_emit.zig`
- Modify: `src/build/codegen_gc_sync.zig`
- Modify: `src/build/codegen_gc_sync_adapter.zig`
- Modify: `src/build/codegen_gc_model_adapter.zig`
- Modify: `src/build/codegen_emit_tuple.zig`
- Modify: `src/build/codegen_emit_union.zig`
- Modify: `src/build/codegen_generics.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Test: `src/build/test/compile_ok/`, `src/build/test/compiled_ok/`, `src/build/test/ok/`, `examples/gc-p3-runtime/`

**Interfaces:**
- Consumes: completed scalar/text/list GC lowering and shared layout/root facts.
- Produces: GC lowering for all ordinary non-imported managed aggregate paths currently accepted by the ARC pipeline.

- [ ] **Step 1: Add backend-neutral aggregate behavior fixtures.**

  Cover nested struct field get/set, list of managed structs, `Tuple<text, [u8]>`, union carriers with managed payloads, generic identity/return, and generic managed field update. Each fixture must assert old-value preservation and returned-value contents.

- [ ] **Step 2: Add pre-WAT rejection tests for resource-containing aggregates.**

  Ensure a WIT resource handle nested inside a GC-managed struct/list/tuple is rejected by representation/layout facts; it must not be silently traced as a GC child.

- [ ] **Step 3: Implement typed nested layout collection.**

  Collect dependent GC struct types in topological order, reject missing/forward-invalid/cyclic layouts, and map each managed child to a typed GC field or array element. Keep resource handles opaque and separate.

- [ ] **Step 4: Implement aggregate rebuild and field-path lowering.**

  For `@get`, load the typed field/array child. For `@set`/`@put`, rebuild only the logical path that changed, copying unchanged child references without ARC operations. Use a private in-place `struct.set`/`array.set` only when the root facts prove non-escape.

- [ ] **Step 5: Route generic calls through GC type bindings.**

  Extend generic instantiation and call lowering to carry resolved `ValueRep` and layout facts. Reject unresolved generic managed types before emission; do not fall back to ARC emitters.

- [ ] **Step 6: Run the aggregate gate.**

  ```bash
  cd src && zig test build/codegen_gc_layout.zig
  cd src && zig test build/codegen_gc_sync.zig
  cd src && zig test build/codegen_emit_tuple.zig
  cd src && zig test build/codegen_emit_union.zig
  cd src && zig test main.zig
  ./src/build/test/run_tests.sh
  ```

  Expected: all ordinary admitted aggregate fixtures execute with GC; resource-containing and unresolved shapes fail closed.

- [ ] **Step 7: Commit aggregate GC lowering.**

  ```bash
  git add src/build/codegen_gc_*.zig src/build/codegen_emit_tuple.zig src/build/codegen_emit_union.zig src/build/codegen_generics.zig src/build/codegen_pipeline.zig src/build/test examples/gc-p3-runtime
  git commit -m "Lower managed aggregates through Wasm GC"
  ```

### Task 3: Convert Synchronous Roots And Remove ARC From Converted Paths

**Files:**
- Modify: `src/build/codegen_context.zig`
- Modify: `src/build/codegen_body.zig`
- Modify: `src/build/codegen_emit_expression.zig`
- Modify: `src/build/codegen_emit_call.zig`
- Modify: `src/build/codegen_emit_control.zig`
- Modify: `src/build/codegen_emit_struct.zig`
- Modify: `src/build/codegen_emit_struct_fields.zig`
- Modify: `src/build/codegen_emit_storage_values.zig`
- Modify: `src/build/codegen_emit_storage_operations.zig`
- Modify: `src/build/codegen_emit_tuple.zig`
- Modify: `src/build/codegen_emit_union.zig`
- Modify: `src/build/codegen_emit_wasi.zig`
- Modify: `src/build/codegen_control_flow.zig`
- Test: `src/build/test/compile_ok/`, `src/build/test/compiled_ok/`

**Interfaces:**
- Consumes: GC `RootPlan`, typed GC locals and aggregate emit fragments.
- Produces: synchronous normal-pipeline code generation with no ARC release plan for converted managed values.

- [x] **Step 1: Add output guards before deleting ARC calls.**

  Add compiled-output tests for local binding, overwrite, call, return, branch join, loop join, `defer`, Tuple and union managed values. Require typed GC locals/root markers and reject `__arc_inc`, `__arc_dec`, `__arc_payload`, `__arc_alloc` in those outputs. The normal and explicit GC-sync routes now run a shared output guard that rejects any `__arc_` marker before returning WAT; admitted-path tests cover the listed root points and aggregate shapes.

- [x] **Step 2: Split any remaining pure control-flow helper from ownership code.**

  Keep reachability, loop labels, defer ordering and branch join helpers in `codegen_control_flow.zig`; no GC module may import ARC release state. The GC sync/component modules now consume the pure control-flow boundary and have no `codegen_ownership` import.

- [ ] **Step 3: Replace managed-local release with root transitions.**

  On binding and overwrite, update the typed GC local/root fact. On branch/loop merge, emit the joined GC local. On return, leave the returned reference as the result root. On `defer`, preserve LIFO side-effect order without source-value `inc/dec`. The root fact layer now rejects duplicate managed locals; full normal-pipeline release replacement remains pending.

  The normal candidate scan also admits body-only `text` direct literals, a
  standalone scalar-list literal, and a following single-value `@put` or
  single-index `@set` whose typed GC lowering is already complete.
  Bounded synchronous `defer` bodies are now admitted as well: the GC emitter
  preserves lexical LIFO cleanup on return, block exit, `break`, and
  `continue`, and accepts `return nil` for no-result functions without
  emitting a value. The old file-wide `defer` rejection is removed; only
  independently unsupported body shapes remain fail-closed.
  Multi-value/spread `@put`, dynamic/non-literal `@set`, producer expressions,
  and list/managed-struct locals with additional storage or control flow remain
  outside this slice until their gates close; the body-local root transition
  itself is still part of this step's remaining normal-pipeline work.

  The bounded `Unit | Bytes([u8])` carrier also supports a typed body local and
  return (`out Message = make(value)`), with one GC reference root for the
  carrier instead of the legacy payload/tag decomposition. A resolved generic
  `T` binding to the same payload union is substituted before local collection,
  so both direct and `T`-typed carrier locals lower through the typed GC struct.
  These are positive GC lowering tests only; ARC/GC equivalence remains a G5b
  pending row because the current ARC path rejects managed payload unions.

  A bounded body-only managed-struct storage slice is now also routed through
  this GC path: direct struct construction, scalar field `@set` rebuild, and
  managed child `@get` are covered by the default pipeline fixture. The GC
  locals boundary filters compiler-generated `__storage_*` and
  `__struct_literal_tmp` names. General inferred storage, nested producers,
  and other storage/control-flow shapes remain pending in this step.

  Bounded inferred scalar-list storage slices are also routed through this GC
  path: an explicit `[u8]` or `[u32]` seed followed by
  `values = @put(seed, 2)` and a no-result return. The inferred local is marked
  as a fresh root, and the default gate verifies typed copy-before-append
  lowering. General inferred lists, inferred non-scalar lists, dynamic
  producers, multi-value/spread `@put`, and additional storage control flow
  remain pending in this step.

  The declared managed-struct list slice now also has a direct one-value
  `@put` admission. `managed-struct-list.do` and its probe verify source-list
  preservation plus `$do_list_box` copy/set lowering. This remains G5a-only:
  the normal compiled/ARC entry rejects `[Box]` lists with `NoMatchingCall`, so
  no G5b equivalence row is claimed.

- [ ] **Step 4: Convert calls and storage operations.**

  Pass GC references directly for managed arguments/results, use typed field/array access for storage, and reject a call when any argument or result would cross into an ARC-only emitter.

- [ ] **Step 5: Run synchronous normal-pipeline gates.**

  ```bash
  cd src && zig test build/codegen_pipeline.zig
  cd src && zig test main.zig
  ./src/build/test/run_tests.sh
  ```

  Expected: every converted synchronous compiled fixture contains only GC managed representation and preserves source behavior; unconverted shapes remain explicit capability errors.

- [ ] **Step 6: Commit the synchronous root conversion.**

  ```bash
  git add src/build/codegen_*.zig src/build/test/compile_ok src/build/test/compiled_ok
  git commit -m "Use GC roots for synchronous managed values"
  ```

### Task 4: Convert Suspendable Roots And Component Boundary Consumption

**Files:**
- Modify: `src/build/codegen_gc_roots.zig`
- Modify: `src/build/codegen_component_abi_plan.zig`
- Modify: `src/build/codegen_component_resource_plan.zig`
- Modify: `src/build/codegen_component_async*.zig`
- Modify: `src/build/codegen_component_future_owned*.zig`
- Modify: `src/wit/manifest.zig`
- Modify: `src/wit/emit_manifest.zig`
- Modify: `src/wit/manifest_test.zig`
- Test: existing bounded async/resource fixtures and Rust/Wasmtime runners

**Interfaces:**
- Consumes: typed GC representation facts and synchronous root plan.
- Produces: GC-traced Future/Stream frame fields, canonical ABI marshal plans with no GC reference crossing, and independent exactly-once resource cleanup plans.

- [ ] **Step 1: Add negative root and ABI tests.**

  Cover managed values live across `@await`, `@cancel`, terminal completion, resume, and early drop. Reject any canonical ABI plan that contains a GC reference slot. Reject duplicate terminal cleanup facts.

- [ ] **Step 2: Extend frame root collection.**

  Store only `GcManaged` values in typed frame fields or traced locals. At suspend, copy the root facts into the frame; at resume, restore them before user code; at cancel/terminal, invalidate the frame after resource cleanup.

- [ ] **Step 3: Keep ABI and resource plans separate.**

  Marshal `text`, lists and aggregates into canonical buffers at the boundary. Apply `ResourcePlan` for `own`/`borrow` transfer and drop exactly once after the host terminal outcome. GC collection must never trigger resource drop.

- [ ] **Step 4: Run bounded Component gates.**

  ```bash
  cd src && zig test build/codegen_component_async_call_plan_test.zig
  cd src && zig test build/codegen_component_future_owned_plan_test.zig
  cd src && zig test build/codegen_component_resource_plan.zig
  cd src && zig test main.zig
  ./src/build/test/run_tests.sh
  ```

  Run all currently admitted Rust/Wasmtime ready, pending, error, cancel and early-drop probes. Expected: existing behavior remains green and no GC reference crosses Component ABI.

- [ ] **Step 5: Commit suspendable root conversion.**

  ```bash
  git add src/build/codegen_gc_roots.zig src/build/codegen_component_*.zig src/wit/manifest.zig src/wit/emit_manifest.zig src/wit/manifest_test.zig
  git commit -m "Integrate GC roots with bounded component frames"
  ```

### Task 5: Build The ARC/GC Semantic Equivalence Matrix (G5b)

**Files:**
- Create: `src/build/test/check_gc_semantic_equivalence.sh`
- Modify: `src/build/test/ok/`
- Modify: `src/build/test/compiled_ok/`
- Modify: `examples/gc-p3-runtime/test_do_gc_*.sh`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/host_abi_blockers.md`

**Interfaces:**
- Consumes: every complete-program slice admitted by Tasks 1-4.
- Produces: executable source-level equivalence evidence; it does not change the default backend.

- [ ] **Step 1: Create backend-neutral fixture rows.**

  For every admitted type/path add cases for read-only pass, alias followed by `@set`/`@put`, local overwrite, nested update, call, return, branch, loop, `defer`, and nearest error/trap boundary. Assertions must inspect Do-level results, never ARC or GC symbol spelling.

- [ ] **Step 2: Implement separate ARC and GC compilation in the checker.**

  Compile each fixture through normal `emit_wat` and the GC test entry into separate temporary artifacts. Validate both with `wasm-tools`; run the GC artifact with Wasmtime and run the normal compiled test through the existing harness. Never combine outputs into one module.

- [ ] **Step 3: Compare observable results and failure classes.**

  Compare return values, old/new value preservation, trap/error class, and resource terminal events for admitted Component cases. Do not require byte-for-byte WAT identity or allocation identity.

- [ ] **Step 4: Record failures without fallback.**

  On failure write fixture, command, compiler/runtime output, affected representation row and retry condition to `doc/host_abi_blockers.md`. Keep the normal ARC path unchanged and return non-zero for the affected row.

- [ ] **Step 5: Run the full G5b gate.**

  ```bash
  cd src && zig build -Doptimize=ReleaseSmall && zig test main.zig
  ./src/build/test/run_tests.sh
  RUN_WASM=1 ./src/build/test/run_tests.sh
  bash src/build/test/check_gc_semantic_equivalence.sh
  ```

  Run the existing Component assembly/canonical validation and all admitted Rust/Wasmtime async/resource runners. G5c is blocked by any missing matrix cell or failed host gate.

- [ ] **Step 6: Commit equivalence evidence.**

  ```bash
  git add src/build/test/check_gc_semantic_equivalence.sh src/build/test/ok src/build/test/compiled_ok examples/gc-p3-runtime doc/roadmap_status.md doc/host_abi_blockers.md
  git commit -m "Verify ARC and GC semantic equivalence"
  ```

### Task 6: Prepare G5c Cutover Residual Tests

**Files:**
- Modify: `src/build/test/compile_err/`
- Modify: `src/build/test/compile_ok/`
- Modify: `src/build/test/run_tests.sh`
- Modify: `src/build/cli.zig`
- Modify: `src/build/run.zig`
- Modify: `src/build/codegen_model.zig`
- Test: CLI and generated-WAT residual scans

**Interfaces:**
- Consumes: green G5b equivalence matrix.
- Produces: tests that fail while ARC or `--gc-core` still exists and pass only after one-backend routing is complete.

- [ ] **Step 1: Add the obsolete selector diagnostic test.**

  Add a CLI fixture invoking `do build file.do --gc-core`; assert `error[UnexpectedCliArg]` and no output artifact.

- [ ] **Step 2: Add ARC residual scans.**

  Add a checker that rejects these in active source or generated output: `__arc_`, `emit_arc_runtime_prelude`, `runtime_arc_wat`, `runtime_prelude_wat`, `codegen_ownership`, ARC release-plan exports. Historical dated docs may retain ARC evidence, but active implementation and active `.expect` files may not.

- [ ] **Step 3: Add representation/root output guards.**

  Require representative GC type declarations, typed GC locals, root markers and canonical ABI boundary markers for text, list, managed struct, Tuple, union, Future/Stream and resource cases.

- [ ] **Step 4: Run the pre-cutover residual tests.**

  ```bash
  ./src/build/test/run_tests.sh
  bash src/build/test/check_gc_migration_inventory.sh
  ```

  Expected: selector/residual scans fail before cutover because ARC is still present. This is the intended RED state for the cutover task.

### Task 7: Route Default Build To GC And Remove ARC (G5c)

**Files:**
- Modify: `src/build/cli.zig`
- Modify: `src/build/run.zig`
- Modify: `src/build/codegen_model.zig`
- Modify: `src/build/codegen_context.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: all active `src/build/codegen_emit_*.zig` modules still importing `codegen_ownership.zig`
- Delete: `src/build/codegen_gc_core.zig`
- Delete: `src/build/runtime_arc_wat.zig`
- Delete: `src/build/runtime_prelude_wat.zig`
- Delete: `src/build/codegen_ownership.zig`
- Modify: ARC-specific active tests and runtime docs

**Interfaces:**
- Consumes: complete G5a coverage, green G5b matrix, residual tests from Task 6.
- Produces: one default GC backend; no public selector, ARC prelude, ARC release lowering or mixed representation.

- [ ] **Step 1: Prove the cutover ledger is complete.**

  Run the inventory and require every default managed path to link both a positive GC lowering fixture and a green equivalence case. Missing cells are P0 and stop routing changes.

- [ ] **Step 2: Remove `gc_core` from CLI and options.**

  Remove `gc_core` from `cli.Args`, parser state, special-target counting, `run.compile_program_wat`, `EmitOptions`, and test scripts. The old command must fail as an unknown/unsupported CLI argument.

- [ ] **Step 3: Route ordinary emission through shared GC lowering.**

  Change `emit_wat_with_options` and the normal `run.compile_program_wat` path to use the complete GC program lowering. Preserve special Component targets only at their existing explicit boundaries; do not route an unsupported shape to ARC.

- [ ] **Step 4: Replace ARC model/runtime dependencies.**

  Replace `StructLayout`, `StringData`, storage and ownership aliases in `codegen_model.zig` and active emit modules with GC layout/root/canonical-memory helpers. Remove ARC release-plan calls from all active paths.

- [ ] **Step 5: Delete obsolete ARC/profile modules.**

  Delete `codegen_gc_core.zig`, `runtime_arc_wat.zig`, `runtime_prelude_wat.zig` and `codegen_ownership.zig` only after `rg` proves no active import or symbol reference remains. Do not delete dated historical documentation.

- [ ] **Step 6: Convert active output assertions.**

  Rewrite ARC-symbol `.expect` files to assert source behavior, typed GC declarations, roots and canonical ABI markers. Keep source-level compiled tests; remove only implementation assertions that no longer represent active behavior.

- [ ] **Step 7: Run one-backend cutover gates.**

  ```bash
  cd src && zig build -Doptimize=ReleaseSmall && zig test main.zig
  ./src/build/test/run_tests.sh
  RUN_WASM=1 ./src/build/test/run_tests.sh
  bash src/build/test/check_gc_migration_inventory.sh
  ! rg -n --glob '*.zig' 'emit_arc_runtime_prelude|__arc_|codegen_ownership|runtime_arc_wat|runtime_prelude_wat' src/build
  ! rg -n --glob '*.expect' '__arc_' src/build/test
  ```

  Also run Core GC text/list/struct/nested/Tuple probes and all admitted Component/Rust/Wasmtime ready, pending, error, cancel and early-drop runners. Every failure blocks completion; no ARC restoration or hidden fallback is allowed.

- [ ] **Step 8: Commit the one-backend switch.**

  ```bash
  git add src/build src/main.zig src/build/test doc/memory.md doc/roadmap_status.md doc/host_abi_blockers.md examples/gc-p3-runtime
  git commit -m "Switch default backend to Wasm GC"
  ```

### Task 8: Documentation, Release Gate And Deferred Mainline Handoff

**Files:**
- Modify: `doc/memory.md`
- Modify: `doc/design/2026-08-11-gc-first-memory-decision.md`
- Modify: `doc/roadmap_status.md`
- Modify: `doc/host_abi_blockers.md`
- Modify: `doc/pending_blocked.md`
- Modify: `README.md`
- Modify: `examples/gc-p3-runtime/README.md`

**Interfaces:**
- Consumes: one-backend cutover evidence.
- Produces: documentation that accurately distinguishes GC target, implemented backend and deferred capability work.

- [ ] **Step 1: Mark migration complete only from evidence.**

  Change the roadmap from “default `do build` remains ARC” to “default managed paths emit GC” only after Task 7 gates pass. Record exact commands, tool versions and pass counts.

- [ ] **Step 2: Move ARC details to historical records.**

  Keep old allocator/layout/release facts only in dated historical plans or changelog entries. Active memory/runtime docs must describe GC roots, typed objects, canonical memory and explicit resource cleanup.

- [ ] **Step 3: Preserve independent blockers.**

  Keep general async-call lowering, arbitrary producers, general filesystem async, HTTP and pinned borrow/resource evidence as separate pending rows with their own WIT/Component/terminal gates.

- [ ] **Step 4: Run documentation consistency checks.**

  ```bash
  rg -n -i 'default.*ARC|ARC.*active|GC migration.*pending|--gc-core' README.md doc doc/superpowers/specs
  git diff --check
  ```

  Expected: only dated historical records may mention ARC as prior implementation or `--gc-core` as removed migration history; active docs must agree with the one-backend state.

- [ ] **Step 5: Run the release command set.**

  ```bash
  cd src && zig build -Doptimize=ReleaseSmall
  cd src && zig test main.zig
  ./src/build/test/run_tests.sh
  RUN_WASM=1 ./src/build/test/run_tests.sh
  ```

  Expected: all compiler, compiled-test, Wasm validation, Component assembly and admitted Rust/Wasmtime gates pass.

- [ ] **Step 6: Restore deferred mainline in fixed order.**

  Update `doc/roadmap_status.md` and `doc/pending_blocked.md` so the next independent designs start in this order:

  ```text
  1. general async-call lowering
  2. arbitrary producer expressions and generic resource/list shapes
  3. general filesystem async
  4. D2 true host I/O and external HTTP
  ```

- [ ] **Step 7: Commit the release state.**

  ```bash
  git add README.md doc/memory.md doc/design/2026-08-11-gc-first-memory-decision.md doc/roadmap_status.md doc/host_abi_blockers.md doc/pending_blocked.md examples/gc-p3-runtime/README.md
  git commit -m "Close GC-first migration release gate"
  ```

## Completion Criteria

The migration is complete only when all conditions hold:

1. `do build` and `do test --compiled` use GC for every admitted managed path.
2. No active compiler source imports ARC runtime/ownership modules.
3. `--gc-core` is rejected and no hidden backend selector remains.
4. No emitted module mixes ARC handles and GC references.
5. G5b source-level ARC/GC equivalence is green for every admitted row.
6. GC roots survive synchronous control flow and admitted Future/Stream suspension.
7. No GC reference crosses canonical Component ABI.
8. WIT resource drop/cancel/terminal cleanup remains explicit and exactly once.
9. Full compiler, Wasm, Component and Rust/Wasmtime gates pass.
10. Active docs state the same backend and preserve independent post-migration blockers.

## Rollback And Failure Policy

- Before G5c, rollback means revert only the latest task commit; the default ARC route remains available while GC slices are tested separately.
- During G5c, do not delete ARC files until the residual inventory and equivalence matrix are green; if routing fails, revert the cutover commit rather than adding a fallback.
- A failed external Wasm/Component tool gate is recorded with command, tool version, output, impact and retry condition; it is not converted into a pass by skipping the test.
- A source shape outside the ledger remains an explicit capability error and is not widened opportunistically during cutover.

## Plan Self-Review

- **Specification coverage:** value representation, immutable rebuild, roots, Future/Stream, canonical ABI, resource cleanup, one-backend cutover, ARC removal, docs and deferred queue are covered by Tasks 0-8.
- **Placeholder scan:** no `TBD`, `TODO`, “implement later”, or vague “add appropriate tests” steps are used; each step names files, commands and expected results.
- **Type consistency:** `ValueRep`, `GcStructLayout`, `RootPlan`, `AbiPlan` and `ResourcePlan` are the existing plan interfaces consumed by later tasks; no public ownership/reference type is introduced.
- **Scope check:** the plan does not claim general async, arbitrary producers, general filesystem async or HTTP completion; those remain separate after migration.

## Execution Handoff

Plan complete and saved to `doc/superpowers/plans/2026-08-13-gc-first-one-pass-migration.md`. Execute Tasks 0-8 serially with the listed gates. The “one-pass” guarantee is a continuous queue, not a bypass of tests or rollback points.
