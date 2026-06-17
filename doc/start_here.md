# 下次启动入口

这是当前主线的接手入口。下次启动时，先按这个顺序读:

1. [README.md](/home/_/._/do/README.md)
2. [CHANGELOG.md](/home/_/._/do/CHANGELOG.md)
3. [doc/master_plan.md](/home/_/._/do/doc/master_plan.md)
4. [doc/roadmap_status.md](/home/_/._/do/doc/roadmap_status.md)
5. [doc/memory.md](/home/_/._/do/doc/memory.md)

当前停点:

- `defer` 阶段已收尾。
- 阶段性计划和内部前缀迁移文档已清理，不再作为入口。
- 当前主线已经推进到 `doc/roadmap_status.md` 的 `07. 生态工具`，其中 `07.1 do run` 第一版桥接、`07.2 do fmt` 第一版、`07.3 do lsp` diagnostics-only 第一版和 `07.5 do check` 前端诊断命令已完成。
- get / pkg / push 包管理线已按用户要求暂停；当前不要从包管理继续，也不要恢复历史 get/push 计划，除非用户明确重开。
- 已完成的边界是 ownership exit plan foundation、死 alias `inc/dec` 相消、保守 last-use move 子集、fresh-owner 字段读取 move 子集、collection loop / recv loop 内 call 参数保守回归、最小 `LoopMoveAnalysis` 输入/输出设计、03.7.4 不落地 loop 内局部 move 的结论, 03.8 不直接引入完整 ownership IR 的决策, 03.8.3 path/cleanup facts 最小接口, 03.8.4 完整 ownership IR 启动边界收口, 03.9 FBIP reuse 设计边界, 05.1 最小 backend IR 骨架, 05.2 控制流优化回归, 05.3 最小 copy fold / trivial inline 回归, 05.4 direct wasm binary emitter 暂不落地的评估结论, 以及 07.1 `do run <input.do>` 外部 `wasm-tools + node` 桥接执行。

下次第一步:

- `do run`、`do fmt`、`do lsp` 和 `do check` 第一版已完成；历史摘要见 [CHANGELOG.md](/home/_/._/do/CHANGELOG.md), 详细验证证据见 [doc/roadmap_status.md](/home/_/._/do/doc/roadmap_status.md)。
- `07.5 do check` 第一版已完成；当前行为是复用 LSP diagnostics collector, 成功静默 exit 0, 失败输出第一条 compile diagnostic 并 exit 1。
- 如果回到全局 roadmap, 先读 `doc/roadmap_status.md` 的第 07 节；`07.1`、`07.2`、`07.3` 和 `07.5` 不要重开, 下一步选择非包管理生态工具小任务或先让用户指定。
- 按 `doc/roadmap_status.md` 顶部的推进协议执行: 每次只推进一个小任务, 完成后马上同步勾选状态和验证证据。
- `05.4` 已收口为“不做 direct wasm binary emitter”，不要再把它当成未完成任务继续推进。
- `do run` 当前只覆盖 core wasm smoke 子集, 依赖本机 `wasm-tools` 与 `node`; 不要把它描述成 WASI / Component Model / 自定义 host runtime。
- `do fmt` 当前只覆盖 stdout/check-only 第一版格式化; 不要把它描述成原地写回、语法感知格式化器或 LSP formatter。
- `do lsp` 当前只覆盖 diagnostics-only stdio server; 不要把它描述成 completion、hover、definition、rename、formatting 或完整语言服务。
- `do check` 当前只覆盖 lexer/parser/sema/import diagnostics; 不要把它描述成 build/codegen/test runner/watch/multi-diagnostic 命令。
- get / pkg / push 已暂停并从活跃代码线移除; 不要把 `do get` 或 `do push` 描述为当前可用命令。
- 新的总规划入口是 [doc/master_plan.md](/home/_/._/do/doc/master_plan.md); 默认下一步按其中“阶段 A: 工具链体验补齐”推进, 优先 A1 LSP formatting 第一版。
- 若未来重新触发 ownership 主线，先重读 `doc/memory.md` 第 8.13 节和第 11.1 节。

不要顺手碰:

- `doc/spec.md` / `doc/spec_rules.md` 的语法规则。
- 不是当前主线的 `ui.do`、`ui_demo.do`、`js/`。
