# G6.2 一般资源所有权与 Host ABI 可行性矩阵

更新时间: 2026-08-04

本文是 G6.2 下一阶段的证据与契约文档。它只记录 pinned toolchain 能力、当前私有
registry/lowering 边界和后续实现必须遵守的所有权状态机；不引入公开
`own<T>`、`borrow<T>`、`ref<T>`、指针或引用语法。

## 1. 固定环境

| 项 | 版本 / 来源 |
| --- | --- |
| Zig | `0.16.0` |
| Rust / Cargo | `rustc 1.97.1` / `cargo 1.97.1` |
| wasm-tools | `1.254.0` (`bb58fdf91`, 2026-07-20) |
| Wasmtime | `47.0.2` (`90fed3c6a`, 2026-07-21) |
| async registry | `src/build/p3_async_registry.json`, schema 1, 23 descriptors |
| resource registry | `src/build/resource_abi_registry.json`, schema 1, 13 descriptors |

结论只能针对上述版本成立。升级 `wasm-tools` 或 Wasmtime 时必须重新跑本矩阵，不能
把新工具的行为隐式当作兼容。

## 2. 能力矩阵

| 形状 | 当前结果 | 证据 | 结论 |
| --- | --- | --- | --- |
| scalar/string record consumer | verified | `test_do_record_stream_probe_lowering.sh` + `test_rust_record_stream_probe.sh` | 已有 generic consumer lowering/runtime |
| direct `own` resource fields | verified | `test_do_record_resource_stream_probe_lowering.sh` + `test_rust_record_resource_stream_probe.sh` | frame-owned handle 与 exactly-once drop 已闭环 |
| multiple direct `own` fields | verified | `test_do_record_resource_stream_multi_probe_lowering.sh` + `test_rust_record_resource_stream_multi_probe.sh` | 多字段 drop 去重与空表已验证 |
| one through six nested `own` levels | verified | `test_do_record_resource_stream_nested_*_probe_lowering.sh` + 对应 Rust gates | 当前最大已验证 nested 深度为 6 |
| two top-level nested paths | verified | `test_do_record_resource_stream_multiple_nested_probe_lowering.sh` + Rust gate | 只允许已登记的固定布局 |
| bounded `StreamWriter<u8>` producer | verified | `test_rust_stream_writer_guest_producer_descriptor.sh` | 固定 producer sequence 已验证 |
| parameterized `u64` countdown producer | verified | `test_rust_stream_writer_guest_producer_parameterized.sh`、`...dynamic.sh` | 仅注册 descriptor 的 countdown 形状 |
| parameterized helper forwarding, 1-5 hops | verified | `test_rust_stream_writer_guest_producer_parameterized_{two,three,four,five}_hop.sh` | 五跳是当前上限 |
| reordered parameterized helper arguments | verified | `test_do_stream_writer_guest_producer_parameterized_reordered_helper.sh` + `test_rust_stream_writer_guest_producer_parameterized_reordered_helper.sh` | 仅按三个已知 typed 参数重排；不接受 literal/extra/missing 参数 |
| one helper-mediated lease with branch-selected `close`/`abort` terminal | verified | `test_do_stream_writer_guest_producer_branch_terminal.sh` + `test_rust_stream_writer_guest_producer_branch_terminal.sh` | `abort` 只接受注册的 `pipe` discriminant `2`; producer-only runner 不提供 `ResourceTable` 证据 |
| descriptor-bounded `StreamMirror` | verified | `test_rust_stream_mirror.sh` | `pending/ready/source-eof/error/cancel/early-drop` 六模式均 exactly-once cleanup |
| `borrow<ticket>` inside a stream record | rejected by `wasm-tools` | `wasm-tools component embed` exits 1: `function read-via-stream returns a type which contains a borrow<T> which is not supported` | pinned Component tool链硬边界；不添加公开 `borrow<T>` |
| private `stream<list<resource-entry>>` ABI probe and registered lowering | verified, descriptor-bounded | `test_record_resource_list_stream_abi.sh` plus `test_do_record_resource_list_stream_lowering.sh` cover `0/1/3`, pending, terminal error, early cleanup, malformed length, duplicate release, and 6000 sequential same-instance calls | only `do:record-resource-list-stream-probe@0.1.0/read-via-stream` with one fixed source plan lowers |
| generic or unregistered `list<resource-entry>` Do source | rejected | `test_do_record_resource_list_stream_boundary.sh` observes `UnknownP3AsyncHostDescriptor` for the unregistered locator | 不能因为一个已登记 private slice 可运行就宣称通用 Do list/resource 支持 |
| private `stream<event>` variant payload containing `own<ticket>` | verified, Do lowering unavailable | `test_variant_resource_stream_abi.sh` covers `ticket` / `idle` / `failed(io)`, pending, completion error, early cleanup, malformed tag, and duplicate release; `tag@0,payload@4,size=8,align=4` in a frame `+64` result buffer | 仅 hand-written private ABI 证据；registry/manifest 无 variant resource stream shape，通用 Do lowering 仍未授权 |
| seventh nested `own` level | tool accepted, manifest rejected | pinned `wasm-tools component embed` exits 0; `zig test build/p3_async_manifest.zig` test `generic record resource metadata rejects a seventh nested owned resource level` returns `InvalidP3AsyncManifest` | 不提高深度常量，先定义通用 layout/cleanup 契约 |
| sixth producer forwarding edge | rejected by Do compiler | five-hop fixture builds; six-hop probe `.tmp/do-tmp/capability/sixth-forwarding.do` exits 1 with `UnsupportedP3AsyncComponent` | 当前边界明确且可回归 |
| arbitrary producer expression | rejected by Do compiler | `.tmp/do-tmp/capability/arbitrary-producer.do` exits 1 with `UnsupportedP3AsyncComponent` | 只接受注册 descriptor 的 literal/parameter countdown |
| two async calls sharing one writer lease | rejected by sema | `.tmp/do-tmp/capability/shared-producer-lease.do` exits 1 with `StreamWriterAlreadyFinalized` at the second transfer | 单一 affine owner，不允许并发/重复转移 |

### 2.1 探针命令与关键输出

borrowed record 的最小 WIT 位于临时目录
`.tmp/do-tmp/capability/borrowed-record-stream/borrowed-record-stream.wit`，命令为：

```bash
wasm-tools component embed \
  .tmp/do-tmp/capability/borrowed-record-stream/borrowed-record-stream.wit \
  .tmp/do-tmp/capability/borrowed-record-stream/core.wasm \
  --world capability-borrowed-record \
  --features cm-async,cm-more-async-builtins \
  -o .tmp/do-tmp/capability/borrowed-record-stream/embedded.wasm
```

关键诊断：

```text
error: function `read-via-stream` returns a type which contains a `borrow<T>` which is not supported
```

2026-08-04 在同一 pinned `wasm-tools 1.254.0` / Component embed 命令上复核，仍以
exit `1` 返回相同诊断；因此该边界不是旧日志残留，也不能通过增加 Do 侧包装类型绕过。

五跳 positive probe：

```bash
DO_LIB_ROOT="$PWD/lib" ./bin/do build --p3-async-component \
  examples/p3-runtime/stream-probe-guest-producer-parameterized-five-hop.do \
  -o .tmp/do-tmp/capability/five-forwarding.wat
```

输出 `ok`；同样形状增加一个 forwarding edge 后输出：

```text
error[UnsupportedP3AsyncComponent]: 此统一 P3 async Component 目标不支持该 descriptor 或源码形态
```

任意 producer expression 与共享 writer lease 的命令和诊断分别保留在
`.tmp/do-tmp/capability/arbitrary-producer.stderr` 与
`.tmp/do-tmp/capability/shared-producer-lease.check.stderr`。这些文件属于临时探针，
不作为源码接口；稳定边界由
`test_do_g6_general_boundary_rejection.sh`、`test_do_borrowed_resource_rejection.sh`
与 `src/build/test/check/412_stream_writer_shared_lease.do` 锁定。

### 2.2 `stream<list<resource-entry>>` 私有 canonical ABI 探针 (2026-08-04)

`examples/p3-runtime/wit/record-resource-list-stream-canonical.wit` 与手写
`record-resource-list-stream-canonical.wat` 只验证一个 stream item。实际
`wasm-tools parse`、Component embed/new/validate 和 Wasmtime `47.0.2` runtime gate
共同固定了以下 `cm32` 事实：

| 项 | 实测值 | 证据 |
| --- | --- | --- |
| list result pointer | frame `+64` | `list-result-pointer` WAT marker；`0/1/3` runtime 皆通过 |
| list result length | frame `+68` | `list-result-length` marker；`0/1/3` runtime 皆通过 |
| `resource-entry` stride | `4` bytes | `cabi_realloc` 只接受 size `4` / `12`，一和三个 entry runtime 都通过 |
| `own<ticket>` word | element `+0` | `list-ticket-offset` marker；每个转移 handle 恰好 drop 一次 |
| alignment | `4` bytes | pointer alignment gate 与 `cabi_realloc` gate |
| allocation | `cabi_realloc(0, 0, 4, 4|12)` | 非空 list 的运行期 gate |
| release | `cabi_realloc(ptr, len * 4, 4, 0)` | raw slots 清零后精确释放；其他 realloc 形状 trap |

正常矩阵中，`0/1/3` 分别创建并 drop `0/1/3` 个 ticket，stream/future 各 drop
一次，且 `ResourceTable` 为空。completion pending-once 轮询两次后同样清空；
completion `Err(io)` 仍先释放三个 ticket，再返回错误；私有 early-cleanup Core
variant 在 completion 尚未 poll 时释放 stream、future 和三个 ticket。

负向矩阵必须保留不同的结束状态：人为把 length 改为 `4` 时，guest 在读取任何
handle 前 trap，`resource-drops=0`，stream/future 也尚未 drop，table 非空；人为连续
调用 release helper 两次时，第一次 drop 三个 ticket 并清零 frame slots，第二次 trap，
table 为空。这两种 Core-only mutation 不属于可构造的 WIT 值，也不允许进入公开接口。

Pinned Wasmtime `47.0.2` 对这个 `do:...` package 的
`wasmtime::component::bindgen!` 会生成未转义 Rust keyword `do` 并失败。runner 因而
使用相邻探针已验证的低层 `Linker` API；不为满足宏生成而修改私有 WIT package 名称。
该工具限制不改变 canonical ABI 事实。

上述证据现已支持一个已登记的 descriptor-specific lowering：
`do:record-resource-list-stream-probe@0.1.0/read-via-stream`。它不修改 generic
record-stream emitter，也不开放第二次 read、长度大于 `3`、nested list、variant element、
borrowed field、未登记 descriptor 或任何公开 ownership 语法；新增任何相邻 shape 仍须另立
canonical ABI 设计与 runtime gate。

## 3. 统一所有权状态机

公开 Do 类型仍是值语义。下面是 compiler 内部语义，不是源代码类型名。

### 3.1 状态

| 状态 | 含义 | 可执行动作 |
| --- | --- | --- |
| `owned` | 当前路径拥有唯一可转移/可终结句柄 | write、transfer、borrow-use、finalize、register-defer |
| `owned-deferred` | 当前作用域已有 defer 终结责任 | write、同一 defer 退出；禁止再次 transfer |
| `borrowed-use` | 一次 host 调用或当前表达式的临时观察 | 只能读取；返回边界后回到原 owner |
| `transferred` | owner 已交给 helper、sink 或 child operation | 禁止再次使用或终结 |
| `in-flight` | endpoint/subtask/future 已被注册到 waitable set，仍有未完成操作 | 只能由对应终态或 cancel 路径收尾 |
| `finalized` | close/abort/drop 已完成 | 不允许任何后续动作 |
| `cancelled` | 取消已进入终态，所有 live child 已释放 | 只允许幂等 frame teardown |
| `maybe` | 分支/循环合流时两条路径状态不一致 | 禁止离开作用域或继续使用，必须先收敛 |

现有 `src/build/sema_stream_lease.zig` 的 `owned`、`owned_deferred`、`moved`、
`finalized`、`maybe` 是上述语义的当前实现子集；`borrowed-use`、`in-flight`、
`cancelled` 属于后续资源/async 组合设计的显式概念，不要求立即增加公开语法。

### 3.2 合法转换

```text
owned -> owned-deferred        register_defer
owned -> borrowed-use          one host call / one expression observation
owned -> transferred           helper/sink/own parameter transfer
owned -> finalized             close / abort / canonical drop
transferred -> in-flight       child async operation is registered
in-flight -> finalized         completion callback drops child then parent
in-flight -> cancelled         cancel path marks terminal and drops live child
any reachable pair -> maybe    branch/loop join differs
maybe -> owned|finalized|...   only after explicit path reconciliation
```

以下动作必须拒绝：

- `transferred`、`finalized` 或 `cancelled` 再次 write/transfer/borrow；
- `owned-deferred` 在 defer 生效期间被转移；
- `maybe` owner 在 `return`、`break`、`continue` 或函数 fallthrough 时离开；
- 一个 parent waitable-set/subtask 在其 child endpoint 仍存活时被 drop；
- 同一个 source future、stream、sink endpoint 或 frame 被终结两次。

### 3.3 分支、循环与 defer

分支和循环合流按同一 slot 做逐项 join：状态相同则保留，否则为 `maybe`。`maybe` 不
允许保守地当作可用 owner；必须显式在所有路径完成相同 transfer/finalize，或拒绝并给出
稳定诊断。词法 `defer` 属于当前作用域的终结责任，跨作用域 transfer 必须先消除该
责任，否则报 `StreamWriterDeferredTransfer`。

### 3.4 嵌套清理顺序

资源图采用反向获取顺序清理：

```text
leaf resource / child subtask
        -> stream or future endpoint
        -> waitable-set membership
        -> parent frame
```

因此 `StreamMirror` 中必须先 `subtask-drop` 已完成的 sink child，再清空 frame slot，
然后 drop waitable-set；`resource has children` 是违反该不变量的硬错误，不能被吞掉或
降级为 warning。嵌套 record 的每个 owned leaf 也必须在 parent frame 释放前清零并 exactly
once drop。

### 3.5 取消

取消只改变 guest/Component 生命周期：

1. 标记 frame 为 `cancelled`，阻止新的 source read/write；
2. 取消并 drop 仍在 `in-flight` 的 subtask/future/stream；
3. 按 child-before-parent 顺序清理 frame 与 waitable-set；
4. 对外部数据库、网络或文件系统已经提交的副作用不做回滚，也不生成 operation id 或
   补偿回调。

## 4. 下一步授权边界

矩阵支持的首个正向切片已经完成：保留 private descriptor，增加一个能真正表达新
`in-flight`/terminal invariant 的 bounded producer operation sequence，包含一次显式
lease transfer 和一次 terminal completion；branch-selected `close/abort` 的证据见
`test_*stream_writer_guest_producer_branch_terminal.sh`。不得把它误解为可以只提高
forwarding 或 nested 深度常量。

### 4.1 当前授权结论

截至 2026-08-03，能力矩阵、负向 fixtures、ownership 状态机和完整回归均已通过。
本阶段不再授权第二个 positive codegen expansion：borrowed/list/variant payload、
任意 producer expression、六跳 forwarding、七层 nested resource、payload-bearing
completion error 和通用 async-call composition 都需要独立的设计、pinned-tool
probe、runtime gate 和 review。没有这些前置证据时，保持 `blocked`，继续做文档与
边界维护，不静默扩大 compiler 支持面。

在 capability matrix、上述状态机、负边界 fixtures 和完整回归都通过前，不得开始：

- 公开 `own<T>`、`borrow<T>`、`ref<T>`；
- 任意 async-call composition 或任意 producer expression；
- borrowed/list/variant resource stream fields；
- 第六跳 forwarding、第七层 nested positive lowering；
- 完整 WASI/D2 真 host I/O。

这些项目需要独立的 positive plan 和独立 review，不是本阶段的隐式副产物。
