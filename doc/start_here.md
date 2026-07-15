# 下次启动入口

这是当前主线的接手入口。状态以本文为准; 计划摘要见 `doc/master_plan.md`; 近期变更见 `CHANGELOG.md`。不保留向后兼容旧路径或历史流水账。

## 1. 阅读顺序

1. [README.md](../README.md) — 能力摘要、非目标、下一阶段计划
2. [CHANGELOG.md](../CHANGELOG.md) — 近期已完成变更
3. [doc/pending_blocked.md](pending_blocked.md) — **待处理与阻断** (G6 / P2 / deferred / skip)
4. [doc/master_plan.md](master_plan.md) — 当前规划摘要
5. [doc/roadmap_status.md](roadmap_status.md) — 当前执行状态
6. [doc/memory.md](memory.md) — 运行时 / ARC 实现 (按需)

模块地图见仓库根 [AGENTS.md](../AGENTS.md)。

**目录约定 (2026-07-12 起)**:

| 路径 | 含义 |
| --- | --- |
| `lib/` | 标准库与 builtin/core 总表 (`lib/_.do`); `@lib("file.do")` 解析根 |
| `src/` | 工具链与编译器 (原 `tool/`); `cd src && zig build` |
| `src/build/test/` | 回归 harness 与 fixture |
| `src/build/test/lib/` | fixture 专用 `~/` 依赖根 (`DO_LIB_ROOT`), 不是公开标准库 |

## 2. 当前停点

| 项 | 状态 |
| --- | --- |
| v1 子集 | 发布候选已收口 |
| 阶段 A–F、H | 已完成 |
| 阶段 D | 可推进项已完成; D2.1 已按 B 方案绿色 regression 收口 |
| 阶段 G | G1–G5、G6.1、G6.3、G6.4 完成; **G6.2 仍阻断** |
| 阶段 I | **已关闭** (I1 递归/self-tail TCO + I2 `Tuple<...>` 第一版) |
| 架构审查/重构 | 五轮已落地 (见 §4); 默认不继续拆 god module |

## 3. 验证入口

接手或改编译器后, 优先跑这三条; 细节证据记在 `doc/roadmap_status.md`。

```bash
# 默认完整回归 (当前基线)
./src/build/test/run_tests.sh
# 期望: pass=933 fail=0 skip=3

# gen 单元测试
cd src && zig test build/codegen_api.zig
# 期望: All 69 tests passed.

# 发布前 smoke
./src/build/test/run_release_smoke.sh
```

可选扩展:

```bash
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
# 最近基线: pass=833 fail=0 skip=3; wasm run summary: pass=6 fail=0
```

| 基线项 | 最近值 |
| --- | --- |
| 默认回归 | `pass=933 fail=0 skip=3` |
| `zig test build/codegen_api.zig` | `69/69` |
| `compile_ok` / `compiled_ok` / `compile_err` | do≈`272` / `77` / `39` |
| 剩余 skip | `16_loop_recv_value`、`96_file_lib_resource_shape`、`118_wasi_p3_std_wrappers` (recv/WASI 后置) |
| 诊断 code | `errorSummary` / `errorHint` 各 57 条 (含 `UnsupportedLowering` / `UnsupportedTupleStorageLeaf`) |

发布候选的其它一致性检查 (链接、fixture companion、WASI registry、shell harness 等) 在收口交付时按 `doc/roadmap_status.md`「文档治理 / gate 复跑」清单执行; **不必每次把整表抄进本文**。

## 4. 架构模块地图

扁平拆分后的编译器边界 (与 `AGENTS.md` 一致):

| 层级 | 模块 | 职责 |
| --- | --- | --- |
| 流水线 | `lexer` → `parser` → `sema` → `codegen` | 主编译路径 |
| 共享纯函数 | `type_name` | 类型/布局 SSOT (scalar/storage/managed/Tuple scheme A) |
| | `sema_error` | ErrorSite 与 sema 错误构造 |
| | `diagnostics` | check/LSP 共用前端诊断收集 (原 `src/lsp/diagnostics.zig` 已删除) |
| Sema 域 | `sema.zig` | 公开入口 (`check_program` / `take_last_error_site`) + 编排 |
| | `sema_tokens.zig` | token/name/scan 谓词与行扫描 |
| | `sema_shapes.zig` | 共享 shape 类型 (`FuncShape` / `StructInfo` / …) |
| | `sema_function_signatures` / `_calls` / `_lambdas` | 签名 / 调用·泛型 / lambda |
| | `sema_function_support.zig` | 多个 sema 域共享的语义辅助函数 |
| | `sema_structures.zig` | struct 字段·ctor / path / Tuple |
| | `sema_type_checks.zig` | 类型声明 / enum·error·payload / union / type refs |
| | `sema_imports.zig` | host/local import + 已知 WASI 签名校验 |
| | `sema_control.zig` | loop/label / defer / field reflection / assign / constraint |
| Gen 域 | `codegen_api.zig` | 公开入口 + 单测 |
| | `codegen_pipeline.zig` | 编排核（`emit_wat*` / hooks install）+ 最小 re-export |
| | `codegen_generics.zig` | 泛型实例化 / 类型绑定 / callback prebind（不 import lower） |
| | `codegen_callbacks.zig` | 晚绑定 emit 回调（破 control/union→expression、struct→union 反向边） |
| | `codegen_model.zig` | 不可变声明、shape、ownership/free、`ExprCallHead` |
| | `codegen_context.zig` | LocalSet、可变 codegen context、local-name helpers |
| | `codegen_constants.zig` | ABI/layout ID 与 compiler temporary-local 名称 |
| | `codegen_collect_util.zig` / `codegen_collect_structs.zig` / `codegen_collect_functions.zig` / `codegen_collect_declarations.zig` | 类型 parse·bind / struct·layout / func / enum collect |
| | `codegen_emit_expression.zig` / `codegen_emit_call.zig` | 表达式与调用 dispatch |
| | `codegen_body.zig` / `codegen_collect_reflection.zig` | body-local、loop、multi-result 与 field-reflection collection |
| | `codegen_emit_control.zig` | 控制流 emit（body/if/loop/defer/guard） |
| | `codegen_emit_storage_operations.zig` / `codegen_emit_storage_values.zig` / `codegen_storage_layout.zig` | storage emit、layout 与 Tuple pack helpers |
| | `codegen_emit_tuple.zig` | Tuple / pure-scalar pack helpers |
| | `codegen_emit_struct.zig` / `codegen_emit_struct_fields.zig` | struct binding / field / literal emit |
| | `codegen_emit_union.zig` | union value / binding emit |
| | `codegen_emit_wasi.zig` | WASI host 调用/结果 emit（`EmitExprFn`/hooks，不 import lower） |
| | `codegen_ownership.zig` | ARC release plan emit / 作用域可达性辅助 |
| | `codegen_tokens.zig` | token/range/scan/decode 工具 |
| | `codegen_names.zig` | public name、core-func 名表、mangled 符号 |
| | `codegen_host_imports.zig` | unified `@host("env", member, sig)` host import collect/parse |
| | `codegen_imports.zig` | 模块 import 解析、reach、string-data |
| | `gen_wasi` / `gen_union` | WASI 表/parse; union layout |
| | `wat_payload` | 标量 payload load/store、Tuple 叶子 pack/unpack |
| | `wat_storage` | storage 指针/header/alias; `HEADER=8` |
| | `runtime_arc_wat` | ARC runtime WAT + layout 类型 SSOT |
| | `runtime_prelude_wat` | string-data memory emit + re-export ARC API |
| | `wat_function_body` / `wat_component_metadata` | 其它 WAT 写出切片 |
| 旁路 | `codegen_ir` | **仅**标量 `start` 旁路 + unit; **不是**主 emit 路径 |
| CLI | `src/main.zig` | 分派; `do test` 经 `runTest` → `loadProgram` |

**刻意未做**: 批量把真 overload `NoMatchingCall` 改成 `UnsupportedLowering`; 合并静态/compiled 双 runner; 把 `codegen_ir` 扩成主路径; 继续硬拆 `codegen_emit_storage_operations` / `codegen_emit_expression` / `parser` / `imports` / `test_runner`（hooks 耦合或高风险，ROI 低）。

**已落地架构竖切**: `sema` 与 `gen` 均已按域拆成扁平 `*_` 模块 (见上表与 `AGENTS.md`); 对外仍经 `sema.zig` / `codegen_api.zig` 入口。Batch B: collect 四叶、sema scan/func 子域、runtime ARC SSOT。

## 5. 当前阻断

| ID | 说明 | 恢复条件 |
| --- | --- | --- |
| G6.2 | `descriptor.read-directory` (stream/future) | 未来 async/Future/Task runtime |
| G6.3 | **已关闭 (方案 B)** create/bind/drop + dual address | 见 `compile_ok/291`–`294`; 真 host 仍属 D2 |
| 06.2 | 已拆到 G2–G6; 剩余由 G6.2 承接 | 同上 |

**待处理 / 阻断 / 延期**: 权威清单见 [pending_blocked.md](pending_blocked.md) (G6 blocked、P2 泛型左侧反推、skip、deferred 非目标)。

**Wasm ref 语法策略 (未实现)**: `externref`→将来 `@host_ref`; 无公开 `anyref`/`funcref` 类型; i32 内存指针不做 do 类型 — [design/wasm_ref_host_syntax.md](design/wasm_ref_host_syntax.md) (D10)。扩讨论存档（已搁置）: [design/2026-07-13-wasm-wasi-support-discussion.md](design/2026-07-13-wasm-wasi-support-discussion.md)。

已落地对照 (勿当待办): pure-scalar Tuple 子槽 `ok/192`; managed 叶子 storage `compile_ok/270`–`271`; field_set `ok/191`。

## 6. 当前计划候选

用户说 `go` / `next` 时, 按以下优先级 (细节与恢复条件见 [pending_blocked.md](pending_blocked.md)):

1. **发布候选维护**: 回归红灯、文档漂移、可独立验证的小修
2. **等待决策**: G6.2 依赖 async/Future/Task runtime 立项 (`descriptor.read-directory`)
3. **可选授权**: deferred 项 (D2 真 host / ownership / JSON / LSP / codegen 再拆) — 默认不自动开做

**已关闭边界速查**:

- I1: 直接/互递归; 参数侧已定型泛型递归; self-tail TCO 子集; 左侧反推泛型仍后置; `defer`/storage/managed/多返回/cleanup **不** TCO
- I2: `Tuple` 位置构造 + `@get`; 嵌套永不拍平; pure-scalar struct 子槽 + managed 叶子 storage + path chain

## 7. 变更与推进协议

- 每次只做一个可验证小任务; 完成后更新本文基线, 必要时写 `CHANGELOG.md`。
- 语法/语义变更同步 `doc/spec_rules.md`、`doc/grammar.peg`、相关 `doc/syntax/*.md` 与回归。
- 工具行为变更同步 `README.md`、`src/build/test/README.md` 与黑盒 fixture。
- **只保留最新**: 不维护向后兼容路径、过期草案、空占位目录或历史 gate 流水账。
- 不默认: 重开 get/pkg/push; 去掉内部 `@` 前缀; direct wasm binary emitter; 完整 WASI/Component; 大规模重写 parser/sema/codegen。
- 产品命令边界: `do run` = core wasm smoke (`wasm-tools`+`node`); `do fmt` = 单文件 stdout/check/write; `do lsp` = diagnostics/formatting/tokens/hover/completion/definition (无 rename); `do check` = 前端诊断 only。
