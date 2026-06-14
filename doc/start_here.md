# 下次启动入口

这是当前主线的接手入口。下次启动时，先按这个顺序读:

1. [README.md](/home/_/._/do/README.md)
2. [doc/roadmap_status.md](/home/_/._/do/doc/roadmap_status.md)
3. [doc/memory.md](/home/_/._/do/doc/memory.md)

当前停点:

- `defer` 阶段已收尾。
- 阶段性计划和内部前缀迁移文档已清理，不再作为入口。
- 当前主线停在 `doc/roadmap_status.md` 的 `03. ARC / Perceus 完整分析`。
- 已完成的边界是 ownership exit plan foundation、死 alias `inc/dec` 相消，以及保守 last-use move 子集。

下次第一步:

- 先重新读 `doc/roadmap_status.md` 的第 03 节，再看 `doc/memory.md` 里 13 到 21 条现有边界。
- 如果要继续扩字段读取 move，先补唯一拥有 / alias 证明，再动 `tool/build/codegen.zig`。
- 如果没有新的证明，不要把参数、借用、helper/shared-source 字段读取直接放开。

不要顺手碰:

- `doc/spec.md` / `doc/spec_rules.md` 的语法规则。
- 不是当前主线的 `ui.do`、`ui_demo.do`、`js/`。
