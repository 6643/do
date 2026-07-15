# Gen 域按功能竖切 Implementation Plan


## Status (2026-07-13)

**Done (evidence-backed):** Tasks 1–6 vertical domain split landed.

| Check | Result |
|-------|--------|
| `cd src && zig build -Doptimize=Debug` | OK |
| `zig test src/build/codegen_api.zig` | 69 passed |
| `./src/build/test/run_tests.sh` | pass=933 fail=0 skip=3 |
| Leaf `@import("codegen_pipeline")` | none |
| `codegen_pipeline` size | ~3029 lines (was ~19.3k) |
| Cycle break | `gen_hooks` late-bound emit/collect |

Domain files: `gen_collect`, `gen_wasi_emit`, `codegen_ownership`, `gen_storage`, `gen_struct`, `gen_union_emit`, `gen_expr`, `gen_ctrl`, `gen_hooks`.


> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `src/build/codegen_pipeline.zig`（~19k 行）按功能拆成高内聚、单向依赖的 `gen_*` 模块，使 `codegen_pipeline` 收敛为编排核；不引入 `build/gen/` 子目录，不大面积抽象 emit 虚表。

**Architecture:** 稳定下层（`gen_types` / `gen_util` / `gen_union` / `gen_wasi` 表 / `gen_*_wat`）只被上层依赖；collect / host / import 为叶；emit 域（wasi / struct / storage / ownership / union）只依赖下层 + 彼此的 **pub API**；`emitExpr` 与编排核最后收口。跨域环只允许 **局部回调** 或暂时同文件编排，禁止全局 `CodegenBackend` 接口层。

**Tech Stack:** Zig 0.16 编译器源码；回归 `./src/build/test/run_tests.sh`；单测 `zig test src/build/codegen_api.zig`；对外入口保持 `@import("codegen_api.zig")`。

## Global Constraints

- 路径根：仓库 `/home/_/._/do`；编译器源在 `src/build/`（**不是** `tool/`）。
- 扁平文件：新建一律 `src/build/gen_<domain>.zig`；**禁止**新建 `src/build/gen/` 子目录（本阶段）。
- 对外契约：调用方继续 `@import("codegen_api.zig")` 的 `emit_wat` / `emit_test_wat` / `emit_wat_with_options`；行为与诊断字符串零漂移。
- 依赖方向：只允许 **下层 ← 上层**；禁止 `A import B` 且 `B import A`。环上最多注入 1–2 个函数指针/回调，禁止 20+ 钩子的万能 Context。
- 抽象优先级：**数据与纯函数**（layout / 表 / WAT 片段）> 物理搬家 > 局部回调；**禁止**为拆分先上全局 trait/vtable。
- Zig 0.16：无 `usingnamespace`；跨文件用显式 `const foo = mod.foo` 或 `pub const foo = mod.foo` re-export。
- 每刀验收：`cd src && zig build -Doptimize=Debug`；`zig test src/build/codegen_api.zig`（69 tests）；`./src/build/test/run_tests.sh` → `pass=933 fail=0 skip=3`（skip 数若基线变化以当时 summary 为准，**fail 必须为 0**）。
- 文档同刀：`AGENTS.md` Gen 列表、`doc/start_here.md` Gen 表、`CHANGELOG.md` 首条；禁止只改代码不同步索引。
- 单刀目标：一次 PR/提交只完成 **一个域**；`codegen_pipeline` 行数应单调不增（允许 re-export 别名行）。
- 不改语言语义、不改 WASI host 表面、不借拆分修功能 bug（发现 bug 另开任务）。

---

## 现状基线（2026-07-13）

| 文件 | 约行 | 职责 |
|------|------|------|
| `codegen_api.zig` | 668 | 公开入口 + 单测 |
| `codegen_pipeline.zig` | **19326** | 主 lowering（待削） |
| `gen_types.zig` | 1118 | LocalSet / CodegenContext / free* / ExprCallHead |
| `codegen_imports.zig` | 802 | 模块解析 / reach / string-data |
| `gen_util.zig` | 555 | token/scan / core-func 名 / mangled |
| `gen_wasi.zig` | 451 | WASI 表 / parse / lowerability |
| `gen_payload_wat` / `gen_storage_wat` | 418 / 246 | 纯 WAT |
| `codegen_host_imports.zig` | 189 | `@host("env", member, sig)` host |
| `gen_union.zig` | 57 | UnionLayout 类型与 clone/free |

`codegen_pipeline` 内粗分（跨域调用已密，不可“整文件剪切即完事”）：

| 域 | 约行 | 代表符号（行号随改动漂移，以符号名为准） |
|----|------|------------------------------------------|
| WASI emit | ~1.6k | `emitWasiHostImportExpr`, `emitWasi*Result*`, multi-assignment |
| collect/parse | ~2.6k | `collectStructDecls`, `collectFuncDecls`, layouts, generic instance collect |
| storage/tuple | ~2.5k | `emitStorageBinding`, `emitTuple*`, agg literal |
| struct | ~1.8k | `emitStructBinding`, field set/meta, literal |
| union | ~1.7k | `emitUnionValue`, `emitUnionBinding`, payload-enum layout |
| ownership | ~0.5–0.8k release + last-use 缠绕 | `emitOwnershipReleasePlan`, `directManagedLastUseMoveSource*` |
| expr/ctrl/编排 | 其余 | `emitExpr*`, `emitBody`, `emitIf*`, `emitLoop*`, `emit_wat*` |

---

## 目标依赖图（终态）

```text
                    type_name / lexer / ownership / ownership_facts
                                      ↑
     gen_util   gen_union   gen_payload_wat   gen_storage_wat   gen_wasi(表)
                                      ↑
                               gen_types
                                      ↑
              codegen_host_imports          codegen_imports
                                      ↑
         gen_collect ──────────────────────────────────┐
                                      ↑                 │
    codegen_ownership   gen_struct   gen_storage   gen_union_emit   gen_wasi_emit
                                      ↑                 │
                         gen_expr / gen_ctrl  ←──────────┘（仅 pub + 少量回调）
                                      ↑
                               codegen_pipeline（编排）
                                      ↑
                                   codegen_api.zig
```

**允许的“外部”依赖（叶与 emit 共用）：**

- `gen_types` 类型与 free
- `gen_util` 纯扫描
- `lexer.Token`、`imports.Module*`
- `ownership` / `ownership_facts` 的 plan 类型
- 纯 WAT 与 `type_name`

**不允许：** emit 域互相 `import` 对方的私有 helper；`gen_wasi_emit` import 整个 `codegen_pipeline`。

---

## 成功度量

| 里程碑 | `codegen_pipeline` 行数（目标） | 新增/加厚模块 | 验收 |
|--------|--------------------------|---------------|------|
| M0 基线冻结 | ~19326 | — | 回归绿（本计划开始前） |
| M1 叶与 collect | **≤ 16k**（实际 ~16946 + `gen_collect` ~2595） | `gen_collect` | 回归绿 + 文档 |
| M2 WASI emit | **≤ 14k** | `gen_wasi_emit` | 同上；WASI fixtures 不退化 |
| M3 struct + storage | **≤ 10k** | `gen_struct`, `gen_storage` | 同上 |
| M4 ownership + union emit | **≤ 7k** | `codegen_ownership`, `gen_union_emit` | 同上 |
| M5 expr/ctrl 收口 | **编排核 ≤ 3k**（理想）或过渡 **≤ 5k** | `gen_expr`, `gen_ctrl` | 同上 |
| 终态 | `codegen_pipeline` 仅 `emit_wat*` / 组装 `CodegenContext` / 调域入口 | 各域 1–3k | 全绿 |

中间里程碑允许停在 M2/M3 做功能开发；**不要**在 M5 未设计回调前硬拆 `emitExpr`。

---

## File map（计划创建/修改）

| 路径 | 动作 | 职责 |
|------|------|------|
| `src/build/gen_collect.zig` | **Create** | struct/enum/func/layout/generic-instance **collect** + 相关 parse 叶 |
| `src/build/gen_wasi_emit.zig` | **Create** | WASI host **emit**（result/union/multi-assign/record），不拥有表 parse |
| `src/build/gen_struct.zig` | **Create** | struct bind / field set / literal / field-meta emit |
| `src/build/gen_storage.zig` | **Create** | storage/tuple bind、agg literal、与 pack 编排（调用 `gen_*_wat`） |
| `src/build/codegen_ownership.zig` | **Create** | release plan emit；last-use 能搬则搬，不能则留 lower 并写明 |
| `src/build/gen_union_emit.zig` | **Create** | union value/binding/branch emit（layout 类型仍在 `gen_union`） |
| `src/build/gen_expr.zig` | **Create（后期）** | `emitExpr*` 与 call/path/get/set 主分发 |
| `src/build/gen_ctrl.zig` | **Create（后期）** | body/if/loop/defer/guard |
| `src/build/codegen_pipeline.zig` | Modify | 删除已迁出符号；`const x = gen_*.x` 或 `pub const` re-export |
| `src/build/codegen_api.zig` | Modify | 仅当单测需要的符号改为 `pub` re-export 路径变化时 |
| `src/build/gen_types.zig` | Modify | 仅当跨域共享类型/小纯函数必须上移时 |
| `src/build/gen_util.zig` | Modify | 仅当发现新的纯扫描/名表重复时上移 |
| `AGENTS.md`, `doc/start_here.md`, `CHANGELOG.md` | Modify | 每里程碑同步 |

**不创建：** `src/build/gen/` 目录、`gen_iface.zig`、`codegen_backend.zig`。

---

## 每刀标准作业程序（SOP）

每完成下面任一 Task，必须按此顺序（可复制到 PR 描述）：

1. **列符号清单**：从 `codegen_pipeline` 用 `rg -n '^pub fn <Name>'` 列出本域 `pub fn` / 仅本域用的 `fn`。
2. **算闭包**：对本域种子函数求 codegen_pipeline 内调用闭包；**只搬闭包内且不反向依赖 emitExpr 全家桶的符号**。闭包爆炸 → 缩小种子或先上移纯 helper 到 `gen_util`/`gen_types`。
3. **定 import 边**：新文件顶部只 `@import` 允许的下层；若需要 `emitExpr`，在新文件定义：
   ```zig
   pub const EmitExprFn = *const fn (
       allocator: std.mem.Allocator,
       tokens: []const lexer.Token,
       start_idx: usize,
       end_idx: usize,
       locals: *LocalSet,
       ctx: CodegenContext,
       out: *std.ArrayList(u8),
   ) anyerror!void;
   ```
   由 `codegen_pipeline` 传入实际 `emitExpr`（签名以当时源码为准，搬迁时对照 `emitExpr` 定义改，禁止臆造参数）。
4. **机械搬家**：保持函数体字节级行为不变；`pub` 性与 `codegen_api.zig` 单测所需 `pub const` re-export 对齐。
5. **接线**：`codegen_pipeline` 删除原体，加 `const foo = gen_xxx.foo`（文件内用）或 `pub const foo = gen_xxx.foo`（`codegen_api.zig`/单测需要）。
6. **编译**：`cd src && zig build -Doptimize=Debug`
7. **单测**：`zig test src/build/codegen_api.zig` → All 69 tests passed
8. **回归**：`./src/build/test/run_tests.sh` → `fail=0`
9. **文档**：更新三处索引 + CHANGELOG 一条
10. **提交**（若用户要求 commit）：主题形如 `refactor(gen): extract gen_wasi_emit from codegen_pipeline`

---

### Task 0: 冻结基线与依赖规则（只读 + 文档锚点）

**Files:**
- Modify: `docs/superpowers/plans/2026-07-13-gen-domain-split.md`（本文件，执行时勾选）
- 不改业务代码

**Interfaces:**
- Consumes: 无
- Produces: 可复现的基线数字（行数、回归 summary）

- [ ] **Step 1: 记录基线**

```bash
wc -l src/build/codegen_pipeline.zig src/build/gen*.zig | sort -n
cd src && zig build -Doptimize=Debug
zig test src/build/codegen_api.zig 2>&1 | tail -3
./src/build/test/run_tests.sh 2>&1 | tail -3
```

Expected: build ok；`All 69 tests passed`；`pass=933 fail=0 skip=3`（或当前主线等价绿）。

- [ ] **Step 2: 在 PR/会话笔记中粘贴上述三行输出**（防止“拆完才发现基线已红”）

- [ ] **Step 3: 确认本阶段不做的事**

- 不做 `src/build/gen/` 目录
- 不上全局 emit 接口
- 不改 sema/parser 行为

---

### Task 1: 提取 `gen_collect.zig`（声明收集叶） — DONE 2026-07-13

**Files:**
- Create: `src/build/gen_collect.zig` (~2595)
- Modify: `src/build/codegen_pipeline.zig` (~19326 → ~16946)
- Modify: `AGENTS.md`, `doc/start_here.md`, `CHANGELOG.md`
- Test: `zig test src/build/codegen_api.zig` 69/69；`run_tests.sh` pass=933 fail=0 skip=3

**Interfaces:**
- Consumes: `gen_types` / `gen_util` / `codegen_imports` / `gen_union` / `gen_wasi` / `type_name` / `lexer` / `imports` / `test_runner`
- Produces: struct/enum/func/layout collect、parse helpers 闭包、`findStruct*`、pack leaf (`isPackManagedHandleLeaf` / `leafPayloadBytesForPack`) 等；**无** `emit*`；**不** import `codegen_pipeline`
- **本刀未搬**: `collectGenericFuncInstances*`（除被 collectFunc 闭包拖入的部分外的大块 generic instance emit 侧）、body locals collect

- [x] **Step 1: 生成种子与闭包**

```bash
rg -n '^pub fn collect|^pub fn ensureStoragePack|^pub fn ensurePreopen|^pub fn appendStructFields|^pub fn managedLeafFieldName|^pub fn nextStructLayoutTypeId' src/build/codegen_pipeline.zig
```

用脚本对种子求 codegen_pipeline 内调用闭包；打印 `extra` 中含 `emit` 前缀的项。若存在 → 从种子中删除对应 collect 或先把被调用的纯函数上移 `gen_util`/`gen_types`。

- [ ] **Step 2: 创建 `gen_collect.zig` 头**

```zig
//! Declaration / layout / generic-instance collection for codegen (no emit).
const std = @import("std");
const imports = @import("imports.zig");
const lexer = @import("lexer.zig");
const test_runner = @import("test_runner.zig");
const gen_util = @import("gen_util.zig");
const gen_types = @import("gen_types.zig");
const gen_union = @import("gen_union.zig");
const codegen_imports = @import("codegen_imports.zig");
const gen_wasi = @import("gen_wasi.zig");
// 仅添加闭包真正用到的 const 别名；禁止 import codegen_pipeline
```

- [ ] **Step 3: 搬家 + `codegen_pipeline` re-export**

```zig
// codegen_pipeline.zig
const gen_collect = @import("gen_collect.zig");
pub const collectStructDecls = gen_collect.collectStructDecls;
pub const collectFuncDecls = gen_collect.collectFuncDecls;
pub const collectStructLayouts = gen_collect.collectStructLayouts;
// …其余本域 pub 符号同样处理；文件内私有使用改为 const 别名
```

- [ ] **Step 4: 验证**

```bash
cd src && zig build -Doptimize=Debug
zig test src/build/codegen_api.zig 2>&1 | tail -5
./src/build/test/run_tests.sh 2>&1 | tail -5
wc -l src/build/codegen_pipeline.zig src/build/gen_collect.zig
```

Expected: fail=0；`codegen_pipeline` 行数 **明显下降**（目标合计收集域 ~2k 级迁出）；`gen_collect` 无 `@import("codegen_pipeline.zig")`。

- [ ] **Step 5: 文档**

- `AGENTS.md` Gen 列表增加 `gen_collect.zig`
- `doc/start_here.md` Gen 表一行
- `CHANGELOG.md` 首条：`refactor(gen): extract gen_collect`

- [ ] **Step 6: Commit（若授权）**

```bash
git add src/build/gen_collect.zig src/build/codegen_pipeline.zig src/build/codegen_api.zig AGENTS.md doc/start_here.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
refactor(gen): extract gen_collect from codegen_pipeline

Move declaration/layout collection out of the lowering god file.
EOF
)"
```

---

### Task 2: 提取 `gen_wasi_emit.zig`（WASI 发射域）

**Files:**
- Create: `src/build/gen_wasi_emit.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: `src/build/gen_wasi.zig`（仅当发现 emit 误放在表模块时下移/上移，保持“表 vs emit”分离）
- Modify: `AGENTS.md`, `doc/start_here.md`, `CHANGELOG.md`
- Test: 同上全量；额外留意 `compile_ok` 中 wasi / preopen / stream fixtures

**Interfaces:**
- Consumes: `gen_wasi`（`WasiHostImport`, `wasiLowering`, coarse error helpers）、`gen_types`、`gen_util`、`gen_union`、`gen_storage_wat` / `gen_payload_wat`（若直接拼 WAT）、**可选** `EmitExprFn` 回调
- Produces:
  - `emitWasiHostImportExpr`
  - `emitWasiResult*Call` / `*AsUnionValue` / `*Values` / multi-assignment 系列
  - `emitWasiRecord*` / `emitWasiDescriptorHandleArg` / `emitWasiStringArg` / …
- **不搬:** `collectWasiHostImports`（已在 `gen_wasi`）、reach validate（已在 `codegen_imports`）

- [ ] **Step 1: 列 WASI emit 符号**

```bash
rg -n '^pub fn emitWasi|^fn emitWasi' src/build/codegen_pipeline.zig
```

- [ ] **Step 2: 检查对 `emitExpr` 的依赖**

```bash
rg -n 'emitExpr' src/build/codegen_pipeline.zig | rg 'emitWasi|Wasi' || true
# 对每个 emitWasi* 函数体是否调用 emitExpr：
rg -n 'emitExpr\(' src/build/codegen_pipeline.zig
```

若仅少数函数需要：在 `gen_wasi_emit.zig` 为这些函数 **增加参数** `emit_expr: EmitExprFn`，或提供薄封装：

```zig
pub fn emitWasiHostImportExpr(
    allocator: std.mem.Allocator,
    // …原参数…
    emit_expr: EmitExprFn,
) !void {
    // 体内原 emitExpr(...) 改为 try emit_expr(...)
}
```

`codegen_pipeline` 调用处传入 `emitExpr`（或与签名匹配的包装）。**禁止** `gen_wasi_emit` import `codegen_pipeline`。

- [ ] **Step 3: 搬家 + 接线 + 验证（SOP 4–10）**

```bash
cd src && zig build -Doptimize=Debug
zig test src/build/codegen_api.zig 2>&1 | tail -5
./src/build/test/run_tests.sh 2>&1 | tail -5
wc -l src/build/codegen_pipeline.zig src/build/gen_wasi_emit.zig
```

Expected: `gen_wasi_emit` ~1.2–1.8k 行；`codegen_pipeline` ≤ 约 16k→14k 量级；fail=0。

- [ ] **Step 4: 文档与 commit**

`CHANGELOG`: `refactor(gen): extract gen_wasi_emit`

---

### Task 3: 提取 `gen_struct.zig` 与 `gen_storage.zig`

**Files:**
- Create: `src/build/gen_struct.zig`
- Create: `src/build/gen_storage.zig`
- Modify: `src/build/codegen_pipeline.zig`
- Modify: docs 三件套

**Interfaces:**
- `gen_struct` Consumes: `gen_types`, `gen_util`, `gen_payload_wat`/`gen_storage_wat`（若需要）, `gen_collect` 仅 **查找** API（`findStructDecl` 若仍在 lower 则先把 find* 纯函数迁 `gen_types` 或 `gen_collect`）
- `gen_storage` Consumes: 同上 + `type_name`；可被 struct 调用的 **仅限 pub**（例如 pack width）；**禁止** storage↔struct 私有互通——共享逻辑上移 `gen_types` 或小 `gen_pack.zig`（仅当重复 ≥2 次且稳定时才建 pack 文件，YAGNI）
- Produces struct: `emitStructBinding`, `emitStructLiteralExpr`, `emitManagedStruct*`, `emitStructField*`, …
- Produces storage: `emitStorageBinding`, `emitStorageAggLiteral`, `emitTuple*`, `emitStorage*Ptr` 编排（薄包装可继续转调 `gen_storage_wat`）

**拆分顺序（串行）：**

- [ ] **Step 1: 先 `gen_storage`**（tuple/storage 对 expr 回调可能更少；用闭包验证）

- [ ] **Step 2: 再 `gen_struct`**（常依赖 storage ptr/pack 的 pub API）

- [ ] **Step 3: 若出现 struct↔storage 环**

优先把共享纯函数移到：

1. `gen_types` / `type_name` / 已有 `gen_*_wat`  
2. 仍不够再抽 `gen_pack.zig`（纯宽度/叶子，**无 emit**）

- [ ] **Step 4: 全量验证 + 文档 + commit**

```bash
wc -l src/build/codegen_pipeline.zig src/build/gen_struct.zig src/build/gen_storage.zig
# 目标：codegen_pipeline ≤ 10k 量级
```

---

### Task 4: 提取 `codegen_ownership.zig` 与 `gen_union_emit.zig`

**Files:**
- Create: `src/build/codegen_ownership.zig`
- Create: `src/build/gen_union_emit.zig`
- Modify: `src/build/codegen_pipeline.zig`, docs

**Interfaces:**
- `codegen_ownership` Consumes: `ownership`, `ownership_facts`, `gen_types`；**尽量不**依赖 emitExpr
  - **优先搬:** `emitReleaseManagedLocals*`, `build*OwnershipPlan`, `emitOwnershipReleasePlan`, `collectManagedOwnershipLocals`, `hasManagedLocals`, reachability of body end helpers **若闭包干净**  
  - **可后置:** `directManagedLastUseMoveSource*`（闭包常拖入 findFunc/infer/call 匹配）——若闭包 >~1.5k 外部符号，**本 Task 明确留下 codegen_pipeline**，在文件头注释 `// last-use move stays in codegen_pipeline until gen_expr exists`
- `gen_union_emit` Consumes: `gen_union`, `gen_types`；Produces: `emitUnionValue`, `emitUnionBinding`, `emitUnionBranch*`, `buildPayloadEnumUnionLayout`（若仍在 lower）

- [ ] **Step 1: ownership release 闭包（不含 LastUse）**

种子：`emitReleaseManagedLocals`, `emitOwnershipReleasePlan`, `buildReturnOwnershipPlan`, `buildFallthroughOwnershipPlan`, `buildBlockOwnershipPlan`, `collectManagedOwnershipLocals`, `managedLocalKindForType`, `isManagedLocalType`。

- [ ] **Step 2: 搬家 release 路径；LastUse 单独决策（搬或注释留下）**

- [ ] **Step 3: union emit 闭包；避免 import gen_struct 私有——字段 payload 经 pub 或参数传入 layout**

- [ ] **Step 4: 验证**

```bash
wc -l src/build/codegen_pipeline.zig src/build/codegen_ownership.zig src/build/gen_union_emit.zig
# 目标：codegen_pipeline ≤ 7k 量级
```

---

### Task 5: `gen_expr` + `gen_ctrl` + 编排核收口（高风险，单独里程碑）

**Files:**
- Create: `src/build/gen_expr.zig`
- Create: `src/build/gen_ctrl.zig`
- Modify: `src/build/codegen_pipeline.zig`（应只剩 `emit_wat*`、上下文组装、域调用）
- Modify: docs；可选 `src/main.zig` 若需 ` _ = @import` 拉单测（通常不需要）

**Interfaces:**
- `gen_expr`：拥有 `emitExpr` / `emitExprWithMoveContext` 及 call 分发；**可以** import `gen_wasi_emit` / `gen_struct` / `gen_storage` / `gen_union_emit` / `codegen_ownership` 的 **pub**
- `gen_ctrl`：`emitBody`, `emitIf*`, `emitLoop*`, `emitDefer*`, `emitGuard*`；调用 `gen_expr.emitExpr` 与 ownership pub
- `codegen_pipeline`：`emit_wat` / `emit_test_wat` 组装 imports/collect/layouts 后调 `emitUserFunc` / start
- **环处理：** 若 `gen_expr` 需要 ctrl 的 helper，把 helper 上移纯函数或保留在 `codegen_pipeline` 编排层，**禁止** expr↔ctrl 双向 import

- [ ] **Step 1: 先画调用边（只读）**

```bash
rg -n 'emitExpr\(|emitBody\(|emitIfBlock\(|emitLoopBlock\(' src/build/codegen_pipeline.zig | head -80
```

写一张“谁调谁”的简短表进 commit message 或本 plan 执行笔记。

- [ ] **Step 2: 迁 `gen_ctrl`（通常依赖 emitExpr → 先留回调或暂与 expr 同 PR 但分 commit）**

- [ ] **Step 3: 迁 `gen_expr`**

- [ ] **Step 4: 削 `codegen_pipeline` 到编排核**

目标结构示意：

```zig
// codegen_pipeline.zig — orchestration only
pub fn emit_wat_with_options(...) ![]u8 {
    // collect host/wasi/structs/funcs/layouts via gen_collect / codegen_host_imports / gen_wasi / codegen_imports
    // build CodegenContext
    // emit prelude + user funcs via gen_ctrl/gen_expr
}
```

- [ ] **Step 5: 全量验证；`wc -l` 对照 M5 成功度量**

- [ ] **Step 6: 文档终态表 + CHANGELOG**

---

### Task 6: 清理与防回归（拆分收尾）

**Files:**
- Modify: `codegen_pipeline.zig`（删除只转发的无意义 re-export 堆叠——**仅当**无外部/单测引用时）
- Modify: `AGENTS.md` / `start_here` 标明“编排 vs 域”
- Optional: `src/build/test/README.md` 若存在拆分说明

- [ ] **Step 1: 检查环**

```bash
# 不应出现
rg -n 'codegen_pipeline' src/build/gen_collect.zig src/build/gen_wasi_emit.zig \
  src/build/gen_struct.zig src/build/gen_storage.zig src/build/codegen_ownership.zig \
  src/build/gen_union_emit.zig src/build/codegen_host_imports.zig src/build/codegen_imports.zig \
  src/build/gen_util.zig src/build/gen_types.zig
```

Expected: **无匹配**（叶与域不 import lower）。

- [ ] **Step 2: 检查 gen_expr/gen_ctrl 无互相 import**

```bash
rg -n 'gen_ctrl|gen_expr' src/build/gen_expr.zig src/build/gen_ctrl.zig
```

Expected: 单向或都只被 lower import。

- [ ] **Step 3: 最终行数报告写入 CHANGELOG 或本 plan 笔记**

```bash
wc -l src/build/gen*.zig | sort -n
```

---

## 风险与回滚

| 风险 | 表现 | 缓解 | 回滚 |
|------|------|------|------|
| import 环 | Zig 编译失败 | 回调 / 上移纯函数 / 缩小本刀种子 | `git revert` 单域 commit |
| pub 丢失 | `zig test codegen_api.zig` 报 not marked pub | `pub const x = mod.x` | 同上 |
| 静默行为变 | 回归 fail | 禁止“顺手重构”函数体 | 同上 |
| 闭包爆炸 | 一刀搬半个 lower | 停刀，改种子；勿强行 M5 | 不提交半截 |
| 文档漂移 | 新人仍改 codegen_pipeline 找 collect | 每刀更新 AGENTS/start_here | 补文档 commit |

---

## 明确非目标

- `sema.zig` 拆分（另案）
- `src/build/gen/` 目录化
- 全局 `CodegenBackend` / 测试用 mock 框架
- 借拆分实现 G6.x / 新语言特性
- 合并或删除 skip=3 的历史 skip 用例

---

## 执行顺序小结

```text
Task 0 基线
  → Task 1 gen_collect          （叶，高 ROI）
  → Task 2 gen_wasi_emit        （功能热点，弱环）
  → Task 3 gen_storage → gen_struct
  → Task 4 codegen_ownership → gen_union_emit
  → Task 5 gen_ctrl / gen_expr / 编排核   （最后）
  → Task 6 防回归检查
```

可在 Task 2 或 Task 3 后 **暂停拆分、做产品功能**；恢复时从下一 Task 基线 `wc -l` 重新量测。

---

## Self-Review

1. **Spec coverage:** 按功能拆、高内聚低耦合、少外部依赖、早接口的取舍 → 已写入 Global Constraints + 依赖图 + 非目标；目录重构明确不做；每里程碑有行数与回归门槛。
2. **Placeholder scan:** 无 TBD；回调签名要求“以当时 `emitExpr` 为准”避免锁死过时参数。
3. **Type consistency:** 模块名 `gen_collect` / `gen_wasi_emit` / `gen_struct` / `gen_storage` / `codegen_ownership` / `gen_union_emit` / `gen_expr` / `gen_ctrl` 前后一致；WASI **表**在 `gen_wasi`，**emit** 在 `gen_wasi_emit`。

---

## 执行方式（完成后由用户选择）

Plan complete and saved to `docs/superpowers/plans/2026-07-13-gen-domain-split.md`.

**1. Subagent-Driven（推荐）** — 每 Task 新开 subagent，Task 间 review  
**2. Inline Execution** — 本会话按 executing-plans 连续做，检查点停顿  

**Which approach?**
