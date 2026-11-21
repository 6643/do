# Pinned WASI HTTP Error Payload Evidence

日期: 2026-11-21
范围: `wasi:http@0.3.0-rc-2025-09-16` 的 `client.send` 返回值

## 结论

当前证据支持这个有限结论: Do 生成的 `client.send` 错误返回路径能通过
Component ABI 保留 pinned WIT 中列出的 15 种 payload-bearing `error-code`
variant。Rust/Wasmtime gate 使用 pinned WIT 生成的 Rust 类型, 由测试 host 合成
`ErrorCode` 并作为 `send` 的错误结果返回。

这些 gate 证明 WIT 类型定义和测试 host 之间的 ABI 往返, 不证明真实 HTTP provider
会在具体网络条件下产生某一种错误。测试没有连接真实网络, 也没有运行生产 HTTP
provider。

## 证据层级

| 层级 | 证据 | 能支持的结论 |
| --- | --- | --- |
| Pinned 源定义 | `src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16/types.wit:29` 定义 `error-code`; `:76` 到 `:92` 定义 payload records | 该版本 WIT 声明的 variant 和字段类型 |
| 编译器 ABI 往返 | `test_do_http_payload_error_lowering.sh all` 生成 Do Component; Rust/Wasmtime host 逐项返回 typed error, 并检查输出值 | 生成组件在测试 host 提供的 pinned `client.send` ABI 下保留指定 variant 和代表性 payload |
| 生命周期边界 | 同一 gate 检查 request consumed、response 未创建、`ResourceTable` 为空 | 这些测试场景中的 request/resource 处理结果 |
| 手写 ABI 对照 | `test_http_payload_error_abi.sh` 当前有 `InternalError(Some)` 和 `DNS-error` 的手写 canonical WAT 对照 | 两个代表性错误的独立 Core ABI 对照, 不覆盖全部 15 个变体 |
| 真实 provider 行为 | 未运行真实网络或生产 WASI HTTP provider | 不能声称任何具体 provider 会在某条件下产生这些错误, 或声称 provider 与测试 host 的行为完全一致 |

## Variant 清单

WIT 行号以 pinned `types.wit` 为准。所有 variant 都有 Rust/Wasmtime typed-host
ABI case。Do 组件 compiler-service gate 的模式列记录当前脚本实际覆盖情况。

| WIT variant | Payload type | WIT line | Runtime case | Do pending | Do ready | 真实 provider |
| --- | --- | --- | --- | --- | --- | --- |
| `DNS-error` | `DNS-error-payload` | 31 | `dns-error` | yes | yes | unverified |
| `TLS-alert-received` | `TLS-alert-received-payload` | 44 | `tls-alert-received` | yes | yes | unverified |
| `HTTP-request-body-size` | `option<u64>` | 47 | `http-request-body-size` | yes | yes | unverified |
| `HTTP-request-header-section-size` | `option<u32>` | 51 | `http-request-header-section-size` | yes | yes | unverified |
| `HTTP-request-header-size` | `option<field-size-payload>` | 52 | `http-request-header-size` | yes | yes | unverified |
| `HTTP-request-trailer-section-size` | `option<u32>` | 53 | `http-request-trailer-section-size` | yes | yes | unverified |
| `HTTP-request-trailer-size` | `field-size-payload` | 54 | `http-request-trailer-size` | yes | yes | unverified |
| `HTTP-response-header-section-size` | `option<u32>` | 56 | `http-response-header-section-size` | yes | yes | unverified |
| `HTTP-response-header-size` | `field-size-payload` | 57 | `http-response-header-size` | yes | yes | unverified |
| `HTTP-response-body-size` | `option<u64>` | 58 | `http-response-body-size` | yes | yes | unverified |
| `HTTP-response-trailer-section-size` | `option<u32>` | 59 | `http-response-trailer-section-size` | yes | yes | unverified |
| `HTTP-response-trailer-size` | `field-size-payload` | 60 | `http-response-trailer-size` | yes | yes | unverified |
| `HTTP-response-transfer-coding` | `option<string>` | 61 | `http-response-transfer-coding` | yes | yes | unverified |
| `HTTP-response-content-coding` | `option<string>` | 62 | `http-response-content-coding` | yes | yes | unverified |
| `internal-error` | `option<string>` | 73 | `internal-error-none`, `internal-error-some` | yes | yes | unverified |

Shared record fields are defined at `types.wit:77` to `:80` for
`DNS-error-payload`, `:83` to `:86` for `TLS-alert-received-payload`, and
`:89` to `:92` for `field-size-payload`.

## Coverage Gaps

- Independent hand-authored canonical WAT coverage is representative, not per-variant.
- No production provider or network scenario has been observed. Provider behavior is
  explicitly outside the current compiler ABI closeout.

To claim real provider behavior later, add a separate provider-specific integration
gate. It must name the provider and version, document reproducible trigger conditions,
and report variants that cannot be triggered as unverified rather than inferred from
the WIT declaration.
