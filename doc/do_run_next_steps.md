# `do run` 下次接手清单

这份文件只服务于 `do run` 这条支线。

如果下次要继续 `do run`，先读这里；如果要继续仓库全局主线，仍以 [doc/start_here.md](/home/_/._/do/doc/start_here.md) 为准。

## 当前状态

- `docs/superpowers/specs/2026-06-16-do-run-design.md` 已写完。
- `docs/superpowers/plans/2026-06-16-do-run-07-1.md` 已写完，并且：
  - Task 1 完成
  - Task 2 完成
  - Task 3 完成
  - Task 4 完成
  - Task 5 完成
  - Task 6 完成
- 当前 `do run <input.do>` 已可跑通 `tool/build/test/run/*.do` 这 6 个黑盒样例。
- `node` launcher 保留 PATH 命中路径的回归已补上，避免 `/snap/bin/node -> /usr/bin/snap` 解引用问题。
- 缺少 `wasm-tools` / `node` 时已输出 `error[MissingExternalTool]: <tool> not found`，并纳入 `run_tests.sh`。
- README、`doc/roadmap_status.md`、`doc/start_here.md` 和 `tool/build/test/README.md` 已同步第一版边界。
- 最终验证已完成:
  - `cd tool && zig build -Doptimize=Debug` 通过。
  - `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过，摘要 `pass=666 fail=0 skip=70`。
  - `RUN_WASM=1 SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过，摘要 `pass=667 fail=0 skip=70`，其中底层 wasm smoke 摘要 `pass=6 fail=0`。

## 下次启动先读

1. [docs/superpowers/specs/2026-06-16-do-run-design.md](/home/_/._/do/docs/superpowers/specs/2026-06-16-do-run-design.md)
2. [docs/superpowers/plans/2026-06-16-do-run-07-1.md](/home/_/._/do/docs/superpowers/plans/2026-06-16-do-run-07-1.md)
3. [tool/run/run.zig](/home/_/._/do/tool/run/run.zig)
4. [tool/build/test/run_tests.sh](/home/_/._/do/tool/build/test/run_tests.sh)

## 下次从哪里开始

`do run 07.1` 支线已完成，没有剩余动作。

如果继续仓库全局主线，回到 [doc/start_here.md](/home/_/._/do/doc/start_here.md)，从 `doc/roadmap_status.md` 的 `07. 生态工具` 后续项开始；`07.1 do run` 不要重开。

历史动作记录：

- [x] 打开 `tool/build/test/run_tests.sh`
- [x] 找现有 wasm smoke 相关 helper 和 CLI strict-args 段
- [x] 只推进 Task 4 Step 1
- [x] 完成后立刻把进度同步回 `docs/superpowers/plans/2026-06-16-do-run-07-1.md`

## 推荐执行顺序

### Task 4: 接入黑盒回归

- [x] Step 1: 给 `do run` 增加 CLI strict-args 检查
  - 验证: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过，摘要 `pass=658 fail=0 skip=70`。
- [x] Step 2: 新增 `run_do_run_case()` helper
  - 已新增 helper，尚未挂循环。
  - 验证: `bash -n tool/build/test/run_tests.sh` 通过；`SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过，摘要 `pass=658 fail=0 skip=70`。
- [x] Step 3: 挂到 `tool/build/test/run/*.do`
  - 已挂接 6 个 `tool/build/test/run/*.do` 到标准回归。
  - 已保留 `RUN_WASM=1` 下的 `run_wasm_smoke.sh`。
  - 验证: `bash -n tool/build/test/run_tests.sh` 通过；`SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过，摘要 `pass=664 fail=0 skip=70`。
- [x] Step 4: 跑 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`
  - 验证: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过，摘要 `pass=664 fail=0 skip=70`。
- [x] Step 5: 同步计划文件勾选和验证结果
  - 已同步 `docs/superpowers/plans/2026-06-16-do-run-07-1.md` 与本文档。
  - 验证沿用 Step 4 fresh 结果: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过，摘要 `pass=664 fail=0 skip=70`。

### Task 5: 补环境失败路径

- [x] Step 1: 明确 `wasm-tools` / `node` 缺失诊断
  - 已完成: `tool/run/run.zig` 将缺失外部工具诊断为 `error[MissingExternalTool]: <tool> not found`。
  - 验证: `cd tool && zig test main.zig` 通过，`3/3`；`cd tool && zig build -Doptimize=Debug` 通过；空 `PATH` 下真实 `do run` 输出 `error[MissingExternalTool]: wasm-tools not found`。
- [x] Step 2: 给 `run_tests.sh` 加缺 `wasm-tools` 覆盖
  - 已新增 `run_do_run_missing_wasm_tools_case()`，用空 `PATH` 验证产品命令缺工具诊断。
  - 验证: `bash -n tool/build/test/run_tests.sh` 通过；`SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过，摘要 `pass=665 fail=0 skip=70`。
- [x] Step 3: 给 `run_tests.sh` 加缺 `node` 覆盖
  - 已新增 `run_do_run_missing_node_case()`，临时 PATH 只放 `wasm-tools` symlink，验证 `node` 缺失诊断。
  - 验证: `bash -n tool/build/test/run_tests.sh` 通过；`SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过，摘要 `pass=666 fail=0 skip=70`。
- [x] Step 4: 再跑 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`
  - 验证: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过，`do run missing wasm-tools`、`do run missing node` 和 6 个 `do run` smoke case 均执行，摘要 `pass=666 fail=0 skip=70`。
- [x] Step 5: 同步计划文件勾选和验证结果
  - 已同步 `docs/superpowers/plans/2026-06-16-do-run-07-1.md` 与本文档。
  - 验证沿用 Step 4 fresh 结果: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过，摘要 `pass=666 fail=0 skip=70`。

### Task 6: 文档和最终验证

- [x] Step 1: 更新 `README.md`
  - 已新增 `do run` 用法、第一版桥接边界，并从生态工具暂跳过项中移除 `do run`。
  - 验证: `rg -n "do run|tool/run|生态工具|第一版桥接" README.md` 与 `sed -n '30,92p' README.md` 确认新旧状态一致。
- [x] Step 2: 更新 `doc/roadmap_status.md`
  - 07 阶段已改为 `partial`，07.1 已标记完成，并记录 `do run` 第一版桥接边界。
  - 验证: `rg -n "07\\.1|do run|wasm-tools|node|状态: partial|状态: skipped" doc/roadmap_status.md` 与 `sed -n '188,226p' doc/roadmap_status.md` 确认 07.1 无旧 blocked 口径。
- [x] Step 3: 更新 `doc/start_here.md`
  - 已将当前停点改为 `07. 生态工具`，明确 `07.1 do run` 已完成；本文档和计划只作为 do run 支线历史记录。
  - 验证: `rg -n "05\\. 后端|后端小任务|07\\.1|do run|do_run_next_steps|WASI|Component|重开|未完成" doc/start_here.md` 与 `sed -n '1,80p' doc/start_here.md` 确认接手口径一致。
- [x] Step 4: 更新 `tool/build/test/README.md`
  - 已记录默认回归执行 `do run <input.do>` 黑盒 smoke，`run_wasm_smoke.sh` 仅保留为 `RUN_WASM=1` 下的底层桥接验证。
  - 验证: `rg -n "do toolchain|do build|do test|do run|run_wasm_smoke|RUN_WASM|MissingExternalTool|只在|默认" tool/build/test/README.md` 与 `sed -n '1,60p' tool/build/test/README.md` 确认说明一致。
- [x] Step 5: 跑最终验证
  - 验证: `cd tool && zig build -Doptimize=Debug` 通过。
  - 验证: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过，摘要 `pass=666 fail=0 skip=70`。
  - 验证: `RUN_WASM=1 SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过，摘要 `pass=667 fail=0 skip=70`，其中底层 wasm smoke 摘要 `pass=6 fail=0`。
- [x] Step 6: 同步计划文件勾选和验证结果
  - 已同步 `docs/superpowers/plans/2026-06-16-do-run-07-1.md` 与本文档。

## 下次先跑的验证命令

```bash
cd tool && zig test build/cli.zig
cd tool && zig test main.zig
cd tool && zig build -Doptimize=Debug
```

标准回归命令:

```bash
SKIP_BUILD=1 ./tool/build/test/run_tests.sh
RUN_WASM=1 SKIP_BUILD=1 ./tool/build/test/run_tests.sh
```

## 不要顺手碰

- `doc/start_here.md` 当前全局主线以外的内容
- `tool/build/codegen.zig`
- `tool/build/ownership.zig`
- `tool/build/backend_ir.zig`
- `js/`
- `ui.do`
- `ui_demo.do`

## 执行纪律

- 每次只推进一个小任务。
- 每完成一个小任务，立刻同步 `docs/superpowers/plans/2026-06-16-do-run-07-1.md`。
- 没有 fresh verification，不要宣称完成。
