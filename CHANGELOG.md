# Changelog

- 2026-08-06 Generated async scalar i64 lowering: the separate private
  `component-async-scalar-i64-v1` capability now accepts the generated
  `Future<i64>` caller with the measured `offset=16`, `byte-size=8`,
  `alignment=8`, `encoding=core-s64` payload descriptor. The generated
  Component and Rust/Wasmtime ready/pending/cancel gate passes with exact
  cleanup; generic Future payloads, text/list/resource shapes, and unrestricted
  generated WIT async lowering remain pending.

- 2026-08-06 Generated async scalar lowering: the private
  `component-async-scalar-u32-v1` capability now accepts the generated
  `Future<u32>` caller through manifest validation, a measured Component
  payload state machine, and a project-root `wit/` Rust/Wasmtime gate. Ready,
  pending, and cancel cleanup are verified; generic Future payloads, streams,
  resources, and unrestricted generated WIT async lowering remain pending.

- 2026-08-05 D2/G6.3 socket real-host gate: the compiler-generated TCP and UDP
  `create/bind/drop` Components now use the measured canonical argument order,
  result tags, IPv4 flattening, and result-area pointers. The Rust/Wasmtime
  loopback matrix passes success, forced create error, and forced bind error
  with exact resource cleanup; listen/connect/accept and general socket I/O
  remain out of scope.

- 2026-08-05 Result source policy closure: ordinary Do and standard-library
  host APIs use `T | E` (or `nil | E`) for distinct WIT result arms, with
  type-based narrowing. Duplicate ordinary union branches remain rejected.
  `Result<T, E>` and its explicit tag are retained only for registered private
  WIT/Component compatibility probes, including same-type arms; no public
  `own<T>`/`borrow<T>`/`ref<T>` syntax is introduced.

- 2026-08-04 G6.2 HTTP payload cancellation: the registered pinned
  `wasi:http/client.send` shape now accepts an explicit
  `@cancel(completion)` nil-returning root. The generated and hand-written
  service-world Components assemble and pass the Rust/Wasmtime pending and
  admitted immediate-terminal gates with exactly-once request/future/resource
  cleanup and an empty `ResourceTable`; sequential nonempty payload calls reuse
  the released private slot. Cancel-after-terminal, double cancellation of one
  Future, implicit cancellation, broader HTTP payload shapes, and public
  ownership syntax remain blocked.

- 2026-08-04 G6.2 HTTP payload-error lowering: the descriptor-registered
  `InternalError(option<string>)` and
  `DNS-error(option<string>, option<u16>)` branches now preserve exact canonical
  values through pending and ready Component/Rust/Wasmtime delivery. Error paths
  create no response resource and leave the resource table empty; `Some` to
  `None` host-lowered substitution and every unregistered payload tag remain
  explicitly blocked. The separate registered HTTP payload-cancellation gate is
  documented independently; general HTTP shapes remain outside both bounded
  gates.

- 2026-08-04 test harness: `run_tests.sh` now creates an explicitly configured
  `TMPDIR` before Node-based Component probes call `mkdtemp`. Release and full
  regression commands can therefore use a fresh worktree-local temp root
  without a manual directory pre-step.

- 2026-08-04 HTTP Component emitter placeholder hardening: the generic service
  and request-construction/send paths now expand the shared
  `[body-future-event-handler]` slot to the normal no-body waitable event
  result. The pinned HTTP service ABI probe, empty-request Rust/Wasmtime gate,
  HTTP emitter suite (`183/183`), default/WASM regressions, and ReleaseSmall
  smoke pass. This only closes template leakage; it does not add general HTTP
  body, payload-bearing error, or public ownership syntax.

- 2026-08-04 G6.2 private resource Result cancellation: the registered
  `do:resource-probe/http@0.1.0` shape now accepts an explicit
  `@cancel(completion)` nil-returning async root. The generated Component calls
  `subtask.cancel`, checks terminal status, drops the subtask exactly once, and
  returns through `[task-return]cancel`. Generated and hand-written
  Component/Rust/Wasmtime gates cover pending future drop, request consumption,
  zero response create/drop, and an empty `ResourceTable`; implicit scope-drop,
  double cancellation, and cancellation after terminal consumption remain
  rejected. No rollback protocol or public `own<T>`/`borrow<T>`/`ref<T>` syntax
  was added.

- 2026-08-04 G6.2 private resource Result error terminal: the registered
  `do:resource-probe/http@0.1.0` async resource now completes a ready
  `Err(failed)` through the same task-return, canonical-buffer, context, and
  GC-frame cleanup path as success. The Component/Rust/Wasmtime gate proves two
  requests are consumed, no response resource is created or dropped on error,
  and pending/immediate success behavior remains green. Cancellation is still
  excluded until an explicit `@cancel` source shape is designed; no public
  `own<T>`/`borrow<T>`/`ref<T>` syntax or arbitrary resource Result payloads were
  added.

- 2026-08-04 G6.2 capability-matrix closeout: the full private positive
  Component/Rust/Wasmtime matrix passed, including record consumers through
  six nested owned-resource levels, producer helpers through five forwarding
  hops, reordered/branch-terminal producers, and all six StreamMirror modes.
  The pinned negative gates still reject arbitrary producers, sixth forwarding,
  shared leases, borrowed stream fields, and seventh-level nesting. Fresh
  regressions remain `pass=1068 fail=0 skip=3`, WASM `pass=1070 fail=0 skip=3`
  with six WASM smoke cases, and `zig test main.zig` is `232/232`.

- 2026-08-03 G6.2 producer lease closeout: the private `do:stream-probe`
  producer now has verified branch-selected `close(writer)` / `abort(writer, 2)`
  terminal lowering, while typed parameter reordering resolves the actual
  `StreamWriter<u8>` formal slot. Component and Rust/Wasmtime gates cover
  pending/ready/abort or error paths with one callback and one stream drop;
  the producer-only runner has no `ResourceTable` and therefore makes no
  `table-empty=true` claim. The capability matrix retains rejection of
  arbitrary producer expressions, shared leases, borrowed stream fields,
  sixth forwarding, seventh nesting, and public `own<T>`/`borrow<T>`/`ref<T>`.

- 2026-08-03 G6.2 StreamMirror runtime closeout: the private
  descriptor-bounded source-to-writer mirror now drops its completed sink
  subtask before dropping the waitable set, preventing Wasmtime's
  `resource has children` failure. The Core/WIT lowering gate and the Rust/
  Wasmtime matrix pass pending, ready, source EOF, `Err(pipe)`, cancellation,
  and early-drop modes with exactly-once source stream/future and sink cleanup
  and an empty resource table. The change keeps ordinary async lowering
  guarded by `AsyncLoweringUnavailable` and does not add public
  `own<T>`/`borrow<T>`/`ref<T>` syntax.

- 2026-08-03 G6.2.3 path-sensitive producer-lease semantic foundation:
  `sema_stream_lease.zig` now checks `StreamWriter<T>` ownership across
  if/else joins, loop exits, lexical `defer`, same-typed transfer, helper
  transfer, writer writes, finalization, and async scope exits. Unequal join
  states report `StreamWriterLeasePathConflict`; moving a deferred writer
  reports `StreamWriterDeferredTransfer`. Fixtures 350, 405-407, and 409-410
  now lock the refined diagnostics, while 351-404 and 408 remain green. The
  change is semantic-only: no public `own<T>`/`borrow<T>`/`ref<T>` syntax,
  general async-call lowering, or arbitrary producer runtime shape was added.
  Focused Zig tests, ReleaseSmall, the full `SKIP_BUILD=1` regression
  (`pass=1065 fail=0 skip=3`), `RUN_WASM=1` (`pass=1067 fail=0 skip=3`), and
  the existing five-hop/six-level Rust/Wasmtime gates pass.

- 2026-08-03 G6.2 six-level nested owned-resource and five-hop forwarding
  checkpoints: the private `do:record-resource-stream-nested-six-level@0.1.0`
  descriptor now admits the exact `inner -> deep -> deeper -> deepest -> ultra
  -> hyper -> own<ticket>` path, and the private `do:stream-probe` producer
  admits five same-typed `(writer, count, value)` forwarding helpers. Component
  lowering plus Rust/Wasmtime pending/ready/error gates pass with two resource
  creates/drops, one stream drop, one future drop, one host callback, and empty
  resource tables. Sixth forwarding, seventh nested level, borrowed/list/variant
  fields, and resource escape remain rejected. Pinned `wasm-tools 1.254.0`
  explicitly rejects a `borrow<ticket>` stream record during Component embed.
  See `docs/superpowers/plans/2026-08-03-g6-2-bounded-next-phase.md`.

- 2026-08-03 G6.2 five-level nested owned-resource record checkpoint: the
  private `do:record-resource-stream-nested-five-level@0.1.0` descriptor now
  admits one `inner -> deep -> deeper -> deepest -> ultra -> own<ticket>` path.
  Recursive manifest/WIT/Core decode-release, Component assembly, and
  Rust/Wasmtime pending/ready/error gates pass with two resource drops, one
  stream drop, one future drop, and an empty resource table. Sixth-level,
  multi-child, mixed scalar/nested, borrow/list/variant, and resource-escape
  shapes remain rejected. See
  `docs/superpowers/specs/2026-08-03-record-stream-nested-five-level-design.md`.

- 2026-08-03 G6.2 parameterized four-hop forwarding helper producer checkpoint:
  the private `do:stream-probe` producer now admits the exact chain
  `produce -> outer_stream -> entry_stream -> forward_stream -> middle_stream -> finish_stream`.
  All four forwarders transfer `(writer, count, value)` unchanged and only
  await the next same-typed helper; the final helper retains the existing
  countdown, sink call, and `defer close(writer)` behavior. Component lowering
  and Rust/Wasmtime pending/ready/`Err(pipe)` gates pass for `count=0/1/3`,
  `value=90`, one host callback, and one stream drop. A fifth forwarding edge,
  general async calls, arbitrary producer expressions, and borrowed/nested/
  variant resource fields remain rejected. See
  `docs/superpowers/specs/2026-08-03-stream-writer-parameterized-four-hop-design.md`.

- 2026-08-03 G6.2 four-level nested owned-resource record checkpoint: the
  private `do:record-resource-stream-nested-four-level@0.1.0` descriptor now
  admits one `inner -> deep -> deeper -> deepest -> own<ticket>` path. The
  recursive manifest/WIT/Core decode-release path, Component assembly, and
  Rust/Wasmtime pending/ready/error gates pass with two resource drops, one
  stream drop, one future drop, and an empty resource table. Fifth-level,
  multi-child, mixed scalar/nested, borrow/list/variant, and resource-escape
  shapes remain rejected. See
  `docs/superpowers/specs/2026-08-03-record-stream-nested-four-level-design.md`.

- 2026-08-03 G6.2 parameterized three-hop forwarding helper producer checkpoint:
  the private `do:stream-probe` producer now admits the exact chain
  `produce -> entry_stream -> forward_stream -> middle_stream -> finish_stream`.
  All three forwarders transfer `(writer, count, value)` unchanged and only
  await the next same-typed helper; the final helper retains the existing
  countdown, sink call, and `defer close(writer)` behavior. Component lowering
  and Rust/Wasmtime pending/ready/`Err(pipe)` gates pass for `count=0/1/3`,
  `value=90`, one host callback, and one stream drop. A fourth forwarding edge,
  general async calls, arbitrary producer expressions, and borrowed/nested/
  variant resource fields remain rejected.

- 2026-08-03 G6.2 three-level nested owned-resource record checkpoint: the
  private `do:record-resource-stream-nested-three-level@0.1.0` descriptor now
  admits one `inner -> deep -> deeper -> own<ticket>` path. Recursive WIT
  declaration, Core decode/release, Component validation, and Rust/Wasmtime
  pending/ready/error gates pass with two resource drops, one stream drop, one
  future drop, and an empty resource table. Fourth-level, multi-child, mixed
  scalar/nested, borrow/list/variant, and resource-escape shapes remain
  rejected.

- 2026-08-03 G6.2 reordered parameterized helper checkpoint: the private
  `do:stream-probe` producer now accepts a helper declaration in any order of
  exactly one `StreamWriter<u8>`, one `u64`, and one `u8`, with calls mapped by
  typed formal position. Sema ownership transfer, Component lowering, and
  Rust/Wasmtime pending/ready/`Err(pipe)` gates pass for count `0/1/3`, value
  `90`, one host callback, and one stream drop. Literal, duplicate, missing,
  extra, crossed, third-hop, and arbitrary producer/resource shapes remain
  rejected.

- 2026-08-03 G6.2 multiple nested owned-resource path checkpoint: the private
  `do:record-resource-stream-multiple-nested@0.1.0` descriptor now admits two
  top-level nested `own<ticket>` paths with Core slots at offsets 0 and 4.
  Recursive WIT/decode/release emission deduplicates the shared resource/drop
  declarations. Component lowering and Rust/Wasmtime pending/ready/error gates
  pass with four resource drops, one stream drop, one future drop, and an empty
  resource table. Third-level, multi-child, mixed scalar/nested, borrow/list/
  variant, and resource-escape shapes remain rejected.

- 2026-08-03 G6.2 two-level nested owned-resource record checkpoint: the private
  `do:record-resource-stream-nested-two-level@0.1.0` descriptor now admits one
  bounded `inner-entry -> deep-entry -> own<ticket>` path. Recursive WIT
  declarations, Core decode, deduplicated drop imports, and frame-owned
  exactly-once release are covered by Component lowering plus Rust/Wasmtime
  pending/ready/error gates; a fourth level, multiple paths, borrowed/list/
  variant fields, and resource escape remain rejected.

- 2026-08-03 G6.2 nested-resource manifest boundary hardening: nested child
  metadata now validates recursive shape and rejects a fourth nested level,
  multiple children, or unsupported metadata instead of silently interpreting
  deeper resource shapes as a shallower record. Existing one-level
  Component/Rust/Wasmtime gates remain unchanged.

- 2026-08-03 G6.2 parameterized two-hop forwarding helper producer checkpoint:
  the private `do:stream-probe` producer now admits the exact chain
  `produce -> forward_stream -> middle_stream -> finish_stream`. Both
  forwarders transfer `(writer, count, value)` unchanged and only await the
  next helper; the final helper retains the existing countdown, sink call, and
  `defer close(writer)` behavior. Component plus Rust/Wasmtime
  pending/ready/`Err(pipe)` gates pass for `count=0/1/3`, `value=90`, one host
  callback, and one stream drop. A third forwarding edge, reordered/literal
  arguments, general async calls, and arbitrary resource shapes remain
  rejected.

- 2026-08-03 G6.2 nested owned-resource record checkpoint: the private
  `do:record-resource-stream-nested@0.1.0` descriptor admits one nested
  `inner-entry` containing one `own<ticket>` child. Component lowering and
  Rust/Wasmtime pending/ready/error gates observe two resource drops, one
  stream drop, one future drop, and an empty resource table. Borrowed, list,
  variant, deeper nested, and arbitrary producer/resource shapes remain outside
  the gate; pinned `wasm-tools 1.254.0` rejects a stream record containing
  `borrow<T>` during Component embed.

- 2026-08-03 G6.2 parameterized forwarding helper producer checkpoint: the
  registered `do:stream-probe` producer now admits one private forwarding
  helper that transfers `(writer, count, value)` unchanged to the existing
  parameterized countdown helper. Component lowering still emits one root
  export with frame offsets 52/60. Component plus Rust/Wasmtime
  pending/ready/`Err(pipe)` gates pass for `count=0/1/3`, `value=90`, one host
  callback, and one stream drop; a third hop and general async/resource shapes
  remain rejected.
- 2026-08-03 G6.2 parameterized helper producer checkpoint: the registered
  `do:stream-probe` guest producer may transfer its capacity-one
  `StreamWriter<u8>` lease to one private helper with `(writer, count, value)`
  parameters. The helper runs the existing zero-pre-guarded countdown using
  frame offsets 52/60, closes once, and calls the registered sink. Component
  lowering plus Rust/Wasmtime pending/ready/`Err(pipe)` gates pass for
  `count=0/1/3`, `value=90`, one host callback, and one stream drop. General
  async calls, extra helper hops, and arbitrary producer/resource shapes remain
  pending.
- 2026-08-03 G6.2 parameterized dynamic producer checkpoint: the registered
  `do:stream-probe` sink now admits `async produce(count u64, value u8)`, with
  a capacity-one countdown pump, `(i64, i32)` async entry, frame value slot at
  offset 60, and per-pump byte admission. Component plus Rust/Wasmtime
  pending/ready/`Err(pipe)` gates pass for `count=0/1/3`, `value=90`, with one
  host callback and one stream drop; general producer expressions and async
  calls remain outside the boundary.
- 2026-08-03 G6.2 bounded dynamic producer checkpoint: the registered `do:stream-probe` sink now admits the explicit `(count u64)` countdown producer shape. It uses a capacity-one `StreamWriter<u8>`, writes literal `65`, stores `remaining` as `i64`, starts the sink before pumping, and supports `count=0/1/3`. Component validation plus Rust/Wasmtime pending/ready/`Err(pipe)` gates pass with one host callback and one stream drop; general loops, dynamic values, and general async calls remain outside the boundary.
- 2026-08-03 G6.2 two-hop helper producer lease checkpoint: one private async forwarding helper may now transfer an open `StreamWriter<u8>` lease to the final same-typed helper, which performs the bounded `[65, 66]` sequence, registered sink call, and `defer close(writer)`. Component lowering and Rust/Wasmtime pending/ready/`Err(pipe)` gates pass; a third hop, general async calls, dynamic producers, and borrowed/nested/variant resource fields remain rejected.
- 2026-08-03 G6.2 helper-owned producer lease checkpoint: the one same-typed async helper may now perform the bounded `[65, 66]` `StreamWriter<u8>` sequence after receiving the lease, then call the registered sink and `defer close(writer)`. The plan still emits only the producer root; Component lowering and Rust/Wasmtime pending/ready/`Err(pipe)` gates pass. General async calls, multi-level helpers, dynamic producers, arbitrary payloads, and borrowed/nested/variant resource fields remain outside the gate.
- 2026-08-03 G6.2 helper-mediated producer lease checkpoint: a bounded `StreamWriter<u8>` producer may transfer its lease once to a same-typed async helper that directly calls the registered stream-writer descriptor and finalizes with `defer close(writer)`. The descriptor-specific Component emitter keeps only the producer root export; pending/ready/`Err(pipe)` Rust/Wasmtime gates observe `[65, 66]`, one host callback, and one stream drop. General async calls, dynamic producers, arbitrary payloads, and borrowed/nested/variant resource fields remain outside the gate.

- 2026-08-02 G6.2 producer-lease terminal-error evidence: the registered custom stream-writer `Err(pipe)` runtime gate now requires one host callback and `stream-dropped=true`, making terminal reader cleanup observable instead of checking callback count alone.

- 2026-08-02 G6.2 generic stream-writer producer checkpoint: the bounded guest `StreamWriter<u8>` pump now runs through the registered `do:stream-probe@0.1.0` sink, with descriptor-selected host instance/export wiring and pending/ready/error Rust/Wasmtime evidence. Capacity-one backpressure consumes `[65, 66]` and drops the stream exactly once; producer leases, borrowed/nested/variant resource fields, broader payload-bearing completion errors, and arbitrary filesystem async methods remain outside this slice.

- 2026-08-02 G6.2 multi-owned-resource record-stream checkpoint: the private descriptor-driven consumer now accepts two `own<ticket>` fields, deduplicates the WIT resource/drop import, and releases all frame-owned handles exactly once. Component lowering plus Rust/Wasmtime pending/ready/error probes observe four resource drops and an empty `ResourceTable`; borrowed/nested resources and producer leases remain pending.

- 2026-08-02 G6.2 generic record-stream consumer: descriptor-driven lowering now accepts the registered `do:record-stream-probe@0.1.0` record stream with dynamic `@next`/`await`, scalar/string record lifting, pending/ready/error completion, and exactly-once stream/future/resource cleanup. Rust/Wasmtime evidence covers two records, EOF, one pending wake, and an empty resource table. Producer leases, borrowed/nested/variant resource fields, broader payload-bearing completion errors, and arbitrary filesystem async methods remain outside this slice.

- 2026-08-02 host ABI and P3 runtime closure: concrete and nested generic host-export structs now use one shared named field-ABI collector for WAT and manifests; pinned HTTP body/empty-request probes and byte-admission checks remain verified. Evidence: `zig test main.zig` 188/188 and `./src/build/test/run_tests.sh` pass=1049 fail=0 skip=3.

- 2026-08-02 G6.2 bounded read-directory slice: the pinned `descriptor.read-directory` now has one-to-three-entry record-stream lowering, explicit EOF probing, pending/ready Rust/Wasmtime execution, independent completion await, exactly-once stream/future/resource cleanup, and `table-empty=true`. This fixed slice does not claim payload-bearing completion errors or arbitrary filesystem async methods.

- **Host import 统一为 `@host(locator, member, sig)`**: 删除 `@env` / `@wasi_func`（零兼容）。env 写作 `@host("env", "name", sig)`；WASI 写作 `@host("wasi:package/interface@version", "member", sig)`（迁移默认 pin `0.3.0`）。内部 target 仍为 `package/interface/member`。stdlib / fixtures / `grammar.peg` / `spec_rules` §21–23 / `wasi_p3_lowering` / 诊断文案同步。

- Docs: record Wasm ref / host syntax strategy (no implementation) — `externref`→future `@host_ref`; no public `anyref`; no first-class `funcref`; i32 memory pointers never do types. See `doc/design/wasm_ref_host_syntax.md`, `pending_blocked` D10, `wasi_p3_lowering` note, `spec_rules` §21.1 pointer.

- G6.3 edge + regression hygiene: collect imported/module-local **payload enums** in codegen (`collectImportedPayloadEnumDecls`) so `@lib` wrappers may use intermediate `total IpSocketAddress = V4(addr)` before host bind; fixture `compile_ok/295`; stdlib tcp/udp bind helpers use intermediate total. `run_tests.sh` falls back to **bun** when `node` is missing; docs: `start_here` plan no longer waits on G6.3.

- **G6.3 sockets scheme B** (create/bind/drop): dual `Ipv4`/`Ipv6` address + payload enum `IpSocketAddress`; resource shells `TcpSocket`/`UdpSocket`; coarse `TcpError`/`UdpError`; stdlib `lib/tcp.do`/`lib/udp.do`/`lib/net.do`; known-table + `wasiLowering` + guest address pack; fixtures `compile_ok/291`–`294`; manifest tool marks sockets create/bind lowerable. Design: `docs/superpowers/specs/2026-07-13-g6-3-sockets-scheme-b-design.md`. Docs: G6.3 closed in `pending_blocked` / start_here / roadmap / wasi_p3_lowering / spec_rules. Non-goals remain: listen/connect, true host smoke (D2), G6.2 async.

- Branch-completeness audit (full `src/**/*.zig`, 2199 fns): check depth-split extracts keep full decision matrices (null/false/true fallthrough, error arms, multi-result LHS). Campaign extracts path-equivalent; tri-state `!?bool` call sites use `|handled| return handled`. No incomplete-branch fix required. Empirical: `zig test codegen_api.zig` 69; suite `pass=933 fail=0 skip=3`.

- Structure flatten (AGENTS): early-return + straight trunk; extract only complete nameable units. Re-inlined peel-off `advanceTupleCtorBodyDepth`. Kept nameable mid-layer units (loop-label stack events, tuple-ctor segment check, WASI error-enum arms, unmanaged struct payload, multi-result LHS). Depth is not a hard quota — do not tear last-layer blocks just to lower nest. Verify: Debug build; `zig test codegen_api.zig` 69 pass; full suite `pass=933 fail=0 skip=3`. No intentional semantic change.

- Guard-style + mid-layer extract (`src/build`): whole semantic units over peel-off micro-helpers (loop-label two passes, `emitIntrinsicCall` / `emitCoreOpArgs`, param/struct collect). Re-inlined single-call peels that split coherent logic. Aligns with early-return / nameable-boundary rule, not a nest-number quota. Verify: Debug build; `zig test codegen_api.zig` 69 pass; full suite.

- Batch B (worth-splitting one-shot): `gen_collect` → facade + `gen_collect_{util,struct,func,type}`; `sema_util` → facade + `sema_scan`; `sema_func` → facade + `sema_func_{sig,call,lambda,shared}`; `runtime_arc_wat` SSOT for ARC WAT/layout types (`runtime_prelude_wat` re-exports). Mutual peer cycles: none. Deferred: further `gen_storage`/`gen_expr`/`parser`/`imports`/`test_runner` splits (hooks coupling / high risk). Verify: Debug build; `zig test codegen_api.zig` 69 pass; full suite `pass=933 fail=0 skip=3`. Docs: `AGENTS.md`, `doc/start_here.md`.

- Gen A3: extract `codegen_generics.zig` (~56 fns: generic instantiate/bind/prebind, template match, result ABI) from `codegen_pipeline.zig` (~2.7k → ~1.1k orchestration). `codegen_pipeline` re-exports for tests/call-sites; generic uses `gen_expr.collectBodyLocals` (no import of lower). Docs: `AGENTS.md`, `doc/start_here.md`.

- Gen A2: extract `gen_expr_collect.zig` (~36 fns: `collectBodyLocals*`, loop locals, multi-result/callback collect helpers) from `gen_expr.zig` (~4.1k → ~3.2k). `gen_expr` re-exports for call-site stability; collect does not import expr. Verify: Debug build; `zig test codegen_api.zig` 69 pass; full suite.

- Gen A1: extract `gen_tuple.zig` (~28 pack helpers: tuple local get/set, leaf load/store/inc/dec, pure-scalar struct pack) from `gen_storage.zig` (~4.5k → ~3.9k). `gen_storage` re-exports for call-site stability; `TupleElementInfo` SSOT in `gen_tuple`. No mutual import with storage. Docs: `AGENTS.md`, `doc/start_here.md`.

- Guard-style flatten (codegen_pipeline/storage): generic callback prebind/bind (`prebindGenericCallbackArg` / `bindGenericCallbackArg`), start-body collect, unmanaged struct result ABI, `callArgMatchesCallbackShape` — early returns + helpers; no semantic change.

- Guard-style flatten (AGENTS nest ≤3): rewrite deep optional-if pyramids in `gen_union_emit` (`emitUnionValue` / `emitUnionBinding` / payload-enum ctor), `gen_ctrl` (`emitDiscardAssignment`), `gen_struct` (unmanaged error-union return), `gen_expr` (`collectLoopBlockLocals` / tuple get). Early returns + small helpers; no semantic change.

- Gen emit cycle break + lower thin: extend `gen_hooks` for reverse peer edges (`collectBodyLocalsWithMode`, multi-result assign, bare user-func call, union-binding move, union struct payload); `gen_ctrl` / `gen_union_emit` / `gen_struct` no longer import `gen_expr` / each other for those paths. Drop ~473 unused `codegen_pipeline` pub re-exports (~3.0k → ~2.6k). Mutual peer imports among gen emit modules: none. Verify: Debug build; `zig test codegen_api.zig` 69 pass; full suite.

- Sema domain split: extract flat modules from `sema.zig` (~9.5k → ~80-line orchestrator). New: `sema_util` (token/name/scan), `sema_types` (shared shapes), `sema_func`, `sema_struct`, `sema_type`, `sema_import`, `sema_ctrl`. Public API unchanged (`checkProgram` / `takeLastErrorSite` / `ErrorSite` via `sema.zig`). One-way deps; no peer mutual imports. Docs: `AGENTS.md`, `doc/start_here.md`, status notes.

- Gen domain split complete (Tasks 1–6): vertical extract of `gen_storage` / `gen_struct` / `gen_union_emit` / `gen_expr` / `gen_ctrl` plus `gen_hooks` late-bound callbacks; leaf domains do not import `codegen_pipeline`. `codegen_pipeline` ~19.3k → ~3.0k (orchestration + generic collect + re-exports). Verify: `zig build` Debug OK; `zig test src/build/codegen_api.zig` 69 pass; `./src/build/test/run_tests.sh` pass=933 fail=0 skip=3.

- Gen domain split (Tasks 1–4 partial): `gen_collect` (decl/layout collect); `gen_wasi_emit` (WASI host emit + `EmitExprFn`); `codegen_ownership` (release plans); `codegen_pipeline` ~16.9k→~15.0k. Storage/struct/union/expr vertical splits deferred (import cycles with `emitExpr`); leaf domains do not import `codegen_pipeline`.

- Gen Task 1: extract `gen_collect.zig` (struct/enum/func/layout collect + pack leaf helpers); `codegen_pipeline` ~19.3k → ~16.9k

- Continue gen split: `codegen_host_imports` (`@host("env", ...)` imports); `codegen_imports` (module resolve / reach / string-data); pure helpers into `gen_util`; free helpers + `ExprCallHead` into `gen_types`; rename `gen_impl` → `codegen_pipeline`

- Gen module split: `codegen_api.zig` (entry) + `gen_types.zig` (types/LocalSet) + `codegen_pipeline.zig` (emit/collect); keep `gen_util`/`gen_wasi`/`gen_union`

- Continue gen split: `gen_union.zig` (layout types/helpers); extend `gen_wasi` (call-shape / lowerability) and `gen_util` (type separators)

- Split `codegen_api.zig`: extract `gen_util.zig` (token helpers) and `gen_wasi.zig` (WASI tables/parse)

- Rename codegen modules to `gen_*` prefix: `codegen_api.zig`, `gen_payload_wat.zig`, `gen_storage_wat.zig`

- Payload enum L1: `Message = Quit | Text([u8]) | Binary([u8])` declare/construct/`@is` narrow (tags by case name)
  - sema: `isPayloadEnumDeclStart` + branch validation; codegen: tag+max-payload layout, unit/payload ctors
  - fixtures: `compile_ok/289`–`290`, `compile_err/339`; docs: `syntax/enum.md`, `grammar.peg`

- WASI C+D: stream hosts use coarse `StreamError` Err arms; docs inventory aligns preopens/stream preferred do forms
  - `lib/io.stream.do`: `[u8] | StreamError`, `u64 | StreamError`, `StreamError | nil`
  - docs: `preopens` lowerable; preferred examples use DirError/FileError/StreamError and `[Tuple<Dir,text>]`


本文只记录**最近仍需可追溯**的已完成变更。实时停点见 `doc/start_here.md`; 总规划见 `doc/master_plan.md`。  
更早条目已从仓库移除, 需要时查 git 历史。

## 2026-07-12

- 文档: WASI host 签名优先 do 联合 `Ok | Err` / `T | nil`
  - 推荐: resource/record 名 + 排他联合；禁止多返回作为 WASI result 模型；无 `wasi_result`/`wasi_option`/`@wasi_tuple`
  - 过渡: 已知 target 仍接受源码 `result<>`；manifest 仍存 WIT
  - 更新: `spec_rules` §21.1/§23、`wasi_p3_lowering` Declarative host surface、`grammar.peg` `WasiHostResult`

- 声明式 WASI 宿主绑定（stdlib 对齐）
  - 新形式: `@host(wasi locator, member, sig)` / `@wasi_resource` / `@wasi_record`（`@wasi_enum` 语法预留；粗 `DirError`/`FileError` 仍手写）
  - 已移除旧的裸 WASI host 别名；codegen 对已知 target 把 do 侧糖（`i32`/`[u8]`）规范为 WIT 签名
  - stdlib: `lib/time.do`、`dir.do`、`file.do`、`random.do`、`io.stream.do` 迁移；host 行保持 import 前缀
  - fixtures: `compile_ok/276_wasi_func_do_sig_and_resource`；私有字段收集覆盖 wasi_resource 声明
  - 文档: `grammar.peg`、`spec_rules` §21.1、`wasi_p3_lowering` declarative surface

- WASI G6.1 方案 A: `filesystem/preopens/get-directories`
  - host: `() -> list<tuple<descriptor,text>>` → do `[Tuple<i32,text>]` (`$__wasi_list_preopen_to_storage`)
  - 公开: `preopen_directories() -> [Tuple<Dir, text>]` (`lib/dir.do`); 调用方 `close_dir` 各根
  - component plan / core import / WIT (`use types.{descriptor}`) 可 lower
  - fixtures: `compile_ok/274`–`275`; 更新 `124` companion expects
  - 文档: `pending_blocked` G6.1 关闭; `wasi_p3_lowering` / start_here 同步

- codegen: **P1** 含 managed 字段的 struct 作 Tuple storage 直接子槽 (永不拍平)
  - `items [Tuple<Cell, u8>]` 且 `Cell` 含 `text` → pack 为 **4B ARC 句柄叶子** + 标量槽; 类型仍是 `Cell`, 不展开字段
  - put/get/path owning load 与 storage pack clone/free 走 `is_storage_pack` managed offset 表
  - 顺带修: multi-leaf pack 共用 `__tuple_pack_spill_i32` 导致 `text+u8` / `Cell+u8` 叶子互相覆盖 → 按叶子索引用 `_1/_2/_3` spill
  - fixtures: `compile_ok/273`, `ok/193` (`compiled_must_pass`); 删除旧 `compile_err/339`
  - 文档: `pending_blocked` P1 关闭; README / start_here / master_plan 同步

- 文档: 新增 `doc/pending_blocked.md` — 阻断 (G6)、待处理 (P2 泛型左侧反推 / skip)、延期非目标与硬约束; `start_here` / `roadmap_status` / `master_plan` / README 指向该文件

- codegen: pure-scalar 具名 struct 作为 Tuple storage **嵌套子槽** (永不拍平)
  - `items [Tuple<Point, u8>]` / `@put` / `@get` / path `@get(items, i, 0)` → `Point`
  - 局部 `Tuple` 槽用位置名 `$pair.0.x` / `$pair.0.y` / `$pair.1` (不是假字段 `v0`)
  - fixtures: `compile_ok/272`, `ok/192` (`compiled_must_pass`)

- codegen: Tuple 局部/参数槽位命名 `vN` → 位置下标 `N` (`$pair.0` 而非 `$pair.v0`)

- 规格: Tuple **永不拍平** 硬约束 — 嵌套 Tuple / struct 直接元素保持嵌套类型与 `@get` 路径; 禁止与扁平 Tuple 等同或隐式 coerce (`spec_rules` / `syntax/type` / `memory` / `start_here`)

- 文档: 删除已 drain 的 `doc/todo_non_g6.md`; 后置/可选并入 `start_here` §5–§6 与 `roadmap_status`

- codegen: 修复纯标量 struct 在 field 反射循环内 `out = @field_set(...)` 写错 local
  - 根因: 循环 collect 把已有 `struct_locals` 的 reassignment 误收成 `__field_*_` shadow; 写 `$out.n` 而 return 读 shadow
  - 修: `collectBodyLocals` 对已登记 `struct_locals` 跳过 inferred struct rebinding
  - 正例: `ok/191_json_from_json_pure_scalar` (`compiled_must_pass`)

- JSON: struct 字段 `u8` stringify/from_json 重载 (`ok/190_json_struct_u8_field`; 混合 managed 字段路径)
- LSP: hover 对当前文件类型声明/引用返回类型名 head (`src/lsp/hover.zig`)
- 非 G6 todo 清单 drain: push-on-advance 协议 + §9 阻断登记; release smoke 绿- 非 G6 日路径: `UnsupportedTupleStorageLeaf` 专用诊断 + 文档漂移收口
  - 裸 struct 等非 packable 叶子 `[Tuple]` storage 从泛化 `UnsupportedLowering` 拆出独立 code/summary/hint
  - 历史反例 `compile_err/339` 已由 P1 收回 (现 `compile_ok/273` / `ok/193`)
  - 文档: README / start_here / master_plan / roadmap_status / spec_rules / syntax/type 对齐「managed 叶子与 path chain 已落地」

- I2 后置 lowering: managed/`text` 叶子 `[Tuple]` storage + `@get(storage,i,j)` path chaining
  - scheme A 扩展: managed payload 叶子 pack 为 4 字节 handle; 合成 `is_storage_pack` layout 负责 clone/free 叶子 ARC
  - path chain: storage 元素基址保留在 `$__tuple_pack_base_tmp`, 再按直接元素索引 load
  - 正例: `compile_ok/270`–`271`, `compiled_ok/75`–`77`

- 清理旧文档与占位; 目录重命名 `lib`/`src`; 架构扁平拆分; 文档规范化

### 验证

```text
cd src && zig test main.zig
  → All 119 tests passed.
./src/build/test/run_tests.sh
  → pass=915 fail=0 skip=3
./src/build/test/run_release_smoke.sh
  → release smoke passed
```
