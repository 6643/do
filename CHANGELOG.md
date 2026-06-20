# Changelog

本文只记录已经完成并仍需要可追溯的阶段性变化。实时执行状态见 `doc/roadmap_status.md`; 下一步入口见 `doc/start_here.md`; 总规划见 `doc/master_plan.md`。

## 2026-06-18

- 新增 `CHANGELOG.md` 作为历史变更入口。
- `do lsp` 补齐 `textDocument/formatting`。
  - 行为: initialize 暴露 `documentFormattingProvider: true`; formatting 返回全量 `TextEdit`, 复用 `do fmt` formatter core。
  - 验证记录保留在 `doc/roadmap_status.md` 的 `A1.*`。
- `do lsp` 补齐 `textDocument/semanticTokens/full`。
  - 行为: initialize 暴露 semantic tokens legend; full 请求返回 LSP delta encoded token data。
  - 边界: 不做 delta tokens、workspace index、主题适配、completion、hover、definition 或 rename。
  - 验证记录保留在 `doc/roadmap_status.md` 的 `A2.*`。
- `do fmt` 补齐 `--write`。
  - 行为: `do fmt --write <input.do>` 生成完整 formatted buffer 后原地写回单文件。
  - 边界: 不做多文件批量、stdin/stdout 自动模式或语法感知 formatter 重写。
  - 验证记录保留在 `doc/roadmap_status.md` 的 `A3.*`。
- `do check` 补齐多文件输入。
  - 行为: `do check a.do b.do` 按命令行顺序检查; 遇到失败继续检查后续输入, 最终 exit 1。
  - 边界: 不做并发、watch、workspace mode 或多诊断聚合。
  - 验证记录保留在 `doc/roadmap_status.md` 的 `A4.*`。
- 清理已完成支线的历史计划和设计文档, 避免 `doc/start_here.md`、`doc/roadmap_status.md` 与旧 plan/spec 双源维护。
- 当前保留的活跃文档入口:
  - `README.md`
  - `doc/start_here.md`
  - `doc/master_plan.md`
  - `doc/roadmap_status.md`
  - `doc/spec.md`
  - `doc/spec_rules.md`
  - `doc/grammar.peg`
  - `doc/syntax/README.md`
  - `doc/memory.md`
  - `doc/wit/wasi_p3_lowering.md`

## 2026-06-17

- `do check <input.do>` 第一版落地。
  - 行为: 复用 LSP diagnostics collector, 只检查 lexer/parser/sema/import diagnostics。
  - 边界: 不编译、不运行、不要求 `start()` 或 `test` 声明。
  - 验证记录保留在 `doc/roadmap_status.md` 的 `07.5.0`。
- `do lsp [--stdio]` diagnostics 第一版落地。
  - 行为: 支持 initialize、initialized、didOpen、didChange、didClose、shutdown、exit。
  - 当时边界: 未包含 formatting、semantic tokens、completion、hover、definition、rename 或 workspace index; formatting 和 semantic tokens 已在 2026-06-18 补齐。
  - 验证记录保留在 `doc/roadmap_status.md` 的 `07.3.*`。
- `do fmt <input.do>` 和 `do fmt --check <input.do>` 第一版落地。
  - 行为: stdout 输出或 check-only。
  - 当时边界: 未包含原地写回、range formatting 或语法感知重写; `--write` 已在 2026-06-18 补齐。
  - 验证记录保留在 `doc/roadmap_status.md` 的 `07.2.*`。
- 总规划重做为 `doc/master_plan.md`。
  - 阶段 A-H 已拆为小任务。
  - 当时下一步为 A1 LSP formatting 第一版; A1/A2 已在 2026-06-18 完成, 当前下一步见 `doc/master_plan.md`。
- get / pkg / push 包管理线暂停。
  - 当前不注册 `do get` / `do push` CLI。
  - 不保留活跃 package 实现和 package smoke regression。

## 2026-06-16

- `do run <input.do>` 第一版落地。
  - 行为: 复用 `do build` 同源 WAT 编译, 再通过外部 `wasm-tools parse` 和 Node runner 执行 `_start`。
  - 边界: 不包含 WASI / Component Model runtime、自定义 host runtime、内置 wasm runtime 或完整资源 ABI。
  - 验证记录保留在 `doc/roadmap_status.md` 的 `07.1`。
- 后端 IR 方向完成阶段性评估。
  - 已有最小 `backend_ir.zig` 骨架、控制流折叠、copy fold 和 trivial inline 回归。
  - direct wasm binary emitter 暂不落地。
- ARC / ownership 阶段完成多个保守子集。
  - 已落地 ownership exit plan foundation、死 alias `inc/dec` 相消、保守 last-use move 子集、source/path cleanup facts 的阶段性收口。
  - 完整 ownership IR、跨函数唯一性证明和 FBIP `reuse` 仍按 `doc/master_plan.md` 后置。

## 更早历史

- 语言规范入口收敛到 `doc/spec.md`。
- 语义规则和正反例分别维护在 `doc/spec_rules.md` 与 `doc/spec_examples.md`。
- 语法设计拆分到 `doc/syntax/*.md`。
- runtime / ARC / allocator 设计维护在 `doc/memory.md` 和 `doc/memory_layout_structs.md`。
