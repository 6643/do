# Roadmap 执行状态

更新时间: 2026-06-25

执行原则: 按 `doc/master_plan.md` 的阶段规划和 `README.md` Roadmap 自上而下推进; 如果某项卡住或需要跳过, 必须在本文记录原因和后续恢复条件。

推进协议:

1. 每个阶段必须拆成可验证的小任务, 写入本文件对应阶段的 `阶段内小任务`。
2. 每次只推进一个小任务; 未完成当前小任务前, 不切到同阶段其他任务或下一阶段。
3. 小任务完成后, 立即把状态从 `[ ]` 改为 `[x]`, 并补充验证命令或阻塞原因。
4. 如果遇到阻塞, 在该小任务后标注 `blocked`, 写清阻塞证据、停止点和恢复条件。
5. 提交或交付前, 必须确认本文件的状态与代码、测试和文档同步。

总规划入口: `doc/master_plan.md`。历史摘要入口: `CHANGELOG.md`。本文只记录执行状态、证据、跳过原因和恢复条件。

## 01. 运行时内存模型

状态: done

结论: v1 managed handle、对象头、`type_id`、layout table 和 ARC 管理已落地到当前 build 子集。

证据:

- `doc/memory.md` 已定义 handle、0 sentinel、对象头 `rc/type_id`、layout table、ARC 插桩和 release worklist。
- `tool/build/codegen.zig` 已生成 `__arc_payload`、`__arc_rc`、`__arc_type_id`、`__arc_inc`、`__arc_dec`、`__arc_release` 和 layout helper。
- `tool/build/test/compile_ok/22_arc_bump_alloc_runtime_prelude.do` 到 `47_arc_struct_layout_table_runtime_prelude.do` 覆盖 allocator、对象头、refcount、release worklist 和 layout table。
- `tool/build/test/compile_ok/48_arc_managed_struct_alloc_lower.do` 到 `74_arc_storage_multi_return_duplicate_local_inc.do` 覆盖 managed struct、storage handle、局部 release、return move/copy 和多返回 ownership。
- `tool/build/test/compile_ok/121_defer_call_and_arc_block_lower.do` 覆盖 `defer` cleanup 先于被离开区域 ARC release 的 lowering 顺序。

阶段内小任务:

- [x] 定义 managed handle、0 sentinel、对象头和 layout table 规格。验证: `doc/memory.md`。
- [x] 在 codegen 中生成 ARC helper 和 layout helper。验证: `tool/build/codegen.zig`。
- [x] 覆盖 allocator 前置 runtime prelude 和 managed struct/storage release 基线。验证: `./tool/build/test/run_tests.sh`。

## 02. 内存分配器

状态: done

结论: v1 allocator 的 1KB block、bitmap small block、large span、free span split/merge 和空 small block 回收已落地到当前 build 子集。

证据:

- `doc/memory_layout_structs.md` 已定义 `SlotClassState`、`SmallBlock`、`LargeBlock`、`FreeBlock` 和 managed `Object` 布局。
- `tool/build/codegen.zig` 已生成 `__arc_alloc_small`、`__arc_alloc_large`、`__free_span_find`、`__free_span_split_tail`、`__free_span_merge_neighbors`、`__arc_release_small` 和 `__arc_release_large`。
- `tool/build/test/compile_ok/31_arc_allocator_split_runtime_prelude.do` 到 `43_arc_empty_small_block_reclaims_free_span_runtime_prelude.do` 覆盖 small/large allocation、slot class state、slot reuse、large span reclaim、free span reuse、unlink、split、merge 和 empty small block reclaim。

阶段内小任务:

- [x] 定义 small block、large span 和 free span 布局。验证: `doc/memory_layout_structs.md`。
- [x] 生成 small/large allocation 与 free span split/merge runtime helper。验证: `tool/build/codegen.zig`。
- [x] 覆盖 small slot reuse、large reclaim、free span reuse/unlink/split/merge。验证: `./tool/build/test/run_tests.sh`。

## defer 完整控制流与 ARC

状态: done

结论: `defer` 的 LIFO cleanup、跨 `return/break/continue` lowering、cleanup block 内 managed locals release 和基础 ARC release 顺序已落地到当前 build 子集。

证据:

- `tool/build/test/compile_ok/142_defer_lifo_multiple_cleanups_lower.do` 到 `150_defer_recv_loop_control_lower.do` 覆盖 cleanup 顺序、return、guard return、break、continue、labeled break、cleanup block、collection loop 和 recv loop。
- `tool/build/test/err/267_defer_call_requires_nil.do`、`274_imported_defer_call_requires_nil.do`、`288_defer_block_return.do`、`289_defer_block_break.do`、`290_defer_block_continue.do`、`304_defer_intrinsic_call.do`、`305_defer_non_call_expr.do` 覆盖非法 cleanup 形态。
- `tool/build/codegen.zig` 的 `emitDeferCleanupStack(...)`、`emitDeferCleanupStackThrough(...)`、`emitReturnStmt(...)`、`emitGuardReturnIf(...)` 和 `emitLoopControlJump(...)` 是当前 lowering 锚点。
- `./tool/build/test/run_tests.sh` 当前回归摘要为 `pass=652 fail=0 skip=70`。

阶段内小任务:

- [x] 支持 `defer call()` 与 `defer { ... }` 的前端校验。验证: err `267`、`274`、`304`、`305`。
- [x] 支持 LIFO cleanup 和 return / guard return cleanup lowering。验证: compile_ok `142` 到 `144`。
- [x] 支持 break / continue / labeled break / loop cleanup lowering。验证: compile_ok `145` 到 `150`。
- [x] 禁止 cleanup block 内 `return/break/continue`。验证: err `288` 到 `290`。

## 03. ARC / Perceus 完整分析

状态: done

结论: 当前已落地 ownership exit plan foundation、死 alias `inc/dec` 相消和保守 last-use move 子集。`tool/build/ownership.zig` 负责构造 `return`、guard `return`、fallthrough、block exit 和 loop control 的 release steps，`tool/build/codegen.zig` 消费这些 steps 并在可证明本地末次使用时跳过部分冗余 `inc`。完整 ownership IR / data-flow、跨函数唯一性证明和 FBIP `reuse` 仍未完成。

当前已完成边界:

- managed storage / managed struct 的 `inc/dec`。
- return move / copy 的基础 ownership。
- 局部变量 fallthrough、return、break、continue 和 `defer` cleanup 的 release 顺序。
- `tool/build/ownership.zig` 已定义 `ExitKind`、`ManagedLocalKind`、`ReleaseReason`、`ReleaseStep`、`ExitPlan` 和对应 builder。
- `tool/build/test/compile_ok/151_arc_return_partial_multi_move_lower.do` 到 `154_arc_continue_cross_scope_release_chain_lower.do` 已锁住 partial move return、nested fallthrough 和 cross-scope `break/continue` release chain。
- `tool/build/test/compile_ok/157_arc_storage_dead_alias_binding_elided_lower.do` 和 `158_arc_managed_struct_dead_alias_binding_elided_lower.do` 已锁住死 alias 绑定相消。
- `tool/build/test/compile_ok/159_*` 到 `212_*` 已覆盖 direct storage / managed struct overwrite、call 参数、binding、assignment、return call、union guard / nil expr、plain struct field read、field reflection read 和 managed struct field write 的保守 last-use move 子集。
- `tool/build/test/compiled_ok/21_*` 到 `42_*` 已覆盖对应 compiled execution 子集。
- `RUN_WASM=1 SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 当前回归摘要为 `pass=653 fail=0 skip=70`。

当前未完成:

- 还没有完整 ownership IR、ownership graph 或跨 block / 跨函数 data-flow pass。
- last-use move 只覆盖当前可证明的本地 direct managed 子集；参数、借用、helper/shared-source 字段读取仍保持保守 `inc`。
- loop / collection loop / recv loop / field reflection loop 内的 call 参数 move 仍保持保守，避免把 loop-carried source 误判成末次使用；collection loop / recv loop 已补回归锁住该边界。
- 还没有 FBIP `reuse`、escape analysis 或 region。

继续条件:

- 若实现字段读取 move 扩展，必须按 `doc/memory.md` 第 8.5 节的唯一拥有 / alias 证明执行，不能只按语法末次使用放开。
- 若继续扩 loop 内 move，先建立 loop-carried source 分析或更强的 data-flow 边界。
- FBIP `reuse` 必须在 ownership、mutability 和 COW 回退条件都明确后单独推进。

阶段内小任务:

- [x] 03.1 建立 ownership exit plan foundation。验证: `tool/build/ownership.zig`, compile_ok `151` 到 `154`。
- [x] 03.2 落地死 alias `inc/dec` 相消。验证: compile_ok `157`、`158`。
- [x] 03.3 落地 direct managed overwrite / call / binding / assignment / return call 的保守 last-use move 子集。验证: compile_ok `159` 到 `185`, compiled_ok `21` 到 `33`。
- [x] 03.4 落地 union guard / nil expr、plain struct field read、field reflection read 和 managed struct field write 的保守 last-use move 子集。验证: compile_ok `186` 到 `212`, compiled_ok `34` 到 `42`。
- [x] 03.5 设计唯一拥有 / alias 证明, 只给可证明唯一的字段读取 move 放开边界。验证: `doc/memory.md` 第 8.5 节。
- [x] 03.6 基于 03.5 实现字段读取 move 扩展, 补 compile_ok 和 compiled_ok 回归。验证: 现有 codegen 已按 `doc/memory.md` 第 8.5 节执行 fresh-owner 字段读取 move; 新增 compile_ok `213` 到 `215` 锁住 helper/shared-source、非退出 loop-carried source 和同语句多字段读取拒绝边界; 现有 compiled_ok `39` 到 `42` 覆盖 fresh local 字段读取 move 执行路径; `./tool/build/test/run_tests.sh` 结果 `pass=655 fail=0 skip=70`。
- [x] 03.7.1 盘点 loop-carried source 现状和设计边界。验证: `doc/memory.md` 第 8.6 节; `tool/build/codegen.zig` 的 `emitBody(...)`、`emitLoopBlock(...)`、`emitCollectionLoopBlock(...)`、`emitRecvLoopBlock(...)`; 现有 compile_ok `166`、`167`、`214` 和 compiled_ok `24`。
- [x] 03.7.2 补 collection loop / recv loop 内 call 参数保守回归, 锁住 managed value binding 和 loop source 不 move。验证: 新增 compile_ok `216` 到 `218` 覆盖 collection loop source、collection loop managed value binding 和 recv loop managed value binding; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 结果 `pass=658 fail=0 skip=70`。
- [x] 03.7.3 设计最小 LoopMoveAnalysis 输入/输出, 明确 source origin、path exit、use-after、cleanup 四类证明。验证: `doc/memory.md` 第 8.7 节; 当前设计要求显式 source origin 元数据, 默认 reject, 不改 codegen。
- [x] 03.7.4 决定是否落地 loop 内 return / break 退出路径的局部 move; 若证据不足, 明确延后到完整 ownership IR。结论: 不落地局部 move, loop body 内 call 参数继续保守 `inc`; 缺显式 source origin enum、break 目标后 use-after 扫描和 loop control release skip 证明。验证: `doc/memory.md` 第 8.8 节; `tool/build/codegen.zig` 的 `Local` / `StructLocal` / `StorageLocal` / `UnionLocal`、`directManagedCallLastUseMoveSource(...)`、`emitBody(...)`、`emitLoopControlJump(...)`; `tool/build/ownership.zig` 的 `buildLoopControlExitPlan(...)`。
- [x] 03.8 决定是否引入完整 ownership IR / graph / data-flow pass。结论: 当前不一次性引入完整 IR, 先走增量 `OwnershipFacts` / source-origin metadata 路径; 完整 IR 仅作为 path/cleanup facts 无法表达时的触发项。验证: `doc/memory.md` 第 8.9 节; `tool/build/codegen.zig` 的 `Local` / `StructLocal` / `StorageLocal` / `UnionLocal`、`directManagedCallLastUseMoveSource(...)`、`emitBody(...)`; `tool/build/ownership.zig` 的 `ExitPlan` / `ReleaseStep` 和 `buildLoopControlExitPlan(...)`。
- [x] 03.8.1 增加只读 `SourceOrigin` 元数据, 默认 `unknown`, 不改变 lowering。验证: `doc/memory.md` 第 8.10 节; `tool/build/codegen.zig` 已给 `Local` / `StructLocal` / `StorageLocal` / `UnionLocal` 增加 origin 字段, 并在参数、collection value、recv value、loop source、compiler temp 等有直接证据的入口做只读标注; `cd tool && zig test build/codegen.zig` 结果 `All 1 tests passed.`; 集成回归需继续保持 `pass=658 fail=0 skip=70`。
- [x] 03.8.2 盘点并标注现有 move candidate 的 origin 来源, 继续保持旧输出。验证: `doc/memory.md` 第 8.11 节; `tool/build/codegen.zig` 的 `LastUseManagedMoveSource`、`directManagedLastUseMoveSource(...)`、`directManagedCallLastUseMoveSource(...)`、`directManagedUnionBindingCallMoveSource(...)`、`fieldGetLastUseMoveSource(...)`; `cd tool && zig test build/codegen.zig` 结果 `All 13 tests passed.`; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 待继续保持绿色。
- [x] 03.8.3 设计 path/cleanup facts 与 release plan skip 的最小接口, 再决定是否允许 return-only loop move。验证: `doc/memory.md` 第 8.12 节; `tool/build/ownership.zig` 已引入 `PathCleanupFacts`、`buildReturnExitPlanWithFacts(...)`、`buildGuardReturnExitPlanWithFacts(...)`、`buildFallthroughExitPlanWithFacts(...)`、`buildBlockExitPlanWithFacts(...)` 和 `LoopFrame.path_facts`; `tool/build/codegen.zig` 已切到新 builder 且默认 facts 不改变 lowering; `cd tool && zig test build/ownership.zig` 结果 `All 2 tests passed.`; `cd tool && zig test build/codegen.zig` 结果 `All 13 tests passed.`; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 待继续保持绿色。
- [x] 03.8.4 若 03.8.3 仍无法表达, 先收口完整 ownership IR 的启动边界与阻断条件, 暂不落实现。验证: `doc/memory.md` 第 8.13 节; 当前阻断仍是 `cleanup_visible` 未接入 move allow、`emitBody(...)` 仍依赖 `loop_ctx == null`、`break` / `continue` 后 use-after 扫描不足、同语句多候选点逐点 move 顺序不可表达; 完整 ownership IR 仅在 path/cleanup facts 无法继续扩展、证明逻辑重复蔓延、或需要跨 block / loop / call 统一唯一性证明时启动。
- [x] 03.9 单独设计 FBIP `reuse` 的 mutability、COW 回退和 `rc == 1` 条件。结论: `reuse` 只作为实现优化, 仅在 `rc == 1`、写路径允许原地更新、且中间状态不可观察时才可使用; `rc > 1`、容量不足、layout 不支持原地替换或 child release 次序不稳定时必须回退到现有 COW / overwrite 逻辑。验证: `doc/memory.md` 第 11.1 节; 当前不新增实现, 只收口设计边界。

## 04. 标准库边界

状态: done

结论: `[u8]`、`List`、`HashMap`、IO、网络类型形态和 `text` runtime 的 core / std / runtime 边界已收敛到当前 v1 子集。完整 I/O 执行能力、真实网络 host ABI 和复杂 WIT lowering 不在本项内, 继续归入最后的 WASI / Component Model。

证据:

- `src/_.do` 是 compiler 隐式加载的 builtin/core 声明表, 明确 core 固定名和 storage primitive, 且不是普通 import target。
- `doc/spec_rules.md` 第 14 章已定义标准库草案边界: core 固定名不可由 std 补充或遮蔽, 纯 do 基础库不依赖 host ABI, 资源库公开层只暴露 do 自己的结构、错误枚举和 wrapper 函数。
- `src/bytes.do`、`src/text.do`、`src/list.do`、`src/set.do`、`src/hash_map.do`、`src/mem.do`、`src/atomic.do` 等文件已经按普通 std 函数承载 `[u8]`、集合、text 边界和 buffer/atomic 语义辅助。
- `src/file.do`、`src/dir.do`、`src/io.stream.do` 用私有 `.host_* = @wasi(...)` 承接已登记 binding, 公开 API 返回 do 层 `File/Dir/InputStream/OutputStream`、错误枚举和多返回值形态。
- `src/tcp.do`、`src/udp.do`、`src/http.client.do` 当前只声明 do 层类型与错误形态, 不在源码里手写复杂 raw WIT host ABI。
- `tool/build/test/ok/109_std_foundation_libs.do`、`111_bytes_text_common_wrappers.do`、`112_slice_range_common_wrappers.do`、`113_set_common_ops.do`、`114_list_common_ops.do`、`115_hash_map_common_wrappers.do`、`118_wasi_p3_std_wrappers.do` 覆盖基础库、bytes/text、集合和资源 wrapper 形态。

阶段内小任务:

- [x] 固定 core / std / runtime 边界, 明确 `src/_.do` 不是普通 import target。验证: `doc/spec_rules.md`。
- [x] 收敛 bytes/text/list/set/hash_map/mem/atomic 基础库外形。验证: `src/*.do` 和 ok `109` 到 `115`。
- [x] 收敛 file/dir/stream 资源 wrapper 外形。验证: ok `118`。
- [x] 把真实网络 host ABI 后置到 WASI / Component Model。验证: 本文件第 06 阶段。

## 05. 后端优化

状态: done

结论: 当前后端阶段已在独立 `tool/build/backend_ir.zig` 内收口最小 IR 骨架、控制流折叠、accessor 风格 copy fold 和 trivial const inline 回归。`tool/build/run.zig` / `tool/build/codegen.zig` 仍以 WAT 文本作为公开输出边界, direct wasm binary emitter 经评估后暂不在本阶段落地。

当前已保留的正确性能力:

- `if/else/else if`、`loop`、`break/continue` 和 `return` 的 WAT lowering。
- `@get/@set/@put`、storage、managed struct、multi-return 和 imported wrapper 的 WAT lowering。
- `do build` 和 `do test --compiled` 的 WAT 输出。

若未来重开后端优化:

- 先让 `backend_ir.zig` 成为更完整的 codegen 输入边界, 再考虑接入新的 lowering 或 emitter。
- 若未来单独重开 binary output, 必须连同 CLI 输出形态、WAT/WASM 测试链和 component 相关 gate 一并设计与回归。

阶段内小任务:

- [x] 05.1 设计 backend instruction model 或稳定 IR 输入输出。验证: `tool/build/backend_ir.zig` 已新增最小独立后端 IR 骨架, 覆盖 function / block / instr / terminator / value id, 且 `cd tool && zig test build/backend_ir.zig` 结果 `All 2 tests passed.`; 当前仍未接入 `codegen.zig`, 只作为后续优化的稳定输入输出边界。
- [x] 05.2 在 IR 基础上实现控制流优化回归。验证: `tool/build/backend_ir.zig` 已新增 `foldEmptyBranchBlocks(...)`, 覆盖空 branch-only block 折叠和非空 block 保留两条回归; `cd tool && zig test build/backend_ir.zig` 结果 `All 4 tests passed.`; 当前仍未接入 `codegen.zig`, 只在独立 IR 模块内验证 CFG 优化边界。
- [x] 05.3 在 IR 基础上实现 `@get/@set` 和小函数内联回归。验证: `tool/build/backend_ir.zig` 已新增 `foldRedundantLocalCopies()` 和 `inlineTrivialConstCalls()`, 覆盖 accessor 风格 copy fold 与 trivial const callee inline 两条独立回归; `cd tool && zig test build/backend_ir.zig` 结果 `All 6 tests passed.`; 当前仍未接入 `codegen.zig`, 只在独立 IR 模块内验证最小内联边界。
- [x] 05.4 评估直接 wasm binary emitter。结论: 当前继续保留 WAT 文本输出, 暂不新增 direct wasm binary emitter。依据: `tool/build/run.zig` 仍直接调用 `codegen.emitWatWithOptions(...)`, `tool/build/codegen.zig` 仍以字符串方式拼接 WAT, `tool/build/test/run_tests.sh` 也以 `wasm-tools parse` 把 WAT 转成 wasm 再执行回归; 说明现有产物、测试和回归 gate 都围绕文本 WAT, 不是 binary writer 路径。恢复条件: 当需要独立 wasm writer、绕过 WAT parse, 或出现明确的性能/体积瓶颈时, 再单独立项。

## 06. WASI / Component Model FFI

状态: deferred

延后原因: 用户已明确要求 WASI 不是现阶段目标, 放到最后处理。

当前保留的守门能力:

- `doc/wit/wasi_p3_lowering.md` 固定当前 `@wasi` / WIT / component lowering 的 compiler-facing 合同, 明确哪些 binding 已可 lower, 哪些仍是 unsupported。
- `doc/wit/wasi_registry.json` 是当前已登记 WIT target / record mirror registry, 供 manifest 校验与 component-plan 工具消费。
- `tool/build/test/validate_wasi_bind_manifest.mjs` 已能对 `wasi-bind` manifest 做 registry 校验, 并生成 `--json`、`--component-plan`、`--wit`、`--core-imports`、`--core-shims` 和 `--component-input-dir` 产物。
- `tool/build/test/run_tests.sh` 已把 `doc/wit/wasi_registry.json` 接入 WASI manifest / component-input / component-core 回归 gate。
- `tool/build/test/ok/118_wasi_p3_std_wrappers.do` 与相关 `compile_ok/*.component_*` 用例覆盖当前公开 wrapper 子集和 component builder 输入验证链。

阶段内小任务:

- [x] 固定当前 `@wasi` / WIT / component lowering 的 compiler-facing 合同。验证: `doc/wit/wasi_p3_lowering.md`。
- [x] 接入 WIT registry 和 manifest/component-plan 校验。验证: `doc/wit/wasi_registry.json`, `tool/build/test/validate_wasi_bind_manifest.mjs`。
- [x] 覆盖当前 std wrapper 子集。验证: ok `118` 和相关 compile_ok component 输出。
- [ ] 06.1 设计完整 binding source / alias 规则。blocked: 用户要求 WASI 放到最后。
- [ ] 06.2 设计 result-area、resource、variant、future lowering。前置: 06.1。

## 07. 生态工具

状态: partial

当前结论: `do check <input.do>...` 第一版已落地, 当前复用 LSP diagnostics collector 执行 lexer/parser/sema/import 检查, 支持按命令行顺序检查多个文件, 不编译、不运行、不要求 `start()` 或 `test` 声明。`do run <input.do>` 第一版已落地, 执行策略固定为外部 `wasm-tools + node` 桥接。`do fmt <input.do>` 第一版已落地, 当前支持 stdout 输出、`--check` 检查和 `--write` 单文件原地写回。`do lsp [--stdio]` 第一版已落地, 当前做 diagnostics + formatting + semantic tokens stdio server。get / pkg / push 包管理线已按用户要求暂停, 不作为当前阶段继续目标。

`do check` 当前边界:

- 命令形态: `do check <input.do>...`。
- 诊断来源: 复用 `tool/lsp/diagnostics.zig` 的 lexer/parser/sema/imports fail-fast 链路。
- 成功行为: 所有输入成功时无输出, exit 0。
- 失败行为: 失败输入输出第一条现有 compile diagnostic 格式; 遇错不 fail-fast, 继续检查后续输入; 最终 exit 1。
- 不包含: `start()` 入口校验、`test` 声明要求、WAT/codegen、运行测试、watch 模式、workspace mode 或多诊断聚合。

`do run` 当前边界:

- 编译路径: 复用 `do build` 同源 WAT 编译 helper。
- 执行路径: 写临时 WAT, 调用 `wasm-tools parse` 生成 wasm, 再由 `node tool/run/run_wasm_program.mjs` 执行。
- 依赖策略: 本机 PATH 必须可找到 `wasm-tools` 和 `node`; 缺失时输出 `error[MissingExternalTool]: <tool> not found`。
- 行为边界: stdout/stderr/exit status 透传子进程结果; 当前只覆盖 `tool/build/test/run/*.do` 的 core wasm smoke 子集。
- 不包含: WASI / Component Model runtime、自定义 host runtime、内置 wasm runtime、真实网络或完整资源 ABI。

`do fmt` 当前边界:

- 命令形态: `do fmt <input.do>` 输出格式化后的源码到 stdout; `do fmt --check <input.do>` 只检查输入是否已格式化; `do fmt --write <input.do>` 原地写回单文件。
- 格式化范围: 第一版 line-based formatter, 覆盖 CRLF/CR -> LF、尾随空白清理、基于 `{}` 的 4 空格缩进、最终单换行和当前行字符串缩进保留策略。
- 回归范围: `tool/build/test/fmt/*.do` / `.expect` 覆盖 stdout、write、idempotence 和 `error[FormatMismatch]`。
- 不包含: 多文件批量、stdin/stdout 自动模式、范围格式化、语法感知 comment/string brace 解析。

`do lsp` 当前边界:

- 命令形态: `do lsp` 和 `do lsp --stdio` 启动 stdio LSP server。
- 诊断来源: 复用 lexer/parser/sema/imports fail-fast 链路, 每个 document 当前最多发布一个编译诊断。
- 已支持 formatting, 返回全量 `TextEdit` 覆盖整个文档。
- 已支持 semantic tokens full, legend 固定为 keyword/type/function/parameter/variable/field/property/string/number/comment/operator/builtin, 当前不支持 delta tokens。
- 回归范围: `tool/build/test/lsp/*.json` 通过 `tool/build/test/run_lsp_case.mjs` 驱动 `bin/do lsp` smoke。
- 不包含: completion、hover、definition、rename、workspace index 和完整语言服务。

get / pkg / push 暂停边界:

- 暂停原因: 用户在 2026-06-17 明确要求“先不要搞包管理这一套。get, pkg, get, push”。
- 当前代码状态: 不注册 `do get` / `do push` CLI, 不保留 `tool/pkg` 包管理实现, 不接入 package smoke regression。
- 当前文档状态: 包管理设计计划不再作为下次启动入口; 历史 get/push 计划和 spec 文件已清理。
- 恢复条件: 只有用户明确要求重开包管理线时, 才重新设计并从新计划开始。

阶段内小任务:

- [x] 07.1 落地 `do run` 第一版执行环境、依赖策略、stdout/stderr/exit 行为和 host import 支持范围。验证: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, `do run missing wasm-tools`、`do run missing node` 和 6 个 `do run` smoke case 均执行, 摘要 `pass=666 fail=0 skip=70`。
- [x] 07.2.1 明确 fmt 格式化规范和稳定输出回归。验证: 当前 formatter 边界已收敛进 README、`CHANGELOG.md` 和本节 `do fmt` 当前边界; 历史 fmt plan/spec 已清理, 不再作为活跃入口。
- [x] 07.2.2 实现 `do fmt` CLI contract。验证: `cd tool && zig test build/cli.zig` 通过 `6/6`; `cd tool && zig test main.zig` 通过 `3/3`; `cd tool && zig build -Doptimize=Debug` 通过。当前 `tool/fmt/run.zig` 仅为最小 runner 骨架, 真实格式化输出继续按 Task 2/3 推进。
- [x] 07.2.3 实现 pure formatter core。验证: `tool/fmt/format.zig` 已新增 `formatSource(allocator, source)` 和三条 focused tests; `cd tool && zig test fmt/format.zig` 通过 `3/3`; `cd tool && zig test main.zig` 通过 `3/3`。
- [x] 07.2.4 实现 `tool/fmt/run.zig` 命令 runner。验证: `cd tool && zig test fmt/format.zig` 通过 `3/3`; `cd tool && zig test main.zig` 通过 `3/3`; `cd tool && zig build -Doptimize=Debug` 通过; 临时文件实测 `do fmt` stdout 输出、`do fmt --check` 成功和 mismatch `error[FormatMismatch]` 均符合计划。
- [x] 07.2.5 接入 fixture 回归、idempotence 和 `--check` 覆盖。验证: `tool/build/test/fmt/01_struct_func_indent.do`、`tool/build/test/fmt/02_comments_line_strings.do`、`tool/build/test/fmt/03_control_blocks.do` 及其 `.expect` 已接入 `tool/build/test/run_tests.sh`; `bash -n tool/build/test/run_tests.sh` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, `fmt` 段三例均通过, 总摘要 `pass=669 fail=0 skip=70`。
- [x] 07.2.6 同步 README、start_here 和最终验证。验证: `README.md` 已记录 `do fmt <input.do>`、`do fmt --check <input.do>` 和 stdout/check-only 边界; `doc/start_here.md` 下一步已切到 `07.3 LSP`; 最终验证通过: `cd tool && zig test build/cli.zig` 6/6, `cd tool && zig test fmt/format.zig` 3/3, `cd tool && zig build -Doptimize=Debug`, `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 摘要 `pass=669 fail=0 skip=70`。
- [x] 07.3.0 明确 LSP 最小能力集和诊断来源。结论: 当时第一版只覆盖 diagnostics stdio server, 未覆盖 completion / hover / definition / rename / formatting; 后续 A1 已补 `textDocument/formatting`。诊断来源复用 lexer/parser/sema/imports fail-fast 链路, 当前每个 document 最多发布一个编译诊断。验证: 当前 LSP 边界已收敛进 README、`CHANGELOG.md` 和本节 `do lsp` 当前边界; 历史 LSP plan 已清理, 不再作为活跃入口。
- [x] 07.3.1 固定 `do lsp [--stdio]` CLI contract。验证: `cd tool && zig test build/cli.zig && zig test main.zig` 通过; `cli` 9/9, `main` 3/3。备注: `tool/lsp/run.zig` 当前只是参数解析 stub, 真实 stdio server 留到 07.3.5。
- [x] 07.3.2 暴露结构化 compiler diagnostics。验证: `cd tool && zig test build/diag.zig && zig test build/cli.zig && zig test main.zig` 通过; `diag` 12/12, `cli` 9/9, `main` 3/3。备注: `printCompileError(...)` 已改为从 `CompileDiagnostic` 打印, 后续 LSP collector 复用同一 summary/hint。
- [x] 07.3.3 实现纯 LSP diagnostics collector。验证: `cd tool && zig test main.zig && zig test build/diag.zig && zig test build/cli.zig` 通过; `main` 27/27, `diag` 12/12, `cli` 9/9。备注: `tool/lsp/diagnostics.zig` 通过 `main.zig` 聚合测试覆盖; 直接 `zig test lsp/diagnostics.zig` 会因当前 Zig 单文件 import 规则拒绝 `../build/...` sibling import。
- [x] 07.3.4 实现最小 JSON-RPC/LSP protocol helper。验证: `cd tool && zig test main.zig && zig test build/diag.zig && zig test build/cli.zig` 通过; `main` 29/29, `diag` 12/12, `cli` 9/9。备注: `tool/lsp/protocol.zig` 通过 `main.zig` 聚合测试覆盖; 当前已支持 initialize/shutdown response 和 publishDiagnostics frame 输出。
- [x] 07.3.5 实现 `do lsp` stdio server。验证: `cd tool && zig test main.zig` 通过 `main` 32/32; `cd tool && zig test build/diag.zig` 通过 `diag` 12/12; `cd tool && zig test build/cli.zig` 通过 `cli` 9/9; `cd tool && zig build -Doptimize=Debug` 通过。附加 smoke: 临时 Node 脚本通过 stdio 驱动 `./bin/do lsp`, initialize / didOpen syntax error / shutdown / exit 通过, stdout 包含 initialize response、publishDiagnostics 和 `UnterminatedString`, stderr 为空。备注: 进程级 fixture harness 留到 07.3.6。
- [x] 07.3.6 接入 LSP smoke regression harness。验证: `node tool/build/test/run_lsp_case.mjs ./bin/do tool/build/test/lsp/01_open_valid.json`、`02_open_syntax_error.json`、`03_change_clears_diagnostic.json` 均通过; `bash -n tool/build/test/run_tests.sh` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, LSP 三例均 PASS, 摘要 `pass=672 fail=0 skip=70`。
- [x] 07.3.7 同步 README、测试说明、roadmap 和 start_here。验证: `README.md` 已记录 `do lsp [--stdio]` diagnostics 边界; `tool/build/test/README.md` 已记录 `lsp/*.json` fixture 和 `run_lsp_case.mjs`; 最终验证通过: `bash -n tool/build/test/run_tests.sh`, `cd tool && zig test main.zig` 32/32, `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 摘要 `pass=672 fail=0 skip=70`。
- [x] 07.4.0 暂停 get / pkg / push 包管理线并清理活跃实现。验证: `tool/build/cli.zig` 不再导出 `parseGet/parsePush`; `tool/main.zig` 不再注册 `get/push`; `tool/build/test/run_tests.sh` 不再接入 package fixture; `tool/pkg`、`tool/get/run.zig`、`tool/push/run.zig` 和历史 get/push 计划/spec 文件已删除。
- [x] 07.5.0 落地 `do check <input.do>` 前端诊断命令。验证: TDD 红灯 `cd tool && zig test build/cli.zig` 失败于 `parseCheck` 未定义; `cd tool && zig test main.zig` 失败于 `check/run.zig` 缺失。绿色验证: `cd tool && zig test build/cli.zig` 11/11, `cd tool && zig test main.zig` 33/33, `cd tool && zig test env.zig` 1/1, `cd tool && zig build -Doptimize=Debug`, 手动 `do check` valid fixture 静默成功、syntax fixture 输出 `error[UnterminatedString]`。
- [x] 07.next 重新制定总规划并细化各阶段小任务。验证: `doc/master_plan.md` 已作为 active 总规划入口, 覆盖阶段 A-H、阶段内小任务、非目标、主要文件和验收命令; 当时默认从阶段 A 的 A2 LSP semantic tokens 第一版继续, 当前 A2 已完成并切到 A3; 禁止默认回到 get / pkg / push。
- [x] A1.1 新增 LSP formatting 请求 fixture, 先红灯验证当前不支持。验证: `tool/build/test/lsp/04_formatting_request.json`; 先以旧二进制复现 `Method not found`, 再在新二进制上通过 formatting response.
- [x] A1.2 扩展 LSP protocol helper, 支持 formatting response 和全量 `TextEdit` 编码。验证: `cd tool && zig test main.zig` 覆盖 `writeTextEditsResponse emits formatting edit payload`。
- [x] A1.3 在 `tool/lsp/run.zig` 接入 `textDocument/formatting` handler, 复用 `tool/fmt/format.zig`。验证: `cd tool && zig test main.zig` 覆盖 `handleMessage formats open document`; LSP fixture `04_formatting_request.json` 返回格式化文本。
- [x] A1.4 让 LSP fixture 回归断言 formatting response。验证: `node tool/build/test/run_lsp_case.mjs ./bin/do tool/build/test/lsp/04_formatting_request.json` 通过。
- [x] A1.5 同步 README、测试说明、master_plan、roadmap 和 start_here。验证: 当时文档已记录 `do lsp` 支持 formatting, 并切到 A2 semantic tokens; 当前 A2 已完成。
- [x] A2.1 固定 semantic token legend 顺序和 token modifier 空集合。验证: `cd tool && zig test main.zig` 通过, 覆盖 `semantic token legend order is stable`。
- [x] A2.2 新增纯 token builder 单元测试, 覆盖 delta line / delta start 编码。验证: 先红灯失败于 `legendTokenTypes` / `SemanticToken` 未定义; 最小实现 `tool/lsp/semantic_tokens.zig` 后 `cd tool && zig test main.zig` 通过 `43/43`。
- [x] A2.3 接入当前文件 lexer token 分类。验证: 先红灯失败于 `collectSemanticTokens` 未定义; 最小实现后 `cd tool && zig test main.zig` 通过 `44/44`, 覆盖 keyword / variable / number / string / operator 分类。
- [x] A2.4 对 builtin `@xxx`、类型名、函数名和字段名做最小语义覆盖。验证: 先红灯失败于 `User` 仍为 variable; 增加上下文分类后 `cd tool && zig test main.zig` 通过 `45/45`, 覆盖 type / function / builtin / field。
- [x] A2.5 新增 LSP fixture 检查 initialize legend 和 token data 非空。验证: 先红灯 `node tool/build/test/run_lsp_case.mjs ./bin/do tool/build/test/lsp/05_semantic_tokens_request.json` 缺少 `semanticTokensProvider` 且 full 请求返回 `Method not found`; 接入 protocol/run 后同命令通过。
- [x] A2.6 同步 README、测试说明、master_plan、roadmap、start_here 和 changelog。验证: `cd tool && zig test main.zig` 通过 `46/46`; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, LSP 五例均 PASS, 总摘要 `pass=672 fail=0 skip=70`。
- [x] A3.1 为 CLI 增加 `--write` 解析红灯测试。验证: 先红灯失败于 `FmtArgs` 缺少 `write` 字段; 增加 `--write` 解析和 `--check` 互斥后 `cd tool && zig test build/cli.zig` 通过 `13/13`。
- [x] A3.2 在 formatter runner 中实现原地写回。验证: 先红灯失败于 `formatPath` 未定义; 抽出可测 `formatPath` 并接入 `--write` 后 `cd tool && zig test main.zig` 通过 `47/47`。
- [x] A3.3 新增临时目录黑盒测试, 验证写回内容和幂等。验证: `tool/build/test/run_tests.sh` 的 fmt 段已对每个 fmt fixture 执行 `do fmt --write` 临时文件写回、内容 diff 和二次写回幂等; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, fmt 三例均 PASS, 总摘要 `pass=672 fail=0 skip=70`。
- [x] A3.4 同步 README、测试说明、roadmap、master_plan、start_here、CLI usage 和 changelog。验证: `cd tool && zig test build/cli.zig && zig test main.zig` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 总摘要 `pass=672 fail=0 skip=70`。
- [x] A4.1 为多个 input 的 CLI parsing 增加红灯测试。验证: 先红灯失败于 `CheckArgs` 缺少 `input_paths`; 改为 `input_paths` 切片并接受多个非 flag 参数后 `cd tool && zig test build/cli.zig` 通过 `14/14`。
- [x] A4.2 调整 `tool/check/run.zig`, 顺序执行每个文件。验证: 增加 `checkPaths` helper 和多输入单元测试; 当前策略为不 fail-fast, 遇错记录失败后继续检查后续输入, 最后由 CLI exit 1; `cd tool && zig test main.zig` 通过 `48/48`。
- [x] A4.3 黑盒 fixture 覆盖全部成功、后一个失败、前一个失败后仍继续的策略。验证: `run_check_multi_case` 复用 check fixture 并复制两个不同 bad 文件证明不 fail-fast; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, `check multi` PASS, 总摘要 `pass=673 fail=0 skip=70`。
- [x] A4.4 同步 README、测试说明、roadmap、master_plan、start_here、CLI usage 和 changelog。验证: `cd tool && zig test build/cli.zig && zig test main.zig` 通过; stale scan 未发现当前入口仍把 `do check` 描述为单文件-only。
- [x] A5.1 扫描 README、start_here、roadmap_status 的命令和边界描述。验证: 当前入口已覆盖 `do run`、`do fmt` stdout/check/write、`do check` 单/多文件、`do lsp` diagnostics/formatting/semantic tokens, 未把 get/push 描述为可用命令。
- [x] A5.2 修正过期的工具链描述。验证: stale scan 未发现活跃入口仍使用 diagnostics-only、fmt 不支持 write、check 单文件-only 或下一步指向 A2/A3/A4 的过期表述。
- [x] A5.3 执行 full regression 并记录摘要。验证: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, `fmt` 三例、`check multi`、LSP 五例均 PASS, 总摘要 `pass=673 fail=0 skip=70`。

## 阶段 B: 语法和语义冻结审查

状态: done

当前结论: 阶段 B 已完成。B1 grammar / parser 差异审查的五个问题已按用户接受的推荐方案落地; B2 spec_rules / sema 差异审查的 6 个问题已按推荐方案全部落地; B3 已完成语法文档治理; B4 已完成语法冻结回归包和 full regression。`@as` 只保留 `@as(Type, value)` 标量转换; `@is` 固定为条件位 special form; 普通集合循环必须写 `loop value, index = source`; import 前置区块检查下沉到 parser; 后续 C2 计划已移除 `@field_type` 主线。已解决的问题文件已删除。

B2 spec_rules / sema 差异审查的 6 个问题已按推荐方案全部落地。第 1 项“绑定遮蔽和重复名”、第 2 项“字段反射 metadata 来源”、第 3 项“`@is(value, A | B)` 目标集合”、第 4 项“复合条件和 enum/nil 收窄”、第 5 项“普通多 payload union 可用边界”和第 6 项“泛化诊断”均已同步实现、fixture 和诊断。已解决的 B2 问题清单文件已删除。

已落地决定:

- P1 `@as`: 删除 PEG 旧 payload 提取形态和 sema 旧兼容判断, 只保留 `@as(Type, value)`。
- P1 `@is`: 从普通表达式 builtin 中移除, parser 增加条件位解析路径, 并修正冲突 fixture。
- P1 collection loop: parser 禁止普通集合 RHS 使用单绑定; 单绑定只保留给 `recv(...)` 和 `fields(TypeOrTypeParam)`。
- P2 import: import 前置区块由 parser 直接校验, sema 不再重复承担该语法边界。
- P2 field reflection plan: C2 以后按 `fields(...)` + `@field_get/@field_set` 静态展开推进, 不把 `@field_type` 重新纳入 v1 主线。
- P2 diagnostics: narrowing 和未收窄 union payload 裸用使用专用诊断 `InvalidNarrowing` / `UnionPayloadRequiresNarrowing`, 不再落到泛化 `InvalidCallArgList` / `NoMatchingCall`。

阶段内小任务:

- [x] B1.1 列出 PEG 有而 parser 没有的语法。验证: 原 B1 问题清单第 1、2、4 项, 已按决策落地后删除问题文件。
- [x] B1.2 列出 parser 有而 PEG 没有的语法。验证: 原 B1 问题清单第 3、4 项, 已按决策落地后删除问题文件。
- [x] B1.3 列出文档示例与 parser 行为冲突的语法。验证: 原 B1 问题清单第 2、5 项, 已按决策落地后删除问题文件。
- [x] B1.4 每个问题给正例、反例、选项 a/b/... 和推荐。验证: 用户接受推荐方案后已删除问题文件。
- [x] B1.5 用户选定后, 再同步 grammar、parser、doc 和 fixture。验证: `doc/grammar.peg`, `doc/syntax/builtin.md`, `tool/build/parser.zig`, `tool/build/sema.zig`, `tool/build/test/ok/121_source_text_type.do`, err `306` 到 `309`。
- [x] B2.1 列出文档定义但 sema 未实现的规则。验证: 原 B2 问题清单第 1、2、3、4、5 项。
- [x] B2.2 列出 sema 已实现但文档未定义的规则。验证: 原 B2 问题清单的 `B2.2 备注`, 本轮聚焦审查未发现独立 P1。
- [x] B2.3 列出测试期望和文档冲突的规则。验证: 原 B2 问题清单第 3、4、5、6 项记录 union/narrowing/diagnostic 测试覆盖缺口。
- [x] B2.4 每个问题给正例、反例、选项 a/b/... 和推荐。验证: 原 B2 问题清单 6 个编号问题均已包含, 用户接受推荐后逐项落地。
- [x] B2.5 用户选定后, 再同步 spec_rules、实现和 fixture。验证: 6 个问题均已落地; 已解决的 B2 问题清单文件已删除。

B1 落地验证:

- `cd tool && zig test build/parser.zig` 通过, `All 22 tests passed.`
- `cd tool && zig test main.zig` 通过, `All 50 tests passed.`
- `cd tool && zig test build/diag.zig && zig test build/cli.zig` 通过, diag `12/12`, cli `14/14`。
- `cd tool && zig build -Doptimize=Debug` 通过。
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=677 fail=0 skip=70`。

B2 初审验证:

- `git diff --check -- <B2 问题清单> doc/roadmap_status.md` 通过; 问题清单后续已在 B2.5 完成后删除。
- 本次只新增待决问题文件和进度记录, 未修改正式语法/语义规则和实现, 因此未重跑 full regression。

B2.5 第 1 项落地验证:

- `cd tool && zig test build/parser.zig && zig test build/sema.zig && zig build -Doptimize=Debug` 通过。
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=684 fail=0 skip=70`。
- 新增 err `310` 到 `316`; 同步 no-shadow 后的 lambda 参数、库私有参数和 `net` 构造参数命名。

B2.5 第 2 项落地验证:

- RED: 新增 err `317` 到 `321` 后, 旧二进制回归失败, 摘要 `pass=684 fail=5 skip=70`; 其中非法 metadata 使用和非法 `fields(...)` 来源未被 sema 稳定拦截。
- `cd tool && zig test build/parser.zig && zig test build/sema.zig && zig build -Doptimize=Debug` 通过。
- `./tool/build/test/run_tests.sh` 通过, 摘要 `pass=689 fail=0 skip=70`。
- 新增 err `317` 到 `321`; `tool/build/sema.zig` 新增字段反射 provenance 校验, `tool/build/diag.zig` 新增 `InvalidFieldReflection` 诊断文案。

B2.5 第 3 项落地验证:

- RED: 新增 err `322_is_union_target` 后, 旧二进制回归失败, 摘要 `pass=689 fail=1 skip=70`; 旧 ok `68_is_union_type_set` 仍把 `@is(v, i32 | i64)` 当作合法用例。
- `cd tool && zig test build/parser.zig && zig test build/sema.zig && zig build -Doptimize=Debug` 通过。
- `./tool/build/test/run_tests.sh` 通过, 摘要 `pass=690 fail=0 skip=70`。
- `doc/spec_rules.md`、`doc/syntax/builtin.md`、`doc/syntax/union.md`、`doc/grammar.peg` 已同步 v1 单目标 `@is` 规则; `tool/build/sema.zig` 只限制 `@is` target 顶层, 不影响普通类型位和 type args 内部 union/nullable。

B2.5 第 4 项落地验证:

- RED: 新增 err `323_is_inside_logic_condition` 后, 旧二进制回归失败, 摘要 `pass=690 fail=1 skip=70`; 旧实现仍接受 `if @and(@is(value, User), ready())`。
- `tool/build/parser.zig` 已禁止 `@and/@or/@not` 的逻辑条件参数根部直接使用 `@is(...)`。
- `doc/spec_rules.md`、`doc/syntax/builtin.md`、`doc/syntax/union.md`、`doc/spec_examples.md` 和 `doc/grammar.peg` 已同步 v1 边界: 只承诺直接条件头 `@is(value, Type)` 和直接条件头 `@eq/@ne(value, nil)` 的单非 nil 分支收窄; 复合条件 proof engine 和 enum 分支值收窄保留到 future。
- 处理第 4 项时发现 `FileError | nil` 未经条件也可直接绑定到 `FileError`; 后续已在第 5 项按 union 支持矩阵单独处理。
- `cd tool && zig test build/parser.zig && zig test build/sema.zig && zig build -Doptimize=Debug` 通过。
- `./tool/build/test/run_tests.sh` 通过, 摘要 `pass=691 fail=0 skip=70`。

B2.5 第 5 项落地验证:

- RED: 新增 compile_err `18_union_payload_requires_narrowing` 后, 旧二进制仍成功 build `FileError | nil` 到 `FileError` 的未收窄裸用。
- `tool/build/codegen.zig` 已要求 scalar/error union payload 提取必须存在当前路径 `narrowed_union_locals` 事实, 和 struct union payload 提取规则一致。
- `doc/spec_rules.md` 和 `doc/syntax/union.md` 已同步 v1 union 支持矩阵: 未收窄 union 不隐式匹配 payload 类型; 多 payload union 的完整目标集合和复杂路径 proof 保留到 future。
- 修复严格 payload 提取后暴露的 JSON compiled 路径: 字段反射 loop body 的 locals 收集现在会继承 guard return 和 guard break/continue 的 false-path narrowing; `if @eq(value_offset, nil) continue` 后的 `value_offset` 可作为已收窄 payload 参与 `parse_value(..., value_offset)` 和后续 `@field_set`。
- 新增 compile_ok `227_field_reflection_nil_continue_payload_lower` 覆盖 `fields(T)` loop 中 `@is(..., JsonError) return`、`@eq(..., nil) continue`、`parse_value`、`@field_set` 的组合 lowering。
- targeted 验证: `cd tool && zig test build/codegen.zig`、`cd tool && zig build -Doptimize=Debug`、JSON compiled 组 `133/136/137/141/143/144/145/146/147` 均通过。
- full regression: `./tool/build/test/run_tests.sh` 通过, 摘要 `pass=694 fail=0 skip=70`。

B2.5 第 6 项落地验证:

- `tool/build/diag.zig` 新增 `InvalidNarrowing` 和 `UnionPayloadRequiresNarrowing` 文案; parser/sema 中 `@is` 非条件位、非法目标集合和复合逻辑条件子项改报 `InvalidNarrowing`; codegen 中未收窄 union payload 裸用改报 `UnionPayloadRequiresNarrowing`。
- 更新 err fixture `55`、`102`、`103`、`126`、`223`、`224`、`306`、`307`、`322`、`323` 和 compile_err `18` 的期望, 锁住 narrowing / union payload 专用诊断。
- 已删除已解决的 B2 问题清单文件; 下一个阶段内小任务切到 B3 语法文档治理。
- targeted 验证: `cd tool && zig test build/parser.zig && zig test build/sema.zig && zig test build/codegen.zig` 通过, parser `23/23`, sema `25/25`, codegen `15/15`。
- full regression: `./tool/build/test/run_tests.sh` 通过, 摘要 `pass=694 fail=0 skip=70`。

B3 语法文档治理:

- [x] B3.1 扫描 start_here、README、roadmap_status 的文档引用。验证: `rg -n "doc/[A-Za-z0-9_./-]+|README\\.md|CHANGELOG\\.md|master_plan\\.md|roadmap_status\\.md|start_here\\.md|spec_rules\\.md|grammar\\.peg|syntax/[A-Za-z0-9_.-]+" README.md doc/start_here.md doc/roadmap_status.md` 已执行; 入口文档引用均指向现存活跃文件或历史证据条目。`rg -n "review_|next_stage|compiled_task_checklist|internal_prefix_rename_plan|do get|do push|pkg|package|completion|hover|definition|rename|diagnostics-only|单文件-only|fmt.*write|B2.*待|剩余第" README.md doc/start_here.md doc/roadmap_status.md doc/master_plan.md` 已执行; get/pkg/push 与 LSP future 能力只作为明确暂停或 future 边界出现, 未发现当前能力误报。
- [x] B3.2 找出已被当前规则替代的设计描述。验证: `rg -n "@as\\([^,]+,[^)]*\\)|@is\\([^)]*\\|[^)]*\\)|@and\\([^)]*@is|@or\\([^)]*@is|@not\\([^)]*@is|@field_type|@field_default_value|@field_default_type|loop\\s+[A-Za-z_][A-Za-z0-9_]*\\s*=\\s*[^\\n{]+\\{|do get|do push|tool/pkg|tool/get|tool/push|review_|next_stage|compiled_task_checklist|internal_prefix_rename_plan|diagnostics-only|单文件-only" README.md CHANGELOG.md doc`、`rg -n "@as\\(|@is\\(|@field_|fields\\(|loop .* = |do get|do push|completion|hover|definition|rename" doc/syntax doc/spec_rules.md doc/spec_examples.md doc/spec.md doc/grammar.peg README.md CHANGELOG.md` 和 `rg -n "future|Future|TODO|暂不|后续|不支持|保留到 future|old|旧|历史|过期" doc/syntax doc/spec_rules.md doc/spec_examples.md doc/spec.md doc/grammar.peg README.md CHANGELOG.md` 已执行。结论: `doc/spec_examples.md` 中 `@is(x, F)` 和 `@and(@is(...))` 命中均位于 `decl err` / `program err` 反例块, 与 `doc/spec_rules.md` 当前规则一致; `Box<User | nil>` 命中是外层 `Box<...>` 判断, 不是顶层 `nil` 分支; `@field_type/@field_default_*` 命中均为 v1 不提供的当前边界; get/pkg/push 命中均为暂停或删除历史。未发现必须在 B3.3 修改的过期设计描述。
- [x] B3.3 更新或删除过期描述。验证: `rg -n "review_sema_freeze|next_stage_plan|compiled_task_checklist|internal_prefix_rename_plan" README.md CHANGELOG.md doc` 和 `rg -n "当前可用|已支持|do get|do push|tool/pkg|@field_type|@field_default_value|@field_default_type|@is\\(value, A \\| B\\)|@is\\(x, F\\)|@and\\(@is" README.md CHANGELOG.md doc/spec_rules.md doc/spec_examples.md doc/syntax doc/master_plan.md doc/start_here.md` 已执行。结论: 命中均为进度记录自身、反例、future 边界、暂停历史或当前能力说明; 没有独立可更新或删除的过期描述。因此本项以 no-op 收口, 不修改语法设计文件。
- [x] B3.4 用 `rg` 检查死链和过期规则关键字。验证: 本地 Markdown 链接存在性脚本 `perl -MFile::Basename=dirname -MCwd=abs_path -ne '...' README.md CHANGELOG.md doc/*.md doc/syntax/*.md` 无输出; `rg -n "review_sema_freeze|next_stage_plan|compiled_task_checklist|internal_prefix_rename_plan|tool/get|tool/push|tool/pkg|doc/[A-Za-z0-9_./-]*(review|plan|task|checklist)[A-Za-z0-9_./-]*\\.md" README.md CHANGELOG.md doc` 和 `rg -n "diagnostics-only|单文件-only|剩余第|待处理|待决|当前可用.*do get|当前可用.*do push|已支持.*completion|已支持.*hover|已支持.*definition|已支持.*rename|@as\\([^,]+,[^)]*\\)\\s*=\\s*提取|@is\\([^)]*\\|[^)]*\\)|@field_type|@field_default_value|@field_default_type" README.md CHANGELOG.md doc/spec_rules.md doc/spec_examples.md doc/spec.md doc/grammar.peg doc/syntax doc/master_plan.md doc/start_here.md` 已执行。结论: 未发现死链; 旧关键字命中均为当前文档、暂停历史、future 边界或 B3 自身证据。同步 `doc/master_plan.md` 和 `doc/start_here.md` 后, 下一个阶段内小任务切到 B4 语法冻结回归包。

B4 语法冻结回归包:

- [x] B4.1 为 parser-only 规则补 `tool/build/test/err` 或 `ok`。结论: 现有最小 fixture 已覆盖 B1 parser-only 冻结规则, 本项无需新增文件。覆盖矩阵: `@is` 条件位正例 `ok/41_is_value_type_guard.do`, 非值表达式反例 `err/306_is_value_position.do` 和 `err/307_is_non_condition_and_arg.do`; `@as(Type, value)` 旧参数顺序反例 `err/308_as_source_first_rejected.do`; 普通集合循环双绑定正例 `ok/09_loop_each_index_value.do` / `ok/10_loop_each_discard_index.do`, 单绑定反例 `err/309_loop_collection_single_binding.do`; import 前置区块正例 `ok/17_import_forms.do`, import-after-decl 反例 `err/268_import_after_decl.do`; source text / line string 边界正例 `ok/121_source_text_type.do`, return 位 line string 反例 `err/215_return_line_string.do` 和 `err/216_guard_return_line_string.do`。验证: `cd tool && zig test build/parser.zig` 通过 `23/23`; 目标 fixture 手动执行全部通过, ok 组要求 `do test` exit 0, err 组逐行匹配对应 `.expect`。
- [x] B4.2 为语义规则补 `ok` / `err`。结论: 现有最小 fixture 已覆盖 B2 sema 冻结规则, 本项无需新增文件。覆盖矩阵: 绑定/遮蔽反例 `err/303`、`310` 到 `316`; 字段反射正例 `ok/130_struct_field_reflection.do`、`ok/135_generic_fields_reflection.do`, 反例 `err/317` 到 `321`; `@is` 单目标正例 `ok/41_is_value_type_guard.do`、`ok/68_is_union_type_set.do`, 非法 nil / 目标集合 / 非类型目标反例 `err/55`、`102`、`103`、`126`、`223`、`224`、`322`; 复合条件内 `@is` 反例 `err/323`; union/nil 正例 `ok/71_nil_first_union.do` 和 JSON from_json 的 `ok/143`、`145`、`146`; 重复 union 分支反例 `err/115`、`116`; lambda block nil 正例 `ok/147`、`148`。验证: `cd tool && zig test build/sema.zig` 通过 `25/25`; 目标 fixture 手动执行全部通过, ok 组要求 `do test` exit 0, err 组逐行匹配对应 `.expect`。
- [x] B4.3 为 codegen 相关规则补 `compile_ok` / `compile_err` 或 `compiled_ok`。新增 `compile_ok/222` 到 `227` 的 `.expect`, 把已有“能 build 即通过”的 nullable/field-reflection lowering fixture 升级为关键输出断言。覆盖矩阵: `@as(Type, value)` lowering `compile_ok/17`; source text lowering `compile_ok/112`、`114`; collection loop lowering `compile_ok/133`; union tag/payload lowering `compile_ok/136` 到 `138`; field reflection set lowering `compile_ok/131`; nil guard / if / else 收窄 `compile_ok/222` 到 `225`; field reflection nullable guard / continue payload lowering `compile_ok/226`、`227`; 未收窄 union payload 诊断 `compile_err/18`; 编译测试执行入口 `compiled_ok/43_compiled_test_union_is_narrowing.do`。验证: `cd tool && zig test build/codegen.zig` 通过 `15/15`; 目标 compile_ok / compile_err / compiled_ok 手动执行全部通过, `.expect` 均逐行匹配输出。
- [x] B4.4 回归并记录摘要。验证: `./tool/build/test/run_tests.sh` 通过, 摘要 `pass=694 fail=0 skip=70`。阶段 B 收口, 下一步切到 C1 JSON stringify / from_json 收口。

## 阶段 C: 标准库与核心库收口

状态: in_progress

当前结论: C4.1 已完成。C1 JSON stringify / from_json 已收口, C2 字段反射 API 收口结束, C3 bytes / text 边界已完成。当前集合 skip 没有 parser/语法缺口; 目标集合 fixture 与相关源码 `do check` 全部通过。List 基础用例里 `49_list_storage_items`、`56_list_del`、`65_list_add_variadic` 已能 compiled 执行, 下一步进入 C4.2, 先把这些 List 基础操作从 skip 收回。List callback/update、Set add 链和 HashMap empty/put 链仍分别卡在跨模块 lambda/函数类型约束推导、imported generic helper codegen 可达性、多类型参数泛型 helper 实例化等 compiled build 缺口。

C1 JSON stringify / from_json 收口:

- [x] C1.1 盘点现有 JSON fixture 和 skip 原因。覆盖矩阵: `ok/117_encoding_json_common_wrappers.do` 覆盖 common wrapper, 当前 static skip; `ok/133_json_string_std.do` 覆盖 escape/quote/unescape 标准转义和 unicode; `ok/134_json_string_errors.do` 覆盖非法转义、截断 unicode、非法 surrogate 和 raw control; `ok/136_json_struct_stringify.do` 覆盖 struct 中 i32/text/bool stringify; `ok/137_json_nested_struct_stringify.do` 覆盖嵌套 struct stringify; `ok/138_json_stringify_max_depth.do` 覆盖 max depth; `ok/141_json_struct_from_json.do` 覆盖 `from_json<User>(...)`; `ok/143_json_from_json_defaults.do` 覆盖缺字段保留默认值; `ok/144_json_from_json_nested.do` 覆盖嵌套 struct from_json; `ok/145_json_from_json_errors.do` 覆盖 trailing bytes 和字段类型不匹配; `ok/146_json_from_json_text_and_bytes.do` 覆盖 text/[u8] 字符串解析; `ok/147_json_nullable_stringify.do` 覆盖 nullable field stringify; `compile_ok/216_json_nullable_field_stringify_lower.do` 覆盖 nullable field stringify lowering。skip 结论: `ok/133` 到 `ok/147` 的 C1 主线 JSON fixture 已 compiled PASS; `ok/117` 仍是 static skip; `src/json.do` 的 std src `NoTestDecl` skip 属于库文件无测试声明。已知缺口: 还未把 from_json 非 struct root、不支持 union/list/map/error 等边界整理成明确正反例。验证: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=694 fail=0 skip=70`; 手动 `DO_LIB_ROOT=tool/build/test/lib ./bin/do test tool/build/test/ok/117_encoding_json_common_wrappers.do` 输出 `skipped`; 手动 `DO_LIB_ROOT=src ./bin/do test src/json.do` 输出 `error[NoTestDecl]`。
- [x] C1.2 固定 `stringify` 支持矩阵和错误边界。支持矩阵: 顶层 `i32`、`text`、`[u8]`、`bool`; struct 字段中的 `i32/text/[u8]/bool`; nested struct; nullable field `T | nil`; `stringify_with_depth` 的 struct max depth `MaxDepth` 错误。实现: `src/json.do` 的公开 `stringify/stringify_with_depth` 继续保留泛型 struct 入口, 并新增顶层 `i32/text/[u8]/bool` 具体入口, 具体入口复用私有 `encode_value(...)`。不纳入本项: 顶层 nullable `T | nil` 需要 import 函数签名区分 union 参数, 当前多个公开 union overload 会因 import 层把 union 参数归为 `.other` 而触发 `DuplicateFuncSignature`; 非 `i32` 整数宽度、任意 union、list/map/error 自动序列化留到 C1.5 或单独决策。验证: 新增 `ok/149_json_scalar_stringify.do` 和 `.compiled_must_pass`; RED: 旧入口顶层 scalar compiled 失败于 `UnsupportedExpr` / `NoMatchingCall`; GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/149_json_scalar_stringify.do --compiled -o /tmp/149_json_scalar_stringify.wat` 通过, `wasm-tools parse /tmp/149_json_scalar_stringify.wat -o /tmp/149_json_scalar_stringify.wasm && node tool/build/test/run_compiled_test_case.mjs /tmp/149_json_scalar_stringify.wasm /tmp/149_json_scalar_stringify.wat` 通过 `1 passed`; 既有 `ok/136_json_struct_stringify.do`、`ok/147_json_nullable_stringify.do` compiled WAT 生成通过; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=695 fail=0 skip=70`; `git diff --check` 通过。
- [x] C1.3 固定 `from_json` 支持矩阵和错误边界。支持矩阵: root 只支持结构体 object; 字段值支持 `i32`、`text`、`[u8]`、`bool`、nested struct; 缺失字段保留构造默认值; trailing bytes 返回 `InvalidJson`; 非 object root 返回 `ExpectedObject`; 缺冒号返回 `ExpectedColon`; 缺逗号返回 `ExpectedComma`; 截断字段值返回 `UnexpectedEnd`; 字段类型不匹配返回 `ExpectedValue`。不纳入本项: 顶层 scalar root, 如 `from_json<i32>("7")`、`from_json<text>("\"x\"")`; 实验性 `JsonSeed<T>` 类型见证会触发 ARC/codegen 副作用, 当前不作为 v1 路径, 先由 `compile_err/260_json_from_json_scalar_root_unsupported.do` 锁住 `NoMatchingCall`, 后续若要支持需先设计零尺寸泛型类型见证或等价编译期分派。验证: 新增 `ok/150_json_from_json_object_errors.do` 和 `.compiled_must_pass`; 新增 `compile_err/260_json_from_json_scalar_root_unsupported.do` 和 `.expect`; 目标验证 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/150_json_from_json_object_errors.do --compiled -o /tmp/150_json_from_json_object_errors.wat && wasm-tools parse /tmp/150_json_from_json_object_errors.wat -o /tmp/150_json_from_json_object_errors.wasm && node tool/build/test/run_compiled_test_case.mjs /tmp/150_json_from_json_object_errors.wasm /tmp/150_json_from_json_object_errors.wat` 通过 `4 passed`; `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_err/260_json_from_json_scalar_root_unsupported.do -o /tmp/260_json_from_json_scalar_root_unsupported.wat` 失败并匹配 `NoMatchingCall`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=697 fail=0 skip=70`; `git diff --check` 通过。
- [x] C1.4 为 struct 字段、嵌套字段、默认字段补正例。新增 `ok/151_json_struct_field_examples.do` 和 `.compiled_must_pass`, 同时覆盖 stringify 按声明顺序输出默认字段、nested struct 默认字段, 以及 `from_json<User>` 保留顶层默认字段和嵌套默认字段。验证: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/151_json_struct_field_examples.do --compiled -o /tmp/151_json_struct_field_examples.wat && wasm-tools parse /tmp/151_json_struct_field_examples.wat -o /tmp/151_json_struct_field_examples.wasm && node tool/build/test/run_compiled_test_case.mjs /tmp/151_json_struct_field_examples.wasm /tmp/151_json_struct_field_examples.wat` 通过 `2 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=698 fail=0 skip=70`; `git diff --check` 通过。
- [x] C1.5 为不支持类型补反例和诊断。新增 `compile_err/261_json_stringify_u64_unsupported.do`、`262_json_stringify_union_root_unsupported.do`、`263_json_stringify_storage_non_u8_unsupported.do`、`264_json_from_json_storage_field_unsupported.do`、`265_json_from_json_union_field_unsupported.do`、`266_json_from_json_enum_field_unsupported.do`、`267_json_stringify_error_root_unsupported.do`、`268_json_from_json_error_field_unsupported.do`。诊断矩阵: `stringify(u64)` -> `UnsupportedExpr`; `stringify(i32 | text)` -> `NoMatchingCall`; `stringify([i32])` -> `UnsupportedExpr`; `from_json` `[i32]` 字段 -> `UnsupportedExpr`; `from_json` union 字段 -> `NoMatchingCall`; `from_json` value enum 字段 -> `NoMatchingCall`; `stringify(JsonError)` -> `UnsupportedExpr`; `from_json` error 字段 -> `NoMatchingCall`。同步 `doc/spec_rules.md`: JSON v1 不自动支持非 `i32` 整数、任意 union、value enum、error、map/list 抽象类型或非 `[u8]` storage。验证: 严格逐行匹配 261-268 `.expect` 通过; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=706 fail=0 skip=70`。
- [x] C1.6 同步 `src/json.do`、相关核心声明和文档。结论: `src/json.do` 的公开入口和 C1 支持矩阵一致, 包括 `escape/quote/unescape`、顶层 `stringify` 的 `i32/text/[u8]/bool/struct` 入口、字段级 `T | nil` stringify、`stringify_with_depth` 最大深度错误, 以及 `from_json<T>` 的 struct object root 解码; `src/_.do` 没有 JSON/core 声明需要同步, JSON 继续作为 `std` 模块通过 `@lib("json.do", ...)` 导入。文档同步: `doc/master_plan.md` 将裸 `nil` 口径收窄为字段级 `T | nil` stringify, 并把下一步切到 C2; `doc/start_here.md` 同步 C2 接手入口。验证: `rg` 对照 `src/json.do`、`src/_.do`、`doc/spec_rules.md`、`doc/master_plan.md`、`doc/roadmap_status.md`、`README.md` 和 `CHANGELOG.md`; 未发现需要修改 `src/json.do` 或 `src/_.do` 的漂移; `git diff --check` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=706 fail=0 skip=70`。

C2 字段反射 API 收口:

- [x] C2.1 固定 Field 的编译期/运行期边界。实现: `tool/build/sema.zig` 在字段反射循环作用域内检查 active field metadata 标识符, 只允许它出现在合法 `@field_*` 调用的指定 field 参数位置; 其他普通表达式位报 `InvalidFieldReflection`。新增 `tool/build/test/err/324_field_metadata_value_escape.do` 和 `325_field_metadata_call_arg_escape.do`, 分别锁住 field metadata 绑定逃逸和普通函数实参逃逸。RED: 旧二进制对两个新增 err fixture 均 `skipped` 并 exit 0。GREEN: 重建编译器后, 新增 err 和既有 `317` 到 `321` 字段反射 err 均匹配 `InvalidFieldReflection`; `ok/130_struct_field_reflection.do`、`ok/135_generic_fields_reflection.do` 保持当前 static skip; `cd tool && zig test build/sema.zig` 通过 `25/25`; compile_ok `131`、`218`、`226`、`227` build 通过; `git diff --check` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=708 fail=0 skip=70`。
- [x] C2.2 固定 `@field_get(target, field)` 的静态展开、重载分派和异构字段接收边界。实现: `tool/build/sema.zig` 为具体 `fields(User)` 收集字段 compact 类型, 在 `@field_get` 使用点按 `@field_name/@field_index/@field_has_default` 静态 guard 过滤候选字段; 未 guard 的异构字段不能统一绑定到一个 inferred local, 普通函数调用必须为每个候选字段类型找到匹配候选。新增 `compile_err/269_field_get_heterogeneous_binding_unsupported.do`、`compile_err/270_field_get_concrete_call_mismatch.do` 锁住异构绑定和具体调用错配; 新增 `compile_ok/228_field_get_concrete_overload_dispatch_lower.do` 锁住 concrete hetero field 通过 `encode_value(i32)` / `encode_value(text)` 重载分派。RED: 旧二进制对 269/270 均 build 成功, full regression 失败于两个新增 compile_err expected failure。GREEN: 重建编译器后 269/270 匹配 `InvalidFieldReflection`, 228 WAT 同时包含 `call $encode_value__i32` 和 `call $encode_value__text`; 既有字段反射正例 `ok/130`、compile_ok `196`、`198`、`218`、`226`、`227` 通过; `cd tool && zig test build/sema.zig` 通过 `25/25`; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=711 fail=0 skip=70`。
- [x] C2.3 固定 `@field_set(target, field, value)` 的同名自赋值 lowering 和类型约束。实现: `tool/build/sema.zig` 对具体 `fields(User)` 中的 `@field_set` 复用静态 guard 候选过滤, 对可证明类型的 value 做候选字段写入校验; 未 guard 的异构字段写入和 guard 后 value/字段类型错配均报 `InvalidFieldReflection`, 同构字段未 guard 写入继续允许并展开每个字段的 lowering。新增 `compile_err/271_field_set_heterogeneous_value_unsupported.do`、`compile_err/272_field_set_guarded_value_mismatch.do` 锁住错配反例; 新增 `compile_ok/229_field_set_homogeneous_unguarded_lower.do` 锁住同构正例。RED: 旧二进制对 271/272 均 build 成功。GREEN: 重建编译器后 271/272 匹配 `InvalidFieldReflection`, 229 WAT 同时包含 `field-set name=user field=left` 和 `field-set name=user field=right`, 既有 131 guarded field_set lowering 保持通过; `cd tool && zig test build/sema.zig` 通过 `25/25`; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=714 fail=0 skip=70`。
- [x] C2.4 用 JSON fixture 验证 field API 足够表达序列化。结论: 现有 JSON compiled fixture 已覆盖 `src/json.do` 的泛型字段反射路径, 包括 `stringify_depth(value T)` 里的 `fields(T)`、`@field_name`、`@field_get`, 以及 `parse_object(seed T, ...)` 里的 `@field_get` seed、`parse_value(...)` 分派和 `@field_set` 回写。目标矩阵 `136_json_struct_stringify`、`137_json_nested_struct_stringify`、`138_json_stringify_max_depth`、`141_json_struct_from_json`、`143_json_from_json_defaults`、`144_json_from_json_nested`、`145_json_from_json_errors`、`146_json_from_json_text_and_bytes`、`147_json_nullable_stringify`、`149_json_scalar_stringify`、`150_json_from_json_object_errors`、`151_json_struct_field_examples` 全部以 `DO_LIB_ROOT=src ./bin/do test <case> --compiled` 生成 WAT, 经 `wasm-tools parse` 和 `node tool/build/test/run_compiled_test_case.mjs` 执行通过。未发现需要新增 field API 或新增 JSON fixture 的缺口。
- [x] C2.5 同步 spec_rules、syntax/struct 和测试。同步内容: `doc/spec_rules.md` 第 11.5 节补齐字段元数据不得逃逸、具体 `fields(User)` 下 `@field_get/@field_set` 的静态 guard 候选过滤、异构字段绑定/写入边界和 `@field_set` 同名自赋值约束; `doc/syntax/struct.md`、`doc/syntax/builtin.md`、`doc/syntax/loop.md` 同步字段反射速查口径; `tool/build/test/README.md` 增加字段反射回归矩阵, 覆盖 `err/317` 到 `325`、`compile_err/269` 到 `272`、`compile_ok/228`、`229` 和 JSON compiled fixture。验证: 文档扫描确认字段反射说明已覆盖 C2.1-C2.4 规则; `git diff --check` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=714 fail=0 skip=70`。

C3 bytes / text 边界:

- [x] C3.1 盘点 `src/bytes.do` 和 `src/text.do` 当前 shape 与测试。源码 shape: `src/bytes.do` 定义 `BytesError = BytesOutOfBounds | BytesInvalidRange`, 并提供 `is_empty/copy/concat/repeat_byte/slice/slice_or/take/take_or/drop/drop_or/first/first_or/last/last_or/starts_with/ends_with/index_of/last_index_of/contains/trim_left_byte/trim_right_byte/trim_byte/replace`; 私有 helper 是 `.append` 和 `.matches_at`。`src/text.do` 导入 `utf8.do` 与 `bytes.do`, 公开 `bytes_of(text) -> [u8]`、`text_from([u8]) -> text | Utf8Error`、`byte_len(text) -> usize`、`char_len(text) -> usize | Utf8Error`, 其余 common wrapper 当前都以 `[u8]` 参数和返回为主, 复用 bytes/utf8 函数。`src/utf8.do` 定义 `Utf8Error`、`Utf8Decode`, 并提供 `decode_at/code_at/size_at/encode/validate/is_valid/count`。测试矩阵: `ok/97_bytes_lib.do` 覆盖 bytes concat/repeat/slice/trim/prefix/suffix/index/error, 当前 `do test` 输出 2 skipped; `ok/98_utf_lib.do` 覆盖 UTF-8 validate/decode/encode 与 invalid continuation, 当前输出 4 skipped; `ok/111_bytes_text_common_wrappers.do` 覆盖 bytes/text common wrapper, 当前输出 2 skipped; `ok/121_source_text_type.do` 覆盖 `text` 字段、`bytes_of`、`text_from`、`byte_len`、`char_len` 和 invalid byte 输入, 当前输出 1 skipped; `ok/109_std_foundation_libs.do` 有更宽的 text wrapper 使用矩阵, 当前输出 6 skipped; `ok/146_json_from_json_text_and_bytes.do` 是现有 compiled 执行正例, 覆盖 JSON `text` 字段和 `[u8]` 字段解析, `wasm-tools parse` 与 node 执行通过 `1 passed`。缺口: 还没有 bytes/text 直接转换的 compiled 正例, 也没有非法 UTF-8 转换的 compiled/compile_err 反例; C3.2 先补 `bytes_of/text_from/byte_len/char_len` 直接正例, C3.3 再补非法 UTF-8 或非法转换反例。验证: 手动执行上述 ok fixture 状态检查; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/146_json_from_json_text_and_bytes.do --compiled -o /tmp/146_json_from_json_text_and_bytes.c3_1.wat`; `wasm-tools parse /tmp/146_json_from_json_text_and_bytes.c3_1.wat -o /tmp/146_json_from_json_text_and_bytes.c3_1.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/146_json_from_json_text_and_bytes.c3_1.wasm /tmp/146_json_from_json_text_and_bytes.c3_1.wat`。
- [x] C3.2 补 bytes/text 转换正例。实现: `tool/build/test/ok/121_source_text_type.do` 新增 `.compiled_must_pass`, 并把 `text_from(raw)`、`text_char_len("中")` 这种 union 结果先用 `@is(..., text/usize)` 收窄到成功 payload 后再比较, 同时保留非法 UTF-8 error 分支检查; `src/text.do` 的 `byte_len` 改为先绑定 `raw [u8]` 再取 `@len(raw)`; `src/utf8.do` 的 `decode_at` 分支内临时变量改为唯一名字, 避免函数级 WAT local 重名; `tool/build/codegen.zig` 补齐 storage literal 作为 managed payload 实参、`text`/`[u8]` 比较兼容、`@is` false 分支收窄和 `if @is(...) { return }` 后续 fallthrough 收窄。验证: RED `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/121_source_text_type.do --compiled -o /tmp/121_source_text_type.c3_2.red.wat` 失败于 `NoMatchingCall`; GREEN `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/121_source_text_type.do --compiled -o /tmp/121_source_text_type.c3_2.green.wat`; `wasm-tools parse /tmp/121_source_text_type.c3_2.green.wat -o /tmp/121_source_text_type.c3_2.green.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/121_source_text_type.c3_2.green.wasm /tmp/121_source_text_type.c3_2.green.wat` 通过 `1 passed`; `cd tool && zig build -Doptimize=Debug` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=715 fail=0 skip=69`; `git diff --check` 通过。
- [x] C3.3 补非法 UTF-8 或非法转换反例。实现: `tool/build/test/ok/98_utf_lib.do` 新增 `.compiled_must_pass`, 并把 `utf8_decode_at/utf8_encode/utf8_validate/utf8_count/utf8_code_at/utf8_size_at` 与 `utf16_decode_at/utf16_encode/utf16_validate/utf16_count/utf16_code_at/utf16_size_at` 的 union 结果先用 `@is(..., Utf8Decode/Utf16Decode/u32/usize/[u8]/[u16])` 或 `@eq(..., nil)` 验证成功 payload 后再比较; invalid bytes 和 invalid surrogate 分支继续先判定 error union payload 再比较具体错误值。`src/utf8.do` 与 `src/utf16.do` 的 `encode` 避免直接返回 `@put(.{}, ...)`, 并把同一函数内的 branch-local `out` 改为唯一名字, 避免函数级 WAT local 重名。`tool/build/codegen.zig` 补齐 narrowed union storage payload 的 `@len(payload)` 和 `@get(payload, index)` lowering。新增 `compiled_ok/44_compiled_test_union_storage_payload_len_get_lower.do` 锁住 union storage payload 收窄后可被 `@len/@get` 读取。验证: RED `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/98_utf_lib.do --compiled -o /tmp/98_utf_lib.c3_3_probe.wat` 失败于 `NoMatchingCall`; RED `./bin/do test tool/build/test/compiled_ok/44_compiled_test_union_storage_payload_len_get_lower.do --compiled -o /tmp/44_union_storage_payload_len_get.red.wat` 失败于 `NoMatchingCall`; GREEN `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/98_utf_lib.do --compiled -o /tmp/98_utf_lib.c3_3_green.wat`; `wasm-tools parse /tmp/98_utf_lib.c3_3_green.wat -o /tmp/98_utf_lib.c3_3_green.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/98_utf_lib.c3_3_green.wasm /tmp/98_utf_lib.c3_3_green.wat` 通过 `4 passed`; `./bin/do test tool/build/test/compiled_ok/44_compiled_test_union_storage_payload_len_get_lower.do --compiled -o /tmp/44_union_storage_payload_len_get.green.wat` 通过; `cd tool && zig build -Doptimize=Debug` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=717 fail=0 skip=68`; `git diff --check` 通过。
- [x] C3.4 同步 spec_rules 和 syntax/type。实现: `doc/spec_rules.md` 第 14 章标准库边界补齐 `src/text.do` 的 `bytes_of/text_from/byte_len/char_len`、`src/utf8.do` / `src/utf16.do` 的 `decode_at/code_at/size_at/encode/validate/is_valid/count` 公开边界, 并明确 UTF-8/UTF-16 错误是普通 union 返回, 成功 payload 需先用 `@is(...)` 或 `@eq(..., nil)` 收窄后再读取字段、`@len/@get` 或比较; 非法 UTF-8 / UTF-16 输入使用 `[u8]` / `[u16]` 聚合, 不用字符串字面量。`doc/syntax/type.md` 增加 `text` 与 `[u8]` 边界速查, 明确 `text` 不是 `[u8]` alias, `@len/@get/@set/@put/@load_*` 只面向 `[T]`, UTF-16 只是库级 `[u16]` 编解码能力。验证: `cd tool && zig build -Doptimize=Debug` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=717 fail=0 skip=68`; `git diff --check` 通过。

C4 list / set / hash_map 常用操作从 skip 收回:

- [x] C4.1 输出 skip 分类。
  取证范围: `36_hash_map_lib_ops`、`37_hash_map_set_missing_key`、`49_list_storage_items`、`52_list_functional_ops`、`56_list_del`、`57_hash_map_del`、`58_list_update`、`59_hash_map_update`、`65_list_add_variadic`、`109_std_foundation_libs`、`113_set_common_ops`、`115_hash_map_common_wrappers`。静态 `DO_LIB_ROOT=src ./bin/do test <case>` 全部输出 skipped; `DO_LIB_ROOT=src ./bin/do check <case>` 全部 exit 0, `src/list.do`、`src/set.do`、`src/hash_map.do`、`src/fp.do` 也全部 `do check` 通过, 因此当前没有 parser/语法缺口, 也没有普通 check 阶段 sema 阻断。
  分类: A. 可直接收回为 compiled 的 List 基础操作: `49_list_storage_items` compiled 执行 `3 passed`, `56_list_del` compiled 执行 `1 passed`, `65_list_add_variadic` compiled 执行 `1 passed`; C4.2 优先给这三项补 `.compiled_must_pass`。
  B. sema/import 类型推导缺口: `52_list_functional_ops`、`58_list_update`、`59_hash_map_update` 均在 compiled build 阶段报 `NoMatchingCall`, 触发点是跨模块 lambda 参数目标类型、函数类型约束 `#Q = (...) -> ...` 和泛型返回推导; 对应规则缺口已在 `doc/spec_rules.md` 第 17.1.7 记录为后续 typecheck 能力。
  C. codegen/import 可达性缺口: `113_set_common_ops` 的最小探针显示 `Set`、`empty_set`、`set_len`、`set_has` 可 compiled build, 但 `set_add` 一进入可达路径就 `NoMatchingCall`; 断点落在 imported generic 函数体内调用 `set_has(xs, value)` 后 guard return `xs` 的 helper 可达性/lowering。
  D. codegen/generic 实例化缺口: `36_hash_map_lib_ops`、`37_hash_map_set_missing_key`、`57_hash_map_del`、`115_hash_map_common_wrappers` 在 compiled build 阶段报 `NoMatchingCall`; 最小探针显示只导入 `HashMap` 类型可过, 直接调用 `hash_map_from_parts` 可过, 但调用 `empty_hash_map` 即失败, 断点落在 imported generic 函数体内两类型参数空 storage 构造与 `hash_map_from_parts(ks, vs)` helper 实例化链。
  E. 聚合 smoke: `109_std_foundation_libs` 是跨 binary/math/path/list/hash/set/text/url 的大用例, compiled build 先在首个 binary import 处报 `NoMatchingCall`; C4 不把它作为第一批收回对象, 等 C4.2-C4.4 分项用例收回后再在 C4.5 更新或拆分 skip 原因。
  验证: `DO_LIB_ROOT=src ./bin/do test <case>` 静态 runner 取证; `DO_LIB_ROOT=src ./bin/do check <case>` 和 `DO_LIB_ROOT=src ./bin/do check src/{list,set,hash_map,fp}.do`; `DO_LIB_ROOT=src ./bin/do test <case> --compiled -o /tmp/<case>.c4_1.wat` + `wasm-tools parse` + `node tool/build/test/run_compiled_test_case.mjs` 对上述 compiled 正例执行通过; `git diff --check` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=717 fail=0 skip=68`。
- [ ] C4.2 先收回 List 基础操作。
- [ ] C4.3 再收回 Set 基础操作。
- [ ] C4.4 再收回 HashMap 基础操作。
- [ ] C4.5 更新 NoTestDecl 或 skip 原因。

## 文档治理

状态: partial

当前结论: 已新增 `CHANGELOG.md` 作为历史摘要入口, 并删除已完成支线的过期 plan/spec 文档。当前活跃入口收敛为 README、CHANGELOG、start_here、master_plan、roadmap_status、spec/spec_rules、grammar、syntax、memory 和 WIT 文档。

阶段内小任务:

- [x] 新增 changelog 并写入近期已完成能力摘要。验证: `CHANGELOG.md`。
- [x] 删除已完成支线的过期文档。验证: 已删除 do run 接手清单和历史计划/设计目录; `test ! -e docs` 输出 `docs directory removed`。
- [x] 清理旧文档残留引用。验证: 旧历史路径关键字扫描无活跃引用。
- [x] 删除暂停包管理线的占位目录。验证: 已删除 `tool/get/.gitkeep` 和 `tool/push/.gitkeep`; README 目录结构不再列出 `tool/get` / `tool/push`。
- [x] 删除过期旧语法 fixture。验证: 已删除 `tool/build/test/err/244_source_char_alias_type_name.*` 和 `tool/build/test/err/92_synth_error_alias_rhs.*`; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 摘要 `pass=670 fail=0 skip=70`。
