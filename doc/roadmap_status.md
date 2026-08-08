# Roadmap 执行状态

更新时间: 2026-08-08

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
| D2 真实 host smoke | in progress; real local filesystem preopen/read-directory, CLI pipe, compiler-generated TCP/UDP socket create/bind/drop loopback, and the private pinned `descriptor.get-type`/`descriptor.sync` async method gates are green; general filesystem async and external HTTP remain blocked |
| 阶段 G | G1–G5、G6.1、G6.2 bounded read-directory slice + generic consumer + multi-owned-resource + one-/two-/three-/four-/five-/six-level nested-owned-resource + multiple nested-owned-resource paths checkpoints + descriptor-bounded single-read `stream<list<resource-entry>>` ownership lowering/runtime checkpoint + bounded scalar producer + helper-mediated lease（含五跳 forwarding）+ fixed/parameterized `u64` countdown producer + parameterized helper（含五跳 forwarding）producer + reordered helper lease + branch-selected terminal checkpoints + path-sensitive `StreamWriter<T>` lease semantic foundation + registry record-layout/source-mirror lowering/runtime checkpoints + bounded root-owned local-frame async-call slice + private owned-future compiler slice + private closed/dynamic-count/batched C-min list/resource producer slices + private D2 `descriptor.get-type`/`descriptor.sync` slices、G6.3、G6.4 done; generic list/producer、borrowed payload 与 root hard-cancel 仍 pending |
| Colorless async / WIT bindgen | canonical `@async/@await/@cancel` surface, legacy `async` deprecation, schema 1/2 generated manifest checks, automatic discovery for the admitted schema 2 unit and scalar capabilities, plus opt-in v2 variant/scalar-i64 slices, the `--p3-async-call-component` root-owned local-frame slice, and the private `--p3-owned-future-component` `Future<Ticket>` -> `future<own<ticket>>` slice verified; unrestricted generated WIT lowering remains pending |
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
  → All 304 tests passed.

./src/build/test/run_tests.sh
  → pass=1141 fail=0 skip=3 (Bun Node-compatible runner)

RUN_WASM=1 SKIP_BUILD=1 ./src/build/test/run_tests.sh
  → pass=1143 fail=0 skip=3; wasm run summary: pass=6 fail=0 (Bun Node-compatible runner)

Generated async manifest Component/Rust/Wasmtime gate (2026-08-06)
  → Zig 0.16.0, wasm-tools 1.254.0, Wasmtime 47.0.2, Rust/Cargo 1.97.1;
    schema 2 `component-async-unit-v1` generated binding passed pending,
    immediate, and cancel modes with exact cleanup markers; module/WIT hash,
    signature, async import, completion, and capability drift rejected before
    WAT emission

Generated async scalar Component/Rust/Wasmtime gate (2026-08-06)
  → `component-async-scalar-u32-v1`, package hash
    `30f2b42501e9047f441628d21b4db1916b572ab830ef02763f86e7ac2c7f9945`,
    payload `offset=12 byte-size=4 alignment=4 encoding=core-u32`; generated
    project-root module passed ready/pending/cancel with exact markers
    (`polls=2/3/3`, `completions=2/2/1`, `future-drops=2`, empty table), and
    module/WIT/payload/signature/import/completion/capability drift rejected
    before WAT emission

Generated async scalar i64 Component/Rust/Wasmtime gate (2026-08-06)
  → `component-async-scalar-i64-v1`, package hash
    `861990fea33b55fecd08573ef94f4088296b2cb2bca3356813a2d2157251f3ba`,
    payload `offset=16 byte-size=8 alignment=8 encoding=core-s64`; generated
    project-root module passed ready/pending/cancel with `value=42`, exact
    future cleanup, and an empty resource table. Payload/signature/import
    drift was rejected before WAT emission. This remains a bounded scalar
    companion, not generic generated WIT async lowering.

Bounded general async-call Component/Rust/Wasmtime gate (2026-08-07)
  → `--p3-async-call-component` admits only a no-parameter, `nil` helper
    called by one root `@async(helper())` and containing one registered
    `host.work: async func()` call. The compiler emits a root-owned local
    helper frame with `[guest-async-child]`, `[guest-async-parent-resume]`,
    `[guest-async-child-drop]`, and `[guest-async-root-terminal]`; it never
    exports or synthesizes an independent helper task. Pinned
    `wasm-tools 1.254.0 (bb58fdf91 2026-07-20)`, Wasmtime `47.0.2`, and Rust
    `1.97.1` gates pass `ready`, `pending`, and `cancel` with exactly-once
    child/future cleanup and an empty `ResourceTable`; payload, multiple-child,
    and nested-helper forms reject as `UnsupportedP3AsyncCallComponent` before
    WAT, while the normal target remains `AsyncLoweringUnavailable`.

Private owned-future Component/Rust/Wasmtime gate (2026-08-07)
  → `--p3-owned-future-component` admits only the registered ordinary Do
    source shape `Future<Ticket>` plus one `@await`, and emits the private
    `future<own<ticket>>` WIT sidecar. The compiler-generated Component passes
    current `wasm-tools 1.255.0` parsing, pinned legacy `1.254.0` async
    assembly/validation, and Wasmtime `47.0.2` ready/pending/cancel with
    representation `0`, exactly-once future/resource cleanup, and an empty
    `ResourceTable`. Unknown descriptor, scalar payload, and second-await
    fixtures reject before WAT as `UnsupportedP3OwnedFutureComponent`; public
    `own<T>`/`borrow<T>`/`ref<T>` syntax and generic owned/borrowed async
    lowering remain pending.

G6.2 C-min producer canonical ABI probe (2026-08-07)
  → `bash examples/p3-runtime/test_g6_2_c_min_list_resource_producer_abi.sh`
    passed the hand-authored producer WIT/Core-WAT/Rust/Wasmtime gate. The
    pinned WIT parses with `wasm-tools component wit`; source hash
    `8decd27aeca4a1f1863544860caec230a1fc50259336a893de79413c6f9ec3f7`.
    Producer layout is `ptr=64`, `len=68`, element stride `4`, ticket offset
    `0`, stream capacity `1`, with only `0/1/3` admitted. Ready/pending/error/
    early-drop/invalid-mode and pre-/post-transfer cancellation pass with
    exactly-once cleanup and `table-empty=true`; malformed length and duplicate
    release variants trap with the expected unknown-handle diagnostics. This
    closes only Gate 1 evidence; no registry entry or compiler lowering is
    enabled, and generic list/producer, borrowed payload, public ownership
    syntax, and root hard-cancel remain pending.

G6.2 C-min producer registry/sema admission (2026-08-08)
  → `cd src && zig test build/p3_async_manifest.zig && zig test build/sema_imports.zig`
    passed `79/79` and `122/122`. The private descriptor is now validated against
    the producer WIT hash, source/sink canonical imports, list/resource layout,
    capacity and terminal metadata. Sema admits only
    `StreamWriter<[ResourceEntry]> -> Result<nil, ErrorCode>` and rejects drifted
    elements/error types and unregistered locators. This closes Gate 3 admission;
    the exact Do emitter and compiler runtime gate are recorded below. Generic
    list/producer, borrowed payload, public ownership syntax, and root hard-cancel
    remain pending.

G6.2 C-min pure list layout slice (2026-08-08)
  → `cd src && zig test build/wit_abi_layout.zig --test-filter 'list resource producer'`
    passed `6/6`; the full layout suite passed `19/19`, and
    `zig test build/wit_abi_types.zig` passed `5/5`. The plan validates the
    measured pointer/length words, stride/alignment, ticket slot, capacity `3`,
    and closed lengths `0/1/3`; nested/borrowed/missing-owned-slot and invalid
    layout cases remain fail-closed. This internal plan is consumed by the
    private producer adapter and does not add public ownership syntax.

G6.2 C-min pure list ownership slice (2026-08-08)
  → `cd src && zig test build/wit_abi_ownership.zig --test-filter 'list producer'`
    passed `6/6`; the full ownership suite passed `17/17`. The plan enforces
    single-slot queueing, closed cardinality `0/1/3`, child-before-parent
    cleanup, pre-transfer guest releases, post-transfer source-slot clearing,
    duplicate-release rejection, and `maybe` branch-join rejection. It remains
    an internal plan and does not add public ownership syntax.

G6.2 C-min bounded async frame slice (2026-08-08)
  → `cd src && zig test build/wit_abi_async.zig --test-filter 'list producer frame'`
    passed `4/4`; full `wit_abi_async` passed `13/13`, and
    `codegen_component_async_plan` passed `156/156`. The plan enforces one
    queue slot, transfer-aware source-slot cleanup, waitable/future lifecycle,
    cancellation before/after transfer, early drop, and child-before-parent
    terminal ordering. It is consumed by the private producer adapter.

G6.2 C-min producer compiler/runtime promotion (2026-08-08)
  → `zig test build/codegen_component_list_resource_producer.zig` passed `139/139`,
    `zig test build/codegen_component_async.zig` passed `453/453`, and the
    dispatcher routes only the registered descriptor. The Do positive gate,
    three negative compile fixtures, and the existing consumer boundary gate all
    pass. `bash examples/p3-runtime/test_rust_g6_2_c_min_list_resource_producer.sh`
    passes compiler-generated Component/Rust/Wasmtime ready `0/1/3`, pending,
    sink error, early drop, invalid mode, and transfer-before/after cancellation;
    admitted terminal paths end with `table-empty=true`. `run_tests.sh` reports
    `pass=1126 fail=0 skip=3`, ReleaseSmall and `git diff --check` pass. C-min is
    closed as a private bounded slice; generic producer/list, arbitrary producer
    expressions, nested/borrowed payloads, public ownership syntax, and root
  hard-cancel remain pending.

G6.2 bounded dynamic list producer compiler/runtime promotion (2026-08-08)
  → the private descriptor `do:g6-2-c-min-dynamic-producer@0.1.0` is pinned to
    WIT hash `95f6d2d616e80248a8710e10199fa3674aa80b76247f25c2e71d3d87ea4afe76`.
    The adapter tests pass `147/147`; the generic async dispatcher passes
    `453/453`; and `bash examples/p3-runtime/test_rust_g6_2_c_min_dynamic_list_producer.sh`
    passes compiler-generated Component/Rust/Wasmtime counts `0/1/2/3`, invalid
    count `4`, pending, sink error, early drop, source failure, and both
    transfer-boundary cancellation variants. Layout is `ptr=64`, `len=68`,
    `stride=4`, ticket offset `0`, stream capacity `1`; every admitted path
    ends with `table-empty=true`. Fixtures `450`–`453` reject drifted version,
    count type, second stream binding, and borrowed entry before WAT.
    Generic/unbounded producer expressions, borrowed async payloads, public
    ownership syntax, and root hard-cancel remain pending.

G6.2 batched list resource producer compiler/runtime promotion (2026-08-08)
  → the private descriptor `do:g6-2-batched-list-producer@0.1.0 /
    consume-via-stream` is pinned to WIT hash
    `a0717b2ac8525c4b1f684a4222f66939312a19c959c66b0ace5ebca16f45299f` and
    canonical Core WAT hash
    `1114696249c4fd9142005ed3b7703c2642741e22e4832494df05bfc635cbd71c`.
    Manifest/sema admission is fail-closed; the isolated adapter passes
    `146/146` and the async dispatcher passes `462/462`. The generated Do
    Component gate and Rust/Wasmtime gate pass `ready`, `pending`,
    `sink-error-first`, `sink-error-second`, `cancel-before-first`, and
    `cancel-after-first`: batches are `[111,222]` then `[333]` where admitted,
    layout is `ptr=64/72`, `len=68/76`, `stride=4`, ticket offset `0`, stream
    capacity `1`, with three resources created/dropped, two list allocations/
    releases, one stream drop, one future drop, and `table-empty=true` on every
    row. Fixtures `454`–`458` reject unregistered version, wrong mode type,
    second sink, borrowed entry, and non-empty producer body before WAT.
    `run_tests.sh` is `pass=1132 fail=0 skip=3`; generic producer expressions,
    generic/unbounded lists, borrowed async payloads, public ownership syntax,
    root hard-cancel, and general filesystem/HTTP async remain pending.

D2 private filesystem `descriptor.get-type` compiler/runtime promotion
(2026-08-08)
  → `bash examples/p3-runtime/test_d2_wasi_filesystem_get_type_abi.sh` passed
    current `wasm-tools 1.255.0` and legacy `1.254.0` gates. The pinned WIT
    hash is `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`;
    the method import is `[async-lower][method]descriptor.get-type` with
    `(i32,i32)->i32`, two `i32` task-return completion words, a component
    variant Result, and `[resource-drop]descriptor`.
    `bash examples/p3-runtime/test_rust_wasi_filesystem_get_type.sh` passes
    the hand-authored Component in ready-directory, ready-regular, pending,
    error, and cancel modes, and the compiler-generated Component in
    ready-directory, ready-regular, pending, and error modes, with matching
    exactly-once future/descriptor cleanup and `table-empty=true`. Fixtures `459`–`461`
    reject unregistered, wrong-result, and borrowed-payload drift before WAT.
    This closes only this private method; other filesystem async methods,
    generic producer expressions, borrowed payloads, and public ownership
    syntax remain blocked.

D2 private filesystem `descriptor.sync` compiler/runtime promotion (2026-08-08)
  → `bash examples/p3-runtime/test_d2_wasi_filesystem_sync_abi.sh` passed
    current `wasm-tools 1.255.0` and legacy `1.254.0`; upstream WIT hash
    `8421d2ac1b15d121ccce9e3596ee342a641043a8b4558f7a4f2893a3eee6359f`, regular
    mirror hash `18ce7dc9efb991cd8e5f945797aea73edeed79f0cfc51ea664cb81537e54e719`,
    cancel mirror hash `9898cd734708a2ab14760da706d69063e5cd6262a5e03d07d8eedd8074745f36`.
    The method import is `[async-lower][method]descriptor.sync` with
    `(i32,i32)->i32`, unit/error-code component-variant completion, and
    `[resource-drop]descriptor (i32)->nil`. Fixtures `462`–`465` reject
    unregistered, wrong-result, borrowed-payload, and second-await drift.
    Hand-authored ready/pending/error/cancel and generated ready/pending/error
    Components pass the Rust/Wasmtime matrix with exactly-once cleanup and
    `table-empty=true`; other filesystem methods and general async producer or
    payload shapes remain pending.

bash examples/p3-runtime/test_task8_step3_baseline.sh
  → all seven registered Component/Rust/Wasmtime runtime gates passed

zig test src/build/codegen_component_record_stream.zig
zig test src/build/codegen_component_record_resource_list_stream.zig
zig test src/build/codegen_component_wasi_filesystem_read_directory.zig
  → scanner suites passed; canonical ordinary-function + `@await` syntax is
    accepted while legacy scanner fixtures remain covered

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

Independent Generic ABI v2 variant emitter (2026-08-06)
  → opt-in adapter rendered a separate v2 WAT template from the pinned
    descriptor/measurement plan; `wasm-tools` parse/embed/new/validate passed,
    followed by the Rust/Wasmtime ticket/idle/failed/pending/completion-error
    cleanup matrix. The unified `--p3-async-component-v2` profile now routes
    this exact shape; default component dispatch remains v1.

Independent Generic ABI v2 scalar-i64 emitter (2026-08-06)
  → `--p3-async-v2-scalar-i64` rendered a separate scalar-i64 WAT template from
    the generated-manifest payload and measured `offset=16`, `byte-size=8`,
    `alignment=8`, `core-s64` layout. `wasm-tools` parse/embed/new/validate and
    the Rust/Wasmtime ready/pending/cancel matrix passed with exact `value=42`
    and empty resource table; a manifest payload mutation was rejected before
    WAT emission. The unified `--p3-async-component-v2` profile also routes
    this exact shape; the legacy single-shape flag remains compatible and
    default dispatch remains v1.

Borrow capability matrix refresh (2026-08-06)
  → the capability matrix was rerun against `wasm-tools 1.255.0` using
    `WASM_TOOLS_EXPECT_VERSION=1.255.0`. Direct `borrow<ticket>`, borrowed
    record, borrowed variant, and `list<borrow<ticket>>` still embed/new
    successfully; `stream<record { ticket: borrow<ticket> }>` and
    `future<borrow<ticket>>` still reject at `component embed` with
    `contains a \`borrow<T>\` which is not supported`.

Generic ABI v2 registry/runtime promotion profile (2026-08-06)
  → `bash examples/p3-runtime/test_generic_abi_v2_promotion.sh` passed both
    independent Component/Rust/Wasmtime matrices and the generated scalar-u32
    fail-closed negative. `--p3-async-component-v2` admits only these two
    measured private shapes; all other targets reject before WAT emission.

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

**回归 harness 环境注记 (2026-08-06):** 当前 `/snap/bin/node` 为
`v24.19.0`；在本机执行 `node -e 'console.log("x")' > file` 会产生空文件，
`process.stdout.write` 在重定向路径还会报告 `EBADF`。因此
`run_tests.sh` 中依赖 stdout 重定向的 `compiled_must_pass`、WIT manifest tool
和 `do run` marker 会批量失败。设置 `NODE_BIN=/home/_/.local/bin/bun`
后，当前完整回归已恢复为 `pass=1109 fail=0 skip=3`；`do run` 现在也会优先
使用这个显式 runtime。该项是测试环境/Node launcher 注意事项，不是 compiler
或 borrow capability 阻断。

Bun regression refresh (2026-08-06)
  → `NODE_BIN=/home/_/.local/bin/bun WASM_TOOLS=/home/_/.local/bin/wasm-tools
     SKIP_BUILD=1 ./src/build/test/run_tests.sh`
    passed with `pass=1109 fail=0 skip=3`; `zig test main.zig --test-filter
    find_node_runtime` passed all 4 runtime-selection tests.

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
