# 待处理与阻断清单

更新时间: 2026-08-05
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
| **G6.2** | `descriptor.read-directory` 及 record-stream 通用能力 | generic consumer 已覆盖注册的非 filesystem record streams；bounded producer、StreamMirror、private Result cancellation、HTTP payload cancellation、resource-list stream 以及私有 `do:variant-resource-stream-canonical@0.1.0` 的 compiler-generated Component/Rust/Wasmtime gate 均已通过。variant slice 固定为 `ticket(own<ticket>)`、`idle`、`failed(io)`、单次 read、pending/completion error，frame `+64` 的 `tag@0,payload@4,size=8,align=4`，并保留 early-drop、malformed-tag 与 duplicate-release 负例；仍缺一般 async helper/producer lease、任意 producer 表达式、通用 list、通用 borrowed/variant lowering、第六跳 forwarding、第七层或更一般 nested resource 字段、payload-bearing completion error 的更广形状、任意 filesystem async method与通用 resource cancellation。Pinned `wasm-tools 1.254.0` 对含 `borrow<T>` 的 stream record 在 Component embed 阶段明确拒绝 | 保持 private cancellation slice 的 descriptor/负边界；扩展其他 producer/resource shape 前必须另立 design 与 gate |
| **06.2** | 历史总项 | 已拆到 G2–G6；通用 consumer slice 已关闭，剩余边界由 **G6.2** 的后续 gates 承接 | 同上 |

**G6.2 next-shape stop (2026-08-05, `can_skip=true`):** 当前计划要求的两个候选都没有形成新的独立 shape：payload-bearing completion error 的 pinned 证据属于现有 HTTP 专用 descriptor，record/list resource shape 已有独立 registry 与 runtime gate。没有新的 pinned WIT/WAT、canonical layout 和 ownership matrix 时不新增 descriptor、不泛化现有 lowering。恢复条件是先提交新的 bounded design、pinned probe、正负 fixture、Component/Rust/Wasmtime cleanup gate，再重新进入 G6.2。

**Task 8 Step 3 runtime baseline (2026-08-05, green):**
`examples/p3-runtime/test_task8_step3_baseline.sh` 已通过当前七个已登记
descriptor gate（cancel-wait-for、scalar/resource Result、stream reader/writer、
filesystem preopen、TCP/UDP sockets）。这只关闭运行时基线核验，不关闭
`AsyncLoweringUnavailable`；generic `Future`/`Stream` lowering 仍须按独立计划
建立 admitted shape、resumable frame、Component metadata 与 Rust/Wasmtime
pending/ready/cancel gate。

本轮执行复核（2026-08-05）重新运行了六跳 forwarding/任意 producer 边界、borrowed stream rejection 与 `p3_async_manifest`（74/74）；三项均保持预期拒绝/通过，因此 no-go 继续有效，未新增 descriptor 或 lowering。

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
| D2 | 完整 WASI/Component 运行时 | 已增加真实本地 filesystem preopen/open-at/sync、read-directory stream、CLI stdin pipe，以及 socket create/bind/drop 的 compiler-generated Component/Rust/Wasmtime smoke；仍缺通用 filesystem async lowering 与 external-network HTTP，故 D2 总项保持 in progress |
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

---

## 6. 推进顺序建议

1. 发布候选维护 (回归红灯 / 文档漂移)  
2. G6.2 capability matrix、ownership invariants、正向 Rust/Wasmtime gates 与 pinned negative gates 已收口；下一步只能为新的 producer/resource shape 建立独立 design、pinned probe、负向 fixture 与 runtime gate。
3. D2 当前只推进已授权的本地 file/dir/CLI smoke；socket/general filesystem async/external HTTP 的扩展须另立 target/design，其他 deferred 项仍需单独授权
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

`async name(...) -> T` is deprecated and rejected by normal semantic analysis
with `DeprecatedAsyncFunctionDecl`; the parser no longer registers it as a
function. It is not a public function model, and new examples and APIs must use
ordinary function declarations. The generic target still keeps a negative
`427_generic_async_runtime_async_root` fixture for its lowering boundary.

These bounded slices do not make arbitrary generated WIT async lowering,
`Future<T>`/`Stream<T>` payloads, resources,
aggregate await, timeout, multi-root scheduling, public ownership syntax, or
ordinary `do build` async programs complete. Unsupported shapes continue to
return `AsyncLoweringUnavailable`.

用户说 `go` / `next` 时以 `doc/start_here.md` §6 为准, 细节以本文件为准。
