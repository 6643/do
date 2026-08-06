# do 编译器主计划

状态: v1 子集发布候选已收口; G6 generic consumer 与 bounded nested resource paths 已闭环, 剩余 producer/resource residual
更新时间: 2026-08-06

实时接手入口: `doc/start_here.md`。  
执行证据与历史勾选不再维护在本文; 需要追溯时查 git 与 `CHANGELOG.md`。

## 0. 当前基线

已完成并可作为后续依赖的能力:

- 规范: `doc/spec.md`、`doc/spec_rules.md`、`doc/grammar.peg`、`doc/syntax/*`、`doc/memory.md`、`doc/wit/*`。
- 工具链: `do build` / `do test` / `do test --compiled` / `do check` / `do run` / `do fmt` / `do lsp`。
- `do lsp`: diagnostics + formatting + semantic tokens + hover + completion + definition (无 rename)。
- `do fmt`: stdout / check-only / write 单文件。
- `do check`: lexer/parser/sema/import diagnostics only; 诊断收集在 `src/build/diagnostics.zig`。
- 阶段 A–F、H 已完成; D 可推进项与 D2.1 已收口; D2 真实本地 file/dir/CLI stream 与 compiler-generated TCP/UDP socket create/bind/drop loopback smoke 已收口，但总项仍受通用 filesystem async/external HTTP 阻断; G1–G5、G6.4 已完成; **阶段 I (I1+I2) 已关闭**。
- 架构扁平拆分已落地: `type_name` / `sema_error` / `diagnostics` / `gen_*` 域竖切 / `sema_*` 域竖切 (见 `AGENTS.md`)。
- 最近回归: Bun Node-compatible runner 下 `./src/build/test/run_tests.sh` → `pass=1108 fail=0 skip=3`; `RUN_WASM=1 SKIP_BUILD=1` → `pass=1110 fail=0 skip=3` (wasm smoke `6/6`); `cd src && zig test main.zig` → `277/277`。
- Colorless async / WIT bindgen 已形成有界可验证切片：`do wit check/bind`、生成 manifest 漂移校验、`@async/@await/@cancel` 前端契约、descriptor-backed generic 与私有 scalar-`u32` Component runtime 的 pending/ready/cancel gates 均通过；自动 manifest-to-lowering 的通用化与任意 payload/Stream/resource lowering 仍是 pending。

当前禁止默认推进:

- 不重开 get / pkg / push。
- 不去掉内部函数 `@` 前缀。
- 不默认推进 direct wasm binary emitter。
- 不默认推进完整 WASI / Component Model (未决部分在 G6)。
- 不大规模重写 parser / sema / codegen; 必须先拆成可回归小任务。
- 不把 `codegen_ir` 在未独立立项前扩成主 emit 路径。

## 1. 推进协议

1. 每次只推进一个可验证小任务。
2. 完成后更新 `doc/start_here.md` 停点/基线, 必要时写 `CHANGELOG.md`。
3. 语法或语义变化同步 `doc/spec_rules.md`、`doc/grammar.peg`、相关 `doc/syntax/*.md` 与回归。
4. 工具行为变化同步 `README.md`、`src/build/test/README.md` 与黑盒 fixture。
5. 文档只保留当前有效入口; 不保留过期草案与空占位目录。

## 2. 阶段结论 (仅状态)

| 阶段 | 状态 |
| --- | --- |
| A 工具链 | done |
| B 语法/语义冻结 | done |
| C 标准库收口 | done |
| D ARC / ownership | done (可推进项) |
| E 后端 IR / codegen | done |
| F LSP | done (v1 无 rename) |
| G WASI / Component | G1–G5、G6.1、G6.2 bounded read-directory slice + generic record-stream consumer + multi-owned/multiple-path/one-/two-/three-/four-/five-/six-level nested-owned resource consumer + bounded scalar producer + helper-mediated lease（含五跳 forwarding）+ fixed/parameterized `u64` countdown producer + parameterized forwarding-helper（含 typed-parameter reorder）+ branch-selected terminal checkpoints + private resource Result error/cancellation + pinned HTTP payload cancellation + private variant-resource-stream checkpoint + record-layout/source-mirror checkpoints、G6.3、G6.4 done; G6.2 general producer/resource extensions pending |
| H 发布前治理 | done |
| I 语言扩展 | **closed** (I1 递归/TCO + I2 Tuple 第一版) |
| Colorless async / WIT bindgen | bounded unit and scalar-`u32` runtime/manifest contracts verified; automatic manifest-to-lowering generalization and unrestricted generic async lowering pending |

## 3. 当前阻断与待处理

权威清单: **`doc/pending_blocked.md`** (G6 后续 producer/resource gates、语言 pending P2、deferred 非目标、skip)。

I2 已收窄: managed/`text` 叶子、pure-scalar struct 嵌套子槽、以及含 managed 字段的 struct 句柄槽 storage 已落地 (`compile_ok/273`, `ok/193`)。

## 4. 当前下一步

用户说 `go` / `next` 时 (细节见 `doc/pending_blocked.md` §6 与 `doc/start_here.md` §6):

1. 检查发布候选回归、文档漂移或可独立验证的小修。
2. 维护 colorless async / WIT bindgen 的 bounded gates；扩展 manifest-to-lowering、Future payload、Stream 或 resource 前，先建立独立 design、pinned ABI probe、负向边界和 Component/Rust/Wasmtime gate。
3. 维护 D2 真实 host matrix：local filesystem preopen/read-directory、CLI pipe 与 socket create/bind/drop loopback 已有 gate；保留通用 filesystem async、external HTTP 的明确阻断。
4. 固定 read-directory、generic consumer、multi-owned/multiple nested paths/one-/two-/three-/four-/five-/six-level nested-owned resource、bounded scalar producer、固定/参数化 `u64` countdown producer、受限（最多五跳 forwarding）helper-mediated lease、branch-selected terminal 与 StreamMirror slices，以及 capability matrix/ownership invariant 复核均已闭环；下一步只能为新的 producer/resource shape 建立独立 design、pinned probe 和 runtime gate，不绕过剩余边界。
5. D2 外的 deferred codegen/ownership/JSON/LSP 仍需单独授权。

验收命令:

```bash
cd src && zig test main.zig
./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh   # 发布前
```
