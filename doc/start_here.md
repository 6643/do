# 下次启动入口

这是当前主线的接手入口。下次启动时，先按这个顺序读:

1. [README.md](/home/_/._/do/README.md)
2. [doc/roadmap_status.md](/home/_/._/do/doc/roadmap_status.md)
3. [doc/memory.md](/home/_/._/do/doc/memory.md)

当前停点:

- `defer` 阶段已收尾。
- 阶段性计划和内部前缀迁移文档已清理，不再作为入口。
- 当前主线停在 `doc/roadmap_status.md` 的 `03. ARC / Perceus 完整分析`。
- 已完成的边界是 ownership exit plan foundation、死 alias `inc/dec` 相消、保守 last-use move 子集、fresh-owner 字段读取 move 子集，以及 collection loop / recv loop 内 call 参数保守回归。

下次第一步:

- 先重新读 `doc/roadmap_status.md` 的第 03 节，再看 `doc/memory.md` 第 8.5 和 8.6 节的 ownership / loop 边界。
- 按 `doc/roadmap_status.md` 顶部的推进协议执行: 每次只推进一个小任务, 完成后马上同步勾选状态和验证证据。
- 当前只推进 `03.7.3 设计最小 LoopMoveAnalysis 输入/输出`, 不要同时落地 move 放开代码或切到 03.7.4。
- 第一步只把 source origin、path exit、use-after、cleanup 四类证明边界写清楚, 先做设计文档和可验证用例边界。
- 不能把 collection loop / recv loop 中的参数、借用、helper/shared-source、loop-carried source、同语句多字段读取或 active defer cleanup 相关 source 直接放开。

不要顺手碰:

- `doc/spec.md` / `doc/spec_rules.md` 的语法规则。
- 不是当前主线的 `ui.do`、`ui_demo.do`、`js/`。
