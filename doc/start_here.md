# 下次启动入口

这是当前主线的接手入口。状态以本文为准; 计划摘要见 `doc/master_plan.md`; 近期变更见 `CHANGELOG.md`。不保留向后兼容旧路径或历史流水账。

## 1. 阅读顺序

1. [README.md](../README.md) — 能力摘要、非目标、下一阶段计划
2. [CHANGELOG.md](../CHANGELOG.md) — 近期已完成变更
3. [doc/master_plan.md](master_plan.md) — 当前规划与阻断
4. [doc/roadmap_status.md](roadmap_status.md) — 当前执行状态
5. [doc/memory.md](memory.md) — 运行时 / ARC 实现 (按需)

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
| 阶段 G | G1–G5、G6.4 完成; **G6.1–G6.3 仍阻断** |
| 阶段 I | **已关闭** (I1 递归/self-tail TCO + I2 `Tuple<...>` 第一版) |
| 架构审查/重构 | 五轮已落地 (见 §4); 默认不继续拆 god module |

## 3. 验证入口

接手或改编译器后, 优先跑这三条; 细节证据记在 `doc/roadmap_status.md`。

```bash
# 默认完整回归 (当前基线)
./src/build/test/run_tests.sh
# 期望: pass=907 fail=0 skip=3

# 聚合单元测试
cd src && zig test main.zig
# 期望: All 115 tests passed.

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
| 默认回归 | `pass=907 fail=0 skip=3` |
| 聚合 unit | `115/115` |
| `compile_ok` / `compiled_ok` / `compile_err` | do≈`270` / `74` / `40` |
| 剩余 skip | `16_loop_recv_value`、`96_file_lib_resource_shape`、`118_wasi_p3_std_wrappers` (recv/WASI 后置) |
| 诊断 code | `errorSummary` / `errorHint` 各 56 条 (含 `UnsupportedLowering`) |

发布候选的其它一致性检查 (链接、fixture companion、WASI registry、shell harness 等) 在收口交付时按 `doc/roadmap_status.md`「文档治理 / gate 复跑」清单执行; **不必每次把整表抄进本文**。

## 4. 架构模块地图

扁平拆分后的编译器边界 (与 `AGENTS.md` 一致):

| 层级 | 模块 | 职责 |
| --- | --- | --- |
| 流水线 | `lexer` → `parser` → `sema` → `codegen` | 主编译路径 |
| 共享纯函数 | `type_name` | 类型/布局 SSOT (scalar/storage/managed/Tuple scheme A) |
| | `sema_error` | ErrorSite 与 sema 错误构造 |
| | `diagnostics` | check/LSP 共用前端诊断收集 (原 `src/lsp/diagnostics.zig` 已删除) |
| Codegen 域 | `codegen_payload_wat` | 标量 payload load/store、Tuple 叶子 pack/unpack |
| | `codegen_storage_wat` | storage 指针/header/alias; `HEADER=8` |
| | `function_body_wat` / `runtime_prelude_wat` / `component_metadata_wat` | WAT 写出切片 |
| 旁路 | `backend_ir` | **仅**标量 `start` 旁路 + unit; **不是**主 emit 路径 |
| CLI | `src/main.zig` | 分派; `do test` 经 `runTest` → `loadProgram` |

**刻意未做**: 全量拆 `codegen`/`sema` god module; 批量把真 overload `NoMatchingCall` 改成 `UnsupportedLowering`; 合并静态/compiled 双 runner; 把 `backend_ir` 扩成主路径。

## 5. 当前阻断

| ID | 说明 | 恢复条件 |
| --- | --- | --- |
| G6.1 | preopens `list<tuple<descriptor,string>>` 公开 API 未确认 | 用户确认 API |
| G6.2 | `descriptor.read-directory` (stream/future) | 未来 async/Future/Task runtime |
| G6.3 | sockets resource + variant | socket wrapper 与 address variant 映射决策 |
| 06.2 | 已拆到 G2–G6; 剩余由 G6.1–G6.3 承接 | 同上 |

**非发布阻断** (阶段 I 后置):

- managed payload / `text` 叶子 `[Tuple]` storage → `UnsupportedLowering`
- `@get(storage, i, j)` path chaining → `UnsupportedLowering`
- loop 绑定上标量叶子 `@get(v, N)` **已支持** (`compile_ok/269`, `compiled_ok/74`)

## 6. 当前计划候选

用户说 `go` / `next` 时, 按以下优先级:

1. **发布候选维护**: 回归红灯、文档漂移、可独立验证的小修
2. **等待决策**: G6.1 / G6.3 公开 API; G6.2 依赖 async runtime 立项
3. **可选小项** (不绕过 G6, 需单独授权):
   - I2 后置: managed 叶子 Tuple storage 或 path chaining (产品化 lowering, 非诊断伪装)
   - codegen 垂直再拆 (如 WASI emit 切片) — 先 parse/validate, 再搬实现
   - 继续 ownership / JSON / LSP 增强 — 见 README「下一阶段计划」, 默认不自动开做

**已关闭边界速查**:

- I1: 直接/互递归; 参数侧已定型泛型递归; self-tail scalar/`if-else`/guard/generic/imported TCO; 仅靠左侧目标类型反推的泛型递归仍 `NoMatchingCall`; `defer`/storage/managed/多返回/cleanup **不** TCO
- I2: `Tuple<T0,T1,...>` 位置构造 + `@get` 数字索引; local/struct/return/param/nested/标量叶子 storage + loop get; sema: `InvalidTypedLiteral` / `InvalidPathIndex` / `InvalidTypeRef`

## 7. 变更与推进协议

- 每次只做一个可验证小任务; 完成后更新本文基线, 必要时写 `CHANGELOG.md`。
- 语法/语义变更同步 `doc/spec_rules.md`、`doc/grammar.peg`、相关 `doc/syntax/*.md` 与回归。
- 工具行为变更同步 `README.md`、`src/build/test/README.md` 与黑盒 fixture。
- **只保留最新**: 不维护向后兼容路径、过期草案、空占位目录或历史 gate 流水账。
- 不默认: 重开 get/pkg/push; 去掉内部 `@` 前缀; direct wasm binary emitter; 完整 WASI/Component; 大规模重写 parser/sema/codegen。
- 产品命令边界: `do run` = core wasm smoke (`wasm-tools`+`node`); `do fmt` = 单文件 stdout/check/write; `do lsp` = diagnostics/formatting/tokens/hover/completion/definition (无 rename); `do check` = 前端诊断 only。
