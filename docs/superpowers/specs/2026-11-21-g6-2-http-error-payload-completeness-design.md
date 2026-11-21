# G6.2 Pinned WASI HTTP Error Payload Completeness

日期: 2026-11-21
状态: 已选定并实现；范围限定为 pinned `client.send`

## 1. 目标

在当前锁定的 `wasi:http/client.send` descriptor 和
`wasi:http@0.3.0-rc-2025-09-16` WIT package 内，完整保留其 15 个 payload-bearing
`error-code` variants 的 tag 与 payload。该工作补全一个已登记 descriptor 的固定错误
类型，不提供任意 WIT error、任意 descriptor 或未来 WIT 版本的自动兼容。

当前 registry、emitter 和 runtime gate 已覆盖下表全部 15 个 payload variants。
支持边界仍锁定在 pinned descriptor、WIT hash、discriminant 和 measured layout。

## 2. 范围

以下列表以仓库内 pinned 官方 WIT 为准
(`src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/types.wit`)：

| Variant | WIT payload | 当前状态 |
| --- | --- | --- |
| `DNS-error` | `DNS-error-payload { rcode: option<string>, info-code: option<u16> }` | 已登记；须回归验证 |
| `TLS-alert-received` | `TLS-alert-received-payload { alert-id: option<u8>, alert-message: option<string> }` | 新增 |
| `HTTP-request-body-size` | `option<u64>` | 新增 |
| `HTTP-request-header-section-size` | `option<u32>` | 新增 |
| `HTTP-request-header-size` | `option<field-size-payload>` | 新增 |
| `HTTP-request-trailer-section-size` | `option<u32>` | 新增 |
| `HTTP-request-trailer-size` | `field-size-payload` | 新增 |
| `HTTP-response-header-section-size` | `option<u32>` | 新增 |
| `HTTP-response-header-size` | `field-size-payload` | 新增 |
| `HTTP-response-body-size` | `option<u64>` | 新增 |
| `HTTP-response-trailer-section-size` | `option<u32>` | 新增 |
| `HTTP-response-trailer-size` | `field-size-payload` | 新增 |
| `HTTP-response-transfer-coding` | `option<string>` | 新增 |
| `HTTP-response-content-coding` | `option<string>` | 新增 |
| `internal-error` | `option<string>` | 已登记；须回归验证 |

`field-size-payload` 是 `{ field-name: option<string>, field-size: option<u32> }`。

## 3. 非目标

- 不支持未列出的 WIT descriptor、错误类型、WIT package version 或新增 future variants。
- 不把未知 discriminant/payload tag 转成默认错误；未知形状必须 trap/fail closed。
- 不改变 public `own<T>`/`borrow<T>`/`ref<T>`、GC inventory 或 ARC equivalence。
- 不在此设计中实现 general async/resource、任意 producer 或 root hard-cancel。
- 不改变 cancellation 对已提交 host side effect 的语义。

## 4. 方案比较

### A. 当前 pinned error-code 的完整 variant 覆盖 (推荐)

扩展 `send` manifest 的 measured variant facts 和专用 HTTP error emitter，覆盖上述全部
15 个 payload cases。发射仍受 descriptor locator、签名、WIT hash、tag、layout 和字段
类型校验限制。

- 优点: Do Component consumer 不会因合法的官方 payload error variant 丢失错误或 trap。
- 代价: 需要为多个 canonical payload layout 建立独立 probe 和分批 runtime gate。

### B. 只补最常见的几个 payload variant

先实现字符串、整数或 TLS 类分支中的一部分，其余继续 trap。

- 优点: 首批变更较小。
- 代价: 相同的官方 `error-code` 仍部分不可消费，使用边界不容易预测。

### C. 泛化为任意 WIT error payload lowering

从通用 WIT 类型描述自动生成所有错误 layout 和 lowering。

- 优点: 长期扩展性最高。
- 代价: 范围远超当前 descriptor；canonical layout、nested option/record、所有权和版本
  漂移需要通用契约，不属于 G6.2 bounded closeout。

选择 A。这里的“完整”只针对当前 pinned `wasi:http/client.send` error type，不表示
通用 WIT error support。

## 5. 实现分批与验收

### Phase 0: 基线与 ABI inventory

- 复核 upstream WIT package hash、`error-code` tag/discriminant 和当前 `send` completion
  ABI；记录现有两条 route 的输出与 runtime 基线。
- 为每个 payload variant 固定 canonical payload layout、payload byte span、option tag、
  completion words 和 discard/free authority。
- 新增的每个 measured fact 都必须由 pinned canonical Core WAT/WIT probe 和
  `wasm-tools` Component validate 证实；禁止只从 WIT 源语法推测 linear-memory offset。

验收: 有 15 行 variant/layout inventory；每行都有源定义、canonical evidence 和明确
支持状态。遇到无法测量或工具链不接受的 case 时停止该批次并保留该 case 的拒绝。

### Phase 1: scalar 与 optional scalar/string payloads

覆盖 `option<u64>`、`option<u32>`、`option<string>` 与 TLS 的 `option<u8>` / string
fields。每种 option 验证 `None`、代表性 `Some` 和无效 tag；string 验证空/非空与精确
一次复制/释放。

### Phase 2: nested optional record payloads

覆盖 `option<field-size-payload>`、`field-size-payload`、`DNS-error-payload` 和
`TLS-alert-received-payload`。对每个独立可选字段验证 None/Some；至少有 all-None、
all-Some 和单字段 Some 组合，确认 nested discriminant、padding、payload span 和
cleanup 不互相覆盖。

### Phase 3: registry/admission/emitter

- 扩展 `p3_async_registry.json` 的 `error_variants` measured model，使其表达本设计列出
  的字段类别与偏移。
- 在 `codegen_component_wasi_http.zig` 中基于 measured facts 发射 variant-specific
  task-return payload；所有未登记分支及 locator/signature/layout drift 在 WAT 前拒绝。
- 保持现有 `DNS-error` / `internal-error` 输出和行为稳定，新增 cases 不可使既有
  success、DNS timeout、payload discard/cancel route 回归。

验收: 正例逐 variant 断言精确 tag/value；负例逐 fact 变异验证未登记 variant、错误
discriminant、错误字段类型、layout/offset drift、错误 payload tag 均拒绝或 trap。

### Phase 4: Component / Rust / Wasmtime lifecycle

- 通过生成 Component validate 和 Rust/Wasmtime host gate，逐 variant 交付并读回精确
  error payload。
- 覆盖 ready error 与 pending completion；适用时覆盖 cancel、early drop、repeat。
- 观测 strings/records exactly-once cleanup、response resource 不误创建/泄漏、Future
  cleanup 和 `ResourceTable::is_empty()`。
- 保留现有未知/non-payload error discriminants 的行为；未知 payload tag trap。

验收: canonical/component payload 值一致；所有适用 terminal paths exactly-once cleanup；
没有任何 unsupported variant 被当作成功或默认错误。

### Phase 5: bounded closeout 同步

所有阶段 gates 已通过，并同步 `doc/pending_blocked.md`、`doc/roadmap_status.md`、
`doc/start_here.md`、`doc/master_plan.md`、`doc/wit/wasi_p3_lowering.md`、
`examples/p3-runtime/README.md` 与 `CHANGELOG.md`。将此能力记录为 pinned HTTP send
payload variant coverage，不得描述为 general HTTP/WIT error support。

## 6. 通用安全与生命周期不变量

- WIT discriminant 顺序、canonical layout 和 payload offsets 来自 pinned probe/manifest，
  不由 emitter 猜测。
- `option<string>` 的 absent arm 不读取未初始化 payload words；present arm 只释放已验证
  的 pointer/length span 一次。
- nested option/record 在所有字段组合中保持源错误值，不静默降为 None 或另一个 variant。
- 无效 discriminant、layout drift、越界 span 和未知 status fail closed/trap。
- 已完成 HTTP/host 副作用不因取消被报告为回滚。

## 7. 文件边界

预期实现触及：

- `src/build/p3_async_registry.json`: pinned error variant layout facts。
- `src/build/codegen_component_wasi_http.zig`: descriptor validation、error lowering 与
  focused unit tests。
- `examples/p3-runtime/`: canonical WAT/WIT probes、Do admission fixtures、Rust/Wasmtime
  assertions 和 executable gates。
- `src/build/test/test_harness.zig`: 将稳定的 compiler/lowering gate 纳入主 harness。
- 当前 G6.2 状态文档：所有阶段验收通过后同步。

实现须按 ABI payload family 分批，每批都可单独 build/validate/runtime-test；某一族失败
时，停止该族，不放宽其它族或未知分支的 fail-closed 行为。
