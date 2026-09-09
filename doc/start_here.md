# 下次启动入口

这是当前主线的接手入口。状态以本文为准; 计划摘要见 `doc/master_plan.md`; 近期变更见 `CHANGELOG.md`。不保留向后兼容旧路径或历史流水账。

当前基线日期: `2026-09-10`。

## 1. 阅读顺序

1. [README.md](../README.md) — 能力摘要、非目标、下一阶段计划
2. [CHANGELOG.md](../CHANGELOG.md) — 近期已完成变更
3. [doc/pending_blocked.md](pending_blocked.md) — **待处理与阻断** (G6 / P2 / deferred / skip)
4. [doc/master_plan.md](master_plan.md) — 当前规划摘要
5. [doc/roadmap_status.md](roadmap_status.md) — 当前执行状态
6. [doc/memory.md](memory.md) — GC-first 运行时目标与迁移边界 (按需)

模块地图见仓库根 [AGENTS.md](../AGENTS.md)。

**目录约定 (2026-07-12 起)**:

| 路径 | 含义 |
| --- | --- |
| `lib/` | 标准库与 builtin/core 总表 (`lib/_.do`); `@lib("file.do")` 解析根 |
| `src/` | 工具链与编译器 (原 `tool/`); `cd src && zig build` |
| `src/wit/` | 生产 WIT lexer/parser/resolver/emitter；`do wit check/bind` 实现 |
| `src/build/test/` | 回归 harness 与 fixture |
| `src/build/test/lib/` | fixture 专用 `~/` 依赖根 (`DO_LIB_ROOT`), 不是公开标准库 |
| `wit/` | 当前项目生成的 `*.do` binding、`manifest.json`、`wit.lock`；源文件可放 `wit/src/` |
| `.deps/wit-bindgen/` | 忽略的 `wit-bindgen v0.60.0` 固定 checkout，只用于 Go/Rust 差分 |

## 2. 当前停点

| 项 | 状态 |
| --- | --- |
| v1 子集 | 发布候选已收口 |
| GC-first runtime cutover | Task 6 已闭环；普通 `do build`/`do test` 只走 `codegen_runtime_api.zig` 的 Wasm GC route，ARC 仅由显式 test-only `gc_arc_equivalence_oracle.zig` 调用；ARC inventory `rows=49 matches=480 unclassified=0 normal_route_matches=0`，生产依赖闭包 `modules=153 forbidden=0` |
| 当前验证基线 | 默认及 `RUN_WASM=1 RUN_GC_CORE=1` 为 `14/14 steps; 53/53 tests`；`zig test main.zig` 为 `1568/1568`；GC default gate `87 fixtures`、semantic-equivalence `26 rows; 0 pending`、ReleaseSmall/release smoke 通过 |
| 当前能力边界 | `complete_rows=15 pending_rows=15` 仍为能力缺口；通用 async/map/producer/resource lowering 与 public `own<T>`/`borrow<T>`/`ref<T>` syntax 继续 pending，未准入形状在 WAT 前 fail-closed |
| Private async map compiler admission | 精确 `HashMap<u32,u32>` async host route 已由 `--p3-async-map-component` 准入；WIT/WAT snapshot、五个 WAT 前负例、Component validate 与 Rust/Wasmtime `ready/pending/cancel/drop` 均通过；默认 route 仍返回 `AsyncLoweringUnavailable`，通用 async map、Stream 跨 poll buffer 与 ownership syntax 继续 pending |
| GC-first memory migration | G5a 已完成 parsed fixed-index + 参数化 `[u8] @set` + 全部当前标量 list literal/update（`[bool]`、`[i8]`、`[i16]`、`[i32]`、`[i64]`、`[u16]`、`[u32]`、`[u64]`、`[isize]`、`[usize]`、`[f32]`、`[f64]`）+ bounded text/list/struct/tuple/union/generic/import slices、直接局部对象的一层、两层、三层、四层与五层 nested managed-struct `@get/@set`，以及 `--p3-wait-for-component` 的 bounded `Future<nil>` GC frame/table slice 和 private resource `Result` terminal Component gate；G5b 已完成当前 admitted synchronous 的 26 行 ARC/GC executable equivalence matrix，`future_stream_frames` 的两个 sequential `Future<nil>` 也已完成 GC/linear backend-neutral equivalence，non-CLI probes 验证旧值保持、新值更新和 root 保活。Task 3 已将默认同步 pipeline 的已准入 managed candidates（含 bounded synchronous `defer`、`return nil` no-result cleanup、推断出的 `text` body binding、推断出的 `[u8]`/`[u32]` body storage `@put`，以及 body-only managed-struct storage ctor/field update）接到 typed GC/root 输出，GC path 过滤旧 storage compiler locals；普通 host/WIT 的 C14 lift/lower、C15-B/C15-D lower、C16-C/C16-D lift、bounded mixed scalar-record lower、bounded byte-list record lower/lift、bounded `list<u32>` record lower 与 bounded `list<u32>` record lift、bounded mixed text/u32-list record lower/lift 已接入 manifest-backed 默认 GC route，未准入的 host/WIT shape、普通 GC sync async 和 Stream 在 WAT 前 fail-closed；root/storage conversion、generic async/resource G5b/G5c、G5c full cutover 与旧 ARC expectation 迁移未完成。新增 C10–C16-B 私有 manifest-backed nested/scalar-plus-text/multi-managed-text record lift/lower 与真实 source-level host boundary 证据，其中固定 descriptor 的默认 gate 已闭合。 |
| G5c route consolidation | C14–C20 已统一消费一次 manifest-backed `LoadedRequest`、descriptor registry 与 measured `SyncValuePlan`；default/explicit route 不重复解析 request，已登记 locator 的 member drift 在 WAT 前 fail-closed。新鲜 focused route/residual gate、Zig harness `14/14 steps; 53/53 tests`、default `87 fixtures`、semantic-equivalence `26 rows; 0 pending`、ReleaseSmall/release smoke 已通过；`RUN_WASM=1` 与 `RUN_GC_CORE=1` wrapper 回归均为 `14/14 steps; 53/53 tests`；inventory 仍为 `complete_rows=15 pending_rows=15`、exit 1。 |
| G5c bounded mixed text + two `list<u32>` lower | 精确 descriptor `demo:marshal-record-mixed-text-two-u32-lists-lower/api.write@1.0.0/lower` 已通过默认 route、Component/Rust/Wasmtime、negative 与 ARC/GC equivalence；root 28 bytes、canonical 七个 `i32`、三 span `second -> first -> label` exactly-once cleanup，host 观察 `allocations=3/frees=3`、`write-calls=1`。这是固定形状 promotion，不关闭 migration row。 |
| G5c bounded mixed text + two `list<u32>` lift | 精确 descriptor `demo:marshal-record-mixed-text-two-u32-lists-lift/api.read@1.0.0/lift` 已通过默认 route、Component/Rust/Wasmtime、negative 与 ARC/GC equivalence；result area 28 bytes、canonical 单个 `(i32)` pointer、三 span `second -> first -> label` exactly-once cleanup，host 观察 `result=54`、`stats=51`、`read-calls=1`、`allocations=3/frees=3`，equivalence 为 `54/54`、`51/51`、`1/1`。这是固定形状 promotion，不关闭 migration row。 |
| G5c residual capability matrix | 15 个 residual row 已逐行复核且仍全部 pending；14 行 blocked，唯一 candidate 为 `demo:marshal-record-mixed-text-byte-u32-lists-lower/api.write@1.0.0/lower`。该候选只接受同步、manifest-backed、ABI 可测量且 canonical ABI 无 GC reference 的固定 shape，已完成 spec/host/equivalence/negative/default/full verification；release-candidate maintenance、G6.2 双 owned-field producer gate 与固定三字段 `ResourceTriple` private compiler admission 已完成，不扩大默认 route。 |
| G6.2 private nested-owned-record producer | 精确 descriptor `do:g6-2-owned-record-nested-producer@0.1.0` / `consume-via-stream` 仅准入 `Outer { inner: Inner }`、`Inner { ticket: own<Ticket> }`；WIT hash 为 `9662440709b01044544d4c4350f3e6f783a8f06aaa5c884a96a1e43a935a7543`，outer 为 4 bytes/alignment 4，语义路径 `inner.ticket` 在 offset `0` flattened 为 `i32`，capacity `1`，source `(i32) -> (i32)`，seed `111`。ownership mask `guest=1 transferred=2` 保证 nested leaf exactly-once cleanup；21 个负例 (`725`–`745`)、Do/Component、Rust/Wasmtime 十模式和 canonical/generated parity 通过，取消/早退为一次 cancel + pending-future drop 且 zero completion，repeat 为 `[111,111]`，所有模式 `table-empty=true`。这是 private fixed-shape Component/compiler evidence，不开放 public `own<T>`/`borrow<T>`/`ref<T>`、generic/arbitrary producer、general async/resource，也不新增 GC inventory row；inventory 仍 `complete_rows=15 pending_rows=15`、exit `1`。 |
| G6.2 producer contract consolidation | 2026-09-04 已闭环内部 immutable `ProducerContract`；统一 measured source/sink、payload layout、ownership path、transfer commit 和 terminal cleanup，重放 direct/fixed-pair/parameterized-pair/triple/nested/list-resource/dynamic-list/batched-list/scalar-list 九条 private route。consolidated gate 为 `routes=9 canonical-parity=5 lifecycle=9 table-empty=true`，四条负例在 WAT 前拒绝；WAT/WIT/template/hash/marker 与既有 lifecycle counters 不变。仅是内部复用，不开放 public ownership、generic/arbitrary producer、borrowed/list/variant async payload 或 unmeasured shape。 |
| G5c mixed text + byte/u32-list lower candidate | `Writing { code: u32, label: text, bytes: [u8], values: [u32] }`；root 28 bytes、字段偏移 `0/4/12/20`、canonical 七个 `i32`、三 span `values -> bytes -> label` exactly-once cleanup。host 观察 `allocations=3/frees=3`、`write-calls=1`，ARC/GC 为 `3/3`、`1/1`；7 个 drift case 在 WAT 前拒绝。仍是固定形状 promotion，不关闭 migration row。 |
| GC-first scalar-leaf default route | `examples/gc-p3-runtime/scalar-leaf.do` 的纯同步 `u32` identity/arithmetic 已接入默认 typed GC route；递归、loop、defer、host/WIT、managed、async/resource 形状保持 fallback/fail-closed。独立 gate、当时的 84-fixture slice checkpoint 和 focused negative tests 已验证；当前总基线为 86 fixtures；该 slice 不关闭 migration row 或 full G5c cutover。 |
| GC-first scalar control-flow default route | `examples/gc-p3-runtime/scalar-control-flow.do` 的纯同步 scalar `if/else`、`else-if` 与 guard-return 已接入默认 typed GC route，WAT 具备 `branch_join`/`guard_join` 且无 `__arc_`；loop、`defer`、递归、导入模块、host/WIT、managed、async/resource 与任意 producer expression 继续 fallback/fail-closed。该 slice 使用当时的 84-fixture checkpoint（当前总基线为 86 fixtures），不改变语法，不关闭 migration row 或 full G5c cutover。 |
| GC-first scalar call-graph boundary | `examples/gc-p3-runtime/scalar-call-graph.do` 的同模块、同步、无环 scalar helper calls 已接入默认 typed GC route；self/mutual/longer recursion 在 WAT 前 fail-closed。独立 gate、`130/130` scalar focused tests 和当时的 84-fixture slice checkpoint（当前总基线为 86 fixtures）已验证；imported graph、host/WIT、managed、async/resource 与任意 producer expression 仍不准入。 |
| GC-first latest bounded producer slice | `nested-byte-list-put.do` 与 `managed-struct-list.do` 分别覆盖精确的 `[[u8]]`、`[Box]` 单值 `@put` producer；`nested-field-path.do`、`two-level-nested-field-path.do`、`three-level-nested-field-path.do`、`four-level-nested-field-path.do` 与 `five-level-nested-field-path.do` 覆盖一层、两层、三层、四层和五层 nested managed-struct scalar field update，并加入第 26 行 ARC/GC 等价矩阵；C10–C14 覆盖 manifest-backed 二层、三层和四层纯标量 record 的 lift/lower，C15-A/B/D 覆盖 `scalar + text` 与 multi-managed-text record 的 lift/lower Component host/equivalence，C15-C/C16-C 覆盖 compiler wiring，C15-B/C15-D/C16-C/C16-D 与 mixed scalar-record lower、bounded byte-list record lower/lift、bounded `list<u32>` record lower/lift 已有普通默认 route gate；C15-B/D 的 lower 固定 ABI 分别为 `(i32, i32, i32)` 和 `(i32, i32, i32, i32, i32)`，并验证调用后释放临时线性内存；2026-08-23 C19 固定 byte-list record lift 使用 12-byte result area、capacity `3`、accepted lengths `0..3`、`$do_bytes` 和 exactly-once linear cleanup，host/equivalence/negative 三个 phase 已纳入 G5c residual gate；`future_stream_frames` 的 bounded G5b 等价已闭合，resource `Result` terminal gate 仍仅闭合 Component 边界证据，通用 nested/managed producer、spread/multi-value、text/list record lower、generic async/resource G5b/G5c 和 G5c 仍未完成。 |
| 阶段 A–F、H | 已完成 |
| 阶段 D | 可推进项已完成; D2.1 已按 B 方案绿色 regression 收口; D2 本地 file/dir/CLI/socket smoke 与私有 `descriptor.get-type`/`descriptor.sync`/`descriptor.get-flags`/`descriptor.stat`/`descriptor.sync-data`/`descriptor.metadata-hash`/`descriptor.metadata-hash-at`/`descriptor.stat-at`/`descriptor.open-at`/`descriptor.set-size` async slices 已验证；通用 filesystem async、external HTTP 的 method-specific recovery 仍阻断 |
| 阶段 G | G1–G5、G6.1、G6.2 有界 read-directory slice + generic consumer + multi-owned-resource + 一层/两层/三层/四层/五层/六层 nested-owned-resource + multiple nested-owned-resource paths + bounded scalar producer + bounded/parameterized `u64` countdown producer + parameterized helper（含六跳 forwarding 与 typed 参数重排）producer + helper-mediated lease + branch-selected terminal + private resource Result error/cancellation checkpoints + path-sensitive `StreamWriter<T>` lease semantic foundation + record-layout/source-mirror lowering/runtime checkpoints + bounded root-owned local-frame async-call slice + scalar-argument async-call slice + **private bounded async host scalar-argument compiler promotion** + private owned-future compiler slice + private closed/dynamic-count/batched C-min list/resource producer slices + **private bounded scalar `stream<list<u32>>` producer promotion** + **private direct/two-field/parameterized two-field owned-record producer lifecycle checkpoints** + **private fixed three-owned-field `ResourceTriple` compiler admission** + **private mixed scalar/owned `MixedEntry` producer compiler admission** + D2 私有 filesystem `descriptor.get-type`/`descriptor.sync`/`descriptor.get-flags`/`descriptor.stat`/`descriptor.sync-data`/`descriptor.metadata-hash`/`descriptor.metadata-hash-at`/`descriptor.stat-at`/`descriptor.open-at`/`descriptor.set-size` slices、G6.3、G6.4 完成；generic list/producer、borrowed payload、general async-call、D2 general methods 与 root hard-cancel pending |
| G6.2 parameterized six-hop forwarding | 现有 `StreamWriter<u8>` descriptor 的参数化 helper 链已准入六个静态 forwarding edge；正例 Component、七跳负例、Rust/Wasmtime `count=0/1/3`、`value=90`、pending/ready/error/early-drop/cancel 均通过，保持一次 callback、一次 stream drop、空 `ResourceTable` 与 exactly-once cleanup；任意 producer、七跳、borrowed/list/variant 与通用 resource 仍拒绝 |
| G6.2 direct owned-record producer | 私有 descriptor `do:g6-2-owned-record-producer@0.1.0` 仅准入 `StreamWriter<ResourceEntry>`；`ResourceEntry` 为 4 bytes，`ticket: own<Ticket>` 位于 offset `0`，stream capacity `1`，WIT hash 为 `6c1406962ee4c4e3eec5b3b4a866acfd1d8eb6ee159ce5b4077df113063d1ace`。canonical/generated Component 与 Rust/Wasmtime 十模式（ready/pending、传输前后 error/cancel/early-drop、repeat、invalid）通过；valid row exactly-once ticket/stream/future cleanup、空 `ResourceTable`，repeat 为 `2/2`。这是独立 Component 生命周期等价证据，不计入 ARC/GC 26-row 矩阵；通用 producer、borrowed/list/variant 与公开 ownership syntax 仍拒绝 |
| G6.2 two-owned-field record producer | 私有 descriptor `do:g6-2-owned-record-pair-producer@0.1.0` 仅准入 `StreamWriter<ResourcePair>`；`ResourcePair` 为 8 bytes，`left/right: own<Ticket>` 位于 offset `0/4`，stream capacity `1`，WIT hash 为 `89345a5213936735d7f065cd54ed42b83d159b80305a1a900ae00df2e811704d`。presence mask 在完整 record 写入成功后原子转移两个 handle，转移前按 `right -> left` 释放，转移后 host 各释放一次。canonical/generated Component、negative admission 与 Rust/Wasmtime 十模式通过；valid row 为 `2/2` ticket cleanup、repeat 为 `4/4`，所有模式 `table-empty=true`，invalid 不创建资源；ABI 还固定观测 `callback-calls`、`poll-calls`、`finish-calls=0` 与取消模式的 `cancel-calls=1`/pending-future-drop。这是独立 Component 生命周期等价证据，不计入 ARC/GC 26-row 矩阵；generic producer、arbitrary expression、borrowed/list/variant、general async/resource 与公开 ownership syntax 仍拒绝 |
| G6.2 parameterized two-owned-field record producer | 私有 descriptor `do:g6-2-owned-record-pair-parameterized-producer@0.1.0` 仅准入 `StreamWriter<ResourcePair>`；WIT hash 为 `e7abd3cf7b7543325865a0b4be4b32ae50a2470ac5083169250719f89b7ce53a`，record 为 8 bytes，`left/right: own<Ticket>` 位于 offset `0/4`，stream capacity `1`，producer inputs 为 `(mode,left-seed,right-seed)` 三个 `u32` words。presence mask 在完整 record 写入成功后原子转移两个 handle，转移前按 `right -> left` 释放，转移后 host 各释放一次。canonical/generated Component、十个 fail-closed negative fixtures 与 Rust/Wasmtime 十模式通过；valid row 为 `2/2` ticket cleanup、repeat 为 `4/4`，所有模式 `table-empty=true`，invalid 不创建资源；`pending` 为两次 stream poll，转移前取消/早退为零次，转移后为一次，所有模式 `finish-calls=0`。这是独立 Component 生命周期等价证据，不计入 ARC/GC 26-row 矩阵；generic producer、arbitrary expression、borrowed/list/variant、general async/resource 与公开 ownership syntax 仍拒绝 |
| G6.2 fixed three-owned-field record producer admission | 私有 compiler route `do:g6-2-owned-record-triple-producer@0.1.0` 仅在 `--p3-async-component` 下准入；WIT hash 为 `73fd57dc8f34f13023b48f2b82e439b212eab52192886f0d07a37d86e63658b1`。`ResourceTriple` 为 12 bytes、alignment 4，`left/middle/right: own<Ticket>` 位于 offset `0/4/8`，stream capacity `1`，输入为 `(mode,left-seed,middle-seed,right-seed)` 四个 `u32` words。manifest/source matcher、13 个负例 `712`–`724`、生成 WAT/WIT、Component validate、Rust/Wasmtime lifecycle 与 canonical/generated parity 全部通过；valid 为 `3/3` ticket cleanup、repeat 为 `6/6`，四种取消/早退各有一次 cancel 与 pending-future drop，invalid 不创建资源，所有模式 `table-empty=true`。该固定 route 不计入 ARC/GC 26-row 矩阵，不开放 generic/arbitrary producer、borrowed/list/variant payload、general async/resource 或公开 `own<T>`/`borrow<T>`/`ref<T>` syntax。 |
| G6.2 mixed scalar/owned record producer admission | 私有 compiler route `do:g6-2-owned-record-mixed-producer@0.1.0` 仅在 `--p3-async-component` 下准入；WIT hash 为 `5fe1c2ed6a0c348bf6f0e96596afc419bbbd379345421f02fa36f05aa472d9ed`。`MixedEntry { code: u32, ticket: own<Ticket> }` 为 8 bytes、alignment 4，字段 offset `0/4`，stream capacity `1`，source `(i32) -> (i32)`，ticket seed `111`。manifest/source matcher、9 个负例 `762`–`770`、生成 WAT/WIT、Component validate、Rust/Wasmtime 十模式 lifecycle 与 canonical/generated parity 全部通过；scalar `code` 不进入 ownership mask，完整写入后才 transfer，valid 为 `1/1` ticket cleanup、repeat 为 `2/2`，invalid 不创建资源，所有模式 `table-empty=true`。该固定 route 不计入 ARC/GC 26-row 矩阵或 inventory row，不开放 generic/arbitrary producer、borrowed/list/variant payload、general async/resource 或公开 `own<T>`/`borrow<T>`/`ref<T>` syntax。 |
| Colorless async / WIT bindgen | canonical `@async/@await/@cancel`、legacy `async` 弃用、schema 1/2 生成 manifest 校验、已准入 schema 2 unit 与 scalar capabilities 的 manifest 自动发现，以及 opt-in v2 variant/scalar-i64 gates、统一 promotion profile、`--p3-async-call-component` root-owned local-frame gate、private `--p3-async-host-arg-component` scalar-argument compiler gate 和 `--p3-owned-future-component` `Future<Ticket>` -> `future<own<ticket>>` gate 已验证；general async-call promotion contract 与 D2 recovery design 已冻结，unrestricted generated WIT lowering 仍 pending |
| 阶段 I | **已关闭** (I1 递归/self-tail TCO + I2 `Tuple<...>` 第一版) |
| 架构审查/重构 | 五轮已落地 (见 §4); 默认不继续拆 god module |
| active Component tooling | `wasm-tools 1.258.0 (5c6d31c78 2026-08-24)`; SHA-256 `282e0014d38daf233cb10fb92815813b339e2b7f8b4734f6698f0176c7d99424`; current-only adapter path is `bin/do-toolchain` |
| Toolchain adapter / Zig harness | Task 9 Step 1 active gate、Task 8 Step 3 Rust host adapter、Step 4/5 Shell-to-Zig parity 均已闭合；`run_tests.sh` 现在只是 `cd src && zig build test --summary all` 的薄入口，`RUN_WASM`/`RUN_GC_CORE` 由 Zig harness 继承处理 |
| WIT `map<K,V>` runtime | parser/model/manifest/registry 的 pair-list schema 已完成；精确同步 manifest-backed `map<u32,u32>` lower/lift Component route 已通过 Do/Rust/Wasmtime host gate（各一次 host call 与一次 allocation/free）；同步 operation-frame 顺序门禁已锁定 lower 的 copy-before-call/free-after-call 与 lift 的 copy/construct/publish-before-free；精确 async `map<u32,u32>` capability probe 与私有 `--p3-async-map-component` compiler route 均已通过，固定 `(ptr,len,result_area)` Core 形状、WAT/WIT snapshot、五个 WAT 前负例和 `ready/pending/cancel/drop` lifecycle；`wit_abi_types` 与 bounded Core WAT probe 已覆盖 `u32` key + `u32`/`text` value 的 lower/lift 并通过 current toolchain parse/validate；通用 Component/WIT map lowering、其他 key/value 组合、Stream 跨 poll owned buffer 与统一 cleanup authority 仍阻断，未支持 shape 继续 fail-closed |

上表中的历史 GC migration 行保留能力切片的审计描述；Task 6 已经单独关闭
backend cutover。当前普通编译不再使用 ARC fallback，ARC 只通过显式 test-only
equivalence oracle 运行；`complete_rows=15 pending_rows=15` 仍表示未实现能力，
不是 cutover 状态。

## 3. 验证入口

接手或改编译器后, 优先跑这三条; 细节证据记在 `doc/roadmap_status.md`。

```bash
# WIT binding checker / generator
./bin/do wit check examples/wit-bindgen-do/async-world.wit --world probe
./bin/do wit bind examples/wit-bindgen-do/async-world.wit \
  --world probe --out examples/wit-bindgen-do/project/wit
./bin/do wit check examples/wit-bindgen-do/async-world.wit --world probe \
  --manifest examples/wit-bindgen-do/project/wit/manifest.json

# generated schema 2 unit-async Component/Rust/Wasmtime gate
bash examples/wit-bindgen-do/test_generated_async_lowering.sh

# generic ABI v2 independent scalar-i64 gate (opt-in; default remains v1)
bash examples/wit-bindgen-do/test_generic_abi_v2_scalar_i64.sh

# generic ABI v2 promotion profile (two verified private shapes; v1 remains default)
bash examples/p3-runtime/test_generic_abi_v2_promotion.sh

# bounded user-function async-call Component gate
bash examples/p3-runtime/test_do_async_call_component.sh
# Rust/Wasmtime matrix: pass the component produced by the Do gate
bash examples/p3-runtime/test_rust_async_call_component.sh <component.wasm>

# private Future<Ticket> -> future<own<ticket>> compiler Component gate
bash examples/p3-runtime/test_do_future_owned_component.sh

# private C-min stream<list<resource-entry>> producer compiler/runtime gate
bash examples/p3-runtime/test_rust_g6_2_c_min_list_resource_producer.sh

# private bounded dynamic-count producer compiler/runtime gate
bash examples/p3-runtime/test_rust_g6_2_c_min_dynamic_list_producer.sh

# private fixed two-batch list-resource producer compiler Component gate
bash examples/p3-runtime/test_do_g6_2_batched_list_resource_producer.sh

# private fixed two-batch list-resource producer Rust/Wasmtime gate
bash examples/p3-runtime/test_rust_g6_2_batched_list_resource_producer.sh

# private bounded scalar stream<list<u32>> producer Component/Rust/Wasmtime gate
bash examples/p3-runtime/test_do_g6_2_scalar_list_producer.sh
bash examples/p3-runtime/test_rust_g6_2_scalar_list_producer.sh

# private direct owned-record stream producer lifecycle gates
bash examples/p3-runtime/test_g6_2_owned_record_producer_abi.sh
bash examples/p3-runtime/test_do_g6_2_owned_record_producer.sh
bash examples/p3-runtime/test_rust_g6_2_owned_record_producer.sh
bash examples/p3-runtime/test_g6_2_owned_record_producer_equivalence.sh

# private bounded two-owned-field record producer lifecycle gates
bash examples/p3-runtime/test_g6_2_owned_record_pair_producer_abi.sh
bash examples/p3-runtime/test_do_g6_2_owned_record_pair_producer.sh
bash examples/p3-runtime/test_do_g6_2_owned_record_pair_producer_negative.sh
bash examples/p3-runtime/test_rust_g6_2_owned_record_pair_producer.sh
bash examples/p3-runtime/test_g6_2_owned_record_pair_producer_equivalence.sh

# private parameterized two-owned-field record producer lifecycle gates
bash examples/p3-runtime/test_g6_2_owned_record_pair_parameterized_producer_abi.sh
bash examples/p3-runtime/test_do_g6_2_owned_record_pair_parameterized_producer.sh
bash examples/p3-runtime/test_do_g6_2_owned_record_pair_parameterized_producer_negative.sh
bash examples/p3-runtime/test_rust_g6_2_owned_record_pair_parameterized_producer.sh
bash examples/p3-runtime/test_g6_2_owned_record_pair_parameterized_producer_equivalence.sh

# private D2 filesystem descriptor.get-type ABI and compiler/runtime gate
bash examples/p3-runtime/test_d2_wasi_filesystem_get_type_abi.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_get_type.sh

# private D2 filesystem descriptor.sync ABI and compiler/runtime gate
bash examples/p3-runtime/test_d2_wasi_filesystem_sync_abi.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_sync.sh

# private D2 filesystem descriptor.get-flags ABI and compiler/runtime gate
bash examples/p3-runtime/test_d2_wasi_filesystem_get_flags_abi.sh
bash examples/p3-runtime/test_do_wasi_filesystem_get_flags.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_get_flags.sh

# private D2 filesystem descriptor.stat ABI and compiler/runtime gate
bash examples/p3-runtime/test_d2_wasi_filesystem_stat_abi.sh
bash examples/p3-runtime/test_do_wasi_filesystem_stat.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_stat.sh

# private D2 filesystem descriptor.sync-data ABI and compiler/runtime gate
bash examples/p3-runtime/test_d2_wasi_filesystem_sync_data_abi.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_sync_data.sh

# private D2 filesystem descriptor.metadata-hash ABI and compiler/runtime gate
bash examples/p3-runtime/test_d2_wasi_filesystem_metadata_hash_abi.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_metadata_hash.sh

# private D2 filesystem descriptor.metadata-hash-at ABI and compiler/runtime gate
bash examples/p3-runtime/test_d2_wasi_filesystem_metadata_hash_at_abi.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_metadata_hash_at.sh

# private D2 filesystem descriptor.stat-at ABI and compiler/runtime gate
bash examples/p3-runtime/test_d2_wasi_filesystem_stat_at_abi.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_stat_at.sh

# private D2 filesystem descriptor.open-at ABI, compiler, and runtime gate
bash examples/p3-runtime/test_d2_wasi_filesystem_open_at_abi.sh
bash examples/p3-runtime/test_d2_wasi_filesystem_open_at_compiler.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_open_at.sh

# private D2 filesystem descriptor.set-size ABI, compiler, and runtime gate
bash examples/p3-runtime/test_d2_wasi_filesystem_set_size_abi.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_set_size.sh

# bounded async-call scalar-argument Component/Rust/Wasmtime gate
bash examples/p3-runtime/test_do_async_call_scalar_argument.sh
bash examples/p3-runtime/test_rust_async_call_scalar_argument.sh \
  /tmp/async-call-scalar-argument.component.wasm

# bounded inline scalar-argument async-call Component/Rust/Wasmtime gate
bash examples/p3-runtime/test_do_async_call_inline_scalar_argument.sh \
  /tmp/async-call-inline-scalar-argument.component.wasm
bash examples/p3-runtime/test_rust_async_call_component.sh \
  /tmp/async-call-inline-scalar-argument.component.wasm

# private async host scalar-argument compiler Component/Rust/Wasmtime gate
bash examples/p3-runtime/test_do_async_host_scalar_argument.sh
bash examples/p3-runtime/test_rust_async_host_scalar_argument.sh

# canonical async host scalar-argument ABI baseline (current assembly route)
PROBE_COMPONENT_OUT=/tmp/async-call-arg-probe.component.wasm \
  bash examples/p3-runtime/test_async_call_arg_probe.sh
runner_cc=examples/p3-runtime/rust-host-runner/zig-cc.sh
for mode in ready pending cancel; do
  CC="$runner_cc" CXX="$runner_cc" \
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="$runner_cc" \
    cargo run --quiet --locked \
    --manifest-path examples/p3-runtime/rust-host-runner/Cargo.toml \
    --bin do-p3-async-call-arg-probe-host-runner -- \
    /tmp/async-call-arg-probe.component.wasm "$mode"
done

# borrow capability refresh and scalar-list producer ABI probe
bash examples/p3-runtime/test_borrow_capability_matrix.sh
bash examples/p3-runtime/test_list_borrow_canonical_abi.sh
bash examples/p3-runtime/test_future_owned_canonical_abi.sh
bash examples/p3-runtime/test_g6_2_scalar_list_producer_abi.sh

# 默认完整回归（薄入口；当前基线）
./src/build/test/run_tests.sh
# 2026-09-05: wrapper delegates to `cd src && zig build test --summary all`;
# Build Summary: 14/14 steps succeeded; 53/53 tests passed.
# `RUN_WASM=1` and `RUN_GC_CORE=1` are inherited by the Zig harness and use the
# current-only `bin/do-toolchain` adapter. The GC inventory remains
# `complete_rows=15 pending_rows=15`, exit 1.

# G5a parsed synchronous Core-GC gates (由 harness 的 RUN_GC_CORE 路由统一执行)
RUN_GC_CORE=1 ./src/build/test/run_tests.sh

# G5c bounded synchronous text Component assembly and host execution probe
bash examples/gc-p3-runtime/test_gc_marshal_text_component.sh
bash examples/gc-p3-runtime/test_gc_marshal_text_host.sh
bash examples/gc-p3-runtime/test_gc_marshal_text_equivalence.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_host.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_equivalence.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_mixed_lower_host.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_mixed_lower_equivalence.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_host.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_indirect_lower_equivalence.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_manifest_host.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_manifest_equivalence.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_manifest_host.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_manifest_equivalence.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deeper_manifest_host.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lift_deeper_manifest_equivalence.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deeper_manifest_host.sh
bash examples/gc-p3-runtime/test_gc_marshal_record_nested_lower_deeper_manifest_equivalence.sh
bash examples/gc-p3-runtime/test_gc_wasi_random_list_lift_equivalence.sh
bash examples/gc-p3-runtime/test_gc_marshal_map_u32_u32_manifest_host.sh

# codegen 单元测试
cd src && zig test build/codegen_api.zig
cd src && zig test main.zig --test-filter 'manifest route'
# 期望: All current codegen API tests passed.

# 发布前 smoke
./src/build/test/run_release_smoke.sh
```

可选扩展:

```bash
RUN_WASM=1 ./src/build/test/run_tests.sh
# 2026-09-05: 14/14 steps、53/53 tests passed; current harness summaries are
# default pass=1070 and RUN_WASM=1 pass=1072, with skip=3.
```

| 基线项 | 最近值 |
| --- | --- |
| 默认回归 | `pass=1070 fail=0 skip=3` (`14/14 steps; 53/53 tests`) |
| WASM 扩展回归 (`RUN_WASM=1`) | `pass=1072 fail=0 skip=3` (`14/14 steps; 53/53 tests`) |
| Core GC 扩展回归 (`RUN_GC_CORE=1`) | `14/14 steps; 53/53 tests` |
| `zig test main.zig` | `1568/1568` (当前独立单测基线) |
| async host scalar-argument ABI probe | current-only adapter Component assembly green; frame `20` bytes, argument `u32@12`; ready/pending/cancel oracle green with `argument=7`, exactly-once Future drop, empty `ResourceTable`; probe-only, general lowering pending |
| G6.2 scalar-list producer | private `stream<list<u32>>` promotion green; `ptr=64`, `len=68`, `stride=4`, max `3`, stream capacity `1`; count `0..3`, invalid `4`, pending/error/drop/cancel, exactly-once list release, empty `ResourceTable`; generic list/producer remains pending |
| G5c bounded text host marshal | pinned Core/WIT assembly plus Rust/Wasmtime host execution observes one canonical `hello` string from a fixed GC text lower/copy/call probe; the paired ARC/GC equivalence probe reports one allocation/free on each route; lift, general shapes, compiler wiring, and default-route cutover remain pending |
| G5c manifest-backed WASI random lift | GC lift and hand-authored linear-memory ARC reference use the same versioned WIT package; Rust/Wasmtime observes `lengths=16/16`, `bytes=16/16`, `calls=1/1`; one canonical-boundary equivalence row is closed, while default host/WIT routing and broader G5c cutover remain pending |
| G5c C2 private manifest route | `codegen_component_manifest_route` accepts only a descriptor id, reuses provenance-checked measured planning, and emits the pinned random GC lift; unknown ids fail before WAT, while default host/WIT routing remains ARC |
| G5c C3 private manifest text lower | The second hash-pinned descriptor emits the parser-backed GC `text` lower with canonical `(i32,i32)`; generated GC and ARC Components both deliver `hello` and report one allocation/free through Rust/Wasmtime; ordinary host/WIT routing and broader G5c cutover remain ARC/pending |
| G5c C4 private manifest `list<u32>` lower | The third hash-pinned descriptor emits the parser-backed typed GC-array lower with canonical `(i32,i32)`; generated GC and ARC Components both deliver `[10, 20, 30]` and report one allocation/free through Rust/Wasmtime; arbitrary lists/aggregates, ordinary host/WIT routing, and broader G5c cutover remain pending |
| G5c C5 private manifest `list<u32>` lift | The fourth hash-pinned descriptor emits the parser-backed typed GC-array lift with canonical `(i32)` result-area input; generated GC and ARC Components both return checksum `60` through Rust/Wasmtime; arbitrary lifts/aggregates, ordinary host/WIT routing, and broader G5c cutover remain pending |
| G5c C6 private manifest scalar-record lower | The fifth hash-pinned descriptor emits the parser-backed flat `writing` record lower with canonical `(i32,i32)`; generated GC and flat Components both return `42` with one `write` callback, and the host gate includes a source-hash drift negative check; ordinary host/WIT routing and broader G5c cutover remain pending |
| G5c C7 private manifest scalar-record lift | The sixth hash-pinned descriptor emits the parser-backed `reading` record lift with canonical `(i32)` result-area input; generated GC and linear-memory Components both return `42`, and the host gate includes a source-hash drift negative check; ordinary host/WIT routing and broader G5c cutover remain pending |
| G5c C8 private manifest mixed scalar-record lift | The seventh hash-pinned descriptor emits the parser-backed `u32/u64/s64` `reading` record lift with a 24-byte measured layout and canonical `(i32)` result-area input; generated GC and linear-memory Components both return `37` from `{7, 35, -5}`, and the host gate includes a source-hash drift negative check; ordinary host/WIT routing and broader G5c cutover remain pending |
| G5c C9 private manifest indirect scalar-record lower | The eighth hash-pinned descriptor emits the parser-backed 17-field `u64` `writing` record lower with a 136-byte measured layout and canonical `(i32)` indirect record-area input; generated GC and linear-memory Components both return `42` with `1/1` callback counts, and the host gate includes a source-hash drift negative check; layouts beyond the pinned shape, ordinary host/WIT routing, and broader G5c cutover remain pending |
| G5c C10 private manifest nested scalar-record lift | The ninth hash-pinned descriptor emits the parser-backed two-level `header`/`reading` lift; `header` measures 16 bytes, outer `reading` 32 bytes, and canonical ABI is one `(i32)` result-area pointer; generated GC and linear-memory Components both return `37`, with source-hash and measured-depth negative checks; deeper/general aggregates, ordinary host/WIT routing, async/resource paths, and G5c cutover remain pending |
| G5c C11 private manifest nested scalar-record lower | The tenth hash-pinned descriptor emits the parser-backed two-level `header`/`writing` lower; `header` measures 16 bytes, outer `writing` 32 bytes with `status@16`, and the WIT-derived canonical ABI is `(i32,i64,i64)`; generated GC and linear-memory Components both return `42` with `1/1` callbacks, while source-hash and measured child-count checks reject drift; deeper/indirect nested aggregates, ordinary host/WIT routing, async/resource paths, and G5c cutover remain pending |
| G5c C12 private manifest three-level nested scalar-record lower | The eleventh hash-pinned descriptor emits the parser-backed `header`/`detail`/`writing` lower; measured layouts are 16/32/48 bytes with `status@16` and `tail@32`, and the WIT-derived canonical ABI is `(i32,i64,i64,i64)`; generated GC and linear-memory Components both return `42` with `1/1` callbacks, while source-hash and measured-shape checks reject drift; deeper/general aggregates, indirect nested layouts beyond this shape, ordinary host/WIT routing, async/resource paths, and G5c cutover remain pending |
| G5c C13 private manifest three-level nested scalar-record lift | The twelfth hash-pinned descriptor emits the parser-backed `header`/`detail`/`reading` lift; canonical result-area layout is `header=16`, `detail=24`, `reading=32` bytes with leaf offsets `code@0`, `count@8`, `status@16`, and `tail@24`, and the ABI remains one `(i32)` result-area pointer; generated GC and linear-memory Components both return `42`, while source-hash and measured-shape checks reject drift; deeper/general aggregates, ordinary host/WIT routing, async/resource paths, and G5c cutover remain pending |
| G5c C14 four-level nested scalar-record default route | The thirteenth and fourteenth hash-pinned descriptors emit the parser-backed `leaf`/`header`/`detail`/`reading` and `writing` trees; measured layouts are 16/24/32/40 bytes with flattened offsets `code@0`, `count@8`, `status@16`, `marker@24`, and `tail@32`, lower ABI is `(i32,i64,i64,i64,i64)`, and lift ABI is one `(i32)` result-area pointer; the ordinary synchronous `@host_func` route recursively validates the source/WIT boundary, and default host/equivalence/negative gates plus focused emitter tests are green; the explicit `--gc-wit-marshal` route remains private measured coverage, while arbitrary/deeper/general aggregates, async/resource paths, and G5c cutover remain pending |
| G5c C15-A private manifest scalar-plus-text record lift | The next hash-pinned descriptor emits `reading { code: u32, label: string }` with a measured 12-byte result area (`code@0`, `label.ptr@4`, `label.len@8`) and one `(i32)` result-area pointer; generated GC and linear-memory Components both return `12`, source-hash/child-count checks reject drift, and no GC reference crosses the boundary; text/list record lower, arbitrary managed aggregates, default host/WIT routing, async/resource paths, and G5c cutover remain pending |
| G5c C15-B private manifest scalar-plus-text record lower | The next hash-pinned descriptor emits `writing { code: u32, label: string }` with measured 12-byte layout (`code@0`, `label.ptr@4`, `label.len@8`) and canonical `(i32,i32,i32)` parameters; generated GC and linear-memory Components both observe `code=7`, `label=hello`, one `write` callback, and one allocation/free pair, with source-hash/child-count checks rejecting drift; general managed-record lower, text/list record lower, default host/WIT routing, async/resource paths, and G5c cutover remain pending |
| G5c C15-C explicit compiler wiring | `do build --gc-wit-marshal demo:marshal-record-managed-lower/api.write@1.0.0/lower` now dispatches the real compiler to the C15-B manifest route; compiler-generated WAT passes `wasm-tools 1.255.0`, host execution, and ARC/GC equivalence (`1/1` allocation/free/callback counters); the option is private and explicit, while default host/WIT routing and broader shapes remain pending |
| G5c C15-D private multi-managed-text lower | `demo:marshal-record-managed-lower-multi/api.write@1.0.0/lower` admits only `writing { code: u32, label: string, note: string }` with a measured 20-byte root (`code@0`, `label.ptr@4`, `label.len@8`, `note.ptr@12`, `note.len@16`) and canonical `(i32,i32,i32,i32,i32)` lower parameters; standalone and real compiler GC/ARC Components observe `code=7`, `label=hello`, `note=world`, one callback, and `2/2` allocation/free counters; the route is private and explicit, while general managed records, default host/WIT routing, async/resource lowering, and G5c cutover remain pending |
| G5c C16-A real host boundary | `564_gc_wit_managed_record_host_boundary.do` is the exact host-first source fixture for the private descriptor; token admission checks the synchronous `@host_func`, locator/member/result, and `Writing { code: u32, label: text, note: text }` shape before emitting the five-`i32` canonical lower. Negative async/mismatch cases fail before WAT, the default build remains ARC-backed, and compiler host/equivalence plus residual baseline gates pass; general aggregate/async/resource lowering and G5c cutover remain pending |
| G5c C16-B fixed-descriptor host validator | The explicit `--gc-wit-marshal` adapter now applies descriptor-specific validation to both C15-B (`Writing { code: u32, label: text }`) and C16-A (`code/label/note`) instead of accepting only one descriptor; C15-B compiler host/equivalence and focused validator tests pass, while the new negative/default gate proves async and locator drift fail before WAT and default `@host` remains ARC-backed; no generic Do-to-WIT inference, ownership syntax, async/resource lowering, or inventory row changed |
| G5c C15-D/C16-D default multi-managed-text promotion | Ordinary `do build` now admits the exact C15-D lower and C16-D lift descriptors alongside C15-B/C16-C; default host/equivalence gates pass with C15-D `allocations=2/frees=2`, `2/2` cleanup and C16-D `value=17`, `17/17` equivalence; async/locator/member drift fails before WAT; general aggregates, async/resource, ownership syntax, and full G5c cutover remain pending |
| G5c bounded scalar-record lift/lower | `lift` observes `{code: 20, count: 22}` through one result-area pointer; parser-backed flat scalar `lower` observes `{code: 7, count: 35}` through canonical `(i32,i32)` and returns `42`; host and GC/flat equivalence gates pass; indirect beyond the pinned 17-field shape, deeper/general aggregates, compiler wiring, and default-route cutover remain pending |
| G5c bounded mixed scalar-record lower | ordinary synchronous `@host_func` now admits the exact parser-backed `u32/u64/s64` record descriptor; the 24-byte measured layout uses canonical `(i32,i64,i64)`, and default host/equivalence/negative gates pass with result `42` and one callback per path; indirect beyond the pinned 17-field shape, deeper/general aggregates, async/resource lowering, ownership syntax, and full G5c cutover remain pending |
| G5c scalar-list route implementation | The bounded synchronous record lowerer now shares one internal `ManagedScalarListField` for the external manifest `byte_list` and `list<u32>` kinds. Kind selects `$do_bytes`/`array.get_s $do_bytes`/`i32.store8` with measured stride `1`, capacity `4`, or `$do_u32`/`array.get $do_u32`/`i32.store` with stride `4`, capacity `3`; length/linear-span/allocation/canonical-call/exactly-once-free ordering and the canonical ABI remain unchanged. This is an internal parameterization only; arbitrary lists, list lift, async/resource lowering, ownership syntax, and full G5c cutover remain pending |
| G5c bounded byte-list record lower promotion | The hash-pinned `demo:marshal-record-byte-list-lower/api.write@1.0.0/lower` descriptor admits only `Writing { code: u32, payload: [u8] }`; ordinary `@host_func` and explicit `--gc-wit-marshal` both use the manifest-backed 12-byte root and canonical `(i32,i32,i32)`, copy one byte list, call the host once, and free the temporary linear buffer; default and pinned Component host/equivalence/negative gates pass with `code=7`, `payload=[10,20,5]`, `result=42`, `result=42/17`, and `1/1` allocation/free counters; general list-record lower, async/resource lowering, ownership syntax, and full G5c cutover remain pending |
| G5c bounded `list<u32>` record lower promotion | The hash-pinned `demo:marshal-record-u32-list-lower/api.write@1.0.0/lower` descriptor admits only `Writing { code: u32, payload: [u32] }`; ordinary `@host_func` and explicit `--gc-wit-marshal` use the measured 12-byte root and canonical `(i32,i32,i32)`, copy the GC `u32` array through temporary linear memory, call the host once, and free it exactly once. Host/equivalence/negative gates pass with `code=7`, `payload=[10,20,30]`, `result=42`, `42/17`, and `1/1` allocation/free counters; general list-record lower, async/resource lowering, ownership syntax, and full G5c cutover remain pending |
| G5c bounded `list<u32>` record lift promotion | The hash-pinned `demo:marshal-record-u32-list-lift/api.read@1.0.0/lift` descriptor admits only `Reading { code: u32, payload: [u32] }`; ordinary `@host_func` and explicit `--gc-wit-marshal` use the measured 12-byte result area and canonical `(i32)` pointer, copy the bounded payload into `$do_u32`, free it exactly once, and construct the GC record. Host/equivalence/negative gates pass with `code=7`, `payload=[10,20,30]`, `result=67`, `67/67`, and `1/1` cleanup; general list-record lift, async/resource lowering, ownership syntax, and full G5c cutover remain pending |
| G5c bounded mixed text + `list<u32>` record lift promotion | The hash-pinned `demo:marshal-record-mixed-text-u32-list-lift/api.read@1.0.0/lift` descriptor admits only `Reading { code: u32, label: text, payload: [u32] }`; ordinary `@host_func` and explicit `--gc-wit-marshal` use the measured 20-byte result area (`code@0`, `label@4`, `payload@12`) and canonical `(i32)` pointer, copy text into `$do_bytes` and payload into `$do_u32`, free both spans once, and construct the GC record. Host/equivalence/negative/default gates pass with `code=7`, `label=hello`, `payload=[10,20,5]`, `result=47`, `stats=34`, `47/47`, `34/34`, and `1/1` cleanup; general mixed record/list lift, async/resource lowering, ownership syntax, and full G5c cutover remain pending |
| G5c bounded byte-list record lift promotion | The hash-pinned `demo:marshal-record-byte-list-lift/api.read@1.0.0/lift` descriptor admits only `Reading { code: u32, payload: [u8] }`; ordinary `@host_func` and explicit `--gc-wit-marshal` use the measured 12-byte result area and canonical `(i32)` pointer, copy the bounded payload into `$do_bytes`, free it exactly once, and construct the GC record. Host/equivalence/negative gates pass with `code=7`, `payload=[10,20,30]`, `result=67`, `stats=17`, `67/67`, `17/17`, and `1/1` cleanup; general list-record lift, async/resource lowering, ownership syntax, and full G5c cutover remain pending |
| G5c bounded mixed text + byte-list record lift promotion | The hash-pinned `demo:marshal-record-mixed-text-byte-list-lift/api.read@1.0.0/lift` descriptor admits only `Reading { code: u32, label: text, payload: [u8] }`; ordinary `@host_func` and explicit `--gc-wit-marshal` use the measured 20-byte result area (`code@0`, `label@4`, `payload@12`) and canonical `(i32)` pointer, copy text and byte payload into `$do_bytes`, free payload then label once, and construct the GC record. Host/equivalence/negative/default gates pass with `code=7`, `label=hello`, `payload=[10,20,5]`, `result=47`, `stats=17`, `47/47`, `17/17`, and `1/1` cleanup; general mixed record/list lift, async/resource lowering, ownership syntax, and full G5c cutover remain pending |
| G5c bounded two `list<u32>` record lower promotion | The hash-pinned `demo:marshal-record-two-u32-lists-lower/api.write@1.0.0/lower` descriptor admits only `Writing { code: u32, first: [u32], second: [u32] }`; ordinary `@host_func` uses the measured 20-byte root (`code@0`, `first.ptr@4`, `first.len@8`, `second.ptr@12`, `second.len@16`) and canonical `(i32,i32,i32,i32,i32)`, guards both spans, calls once, and frees `second` then `first`. Host/equivalence/negative/default gates pass with `code=7`, `first=[10,20,5]`, `second=[3,4]`, `2/2` allocation/free counts, and `1/1` callback counts; general aggregate/list lowering, async/resource lowering, ownership syntax, and full G5c cutover remain pending |
| G5c bounded indirect scalar-record lower | parser-backed 17-field `u64` record measures 136 bytes/alignment 8 and lowers to canonical `(i32)`; host gate passes `result=42 write-calls=1`, GC/flat equivalence passes `42/42` and `1/1`; arbitrary indirect/nested layouts, compiler wiring, and default-route cutover remain pending |
| async/D2 recovery designs | general async-call promotion and D2 filesystem/HTTP method matrix recorded; no generic lowering |
| Task 8 Step 3 runtime baseline | 十一个已登记同步 Component/Rust/Wasmtime descriptor gate 通过 |
| D2 descriptor.stat private promotion | ABI/Do/generated Component/Rust gate green; Core template SHA-256 `b7aee0221318c857817859c5e849fa98da9909c2151b09c6dea9b964c986a69a`; generated WIT SHA-256 `4a2e5055c2ec06c772660b211c3e3ab3e3e15d8b5931c8e7def804e56d5175da`; generic filesystem async remains pending |
| D2 descriptor.sync-data private promotion | ABI/Do/generated Component/Rust gate green; Core template SHA-256 `3269e6f8c61a34dbea99f2637a257d582d79ab860f812d6ddfc46392e4fc3e7b`; generated WIT SHA-256 `df3c055bab6ecff3d3b77435ba67df6c4d207eb786e243d41f1301873fabfed9`; ready/pending/error/cancel/repeat and Store-disposal early-drop boundary verified; generic filesystem async remains pending |
| D2 descriptor.metadata-hash private promotion | ABI/Do/generated Component/Rust gate green; Core template SHA-256 `f51c82887174a7ed1adf95a1cbe0e333f80a487962a2a8478334ca9750933b6b`; regular/cancel WIT mirror SHA-256 `6976359b3a4813d6771b3ef9a7fdcfb2ee9323e70c33b9ac7d6b628519fecfed` / `b6e98cf2ae6f76e105f53c7ea09666b1c5684d33edb9838d034862a27b09f5c3`; fixture `516` passes and `517`-`519` reject; generated ready/pending/error/repeat plus hand-authored cancel/Store-disposal early-drop oracle verified; generic filesystem async remains pending |
| D2 descriptor.metadata-hash-at private promotion | ABI/Do/generated Component/Rust gate green; method `(i32,i32,i32,i32,i32)->i32`, task-return `(i32,i64,i64)`, Core template SHA-256 `6056d1e6f42d6ab4edce60e2bb1ef61f358bfd6d03e6aa1e3c35daf08672713f`; regular/cancel WIT mirror SHA-256 `95e24b70eeed89407706c18a6e4cd13a8bc4dce72d1e56638436b03287d23412` / `aca9c5933786a00a2dd20b1ad1ddbb6d0a79ab5b3bdbd5bd61e14b100a3b6e0a`; fixture `520` passes and `521`-`529` reject; UTF-8 path-copy pending/wake and exactly-once cleanup verified; generic filesystem async remains pending |
| D2 descriptor.stat-at private promotion | ABI/Do/generated Component/Rust gate green; method `(i32,i32,i32,i32,i32)->i32`, task-return `(i32,i32,i64,i64,i32,i64,i32,i32,i64,i32,i32,i64,i32)`, Core template SHA-256 `4503fa7634560c66463f96ac142bcc7cfb7b90cca93a8b705c1d1eb05040ddef`; regular/cancel WIT mirror SHA-256 `92afa427efedc960fd60ce2edbd3ced26521225ae8857377554956646a1059bd` / `420fb95fae7505e568414e55f19dc2f89f5b32e015e8d999166e38b48e4a4a49`; fixture `530` passes and `531`-`539` reject; path-copy/flag propagation and exactly-once cleanup verified; generic filesystem async remains pending |
| D2 descriptor.open-at private promotion | ABI/Do/generated Component/Rust/Wasmtime gate green; method `(i32,i32)->i32`, six-word indirect parameter block, task-return `(i32,i32)`, Core template SHA-256 `a05a8e90cfb553658a8a5337e026a0fa1304aa42f0b33558a3d6ecfc17623201`; regular/cancel WIT mirror SHA-256 `1e5f9131387015c4e650a64e02bb9f112d8266f4755aa6b605af038407ef807a` / `1c48fba03b569d91617efd834232fcccc553ca3001ffb0e0834b4134f93e4f52`; fixture `540` passes and `541`-`551` reject; copied path and exactly-once parent/child cleanup verified; cancel defers parent drop to unified termination; generic filesystem async remains pending |
| HTTP service ABI / empty-request gate | pinned Component + Rust/Wasmtime pass; `codegen_component_wasi_http` `189/189`; registered payload pending/ready gate green, unregistered/general ready delivery remains blocked |
| pinned filesystem record source mirror | `p3_filesystem_wit_manifest` + read-directory sema tests pass |
| `compile_ok` / `compiled_ok` / `compile_err` | `333` / `78` / `181` fixtures |
| 剩余 skip | `16_loop_recv_value`、`96_file_lib_resource_shape`、`118_wasi_p3_std_wrappers` (recv/WASI 后置) |
| 诊断 code | `errorSummary` / `errorHint` 各 59 条 (含 `StreamWriterLeasePathConflict` / `StreamWriterDeferredTransfer`) |

私有 D2 filesystem async 当前只开放十个独立的有界方法：
`wasi:filesystem/types@0.3.0-rc-2025-09-16 / descriptor.get-type`、
`descriptor.sync`、`descriptor.get-flags`、`descriptor.stat`、`descriptor.sync-data`
、`descriptor.metadata-hash`、`descriptor.metadata-hash-at`、
`descriptor.stat-at`、`descriptor.open-at` 与 `descriptor.set-size`。`get-type` 的
`[async-lower][method]descriptor.get-type` 使用 `(i32,i32)->i32`，task-return
完成参数为两个 `i32`，Result 是 `descriptor-type | error-code` component
variant，资源 drop 为 `[resource-drop]descriptor`。ABI、手写/生成 Component、
Rust/Wasmtime 手写 Component 的 ready/pending/error/cancel、生成 Component 的
ready/pending/error 和 fixtures `459`-`461` 均已验证；
`sync` 的 `[async-lower][method]descriptor.sync` 同样使用 `(i32,i32)->i32`，
Result 为 unit/error-code component variant，fixtures `462`-`465` 覆盖
unregistered/result/borrowed-payload/second-await 负边界；手写 Component 的
ready/pending/error/cancel 与生成 Component 的 ready/pending/error 均通过
exactly-once cleanup 和 `table-empty=true`。两者都不意味着通用
`read`/`write`/其它通用 filesystem methods、通用 producer、borrowed payload 与公开
`own<T>`/`borrow<T>`/`ref<T>` 仍需独立 design/probe/gate。
`get-flags` 的 `[async-lower][method]descriptor.get-flags` 也使用
`(i32,i32)->i32`，canonical result-area 是 `u8`、flat task-return 是 `i32`，
Result 为 `descriptor-flags | error-code`；fixtures `471`-`474` 与
ready/pending/error/cancel cleanup gate 已通过。`sync-data` 的
`[async-lower][method]descriptor.sync-data` 也使用 `(i32,i32)->i32`，
task-return 为两个 `i32`，Result 为 `unit | error-code`；fixture `511` 通过，
`512`-`515` 在 WAT 前拒绝，ready/pending/error/cancel/repeat 与
Store-disposal early-drop 行均通过。这些方法都不意味着通用
filesystem async 或公开 ownership 支持，扩展仍需独立 design/probe/gate。
`metadata-hash` 的 `[async-lower][method]descriptor.metadata-hash` 使用
`(i32,i32)->i32`，task-return 为 `(i32,i64,i64)`，Result 为
`metadata-hash-value { lower:u64, upper:u64 } | error-code`；fixture `516`
通过，`517`-`519` 在 WAT 前拒绝，generated ready/pending/error/repeat 与
hand-authored cancel/Store-disposal early-drop oracle 均通过。`metadata-hash-at`
的五参数 path-flags/string lowering 另通过 fixture `520`、`521`-`529` 与
generated Component/Rust/Wasmtime path-copy matrix；generic filesystem async
仍需独立 design/probe/gate。`stat-at` 的五参数 path-flags/string lowering
通过 fixture `530`、`531`-`539` 与生成 Component/Rust/Wasmtime path-copy /
flag propagation matrix；其 `descriptor-stat | error-code` record layout 与
两页 UTF-8 path memory boundary固定，通用 filesystem async 仍需独立
design/probe/gate。
`set-size` 的 `[async-lower][method]descriptor.set-size` 使用
`(i32,i64,i32)->i32`，参数顺序为 `descriptor, size, result-area`，task-return
为 `(i32,i32)`，Result 为 `unit | error-code`；fixture `552` 通过，`553`-`563`
在 WAT 前拒绝，generated Component/Rust/Wasmtime 的 ready/pending/error/cancel/
early-drop/repeat mutation matrix 与 exactly-once cleanup 均通过。取消只清理
guest/Component 状态，不回滚已经发出的 host 文件大小变更。
`sync` ABI gate 固定 upstream hash
`8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`、regular
mirror `18ce7dc9efb991cd8e5f945797aea73edeed79f0cfc51ea664cb81537e54e719`、
cancel mirror `9898cd734708a2ab14760da706d69063e5cd6262a5e03d07d8eedd8074745f36`；
The active wasm-tools hash and runtime counters are recorded in
`doc/host_abi_blockers.md`; historical 1.254.0 measurements are evidence only。

### 2026-08-09 next-phase boundary handoff

The borrow capability refresh against `wasm-tools 1.255.0` still accepts only
the checked synchronous `list<borrow<T>>` row; `future<borrow<T>>` and borrowed
stream records remain rejected during `component embed`. The bounded pure
scalar `stream<list<u32>>` probe is green as an independent WIT/Core/Rust/
Wasmtime artifact, with list words `64/68`, stride `4`, maximum length `3`,
exactly-once list release, and an empty `ResourceTable`. It is not a Do type or
registry capability.

The promotion contract and D2 recovery matrix are documented in
[`general-async-call-promotion-design.md`](../doc/superpowers/specs/2026-08-09-general-async-call-promotion-design.md)
and
[`d2-general-filesystem-async-boundary-design.md`](../doc/superpowers/specs/2026-08-09-d2-general-filesystem-async-boundary-design.md).
Arbitrary producers, multiple unmeasured awaits, payload/resource/list/stream
futures, general filesystem methods, external HTTP service worlds, and public
`own<T>`/`borrow<T>`/`ref<T>` remain pending and require their own gates.

The private async host scalar-argument compiler promotion is green. Its
opt-in target is `--p3-async-host-arg-component` and it admits only the pinned
`do:async-call-arg-probe/host@0.1.0 / work` source shape with one `u32` helper
argument and root literal `@async(helper(7))`. The generated WIT package hash
is `b9f5f8355e87231317ec05cccf692ee465c6f339bd509640aedc196e58f81e61`; the
root-owned frame remains `20` bytes with the argument at offset `12`.
`test_do_async_host_scalar_argument.sh` and `test_rust_async_host_scalar_argument.sh`
pass current-only adapter Component assembly/validation and
generated ready/pending/cancel with argument `7`, exactly-once Future cleanup,
and an empty `ResourceTable`. General async-call lowering, arbitrary producer
expressions, payload/resource/list/stream futures, borrowed values, root
hard-cancel, D2 general methods, and public `own<T>`/`borrow<T>`/`ref<T>` remain
pending and require separate design/probe/gate evidence.

### WIT bindgen 当前边界

`do wit check` 解析并校验 WIT；`do wit bind` 在项目根 `wit/` 生成扁平
`*.do`、`manifest.json` 和 `wit.lock`。可用 `do wit check --manifest` 校验
生成 metadata 与 WIT 的 package/world/hash/effect 一致性。项目源文件若放在 `wit/src/`，生成时
不会被当作生成输入删除。生成的普通 `@host_func` locator（包括自定义 namespace）
已可通过 checker；WASI/P3 lowering 仍只接受现有 pinned registry，通用 custom
host 的 WAT/Component lowering 尚未开放。

当前已开放的 generated WIT async Component capability 仍是严格私有且有界的：
其中一个是
`do:generic-async-runtime-probe@0.1.0` 的 `host.work: async func()`：它使用
manifest schema 2 的 `component-async-unit-v1`，由 import graph 自动发现并
复用有界 generic runtime template。`examples/wit-bindgen-do/test_generated_async_lowering.sh`
同时验证 `wasm-tools 1.255.0`、Wasmtime 47.0.2 和 Rust 1.97.1 的
pending/immediate/cancel 运行时矩阵。payload、Stream、resource、参数化或
任意其他 generated WIT async shape 仍拒绝并保持 `AsyncLoweringUnavailable`。

另一个已开放但同样严格私有的 capability 是
`do:generic-async-scalar-probe@0.1.0` 的
`host.completion: func() -> future<u32>`，使用
`component-async-scalar-u32-v1` 和经 probe 测量的 `offset=12`、`byte-size=4`、
`alignment=4`、`encoding=core-u32`。运行
`bash examples/wit-bindgen-do/test_generated_async_scalar_lowering.sh` 可复现
生成模块、manifest drift、Component 以及 ready/pending/cancel Rust/Wasmtime
矩阵。它只接受普通 `run() -> nil` 中一次 `Future<u32>` `@await` 和一次终止
`@cancel`；generic Future payload、Stream、resource、分支/循环、timeout 和
unrestricted generated WIT lowering 仍拒绝。

同一阶段另有独立的 i64 scalar capability：
`do:generic-async-scalar-i64-probe@0.1.0` 的
`host.completion: func() -> future<s64>` 使用
`component-async-scalar-i64-v1`，package hash 为
`861990fea33b55fecd08573ef94f4088296b2cb2bca3356813a2d2157251f3ba`，payload
为 `offset=16`、`byte-size=8`、`alignment=8`、`encoding=core-s64`。运行
`bash examples/wit-bindgen-do/test_generated_async_scalar_i64_lowering.sh`
可复现同样的 manifest drift、Component 与 ready/pending/cancel
Rust/Wasmtime 矩阵。当前只开放这两个明确 pinned 的 scalar descriptor，
不代表 generic `Future<T>` 已完成。

generic ABI v2 的第二个独立 shape 是同一 i64 scalar descriptor 的 v2
adapter。使用 `bash examples/wit-bindgen-do/test_generic_abi_v2_scalar_i64.sh`
可复现独立模板、测量 layout、Component assembly 和 Rust/Wasmtime
ready/pending/cancel 矩阵；它仍支持旧的单 shape `--p3-async-v2-scalar-i64`
入口。统一 promotion profile 使用 `--p3-async-component-v2`（完整 gate：
`bash examples/p3-runtime/test_generic_abi_v2_promotion.sh`），只接受
variant-resource-stream 与 generated `Future<i64>` 两个已验证 shape，默认
`--p3-async-component` registry/v1 dispatch 不变。

用户函数 async-call 另有一个独立 opt-in bounded slice：
`--p3-async-call-component` 接受无参数、`nil` 返回的 `helper`，以及一个
单 `u32` literal 参数的 inline scalar companion；根函数通过一次
`@async(helper(...))` 创建并 `@await`，helper 内只允许一次已登记的
`do:generic-async-call-probe/host@0.1.0` `work: async func()`。其实现使用
root-owned local frame/state，并通过根 `[task-return]run` 完成，不暴露 helper
Component export，也不伪造独立 child task。使用
`examples/p3-runtime/test_do_async_call_component.sh`、
`test_do_async_call_inline_scalar_argument.sh` 和 Rust/Wasmtime gate 可复现
pinned `wasm-tools 1.255.0` / Wasmtime `47.0.2` 的 ready/pending/cancel 矩阵。
额外参数、payload、多个 child、嵌套 helper、resource、Stream、list、任意
producer expression、filesystem async 和 D2 I/O 仍保持拒绝或 pending。

当前工作区的 `/tmp` 配额会让 Zig Debug cache 返回 `DiskQuota`；`run_tests.sh` 现在
尊重 `TMPDIR`、`ZIG_LOCAL_CACHE_DIR` / `ZIG_GLOBAL_CACHE_DIR` 覆盖，并在回归开始时
创建显式的 `TMPDIR` 根目录。配额受限环境使用项目专用目录运行标准回归，例如：

```bash
TMPDIR="$PWD/.tmp/do-tmp/debug-tmp" \
ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/do-tmp/debug-zig-cache" \
ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/do-tmp/debug-zig-gcache" \
./src/build/test/run_tests.sh
```

不应通过删除无关 `/tmp` 内容来规避环境问题。

发布候选的其它一致性检查 (链接、fixture companion、WASI registry、shell harness 等) 在收口交付时按 `doc/roadmap_status.md`「文档治理 / gate 复跑」清单执行; **不必每次把整表抄进本文**。

## 4. 架构模块地图

扁平拆分后的编译器边界 (与 `AGENTS.md` 一致):

| 层级 | 模块 | 职责 |
| --- | --- | --- |
| 流水线 | `lexer` → `parser` → `sema` → `codegen` | 主编译路径 |
| 共享纯函数 | `type_name` | 类型/布局 SSOT (scalar/storage/managed/Tuple scheme A) |
| | `sema_error` | ErrorSite 与 sema 错误构造 |
| | `diagnostics` | check/LSP 共用前端诊断收集 (原 `src/lsp/diagnostics.zig` 已删除) |
| Sema 域 | `sema.zig` | 公开入口 (`check_program` / `take_last_error_site`) + 编排 |
| | `sema_tokens.zig` | token/name/scan 谓词与行扫描 |
| | `sema_shapes.zig` | 共享 shape 类型 (`FuncShape` / `StructInfo` / …) |
| | `sema_function_signatures` / `_calls` / `_lambdas` | 签名 / 调用·泛型 / lambda |
| | `sema_function_support.zig` | 多个 sema 域共享的语义辅助函数 |
| | `sema_structures.zig` | struct 字段·ctor / path / Tuple |
| | `sema_type_checks.zig` | 类型声明 / enum·error·payload / union / type refs |
| | `sema_imports.zig` | host/local import + 已知 WASI 签名校验 |
| | `sema_control_flow.zig` | loop/label / defer |
| | `sema_field_checks.zig` | field reflection |
| | `sema_constraints.zig` | assign / constraint |
| Gen 域 | `codegen_api.zig` | 公开入口 + 单测 |
| | `codegen_pipeline.zig` | 编排核（`emit_wat*` / hooks install）+ 最小 re-export |
| | `codegen_generics.zig` | 泛型实例化 / 类型绑定 / callback prebind（不 import lower） |
| | `codegen_callbacks.zig` | 晚绑定 emit 回调（破 control/union→expression、struct→union 反向边） |
| | `codegen_model.zig` | 不可变声明、shape、ownership/free、`ExprCallHead` |
| | `codegen_context.zig` | LocalSet、可变 codegen context、local-name helpers |
| | `codegen_constants.zig` | ABI/layout ID 与 compiler temporary-local 名称 |
| | `codegen_collect_util.zig` / `codegen_collect_structs.zig` / `codegen_collect_functions.zig` / `codegen_collect_declarations.zig` | 类型 parse·bind / struct·layout / func / enum collect |
| | `codegen_emit_expression.zig` / `codegen_emit_call.zig` | 表达式与调用 dispatch |
| | `codegen_body.zig` / `codegen_collect_reflection.zig` | body-local、loop、multi-result 与 field-reflection collection |
| | `codegen_emit_control.zig` | 控制流 emit（body/if/loop/defer/guard） |
| | `codegen_emit_storage_operations.zig` / `codegen_emit_storage_values.zig` / `codegen_storage_layout.zig` | storage emit、layout 与 Tuple pack helpers |
| | `codegen_emit_tuple.zig` | Tuple / pure-scalar pack helpers |
| | `codegen_emit_struct.zig` / `codegen_emit_struct_fields.zig` | struct binding / field / literal emit |
| | `codegen_emit_union.zig` | union value / binding emit |
| | `codegen_emit_wasi.zig` | WASI host 调用/结果 emit（`EmitExprFn`/hooks，不 import lower） |
| | `codegen_ownership.zig` | ARC release plan emit / 作用域可达性辅助 |
| | `codegen_tokens.zig` | token/range/scan/decode 工具 |
| | `codegen_names.zig` | public name、core-func 名表、mangled 符号 |
| | `codegen_host_imports.zig` | unified `@host_func("env", member, sig)` host import collect/parse |
| | `codegen_imports.zig` | 模块 import 解析、reach、string-data |
| | `codegen_wasi_registry.zig` / `codegen_union_layout.zig` | WASI 表/parse; union layout |
| | `wat_payload` | 标量 payload load/store、Tuple 叶子 pack/unpack |
| | `wat_storage` | storage 指针/header/alias; `HEADER=8` |
| | `runtime_arc_wat` | ARC runtime WAT + layout 类型 SSOT |
| | `runtime_prelude_wat` | string-data memory emit + re-export ARC API |
| | `wat_function_body` / `wat_component_metadata` | 其它 WAT 写出切片 |
| 旁路 | `codegen_ir` | **仅**标量 `start` 旁路 + unit; **不是**主 emit 路径 |
| CLI | `src/main.zig` | 分派; `do test` 经 `runTest` → `loadProgram` |

**刻意未做**: 批量把真 overload `NoMatchingCall` 改成 `UnsupportedLowering`; 合并静态/compiled 双 runner; 把 `codegen_ir` 扩成主路径; 继续硬拆 `codegen_emit_storage_operations` / `codegen_emit_expression` / `parser` / `imports` / `test_runner`（hooks 耦合或高风险，ROI 低）。

**已落地架构竖切**: `sema` 与 `gen` 均已按域拆成扁平 `*_` 模块 (见上表与 `AGENTS.md`); 对外仍经 `sema.zig` / `codegen_api.zig` 入口。Batch B: collect 四叶、sema scan/func 子域、runtime ARC SSOT。

### 2026-08-21 G5c C16-C checkpoint

已将 C15-A 的固定 `Reading { code: u32, label: text }` lift 证据接入真实
编译器的私有显式 route：
`--gc-wit-marshal demo:marshal-record-managed-lift/api.read@1.0.0/lift`。
该 route 只接受精确同步 `@host_func`、零参数、`Reading` 返回值和有序字段，
生成 12-byte result area、canonical `(func (param i32))` 以及 typed GC text
构造。compiler host gate 返回 `12`，ARC/GC equivalence 返回 `12/12`；async
和 locator mismatch 在 WAT 写出前拒绝，省略 opt-in 时仍走 ARC。C16-C 是私有
固定 descriptor 证据，不改变 15 行 migration inventory，也不代表通用
aggregate、默认 host/WIT GC route、async/resource 或 ownership lowering 已完成。

### 2026-08-21 G5c C16-D checkpoint

已将固定三字段 `Reading { code: u32, label: text, note: text }` lift 接入真实
编译器的私有显式 route：
`--gc-wit-marshal demo:marshal-record-managed-lift-multi/api.read@1.0.0/lift`。
该 route 只接受精确同步 `@host_func`、零参数和有序三字段结果，使用 20-byte
result area 与 canonical `(func (param i32))`，并构造两个 typed GC text 字段。
compiler host gate 返回 `17`，ARC/GC equivalence 返回 `17/17`；async 和 locator
mismatch 在 WAT 写出前拒绝，省略 opt-in 时仍走 ARC。focused `3/3`、完整 Zig
`591/591`、`run_tests.sh` `pass=1279 fail=0 skip=3`、ReleaseSmall/release smoke
与 `git diff --check` 均通过。C16-D 仍是私有固定 descriptor 证据，不改变 15 行
migration inventory，也不代表通用 aggregate、默认 host/WIT GC route、
async/resource 或 ownership lowering 已完成。

### 2026-08-21 G5c manifest-driven bounded compiler route closeout

四个私有同步 managed-record route 现在从 hash-pinned descriptor manifest
读取 `measured_layout`，并从 resolved WIT member 与实际 Do token 派生
host boundary。仍必须显式使用 `--gc-wit-marshal`；普通 `@host` 保持
ARC-backed，canonical import 不允许 GC reference。8 个 compiler
host/equivalence gate 与 4 个 negative/default gate 通过；完整 Zig 为
`598/598`，`run_tests.sh` 为 `pass=1279 fail=0 skip=3`，ReleaseSmall、
release smoke 与 `wasm-tools 1.255.0` 验证通过。migration inventory 保持
`complete_rows=15 pending_rows=15`、exit 1；通用 aggregate、async/resource、
ownership syntax 与 G5c full cutover 仍 pending。

### 2026-08-22 G5c default host/WIT route promotion

普通 `do build` 现对精确 descriptor 使用 manifest-backed 默认 GC/WIT
route：C14 lift/lower、C15-B/C15-D lower、C16-C/C16-D lift、mixed scalar-record lower、byte-list record lower、`list<u32>` record lower 与 mixed text/u32-list lower。各路径均输出
`;; gc-sync`、不含 `__arc_`，canonical import 不携带 GC reference；async
与 locator mismatch 在 WAT 写出前拒绝。专门的 C14 默认 host/equivalence/
negative gate、mixed lower host/equivalence/negative gate 与 C15-D/C16-D 默认 gate 分别锁定 `42/42` value 和 `2/2`
cleanup、`17/17` value；通用 aggregate、
async/resource、ownership syntax 和 full cutover 继续 pending。
本次 promotion 的全量验证已通过：`zig test main.zig` `609/609`、
`run_tests.sh` `pass=1297 fail=0 skip=3`、ReleaseSmall、release smoke、
residual baseline 和 `git diff --check` 均通过；inventory 仍为
`complete_rows=15 pending_rows=15`、exit 1。

### 2026-08-22 G5c C14 default synchronous host/WIT route checkpoint

The ordinary `@host_func` route now admits only the two C14 four-level
scalar-record descriptors. Recursive record-shape, scalar-order, synchronous
host declaration, and WIT locator/member checks run before WAT; the lift/lower
canonical imports remain `(i32)` and `(i32, i64, i64, i64, i64)` with no GC
reference crossing the boundary. Default host/equivalence/negative gates and
focused emitter tests `3/3` are green. The explicit `--gc-wit-marshal` route
remains private measured coverage; arbitrary aggregates, async/resource,
ownership syntax, and full G5c cutover remain pending.

### 2026-08-25 G5c mixed text + `list<u32>` lower default route

普通 `do build` 现准入唯一精确 descriptor
`demo:marshal-record-mixed-text-u32-list-lower/api.write@1.0.0/lower`，对应
同步 `@host_func` 与 `Writing { code: u32, label: text, payload: [u32] }`。
root 为 20 bytes，字段偏移为 `0/4/12`，payload capacity 为 `3`、stride 为
`4`，canonical lower ABI 为五个 `i32` words，且无 GC reference 跨边界。
Host gate 观察 `code=7`、`label=hello`、`payload=[10,20,5]`、
`allocations=2/frees=2`、`write-calls=1`；ARC/GC equivalence 观察
`2/2` cleanup 与 `1/1` callback；8 个负向 fixture 在 WAT 前拒绝。
default 83-fixture gate、residual 三阶段 gate、ReleaseSmall 与 release smoke
均通过 `wasm-tools 1.255.0`。这是固定 bounded promotion；通用 aggregate、
async/resource、ownership syntax、full G5c cutover 和
`complete_rows=15 pending_rows=15` inventory 仍 pending。

### 2026-08-25 G5c mixed text + `list<u32>` lift default route

普通 `do build` 现准入唯一精确 descriptor
`demo:marshal-record-mixed-text-u32-list-lift/api.read@1.0.0/lift`，对应
同步 `@host_func` 与
`Reading { code: u32, label: text, payload: [u32] }`。result area 为
20 bytes，字段偏移为 `0/4/12`，payload capacity 为 `3`、stride 为 `4`，
canonical lift ABI 为单个 `(i32)` result-area pointer，且无 GC reference
跨边界。GC lift 将 label 复制到 `$do_bytes`、payload 复制到 `$do_u32`，按
payload -> label 顺序各释放一次；host 观察 `code=7`、`label=hello`、
`payload=[10,20,5]`、`result=47`、`stats=34`、`read-calls=1`、
`allocations=2/frees=2`，ARC/GC equivalence 观察 `47/47`、`34/34`、
`1/1`。负例 `640–647` 在 WAT 前拒绝；该 slice 当时的 default GC
build/parse gate 覆盖 `83 fixtures`，当前总基线为 `86 fixtures`，residual、
ReleaseSmall 和 release smoke 均通过 `wasm-tools 1.255.0`。这是固定
bounded promotion；通用 aggregate/list、async/resource、ownership syntax、
full G5c cutover 和 `complete_rows=15 pending_rows=15` inventory 仍 pending。

### 2026-08-25 G5c two `list<u32>` record lower default route

普通同步 `@host_func` 现准入唯一精确 descriptor
`demo:marshal-record-two-u32-lists-lower/api.write@1.0.0/lower`，对应
`Writing { code: u32, first: [u32], second: [u32] }`。root 为 20 bytes，
字段偏移为 `code@0`、`first.ptr@4`/`first.len@8`、
`second.ptr@12`/`second.len@16`；两个 list capacity 分别为 `3/2`，
stride 为 `4`，canonical lower ABI 为五个 `i32` words，且无 GC reference
跨边界。两个 linear span 均在 copy 前做范围校验，host call 一次，释放顺序
为 `second` 后 `first`，各一次。

Host gate 观察 `code=7`、`first=[10,20,5]`、`second=[3,4]`、
`allocations=2/frees=2`、`write-calls=1`；ARC/GC equivalence 观察相同
payload 与 `2/2` cleanup；7 个 descriptor drift negative fixtures 在
WAT 写出前拒绝。该 slice 当时的 default GC build/parse gate 覆盖
`83 fixtures`，当前总基线为 `86 fixtures`；residual baseline 通过，工具链
为 pinned `wasm-tools 1.255.0`。这是固定 bounded promotion，不开放通用
aggregate/list、async/resource、ownership syntax，也不关闭 migration row；
inventory 仍为 `complete_rows=15 pending_rows=15`。

### 当前阶段增量（2026-09-09）

私有 async `map<u32,u32>` compiler admission 已完成：
`--p3-async-map-component` 只接受
`demo:map-async-probe/api@0.1.0.submit` 的固定 `HashMap<u32,u32>` 输入、两个
pair `[7,70]`/`[9,90]`、一个 helper/root await 拓扑和 pinned WIT/WAT。严格
source analyzer、五个负例（错误 value type、动态 map、额外 pair、同步 host
marker、第二次 await）均在 WAT 写出前拒绝；正例 WIT/WAT 与 snapshot 完全一致，
Core/Component 及 Rust/Wasmtime `ready/pending/cancel/drop` gate 通过。默认不带
flag 的同一源仍返回 `AsyncLoweringUnavailable` 且无 WAT/WIT 输出。

该 route 是 private bounded promotion，不改变同步 map 或普通 GC pipeline；通用
async map、其他 key/value、Stream 跨 poll owned buffer、arbitrary producer 与
public `own<T>`/`borrow<T>`/`ref<T>` syntax 仍 pending。专用能力与设计背景见
`doc/superpowers/specs/2026-09-05-async-map-capability-design.md` 和
`doc/superpowers/specs/2026-09-09-async-map-compiler-admission-design.md`。

### 当前阶段增量（2026-09-05）

精确 async `map<u32,u32>` capability probe 已完成并通过专用 gate：WIT 为
`async func(values: map<u32, u32>) -> u32`，Core 观察形状为
`(i32 ptr, i32 len, i32 result_area) -> i32`。host 在 Future 可能挂起前复制
pair-list，canonical WAT 随后覆盖 guest 输入；`ready/pending/cancel/drop` 均满足
`input-mismatches=0`、`frame-frees=1`、空 `ResourceTable` 与 exactly-once future
cleanup。设计记录见
`doc/superpowers/specs/2026-09-05-async-map-capability-design.md`。

本轮默认及 `RUN_WASM=1 RUN_GC_CORE=1` 组合回归均为
`14/14 steps succeeded; 53/53 tests passed`，`zig test main.zig` 为 `792/792`，
ReleaseSmall/release smoke 通过。该 probe 只关闭精确 runtime capability 证据，
不开放通用 async map lowering、Stream 跨 poll buffer、ownership syntax 或新的
GC inventory row。

### 当前阶段交接（2026-09-04）

G6.2 internal producer/resource contract consolidation 已完成 release-candidate
验证。`ProducerContract` 及其 source/sink、payload、ownership-transfer 和 terminal
子计划只接收已测量的九条 private route；不扩大 Do/WIT 公开语法，也不把 route-specific
模板合并成未经测量的通用 emitter。fresh evidence 位于
`.superpowers/sdd/2026-09-03-g6-2-general-producer-resource/task-7-release-verification.txt`：
默认 harness 为 `pass=1070 fail=0 skip=3`，`RUN_WASM=1` 为 `pass=1072 fail=0 skip=3`，
`RUN_GC_CORE=1`、ReleaseSmall、release smoke 和 `zig test main.zig` `785/785` 均通过；
GC inventory 仍为 `complete_rows=15 pending_rows=15`、预期 exit 1。

### 上一阶段交接（2026-08-30）

固定 descriptor promotion 已达到当前 bounded slice，G5c route consolidation
也已完成验证闭环：现有 C14–C20 精确 route 与 mixed text/two-u32-list route
共用一次 manifest-backed `LoadedRequest`、descriptor registry、owned
host-boundary facts 和 measured `SyncValuePlan`，并由同一套 span guard、canonical
ABI 与 exactly-once cleanup 门禁覆盖。新鲜证据为 `run_tests.sh`
`pass=1446 fail=0 skip=3`、`zig test main.zig` `701/701`、default GC gate
`86 fixtures`、semantic-equivalence `26 rows; 0 pending`、ReleaseSmall/release-smoke 均通过；
inventory 仍为 `complete_rows=15 pending_rows=15`、预期 exit 1。

本轮已完成 release-candidate maintenance（含六跳 forwarding 证据文档收口）并重新
通过 residual capability matrix 设计门。使用项目专用 `TMPDIR`、
`ZIG_LOCAL_CACHE_DIR`、`ZIG_GLOBAL_CACHE_DIR` 复跑后，focused marshal module/ops/WAT
为 `90/90`、`43/43`、`66/66`，并闭合 G6.2 私有双 owned-field record producer 与固定三字段
`ResourceTriple` compiler admission 的 manifest/source matcher、canonical ABI、Component
assembly、13 个 negative、Rust/Wasmtime lifecycle 与 canonical/generated equivalence 十模式
gate。host、ARC/GC equivalence、negative、
default、residual、semantic-equivalence、全量回归、ReleaseSmall、release smoke 均通过；
inventory 仍为 `complete_rows=15 pending_rows=15`、预期 exit 1。默认 `/tmp` 配额
导致的 `DiskQuota` 仅是环境限制，已由显式缓存路径复验通过，不是语义失败。

唯一 candidate `demo:marshal-record-mixed-text-byte-u32-lists-lower/api.write@1.0.0/lower`
已完成候选专用闭环；当前没有第二个满足 admission contract 的同步 descriptor。G6.2
direct owned-record、双 owned-field producer 与固定三字段 `ResourceTriple` compiler
admission 的独立 design/lifecycle gate 均已闭环；后续新的 producer/resource shape 仍须
按 design -> manifest/hash/ABI -> compiler/source matcher -> negative -> Component ->
Rust/Wasmtime -> exactly-once cleanup 顺序单独立项。默认 route 不直接扩大，当前仍不开放
通用 `list<T>`、aggregate inference、async/resource lowering 或 `own<T>`/`borrow<T>`/`ref<T>`。

本次刷新另外通过 focused marshal module/ops/WAT `90/90`、`43/43`、`66/66`
以及 mixed-text/two-`list<u32>` lower/lift 的 host、ARC/GC equivalence、negative
矩阵。上述证据仍只覆盖固定 descriptor，不代表 full G5c 或全局 GC cutover。

## 5. 当前阻断

| ID | 说明 | 恢复条件 |
| --- | --- | --- |
| G6.2 | `descriptor.read-directory`、注册 record-stream consumer 与 bounded scalar/dynamic/batched producer | scalar/string、多-owned-resource、多个顶层 nested paths 与一层/两层/三层/四层/五层/六层 nested-owned-resource consumer、注册 `do:stream-probe` 的 capacity-one `StreamWriter<u8>` producer、固定/参数化 `u64` countdown producer、参数化 helper 的六跳 forwarding、typed 参数受限重排、其它同类型 async helper、bounded StreamMirror、私有 `variant-resource-stream`、private C-min list/resource producer、动态 count `0..3` producer、固定两批 list-resource producer 与固定三字段 `ResourceTriple` compiler admission 已验证；一般 producer lease、borrowed/list/通用 variant、第七跳 forwarding、第七层或更一般 nested resource gates 与任意 filesystem async method 仍待单独推进 |
| G6.2-cancel | 私有 resource Result cancellation | 显式 `@cancel(completion)` 的 Do lowering、负边界、Component assembly 与 Rust/Wasmtime pending/drop/empty-table gate 已通过；pinned `wasi:http` service-world gate 另验证 pending、immediate `Ok(response)` 的 exactly-once drop、`DnsTimeout`、bounded `DNS-error.rcode` 的 `Some(nonempty)` 与 `None`（两种长度和 `info-code` optional 状态）以及同一布局的 `InternalError(Some(nonempty string))` / `InternalError(None)` canonical discard。同一组件实例连续两次 nonempty DNS error 会在每次精确释放后复用该私有槽位。`None` 不读取或释放 pointer/length；空字符串和其他 payload error 仍 trap；不扩展到通用 resource cancellation 或公开 ownership syntax |
| G6.3 | **已关闭 (方案 B)** create/bind/drop + dual address | 见 `compile_ok/291`–`294`; TCP/UDP loopback real-host gate 已通过，listen/connect/accept 与真实 socket I/O 仍后置 |
| D2 | 真实 host runtime smoke | local filesystem preopen/open-at/sync、read-directory stream、CLI stdin pipe、TCP/UDP socket create/bind/drop，以及私有 `descriptor.get-type`/`descriptor.sync`/`descriptor.get-flags`/`descriptor.stat`/`descriptor.sync-data`/`descriptor.metadata-hash`/`descriptor.metadata-hash-at`/`descriptor.stat-at`/`descriptor.open-at`/`descriptor.set-size` async slices 已有 gates；通用 filesystem async 与 external HTTP 仍阻断 |
| 06.2 | 已拆到 G2–G6; 剩余由 G6.2 承接 | 同上 |

**Result source policy (closed):** ordinary public and standard-library APIs use
`T | E` (or `nil | E`); duplicate ordinary union branches remain rejected.
`Result<T, E>` is retained only for registered private WIT/Component probes
whose ABI needs an explicit tag, including same-type arms. This does not add
public `own<T>`, `borrow<T>`, or `ref<T>` syntax.

**待处理 / 阻断 / 延期**: 权威清单见 [pending_blocked.md](pending_blocked.md) (G6 后续 producer/borrowed-resource gates、P2 泛型左侧反推、skip、deferred 非目标)。

**Wasm ref 语法策略 (未实现)**: `externref`→将来 `@host_ref`; 无公开 `anyref`/`funcref` 类型; i32 内存指针不做 do 类型 — [design/wasm_ref_host_syntax.md](design/wasm_ref_host_syntax.md) (D10)。扩讨论存档（已搁置）: [design/2026-07-13-wasm-wasi-support-discussion.md](design/2026-07-13-wasm-wasi-support-discussion.md)。

已落地对照 (勿当待办): pure-scalar Tuple 子槽 `ok/192`; managed 叶子 storage `compile_ok/270`–`271`; field_set `ok/191`。

## 6. 当前计划候选

用户说 `go` / `next` 时, 按以下优先级 (细节与恢复条件见 [pending_blocked.md](pending_blocked.md)):

当前默认 GC build/parse gate 基线为 87 fixtures；下方较早增量中的 79/80/81/82/83/84/85/86 为
历史 checkpoint。

1. **发布候选维护**: 回归红灯、文档漂移、可独立验证的小修
1a. **G5a/G5b/G5c GC migration**: parsed bounded text/list/struct/tuple/union/generic/import slices 已有 typed GC evidence，当前 admitted synchronous 的 26 行 ARC/GC executable equivalence 已闭环；Task 3 已把已准入同步 candidates 接入默认 pipeline，并覆盖推断出的 `text` body binding 的首次 `local_bind` 与后续 `overwrite`、推断出的 `[u8]`/`[u32]` body storage `@put`，以及 body-only managed-struct storage ctor/field update，未准入形状在 WAT 前 fail-closed。`src/build/test/check_gc_default_build_gate.sh` 已锁定 87 个 admitted fixture 的默认 `do build` + current-only `bin/do-toolchain parse-core` gate；scalar-leaf 的纯同步 identity/arithmetic、scalar control-flow 的 `if/else`、`else-if`、guard-return 与 acyclic same-module scalar helper calls 也已通过独立 no-ARC gate，self/mutual/longer recursion、loop、defer、导入模块和 scalar host binding 保持 fail-closed。bounded parser-backed scalar-record `lift/lower` 已通过 Component assembly、host execution 与 ARC/GC equivalence gates，C14 已扩到四层纯标量树，C15-A/B/D 已闭合私有 scalar-plus-text 与 multi-managed-text record lift/lower 的独立 Component host/equivalence gates，C15-C 已闭合单 descriptor的 lower compiler wiring，C16-C 已闭合 C15-A 的 lift compiler wiring；C15-B/D 的固定 lower ABI 分别为 `(i32, i32, i32)` 和 `(i32, i32, i32, i32, i32)`，临时线性内存均只在 host call 后释放。C14 lift/lower、C15-D/C16-D multi-managed-text promotion、C19 byte-list record lift、C20 mixed text/byte-list record lift、two-u32-list record lower、mixed text/two-u32-list record lower 与 mixed text/two-u32-list record lift 已完成默认 route、probe、negative 与等价 gate；G5c residual capability matrix 已完成逐行复核，当前 exact candidate 已通过专用和全局门禁；G6.2 固定三字段 `ResourceTriple` compiler admission 也已完成其独立 manifest/negative/Component/Rust/Wasmtime/parity 闭环。保持通用 aggregate、未准入 host/WIT shape、async/resource、ownership syntax 与 full cutover 不开放。
    2026-08-20 增量（已由后续 bounded slice 扩展）：第三个 managed segment 的直接 `@get/@set(outer, .inner, .middle, .leaf, ...)` nested managed-struct 路径已通过 typed GC lowering、compiled-test、Wasmtime probe 和等价矩阵；更深路径、producer expression、async/resource 与 host/WIT 当时仍不准入。
    2026-08-22 增量：第五个 managed segment 的直接 `@get/@set(top, .outer, .inner, .middle, .leaf, .core, ...)` nested managed-struct 路径已通过 typed GC lowering、compiled-test、Wasmtime probe 和 26 行 ARC/GC 等价矩阵；内部实现随后收敛为固定容量五-link 的 `GenericNestedFieldPath` 与 loop-based parser/emitter，未改变公开 admission。第六个 managed segment、producer expression、async/resource 与通用 host/WIT 仍不准入。focused `codegen_gc_sync.zig` 为 `245/245`、`gc_sync_probe.zig` 为 `65/65`，默认 GC build/parse gate 为 72 fixtures，均使用 pinned `wasm-tools 1.255.0` 与 `27815` oracle。
2. **推进 G6.2 后续 gates**: generic consumer、multi-owned-resource、多个顶层 nested-owned-resource paths、一层/两层/三层/四层/五层/六层 nested-owned-resource、bounded scalar/parameterized dynamic producer、参数化 helper（含六跳 forwarding 与 typed 参数受限重排）与受限 helper-mediated lease slices 已闭环；继续一般 producer lease、borrowed/list/variant、第七跳 forwarding、第七层或更一般 nested resource fields 与更广泛 async method 的独立验证
2a. **当前 gate 状态**: branch-selected terminal、reordered helper、StreamMirror、pinned negative probes 与 ownership invariant 复核已通过；下一步只能在独立 positive plan 授权后扩大 producer/resource 形状
3. **推进 D2 已授权的本地 smoke**: 维护 file/dir/CLI/socket create-bind-drop 与私有 `descriptor.get-type`/`descriptor.sync`/`descriptor.get-flags`/`descriptor.stat`/`descriptor.sync-data`/`descriptor.metadata-hash`/`descriptor.metadata-hash-at`/`descriptor.stat-at`/`descriptor.open-at`/`descriptor.set-size` gates；通用 filesystem async/external HTTP 另立 target/design 后再推进
4. **可选授权**: 其他 deferred 项 (ownership / JSON / LSP / codegen 再拆)

**已关闭边界速查**:

- I1: 直接/互递归; 参数侧已定型泛型递归; self-tail TCO 子集; 左侧反推泛型仍后置; `defer`/storage/managed/多返回/cleanup **不** TCO
- I2: `Tuple` 位置构造 + `@get`; 嵌套永不拍平; pure-scalar struct 子槽 + managed 叶子 storage + path chain

## 7. 变更与推进协议

- 每次只做一个可验证小任务; 完成后更新本文基线, 必要时写 `CHANGELOG.md`。
- 语法/语义变更同步 `doc/spec_rules.md`、`doc/grammar.peg`、相关 `doc/syntax/*.md` 与回归。
- 工具行为变更同步 `README.md`、`src/build/test/README.md` 与黑盒 fixture。
- **只保留最新**: 不维护向后兼容路径、过期草案、空占位目录或历史 gate 流水账。
- 不默认: 重开 get/pkg/push; 去掉内部 `@` 前缀; direct wasm binary emitter; 完整 WASI/Component; 大规模重写 parser/sema/codegen。
- 产品命令边界: `do run` = core wasm smoke (`do-toolchain`+`node`); `do fmt` = 单文件 stdout/check/write; `do lsp` = diagnostics/formatting/tokens/hover/completion/definition (无 rename); `do check` = 前端诊断 only。
