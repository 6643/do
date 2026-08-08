# 待处理与阻断清单

更新时间: 2026-08-08
基线: 默认回归以 `./src/build/test/run_tests.sh` 最新结果为准  
关系: 总规划 `doc/master_plan.md`; 接手 `doc/start_here.md`; 执行状态 `doc/roadmap_status.md`  
约定: **只记未关闭项**; 完成后从本文件删除或移入「已关闭摘要」, 并同步入口文档与 `CHANGELOG.md`。

## 图例

| 标记 | 含义 |
| --- | --- |
| **blocked** | 缺产品/runtime 决策, 禁止绕过扩实现 |
| **pending** | 能力缺口已明确, 可单独授权后做 |
| **deferred** | v1 非目标或日路径不自动开, 需明确立项 |
| **skip** | 回归故意跳过, 与后置能力绑定 |

---

## 1. 阻断 (blocked) — G6 WASI / Component

Result source policy is closed and is not a G6 blocker: ordinary public Do
APIs use `T | E` (or `nil | E`), duplicate ordinary union branches remain
rejected, and same-type `Result<T, E>` is private WIT/Component compatibility
only. Public `own<T>`/`borrow<T>`/`ref<T>` syntax remains outside this phase.

| ID | 问题 | 证据 / 停止点 | 恢复条件 |
| --- | --- | --- | --- |
| **G6.2** | `descriptor.read-directory` 及 record-stream 通用能力 | generic consumer 已覆盖注册的非 filesystem record streams；bounded producer、StreamMirror、private Result cancellation、HTTP payload cancellation、resource-list stream、私有 `do:variant-resource-stream-canonical@0.1.0`、动态 count `0..3` 的私有 `do:g6-2-c-min-dynamic-producer@0.1.0`，以及固定两批 `[111,222]`/`[333]` 的私有 `do:g6-2-batched-list-producer@0.1.0` compiler-generated Component/Rust/Wasmtime gate 均已通过。D2 另关闭了私有 `descriptor.get-type`、`descriptor.sync` 与 `descriptor.get-flags` 三个有界方法；三者均固定 upstream WIT hash `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`，并分别通过独立 ABI、compiler admission 和 ready/pending/error/cancel cleanup gate。两类 producer 均固定 `ptr=64/len=68/stride=4/ticket=0`、stream capacity `1`，并保留 pending、sink error、early drop、转移前/后 cancellation、exactly-once resource/list cleanup 与 fail-closed 负例；仍缺一般 async helper/producer lease、任意 producer 表达式、通用 list、通用 borrowed/variant lowering、第六跳 forwarding、第七层或更一般 nested resource 字段、payload-bearing completion error 的更广形状、任意其它 filesystem async method与通用 resource cancellation。Pinned `wasm-tools 1.255.0` 对含 `borrow<T>` 的 stream record 在 Component embed 阶段明确拒绝（1.254.0 同样拒绝） | 保持所有 private bounded descriptor 的精确边界；扩展其他 producer/resource shape 前必须另立 design、probe 与 gate |
| **06.2** | 历史总项 | 已拆到 G2–G6；通用 consumer slice 已关闭，剩余边界由 **G6.2** 的后续 gates 承接 | 同上 |

**G6.2 next-shape stop (2026-08-08, `can_skip=true`):** 动态 count `0..3`
与固定两批次 private producer 均已形成独立 design、pinned WIT/WAT、registry/sema admission、
compiler adapter、正负 fixture和 Component/Rust/Wasmtime cleanup gate；这两个
bounded shape 已关闭。下一 shape 仍不得从它泛化：没有新的 pinned WIT/WAT、
canonical layout 和 ownership matrix 时不新增 descriptor、不泛化现有 lowering。
恢复条件是先提交新的 bounded design、pinned probe、正负 fixture、
Component/Rust/Wasmtime cleanup gate，再重新进入 G6.2。

**Generic ABI v2 borrow capability matrix (2026-08-06):** pinned
`wasm-tools 1.254.0 (bb58fdf91 2026-07-20)` accepted `component embed` plus
`component new` for direct `borrow<ticket>`, a borrowed record, a borrowed
variant, and `list<borrow<ticket>>`. A `stream<record { ticket: borrow<ticket> }>`
and `future<borrow<ticket>>` were both rejected during `component embed` with
the exact diagnostic `contains a \`borrow<T>\` which is not supported`.
This proves only toolchain shape capability; no Do compiler registry entry was
added. Before either rejected shape can be reconsidered, rerun the matrix with
a pinned toolchain upgrade or a newly measured canonical WIT shape.

**Generic ABI v2 borrow capability matrix refresh (2026-08-06):** the same
matrix was rerun against `wasm-tools 1.255.0 (76e20611d 2026-07-30)` via
`WASM_TOOLS_EXPECT_VERSION=1.255.0`. Direct `borrow<ticket>`, borrowed record,
borrowed variant, and `list<borrow<ticket>>` still accepted;
`stream<record { ticket: borrow<ticket> }>` and `future<borrow<ticket>>` still
rejected during `component embed` with the same
`contains a \`borrow<T>\` which is not supported` diagnostic. The boundary
is therefore not an artifact of 1.254.0 alone.

**Owned async capability matrix (2026-08-07):** the same pinned
`wasm-tools 1.255.0` probe also accepts `future<own<ticket>>` and
`stream<record { ticket: own<ticket> }>` during `component embed` and
`component new`. These are toolchain-only positive rows: no canonical async
frame layout, transfer/drop behavior, Rust/Wasmtime runtime gate, Do source
admission rule, or compiler registry descriptor exists for either shape. The
borrowed stream/future rejection and the no-public-ownership-syntax boundary
remain unchanged.

**Owned future canonical runtime checkpoint (2026-08-07):**
`examples/p3-runtime/test_future_owned_canonical_abi.sh` now proves one private
`future<own<ticket>>` shape through `wasm-tools 1.255.0`, Component assembly,
and Wasmtime `47.0.2`. The Core frame uses payload `+12`, ticket `+16`, and an
independent presence bit at `+20`; this is required because Wasmtime's first
`ResourceTable` representation is the valid handle `0`. Ready, pending-once,
and pending-then-cancel modes all pass with one future drop, exactly-once
resource drop only when a ticket is created, and `table-empty=true`. The
callback path also follows Wasmtime's contract that the third callback value is
encoded `ReturnCode`, while the result payload is already in the `future.read`
destination. This closes only the measured private runtime slice; it does not
admit generic owned futures/streams, borrowed async values, Do ownership syntax,
or a compiler registry descriptor.

**Private owned-future compiler promotion (2026-08-07, green):**
`--p3-owned-future-component` now admits exactly the registered
`Future<Ticket>` source shape and emits the private `future<own<ticket>>` WIT
sidecar. `examples/p3-runtime/test_do_future_owned_component.sh` passes
sidecar identity, compiler WAT markers, `wasm-tools 1.255.0` parsing, pinned
`wasm-tools 1.254.0` legacy async assembly/validation, target isolation, and
the Rust/Wasmtime ready/pending/cancel matrix. The three opt-in negative
fixtures reject before WAT as `UnsupportedP3OwnedFutureComponent`. This
closes only one private compiler promotion; generic owned futures/streams,
borrowed async values, public ownership syntax, arbitrary producer
expressions, general filesystem async, and D2 host I/O remain pending.

**Synchronous `list<borrow<T>>` canonical ABI probe (2026-08-06):**
`examples/p3-runtime/test_list_borrow_canonical_abi.sh` independently assembles
`do:list-borrow-canonical@0.1.0` with `wasm-tools 1.255.0`, validates the
Component, and executes the Core import through Wasmtime `47.0.2`. The probe
covers `len=0/1/3`, observes a canonical `ptr=64` list base with 4-byte handle
elements, and passes the same owner handle as each borrowed element. The host
callback sees the owner live and records one borrow call; the owner is dropped
exactly once after the exported call and the `ResourceTable` is empty. This is
evidence for one synchronous private ABI shape only; it does not admit the
shape to the Do compiler registry, and does not relax the rejected nested
`stream`/`future` borrow rows or add public ownership syntax.

**Generic ABI v2 internal plan checkpoint (2026-08-06):** pure `AbiType`,
measured `LayoutPlan`, explicit own/direct-borrow `OwnershipPlan`, and terminal
`AsyncPlan` modules are green. The private variant-resource-stream adapter is
still opt-in only, but now renders an independent v2 template from the pinned
descriptor and measured layout; it no longer returns the v1 canonical WAT. The
independent artifact passed `wasm-tools` parse/embed/new/validate and the
ticket/idle/error/pending/completion-error Rust/Wasmtime cleanup matrix. The
private scalar-i64 adapter is also opt-in through
`--p3-async-v2-scalar-i64`; its measured 8-byte layout and
ready/pending/cancel Rust/Wasmtime matrix are green, and payload manifest drift
is rejected before emission. The new unified `--p3-async-component-v2` profile
routes the same scalar-i64 adapter plus the variant-resource-stream adapter, but
the default emitter and registry dispatch remain v1. Public
`own<T>`/`borrow<T>`/`ref<T>` syntax, generic WAT emission beyond this admitted
pair of private shapes, unmeasured layouts, and the toolchain-rejected borrowed
stream/future shapes remain pending. Promotion now has two independent private
shape gates and a deliberate registry/runtime switch, but default v1 dispatch
still stays unchanged.

**Generic ABI v2 promotion profile (2026-08-07):** the explicit
`--p3-async-component-v2` profile is now wired through CLI, pipeline, and a
fail-closed dispatcher. `bash examples/p3-runtime/test_generic_abi_v2_promotion.sh`
passes the independent variant-resource-stream and generated `Future<i64>`
Component/Rust/Wasmtime matrices; a generated scalar-u32 input is rejected as
`UnsupportedGenericAbiV2Promotion` before a WAT file is created. The default
`--p3-async-component` path and the legacy scalar-i64 compatibility flag remain
unchanged. This closes only registry/runtime promotion for the two private
shapes; generic payload/list/resource lowering, public ownership syntax, and
borrowed stream/future shapes remain pending.

**Task 8 Step 3 runtime baseline (2026-08-06, green):**
`examples/p3-runtime/test_task8_step3_baseline.sh` 已通过当前七个已登记
descriptor gate（cancel-wait-for、scalar/resource Result、stream reader/writer、
filesystem preopen、TCP/UDP sockets）。这只关闭运行时基线核验，不关闭
`AsyncLoweringUnavailable`；generic `Future`/`Stream` lowering 仍须按独立计划
建立 admitted shape、resumable frame、Component metadata 与 Rust/Wasmtime
pending/ready/cancel gate。

**General async-call lowering ABI boundary (2026-08-07):** the independent
probe `examples/p3-runtime/test_async_call_component_probe.sh` was run with
pinned `wasm-tools 1.254.0 (bb58fdf91 2026-07-20)` (SHA-256
`cc1f862d69363aac2d4a88f01c414a2dcf10858632d0c0a45e93ff60503979d6`). Core
parsing and legacy async metadata attachment succeeded, but Component
assembly rejected a synthetic internal helper endpoint:
`failed to resolve import [export]$root::[task-return]helper` / `no export
helper found`. The current async Component ABI exposes `task.return` only for
WIT async exports; an ordinary guest helper has no independent child-task
endpoint. `wit-bindgen` `spawn_local` is an executor-local queue, not a
Component task primitive. The same gate accepts and validates the selected
root-owned local-frame probe, which stores the host subtask in the root frame
and resumes through `[task-return]run`. The compiler plan therefore continues
with local frame/state lowering; independent guest child-task creation remains
deferred. Do not add a helper WIT export or route this shape through v1.
Recovery for the deferred capability requires a pinned ABI/toolchain design
that specifies guest child-task creation, continuation delivery, cancellation,
and child-before-parent cleanup.

**Bounded general async-call slice (2026-08-08, green):** the root-owned
local-frame target is implemented behind `--p3-async-call-component`. It uses
the separate private `do:generic-async-call-probe@0.1.0` `host.work: async
func()` descriptor; the existing `do:generic-async-runtime-probe` descriptor
and v1/v2 targets remain unchanged. The analyzer accepts both the child-only
unit root and exactly one leading inline `helper()` followed by the explicit
`@async(helper())` child. `examples/p3-runtime/test_do_async_call_component.sh`
passes pinned `wasm-tools 1.254.0` assembly/validation, verifies inline and
child state markers, two host call sites, no helper export, and v1 rejection
before WAT. The Rust/Wasmtime gate
`test_rust_async_call_component.sh` passes `ready`, `pending`, `cancel-inline`,
and `cancel-child`: ready/pending each observe two completions and two drops;
`cancel-inline` observes one pending drop; `cancel-child` observes one
completed and one pending drop. Both cancellation modes have no duplicate drop
and an empty `ResourceTable`.

The opt-in analyzer rejects helper parameters/payloads, multiple live
children, a second inline call, and nested helper calls as
`UnsupportedP3AsyncCallComponent`; the normal default build still reports
`AsyncLoweringUnavailable` for those fixtures because it does not select the
opt-in target. Generic async-call composition, arbitrary producer expressions,
payload/Stream/resource/list futures, public ownership syntax, general
filesystem async, and D2 host I/O remain pending. Independent guest child-task
creation remains blocked by the pinned Component ABI described above.

本轮执行复核（2026-08-07）重新运行了六跳 forwarding/任意 producer 边界、borrowed stream rejection 与 `p3_async_manifest`（74/74）；三个 gate 均保持预期拒绝/通过。同步确认了 descriptor-bounded StreamMirror 六模式、默认 Bun 回归 `pass=1116 fail=0 skip=3`、WASM 回归 `pass=1118 fail=0 skip=3`（WASM smoke `6/6`）和 ReleaseSmall smoke 通过；nested lowering、borrowed rejection、G6.2 boundary 与完整 compiler/Wasm 矩阵均保持绿色，未新增 descriptor 或 lowering。

**规则**: 固定一至三条目 read-directory slice、generic consumer slice、multi-owned、多个顶层 nested-owned resource path 以及一层/两层/三层/四层/五层/六层 nested-owned resource consumer slice、注册的单读 `stream<list<resource-entry>>` private slice、bounded scalar producer slice、受限（最多五跳 forwarding）helper-mediated producer-lease slice、固定/参数化 `u64` countdown producer slice、参数化 helper producer slice及其五跳 forwarding、三种 typed 参数受限重排形状与 branch-selected terminal slice 均已可用；无对应 producer-lease/resource gate 时，不绕过上述边界扩 WASI async/stream codegen。

**G6.2 HTTP payload-error checkpoint (registered slice green; broader support pending):**
注册的 `internal-error(option<string>)` 与
`DNS-error(option<string>, option<u16>)` 已通过 compiler-generated
Component 的 pending/ready 精确值与 cleanup gate；`InternalError(None)`、
`InternalError(Some("x"))`、`DnsError(rcode=Some("EAI"),info-code=Some(7))`
均保持 payload 且 `table-empty=true`。ready immediate-return 路径按
`Status::Returned` 不携带 waitable 的协议处理，不再把 `0` 当作 handle；
`examples/p3-runtime/test_do_http_payload_error_lowering.sh all` 是组合入口。
未登记 payload tag 仍必须 trap，不能把这个注册 slice 扩写成完整 HTTP
payload/runtime 支持。

**G6.2 HTTP payload-cancellation checkpoint (registered slice green; broader
support pending):** `http-payload-cancel.do` 的显式
`@cancel(completion)` 已通过 pinned `wasi:http` service-world 组装、精确的
`[async-lower]send`/resource-drop 导入检查，以及 Rust/Wasmtime 三模式 gate。
pending 观察到一次 request consumption、至少一次 poll、一次 pending future drop、零
response create/drop 和空 `ResourceTable`；`Status::Returned` 的 immediate
`Ok(response)` 使用固定 `[64,128)` result scratch、从 offset `8` drop 一次
response，`Err(DnsTimeout)` 不创建资源，两个 ready host Future 均 poll/drop 一次，
二者也都 table-empty。独立手写 WAT probe 已在
`DNS-error(rcode: Some("EAI"), info-code: Some(7))` 上证明 canonical lowering 的
`cabi_realloc(0,0,1,3)` 与 guest discard 的 `cabi_realloc(ptr,3,1,0)` 各恰好一次；
重复、遗漏或参数不一致都 trap。compiler template 据此允许每个 immediate
`DNS-error`：`rcode` 可为 `None` 或 `Some(nonempty)`；`Some` 在 `[128,65536)` 内同一时刻分配
一次并以实测 `ptr,len` 精确释放，释放后槽位可供同一实例的后续顺序调用复用，`None` 只校验
discriminant，不读取或释放 payload；
`info-code` 可为 `Some` 或 `None`。Rust/Wasmtime gate 覆盖
`Some("EAI"), Some(7)`、`Some("dns-error-long"), None` 和
`None, None`，均为 ready poll/drop `1/1`、零 response、`table-empty=true`；同一实例连续两次
`Some("EAI")` 也验证两次 poll/drop、零 response 与空表。
同一 string ABI 也已覆盖 `InternalError(Some("no"))` 与 `InternalError(None)` 的正常
discard；空字符串、含 resource/record 的 payload、cancel-after-terminal、double
cancellation、隐式 scope-drop、未登记 HTTP 形状和通用 resource cancellation 仍保持
显式 trap 或阻断；同一组件实例的并发 cancellation invocation 未由该单槽
scratch gate 证明，不得从该 bounded slice 推断并发安全或 generic free。

G6.2.3 的路径敏感 `StreamWriter<T>` lease 语义基础已完成：if/else 合流、loop
`break`/`continue`、词法 `defer`、同类型 transfer、helper transfer、writer write、终结
和 async exit 都有统一状态检查；不一致合流报 `StreamWriterLeasePathConflict`，带 defer
cleanup 的跨作用域转移报 `StreamWriterDeferredTransfer`。该项只关闭前端语义检查，不关闭
本行列出的 general producer lease、任意 async-call lowering、任意 producer expression、
borrowed/list/variant resource field 或更宽 runtime 形状。

**G6.1 已关闭 (方案 A)**: `preopens.get-directories` → do `[Tuple<i32,text>]` host / 公开 `preopen_directories() -> [Tuple<Dir, text>]`; list-of-tuple resource lowering + `lib/dir.do`; 见 `compile_ok/274`–`275`。

**G6.3 已关闭 (方案 B)**: sockets `tcp/udp-socket.create|bind|drop` 可 lower; 地址为 dual concrete + `IpSocketAddress = V4|V6` payload enum; resource shell + 粗粒度 `TcpError`/`UdpError`; stdlib `lib/tcp.do` / `lib/udp.do` / `lib/net.do`; compiler-generated Component 与 Rust/Wasmtime TCP/UDP loopback smoke 已通过（含 create/bind failure cleanup）；见 `compile_ok/291`–`294` 与 `docs/superpowers/specs/2026-07-13-g6-3-sockets-scheme-b-design.md`。D2 总项仍保持 in progress。

---

## 2. 待处理 (pending) — 语言 / codegen 已知缺口

### P2. 泛型递归: 仅靠左侧目标类型反推

| 项 | 内容 |
| --- | --- |
| 状态 | **pending** (产品原则: 默认 **不** 放开) |
| 现象 | `out i32 = generic_countdown(2, 9)` → `NoMatchingCall` |
| 锁点 | `err/329_generic_recursive_target_type_only_uninferred` |
| 已支持对照 | 参数侧已定型: `seed i32 = 9; generic_countdown(2, seed)` (`ok/184`) |
| 原则 | 调用点参与决议的类型须在 **实参侧已知**; 泛型位先绑有类型局部再传入, 不靠左侧静默反推 (避免 monomorphize 分支不明) |
| 恢复条件 | 若改原则须单独规格 + 实现; 否则保持失败, 可仅改善诊断文案 |

### P3. 回归 skip (与 host / WASI 后置绑定)

| Skip fixture | 状态 | 说明 |
| --- | --- | --- |
| `16_loop_recv_value` | **skip** | recv 相关后置 |
| `96_file_lib_resource_shape` | **skip** | file/resource shape; 真 host I/O 后置 |
| `118_wasi_p3_std_wrappers` | **skip** | WASI p3 std wrappers; 依赖 G6 / host |

恢复: G6 决策 + 真 host smoke 后再收回, 不在默认回归里强行变绿。

---

## 3. 延期 (deferred) — v1 非目标 / 需单独授权

| ID | 项 | 说明 |
| --- | --- | --- |
| D1 | 完整 ownership IR | 跨函数唯一性 / escape / region / 激进 loop move; 门槛见 `doc/memory.md` |
| D2 | 完整 WASI/Component 运行时 | 已增加真实本地 filesystem preopen/open-at/sync、read-directory stream、CLI stdin pipe，以及 socket create/bind/drop 的 compiler-generated Component/Rust/Wasmtime smoke；私有 `descriptor.get-type`、`descriptor.sync` 与 `descriptor.get-flags` 各自通过 pinned ABI、compiler/runtime gates；仍缺通用 filesystem async lowering 与 external-network HTTP，故 D2 总项保持 in progress |
| D3 | JSON 自动序列化扩展 | error/enum/union/复杂 storage; 当前仅已验证 struct 字段子集 |
| D4 | LSP 增强 | rename / references / import-aware 跨模块 / 增量 index |
| D5 | fmt 增强 | 多文件批量、range/on-type、完整语法感知 |
| D6 | direct wasm binary emitter | 不替换 WAT 主路径; 仅并行评估 |
| D7 | codegen 垂直再拆 | 如 WASI emit 切片; 先 parse/validate 再搬; 需授权 |
| D8 | 包管理 get/pkg/push | 不重开 |
| D9 | `RUN_WASM=1` 全量扩展回归 | 耗时长; 发布前显式跑, 非默认日路径 |
| D10 | `@host_ref` / Wasm ref 语法 | `externref`→将来 `@host_ref`; `anyref` 不做公开; `funcref` 非一等类型; i32 指针永不做 do 类型。**仅记录策略, 不实现**。权威: `doc/design/wasm_ref_host_syntax.md`。扩讨论: `doc/design/2026-07-13-wasm-wasi-support-discussion.md`（已搁置） |

详见 README「v1 非目标」与「下一阶段计划」。

---

## 4. 设计硬约束 (非待办, 实现必守)

| 约束 | 说明 |
| --- | --- |
| Tuple **永不拍平** | 嵌套 `Tuple` / struct 直接子槽保持嵌套类型与 `@get` 路径; 禁止与扁平 Tuple 等同或隐式 coerce |
| 泛型调用类型已知 | 函数要用的类型在实参侧已知; 不默认左侧反推 direct type param |
| G6 不绕过 | 无决策不扩 read-dir (async) codegen; sockets create/bind/drop 已按 G6.3 B 落地 |
| Wasm ref 语法 | 不引入 `*T`/`&T`/公开 `externref`/`anyref`/`funcref`; 策略见 `doc/design/wasm_ref_host_syntax.md` (D10, 未实现) |

权威条文: `doc/spec_rules.md` (Tuple 节等)。

---

## 5. 已关闭摘要 (勿当待办)

- pure-scalar struct 作为 Tuple storage 嵌套子槽 (`compile_ok/272`, `ok/192`; 局部名 `$pair.0.x`)
- managed/`text` 作为 Tuple **直接叶子** storage + path chain (`compile_ok/270`–`271`)
- **P1** 含 managed 字段的 struct 作 Tuple 直接子槽: 句柄叶子 + storage pack ARC (`compile_ok/273`, `ok/193`; 不拍平 `Cell` 字段)
- pure-scalar field-reflect `field_set` 误 shadow (`ok/191`)
- 阶段 A–F、H、I (I1+I2) 主线; G1–G5、G6.1、G6.4
- **G6.1** preopens 方案 A: host `[Tuple<i32,text>]` + `preopen_directories() -> [Tuple<Dir, text>]` (`compile_ok/274`–`275`)
- **G6.3** sockets 方案 B: create/bind/drop + dual address + payload enum + stdlib wrappers (`compile_ok/291`–`294`)
- **G6.2 C-min producers**: private closed `0/1/3`, dynamic-count `0..3`, and
  fixed two-batch `[111,222]`/`[333]`
  `stream<list<resource-entry>>` producers with measured
  `ptr=64/len=68/stride=4/ticket=0`, exact Do admission, compiler
  Component/Rust/Wasmtime ready/pending/error/cancel gates, and fail-closed
  negative fixtures; generic list/producer and public ownership remain pending
- **D2 filesystem `descriptor.get-type`**: the private pinned method passed
  hand-authored/generated Component assembly and Rust/Wasmtime
  ready-directory/regular, pending, error, and cancel cleanup gates; fixtures
  `459`-`461` reject descriptor/result/borrowed-payload drift. General
  filesystem async methods and public ownership remain pending.
- **D2 filesystem `descriptor.sync`**: the private pinned method passed both
  current `wasm-tools 1.255.0` and legacy `1.254.0` ABI assembly/validation with
  upstream WIT hash
  `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f` and
  regular/cancel mirror hashes
  `18ce7dc9efb991cd8e5f945797aea73edeed79f0cfc51ea664cb81537e54e719` /
  `9898cd734708a2ab14760da706d69063e5cd6262a5e03d07d8eedd8074745f36`,
  `[async-lower][method]descriptor.sync (i32,i32)->i32`, unit/error-code
  component-variant completion, and `[resource-drop]descriptor`. The private
  compiler fixtures `462`-`465` reject locator/result/borrowed-payload/second-
  await drift. Hand-authored ready/pending/error/cancel and generated
  ready/pending/error Rust/Wasmtime rows pass with exactly-once cleanup and
  `table-empty=true` (ready/error one poll, pending two polls plus one wake,
  cancel zero completion with one pending-future drop). Fresh gates are
  `zig=308/308`, default `pass=1149 fail=0 skip=3`, WASM
  `pass=1151 fail=0 skip=3` (`6/6`), and ReleaseSmall smoke; other filesystem
  methods, general async producers, borrowed payloads, and public ownership
  remain pending.
- **D2 filesystem `descriptor.get-flags`**: the private pinned method passed
  current and legacy `wasm-tools` ABI assembly/validation with upstream WIT
  hash `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`, WIT
  mirror hash `12afdb48b07d7160c76f04231fb8da4862350d42f6170174e6e27264b7307be9`,
  `[async-lower][method]descriptor.get-flags (i32,i32)->i32`, canonical `u8`
  result storage, flat `i32` task-return payload, `descriptor-flags | error-code`
  completion, and `[resource-drop]descriptor`. Compiler fixtures `471`-`474`
  reject locator/result/borrowed-payload drift. Hand-authored
  ready/pending/error/cancel and generated ready/pending/error Rust/Wasmtime
  rows pass with exactly-once cleanup and `table-empty=true`; other filesystem
  methods, general async producers, borrowed payloads, and public ownership
  remain pending.

---

## 6. 推进顺序建议

1. 发布候选维护 (回归红灯 / 文档漂移)  
2. G6.2 capability matrix、ownership invariants、正向 Rust/Wasmtime gates 与 pinned negative gates 已收口；下一步只能为新的 producer/resource shape 建立独立 design、pinned probe、负向 fixture 与 runtime gate。
3. D2 当前只推进已授权的本地 file/dir/CLI smoke 与已关闭的私有 `descriptor.get-type`/`descriptor.sync`/`descriptor.get-flags` slices；socket/general filesystem async/external HTTP 的扩展须另立 target/design，其他 deferred 项仍需单独授权
4. **P2** 默认不改; 除非产品明确要左侧反推

## 7. Generic async Component runtime slices (2026-08-06)

The admitted source model is now colorless: user functions use ordinary
declarations, synchronous calls become `Future<T>` only through `@async(call)`,
and `@await`/`@cancel` are explicit intrinsics. A registered WIT `async func`
already returns `Future<T>` and must not be wrapped in `@async`.

The exact descriptor-backed runtime shape in
`examples/p3-runtime/generic-async-runtime.do` has a separate Component target.
Its WIT sidecar, real pending/ready/cancel state machine, wasm-tools
componentization, and Wasmtime host-drive smoke are reproducible with
`examples/p3-runtime/test_do_generic_async_runtime.sh`. The Rust host observes
one external wake and one completion for pending, immediate completion without
an external wake, and cancellation before completion with one drop.

Generated WIT bindings now have one additional bounded admission path. The
private `do:generic-async-runtime-probe@0.1.0` world is emitted as manifest
schema 2 with the exact `component-async-unit-v1` capability; import resolution
discovers and validates that metadata before Component codegen. The generated
caller and its full Component/Rust/Wasmtime gate are reproducible with
`examples/wit-bindgen-do/test_generated_async_lowering.sh`. The gate observes
`pending external-wakes=2 completions=2 drops=1`,
`immediate external-wakes=0 completions=3 drops=0`, and
`cancel cancel-before-completion=1 completions=2`.

The scalar companion is also admitted as a separate private capability:
`do:generic-async-scalar-probe@0.1.0` `host.completion: func() -> future<u32>`
uses manifest `component-async-scalar-u32-v1` and the measured payload layout
`offset=12`, `byte-size=4`, `alignment=4`, `encoding=core-u32`. Its generated
caller and Component/Rust/Wasmtime gate are reproducible with
`examples/wit-bindgen-do/test_generated_async_scalar_lowering.sh`; ready,
pending, and cancel all verify `value=42`, exactly-once future cleanup, and an
empty resource table. The cancel path observes three polls because the
Wasmtime cancellation protocol performs the initial readable check and a
second cancellation check; this is the measured protocol, not a rollback.

The scalar companion now also has a separate pinned i64 capability:
`do:generic-async-scalar-i64-probe@0.1.0` `host.completion: func() -> future<s64>`
uses `component-async-scalar-i64-v1` and the measured payload layout
`offset=16`, `byte-size=8`, `alignment=8`, `encoding=core-s64`. Its generated
caller and Component/Rust/Wasmtime gate are reproducible with
`examples/wit-bindgen-do/test_generated_async_scalar_i64_lowering.sh`; the
same ready/pending/cancel cleanup markers pass, while generic `Future<T>`,
text/list/resource payloads, and unrestricted generated WIT lowering remain
rejected.

`async name(...) -> T` is deprecated and rejected by normal semantic analysis
with `DeprecatedAsyncFunctionDecl`; the parser no longer registers it as a
function. It is not a public function model, and new examples and APIs must use
ordinary function declarations. The generic target still keeps a negative
`427_generic_async_runtime_async_root` fixture for its lowering boundary.

These bounded slices do not make arbitrary generated WIT async lowering,
generic `Future<T>`/`Stream<T>` payloads, resources,
aggregate await, timeout, multi-root scheduling, public ownership syntax, or
ordinary `do build` async programs complete. Unsupported shapes continue to
return `AsyncLoweringUnavailable`.

用户说 `go` / `next` 时以 `doc/start_here.md` §6 为准, 细节以本文件为准。
