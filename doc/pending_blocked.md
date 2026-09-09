# 待处理与阻断清单

更新时间: 2026-09-10
基线: 默认回归由 `./src/build/test/run_tests.sh` 薄入口转发到 Zig harness
关系: 总规划 `doc/master_plan.md`; 接手 `doc/start_here.md`; 执行状态 `doc/roadmap_status.md`
约定: **只记未关闭项**; 完成后从本文件删除或移入「已关闭摘要」, 并同步入口文档与 `CHANGELOG.md`。

> **Superseded by GC-first (2026-08-11, cutover closed 2026-09-09):**
> `doc/memory.md` 与 `doc/design/2026-08-11-gc-first-memory-decision.md` 已选定
> Wasm GC 为 v1 managed-memory target。Task 6 已将普通编译入口切换为 GC-only；
> ARC 只保留为显式 test-only equivalence oracle。下文只记录仍未关闭的能力缺口；
> Component/WIT resource 的 ownership 与 drop 继续是显式 ABI contract, 不由 GC 接管。

### GC-first runtime cutover (已关闭, 2026-09-09)

生产入口 `src/build/codegen_runtime_api.zig` 只选择 Wasm GC，ARC runtime/legacy
emitter 仅由 `src/build/test/gc_arc_equivalence_oracle.zig` 显式引用。fresh
evidence: ARC inventory post-cutover `rows=49 matches=480 unclassified=0
normal_route_matches=0`，生产依赖闭包 `modules=153 forbidden=0`，GC default gate
`87 fixtures`，semantic-equivalence `26 rows; 0 pending`；默认及
`RUN_WASM=1 RUN_GC_CORE=1` harness 均为 `14/14 steps; 53/53 tests`，独立
`zig test main.zig` 为 `1561/1561`，ReleaseSmall/release smoke 通过。

该项只关闭 backend 选择和 ARC 隔离，不关闭下方 capability inventory；
`complete_rows=15 pending_rows=15` 仍按设计返回 `1`，通用 async/map/producer/
resource lowering 与 public `own<T>`/`borrow<T>`/`ref<T>` syntax 继续 pending。

### G6.2 private mixed owned-record producer (已关闭, 2026-09-10)

精确 descriptor `do:g6-2-owned-record-mixed-producer@0.1.0` 已在
`--p3-async-component` 下完成 private compiler admission。它只接受
`MixedEntry { code: u32, ticket: own<Ticket> }`、capacity-one
`stream<mixed-entry>`、同步 source `(i32) -> (i32)` 和一个 `mode u32` producer
输入；record size/alignment 为 `8/4`，字段 offset 为 `code=0`、`ticket=4`，
ticket seed 为 `111`，WIT SHA-256 为
`5fe1c2ed6a0c348bf6f0e96596afc419bbbd379345421f02fa36f05aa472d9ed`。
immutable `ProducerContract` 只为 `ticket` 建立 bit `0` ownership leaf，scalar
`code` 不带 ownership/drop bit；完整 record 写入是唯一 transfer commit point，
转移前后 cleanup 均 exactly once，handle `0` 在 presence bit 设置时仍有效。

Do/Component 正向 gate、9 个 WAT 前负例 (`762`–`770`)、canonical ABI、生成
Rust/Wasmtime lifecycle 和 canonical/generated parity 全部通过。十模式覆盖
ready/pending、sink error、transfer 前后 cancel/early-drop、repeat、invalid；
valid 为 `1/1` ticket cleanup（repeat `2/2`），invalid 不创建资源，所有模式
`table-empty=true`，生成 WAT/WIT 与 canonical 产物保持字节一致且无 `__arc_`。
该项不关闭通用 producer、arbitrary expression、borrowed/list/variant payload、
general async/resource lowering 或 public `own<T>`/`borrow<T>`/`ref<T>` syntax，
也不新增 GC inventory row；这些仍按下方边界单独推进。

### Toolchain adapter 与 Zig harness (2026-09-02)

Task 9 Step 1 的 current-only active gate 已通过独立复核：
`src/build/test/check_toolchain_adapter.sh` 固定检查仓库
`bin/do-toolchain`、`toolchain/toolchain.lock.json`、probe identity、active
Shell raw-command/alias 扫描和旧版引用拒绝；根目录及无关 `/tmp` cwd、负例、
`bash -n` 与 scoped `git diff --check` 均通过。当前 active route 为
`wasm-tools 1.258.0`、Wasmtime `48.0.1`；历史 `1.255.0` 只保留在 dated
证据中。跨行二级 Shell alias 尚未被完整解析，属于 P3 残余风险，当前 active
脚本未命中且不阻断本 gate。

Task 8 Step 3 的 Rust host adapter 批次已按报告闭合；Step 4 的 Shell 入口已
缩减为 `cd src && zig build test --summary all` 薄 wrapper，Step 5 的逐 fixture
parity 已闭合，报告位于
`.superpowers/sdd/2026-08-30-map-toolchain-zig-harness/task-8-step4-5-parity-report.md`。
`check_run_tests_entrypoint.sh` 另外锁定 cwd、参数、cache 环境和
`RUN_WASM`/`RUN_GC_CORE` 继承。Task 9 Step 1 active gate 与 Step 2 文档同步
已闭合；Task 9 Step 3 的完整 active 验证和 Step 5 的交付前工作区审查也已
通过。默认、`RUN_WASM=1`、`RUN_GC_CORE=1` 薄入口均为 14/14 steps、51/51
tests，ReleaseSmall/release smoke、adapter gate、入口契约和
`git diff --check` 均通过；Rust Cargo 测试使用仓库内 `zig-cc.sh` linker 环境
通过，裸命令的 `cc` 缺失仅是本机环境前提。

验证环境备注：本机没有 `cc` 可执行文件，裸 `cargo test --locked` 会在
Wasmtime build script 阶段失败；通过仓库内
`examples/p3-runtime/rust-host-runner/zig-cc.sh` 注入 `CC`、`CXX` 和 target
linker 后，Rust 48.0.1 全量测试通过。该项是环境前提，不是 active runtime
blocker。

2026-09-09 验证刷新：默认及 `RUN_WASM=1 RUN_GC_CORE=1` 组合回归均为
`14/14 steps; 53/53 tests`，`zig test main.zig` 为 `1561/1561`，ReleaseSmall 与
release smoke 通过。新增 async map probe 与 private compiler admission 已包含在
两次 harness 运行中；默认不带 flag 的 async-map fixture 仍返回
`AsyncLoweringUnavailable` 且不写出 WAT/WIT。这些结果不改变下方通用 map、Stream
跨 poll 或 cleanup authority 的阻断边界。

### WIT map runtime lowering (P2, exact sync route closed; general pending)

`map<K,V>` 的 parser/model/manifest/registry schema 已按 pair-list ABI 表示
完成；map 与 `list<tuple<K,V>>` 仍是不同语义。`wit_abi_types` 已有 map 节点，
bounded Core WAT emitter/probe 已覆盖 `u32` key 与 `u32`/`text` value 的
lower/lift，并通过当前 `wasm-tools` 的 parse/validate。精确同步
`map<u32,u32>` lower/lift 的 manifest-backed Component route 已闭环：
`HashMap<u32,u32>` host boundary、Do/Rust/Wasmtime fixtures、负例签名漂移和
Zig harness 均通过，lower/lift 各为一次 host call 与一次 allocation/free。
同步 map operation-frame 顺序门禁已加入：lower 在 canonical call 前完成临时
pair-list copy，call 后才释放；lift 在释放 result-area 前完成 copy、GC value
construct 和 root publish，异步逃逸标记在 WAT 前拒绝。该门禁只约束已有同步
route，不代表 async map 参数 copy、Stream 跨 poll owned buffer 或通用 cleanup
authority 已实现。
精确 async capability probe `demo:map-async-probe/api.submit@0.1.0` 已单独建立：
WIT 为 `async func(values: map<u32, u32>) -> u32`，Core 观察形状为
`(i32 ptr, i32 len, i32 result_area) -> i32`。固定 pair-list 输入在 host callback
返回 Future 前复制，随后由 canonical WAT 覆盖 guest 输入；`ready`、`pending`、
`cancel`、`drop` 四种终态均验证 `input-mismatches=0`、一次 frame free、一次
future drop 和空 `ResourceTable`。设计与产物见
`doc/superpowers/specs/2026-09-05-async-map-capability-design.md`；该 probe 本身
只证明 runtime capability，不等于通用 compiler lowering。

其上新增的 private compiler admission 只由
`--p3-async-map-component` 选择，严格接受两个固定 pair、一个 helper/root
await 拓扑和 pinned descriptor；WAT/WIT snapshot、五个 WAT 前负例、Component
validate 与 Rust/Wasmtime 四模式 gate 均通过。默认 route 仍返回
`AsyncLoweringUnavailable`，且不产生 WAT/WIT。该 private route 不关闭任何 G5c
inventory row。
通用 Component/WIT map lowering、其他 key/value 组合、其他 async map 参数 copy、Stream
跨 poll owned buffer 和统一 cleanup authority 尚未实现。当前 registry 对这些
未支持 shape 仍返回 `UnsupportedWitMarshalShape`，不得据精确 route 推断通用
map runtime 已完成。该剩余阻断不妨碍主线的 GC/G6.2/D2 独立工作。

### G6.2 private two-owned-field record producer checkpoint (2026-08-27)

本轮已闭合一个独立、私有且固定形状的 producer gate：descriptor
`do:g6-2-owned-record-pair-producer@0.1.0` 只准入
`StreamWriter<ResourcePair> -> Result<nil, ProducerError>`，其中
`ResourcePair { left: Ticket, right: Ticket }` 映射为两个 `own<ticket>` 字段。
WIT hash 为
`89345a5213936735d7f065cd54ed42b83d159b80305a1a900ae00df2e811704d`，record
size/alignment 为 `8/4`，字段 offset 为 `0/4`，stream capacity 为 `1`，seed
为 `111/222`。独立 presence mask 只在完整 record 写入成功后清除两个 guest
ownership bits 并原子转移；转移前按 `right -> left` 释放，转移后 host 各释放
一次，handle 值 `0` 不作为 absence sentinel。

canonical ABI、Do/Component、negative admission、generated Rust/Wasmtime
lifecycle 与 canonical/generated equivalence gates 均通过十模式；valid 模式
均为 `2/2` ticket drops、`1/1` stream/future cleanup 且 `table-empty=true`，
repeat 为 `4/4`，invalid 不创建资源。Rust/Wasmtime 还记录每次有效 host import
一次 `callback-calls`；`pending` 为两次 stream-consumer poll，转移前取消/早退
为零次，转移后为一次；十种模式均为 `finish-calls=0`。四种取消/早退各有一次
未完成 future drop，并以 `cancel-calls=1` 记录 host-task 中止；其余有效模式
future 完成一次。该 Component 生命周期证据不计入
ARC/GC semantic-equivalence matrix，迁移 inventory 仍为
`complete_rows=15 pending_rows=15`、exit `1`。

剩余阻断不变：generic producer、arbitrary producer expression、borrowed/list/
variant/mixed resource payload、general async/resource lowering、public
`own<T>`/`borrow<T>`/`ref<T>` syntax 与 full GC cutover 仍需独立 design 和
可验证 gate；本 checkpoint 不扩大默认 route。

### G6.2 private parameterized two-owned-field record producer checkpoint (2026-08-28)

参数化 pair route 已完成独立、私有且固定形状的 admission gate：descriptor
`do:g6-2-owned-record-pair-parameterized-producer@0.1.0` 只准入
`StreamWriter<ResourcePair> -> Result<nil, ProducerError>`，producer 以
`(mode, left-seed, right-seed)` 接收三个 `u32` words。WIT hash 为
`e7abd3cf7b7543325865a0b4be4b32ae50a2470ac5083169250719f89b7ce53a`，record
size/alignment 为 `8/4`，字段 offset 为 `0/4`，stream capacity 为 `1`。
presence mask 在完整 record 写入成功后才原子转移两个 owned handle；转移前
按 `right -> left` 释放，转移后 host 各释放一次，handle `0` 不作为 absence
sentinel。

canonical ABI、Do/Component、十个 fail-closed negative fixtures、generated
Rust/Wasmtime lifecycle 与 canonical/generated equivalence gates 均通过。十种
模式保持 valid `2/2` ticket cleanup、repeat `4/4`、`table-empty=true`，invalid
不创建资源；`pending` 为两次 stream poll，转移前取消/早退为零次，转移后为一次，
所有模式 `finish-calls=0`。fresh full regression 为 `pass=1410 fail=0 skip=3`，
`zig test main.zig` 为 `692/692`，ReleaseSmall/release smoke 通过；inventory
仍为 `complete_rows=15 pending_rows=15`、exit `1`。这些 Component 生命周期
证据不关闭 ARC/GC semantic-equivalence row。

该 route 只关闭参数化 pair 的私有证据，不扩大默认 route。generic producer、
arbitrary producer expression、borrowed/list/variant/mixed resource payload、
general async/resource lowering、public `own<T>`/`borrow<T>`/`ref<T>` syntax 与
full GC cutover 仍 pending；固定三字段 `ResourceTriple` 的 private compiler
admission 已通过并在下方「已关闭摘要」记录。

### G5c bounded mixed text + two `list<u32>` lower promotion (2026-08-25)

固定 descriptor
`demo:marshal-record-mixed-text-two-u32-lists-lower/api.write@1.0.0/lower` 已完成
独立 spec、manifest/WIT source hash、普通同步 `@host_func` default route、
Component/Rust/Wasmtime host、negative、ARC/GC equivalence 与全量验证。它只准入：

```text
Writing { code: u32, label: text, first: [u32], second: [u32] }
```

root 为 28 bytes，字段偏移为 `0/4/12/20`，两个 list capacity 为 `3/2`、stride
为 `4`，canonical lower ABI 为七个 `i32` words，且无 GC reference 跨边界。三条
linear span 均在 copy 前做范围校验，host call 一次，按
`second -> first -> label` exactly once 释放。Host 观察
`code=7`、`label=hello`、`first=[10,20,5]`、`second=[3,4]`、
`allocations=3/frees=3`、`write-calls=1`；ARC/GC equivalence 观察 `3/3`
cleanup 与 `1/1` callback；负例 `666–672` 在 WAT 前拒绝。default GC gate 覆盖
`86 fixtures`，`run_tests.sh` 为 `pass=1398 fail=0 skip=3`，`zig test main.zig`
为 `686/686`，residual、semantic-equivalence、ReleaseSmall 和 release smoke
均通过。

这是固定形状 promotion，不开放通用 aggregate/list、async/resource、ownership
syntax 或 full G5c cutover；inventory 仍为 `complete_rows=15 pending_rows=15`、
exit `1`。

### G5c bounded mixed text + two `list<u32>` lift promotion (2026-08-25)

当前 inventory 仍为 `complete_rows=15 pending_rows=15`、exit `1`。mixed text +
two `list<u32>` lower 已闭合，不重复作为候选；本轮已完成同步
`Reading { code: u32, label: text, first: [u32], second: [u32] }` lift。独立
spec/plan 与实现验证；lift 只准入 `Reading { code: u32, label: text, first:
[u32], second: [u32] }`，result area 为 28 bytes，canonical ABI 为单个 `i32`
result-area pointer，三条 span 按 `second -> first -> label` exactly once 释放。
Host 观察 `result=54`、`stats=51`、`read-calls=1`、`allocations=3/frees=3`；
ARC/GC equivalence 为 `54/54`、`51/51`、`1/1`，负例 `674–681` 在 WAT 前拒绝。
这是固定形状 promotion，不开放通用 aggregate/list、async/resource、ownership
syntax 或 full G5c cutover；inventory 仍为 pending。

### G5c residual capability matrix and candidate gate (2026-08-26)

15-row capability matrix 已完成逐行复核，每行只出现一次：
`host_wit_marshalling` 中的一个 exact descriptor 被选为 candidate，其余 14
行因通用 aggregate/list、producer、async/resource、ownership 或缺少 ABI/
cleanup 契约而保持 blocked。候选为：

```text
demo:marshal-record-mixed-text-byte-u32-lists-lower/api.write@1.0.0/lower
```

它只接受同步 `@host_func` 与
`Writing { code: u32, label: text, bytes: [u8], values: [u32] }`，manifest
source/WIT hash 为
`sha256:2d966dfc68f27f42ba7ce5f44c471907cf2ebe922a9af24d3cfc810847cce9c3`，
root 为 28 bytes，canonical lower ABI 为七个 scalar `i32` words，无 GC
reference 跨边界。当前 host/equivalence/negative 以及 focused、default、
residual、semantic-equivalence、全量回归、ReleaseSmall、release smoke 门禁
均已现场通过；host 观察 `allocations=3/frees=3`、`write-calls=1`，等价为
`3/3` cleanup、`1/1` callback，7 个 drift case 在 WAT 前拒绝。

该候选仍是固定形状 promotion，不关闭 migration row。下一步只做候选收口
和 release-candidate maintenance，然后重新筛选下一单一同步 descriptor；不
扩大默认 route，也不开放 `own<T>`、`borrow<T>`、`ref<T>`、通用 async/resource
或 full GC cutover。

### G5c current batch verification refresh (2026-08-26)

Fresh verification reran the focused marshal module/operation/WAT suites with
`90/90`, `43/43`, and `66/66` passing. The mixed-text/two-`list<u32>` lower and
lift host, ARC/GC equivalence, and negative gates all pass with the pinned
`wasm-tools 1.255.0`; the full regression is `pass=1398 fail=0 skip=3`, Zig is
`686/686`, the default GC gate covers `86 fixtures`, the residual and semantic
equivalence gates pass, and ReleaseSmall/release smoke pass. The migration
inventory intentionally remains `complete_rows=15 pending_rows=15` with exit
`1`. This refresh changes evidence only; it does not close a migration row or
open general aggregate/list, async/resource, or ownership syntax.

### Release-candidate maintenance and residual recheck (2026-08-26)

Release-candidate maintenance and the residual recheck are green with explicit
project-local `TMPDIR` and Zig cache paths. The default `/tmp` tmpfs produced
`DiskQuota` while writing compiler caches; no source or semantic failure was
observed. The rerun passed the six-hop Do/Rust gates, focused marshal module/ops/WAT
`90/90`, `43/43`, `66/66`, full regression `pass=1398 fail=0 skip=3`, Zig
`686/686`, default GC `86 fixtures`, G5c residual, semantic-equivalence `26 rows;
0 pending`, ReleaseSmall, and release smoke.

The inventory remains `complete_rows=15 pending_rows=15` with deliberate exit `1`.
The matrix has one candidate and fourteen blocked rows; the candidate-specific
mixed-text/byte-u32-list lower host, ARC/GC equivalence, and negative gates pass.
The matrix table now escapes the union separator as `Unit \| Bytes([u8])`, so its
15-row decision columns are machine-readable. The candidate is fixed-shape only;
the next executable work is an independently designed G6.2 bounded producer/resource
shape. General aggregate/list, arbitrary producer expressions, borrowed/variant
payloads, seventh-hop/deeper nested resource shapes, public ownership syntax, and
full GC cutover remain blocked.

### G5c bounded mixed text + `list<u32>` lower promotion (2026-08-25)

The hash-pinned descriptor
`demo:marshal-record-mixed-text-u32-list-lower/api.write@1.0.0/lower` is
closed only for the exact synchronous source/WIT pair
`Writing { code: u32, label: text, payload: [u32] }`. The measured root is
20 bytes with field offsets `0`, `4`, and `12`; the `list<u32>` child has
capacity `3`, element size/alignment/stride `4`, and the canonical lower import
has five `i32` words with no GC reference. The GC lowerer copies the label and
u32 payload into temporary linear spans, calls the host once, then frees
payload before label exactly once. Host output is `code=7`, `label=hello`,
`payload=[10,20,5]`, `allocations=2`, `frees=2`, `write-calls=1`; ARC/GC
equivalence observes `2/2` cleanup and `1/1` callback. Fixtures 631-638 reject
async, locator/member, field-order, payload-kind, extra-field, and record-name
drift before WAT. The default 83-fixture gate, residual three-phase gate, and
ReleaseSmall/release smoke pass with pinned `wasm-tools 1.255.0`.

This is a fixed-shape promotion, not general record/list lowering. Arbitrary
aggregates, async/resource lowering, ownership syntax, and full G5c cutover
remain pending; the migration inventory remains
`complete_rows=15 pending_rows=15` with exit 1.

### G5c bounded mixed text + `list<u32>` lift promotion (2026-08-25)

The hash-pinned descriptor
`demo:marshal-record-mixed-text-u32-list-lift/api.read@1.0.0/lift` is closed
only for the exact synchronous source/WIT pair
`Reading { code: u32, label: text, payload: [u32] }`. The measured result area
is 20 bytes with field offsets `0`, `4`, and `12`; the `list<u32>` child has
capacity `3`, element size/alignment/stride `4`, and the canonical lift import
has one `i32` result-area pointer with no GC reference. The GC lift copies the
label into `$do_bytes` and the payload into `$do_u32`, then frees payload before
label exactly once. Host output is `code=7`, `label=hello`,
`payload=[10,20,5]`, `result=47`, `stats=34`, `read-calls=1`,
`allocations=2`, `frees=2`; ARC/GC equivalence observes `47/47`, `34/34`,
and `1/1`. Fixtures `640–647` reject async, locator/member, field-order,
payload-kind, extra-field, and record-name drift before WAT. The default gate
covers `83 fixtures`, and the residual, ReleaseSmall, and release-smoke gates
pass with pinned `wasm-tools 1.255.0`.

This is a fixed-shape promotion, not general mixed record/list lift. Arbitrary
aggregates, other list element types, async/resource lowering, ownership syntax,
and full G5c cutover remain pending; the migration inventory remains
`complete_rows=15 pending_rows=15` with exit 1.

### G5c bounded mixed text + byte-list lift promotion (2026-08-25)

The hash-pinned descriptor
`demo:marshal-record-mixed-text-byte-list-lift/api.read@1.0.0/lift` is closed
only for the exact synchronous source/WIT pair
`Reading { code: u32, label: text, payload: [u8] }`. The measured result area
is 20 bytes with field offsets `0`, `4`, and `12`; the `list<u8>` child has
capacity `4`, element size/alignment/stride `1`, and the canonical lift import
has one `i32` result-area pointer with no GC reference. The GC lift copies both
label and payload into `$do_bytes`, then frees payload before label exactly once.
Host output is `code=7`, `label=hello`, `payload=[10,20,5]`, `result=47`,
`stats=17`, `read-calls=1`, `allocations=2`, `frees=2`; ARC/GC equivalence
observes `47/47`, `17/17`, and `1/1`. Fixtures `649–656` reject async,
locator/member, field-order, payload-kind, extra-field, and record-name drift
before WAT. The current default gate covers `83 fixtures`, and the residual,
ReleaseSmall, and release-smoke gates pass with pinned `wasm-tools 1.255.0`.

This is a fixed-shape promotion, not general mixed record/list lift. Arbitrary
aggregates, other list element types, async/resource lowering, ownership syntax,
and full G5c cutover remain pending; the migration inventory remains
`complete_rows=15 pending_rows=15` with exit 1.

### G5c scalar-list internal route parameterization (2026-08-23)

The bounded synchronous record lower implementation now shares one internal
`ManagedScalarListField` specification for manifest `byte_list` and `list`
inputs. Element kind selects the GC array and linear store (`u8`: stride `1`,
capacity `4`; `u32`: stride `4`, capacity `3`), while the measured length,
span, allocation, canonical-call, and exactly-once free guards stay in one
emitter. This does not change the manifest schema or canonical ABI and does
not add a descriptor. Arbitrary `list<T>`, list lift, async/resource lowering,
ownership syntax, and full G5c cutover remain pending; the existing
`complete_rows=15 pending_rows=15` inventory is unchanged.

### G5c default host/WIT route update (2026-08-23)

普通 `do build` 已接入固定的一组精确 manifest-backed synchronous route：C14
four-level scalar-record lift/lower、C15-B/C15-D managed-record lower、
C16-C/C16-D managed-record lift、bounded mixed scalar-record lower、bounded
byte-list record lower/lift、bounded `list<u32>` record lower 与 bounded
`list<u32>` record lift、bounded mixed scalar-list record lower、bounded mixed
text/u32-list record lower/lift、bounded mixed text/two-u32-list record lower/lift。
各 route 的
default GC、
canonical ABI 无 GC reference、async/locator/member mismatch 负例、host/
equivalence 和无 ARC marker gate 已通过。通用 aggregate、async/resource、
公开 ownership syntax 以及完整 G5c migration 仍是 pending；本节不将这些
bounded route 的完成扩大解释为全量 host/WIT cutover。

2026-08-25 route consolidation checkpoint: C14–C20 的 default 与显式
marshal route 现在共用一次 manifest-backed `LoadedRequest`、descriptor
registry、owned host-boundary facts 和 measured `SyncValuePlan`。已登记 locator
但 member 漂移在 WAT 前返回 `GcWitHostMemberMismatch`；未知 locator 仍保持
既有 ARC fallback。新鲜 focused host/equivalence/negative 矩阵与 residual gate、
完整回归 `pass=1363 fail=0 skip=3`、`zig test main.zig` `668/668`、default
`83 fixtures`、ReleaseSmall/release-smoke 均通过。该 checkpoint 只收敛重复解析、
span guard、canonical ABI 与 exactly-once cleanup 的 fail-closed 边界，不提升通用
aggregate/list、async/resource 或 ownership；所有 15 个 migration rows 仍按
inventory 保持 pending。

### G5c private mixed scalar-list record lower descriptor status (2026-08-23)

The hash-pinned descriptor
`demo:marshal-record-mixed-scalar-list-lower/api.write@1.0.0/lower` is closed
for the exact source/WIT pair
`Writing { code: u32, label: text, payload: [u8] }`. Its measured root is
20 bytes with field offsets `0`, `4`, and `12`; the canonical lower import has
five `i32` words in field order: `code`, `label.ptr`, `label.len`,
`payload.ptr`, and `payload.len`. The GC lowerer copies both managed spans to
linear memory, calls the host once, and frees payload then label exactly once.
The host and ARC/GC equivalence gates observe `code=7`, `label=hello`,
`payload=[10,20,5]`, two allocations, and two frees. Fixtures 623-629 reject
async, locator, member, field-order, payload-element, and extra-field drift
before WAT. General record/list lowering, lift, async/resource lowering,
ownership syntax, and full G5c cutover remain pending; the migration inventory
remains `complete_rows=15 pending_rows=15` with exit 1.

### G5c private byte-list record lift descriptor status (2026-08-23)

The hash-pinned descriptor
`demo:marshal-record-byte-list-lift/api.read@1.0.0/lift` is closed for the
exact source/WIT pair `Reading { code: u32, payload: [u8] }`. The ordinary
default route and explicit `--gc-wit-marshal` route share the measured 12-byte
result area and one `(i32)` canonical lift pointer. The lift validates the
result-area and list span, copies `payload` into a GC `$do_bytes` array, frees
the temporary linear span exactly once, and constructs one GC record. The host
gate observes `code=7`, `payload=[10,20,30]`, `result=67`, one callback, one
allocation/free pair, and `stats=17`; ARC/GC equivalence observes `67/67`,
`17/17`, and `1/1` cleanup. Fixtures 616-621 reject async, locator, member,
field-order, element-type, and extra-field drift before WAT. General list-record lift, async/resource
lowering, ownership syntax, and full G5c cutover remain pending; the migration
inventory remains `complete_rows=15 pending_rows=15` with exit 1.

### G5c private `list<u32>` record lift descriptor status (2026-08-23)

The hash-pinned descriptor
`demo:marshal-record-u32-list-lift/api.read@1.0.0/lift` remains closed for the
exact source/WIT pair `Reading { code: u32, payload: [u32] }`. Its measured
12-byte result area, capacity `3`, accepted lengths `0..3`, canonical `(i32)`
lift pointer, host/equivalence evidence, and fixtures 609-614 remain a separate
fixed-shape promotion. General list-record lift, async/resource lowering,
ownership syntax, and full G5c cutover remain pending.

### G5c private byte-list record lower descriptor status (2026-08-22)

The hash-pinned descriptor
`demo:marshal-record-byte-list-lower/api.write@1.0.0/lower` is closed for the
exact source/WIT pair `Writing { code: u32, payload: [u8] }`; both the
ordinary default route and explicit `--gc-wit-marshal` route use its measured
plan. Its root is 12 bytes with
`code@0`, `payload.ptr@4`, and `payload.len@8`; the canonical lower import is
`(i32, i32, i32)` and contains no GC reference. The host gate observes
`code=7`, `payload=[10,20,5]`, `result=42`, one callback, and one
allocation/free pair. The ARC/GC equivalence gate observes `42/17` result,
`17/17` stats, and `1/1` allocation/free counters. Async, locator, member,
field-order, element-type, and extra-field source fixtures fail before WAT.

This is fixed-shape evidence for a bounded default promotion, not general
list-record lowering. Arbitrary aggregates, async/resource lowering, ownership
syntax, and full G5c cutover remain pending; the migration inventory remains
`complete_rows=15 pending_rows=15` with exit 1.

### G5c private `list<u32>` record lower descriptor status (2026-08-22)

The hash-pinned descriptor
`demo:marshal-record-u32-list-lower/api.write@1.0.0/lower` is closed for the
exact source/WIT pair `Writing { code: u32, payload: [u32] }`. The ordinary
default route and explicit `--gc-wit-marshal` route share the measured 12-byte
root and canonical `(i32, i32, i32)` import. The lowerer copies the GC `u32`
array to temporary linear memory, calls `write` once, and frees it exactly
once. The host gate observes `code=7`, `payload=[10,20,30]`, `result=42`, one
callback, and one allocation/free pair; ARC/GC equivalence observes `42/17`
and `1/1` cleanup. Async, locator, member, order, element-type, and extra-field
fixtures fail before WAT.

This is a fixed-shape promotion, not general list-record lowering. Arbitrary
aggregates, async/resource lowering, ownership syntax, and full G5c cutover
remain pending; the migration inventory remains `complete_rows=15
pending_rows=15` with exit 1.

**G5a generic nested-path implementation note (2026-08-22):** the admitted
one-through-five managed-link `@get/@set` paths now share one fixed-capacity
`GenericNestedFieldPath` parser/emitter implementation. This is an internal
refactor only and does not add an inventory row or widen public admission;
sixth/deeper paths, producer expressions, async/resource paths, and general
host/WIT lowering remain pending under the existing boundaries.

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
| **G6.2** | `descriptor.read-directory` 及 record-stream 通用能力 | generic consumer 已覆盖注册的非 filesystem record streams；bounded producer、StreamMirror、private Result cancellation、HTTP payload cancellation、resource-list stream、私有 `do:variant-resource-stream-canonical@0.1.0`、动态 count `0..3` 的私有 `do:g6-2-c-min-dynamic-producer@0.1.0`、固定两批 `[111,222]`/`[333]` 的私有 `do:g6-2-batched-list-producer@0.1.0`，以及私有 `do:g6-2-scalar-list-producer@0.1.0` `stream<list<u32>>` producer 的 compiler-generated Component/Rust/Wasmtime gate 均已通过。scalar producer 固定 `ptr=64/len=68/stride=4/max=3`、stream capacity `1`、count `0..3`/invalid `4`，并保留 pending、sink error、early drop、转移前/后 cancellation、exactly-once list cleanup、empty `ResourceTable` 与 fail-closed 负例。D2 另关闭了私有 `descriptor.get-type`、`descriptor.sync`、`descriptor.get-flags`、`descriptor.stat`、`descriptor.sync-data`、`descriptor.metadata-hash`、`descriptor.metadata-hash-at`、`descriptor.stat-at`、`descriptor.open-at` 与 `descriptor.set-size` 十个有界方法；十者均固定 upstream WIT hash `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`，并分别通过独立 ABI、compiler admission 和 ready/pending/error/cancel cleanup gate；`sync-data`、`metadata-hash`、`metadata-hash-at`、`stat-at`、`open-at` 与 `set-size` 另通过 repeat 与 Store-disposal early-drop 边界。固定三字段 `ResourceTriple` compiler admission 已关闭，但仍缺一般 async helper/producer lease、任意 producer 表达式、通用 list、通用 borrowed/variant lowering、第七跳 forwarding、第七层或更一般 nested resource 字段、payload-bearing completion error 的更广形状、任意其它 filesystem async method 与通用 resource cancellation。Pinned `wasm-tools 1.255.0` 对含 `borrow<T>` 的 stream record 在 Component embed 阶段明确拒绝 | 保持所有 private bounded descriptor 的精确边界；扩展其他 producer/resource shape 前必须另立 design、probe 与 gate |
| **06.2** | 历史总项 | 已拆到 G2–G6；通用 consumer slice 已关闭，剩余边界由 **G6.2** 的后续 gates 承接 | 同上 |

**D2 general filesystem/HTTP recovery boundary (2026-08-11):**
`descriptor.get-type`, `descriptor.sync`, `descriptor.get-flags`,
`descriptor.sync-data`, `descriptor.metadata-hash`,
`descriptor.metadata-hash-at`, `descriptor.stat-at`, `descriptor.open-at`, and
`descriptor.set-size` remain ten
independently verified private
descriptors. Fresh ABI and Rust/Wasmtime gates passed with the pinned
filesystem WIT hash
`8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`; each
records its own measured import, Result/payload layout, descriptor drop,
ready/pending/error/cancel cleanup, and empty `ResourceTable`.
`read-via-stream`, `write-via-stream`, `append-via-stream`,
`read-directory`, path mutation, borrowed
descriptor methods, and metadata records other than `metadata-hash` and
`metadata-hash-at` remain
unadmitted because their
stream/future/resource/borrow/record ownership contracts have not each been
probed. The pinned HTTP service world's `client.send` and `handler.handle`
also remain separate service-world work; request/response resources, body
streams, payload errors, repeated calls, and cancellation require an exact
HTTP gate. See
`doc/superpowers/specs/2026-08-09-d2-general-filesystem-async-boundary-design.md`.
Recovery requires a new method-specific design, WIT hash, canonical WAT,
positive/negative fixtures, Component validation, and Rust/Wasmtime cleanup
matrix; do not infer a generic lowering from a neighboring bounded method.

**D2 bounded `descriptor.stat` early-drop boundary (2026-08-10):** the latest
`wasm-tools 1.255.0` ABI gate, exact opt-in Do compiler gate, and the
Rust/Wasmtime ready, pending, error, explicit-cancel, Store-disposal
early-drop, and repeat rows pass. The measured result area uses tag `frame+8`,
aligned payload `frame+16`, status `+112`, and callback subtask handle `+116`
in a 128-byte frame. The generated regular Component matches the
hand-authored ready/pending/error/repeat matrix. Wasmtime 47 explicitly states
that dropping a started `TypedFunc::call_concurrent` future does not cancel its
guest task; only dropping the whole Store hard-cancels it. The early-drop row
therefore reports one pending host-future drop with `descriptor-drops=0` and
`table-empty=not-applicable`, while the explicit `[async-lower][subtask-cancel]`
row proves Component-level cancellation and exact descriptor cleanup. This
closes only the private method-specific compiler slice; generic host-future
cancellation and general filesystem async remain blocked.

**D2 bounded `descriptor.sync-data` promotion (2026-08-10):** the current-only
ABI, opt-in compiler, and Rust/Wasmtime gates pass the private
`descriptor.sync-data` shape. The measured import is `(i32,i32) -> i32`, the
task-return is two `i32` words, and the Result is `unit | error-code`; fixture
`511` passes while `512`-`515` reject before WAT. Ready, pending, error,
explicit cancel, repeat, and Store-disposal early-drop rows pass. Early-drop
is explicitly `table-empty=not-applicable` with `descriptor-drops=0`; this is
not generic host-future cancellation. General filesystem async, external
HTTP, and public ownership syntax remain blocked.

**D2 bounded `descriptor.metadata-hash` promotion (2026-08-10):** the
current-only ABI, opt-in compiler, and Rust/Wasmtime gates pass the private
`descriptor.metadata-hash` shape. The measured import is `(i32,i32) -> i32`,
task-return is `(i32,i64,i64)`, and the Result payload is
`metadata-hash-value { lower: u64, upper: u64 } | error-code`; fixture `516`
passes while `517`-`519` reject before WAT. Regular/cancel WIT mirror hashes
are `6976359b3a4813d6771b3ef9a7fdcfb2ee9323e70c33b9ac7d6b628519fecfed` /
`b6e98cf2ae6f76e105f53c7ea09666b1c5684d33edb9838d034862a27b09f5c3`, and
the compiler template hash is
`f51c82887174a7ed1adf95a1cbe0e333f80a487962a2a8478334ca9750933b6b`.
Ready, pending, error, and repeat pass in the generated Component/Rust gate;
explicit cancel and Store-disposal early-drop remain hand-authored oracle
rows. This closes only the private method-specific target. Generic filesystem
async, external HTTP, and public ownership syntax remain blocked.

**D2 `descriptor.metadata-hash-at` bounded promotion (2026-08-11):** the
current `wasm-tools 1.255.0` ABI, exact `--p3-async-component` compiler
admission, generated Component, and Rust/Wasmtime matrix pass for the mixed
`path-flags + string` method. The measured import is
`(i32,i32,i32,i32,i32) -> i32` in the order
`descriptor, path-flags, path-ptr, path-len, result-area`; task-return remains
`(i32,i64,i64)`, result payload is
`metadata-hash-value { lower: u64, upper: u64 } | error-code`, and descriptor
drop is `[resource-drop]descriptor (i32) -> nil`. Regular/cancel mirror hashes
are `95e24b70eeed89407706c18a6e4cd13a8bc4dce72d1e56638436b03287d23412` /
`aca9c5933786a00a2dd20b1ad1ddbb6d0a79ab5b3bdbd5bd61e14b100a3b6e0a`.
Fixture `520` passes; `521`-`529` reject before WAT for unregistered,
signature, topology, record, and async-root drift. The compiler template hash
is `6056d1e6f42d6ab4edce60e2bb1ef61f358bfd6d03e6aa1e3c35daf08672713f`.
The Rust host copies the UTF-8 path into an owned String before returning its
future; ready/pending/error/cancel/early-drop/repeat rows pass with exactly-once
live-Store cleanup and the documented Store-disposal boundary.
Generic filesystem async, external HTTP, and public ownership syntax remain
blocked.

**D2 `descriptor.set-size` bounded promotion (2026-08-11):** the current-only
ABI, exact `--p3-async-component` compiler admission, generated Component, and
Rust/Wasmtime mutation/cancellation matrix pass for the private
`wasi:filesystem/types@0.3.0-rc-2025-09-16 / descriptor.set-size` shape. The
measured import is `(i32,i64,i32) -> i32` in the order
`descriptor, size, result-area`; task-return is `(i32,i32)`, the result is
`unit | error-code`, and descriptor drop is `[resource-drop]descriptor`.
Regular/cancel mirror hashes are
`f09241f8fcf4b94e1a684553b439b592f254c83c7d23a3708930040a2324c3f4` /
`7030161e35a18fe40220cb2701864141a00a6c8d897cdfc8291839f2b742cc67`; the
compiler template hash is
`db09b4c2fe6f1f0a8c26f582759e9937249e352b6c852c40dc88ff753ce29385`; generated
WIT hash is
`201038081bc51c5aeae77eca36fc4f873522e2357c2ec25c222e3ce31f486bef`.
Fixture `552` passes; `553`-`563` reject before WAT. Ready/pending/error,
explicit cancel, Store-disposal early-drop, repeat, and generated
ready/pending/error/repeat rows pass with exactly-once live-Store cleanup.
Cancel preserves the issued file-size mutation and never claims rollback;
generic filesystem async, external HTTP, and public ownership syntax remain
blocked.

**D2 `descriptor.stat-at` bounded promotion (2026-08-11):** the current
`wasm-tools 1.255.0` ABI, exact `--p3-async-component` compiler admission,
generated Component, and Rust/Wasmtime matrix pass for the measured
`path-flags + string` method. The import is
`(i32,i32,i32,i32,i32) -> i32` in the order
`descriptor, path-flags, path-ptr, path-len, result-area`; task-return is
`(i32,i32,i64,i64,i32,i64,i32,i32,i64,i32,i32,i64,i32)` and the Result payload
is `descriptor-stat | error-code`. Fixture `530` passes; `531`-`539` reject
before WAT. Regular/cancel WIT mirror hashes are
`92afa427efedc960fd60ce2edbd3ced26521225ae8857377554956646a1059bd` /
`420fb95fae7505e568414e55f19dc2f89f5b32e015e8d999166e38b48e4a4a49`; the
compiler template hash is
`4503fa7634560c66463f96ac142bcc7cfb7b90cca93a8b705c1d1eb05040ddef`.
The Rust host observes the copied relative path and `symlink-follow` flag;
ready/pending/error/cancel/Store-disposal early-drop/repeat rows pass with
exactly-once cleanup. This closes only the private method-specific target;
generic filesystem async, external HTTP, and public ownership syntax remain
blocked.

**D2 `descriptor.open-at` bounded promotion (2026-08-11):** the current
`wasm-tools 1.255.0` ABI, exact `--p3-async-component` compiler admission,
generated regular Component, and Rust/Wasmtime ownership/cancellation matrix
pass for the indirect six-word method shape. The import is
`[async-lower][method]descriptor.open-at: (i32,i32) -> i32`; the parameter
block is `descriptor, path-flags, path-ptr, path-len, open-flags,
descriptor-flags`, task-return is `(i32,i32)`, and the Result payload is
`descriptor | error-code`. Regular/cancel WIT mirror hashes are
`1e5f9131387015c4e650a64e02bb9f112d8266f4755aa6b605af038407ef807a` /
`1c48fba03b569d91617efd834232fcccc553ca3001ffb0e0834b4134f93e4f52`;
the compiler template hash is
`a05a8e90cfb553658a8a5337e026a0fa1304aa42f0b33558a3d6ecfc17623201`.
Fixture `540` passes; `541`-`551` reject before WAT. The Rust host copies
the UTF-8 path before returning its future, creates/drops a child descriptor
only on `Ok`, and passes ready, pending, error, cancel, Store-disposal
early-drop, and repeat rows with exactly-once live-Store cleanup. The cancel
probe leaves the borrowed parent for the unified termination path; immediate
parent drop after subtask cancellation fails Wasmtime's borrowed-resource
check. Cancellation remains cleanup-only and does not claim host rollback.
Generic filesystem async, external HTTP, and public ownership syntax remain
blocked.

**G6.2 next-shape stop (2026-08-09, `can_skip=true`):** 动态 count `0..3`、
固定两批次 private producer 与 pure-scalar `stream<list<u32>>` producer 均已形成独立
design、pinned WIT/WAT、registry/sema admission、compiler adapter、正负 fixture 和
Component/Rust/Wasmtime cleanup gate；这些 bounded shape 已关闭。下一 shape 仍不得从它
泛化：没有新的 pinned WIT/WAT、canonical layout 和 ownership matrix 时不新增 descriptor、
不泛化现有 lowering。
恢复条件是先提交新的 bounded design、pinned probe、正负 fixture、
Component/Rust/Wasmtime cleanup gate，再重新进入 G6.2。

**Generic ABI v2 borrow capability matrix (historical baseline, 2026-08-06):**
the then-pinned `wasm-tools 1.254.0 (bb58fdf91 2026-07-20)` accepted `component embed` plus
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
is therefore confirmed by the current-only 1.255.0 matrix, not an active
dependency on the historical binary.

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
sidecar identity, compiler WAT markers, current `wasm-tools 1.255.0` parsing
and async assembly/validation, target isolation, and
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

**General async-call lowering ABI boundary (2026-08-07, current-only refresh):**
the independent probe `examples/p3-runtime/test_async_call_component_probe.sh`
was rerun with current `wasm-tools 1.255.0 (76e20611d 2026-07-30)` (SHA-256
`6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`). Core
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
passes current `wasm-tools 1.255.0` assembly/validation, verifies inline and
child state markers, two host call sites, no helper export, and v1 rejection
before WAT. The Rust/Wasmtime gate
`test_rust_async_call_component.sh` passes `ready`, `pending`, `cancel-inline`,
and `cancel-child`: ready/pending each observe two completions and two drops;
`cancel-inline` observes one pending drop; `cancel-child` observes one
completed and one pending drop. Both cancellation modes have no duplicate drop
and an empty `ResourceTable`.

The opt-in analyzer rejects helper parameters other than the exact single
`u32` scalar shape, payloads, multiple live children, a second inline call, and
nested helper calls as
`UnsupportedP3AsyncCallComponent`; the normal default build still reports
`AsyncLoweringUnavailable` for those fixtures because it does not select the
opt-in target. Generic async-call composition, arbitrary producer expressions,
payload/Stream/resource/list futures, public ownership syntax, general
filesystem async, and D2 host I/O remain pending. Independent guest child-task
creation remains blocked by the pinned Component ABI described above.

**Bounded inline scalar-argument checkpoint (2026-08-09, green):** the same
root-owned local-frame target now admits exactly one leading
`helper(7)` followed by `child Future<nil> = @async(helper(7))` when
`helper(value u32) -> nil`. The scalar slot is frame offset `12` in a 20-byte
frame and is reused sequentially by the inline and child phases; no helper WIT
export or new host descriptor is emitted. The dedicated
`test_do_async_call_inline_scalar_argument.sh` gate passes pinned
`wasm-tools 1.255.0` assembly, and `test_rust_async_call_component.sh` passes
ready/pending/cancel-inline/cancel-child with exactly-once cleanup and an empty
`ResourceTable`. `u32` is a probe boundary, not the final scalar type set.
Additional parameters, non-literal expressions, payload/resource/stream/list
values, general async-call composition, ownership syntax, and independent guest
child tasks remain pending.

**Private async host scalar-argument compiler promotion (2026-08-09, green):**
the opt-in `--p3-async-host-arg-component` target now admits exactly one
registered `@host_async_func` binding for
`do:async-call-arg-probe/host@0.1.0 / work`, one `u32` helper parameter, and the
root literal `@async(helper(7))`. The generated WIT hash remains
`b9f5f8355e87231317ec05cccf692ee465c6f339bd509640aedc196e58f81e61`; the
compiler emits the measured 20-byte root frame with argument slot `+12`.
Negative `compile_err/490`–`497` fixtures reject descriptor, marker, type,
arity, topology, dynamic-root, and payload drift before WAT. The current Component
assembly/validation pass, and the generated Rust/Wasmtime gate passes ready,
pending, and cancel with argument `7`, exactly-once Future cleanup, and an
empty `ResourceTable`. This closes only the private bounded compiler shape;
arbitrary producer expressions, payload/resource/list/stream futures, borrowed
values, root hard-cancel, general filesystem/HTTP async, and public
`own<T>`/`borrow<T>`/`ref<T>` remain pending.

本轮执行复核（2026-08-07）重新运行了六跳 forwarding/任意 producer 边界、borrowed stream rejection 与 `p3_async_manifest`（74/74）；三个 gate 均保持预期拒绝/通过。同步确认了 descriptor-bounded StreamMirror 六模式、默认 Bun 回归 `pass=1116 fail=0 skip=3`、WASM 回归 `pass=1118 fail=0 skip=3`（WASM smoke `6/6`）和 ReleaseSmall smoke 通过；nested lowering、borrowed rejection、G6.2 boundary 与完整 compiler/Wasm 矩阵均保持绿色，未新增 descriptor 或 lowering。

**规则**: 固定一至三条目 read-directory slice、generic consumer slice、multi-owned、多个顶层 nested-owned resource path 以及一层/两层/三层/四层/五层/六层 nested-owned resource consumer slice、注册的单读 `stream<list<resource-entry>>` private slice、bounded scalar producer slice、受限（最多六跳 forwarding）helper-mediated producer-lease slice、固定/参数化 `u64` countdown producer slice、参数化 helper producer slice及其六跳 forwarding、三种 typed 参数受限重排形状与 branch-selected terminal slice 均已可用；无对应 producer-lease/resource gate 时，不绕过上述边界扩 WASI async/stream codegen。

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

**G6.3 已关闭 (方案 B)**: sockets `tcp/udp-socket.create|bind|drop` 可 lower; 地址为 dual concrete + `IpSocketAddress = V4|V6` payload enum; resource shell + 粗粒度 `TcpError`/`UdpError`; stdlib `lib/tcp.do` / `lib/udp.do` / `lib/net.do`; compiler-generated Component 与 Rust/Wasmtime TCP/UDP loopback smoke 已通过（含 create/bind failure cleanup）；见 `compile_ok/291`–`294` 与 `doc/superpowers/specs/2026-07-13-g6-3-sockets-scheme-b-design.md`。D2 总项仍保持 in progress。

---

## 2. 待处理 (pending) — 语言 / codegen 已知缺口

### P2. GC nested aggregate depth and producer boundary

当前 typed-GC synchronous admission 已覆盖 direct-local 的一层、两层、三层、
四层和五层 managed-struct field path，并有 compiled/Wasmtime/ARC-GC
equivalence evidence。第六个 managed segment、更深路径、任意 producer
expression、async/resource 和 host/WIT 仍保持 fail-closed；不得把这条 bounded
slice 解释为 G5c 或 full GC cutover。

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
| D2 | 完整 WASI/Component 运行时 | 已增加真实本地 filesystem preopen/open-at/sync、read-directory stream、CLI stdin pipe，以及 socket create/bind/drop 的 compiler-generated Component/Rust/Wasmtime smoke；私有 `descriptor.get-type`、`descriptor.sync`、`descriptor.get-flags`、`descriptor.stat`、`descriptor.sync-data`、`descriptor.metadata-hash`、`descriptor.metadata-hash-at`、`descriptor.stat-at` 与 `descriptor.open-at` 各自通过 pinned ABI、compiler/runtime gates；仍缺通用 filesystem async lowering 与 external-network HTTP，故 D2 总项保持 in progress |
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

- **Task 6 GC-first runtime cutover (2026-09-09)**: 普通编译入口已切换到
  `codegen_runtime_api.zig` 的 Wasm GC-only route；ARC runtime/legacy emitter 只
  由显式 test-only `gc_arc_equivalence_oracle.zig` 引用。post-cutover ARC scan 为
  `rows=49 matches=480 unclassified=0 normal_route_matches=0`，生产依赖闭包为
  `modules=153 forbidden=0`，GC default gate 为 `87 fixtures`，semantic-equivalence
  为 `26 rows; 0 pending`。默认及 `RUN_WASM=1 RUN_GC_CORE=1` harness 均为
  `14/14 steps; 53/53 tests`，`zig test main.zig` 为 `1561/1561`，ReleaseSmall/
  release smoke 通过。该项不关闭 `complete_rows=15 pending_rows=15` capability
  inventory，也不开放 public `own<T>`/`borrow<T>`/`ref<T>` 或通用
  async/map/producer/resource lowering。

- pure-scalar struct 作为 Tuple storage 嵌套子槽 (`compile_ok/272`, `ok/192`; 局部名 `$pair.0.x`)
- managed/`text` 作为 Tuple **直接叶子** storage + path chain (`compile_ok/270`–`271`)
- **P1** 含 managed 字段的 struct 作 Tuple 直接子槽: 句柄叶子 + storage pack ARC (`compile_ok/273`, `ok/193`; 不拍平 `Cell` 字段). 这是 ARC transition implementation evidence; 后续 GC migration 必须保持同一源码值语义与 `Cell` 不拍平边界。
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
- **G6.2 scalar-list producer**: private `do:g6-2-scalar-list-producer@0.1.0`
  admits only `StreamWriter<[u32]> -> Result<nil, ProducerError>` plus the fixed
  `produce(count u32)` topology. Its independent scalar adapter uses
  `ptr=64/len=68/stride=4/max=3`, stream capacity `1`, runner-only controls
  `10..14`, and passes count `0..3`, invalid `4`, pending/error/drop and both
  cancellation positions with exactly-once list release and an empty
  `ResourceTable`; fixtures `483`-`489` reject descriptor/element/count/sink/body/
  payload/result drift before WAT. Generic `list<T>`, arbitrary producer
  expressions, borrowed async payloads, and public ownership remain pending.
- **G6.2 parameterized six-hop forwarding**: the existing
  `StreamWriter<u8>` descriptor now admits exactly six static helper transfers.
  The analyzer, generated Component, seventh-hop negative, and Rust/Wasmtime
  `count=0/1/3`, `value=90`, pending/ready/error/early-drop/cancel matrix pass
  with one callback, one stream drop, empty `ResourceTable`, and exactly-once
  cleanup. This does not admit arbitrary producers, seventh-hop forwarding,
  borrowed/list/variant payloads, or general resource lowering.
- **G6.2 direct owned-record producer**: the private
  `do:g6-2-owned-record-producer@0.1.0` descriptor admits only
  `StreamWriter<ResourceEntry>` with one owned `Ticket` field. The four-byte
  record uses offset `0`, stream capacity `1`, and ticket seed `111`; canonical
  ABI, Do/Component, Rust/Wasmtime, and canonical/generated lifecycle gates pass
  all ten modes with exactly-once cleanup and an empty `ResourceTable`. This is
  a separate Component lifecycle comparison, not an ARC/GC matrix row; generic
  producer/resource, borrowed/list/variant, and public ownership remain pending.
- **G6.2 fixed three-owned-field record producer**: the private compiler route
  admits exactly `do:g6-2-owned-record-triple-producer@0.1.0` behind
  `--p3-async-component`. Its WIT hash is
  `73fd57dc8f34f13023b48f2b82e439b212eab52192886f0d07a37d86e63658b1`;
  `ResourceTriple` is a 12-byte, alignment-4 record with
  `left/middle/right: own<ticket>` at offsets `0/4/8`, a capacity-one stream,
  and producer inputs `(mode,left-seed,middle-seed,right-seed)` as four `u32`
  words. The manifest/source matcher, generated WAT/WIT, Component validation,
  13 fail-closed compiler fixtures (`712`-`724`), Rust/Wasmtime ten-mode
  lifecycle, and canonical/generated parity gates pass. Valid rows observe
  `3/3` ticket cleanup, `repeat` observes `6/6`, cancellation/early-drop each
  observe one cancel and pending-future drop, invalid creates no resources, and
  every mode leaves `table-empty=true`. This private route is not an ARC/GC
  equivalence row or inventory row; generic/arbitrary producers,
  borrowed/list/variant payloads, general async/resource lowering, and public
  `own<T>`/`borrow<T>`/`ref<T>` syntax remain pending.
- **G6.2 nested-owned-record producer**: the private compiler route admits only
  `do:g6-2-owned-record-nested-producer@0.1.0` / `consume-via-stream` with
  `Outer { inner: Inner }` and `Inner { ticket: own<Ticket> }`. The pinned WIT
  hash is
  `9662440709b01044544d4c4350f3e6f783a8f06aaa5c884a96a1e43a935a7543`;
  outer layout is 4 bytes/alignment 4, semantic path `inner.ticket` is the
  flattened `i32` leaf at offset `0`, source ABI is `(i32) -> (i32)`, stream
  capacity is `1`, and seed is `111`. Independent ownership bits
  `guest=1/transferred=2` release the nested leaf exactly once before or after
  transfer. The manifest/source matcher, generated WAT/WIT, Component
  validation, 21 negative fixtures (`725`-`745`), Rust/Wasmtime ten-mode
  lifecycle, and canonical/generated parity gates pass; cancellation/early
  drop has one cancel and pending-future drop with zero completion, repeat is
  `[111,111]`, invalid creates no resources, and every row leaves
  `table-empty=true`. This is closed private evidence, not an ARC/GC matrix or
  inventory row; public ownership syntax, generic/arbitrary producer lowering,
  borrowed/list/variant payloads, and general async/resource lowering remain
  pending.
- **G6.2 general producer/resource contract consolidation (2026-09-04)**: the
  immutable internal `ProducerContract` now normalizes measured source/sink,
  payload layout, ownership paths, transfer commit, and terminal cleanup for
  the nine already-private routes: direct record, fixed pair, parameterized
  pair, triple, nested, list-resource, dynamic-list, batched-list, and
  scalar-list. The consolidated gate passes `routes=9`,
  `canonical-parity=5`, `lifecycle=9`, and `table-empty=true`; the existing
  WAT/WIT/template/hash/marker bytes and route-specific diagnostics remain
  unchanged. Four negative fixtures reject arbitrary expression, shared lease,
  borrowed async payload, and hop overflow before WAT. This closes internal
  reuse only; public `own<T>`/`borrow<T>`/`ref<T>`, generic/arbitrary producer
  lowering, borrowed/list/variant async payloads, unmeasured shapes, and the
  GC inventory rows remain pending.
- **Private async `map<u32,u32>` compiler admission (2026-09-09)**: the
  `--p3-async-map-component` route admits only the pinned
  `demo:map-async-probe/api@0.1.0.submit` shape with `HashMap<u32,u32>`, two
  literal pairs `[7,70]` and `[9,90]`, and one helper/root await topology. Its
  manifest/hash, fixed Core `(i32 ptr, i32 len, i32 result_area) -> i32` shape,
  generated WAT/WIT snapshots, copy/overwrite/result/cleanup markers, five
  WAT-before-rejection negatives, Component validation, and Rust/Wasmtime
  `ready/pending/cancel/drop` lifecycle all pass. The default route still
  returns `AsyncLoweringUnavailable` with no artifacts. Generic async map,
  other key/value combinations, Stream cross-poll buffers, arbitrary producers,
  and public ownership syntax remain pending.
- **Bounded async-call internal consolidation (2026-08-09)**: the five
  admitted child/inline/host-scalar forms now share private validated frame and
  cleanup facts only. Planner admission remains separate and emitter templates
  remain byte-identical. Differential pins are WAT
  `bec944caece221821f43a79041e2989281f9f9b90d59547f9348ef641e1b2e03`,
  `7402916ce09060ca63e792498dc1523923b6a1545004d91c61f1a037496f2fc1`,
  `0e362d90a30c38de5e5900783b7474ddac05292f50c402a20786c0a940598dcc`,
  `7edf6a66095c3c24b8c5440ebcad5a7f5dfcc5fea3c943a8e4d28453bb96fe83`,
  `e9e2330a75430b569b538d15d676d92492c952f89c5cc135a38343670da01553`,
  with generic WIT `ecf47e1e33b3a0d14761a1341f3b749f4ba072051c018083db2d5cda356c101f`
  and host-scalar WIT
  `b9f5f8355e87231317ec05cccf692ee465c6f339bd509640aedc196e58f81e61`.
  Component current-only assembly, Rust/Wasmtime ready/pending/cancel
  cleanup, `zig test main.zig` `336/336`, default regression
  `pass=1177 fail=0 skip=3`, and ReleaseSmall smoke are green. This closes
  only private internal reuse; generic async-call lowering, arbitrary producer
  expressions, payload/resource/list/stream futures, borrowed values, root
  hard-cancel, and public `own<T>`/`borrow<T>`/`ref<T>` remain pending.
- **D2 filesystem `descriptor.get-type`**: the private pinned method passed
  hand-authored/generated Component assembly and Rust/Wasmtime
  ready-directory/regular, pending, error, and cancel cleanup gates; fixtures
  `459`-`461` reject descriptor/result/borrowed-payload drift. General
  filesystem async methods and public ownership remain pending.
- **D2 filesystem `descriptor.sync`**: the private pinned method passed
  current `wasm-tools 1.255.0` ABI assembly/validation with
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
  current `wasm-tools 1.255.0` ABI assembly/validation with upstream WIT
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
3. D2 当前只推进已授权的本地 file/dir/CLI smoke 与已关闭的私有 `descriptor.get-type`/`descriptor.sync`/`descriptor.get-flags`/`descriptor.stat`/`descriptor.sync-data`/`descriptor.metadata-hash` slices；socket/general filesystem async/external HTTP 的扩展须另立 target/design，其他 deferred 项仍需单独授权
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

The bounded resource Result cancellation slice now compares the compiler-
generated GC Component with a hand-authored linear Component through the same
Rust/Wasmtime host and requires identical terminal observations. This closes
the backend-neutral G5b cancellation oracle for that one resource shape; it
does not close ordinary async lowering or G5c default routing.

These bounded slices do not make arbitrary generated WIT async lowering,
generic `Future<T>`/`Stream<T>` payloads, resources,
aggregate await, timeout, multi-root scheduling, public ownership syntax, or
ordinary `do build` async programs complete. Unsupported shapes continue to
return `AsyncLoweringUnavailable`.

### G5b bounded Future frame equivalence (2026-08-21)

The pinned `two-await-component.do` Future frame slice now has independent
backend-neutral evidence. The generated GC frame/table Component and a
hand-authored linear-memory frame Component are assembled from the same WIT and
executed by the same Rust/Wasmtime runner. The gate
`examples/gc-p3-runtime/test_gc_async_frame_equivalence.sh` passes with
`wasm-tools 1.255.0`; both paths observe `pending-polls=4`,
`external-wakes=4`, and `completions=4`.

This closes only `future_stream_frames` G5b for two sequential `Future<nil>`
awaits. Generic async lowering, arbitrary producers, `Stream<T>`, ordinary GC
sync async admission, resource shapes beyond their own bounded rows, and G5c
default routing remain pending.

用户说 `go` / `next` 时以 `doc/start_here.md` §6 为准, 细节以本文件为准。

### G5c B descriptor-manifest status (2026-08-20)

Closed for the bounded random `u64 -> list<u8>` lift: checked-in source and
world-fragment provenance, exact hash validation, parser/member/signature and
versioned Component-import comparison, unsupported-shape rejection, and the
mutated-source negative gate are green. The default host/WIT path is unchanged
and remains ARC-backed. `host_wit_marshalling`, general WIT aggregates,
async/resource descriptors, ARC/GC equivalence inventory, and G5c cutover are
still pending; no public ownership or new async syntax is admitted by this
gate.

### G5c C8 mixed scalar-record lift status (2026-08-20)

The seventh manifest descriptor is independently closed for the bounded
`reading { code: u32, count: u64, status: s64 }` lift. The 24-byte/alignment-8
layout, result-area canonical `(i32)` import, source-hash drift rejection,
Component assembly, Rust/Wasmtime host execution, and GC/linear-memory
equivalence (`37/37`) are green. This remains private evidence: the default
host/WIT route is ARC-backed, nested/general aggregates and async/resource
paths remain unadmitted, and G5c cutover is still pending.

### G5c C9 indirect scalar-record lower status (2026-08-20)

The eighth manifest descriptor is independently closed for the bounded
17-field `u64` record lower. The 136-byte/alignment-8 indirect layout,
canonical `(i32)` record-area import, source-hash drift rejection, Component
assembly, Rust/Wasmtime host execution (`result=42`, `write-calls=1`), and
GC/linear-memory equivalence (`42/42`, `1/1`) are green. This remains private
evidence: layouts beyond the pinned shape, the default host/WIT route,
nested/general aggregates, async/resource paths, and G5c cutover remain
pending.

### G5c C10 nested scalar-record lift status (2026-08-20)

The ninth manifest descriptor is independently closed for the pinned
two-level `reading { header: header, status: s64 }` lift. The nested `header`
layout is 16 bytes/alignment 8 and the outer `reading` layout is 32
bytes/alignment 8 with `status` at offset 16; the canonical import is one
`(i32)` result-area pointer. Source-hash and measured-depth rejection,
Component assembly, Rust/Wasmtime host execution (`sum=37`), and GC/linear-
memory equivalence (`37/37`) are green. This remains private evidence:
deeper/general aggregates, nested lower, the default host/WIT route,
async/resource paths, and G5c cutover remain pending.

### G5c C13 three-level nested scalar-record lift status (2026-08-20)

The manifest-backed descriptor
`demo:marshal-record-nested-lift-deep/api.read@1.0.0/lift` is independently
closed for the pinned three-level `reading { detail: detail, tail: s64 }`
lift. The canonical result-area measurement is `header=16`, `detail=24`, and
`reading=32` bytes with leaf offsets `code@0`, `count@8`, `status@16`, and
`tail@24`; the import remains one `(i32)` result-area pointer. Source-hash and
measured-shape rejection, Component assembly, Rust/Wasmtime host execution
(`sum=42`), and GC/linear-memory equivalence (`42/42`) are green. This remains
private evidence: deeper/general aggregates, indirect nested layouts, the
default host/WIT route, async/resource paths, and G5c cutover remain pending.

### G5c C14 four-level nested scalar-record lift/lower status (2026-08-20)

The manifest-backed descriptors
`demo:marshal-record-nested-lift-deeper/api.read@1.0.0/lift` and
`demo:marshal-record-nested-lower-deeper/api.write@1.0.0/lower` are independently
closed for the pinned four-level `reading.detail.header.leaf` / `writing.detail.header.leaf`
scalar tree. The measured layouts are `leaf=16`, `header=24`, `detail=32`, and
`reading=40` bytes with flattened leaf offsets `code@0`, `count@8`, `status@16`,
`marker@24`, and `tail@32`; lower uses `(i32, i64, i64, i64, i64)` and lift uses
one `(i32)` result-area pointer. Source-hash and shape rejection, Component
assembly, Rust/Wasmtime host execution (`sum=42`, `result=42`, one lower
callback), and GC/linear-memory equivalence (`42/42`, `1/1`) are green. This
remains private evidence: arbitrary/deeper/general aggregates, default
host/WIT routing, async/resource paths, and G5c cutover remain pending.
### G5c C15-C explicit compiler wiring status (2026-08-21)

The private opt-in
`--gc-wit-marshal demo:marshal-record-managed-lower/api.write@1.0.0/lower`
now dispatches the real `do build` entry point to the manifest-backed C15-B
route. CLI conflict checks, unknown-descriptor fail-closed behavior, generated
WAT Component validation with `wasm-tools 1.255.0`, compiler-output host
execution, and compiler-output ARC/GC equivalence are green. The observed
host values are `code=7`, `label=hello`, `write-calls=1`, `allocations=1`, and
`frees=1`; equivalence reports `1/1` for allocations, frees, and callbacks.

This closes only the explicit private compiler wiring for that descriptor. It
does not change the default `@host` route, which remains ARC-backed, and does
not admit general managed records, text/list aggregates, async/resource
lowering, public ownership syntax, or G5c full cutover.

### G5c C15-D private multi-managed-text lower status (2026-08-21)

The explicit descriptor
`demo:marshal-record-managed-lower-multi/api.write@1.0.0/lower` is green for
the single direct-root shape `writing { code: u32, label: string, note: string }`.
The measured 20-byte layout is `code@0`, `label.ptr@4`, `label.len@8`,
`note.ptr@12`, and `note.len@16`; the lower boundary is exactly
`(i32, i32, i32, i32, i32)`. Both text spans are copied through temporary
linear memory and freed after the host call, with no GC reference at the
canonical import.

Standalone and compiler host gates observe `code=7`, `label=hello`,
`note=world`, `write-calls=1`, `allocations=2`, and `frees=2`. Standalone and
compiler GC/ARC equivalence gates observe `allocations=2/2`, `frees=2/2`, and
`write-calls=1/1`. This evidence is private and opt-in only; it does not
remove the pending rows for general managed records, default host/WIT
routing, text/list aggregates, async/resource lowering, or G5c full cutover.

### G5c C16-A real source-level host boundary status (2026-08-21)

The private `--gc-wit-marshal` adapter now consumes the exact host-first fixture
`src/build/test/compile_ok/564_gc_wit_managed_record_host_boundary.do` and
validates its single synchronous `@host_func` against
`demo:marshal-record-managed-lower-multi/api.write@1.0.0/lower`. The admitted
shape is `Writing { code: u32, label: text, note: text }`, with exact locator,
member, one parameter, and `nil` result checks. The generated canonical lower
is `(i32, i32, i32, i32, i32)` for the measured 20-byte root, and no GC
reference crosses the boundary.

Compiler host and ARC/GC equivalence gates are green with
`code=7`, `label=hello`, `note=world`, one callback, two allocations, and two
frees (`2/2`, `2/2`, `1/1` equivalence). Async and locator-mismatch fixtures
fail before WAT, and the default build remains ARC-backed. This is a private
opt-in declaration gate only; general aggregate/text-list marshalling, default
host/WIT routing, async/resource lowering, ownership syntax, and G5c cutover
remain pending.

### G5c C16-B fixed-descriptor host validator expansion status (2026-08-21)

The private `--gc-wit-marshal` adapter now applies descriptor-specific source
validation to both the C15-B and C16-A fixed descriptors. C15-B admits only
`Writing { code: u32, label: text }` with locator
`demo:marshal-record-managed-lower/api@1.0.0`, member `write`, one parameter,
and `nil` result; C16-A keeps its separate three-field specification. The
validator does not infer arbitrary Do-to-WIT types and rejects unknown,
async, mismatched, duplicate, extra, or shape-drifted declarations before WAT.

C15-B compiler host/equivalence gates and focused validator tests are green.
The new negative/default gate confirms async and locator mismatch leave no WAT
artifact, while the ordinary host-first fixture remains ARC-backed. This is
still private opt-in evidence; general managed-record/text-list marshalling,
default host/WIT routing, async/resource lowering, ownership syntax, G5c
cutover, and the inventory rows remain pending.

### G5c C16-C private managed-record lift compiler boundary status (2026-08-21)

The explicit compiler route now admits the fixed C15-A lift descriptor
`demo:marshal-record-managed-lift/api.read@1.0.0/lift` for exactly
`Reading { code: u32, label: text }`. Its manifest-backed result area is
12 bytes (`code@0`, `label.ptr@4`, `label.len@8`), and the canonical import is
`(func (param i32))`; the generated wrapper copies the host text into GC
values and returns the checked probe value `12`.

Focused validator/emitter tests are `3/3` green. Compiler host execution and
ARC/GC equivalence are green (`12` and `12/12`); async and locator-mismatch
fixtures fail before WAT, and a default build remains ARC-backed. This closes
only the private C16-C compiler boundary. General aggregate inference, default
host/WIT GC routing, async/resource lowering, public ownership syntax, G5c
cutover, and all migration inventory rows remain pending.

### G5c C16-D private multi-managed-field lift compiler boundary status (2026-08-21)

The explicit compiler route now admits the fixed descriptor
`demo:marshal-record-managed-lift-multi/api.read@1.0.0/lift` for exactly
`Reading { code: u32, label: text, note: text }`. Its manifest-backed result
area is 20 bytes (`code@0`, `label.ptr@4`, `label.len@8`, `note.ptr@12`,
`note.len@16`) and its canonical import is `(func (param i32))`; the generated
wrapper copies both host strings into GC values and returns the checked probe
value `17`.

Focused tests are `3/3` green. Compiler host execution and ARC/GC equivalence
are green (`17` and `17/17`); async and locator-mismatch fixtures fail before
WAT, and a default build remains ARC-backed. Full Zig/integration/ReleaseSmall
verification is green. This closes only private C16-D opt-in evidence; general
aggregate inference, default host/WIT routing, text/list records beyond the
pinned shape, async/resource lowering, ownership syntax, G5c cutover, and all
15 migration inventory rows remain pending.

### G5c manifest-driven bounded compiler route closeout (2026-08-21)

The four private synchronous managed-record routes now use manifest-owned
`measured_layout` data and a WIT-derived source-level host boundary. The route
is explicit `--gc-wit-marshal` opt-in; ordinary `@host` remains ARC-backed and
canonical imports reject GC references. Eight compiler host/equivalence gates
and four negative/default gates pass, with full Zig `598/598` and regression
`pass=1279 fail=0 skip=3`; ReleaseSmall, release smoke, and pinned
`wasm-tools 1.255.0` also pass. The inventory remains intentionally pending at
`complete_rows=15 pending_rows=15` with exit 1. This closes only the bounded
private route; general aggregate, async/resource, ownership syntax, and full
G5c cutover remain pending.

### G5c residual gate coverage (2026-08-22)

The baseline residual gate now invokes the verified bounded Future G5b
GC/linear equivalence script before the manifest and residual checks. A focused
static wiring test protects that coverage, and ReleaseSmall smoke executes the
test. This changes verifier coverage only; it does not admit ordinary async,
Stream, general host/WIT routing, or G5c cutover.

### G5c C14 default four-level synchronous host/WIT route (2026-08-22)

The ordinary synchronous `@host_func` route now admits the exact C14 lift and
lower descriptors for the four-level scalar tree
`reading.detail.header.leaf` / `writing.detail.header.leaf`. It recursively
validates the resolved Do record children, field order and scalar types,
synchronous `@host_func` shape, and exact WIT locator/member before WAT
emission. Lift keeps the canonical `(i32)` result-area import; lower keeps
`(i32, i64, i64, i64, i64)`; neither boundary carries a GC reference.
The explicit `--gc-wit-marshal` route remains private measured coverage.

The default host, equivalence, and negative gates pass, as do the focused `3/3`
emitter tests. Async, locator/member, and nested-shape drift reject before WAT
and leave no artifact. This closes only the exact C14 default route; arbitrary
aggregates, async/resource lowering, ownership syntax, G5c cutover, and the
15 pending migration rows remain pending.

### G5c bounded mixed scalar-record lower default route (2026-08-22)

The ordinary synchronous `@host_func` route now admits the exact
`demo:marshal-record-mixed-lower/api.write@1.0.0/lower` descriptor for
`Writing { code: u32, count: u64, status: i64 }`. The measured record is
24 bytes with alignment 8; its canonical import is `(i32, i64, i64)` and no
GC reference crosses the boundary. The host, compiler-vs-ARC equivalence, and
negative gates pass with `result=42` and `write-calls=1/1`; async, shape, and
member drift reject before WAT, while an unadmitted host fixture retains ARC.

This closes only the fixed bounded descriptor. General aggregates, text/list
record lower, async/resource lowering, ownership syntax, full G5c cutover, and
the 15 pending migration rows remain pending.
