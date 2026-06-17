# 下次启动入口

这是当前主线的接手入口。下次启动时，先按这个顺序读:

1. [README.md](/home/_/._/do/README.md)
2. [doc/roadmap_status.md](/home/_/._/do/doc/roadmap_status.md)
3. [doc/memory.md](/home/_/._/do/doc/memory.md)

当前停点:

- `defer` 阶段已收尾。
- 阶段性计划和内部前缀迁移文档已清理，不再作为入口。
- 当前主线已经推进到 `doc/roadmap_status.md` 的 `07. 生态工具`，其中 `07.1 do run` 第一版桥接和 `07.2 do fmt` 第一版已完成, `07.3 do lsp` 已写好阶段计划。
- 已完成的边界是 ownership exit plan foundation、死 alias `inc/dec` 相消、保守 last-use move 子集、fresh-owner 字段读取 move 子集、collection loop / recv loop 内 call 参数保守回归、最小 `LoopMoveAnalysis` 输入/输出设计、03.7.4 不落地 loop 内局部 move 的结论, 03.8 不直接引入完整 ownership IR 的决策, 03.8.3 path/cleanup facts 最小接口, 03.8.4 完整 ownership IR 启动边界收口, 03.9 FBIP reuse 设计边界, 05.1 最小 backend IR 骨架, 05.2 控制流优化回归, 05.3 最小 copy fold / trivial inline 回归, 05.4 direct wasm binary emitter 暂不落地的评估结论, 以及 07.1 `do run <input.do>` 外部 `wasm-tools + node` 桥接执行。

下次第一步:

- `do run` 支线已完成；若需要查历史, 读 [doc/do_run_next_steps.md](/home/_/._/do/doc/do_run_next_steps.md) 和 [docs/superpowers/plans/2026-06-16-do-run-07-1.md](/home/_/._/do/docs/superpowers/plans/2026-06-16-do-run-07-1.md)。
- `do fmt` 支线已完成；若需要查历史, 读 [docs/superpowers/plans/2026-06-17-fmt-07-2.md](/home/_/._/do/docs/superpowers/plans/2026-06-17-fmt-07-2.md) 和 [docs/superpowers/specs/2026-06-17-fmt-design.md](/home/_/._/do/docs/superpowers/specs/2026-06-17-fmt-design.md)。
- 如果回到全局 roadmap, 先读 `doc/roadmap_status.md` 的第 07 节；`07.1` 和 `07.2` 不要重开, 下一步从 `07.3.1` 开始实施 `do lsp [--stdio]` CLI contract。
- `07.3 do lsp` 计划入口是 [docs/superpowers/plans/2026-06-17-lsp-07-3.md](/home/_/._/do/docs/superpowers/plans/2026-06-17-lsp-07-3.md)。
- 按 `doc/roadmap_status.md` 顶部的推进协议执行: 每次只推进一个小任务, 完成后马上同步勾选状态和验证证据。
- `05.4` 已收口为“不做 direct wasm binary emitter”，不要再把它当成未完成任务继续推进。
- `do run` 当前只覆盖 core wasm smoke 子集, 依赖本机 `wasm-tools` 与 `node`; 不要把它描述成 WASI / Component Model / 自定义 host runtime。
- `do fmt` 当前只覆盖 stdout/check-only 第一版格式化; 不要把它描述成原地写回、语法感知格式化器或 LSP formatter。
- `do lsp` 当前只有计划, 尚未实现; 第一版范围限定为 diagnostics-only stdio server, 不要加入 completion、hover、definition、rename 或 formatting。
- 若未来重新触发 ownership 主线，先重读 `doc/memory.md` 第 8.13 节和第 11.1 节。

不要顺手碰:

- `doc/spec.md` / `doc/spec_rules.md` 的语法规则。
- 不是当前主线的 `ui.do`、`ui_demo.do`、`js/`。
