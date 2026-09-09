# do 编译器主计划

状态: v1 子集发布候选已收口; G5c residual capability matrix 已完成且当前 exact candidate 已通过专用与全局门禁; G6 generic consumer、bounded nested resource paths、私有双 owned-field record producer、参数化双 owned-field record producer、固定三字段 `ResourceTriple`、nested-owned-record private compiler admission、private async `map<u32,u32>` compiler admission 与 G6.2 general producer/resource internal contract consolidation 已闭环, D2 私有 descriptor slices 与私有有界 `stream<list<u32>>` producer promotion 已闭环, 剩余 producer/resource residual；Task 8 Step 4/5 Shell-to-Zig parity 与 Task 9 active gate/文档/回归/回滚检查点已闭环；Task 6 GC-first runtime cutover 已闭环，普通编译入口现为 GC-only，ARC 仅保留显式 test-only equivalence oracle
更新时间: 2026-09-09

实时接手入口: `doc/start_here.md`。  
执行证据与历史勾选不再维护在本文; 需要追溯时查 git 与 `CHANGELOG.md`。

## 0.1 2026-09-09 GC-first runtime cutover

Task 6 已闭环。生产入口改为 `src/build/codegen_runtime_api.zig`，普通
`do build`/`do test` 路径只选择 Wasm GC；ARC emitter 不再作为隐式 fallback，
仅由 `src/build/test/gc_arc_equivalence_oracle.zig` 显式调用，用于保留语义等价
快照。当前证据为 ARC inventory post-cutover `rows=49 matches=480
unclassified=0 normal_route_matches=0`、生产依赖闭包 `modules=153 forbidden=0`、
GC default gate `87 fixtures`、semantic-equivalence `26 rows; 0 pending`。

当前工具链为 `wasm-tools 1.258.0`、Wasmtime `48.0.1`、Zig `0.16.0`、
Rust/Cargo `1.97.1`。默认及 `RUN_WASM=1 RUN_GC_CORE=1` harness 均为
`14/14 steps; 53/53 tests`，独立 `zig test main.zig` 为 `1561/1561`，
ReleaseSmall/release smoke 通过。`complete_rows=15 pending_rows=15` 仍是
能力矩阵状态，不能被解释为 cutover 失败或通过 cutover 自动关闭。

GC cutover 不开放 public `own<T>`、`borrow<T>`、`ref<T>`，也不扩大通用
async/map/producer/resource lowering；这些继续按各自 design、manifest、negative
和 Component lifecycle gate 推进。

## 0.2 2026-09-09 private async map compiler admission

`--p3-async-map-component` 只准入 pinned
`demo:map-async-probe/api@0.1.0.submit`：Do 输入是
`HashMap<u32,u32>`，严格 source matcher 要求两个固定 pair、一个 helper/root
await 拓扑和注册 descriptor，Core 形状为
`(i32 ptr, i32 len, i32 result_area) -> i32`。WAT/WIT snapshot、copy-before-call、
post-call overwrite、result-area/root return、cleanup markers 和五个 WAT 前负例
均通过 `UnsupportedP3AsyncMapComponent` 门禁；Component parse/embed/new/validate
及 Rust/Wasmtime `ready/pending/cancel/drop` 也通过。默认构建同一源仍返回
`AsyncLoweringUnavailable` 且不产生 WAT/WIT。该 private promotion 不开放通用
async map、其他 key/value、Stream 跨 poll buffer、arbitrary producer 或 public
ownership syntax。

## 0. 当前基线

当前 active toolchain adapter 以 `toolchain/toolchain.lock.json` 为唯一版本
来源：`wasm-tools 1.258.0 (5c6d31c78 2026-08-24)`、Wasmtime `48.0.1`、
Zig `0.16.0`、Rust/Cargo `1.97.1`。文档中较早的 `wasm-tools 1.255.0`
仅保留为历史验证证据，不参与 active route。Zig harness 的 compiler/GC、
WASI/component、Rust lifecycle 与 structural 编排已验证；`run_tests.sh` 现为
薄入口 `cd src && zig build test --summary all`，默认及 `RUN_WASM=1` /
`RUN_GC_CORE=1` opt-in 回归均为 `14/14` steps、`53/53` tests；独立
`zig test main.zig` 为 `1561/1561`；WIT map 的
`wit_abi_types`/bounded Core WAT lower/lift probe 与精确同步
`map<u32,u32>` manifest-backed Component lower/lift gate 已通过 current
toolchain parse/validate 和 Rust/Wasmtime host execution；精确 async
`map<u32,u32>` capability 与 private `--p3-async-map-component` compiler route
也已通过固定 WIT/WAT、负例和四模式 lifecycle gate，但通用 Component/WIT map
runtime lowering 仍独立阻断。

已完成并可作为后续依赖的能力:

- 规范: `doc/spec.md`、`doc/spec_rules.md`、`doc/grammar.peg`、`doc/syntax/*`、`doc/memory.md`、`doc/wit/*`。
- 工具链: `do build` / `do test` / `do test --compiled` / `do check` / `do run` / `do fmt` / `do lsp`。
- Component assembly tooling is current-only: `wasm-tools 1.258.0 (5c6d31c78 2026-08-24)`, SHA-256 `282e0014d38daf233cb10fb92815813b339e2b7f8b4734f6698f0176c7d99424`; `--dummy-names legacy` is a current async naming mode, not a legacy binary route.
- `do lsp`: diagnostics + formatting + semantic tokens + hover + completion + definition (无 rename)。
- `do fmt`: stdout / check-only / write 单文件。
- `do check`: lexer/parser/sema/import diagnostics only; 诊断收集在 `src/build/diagnostics.zig`。
- 阶段 A–F、H 已完成; D 可推进项与 D2.1 已收口; D2 真实本地 file/dir/CLI stream、compiler-generated TCP/UDP socket create/bind/drop loopback smoke 与私有 `descriptor.get-type`/`descriptor.sync`/`descriptor.get-flags`/`descriptor.stat`/`descriptor.sync-data`/`descriptor.metadata-hash`/`descriptor.metadata-hash-at`/`descriptor.stat-at`/`descriptor.open-at`/`descriptor.set-size` async slices 已收口，但总项仍受通用 filesystem async/external HTTP 阻断; G1–G5、G6.4 已完成; **阶段 I (I1+I2) 已关闭**。
- 架构扁平拆分已落地: `type_name` / `sema_error` / `diagnostics` / `gen_*` 域竖切 / `sema_*` 域竖切 (见 `AGENTS.md`)。
- 最新 fresh release-candidate 回归: 默认及 `RUN_WASM=1 RUN_GC_CORE=1` 组合的 `./src/build/test/run_tests.sh` 均为 `14/14` steps、`53/53` tests；`zig test main.zig` 为 `1561/1561`。ReleaseSmall/release smoke、GC default gate（87 fixtures）、ARC inventory post-cutover（`rows=49 matches=480 unclassified=0 normal_route_matches=0`）、生产依赖闭包（`modules=153 forbidden=0`）和 semantic-equivalence（26 rows; 0 pending）均通过；inventory 仍为 `complete_rows=15 pending_rows=15`、预期 exit `1`。
- G6.2 私有 direct owned-record producer 已通过独立 canonical ABI、Do/Component、Rust/Wasmtime 与 canonical/generated Component 生命周期等价门禁：精确 `stream<resource-entry>`、4-byte `ticket: own<ticket>` record、offset `0`、capacity `1`、WIT hash `6c1406962ee4c4e3eec5b3b4a866acfd1d8eb6ee159ce5b4077df113063d1ace`；十模式 valid/invalid cleanup 均闭环。该 Component 等价证据不计入 ARC/GC 语义矩阵；通用 producer/resource 与公开 ownership syntax 仍未开放。
- G6.2 私有 two-owned-field record producer 已通过独立 canonical ABI、Do/Component、negative admission、generated Rust/Wasmtime 与 canonical/generated Component 生命周期等价门禁：精确 `stream<resource-pair>`、8-byte `left/right: own<ticket>` record、offset `0/4`、capacity `1`、WIT hash `89345a5213936735d7f065cd54ed42b83d159b80305a1a900ae00df2e811704d`；presence mask 只在完整写入成功后原子转移两个 handle，十模式 valid/invalid cleanup 均闭环，valid 为 `2/2` drops、repeat 为 `4/4`，invalid 不创建资源；ABI 还观测 host `callback-calls`、stream poll/finish（`finish-calls=0`）及取消模式的 `cancel-calls=1` 与 pending future drop。该独立 Component 生命周期证据不计入 ARC/GC 语义矩阵；generic producer、arbitrary expression、borrowed/list/variant payload、general async/resource lowering 与公开 ownership syntax 仍未开放。
- G6.2 私有参数化 two-owned-field record producer 已通过独立 canonical ABI、Do/Component、十个 fail-closed negative fixtures、generated Rust/Wasmtime 与 canonical/generated Component 生命周期等价门禁：精确 descriptor `do:g6-2-owned-record-pair-parameterized-producer@0.1.0`、WIT hash `e7abd3cf7b7543325865a0b4be4b32ae50a2470ac5083169250719f89b7ce53a`、`stream<resource-pair>`、8-byte `left/right: own<ticket>` record、offset `0/4`、capacity `1`、producer inputs `(mode,left-seed,right-seed)`；presence mask 只在完整写入成功后原子转移两个 handle，十模式 valid/invalid cleanup 均闭环，valid 为 `2/2` drops、repeat 为 `4/4`，invalid 不创建资源，`table-empty=true`。该独立 Component 生命周期证据不计入 ARC/GC 语义矩阵；generic producer、arbitrary expression、borrowed/list/variant payload、general async/resource lowering 与公开 ownership syntax 仍未开放。
- G6.2 固定三字段 `ResourceTriple` private compiler admission 已通过精确 manifest/source matcher/lowering、13 个负例 fixture (`712`–`724`)、生成 WAT/WIT、Component validate、Rust/Wasmtime lifecycle 与 canonical/generated parity gate：package `do:g6-2-owned-record-triple-producer@0.1.0`、WIT hash `73fd57dc8f34f13023b48f2b82e439b212eab52192886f0d07a37d86e63658b1`、12-byte/alignment-4 `left/middle/right: own<ticket>` record、offset `0/4/8`、capacity `1`、producer inputs `(mode,left-seed,middle-seed,right-seed)`；presence mask 仅在完整写入后转移，转移前按 `right -> middle -> left` 释放，转移后 host 各释放一次，十模式 valid/invalid cleanup 均闭环，valid 为 `3/3` drops、repeat 为 `6/6`，所有模式 `table-empty=true`，invalid 不创建资源。该私有 route 仍不计入 ARC/GC 语义矩阵，不开放 generic/arbitrary producer、borrowed/list/variant payload、general async/resource lowering、公开 ownership syntax 或 GC inventory row。
- G6.2 nested-owned-record producer private compiler admission 已通过精确 manifest/source matcher/lowering、21 个负例 fixture (`725`–`745`)、生成 WAT/WIT、Component validate、Rust/Wasmtime lifecycle 与 canonical/generated parity gate：package `do:g6-2-owned-record-nested-producer@0.1.0`、WIT hash `9662440709b01044544d4c4350f3e6f783a8f06aaa5c884a96a1e43a935a7543`、`Outer { inner: Inner }` / `Inner { ticket: own<ticket> }`、4-byte/alignment-4 outer record、语义路径 `inner.ticket` flattened 到 offset `0` 的 `i32`、capacity `1`、source `(i32) -> (i32)`、seed `111`。ownership mask 为 `guest=1 transferred=2`，完整写入前 nested cleanup exactly once，成功转移后 host exactly once；十模式 valid/invalid cleanup 均闭环，valid 为 `1/1` drops、repeat 为 `2/2` 且观察 `[111,111]`，取消/早退各有一次 cancel 与 pending-future drop，invalid 不创建资源，所有模式 `table-empty=true`。该固定 route 不计入 ARC/GC 语义矩阵或 inventory row，不开放 public ownership syntax、generic/arbitrary producer、borrowed/list/variant payload 或 general async/resource lowering。
- G6.2 general producer/resource internal contract consolidation 已通过：不可变 `ProducerContract` 及 `SourceContract`、`SinkContract`、`PayloadLayout`、`OwnershipTransferPlan`、`TerminalContract` 统一了已测量的 source/sink、payload layout、ownership path、transfer commit 和 terminal cleanup facts；九条既有 private route（direct record、fixed pair、parameterized pair、triple、nested、list-resource、dynamic-list、batched-list、scalar-list）均由 route-specific adapter 重放，既有 WAT/WIT/template/hash/marker 保持不变。consolidated gate 覆盖 9 routes、5 canonical/generated parity、9 lifecycle groups；valid/invalid cleanup、cancel、pending future 与 `table-empty=true` 保持既有计数。四条负例在 WAT 前拒绝，未开放 public `own<T>`/`borrow<T>`/`ref<T>`、arbitrary producer expression、generic producer、borrowed async payload 或 unmeasured list/variant/mixed-resource shape；该内部整理不新增 GC inventory row。
- 精确同步 manifest-backed `map<u32,u32>` lower/lift route 已通过：两个
  hash-pinned WIT world、pair-list measured layout、`HashMap<u32,u32>`
  host-boundary admission、Do/Rust/Wasmtime fixtures、负例签名漂移和 Zig
  harness gate 均通过；lower/lift 各一次 host call 与一次 allocation/free。
  该固定 shape 不开放通用 map、async 参数 copy、Stream 跨 poll buffer 或
  其他 map key/value 组合。
- 精确 async `map<u32,u32>` capability probe 已通过：固定 WIT
  `async func(values: map<u32, u32>) -> u32`、Core `(i32 ptr, i32 len, i32 result_area) -> i32`
  观察形状、host Future 前输入复制、canonical WAT 输入覆盖，以及
  `ready/pending/cancel/drop` 的 exactly-once frame/future cleanup 和空
  `ResourceTable` 均有独立证据。该 probe 不开放通用 async map lowering、Stream
  跨 poll buffer、ownership syntax 或 GC inventory row；设计见
  `doc/superpowers/specs/2026-09-05-async-map-capability-design.md`。
- D2 `descriptor.sync` 的私有记录固定 upstream WIT hash
  `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`、regular/
  cancel mirror hashes `18ce7dc9efb991cd8e5f945797aea73edeed79f0cfc51ea664cb81537e54e719` /
  `9898cd734708a2ab14760da706d69063e5cd6262a5e03d07d8eedd8074745f36`，ABI
  `(i32,i32)->i32`、fixtures `462`–`465` 与 ready/pending/error/cancel cleanup
  矩阵；完整证据见 `doc/host_abi_blockers.md`。
- D2 `descriptor.stat` 的私有记录固定 upstream WIT hash
  `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`、regular/
  cancel mirror hashes `4f5ee39cad9280cdcd308550978ba0006503f5952d61304fc5130a74df5ea121` /
  `caf50d3fb78cca697ed05cbe02aa86794359ba1e8d576ba5156857d2ffb5af28`，ABI
  `(i32,i32)->i32`、record task-return layout and fixtures `498`–`510`; the
  opt-in compiler gate, generated regular Component, and Rust/Wasmtime matrix
  are green. Cancel and Store-disposal early-drop remain hand-authored oracle
  rows because the admitted Do source has no cancel export; generic filesystem
  async and host-future-drop cancellation remain pending.
- D2 `descriptor.sync-data` 的私有记录固定 upstream WIT hash
  `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`、regular/
  cancel probe WIT mirror hashes `ffc10164efb9a457637d56df111bb92844eef7b3258fec5dfb075b8e68dff8bb` /
  `2107a6283e8ae2b6f2cea296d91269c65d543456e39376ef4e70b0b69fd974e3`，ABI
  `(i32,i32)->i32`、unit/error-code Result、fixtures `511`–`515` 与
  ready/pending/error/cancel/repeat/Store-disposal early-drop cleanup matrix
  均通过；generic filesystem async and host-future-drop cancellation remain pending.
- D2 `descriptor.metadata-hash` 的私有记录固定 upstream WIT hash
  `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`、regular/
  cancel probe WIT mirror hashes `6976359b3a4813d6771b3ef9a7fdcfb2ee9323e70c33b9ac7d6b628519fecfed` /
  `b6e98cf2ae6f76e105f53c7ea09666b1c5684d33edb9838d034862a27b09f5c3`，ABI
  `(i32,i32)->i32`、`(i32,i64,i64)` task-return、`metadata-hash-value` 两个
  `u64` 字段、fixtures `516`-`519` 与 ready/pending/error/repeat/hand-authored
  cancel/Store-disposal early-drop oracle matrix 均通过；`descriptor.metadata-hash-at`
  另以 `(i32,i32,i32,i32,i32)->i32`、UTF-8 path-copy、fixtures `520`-`529` 与
  generated Component/Rust/Wasmtime ready/pending/error/cancel/early-drop/repeat
  gate 闭环；generic filesystem async and host-future-drop cancellation remain
  pending.
- D2 `descriptor.stat-at` 的私有记录固定 upstream WIT hash
  `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`、regular/
  cancel mirror hashes `92afa427efedc960fd60ce2edbd3ced26521225ae8857377554956646a1059bd` /
  `420fb95fae7505e568414e55f19dc2f89f5b32e015e8d999166e38b48e4a4a49`，ABI
  `(i32,i32,i32,i32,i32)->i32`、task-return
  `(i32,i32,i64,i64,i32,i64,i32,i32,i64,i32,i32,i64,i32)`、fixtures `530`-`539`；
  generated Component/Rust/Wasmtime ready/pending/error/repeat/cancel/early-drop
  path-copy and `symlink-follow` propagation matrix 均通过；两页 Core memory
  仅用于容纳 UTF-8 path allocation，generic filesystem async and host-future-drop
  cancellation remain pending.
- D2 `descriptor.open-at` 的私有记录固定 upstream WIT hash
  `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`、regular/
  cancel mirror hashes `1e5f9131387015c4e650a64e02bb9f112d8266f4755aa6b605af038407ef807a` /
  `1c48fba03b569d91617efd834232fcccc553ca3001ffb0e0834b4134f93e4f52`，ABI
  `(i32,i32)->i32`、六词参数块、`(i32,i32)` task-return、fixtures `540`-`551`；
  generated Component/Rust/Wasmtime ready/pending/error/repeat/cancel/early-drop
  path-copy and exactly-once parent/child cleanup matrix 均通过；取消只清理状态,
  不回滚已发出的 host open, generic filesystem async and host-future-drop
  cancellation remain pending.
- D2 `descriptor.set-size` 的私有记录固定 upstream WIT hash
  `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`、regular/
  cancel mirror hashes `f09241f8fcf4b94e1a684553b439b592f254c83c7d23a3708930040a2324c3f4` /
  `7030161e35a18fe40220cb2701864141a00a6c8d897cdfc8291839f2b742cc67`，ABI
  `(i32,i64,i32)->i32`、`(i32,i32)` task-return、fixtures `552`-`563`；
  generated Component/Rust/Wasmtime ready/pending/error/cancel/early-drop/repeat
  mutation and exactly-once cleanup matrix 均通过；取消只清理状态, 不回滚已发出的
  host file-size mutation, generic filesystem async and host-future-drop cancellation
  remain pending.
- Colorless async / WIT bindgen 已形成有界可验证切片：`do wit check/bind`、生成 manifest 漂移校验、`@async/@await/@cancel` 前端契约、descriptor-backed generic/scalar、私有 root-owned local-frame async-call Component（unit inline 与单 `u32` inline scalar）、私有 `--p3-async-host-arg-component` scalar-argument compiler promotion、以及私有 `Future<Ticket>` -> `future<own<ticket>>` Component runtime 的 pending/ready/cancel gates 均通过；general async-call promotion contract 与 D2 filesystem/HTTP method recovery design 已冻结，但没有 compiler widening；自动 manifest-to-lowering 的通用化与任意 payload/Stream/resource lowering 仍是 pending。

当前禁止默认推进:

- 不重开 get / pkg / push。
- 不去掉内部函数 `@` 前缀。
- 不默认推进 direct wasm binary emitter。
- 不默认推进完整 WASI / Component Model (未决部分在 G6)。
- 不大规模重写 parser / sema / codegen; 必须先拆成可回归小任务。
- 不把 `codegen_ir` 在未独立立项前扩成主 emit 路径。

## 1. 推进协议

1. 每次只推进一个可验证小任务。
2. 完成后更新 `doc/start_here.md` 停点/基线, 必要时写 `CHANGELOG.md`。
3. 语法或语义变化同步 `doc/spec_rules.md`、`doc/grammar.peg`、相关 `doc/syntax/*.md` 与回归。
4. 工具行为变化同步 `README.md`、`src/build/test/README.md` 与黑盒 fixture。
5. 文档只保留当前有效入口; 不保留过期草案与空占位目录。

## 2. 阶段结论 (仅状态)

| 阶段 | 状态 |
| --- | --- |
| A 工具链 | done |
| B 语法/语义冻结 | done |
| C 标准库收口 | done |
| D ARC / ownership | done (可推进项) |
| E 后端 IR / codegen | done |
| F LSP | done (v1 无 rename) |
| GC-first runtime cutover | **done** (Task 6); normal compiler route is GC-only, ARC is explicit test-only oracle |
| G WASI / Component | G1–G5、G6.1、G6.2 bounded read-directory slice + generic record-stream consumer + multi-owned/multiple-path/one-/two-/three-/four-/five-/six-level nested-owned resource consumer + bounded scalar producer + scalar-argument async-call + inline scalar-argument async-call + **private async host scalar-argument compiler promotion** + helper-mediated lease（含六跳 forwarding）+ fixed/parameterized `u64` countdown producer + parameterized forwarding-helper（含 typed-parameter reorder）+ branch-selected terminal checkpoints + private resource Result error/cancellation + pinned HTTP payload cancellation + private variant-resource-stream checkpoint + record-layout/source-mirror checkpoints + bounded root-owned local-frame async-call slice + private owned-future compiler slice + private bounded scalar `stream<list<u32>>` producer promotion + **private direct owned-record `stream<resource-entry>` producer lifecycle checkpoint** + **private bounded two-owned-field `stream<resource-pair>` producer lifecycle checkpoint** + **private parameterized two-owned-field `stream<resource-pair>` producer lifecycle checkpoint** + **private fixed three-owned-field `ResourceTriple` compiler admission** + private D2 `descriptor.get-type`/`descriptor.sync`/`descriptor.get-flags`/`descriptor.stat`/`descriptor.sync-data`/`descriptor.metadata-hash`/`descriptor.metadata-hash-at`/`descriptor.stat-at`/`descriptor.open-at` slices、G6.3、G6.4 done; G6.2 general producer/resource extensions and general async/D2 methods pending |
| D2 `descriptor.set-size` | private bounded `(i32,i64,i32)->i32` async method slice closed; fixture `552` and generated Component/Rust/Wasmtime mutation/cancellation matrix green; general filesystem async remains pending |
| H 发布前治理 | done |
| I 语言扩展 | **closed** (I1 递归/TCO + I2 Tuple 第一版) |
| Colorless async / WIT bindgen | bounded unit/scalar runtime-manifest contracts, opt-in root-owned local-frame async-call contract including one inline `u32` scalar argument, private `--p3-async-host-arg-component` scalar-argument compiler promotion, and private `Future<Ticket>` -> `future<own<ticket>>` compiler contract verified; automatic manifest-to-lowering generalization and unrestricted generic async lowering pending |

## 3. 当前阻断与待处理

权威清单: **`doc/pending_blocked.md`** (G6 后续 producer/resource gates、语言 pending P2、deferred 非目标、skip)。

I2 已收窄: managed/`text` 叶子、pure-scalar struct 嵌套子槽、以及含 managed 字段的 struct 句柄槽 storage 已落地 (`compile_ok/273`, `ok/193`)。

## 4. 当前下一步

用户说 `go` / `next` 时 (细节见 `doc/pending_blocked.md` §6 与 `doc/start_here.md` §6):

1. 发布候选维护与文档基线已复核通过（显式项目缓存路径下）；后续只处理新出现的真实发布阻断或文档漂移。
2. G5c 的 15-row inventory 与 residual matrix 已重新逐行核验；当前仍为 `complete_rows=15 pending_rows=15`，唯一固定 candidate 已完成专用闭环，14 行保持 blocked。
3. 当前没有第二个满足 admission contract 的同步 exact candidate；不扩大通用 aggregate/list、任意 producer、async/resource 或 ownership，也不从邻近 descriptor 推断通用能力。
4. G6.2 direct、static two-owned-field、parameterized two-owned-field record producer 与固定三字段 `ResourceTriple` private compiler admission 的独立 lifecycle/design gates 均已闭环；当前没有第二个满足 admission contract 的同步 exact candidate。后续如需新的 producer/resource shape，仍须另立 design、manifest/hash/ABI、source matcher、negative fixtures、Component parity 和 Rust/Wasmtime cleanup gate；不得直接扩大 default route。
5. D2 通用 filesystem async/external HTTP 与 deferred codegen/ownership/JSON/LSP 继续保持明确阻断或单独授权，不与本阶段混合。

验收命令:

```bash
cd src && zig test main.zig
./src/build/test/run_tests.sh
./src/build/test/run_release_smoke.sh   # 发布前
```
