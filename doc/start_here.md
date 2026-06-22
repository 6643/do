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
- 阶段 A 工具链体验补齐已收口: `do run`、`do fmt` stdout/check/write、`do lsp` diagnostics/formatting/semantic tokens、`do check` 单/多文件和工具链收口检查均已完成。
- 阶段 B 已完成 B1 grammar / parser 差异审查、B2 spec_rules / sema 差异审查、B3 语法文档治理和 B4 语法冻结回归包; B2 问题清单已按选定方案全部落地并删除。
- get / pkg / push 包管理线已按用户要求暂停；当前不要从包管理继续，也不要恢复历史 get/push 计划，除非用户明确重开。
- 已完成的边界是 ownership exit plan foundation、死 alias `inc/dec` 相消、保守 last-use move 子集、fresh-owner 字段读取 move 子集、collection loop / recv loop 内 call 参数保守回归、最小 `LoopMoveAnalysis` 输入/输出设计、03.7.4 不落地 loop 内局部 move 的结论, 03.8 不直接引入完整 ownership IR 的决策, 03.8.3 path/cleanup facts 最小接口, 03.8.4 完整 ownership IR 启动边界收口, 03.9 FBIP reuse 设计边界, 05.1 最小 backend IR 骨架, 05.2 控制流优化回归, 05.3 最小 copy fold / trivial inline 回归, 05.4 direct wasm binary emitter 暂不落地的评估结论, 以及 07.1 `do run <input.do>` 外部 `wasm-tools + node` 桥接执行。

下次第一步:

- `do run`、`do fmt`、`do lsp` 和 `do check` 第一版已完成；其中 `do fmt` 现已支持 `--write`, `do check` 现已支持多文件输入, `do lsp` 现已支持 formatting 和 semantic tokens。历史摘要见 [CHANGELOG.md](/home/_/._/do/CHANGELOG.md), 详细验证证据见 [doc/roadmap_status.md](/home/_/._/do/doc/roadmap_status.md)。
- `07.5 do check` 第一版已完成；当前行为是复用 LSP diagnostics collector, 成功静默 exit 0, 失败输出第一条 compile diagnostic 并 exit 1。
- 如果回到全局 roadmap, 先读 `doc/roadmap_status.md` 的阶段 C；B1、B2、B3 和 B4 不要重开, C1.1/C1.2/C1.3/C1.4/C1.5 已完成, 下一步从 C1.6 同步 `src/json.do`、相关核心声明和文档开始。
- 按 `doc/roadmap_status.md` 顶部的推进协议执行: 每次只推进一个小任务, 完成后马上同步勾选状态和验证证据。
- `05.4` 已收口为“不做 direct wasm binary emitter”，不要再把它当成未完成任务继续推进。
- `do run` 当前只覆盖 core wasm smoke 子集, 依赖本机 `wasm-tools` 与 `node`; 不要把它描述成 WASI / Component Model / 自定义 host runtime。
- `do fmt` 当前覆盖 stdout/check-only/write 单文件格式化; 不要把它描述成多文件批量、stdin/stdout 自动模式或语法感知格式化器。
- `do lsp` 当前覆盖 diagnostics stdio server、formatting 和 semantic tokens; 不要把它描述成 completion、hover、definition、rename 或完整语言服务。
- `do check` 当前覆盖单文件和多文件 lexer/parser/sema/import diagnostics; 不要把它描述成 build/codegen/test runner/watch/multi-diagnostic 命令。
- get / pkg / push 已暂停并从活跃代码线移除; 不要把 `do get` 或 `do push` 描述为当前可用命令。
- 新的总规划入口是 [doc/master_plan.md](/home/_/._/do/doc/master_plan.md); 默认下一步按其中“阶段 C: 标准库与核心库收口”推进。阶段 B 已完成, C1.1/C1.2/C1.3/C1.4/C1.5 已完成, 下一步优先 C1.6 同步 JSON 源码、核心声明和文档。
- 若未来重新触发 ownership 主线，先重读 `doc/memory.md` 第 8.13 节和第 11.1 节。

变更边界:

- 只有语法、语义或文档治理任务需要时, 才同步 `doc/spec.md`、`doc/spec_rules.md`、`doc/grammar.peg` 和 `doc/syntax/`。
- 不是当前主线的 `ui.do`、`ui_demo.do`、`js/` 不要顺手改。
