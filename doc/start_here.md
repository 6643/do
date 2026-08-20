# 下次启动入口

这是当前主线的接手入口。状态以本文为准; 计划摘要见 `doc/master_plan.md`; 近期变更见 `CHANGELOG.md`。不保留向后兼容旧路径或历史流水账。

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
| GC-first memory migration | G5a 已完成 parsed fixed-index + 参数化 `[u8] @set` + 全部当前标量 list literal/update（`[bool]`、`[i8]`、`[i16]`、`[i32]`、`[i64]`、`[u16]`、`[u32]`、`[u64]`、`[isize]`、`[usize]`、`[f32]`、`[f64]`）+ bounded text/list/struct/tuple/union/generic/import slices、直接局部对象的一层、两层与三层 nested managed-struct `@get/@set`，以及 `--p3-wait-for-component` 的 bounded `Future<nil>` GC frame/table slice 和 private resource `Result` terminal Component gate；G5b 已完成当前 admitted synchronous 的 24 行 ARC/GC executable equivalence matrix，non-CLI probes 验证旧值保持、新值更新和 root 保活。Task 3 已将默认同步 pipeline 的已准入 managed candidates（含 bounded synchronous `defer`、`return nil` no-result cleanup、推断出的 `text` body binding、推断出的 `[u8]`/`[u32]` body storage `@put`，以及 body-only managed-struct storage ctor/field update）接到 typed GC/root 输出，GC path 过滤旧 storage compiler locals；host/WIT、普通 GC sync async 和 Stream 仍 ARC fallback；root/storage conversion、async/resource G5b/G5c、G5c full cutover 与旧 ARC expectation 迁移未完成。 |
| GC-first latest bounded producer slice | `nested-byte-list-put.do` 与 `managed-struct-list.do` 分别覆盖精确的 `[[u8]]`、`[Box]` 单值 `@put` producer；`nested-field-path.do`、`two-level-nested-field-path.do` 与 `three-level-nested-field-path.do` 覆盖一层、两层和三层 nested managed-struct scalar field update，并加入第 24 行 ARC/GC 等价矩阵；resource `Result` terminal gate 仅闭合 Component 边界的 G5a 证据，通用 nested/managed producer、spread/multi-value、host/WIT、async/resource G5b/G5c 和 G5c 仍未完成。 |
| 阶段 A–F、H | 已完成 |
| 阶段 D | 可推进项已完成; D2.1 已按 B 方案绿色 regression 收口; D2 本地 file/dir/CLI/socket smoke 与私有 `descriptor.get-type`/`descriptor.sync`/`descriptor.get-flags`/`descriptor.stat`/`descriptor.sync-data`/`descriptor.metadata-hash`/`descriptor.metadata-hash-at`/`descriptor.stat-at`/`descriptor.open-at`/`descriptor.set-size` async slices 已验证；通用 filesystem async、external HTTP 的 method-specific recovery 仍阻断 |
| 阶段 G | G1–G5、G6.1、G6.2 有界 read-directory slice + generic consumer + multi-owned-resource + 一层/两层/三层/四层/五层/六层 nested-owned-resource + multiple nested-owned-resource paths + bounded scalar producer + bounded/parameterized `u64` countdown producer + parameterized helper（含五跳 forwarding 与 typed 参数重排）producer + helper-mediated lease + branch-selected terminal + private resource Result error/cancellation checkpoints + path-sensitive `StreamWriter<T>` lease semantic foundation + record-layout/source-mirror lowering/runtime checkpoints + bounded root-owned local-frame async-call slice + scalar-argument async-call slice + **private bounded async host scalar-argument compiler promotion** + private owned-future compiler slice + private closed/dynamic-count/batched C-min list/resource producer slices + **private bounded scalar `stream<list<u32>>` producer promotion** + D2 私有 filesystem `descriptor.get-type`/`descriptor.sync`/`descriptor.get-flags`/`descriptor.stat`/`descriptor.sync-data`/`descriptor.metadata-hash`/`descriptor.metadata-hash-at`/`descriptor.stat-at`/`descriptor.open-at`/`descriptor.set-size` slices、G6.3、G6.4 完成；generic list/producer、borrowed payload、general async-call、D2 general methods 与 root hard-cancel pending |
| Colorless async / WIT bindgen | canonical `@async/@await/@cancel`、legacy `async` 弃用、schema 1/2 生成 manifest 校验、已准入 schema 2 unit 与 scalar capabilities 的 manifest 自动发现，以及 opt-in v2 variant/scalar-i64 gates、统一 promotion profile、`--p3-async-call-component` root-owned local-frame gate、private `--p3-async-host-arg-component` scalar-argument compiler gate 和 `--p3-owned-future-component` `Future<Ticket>` -> `future<own<ticket>>` gate 已验证；general async-call promotion contract 与 D2 recovery design 已冻结，unrestricted generated WIT lowering 仍 pending |
| 阶段 I | **已关闭** (I1 递归/self-tail TCO + I2 `Tuple<...>` 第一版) |
| 架构审查/重构 | 五轮已落地 (见 §4); 默认不继续拆 god module |
| active Component tooling | `wasm-tools 1.255.0 (76e20611d 2026-07-30)`; SHA-256 `6e431ad26863c697cc30733aae69cbd9248f83811d9e63e4eb01061fc2ece013`; no 1.254.0 executable path |

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
  WASM_TOOLS_EXPECT_VERSION=1.255.0 \
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
WASM_TOOLS_EXPECT_VERSION=1.255.0 \
  bash examples/p3-runtime/test_borrow_capability_matrix.sh
bash examples/p3-runtime/test_list_borrow_canonical_abi.sh
bash examples/p3-runtime/test_future_owned_canonical_abi.sh
bash examples/p3-runtime/test_g6_2_scalar_list_producer_abi.sh

# 默认完整回归 (当前基线; 本机使用 Bun 作为 Node-compatible runner)
NODE_BIN="$(command -v bun)" WASM_TOOLS="$(command -v wasm-tools)" ./src/build/test/run_tests.sh
# 最近验证 (2026-08-20, repository-local TMPDIR): pass=1267 fail=0 skip=3.
# The admitted GC output now has typed GC/root expectations; bounded
# parser-backed scalar-record lower is green, while G5c default cutover and
# non-admitted path work remain pending. The last RUN_WASM=1 baseline remains
# pass=1269 fail=0 skip=3 (2026-08-20).

# G5a parsed synchronous Core-GC gates (non-CLI test entry)
WASMTIME_BIN="$(command -v wasmtime)" WASM_TOOLS_BIN="$(command -v wasm-tools)" \
  bash src/build/test/check_gc_core_oracles.sh
WASMTIME_BIN="$(command -v wasmtime)" WASM_TOOLS_BIN="$(command -v wasm-tools)" \
  bash examples/gc-p3-runtime/test_do_gc_list_literal.sh
WASMTIME_BIN="$(command -v wasmtime)" WASM_TOOLS_BIN="$(command -v wasm-tools)" \
  bash examples/gc-p3-runtime/test_do_gc_list_put.sh
WASMTIME_BIN="$(command -v wasmtime)" WASM_TOOLS_BIN="$(command -v wasm-tools)" \
  bash examples/gc-p3-runtime/test_do_gc_remaining_scalar_lists.sh
WASMTIME_BIN="$(command -v wasmtime)" WASM_TOOLS_BIN="$(command -v wasm-tools)" \
  bash examples/gc-p3-runtime/test_do_gc_managed_struct_remaining_scalar_fields.sh

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
bash examples/gc-p3-runtime/test_gc_wasi_random_list_lift_equivalence.sh

# codegen 单元测试
cd src && zig test build/codegen_api.zig
cd src && zig test main.zig --test-filter 'manifest route'
# 期望: All current codegen API tests passed.

# 发布前 smoke
./src/build/test/run_release_smoke.sh
```

可选扩展:

```bash
RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
# 最近扩展基线 (2026-08-20): pass=1269 fail=0 skip=3; wasm run summary: pass=6 fail=0
```

| 基线项 | 最近值 |
| --- | --- |
| 默认回归 (`SKIP_BUILD=1`) | `pass=1267 fail=0 skip=3` |
| WASM 扩展回归 (`RUN_WASM=1 SKIP_BUILD=1`) | `pass=1269 fail=0 skip=3`; smoke `6/6` |
| `zig test main.zig` | `524/524` |
| async host scalar-argument ABI probe | current `wasm-tools 1.255.0` Component assembly green; frame `20` bytes, argument `u32@12`; ready/pending/cancel oracle green with `argument=7`, exactly-once Future drop, empty `ResourceTable`; probe-only, general lowering pending |
| G6.2 scalar-list producer | private `stream<list<u32>>` promotion green; `ptr=64`, `len=68`, `stride=4`, max `3`, stream capacity `1`; count `0..3`, invalid `4`, pending/error/drop/cancel, exactly-once list release, empty `ResourceTable`; generic list/producer remains pending |
| G5c bounded text host marshal | pinned Core/WIT assembly plus Rust/Wasmtime host execution observes one canonical `hello` string from a fixed GC text lower/copy/call probe; the paired ARC/GC equivalence probe reports one allocation/free on each route; lift, general shapes, compiler wiring, and default-route cutover remain pending |
| G5c manifest-backed WASI random lift | GC lift and hand-authored linear-memory ARC reference use the same versioned WIT package; Rust/Wasmtime observes `lengths=16/16`, `bytes=16/16`, `calls=1/1`; one canonical-boundary equivalence row is closed, while default host/WIT routing and broader G5c cutover remain pending |
| G5c C2 private manifest route | `codegen_component_manifest_route` accepts only a descriptor id, reuses provenance-checked measured planning, and emits the pinned random GC lift; unknown ids fail before WAT, while default host/WIT routing remains ARC |
| G5c C3 private manifest text lower | The second hash-pinned descriptor emits the parser-backed GC `text` lower with canonical `(i32,i32)`; generated GC and ARC Components both deliver `hello` and report one allocation/free through Rust/Wasmtime; ordinary host/WIT routing and broader G5c cutover remain ARC/pending |
| G5c bounded scalar-record lift/lower | `lift` observes `{code: 20, count: 22}` through one result-area pointer; parser-backed flat scalar `lower` observes `{code: 7, count: 35}` through canonical `(i32,i32)` and returns `42`; host and GC/flat equivalence gates pass; indirect beyond the pinned 17-field shape, nested/general aggregates, compiler wiring, and default-route cutover remain pending |
| G5c bounded mixed scalar-record lower | parser-backed `u32/u64/s64` record observes `{code: 7, count: 35, status: -5}` through canonical `(i32,i64,i64)` with a 24-byte measured layout; host and GC/flat equivalence gates pass with result `42` and one callback per path; indirect beyond the pinned 17-field shape, nested/general aggregates, compiler wiring, and default-route cutover remain pending |
| G5c bounded indirect scalar-record lower | parser-backed 17-field `u64` record measures 136 bytes/alignment 8 and lowers to canonical `(i32)`; host gate passes `result=42 write-calls=1`, GC/flat equivalence passes `42/42` and `1/1`; arbitrary indirect layouts, nested/general aggregates, compiler wiring, and default-route cutover remain pending |
| async/D2 recovery designs | general async-call promotion and D2 filesystem/HTTP method matrix recorded; no generic lowering |
| Task 8 Step 3 runtime baseline | 八个已登记 Component/Rust/Wasmtime gate 通过 |
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
`test_do_async_host_scalar_argument.sh` passes current `wasm-tools 1.255.0`
Component assembly/validation, and `test_rust_async_host_scalar_argument.sh` passes
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

## 5. 当前阻断

| ID | 说明 | 恢复条件 |
| --- | --- | --- |
| G6.2 | `descriptor.read-directory`、注册 record-stream consumer 与 bounded scalar/dynamic/batched producer | scalar/string、多-owned-resource、多个顶层 nested paths 与一层/两层/三层/四层/五层/六层 nested-owned-resource consumer、注册 `do:stream-probe` 的 capacity-one `StreamWriter<u8>` producer、固定/参数化 `u64` countdown producer、参数化 helper 的五跳 forwarding、typed 参数受限重排、其它同类型 async helper、bounded StreamMirror、私有 `variant-resource-stream`、private C-min list/resource producer、动态 count `0..3` producer 与固定两批 list-resource producer 已验证；一般 producer lease、borrowed/list/通用 variant、第六跳 forwarding、第七层或更一般 nested resource gates 与任意 filesystem async method 仍待单独推进 |
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

1. **发布候选维护**: 回归红灯、文档漂移、可独立验证的小修
1a. **G5a/G5b/G5c GC migration**: parsed bounded text/list/struct/tuple/union/generic/import slices 已有 typed GC evidence，当前 admitted synchronous 的 24 行 ARC/GC executable equivalence 已闭环；Task 3 已把已准入同步 candidates 接入默认 pipeline，并覆盖推断出的 `text` body binding 的首次 `local_bind` 与后续 `overwrite`、推断出的 `[u8]`/`[u32]` body storage `@put`，以及 body-only managed-struct storage ctor/field update，未准入形状继续 ARC fallback。`src/build/test/check_gc_default_build_gate.sh` 已锁定 63 个 admitted fixture 的默认 `do build` + `wasm-tools 1.255.0` parse gate。bounded parser-backed scalar-record `lift/lower` 已通过 Component assembly、host execution 与 ARC/GC equivalence gates；下一优先是为通用 aggregate 或默认 host/WIT compiler wiring 另立 design、pinned ABI probe、负向边界和等价 gate，不扩大 async/resource admission。
    2026-08-20 增量：第三个 managed segment 的直接 `@get/@set(outer, .inner, .middle, .leaf, ...)` nested managed-struct 路径已通过 typed GC lowering、compiled-test、Wasmtime probe 和等价矩阵；第四个 managed segment、更深路径、producer expression、async/resource 与 host/WIT 仍不准入。
2. **推进 G6.2 后续 gates**: generic consumer、multi-owned-resource、多个顶层 nested-owned-resource paths、一层/两层/三层/四层/五层/六层 nested-owned-resource、bounded scalar/parameterized dynamic producer、参数化 helper（含五跳 forwarding 与 typed 参数受限重排）与受限 helper-mediated lease slices 已闭环；继续一般 producer lease、borrowed/list/variant/第六跳 forwarding、第七层或更一般 nested resource fields 与更广泛 async method 的独立验证
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
- 产品命令边界: `do run` = core wasm smoke (`wasm-tools`+`node`); `do fmt` = 单文件 stdout/check/write; `do lsp` = diagnostics/formatting/tokens/hover/completion/definition (无 rename); `do check` = 前端诊断 only。
