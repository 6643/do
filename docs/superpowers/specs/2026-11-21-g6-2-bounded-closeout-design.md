# G6.2 Bounded Closeout Design

日期: 2026-11-21
状态: 待用户审阅；不授权 compiler capability expansion

## 1. 目标

为 G6.2 定义一个可验收的 bounded 阶段收口。收口意味着当前选择的、manifest-backed
private producer/resource 形状均有可复核的 ABI、compiler admission、Component 和
Rust/Wasmtime 生命周期证据；它不意味着 Do 已支持任意 producer、borrowed payload 或
通用 WASI async。

当前 producer contract、ownership state machine、固定资源/列表/record producer 与
HTTP request-body write-error probe 已有独立证据。剩余问题混有两类工作：可被单个
pinned probe 判定的 bounded 边界，以及需要新语言/ABI/运行时契约的通用能力。此设计
将两者分开，避免把一组 bounded gates 的完成描述成通用 G6.2 完成。

## 2. 目标与非目标

目标:

- 复核现有 G6.2 private routes、toolchain pin、正负 admission 和 lifecycle gates。
- 盘点已登记 payload-bearing completion error 的 canonical ABI/runtime 覆盖，并区分
  已支持的精确分支与仍 fail-closed 的其它官方分支。
- 固定每个准入 route 的 cleanup authority、转移提交点、取消终态及错误映射证据。
- 将 generic producer、borrowed payload 和更宽 async/resource 工作明确拆分到后续阶段。
- 给出 bounded G6.2 的退出标准，并同步权威状态文档。

非目标:

- 不新增 public `own<T>`、`borrow<T>`、`ref<T>` 或 lifetime 语法。
- 不开放 arbitrary producer expressions、generic list/variant/borrowed lowering，或
  general async-call/resource lowering。
- 不提升第七跳 forwarding、第七层 nested resource 等仅因常量边界而提出的形状。
- 不把 D2 通用 filesystem async、external HTTP host runtime、GC inventory 或 ARC
  equivalence 纳入 G6.2 收口条件。
- 不把 Wasmtime Store disposal 解释为 guest-level root hard-cancel。

## 3. 方案比较

### A. 收口 bounded G6.2 (推荐)

复核既有 gates；最多新增一个由具体调用需求支持的 bounded error-payload probe；未测量
或不支持的通用形状转入后续阶段。

- 优点: 产出清晰可验收的阶段状态，不模糊当前 fail-closed 边界。
- 代价: 不提供通用 producer/resource API。

### B. 实现通用 producer/resource

设计统一的通用 source/payload/lease/cancel lowering，并覆盖 borrowed、list、variant
与任意 producer expression。

- 优点: 目标表达力最大。
- 代价: 需要完整 alias/borrow/async lifetime 与 ABI 契约；当前 pinned Component
  toolchain 对部分 borrowed stream/future shape 在 embed 阶段拒绝。该工作远超本阶段。

### C. 持续逐个增加 private probe，不定义收口

每次只增加一个固定 descriptor，但不设 G6.2 完成条件。

- 优点: 单次变更范围最小。
- 代价: G6.2 长期保持开放，阶段边界和后续优先级不清晰。

选择 A。它与既有 manifest-backed、fail-closed 路线一致，并允许把真正的通用能力作为
独立项目决策，而不是 bounded gates 的隐含结果。

## 4. 推进阶段

### Phase 0: 冻结范围与基线

- 逐项复核 `doc/pending_blocked.md` G6.2 行与当前 registry、fixture、gate 的对应关系。
- 在当前锁定的 `wasm-tools` / Wasmtime / Zig / Rust 工具链上运行既有 G6.2 route
  gates；保留命令、退出码、WIT hash 和观测计数。
- 对重复、过时或与 D2/GC 混淆的条目作状态分类；不改变 compiler。

验收: 每个 bounded route 有唯一可运行 gate 和当前结果；无证据的陈述标记
unverified，不继承旧结果。

### Phase 1: 补全 pinned HTTP payload-bearing completion error

- 按 [G6.2 pinned WASI HTTP error payload design](2026-11-21-g6-2-http-error-payload-completeness-design.md)
  测量并支持当前 pinned `wasi:http/client.send` `error-code` 的全部 15 个
  payload-bearing variants。
- 现有 `DNS-error` 与 `internal-error` gates 纳入 fresh baseline；其余 13 个 variant
  按 ABI payload family 分批增加 canonical probe、manifest facts、negative admission、
  Component validation 和 Rust/Wasmtime lifecycle coverage。
- 本阶段仅承诺该 pinned descriptor/version 的完整 payload variant 集合；其它 descriptor、
  future WIT variants 和 arbitrary WIT error lowering 继续 fail-closed。

验收: 15 个 variants 的 canonical/component value 与 cleanup evidence 全部通过；未知
tag、错误布局及其它 descriptor 仍 fail-closed。该工作完成后再执行 Phase 2 和 Phase 3。

### Phase 2: 取消与资源边界归类

- 汇总已有显式 cancel、pending Future drop、stream close、Store disposal 和
  `table-empty` 证据，区分 guest cancellation、host future drop 与 Store teardown。
- 把尚未证明的 root hard-cancel、一般 async cancellation 和 D2 host cancellation
  标为独立 blocked 项，写明恢复条件。
- 只有存在 compiler 可表达且业务需要的具体取消形状时，才另立 bounded probe。

验收: 文档不再把不同 cancellation 机制混为同一项；每个未覆盖路径有明确 owner 和
恢复条件。

### Phase 3: 阶段收口与后续拆分

- 在所有选入 bounded 阶段的 route gates 通过后，将 G6.2 状态改为
  `bounded complete; general capabilities deferred/blocked`。
- 从 G6.2 当前阶段移出 generic producer expressions、generic list、borrowed/variant
  payload、更一般 nested/forwarding、general async/resource、root hard-cancel 和 D2
  通用 filesystem/HTTP；为每项保留单独的后续立项条件。
- 不修改 GC migration inventory 或 claim public ownership syntax。

## 5. 通用验收不变量

每个纳入 compiler admission 的形状都必须满足:

- descriptor locator/member/signature 与 pinned WIT hash 完全匹配；漂移在 WAT 前拒绝。
- 资源转移只在完整 payload 写入成功后提交；缺席状态用 presence state 表示，不借用
  handle 数值作为 sentinel。
- 所有 terminal path 对 owner、stream、future、subtask、waitable 和 frame 至多清理一次。
- 子 endpoint 先于 parent waitable/frame 清理；正常返回、错误、取消、early drop、
  repeat 和 invalid input 覆盖其适用路径。
- 不把 host 副作用回滚、Store disposal 或 `ResourceTable` 不适用场景伪报为 guest
  cancellation/empty-table 证据。
- 正例、逐事实负例、Component validate 和 Rust/Wasmtime lifecycle 结果一致；任何
  未知 status fail closed。

## 6. 工作边界

Phase 1 的具体变体清单与 gates 见独立 payload design。按该 bounded descriptor/version
完成后，继续 Phase 2 和 Phase 3；所有通用能力仍移交后续项目。

权威状态文档为 `doc/pending_blocked.md`、`doc/roadmap_status.md`、
`doc/start_here.md`、`doc/master_plan.md`；用户指南和 `CHANGELOG.md` 只在实际实现或
阶段状态变化后同步。
