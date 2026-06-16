# `do run` 下次接手清单

这份文件只服务于 `do run` 这条支线。

如果下次要继续 `do run`，先读这里；如果要继续仓库全局主线，仍以 [doc/start_here.md](/home/_/._/do/doc/start_here.md) 为准。

## 当前状态

- `docs/superpowers/specs/2026-06-16-do-run-design.md` 已写完。
- `docs/superpowers/plans/2026-06-16-do-run-07-1.md` 已写完，并且：
  - Task 1 完成
  - Task 2 完成
  - Task 3 完成
- 当前 `do run <input.do>` 已可跑通 `tool/build/test/run/*.do` 这 6 个黑盒样例。
- `node` launcher 保留 PATH 命中路径的回归已补上，避免 `/snap/bin/node -> /usr/bin/snap` 解引用问题。

## 下次启动先读

1. [docs/superpowers/specs/2026-06-16-do-run-design.md](/home/_/._/do/docs/superpowers/specs/2026-06-16-do-run-design.md)
2. [docs/superpowers/plans/2026-06-16-do-run-07-1.md](/home/_/._/do/docs/superpowers/plans/2026-06-16-do-run-07-1.md)
3. [tool/run/run.zig](/home/_/._/do/tool/run/run.zig)
4. [tool/build/test/run_tests.sh](/home/_/._/do/tool/build/test/run_tests.sh)

## 下次从哪里开始

从 `docs/superpowers/plans/2026-06-16-do-run-07-1.md` 的 Task 4 开始，不要重开 Task 1-3。

第一个动作就是：

- [ ] 打开 `tool/build/test/run_tests.sh`
- [ ] 找现有 wasm smoke 相关 helper 和 CLI strict-args 段
- [ ] 只推进 Task 4 Step 1
- [ ] 完成后立刻把进度同步回 `docs/superpowers/plans/2026-06-16-do-run-07-1.md`

## 推荐执行顺序

### Task 4: 接入黑盒回归

- [ ] Step 1: 给 `do run` 增加 CLI strict-args 检查
- [ ] Step 2: 新增 `run_do_run_case()` helper
- [ ] Step 3: 挂到 `tool/build/test/run/*.do`
- [ ] Step 4: 跑 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`
- [ ] Step 5: 同步计划文件勾选和验证结果

### Task 5: 补环境失败路径

- [ ] Step 1: 明确 `wasm-tools` / `node` 缺失诊断
- [ ] Step 2: 给 `run_tests.sh` 加缺 `wasm-tools` 覆盖
- [ ] Step 3: 给 `run_tests.sh` 加缺 `node` 覆盖
- [ ] Step 4: 再跑 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`
- [ ] Step 5: 同步计划文件勾选和验证结果

### Task 6: 文档和最终验证

- [ ] Step 1: 更新 `README.md`
- [ ] Step 2: 更新 `doc/roadmap_status.md`
- [ ] Step 3: 更新 `doc/start_here.md`
- [ ] Step 4: 更新 `tool/build/test/README.md`
- [ ] Step 5: 跑最终验证
- [ ] Step 6: 同步计划文件勾选和验证结果

## 下次先跑的验证命令

```bash
cd tool && zig test build/cli.zig
cd tool && zig test main.zig
cd tool && zig build -Doptimize=Debug
```

若只是继续 Task 4，进入回归脚本改动前再跑：

```bash
SKIP_BUILD=1 ./tool/build/test/run_tests.sh
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
