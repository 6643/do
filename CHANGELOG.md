# Changelog

本文只记录已经完成并仍需要可追溯的阶段性变化。实时执行状态见 `doc/roadmap_status.md`; 下一步入口见 `doc/start_here.md`; 总规划见 `doc/master_plan.md`。

## 2026-06-18

- 新增 `CHANGELOG.md` 作为历史变更入口。
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
- `do lsp [--stdio]` diagnostics-only 第一版落地。
  - 行为: 支持 initialize、initialized、didOpen、didChange、didClose、shutdown、exit。
  - 边界: 不包含 formatting、semantic tokens、completion、hover、definition、rename 或 workspace index。
  - 验证记录保留在 `doc/roadmap_status.md` 的 `07.3.*`。
- `do fmt <input.do>` 和 `do fmt --check <input.do>` 第一版落地。
  - 行为: stdout 输出或 check-only。
  - 边界: 不做原地写回、不做 range formatting、不做语法感知重写。
  - 验证记录保留在 `doc/roadmap_status.md` 的 `07.2.*`。
- 总规划重做为 `doc/master_plan.md`。
  - 阶段 A-H 已拆为小任务。
  - 下一步固定为 A1 LSP formatting 第一版。
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
