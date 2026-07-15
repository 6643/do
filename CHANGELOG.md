# Changelog

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
