# Roadmap 执行状态

更新时间: 2026-07-12

**本文只保留当前状态与阻断。** 历史小任务勾选与逐条 gate 证据已从仓库移除; 追溯用 git 历史与 `CHANGELOG.md`。  
总规划: `doc/master_plan.md`。接手入口: `doc/start_here.md`。

## 推进协议

1. 每次只做一个可验证小任务。
2. 完成后更新本文「当前状态」与 `doc/start_here.md` 基线。
3. 阻塞时写清证据、停止点与恢复条件。
4. 语法/语义变更同步 `doc/spec_rules.md`、`doc/grammar.peg`、syntax 与回归。

## 当前状态

| 项 | 状态 |
| --- | --- |
| v1 子集 | 发布候选已收口 |
| 阶段 A–F、H | done |
| 阶段 D | 可推进项 done; D2.1 按 B 方案绿色 regression 收口 |
| 阶段 G | G1–G5、G6.1、G6.4 done; G6.2–G6.3 **blocked** |
| 阶段 I | **closed** (I1 递归/self-tail TCO + I2 `Tuple<...>` 第一版) |
| 架构扁平拆分 | 五轮已落地 (`diagnostics` / `type_name` / `sema_error` / `codegen_payload_wat` / `codegen_storage_wat`) |
| 目录 | 标准库 `lib/`; 工具链 `src/` (原 `tool/`) |

### 最近验证

```text
cd src && zig test main.zig
  → All 119 tests passed.

./src/build/test/run_tests.sh
  → pass=919 fail=0 skip=3

RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  → pass=833 fail=0 skip=3; wasm run summary: pass=6 fail=0
```

剩余 skip: `16_loop_recv_value`、`96_file_lib_resource_shape`、`118_wasi_p3_std_wrappers` (recv / WASI 后置)。

### 阶段 I 边界 (已关闭)

- I1: 直接/互递归; 参数侧已定型泛型递归; self-tail scalar / `if-else` / guard / generic / imported TCO。  
  仅靠左侧目标类型反推的泛型递归仍 `NoMatchingCall`; `defer` / storage / managed / 多返回 / cleanup 不 TCO。
- I2: `Tuple<T0,T1,...>` 位置构造 + `@get` 数字索引; local/struct/return/param/nested/标量与 managed 叶子 storage + path chain + loop get。  
  pure-scalar struct 与含 managed 字段的 struct 直接子槽 storage 已支持 (永不拍平; managed struct 为句柄叶子)。

## 当前阻断与待处理

权威清单 (blocked / pending / deferred / skip): **`doc/pending_blocked.md`**。

摘要:

| 类 | 项 |
| --- | --- |
| blocked | G6.2 read-directory/async; G6.3 sockets; 06.2→G6 |
| pending | P2 左侧反推泛型 (默认不放开); skip 16/96/118 |
| deferred | ownership IR、真 host I/O、JSON 扩展、LSP/fmt、wasm emitter 等 (见该文件 §3) |

## 下一步

1. 发布候选维护 (回归 / 文档漂移 / 独立小修)。
2. 等待 G6 决策; 不绕过阻断扩 codegen。
3. 可选授权项见 `doc/pending_blocked.md` 与 README「下一阶段计划」。
