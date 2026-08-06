# Roadmap 执行状态

更新时间: 2026-08-05

**本文只保留当前状态与阻断。** 历史小任务勾选与逐条 gate 证据已从仓库移除; 追溯用 git 历史与 `CHANGELOG.md`。  
总规划: `doc/master_plan.md`。接手入口: `doc/start_here.md`。

## 推进协议

1. 每次只做一个可验证小任务。
2. 完成后更新本文「当前状态」与 `doc/start_here.md` 基线。
3. 阻塞时写清证据、停止点与恢复条件。
4. 语法/语义变更同步 `doc/spec_rules.md`、`doc/grammar.peg`、syntax 与回归。

## 当前状态

| 项 | 状态 |
| --- | --- |
| v1 子集 | 发布候选已收口 |
| 阶段 A–F、H | done |
| 阶段 D | 可推进项 done; D2.1 按 B 方案绿色 regression 收口 |
| D2 真实 host smoke | in progress; real local filesystem preopen/read-directory, CLI pipe, and compiler-generated TCP/UDP socket create/bind/drop loopback gates are green; general filesystem async and external HTTP remain blocked |
| 阶段 G | G1–G5、G6.1、G6.2 bounded read-directory slice + generic consumer + multi-owned-resource + one-/two-/three-/four-/five-/six-level nested-owned-resource + multiple nested-owned-resource paths checkpoints + descriptor-bounded single-read `stream<list<resource-entry>>` ownership lowering/runtime checkpoint + bounded scalar producer + helper-mediated lease（含五跳 forwarding）+ fixed/parameterized `u64` countdown producer + parameterized helper（含五跳 forwarding）producer + reordered helper lease + branch-selected terminal checkpoints + path-sensitive `StreamWriter<T>` lease semantic foundation + registry record-layout/source-mirror lowering/runtime checkpoints、G6.3、G6.4 done; G6.2 general producer-lease/borrowed-resource/list extensions pending |
| Colorless async / WIT bindgen | canonical `@async/@await/@cancel` surface, legacy `async` deprecation, schema 1/2 generated manifest checks, automatic discovery for the admitted schema 2 unit capability, and bounded generic runtime slices verified; unrestricted generated WIT lowering remains pending |
| 阶段 I | **closed** (I1 递归/self-tail TCO + I2 `Tuple<...>` 第一版) |
| 架构扁平拆分 | 已落地: `diagnostics` / `type_name` / `sema_error` / codegen 域竖切 / **`sema_*` 域竖切** (`sema_tokens`/`sema_shapes`/`sema_function_*`/`sema_structures`/`sema_type_checks`/`sema_imports`/`sema_control`) |
| 目录 | 标准库 `lib/`; 工具链 `src/` (原 `tool/`) |

### 最近验证

```text
bash examples/p3-runtime/test_rust_wasi_filesystem_real.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_read_directory_real.sh
bash examples/p3-runtime/test_rust_cli_stream_stdin_real.sh
  → real local file, directory stream, and CLI pipe gates passed in pending/ready matrices
```

```text
cd src && zig test main.zig
  → All 271 tests passed.

TMPDIR=.tmp/do-tmp/next-default \
ZIG_LOCAL_CACHE_DIR=.tmp/do-tmp/next-zig-cache \
ZIG_GLOBAL_CACHE_DIR=.tmp/do-tmp/next-zig-gcache \
./src/build/test/run_tests.sh
  → pass=1098 fail=0 skip=3

Generated async manifest Component/Rust/Wasmtime gate (2026-08-06)
  → Zig 0.16.0, wasm-tools 1.254.0, Wasmtime 47.0.2, Rust/Cargo 1.97.1;
    schema 2 `component-async-unit-v1` generated binding passed pending,
    immediate, and cancel modes with exact cleanup markers; module/WIT hash,
    signature, async import, completion, and capability drift rejected before
    WAT emission

RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  → pass=1072 fail=0 skip=3; wasm run summary: pass=6 fail=0

cd src && zig build -Doptimize=ReleaseSmall
  → passed; run_tests.sh accepts explicit Zig cache directories when `/tmp` quota
    would return DiskQuota

cd src && zig test build/sema_stream_lease.zig
  → All 16 tests passed; reordered helper binding and path-sensitive lease diagnostics 405-410 verified

cd src && zig test build/codegen_component_async_plan.zig
  → All 136 tests passed; branch-selected close/abort plan is verified

cd src && zig test build/codegen_component_stream_writer.zig
  → All 188 tests passed; waitable-set handle and exactly-once terminal cleanup are verified

Rust/Wasmtime G6.2 positive matrix
  → 24 producer/consumer/StreamMirror gates passed; StreamMirror pending/ready/source-eof/error/cancel/early-drop all passed

bash examples/p3-runtime/test_record_resource_list_stream_abi.sh
bash examples/p3-runtime/test_do_record_resource_list_stream_lowering.sh
bash examples/p3-runtime/test_do_record_resource_list_stream_boundary.sh
  → canonical and compiler-generated `stream<list<resource-entry>>` matrices passed for `0/1/3`, pending, `Err(io)`, early cleanup, malformed length, duplicate release, and 6000 same-instance sequential calls; unknown locator stayed rejected

bash examples/p3-runtime/test_do_variant_resource_stream_lowering.sh
  → private `variant-resource-stream` registry/sema/emitter and generated Component/Rust/Wasmtime matrix passed for `ticket`, `idle`, `failed(io)`, pending, and completion-error; generic variant/borrowed shapes remain blocked

bash examples/p3-runtime/test_do_g6_general_boundary_rejection.sh
bash examples/p3-runtime/test_do_borrowed_resource_rejection.sh
cd src && zig test build/p3_async_manifest.zig
  → sixth-forwarding/arbitrary-producer rejected by Do, borrowed stream rejected by pinned wasm-tools, manifest 74/74 passed

bash examples/p3-runtime/test_do_async_resource_result.sh
bash examples/p3-runtime/test_rust_async_resource_result.sh
  → private `Result<own<Response>, HttpError>` resource probe passed pending, immediate, and ready `Err(failed)` completion; success consumes and drops one response per call, while error creates/drops no response.

bash examples/p3-runtime/test_http_service_abi_surface.sh
bash examples/p3-runtime/test_rust_http_service_empty_request.sh
cd src && zig test build/codegen_component_wasi_http.zig
  → generic HTTP service and request-construction/send emitters expand the
    no-body future event handler; pinned Component assembly, empty-request
    Rust/Wasmtime execution, and all 189 emitter tests pass.

WASI HTTP payload-error pending/ready gate
  → compiler-generated `InternalError(None)`, `InternalError(Some("x"))`, and
    `DnsError(rcode=Some("EAI"),info-code=Some(7))` pass pending and ready
    Component/Rust execution with zero response creation and `table-empty=true`;
    immediate `Status::Returned` completion no longer enters `waitable-join`.

bash examples/p3-runtime/test_do_resource_cancellation_shape.sh
bash examples/p3-runtime/test_rust_resource_cancellation_shape.sh
  → explicit `@cancel(completion)` lowers through the private resource emitter;
    positive and negative Do boundaries, generated and hand-written Component
    assembly, and Rust/Wasmtime runtime pass `pending-future-drops=1`, zero
    response create/drop, and `table-empty=true`.

TMPDIR="$PWD/.tmp/do-tmp" bash examples/p3-runtime/test_do_http_payload_cancellation.sh
  → pinned `wasi:http` service-world Component/Rust/Wasmtime gate passes the
    explicit `@cancel(completion)` HTTP payload path: pending has one request
    consumption and one pending-future drop; immediate `Ok(response)` has one
    response creation/drop; immediate `Err(DnsTimeout)` has no resource; every
    ready host Future polls/drops once and every admitted mode finishes with
    `table-empty=true`. The compiler now discards one bounded immediate
    `DNS-error` payload with `rcode=Some(nonempty string)` through its verified
    canonical allocation/free protocol; the runtime gate covers distinct DNS
    string lengths, both `info-code` option states, and the no-payload
`rcode=None` / `InternalError(None)` cases. `None` validates only the option
discriminant and does not read or free pointer/length fields. A second sequential
nonempty DNS error in the same component instance reuses the slot after its
first exact release. Empty strings and all other immediate payload errors remain
compiler traps.

bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_abi.sh
  → WASI G6.2 read-directory ABI probe passed; fixed lowering/runtime slice is verified

bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_lowering.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_read_directory.sh
  → one directory entry, pending/ready completion, exactly-once cleanup, table-empty=true

bash examples/p3-runtime/test_do_wasi_filesystem_read_directory_bounded_lowering.sh
bash examples/p3-runtime/test_rust_wasi_filesystem_read_directory_bounded.sh
  → bounded two-entry read plus EOF, registry-owned record offsets, pending/ready completion, exactly-once cleanup

bash examples/p3-runtime/test_do_record_stream_probe_lowering.sh
bash examples/p3-runtime/test_rust_record_stream_probe.sh
  → generic record-stream consumer: dynamic @next loop, scalar/string record lifting, pending/ready/error completion, exactly-once cleanup, table-empty=true

bash examples/p3-runtime/test_do_record_resource_stream_multi_probe_lowering.sh
bash examples/p3-runtime/test_rust_record_resource_stream_multi_probe.sh
  → two own<ticket> fields, one deduplicated drop import, four resource drops across pending/ready/error, table-empty=true

bash examples/p3-runtime/test_do_record_resource_stream_nested_probe_lowering.sh
bash examples/p3-runtime/test_rust_record_resource_stream_nested_probe.sh
  → one-level nested own<ticket> field, canonical nested handle slot, two resource drops across pending/ready/error, table-empty=true; borrow<ticket> remains rejected by pinned wasm-tools

bash examples/p3-runtime/test_do_record_resource_stream_nested_two_level_probe_lowering.sh
bash examples/p3-runtime/test_rust_record_resource_stream_nested_two_level_probe.sh
  → two-level nested own<ticket> path, recursive WIT/decode/release, two resource drops across pending/ready/error, table-empty=true

bash examples/p3-runtime/test_do_record_resource_stream_nested_three_level_probe_lowering.sh
bash examples/p3-runtime/test_rust_record_resource_stream_nested_three_level_probe.sh
  → three-level nested own<ticket> path, recursive WIT/decode/release, two resource drops across pending/ready/error, table-empty=true

bash examples/p3-runtime/test_do_record_resource_stream_nested_four_level_probe_lowering.sh
bash examples/p3-runtime/test_rust_record_resource_stream_nested_four_level_probe.sh
  → four-level nested own<ticket> path, recursive WIT/decode/release, two resource drops across pending/ready/error, table-empty=true

bash examples/p3-runtime/test_do_record_resource_stream_nested_five_level_probe_lowering.sh
bash examples/p3-runtime/test_rust_record_resource_stream_nested_five_level_probe.sh
  → five-level nested own<ticket> path, recursive WIT/decode/release, two resource drops across pending/ready/error, table-empty=true

bash examples/p3-runtime/test_do_record_resource_stream_nested_six_level_probe_lowering.sh
bash examples/p3-runtime/test_rust_record_resource_stream_nested_six_level_probe.sh
  → six-level nested own<ticket> path, recursive WIT/decode/release, two resource drops across pending/ready/error, table-empty=true

bash examples/p3-runtime/test_do_record_resource_stream_multiple_nested_probe_lowering.sh
bash examples/p3-runtime/test_rust_record_resource_stream_multiple_nested_probe.sh
  → two top-level nested own<ticket> paths, Core handle slots at offsets 0/4, one deduplicated drop import, four resource drops across pending/ready/error, table-empty=true

cd src && zig test build/p3_filesystem_wit_manifest.zig
cd src && zig test build/sema_imports.zig --test-filter 'pinned read-directory'
  → pinned filesystem WIT hashes/record fields and @wasi_record source-mirror drift rejection pass

bash examples/p3-runtime/test_do_http_request_body_lowering.sh
bash examples/p3-runtime/test_do_http_request_body_await_completion_lowering.sh
bash examples/p3-runtime/test_rust_http_request_body.sh
bash examples/p3-runtime/test_rust_http_request_body_await_completion.sh
  → all HTTP request-body lowering and Rust/Wasmtime gates passed

bash examples/p3-runtime/test_do_stream_writer_guest_producer_helper_two_hop_descriptor.sh
bash examples/p3-runtime/test_rust_stream_writer_guest_producer_helper_two_hop.sh
  → one forwarding helper hop, bounded [65,66], pending/ready/Err(pipe), exactly-once stream drop

bash examples/p3-runtime/test_rust_stream_writer_guest_producer_dynamic.sh
  → bounded count=0/1/3 producer, pending/ready/Err(pipe), ordered bytes, one host callback, one stream drop

bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized.sh
bash examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized.sh
  → parameterized count=0/1/3, value=90 producer, `(i64, i32)` async entry, pending/ready/Err(pipe), ordered bytes, one host callback, one stream drop

bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_helper.sh
bash examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_helper.sh
  → parameterized helper count=0/1/3, value=90, one root export, pending/ready/Err(pipe), one host callback, one stream drop

bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_forwarding_helper.sh
bash examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_forwarding_helper.sh
  → parameterized one-hop forwarding helper, count=0/1/3, value=90, one root export, pending/ready/Err(pipe), one host callback, one stream drop

bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_two_hop.sh
bash examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_two_hop.sh
  → parameterized two-hop forwarding helper, count=0/1/3, value=90, one root export, pending/ready/Err(pipe), one host callback, one stream drop

bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_three_hop.sh
bash examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_three_hop.sh
  → parameterized three-hop forwarding helper, count=0/1/3, value=90, one root export, pending/ready/Err(pipe), one host callback, one stream drop

bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_four_hop.sh
bash examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_four_hop.sh
  → parameterized four-hop forwarding helper, count=0/1/3, value=90, one root export, pending/ready/Err(pipe), one host callback, one stream drop

bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_five_hop.sh
bash examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_five_hop.sh
  → parameterized five-hop forwarding helper, count=0/1/3, value=90, one root export, pending/ready/Err(pipe), one host callback, one stream drop

bash examples/p3-runtime/test_do_stream_writer_guest_producer_parameterized_reordered_helper.sh
bash examples/p3-runtime/test_rust_stream_writer_guest_producer_parameterized_reordered_helper.sh
  → typed helper parameter reorder, count=0/1/3, value=90, pending/ready/Err(pipe), one host callback, one stream drop

bash examples/p3-runtime/test_do_stream_writer_guest_producer_branch_terminal.sh
bash examples/p3-runtime/test_rust_stream_writer_guest_producer_branch_terminal.sh
  → helper-mediated branch-selected close/abort, pending/ready/abort, one host callback and one stream drop; stream-only runner has no ResourceTable assertion

bash src/build/test/run_release_smoke.sh
  → ReleaseSmall build, build/test/check/fmt/run/lsp smoke passed
```

剩余 skip: `16_loop_recv_value`、`96_file_lib_resource_shape`、`118_wasi_p3_std_wrappers` (recv / WASI 后置)。

### 阶段 I 边界 (已关闭)

- I1: 直接/互递归; 参数侧已定型泛型递归; self-tail scalar / `if-else` / guard / generic / imported TCO。  
  仅靠左侧目标类型反推的泛型递归仍 `NoMatchingCall`; `defer` / storage / managed / 多返回 / cleanup 不 TCO。
- I2: `Tuple<T0,T1,...>` 位置构造 + `@get` 数字索引; local/struct/return/param/nested/标量与 managed 叶子 storage + path chain + loop get。  
  pure-scalar struct 与含 managed 字段的 struct 直接子槽 storage 已支持 (永不拍平; managed struct 为句柄叶子)。

## 当前阻断与待处理

权威清单 (blocked / pending / deferred / skip): **`doc/pending_blocked.md`**。

摘要:

| 类 | 项 |
| --- | --- |
| blocked | G6.2 general producer-lease/borrowed-resource/list extensions; path-sensitive `StreamWriter<T>` lease semantic foundation is done (branch/loop joins, defer, transfer, write, finalization, exit diagnostics 405-410); 06.2→G6.2 (multi-owned consumer, multiple nested paths, one-/two-/three-/four-/five-/six-level nested resource consumer, descriptor-bounded single-read list-owned resource stream, bounded scalar producer, fixed/parameterized `u64` countdown producer, parameterized helper including five forwarding hops and typed-parameter reorder, helper-mediated lease, branch-selected close/abort terminal, descriptor-bounded StreamMirror, private resource Result cancellation, and pinned HTTP payload cancellation pending/immediate-`Ok`/immediate-`DnsTimeout` plus bounded immediate `DNS-error` optional-string (`Some`/`None`) lowering/runtime cleanup done; empty payload strings, other payload-bearing immediate errors, sixth forwarding hop, seventh nested level, and general resource/list shapes remain pending) |
| pending | P2 左侧反推泛型 (默认不放开); skip 16/96/118 |
| deferred | ownership IR、真 host I/O、JSON 扩展、LSP/fmt、wasm emitter 等 (见该文件 §3) |

## 下一步

1. 发布候选维护 (回归 / 文档漂移 / 独立小修)。
2. 推进 G6.2 后续 gates；generic consumer、多个顶层 nested paths、一-/两层/三层/四层/五层/六层 nested resource、descriptor-bounded single-read list-owned resource stream、bounded scalar producer、固定/参数化 `u64` countdown producer、参数化 helper（含五跳 forwarding 与 typed-parameter reorder）、受限 helper-mediated lease、branch-selected terminal、固定 read-directory、StreamMirror、private resource Result cancellation、HTTP payload cancellation、pinned negative gates 与 ownership invariant 复核均已闭环；一般 producer lease、通用 list、borrowed/variant、第六跳 forwarding、第七层或更一般 nested resource fields 与更广泛 async method 仍需独立设计与验证，不绕过剩余边界扩 codegen。
3. 可选授权项见 `doc/pending_blocked.md` 与 README「下一阶段计划」。
