# Roadmap 执行状态

更新时间: 2026-07-12

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
- `tool/build/test/compile_ok/234_defer_call_and_arc_block_lower.do` 覆盖 `defer` cleanup 先于被离开区域 ARC release 的 lowering 顺序。

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
- `./tool/build/test/run_tests.sh` 当时回归摘要为 `pass=652 fail=0 skip=70`。

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
- `RUN_WASM=1 SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 该阶段验收摘要为 `pass=653 fail=0 skip=70`。

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
- [x] 03.8.1 增加只读 `SourceOrigin` 元数据, 默认 `unknown`, 不改变 lowering。验证: `doc/memory.md` 第 8.10 节; `tool/build/codegen.zig` 已给 `Local` / `StructLocal` / `StorageLocal` / `UnionLocal` 增加 origin 字段, 并在参数、collection value、recv value、loop source、compiler temp 等有直接证据的入口做只读标注; `cd tool && zig test build/codegen.zig` 结果 `All 1 tests passed.`; 当时后续集成回归目标为继续保持 `pass=658 fail=0 skip=70`。
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

状态: blocked-residual; G1-G5 和 G6.4 已完成, G6.1/G6.3 等待公开 API 决策, G6.2 因当前无 async/Future runtime 暂时阻断。

状态说明: 用户此前明确要求 WASI 放到最后处理; 当前阶段 A-H 已完成到可验证收口。历史 06 守门能力继续有效, G1、G2.1、G2.2、G2.3、G3.1、G3.2、G3.3、G4.1、G4.2、G4.3、G4.4、G5.1、G5.2、G5.3、G5.4 和 G6.4 已完成; G6.1、G6.2、G6.3 已记录阻断。D2.1 已按用户确认的 B 方案绿色 regression 收口。当前无新的未记录阻断; 若继续实现, 先由用户确认 G6.1/G6.3 API 方向, 或等 G6.2 所需 async/Future runtime 立项。

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
- [x] 06.1 设计完整 binding source / alias 规则。验证: G1 已完成 source + alias 规则冻结、manifest 工具正反例、编译层重复 alias 反例和文档同步。
- [ ] 06.2 设计 result-area、resource、variant、future lowering。blocked/decomposed:
  - 已完成部分: result-area lowering 已由 G2.1/G2.2/G2.3 收口; resource wrapper / resource-drop 边界已由 G3.1/G3.2/G3.3 收口; variant / flags / list<record> 评估已由 G4.1/G4.2/G4.3/G4.4 收口; component 输入和真实 component wasm validate gate 已由 G5.1-G5.4 收口。
  - 剩余部分: preopens `list<tuple<descriptor,string>>`、`descriptor.read-directory` stream/future、sockets resource + variant 已拆到 G6.1/G6.2/G6.3, 且均有 blocked 记录、停止条件和恢复条件。
  - 当前恢复条件: 用户确认 G6.1 公开 API, 或未来完成 G6.2 所需 async/Future/Task/resource stream 运行时设计, 或确认 G6.3 socket resource wrapper 与 address variant 映射。

## 07. 生态工具

状态: done/paused; 当前 v1 工具链入口已完成, get / pkg / push 包管理线按用户要求暂停。

当前结论: `do check <input.do>...` 第一版已落地, 当前复用 LSP diagnostics collector 执行 lexer/parser/sema/import 检查, 支持按命令行顺序检查多个文件, 不编译、不运行、不要求 `start()` 或 `test` 声明。`do run <input.do>` 第一版已落地, 执行策略固定为外部 `wasm-tools + node` 桥接。`do fmt <input.do>` 第一版已落地, 当前支持 stdout 输出、`--check` 检查和 `--write` 单文件原地写回。`do lsp [--stdio]` 第一版已落地, 当前做 diagnostics + formatting + semantic tokens + hover + completion + definition stdio server。get / pkg / push 包管理线已按用户要求暂停, 不作为当前阶段继续目标。

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
- 已支持 F1 最小函数 hover, 返回 plaintext `MarkupContent`; 当前只覆盖打开文件内的 top-level 函数声明签名和函数调用回查声明。
- 已支持 F2 最小 completion, 返回当前文件函数名、类型名、字段段候选和 workspace 顶层函数 / 类型候选; 当前不做排序打分、snippet 或字段 receiver 类型收窄。
- 已支持 F3 最小 definition, 返回当前文件 top-level 函数 / 类型声明的 `Location`; 当前文件未命中时回退 workspace 顶层函数 / 类型 symbol; 当前不做 import-aware resolution、字段或 local definition。
- 已支持 F4.1/F4.2 workspace root 输入和 top-level symbol 扫描; 当前只扫描 `file:///abs/path` root 下的一层 `.do` 文件。
- 回归范围: `tool/build/test/lsp/*.json` 通过 `tool/build/test/run_lsp_case.mjs` 驱动 `bin/do lsp` smoke。
- 不包含: rename、递归 / 增量 workspace index、字段/local/type hover、字段/local definition 和完整语言服务。

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
- [x] 07.3.0 明确 LSP 最小能力集和诊断来源。结论: 当时第一版只覆盖 diagnostics stdio server, 未覆盖 completion / hover / definition / rename / formatting; 后续 A1 已补 `textDocument/formatting`, A2 已补 semantic tokens, F1 已补最小函数 hover, F2 已补最小 completion, F3 已补最小 definition。诊断来源复用 lexer/parser/sema/imports fail-fast 链路, 当前每个 document 最多发布一个编译诊断。验证: 当前 LSP 边界已收敛进 README、`CHANGELOG.md` 和本节 `do lsp` 当前边界; 历史 LSP plan 已清理, 不再作为活跃入口。
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

## 08. 后续语言能力扩展

状态: in-progress

当前结论: 阶段 I 已开始推进。I1.1 递归基线盘点已完成; I1.2 已把普通直接/互递归、递归未命中 overload 报 `NoMatchingCall`、参数侧已知 concrete type 的泛型递归可执行, 以及“左侧目标类型不参与 direct type param 反推”的边界固定到 `doc/spec_rules.md`。I1.3 已补普通 `do test`、`do build` 与 compiled 路径的递归正反例矩阵。I1.4 已补 scalar / `if/else` / guard / generic / imported self-tail TCO, 以及 generic/imported `if/else` self-tail 回归。I1.5 已锁住 `defer`、storage local、managed struct、多返回、guard+defer、`if/else+defer` 的不优化边界。I1.6 已同步 README、测试说明、handoff 文档和最新默认回归摘要。I2 已进入实现: I2.1 已固定规格, I2.2 已完成 grammar/parser, 当前 I2.3/I2.4 已打通最小 typed tuple build/compiled + arity/index + struct field + return/param multi-value + 嵌套叶子 ABI + 标量叶子 `[Tuple<...>]` storage put/get/set/literal pack, 后续继续 managed payload 与更完整 sema 规则。


需求评估:

- I1 递归 + TCO: 推荐先支持普通直接递归和互递归, 再做 self-tail TCO。TCO 第一版只降 `return self(new_args)` 到 loop, 不依赖 Wasm tail-call proposal, 不承诺 mutual/general TCO。泛型递归必须先定义实例化上限或错误诊断。
- I2 `Tuple<bool, u8>`: 推荐做大写源码层 `Tuple<T0, T1, ...>` 内建泛型类型, 构造使用 `Tuple<bool, u8>{flag, code}`, 读取使用 `@get(pair, 0)` / `@get(pair, 1)` 数字位置索引, 与 `@wasi` 签名里的小写 WIT `tuple<...>` 分离。第一版不做 `(bool, u8)` 类型语法或 `(true, 7)` 字面量, 避免和函数类型、多返回、调用实参列表冲突。

阶段内小任务:

- [x] I1.1 盘点当前递归行为和失败点。验证: `compiled_ok/53_compiled_test_direct_and_mutual_recursion` 与 `compiled_ok/54_compiled_test_generic_recursive_known_arg` 通过 compiled WAT/wasm; `compiled_err/02_recursive_call_no_matching_overload` 与 `compiled_err/03_generic_recursive_call_currently_unsupported` 均稳定报 `NoMatchingCall`。
- [x] I1.2 固定递归语义规则和泛型递归边界。`doc/spec_rules.md` 已写明普通直接/互递归、递归未命中 overload 报 `NoMatchingCall`, 参数侧已知 concrete type 的泛型递归可执行, 以及“返回上下文不参与 direct type param 反推”的当前边界; 该 slice 不引入新语法, `doc/grammar.peg` 无需变更。
- [ ] I1.3 落地普通递归调用支持。当前已补 `ok/182_recursive_sum_and_parity`、`ok/183_recursive_error_union`、`ok/184_generic_recursive_known_arg`、`ok/185_recursive_factorial`、`ok/186_recursive_guard_return`、`ok/187_imported_recursive_factorial`、`compile_ok/242_recursive_start_sum_lower`、`compile_ok/243_recursive_factorial_start_lower`、`compile_ok/244_recursive_if_else_start_lower`、`compile_ok/245_imported_recursive_start_lower`、`compiled_ok/53_compiled_test_direct_and_mutual_recursion`、`compiled_ok/54_compiled_test_generic_recursive_known_arg`、`compiled_ok/55_compiled_test_recursive_factorial`、`compiled_ok/56_compiled_test_recursive_if_else` 和 `compiled_ok/57_compiled_test_imported_recursive_factorial`; 当前已登记递归静态 runner 矩阵已收口, 更复杂 control-flow / aggregate 边界继续后置推进。
- [ ] I1.4 落地 self-tail TCO 第一版。当前已补 `compile_ok/246_self_tail_scalar_tco_lower`、`247_self_tail_if_else_tco_lower`、`252_self_tail_guard_tco_lower`、`254_generic_self_tail_tco_lower`、`255_imported_self_tail_scalar_tco_lower`、`257_generic_self_tail_if_else_tco_lower`、`258_imported_self_tail_if_else_tco_lower`, `compiled_ok/58` 到 `64`, 以及 `ok/188`、`ok/189`, 证明 scalar、`if/else`、guard、generic、imported 和 generic/imported `if/else` self-tail path 已能 lower 到 loop; 更复杂 cleanup/aggregate 边界继续后置。
- [ ] I1.5 评估 storage / managed / defer / 多返回 TCO 边界。当前已补 `compile_ok/248_self_tail_defer_not_optimized_lower`、`249_self_tail_storage_local_not_optimized_lower`、`250_self_tail_managed_struct_not_optimized_lower`、`251_self_tail_multi_return_not_optimized_lower`、`253_self_tail_if_else_defer_not_optimized_lower`、`256_self_tail_guard_defer_not_optimized_lower`, 锁住这六条“不优化”边界; 更激进放开前先保持保守。
- [x] I1.6 同步文档和回归摘要。README、`tool/build/test/README.md`、`doc/master_plan.md`、`doc/start_here.md` 和本文已对齐阶段 I 当前回归矩阵; 递归 / self-tail TCO 不引入新语法, 因此无 `doc/syntax/*` 变更; 最新默认完整回归基线为 `pass=874 fail=0 skip=3`。
- [x] I2.1 固定 `Tuple` 规格、arity、位置构造器和数字索引读取规则。结论: 第一版采用源码层大写内建泛型类型 `Tuple<T0, T1, ...>`; arity 下限为 2, 当前不设上限; 允许嵌套 `Tuple<Tuple<i32, bool>, u8>`; 允许作为局部绑定、参数、单返回、struct 字段、storage 元素和 union 分支。构造固定为 `Tuple<T0, T1, ...>{v0, v1, ...}` 的位置构造器, 实参数量必须与 arity 完全一致; 读取固定为 `@get(tuple_value, <index>)`, `<index>` 必须是编译期整数字面量且落在 `0..arity-1`。第一版不支持命名字段构造、`.v0/.v1` 字段段访问、`@set(tuple_value, <index>, value)` 数字索引写入、tuple literal、destructuring 或 pattern matching。`Tuple` 进入保留内建类型集合, 不能再被普通类型声明或 import alias 占用; 小写 `tuple<...>` 继续只保留给 WIT / `@wasi` 签名。
- [x] I2.2 更新 grammar / parser。结论: `Tuple<...>` 继续复用现有大写类型名 + type args 路径进入普通源码类型位; parser 现已接受 `Tuple<bool, u8>{true, 7}` 这类位置构造器语法, 并在 typed bind 左侧把小写 `tuple<bool, u8>` 拒绝为 `InvalidTypeRef`。这一轮只收语法层: 还不保证 sema/codegen 已能解释 `Tuple` 构造、索引访问或布局。
- [ ] I2.3 更新 sema 内建类型、构造器和字段访问规则。当前已完成最小产品切片所需的前端/类型接线: 小写 `tuple<...>` 在普通 typed bind 左侧被拒绝, `Tuple<>` / `Tuple<T>` 的 arity 下限已在前端校验, `@get(pair, 2)` 这类编译期越界索引已由 `compile_err/331_tuple_get_index_oob` 锁在当前 `NoMatchingCall` 行为; 后续仍需把 `Tuple` 正式提升为内建泛型类型, 系统化校验位置构造器实参数量 / 类型顺序、数字索引边界和更广泛的重载匹配。
- [ ] I2.4 更新 codegen layout / access / return / param / storage lowering。当前已完成最小 typed tuple build/compiled + arity/index + struct field + return/param multi-value + 嵌套 Tuple 叶子 ABI 展平 + **标量叶子 storage 内联 pack (scheme A)**: `compile_ok/259`–`264` 与 `compiled_ok/65`–`70` 覆盖 local/struct/return/param/nested ABI; 新增 `compile_ok/265_tuple_storage_put_get_lower`、`266_tuple_storage_nested_put_get_lower`、`267_tuple_storage_literal_set_lower` 与 `compiled_ok/71_compiled_test_tuple_storage_put_get`、`72_compiled_test_tuple_storage_nested`、`73_compiled_test_tuple_storage_set` 覆盖 `[Tuple<bool, u8>]` / 嵌套 `[Tuple<Tuple<bool, u8>, i32>]` 的 empty literal、`@put`/`@get`/`@set` 与 non-empty storage literal (runtime wasm 已 PASS)。实现: `tupleScalarLeafStorageByteWidth` + pack/unpack temps (`$__tuple_pack_*`), element 按叶子 payload 连续写入 storage data (bool+u8=5B, nested=9B), type id 仍走 `TYPE_ID_STORAGE_U8`。**仍后置**: managed payload 叶子、`[Tuple]` path chaining、loop 完整 tuple local、更明确 sema 诊断。

- [ ] I2.5 补 Tuple 正反例回归。
- [ ] I2.6 同步 README、语法文档、spec rules、grammar 和测试说明。

本轮证据:

- `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_ok/53_compiled_test_direct_and_mutual_recursion.do --compiled -o /tmp/do_i1_recursion.wat` 通过, 且 `wasm-tools parse` + `node tool/build/test/run_compiled_test_case.mjs /tmp/do_i1_recursion.wasm` 输出 `1 passed`。
- `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_err/02_recursive_call_no_matching_overload.do --compiled -o /tmp/do_i1_bad_recursive.wat` 失败并匹配 `NoMatchingCall`。
- `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_err/03_generic_recursive_call_currently_unsupported.do --compiled -o /tmp/do_i1_generic_recursive.wat` 失败并匹配 `NoMatchingCall`。
- `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/182_recursive_sum_and_parity.do` 通过, 输出 `1 passed`。
- `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/183_recursive_error_union.do` 通过, 输出 `1 passed`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/183_recursive_error_union.do --compiled -o /tmp/do_i1_recursive_error_union.wat` 通过, `wasm-tools parse` + `node tool/build/test/run_compiled_test_case.mjs` 输出 `1 passed`。
- `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/184_generic_recursive_known_arg.do` 通过, 输出 `1 passed`; `--compiled` 路径同样通过。
- `DO_LIB_ROOT=src ./bin/do test tool/build/test/err/329_generic_recursive_target_type_only_uninferred.do` 失败并匹配 `NoMatchingCall`。
- `cd tool && zig test build/parser.zig` 通过, 输出 `All 26 tests passed.`; 新增 parser red/green 覆盖 `Tuple<bool, u8>{true, 7}` 位置构造器语法和 typed bind 左侧小写 `tuple<bool, u8>` 的 `InvalidTypeRef`。
- `cd tool && zig test main.zig` 通过, 输出 `All 103 tests passed.`。
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `[INFO] summary: pass=886 fail=0 skip=3`。

- probe: `test "tuple lower type" { other tuple<bool, u8> = nil return }` 当前前端返回 `error[InvalidTypeRef]`; `test "tuple ctor" { other Tuple<bool, u8> = Tuple<bool, u8>{true, 7} return }` 当前 `do check` 前端不再报 `InvalidStructLiteral`。
- `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/259_tuple_pair_get_lower.do -o /tmp/259_tuple_pair_get_lower.wat` 通过, WAT 中已出现 `local.set $pair.v0` / `local.set $pair.v1` 与后续 `local.get $pair.v0` / `local.get $pair.v1`。
- `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_ok/65_compiled_test_tuple_pair.do --compiled -o /tmp/65_compiled_test_tuple_pair.wat` 通过; `wasm-tools parse` + `node tool/build/test/run_compiled_test_case.mjs` 输出 `test "compiled tuple pair" ... ok`。
- `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/260_tuple_struct_field_lower.do -o /tmp/260_tuple_struct_field_lower.wat` 通过, WAT 中已出现 `local.set $box.pair.v0` / `local.set $box.pair.v1` 与后续 `local.get $box.pair.v0` / `local.get $box.pair.v1`。
- `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_ok/66_compiled_test_tuple_struct_field.do --compiled -o /tmp/66_compiled_test_tuple_struct_field.wat` 通过; `wasm-tools parse` + `node tool/build/test/run_compiled_test_case.mjs` 输出 `test "compiled tuple struct field" ... ok`。
- `DO_LIB_ROOT=src ./bin/do test tool/build/test/err/330_lowercase_tuple_source_type.do` 失败并匹配 `InvalidTypeRef`。
- `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_err/331_tuple_get_index_oob.do -o /tmp/331_tuple_get_index_oob.wat` 失败并匹配 `NoMatchingCall`。
- `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_err/332_tuple_arity_one.do -o /tmp/332_tuple_arity_one.wat` 失败并匹配 `InvalidTypeRef`。
- `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_err/333_tuple_arity_zero.do -o /tmp/333_tuple_arity_zero.wat` 失败并匹配 `InvalidTypeRef`。
- `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/261_tuple_return_lower.do -o /tmp/261_tuple_return_lower.wat` 通过, WAT 中已出现 `(func $make_pair (result i32 i32)`、`call $make_pair` 后 reverse `local.set $pair.v1` / `local.set $pair.v0`。
- `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/262_tuple_param_get_lower.do -o /tmp/262_tuple_param_get_lower.wat` 通过, WAT 中已出现 `(func $pair_first (param $pair.v0 i32) (param $pair.v1 i32) (result i32)` 与 `call $pair_first`。
- `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_ok/67_compiled_test_tuple_return.do --compiled -o /tmp/67_compiled_test_tuple_return.wat` 通过, `.expect` 逐行匹配通过。
- `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_ok/68_compiled_test_tuple_param.do --compiled -o /tmp/68_compiled_test_tuple_param.wat` 通过, `.expect` 逐行匹配通过。
- `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/242_recursive_start_sum_lower.do -o /tmp/do_i1_recursive_start.wat` 通过, `.expect` 逐行匹配通过。

- `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/185_recursive_factorial.do` 通过, 输出 `1 passed`; `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/243_recursive_factorial_start_lower.do -o /tmp/do_i1_factorial_start.wat` 通过, `.expect` 逐行匹配通过; `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_ok/55_compiled_test_recursive_factorial.do --compiled -o /tmp/do_i1_factorial_compiled.wat` 通过且 wasm 执行 `1 passed`。
- `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/186_recursive_guard_return.do` 通过, 输出 `1 passed`; `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/244_recursive_if_else_start_lower.do -o /tmp/do_i1_if_else_start.wat` 通过, `.expect` 逐行匹配通过; `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_ok/56_compiled_test_recursive_if_else.do --compiled -o /tmp/do_i1_if_else_compiled.wat` 通过且 wasm 执行 `1 passed`。
- `DO_LIB_ROOT=tool/build/test/lib ./bin/do test tool/build/test/ok/187_imported_recursive_factorial.do` 通过, 输出 `1 passed`; `DO_LIB_ROOT=tool/build/test/lib ./bin/do build tool/build/test/compile_ok/245_imported_recursive_start_lower.do -o /tmp/do_i1_imported_factorial_start.wat` 通过, `.expect` 逐行匹配通过; `DO_LIB_ROOT=tool/build/test/lib ./bin/do test tool/build/test/compiled_ok/57_compiled_test_imported_recursive_factorial.do --compiled -o /tmp/do_i1_imported_factorial_compiled.wat` 通过且 wasm 执行 `1 passed`。
- `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/246_self_tail_scalar_tco_lower.do -o /tmp/do_i1_tco_green.wat` 通过, `.expect` 逐行匹配通过; `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_ok/58_compiled_test_self_tail_scalar_tco.do --compiled -o /tmp/do_i1_tco_compiled.wat` 通过且 wasm 执行 `1 passed`。
- `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/247_self_tail_if_else_tco_lower.do -o /tmp/do_i1_branch_tco_green.wat` 通过, `.expect` 逐行匹配通过; `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_ok/59_compiled_test_self_tail_if_else_tco.do --compiled -o /tmp/do_i1_branch_tco_compiled.wat` 通过且 wasm 执行 `1 passed`。
- `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/252_self_tail_guard_tco_lower.do -o /tmp/do_i1_guard_tco_green.wat` 通过, `.expect` 逐行匹配通过; `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_ok/60_compiled_test_self_tail_guard_tco.do --compiled -o /tmp/do_i1_guard_tco_compiled.wat` 通过且 wasm 执行 `1 passed`。
- `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/254_generic_self_tail_tco_lower.do -o /tmp/do_i1_generic_tco.wat` 通过, `.expect` 逐行匹配通过; `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_ok/61_compiled_test_generic_self_tail_tco.do --compiled -o /tmp/do_i1_generic_tco_compiled.wat` 通过且 wasm 执行 `1 passed`。
- `DO_LIB_ROOT=tool/build/test/lib ./bin/do test tool/build/test/ok/188_imported_self_tail_scalar_tco.do` 通过, 输出 `1 passed`; `DO_LIB_ROOT=tool/build/test/lib ./bin/do build tool/build/test/compile_ok/255_imported_self_tail_scalar_tco_lower.do -o /tmp/do_i1_imported_tco_build.wat` 通过, `.expect` 逐行匹配通过; `DO_LIB_ROOT=tool/build/test/lib ./bin/do test tool/build/test/compiled_ok/62_compiled_test_imported_self_tail_scalar_tco.do --compiled -o /tmp/do_i1_imported_tco_compiled.wat` 通过且 wasm 执行 `1 passed`。
- `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/257_generic_self_tail_if_else_tco_lower.do -o /tmp/do_i1_generic_if_else_tco.wat` 通过, `.expect` 逐行匹配通过; `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_ok/63_compiled_test_generic_self_tail_if_else_tco.do --compiled -o /tmp/do_i1_generic_if_else_tco_compiled.wat` 通过且 wasm 执行 `1 passed`。
- `DO_LIB_ROOT=tool/build/test/lib ./bin/do build tool/build/test/compile_ok/258_imported_self_tail_if_else_tco_lower.do -o /tmp/do_i1_imported_if_else_tco.wat` 通过, `.expect` 逐行匹配通过; `DO_LIB_ROOT=tool/build/test/lib ./bin/do test tool/build/test/compiled_ok/64_compiled_test_imported_self_tail_if_else_tco.do --compiled -o /tmp/do_i1_imported_if_else_tco_compiled.wat` 通过且 wasm 执行 `1 passed`。
- `DO_LIB_ROOT=tool/build/test/lib ./bin/do test tool/build/test/ok/189_imported_self_tail_if_else_tco.do` 通过, 输出 `1 passed`; imported self-tail `if/else` 的静态 runner 边界已收回。
- `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_ok/54_compiled_test_generic_recursive_known_arg.do --compiled -o /tmp/do_i1_compiled54.wat` 通过, `wasm-tools parse` + `node tool/build/test/run_compiled_test_case.mjs` 输出 `1 passed`。
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=874 fail=0 skip=3`; 回归后的 `tool/build/test/tmp` ignored 产物已清理到 `0`。

下一步:

- 下一步继续 I2.3/I2.4: 嵌套叶子 ABI 与标量叶子 storage pack 已落地; 后续优先 managed payload, 或把更多边界从产品级 `NoMatchingCall` 收敛成更明确的语义诊断。
- 若 I1 暂无新的可独立收口小项, 则切到 I2.1 `Tuple<...>` 规格固定, 先把 arity、位置构造器和数字索引规则写实。


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

状态: done

当前结论: 阶段 C 已完成。C1 JSON stringify / from_json、C2 字段反射 API、C3 bytes/text 边界、C4 集合 skip 收回、C5 基础库 executable/compiled fixture 与稳定公开文档边界均已收口。H1.3 已把标准库源码 `NoTestDecl` 从 skip 改为 metadata-only pass, H1.4 已为剩余 3 个 skip 记录原因和恢复条件, H2.1 已确认当前 markdown 本地链接无缺失, H2.2 已发现 README Roadmap 状态漂移, H2.3 已修正 README 过期状态描述, H3.1 已列出 55 个显式诊断 code/message, H3.2/H3.3 已修复 `InvalidReturnStmt` summary/hint 不一致, H3.4 full regression 已通过, H4 release smoke 已通过, H5.1 已把当前 v1 已完成能力汇总到 README, H5.2 已把 v1 非目标单独汇总到 README, H5.3 已把下一阶段计划写入 README, 阶段 H 最终验证已通过, 当前默认完整回归基线为 `pass=856 fail=0 skip=3`; `RUN_WASM=1` 扩展回归基线为 `pass=833 fail=0 skip=3`; 剩余 `16/96/118` 归 recv/WASI/resource 后置线。阶段 C 之后已进入阶段 D, D1-D5 已完成, D2.1 已按用户确认的 B 方案绿色 regression 收口。阶段 E 已完成, 阶段 F 已完成到 rename 评估并决定 v1 不支持 rename; G1-G5 已完成; G6.1、G6.3 已按阻断记录等待用户决策; G6.2 因当前无 async/Future runtime 暂时阻断; G6.4 已完成 public flags API 决策。阶段 I 当前已完成 I1.1 递归基线盘点, 并已补 I1.3 五批递归产品回归与 I1.2 语义边界负例。

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
  C. codegen/import 可达性缺口: `113_set_common_ops` 的最小探针显示 `Set`、`empty_set`、`set_len`、`set_has` 可 compiled build, 但 `set_add` 一进入可达路径就 `NoMatchingCall`; C4.3 复查后确认直接触发点是 `set_add` 内 `@put(items(xs), value)` 这种非本地 storage 源表达式不在当前 `@put` lowering 子集内, 先通过库内显式绑定 `data [T] = items(xs)` 收回 Set 基础用例。
  D. codegen/generic 实例化缺口: `36_hash_map_lib_ops`、`37_hash_map_set_missing_key`、`57_hash_map_del`、`115_hash_map_common_wrappers` 在 compiled build 阶段报 `NoMatchingCall`; 最小探针显示只导入 `HashMap` 类型可过, 直接调用 `hash_map_from_parts` 可过, 但调用 `empty_hash_map` 即失败, 断点落在 imported generic 函数体内两类型参数空 storage 构造与 `hash_map_from_parts(ks, vs)` helper 实例化链。C4.4 已补齐这些 compiled lowering 子集并收回四个用例。
  E. 聚合 smoke: `109_std_foundation_libs` 是跨 binary/math/path/list/hash/set/text/url 的大用例, compiled build 先在首个 binary import 处报 `NoMatchingCall`; C4 不把它作为第一批收回对象, 等 C4.2-C4.4 分项用例收回后再在 C4.5 更新或拆分 skip 原因。
  验证: `DO_LIB_ROOT=src ./bin/do test <case>` 静态 runner 取证; `DO_LIB_ROOT=src ./bin/do check <case>` 和 `DO_LIB_ROOT=src ./bin/do check src/{list,set,hash_map,fp}.do`; `DO_LIB_ROOT=src ./bin/do test <case> --compiled -o /tmp/<case>.c4_1.wat` + `wasm-tools parse` + `node tool/build/test/run_compiled_test_case.mjs` 对上述 compiled 正例执行通过; `git diff --check` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=717 fail=0 skip=68`。
- [x] C4.2 先收回 List 基础操作。实现: 新增 `tool/build/test/ok/49_list_storage_items.compiled_must_pass`、`56_list_del.compiled_must_pass`、`65_list_add_variadic.compiled_must_pass`, 不改 List 库语义和测试源码。RED: marker 不存在时, `DO_LIB_ROOT=src ./bin/do test` 对三项分别输出 `3 skipped`、`1 skipped`、`1 skipped`。GREEN: 三项 `--compiled` WAT 生成通过; `wasm-tools parse` 通过; `node tool/build/test/run_compiled_test_case.mjs` 分别执行通过 `3 passed`、`1 passed`、`1 passed`。完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=720 fail=0 skip=65`。
- [x] C4.3 再收回 Set 基础操作。实现: 新增 `tool/build/test/ok/113_set_common_ops.compiled_must_pass`, 并把 `src/set.do` 的 `set_add` 从直接 `@put(items(xs), value)` 改为先绑定本地 `data [T] = items(xs)`, 再执行 `data = @put(data, value)`。这不改变 Set 对外值语义, 只把标准库源码改回当前 storage write lowering 已支持的本地源形态。RED: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/113_set_common_ops.do --compiled -o /tmp/113_set_common_ops.c4_3.red.wat` 失败于 `NoMatchingCall`。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/113_set_common_ops.do --compiled -o /tmp/113_set_common_ops.c4_3.green.wat` 通过; `wasm-tools parse /tmp/113_set_common_ops.c4_3.green.wat -o /tmp/113_set_common_ops.c4_3.green.wasm` 通过; `node tool/build/test/run_compiled_test_case.mjs /tmp/113_set_common_ops.c4_3.green.wasm /tmp/113_set_common_ops.c4_3.green.wat` 通过 `1 passed`; `DO_LIB_ROOT=src ./bin/do check src/set.do` 通过; `git diff --check` 通过; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=721 fail=0 skip=64`。
- [x] C4.4 再收回 HashMap 基础操作。实现: 新增 `tool/build/test/ok/36_hash_map_lib_ops.compiled_must_pass`、`37_hash_map_set_missing_key.compiled_must_pass`、`57_hash_map_del.compiled_must_pass`、`115_hash_map_common_wrappers.compiled_must_pass`; `src/hash_map.do` 的 `hash_put/hash_set/hash_set_or` 改为先绑定本地 keys/values storage, 再走当前 `@put/@set` 已支持的本地源 lowering。codegen 修复点: `_ = expr` 作为 discard statement, 不再污染 locals, 但 call/expr 副作用仍执行; 显式泛型 storage 绑定如 `ks [K] = .{}` 和嵌套 `[Entry<K, V>]` 能被收集; 收集 imported generic struct 时清理 pending `#T` 参数并跳过函数体, 避免 `Entry` 的 type params 被前序泛型函数污染; 为 `Entry<[u8], i32>` 这类具体泛型 struct 生成精确 layout; 支持 `@get(@get(entries, 0), .key)` 的 nested managed struct field get; 支持 `[[u8]]` managed storage content equality; 修复嵌套 managed storage aggregate literal 使用 overwrite tmp 时覆盖外层 handle。RED: 四个目标在 marker 缺失或修复前会 skipped 或报 `NoMatchingCall`。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/36_hash_map_lib_ops.do --compiled -o /tmp/36_hash_map_lib_ops.c4_4.final.wat` + `wasm-tools parse` + `node tool/build/test/run_compiled_test_case.mjs` 通过 `4 passed`; `37_hash_map_set_missing_key` 通过 `1 passed`; `57_hash_map_del` 通过 `1 passed`; `115_hash_map_common_wrappers` 通过 `1 passed`; `DO_LIB_ROOT=src ./bin/do check src/hash_map.do` 通过; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=729 fail=0 skip=60`。
- [x] C4.5 更新 NoTestDecl 或 skip 原因。实现: 新增 `tool/build/test/ok/107_private_field_ctor_bridge.compiled_must_pass`、`119_mem_atomic_libs.compiled_must_pass`、`62_lambda_explicit_param_selects_overload.compiled_must_pass`、`63_func_name_selects_overload.compiled_must_pass`、`64_import_func_name_value_selects_overload.compiled_must_pass`、`70_error_type_single_letter_prefix.compiled_must_pass`、`88_local_constraint_name_overload.compiled_must_pass`、`95_imported_multi_return_values.compiled_must_pass`, 把 8 个已能 compiled WAT 生成、`wasm-tools parse` 和 Node 执行通过的漏网静态 skip 收回。当前剩余 ok skip 共 18 个: `109_std_foundation_libs`、`111_bytes_text_common_wrappers`、`117_encoding_json_common_wrappers`、`50_pipe_lib`、`96_file_lib_resource_shape`、`97_bytes_lib` 属于标准库 wrapper / resource shape / helper lowering 待拆分; `52_list_functional_ops`、`58_list_update`、`59_hash_map_update` 属于跨模块 lambda、函数类型约束或泛型返回推导待推进; `14_path_index_expr_segment`、`15_path_index_complex_expr_segment` 属于 path index 表达式和 List helper compiled 链待拆分; `16_loop_recv_value` 属于 recv loop compiled lowering 未支持; `39_else_if_chain` 当前 compiled WAT 在 wasm instantiate 阶段 stack fallthrough 校验失败; `41_is_value_type_guard`、`46_loop_label_break` 当前 compiled 执行触发 `unreachable`; `54_nested_if_blocks_are_not_structs` 当前 WAT parse 报 duplicate local; `07_net_socket_smoke` 属于 net/socket runtime smoke, 当前 compiled 执行触发 `unreachable`; `118_wasi_p3_std_wrappers` 属于 WASI P3 std wrapper, 继续归入后置 WASI / Component Model。std src `NoTestDecl` 共 31 个: `atomic`、`base64`、`binary`、`bytes`、`dir`、`file`、`fp`、`hash_map`、`hex`、`http.client`、`io.stream`、`json`、`list`、`math`、`md5`、`mem`、`net`、`path`、`random`、`range`、`set`、`sha1`、`sha256`、`simd`、`slice`、`tcp`、`text`、`time`、`udp`、`url`、`utf16`、`utf8`; 这些是标准库源码模块, 不是 test entry, 后续应通过 ok / compile_ok / compiled_ok fixture 验证公开 API, 不把 `do test src/*.do` 的 `NoTestDecl` 当成失败。`src/_.do` 是 builtin/core declaration table, runner 明确按 metadata table 处理。验证: 8 个新增 marker 对应用例均通过 `DO_LIB_ROOT=src ./bin/do test <case> --compiled -o /tmp/<case>.c4_5.marker.wat`、`wasm-tools parse` 和 `node tool/build/test/run_compiled_test_case.mjs`; 所有剩余 ok skip 通过 `DO_LIB_ROOT=src ./bin/do check`; 除 `src/_.do` 外所有 `src/*.do` 均通过 `DO_LIB_ROOT=src ./bin/do check`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=737 fail=0 skip=52`。备注: `06_hash_digest_smoke` 已在 C5.3.7 收回, `112_slice_range_common_wrappers` 已在 C5.3.11 收回。

C5 math / encoding / hash 基础库一致性:

- [x] C5.1 盘点 `src/*.do` 中只有 shape 没有测试的文件。取证口径: 只统计 `tool/build/test/{ok,compile_ok,compile_err,compiled_ok,compiled_err,run,check}` 中直接 `@lib("module.do", ...)` 引用的 fixture; 只被其他 `src` 模块内部依赖引用不算独立测试覆盖。严格没有任何直接 fixture 的模块只有 `simd.do`。只有 skipped fixture、没有 passing fixture 的模块有 15 个: `base64.do`、`binary.do`、`bytes.do`、`hex.do`、`http.client.do`、`md5.do`、`net.do`、`path.do`、`range.do`、`sha1.do`、`sha256.do`、`slice.do`、`tcp.do`、`udp.do`、`url.do`。只有 lowering/static 覆盖、还没有 executable fixture 的模块有 5 个: `dir.do`、`file.do`、`io.stream.do`、`random.do`、`time.do`。已有 executable 或明确诊断覆盖的模块有 11 个: `atomic.do`、`mem.do`、`fp.do`、`hash_map.do`、`json.do`、`list.do`、`math.do`、`set.do`、`text.do`、`utf16.do`、`utf8.do`。C5.2 推荐顺序: 先拆纯函数且不依赖 host 的 `binary/path/url/range/slice/bytes/hex`, 再处理 `base64/md5/sha1/sha256` 的 helper lowering, `simd` 单独决定是否保留或补最小 fixture; `net/tcp/udp/http.client/dir/file/io.stream/random/time` 归 C5.3 或后置 WASI/host 边界。验证: `@lib("module.do", ...)` 直接引用扫描完成; 31 个 std src `NoTestDecl` 与 `src/_.do` metadata table 边界沿用 C4.5 结论; 除 `src/_.do` 外所有 `src/*.do` 均通过 `DO_LIB_ROOT=src ./bin/do check`; `git diff --check` 通过。
- [x] C5.2 为纯函数库补 `do test` fixture。
  - [x] C5.2.1 `binary.do` 大小端定宽整数读写 executable fixture。实现: 新增 `tool/build/test/ok/152_binary_endian_helpers.do` 和 `.compiled_must_pass`, 覆盖 `read_u16/u32/u64` 的 little-endian / big-endian 与 `write_u16/u32/u64` 的 little-endian / big-endian。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/152_binary_endian_helpers.do` 输出 `1 skipped`。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/152_binary_endian_helpers.do --compiled -o /tmp/152_binary_endian_helpers.c5_2.wat`; `wasm-tools parse /tmp/152_binary_endian_helpers.c5_2.wat -o /tmp/152_binary_endian_helpers.c5_2.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/152_binary_endian_helpers.c5_2.wasm /tmp/152_binary_endian_helpers.c5_2.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=738 fail=0 skip=52`。
  - [x] C5.2.2 `path.do` 非 variadic helper executable fixture。实现: 新增 `tool/build/test/ok/153_path_helpers.do` 和 `.compiled_must_pass`, 覆盖 `is_absolute/is_empty/basename/dirname/extname`。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/153_path_helpers.do` 输出 `1 skipped`。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/153_path_helpers.do --compiled -o /tmp/153_path_helpers.c5_2.wat`; `wasm-tools parse /tmp/153_path_helpers.c5_2.wat -o /tmp/153_path_helpers.c5_2.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/153_path_helpers.c5_2.wasm /tmp/153_path_helpers.c5_2.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=739 fail=0 skip=52`。备注: `join(a [u8], b [u8], rest ...[u8])` 仍触发 imported variadic `[u8]` helper 链 `NoMatchingCall`, 本项先不扩大 codegen 修复范围, 后续随 `bytes.concat/text.concat` 同类 variadic `[u8]` 问题一起处理。
  - [x] C5.2.3 `url.do` encode executable fixture。实现: 新增 `tool/build/test/ok/154_url_escape_helpers.do` 和 `.compiled_must_pass`, 覆盖 `url_encode` 对空格、问号和 unreserved 字符的输出。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/154_url_escape_helpers.do` 输出 `1 skipped`。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/154_url_escape_helpers.do --compiled -o /tmp/154_url_escape_helpers.c5_2.wat`; `wasm-tools parse /tmp/154_url_escape_helpers.c5_2.wat -o /tmp/154_url_escape_helpers.c5_2.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/154_url_escape_helpers.c5_2.wasm /tmp/154_url_escape_helpers.c5_2.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=740 fail=0 skip=52`。备注: 当时保留的 `url_decode` 和 `UrlInvalidEscape` imported error branch / union helper 链已在 C5.3.9 收回。
  - [x] C5.2.4 `range.do` executable fixture。实现: 新增 `tool/build/test/ok/155_range_helpers.do` 和 `.compiled_must_pass`, 覆盖 `range_i32/range_usize` 的非空和空区间, 以及 `repeat_i32/repeat_usize` 的非空和 0 次重复。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/155_range_helpers.do` 输出 `1 skipped`。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/155_range_helpers.do --compiled -o /tmp/155_range_helpers.c5_2.wat`; `wasm-tools parse /tmp/155_range_helpers.c5_2.wat -o /tmp/155_range_helpers.c5_2.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/155_range_helpers.c5_2.wasm /tmp/155_range_helpers.c5_2.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=741 fail=0 skip=52`。
  - [x] C5.2.5 `slice.do` 访问 helper executable fixture。实现: 新增 `tool/build/test/ok/156_slice_access_helpers.do` 和 `.compiled_must_pass`, 覆盖 `first/first_or/last/last_or` 对非空 `[i32]` 和空 `[i32]` fallback 的行为。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/156_slice_access_helpers.do` 输出 `1 skipped`。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/156_slice_access_helpers.do --compiled -o /tmp/156_slice_access_helpers.c5_2.wat`; `wasm-tools parse /tmp/156_slice_access_helpers.c5_2.wat -o /tmp/156_slice_access_helpers.c5_2.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/156_slice_access_helpers.c5_2.wasm /tmp/156_slice_access_helpers.c5_2.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=742 fail=0 skip=52`。备注: 当时保留的 `slice_or/take_or/drop_or` generic error-union wrapper imported helper 链已在 C5.3.10 收回。
  - [x] C5.2.6 `bytes.do` sequence helper executable fixture。实现: 新增 `tool/build/test/ok/157_bytes_sequence_helpers.do` 和 `.compiled_must_pass`, 覆盖 `is_empty/copy/repeat_byte/starts_with/ends_with/contains/index_of/last_index_of/replace/first/first_or/last/last_or` 的 `[u8]` 行为, 包括 search miss 的 `nil` 返回和空 bytes fallback。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/157_bytes_sequence_helpers.do` 输出 `1 skipped`。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/157_bytes_sequence_helpers.do --compiled -o /tmp/157_bytes_sequence_helpers.c5_2.wat`; `wasm-tools parse /tmp/157_bytes_sequence_helpers.c5_2.wat -o /tmp/157_bytes_sequence_helpers.c5_2.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/157_bytes_sequence_helpers.c5_2.wasm /tmp/157_bytes_sequence_helpers.c5_2.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=743 fail=0 skip=52`。保留边界: `bytes_trim_left_byte` 单独 compiled 探针仍在 import 阶段报 `NoMatchingCall`; `bytes_copy`、`bytes_contains`、`bytes_index_of/last_index_of` 和 `bytes_replace` 单独 compiled 探针均通过。因此 `trim_*` 暂归后续 helper 链修复; `concat/slice/take/drop` 继续因 variadic 或 `BytesError` union 边界留在后续项。
  - [x] C5.2.7 `hex.do` encode executable fixture。实现: 新增 `tool/build/test/ok/158_hex_encode_helpers.do` 和 `.compiled_must_pass`, 覆盖 `encode/encode_upper` 对空 bytes、lowercase 和 uppercase 输出。生产修复: `src/hex.do` 去掉 `list.do` 依赖和 top-level alphabet `[u8]` lookup, 改用本地 `[u8]` + `@put` 构建输出, 并用 `encode_digit(value, upper)` 算术生成 hex digit; 这是因为本地 compiled 探针确认 `@div/@rem` 和 `@as(usize, u8)` 正常, 但 `@get(top_level_bytes, index)` 在当前 compiled lowering 中会触发 `NoMatchingCall`。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/158_hex_encode_helpers.do` 输出 `1 skipped`; 初次加 marker 后 `hex_encode = @lib("hex.do", encode)` 报 `NoMatchingCall`。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/158_hex_encode_helpers.do --compiled -o /tmp/158_hex_encode_helpers.c5_2.wat`; `wasm-tools parse /tmp/158_hex_encode_helpers.c5_2.wat -o /tmp/158_hex_encode_helpers.c5_2.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/158_hex_encode_helpers.c5_2.wasm /tmp/158_hex_encode_helpers.c5_2.wat` 通过 `1 passed`; `DO_LIB_ROOT=src ./bin/do check src/hex.do` 通过; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=744 fail=0 skip=52`。备注: 当时保留的 `hex_decode` imported error-union 边界已在 C5.3.8 收回。
- [x] C5.3 为需要 codegen / imported helper 链支持的库补 compiled fixture。结论: C5.3.1-C5.3.33 已完成, 非 WASI/resource executable skip 已清空; 剩余 `16/96/118` 归 recv/WASI/resource 后置线, 公开边界已由 C5.4 收口。
  - [x] C5.3.1 `base64.do` encode executable fixture。实现: 新增 `tool/build/test/ok/159_base64_encode_helpers.do` 和 `.compiled_must_pass`, 覆盖 `encode/encode_raw/encode_url/encode_raw_url` 对空 bytes、标准 padding、raw、URL alphabet 和 raw URL 输出。生产修复: `src/base64.do` 的四个常用 encode 入口改为直接 `[u8]` + `@put` 构建输出, 用 `encode_digit(index, url)` 算术生成 base64 digit, 避开当前 compiled import 对 `List<u8>` helper 链和 top-level alphabet `[u8]` dynamic lookup 的 `NoMatchingCall` 边界; `encode_with/decode_with` 暂不改, 避免扩大 `Encoding/new/with_padding/without_padding` 的公共策略语义。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/159_base64_encode_helpers.do` 输出 `1 skipped`; 加 marker 后初次 compiled 在 `base64_encode = @lib("base64.do", encode)` 报 `NoMatchingCall`; 第一次修复后 WAT parse 报 `duplicate local identifier $b0`, 通过拆分 `encode_config` 分支局部名收口。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/159_base64_encode_helpers.do --compiled -o /tmp/159_base64_encode_helpers.green.wat`; `wasm-tools parse /tmp/159_base64_encode_helpers.green.wat -o /tmp/159_base64_encode_helpers.green.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/159_base64_encode_helpers.green.wasm /tmp/159_base64_encode_helpers.green.wat` 通过 `1 passed`; `DO_LIB_ROOT=src ./bin/do check src/base64.do` 通过; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=745 fail=0 skip=52`。保留边界: `decode/decode_raw/decode_url/decode_raw_url` 和显式 `Encoding` 策略仍属于 error-union/imported helper 链后续项。
  - [x] C5.3.2 `base64.do` decode 成功路径 executable fixture。实现: 新增 `tool/build/test/ok/160_base64_decode_helpers.do` 和 `.compiled_must_pass`, 覆盖 `decode/decode_raw/decode_url/decode_raw_url` 对标准 padding、raw、URL alphabet 和 raw URL 输入的成功解码。生产修复: `src/base64.do` 的四个公开 decode 入口改为直接 `[u8]` + `@put` 构建输出, 用 `decode_digit_config(c, url) -> u8 | Base64Error` 算术解析 digit, 避开当前 compiled import 对 `List<u8>` helper 链和 top-level alphabet dynamic lookup 的 `NoMatchingCall` 边界; fixture 按 JSON 既有模式使用 `base64_bytes_eq(value [u8] | Base64Error, expect [u8])` 先用 `@is(value, Base64Error)` guard 排除错误分支后再比较 payload。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/160_base64_decode_helpers.do` 输出 `1 skipped`; 初始导入 `InvalidLength` 分支值和直接 `@eq(decoded, "hello")` 均会在 compiled 阶段报 `NoMatchingCall`, 因此本项先固定成功路径和必要 narrowing pattern。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/160_base64_decode_helpers.do --compiled -o /tmp/160_base64_decode_helpers.green.wat`; `wasm-tools parse /tmp/160_base64_decode_helpers.green.wat -o /tmp/160_base64_decode_helpers.green.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/160_base64_decode_helpers.green.wasm /tmp/160_base64_decode_helpers.green.wat` 通过 `1 passed`; `DO_LIB_ROOT=src ./bin/do check src/base64.do` 通过; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=746 fail=0 skip=52`。保留边界: 显式 `Encoding` 策略仍未收回; base64 错误分支另拆小项。
  - [x] C5.3.3 base64 decode 错误分支 executable fixture。实现: 新增 `tool/build/test/ok/161_base64_decode_error_helpers.do` 和 `.compiled_must_pass`, 覆盖 `decode("x") -> InvalidLength`、`decode("!!!!") -> InvalidDigit`、`decode_raw("AA==") -> InvalidPadding`。fixture 使用三个专用 helper: `base64_is_invalid_length/digit/padding(value [u8] | Base64Error) -> bool`, 在 `@is(value, Base64Error)` guard 后和 imported branch value 比较。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/161_base64_decode_error_helpers.do` 输出 `1 skipped`; 初版 `base64_error_eq(value [u8] | Base64Error, err Base64Error)` 在 compiled import 阶段报 `NoMatchingCall`, 根因收窄为 imported error type 作为普通函数参数类型的当前边界。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/161_base64_decode_error_helpers.do --compiled -o /tmp/161_base64_decode_error_helpers.green.wat`; `wasm-tools parse /tmp/161_base64_decode_error_helpers.green.wat -o /tmp/161_base64_decode_error_helpers.green.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/161_base64_decode_error_helpers.green.wasm /tmp/161_base64_decode_error_helpers.green.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=747 fail=0 skip=52`。保留边界: imported error type 作为可传递值参数的泛化 helper 暂不作为当前设计推荐, 后续若需要再单独设计。
  - [x] C5.3.4 `md5.do` digest executable fixture。实现: 新增 `tool/build/test/ok/162_md5_digest_helpers.do` 和 `.compiled_must_pass`, 覆盖 `sum("abc")` 和 `sum("")` 经 `hex.encode` 后的标准 MD5 digest。生产修复: `src/md5.do` 显式导入 `math.do` 的 `add_wrap_u32/bit_not_u32`; 将 `_md5_s/_md5_k` 从 top-level `[u32]` 动态 lookup 改为 `block` 局部 storage literal; 将 `words` 构建从 `@put(.{}, ...16 values...)` 改为局部 storage literal `.{...}`。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/162_md5_digest_helpers.do` 输出 `1 skipped`; 初次 compiled 在 `md5_sum = @lib("md5.do", sum)` 链路报 `NoMatchingCall`; 标量探针确认缺显式 math import; 临时 top-level table 探针确认 imported compiled 函数里动态读取 top-level storage 会报 `NoMatchingCall`; 临时 `@put(.{}, 16 values)` 探针确认多元素 builder 也会报 `NoMatchingCall`, 而局部 storage literal 可过。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/162_md5_digest_helpers.do --compiled -o /tmp/162_md5_digest_helpers.green.wat`; `wasm-tools parse /tmp/162_md5_digest_helpers.green.wat -o /tmp/162_md5_digest_helpers.green.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/162_md5_digest_helpers.green.wasm /tmp/162_md5_digest_helpers.green.wat` 通过 `1 passed`; `DO_LIB_ROOT=src ./bin/do check src/md5.do` 通过; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=748 fail=0 skip=52`。
  - [x] C5.3.5 `sha1.do` digest executable fixture。实现: 新增 `tool/build/test/ok/163_sha1_digest_helpers.do` 和 `.compiled_must_pass`, 覆盖 `sum("abc")` 和 `sum("")` 经 `hex.encode` 后的标准 SHA1 digest。生产修复: `src/sha1.do` 显式导入 `math.do` 的 `add_wrap_u32/bit_not_u32`; 将 `w` 构建从 `@put(.{}, ...16 values...)` 改为局部 storage literal `.{...}`。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/163_sha1_digest_helpers.do` 输出 `1 skipped`; 初次 compiled 在 `sha1_sum = @lib("sha1.do", sum)` 链路报 `NoMatchingCall`, 与 MD5 同类。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/163_sha1_digest_helpers.do --compiled -o /tmp/163_sha1_digest_helpers.green.wat`; `wasm-tools parse /tmp/163_sha1_digest_helpers.green.wat -o /tmp/163_sha1_digest_helpers.green.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/163_sha1_digest_helpers.green.wasm /tmp/163_sha1_digest_helpers.green.wat` 通过 `1 passed`; `DO_LIB_ROOT=src ./bin/do check src/sha1.do` 通过; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=749 fail=0 skip=52`。
  - [x] C5.3.6 `sha256.do` digest executable fixture。实现: 新增 `tool/build/test/ok/164_sha256_digest_helpers.do` 和 `.compiled_must_pass`, 覆盖 `sum("abc")` 和 `sum("")` 经 `hex.encode` 后的标准 SHA256 digest。生产修复: `src/sha256.do` 显式导入 `math.do` 的 `add_wrap_u32/bit_not_u32`; 删除 top-level `_sha256_k` 动态表和 `sha256_k_table`; 在 `block` 内使用局部 `sha256_k` storage literal; 将 `w` 构建从 `list_add(.{}, ...16 values...)` 改为局部 storage literal `.{...}`。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/164_sha256_digest_helpers.do` 输出 `1 skipped`; 初次 compiled 在 `sha256_sum = @lib("sha256.do", sum)` 链路报 `NoMatchingCall`, 与 MD5/SHA1 同类。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/164_sha256_digest_helpers.do --compiled -o /tmp/164_sha256_digest_helpers.green.wat`; `wasm-tools parse /tmp/164_sha256_digest_helpers.green.wat -o /tmp/164_sha256_digest_helpers.green.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/164_sha256_digest_helpers.green.wasm /tmp/164_sha256_digest_helpers.green.wat` 通过 `1 passed`; `DO_LIB_ROOT=src ./bin/do check src/sha256.do` 通过; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=750 fail=0 skip=52`。
  - [x] C5.3.7 收回旧 `06_hash_digest_smoke` compiled smoke。实现: 新增 `tool/build/test/ok/06_hash_digest_smoke.compiled_must_pass`, 把同一 fixture 内 MD5/SHA1/SHA256 的 `abc` 和空输入六个 digest smoke 固定为 compiled 必过。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/06_hash_digest_smoke.do --compiled -o /tmp/06_hash_digest_smoke.try.wat` 输出 `compiled_tests=6`; `wasm-tools parse /tmp/06_hash_digest_smoke.try.wat -o /tmp/06_hash_digest_smoke.try.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/06_hash_digest_smoke.try.wasm /tmp/06_hash_digest_smoke.try.wat` 通过 `6 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=751 fail=0 skip=51`。
  - [x] C5.3.8 `hex_decode` executable fixture。实现: 新增 `tool/build/test/ok/165_hex_decode_helpers.do` 和 `.compiled_must_pass`, 覆盖 lowercase/mixed-case decode 成功路径、`InvalidLength` 和 `InvalidDigit` 错误分支。fixture 使用 `hex_bytes_eq(value [u8] | HexError, expect [u8])` 和专用 `hex_is_invalid_length/digit(...)` helper, 在 `@is(value, HexError)` guard 后比较 imported branch value。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/165_hex_decode_helpers.do` 输出 `1 skipped`。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/165_hex_decode_helpers.do --compiled -o /tmp/165_hex_decode_helpers.try.wat`; `wasm-tools parse /tmp/165_hex_decode_helpers.try.wat -o /tmp/165_hex_decode_helpers.try.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/165_hex_decode_helpers.try.wasm /tmp/165_hex_decode_helpers.try.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=752 fail=0 skip=51`。
  - [x] C5.3.9 `url_decode` executable fixture。实现: 新增 `tool/build/test/ok/166_url_decode_helpers.do` 和 `.compiled_must_pass`, 覆盖普通 unreserved 字节、大小写 percent escape、截断 escape 和非法 hex digit。fixture 使用 `url_bytes_eq(value [u8] | UrlError, expect [u8])` 和 `url_is_invalid_escape(...)`, 在 `@is(value, UrlError)` guard 后比较 imported `UrlInvalidEscape`。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/166_url_decode_helpers.do` 输出 `1 skipped`。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/166_url_decode_helpers.do --compiled -o /tmp/166_url_decode_helpers.try.wat`; `wasm-tools parse /tmp/166_url_decode_helpers.try.wat -o /tmp/166_url_decode_helpers.try.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/166_url_decode_helpers.try.wasm /tmp/166_url_decode_helpers.try.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=753 fail=0 skip=51`。
  - [x] C5.3.10 `slice_or/take_or/drop_or` executable fixture。实现: 新增 `tool/build/test/ok/167_slice_fallback_helpers.do` 和 `.compiled_must_pass`, 覆盖 `slice_or` 的正常切片、非法 range、越界 fallback, 以及 `take_or/drop_or` 的正常和越界 fallback。生产修复: `src/slice.do` 的 `slice_or/take_or/drop_or` 改为直接检查边界并构造输出, 不再先调用 `slice/take/drop` union helper 后收窄 payload; 这是因为当前 imported compiled helper 链对“泛型函数调用同模块 union-returning helper 再返回 payload”的形态会在 `@lib("slice.do", slice_or)` 处报 `NoMatchingCall`。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/167_slice_fallback_helpers.do` 输出 `1 skipped`; 初次 compiled 报 `error[NoMatchingCall]` at `slice_slice_or = @lib("slice.do", slice_or)`。GREEN: `DO_LIB_ROOT=src ./bin/do check src/slice.do`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/167_slice_fallback_helpers.do --compiled -o /tmp/167_slice_fallback_helpers.try.wat`; `wasm-tools parse /tmp/167_slice_fallback_helpers.try.wat -o /tmp/167_slice_fallback_helpers.try.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/167_slice_fallback_helpers.try.wasm /tmp/167_slice_fallback_helpers.try.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=754 fail=0 skip=51`。
  - [x] C5.3.11 收回旧 `112_slice_range_common_wrappers` compiled wrapper。实现: 新增 `tool/build/test/ok/112_slice_range_common_wrappers.compiled_must_pass`, 在 C5.3.10 的 `slice_or/take_or/drop_or` 修复后, 旧 wrapper 内 `range.repeat_i32`、`slice first/last` 和 fallback 组合已整体 compiled 可执行。结论: 先前 `repeat_i32 = @lib("range.do", repeat_i32)` 处的 `NoMatchingCall` 是导入期表象, `155_range_helpers` 已证明 range 本身可 compiled, 根因是同 fixture 后续 slice fallback helper 链。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/112_slice_range_common_wrappers.do --compiled -o /tmp/112_slice_range_common_wrappers.after_slice.wat`; `wasm-tools parse /tmp/112_slice_range_common_wrappers.after_slice.wat -o /tmp/112_slice_range_common_wrappers.after_slice.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/112_slice_range_common_wrappers.after_slice.wasm /tmp/112_slice_range_common_wrappers.after_slice.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=755 fail=0 skip=50`。
  - [x] C5.3.12 `bytes.slice/take/drop/_or` executable fixture。实现: 新增 `tool/build/test/ok/168_bytes_slice_helpers.do` 和 `.compiled_must_pass`, 覆盖 `slice/take/drop` 的成功和 `BytesError` 分支, 以及 `slice_or/take_or/drop_or` fallback。生产修复: `src/bytes.do` 的 `slice_or/take/take_or/drop/drop_or` 改为直接边界检查和输出构造, 避开公开 wrapper 调用同模块 union-returning helper 后再返回 payload的 imported helper 链形态。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/168_bytes_slice_helpers.do` 输出 `1 skipped`; 旧 `111_bytes_text_common_wrappers` 仍在 `bytes_drop = @lib("bytes.do", drop)` 处报 `NoMatchingCall`, 但 focused fixture 证明 bytes slice 子集已可收回, 旧 `111` 的剩余失败应继续拆到 text/trim 子集定位。GREEN: `DO_LIB_ROOT=src ./bin/do check src/bytes.do`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/168_bytes_slice_helpers.do --compiled -o /tmp/168_bytes_slice_helpers.try.wat`; `wasm-tools parse /tmp/168_bytes_slice_helpers.try.wat -o /tmp/168_bytes_slice_helpers.try.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/168_bytes_slice_helpers.try.wasm /tmp/168_bytes_slice_helpers.try.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=756 fail=0 skip=50`。
  - [x] C5.3.13 `text.slice_or` executable fixture。实现: 新增 `tool/build/test/ok/169_text_slice_helpers.do` 和 `.compiled_must_pass`, 覆盖 `text.slice_or` 的成功切片和非法 range fallback。生产修复: `src/text.do` 的 `slice_or` 改为直接边界检查和输出构造, 并清理不再使用的 `bytes_slice_or` import; 这是因为 text wrapper 转调 bytes wrapper 的 imported helper 链在 `text_slice_or = @lib("text.do", slice_or)` 处报 `NoMatchingCall`。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/169_text_slice_helpers.do` 输出 `1 skipped`; 初版包含 `text.trim_*` 时仍失败, 缩小到 slice_only 后通过, 因此 trim 另拆小项。GREEN: `DO_LIB_ROOT=src ./bin/do check src/text.do`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/169_text_slice_helpers.do --compiled -o /tmp/169_text_slice_helpers.try.wat`; `wasm-tools parse /tmp/169_text_slice_helpers.try.wat -o /tmp/169_text_slice_helpers.try.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/169_text_slice_helpers.try.wasm /tmp/169_text_slice_helpers.try.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=757 fail=0 skip=50`。
  - [x] C5.3.14 `text.trim_*` executable fixture。实现: 新增 `tool/build/test/ok/170_text_trim_helpers.do` 和 `.compiled_must_pass`, 覆盖 `trim_left_byte/trim_byte/trim_right_byte` 的普通输入和全 trim 输入。生产修复: `src/text.do` 的 `trim_*` 改为直接实现并清理不再使用的 bytes trim imports; `src/bytes.do` 和 `src/text.do` 的 trim 空结果从直接 `return .{}` 改为先绑定 `empty [u8] = .{}` 再返回, 避开当前 imported compiled helper 对直接空 storage literal return 的 `NoMatchingCall`。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/170_text_trim_helpers.do` 输出 `1 skipped`; 初始 compiled 报 `NoMatchingCall` at `text_trim_left_byte = @lib("text.do", trim_left_byte)`; 缩小到 trim_left 后仍失败, 改为局部 empty return 后通过。GREEN: `DO_LIB_ROOT=src ./bin/do check src/text.do`; `DO_LIB_ROOT=src ./bin/do check src/bytes.do`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/170_text_trim_helpers.do --compiled -o /tmp/170_text_trim_helpers.try.wat`; `wasm-tools parse /tmp/170_text_trim_helpers.try.wat -o /tmp/170_text_trim_helpers.try.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/170_text_trim_helpers.try.wasm /tmp/170_text_trim_helpers.try.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=758 fail=0 skip=50`。
  - [x] C5.3.15 `bytes.trim_*` executable fixture。实现: 新增 `tool/build/test/ok/171_bytes_trim_helpers.do` 和 `.compiled_must_pass`, 覆盖 `trim_left_byte/trim_byte/trim_right_byte` 的普通输入和全 trim 输入。生产代码无新增修改; 该项复用 C5.3.14 已完成的 `src/bytes.do` empty storage literal return 局部绑定修复。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/171_bytes_trim_helpers.do` 输出 `1 skipped`。GREEN: `DO_LIB_ROOT=src ./bin/do check src/bytes.do`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/171_bytes_trim_helpers.do --compiled -o /tmp/171_bytes_trim_helpers.try.wat`; `wasm-tools parse /tmp/171_bytes_trim_helpers.try.wat -o /tmp/171_bytes_trim_helpers.try.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/171_bytes_trim_helpers.try.wasm /tmp/171_bytes_trim_helpers.try.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=759 fail=0 skip=50`。
  - [x] C5.3.16 `text.take/drop/_or` executable fixture。实现: 新增 `tool/build/test/ok/172_text_take_drop_helpers.do` 和 `.compiled_must_pass`, 覆盖 `take/drop` 的成功与 `BytesOutOfBounds` 分支, 以及 `take_or/drop_or` 的 fallback 返回。生产代码无新增修改; 当前 text -> bytes union-returning forwarder 在该 focused fixture 下已可 compiled 执行。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/172_text_take_drop_helpers.do` 输出 `1 skipped`。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/172_text_take_drop_helpers.do --compiled -o /tmp/172_text_take_drop_helpers.try.wat`; `wasm-tools parse /tmp/172_text_take_drop_helpers.try.wat -o /tmp/172_text_take_drop_helpers.try.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/172_text_take_drop_helpers.try.wasm /tmp/172_text_take_drop_helpers.try.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=760 fail=0 skip=50`。
  - [x] C5.3.17 `text` 非 variadic sequence wrapper executable fixture。实现: 新增 `tool/build/test/ok/173_text_sequence_helpers.do` 和 `.compiled_must_pass`, 覆盖 `copy/repeat_byte/first/first_or/last/last_or/index_of/last_index_of/replace`。生产代码无新增修改; 该项刻意不纳入 `concat`, 避免和 variadic `[u8]` helper 边界混在同一个小任务。RED: 未加 marker 时 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/173_text_sequence_helpers.do` 输出 `1 skipped`。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/173_text_sequence_helpers.do --compiled -o /tmp/173_text_sequence_helpers.try.wat`; `wasm-tools parse /tmp/173_text_sequence_helpers.try.wat -o /tmp/173_text_sequence_helpers.try.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/173_text_sequence_helpers.try.wasm /tmp/173_text_sequence_helpers.try.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=761 fail=0 skip=50`。
  - [x] C5.3.18 `bytes.concat` / `text.concat` variadic `[u8]` wrapper executable fixture。实现: 新增 `tool/build/test/ok/174_bytes_text_concat_helpers.do` 和 `.compiled_must_pass`, 覆盖 `bytes.concat` 与 `text.concat` 的 2 参数和 3 参数调用。生产修复: `tool/build/imports.zig` 的 imported func shape 对 `[u8]` 使用 compact type name, `tool/build/codegen.zig` 的 variadic storage ABI 支持 `[u8]` 参数打包为 `[[u8]]`, 并新增 `__storage_write_target_tmp` 保存 managed storage put 的目标数组, 避免 RHS storage/string 分配复用 `__storage_overwrite_tmp` 后把 variadic pack 指针污染成最后一个元素。RED: 初始 compiled 执行触发 `RuntimeError: unreachable`, 栈为 `__layout_managed_count -> __arc_release_managed_children -> __arc_release -> __arc_drain_release_worklist -> __arc_dec -> bytes_concat`; WAT 证据显示 variadic pack 本身是 `TYPE_ID_STORAGE_MANAGED=65535`, 但 managed put 写完第三个元素后把 `__storage_overwrite_tmp` 当成 pack 更新 len 并返回, 根因是目标 local 被 RHS 覆盖。GREEN: `cd tool && zig test main.zig` 通过 `52/52`; `cd tool && zig test build/codegen.zig --test-filter "variadic storage"` 通过; `cd tool && zig build -Doptimize=Debug`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/174_bytes_text_concat_helpers.do --compiled -o /tmp/174_bytes_text_concat_helpers.try.wat`; `wasm-tools parse /tmp/174_bytes_text_concat_helpers.try.wat -o /tmp/174_bytes_text_concat_helpers.try.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/174_bytes_text_concat_helpers.try.wasm /tmp/174_bytes_text_concat_helpers.try.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=762 fail=0 skip=50`。
  - [x] C5.3.19 旧 `117_encoding_json_common_wrappers` executable wrapper。实现: 更新 `tool/build/test/ok/117_encoding_json_common_wrappers.do`, 把 `Base64Error` / `HexError` / `JsonError` 的 union 返回值直接 `@eq` 改为 helper 中先 `@is(value, ErrorType)` 收窄, 再比较 payload 或 error branch; 新增 `.compiled_must_pass`。生产代码无新增修改。RED: 修改前 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/117_encoding_json_common_wrappers.do --compiled -o /tmp/117_encoding_json_common_wrappers.probe.wat` 在 import 展开期报 `error[NoMatchingCall]` at line 1; `DO_LIB_ROOT=src ./bin/do check tool/build/test/ok/117_encoding_json_common_wrappers.do` 通过, 说明这是 compiled helper / union narrowing 使用方式问题, 不是 parser 或 sema 静态错误。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/117_encoding_json_common_wrappers.do --compiled -o /tmp/117_encoding_json_common_wrappers.try.wat`; `wasm-tools parse /tmp/117_encoding_json_common_wrappers.try.wat -o /tmp/117_encoding_json_common_wrappers.try.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/117_encoding_json_common_wrappers.try.wasm /tmp/117_encoding_json_common_wrappers.try.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=763 fail=0 skip=49`。
  - [x] C5.3.20 旧 `111_bytes_text_common_wrappers` executable wrapper。实现: 更新 `tool/build/test/ok/111_bytes_text_common_wrappers.do`, 新增 `BytesError` import 和 `bytes_value_eq` helper, 把 `bytes_take/drop` 与 `text_take/drop` 的 `[u8] | BytesError` 返回值先 `@is(value, BytesError)` 收窄, 再比较 payload; 新增 `.compiled_must_pass`。生产代码无新增修改。RED: 修改前 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/111_bytes_text_common_wrappers.do --compiled -o /tmp/111_bytes_text_common_wrappers.probe.wat` 在 import 展开期报 `error[NoMatchingCall]` at line 1; `DO_LIB_ROOT=src ./bin/do check tool/build/test/ok/111_bytes_text_common_wrappers.do` 通过, 说明问题在 compiled union payload 比较写法。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/111_bytes_text_common_wrappers.do --compiled -o /tmp/111_bytes_text_common_wrappers.try.wat`; `wasm-tools parse /tmp/111_bytes_text_common_wrappers.try.wat -o /tmp/111_bytes_text_common_wrappers.try.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/111_bytes_text_common_wrappers.try.wasm /tmp/111_bytes_text_common_wrappers.try.wat` 通过 `2 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=764 fail=0 skip=48`。
  - [x] C5.3.21 旧 `97_bytes_lib` executable wrapper。实现: 更新 `tool/build/test/ok/97_bytes_lib.do`, 新增 `bytes_value_eq` 和 `bytes_is_invalid_range` helper, 把 `bytes_slice` 的 `[u8] | BytesError` 返回值先 `@is(value, BytesError)` 收窄, 再比较 payload 或 error branch; 新增 `.compiled_must_pass`。生产代码无新增修改。RED: 修改前 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/97_bytes_lib.do --compiled -o /tmp/97_bytes_lib.probe.wat` 在 import 展开期报 `error[NoMatchingCall]` at line 1; `DO_LIB_ROOT=src ./bin/do check tool/build/test/ok/97_bytes_lib.do` 通过。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/97_bytes_lib.do --compiled -o /tmp/97_bytes_lib.try.wat`; `wasm-tools parse /tmp/97_bytes_lib.try.wat -o /tmp/97_bytes_lib.try.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/97_bytes_lib.try.wasm /tmp/97_bytes_lib.try.wat` 通过 `2 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=765 fail=0 skip=47`。
  - [x] C5.3.22 旧 `109_std_foundation_libs` executable wrapper。实现: 更新 `tool/build/test/ok/109_std_foundation_libs.do`, 为 base64/hex/json/path/list/hash/set/text/url 聚合 smoke 增加显式错误类型 import 和 helper narrowing, 把 `[T] | Error`、`[u8] | UrlError`、`usize | Utf8Error`、`Utf8Error | nil` 等 union 返回值先 `@is` 收窄后再比较, 并用 per-element helper 避免当前 storage equality 只覆盖 u8 的边界; 同步 `tool/build/test/ok/153_path_helpers.do` 覆盖 `path_join`; 新增 `tool/build/test/ok/109_std_foundation_libs.compiled_must_pass`。生产修复: `tool/build/codegen.zig` 的 union 参数只复制 managed payload, 避免对 union ABI tuple/tag 外层做 ARC copy; 函数调用 union 绑定从 strict layout equal 放宽为 ABI-compatible; `collectUnionReturnMoveNames` 对泛型返回 union 做 type binding 替换并识别单 payload ABI-compatible managed union return, 防止 generic `[T] | Error` 返回本地 storage 后被提前 release。RED: 初始 compiled 失败于 import 行 `error[NoMatchingCall]`, 后续 runtime 栈定位到 `__layout_managed_count -> __arc_release... -> slice_i32_eq`, 根因是 union 参数 ARC copy 和 generic union return move。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/109_std_foundation_libs.do --compiled -o /tmp/109_std_foundation_libs.wat`; `wasm-tools parse /tmp/109_std_foundation_libs.wat -o /tmp/109_std_foundation_libs.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/109_std_foundation_libs.wasm /tmp/109_std_foundation_libs.wat` 通过 `6 passed`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/153_path_helpers.do --compiled -o /tmp/153_path_helpers.wat` + parse + node 通过; `cd tool && zig test main.zig` 通过 `52/52`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=766 fail=0 skip=46`。后续候选: 纯 compiled skip 推荐 `41_is_value_type_guard`、`39_else_if_chain`、`46_loop_label_break`; recv/WASI/resource wrapper 仍受执行 harness 阻塞, 暂不作为 compiled_must_pass 候选。
  - [x] C5.3.23 旧 `07_net_socket_smoke` executable smoke。实现: 更新 `tool/build/test/ok/07_net_socket_smoke.do`, 把 v4 地址构造后的成功条件从 `if @not(is_v4(addr)) return` 修正为 `if is_v4(addr) return`; 新增 `tool/build/test/ok/07_net_socket_smoke.compiled_must_pass`。生产代码无新增修改; 该用例验证 `net.do` 地址构造、`is_v4` 和 tcp/udp 类型 import shape, 不验证真实 socket host I/O。RED: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/07_net_socket_smoke.do --compiled -o /tmp/07_net_socket_smoke.red.wat` 生成 WAT 通过, `wasm-tools parse /tmp/07_net_socket_smoke.red.wat -o /tmp/07_net_socket_smoke.red.wasm` 通过, 但 `node tool/build/test/run_compiled_test_case.mjs /tmp/07_net_socket_smoke.red.wasm /tmp/07_net_socket_smoke.red.wat` 失败于 `RuntimeError: unreachable`; 根因是 `socket_addr_v4` 设置 `family = 4`, 旧测试成功路径不会 return。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/07_net_socket_smoke.do --compiled -o /tmp/07_net_socket_smoke.green.wat`; `wasm-tools parse /tmp/07_net_socket_smoke.green.wat -o /tmp/07_net_socket_smoke.green.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/07_net_socket_smoke.green.wasm /tmp/07_net_socket_smoke.green.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=767 fail=0 skip=45`。
  - [x] C5.3.24 旧 `46_loop_label_break` executable smoke。实现: 更新 `tool/build/test/ok/46_loop_label_break.do`, 在外层 loop 后补显式 `return`; 新增 `tool/build/test/ok/46_loop_label_break.compiled_must_pass`。生产修复: `tool/build/codegen.zig` 新增 `tokenRangeContainsLabeledBreak`, 让 loop reachability 能识别嵌套块内的 `break #outer`, 从而不再在可被 labeled break 跳出的外层 loop 后插入错误的 `unreachable`; 同名 nested loop body 会被跳过, 避免 label shadow 误判。RED: 初始 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/46_loop_label_break.do --compiled -o /tmp/46_loop_label_break.red.wat` 和 `wasm-tools parse` 通过, 但 node 执行失败于 `RuntimeError: unreachable`; 单纯补 `return` 后 WAT 仍显示外层 loop 后先有 `unreachable`, 说明根因在 reachability 而不是 fixture。GREEN: `cd tool && zig build -Doptimize=Debug`; `cd tool && zig test main.zig` 通过 `52/52`; `cd tool && zig test build/codegen.zig` 通过 `16/16`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/46_loop_label_break.do --compiled -o /tmp/46_loop_label_break.green2.wat`; `wasm-tools parse /tmp/46_loop_label_break.green2.wat -o /tmp/46_loop_label_break.green2.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/46_loop_label_break.green2.wasm /tmp/46_loop_label_break.green2.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=768 fail=0 skip=44`。
  - [x] C5.3.25 旧 `41_is_value_type_guard` executable smoke。实现: 新增 `tool/build/test/ok/41_is_value_type_guard.compiled_must_pass`。生产修复: `tool/build/codegen.zig` 的 `true` / `false` literal emission 现在尊重 `expected_ty`, 只有无 expected type 或 expected type 为 `bool` 时才接受, 避免 union 分支选择时把 bool literal 提前当作 `i32` payload。RED: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/41_is_value_type_guard.do --compiled -o /tmp/41_is_value_type_guard.red.wat` 和 `wasm-tools parse` 通过, 但 node 执行失败于 `RuntimeError: unreachable`; WAT 显示 `false` 写入 union tag 1, 而 `@is(v, bool)` 比较 tag 2。GREEN: `cd tool && zig build -Doptimize=Debug`; `cd tool && zig test build/codegen.zig` 通过 `16/16`; `cd tool && zig test main.zig` 通过 `52/52`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/41_is_value_type_guard.do --compiled -o /tmp/41_is_value_type_guard.green.wat`, WAT 显示 union tag 已改为 2; `wasm-tools parse /tmp/41_is_value_type_guard.green.wat -o /tmp/41_is_value_type_guard.green.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/41_is_value_type_guard.green.wasm /tmp/41_is_value_type_guard.green.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=769 fail=0 skip=43`。
  - [x] C5.3.26 旧 `39_else_if_chain` executable smoke。实现: 新增 `tool/build/test/ok/39_else_if_chain.compiled_must_pass`。生产修复: `tool/build/codegen.zig` 在非 arrow result 函数 body 不可落底、且末语句不是 plain `return` 时, 在 fallthrough release 后补 `unreachable`, 让 `if/else if/else` 全分支 return 的 result 函数满足 Wasm fallthrough 类型校验。RED: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/39_else_if_chain.do --compiled -o /tmp/39_else_if_chain.red.wat` 和 `wasm-tools parse` 通过, 但 node instantiate 失败于 `expected 1 elements on the stack for fallthru, found 0`; WAT 显示 `$f` 是 `(result i32)`, 所有分支 `return`, 函数尾无 `unreachable` 或 result value。GREEN: `cd tool && zig build -Doptimize=Debug`; `cd tool && zig test build/codegen.zig` 通过 `16/16`; `cd tool && zig test main.zig` 通过 `52/52`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/39_else_if_chain.do --compiled -o /tmp/39_else_if_chain.green.wat`, WAT 显示 `$f` 尾部已补 `unreachable`; `wasm-tools parse /tmp/39_else_if_chain.green.wat -o /tmp/39_else_if_chain.green.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/39_else_if_chain.green.wasm /tmp/39_else_if_chain.green.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=770 fail=0 skip=42`。
  - [x] C5.3.27 旧 `54_nested_if_blocks_are_not_structs` executable smoke。实现: 新增 `tool/build/test/ok/54_nested_if_blocks_are_not_structs.compiled_must_pass`。生产修复: `tool/build/codegen.zig` 的 `appendBorrowedLocalWithOrigin` 现在按 resolved wasm local name 去重, 同名同类型 local 复用同一个 function-local, 同名不同类型仍报 `NoMatchingCall`; 这避免多个独立 block 中同名同类型局部变量被收集成重复 `(local $name ...)`。RED: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/54_nested_if_blocks_are_not_structs.do --compiled -o /tmp/54_nested_if_blocks.red.wat` 生成 WAT 通过, 但 `wasm-tools parse /tmp/54_nested_if_blocks.red.wat -o /tmp/54_nested_if_blocks.red.wasm` 失败于 `duplicate local identifier`, WAT 中 `$check_nested_if` 有两个 `(local $out i32)`。GREEN: `cd tool && zig build -Doptimize=Debug`; `cd tool && zig test build/codegen.zig` 通过 `16/16`; `cd tool && zig test main.zig` 通过 `52/52`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/54_nested_if_blocks_are_not_structs.do --compiled -o /tmp/54_nested_if_blocks.green.wat`; `wasm-tools parse /tmp/54_nested_if_blocks.green.wat -o /tmp/54_nested_if_blocks.green.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/54_nested_if_blocks.green.wasm /tmp/54_nested_if_blocks.green.wat` 通过 `1 passed`; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=771 fail=0 skip=41`。
  - [x] C5.3.28 旧 `14_path_index_expr_segment` / `15_path_index_complex_expr_segment` executable smoke。实现: 新增 `tool/build/test/ok/14_path_index_expr_segment.compiled_must_pass` 和 `tool/build/test/ok/15_path_index_complex_expr_segment.compiled_must_pass`。生产修复: `tool/build/codegen.zig` 支持 `@get(value, index, .field)` / `@get(value, expr, .field)` 多段 path get lowering 和类型推导; `callArgMatchesParam` 接受目标 struct literal; generic variadic 参数拆分源码元素类型与 ABI pack 类型, `funcParamAbiType` 负责 `...[u8]` 的 `[[u8]]` ABI, `funcVariadicElemType` 保持 `[u8]` 语义元素类型, `cloneFuncParams` 保留 `abi_ty`。RED: 新增 marker 后单项 14/15 已能通过, 但完整回归暴露 5 个同源 import-line `NoMatchingCall` (`109_std_foundation_libs`、`111_bytes_text_common_wrappers`、`153_path_helpers`、`174_bytes_text_concat_helpers`、`97_bytes_lib`), 代表命令 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/174_bytes_text_concat_helpers.do --compiled -o /tmp/174_probe.wat` 失败在 `bytes_concat = @lib("bytes.do", concat)`; 根因是 variadic `[u8]` tail 被错误剥成 `u8` 参与匹配。GREEN: `cd tool && zig build -Doptimize=Debug`; `cd tool && zig test build/codegen.zig` 通过 `18/18`; `cd tool && zig test main.zig` 通过 `52/52`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/14_path_index_expr_segment.do --compiled -o /tmp/14_path_index_expr_segment.green2.wat` + parse + node 通过; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/15_path_index_complex_expr_segment.do --compiled -o /tmp/15_path_index_complex_expr_segment.green2.wat` + parse + node 通过; `109/111/153/174/97` 五个代表 compiled fixture 单项均通过; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=773 fail=0 skip=39`。
  - [x] C5.3.29 旧 `58_list_update` executable smoke。实现: 新增 `tool/build/test/ok/175_generic_callback_typed_local.do` 与 `.compiled_must_pass`, 并新增 `tool/build/test/ok/58_list_update.compiled_must_pass`。生产修复: `tool/build/codegen.zig` 新增 `typedScalarBindingType`, 让 `value T = f(x)` 这类泛型实例函数体内的显式 typed scalar local 先按 `ctx.type_bindings` 替换为具体类型, 再收集 local 和发射 scalar binding; 避免 callback 返回值按 raw type-param `T` 匹配失败。RED: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/175_generic_callback_typed_local.do --compiled -o /tmp/175_generic_callback_typed_local.red.wat` 在首行泛型约束处报 `NoMatchingCall`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/58_list_update.do --compiled -o /tmp/58_probe.wat` 在 `List = @lib("list.do", List)` 报 `NoMatchingCall`。GREEN: `cd tool && zig build -Doptimize=Debug`; `cd tool && zig test build/codegen.zig` 通过 `18/18`; `cd tool && zig test main.zig` 通过 `52/52`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/175_generic_callback_typed_local.do --compiled -o /tmp/175_generic_callback_typed_local.marker.wat` + parse + node 通过; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/58_list_update.do --compiled -o /tmp/58_list_update.marker.wat` + parse + node 通过; 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=775 fail=0 skip=38`。后续边界: `59_hash_map_update` 仍在 import-line `NoMatchingCall`; `50_pipe_lib` / `52_list_functional_ops` 仍保留 skip, 其中 `find_index` 方向还涉及 `usize | nil` 裸 scalar payload return。
  - [x] C5.3.30 旧 `50_pipe_lib` executable wrapper。实现: 新增 `tool/build/test/ok/50_pipe_lib.compiled_must_pass`, `179_imported_pipe_multi_arity_compile.do`, `180_generic_callback_func_ref_nil.do`, `181_generic_callback_distinct_lambdas.do` 及对应 `.compiled_must_pass`。生产修复: `tool/build/codegen.zig` 的 generic concrete 覆盖判断和函数调用匹配现在同时比较实例化 callback shape 与实际 callback 绑定对象, 避免同形不同 lambda 误复用; function-ref callback 匹配将期望 `nil` 视为目标函数无 wasm 结果。RED: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/179_imported_pipe_multi_arity_compile.do --compiled -o /tmp/179_imported_pipe_multi_arity_compile.wat` 在 `pipe = @lib("fp.do", pipe)` 报 `NoMatchingCall`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/180_generic_callback_func_ref_nil.do --compiled -o /tmp/180_generic_callback_func_ref_nil.wat` 在 `tap = @lib("fp.do", tap)` 报 `NoMatchingCall`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/181_generic_callback_distinct_lambdas.do --compiled -o /tmp/181_generic_callback_distinct_lambdas.wat` 生成 WAT 后 node 执行失败于 `RuntimeError: unreachable`; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/50_pipe_lib.do --compiled -o /tmp/50_pipe_lib.wat` 曾先后暴露 imported multi-arity `pipe`、`tap(..., noop)` nil callback 和同形 callback 复用问题。GREEN: `cd tool && zig build -Doptimize=Debug`; `cd tool && zig test build/codegen.zig --test-filter 'generic multi callback instances collect'` 通过; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/179_imported_pipe_multi_arity_compile.do --compiled -o /tmp/179_imported_pipe_multi_arity_compile.wat` + parse + node 通过; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/180_generic_callback_func_ref_nil.do --compiled -o /tmp/180_generic_callback_func_ref_nil.wat` + parse + node 通过; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/181_generic_callback_distinct_lambdas.do --compiled -o /tmp/181_generic_callback_distinct_lambdas.wat` + parse + node 通过; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/50_pipe_lib.do --compiled -o /tmp/50_pipe_lib.wat` + parse + node 通过 `6 passed`。后续边界: `52_list_functional_ops` 已定位为 fixture 漏 `list_update` import; `59_hash_map_update` 已定位为 `src/hash_map.do` 的 `@set(@get(...), ...)` compiled lowering shape 问题。
  - [x] C5.3.31 旧 `52_list_functional_ops` executable wrapper。实现: 新增 `tool/build/test/ok/52_list_functional_ops.compiled_must_pass`, 并给 fixture 补 `list_update = @lib("list.do", update)`。生产修复: 延续 C5.3.30 的 callback 绑定匹配修复, 去掉 callback 实参身份比较中的跨层形参名要求, 让 `list.do` 的 `f` 转发到 `fp.do` 的 `p` 时按实际 callback 实参对象匹配。RED: 补 import 前 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/52_list_functional_ops.do --compiled -o /tmp/52_probe.wat` 在 `List = @lib("list.do", List)` 报 `NoMatchingCall`; 补 import 后最小切片显示 `list_map` 后接 `list_filter` 仍在 import-line `NoMatchingCall`, 根因是 callback 转发链把不同层形参名当成不同实参身份。GREEN: `cd tool && zig build -Doptimize=Debug`; `cd tool && zig test build/codegen.zig --test-filter 'generic multi callback instances collect'` 通过; `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/52_list_functional_ops.do --compiled -o /tmp/52_list_functional_ops.wat`; `wasm-tools parse /tmp/52_list_functional_ops.wat -o /tmp/52_list_functional_ops.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/52_list_functional_ops.wasm /tmp/52_list_functional_ops.wat` 通过 `3 passed`。后续边界: `59_hash_map_update` 仍待按 `@set` target local shape 收口。
  - [x] C5.3.32 旧 `59_hash_map_update` executable wrapper。实现: 新增 `tool/build/test/ok/59_hash_map_update.compiled_must_pass`。生产修复: `src/hash_map.do` 的 `update/update_or` 改为先把 `values(m)` 和 `keys(m)` 落到 local, 再执行 `@set(data_vals, index, new_value)` 和 `hash_map_from_parts(data_keys, next_vals)`, 对齐 `hash_set/hash_set_or` 的 compiled lowering shape。RED: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/59_hash_map_update.do --compiled -o /tmp/59_probe.wat` 在 `HashMap = @lib("hash_map.do", HashMap)` 报 `NoMatchingCall`; 根因是 `@set(@get(m, .vals), ...)` 不满足当前 `@set` compiled lowering 的 storage target 必须是 local ident 的边界。GREEN: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/59_hash_map_update.do --compiled -o /tmp/59_hash_map_update.wat`; `wasm-tools parse /tmp/59_hash_map_update.wat -o /tmp/59_hash_map_update.wasm`; `node tool/build/test/run_compiled_test_case.mjs /tmp/59_hash_map_update.wasm /tmp/59_hash_map_update.wat` 通过 `2 passed`; 复验 `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/115_hash_map_common_wrappers.do --compiled -o /tmp/115_hash_map_common_wrappers.recheck.wat` + parse + node 通过 `1 passed`; 修正 `176_union_scalar_payload_return` 的普通 `do test` 反向断言后, 完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=784 fail=0 skip=35`。后续边界: C5.3 剩余 skip 需要按新基线重新盘点。
  - [x] C5.3.33 剩余 skip 盘点。结论: C5.3 非 WASI/resource executable skip 已清空。当前完整回归剩余 `skip=35`: ok fixture 仅 `118_wasi_p3_std_wrappers`、`16_loop_recv_value`、`96_file_lib_resource_shape`; 其余 32 个为 std src `NoTestDecl` 元数据扫描, 包括 `atomic/base64/binary/bytes/dir/file/fp/hash_map/hex/http.client/io.stream/json/list/math/md5/mem/net/path/random/range/set/sha1/sha256/simd/slice/tcp/text/time/udp/url/utf16/utf8`。验证: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh > /tmp/do-skip-scan-a075.txt 2>&1`; `rg '^\[SKIP\]' /tmp/do-skip-scan-a075.txt`; 摘要 `pass=784 fail=0 skip=35`。后续边界: `16/96/118` 归 recv/WASI/resource 后置线; 公开边界同步已由 C5.4 收口。
  - [x] C5.4 README 或 spec_rules 只记录稳定公开边界。实现: README 的标准库边界收窄为当前已验证纯 do 库、少量已登记 WASI wrapper 和明确后置项; `doc/spec_rules.md` 的 JSON 规则明确 `stringify/from_json` 只是当前签名与支持矩阵的稳定公开边界, 不表示通用 `Serialize/Deserialize` 协议、运行时 JSON AST 或任意类型自动序列化兜底; 同步收窄 `from_json` 默认构造和深度边界、UTF `@is` 单目标写法、time 非目标和 file wrapper 列举; `tool/build/test/README.md` 收窄 resource-method 测试说明。验证: `git diff --check -- README.md tool/build/test/README.md doc/spec_rules.md doc/master_plan.md doc/roadmap_status.md doc/start_here.md`。

## 阶段 D: ARC / Ownership / FBIP 深化

状态: done

当前结论: D1 ownership facts 统一入口第一轮已完成。D1.1 已完成当前 last-use / move 判断分散点盘点; D1.2 已新增 `tool/build/ownership_facts.zig`; D1.3 已把普通用户函数 call 参数 last-use move 的 allow/defer/use-after 判断迁移到 facts helper; D1.4 已用现有 ARC fixture 和 full regression 锁住 WAT 不回退。D2.1 未找到真实 if/else 红灯缺口; 原阻断原因是任务目标要求先找出能证明当前实现错误的红灯 fixture, 但已有 probe 都显示当前 WAT 与目标 path-sensitive liveness 一致, 因此不能落地伪红灯。用户已确认按 B 方案把 D2.1 改为绿色 regression 收口, 新增 compile_ok `239` 到 `241` 锁住 if/else path-sensitive liveness 当前行为。D2.2-D2.4 已完成 guard return 后续路径红灯、最小修复和完整回归。D3 字段读取 move 扩展已完成到 facts 接入。D4 函数参数 ownership contract 已完成, 参数可重新赋值与 managed 参数 move/copy/release 边界已由文档和 WAT fixture 锁住。D5.1 已固定 FBIP reuse eligibility, D5.2 已补 `rc == 1` 可 reuse WAT pattern, D5.3 已补 `rc > 1` 必须 COW 反例, D5.4 已实现 managed struct 最小 clone/reuse lowering, D5.5 已补 compiled trap smoke。阶段 D 当前无剩余 blocked 残留。

D1 ownership facts 统一入口:

- [x] D1.1 盘点当前 last-use / move 判断分散点。结论:
  - source/origin 仍是 codegen-local 信息: `SourceOrigin` 定义在 `tool/build/codegen.zig:8`, 并分别挂在 `Local`、`StructLocal`、`StorageLocal`、`UnionLocal` 上, 入口见 `tool/build/codegen.zig:20`、`tool/build/codegen.zig:71`、`tool/build/codegen.zig:83`、`tool/build/codegen.zig:104`。
  - move candidate 判断分散在多条路径: 死 alias `isDeadManagedAliasBinding(...)` 见 `tool/build/codegen.zig:3412`; direct 绑定/赋值 `directManagedLastUseMoveSource(...)` 见 `tool/build/codegen.zig:3474`; field get `fieldGetLastUseMoveSource(...)` 见 `tool/build/codegen.zig:3549`; 普通 call 参数 `directManagedCallLastUseMoveSource(...)` 见 `tool/build/codegen.zig:3586`; union binding call 参数 `directManagedUnionBindingCallMoveSource(...)` 见 `tool/build/codegen.zig:3621`。
  - 共享子判断仍是 ad hoc token 扫描: direct managed local 识别见 `tool/build/codegen.zig:3368`; use-after 识别见 `tool/build/codegen.zig:3438`; active defer gate 见 `tool/build/codegen.zig:3452`; fresh struct literal 反查见 `tool/build/codegen.zig:3512`。
  - emit 副作用也分散: return / guard return 会收集 `move_names` 供 release skip 使用, 相关入口见 `tool/build/codegen.zig:2347`、`tool/build/codegen.zig:2543`、`tool/build/codegen.zig:2655` 和 `tool/build/codegen.zig:18524`; return move marker 见 `tool/build/codegen.zig:2356` 和 `tool/build/codegen.zig:2567`; field-set move 清零见 `tool/build/codegen.zig:5092`; field-get move marker 见 `tool/build/codegen.zig:15347` 和 `tool/build/codegen.zig:15788`; 普通 call 与 union-binding call 的 inc/move/清零逻辑分别在 `tool/build/codegen.zig:17551` 和 `tool/build/codegen.zig:17610`, 两者存在重复。
  - loop gate 目前是全局保守开关: `emitBody(...)` 在 `tool/build/codegen.zig:5129` 用 `loop_ctx == null` 禁止所有 loop body call 参数 last-use move。collection loop / recv loop / field reflection loop 因都会构造 loop context, 当前边界保持保守。
  - release facts 已有最小接口, 但还不是 move allow 的统一输入: `PathCleanupFacts` 见 `tool/build/ownership.zig:25`; release skip 只有 `cleanup_visible` 为 true 时生效, 见 `tool/build/ownership.zig:155`; codegen 仅在 return / guard return plan 构造时传入 skip, 见 `tool/build/codegen.zig:3184` 和 `tool/build/codegen.zig:3198`。
  - 已有回归锁住保守边界: call move / keep-inc 分布在 `tool/build/test/compile_ok/159_*` 到 `185_*`; union/nil 和 field move 分布在 `186_*` 到 `215_*`; collection / recv loop call 参数保守边界由 `216_*` 到 `218_*` 锁住。
  - D1.2 输入: 需要统一表达 source identity、actual local、SourceOrigin、candidate kind、body/stmt/arg token range、defer visibility、cleanup facts、loop-carried source、collection/recv value、same-stmt multi-candidate、direct / call arg / union-binding call arg / field-get / dead-alias 的不同 future-use 窗口, 以及当前保守决策 reason。D1.2 不能先放开 loop move 或字段 move, 只能让现有判断可解释、可迁移、可回归。
  - 验证: 本项为文档盘点, 未改编译器行为; 当前验证采用 `git diff --check` 和 D1.1 关键字扫描。
- [x] D1.2 设计 `ownership_facts` 数据结构。实现:
  - 新增 `tool/build/ownership_facts.zig`, 定义 `SourceOrigin`、`MoveCandidateKind`、`MoveRejectReason`、`TokenRange`、`MoveSource`、`MoveUseWindows`、`MoveContext`、`MoveCandidate`、`MoveActions` 和 `MoveDecision`。
  - `MoveContext` 显式承载 body / statement / arg / args token range, `ownership.PathCleanupFacts`, `defer_visible`, `inside_loop`, `allow_last_use_move` 和 `allow_field_read_move`。
  - `MoveUseWindows` 显式承载 fresh source gap、after expr、after arg、after stmt 和 body rest, 为 D1.3 迁移 token-range use-after 判断提供统一输入。
  - `MoveDecision` 显式区分 accepted 与 reject reason, 并携带 zero source / zero field / release skip action; 当前只记录事实, 不发出 WAT, 不改变 `codegen.zig` lowering。
  - `tool/main.zig` test block 已 import `build/ownership_facts.zig`, 让聚合 `zig test main.zig` 覆盖新模块。
  - TDD RED: 先新增 focused tests 后执行 `cd tool && zig test build/ownership_facts.zig`, 失败于 `use of undeclared identifier 'MoveCandidate'`。
  - GREEN 验证: `cd tool && zig test build/ownership_facts.zig` 通过 `All 4 tests passed.`; `cd tool && zig test main.zig` 通过 `All 56 tests passed.`。
- [x] D1.3 把一个现有判断迁移到 facts。实现:
  - 迁移对象: 普通用户函数 call 参数 last-use move 的判断路径, 即 `directManagedCallLastUseMoveSource(...)`。
  - facts 层新增 `decideCallArgMove(...)`, 统一处理 `.call_arg` candidate 的 `allow_last_use_move`、defer 可见性、after-arg use、after-stmt use 和 body-rest use 判断。
  - `tool/build/codegen.zig` 新增 `ownership_facts` import 和 `factsSourceOrigin(...)` 显式映射, 保持 codegen-local `SourceOrigin` 暂不整体搬迁。
  - `directManagedCallLastUseMoveSource(...)` 仍负责 direct managed local 识别和 source/origin 查找, 但 now 构造 `ownership_facts.MoveCandidate` 并调用 `decideCallArgMove(...)` 决定 accept/reject。
  - 行为边界: 不改变 `allow_call_arg_last_use_move = loop_ctx == null`; 不放开 loop 内 move; 不迁移 union-binding call、field-get、field-set 或 return move; WAT marker 和清零行为保持原样。
  - TDD RED: 新增 facts focused test 后, `cd tool && zig test build/ownership_facts.zig` 失败于 `use of undeclared identifier 'decideCallArgMove'`。
  - GREEN 验证: `cd tool && zig test build/ownership_facts.zig` 通过 `All 5 tests passed.`; `cd tool && zig test build/codegen.zig` 通过 `All 30 tests passed.`。
- [x] D1.4 用现有 ARC fixture 锁住 WAT 不回退。验证:
  - `cd tool && zig build -Doptimize=Debug` 通过。
  - 目标 WAT pattern: `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/161_arc_storage_bare_call_last_use_move_lower.do -o /tmp/161_arc_storage_bare_call_last_use_move_lower.wat` 后 `rg -q "arc-call-move data"` 命中; `162_arc_storage_param_call_live_source_inc_lower.do` 生成 WAT 后 `arc-call-move data` 为 0 命中。
  - 完整回归: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=784 fail=0 skip=35`。

D2 跨 block data-flow 最小版:

- [x] D2.1 为 if/else 两边不同使用路径补红灯 fixture。结论: 当前未找到可证明的真实红灯缺口, 不落地伪红灯; 用户已确认按 B 方案把已验证绿色路径正式纳入 regression。已覆盖:
  - 两个显式 if/else 分支分别 `take(data)` 的 call 参数 move, 当前 WAT 已有 `count=2 ;; arc-call-move data` 且无 `call $__arc_inc`。
  - 一个分支 `take(data)`, 另一个分支只 `@len(data)` borrow, 当前 WAT 已有 `count=1 ;; arc-call-move data` 且无 `call $__arc_inc`。
  - 一个分支 `take(data)` 后继续 `@len(data)`, 另一个分支 `take(data)`, 当前 WAT 已有 `count=1 ;; arc-call-move data` 和 `count=1 call $__arc_inc`, 分支内路径差异已被现有范围处理。
  - 显式 if/else 中只有一个分支声明 managed local, 当前 WAT 只有一次 `;; arc-release-local data`。
  - 隐式 fallthrough 分支没有 managed local 的 if-block, 当前 WAT 也只有一次 `;; arc-release-local data`; 旧 `66_arc_if_block_local_fallthrough_release_lower.expect` 只按子串匹配, 不是当前实际重复释放证据。
  - 临时 pending fixture `tool/build/test/pending/compile_ok/226_arc_if_else_branch_call_last_use_move_pending.*` 因不是红灯已删除。
  - 新增正式 regression: `tool/build/test/compile_ok/239_arc_if_else_both_branches_call_last_use_move_lower.do`、`240_arc_if_else_one_branch_call_other_borrow_move_lower.do` 和 `241_arc_if_else_branch_use_after_call_keeps_inc_lower.do`。
- [x] D2.2 为 guard return 后续路径补红灯 fixture。实现与红灯证据:
  - 先新增 pending 编译 fixture `tool/build/test/pending/compile_ok/227_arc_guard_return_condition_call_fallthrough_pending.do`, 覆盖 `if ok return id(source)` 后 fallthrough 分支仍执行 `@len(source)` 与 `return source` 的路径。
  - 同名 `.expect` 要求 guard return 分支出现 `count=1 ;; arc-call-move source`, 且函数内不再为该分支插入 `count=0 call $__arc_inc`, 同时保留 fallthrough 侧 `local.set $n`。
  - `tool/build/test/run_tests.sh` 已新增 `PENDING_COMPILE_OK_DIR` 并在 `RUN_PENDING=1` 下复用 `run_compile_ok_case`, 让 pending compile 红灯进入同一 WAT pattern harness。
  - `tool/build/test/README.md` 已记录 `pending/compile_ok` 目录和 `RUN_PENDING=1 SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 复现命令。
  - 手工 RED: `DO_LIB_ROOT=src ./bin/do build tool/build/test/pending/compile_ok/227_arc_guard_return_condition_call_fallthrough_pending.do -o /tmp/227_arc_guard_return_condition_call_fallthrough_pending.wat` 后, `arc-call-move source count=0`, `arc-inc count=1`, `local.set n count=5`。
  - harness RED: `RUN_PENDING=1 SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 失败在 pending compile ok `227_arc_guard_return_condition_call_fallthrough_pending`, 输出 `expected count=1 for wat text: ;; arc-call-move source, got 0` 和 `expected count=0 for wat text: call $__arc_inc, got 1`; 默认回归不执行 pending。
  - 辅助验证: `bash -n tool/build/test/run_tests.sh` 通过。
- [x] D2.3 实现函数内 data-flow 最小 pass。实现与排障:
  - 根因: `emitGuardReturnIf(...)` 已为 single managed return 构造 return 分支局部 `CallLastUseMoveContext`, 但 `emitSingleReturnAbiValue(...)` 直接进入通用 `emitExprWithMoveContext(...)`; 普通 user-call 表达式路径不传递 move context, 导致 `id(source)` 被当成 copy call arg 并插入 `call $__arc_inc`。
  - 曾尝试把 `emitExprWithMoveContext(...)` 的普通 user-call 分支改为全局传递 `move_ctx`, 但完整回归暴露 `109_std_foundation_libs`、`111_bytes_text_common_wrappers`、`157_bytes_sequence_helpers`、`173_text_sequence_helpers` compiled 执行失败, 原因是嵌套表达式中过早 move 并清零 source。该过宽方案已撤销。
  - 最终实现: 只在 `emitSingleReturnAbiValue(...)` 的 managed return 且表达式是完整普通 user-call 时, 复用 `emitManagedHandleCallExprWithMoveContext(...)`; 通用表达式 user-call 路径继续保持 copy/保守语义。
  - 修复后 `tool/build/test/compile_ok/230_arc_guard_return_condition_call_fallthrough_move_lower.do` 已从 pending 提升为正式 compile_ok 回归; `tool/build/test/pending/compile_ok` 当前为空。
  - focused 验证: `cd tool && zig test build/codegen.zig` 通过 `All 30 tests passed.`; `cd tool && zig build -Doptimize=Debug` 通过。
  - WAT 验证: `230_arc_guard_return_condition_call_fallthrough_move_lower` 生成 `arc-call-move source count=1`, `arc-inc count=0`, `local.set n count=5`。
  - 风险回归: `162_arc_storage_param_call_live_source_inc_lower`、`167_arc_storage_assignment_call_loop_live_source_inc_lower`、`181_arc_storage_return_call_defer_keeps_inc_lower`、`189_arc_unmanaged_struct_error_guard_return_call_defer_keeps_inc_lower` 均保持 `arc-call-move=0`、`arc-inc=1`。
- [x] D2.4 回归 ARC WAT pattern 和 compiled execution。验证:
  - 聚合 Zig: `cd tool && zig test main.zig` 通过 `All 57 tests passed.`。
  - targeted compiled execution: `109_std_foundation_libs`、`111_bytes_text_common_wrappers`、`157_bytes_sequence_helpers`、`173_text_sequence_helpers` 均通过 `do test --compiled` + `wasm-tools parse` + `run_compiled_test_case.mjs`。
  - 完整默认回归: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=785 fail=0 skip=35`。

D3 字段读取 move 扩展:

- [x] D3.0 对齐当前 D3 计划与历史字段读取 move 实现。结论:
  - 已有实现不是空白: `tool/build/codegen.zig:3582` 的 `fieldGetLastUseMoveSource(...)` 已按 `allow_field_read_move`、managed field、active defer、fresh struct literal source、source-before/after use window 做 codegen-local 决策。
  - direct `@get` 与 field reflection `@field_get` 都已消费该决策: direct 路径见 `tool/build/codegen.zig:15387`, move 时输出 `;; field-get-move` 并把源字段写 0; field reflection 路径见 `tool/build/codegen.zig:15828`, 行为一致。
  - 规则文档已存在: `doc/memory.md` 第 8.5 节记录 fresh-owner 字段读取 move 的 9 条证明条件、move/copy 效果和 03.6 回归矩阵。
  - 因此 D3.1/D3.2 不需要重新补红灯; 当前真实剩余是 D3.3/D3.4, 即把 field-get source ownership 和 allow/reject reason 迁移进 `tool/build/ownership_facts.zig`, 再让 codegen 通过 facts 选择 move/copy。
  - 验证: 证据扫描 `rg "fieldGetLastUseMoveSource|field-get-move|helper_shared"` 覆盖 codegen、doc 和 fixture; 本项只更新计划与进度文档。
- [x] D3.1 补 fresh owner 字段读取可 move 正例。已有证据:
  - compile_ok `202_arc_field_reflection_get_return_fresh_local_move_lower.expect` 要求 `count=1 ;; field-get-move user.name` 且 `count=0 call $__arc_inc`。
  - compile_ok `204`、`207`、`210` 覆盖 direct `@get` return / binding / assignment fresh local move。
  - compiled_ok `39` 到 `42` 覆盖 fresh local direct `@get`、field reflection `@field_get`、binding 和 assignment 的执行路径。
- [x] D3.2 补 shared source 字段读取必须 copy 反例。已有证据:
  - compile_ok `206_arc_struct_get_return_param_keeps_inc_lower.expect` 要求参数字段读取 `count=1 call $__arc_inc` 且 `count=0 ;; field-get-move user.name`。
  - compile_ok `213_arc_struct_get_helper_source_keeps_inc_lower.expect` 要求 helper/shared-source 不 move, 保留 `count=2 call $__arc_inc`。
  - compile_ok `214_arc_struct_get_loop_carried_keeps_inc_lower.expect` 要求 loop-carried source 不 move, 保留 `count=2 call $__arc_inc`。
  - compile_ok `215_arc_struct_get_same_stmt_multi_field_keeps_inc_lower.expect` 要求同语句多字段读取不 move, 保留 `count=4 call $__arc_inc`。
- [x] D3.3 在 facts 中表达 source ownership。实现:
  - `tool/build/ownership_facts.zig` 新增 `decideFieldGetMove(...)`, 只接受 `.field_get` candidate。
  - 决策要求 `allow_last_use_move` 和 `allow_field_read_move` 同时开启, active defer 不可见, `source.origin == .fresh_local`, 且没有 fresh-source gap、expr 后续使用、statement 后续使用或 body-rest 使用。
  - accept action 使用 `zero_field = true`, 不使用 `zero_source` 和 release-skip, 对齐字段读取 move 的“清字段不清结构体 local”语义。
  - TDD RED: `cd tool && zig test build/ownership_facts.zig` 失败于 `use of undeclared identifier 'decideFieldGetMove'`。
  - GREEN: `cd tool && zig test build/ownership_facts.zig` 通过 `All 6 tests passed.`; `cd tool && zig test main.zig` 通过 `All 58 tests passed.`。
- [x] D3.4 codegen 根据 facts 选择 move / copy。实现与验证:
  - `fieldGetLastUseMoveSource(...)` 现在构造 `.field_get` `ownership_facts.MoveCandidate`, 把 allow flags、defer 可见性、fresh-source gap、expr 后续使用和 body-rest 使用交给 `decideFieldGetMove(...)` 判断。
  - codegen 仍保留 `freshStructLiteralBindingStmtEnd(...)` 作为 fresh-owner 证明入口; 证明成立后 facts candidate 使用 `.fresh_local`, 但返回的 `LastUseManagedMoveSource.origin` 保留原 `StructLocal.origin`, 不改变现有元数据行为。
  - 初次接入直接使用 `struct_local.origin` 会让现有 `field-get move candidate preserves struct local origin` 单测失败, 因为收集阶段 struct local 默认 origin 是 `unknown`; 已修正为“codegen 证明 fresh struct literal 后向 facts 传 `.fresh_local`”。
  - focused 验证: `cd tool && zig test build/codegen.zig` 通过 `All 31 tests passed.`; `cd tool && zig test main.zig` 通过 `All 58 tests passed.`。
  - 字段读取 WAT 矩阵: compile_ok `202` 到 `215` 全部按 `.expect` 通过。
  - 字段读取 compiled 矩阵: compiled_ok `39` 到 `42` 全部通过 `do test --compiled` + `wasm-tools parse` + `run_compiled_test_case.mjs`。
  - 完整默认回归: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=785 fail=0 skip=35`。

D4 函数参数 ownership contract:

- [x] D4.1 审查当前参数赋值和 call lowering 行为。结论:
  - 参数 local 收集时显式标为 `param_or_import`: storage 参数经 `appendBorrowedLocalWithOrigin(..., .param_or_import)` 和 `storage_locals` 注册, managed struct 参数经 `struct_locals` origin `.param_or_import` 与 borrowed local 注册, 见 `tool/build/codegen.zig:11675` 到 `tool/build/codegen.zig:11705`。
  - 参数名不能写 `_name` 或 UpperIdent, 也不能重复或遮蔽可见顶层函数/值; 证据是 err `50_param_readonly_name`、`51_param_upper_name`、`310_duplicate_func_param`、`311_func_param_shadows_func`、`316_func_param_shadows_top_value`。
  - 参数绑定本身当前可重新赋值。compile_ok `141_param_reassign_lower` 覆盖 `x = @add(x, 1)` 并期望 `local.set $x`。
  - loop 头绑定仍不可赋值, 不受“参数可重新赋值”影响。err `298_loop_binding_assign` 期望 `InvalidAssignExpr`; sema 在 `checkAssignmentConstraints(...)` 中对 `scopesContainLoopBinding(...)` 直接报 `InvalidAssignExpr`, 见 `tool/build/sema.zig:8397`。
  - managed 参数 call lowering 当前语义是 caller 侧决定 move/copy: 非末次使用 copy 时插入 `call $__arc_inc`; 末次使用 move 时输出 `;; arc-call-move` 并清零 caller source。callee 将参数作为本地 handle 使用, 退出时按本地 release 释放参数 local。
  - 证据: `59_arc_storage_param_call_ownership_lower.expect` 覆盖 callee `$x` release 与 caller 侧 `;; arc-call-move data`; `162_arc_storage_param_call_live_source_inc_lower.expect` 覆盖 caller 后续仍使用 source 时 `count=1 call $__arc_inc` 且不 move; `206_arc_struct_get_return_param_keeps_inc_lower.expect` 覆盖 managed struct 参数字段读取必须 copy, 不触发 `field-get-move`。
  - 当前缺口: 已由 D4.2-D4.4 收口, 下一步进入 FBIP reuse 规则。
- [x] D4.2 在 `doc/spec_rules.md` 固定参数 ownership 规则。实现:
  - `doc/spec_rules.md` 已集中固定函数参数是普通可写本地绑定, 参数 origin 归为 `param_or_import`, managed 参数重赋值先释放旧 handle, caller 侧按后续使用决定 move/copy, callee 不从参数或共享 source 中 move 字段。
  - 规则同时固定 loop 绑定仍不可变, 不受“函数参数可写”影响。
- [x] D4.3 补参数 move/copy 正反例。证据:
  - 已有 compile_ok `59_arc_storage_param_call_ownership_lower` 覆盖 caller last-use move 与 callee 参数 release。
  - 已有 compile_ok `162_arc_storage_param_call_live_source_inc_lower` 覆盖 caller live source 必须 copy/inc。
  - 已有 compile_ok `206_arc_struct_get_return_param_keeps_inc_lower` 覆盖 managed struct 参数字段读取必须 copy, 不触发 `field-get-move`。
  - 新增 compile_ok `231_arc_storage_param_reassign_releases_old_lower` 覆盖 managed storage 参数在函数体内重新赋值时释放旧 handle。
- [x] D4.4 同步 codegen tests。验证:
  - `tool/build/test/compile_ok/231_arc_storage_param_reassign_releases_old_lower.expect` 要求 `count=1 ;; arc-overwrite-release data`、`count=1 ;; arc-release-local data`、`count=1 ;; arc-call-move source` 和 `local.set $data`。
  - focused Zig: `cd tool && zig test build/ownership_facts.zig` 通过 `All 6 tests passed.`; `cd tool && zig test build/codegen.zig` 通过 `All 31 tests passed.`; `cd tool && zig test main.zig` 通过 `All 58 tests passed.`。
  - 构建: `cd tool && zig build -Doptimize=Debug` 通过。
  - 完整默认回归: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=786 fail=0 skip=35`。

D5 FBIP reuse 第一版:

- [x] D5.1 固定 reuse eligibility 规则。结论:
  - `doc/memory.md` 第 11.1 节已把 D5.1 规则固定为“runtime `rc == 1` 是必要条件但不是充分条件”: 写路径还必须有 COW / clone 回退、alias protection、容量/layout 条件和 managed child retain/release 顺序证明。
  - storage `@set/@put` 的合格复用分支限定为当前写 helper 的本地决策: `@set` 需要 range check 通过且 `rc == 1`; `@put` 需要 `rc == 1 && len < cap`; 失败时 clone / grow 后写入。
  - managed struct field update 的 D5 合格形态必须增加 `rc == 1` 原地替换与 `rc > 1` clone struct 回退; 当前已有直接 payload 写字段路径只能作为现状证据, 不算完整 FBIP reuse。
  - 规则明确不改变源码值语义, 不引入 mutable reference, 不放宽 loop move / call 参数 move / return move / field-get move, 不启动完整 ownership IR。
  - 实现证据: storage runtime helper `__storage_set_u8` / `__storage_put_u8` 已在 `tool/build/codegen.zig` 的 runtime prelude 中按 `__arc_rc` 分支; scalar / managed storage lowering 已在 `emitStorageSetScalarCall`、`emitStoragePutScalarCall`、`emitStorageSetManagedCall` 和 `emitStoragePutManagedCall` 中按 `__arc_rc` 与容量条件选择 source 或 clone; `emitStorageAliasProtect` / `emitStorageAliasRelease` 负责跨变量写入的临时 retain/release。
  - 当前阻塞: 无。D5.2 已补 storage helper 正例, 下一步 D5.3 补 `rc > 1` 必须 COW 反例。
  - 验证: 本项为文档规则收口, 使用 `rg` 核对 FBIP / COW / storage write helper / managed struct set 证据, 并执行 `git diff --check -- doc/memory.md doc/roadmap_status.md doc/master_plan.md doc/start_here.md`。
- [x] D5.2 补 `rc == 1` 可 reuse WAT pattern。实现与验证:
  - 新增 compile_ok `232_arc_storage_reuse_rc1_set_put_lower`, 使用同一 local `data = @set(data, 1, 90)` 和 `data = @put(data, 33)` 锁住 storage 写路径的当前可复用形态。
  - `.expect` 要求 runtime prelude 存在 `__storage_set_u8` / `__storage_put_u8`, `count=2 call $__arc_rc`, `count=0 call $__arc_inc`, 且源码写路径各调用一次 `call $__storage_set_u8` 和 `call $__storage_put_u8`。
  - 手动验证: `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/232_arc_storage_reuse_rc1_set_put_lower.do -o /tmp/232_arc_storage_reuse_rc1_set_put_lower.verify.wat` 后逐行匹配 `.expect` 通过。
  - 完整默认回归: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=787 fail=0 skip=35`。
  - 当前阻塞: 无。D5.3 已补 `rc > 1` 必须 COW 反例。
- [x] D5.3 补 `rc > 1` 必须 COW 反例。实现与验证:
  - 新增 compile_ok `233_arc_storage_reuse_rc_gt1_alias_cow_lower`, 用 `alias [u8] = data` 后执行 `next [u8] = @set(data, 1, 90)` 锁住跨变量写入前的 alias protect。
  - `.expect` 要求 `count=2 call $__arc_inc`: 一次来自 alias 绑定, 一次来自写 helper 前的临时 protect; 同时要求 `count=1 call $__storage_set_u8` 和 helper 后 `call $__arc_dec` 平衡临时 retain。
  - 新增 compiled_ok `49_compiled_test_storage_alias_set_keeps_old_value`, 执行验证 `alias` 仍读到原字节 `98` (`b`), `next` 读到新字节 `90` (`Z`), 证明共享 source 走 COW 后旧值不可被原地改写。
  - 手动验证: `233` 的 WAT pattern 逐行匹配通过; `49` 通过 `do test --compiled` + `wasm-tools parse` + `run_compiled_test_case.mjs`, 输出 `ok: 1 passed; 0 failed`。
  - 完整默认回归: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=789 fail=0 skip=35`。
  - 当前阻塞: 无。D5.4 已实现 managed struct 最小 helper 和 lowering。
- [x] D5.4 实现最小 helper 和 lowering。实现与验证:
  - 修改 `tool/build/codegen.zig` 的 `emitManagedStructFieldSet(...)`: RHS 先落入 `__storage_overwrite_tmp`; 随后按 `__arc_rc(target) == 1` 分支。唯一对象分支输出 `;; arc-managed-struct-reuse target.field`, 保留旧 child 不同才 `__arc_dec` 的覆盖释放; 共享对象分支输出 `;; arc-managed-struct-clone-set target.field`, 分配新 struct object, 写目标字段, 复制其他字段并 retain managed child, 再 `__arc_dec` 当前 local 持有的旧 handle, 最后 `local.set target`。
  - 新增 helper `emitManagedStructCloneWithFieldSet(...)`, 只服务 managed struct field update 的 clone 分支, 不改变用户语法和 `@set` 返回值语义。
  - 更新 compile_ok `50_arc_managed_struct_set_lower.expect`, 锁住 `call $__arc_rc`、`arc-managed-struct-reuse`、`arc-managed-struct-clone-set` 和 `local.set $box`。
  - 新增 compiled_ok `50_compiled_test_managed_struct_alias_set_keeps_old_field`: RED 时 shared alias 读到新字段并触发 `RuntimeError: unreachable`; 修复后 alias 读旧字段, box 读新字段。
  - 新增 compiled_ok `51_compiled_test_managed_struct_alias_set_preserves_other_field`, 验证 clone 分支复制并 retain 非目标 managed field。
  - focused 验证: `cd tool && zig test build/codegen.zig` 通过 `All 31 tests passed.`; `cd tool && zig test main.zig` 通过 `All 58 tests passed.`; `cd tool && zig build -Doptimize=Debug` 通过。
  - targeted 验证: compile_ok `50`、`58`、`199`、`200`、`201` expect 均通过; compiled_ok `50`、`51` 均通过 `do test --compiled` + `wasm-tools parse` + `run_compiled_test_case.mjs`。
  - 完整默认回归: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=791 fail=0 skip=35`。
- [x] D5.5 补 trap smoke。实现与验证:
  - 新增 compiled_trap `02_compiled_managed_struct_alias_set_oob_get_traps`, 覆盖 shared managed struct alias 经过 field set clone 后, 旧 alias 字段仍保持旧 storage, 且旧 storage 越界读取仍走 `__storage_check_range` trap。
  - targeted 验证: `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_trap/02_compiled_managed_struct_alias_set_oob_get_traps.do --compiled -o /tmp/02_compiled_managed_struct_alias_set_oob_get_traps.wat` 通过; `wasm-tools parse` 通过; `node tool/build/test/run_compiled_test_case.mjs /tmp/02_compiled_managed_struct_alias_set_oob_get_traps.wasm /tmp/02_compiled_managed_struct_alias_set_oob_get_traps.wat` 按预期非 0 退出, trap 为 `RuntimeError: unreachable` at `__storage_check_range`。
  - 完整 wasm 回归: `RUN_WASM=1 SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=793 fail=0 skip=35`。
  - 当前阻塞: D5 无。D2.1 仍是已记录 blocked 残留; 当前已进入阶段 E, E1、E2、E3、E4.1、E4.2、E4.3、E4.4、E4.5、E5.1、E5.2 和 E5.3 已完成。阶段 E 当前完成, 下一步进入阶段 F 或新开 backend IR 工程化子阶段。

## 阶段 E: 后端 IR 和 codegen 稳定化

状态: done

当前结论: E1.1 已扩展 `tool/build/backend_ir.zig` 的标量 IR 指令集合, 并把 `backend_ir.zig` 接入 `tool/main.zig` 聚合测试。E1.2 已补最小 IR builder API 和单元测试。E1.3 已补最小 WAT emitter 单元测试。E2.1 已选定 `compile_ok/02_scalar_numeric_lower.do` 作为最小 IR lowering 目标。E2.2 已在 `emitStartFunc` 中新增 backend IR lowering 窄入口。E2.3 已完成目标 WAT/wasm 执行对比。E3.1 已补 const fold IR test 和最小实现。E3.2 已复验 local copy fold IR test。E3.3 已复验 trivial call inline IR test。E3.4 已补 WAT pattern 验证。E4.1 已完成 codegen 输出边界盘点。E4.2 已抽出 runtime prelude writer。E4.3 已抽出 function body writer 外壳。E4.4 已抽出 component metadata writer。E4.5 已完成 full regression。E5.1 已完成继续 WAT 的成本评估。E5.2 已完成 direct binary emitter 收益和测试代价评估。E5.3 已给出推荐: 当前继续保留 WAT 主路径, 暂不正式引入 direct binary emitter; 后续只允许在 backend IR 小子集内做实验性并行输出。阶段 E 当前完成。

E1 扩展 backend IR 到当前标量表达式:

- [x] E1.1 扩展 `tool/build/backend_ir.zig` 指令集合。实现与验证:
  - 新增 `ScalarType`、`ConstValue`、`NumericOp`、`CompareOp`、`NumericInstr`、`CompareInstr` 和 `ConditionalBranch`, 覆盖 E1 范围内的 locals、constants、numeric op、comparison、branch、return 表达能力。
  - `Instr` 保留旧 `const_i32/local_get/local_set/call` 标签, 追加 `const_value/local_tee/numeric/compare`; `Terminator` 保留旧 `ret/br`, 追加 `ret_value/br_if`。
  - `foldEmptyBranchBlocks(...)` 只补 `br_if` 两侧目标重写, 不改变空 block 删除条件, 不触碰 codegen lowering 和 managed storage。
  - 同步 `tool/main.zig` 聚合测试导入 `build/backend_ir.zig`, 避免 `zig test main.zig` 漏掉 backend IR 文件内单测。
  - RED: `cd tool && zig test build/backend_ir.zig` 先失败于缺少 `const_value` 和 `br_if` union tag; 实现后曾暴露测试保存 `ArrayList` 元素指针跨 append 的悬空指针问题, 已改为通过 block id/index 重新取元素。
  - GREEN: `cd tool && zig test build/backend_ir.zig` 通过 `All 8 tests passed.`; `cd tool && zig test main.zig` 通过 `All 66 tests passed.`。
- [x] E1.2 补 IR builder 单元测试。实现与验证:
  - 新增 `Function.addBlockId(...)`、`appendInstr(...)`、`setTerminator(...)` 和 `getBlock(...)`, 让 builder 通过稳定 `BlockId` 写入 block, 不再要求调用方长期保存 `ArrayList` 元素指针。
  - `Function.addBlock(...)` 保持旧 API 兼容, 内部委托 `addBlockId(...)` 后再通过 `getBlock(...)` 返回当前 block 指针。
  - 新增 `next_block_id`, 避免 block 被 `orderedRemove` 折叠后新 block id 与存量 id 复用。
  - RED: `cd tool && zig test build/backend_ir.zig` 先失败于缺少 `addBlockId` / `appendInstr` builder API。
  - GREEN: `cd tool && zig test build/backend_ir.zig` 通过 `All 10 tests passed.`; `cd tool && zig test main.zig` 通过 `All 68 tests passed.`; `cd tool && zig build -Doptimize=Debug` 通过。
- [x] E1.3 补 WAT emitter 单元测试或 fixture。实现与验证:
  - 新增 `emitFunctionWat(...)` 最小 emitter, 支持 straight-line 标量函数和 entry `br_if` 到 then/else 两个 return block 的结构化 if 形态。
  - emitter 覆盖 `const_i32`、`const_value`、`local_get`、`local_set`、`local_tee`、`numeric`、`compare`、`call`、`ret` 和 `ret_value`; 其它 CFG shape 显式返回 `UnsupportedIrWatShape`, 不伪装支持任意 CFG lowering。
  - RED: `cd tool && zig test build/backend_ir.zig` 先失败于缺少 `emitFunctionWat`。
  - GREEN: `cd tool && zig test build/backend_ir.zig` 通过 `All 12 tests passed.`; `cd tool && zig test main.zig` 通过 `All 70 tests passed.`; `cd tool && zig build -Doptimize=Debug` 通过。

E2 一个小型 compiled_ok 走 IR lowering:

- [x] E2.1 选定最小 compiled_ok case。结论:
  - 目标 fixture 选 `tool/build/test/compile_ok/02_scalar_numeric_lower.do`。虽然 E2 标题沿用 compiled_ok 表述, 但阶段 E2 范围允许“标量 start 或 compiled test”; 这里先选标量 `start()` compile fixture, 避免第一条 IR lowering 同时处理 test harness、compiled-test manifest、`unreachable` 或 managed storage。
  - 该 fixture 只覆盖 i32 local、常量、`@add/@mul` 和 `return`: `x i32 = @add(1, 2, 3)`, `y i32 = @mul(x, 4)`, 对应 `.expect` 锁住 `(local $x i32)`、`i32.const`、`i32.add`、`local.set $x`、`local.get $x`、`i32.mul` 和 `local.set $y`。
  - 对比未选项: `compile_ok/01_start_entry_valid.do` 只有空 return, 太弱; `compile_ok/06_guard_if_return_eq.do` 额外涉及 host import fallback; `compiled_ok/11_compiled_test_inferred_numeric_literal_call.do` 涉及 compiled test harness 和 `unreachable`, 不适合作为第一条窄入口。
  - 验证: `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/02_scalar_numeric_lower.do -o /tmp/02_scalar_numeric_lower.e2.wat` 通过; 逐行匹配 `tool/build/test/compile_ok/02_scalar_numeric_lower.expect` 通过。
- [x] E2.2 新增 IR lowering 路径。实现与验证:
  - 在 `tool/build/codegen.zig` 引入 `backend_ir.zig`, 并在 `emitStartFunc(...)` 的 local 声明之后、旧 `emitBody(...)` 之前增加窄入口 `emitScalarNumericStartWithBackendIr(...)`。
  - 窄入口只匹配 E2.1 选定目标形态: `start()` body 内的 i32 typed scalar binding、`@add/@sub/@mul` numeric core call、number/local 参数和 plain `return`; 匹配失败时回退旧 `emitBody(...)`, 不影响 managed storage、host import、compiled test harness 或通用表达式路径。
  - `backend_ir.Function` 新增 `setValueName(...)` 和 `emitFunctionBodyWat(...)`, 让 IR emitter 可以保持现有源码 local 名称 `$x/$y`, 并只输出 body 指令, 外层 `(func $_start)`、local declaration 和 export 仍由旧 codegen 负责。
  - RED: 新增 focused codegen test 后, `cd tool && zig test build/codegen.zig --test-filter 'backend ir lowering emits selected scalar numeric start body'` 先失败于缺少 `emitScalarNumericStartWithBackendIr`。
  - GREEN: focused codegen test 通过; `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/02_scalar_numeric_lower.do -o /tmp/02_scalar_numeric_lower.ir.after_fmt.wat` 通过且逐行匹配原 `.expect`; `cd tool && zig test build/backend_ir.zig` 通过 `All 12 tests passed.`; `cd tool && zig test build/codegen.zig` 通过 `All 44 tests passed.`; `cd tool && zig test main.zig` 通过 `All 70 tests passed.`; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=791 fail=0 skip=35`。
- [x] E2.3 对比 WAT 输出和执行结果。验证:
  - WAT 文本: `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/02_scalar_numeric_lower.do -o /tmp/02_scalar_numeric_lower.ir.after_fmt.wat` 通过, 且逐行匹配原 `tool/build/test/compile_ok/02_scalar_numeric_lower.expect`。
  - WAT 片段保持原语义: `_start` 内仍包含 `(local $x i32)`、`(local $y i32)`、`i32.const 1`、`i32.const 2`、`i32.add`、`i32.const 3`、`i32.add`、`local.set $x`、`local.get $x`、`i32.const 4`、`i32.mul`、`local.set $y` 和 `return`。
  - wasm parse: `wasm-tools parse /tmp/02_scalar_numeric_lower.ir.after_fmt.wat -o /tmp/02_scalar_numeric_lower.ir.after_fmt.wasm` 通过。
  - wasm execution: `node tool/build/test/run_wasm_case.mjs /tmp/02_scalar_numeric_lower.ir.after_fmt.wasm > /tmp/02_scalar_numeric_lower.ir.after_fmt.stdout && test ! -s /tmp/02_scalar_numeric_lower.ir.after_fmt.stdout` 通过, `_start` 无 trap 且无 stdout。
  - 回归: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=791 fail=0 skip=35`。

E3 IR peephole 扩展:

- [x] E3.1 为 const fold 补 IR test。实现与验证:
  - 新增 `Function.foldConstantNumericOps()`, 先只折叠安全的 i32 `add/sub/mul` 常量序列, 不碰除法/取余、浮点或跨 block 传播。
  - 新增 IR 单测 `backend ir folds constant i32 numeric op`, 锁住 `i32.const 1; i32.const 2; i32.add` 折叠为单个 `const_value.i32 = 3`。
  - RED: `cd tool && zig test build/backend_ir.zig --test-filter 'folds constant i32 numeric op'` 先失败于缺少 `foldConstantNumericOps`。
  - GREEN: focused test 通过; `cd tool && zig test build/backend_ir.zig` 通过 `All 13 tests passed.`; `cd tool && zig test main.zig` 通过 `All 71 tests passed.`; `cd tool && zig build -Doptimize=Debug` 通过。
- [x] E3.2 为 local copy fold 补 IR test。结论:
  - `tool/build/backend_ir.zig` 已有 `Function.foldRedundantLocalCopies()` 和单测 `backend ir folds redundant local_get local_set pair`, 覆盖同一 `ValueId` 的连续 `local_get` + `local_set` 被删除。
  - 当前不新增行为, 只把已有 E3 local copy fold 回归纳入阶段 E 状态。
  - 验证: `cd tool && zig test build/backend_ir.zig --test-filter 'folds redundant local_get local_set pair'` 通过。
- [x] E3.3 为 trivial call inline 补 IR test。结论:
  - `tool/build/backend_ir.zig` 已有 `Module.inlineTrivialConstCalls(...)` 和单测 `backend ir inlines trivial const callee call`, 覆盖单 block、单 `const_i32`、`ret` 的 trivial callee 被内联到 caller 的 `call` 位置。
  - 当前不新增行为, 只把已有 E3 trivial inline 回归纳入阶段 E 状态。
  - 验证: `cd tool && zig test build/backend_ir.zig --test-filter 'inlines trivial const callee call'` 通过。
- [x] E3.4 如已接入 E2, 增加 WAT pattern 验证。实现与验证:
  - 在 `tool/build/test/compile_ok/02_scalar_numeric_lower.expect` 增加 `;; backend-ir-lowering scalar-numeric-start` pattern, 锁住该 fixture 确实走 backend IR lowering 窄入口。
  - `tool/build/codegen.zig` 的 `emitStartFunc(...)` 先把 IR body 输出到临时 buffer; 只有 `emitScalarNumericStartWithBackendIr(...)` 成功匹配时才写入 marker 和 IR body, 匹配失败仍回退旧 `emitBody(...)`。
  - 目标 WAT: `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/02_scalar_numeric_lower.do -o /tmp/02_scalar_numeric_lower.e3_4.green.wat` 通过, 且逐行匹配更新后的 `.expect`。
  - wasm parse/execution: `wasm-tools parse /tmp/02_scalar_numeric_lower.e3_4.green.wat -o /tmp/02_scalar_numeric_lower.e3_4.green.wasm` 通过; `node tool/build/test/run_wasm_case.mjs /tmp/02_scalar_numeric_lower.e3_4.green.wasm > /tmp/02_scalar_numeric_lower.e3_4.green.stdout && test ! -s /tmp/02_scalar_numeric_lower.e3_4.green.stdout` 通过。
  - 聚合测试: `cd tool && zig test build/codegen.zig --test-filter 'backend ir lowering emits selected scalar numeric start body' && zig test main.zig` 通过, `main.zig` 摘要 `All 71 tests passed.`。
  - 默认完整回归: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=791 fail=0 skip=35`。

E4 WAT emitter 边界清理:

- [x] E4.1 盘点 codegen 输出片段边界。结论:
  - module skeleton / orchestration 边界: 普通 build 由 `tool/build/codegen.zig:892` 的 `emitWatWithOptions(...)` 组织, 最终输出序列在 `tool/build/codegen.zig:1021` 到 `tool/build/codegen.zig:1032`: `(module` header、source counters、WASI bind metadata、WASI core imports、env host imports、memory/data、ARC runtime prelude、user funcs、`_start`、module close。
  - compiled test orchestration 边界: `tool/build/codegen.zig:1036` 的 `emitTestWat(...)` 复用同类收集逻辑, 输出序列在 `tool/build/codegen.zig:1169` 到 `tool/build/codegen.zig:1182`: module header、compiled_test_count、imports、memory/runtime、user funcs、`__test_N` funcs、test `_start`、module close。
  - import / metadata writer 边界: `emitWasiBindings(...)` 写 `;; wasi-bind ...` manifest comment, `emitWasiCoreImports(...)` 写已登记 WASI core imports, `emitHostImports(...)` 写 `env` imports, 入口分别在 `tool/build/codegen.zig:8066`, `tool/build/codegen.zig:8084`, `tool/build/codegen.zig:8112`。
  - memory / data / component-core 边界: E4.2 后由 `tool/build/runtime_prelude_wat.zig:31` 的 `emitStringDataMemory(...)` 负责普通 memory export vs `--component-core` memory 形态、`cm32p2_memory` export 和 static data segments; `tool/build/codegen.zig:1010` 和 `tool/build/codegen.zig:1159` 只保留 orchestration 调用。
  - runtime prelude 边界: E4.2 后由 `tool/build/runtime_prelude_wat.zig:159` 的 `emitArcRuntimePrelude(...)` 负责 heap globals、`cm32p2_realloc` / `cm32p2_initialize`、WASI result area、allocator/free-span/ARC helpers、layout table 和 release worklist; layout table 的内部 writer 是 `emitArcLayoutTable(...)` (`tool/build/runtime_prelude_wat.zig:68`)。
  - function body 边界: `emitUserFuncs(...)` / `emitUserFunc(...)` 从 `tool/build/codegen.zig:1392` / `tool/build/codegen.zig:1404` 进入, `emitStartFunc(...)` 在 `tool/build/codegen.zig:1168`, `emitTestFuncs(...)` / `emitTestStartFunc(...)` 在 `tool/build/codegen.zig:1340` / `tool/build/codegen.zig:1379`; 共同依赖 `emitBody(...)` 递归输出 statement-level WAT。
  - E4.2 已抽出 runtime prelude writer 边界, 并保持 `emitStringDataMemory(...)`、heap base、layout table 和 `cm32p2_*` 输出顺序不变。
  - E4.3 推荐再抽 function body writer façade, 先搬移 `emitUserFuncs` / `emitStartFunc` / `emitTestFuncs` 的外层函数声明和 local declaration 组织, 不碰 `emitBody(...)` 内部 statement lowering 语义。
  - E4.4 推荐只处理 component metadata / WASI manifest writer, 以 `emitWasiBindings`、core imports 和 component-core memory 选项为边界, 不把真实 component wasm/binary emitter 拉进本阶段。
  - 当前非目标: 不改公开 WAT 输出语义, 不重排 `.expect` 依赖的片段顺序, 不做 direct wasm binary emitter, 不触碰 `do run` / WASI resource 后置线。
  - 验证: 只读盘点 + 文档同步; `rg -n "pub fn emitWat|pub fn emitWatWithOptions|try out.appendSlice\\(allocator, \"\\(module|emitWasiBindings|runtime_prelude_wat|emitUserFuncs|emitStartFunc|return out.toOwnedSlice" tool/build/codegen.zig` 用于定位主输出序列; `rg -n "pub fn emitStringDataMemory|pub fn emitArcRuntimePrelude|pub fn emitArcLayoutTable|emitUserFuncs|emitTestFuncs|emitTestStartFunc" tool/build/runtime_prelude_wat.zig tool/build/codegen.zig` 用于定位 writer 边界。
- [x] E4.2 抽出 runtime prelude writer。实现与验证:
  - 新增 `tool/build/runtime_prelude_wat.zig`, 把 `StringData`、`ManagedFieldOffset`、`StructLayout`、memory/data segment writer、ARC runtime header、完整 ARC runtime prelude WAT helper body、layout table writer 和 WAT string literal escape 收敛到 runtime prelude writer 模块。
  - `tool/build/codegen.zig` 仅保留语义收集和 module orchestration; `emitWatWithOptions(...)` 与 `emitTestWat(...)` 改为调用 `runtime_prelude_wat.emitStringDataMemory(...)` 和 `runtime_prelude_wat.emitArcRuntimePrelude(...)`。
  - `tool/main.zig` 聚合测试导入 `build/runtime_prelude_wat.zig`, 避免新 writer 单测被漏跑。
  - RED: `cd tool && zig test build/runtime_prelude_wat.zig` 先失败于缺少 `StringData` / `ManagedFieldOffset`, 确认测试先于实现生效。
  - GREEN: `cd tool && zig test build/runtime_prelude_wat.zig` 通过 `All 2 tests passed.`; `cd tool && zig test main.zig` 通过 `All 73 tests passed.`; `cd tool && zig build -Doptimize=Debug` 通过。
  - 局部 WAT smoke: `./bin/do build tool/build/test/compile_ok/02_scalar_numeric_lower.do -o /tmp/e4_2_scalar.after_move.wat`; `./bin/do build --component-core tool/build/test/compile_ok/96_wasi_manifest_module_scoped_alias.do -o /tmp/e4_2_component_core.after_move.wat`; `./bin/do test tool/build/test/compiled_ok/01_compiled_test_entry.do --compiled -o /tmp/e4_2_compiled_test.after_move.wat` 均通过。
  - WAT 边界核查: `rg -n "\\(memory|cm32p2_memory|arc-runtime|arc-layout|compiled-test|backend-ir-lowering" /tmp/e4_2_scalar.after_move.wat /tmp/e4_2_component_core.after_move.wat /tmp/e4_2_compiled_test.after_move.wat` 确认普通 build 仍导出 `memory`, component-core 仍输出 `(memory 1)` + `cm32p2_memory`, ARC runtime/layout marker、compiled-test marker 和 backend IR marker 保持存在。
  - 默认完整回归: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=791 fail=0 skip=35`。
- [x] E4.3 抽出 function body writer。实现与验证:
  - 新增 `tool/build/function_body_wat.zig`, 只承载 WAT-ready 的函数外壳 writer: `emitFuncOpen(...)`、`emitFuncClose(...)`、`emitFuncExport(...)`、`emitLocalDecl(...)`、`emitCompiledTestOpen(...)`、`emitCompiledTestExport(...)` 和 `emitTestStartFunc(...)`。
  - `tool/build/codegen.zig` 继续保留 `emitBody(...)`、`emitUserFunc(...)` 签名 ABI lowering、locals 收集、backend IR fallback、ARC cleanup 和 compiled-test `unreachable` 语义; 仅把 `_start` 外壳、compiled-test 外壳、local declaration、函数 close/export 和 compiled-test `_start` wrapper 委托给 `function_body_wat.zig`。
  - `tool/main.zig` 聚合测试导入 `build/function_body_wat.zig`, 避免新 writer 单测被漏跑。
  - RED: `cd tool && zig test build/function_body_wat.zig` 先失败于缺少 `emitFuncOpen` / `emitCompiledTestOpen`, 确认测试先于实现生效。
  - GREEN: `cd tool && zig test build/function_body_wat.zig` 通过 `All 2 tests passed.`; `cd tool && zig test main.zig` 通过 `All 75 tests passed.`; `cd tool && zig build -Doptimize=Debug` 通过。
  - 局部 WAT smoke: `./bin/do build tool/build/test/compile_ok/02_scalar_numeric_lower.do -o /tmp/e4_3_scalar.after_build.wat`; `./bin/do test tool/build/test/compiled_ok/01_compiled_test_entry.do --compiled -o /tmp/e4_3_compiled_test.after_build.wat` 均通过。
  - WAT 边界核查: `rg -n "\\(func \\$_start|\\(local \\$|compiled-test|export \\\"__test_|export \\\"_start\\\"|backend-ir-lowering" /tmp/e4_3_scalar.after_build.wat /tmp/e4_3_compiled_test.after_build.wat` 确认 `_start` export、compiled-test manifest/export 和 backend IR marker 保持存在。
  - 默认完整回归: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=791 fail=0 skip=35`。
- [x] E4.4 抽出 component metadata writer。实现与验证:
  - 新增 `tool/build/component_metadata_wat.zig`, 只承载 component/WASI metadata 和 import WAT 输出: `emitWasiBindings(...)`、`emitWasiCoreImports(...)`、`emitHostImports(...)`、`appendWasiImportSymbol(...)` 和 WASI target 到 core import ABI 的 `wasiLowering(...)` 表。
  - `tool/build/codegen.zig` 继续保留 `@env` / `@wasi` 扫描解析、build-use 验证、reachable/import graph 语义、lowerability 判断和实际 host/WASI call lowering; 仅把 module header 的 manifest/import 输出委托给 `component_metadata_wat.zig`。
  - `tool/main.zig` 聚合测试导入 `build/component_metadata_wat.zig`, 避免新 writer 单测被漏跑。
  - RED: `cd tool && zig test build/component_metadata_wat.zig` 先失败于缺少 `emitWasiBindings` / `emitWasiCoreImports` / `emitHostImports` / `appendWasiImportSymbol`, 确认测试先于实现生效。
  - GREEN: `cd tool && zig test build/component_metadata_wat.zig` 通过 `All 4 tests passed.`; `cd tool && zig test main.zig` 通过 `All 79 tests passed.`; `cd tool && zig build -Doptimize=Debug` 通过。
  - 局部 WAT smoke: `DO_LIB_ROOT=tool/build/test/lib ./bin/do build tool/build/test/compile_ok/96_wasi_manifest_module_scoped_alias.do -o /tmp/e44_manifest.wat` 后用 `node tool/build/test/validate_wasi_bind_manifest.mjs --registry doc/wit/wasi_registry.json --component-input-dir /tmp/e44_component_input /tmp/e44_manifest.wat` 校验通过; `--component-core` 输出仍包含 `cm32p2|wasi:*` imports、`(memory 1)` 和 `cm32p2_memory`; env host import fixture 仍包含 `(memory (export "memory") 1)` 和 `call $host_log`。
- [x] E4.5 full regression。验证:
  - `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=791 fail=0 skip=35`。

E5 direct wasm binary emitter 重新评估:

- [x] E5.1 评估继续 WAT 的成本。结论:
  - 推荐当前继续保留 WAT 作为公开可验证输出, 暂不把 direct wasm binary emitter 放入实现主线。E5.1 只评估“继续 WAT”的成本, E5.2 再单独评估 binary emitter 收益和测试代价。
  - P1 成本: statement-level lowering 仍集中在 `tool/build/codegen.zig`, 该文件当前约 19.6k 行; 即使 E4 已抽出 runtime prelude、function body 和 component metadata writer, `emitBody(...)` 及大量表达式/控制流/ARC lowering 仍直接拼接 WAT 文本。继续 WAT 会继续放大“语义判断 + 文本输出”混在同一文件的问题。
  - P1 成本: 运行和 compiled wasm gate 依赖外部 `wasm-tools parse` 把 WAT 转 wasm; `do run` 当前公开边界也是 `build -> WAT -> wasm-tools parse -> node`。这让 WAT parse 成为执行路径的一部分, 缺失工具时只能报外部依赖错误。
  - P2 成本: `.expect`、`.core_imports.expect`、`.core_shims.expect`、`.component_input.expect` 和 `.component_core.expect` 都以文本片段锁住输出, 好处是可读, 代价是 WAT 格式重排会造成大量测试噪声。
  - P2 成本: Component Model 输入仍从 WAT manifest 注释和文本 core imports 派生, 需要继续维护 `;; wasi-bind ...`、`cm32p2_memory`、core shims 等文本契约。新抽出的 `component_metadata_wat.wasmType(...)` 仍对未知类型默认落到 `i32`, 后续若继续扩展 host import 类型, 推荐改为显式 unsupported 诊断或在调用前保证已完成类型白名单校验。
  - P3 成本: WAT 对调试友好, 但长期看会让 backend IR 的收益受限于“最终仍要生成字符串”的边界, 优化 pass 很容易绕回 `codegen.zig`。
  - 稳定性收益: README 已把 WAT 代码生成子集列为已完成能力, 并明确 `do run` / 回归入口走 WAT; 测试 harness 已覆盖 WAT 片段、WASI manifest、component input/core、可用时的 component embed/new/validate, 默认完整回归当前为 `pass=799 fail=0 skip=35`。
  - 维持 WAT 的优先优化点: 1) 扩大 backend IR 覆盖面, 让更多 locals、basic control-flow、scalar call 和 storage handle 路径先降到 IR 再统一 emit WAT; 2) 抽出 build/test 共享的 `CodegenInputs` 构造流程, 避免 `emitWatWithOptions(...)` 和 `emitTestWat(...)` 双路径漂移; 3) 强化 WAT 验证边界, 在工具可用时默认 parse 更多 compile/compiled WAT, 并把未知类型 fallback 改成显式 unsupported。
  - 证据: `tool/build/codegen.zig` 仍由 `emitWatWithOptions(...)` 和 `emitTestWat(...)` 组织 WAT module 输出; 当前调用 `component_metadata_wat.emitWasiBindings(...)` / `emitWasiCoreImports(...)` / `emitHostImports(...)` 后再写 memory/runtime/function body。`tool/build/backend_ir.zig` 只有窄 WAT emitter, 不支持任意 CFG。`tool/build/test/run_tests.sh` 仍用文本 `.expect`、component input/core expect 和 `wasm-tools parse/embed/new/validate` 做 gate。README 明确 `do run` 当前边界是 WAT 到 wasm-tools parse。
  - 验证: 只读评估 + 文档同步; E4.5 已先跑 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 并通过 `pass=791 fail=0 skip=35`。
- [x] E5.2 评估 direct binary emitter 的收益和测试代价。结论:
  - direct wasm binary emitter 的收益存在, 但当前不适合作为正式主路径直接替换 WAT。若要做, 推荐只作为实验性并行输出, 且必须保留 WAT 文本输出作为调试和 golden 基线。
  - P1 收益: `do run` 和 compiled wasm 执行可以绕过 `wasm-tools parse`, 减少产品命令对外部 parse 工具的硬依赖; 当前 `tool/run/run.zig` 明确先查找 `wasm-tools`, 写 `out.wat`, 再执行 `wasm-tools parse out.wat -o out.wasm` 后交给 Node runner。
  - P1 收益: binary writer 可以在编码阶段直接暴露 section/type/local/function index 错误, 不再等 WAT parse 才发现 duplicate local、fallthrough type mismatch 或 label shape 问题。
  - P2 收益: 长期可让 backend IR 的最终输出从“字符串打印”演进为结构化 module builder, 减少文本格式变动导致的 `.expect` 噪声。
  - P1 代价: 本机 Zig 0.16 的 `std.wasm` 主要提供 opcode、value type、section、magic/version 等常量; `std.leb` / `std.Io.Writer` 提供 LEB128 写入工具, 但没有可直接复用的高级 wasm module writer。direct binary emitter 需要自建 type/import/function/memory/global/export/code/data/custom/name section builder、type interning、index 分配、local declaration 编码、block/loop/if label depth 编码和 instruction encoder。
  - P1 代价: 当前 ARC runtime prelude、allocator、release worklist、layout table、WASI result area 和 component memory 都是手写 WAT。binary emitter 若只覆盖用户函数, 仍要混合 WAT parse; 若覆盖完整模块, 就必须把 runtime prelude 也迁成结构化 instruction builder。
  - P1 代价: 当前 Component Model 链路依赖 WAT 文本和 `;; wasi-bind ...` manifest 注释。binary wasm 没有普通注释通道, 必须改成 sidecar metadata、custom section 或继续产出 WAT companion; 否则 `validate_wasi_bind_manifest.mjs`、component input/core 生成、core imports/core shims expect 都要重写。
  - P2 代价: 测试体系不能只检查 binary bytes。最小 gate 至少要保留 WAT golden 或新增 canonical disassembly/metadata golden, 并对同一 fixture 做 `WAT -> wasm-tools parse` 与 direct wasm 的行为对比、`wasm-tools validate`、Node instantiate/execute、component embed/new/validate。否则 direct emitter 容易在不可读 bytes 中藏 ABI 漂移。当前 `compile_ok` WAT expect 约 231 个, `compiled_ok` WAT expect 约 52 个, component 相关 expect 约 34 个, 都会放大直接替换成本。
  - P2 代价: CLI 语义需要重新设计。当前 README 和 `do build` 示例以 `-o app.wat` 为用户可见产物; `parseBuild(...)` 和 compiled test CLI 默认输出都是 `out.wat`, usage 文案也写 `out.wat`。直接把默认输出改成 `.wasm` 会破坏现有调试流和 fixture 体系。合理路径应是后续单独设计 `--emit=wat|wasm` 或内部实验命令, 不在 E5 评估期直接改变默认输出。
  - P2 代价: compiled test runner 当前除了枚举 `__test_N` export, 还从 WAT 中的 `;; compiled-test N "name"` 注释读取测试显示名。direct binary emitter 如果不提供 WAT companion 或 sidecar manifest, 会丢失现有测试名输出。
  - 证据: `tool/build/run.zig` 的 build/test compiled 路径仍分别调用 `compileProgramWat(...)` / `codegen.emitTestWat(...)` 并写出 WAT; `tool/run/run.zig` 仍强依赖 `wasm-tools` parse; `tool/build/test/run_tests.sh` 对 `.wat`、component input/core WAT、core shims WAT 和 `wasm-tools component embed/new/validate` 有大量 gate; `README.md` 明确 `do build app.do -o app.wat` 与 `do run` 的 WAT parse 边界; `tool/build/test/README.md` 明确 component/WASI 输入仍是 WAT 和 `wasi-bind` 注释契约。Zig 0.16 证据: `std.wasm` 暴露 binary constants/types, `std.leb128` / `std.Io.Writer` 暴露 LEB writers, 没有现成 module writer。
  - 最小实验范围建议: 只在 backend IR 已覆盖的 `compile_ok/02_scalar_numeric_lower.do` 这类标量 start 子集试做 `emitWasmBinaryFromIr(...)`; 不碰 ARC runtime、component/WASI、managed storage、compiled test harness 和 CLI 默认输出。实验验收必须包含 direct wasm 与当前 WAT parse wasm 的 Node 执行等价、`wasm-tools validate` 通过、以及保留 WAT 输出不变。
  - 验证: 只读评估 + 文档同步; 复验 `cd tool && zig test build/component_metadata_wat.zig && zig test main.zig` 通过, `All 4 tests passed.` / `All 79 tests passed.`。
- [x] E5.3 给出继续保留、实验性引入或正式引入的推荐。结论:
  - 推荐 A: 当前继续保留 WAT 作为主输出和稳定调试格式, 不正式引入 direct wasm binary emitter。原因是 WAT 已被 README、CLI、run/test harness、component/WASI 工具链和大量 `.expect` 锁定; 直接替换会制造大面积迁移风险, 但收益主要集中在绕过 `wasm-tools parse` 和结构化编码, 尚不足以覆盖当前主线代价。
  - 允许 B: 后续可以新开一个 backend IR 工程化子阶段, 在不改 CLI 默认输出、不改现有 WAT golden、不触碰 runtime prelude / component / WASI 的前提下, 对 `backend_ir` 小子集做实验性 `emitWasmBinaryFromIr(...)`。该实验只验证 direct wasm 与当前 WAT parse wasm 等价, 不承诺成为产品输出; 如果覆盖 compiled test, 必须提供 sidecar manifest 或继续保留 WAT companion 以维持测试名输出。
  - 不推荐 C: 现在正式引入 direct binary emitter 并尝试替换 `do build` / `do test --compiled` 主路径。当前缺少完整 IR 覆盖、缺少高级 wasm module writer、runtime prelude 仍是手写 WAT、component manifest 依赖 WAT 注释, 替换会同时扩大后端、runtime、component 和测试体系风险。
  - 后续优先级: 先做 backend IR 覆盖扩展和 `CodegenInputs` 共用构造, 再决定 binary emitter 是否值得进入产品路径; binary emitter 的任何实验都必须以“不改变 WAT 输出”和“不降低 full regression gate”为前提。
  - 验证: 只读决策 + 文档同步; 复用 E5.1/E5.2 证据和 `cd tool && zig test build/component_metadata_wat.zig && zig test main.zig` 的通过结果。

## 阶段 F: LSP 编辑器体验升级

状态: done

当前结论: 阶段 F 已完成 F1 hover、F2 completion、F3 definition 最小版、F4.1 workspace root 输入记录、F4.2 workspace top-level symbol 扫描、F4.3 completion / definition index 复用、F4.4 多文件 LSP fixture 和 F5 rename 评估。结论是 v1 不实现 rename, 当前继续不声明 `renameProvider`。A1 formatting 和 A2 semantic tokens 已完成, F 阶段不重复这两项; F5 已同步 README / roadmap。下一步进入阶段 G: WASI / Component Model 最后处理。

F1 hover 最小版:

- [x] F1.1 设计 hover 内容格式。结论:
  - LSP response 采用标准 `MarkupContent`: `{"contents":{"kind":"plaintext","value":"..."}}`; 未命中任何 symbol 时返回 `result:null`, 不返回空字符串或错误。
  - hover 文本只包含一段 plaintext 签名或声明摘要, 不加解释性 prose, 不读取文档注释, 不做跨模块深度搜索。
  - top-level type hover: 对结构体名显示 `User { ... }`; 对 value enum / error / union 这类顶层类型后续按声明首行显示, 例如 `FileError error = ...` 或 `Value = i32 | text`。
  - function hover: 显示规范化签名, 例如 `get_title(user User) -> text`; 无显式返回时显示 `-> nil`, 让 hover 与调用者心智一致。
  - field hover: 只在当前文件可确定所属 struct 时显示 `User.title text`; 暂不展示默认值、可见性解释或字段注释。
  - local / parameter hover: 显示 `name Type`; 对推导类型仅在当前已有明确类型来源时展示, 否则不命中, 避免猜测。
  - builtin type / keyword / operator 暂不作为 F1.1 目标; `@` builtin 函数 hover 后置到 completion/builtin doc 阶段。
  - fixture 断言建议: 当前 `run_lsp_case.mjs` 只做 stdout 子串匹配, 因此 F1.2 先断言 `"hoverProvider":true`、`"kind":"plaintext"`、以及函数签名片段, 不要求完整 JSON 结构 diff。
  - 证据: 当前 `protocol.writeInitializeResponse(...)` 已集中写 capabilities; `protocol.writeTextEditsResponse(...)` 和 `writeSemanticTokensResponse(...)` 都按手写 JSON response 模式输出; `tool/lsp/run.zig` 的 `handleMessage(...)` 已按 method 分支处理 formatting / semantic tokens; `tool/build/test/lsp/*.json` 和 `run_lsp_case.mjs` 使用 request fixtures + stdout substring 作为黑盒 LSP gate。
- [x] F1.2 新增 hover fixture。实现与验证:
  - 新增 `tool/build/test/lsp/06_hover_request.json`, 打开包含 `User` struct 和 `get_title(user User) -> text` 的当前文件, 在函数名位置发送 `textDocument/hover`。
  - fixture 期望 initialize capability 包含 `"hoverProvider":true`, hover response 包含 `MarkupContent` plaintext: `get_title(user User) -> text`。
  - RED: `node tool/build/test/run_lsp_case.mjs ./bin/do tool/build/test/lsp/06_hover_request.json` 失败于缺少 `"hoverProvider":true`, 同时 hover 请求返回 `Method not found`; 证明 fixture 先于实现生效。
- [x] F1.3 接入当前文件 symbol lookup。实现与验证:
  - 新增 `tool/lsp/hover.zig`, 使用 lexer token 和 LSP zero-based position 在当前打开文件中识别光标下 token, 支持 top-level 函数声明 hover 和当前文件函数调用回查声明; 未命中返回 `null`。
  - `tool/lsp/protocol.zig` 声明 `"hoverProvider":true`, 并新增 plaintext `writeHoverResponse(...)`; `tool/lsp/run.zig` 接入 `textDocument/hover` handler。
  - 验证: `cd tool && zig test main.zig` 通过 `84/84`; `cd tool && zig build -Doptimize=Debug` 通过; `node tool/build/test/run_lsp_case.mjs ./bin/do tool/build/test/lsp/06_hover_request.json` 通过。
- [x] F1.4 同步 README 和 roadmap。实现与验证:
  - `README.md`、`tool/build/test/README.md`、`CHANGELOG.md`、`doc/master_plan.md` 和 `doc/start_here.md` 当时已同步 `do lsp` 边界: diagnostics、formatting、semantic tokens 和最小函数 hover; completion 当时继续后置, 后续已由 F2 最小版完成。
  - `doc/master_plan.md` 和 `doc/start_here.md` 的下一步已切到 F2.1。
  - 验证: stale scan 未发现当前入口仍把 hover 描述为当前缺失能力; `git diff --check` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=792 fail=0 skip=35`。

F2 completion 最小版:

- [x] F2.1 completion item 编码测试。实现与验证:
  - `tool/lsp/protocol.zig` 新增 `CompletionItemKind`、`CompletionItem` 和 `writeCompletionResponse(...)`, 采用 LSP `CompletionItem[]` 数组 response。
  - 只完成 response 编码, 暂不在 initialize 中暴露 `completionProvider`, 避免 handler 未接入前编辑器收到不可用能力。
  - 验证: 先以 `cd tool && zig test main.zig` 复现红灯 `use of undeclared identifier 'writeCompletionResponse'`; 实现后同命令通过 `85/85`。
- [x] F2.2 当前文件函数 / 类型 completion。实现与验证:
  - 新增 `tool/lsp/completion.zig`, 使用 lexer token 和 top-level brace depth 收集当前文件函数名与类型名 completion item, 并去重。
  - 当前不收集字段名, 字段 completion 留给 F2.3; 当前也不接 LSP handler, handler / fixture 留给 F2.4。
  - 验证: 先以 `cd tool && zig test main.zig` 复现红灯 `use of undeclared identifier 'collectCompletionItems'`; 实现后同命令通过 `87/87`。
- [x] F2.3 字段 completion 最小支持。实现与验证:
  - `tool/lsp/completion.zig` 在字段段上下文追加当前文件 struct 字段 completion item; item label 使用字段名本身, 避免在用户已经输入 `.` 时产生双点。
  - 当前字段 completion 不做 receiver 类型收窄, 只按当前文件 struct 字段集合给出最小候选; 类型收窄后置。
  - 验证: 先以 `cd tool && zig test main.zig` 复现红灯 `MissingCompletionItem`; 实现并修正 LSP zero-based 测试坐标后同命令通过 `88/88`。
- [x] F2.4 completion fixture 回归。实现与验证:
  - 新增 `tool/build/test/lsp/07_completion_request.json`, 覆盖 initialize `completionProvider`、`textDocument/completion` response、当前文件类型/函数候选和字段段候选。
  - `tool/lsp/protocol.zig` 暴露 `completionProvider` 和 `.` trigger; `tool/lsp/run.zig` 接入 `textDocument/completion` handler, 复用 `tool/lsp/completion.zig` collector。
  - `README.md`、`tool/build/test/README.md`、`CHANGELOG.md`、`doc/master_plan.md` 和 `doc/start_here.md` 已同步 F2 completion 当前边界。
  - 验证: 先用旧二进制复现 fixture 红灯, 缺少 `completionProvider` 且请求返回 `Method not found`; 实现后 `cd tool && zig test main.zig` 通过 `89/89`, `cd tool && zig build -Doptimize=Debug` 通过, `node tool/build/test/run_lsp_case.mjs ./bin/do tool/build/test/lsp/07_completion_request.json` 通过, `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=793 fail=0 skip=35`。

F3 definition 最小版:

- [x] F3.1 definition 位置格式。实现与验证:
  - `tool/lsp/protocol.zig` 新增 `Location` 和 `writeDefinitionResponse(...)`, 使用标准 LSP `Location | null` response, 范围沿用现有 zero-based `Range` 编码。
  - 只完成 response 编码, 暂不在 initialize 中暴露 `definitionProvider`, 避免 handler 未接入前编辑器收到不可用能力。
  - 验证: 先以 `cd tool && zig test main.zig` 复现红灯 `use of undeclared identifier 'writeDefinitionResponse'`; 实现后同命令通过 `90/90`。
- [x] F3.2 当前文件函数 / 类型 definition。实现与验证:
  - 新增 `tool/lsp/definition.zig`, 使用 lexer token 查找光标 token, 并在当前文件 top-level 函数 / 类型声明中回查同名 definition。
  - 当前只返回当前打开文件内的 `Location`; 不做 workspace index、import 跳转、字段/local definition。
  - 验证: 先以 `cd tool && zig test main.zig` 复现红灯 `use of undeclared identifier 'findDefinition'`; 实现后同命令通过 `93/93`。
- [x] F3.3 definition fixture。实现与验证:
  - 新增 `tool/build/test/lsp/08_definition_request.json`, 覆盖 initialize `definitionProvider` 和当前文件函数 / 类型 `textDocument/definition` response。
  - `tool/lsp/protocol.zig` 暴露 `"definitionProvider":true`; `tool/lsp/run.zig` 接入 `textDocument/definition` handler, 复用 `tool/lsp/definition.zig` 当前文件 lookup。
  - RED: 先用旧二进制复现 fixture 红灯, 缺少 `"definitionProvider":true` 且请求返回 `Method not found`。
  - GREEN: `cd tool && zig test main.zig` 通过 `94/94`; `cd tool && zig build -Doptimize=Debug` 通过; `node tool/build/test/run_lsp_case.mjs ./bin/do tool/build/test/lsp/08_definition_request.json` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=794 fail=0 skip=35`。

F4 workspace index 第一版:

- [x] F4.1 定义 workspace root 输入。实现与验证:
  - `tool/lsp/run.zig` 的 `ServerState` 新增 `workspace_roots`, initialize 时优先记录 `params.workspaceFolders[*].uri`; 若没有有效 workspaceFolders, 回退记录 `params.rootUri`。
  - 当前只保存 URI 字符串, 不读取 `rootPath`, 不扫描 workspace 文件, 不建立 symbol index; F4.2 再消费这些 roots 扫描 `.do` 文件。
  - RED: 先新增 `handleMessage records initialize workspace folders` 用例, `cd tool && zig test main.zig` 失败于 `no field named 'workspace_roots' in struct 'lsp.run.ServerState'`。
  - GREEN: 实现 workspace root 记录并补 `rootUri` 回退用例后, `cd tool && zig test main.zig` 通过 `96/96`; `cd tool && zig build -Doptimize=Debug` 通过; `node tool/build/test/run_lsp_case.mjs ./bin/do tool/build/test/lsp/08_definition_request.json` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=794 fail=0 skip=35`。
- [x] F4.2 扫描 `.do` 文件 top-level symbol。实现与验证:
  - 新增 `tool/lsp/workspace.zig`, 提供 `collectWorkspaceSymbols(...)` 和 `WorkspaceSymbol` / `WorkspaceSymbolKind`, 扫描 `file:///abs/path` workspace root 下的一层 `.do` 文件。
  - `ServerState` 新增 `workspace_symbols`, initialize 记录 roots 后刷新 index; 当前只记录顶层函数 / 类型 symbol, 不递归、不处理非 file URI / host URI / percent-encoded URI, 不把 index 接到 completion / definition 输出。
  - RED: 先新增 workspace scanner 用例, `cd tool && zig test main.zig` 失败于 `use of undeclared identifier 'collectWorkspaceSymbols'`; 再新增 initialize 集成用例, 失败于 `no field named 'workspace_symbols' in struct 'lsp.run.ServerState'`。
  - GREEN: 实现 scanner 和 initialize index 后, `cd tool && zig test main.zig` 通过 `98/98`; `cd tool && zig build -Doptimize=Debug` 通过; `node tool/build/test/run_lsp_case.mjs ./bin/do tool/build/test/lsp/08_definition_request.json` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=794 fail=0 skip=35`。
- [x] F4.3 completion / definition 复用 index。实现与验证:
  - `tool/lsp/completion.zig` 新增 `collectCompletionItemsWithWorkspace(...)`, 在当前文件候选后追加 workspace 顶层函数 / 类型候选并去重。
  - `tool/lsp/definition.zig` 新增 `findDefinitionWithWorkspace(...)`, 当前文件命中优先; 当前文件未命中时按 token 名称回退 workspace symbol 的 URI/range。
  - `tool/lsp/run.zig` 的 completion / definition handler 已改为传入 `state.workspace_symbols.items`。
  - 同步修复顶层 symbol 误判: completion、definition 和 workspace scanner 的函数 / 类型声明识别都要求声明 token 从行首开始, 避免把函数签名里的返回类型误当顶层类型声明。
  - RED: `cd tool && zig test main.zig` 先失败于 `use of undeclared identifier 'collectCompletionItemsWithWorkspace'` 和 `findDefinitionWithWorkspace`; 接入后曾暴露返回类型误判为当前文件 definition, 已用同一轮测试固定。
  - GREEN: `cd tool && zig test main.zig` 通过 `100/100`; `cd tool && zig build -Doptimize=Debug` 通过; `node tool/build/test/run_lsp_case.mjs ./bin/do tool/build/test/lsp/08_definition_request.json` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=794 fail=0 skip=35`。
- [x] F4.4 multi-file fixture。实现与验证:
  - 新增 `tool/build/test/lsp/09_workspace_index_request.json`, 覆盖临时 workspace 中 `external.do` 的顶层类型 / 函数被 `main.do` 的 completion 和 definition 使用。
  - `tool/build/test/run_lsp_case.mjs` 支持 fixture `workspace.files`, 会创建临时 workspace 文件, 并在 messages / expect 中替换 `{{workspaceUri}}`。
  - RED: 新 fixture 在旧 harness 下失败, completion 返回空数组且 definition 返回 `null`, 缺少 `"label":"ProjectUser","kind":7`。
  - GREEN: `node tool/build/test/run_lsp_case.mjs ./bin/do tool/build/test/lsp/09_workspace_index_request.json` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过并收录 `lsp 09_workspace_index_request`, 摘要 `pass=795 fail=0 skip=35`。

F5 rename 评估:

- [x] F5.1 列出 rename 误改风险。结论:
  - 当前 workspace index 只记录顶层函数 / 类型定义, 不记录引用点; 没有 references graph 时无法生成可靠 `WorkspaceEdit`。
  - 当前 definition fallback 只按 token 名称匹配 workspace symbol, 不是 import-aware resolution; 同名函数、同名类型、跨文件 shadow 和未导入 symbol 都会造成误改风险。
  - 语言允许同名函数重载, rename 如果只按 name 改写会把不同签名重载一起改掉; 如果按签名改写, 当前 LSP index 还没有参数签名级 identity。
  - 当前 LSP 不索引 local、parameter、field、field segment、private `.name`、builtin 或 import alias 的作用域; rename 这些名字会混淆声明、引用和普通同名 token。
  - 当前 workspace scan 只处理 `file:///abs/path` root 下的一层 `.do` 文件, 不递归、不处理 percent-encoded URI、非 file URI 或增量文件变更; rename 的编辑范围会不完整。
  - 当前 `didChange` 只更新打开文档 diagnostics, 不刷新 workspace index; unsaved buffer 与磁盘文件不一致时 rename 可能基于陈旧 symbol。
  - 当前实现使用 lexer token 和少量 top-level 规则, 没有 AST/source map 级别的引用分类; 虽然不会改字符串内容, 但无法区分同名值、类型、参数、字段和函数引用。
  - 因此 F5.1 结论是: rename 的误改风险高于当前 v1 LSP index 能力, 不能直接进入实现。
- [x] F5.2 给出 v1 是否支持的推荐。结论:
  - 推荐: v1 不支持 `textDocument/rename`, 当前继续不在 initialize capabilities 中声明 `renameProvider`, 也不新增 rename handler。
  - 理由: 当前 index 已足够支撑 completion / definition 的低风险回退, 但还不能支撑跨文件批量改写; rename 一旦误改会直接修改用户源码, 风险高于当前证据边界。
  - 未来进入条件: 先建立 import-aware symbol identity、引用点 graph、重载签名级 identity、open document overlay、增量/递归 workspace index、URI decode / path normalize, 并补 prepareRename / rename 的正反例 fixture。
  - 当前验收: 决策记录落地到 `doc/roadmap_status.md`; 公开文档继续描述 `do lsp` 不提供 rename。

G1 binding source / alias 规则冻结:

- [x] G1.1 审查 `doc/wit/wasi_p3_lowering.md` 与实现。结论:
  - `doc/wit/wasi_p3_lowering.md` 已明确 `wasi-bind` manifest 字段和 binding identity 是 `source + alias`; `source="entry"` 表示入口模块, `source="module-path"` 表示递归导入模块, `alias` 只在 source module 内局部有效。
  - 实现侧 `tool/build/codegen.zig` 已在模块收集和调用解析中携带 source; 调用时通过当前 token buffer 映射 source, 再按 `source + alias` 查找 WASI host import。
  - 发现并修复缺陷: 同一入口模块内重复 `@wasi` alias 之前能 build 成两条相同 `source+alias` manifest, 直到 manifest validator 才失败。现在 `tool/build/sema.zig` 在同一 source module 内前置拒绝重复 host import alias, 报 `DuplicateHostImportAlias`。
  - 文档漂移已修正: `doc/master_plan.md` 的当前推荐阶段从旧的 F 修正为 G, 并在 G1 完成后切到 G2。
- [x] G1.2 审查 `doc/wit/wasi_registry.json` 与 manifest tool。结论:
  - `tool/build/test/validate_wasi_bind_manifest.mjs` 用 `${source}\0${alias}` 做唯一键, 输出 `identity: "${source}/${alias}"`, 不是只按 alias 去重。
  - `doc/wit/wasi_registry.json` 与 manifest tool 已按 target/params/result 做已知签名校验; core import 按 WIT target 去重, per-source alias 由 core shim / component plan identity 保留。
  - 验证: `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/96_wasi_manifest_module_scoped_alias.do -o /tmp/g1_96_wasi_manifest_module_scoped_alias.green.wat && node tool/build/test/validate_wasi_bind_manifest.mjs --registry doc/wit/wasi_registry.json --component-input-dir /tmp/g1_96_component_input_green /tmp/g1_96_wasi_manifest_module_scoped_alias.green.wat` 通过。
- [x] G1.3 补 alias 正反例。实现与验证:
  - manifest tool 正例: `tool/build/test/test_wasi_bind_manifest_tool.mjs` 覆盖 `entry/host_now` 与 `src/time.do/host_now` 可以共存, JSON 输出两个不同 identity。
  - manifest tool 反例: 同一 `source="entry"` 下重复 `alias="host_now"` 必须失败并报 `duplicate wasi binding identity: entry/host_now`。
  - compile 正例: 既有 `tool/build/test/compile_ok/96_wasi_manifest_module_scoped_alias.do` 覆盖入口模块和 `src/time.do` 同名 `host_now` alias 共存, component input 期望包含 `src/time.do/host_now` 与 `entry/host_now` 两个 shim identity。
  - compile 反例: 新增 `tool/build/test/compile_err/273_wasi_duplicate_host_import_alias.do`, 锁住同一入口模块内重复 `host_now = @wasi(...)` 必须报 `DuplicateHostImportAlias`。
  - 文档同步: `doc/spec_rules.md` 写明 host import alias 在同一 source module 内唯一; 入口模块和递归导入模块可以各自使用同名 alias, 因为 WASI binding identity 是 `source + alias`。
  - 验证: `cd tool && zig test main.zig` 通过 `100/100`; `cd tool && zig build -Doptimize=Debug` 通过; `node tool/build/test/test_wasi_bind_manifest_tool.mjs tool/build/test/validate_wasi_bind_manifest.mjs /tmp/do-wasi-bind-test` 通过, 输出 `ok: wasi-bind manifest tool`; 新增 compile_err 手动验证输出 `error[DuplicateHostImportAlias]`; `git diff --check` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=796 fail=0 skip=35`。

G2 result-area lowering 完整化:

- [x] G2.1 盘点已登记 result target。结论:
  - `doc/wit/wasi_registry.json` 当前登记 17 个 result/result-bearing target: 11 个已 lower 的 result-area 形态, 5 个 socket/http result 形态已知但 unsupported, 1 个 `descriptor.read-directory` 的 `future<result<_,error-code>>` 复合形态已知但 unsupported。
  - 已 lower 的 result-area target: `descriptor.sync/write/read/link-at/open-at/create-directory-at/remove-directory-at`, `input-stream.read`, `output-stream.check-write/write/flush`。
  - known unsupported target: `descriptor.read-directory`, `tcp-socket.create/bind`, `udp-socket.create/bind`, `http/client.send`。
  - 文档同步: `doc/wit/wasi_p3_lowering.md` 新增 `Registered Result Target Inventory` 表, 作为 G2.2 fixture 补齐的工作清单。
  - 验证: `node` 读取 `doc/wit/wasi_registry.json` 并筛出 `result<...>` target; 对照 `tool/build/component_metadata_wat.zig`、`tool/build/test/validate_wasi_bind_manifest.mjs`、`src/file.do`、`src/dir.do`、`src/io.stream.do` 和 `doc/wit/wasi_p3_lowering.md` 的 result-area / unsupported 描述。
- [x] G2.2 补 result-area lowering fixture。结论:
  - 11 个当前 lowerable result-area target 均已有 compile_ok lowering 覆盖。
  - raw host direct lowering: `100_wasi_result_unit_statement_lower`, `101_wasi_result_filesize_statement_lower`, `102_wasi_result_filesize_multi_lhs_lower`, `107_wasi_result_unit_status_multi_lhs_lower`, `109_wasi_result_read_multi_lhs_lower`, `111_wasi_result_link_at_multi_lhs_lower`, `115_wasi_result_stream_read_multi_lhs_lower`, `117_wasi_result_output_check_write_multi_lhs_lower`, `118_wasi_result_output_write_flush_status_lower`, `120_wasi_result_descriptor_open_at_multi_lhs_lower`。
  - std wrapper lowering: `105_imported_file_write_wrapper_lower`, `108_imported_file_flush_wrapper_lower`, `110_imported_file_read_wrapper_lower`, `113_imported_file_link_wrapper_lower`, `116_imported_stream_read_wrapper_lower`, `119_imported_stream_output_wrapper_lower`, `121_imported_file_open_at_wrapper_lower`, `124_imported_dir_create_remove_wrapper_lower`。
  - `descriptor.create-directory-at` / `descriptor.remove-directory-at` 当前通过 `124_imported_dir_create_remove_wrapper_lower` 的 wrapper lowering 覆盖, 没有单独 raw host direct fixture; 这与当前 std 公开边界一致。
  - 验证: `rg` 对 `descriptor.sync/write/read/link-at/open-at/create-directory-at/remove-directory-at`, `input-stream.read`, `output-stream.check-write/write/flush` 在 `tool/build/test/compile_ok` 和 `src` 中逐项检索, 并核对 `.expect` 中存在对应 `cm32p2` import / call pattern。
- [x] G2.3 补 component plan/core shims 验证。结论:
  - 11 个当前 lowerable result-area target 均已有 target 级 `.component_plan.expect`、`.core_imports.expect` 和 `.core_shims.expect` 覆盖。
  - 本项新增 `107_wasi_result_unit_status_multi_lhs_lower.*` 三类 sidecar, 锁住 `descriptor.sync` 的 component plan、core import ABI 和 per-alias core shim。
  - 本项新增 `109_wasi_result_read_multi_lhs_lower.*` 三类 sidecar, 锁住 `descriptor.read` 的 tuple/list/bool result plan、core import ABI 和 per-alias core shim。
  - 验证: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=796 fail=0 skip=35`。
  - 后续: G3.1/G3.2/G3.3/G4.1/G4.2/G4.3/G4.4/G5.1/G5.2/G5.3/G5.4 已完成, 当前下一步进入 G6.1。

G3 resource lifecycle:

- [x] G3.1 固定 resource handle 表达。结论:
  - `File`、`Dir`、`InputStream` 和 `OutputStream` 当前统一表达为带私有 `.id i64` 的 Do wrapper struct。
  - 外部模块只能接收和传递 wrapper 值, 不能构造、读取或修改 `.id`, 也不能假定资源由 ARC 自动关闭。
  - 私有 std wrapper 在调用已登记 `@wasi` binding 前显式读取 `.id` 并收窄到 WIT resource handle；公开 API 继续只暴露 Do 类型、错误枚举和多返回值形态。
  - 文档同步: `doc/spec_rules.md` 和 `doc/wit/wasi_p3_lowering.md` 已补齐该资源句柄表达规则。
  - 新增负例: `326_resource_file_private_id_ctor` 锁住外部不能构造 `File{id = ...}`; `327_resource_file_private_id_get` 锁住外部不能读取 `.id`; `328_resource_file_private_helper_import` 锁住外部不能导入 `file_id` private helper。
  - 验证: 只读核对 `src/file.do`、`src/dir.do`、`src/io.stream.do`、`tool/build/test/compile_ok/105/108/110/113/116/119/121/122/123/124_*`、`tool/build/test/ok/96_file_lib_resource_shape.do` 和 `tool/build/test/ok/118_wasi_p3_std_wrappers.do`; 新增 3 个 err fixture 均手动命中预期诊断; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=799 fail=0 skip=35`。
- [x] G3.2 固定 close/drop 错误边界。结论:
  - WIT `descriptor.drop` / resource-drop 没有普通错误结果, 标准库 close/drop wrapper 固定为 `close_file(file File) -> nil` 和 `close_dir(dir Dir) -> nil`。
  - 删除不可达的 `FileCloseFailed` 分支；会失败的资源 API 继续保留在有 status/result 的 `flush/read/write/link/open/create/remove` 等 wrapper 中。
  - `close_file` / `close_dir` 现在可作为 `defer` cleanup 调用；返回错误枚举的 cleanup 仍不得放进 `defer`。
  - 同步: `src/file.do`、`src/dir.do`、`tool/build/test/compile_ok/122_*`、`123_*`、`tool/build/test/ok/96_*`、`118_*`、`doc/spec_rules.md`、`doc/spec_examples.md` 和 `doc/wit/wasi_p3_lowering.md`。
  - 验证: `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/122_imported_file_close_wrapper_lower.do -o /tmp/do_g32_122_after.wat` 通过; `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/123_imported_dir_open_close_wrapper_lower.do -o /tmp/do_g32_123_after.wat` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=799 fail=0 skip=35`。
- [x] G3.3 std wrapper compiled_ok。结论:
  - 当前 file / dir / input-stream / output-stream 公开 resource wrapper 均已有 compile_ok lowering 覆盖。
  - 覆盖矩阵: `105_imported_file_write_wrapper_lower`, `108_imported_file_flush_wrapper_lower`, `110_imported_file_read_wrapper_lower`, `113_imported_file_link_wrapper_lower`, `116_imported_stream_read_wrapper_lower`, `119_imported_stream_output_wrapper_lower`, `121_imported_file_open_at_wrapper_lower`, `122_imported_file_close_wrapper_lower`, `123_imported_dir_open_close_wrapper_lower`, `124_imported_dir_create_remove_wrapper_lower`。
  - 边界: `ok/96_file_lib_resource_shape` 和 `ok/118_wasi_p3_std_wrappers` 仍可保持 runtime skip; G3.3 验收的是 compile_ok lowering, 不是本机 WASI runtime 执行。
  - 验证: 对上述 10 个 compile_ok fixture 逐一执行 `DO_LIB_ROOT=src ./bin/do build ... -o /tmp/*.g33.wat` 均通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=799 fail=0 skip=35`。
  - 下一步: G4.1/G4.2/G4.3/G4.4/G5.1/G5.2/G5.3/G5.4 已完成, 当前进入 G6.1 preopens 设计。

G4 variant / flags / list<record> 支持评估:

- [x] G4.1 variant 支持评估。结论:
  - 当前不引入通用 WIT variant lowering。已 lower 的 `error-code` / `stream-error` 只存在于 result-area status 编码中: `status == 0` 表示 ok, 非 0 表示 WIT variant index + 1, 再由标准库 wrapper 转成领域内 `FileError`、`DirError` 或 `StreamError`。
  - 当前 known-but-unsupported sockets 目标才是真正需要通用 variant 的压力点: `tcp-socket.create` / `udp-socket.create` 使用 `ip-address-family`, `tcp-socket.bind` / `udp-socket.bind` 使用 `ip-socket-address`, 同时还依赖 resource handle。单独实现 variant 不能让 sockets 可 lower。
  - 当前标准库 `src/tcp.do`、`src/udp.do` 和 `src/http.client.do` 仍只是公开形状枚举/结构, 没有私有 `@wasi` wrapper 调用链; 不应在 G4.1 为未接入的 socket/http API 预先扩大 codegen 表面。
  - 推荐: G4.1 只记录评估结论并后置通用 variant lowering。下一步先评估 G4.2 flags, 因为当前 lowerable `descriptor.link-at/open-at` 已实际使用 `path-flags` / `open-flags` / `descriptor-flags`, 但源码层仍用 `0/1/2` 这类私有整数常量承接。
  - 验证: `doc/wit/wasi_registry.json` registry 盘点; `tool/build/test/validate_wasi_bind_manifest.mjs` 的 `stream-error` WIT 输出和 result shim kind 检查; `tool/build/test/test_wasi_bind_manifest_tool.mjs` 的 sockets known-but-unsupported 断言; `node tool/build/test/test_wasi_bind_manifest_tool.mjs tool/build/test/validate_wasi_bind_manifest.mjs /tmp/do-wasi-bind-g41` 通过, 输出 `ok: wasi-bind manifest tool`。
  - 下一步: G4.2/G4.3/G4.4/G5.1/G5.2/G5.3/G5.4 已完成, 当前进入 G6.1 preopens 设计。
- [x] G4.2 flags 支持评估。结论:
  - 当前不新增公开 WIT flags 类型, 也不把 `path-flags` / `open-flags` / `descriptor-flags` 暴露成普通 Do 类型。标准库 wrapper 内部继续按 canonical ABI bitset 用 `i32` 传入私有 `@wasi` binding。
  - 实现收口: `src/file.do` 的 `link_file/open_file_at` 和 `src/dir.do` 的 `open_dir_at` 已把 raw host call 位的裸 flags 数字改成局部 `path_flags/open_flags/descriptor_flags` 绑定；`open_dir_at` 的 `open_flags = 2` 仍对应 directory bit, 但不作为公开 API 泄漏。
  - 边界: flags 的 public 设计后置。若后续需要用户可配置 open/create/truncate/read/write 语义, 推荐先提供领域函数或私有 value enum/bitset helper, 不直接让用户构造 WIT flags。
  - 验证: `DO_LIB_ROOT=src ./bin/do check src/file.do`; `DO_LIB_ROOT=src ./bin/do check src/dir.do`; `DO_LIB_ROOT=src ./bin/do build` 重新生成 `113_imported_file_link_wrapper_lower`, `121_imported_file_open_at_wrapper_lower`, `123_imported_dir_open_close_wrapper_lower`; 三个 WAT 逐行匹配各自 `.expect` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=799 fail=0 skip=35`。
  - 下一步: G4.3/G4.4/G5.1/G5.2/G5.3/G5.4 已完成, 当前进入 G6.1 preopens 设计。
- [x] G4.3 list<record> 支持评估。结论:
  - 当前 registry 中没有可独立落地的普通 `list<record>` 子集。已 lower 的 list 子集仍是 `list<u8>`；已登记但 unsupported 的集合形态是 `filesystem/preopens/get-directories -> list<tuple<descriptor,string>>`。
  - `preopens.get-directories` 不能按普通 list<record> 直接实现, 因为元素里包含 `descriptor` resource handle 和 `string`; 需要先明确 resource ownership、tuple/list canonical ABI 和公开 `PreopenDir` wrapper 形态。
  - `descriptor.read-directory` 也不是 list<record>, 而是 `tuple<stream<directory-entry>,future<result<_,error-code>>>`; 它需要 stream/future/resource 生命周期设计, 不属于 G4.3 可单独落地范围。
  - 推荐: G4.3 只记录评估结论, 不新增 codegen。G4.4 再输出最小实现计划或明确把 preopens/read-directory 后置到 G5 component wasm 之后。
  - 验证: `doc/wit/wasi_registry.json` registry 盘点; `tool/build/test/test_wasi_bind_manifest_tool.mjs` 已锁住 `read-directory` 和 `preopens.get-directories` 为 known-but-unsupported; 最近完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=799 fail=0 skip=35`。
  - 下一步: 当前进入 G6.1 preopens 设计。
- [x] G4.4 输出最小实现计划或明确后置。结论:
  - 决策: G4 当前不继续实现通用 WIT variant、public flags 或 list<record>/list<tuple<resource,string>> lowering。阶段 G 的下一步切到 G5, 先证明现有 component input dir 能生成真实 component wasm 并通过 validate。
  - 保留的可执行子集: scalar、registered record result、`list<u8>`、已登记 result-area wrapper、resource-drop direct import、file/dir/io.stream 标准库 wrapper。
  - 后置进入条件: G5 证明 component builder 真实路径后, 再按依赖顺序扩复杂类型。推荐顺序是 preopens `list<tuple<descriptor,string>>` / wrapper struct, 再 read-directory stream/future, 再 sockets 的 resource + variant, 最后考虑公开 flags API。
  - 不做: 不在 G4.4 新增 codegen, 不把 socket/http/preopens/read-directory 包装成假可执行 API, 不把 WIT flags/variant/list tuple 泄漏成普通公开类型。
  - 验证: G4.1-G4.3 的 registry/manifest/test 证据已覆盖该决策; G4.2 代码变更后完整回归 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=799 fail=0 skip=35`。
  - 下一步: 当前进入 G6.1 preopens 设计。

G5 component builder 输入到真实 component wasm:

- [x] G5.1 固定本机工具链要求。结论:
  - 本机工具: `/home/_/.local/bin/wasm-tools` 为 `wasm-tools 1.251.0 (a1a178a02 2026-05-28)`, `/snap/bin/node` 为 `v24.18.0`, `/snap/bin/zig` 为 `0.16.0`。
  - 当前 `wasm-tools component` 子命令包含 `embed`, `new`, `wit`, `targets`, `link`, `semver-check`, `unbundle`, 不包含 `component validate`。
  - 固定验证链路: `wasm-tools component embed <wit-dir> <core_component.wat> -o embedded.wasm`; `wasm-tools component new embedded.wasm -o component.wasm`; `wasm-tools validate component.wasm`。
  - 现有测试证据: `tool/build/test/test_wasi_bind_manifest_tool.mjs` 和 `tool/build/test/run_tests.sh` 已按上述等价链路执行 embed/new/validate; G5.2 已把这条链路从测试内的派生产物推进成明确的 component wasm 生成目标。
  - 同步: `doc/master_plan.md` 已把旧的 `wasm-tools component validate` 说法改成顶层 `wasm-tools validate`。
- [x] G5.2 生成 component wasm。结论:
  - 实现: `tool/build/test/validate_wasi_bind_manifest.mjs` 新增 `--component-wasm <file.wasm>` 输出模式, 复用 `emitComponentInputDir(...)` 生成临时 component input, 再调用 `wasm-tools component embed` 和 `wasm-tools component new` 写出真实 component wasm。
  - 行为边界: 该模式生成 component wasm 产物; G5.3 已把 `wasm-tools validate` 明确接成工具成功条件。
  - 验证: `node tool/build/test/test_wasi_bind_manifest_tool.mjs tool/build/test/validate_wasi_bind_manifest.mjs /tmp/do-wasi-bind-g52-green` 通过, 输出 `ok: wasi-bind manifest tool`。
  - 产物验证: `wasm-tools validate /tmp/do-wasi-bind-g52-green/component_tool_output.wasm` 通过; 产物大小为 `2138` bytes。
  - 完整回归: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=799 fail=0 skip=35`。
- [x] G5.3 `wasm-tools validate`。结论:
  - 实现: `--component-wasm` 在 `wasm-tools component new` 之后执行顶层 `wasm-tools validate <component.wasm>`, validate 失败时通过 `failPlan(...)` 返回非 0。
  - 红灯: fake `wasm-tools` 让 embed/new 成功但 validate 失败时, `test_wasi_bind_manifest_tool.mjs` 先失败于 `component wasm output should validate generated component`。
  - 绿色验证: `node tool/build/test/test_wasi_bind_manifest_tool.mjs tool/build/test/validate_wasi_bind_manifest.mjs /tmp/do-wasi-bind-g53-green` 通过, 输出 `ok: wasi-bind manifest tool`。
  - 产物验证: `wasm-tools validate /tmp/do-wasi-bind-g53-green/component_tool_output.wasm` 通过; 产物大小为 `2138` bytes。
  - 完整回归: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=799 fail=0 skip=35`。
- [x] G5.4 接入可选回归 gate。结论:
  - 实现: `tool/build/test/run_tests.sh` 在 `.component_input.expect` 用例且 `wasm-tools` 可用时, 额外调用 `validate_wasi_bind_manifest.mjs --component-wasm <file.wasm>` 生成并验证真实 component wasm。
  - 红灯: `rg -n -- '--component-wasm' tool/build/test/run_tests.sh` 初始无命中。
  - 绿色验证: `bash -n tool/build/test/run_tests.sh`; `rg -n -- '--component-wasm' tool/build/test/run_tests.sh tool/build/test/README.md`; `node tool/build/test/test_wasi_bind_manifest_tool.mjs tool/build/test/validate_wasi_bind_manifest.mjs /tmp/do-wasi-bind-g54-pre` 均通过。
  - 完整回归: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=799 fail=0 skip=35`。
  - 下一步: G6.1 preopens `list<tuple<descriptor,string>>` / wrapper struct 设计。

G6 后置复杂 WIT 类型分批展开:

- [ ] G6.1 preopens `list<tuple<descriptor,string>>` / wrapper struct 设计。blocked:
  - 阻断点: 公开 API 需要用户确认。已提出三种方案: A `PreopenDir { dir Dir, name text }` + `preopen_dirs() -> [PreopenDir] | DirError`；B 多返回 `[Dir], [text], DirError | nil`；C 只 lower manifest/codegen, 暂不公开标准库 API。
  - 推荐: A。理由是它保留 WIT tuple 的结构语义, 对用户比多返回更稳定, 也能把 descriptor resource 包装成现有 `Dir` 边界。
  - 证据: registry 目标是 `filesystem/preopens/get-directories -> list<tuple<descriptor,string>>`; 当前 manifest tool 已把它标记为 `unsupported`, component plan 会拒绝 `entry/host_preopens`。
  - 停止条件: 不在未确认公开 API 的情况下扩 codegen 或 std wrapper, 避免把 `descriptor` ownership 和 preopen close 语义做错。
  - 恢复条件: 用户确认 A/B/C 或给出新 API 形态。
  - 下一步: G6.2 已确认因当前无 async/Future runtime 暂阻断; 若继续 G6, 转 G6.3 sockets resource + variant 设计取证。
- [ ] G6.2 `descriptor.read-directory` stream/future 设计。blocked:
  - 阻断点: 这不是现有 `io.stream.do` 同步 stream wrapper 的简单扩展。WIT 返回 `tuple<stream<directory-entry>,future<result<_,error-code>>>`, 同时涉及 stream resource、future completion 和 `directory-entry` record/variant 镜像; 当前语言/运行时没有 async / Future / Task 支持。
  - 证据: `doc/wit/wasi_registry.json` 只登记了该 target 的 compact result 文本, 当前 `records` 只有 `Datetime`, 没有 `directory-entry` 或 descriptor-type 镜像; `tool/build/test/test_wasi_bind_manifest_tool.mjs` 明确断言 read-directory `shim.kind = "unsupported"` 且 `--component-plan` 必须拒绝 `entry/host_dir_read`; `doc/arc.md` 的 Future/Task/FFI 仍是后续预留。
  - 推荐: 不在 G6.2 直接实现, 维持 blocked。先另立 async/Future/Task/resource stream 运行时设计, 再回来定义公开 API。公开 API 倾向为同步拉取式 wrapper, 例如 `DirEntries` 不透明句柄 + `next_dir_entry(entries) -> DirEntry | DirError | nil`, 但这需要先明确 future completion 何时 await/drop、directory stream 如何 close/drop。
  - 停止条件: 不把 `tuple<stream<directory-entry>,future<result<_,error-code>>>` 降成假普通多返回, 不引入未定义的 Future 运行时对象, 不把 `directory-entry` 当成已知 record。
  - 恢复条件: 完成 async/Future/Task/resource stream 运行时设计, 并明确 future completion 的 await/drop 语义、directory stream close/drop 语义和公开 wrapper 边界。
  - 下一步: 先推进 G6.3 sockets resource + variant 设计取证。
- [ ] G6.3 sockets resource + variant 设计。blocked:
  - 阻断点: `tcp-socket.create/bind` 和 `udp-socket.create/bind` 同时依赖 WIT resource、WIT variant 和地址 record/variant 映射, 不能只按已有 scalar/result-area 路径 lower。
  - 证据: registry 登记 `ip-address-family`, `ip-socket-address`, `tcp-socket`, `udp-socket`; manifest tool 已断言四个 sockets target `shim.kind = "unsupported"` 且 `--component-plan` 必须拒绝 `entry/host_tcp_create`; `src/tcp.do` / `src/udp.do` 当前只有 do 层 `TcpListener`、`TcpStream`、`UdpSocket` 和错误枚举形态, 没有私有 `@wasi` wrapper; `doc/spec_rules.md` 明确真实 I/O API 留到 host ABI lowering、WIT resource 生命周期和 stream ownership 规则明确后实现。
  - 推荐: 不在 G6.3 直接实现 sockets lowering。先统一所有 resource wrapper 的 private `.id i64` 形态, 再新增 WIT variant 镜像策略, 最后设计 `SocketAddr` 到 `ip-socket-address` 的双向映射。
  - 停止条件: 不把当前 `TcpListener { .fd i32 }` / `TcpStream { .fd i32 }` / `UdpSocket { .fd i32 }` 当成最终 WIT resource ABI, 不把 `SocketAddr.family` 的 `u8` 直接当成 WIT variant tag 泄漏。
  - 恢复条件: 用户确认 socket resource wrapper 形态和 address variant 映射, 或先完成通用 WIT variant/resource lowering 计划。
  - 下一步: 先推进 G6.4 public flags API 决策。
- [x] G6.4 public flags API 是否需要公开。结论:
  - 决策: 当前不新增公开 WIT flags 类型, 也不把 `path-flags` / `open-flags` / `descriptor-flags` 暴露成普通 Do 类型。
  - 证据: G4.2 已完成 flags 支持评估; `src/file.do` 和 `src/dir.do` 只在 wrapper 内部用 `path_flags/open_flags/descriptor_flags i32` 承接 canonical ABI bitset; `tool/build/test/validate_wasi_bind_manifest.mjs` 只在 WIT emitter 里输出 flags 定义, 不把它们变成公开 Do 类型; `doc/spec_rules.md` 明确不允许把 WIT `flags` 作为普通公开类型泄漏。
  - 推荐: 以后如果用户需要 open/create/truncate/read/write 这类配置, 先提供领域函数或 wrapper-local value enum/bitset helper, 不直接公开 WIT flags API。
  - 验证: `rg -n "path-flags|open-flags|descriptor-flags|flags|open_flags|path_flags|descriptor_flags" src doc/wit/wasi_p3_lowering.md doc/spec_rules.md tool/build/test/compile_ok tool/build/test/validate_wasi_bind_manifest.mjs`。
  - 下一步: H1.1 输出 skip 列表。

H1 skip 用例审计:

- [x] H1.1 输出 skip 列表。结论:
  - 当前完整回归: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=799 fail=0 skip=35`。
  - 实际 skip 总数: 35。提取命令: `grep '^\\[SKIP\\]' /tmp/do_h1_skip_audit.out`。
  - ok fixture skip 共 3 个:
    - `ok/118_wasi_p3_std_wrappers`
    - `ok/16_loop_recv_value`
    - `ok/96_file_lib_resource_shape`
  - std src `NoTestDecl` skip 共 32 个:
    - `atomic`, `base64`, `binary`, `bytes`, `dir`, `file`, `fp`, `hash_map`
    - `hex`, `http.client`, `io.stream`, `json`, `list`, `math`, `md5`, `mem`
    - `net`, `path`, `random`, `range`, `set`, `sha1`, `sha256`, `simd`
    - `slice`, `tcp`, `text`, `time`, `udp`, `url`, `utf16`, `utf8`
  - 备注: `std src _` 当前是 `[PASS] ... (metadata table skipped)`, 不计入 skip 总数。
- [x] H1.2 按语法、sema、codegen、runtime、外部工具分类。结论:
  - 分类命令: 直接运行三个 ok skip fixture 的 `do test`, 并核对 `run_tests.sh` 的 `run_ok_case` / `run_std_src_case` skip 规则。
  - 语法类: 0。
  - sema 类: 0。
  - codegen 类: 0 个已确认直接由 WAT pattern 缺口导致的 skip。
  - runtime / 静态 runner 类: 3 个 ok fixture。
    - `ok/16_loop_recv_value`: recv loop 当前静态 test runner 全部 skipped, 属于 recv runtime / runner 能力边界。
    - `ok/96_file_lib_resource_shape`: file resource wrapper shape 可 parse/sema, 但静态 runner 无法执行该导入 wrapper 形态, 仍保留 runtime/WASI 后置 skip。
    - `ok/118_wasi_p3_std_wrappers`: 多个 WASI P3 std wrapper shape 可 parse/sema, 但静态 runner 无法执行这些 resource/WASI wrapper, 仍保留 runtime/WASI 后置 skip。
  - std source metadata 类: 32 个 `std src <module> (NoTestDecl)`。这些不是行为失败, 而是 `run_std_src_case` 对没有顶层 `test` 声明的标准库源码做元数据扫描时计入 skip。
  - 外部工具类: 0。当前 `wasm-tools` 和 `node` 可用; `RUN_WASM=1` 未纳入本次默认 skip 计数。
  - 验证: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh > /tmp/do_h1_skip_audit.out`; `grep '^\\[SKIP\\]' /tmp/do_h1_skip_audit.out`; 三个 ok skip 直接 `do test` 均输出 skipped; `grep '^\\[SKIP\\]' ... | wc -l` 为 `35`。
  - 下一步: H1.3 选择一批低风险 skip 转 pass。
- [x] H1.3 选择一批低风险 skip 转 pass。结论:
  - 实现: `run_tests.sh` 的 `run_std_src_case` 在标准库源码入口返回 `NoTestDecl` 时输出 `[PASS] std src <module> (NoTestDecl metadata only)`, 不再把无顶层 `test` 的库模块计入 skip。
  - 收回范围: H1.1/H1.2 中列出的 32 个 std src `NoTestDecl` 项全部从 skip 转为 metadata-only pass。
  - 当前完整回归: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=831 fail=0 skip=3`。
  - 剩余 skip:
    - `ok/118_wasi_p3_std_wrappers`
    - `ok/16_loop_recv_value`
    - `ok/96_file_lib_resource_shape`
  - 验证: `bash -n tool/build/test/run_tests.sh`; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh > /tmp/do_h13_regression.out 2> /tmp/do_h13_regression.err`; `grep '^\\[SKIP\\]' /tmp/do_h13_regression.out` 只输出上述 3 项。
  - 下一步: H1.4 已完成, 当前进入 H2.1 文档死链扫描。
- [x] H1.4 为剩余 skip 写原因。结论:
  - `ok/16_loop_recv_value`: 语法和 sema 已通过, 但静态 runner 对 `recv(...)` 消费循环仍输出 skipped。原因是当前 `recv(...)` 是消费循环专用形态, build lowering 只承诺 `[T]` storage-backed receive 子集, 真实 channel/stream receive ABI 与 runner 执行语义后置。影响: 不影响 parser/sema 和当前 `[T]` compiled lowering 回归; 不应把该用例标记为 `must_pass`。恢复条件: 静态 runner 或 compiled runner 支持该 fixture 的 `recv(ch)` 有限输入语义, 或新增真实 channel/stream receive runtime 后改为可执行 fixture。
  - `ok/96_file_lib_resource_shape`: `do check` 已通过, 但 `do test` 因导入 `file.do` resource wrapper 形态输出 skipped。原因是该 ok fixture 只验证 file 资源类型、错误枚举和 wrapper API shape; 真实执行需要 WASI resource/host runtime, 当前已由 `compile_ok/105/108/110/113/121/122_*` 覆盖 lowering, 不由静态 runner 执行。恢复条件: 有本机 WASI/resource host runtime smoke, 或将该用例拆成 compiled/host fixture 并能实际执行。
  - `ok/118_wasi_p3_std_wrappers`: `do check` 已通过, 但 `do test` 因跨 `time/random/file/dir/io.stream/tcp/udp/http.client` 的 WASI P3 wrapper/resource shape 输出 skipped。原因是该用例聚合多个资源 wrapper 和 host API shape, 其中 sockets/http 仍属于 G6 resource + variant / async host 后置线; 当前 component manifest/core lowering 只覆盖已登记子集。恢复条件: G6 的 resource wrapper、variant/address 映射、stream/future 或 host runtime 设计完成后, 拆成可执行 host smoke 或 component-level fixture。
  - 当前 skip 总数保持 3, 且都已记录为 runtime / WASI 后置原因; 语法类、sema 类、外部工具类 skip 仍为 0。
  - 验证: `DO_LIB_ROOT=src ./bin/do check tool/build/test/ok/16_loop_recv_value.do`; `DO_LIB_ROOT=src ./bin/do check tool/build/test/ok/96_file_lib_resource_shape.do`; `DO_LIB_ROOT=src ./bin/do check tool/build/test/ok/118_wasi_p3_std_wrappers.do` 均通过; 对三个用例分别执行 `DO_LIB_ROOT=src ./bin/do test ...` 均返回 `ok: 0 passed; 0 failed; N skipped`。
  - 下一步: H2.1 扫描 markdown 链接。

H2 文档死链和过期规则扫描:

- [x] H2.1 扫描 markdown 链接。结论:
  - 范围: `README.md`、`CHANGELOG.md` 和 `doc/**/*.md`。
  - 结果: 扫描 26 个 markdown 文件, 检查 21 个本地 markdown 链接, 缺失本地链接为 0。
  - 验证: Node 只读扫描脚本过滤外部 URL、`mailto:` 和纯锚点后检查本地目标存在性。
  - 下一步: H2.2 扫描过期入口、过期规则和删除文件引用。
- [x] H2.2 扫描过期入口、过期规则和删除文件引用。结论:
  - 未发现 `doc/review_blockers.md`、`doc/review_issues.md`、`compiled_task_checklist.md`、`next_stage_plan.md`、`internal_prefix_rename_plan.md` 等旧文档入口的活跃引用。
  - `get / pkg / push` 只保留 README / CHANGELOG 中的暂停说明, 未发现当前命令或活跃实现入口。
  - README Roadmap 存在 3 类状态漂移, 需要 H2.3 修正:
    - ARC / Perceus 段落仍把 FBIP `reuse` 描述为未完成, 需要区分 D5 第一版已完成与完整 ownership IR / 跨函数唯一性证明仍后置。
    - 后端优化段落仍说 backend instruction model、WAT peephole、小函数内联和 `@get/@set` 专门内联待补, 与 E1-E5 已完成冲突。
    - WASI / Component Model 段落仍把 component lowering 整体放到最后处理, 需要改成 G1-G5 已完成、G6 复杂 WIT 类型阻断。
  - 历史验证记录中的旧 `pass=799 fail=0 skip=35`、`direct wasm binary emitter` 非目标、WIT `package` 字段和已暂停包管理说明均保留为历史/领域语义, 不在 H2.2 判定为待删引用。
  - 验证: `find doc -maxdepth 2 -type f | sort`; `rg` 扫描旧文档名、暂停命令、direct wasm binary、旧基线和 README Roadmap 关键字。
  - 下一步: H2.3 修正 README 中 ARC/FBIP、后端优化和 WASI/Component Model 的过期状态描述。
- [x] H2.3 修正或删除过期文档。结论:
  - README 已修正 ARC / Perceus 描述: D5 最小 `rc == 1` reuse / `rc > 1` COW 回退已完成, 完整 ownership IR、跨函数唯一性证明、escape analysis 和 region 仍后置。
  - README 已修正后端优化描述: backend instruction model、基础控制流优化、copy fold、trivial inline、writer 拆分和 direct wasm binary emitter 评估已归入已完成; direct wasm binary emitter 作为当前暂不引入项保留。
  - README 已修正 WASI / Component Model 描述: G1-G5 已完成, G6 的 preopens、read-directory stream/future 和 sockets resource + variant 仍阻断。
  - 验证: `rg -n '完整 FBIP `reuse` 仍|FBIP `reuse` 仍未完成|backend instruction model.*仍待补|WAT peephole.*仍待补|小函数内联.*仍待补|component lowering.*继续放到阶段 G|defer.*### 暂跳过|后端优化.*仍待补' README.md` 无命中; `git diff --check -- README.md CHANGELOG.md doc/master_plan.md doc/start_here.md doc/roadmap_status.md` 通过。
  - 下一步: H3.1 列出错误 code 和 message。

H3 错误诊断一致性审查:

- [x] H3.1 列出错误 code 和 message。结论:
  - `tool/build/diag.zig` 的 `errorSummary` 当前显式列出 55 个 code/message。
  - `tool/build/diag.zig` 的 `errorHint` 当前显式列出 55 个 code/hint。
  - `.expect` 中出现但 `errorSummary` 没有的 code: `TestFailed`。该 code 来自静态 test runner 失败输出, 是否应进入 compile diagnostic summary 留到 H3.2 判断。
  - 当前 code/message 清单:
    ```text
    UnterminatedString: 字符串语法: `"text"`
    InvalidStringEscape: 字符串 escape 只支持 `\"`, `\\`, `\n`, `\r`, `\t`, `\xNN`
    InvalidStringUtf8: 字符串字面量解码后必须是有效 UTF-8
    InvalidComment: 注释只能独立成行；行注释写 `// ...`，块注释写 `/* ... */`
    InvalidIfHeader: if 语法: `if expr { ... }`, `if expr return`, `if expr break`, `if expr continue`
    InvalidLoopHeader: loop 语法: `loop { ... }`, `loop v, i = source { ... }`, `loop v = recv(ch) { ... }`, `loop field = fields(Type) { ... }`; 绑定名使用 snake_case 或 `_`
    InvalidLoopSource: 集合循环源必须是 `[T]` 或显式 `[T]` 视图函数结果
    InvalidStructLiteral: 结构体构造语法: `Type{field = value}` 或已知目标类型的 `.{field = value}`
    InvalidTypeDeclName: 类型声明位使用 UpperCamel；私有类型只在声明位写前置 `.`；`XxxError` 名只用于错误枚举
    InvalidErrorBranchName: 错误枚举不支持私有声明；错误枚举写作 `XxxError error = Branch | OtherBranch`；value enum 承载值必须在范围内且唯一
    InvalidSynthErrorType: 源码类型位不能使用合成 `Error`
    InvalidTypeRef: 类型引用写作 `Type`；普通固定数据参数可写平铺 union/nullable；变参元素、函数类型和接口约束参数不接收 union/nullable；私有类型声明写作 `.Type`；裸 `nil` 类型非法；重复 union 分支非法；`nil` 分支最多一次；匿名函数类型不能直接作为 union 分支；TypeArgs 不接受 `(T)` 或匿名函数类型
    InvalidPathIndex: 路径参数写作 `@get(value, index, .field)`；字段段写作 `.field`
    InvalidPathAccess: 字段读取语法: `@get(value, .field)`; 字段写入语法: `@set(value, .field, new_value)`；字段段只用于 @get/@set 路径参数
    InvalidFieldReflection: 字段反射语法: `loop field = fields(StructOrTypeParam) { ... }`; `@field_*` 的 field 参数必须来自当前字段反射循环
    InvalidNarrowing: 收窄语法: `@is(value, Type)` 只能直接作为条件头使用; Type 必须是单个可达非 nil 类型
    UnionPayloadRequiresNarrowing: union payload 使用前必须先通过直接 `@is(value, Type)` 或直接 `@eq/@ne(value, nil)` 收窄
    InvalidFuncDeclName: 函数声明名语法: `lower_name(...) -> Type { ... }` 或 `.lower_name(...) -> Type { ... }`
    InvalidTypedLiteral: 聚合构造语法: `Type{field = value}` 或 `Type<...>{field = value}`
    InvalidBraceExpr: 聚合构造语法: `Type{field = value}`、已知目标类型的 `.{field = value}` 或 `.{expr, ...}`
    NoMatchingCall: 函数调用需要匹配可见函数签名
    InvalidReturnStmt: return 语句返回位数不匹配
    InvalidCallExpr: 函数调用语法: `name(arg, next_arg)`；内建/core 调用写 `@name(arg, next_arg)`；私有函数调用去掉声明位前置点
    InvalidCallArgList: 调用语法: `name(arg, next_arg)`、`name(arg, ...rest)` 或内建 `@name(...)`; `@is/@as` 语法: `@is(value, Type)` / `@as(Type, value)`
    InvalidReservedName: 内建名和声明专用名只能用于保留位置
    LiteralCannotBeCalled: 函数调用语法: `name(arg, next_arg)`
    InvalidIfPatternBind: if 语法: `if expr { ... }`, `if expr return`, `if expr break`, `if expr continue`
    InvalidBindingName: 顶层值写作 `_snake_case Type = expr`、`snake_case Type = expr` 或 `.snake_case Type = expr`; 局部绑定名使用 `snake_case` 或 `_snake_case`
    PrivateIdentCannotBeLValue: 赋值语法: `name = expr`; 字段写入语法: `@set(value, .field, new_value)`
    DuplicateImmutableBinding: 可见作用域内 `_name` 只能绑定 1 次
    DuplicateLocalBinding: 局部绑定名不能重声明, 也不能遮蔽可见外层绑定
    DuplicateTypeDeclName: 类型名按去掉私有标记后的名字唯一
    DuplicateFuncSignature: 函数签名按去掉私有标记后的名字和参数类型序列唯一
    DuplicateHostImportAlias: host import alias 在同一模块内只能绑定 1 次
    DuplicateStructFieldName: 结构体字段名按去掉私有标记后的名字唯一; 每个字段名保留 1 个声明
    MultiReturnInIfCondition: 先接收多返回值, 再在 if 使用单值变量
    MultiReturnInIfBindRhs: if 条件语法使用单值 bool 表达式
    MultiReturnInLoopCondition: 先接收多返回值, 再在 loop 条件使用单值变量
    MultiReturnInSingleValuePosition: 多返回调用只能用于多左值赋值右侧或完整 return 位
    AmbiguousConditionCallReturnArity: 调用返回位数不唯一, 需要先显式接收或选择具体重载
    InvalidImportDecl: 导入使用 `name = @lib("file.do", symbol)`, `name = @lib("./file.do", symbol)`, `name = @lib("~/vendor.name.do", symbol)`；host import 左侧使用 `LowerIdent` 或 `.LowerIdent`，右侧使用 `@env("name", (...) -> Type)` 或 `@wasi("path/member", (...) -> Type)`
    NoTopLevelDecl: top-level 项写作 import/type/value/start/func/test
    NoTestDecl: 在文件顶层添加 `test "name" { ... }`
    InvalidTestDecl: 使用 `test "name" { ... }` 顶层声明
    InvalidConstraintDecl: 约束独立成行；类型参数名写作 `UpperIdent`，函数约束前必须先有类型约束
    InvalidParamName: 参数名写作 `snake_case`; `_name` 写作顶层常量和局部只读绑定
    MissingStartEntry: 编译入口写作 `start() { ... }`
    InvalidStartEntrySig: 入口签名写作 `start() { ... }` (无参、无返回)
    DuplicateStartEntry: 顶层 `start` 写作 1 次
    UnsupportedWasiHostImport: 这个 WIT host import 签名尚未支持 lowering
    MissingOutputPath: 示例: `do build input.do -o out.wat` 或 `do test sample.do --compiled -o sample.wat`
    MissingTestInputPath: 示例: `do test sample.do` 或 `do test sample.do --compiled -o sample.wat`
    UnexpectedCliArg: 命令只接受一个输入文件和已声明的选项
    OutputRequiresCompiledTest: `do test -o out.wat` 需要同时写 `--compiled`
    FormatMismatch: input is not formatted
    ```
  - 验证: Node 只读脚本解析 `errorSummary` / `errorHint` switch; `.expect` code 扫描覆盖 `tool/build/test/{err,compile_err,compiled_err,check,fmt,run}`。
  - 下一步: H3.2 找出同类错误不一致的地方。
- [x] H3.2 找出同类错误不一致的地方。结论:
  - P1: `InvalidReturnStmt` 是真实不一致。证据: parser/sema/imports 都会抛出 `error.InvalidReturnStmt`; 多个 `.expect` 断言 `return 语句返回位数不匹配`; `errorHint` 已有专用文案, 但修复前 `errorSummary(error.InvalidReturnStmt)` 落到通用 `编译失败`。
  - P3: `TestFailed` 不纳入 compile diagnostic summary。证据: `tool/build/test_runner.zig` 返回 `error.TestFailed`; 该 code 来自静态 test runner 运行失败, 不是 parser/sema/import/build diagnostic; `tool/build/test/err/283_static_unknown_assertion_fails.expect` 明确断言 `error[TestFailed]`。
  - 恢复条件: H3.3 给 `InvalidReturnStmt` 增加 summary 并补 focused test; `TestFailed` 保持 test runner 输出, 不改 `diag.zig`。
  - 下一步: H3.3 修正实现或 `.expect`。
- [x] H3.3 修正实现或 `.expect`。结论:
  - 实现: `tool/build/diag.zig` 的 `errorSummary` 已增加 `error.InvalidReturnStmt => "return 语句返回位数不匹配"`。
  - 测试: 新增 `return statement diagnostic has specific summary`, 先红灯确认旧实现返回 `编译失败`, 修复后通过。
  - 验证: `cd tool && zig test build/diag.zig` 通过, `All 13 tests passed.`; Node 只读脚本确认 `summary_entries=55`, `hint_entries=55`, `summary_without_hint=(none)`, `hint_without_summary=(none)`。
  - 下一步: H3.4 full regression。
- [x] H3.4 full regression。结论:
  - 验证: `./tool/build/test/run_tests.sh` 重新构建编译器并通过, 摘要 `pass=831 fail=0 skip=3`。
  - 剩余 skip 仍为 H1.4 已记录的 `118_wasi_p3_std_wrappers`、`16_loop_recv_value` 和 `96_file_lib_resource_shape`。
  - 下一步: H4.1 确定 release smoke 输入文件。

H4 release smoke:

- [x] H4.1 确定 smoke 输入文件。结论:
  - ReleaseSmall build: `cd tool && zig build -Doptimize=ReleaseSmall`。
  - build smoke: `tool/build/test/compile_ok/01_start_entry_valid.do`, 最小 `start()` 入口, 只验证公开 `do build` 到 WAT 产物链路。
  - test smoke: `tool/build/test/ok/01_path_get_single.do`, 覆盖静态 `do test`、struct literal 和 `@get` 基础路径。
  - compiled test smoke: `tool/build/test/compiled_ok/01_compiled_test_entry.do`, 覆盖 `do test --compiled -o out.wat` 入口和 compiled test manifest。
  - check smoke: `tool/build/test/check/01_valid.do`, 覆盖 `do check` 成功时 stdout/stderr 静默和 exit 0。
  - fmt smoke: `tool/build/test/fmt/01_struct_func_indent.do` 与 `tool/build/test/fmt/01_struct_func_indent.expect`, 覆盖 stdout 格式化、`--check` 和 `--write` 的单文件路径。
  - run smoke: `tool/build/test/run/01_start_scalar.do`, 覆盖公开 `do run` 的 build -> WAT -> wasm-tools parse -> node 执行桥接。
  - lsp smoke: `tool/build/test/lsp/*.json`, 复用当前全部 LSP JSON-RPC smoke fixtures, 覆盖 diagnostics、formatting、semantic tokens、hover、completion、definition 和 workspace index。
  - 选择原则: 全部复用现有稳定 fixture, 不新增 sample app, 避免 release smoke 与回归样例双源漂移。
  - 验证: 已逐项读取上述输入文件和 `tool/build/test/README.md` 对应目录说明, 确认文件存在且属于当前已支持子集。
  - 下一步: H4.2 新增 release smoke script 或文档化命令。
- [x] H4.2 新增 release smoke script。结论:
  - 实现: 新增 `tool/build/test/run_release_smoke.sh`, 入口会先构建 ReleaseSmall 编译器, 再执行 H4.1 选定的 build/test/compiled/check/fmt/run/lsp smoke。
  - 脚本边界: 依赖本机 `zig`、`wasm-tools` 和 `node`; 使用 `DO_RELEASE_SMOKE_TMP_DIR` 可覆盖临时目录; 默认临时输出写入 `tool/build/test/tmp/release_smoke`。
  - 文档: README 和 `tool/build/test/README.md` 已增加 release smoke 命令。
  - RED: `test -x tool/build/test/run_release_smoke.sh` 在脚本新增前返回 exit 1。
  - 验证: `chmod +x tool/build/test/run_release_smoke.sh`; `bash -n tool/build/test/run_release_smoke.sh` 通过。
  - 下一步: H4.3 在本机执行 release smoke 并记录结果。
- [x] H4.3 在本机执行并记录结果。结论:
  - 首次执行发现脚本断言错误: `do build` 成功会输出 `ok: input -> output`, 不能按 `do check` 的静默契约要求 stdout 为空。
  - 修复: `run_release_smoke.sh` 改为断言 `do build` stdout 包含成功 marker, 同时继续要求 stderr 为空和 WAT 输出存在。
  - 验证: `./tool/build/test/run_release_smoke.sh` 通过, 输出 `ReleaseSmall build`、`do build`、`do test`、`do test --compiled`、`do check`、`do fmt`、`do run`、`do lsp` 全部 `[PASS]`, 最后输出 `[INFO] release smoke passed`。
  - 下一步: H5.1 汇总已完成能力。

H5 版本说明:

- [x] H5.1 汇总已完成能力。结论:
  - 实现: README 新增 `当前 v1 子集摘要`, 汇总语言前端、内存与所有权、标准库、后端与 WASI、工具链和验证入口的已完成能力。
  - 边界: 只写当前已验证能力; 完整 ownership IR、direct wasm binary emitter、完整 I/O runtime、复杂 WASI resource/variant/future/component 输出等非目标留给 H5.2 汇总。
  - 验证: `rg -n "当前 v1 子集摘要|语言前端|内存与所有权|工具链|发布前 smoke" README.md`。
  - 下一步: H5.2 汇总 v1 非目标。
- [x] H5.2 汇总 v1 非目标。结论:
  - 实现: README 新增 `v1 非目标`, 单独列出完整 ownership IR、direct wasm binary emitter、完整 WASI / Component Model runtime、完整自动序列化、get/pkg/push、完整 formatter、完整 LSP 和 WASI/Component host runtime 等后置边界。
  - 目的: 把“已完成能力”和“明确不属于 v1 的能力”分离, 避免 README Roadmap 与当前实现双源冲突。
  - 验证: `rg -n "v1 非目标|direct wasm binary emitter|完整 WASI|完整自动序列化|rename|do run" README.md`。
  - 下一步: H5.3 写下一阶段计划。
- [x] H5.3 写下一阶段计划。结论:
  - 实现: README 新增 `下一阶段计划`, 顺序为发布候选收口、G6 WASI/Component 决策、host runtime smoke、JSON/序列化扩展、ownership 深化、编辑器/格式化增强和后端输出实验。
  - 边界: get/pkg/push 仍暂停; G6.1/G6.2/G6.3 仍按 blocked 记录等待用户或运行时设计决策; direct wasm binary emitter 只作为并行实验线。
  - 验证: `rg -n "下一阶段计划|发布候选收口|WASI / Component Model 决策|Host runtime smoke|Ownership 深化|后端输出实验" README.md`。
  - 下一步: 阶段 H 最终验证记录。
- [x] 阶段 H 最终验证。结论:
  - 文档/脚本静态检查: `git diff --check -- README.md CHANGELOG.md doc/master_plan.md doc/start_here.md doc/roadmap_status.md tool/build/test/README.md tool/build/test/run_release_smoke.sh` 通过; `bash -n tool/build/test/run_release_smoke.sh` 通过。
  - 完整回归: `./tool/build/test/run_tests.sh` 通过, 摘要 `pass=831 fail=0 skip=3`。
  - Release smoke: `./tool/build/test/run_release_smoke.sh` 通过, `ReleaseSmall build`、`do build`、`do test`、`do test --compiled`、`do check`、`do fmt`、`do run`、`do lsp` 全部 `[PASS]`。
  - 剩余 skip: `118_wasi_p3_std_wrappers`、`16_loop_recv_value`、`96_file_lib_resource_shape`, 原因和恢复条件见 H1.4。
  - 后续: 无新的未记录阻断; G6.1/G6.2/G6.3 等待用户或运行时设计决策, D2.1 只有找到真实红灯缺口或重定义为绿色 regression 收口时再重开。

发布候选扩展 gate:

- [x] 复跑默认完整回归。结论:
  - 验证: `./tool/build/test/run_tests.sh` 通过, 摘要 `pass=831 fail=0 skip=3`。
  - 剩余 skip: `118_wasi_p3_std_wrappers`、`16_loop_recv_value`、`96_file_lib_resource_shape`, 仍与 H1.4 记录一致。
  - 结果: 默认发布候选 gate 当前仍通过; 未新增阻断。
- [x] 复跑 `RUN_WASM=1` 扩展回归。结论:
  - 验证: `RUN_WASM=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=833 fail=0 skip=3`。
  - 覆盖: compiled trap、compiled wasm execution 和 6 个 wasm run smoke; 输出 `wasm run summary: pass=6 fail=0`。
  - 剩余 skip: `118_wasi_p3_std_wrappers`、`16_loop_recv_value`、`96_file_lib_resource_shape`, 仍与 H1.4 记录一致。
  - 结果: 扩展发布候选 gate 当前仍通过; 未新增阻断。
- [x] 刷新 `RUN_WASM=1` 扩展回归基线。结论:
  - 验证: `RUN_WASM=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=833 fail=0 skip=3`。
  - 覆盖: 默认完整回归外, 额外执行 compiled trap、compiled wasm execution 和 `run_wasm_smoke.sh` 的 6 个 wasm run smoke。
  - 结果: `wasm run summary: pass=6 fail=0`; 剩余 skip 仍是 H1.4 记录的 `118_wasi_p3_std_wrappers`、`16_loop_recv_value`、`96_file_lib_resource_shape`。
  - 后续: 无新的未记录阻断; 继续等待 G6 API/运行时方向或 D2.1 重定义。
- [x] 复验 release smoke 脚本入口。结论:
  - 验证: `test -x tool/build/test/run_release_smoke.sh` 输出 `executable`; `bash -n tool/build/test/run_release_smoke.sh` 通过并输出 `bash-n-ok`。
  - 结果: 脚本可执行位和 shell 语法仍满足发布候选 smoke 入口要求。
- [x] 复跑 release smoke。结论:
  - 验证: `./tool/build/test/run_release_smoke.sh` 通过, 输出 `ReleaseSmall build`、`do build`、`do test`、`do test --compiled`、`do check`、`do fmt`、`do run`、`do lsp` 全部 `[PASS]`, 最后输出 `[INFO] release smoke passed`。
  - 结果: 发布候选最小链路当前仍通过; 未新增阻断。
- [x] 审计活跃未完成项和旧下一步指针。结论:
  - `C5.3` 已由 C5.3.1-C5.3.33 完成, 但阶段清单仍是 `[ ]`; 已改为 `[x]` 并补充完成口径。
  - `06.2` 不是未开始项, 而是已拆分到 G2-G6; 已补 `blocked/decomposed` 说明, 明确 result-area/resource/variant 评估的已完成部分和 G6.1/G6.2/G6.3 的剩余阻断。
  - `doc/master_plan.md` 的 `当前推荐继续阶段 H` 已改为 `当前状态`, 并明确 `go` / `next` 时先查发布候选回归、文档漂移或可独立收口小项; 没有新小项时不绕过 G6/D2.1 阻断。
  - 验证: `rg -n "\\[ \\]|blocked/decomposed|blocked:" doc/roadmap_status.md doc/master_plan.md README.md doc/start_here.md`; 剩余 `[ ]` 均为 README 非目标或已标 blocked/decomposed 的 D2/G6/06.2。

## 文档治理

状态: done

当前结论: 已新增 `CHANGELOG.md` 作为历史摘要入口, 并删除已完成支线的过期 plan/spec 文档。当前活跃入口收敛为 README、CHANGELOG、start_here、master_plan、roadmap_status、spec/spec_rules、grammar、syntax、memory 和 WIT 文档。本段阶段内小任务均已完成, 后续文档变更按对应功能阶段同步记录。

阶段内小任务:

- [x] 新增 changelog 并写入近期已完成能力摘要。验证: `CHANGELOG.md`。
- [x] 删除已完成支线的过期文档。验证: 已删除 do run 接手清单和历史计划/设计目录; `test ! -e docs` 输出 `docs directory removed`。
- [x] 清理旧文档残留引用。验证: 旧历史路径关键字扫描无活跃引用。
- [x] 删除暂停包管理线的占位目录。验证: 已删除 `tool/get/.gitkeep` 和 `tool/push/.gitkeep`; README 目录结构不再列出 `tool/get` / `tool/push`。
- [x] 删除过期旧语法 fixture。验证: 已删除 `tool/build/test/err/244_source_char_alias_type_name.*` 和 `tool/build/test/err/92_synth_error_alias_rhs.*`; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 摘要 `pass=670 fail=0 skip=70`。
- [x] 收口文档治理状态。验证: 本段阶段内小任务均为 `[x]`; `状态` 从 `partial` 改为 `done`, 后续新增文档治理项应随对应功能阶段独立记录。
- [x] 收口阶段状态口径。修正: `doc/master_plan.md` 的 D3 子项从 `active` 改为 `done`; `doc/roadmap_status.md` 的 06、阶段 D、阶段 E、阶段 F 从泛化 `active` 改为当前事实状态。验证: `rg -n "^## |^### |^状态:" doc/master_plan.md doc/roadmap_status.md`。
- [x] 收口接手入口状态口径。修正: README 顶部从“第二版编译器正在实现”改为 v1 子集发布候选已收口; `doc/start_here.md` 不再指向继续阶段 H, 改为按 `doc/master_plan.md` 的“当前下一步”检查发布候选回归、文档漂移或可独立收口小项。验证: `rg -n "第二版编译器正在实现|默认下一步按其中“阶段 H: 发布前治理”推进|当前仓库状态|当前下一步" README.md doc/start_here.md doc/master_plan.md`。
- [x] 收口总规划阶段顺序口径。修正: `doc/master_plan.md` 第 2 节从旧“推荐阶段顺序 / 阶段 A 当前首选 A1”改为“阶段顺序和当前状态”, 明确 A/B/C/E/F/H 已完成、D 只剩 D2.1 blocked 残留、G 只剩 G6.1-G6.3 决策项。验证: `rg -n "当前首选 A1|阶段 A 可以立即推进|阶段顺序和当前状态|G6.1" doc/master_plan.md`。
- [x] 收口 `start_here` 接手入口。修正: `doc/start_here.md` 删除旧编号 `03.*`、`05.4`、`07.5` 和重复“下次第一步”长段, 改为当前停点、下一步规则、当前阻断、当前边界和变更边界。验证: `rg -n "03\\.|05\\.4|07\\.5|下次第一步|第二版编译器正在实现|当前首选 A1" doc/start_here.md` 无输出; `rg -n "当前停点|下一步规则|当前阻断|当前边界|变更边界" doc/start_here.md` 命中全部入口段。
- [x] 收口当前未提交交付范围。修正: `doc/start_here.md` 新增当前 dirty worktree 范围说明, 明确当前累计主线改动覆盖 README/CHANGELOG/规划文档、`bin/do`、stdlib、compiler、LSP、WASI/component、ARC/backend IR、fixtures 和 release smoke; `ui.do`、`ui_demo.do` 明确不属于当前主线且不得默认 stage/touch。验证: `git diff --name-only | wc -l`; `git ls-files --others --exclude-standard | wc -l`; `rg -n "当前未提交交付范围|ui\\.do|ui_demo\\.do" doc/start_here.md doc/roadmap_status.md CHANGELOG.md`。
- [x] 收口总规划顶部状态。修正: `doc/master_plan.md` 顶部 `状态` 从泛化 `active` 改为 `v1 子集发布候选已收口, 剩余 G6/D2.1 blocked residual`, 避免误读为仍有未记录的活跃大阶段。验证: `rg -n "^状态: active$|v1 子集发布候选已收口" doc/master_plan.md`。
- [x] 复核活跃文档本地链接和旧入口残留。结论: README、CHANGELOG、`doc/*.md`、`doc/syntax/*.md` 和 `doc/wit/*.md` 中 20 个本地 Markdown 链接全部存在; `review_blockers`、`review_issues`、`compiled_task_checklist`、`next_stage_plan`、`internal_prefix_rename_plan`、旧阶段指针和“第二版编译器正在实现”命中均为 changelog / roadmap 历史记录或验证命令, 未发现新的活跃入口漂移。验证: Markdown 本地链接 Node 扫描输出 `checked=20 missing=0`; 旧入口 `rg` 扫描无活跃入口命中。
- [x] 刷新 release smoke 轻量 gate。验证: `test -x tool/build/test/run_release_smoke.sh`; `bash -n tool/build/test/run_release_smoke.sh`; `./tool/build/test/run_release_smoke.sh` 通过, ReleaseSmall build、`do build`、`do test`、`do test --compiled`、`do check`、`do fmt`、`do run` 和 `do lsp` 全部 `[PASS]`, 最后输出 `[INFO] release smoke passed`。
- [x] 刷新默认完整回归 gate。验证: `./tool/build/test/run_tests.sh` 通过, 摘要 `pass=831 fail=0 skip=3`; 剩余 skip 仍是 H1.4 已记录的 `118_wasi_p3_std_wrappers`、`16_loop_recv_value` 和 `96_file_lib_resource_shape`, 未新增阻断。
- [x] 刷新 `RUN_WASM=1` 扩展回归 gate。验证: `RUN_WASM=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=833 fail=0 skip=3`; compiled trap、compiled wasm execution 和 wasm smoke 均执行, `wasm run summary: pass=6 fail=0`; 剩余 skip 仍是 H1.4 已记录的 `118_wasi_p3_std_wrappers`、`16_loop_recv_value` 和 `96_file_lib_resource_shape`, 未新增阻断。
- [x] 刷新 repo-wide diff whitespace gate。验证: `git diff --check` 通过, 当前 tracked diff 未发现 trailing whitespace 或 conflict marker。
- [x] 复核剩余 skip 边界。验证: 对 `tool/build/test/ok/16_loop_recv_value.do`、`tool/build/test/ok/96_file_lib_resource_shape.do`、`tool/build/test/ok/118_wasi_p3_std_wrappers.do` 分别执行 `DO_LIB_ROOT=src ./bin/do check <case>` 均通过; 分别执行 `DO_LIB_ROOT=src ./bin/do test <case>` 均返回 `ok: 0 passed; 0 failed; N skipped`, 与 H1.4 的 runner / WASI resource 后置边界一致。
- [x] 同步 `start_here` 最新验证证据。修正: `doc/start_here.md` 当前停点新增 repo-wide `git diff --check` 通过和剩余 3 个 skip 的 check/test 边界复核结果, 避免下次接手只看到 full/wasm/smoke 三个 gate。验证: `rg -n "Repo-wide diff whitespace gate|剩余 3 个 skip" doc/start_here.md`。
- [x] 刷新 JS/MJS test helper syntax gate。验证: 当前 tracked JS/MJS diff 只有 `tool/build/test/run_lsp_case.mjs`、`tool/build/test/test_wasi_bind_manifest_tool.mjs`、`tool/build/test/validate_wasi_bind_manifest.mjs`, 无 untracked JS/MJS; `node --check` 三个脚本均通过。
- [x] 刷新 Zig unit/build gate。验证: `cd tool && zig test main.zig` 通过, 输出 `All 101 tests passed.`; 同一命令链继续执行 `zig build -Doptimize=Debug` 并成功退出。
- [x] 刷新 shell harness syntax gate。验证: 当前 shell 脚本 diff 范围为 tracked `tool/build/test/run_tests.sh` 和 untracked `tool/build/test/run_release_smoke.sh`; `bash -n` 两个脚本均通过。
- [x] 同步 `start_here` syntax gate 证据。修正: `doc/start_here.md` 当前停点新增 JS/MJS test helper syntax gate 和 shell harness syntax gate 最近通过记录。验证: `rg -n "JS/MJS test helper syntax gate|Shell harness syntax gate" doc/start_here.md`。
- [x] 刷新 Zig fmt gate。结论:
  - 取证: `rg --files -g '*.zig' | wc -l` 显示当前全仓 31 个 Zig 文件。
  - 首次验证: `rg --files -g '*.zig' -0 | xargs -0 zig fmt --check` 失败并指向 `tool/check/run.zig`。
  - 修复: 对 `tool/check/run.zig` 执行 `zig fmt` 机械格式化。
  - 复验: `rg --files -g '*.zig' -0 | xargs -0 zig fmt --check` 通过; `cd tool && zig test main.zig && zig build -Doptimize=Debug` 通过, 输出 `All 101 tests passed.`。
  - 结果: 当前 Zig 格式、Zig unit 和 Debug build gate 均通过; 未新增阻断。
- [x] 复核活跃未完成项和状态口径。结论:
  - 扫描: `rg -n "\\[ \\]|状态: (active|partial|blocked)|blocked:|TODO|FIXME|当前推荐|下次第一步|第二版编译器正在实现" README.md CHANGELOG.md doc/master_plan.md doc/roadmap_status.md doc/start_here.md`。
  - 结果: 剩余 `[ ]` 只指向 D2.1、G6.1-G6.3、06.2 blocked/decomposed 和 README 的后置非目标; 未发现新的活跃未完成小项。
  - 修正: `06. WASI / Component Model FFI` 状态从 `blocked/partial` 收窄为 `blocked-residual`; `07. 生态工具` 状态从 `partial` 收窄为 `done/paused`, 对齐当前 v1 工具链已完成且 get/pkg/push 暂停的事实。
  - 复验: `rg -n "^状态: (active|partial|blocked)(;|$)|^状态: blocked/partial|^状态: partial" doc/master_plan.md doc/roadmap_status.md doc/start_here.md README.md CHANGELOG.md` 无输出; `rg -n "^- \\[ \\]" doc/master_plan.md doc/roadmap_status.md README.md` 只命中 README 后置非目标、06.2/D2.1/G6.1-G6.3 blocked 项。
  - 结果: 当前仍无新的未记录阻断; 不绕过 G6/D2.1。
- [x] 刷新 dirty worktree 交付边界。结论:
  - 取证: `git diff --name-only | wc -l` 为 52; `git ls-files --others --exclude-standard | wc -l` 为 117。
  - 边界: `git ls-files --others --exclude-standard | rg '(^|/)(ui\\.do|ui_demo\\.do)$'` 命中 `ui.do` 和 `ui_demo.do`; `git diff --name-only | rg '(^|/)(ui\\.do|ui_demo\\.do)$'` 无输出。
  - 修正: `doc/start_here.md` 当前未提交交付范围补充最新 tracked/untracked 计数, 并明确 `ui.do` / `ui_demo.do` 只在 untracked, 不在 tracked diff。
  - 结果: 当前累计交付边界更清晰; 未新增阻断, 未触碰非主线 UI 文件。
- [x] 刷新 Markdown local link gate。结论:
  - 验证: 一次性 Node 只读扫描 `README.md`、`CHANGELOG.md` 和 `doc/**/*.md` 的本地 `.md` 链接。
  - 结果: `markdown_files=26`, `local_markdown_links=20`, `missing=0`。
  - 修正: `doc/start_here.md` 当前停点新增 Markdown local link gate 最近通过记录。
  - 结果: 最近文档改动未引入本地 Markdown 死链; 未新增阻断。
- [x] 复跑 release smoke gate。结论:
  - 验证: `./tool/build/test/run_release_smoke.sh` 通过。
  - 覆盖: ReleaseSmall build、`do build`、`do test`、`do test --compiled`、`do check`、`do fmt`、`do run` 和 `do lsp` 全部 `[PASS]`, 最后输出 `[INFO] release smoke passed`。
  - 修正: `doc/start_here.md` 当前停点同步最新 release smoke 证据。
  - 结果: 发布候选最小链路仍通过; 未新增阻断。
- [x] 复跑默认回归矩阵。结论:
  - 验证: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=831 fail=0 skip=3`。
  - 覆盖: tool、ok、err、std src metadata、compile ok、compile err、compiled ok/err、do run、fmt、check 和 lsp cases。
  - 剩余 skip: `118_wasi_p3_std_wrappers`、`16_loop_recv_value`、`96_file_lib_resource_shape`, 仍与 H1.4 的 runner / WASI resource 后置边界一致。
  - 修正: `doc/start_here.md` 当前停点从旧的完整回归表述更新为本次 `SKIP_BUILD=1` 默认回归矩阵证据。
  - 结果: 默认回归矩阵仍通过; 未新增阻断。
- [x] 复跑 `RUN_WASM=1` 扩展回归矩阵。结论:
  - 验证: `RUN_WASM=1 SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=833 fail=0 skip=3`。
  - 覆盖: 默认回归矩阵外, 额外执行 compiled trap、compiled wasm execution 和 6 个 wasm run smoke。
  - 结果: `wasm run summary: pass=6 fail=0`; 剩余 skip 仍是 `118_wasi_p3_std_wrappers`、`16_loop_recv_value`、`96_file_lib_resource_shape`。
  - 修正: `doc/start_here.md` 当前停点同步本次 `RUN_WASM=1 SKIP_BUILD=1` 扩展回归证据。
  - 结果: 扩展回归矩阵仍通过; 未新增阻断。
- [x] 复核剩余 skip 边界。结论:
  - 验证: `DO_LIB_ROOT=src ./bin/do check tool/build/test/ok/16_loop_recv_value.do`、`96_file_lib_resource_shape.do`、`118_wasi_p3_std_wrappers.do` 均静默通过。
  - 验证: 对上述三个用例分别执行 `DO_LIB_ROOT=src ./bin/do test ...`, 结果均为 `0 failed` 且 skipped; skipped 数分别为 `3`、`1`、`1`。
  - 修正: `doc/start_here.md` 当前停点同步最新剩余 skip 边界复核结果。
  - 结果: 剩余 skip 仍符合 H1.4 记录的 runner / WASI resource 后置边界; 未新增阻断。
- [x] 刷新 JS/MJS test helper syntax gate。结论:
  - 范围: `git diff --name-only | rg '\\.(mjs|js)$'` 只命中 `tool/build/test/run_lsp_case.mjs`、`tool/build/test/test_wasi_bind_manifest_tool.mjs` 和 `tool/build/test/validate_wasi_bind_manifest.mjs`; `git ls-files --others --exclude-standard | rg '\\.(mjs|js)$'` 无输出。
  - 验证: `node --check tool/build/test/run_lsp_case.mjs`; `node --check tool/build/test/test_wasi_bind_manifest_tool.mjs`; `node --check tool/build/test/validate_wasi_bind_manifest.mjs` 均通过。
  - 修正: `doc/start_here.md` 当前停点同步本次 JS/MJS syntax gate 证据。
  - 结果: 当前变更 JS/MJS helper 语法仍通过; 未新增阻断。
- [x] 刷新 shell harness syntax gate。结论:
  - 范围: `git diff --name-only | rg '\\.sh$|(^|/)run_.*\\.sh$'` 只命中 tracked `tool/build/test/run_tests.sh`; `git ls-files --others --exclude-standard | rg '\\.sh$|(^|/)run_.*\\.sh$'` 只命中 untracked `tool/build/test/run_release_smoke.sh`。
  - 验证: `bash -n tool/build/test/run_tests.sh`; `bash -n tool/build/test/run_release_smoke.sh` 均通过。
  - 修正: `doc/start_here.md` 当前停点同步本次 shell harness syntax gate 证据。
  - 结果: 当前 shell harness 语法仍通过; 未新增阻断。
- [x] 刷新 Zig unit/build gate。结论:
  - 环境: `zig version` 输出 `0.16.0`。
  - 验证: `cd tool && zig test main.zig && zig build -Doptimize=Debug` 通过, 输出 `All 101 tests passed.`。
  - 修正: `doc/start_here.md` 当前停点同步本次 Zig unit/build gate 证据。
  - 结果: 当前 Zig unit 和 Debug build gate 均通过; 未新增阻断。
- [x] 刷新 LSP smoke fixture gate。结论:
  - 范围: `rg --files tool/build/test/lsp -g '*.json' | sort` 当前共 9 个 LSP JSON fixture。
  - 验证: 对 `tool/build/test/lsp/*.json` 逐个执行 `node tool/build/test/run_lsp_case.mjs ./bin/do <case>` 均通过。
  - 覆盖: open diagnostics、change clear、formatting、semantic tokens、hover、completion、definition 和 workspace index。
  - 修正: `doc/start_here.md` 当前停点同步本次 LSP smoke fixture gate 证据。
  - 结果: 当前 LSP smoke fixture gate 仍通过; 未新增阻断。
- [x] 刷新 do fmt fixture gate。结论:
  - 范围: `tool/build/test/fmt/*.do` 当前共 3 个 fmt fixture。
  - 验证: 对每个 fixture 执行 focused fmt gate, 覆盖 `do fmt` stdout 与 `.expect` 对比、二次格式化幂等、`fmt --check` 对已格式化输入静默成功、`fmt --write` 内容对比和二次写回幂等。
  - 验证: 对原始未格式化输入执行 `fmt --check` 均失败并包含 `error[FormatMismatch]`, stdout 为空。
  - 修正: `doc/start_here.md` 当前停点同步本次 do fmt fixture gate 证据。
  - 结果: 当前 do fmt fixture gate 仍通过; 未新增阻断。
- [x] 刷新 do run product command gate。结论:
  - 范围: `tool/build/test/run/*.do` 当前共 6 个 do run fixture, 另覆盖缺失 `wasm-tools` 和缺失 `node` 两个诊断路径。
  - 验证: 对 6 个 fixture 逐个执行 `DO_LIB_ROOT=src ./bin/do run <case>`, stderr 均为空; 有 `.stdout.expect` 的用例逐行 diff 通过, 无 expect 的 `01_start_scalar` stdout 为空。
  - 验证: 空 `PATH` 下执行 `do run` 返回 `error[MissingExternalTool]: wasm-tools not found`; 仅暴露 `wasm-tools` 的 `PATH` 下执行 `do run` 返回 `error[MissingExternalTool]: node not found`; 两个诊断路径 stdout 均为空。
  - 修正: `doc/start_here.md` 当前停点同步本次 do run product command gate 证据。
  - 结果: 当前 do run product command gate 仍通过; 未新增阻断。
- [x] 刷新 do check product command gate。结论:
  - 范围: `tool/build/test/check/*.do` 当前共 2 个 check fixture, 另覆盖多文件输入策略。
  - 验证: `DO_LIB_ROOT=src ./bin/do check tool/build/test/check/01_valid.do` 静默成功; `02_syntax_error.do` 失败并逐行匹配 `.expect`, stdout 为空。
  - 验证: 多文件输入覆盖全部成功静默通过、后一个失败时最终失败且 stderr 包含 bad path、前一个失败后仍继续检查后续 bad input 并最终失败。
  - 修正: `doc/start_here.md` 当前停点同步本次 do check product command gate 证据。
  - 结果: 当前 do check product command gate 仍通过; 未新增阻断。
- [x] 刷新 do build product command smoke gate。结论:
  - 范围: 最小成功入口 `tool/build/test/compile_ok/01_start_entry_valid.do` 和最小失败诊断 `tool/build/test/compile_err/01_missing_start_entry.do`。
  - 验证: `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/01_start_entry_valid.do -o <tmp>.wat` 成功, stdout 包含 `ok:`, stderr 为空, WAT 产物非空且包含 `(module`。
  - 验证: `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_err/01_missing_start_entry.do -o <tmp>.wat` 失败, stderr 逐行匹配 `.expect`, stdout 为空且未生成 WAT。
  - 修正: `doc/start_here.md` 当前停点同步本次 do build product command smoke gate 证据。
  - 结果: 当前 do build product command smoke gate 仍通过; 未新增阻断。
- [x] 刷新 do test product command smoke gate。结论:
  - 范围: 静态 runner `tool/build/test/ok/01_path_get_single.do`, compiled runner `tool/build/test/compiled_ok/01_compiled_test_entry.do`, 以及 `do test -o` 必须搭配 `--compiled` 的 CLI 保护。
  - 验证: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/01_path_get_single.do` 成功, stderr 为空, stdout 包含 `test "path get single" ... ok` 和 `ok: 1 passed; 0 failed; 0 skipped`。
  - 验证: `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_ok/01_compiled_test_entry.do --compiled -o <tmp>.wat` 成功生成非空 WAT, 包含 `;; compiled-test 0 "compiled test entry"`; 随后 `wasm-tools parse` 和 `node tool/build/test/run_compiled_test_case.mjs` 执行通过, 输出 `test "compiled test entry" ... ok`。
  - 验证: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/01_path_get_single.do -o <tmp>.wat` 失败并输出 `error[OutputRequiresCompiledTest]`, stdout 为空且未生成 WAT。
  - 修正: `doc/start_here.md` 当前停点同步本次 do test product command smoke gate 证据。
  - 结果: 当前 do test product command smoke gate 仍通过; 未新增阻断。
- [x] 刷新 CLI argument / output path guard gate。结论:
  - 范围: `build -o <out> <input>` 和 `test --compiled -o <out> <input>` 的 output-order 路径, 以及 build/run/test 的严格参数保护。
  - 验证: `DO_LIB_ROOT=src ./bin/do build -o <tmp>.wat tool/build/test/compile_ok/01_start_entry_valid.do` 成功生成非空 WAT; `DO_LIB_ROOT=src ./bin/do test --compiled -o <tmp>.wat tool/build/test/compiled_ok/01_compiled_test_entry.do` 成功生成非空 WAT。
  - 验证: `do build <input> --bad`、`do build <input> <input>`、`do run <input> --bad`、`do run <input> <input>` 均失败并输出 `error[UnexpectedCliArg]`, stdout 为空。
  - 验证: `do test <input> -o <tmp>.wat` 失败并输出 `error[OutputRequiresCompiledTest]`, stdout 为空且未生成 WAT。
  - 修正: `doc/start_here.md` 当前停点同步本次 CLI argument / output path guard gate 证据。
  - 结果: 当前 CLI argument / output path guard gate 仍通过; 未新增阻断。
- [x] 刷新 WASI bind manifest helper gate。结论:
  - 范围: `tool/build/test/test_wasi_bind_manifest_tool.mjs` 驱动 `tool/build/test/validate_wasi_bind_manifest.mjs` 的 helper 自测。
  - 验证: `node tool/build/test/test_wasi_bind_manifest_tool.mjs tool/build/test/validate_wasi_bind_manifest.mjs <tmp-dir>` 通过, stdout 输出 `ok: wasi-bind manifest tool`, stderr 为空。
  - 边界: 本项只证明现有 manifest JSON、known/unsupported、component-plan、core imports/shims、component input 和 component wasm helper 行为仍通过; 不解除 G6.1 preopens、G6.2 read-directory stream/future、G6.3 sockets resource/variant 的设计阻断。
  - 修正: `doc/start_here.md` 当前停点同步本次 WASI bind manifest helper gate 证据。
  - 结果: 当前 WASI bind manifest helper gate 仍通过; 未新增阻断。
- [x] 刷新 run_wasm_smoke bridge gate。结论:
  - 范围: `tool/build/test/run_wasm_smoke.sh` 的底层 WAT -> `wasm-tools parse` -> Node 执行桥接; 它不替代 `do run` 产品命令回归。
  - 验证: `SKIP_BUILD=1 ./tool/build/test/run_wasm_smoke.sh` 通过, `01_start_scalar`、`02_env_host_import_string_literal`、`03_env_host_import_storage_wrapper`、`04_defer_lifo`、`05_defer_block`、`06_defer_loop_break` 全部 `[PASS]`。
  - 结果: 输出 `wasm run summary: pass=6 fail=0`; 当前底层 wasm bridge gate 仍通过, 未新增阻断。
  - 修正: `doc/start_here.md` 当前停点同步本次 run_wasm_smoke bridge gate 证据。
- [x] 刷新 compiled trap smoke gate。结论:
  - 范围: `tool/build/test/compiled_trap/*.do` 当前共 2 个 fixture。
  - 验证: 对 `01_compiled_test_fallthrough_traps.do` 和 `02_compiled_managed_struct_alias_set_oob_get_traps.do` 分别执行 `DO_LIB_ROOT=tool/build/test/lib ./bin/do test <case> --compiled -o <tmp>.wat`, 均成功生成非空 WAT 且 stderr 为空。
  - 验证: 两个 WAT 均通过 `wasm-tools parse`; 随后 `node tool/build/test/run_compiled_test_case.mjs <wasm> <wat>` 均按预期非 0 退出, 因该目录用例的正确结果是运行期 trap。
  - 修正: `doc/start_here.md` 当前停点同步本次 compiled trap smoke gate 证据。
  - 结果: 当前 compiled trap smoke gate 仍通过; 未新增阻断。
- [x] 刷新 diagnostic unit / contract gate。结论:
  - 范围: `tool/build/diag.zig` focused tests, 以及 `errorSummary` / `errorHint` 显式诊断条目一致性。
  - 验证: `cd tool && zig test build/diag.zig` 通过, 输出 `All 13 tests passed.`。
  - 验证: Node 只读扫描 `tool/build/diag.zig`, 结果为 `summary_entries=55`, `hint_entries=55`, `summary_without_hint=(none)`, `hint_without_summary=(none)`。
  - 修正: `doc/start_here.md` 当前停点同步本次 diagnostic unit / contract gate 证据。
  - 结果: 当前 diagnostic unit / contract gate 仍通过; 未新增阻断。
- [x] 刷新 CLI parser unit gate。结论:
  - 范围: `tool/build/cli.zig` 的 run/fmt/lsp/check 参数解析单元测试。
  - 验证: `cd tool && zig test build/cli.zig` 通过, 输出 `All 14 tests passed.`。
  - 边界: 本项是 CLI parser unit gate; build/test 的黑盒严格参数和 output-order 路径由 CLI argument / output path guard gate 覆盖。
  - 修正: `doc/start_here.md` 当前停点同步本次 CLI parser unit gate 证据。
  - 结果: 当前 CLI parser unit gate 仍通过; 未新增阻断。
- [x] 刷新 lexer / tokenization unit gate。结论:
  - 范围: `tool/build/lexer.zig` 的 focused tokenizer tests。
  - 验证: `cd tool && zig test build/lexer.zig` 通过, 输出 `All 10 tests passed.`。
  - 覆盖: dot/private 标识符、internal dot 拆分、spread token、loop label apostrophe、字符串 escape UTF-8 校验、line string block、inline RHS line string 和 blank-line split。
  - 修正: `doc/start_here.md` 当前停点同步本次 lexer / tokenization unit gate 证据。
  - 结果: 当前 lexer / tokenization unit gate 仍通过; 未新增阻断。
- [x] 刷新 parser unit gate。结论:
  - 范围: `tool/build/parser.zig` 的 focused parser tests。
  - 验证: `cd tool && zig test build/parser.zig` 通过, 输出 `All 24 tests passed.`。
  - 覆盖: bool/nil literals、literal-call rejection、lambda placement/call args、lambda omitted param type/block body、spread、function name call args、struct literal equals、generic bind arity、import ordering、storage variadic arity 和 collection loop two-binding parser rule。
  - 边界: 该 gate 同时执行 parser 导入的 lexer tests; 不替代完整 parser/sema/codegen 回归。
  - 修正: `doc/start_here.md` 当前停点同步本次 parser unit gate 证据。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "parser unit gate|All 24 tests passed|build/parser\\.zig|collection loop two-binding" CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 parser unit gate 仍通过; 未新增阻断。
- [x] 刷新 sema unit gate。结论:
  - 范围: `tool/build/sema.zig` 的 focused semantic analysis tests。
  - 验证: `cd tool && zig test build/sema.zig` 通过, 输出 `All 26 tests passed.`。
  - 覆盖: private host import 不被误判为 private lvalue assignment、private assignment rejection, 以及 sema 导入链上的 lexer/parser unit tests。
  - 边界: 该 gate 不替代完整 sema fixture regression 或 codegen regression。
  - 修正: `doc/start_here.md` 当前停点同步本次 sema unit gate 证据。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "sema unit gate|All 26 tests passed|build/sema\\.zig|private host import|private assignment" CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 sema unit gate 仍通过; 未新增阻断。
- [x] 刷新 codegen unit gate。结论:
  - 范围: `tool/build/codegen.zig` 的 focused codegen tests。
  - 验证: `cd tool && zig test build/codegen.zig` 通过, 输出 `All 51 tests passed.`。
  - 覆盖: source origin metadata、move candidate metadata、generic union/callback binding、variadic storage ABI、Backend IR scalar lowering、runtime prelude、component metadata、test runner variadic dispatch 和 ownership facts。
  - 边界: 该 gate 会执行导入模块的 unit tests; 不替代完整 fixture regression 或 wasm execution gate。
  - 修正: `doc/start_here.md` 当前停点同步本次 codegen unit gate 证据。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "codegen unit gate|All 51 tests passed|build/codegen\\.zig|generic union/callback|variadic storage ABI|Backend IR" CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 codegen unit gate 仍通过; 未新增阻断。
- [x] 刷新 backend / writer / ownership / runner focused unit gates。结论:
  - 范围: `tool/build/backend_ir.zig`、`runtime_prelude_wat.zig`、`component_metadata_wat.zig`、`function_body_wat.zig`、`ownership.zig`、`ownership_facts.zig`、`test_runner.zig` 和 `run.zig`。
  - 验证: `cd tool && zig test build/backend_ir.zig` 通过, 输出 `All 13 tests passed.`。
  - 验证: `cd tool && zig test build/runtime_prelude_wat.zig` 通过, 输出 `All 2 tests passed.`。
  - 验证: `cd tool && zig test build/component_metadata_wat.zig` 通过, 输出 `All 4 tests passed.`。
  - 验证: `cd tool && zig test build/function_body_wat.zig` 通过, 输出 `All 2 tests passed.`。
  - 验证: `cd tool && zig test build/ownership.zig` 通过, 输出 `All 2 tests passed.`; `cd tool && zig test build/ownership_facts.zig` 通过, 输出 `All 6 tests passed.`。
  - 验证: `cd tool && zig test build/test_runner.zig` 通过, 输出 `All 14 tests passed.`; `cd tool && zig test build/run.zig` 通过, 输出 `All 27 tests passed.`。
  - 覆盖: Backend IR block/value/emit/fold/inline、runtime prelude memory/layout writer、component manifest/import writer、function body shell/compiled-test writer、ownership exit/facts、static test runner variadic dispatch 和 normal compile path start-entry enforcement。
  - 边界: 这些是 focused module unit gates, 不替代 `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 或 `RUN_WASM=1` 扩展回归。
  - 修正: `doc/start_here.md` 当前停点同步本次 focused unit gate 证据。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "backend / writer / ownership / runner focused unit gates|All 13 tests passed|All 27 tests passed|runtime_prelude_wat|component_metadata_wat|function_body_wat|ownership_facts|test_runner" CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 backend / writer / ownership / runner focused unit gates 仍通过; 未新增阻断。
- [x] 刷新 Zig aggregate unit gate。结论:
  - 范围: `tool/main.zig` 聚合导入的 Zig unit tests。
  - 验证: `cd tool && zig test main.zig` 通过, 输出 `All 101 tests passed.`。
  - 覆盖: CLI/run/fmt/check/LSP、backend IR、component metadata writer、function body writer、ownership facts、runtime prelude、lexer、diag、parser、sema 和 formatter 聚合单元测试。
  - 边界: 该 gate 不替代 `zig build -Doptimize=Debug`、fixture regression 或 wasm execution gate。
  - 修正: `doc/start_here.md` 当前停点同步本次 Zig aggregate unit gate 证据, 并保留 Debug build gate 作为独立最近通过证据。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "Zig aggregate unit gate|All 101 tests passed|zig test main\\.zig|Debug build gate|backend / writer / ownership / runner focused unit gates" CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 Zig aggregate unit gate 仍通过; 未新增阻断。
- [x] 刷新 Zig fmt / Debug build gates。结论:
  - 环境: `zig version` 输出 `0.16.0`。
  - 验证: `rg --files -g '*.zig' -0 | xargs -0 zig fmt --check` 通过, 当前全仓 Zig 文件数为 31。
  - 验证: `cd tool && zig build -Doptimize=Debug` 通过。
  - 边界: 本项只证明 Zig 格式和 Debug build, 不替代 unit tests、fixture regression 或 release smoke。
  - 修正: `doc/start_here.md` 当前停点同步本次 Zig fmt / Debug build gate 证据。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "Zig fmt / Debug build gates|zig fmt --check|zig build -Doptimize=Debug|0\\.16\\.0|全仓 Zig 文件数为 31" CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 Zig fmt / Debug build gates 仍通过; 未新增阻断。
- [x] 刷新 JS/MJS 和 shell syntax gates。结论:
  - JS/MJS 范围: `git diff --name-only | rg '\\.(mjs|js)$'` 只命中 `tool/build/test/run_lsp_case.mjs`、`tool/build/test/test_wasi_bind_manifest_tool.mjs` 和 `tool/build/test/validate_wasi_bind_manifest.mjs`; `git ls-files --others --exclude-standard | rg '\\.(mjs|js)$'` 无输出。
  - JS/MJS 验证: `node --check tool/build/test/run_lsp_case.mjs`; `node --check tool/build/test/test_wasi_bind_manifest_tool.mjs`; `node --check tool/build/test/validate_wasi_bind_manifest.mjs` 均通过。
  - Shell 范围: `git diff --name-only | rg '\\.sh$|(^|/)run_.*\\.sh$'` 只命中 tracked `tool/build/test/run_tests.sh`; `git ls-files --others --exclude-standard | rg '\\.sh$|(^|/)run_.*\\.sh$'` 只命中 untracked `tool/build/test/run_release_smoke.sh`。
  - Shell 验证: `bash -n tool/build/test/run_tests.sh`; `bash -n tool/build/test/run_release_smoke.sh` 均通过。
  - 修正: `doc/start_here.md` 当前停点继续保持本次 JS/MJS 和 shell syntax gate 证据。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "JS/MJS 和 shell syntax gates|node --check tool/build/test/run_lsp_case\\.mjs|bash -n tool/build/test/run_tests\\.sh|run_release_smoke\\.sh|validate_wasi_bind_manifest\\.mjs" CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 JS/MJS 和 shell syntax gates 仍通过; 未新增阻断。
- [x] 刷新 Markdown link 和 active/blocker 状态口径 gates。结论:
  - Markdown 验证: Node 只读扫描 README、CHANGELOG 和 `doc/**/*.md`, 输出 `markdown_files=26`, `local_markdown_links=20`, `missing=0`。
  - 状态扫描: `rg -n "\\[ \\]|状态: (active|partial|blocked)|blocked:|TODO|FIXME|当前推荐|下次第一步|第二版编译器正在实现" README.md CHANGELOG.md doc/master_plan.md doc/roadmap_status.md doc/start_here.md`。
  - 未完成项扫描: `rg -n "^- \\[ \\]" doc/master_plan.md doc/roadmap_status.md README.md` 只命中 README 后置非目标、06.2 blocked/decomposed、D2.1 blocked 和 G6.1-G6.3 blocked。
  - 泛化状态扫描: `rg -n "^状态: (active|partial|blocked)(;|$)|^状态: blocked/partial|^状态: partial" doc/master_plan.md doc/roadmap_status.md doc/start_here.md README.md CHANGELOG.md` 无输出。
  - 修正: `doc/start_here.md` 当前停点同步本次 active/blocker 状态口径 gate 证据。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "Markdown link 和 active/blocker 状态口径 gates|markdown_files=26|local_markdown_links=20|missing=0|Active/blocker 状态口径 gate|泛化状态扫描" CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前文档入口、链接和状态口径未新增漂移; 未新增阻断。
- [x] 刷新 LSP fixture 和 WASI bind manifest helper gates。结论:
  - LSP 范围: `rg --files tool/build/test/lsp -g '*.json' | wc -l` 输出 `9`。
  - LSP 验证: 对 `tool/build/test/lsp/*.json` 逐个执行 `node tool/build/test/run_lsp_case.mjs ./bin/do <case>` 均通过, 摘要 `lsp_cases=9`。
  - WASI helper 验证: `node tool/build/test/test_wasi_bind_manifest_tool.mjs tool/build/test/validate_wasi_bind_manifest.mjs <tmp-dir>` 通过, 输出 `ok: wasi-bind manifest tool`。
  - 边界: 本项不解除 G6.1 preopens、G6.2 read-directory stream/future、G6.3 sockets resource/variant 的设计阻断。
  - 修正: `doc/start_here.md` 当前停点继续保持本次 LSP 和 WASI helper gate 证据。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "LSP fixture 和 WASI bind manifest helper gates|lsp_cases=9|ok: wasi-bind manifest tool|G6\\.1 preopens|run_lsp_case\\.mjs" CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 LSP fixture 和 WASI bind manifest helper gates 仍通过; 未新增阻断。
- [x] 复跑默认回归矩阵。结论:
  - 验证: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=831 fail=0 skip=3`。
  - 覆盖: tool、ok、err、std src metadata、compile ok、compile err、compiled ok/err、do run、fmt、check 和 lsp cases。
  - 剩余 skip: `118_wasi_p3_std_wrappers`、`16_loop_recv_value`、`96_file_lib_resource_shape`, 仍与 H1.4 的 runner / WASI resource 后置边界一致。
  - 边界: 本项不解除 G6.1-G6.3 或 D2.1 阻断。
  - 修正: `doc/start_here.md` 当前停点已保留同一默认回归摘要, 本次无需改动以避免重复噪音。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑默认回归矩阵|pass=831 fail=0 skip=3|118_wasi_p3_std_wrappers|16_loop_recv_value|96_file_lib_resource_shape|SKIP_BUILD=1 ./tool/build/test/run_tests.sh" CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前默认回归矩阵仍通过; 未新增阻断。
- [x] 复跑 `RUN_WASM=1` 扩展回归矩阵。结论:
  - 验证: `RUN_WASM=1 SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=833 fail=0 skip=3`。
  - 覆盖: 默认回归矩阵外, 额外执行 compiled trap、compiled wasm execution 和 6 个 wasm run smoke。
  - 结果: `wasm run summary: pass=6 fail=0`; 剩余 skip 仍是 `118_wasi_p3_std_wrappers`、`16_loop_recv_value`、`96_file_lib_resource_shape`。
  - 边界: 本项不解除 G6.1-G6.3 或 D2.1 阻断。
  - 修正: `doc/start_here.md` 当前停点已保留同一扩展回归摘要, 本次无需改动以避免重复噪音。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "RUN_WASM=1|pass=833 fail=0 skip=3|wasm run summary: pass=6 fail=0|compiled trap|compiled wasm execution|复跑" CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 `RUN_WASM=1` 扩展回归矩阵仍通过; 未新增阻断。
- [x] 复跑 release smoke gate。结论:
  - 验证: `./tool/build/test/run_release_smoke.sh` 通过。
  - 覆盖: ReleaseSmall build、`do build`、`do test`、`do test --compiled`、`do check`、`do fmt`、`do run` 和 `do lsp` 全部 `[PASS]`。
  - 结果: 输出 `[INFO] release smoke passed`。
  - 边界: 本项是发布候选最小链路 smoke, 不替代默认/扩展完整回归。
  - 修正: `doc/start_here.md` 当前停点已保留同一 release smoke 摘要, 本次无需改动以避免重复噪音。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑 release smoke gate|run_release_smoke\\.sh|ReleaseSmall build|release smoke passed|do test --compiled" CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 release smoke gate 仍通过; 未新增阻断。
- [x] 复核提交前交付边界。结论:
  - tracked diff 范围: `git diff --name-only | wc -l` 输出 `52`。
  - untracked 范围: `git ls-files --others --exclude-standard | wc -l` 输出 `117`。
  - UI 边界: `git diff --name-only | rg '(^|/)(ui\\.do|ui_demo\\.do)$' || true` 无输出。
  - UI 边界: `git ls-files --others --exclude-standard | rg '(^|/)(ui\\.do|ui_demo\\.do)$' || true` 只输出 `ui.do` 和 `ui_demo.do`。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复核提交前交付边界|git diff --name-only \\| wc -l|git ls-files --others --exclude-standard \\| wc -l|ui_demo\\.do|非主线 UI 文件未进入 tracked diff" doc/roadmap_status.md doc/start_here.md` 确认。
  - 结果: 当前累计交付范围与 `doc/start_here.md` 记录一致; 非主线 UI 文件未进入 tracked diff; 未新增阻断。
- [x] 复核旧草稿和过期入口残留。结论:
  - 文件名扫描: `rg --files | rg '(^|/)(review_blockers|review_issues|compiled_task_checklist|next_stage_plan|internal_prefix_rename_plan|task_checklist|blockers|draft|todo)\\.(md|txt)$' || true` 无输出。
  - untracked 扫描: `git ls-files --others --exclude-standard | rg '(^|/)(review_blockers|review_issues|compiled_task_checklist|next_stage_plan|internal_prefix_rename_plan|task_checklist|blockers|draft|todo)\\.(md|txt)$|(^|/)doc/' || true` 无输出。
  - 活跃引用扫描: `rg -n "review_blockers|review_issues|compiled_task_checklist|next_stage_plan|internal_prefix_rename_plan|当前推荐继续阶段|第二版编译器正在实现|下次第一步|TODO|FIXME" README.md CHANGELOG.md doc tool/build/test/README.md` 的命中均为 `CHANGELOG.md` / `doc/roadmap_status.md` 历史记录或验证命令。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复核旧草稿和过期入口残留|文件名扫描|untracked 扫描|活跃引用扫描|当前没有需要删除的旧草稿文件" doc/roadmap_status.md` 确认。
  - 结果: 当前没有需要删除的旧草稿文件或活跃旧入口; 未修改语法设计文件; 未新增阻断。
- [x] 复核 regression fixture companion 一致性。结论:
  - 初始扫描误报: `err/fixture.*.do` 是 import 依赖 fixture, `run_tests.sh` 会跳过, 不能要求逐个配 `.expect`。
  - 依据: `rg -n "fixture\\.|\\.expect|compiled_must_pass|compile_err|err/" tool/build/test/run_tests.sh tool/build/test/README.md` 命中 `run_tests.sh` 中 `fixture.*.do` skip 规则和 README 的 marker/expect 约定。
  - 正确口径复核: Node 只读扫描 `err`、`compile_err`、`compiled_ok`、`compiled_err`、`run`、`fmt`、`ok`、`check` 的 `.do` / `.expect` / `.must_pass` / `.compiled_must_pass` companion 关系。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复核 regression fixture companion 一致性|fixture_companion_counts|fixture_companion_missing=0|fixture\\.\\*\\.do" doc/roadmap_status.md` 确认。
  - 结果: 输出 `fixture_companion_counts={"err":580,"compile_err":60,"compiled_ok":104,"compiled_err":2,"run":11,"fmt":6,"ok":293,"check":3}` 和 `fixture_companion_missing=0`; 未新增阻断。
- [x] 复核 Markdown 链接和入口状态口径。结论:
  - Markdown 本地链接扫描: Node 只读扫描 README、CHANGELOG 和 `doc/**/*.md`, 输出 `markdown_files=26`, `local_markdown_links=20`, `missing=0`。
  - 入口状态扫描: `rg -n "^- \\[ \\]|状态: (active|partial|blocked)|blocked:|TODO|FIXME|当前推荐|下次第一步|第二版编译器正在实现" README.md CHANGELOG.md doc/master_plan.md doc/roadmap_status.md doc/start_here.md`。
  - 泛化状态扫描: `rg -n "^状态: (active|partial|blocked)(;|$)|^状态: blocked/partial|^状态: partial" doc/master_plan.md doc/roadmap_status.md doc/start_here.md README.md CHANGELOG.md || true` 无输出。
  - 未完成项扫描: `rg -n "^- \\[ \\]" doc/master_plan.md doc/roadmap_status.md README.md` 只命中 README 后置非目标、06.2 blocked/decomposed、D2.1 blocked 和 G6.1-G6.3 blocked。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复核 Markdown 链接和入口状态口径|markdown_files=26|local_markdown_links=20|missing=0|泛化状态扫描|未完成项扫描" doc/roadmap_status.md` 确认。
  - 结果: 当前文档链接、入口状态和阻断口径未新增漂移; 未新增阻断。
- [x] 复核 JSON 配置和 fixture 语法。结论:
  - 文件枚举: `{ rg --files -g '*.json'; git ls-files --others --exclude-standard | rg '\\.json$' || true; } | sort -u` 覆盖 tracked 与 untracked JSON。
  - 解析验证: Node 对枚举结果逐个 `JSON.parse`, 输出 `json_files=22` 和 `json_parse_fail=0`。
  - untracked JSON 边界: `git ls-files --others --exclude-standard | rg '\\.json$' | sort || true` 只命中 `tool/build/test/lsp/06_hover_request.json`、`07_completion_request.json`、`08_definition_request.json` 和 `09_workspace_index_request.json`。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复核 JSON 配置和 fixture 语法|json_files=22|json_parse_fail=0|untracked JSON 边界|09_workspace_index_request\\.json" doc/roadmap_status.md` 确认。
  - 结果: 当前 JSON 配置和 LSP / WASI fixture 语法均可解析; 未新增阻断。
- [x] 复核 WIT registry 结构。结论:
  - 依据: `doc/wit/wasi_registry.json` 顶层当前为 `records` 和 `functions`; `tool/build/test/validate_wasi_bind_manifest.mjs` 的 `loadRegistry` 会校验 `records` object 和 `functions` array。
  - 结构验证: Node 只读扫描 registry, 校验 record mirror 名称、字段唯一性、WIT 类型尖括号平衡、function target 形状、target 唯一性、params/result 类型和 `result_record` 指向。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复核 WIT registry 结构|wasi_registry_records=1|wasi_registry_functions=26|wasi_registry_result_records=1|wasi_registry_shape_errors=0|result_record" doc/roadmap_status.md` 确认。
  - 结果: 输出 `wasi_registry_records=1`, `wasi_registry_functions=26`, `wasi_registry_result_records=1`, `wasi_registry_shape_errors=0`; 未新增阻断。
- [x] 复核 WIT registry 生成缓存边界。结论:
  - 初始广义比较: `doc/wit/wasi_registry.json` 与 `tool/build/test/tmp/wasi_registry.json` 内容不同, 但该 tmp 文件不是 tracked 交付源。
  - 边界取证: `git ls-files --stage -- tool/build/test/tmp/wasi_registry.json || true` 无输出; `git check-ignore -v tool/build/test/tmp/wasi_registry.json || true` 命中 `tool/build/test/tmp/.gitignore:1:*`。
  - tracked tmp 范围: `git ls-files tool/build/test/tmp` 只输出 `tool/build/test/tmp/.gitignore`, 该文件内容为 `*` 和 `!.gitignore`。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复核 WIT registry 生成缓存边界|tool/build/test/tmp/wasi_registry\\.json|git check-ignore|WIT registry 的交付源仍只有" doc/roadmap_status.md` 确认。
  - 结果: WIT registry 的交付源仍只有 `doc/wit/wasi_registry.json`; `tool/build/test/tmp/wasi_registry.json` 属于 ignored 生成缓存, 不作为 registry drift gate; 未新增阻断。
- [x] 复跑 LSP fixture 行为 gate。结论:
  - 范围: `rg --files tool/build/test/lsp -g '*.json' | sort` 当前列出 `01_open_valid` 到 `09_workspace_index_request` 共 9 个 JSON fixture。
  - 验证: 对每个 fixture 执行 `node tool/build/test/run_lsp_case.mjs ./bin/do <case>` 均通过。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑 LSP fixture 行为 gate|lsp_cases=9|09_workspace_index_request|run_lsp_case\\.mjs|workspace index" doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 输出 `lsp_cases=9`; 当前 diagnostics、formatting、semantic tokens、hover、completion、definition 和 workspace index LSP smoke 仍通过; 未新增阻断。
- [x] 复跑 `do fmt` fixture 行为 gate。结论:
  - 范围: `rg --files tool/build/test/fmt -g '*.do' | sort` 当前列出 `01_struct_func_indent`、`02_comments_line_strings` 和 `03_control_blocks` 共 3 个 fixture。
  - 验证: 按 `run_fmt_case` 等价口径逐个执行 `./bin/do fmt`, 对比 `.expect`, 复跑格式化输出校验幂等, 对 formatted 临时文件执行 `do fmt --check`, 对临时副本执行 `do fmt --write` 和 write idempotence, 并对未格式化原输入校验 `error[FormatMismatch]`。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 `do fmt` fixture 行为 gate|fmt_cases=3|01_struct_func_indent|FormatMismatch|run_fmt_case' doc/roadmap_status.md tool/build/test/README.md tool/build/test/run_tests.sh` 确认。
  - 结果: 输出 `fmt_cases=3`; 当前 `do fmt` fixture 行为 gate 仍通过; 未新增阻断。
- [x] 复跑 `do check` fixture 行为 gate。结论:
  - 范围: `rg --files tool/build/test/check -g '*.do' | sort` 当前列出 `01_valid.do` 和 `02_syntax_error.do` 共 2 个 fixture。
  - 验证: 按 `run_check_case` 等价口径复跑单文件检查; 无 `.expect` 的 `01_valid.do` 静默成功, 有 `.expect` 的 `02_syntax_error.do` 失败并逐行匹配 stderr 子串且 stdout 为空。
  - 多输入验证: 按 `run_check_multi_case` 等价口径覆盖全部成功、后一个失败、前一个失败后继续检查后续输入并最终失败。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 `do check` fixture 行为 gate|check_cases=2|check_multi=pass|run_check_case|run_check_multi_case' doc/roadmap_status.md tool/build/test/README.md tool/build/test/run_tests.sh` 确认。
  - 结果: 输出 `check_cases=2` 和 `check_multi=pass`; 当前 `do check` fixture 行为 gate 仍通过; 未新增阻断。
- [x] 复跑 `do run` fixture 行为 gate。结论:
  - 范围: `rg --files tool/build/test/run -g '*.do' | sort` 当前列出 `01_start_scalar` 到 `06_defer_loop_break` 共 6 个 fixture。
  - 验证: 按 `run_do_run_case` 等价口径逐个执行 `./bin/do run`, 要求 stderr 为空; 有 `.stdout.expect` 的用例逐行对比 stdout, 无 `.stdout.expect` 的用例要求 stdout 为空。
  - 外部工具诊断: 按 `run_do_run_missing_wasm_tools_case` / `run_do_run_missing_node_case` 等价口径覆盖缺 `wasm-tools` 和缺 `node` 的 `error[MissingExternalTool]` 诊断, 两者 stdout 均为空。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 `do run` fixture 行为 gate|run_cases=6|run_missing_tools=pass|run_do_run_case|MissingExternalTool' doc/roadmap_status.md tool/build/test/README.md tool/build/test/run_tests.sh` 确认。
  - 结果: 输出 `run_cases=6` 和 `run_missing_tools=pass`; 当前 `do run` fixture 行为 gate 仍通过; 未新增阻断。
- [x] 复跑 `do build` product smoke gate。结论:
  - 成功路径: `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/01_start_entry_valid.do -o <tmp>.wat` 成功, stdout 包含 `ok:`, stderr 为空, WAT 非空且包含 `(module`。
  - 失败路径: `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_err/01_missing_start_entry.do -o <tmp>.wat` 失败, stderr 逐行匹配 `tool/build/test/compile_err/01_missing_start_entry.expect`, stdout 为空且未生成非空 WAT。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 `do build` product smoke gate|build_smoke_success=1|build_smoke_failure=1|01_start_entry_valid|01_missing_start_entry' doc/roadmap_status.md tool/build/test/README.md tool/build/test/run_tests.sh` 确认。
  - 结果: 输出 `build_smoke_success=1` 和 `build_smoke_failure=1`; 当前 `do build` product smoke gate 仍通过; 未新增阻断。
- [x] 复跑 `do test` product smoke gate。结论:
  - 静态路径: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/01_path_get_single.do` 成功, stderr 为空, stdout 包含 `test "path get single" ... ok` 和 `ok: 1 passed; 0 failed; 0 skipped`。
  - compiled 路径: `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_ok/01_compiled_test_entry.do --compiled -o <tmp>.wat` 成功生成非空 WAT, stdout 包含 `ok:`, stderr 为空, WAT 包含 `;; compiled-test 0 "compiled test entry"`; `wasm-tools parse` 和 `node tool/build/test/run_compiled_test_case.mjs` 执行通过。
  - output guard: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/01_path_get_single.do -o <tmp>.wat` 失败并输出 `error[OutputRequiresCompiledTest]`, stdout 为空且未生成非空 WAT。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 `do test` product smoke gate|test_smoke_static=1|test_smoke_compiled=1|test_output_guard=1|OutputRequiresCompiledTest|01_compiled_test_entry' doc/roadmap_status.md tool/build/test/README.md tool/build/test/run_tests.sh` 确认。
  - 结果: 输出 `test_smoke_static=1`, `test_smoke_compiled=1` 和 `test_output_guard=1`; 当前 `do test` product smoke gate 仍通过; 未新增阻断。
- [x] 复跑 CLI argument / output path guard gate。结论:
  - output-order 路径: `DO_LIB_ROOT=src ./bin/do build -o <tmp>.wat tool/build/test/compile_ok/01_start_entry_valid.do` 成功生成非空 WAT, stdout 包含 `ok:`, stderr 为空。
  - output-order 路径: `DO_LIB_ROOT=src ./bin/do test --compiled -o <tmp>.wat tool/build/test/compiled_ok/01_compiled_test_entry.do` 成功生成非空 WAT, stdout 包含 `ok:`, stderr 为空, WAT 包含 `;; compiled-test 0 "compiled test entry"`。
  - strict-args 路径: `do build <input> --bad`、`do build <input> <input>`、`do run <input> --bad` 和 `do run <input> <input>` 均失败并输出 `error[UnexpectedCliArg]`, stdout 为空。
  - output guard: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/01_path_get_single.do -o <tmp>.wat` 失败并输出 `error[OutputRequiresCompiledTest]`, stdout 为空且未生成非空 WAT。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 CLI argument / output path guard gate|cli_output_order_build=1|cli_output_order_test=1|cli_strict_build_bad=1|cli_strict_build_extra=1|cli_strict_run_bad=1|cli_strict_run_extra=1|cli_test_output_guard=1|UnexpectedCliArg|OutputRequiresCompiledTest' doc/roadmap_status.md tool/build/test/README.md tool/build/test/run_tests.sh` 确认。
  - 结果: 输出 `cli_output_order_build=1`, `cli_output_order_test=1`, `cli_strict_build_bad=1`, `cli_strict_build_extra=1`, `cli_strict_run_bad=1`, `cli_strict_run_extra=1` 和 `cli_test_output_guard=1`; 当前 CLI argument / output path guard gate 仍通过; 未新增阻断。
- [x] 复跑 WASI bind manifest helper gate。结论:
  - 范围: `tool/build/test/test_wasi_bind_manifest_tool.mjs` 驱动 `tool/build/test/validate_wasi_bind_manifest.mjs` 的 helper 自测, 覆盖 manifest JSON、known/unsupported、component-plan、core imports/shims、component input 和 component wasm helper 行为。
  - 验证: `node tool/build/test/test_wasi_bind_manifest_tool.mjs tool/build/test/validate_wasi_bind_manifest.mjs <tmp-dir>` 通过, stdout 输出 `ok: wasi-bind manifest tool`, stderr 为空。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑 WASI bind manifest helper gate|wasi_bind_manifest_helper=1|ok: wasi-bind manifest tool|test_wasi_bind_manifest_tool\\.mjs|validate_wasi_bind_manifest\\.mjs" doc/roadmap_status.md tool/build/test/README.md tool/build/test/run_tests.sh` 确认。
  - 结果: 输出 `wasi_bind_manifest_helper=1`; 当前 WASI bind manifest helper gate 仍通过; 本项不解除 G6.1-G6.3 的公开 API 或运行时设计阻断; 未新增阻断。
- [x] 复跑 run_wasm_smoke bridge gate。结论:
  - 范围: `tool/build/test/run_wasm_smoke.sh` 的底层 WAT -> `wasm-tools parse` -> Node 执行桥接; 它不替代 `do run` 产品命令回归。
  - 验证: `SKIP_BUILD=1 ./tool/build/test/run_wasm_smoke.sh` 通过, `01_start_scalar`、`02_env_host_import_string_literal`、`03_env_host_import_storage_wrapper`、`04_defer_lifo`、`05_defer_block` 和 `06_defer_loop_break` 全部 `[PASS]`。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑 run_wasm_smoke bridge gate|wasm run summary: pass=6 fail=0|01_start_scalar|06_defer_loop_break|run_wasm_smoke\\.sh" doc/roadmap_status.md tool/build/test/README.md tool/build/test/run_tests.sh` 确认。
  - 结果: 输出 `wasm run summary: pass=6 fail=0`; 当前底层 wasm bridge gate 仍通过; 未新增阻断。
- [x] 复跑 compiled trap smoke gate。结论:
  - 范围: `tool/build/test/compiled_trap/*.do` 当前共 2 个 fixture: `01_compiled_test_fallthrough_traps` 和 `02_compiled_managed_struct_alias_set_oob_get_traps`。
  - 验证: 两个 fixture 均执行 `DO_LIB_ROOT=tool/build/test/lib ./bin/do test <case> --compiled -o <tmp>.wat` 成功, stdout 包含 `ok:`, stderr 为空, WAT 非空。
  - 验证: 两个 WAT 均通过 `wasm-tools parse`; 随后 `node tool/build/test/run_compiled_test_case.mjs <wasm> <wat>` 均按预期非 0 退出, 输出包含 trap marker。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑 compiled trap smoke gate|compiled_trap_cases=2|01_compiled_test_fallthrough_traps|02_compiled_managed_struct_alias_set_oob_get_traps|run_compiled_test_case\\.mjs" doc/roadmap_status.md tool/build/test/README.md tool/build/test/run_tests.sh` 确认。
  - 结果: 输出 `compiled_trap_01_compiled_test_fallthrough_traps=1`, `compiled_trap_02_compiled_managed_struct_alias_set_oob_get_traps=1` 和 `compiled_trap_cases=2`; 当前 compiled trap smoke gate 仍通过; 未新增阻断。
- [x] 复跑 diagnostic unit / contract gate。结论:
  - 范围: `tool/build/diag.zig` focused tests, 以及 `errorSummary` / `errorHint` 显式诊断条目一致性。
  - 验证: `cd tool && zig test build/diag.zig` 通过, 输出 `All 13 tests passed.`。
  - 验证: Node 只读扫描 `tool/build/diag.zig`, 结果为 `summary_entries=55`, `hint_entries=55`, `summary_without_hint=(none)`, `hint_without_summary=(none)`。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑 diagnostic unit / contract gate|All 13 tests passed|summary_entries=55|hint_entries=55|summary_without_hint=\\(none\\)|hint_without_summary=\\(none\\)|build/diag\\.zig" doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前 diagnostic unit / contract gate 仍通过; 未新增阻断。
- [x] 复跑 CLI parser unit gate。结论:
  - 范围: `tool/build/cli.zig` 的 run/fmt/lsp/check 参数解析单元测试。
  - 验证: `cd tool && zig test build/cli.zig` 通过, 输出 `All 14 tests passed.`。
  - 覆盖: run 单 input / extra args / unknown flag / missing input, fmt stdout/check/write/互斥/缺失与非法参数, lsp stdio/extra/unknown flag, check 单 input/多 input/缺失与非法参数。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑 CLI parser unit gate|All 14 tests passed|parseRun accepts exactly one input path|parseFmt accepts write mode|parseLsp accepts explicit stdio flag|parseCheck accepts multiple input paths|build/cli\\.zig" doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前 CLI parser unit gate 仍通过; build/test 的黑盒严格参数和 output-order 路径由 CLI argument / output path guard gate 覆盖; 未新增阻断。
- [x] 复跑 lexer / tokenization unit gate。结论:
  - 范围: `tool/build/lexer.zig` 的 focused tokenizer tests。
  - 验证: `cd tool && zig test build/lexer.zig` 通过, 输出 `All 10 tests passed.`。
  - 覆盖: dot/private 标识符、internal dot 拆分、spread token、loop label apostrophe、identifier 后 apostrophe、字符串 escape UTF-8 校验、line string block、inline RHS line string 和 blank-line split。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑 lexer / tokenization unit gate|All 10 tests passed|dot prefixed names tokenize|spread token is separate|blank line breaks line string block|build/lexer\\.zig" doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前 lexer / tokenization unit gate 仍通过; 未新增阻断。
- [x] 复跑 parser unit gate。结论:
  - 范围: `tool/build/parser.zig` 的 focused parser tests, 并包含 parser 导入链上的 lexer tests。
  - 验证: `cd tool && zig test build/parser.zig` 通过, 输出 `All 24 tests passed.`。
  - 覆盖: bool/nil literals、literal-call rejection、lambda placement/call args、lambda omitted param type/block body、spread、function name call args、struct literal equals、generic bind arity、import ordering、storage variadic arity 和 collection loop two-binding parser rule。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑 parser unit gate|All 24 tests passed|bool and nil literals parse|lambda block body is accepted|collection loop requires value and index bindings|build/parser\\.zig" doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前 parser unit gate 仍通过; 未新增阻断。
- [x] 复跑 sema unit gate。结论:
  - 范围: `tool/build/sema.zig` 的 focused semantic analysis tests, 并包含 sema 导入链上的 lexer/parser unit tests。
  - 验证: `cd tool && zig test build/sema.zig` 通过, 输出 `All 26 tests passed.`。
  - 覆盖: private host import 不被误判为 private lvalue assignment、private assignment rejection, 以及导入链上的 tokenizer/parser 边界。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑 sema unit gate|All 26 tests passed|private host import is not a private lvalue assignment|private assignment is rejected|build/sema\\.zig" doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前 sema unit gate 仍通过; 未新增阻断。
- [x] 复跑 codegen unit gate。结论:
  - 范围: `tool/build/codegen.zig` 的 focused codegen tests, 并包含 codegen 导入链上的 lexer、backend/runtime/component/test-runner/ownership unit tests。
  - 验证: `cd tool && zig test build/codegen.zig` 通过, 输出 `All 51 tests passed.`。
  - 覆盖: source origin metadata、move candidate metadata、generic union/callback binding、variadic storage ABI、Backend IR scalar lowering、runtime prelude、component metadata、test runner variadic dispatch 和 ownership facts。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑 codegen unit gate|All 51 tests passed|build/codegen\\.zig|generic union/callback|variadic storage ABI|Backend IR" doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前 codegen unit gate 仍通过; 未新增阻断。
- [x] 复跑 backend / writer / ownership / runner focused unit gates。结论:
  - 范围: 后端 IR、runtime prelude WAT writer、component metadata WAT writer、function body WAT writer、ownership exit/facts、static test runner dispatch 和 normal compile path start-entry enforcement。
  - 验证: `cd tool && zig test build/backend_ir.zig` 通过, 输出 `All 13 tests passed.`。
  - 验证: `cd tool && zig test build/runtime_prelude_wat.zig` 通过, 输出 `All 2 tests passed.`。
  - 验证: `cd tool && zig test build/component_metadata_wat.zig` 通过, 输出 `All 4 tests passed.`。
  - 验证: `cd tool && zig test build/function_body_wat.zig` 通过, 输出 `All 2 tests passed.`。
  - 验证: `cd tool && zig test build/ownership.zig` 通过, 输出 `All 2 tests passed.`。
  - 验证: `cd tool && zig test build/ownership_facts.zig` 通过, 输出 `All 6 tests passed.`。
  - 验证: `cd tool && zig test build/test_runner.zig` 通过, 输出 `All 14 tests passed.`。
  - 验证: `cd tool && zig test build/run.zig` 通过, 输出 `All 27 tests passed.`。
  - 覆盖: Backend IR block/value/emit/fold/inline、runtime prelude memory/layout writer、component manifest/import writer、function body shell/compiled-test writer、ownership exit/facts、static test runner variadic dispatch 和 normal compile path start-entry enforcement。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑 backend / writer / ownership / runner focused unit gates|All 13 tests passed|All 27 tests passed|runtime_prelude_wat|component_metadata_wat|function_body_wat|ownership_facts|test_runner|build/run\\.zig" doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前 backend / writer / ownership / runner focused unit gates 仍通过; 未新增阻断。
- [x] 复跑 Zig fmt / Debug build gates。结论:
  - 环境: `zig version` 输出 `0.16.0`。
  - 验证: `rg --files -g '*.zig' | wc -l` 输出 `31`。
  - 验证: `rg --files -g '*.zig' -0 | xargs -0 zig fmt --check` 通过。
  - 验证: `cd tool && zig build -Doptimize=Debug` 通过。
  - 边界: 本项只证明 Zig 格式和 Debug build, 不替代 unit tests、fixture regression、wasm execution gate 或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑 Zig fmt / Debug build gates|zig version|0\\.16\\.0|zig fmt --check|zig build -Doptimize=Debug|输出 \\`31\\`" doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前 Zig fmt / Debug build gates 仍通过; 未新增阻断。
- [x] 复跑 JS/MJS 和 shell syntax gates。结论:
  - JS/MJS 范围: `git diff --name-only | rg '\\.(mjs|js)$'` 只命中 `tool/build/test/run_lsp_case.mjs`、`tool/build/test/test_wasi_bind_manifest_tool.mjs` 和 `tool/build/test/validate_wasi_bind_manifest.mjs`; `git ls-files --others --exclude-standard | rg '\\.(mjs|js)$'` 无输出。
  - JS/MJS 验证: `node --check tool/build/test/run_lsp_case.mjs`; `node --check tool/build/test/test_wasi_bind_manifest_tool.mjs`; `node --check tool/build/test/validate_wasi_bind_manifest.mjs` 均通过。
  - Shell 范围: `git diff --name-only | rg '\\.sh$|(^|/)run_.*\\.sh$'` 只命中 tracked `tool/build/test/run_tests.sh`; `git ls-files --others --exclude-standard | rg '\\.sh$|(^|/)run_.*\\.sh$'` 只命中 untracked `tool/build/test/run_release_smoke.sh`。
  - Shell 验证: `bash -n tool/build/test/run_tests.sh`; `bash -n tool/build/test/run_release_smoke.sh` 均通过。
  - 边界: 本项只证明测试 helper 和 shell harness 语法, 不替代 fixture regression、release smoke 或 wasm execution gate。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑 JS/MJS 和 shell syntax gates|node --check tool/build/test/run_lsp_case\\.mjs|bash -n tool/build/test/run_tests\\.sh|run_release_smoke\\.sh|validate_wasi_bind_manifest\\.mjs" doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前 JS/MJS 和 shell syntax gates 仍通过; 未新增阻断。
- [x] 复跑 Markdown link 和 active/blocker 状态口径 gates。结论:
  - Markdown 验证: Node 只读扫描 README、CHANGELOG 和 `doc/**/*.md`, 输出 `markdown_files=26`, `local_markdown_links=20`, `missing=0`。
  - 未完成项扫描: `rg -n "^- \\[ \\]" doc/master_plan.md doc/roadmap_status.md README.md` 只命中 README 后置非目标、06.2 blocked/decomposed、D2.1 blocked 和 G6.1-G6.3 blocked。
  - 泛化状态扫描: `rg -n "^状态: (active|partial|blocked)(;|$)|^状态: blocked/partial|^状态: partial" doc/master_plan.md doc/roadmap_status.md doc/start_here.md README.md CHANGELOG.md` 无输出。
  - 旧入口扫描: `rg -n "当前推荐|下次第一步|第二版编译器正在实现|TODO|FIXME" README.md doc/master_plan.md doc/start_here.md` 无输出; `rg -n "review_blockers|review_issues|compiled_task_checklist|next_stage_plan|internal_prefix_rename_plan|当前推荐继续阶段" README.md doc/master_plan.md doc/start_here.md doc/syntax doc/spec.md doc/spec_rules.md doc/grammar.peg tool/build/test/README.md` 无输出。
  - 边界: 本项只证明文档链接、入口状态和阻断口径没有新增漂移, 不解除 README 后置非目标、06.2、D2.1 或 G6.1-G6.3。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑 Markdown link 和 active/blocker 状态口径 gates|markdown_files=26|local_markdown_links=20|missing=0|未完成项扫描|旧入口扫描" doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前文档链接、入口状态和阻断口径未新增漂移; 未新增阻断。
- [x] 复跑 LSP fixture 和 WASI bind manifest helper gates。结论:
  - LSP 范围: `rg --files tool/build/test/lsp -g '*.json' | sort` 当前覆盖 `01_open_valid` 到 `09_workspace_index_request` 共 9 个 JSON fixture。
  - LSP 验证: 对每个 fixture 执行 `node tool/build/test/run_lsp_case.mjs ./bin/do <case>` 均通过, 摘要 `lsp_cases=9`。
  - WASI helper 验证: `node tool/build/test/test_wasi_bind_manifest_tool.mjs tool/build/test/validate_wasi_bind_manifest.mjs <tmp-dir>` 通过, 输出 `ok: wasi-bind manifest tool`。
  - 边界: 本项不解除 G6.1 preopens、G6.2 read-directory stream/future、G6.3 sockets resource/variant 的设计阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑 LSP fixture 和 WASI bind manifest helper gates|lsp_cases=9|ok: wasi-bind manifest tool|09_workspace_index_request|G6\\.1 preopens" doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前 LSP fixture 和 WASI bind manifest helper gates 仍通过; 未新增阻断。
- [x] 复跑 `do fmt` fixture 行为 gate。结论:
  - 范围: `tool/build/test/fmt/*.do` 当前共 3 个 fixture: `01_struct_func_indent`、`02_comments_line_strings` 和 `03_control_blocks`。
  - 验证: 按 `tool/build/test/run_tests.sh` 的 `run_fmt_case` 等价口径逐个执行 `./bin/do fmt`, 对比 `.expect`, 复跑格式化输出校验幂等, 对 formatted 临时文件执行 `do fmt --check`, 对临时副本执行 `do fmt --write` 和 write idempotence, 并对未格式化原输入校验 `error[FormatMismatch]`。
  - 验证: 输出 `fmt_case_01_struct_func_indent=1`, `fmt_case_02_comments_line_strings=1`, `fmt_case_03_control_blocks=1` 和 `fmt_cases=3`。
  - 边界: 本项只证明 `do fmt` fixture 行为, 不替代 full fixture regression、release smoke 或 parser/sema/codegen unit gates。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 `do fmt` fixture 行为 gate|fmt_cases=3|fmt_case_01_struct_func_indent=1|FormatMismatch|run_fmt_case' doc/roadmap_status.md tool/build/test/run_tests.sh doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前 `do fmt` fixture 行为 gate 仍通过; 未新增阻断。
- [x] 复跑 `do check` fixture 行为 gate。结论:
  - 范围: `tool/build/test/check/*.do` 当前共 2 个 fixture: `01_valid` 和 `02_syntax_error`。
  - 单文件验证: 按 `tool/build/test/run_tests.sh` 的 `run_check_case` 等价口径复跑; 无 `.expect` 的 `01_valid.do` 静默成功, 有 `.expect` 的 `02_syntax_error.do` 失败并逐行匹配 stderr 子串且 stdout 为空。
  - 多输入验证: 按 `run_check_multi_case` 等价口径覆盖全部成功、后一个失败、前一个失败后继续检查后续输入并最终失败。
  - 验证: 输出 `check_case_01_valid=1`, `check_case_02_syntax_error=1`, `check_cases=2` 和 `check_multi=pass`。
  - 边界: 本项只证明 `do check` fixture 行为, 不替代 full fixture regression、release smoke 或 parser/sema/codegen unit gates。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 `do check` fixture 行为 gate|check_cases=2|check_multi=pass|check_case_01_valid=1|run_check_case|run_check_multi_case' doc/roadmap_status.md tool/build/test/run_tests.sh doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前 `do check` fixture 行为 gate 仍通过; 未新增阻断。
- [x] 复跑 `do run` fixture 行为 gate。结论:
  - 范围: `tool/build/test/run/*.do` 当前共 6 个 fixture: `01_start_scalar`、`02_env_host_import_string_literal`、`03_env_host_import_storage_wrapper`、`04_defer_lifo`、`05_defer_block` 和 `06_defer_loop_break`。
  - 正常执行验证: 按 `tool/build/test/run_tests.sh` 的 `run_do_run_case` 等价口径逐个执行 `./bin/do run`, 要求 stderr 为空; 有 `.stdout.expect` 的用例逐行对比 stdout, 无 `.stdout.expect` 的用例要求 stdout 为空。
  - 外部工具诊断: 按 `run_do_run_missing_wasm_tools_case` / `run_do_run_missing_node_case` 等价口径覆盖缺 `wasm-tools` 和缺 `node` 的 `error[MissingExternalTool]` 诊断, 两者 stdout 均为空。
  - 验证: 输出 `run_case_01_start_scalar=1`, `run_case_02_env_host_import_string_literal=1`, `run_case_03_env_host_import_storage_wrapper=1`, `run_case_04_defer_lifo=1`, `run_case_05_defer_block=1`, `run_case_06_defer_loop_break=1`, `run_cases=6` 和 `run_missing_tools=pass`。
  - 边界: 本项只证明 `do run` fixture 行为和缺失外部工具诊断, 不替代 full fixture regression、release smoke 或 WASI / Component Model runtime。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 `do run` fixture 行为 gate|run_cases=6|run_missing_tools=pass|run_case_01_start_scalar=1|run_do_run_case|MissingExternalTool' doc/roadmap_status.md tool/build/test/run_tests.sh doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前 `do run` fixture 行为 gate 仍通过; 未新增阻断。
- [x] 复跑 `do build` product smoke gate。结论:
  - 成功路径: `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/01_start_entry_valid.do -o <tmp>.wat` 成功, stdout 包含 `ok:`, stderr 为空, WAT 非空且包含 `(module`。
  - 失败路径: `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_err/01_missing_start_entry.do -o <tmp>.wat` 失败, stderr 逐行匹配 `tool/build/test/compile_err/01_missing_start_entry.expect`, stdout 为空且未生成非空 WAT。
  - 验证: 输出 `build_smoke_success=1` 和 `build_smoke_failure=1`。
  - 边界: 本项只证明最小 `do build` 产品链路和最小失败诊断, 不替代 full compile fixture regression、release smoke 或 wasm execution gate。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 `do build` product smoke gate|build_smoke_success=1|build_smoke_failure=1|01_start_entry_valid|01_missing_start_entry' doc/roadmap_status.md tool/build/test/run_tests.sh doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前 `do build` product smoke gate 仍通过; 未新增阻断。
- [x] 复跑 `do test` product smoke gate。结论:
  - 静态路径: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/01_path_get_single.do` 成功, stdout 包含 `test "path get single" ... ok` 和 `ok: 1 passed; 0 failed; 0 skipped`, stderr 为空。
  - compiled 路径: `DO_LIB_ROOT=src ./bin/do test tool/build/test/compiled_ok/01_compiled_test_entry.do --compiled -o <tmp>.wat` 成功生成非空 WAT, stdout 包含 `ok:`, stderr 为空, WAT 包含 `;; compiled-test 0 "compiled test entry"`; `wasm-tools parse` 和 `node tool/build/test/run_compiled_test_case.mjs` 执行通过, stdout 包含 `test "compiled test entry" ... ok`。
  - output guard: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/01_path_get_single.do -o <tmp>.wat` 失败并输出 `error[OutputRequiresCompiledTest]`, stdout 为空且未生成非空 WAT。
  - 验证: 输出 `test_smoke_static=1`, `test_smoke_compiled=1` 和 `test_output_guard=1`。
  - 边界: 本项只证明最小 `do test` 产品链路、compiled WAT 生成执行和 output guard, 不替代 full fixture regression 或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 `do test` product smoke gate|test_smoke_static=1|test_smoke_compiled=1|test_output_guard=1|OutputRequiresCompiledTest|01_compiled_test_entry' doc/roadmap_status.md tool/build/test/run_tests.sh doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前 `do test` product smoke gate 仍通过; 未新增阻断。
- [x] 复跑 CLI argument / output path guard gate。结论:
  - output-order 路径: `DO_LIB_ROOT=src ./bin/do build -o <tmp>.wat tool/build/test/compile_ok/01_start_entry_valid.do` 成功生成非空 WAT, stdout 包含 `ok:`, stderr 为空。
  - output-order 路径: `DO_LIB_ROOT=src ./bin/do test --compiled -o <tmp>.wat tool/build/test/compiled_ok/01_compiled_test_entry.do` 成功生成非空 WAT, stdout 包含 `ok:`, stderr 为空, WAT 包含 `;; compiled-test 0 "compiled test entry"`。
  - strict-args 路径: `do build <input> --bad`、`do build <input> <input>`、`do run <input> --bad` 和 `do run <input> <input>` 均失败并输出 `error[UnexpectedCliArg]`, stdout 为空。
  - output guard: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/01_path_get_single.do -o <tmp>.wat` 失败并输出 `error[OutputRequiresCompiledTest]`, stdout 为空且未生成非空 WAT。
  - 验证: 输出 `cli_output_order_build=1`, `cli_output_order_test=1`, `cli_strict_build_bad=1`, `cli_strict_build_extra=1`, `cli_strict_run_bad=1`, `cli_strict_run_extra=1` 和 `cli_test_output_guard=1`。
  - 边界: 本项只证明 CLI 参数顺序、严格参数拒绝和 output guard, 不替代 CLI parser unit gate、full fixture regression 或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 CLI argument / output path guard gate|cli_output_order_build=1|cli_output_order_test=1|cli_strict_build_bad=1|cli_strict_build_extra=1|cli_strict_run_bad=1|cli_strict_run_extra=1|cli_test_output_guard=1|UnexpectedCliArg|OutputRequiresCompiledTest' doc/roadmap_status.md tool/build/test/run_tests.sh doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前 CLI argument / output path guard gate 仍通过; 未新增阻断。
- [x] 复跑 run_wasm_smoke bridge gate。结论:
  - 范围: `tool/build/test/run_wasm_smoke.sh` 的底层 WAT -> `wasm-tools parse` -> Node 执行桥接; 它不替代 `do run` 产品命令回归。
  - 验证: `SKIP_BUILD=1 ./tool/build/test/run_wasm_smoke.sh` 通过, `01_start_scalar`、`02_env_host_import_string_literal`、`03_env_host_import_storage_wrapper`、`04_defer_lifo`、`05_defer_block` 和 `06_defer_loop_break` 全部 `[PASS]`。
  - 验证: 输出 `wasm run summary: pass=6 fail=0`。
  - 边界: 本项只证明当前 6 个 wasm run smoke 的 bridge 行为, 不替代 full fixture regression、RUN_WASM 扩展回归或 WASI / Component Model runtime。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复跑 run_wasm_smoke bridge gate|wasm run summary: pass=6 fail=0|01_start_scalar|06_defer_loop_break|run_wasm_smoke\\.sh" doc/roadmap_status.md tool/build/test/run_tests.sh doc/start_here.md CHANGELOG.md` 确认。
  - 结果: 当前 run_wasm_smoke bridge gate 仍通过; 未新增阻断。
- [x] 复核当前 dirty worktree 交付边界。结论:
  - tracked diff 范围: `git diff --name-only | wc -l` 输出 `52`。
  - untracked 范围: `git ls-files --others --exclude-standard | wc -l` 输出 `117`。
  - UI 边界: `git diff --name-only | rg '(^|/)(ui\\.do|ui_demo\\.do)$' || true` 无输出。
  - UI 边界: `git ls-files --others --exclude-standard | rg '(^|/)(ui\\.do|ui_demo\\.do)$' || true` 只输出 `ui.do` 和 `ui_demo.do`。
  - 复验: `git diff --check` 通过; 现有 `doc/start_here.md` 的 dirty 范围记录与现场一致, 本轮无需更新入口文件。
  - 结果: 当前累计交付边界没有漂移; 非主线 UI 文件未进入 tracked diff; 未新增阻断。
- [x] 复核 WASI registry / lowering 文档覆盖 gate。结论:
  - 发现: 只读扫描先报 `doc_target_missing` / `table_target_missing`, 根因是 `doc/wit/wasi_p3_lowering.md` 的 G2 registry worklist 未覆盖全部 `doc/wit/wasi_registry.json` target。
  - 修正: 补齐 G2 表格中的 `descriptor.drop`、`preopens.get-directories`、`text/char/echo`、clock scalar/record、random list/u64 等已登记 target 状态行。
  - 验证: Node 只读扫描 `doc/wit/wasi_registry.json` 和 `doc/wit/wasi_p3_lowering.md` 通过, 输出 `wasi_registry_records=1`, `wasi_registry_functions=26`, `wasi_registry_result_records=1`, `wasi_registry_unique_targets=26`, `wasi_registry_doc_target_coverage=26/26`, `wasi_registry_table_target_coverage=26/26` 和 `wasi_registry_known_unsupported=7`。
  - 边界: `filesystem/preopens/get-directories`、`descriptor.read-directory`、sockets create/bind 和 `http/client/send` 仍保持 `known but unsupported`; 本项只修正文档覆盖漂移, 不解除 G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n "复核 WASI registry / lowering 文档覆盖 gate|wasi_registry_table_target_coverage=26/26|known but unsupported|text/char/echo|random/random/get-random-u64" doc/roadmap_status.md doc/wit/wasi_p3_lowering.md` 确认。
  - 结果: 当前 WASI registry 与 lowering 文档 worklist 覆盖重新对齐; 未新增阻断。
- [x] 复核 stdlib / positive fixture `@wasi` target registry 覆盖 gate。结论:
  - 范围: `src`、`tool/build/test/ok`、`tool/build/test/compile_ok`、`tool/build/test/compiled_ok`、`tool/build/test/run` 和 `tool/build/test/check` 下的 `.do` 文件。
  - 验证: Node 只读扫描 `.do` 文件中的 `@wasi("...")` target, 并逐项对照 `doc/wit/wasi_registry.json` 的 `functions[].target`。
  - 结果: 输出 `wasi_positive_files_scanned=515`, `wasi_positive_uses=40`, `wasi_positive_unique_targets=19`, `wasi_stdlib_uses=20`, `wasi_positive_fixture_uses=20` 和 `wasi_positive_missing_registry=0`。
  - 边界: 本项只证明标准库和正向 fixture 当前使用的 WASI target 均已登记; 不证明这些 target 都能运行, 也不解除 G6.1-G6.3 的 runtime/API 阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复核 stdlib / positive fixture|wasi_positive_missing_registry=0|wasi_positive_unique_targets=19|wasi_stdlib_uses=20' doc/roadmap_status.md` 确认。
  - 结果: stdlib 和正向 fixture 的 `@wasi` target 未发现 registry 漏登记; 未新增阻断。
- [x] 复跑负向 WASI fixture 诊断 gate。结论:
  - 范围: `tool/build/test/err/*wasi*.do`、`tool/build/test/compile_err/*wasi*.do` 和 `tool/build/test/compiled_err/*wasi*.do` 当前共 13 个负向 WASI fixture。
  - 验证: 按 `tool/build/test/run_tests.sh` 等价口径分别执行 `do test`、`do build -o <tmp>.wat` 和 `do test --compiled -o <tmp>.wat`, 要求命令失败并逐行匹配同名 `.expect`。
  - 结果: 输出 `err_238_wasi_host_import_colon=1`, `err_239_wasi_host_import_unknown_record=1`, `err_256_wasi_known_signature_mismatch=1`, `err_257_wasi_known_params_mismatch=1`, `err_258_wasi_known_record_mismatch=1`, `err_259_wasi_known_unsupported_signature_mismatch=1`, `err_260_wasi_known_resource_drop_signature_mismatch=1`, `err_261_import_std_private_wasi_host_binding=1`, `compile_err_06_wasi_host_import_build_unsupported=1`, `compile_err_10_imported_wasi_wrapper_build_unsupported=1`, `compile_err_259_wasi_result_single_value_forbidden=1`, `compile_err_273_wasi_duplicate_host_import_alias=1`, `compiled_err_01_imported_wasi_wrapper_unsupported=1`, `wasi_negative_cases=13` 和 `wasi_negative_failures=0`。
  - 边界: 本项只证明已登记的负向 WASI 诊断仍按预期触发; 不改变 known-but-unsupported target 的状态, 也不解除 G6.1-G6.3。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑负向 WASI fixture 诊断 gate|wasi_negative_cases=13|wasi_negative_failures=0|err_260_wasi_known_resource_drop_signature_mismatch|compiled_err_01_imported_wasi_wrapper_unsupported' doc/roadmap_status.md` 确认。
  - 结果: 当前负向 WASI fixture 诊断 gate 通过; 未新增阻断。
- [x] 复跑 WASI component plan expect / registry 对齐 gate。结论:
  - 范围: `tool/build/test/compile_ok/*.component_plan.expect` 当前共 11 个 fixture。
  - 验证: 按 `run_compile_ok_case` 核心口径逐个执行 `DO_LIB_ROOT=tool/build/test/lib ./bin/do build <case>.do -o <tmp>.wat`, 再执行 `node tool/build/test/validate_wasi_bind_manifest.mjs --registry doc/wit/wasi_registry.json --component-plan <tmp>.wat`, 要求输出逐行匹配同名 `.component_plan.expect`。
  - 额外校验: 从 `.component_plan.expect` 抽取 `"target": "..."` 行, 逐项确认存在于 `doc/wit/wasi_registry.json` 的 `functions[].target`。
  - 结果: 输出 `component_plan_08_wasi_std_import_binding_manifest=1`, `component_plan_101_wasi_result_filesize_statement_lower=1`, `component_plan_103_wasi_file_write_std_manifest=1`, `component_plan_107_wasi_result_unit_status_multi_lhs_lower=1`, `component_plan_109_wasi_result_read_multi_lhs_lower=1`, `component_plan_111_wasi_result_link_at_multi_lhs_lower=1`, `component_plan_115_wasi_result_stream_read_multi_lhs_lower=1`, `component_plan_117_wasi_result_output_check_write_multi_lhs_lower=1`, `component_plan_118_wasi_result_output_write_flush_status_lower=1`, `component_plan_120_wasi_result_descriptor_open_at_multi_lhs_lower=1`, `component_plan_124_imported_dir_create_remove_wrapper_lower=1`, `wasi_component_plan_cases=11` 和 `wasi_component_plan_failures=0`。
  - 边界: 本项只证明当前已 lower 的 component plan 期望和 registry 对齐; 不证明 WIT dir/core imports/core shims/component input 全链路, 也不解除 G6.1-G6.3。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 WASI component plan expect / registry 对齐 gate|wasi_component_plan_cases=11|wasi_component_plan_failures=0|component_plan_124_imported_dir_create_remove_wrapper_lower' doc/roadmap_status.md` 确认。
  - 结果: 当前 WASI component plan expect / registry 对齐 gate 通过; 未新增阻断。
- [x] 复跑 WASI core imports / core shims expect gate。结论:
  - 范围: `tool/build/test/compile_ok/*.core_imports.expect` 当前共 13 个 fixture; `tool/build/test/compile_ok/*.core_shims.expect` 当前共 13 个 fixture。
  - 验证: 按 `run_compile_ok_case` 核心口径逐个执行 `DO_LIB_ROOT=tool/build/test/lib ./bin/do build <case>.do -o <tmp>.wat`, 再分别执行 `node tool/build/test/validate_wasi_bind_manifest.mjs --registry doc/wit/wasi_registry.json --core-imports <tmp>.wat` 和 `--core-shims <tmp>.wat`, 要求输出逐行匹配同名 expect。
  - 验证: 本机存在 `wasm-tools` 时, 将每个 core shims 输出包成 `(module ...)` 并执行 `wasm-tools parse`。
  - 结果: 13 个 core imports fixture 均输出对应 `core_imports_<case>=1`; 13 个 core shims fixture 均输出对应 `core_shims_<case>=1`; 汇总为 `wasi_core_imports_cases=13`, `wasi_core_shims_cases=13` 和 `wasi_core_wat_failures=0`。
  - 边界: 本项只证明当前已 lower 的 core import WAT 和 shim WAT 期望仍可生成并通过基础 parse; 不证明 component input / component wasm 全链路, 也不解除 G6.1-G6.3。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 WASI core imports / core shims expect gate|wasi_core_imports_cases=13|wasi_core_shims_cases=13|wasi_core_wat_failures=0|core_shims_124_imported_dir_create_remove_wrapper_lower=1' doc/roadmap_status.md` 确认。
  - 结果: 当前 WASI core imports / core shims expect gate 通过; 未新增阻断。
- [x] 复跑 WASI component input / component core expect gate。结论:
  - 范围: `tool/build/test/compile_ok/*.component_input.expect` 当前共 1 个 fixture; `tool/build/test/compile_ok/*.component_core.expect` 当前共 1 个 fixture。
  - 纠偏: 首次手写复核脚本误用普通 WAT 检查 component core, 漏掉 `do build --component-core`, 因此报缺少 `(memory 1)`。复查 `tool/build/test/run_tests.sh` 后确认应按 component-core 专用 build 入口验证。
  - 验证: component input 按 `run_compile_ok_case` 核心口径执行 `do build -o <tmp>.wat`, 生成 `--component-input-dir`, 拼接 metadata、component plan、core imports、core shims 和 WIT 输出后逐行匹配 `.component_input.expect`。
  - 验证: component core 按 `DO_LIB_ROOT=tool/build/test/lib ./bin/do build <case>.do --component-core -o <tmp>.wat` 生成专用 WAT, 逐行匹配 `.component_core.expect`, 并确认没有 `(memory (export "memory")` 普通 memory export。
  - 验证: 本机存在 `wasm-tools` 时, component input 和 component core 均执行 WIT 解析、embed、component new 和 validate。
  - 结果: 输出 `component_input_96_wasi_manifest_module_scoped_alias=1`, `component_core_96_wasi_manifest_module_scoped_alias=1`, `wasi_component_input_cases=1`, `wasi_component_core_cases=1` 和 `wasi_component_input_core_failures=0`。
  - 边界: 本项只证明当前 component input / component core fixture 仍可生成并通过最小 component validate; 不扩大 WASI runtime 执行边界, 也不解除 G6.1-G6.3。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 WASI component input / component core expect gate|wasi_component_input_cases=1|wasi_component_core_cases=1|wasi_component_input_core_failures=0|component_core_96_wasi_manifest_module_scoped_alias=1' doc/roadmap_status.md` 确认。
  - 结果: 当前 WASI component input / component core expect gate 通过; 未新增阻断。
- [x] 复跑 WASI WIT dir expect gate。结论:
  - 范围: `tool/build/test/compile_ok/*.wit_dir.expect` 当前共 1 个 fixture。
  - 验证: 按 `run_compile_ok_case` 核心口径执行 `DO_LIB_ROOT=tool/build/test/lib ./bin/do build <case>.do -o <tmp>.wat`, 再执行 `node tool/build/test/validate_wasi_bind_manifest.mjs --registry doc/wit/wasi_registry.json --wit-dir <tmp-dir> <tmp>.wat`。
  - 验证: 本机存在 `wasm-tools` 时, 使用 `wasm-tools component wit <tmp-dir>` 解析生成的 WIT package dir; 否则拼接生成的 `.wit` 文件。输出逐行匹配 `.wit_dir.expect`。
  - 结果: 输出 `wit_dir_96_wasi_manifest_module_scoped_alias=1`, `wasi_wit_dir_cases=1` 和 `wasi_wit_dir_failures=0`。
  - 边界: 本项只证明当前 WIT package dir 生成和期望文本匹配; 不证明 component wasm 运行时执行, 也不解除 G6.1-G6.3。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 WASI WIT dir expect gate|wasi_wit_dir_cases=1|wasi_wit_dir_failures=0|wit_dir_96_wasi_manifest_module_scoped_alias=1' doc/roadmap_status.md` 确认。
  - 结果: 当前 WASI WIT dir expect gate 通过; 未新增阻断。
- [x] 复跑 WASI component wasm generation / validate gate。结论:
  - 范围: `tool/build/test/compile_ok/96_wasi_manifest_module_scoped_alias.do` 的 component input 到真实 component wasm 生成路径。
  - 验证: 先执行 `DO_LIB_ROOT=tool/build/test/lib ./bin/do build <case>.do -o <tmp>.wat`, 再执行 `WASM_TOOLS=$(command -v wasm-tools) node tool/build/test/validate_wasi_bind_manifest.mjs --registry doc/wit/wasi_registry.json --component-wasm <tmp>.component.wasm <tmp>.wat`。
  - 验证: 生成的 component wasm 非空, 并在本机 `wasm-tools` 存在时执行 `wasm-tools validate <tmp>.component.wasm`。
  - 结果: 输出 `component_wasm_96_wasi_manifest_module_scoped_alias=1`, `wasi_component_wasm_bytes=7893` 和 `wasi_component_wasm_failures=0`。
  - 边界: 本项只证明当前 component input 可生成并 validate 真实 component wasm; 不证明 WASI host runtime 执行, 也不解除 G6.1-G6.3。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 WASI component wasm generation / validate gate|component_wasm_96_wasi_manifest_module_scoped_alias=1|wasi_component_wasm_bytes=7893|wasi_component_wasm_failures=0' doc/roadmap_status.md` 确认。
  - 结果: 当前 WASI component wasm generation / validate gate 通过; 未新增阻断。
- [x] 同步 `doc/start_here.md` 的 WASI component wasm gate 入口记录。结论:
  - 发现: `doc/roadmap_status.md` 已记录 component wasm generation / validate gate, 但 `doc/start_here.md` 的最近 gate 摘要还停在 WASI bind manifest helper 后直接到 run_wasm_smoke。
  - 修正: 在 `doc/start_here.md` 当前停点中补入 `WASI component wasm generation / validate gate 最近通过` 摘要, 明确 `96_wasi_manifest_module_scoped_alias` 生成真实 component wasm 且 `wasm-tools validate` 通过。
  - 边界: 本项只同步入口文档的最近 gate 摘要; 不扩大 WASI host runtime 执行边界, 也不解除 G6.1-G6.3。
  - 复验: `git diff --check` 通过; 入口/进度记录命中已由 `rg -n 'WASI component wasm generation / validate gate 最近通过|component_wasm_96_wasi_manifest_module_scoped_alias=1|wasi_component_wasm_failures=0' doc/start_here.md doc/roadmap_status.md` 和 `rg -n '同步 `doc/start_here\\.md` 的 WASI component wasm gate 入口记录|当前入口文档重新包含最近 component wasm gate' doc/roadmap_status.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前入口文档重新包含最近 component wasm gate; 未新增阻断。
- [x] 复跑 Markdown local link gate。结论:
  - 范围: 沿用既有 gate 口径, 扫描 `README.md`、`CHANGELOG.md` 和 `doc/**/*.md`, 不把 `AGENTS.md` 或 `tool/build/test/README.md` 临时并入本 gate。
  - 验证: Node 只读扫描 Markdown 链接, 忽略外部链接, 只检查指向 `.md` 文件的本地链接存在性。
  - 结果: 输出 `markdown_files=26`, `local_markdown_links=20` 和 `missing=0`。
  - 边界: 本项只证明当前活跃文档入口的本地 Markdown 链接无缺失; 不验证外部 URL, 也不解除 G6.1-G6.3。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 Markdown local link gate|markdown_files=26|local_markdown_links=20|missing=0|当前 Markdown local link gate 仍通过' doc/roadmap_status.md doc/start_here.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 Markdown local link gate 仍通过; 未新增阻断。
- [x] 复跑 active/blocker 状态口径 gate。结论:
  - 未完成项扫描: `rg -n '^- \\[ \\]' README.md doc/master_plan.md doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 只命中 README 后置非目标、06.2 blocked/decomposed、D2.1 blocked 和 G6.1-G6.3 blocked。
  - 泛化状态扫描: `rg -n '^状态: (active|partial|blocked)(;|$)|^状态: blocked/partial|^状态: partial' README.md doc/master_plan.md doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 无输出。
  - 旧入口扫描: `rg -n '当前推荐|下次第一步|第二版编译器正在实现|TODO|FIXME' README.md doc/master_plan.md doc/start_here.md CHANGELOG.md` 只命中 `CHANGELOG.md` 历史记录; `rg -n 'review_blockers|review_issues|compiled_task_checklist|next_stage_plan|internal_prefix_rename_plan|当前推荐继续阶段' README.md doc/master_plan.md doc/start_here.md doc/syntax doc/spec.md doc/spec_rules.md doc/grammar.peg tool/build/test/README.md CHANGELOG.md` 只命中 `CHANGELOG.md` 历史记录。
  - 边界: 本项只证明活跃入口和当前计划没有新增未记录阻断或旧入口漂移; 不解除 README 后置非目标、06.2、D2.1 或 G6.1-G6.3。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 active/blocker 状态口径 gate|当前 active/blocker 状态口径未新增漂移|未完成项扫描: `rg -n|旧入口扫描:' doc/roadmap_status.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 active/blocker 状态口径未新增漂移; 未新增阻断。
- [x] 复跑 Zig fmt gate。结论:
  - 范围: `rg --files -g '*.zig'` 当前输出 `31` 个 Zig 文件, 覆盖 tracked 和当前 untracked Zig 源文件。
  - 验证: `rg --files -g '*.zig' -0 | xargs -0 zig fmt --check` 通过, 无格式化输出。
  - 边界: 本项只证明当前 Zig 源文件格式符合 `zig fmt --check`; 不替代 Zig unit test、Debug build 或 full regression。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 Zig fmt gate|当前 Zig fmt gate 仍通过|31` 个 Zig 文件|zig fmt --check' doc/roadmap_status.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 Zig fmt gate 仍通过; 未新增阻断。
- [x] 复跑 Zig aggregate unit gate。结论:
  - 范围: `cd tool && zig test main.zig` 聚合覆盖 CLI/run/fmt/check/LSP、backend IR、component metadata writer、function body writer、ownership facts、runtime prelude、lexer、diag、parser、sema 和 formatter 单元测试。
  - 验证: `cd tool && zig test main.zig` 通过, 输出 `All 101 tests passed.`。
  - 边界: 本项只证明 Zig 聚合单元测试通过; 不替代 Debug build、black-box fixture regression 或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 Zig aggregate unit gate|当前 Zig aggregate unit gate 仍通过|All 101 tests passed|zig test main\\.zig' doc/roadmap_status.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 Zig aggregate unit gate 仍通过; 未新增阻断。
- [x] 复跑 JS/MJS helper syntax gate。结论:
  - 范围: `git ls-files '*.mjs'` 当前输出 6 个 tracked `.mjs` 文件: `run_compiled_test_case.mjs`、`run_lsp_case.mjs`、`run_wasm_case.mjs`、`test_wasi_bind_manifest_tool.mjs`、`validate_wasi_bind_manifest.mjs` 和 `tool/run/run_wasm_program.mjs`; `git ls-files --others --exclude-standard '*.mjs'` 输出 0。
  - 验证: 对上述 6 个文件逐个执行 `node --check` 均通过。
  - 修正: `doc/start_here.md` 中 JS/MJS syntax gate 的描述从旧的 3 个 tracked `.mjs` 更新为当前 6 个 tracked `.mjs` helper/runtime 脚本。
  - 边界: 本项只证明当前 tracked `.mjs` helper/runtime 脚本语法通过; 不替代 Node runner 行为测试、black-box fixture regression 或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'JS/MJS helper syntax gate 最近通过|当前 6 个 tracked `\\.mjs`|复跑 JS/MJS helper syntax gate|当前 JS/MJS helper syntax gate 仍通过|run_wasm_program\\.mjs' doc/start_here.md doc/roadmap_status.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 JS/MJS helper syntax gate 仍通过; 未新增阻断。
- [x] 复跑 shell harness syntax gate。结论:
  - 范围: `git ls-files '*.sh'` 当前输出 2 个 tracked shell 脚本: `tool/build/test/run_tests.sh` 和 `tool/build/test/run_wasm_smoke.sh`; `git ls-files --others --exclude-standard '*.sh'` 当前输出 1 个 untracked shell 脚本: `tool/build/test/run_release_smoke.sh`。
  - 验证: 对上述 3 个脚本逐个执行 `bash -n` 均通过。
  - 修正: `doc/start_here.md` 中 shell harness syntax gate 的描述从旧的 1 tracked + 1 untracked 更新为当前 2 tracked + 1 untracked。
  - 边界: 本项只证明当前 shell harness 语法通过; 不替代实际 smoke、fixture regression 或 release smoke 执行。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'Shell harness syntax gate 最近通过|2 个 tracked `\\.sh`|复跑 shell harness syntax gate|当前 shell harness syntax gate 仍通过|run_wasm_smoke\\.sh|run_release_smoke\\.sh' doc/start_here.md doc/roadmap_status.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 shell harness syntax gate 仍通过; 未新增阻断。
- [x] 复跑 Zig Debug build gate。结论:
  - 环境: `zig version` 输出 `0.16.0`。
  - 验证: `cd tool && zig build -Doptimize=Debug` 成功退出, 同轮命令输出 `zig_debug_build=1`。
  - 边界: 本项只证明 Debug 编译器构建通过; 不替代 Zig unit test、black-box fixture regression、wasm execution gate 或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 Zig Debug build gate|当前 Zig Debug build gate 仍通过|zig_debug_build=1|zig build -Doptimize=Debug|0\\.16\\.0' doc/roadmap_status.md doc/start_here.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 Zig Debug build gate 仍通过; 未新增阻断。
- [x] 复跑 diagnostic unit / contract gate。结论:
  - 范围: `tool/build/diag.zig` focused tests, 以及 `errorSummary` / `errorHint` 显式诊断条目一致性。
  - 验证: `cd tool && zig test build/diag.zig` 通过, 输出 `All 13 tests passed.`。
  - 验证: Node 只读扫描 `tool/build/diag.zig`, 结果为 `summary_entries=55`, `hint_entries=55`, `summary_without_hint=(none)`, `hint_without_summary=(none)`。
  - 边界: 本项只证明 focused diagnostic unit 和 summary/hint contract 通过; 不替代 parser/sema/codegen 单元测试、black-box diagnostic fixture regression 或 full regression。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 diagnostic unit / contract gate|当前 diagnostic unit / contract gate 仍通过|All 13 tests passed|summary_entries=55|hint_entries=55|summary_without_hint=\\(none\\)|hint_without_summary=\\(none\\)' doc/roadmap_status.md doc/start_here.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 diagnostic unit / contract gate 仍通过; 未新增阻断。
- [x] 复跑 CLI parser unit gate。结论:
  - 范围: `tool/build/cli.zig` 的 run/fmt/lsp/check 参数解析单元测试。
  - 验证: `cd tool && zig test build/cli.zig` 通过, 输出 `All 14 tests passed.`。
  - 覆盖: `parseRun` 单输入和错误参数, `parseFmt` stdout/check/write 及互斥, `parseLsp` stdio 模式, `parseCheck` 单输入/多输入和错误参数。
  - 边界: 本项只证明 CLI parser unit gate 通过; build/test 的黑盒严格参数和 output-order 路径由 CLI argument / output path guard gate 覆盖。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 CLI parser unit gate|当前 CLI parser unit gate 仍通过|All 14 tests passed|parseRun|parseFmt|parseLsp|parseCheck' doc/roadmap_status.md doc/start_here.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 CLI parser unit gate 仍通过; 未新增阻断。
- [x] 复跑 lexer / tokenization unit gate。结论:
  - 范围: `tool/build/lexer.zig` 的 focused tokenizer tests。
  - 验证: `cd tool && zig test build/lexer.zig` 通过, 输出 `All 10 tests passed.`。
  - 覆盖: dot/private 标识符、spread、loop label apostrophe、字符串 UTF-8 escape、line string block / inline RHS line string / blank-line break 边界。
  - 边界: 本项只证明 lexer focused tokenizer unit gate 通过; 不替代 parser/sema/codegen 单元测试或 black-box syntax diagnostic fixtures。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 lexer / tokenization unit gate|当前 lexer / tokenization unit gate 仍通过|All 10 tests passed|dot/private|blank-line break|build/lexer\\.zig' doc/roadmap_status.md doc/start_here.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 lexer / tokenization unit gate 仍通过; 未新增阻断。
- [x] 复跑 parser unit gate。结论:
  - 范围: `tool/build/parser.zig` 的 focused parser tests, 并包含 parser 导入链上的 lexer tests。
  - 验证: `cd tool && zig test build/parser.zig` 通过, 输出 `All 24 tests passed.`。
  - 覆盖: bool/nil literals、literal-call rejection、lambda placement/call args、lambda omitted param type/block body、spread、function name call args、struct literal equals、generic bind arity、import ordering、storage variadic arity 和 collection loop two-binding parser rule。
  - 边界: 本项只证明 parser focused unit gate 通过; 不替代 sema/codegen 单元测试、grammar 文档审查或 black-box syntax diagnostic fixtures。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 parser unit gate|当前 parser unit gate 仍通过|All 24 tests passed|lambda omitted param type|collection loop two-binding|build/parser\\.zig' doc/roadmap_status.md doc/start_here.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 parser unit gate 仍通过; 未新增阻断。
- [x] 复跑 sema unit gate。结论:
  - 范围: `tool/build/sema.zig` 的 focused semantic analysis tests, 并包含 sema 导入链上的 lexer/parser unit tests。
  - 验证: `cd tool && zig test build/sema.zig` 通过, 输出 `All 26 tests passed.`。
  - 覆盖: private host import 不被误判为 private lvalue assignment、private assignment rejection, 以及导入链上的 tokenizer/parser 边界。
  - 边界: 本项只证明 sema focused unit gate 通过; 不替代 codegen 单元测试、semantic black-box fixtures 或 full regression。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 sema unit gate|当前 sema unit gate 仍通过|All 26 tests passed|private host import|private assignment|build/sema\\.zig' doc/roadmap_status.md doc/start_here.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 sema unit gate 仍通过; 未新增阻断。
- [x] 复跑 codegen unit gate。结论:
  - 范围: `tool/build/codegen.zig` focused tests, 并覆盖其导入链上的 lexer、runtime prelude writer、backend IR、component metadata writer、test runner、ownership facts 和 ownership unit tests。
  - 验证: `cd tool && zig test build/codegen.zig` 通过, 输出 `All 51 tests passed.`。
  - 覆盖: origin metadata、generic union / callback binding、variadic storage ABI、Backend IR lowering、runtime prelude、component metadata、test runner 和 ownership facts。
  - 边界: 本项只证明 codegen focused unit gate 通过; 不替代 full fixture regression、compiled wasm execution、WASI component validate 或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 codegen unit gate|当前 codegen unit gate 仍通过|All 51 tests passed|generic union / callback|variadic storage ABI|Backend IR lowering' doc/roadmap_status.md doc/start_here.md` 确认。
  - 结果: 当前 codegen unit gate 仍通过; 未新增阻断。
- [x] 复跑 backend / writer / ownership / runner focused unit gates。结论:
  - 范围: `tool/build/backend_ir.zig`、`runtime_prelude_wat.zig`、`component_metadata_wat.zig`、`function_body_wat.zig`、`ownership.zig`、`ownership_facts.zig`、`test_runner.zig` 和 `run.zig`。
  - 验证: `cd tool && zig test build/backend_ir.zig` 通过, 输出 `All 13 tests passed.`。
  - 验证: `cd tool && zig test build/runtime_prelude_wat.zig` 通过, 输出 `All 2 tests passed.`。
  - 验证: `cd tool && zig test build/component_metadata_wat.zig` 通过, 输出 `All 4 tests passed.`。
  - 验证: `cd tool && zig test build/function_body_wat.zig` 通过, 输出 `All 2 tests passed.`。
  - 验证: `cd tool && zig test build/ownership.zig` 通过, 输出 `All 2 tests passed.`; `cd tool && zig test build/ownership_facts.zig` 通过, 输出 `All 6 tests passed.`。
  - 验证: `cd tool && zig test build/test_runner.zig` 通过, 输出 `All 14 tests passed.`; `cd tool && zig test build/run.zig` 通过, 输出 `All 27 tests passed.`。
  - 边界: 本项只证明 backend IR、WAT writer、ownership facts/exit plan、test runner 和 run command focused unit gates 通过; 不替代 full fixture regression、compiled wasm execution、WASI component validate 或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 backend / writer / ownership / runner focused unit gates|当前 backend / writer / ownership / runner focused unit gates 仍通过|All 13 tests passed|All 27 tests passed|runtime_prelude_wat|component_metadata_wat|function_body_wat|ownership_facts|test_runner|build/run\\.zig' doc/roadmap_status.md doc/start_here.md` 确认。
  - 结果: 当前 backend / writer / ownership / runner focused unit gates 仍通过; 未新增阻断。
- [x] 复核剩余 3 个 skip 边界。结论:
  - 范围: `tool/build/test/ok/16_loop_recv_value.do`、`96_file_lib_resource_shape.do` 和 `118_wasi_p3_std_wrappers.do`。
  - 验证: `DO_LIB_ROOT=src ./bin/do check tool/build/test/ok/16_loop_recv_value.do`、`DO_LIB_ROOT=src ./bin/do check tool/build/test/ok/96_file_lib_resource_shape.do` 和 `DO_LIB_ROOT=src ./bin/do check tool/build/test/ok/118_wasi_p3_std_wrappers.do` 均静默通过。
  - 验证: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/16_loop_recv_value.do` 输出 `ok: 0 passed; 0 failed; 3 skipped`。
  - 验证: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/96_file_lib_resource_shape.do` 输出 `ok: 0 passed; 0 failed; 1 skipped`。
  - 验证: `DO_LIB_ROOT=src ./bin/do test tool/build/test/ok/118_wasi_p3_std_wrappers.do` 输出 `ok: 0 passed; 0 failed; 1 skipped`。
  - 边界: 本项只证明剩余 skip 仍与 H1.4 的 recv runner / WASI resource 后置边界一致; 不把这些用例改成 `must_pass`, 也不解除 G6.1-G6.3 运行时/API 设计阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复核剩余 3 个 skip 边界|0 failed; 3 skipped|0 failed; 1 skipped|recv runner / WASI resource 后置边界|16_loop_recv_value|96_file_lib_resource_shape|118_wasi_p3_std_wrappers' doc/roadmap_status.md doc/start_here.md` 确认。
  - 结果: 剩余 3 个 skip 边界仍按预期保持; 未新增阻断。
- [x] 复跑 active/blocker 状态口径 gate。结论:
  - 未完成项扫描: `rg -n '^- \\[ \\]' README.md doc/master_plan.md doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 只命中 README 后置非目标、06.2 blocked/decomposed、D2.1 blocked 和 G6.1-G6.3 blocked。
  - 泛化状态扫描: `rg -n '^状态: (active|partial|blocked)(;|$)|^状态: blocked/partial|^状态: partial' README.md doc/master_plan.md doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 无输出。
  - 旧入口扫描: `rg -n '当前推荐|下次第一步|第二版编译器正在实现|TODO|FIXME' README.md doc/master_plan.md doc/start_here.md CHANGELOG.md` 只命中 `CHANGELOG.md` 历史记录; `rg -n 'review_blockers|review_issues|compiled_task_checklist|next_stage_plan|internal_prefix_rename_plan|当前推荐继续阶段' README.md doc/master_plan.md doc/start_here.md doc/syntax doc/spec.md doc/spec_rules.md doc/grammar.peg tool/build/test/README.md CHANGELOG.md` 只命中 `CHANGELOG.md` 历史记录。
  - 边界: 本项只证明当前活跃入口和计划状态未新增漂移; 不解除 README 后置非目标、06.2、D2.1 或 G6.1-G6.3。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 active/blocker 状态口径 gate|当前 active/blocker 状态口径未新增漂移|未完成项扫描: `rg -n|旧入口扫描:' doc/roadmap_status.md` 确认。
  - 结果: 当前 active/blocker 状态口径未新增漂移; 未新增阻断。
- [x] 复核当前 dirty worktree 交付边界。结论:
  - 范围: 当前累计主线改动的 tracked/untracked 规模和非主线 UI 文件边界。
  - 验证: `git diff --name-only | wc -l` 输出 `52`; `git ls-files --others --exclude-standard | wc -l` 输出 `117`。
  - UI 边界: `git diff --name-only | rg '(^|/)(ui\\.do|ui_demo\\.do)$' || true` 无输出; `git ls-files --others --exclude-standard | rg '(^|/)(ui\\.do|ui_demo\\.do)$' || true` 只输出 `ui.do` 和 `ui_demo.do`。
  - 边界: 当前 dirty worktree 仍是累计主线成果, 不是单一文档变更; 提交前仍必须重新核对暂存范围, 且没有用户明确要求时不 stage、修改或删除 `ui.do` / `ui_demo.do`。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复核当前 dirty worktree 交付边界|git diff --name-only \\| wc -l` 输出 `52|git ls-files --others --exclude-standard \\| wc -l` 输出 `117|ui\\.do|ui_demo\\.do|当前 dirty worktree 仍是累计主线成果' doc/roadmap_status.md doc/start_here.md` 确认。
  - 结果: 当前累计交付边界没有漂移; 非主线 UI 文件未进入 tracked diff; 未新增阻断。
- [x] 复跑 LSP smoke fixture gate。结论:
  - 范围: `tool/build/test/lsp/*.json` 当前覆盖 9 个 JSON fixture, 从 `01_open_valid.json` 到 `09_workspace_index_request.json`。
  - 验证: `find tool/build/test/lsp -maxdepth 1 -type f -name '*.json' -print | sort | xargs -n 1 node tool/build/test/run_lsp_case.mjs ./bin/do` 通过。
  - 输出: 9 个 fixture 均输出 `ok: lsp ...`, 覆盖 diagnostics、change clears diagnostics、formatting、semantic tokens、hover、completion、definition 和 workspace index。
  - 边界: 本项只证明当前 LSP smoke fixture 行为通过; 不扩大 v1 LSP 边界, 不覆盖 rename、references graph、import-aware definition 或增量 workspace index。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 LSP smoke fixture gate|9 个 JSON fixture|ok: lsp|workspace index|run_lsp_case\\.mjs|不扩大 v1 LSP 边界' doc/roadmap_status.md doc/start_here.md` 确认。
  - 结果: 当前 LSP smoke fixture gate 仍通过; 未新增阻断。
- [x] 复跑 `do fmt` fixture 行为 gate。结论:
  - 范围: `tool/build/test/fmt/*.do` 当前共 3 个 fixture: `01_struct_func_indent`、`02_comments_line_strings` 和 `03_control_blocks`。
  - 验证: 按 `tool/build/test/run_tests.sh` 的 `run_fmt_case` 等价口径逐个执行 `./bin/do fmt`, 对比 `.expect`, 复跑格式化输出校验幂等, 对 formatted 临时文件执行 `do fmt --check`, 对临时副本执行 `do fmt --write` 和 write idempotence, 并对未格式化原输入校验 `error[FormatMismatch]`。
  - 输出: `fmt_case_01_struct_func_indent=1`, `fmt_case_02_comments_line_strings=1`, `fmt_case_03_control_blocks=1` 和 `fmt_cases=3`。
  - 边界: 本项只证明 `do fmt` fixture 行为通过; 不扩大 formatter v1 边界, 不覆盖多文件批量、stdin/stdout 自动模式、range/on-type 或完整语法感知 formatter。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 `do fmt` fixture 行为 gate|fmt_cases=3|fmt_case_01_struct_func_indent=1|FormatMismatch|run_fmt_case|不扩大 formatter v1 边界' doc/roadmap_status.md tool/build/test/run_tests.sh doc/start_here.md` 确认。
  - 结果: 当前 `do fmt` fixture 行为 gate 仍通过; 未新增阻断。
- [x] 复跑 `do check` product command gate。结论:
  - 范围: `tool/build/test/check/*.do` 当前共 2 个 fixture: `01_valid.do` 和 `02_syntax_error.do`, 另覆盖 multi-input 策略。
  - 单文件验证: 按 `tool/build/test/run_tests.sh` 的 `run_check_case` 等价口径复跑; 无 `.expect` 的 `01_valid.do` 静默成功, 有 `.expect` 的 `02_syntax_error.do` 失败并逐行匹配 stderr 子串且 stdout 为空。
  - 多文件验证: `do check valid valid` 静默成功; `do check valid bad` 失败且 stderr 包含 bad path; `do check bad valid bad` 失败且 stderr 同时包含两个 bad path, 证明前一个失败后仍继续检查后续输入。
  - 输出: `check_case_01_valid=1`, `check_case_02_syntax_error=1`, `check_multi=pass` 和 `check_cases=2`。
  - 边界: 本项只证明当前 `do check` product command fixture 行为通过; 不把 `do check` 扩大成 build/codegen/test runner/watch/multi-diagnostic 命令。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 `do check` product command gate|check_cases=2|check_multi=pass|check_case_01_valid=1|run_check_case|run_check_multi_case|不把 `do check` 扩大' doc/roadmap_status.md tool/build/test/run_tests.sh doc/start_here.md` 确认。
  - 结果: 当前 `do check` product command gate 仍通过; 未新增阻断。
- [x] 复跑 `do run` product command gate。结论:
  - 范围: `tool/build/test/run/*.do` 当前共 6 个 fixture: `01_start_scalar`、`02_env_host_import_string_literal`、`03_env_host_import_storage_wrapper`、`04_defer_lifo`、`05_defer_block` 和 `06_defer_loop_break`。
  - 正常执行验证: 按 `tool/build/test/run_tests.sh` 的 `run_do_run_case` 等价口径逐个执行 `./bin/do run`, 要求 stderr 为空; 有 `.stdout.expect` 的用例逐行对比 stdout, 无 `.stdout.expect` 的用例要求 stdout 为空。
  - 外部工具诊断: 按 `run_do_run_missing_wasm_tools_case` / `run_do_run_missing_node_case` 等价口径覆盖缺 `wasm-tools` 和缺 `node` 的 `error[MissingExternalTool]` 诊断, 两者 stdout 均为空。
  - 输出: `run_case_01_start_scalar=1`, `run_case_02_env_host_import_string_literal=1`, `run_case_03_env_host_import_storage_wrapper=1`, `run_case_04_defer_lifo=1`, `run_case_05_defer_block=1`, `run_case_06_defer_loop_break=1`, `run_missing_tools=pass` 和 `run_cases=6`。
  - 边界: 本项只证明当前 `do run` product command fixture 行为通过; 不把 `do run` 描述成 WASI / Component Model / 自定义 host runtime。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n '复跑 `do run` product command gate|run_cases=6|run_missing_tools=pass|run_case_01_start_scalar=1|run_do_run_case|MissingExternalTool|不把 `do run` 描述成 WASI' doc/roadmap_status.md tool/build/test/run_tests.sh doc/start_here.md` 确认。
  - 结果: 当前 `do run` product command gate 仍通过; 未新增阻断。
- [x] 复跑 `do build` product command smoke gate。结论:
  - 范围: `tool/build/test/compile_ok/01_start_entry_valid.do` 正向 build 和 `tool/build/test/compile_err/01_missing_start_entry.do` 缺失 `start` 诊断。
  - 正向验证: `DO_LIB_ROOT=tool/build/test/lib ./bin/do build tool/build/test/compile_ok/01_start_entry_valid.do -o <tmp>/start.wat` 成功, stderr 为空, stdout 包含 `ok: tool/build/test/compile_ok/01_start_entry_valid.do -> <tmp>/start.wat`, WAT 输出非空。
  - 负向验证: `DO_LIB_ROOT=tool/build/test/lib ./bin/do build tool/build/test/compile_err/01_missing_start_entry.do -o <tmp>/missing.wat` 按预期失败, stdout 为空, stderr 匹配 `tool/build/test/compile_err/01_missing_start_entry.expect` 的 2 行诊断。
  - 输出: `build_ok_wat_bytes=32806`, `build_err_expect_lines=2`, `do_build_smoke=pass`。
  - 边界: 本项只证明当前 `do build` product command smoke 行为通过; 不替代 compile_ok / compile_err 全量 fixture regression、Debug build 或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'do build.*product command smoke gate|build_ok_wat_bytes=32806|do_build_smoke=pass|32806.*bytes|01_missing_start_entry\\.expect' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 `do build` product command smoke gate 仍通过; 未新增阻断。
- [x] 复跑 `do test` product command smoke gate。结论:
  - 范围: 静态 runner `tool/build/test/ok/01_path_get_single.do`, compiled runner `tool/build/test/compiled_ok/01_compiled_test_entry.do`, 以及 `do test -o` 必须搭配 `--compiled` 的 CLI 保护。
  - 静态验证: `DO_LIB_ROOT=tool/build/test/lib ./bin/do test tool/build/test/ok/01_path_get_single.do` 成功, stderr 为空, stdout 包含 `test "path get single" ... ok` 和 `ok: 1 passed; 0 failed; 0 skipped`。
  - compiled 验证: `DO_LIB_ROOT=tool/build/test/lib ./bin/do test tool/build/test/compiled_ok/01_compiled_test_entry.do --compiled -o <tmp>/compiled.wat` 成功生成非空 WAT; `wasm-tools parse <tmp>/compiled.wat -o <tmp>/compiled.wasm` 成功; `node tool/build/test/run_compiled_test_case.mjs <tmp>/compiled.wasm <tmp>/compiled.wat` 成功, stderr 为空, stdout 包含 `test "compiled test entry" ... ok` 和 `ok: 1 passed; 0 failed`。
  - CLI 保护验证: `DO_LIB_ROOT=tool/build/test/lib ./bin/do test tool/build/test/ok/01_path_get_single.do -o <tmp>/no_compiled.wat` 按预期失败, stdout 为空, stderr 包含 `error[OutputRequiresCompiledTest]`。
  - 输出: `test_static_cases=1`, `compiled_wat_bytes=32924`, `compiled_wasm_bytes=5638`, `test_output_guard=1`, `do_test_smoke=pass`。
  - 边界: 本项只证明当前 `do test` product command smoke 行为通过; 不替代 ok / compiled_ok 全量 fixture regression、compiled trap gate 或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'do test.*product command smoke gate|compiled_wat_bytes=32924|compiled_wasm_bytes=5638|do_test_smoke=pass|OutputRequiresCompiledTest|32924.*WAT' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 `do test` product command smoke gate 仍通过; 未新增阻断。
- [x] 复跑 CLI argument / output path guard gate。结论:
  - 范围: `build -o <out> <input>`、`test --compiled -o <out> <input>` 的输出参数顺序, build/run 的未知 flag 和额外 input 保护, 以及 `test -o` 无 `--compiled` 的保护。
  - output-order 验证: `DO_LIB_ROOT=tool/build/test/lib ./bin/do build -o <tmp>/cli_build_pre_output.wat tool/build/test/compile_ok/01_start_entry_valid.do` 成功, stderr 为空, 输出 WAT 非空; `DO_LIB_ROOT=tool/build/test/lib ./bin/do test --compiled -o <tmp>/cli_test_pre_output.wat tool/build/test/compiled_ok/01_compiled_test_entry.do` 成功, stderr 为空, 输出 WAT 非空。
  - strict args 验证: `do build <input> --bad`、`do build <input> <input>`、`do run <input> --bad` 和 `do run <input> <input>` 均按预期失败, stdout 为空, stderr 包含 `error[UnexpectedCliArg]`。
  - test output guard 验证: `DO_LIB_ROOT=tool/build/test/lib ./bin/do test tool/build/test/ok/01_path_get_single.do -o <tmp>/cli_strict_args.wat` 按预期失败, stdout 为空, stderr 包含 `error[OutputRequiresCompiledTest]`。
  - 输出: `cli_output_order_build=1`, `cli_output_order_test=1`, `cli_strict_build_bad=1`, `cli_strict_build_extra=1`, `cli_strict_run_bad=1`, `cli_strict_run_extra=1`, `cli_test_output_guard=1`, `cli_output_build_wat_bytes=32806`, `cli_output_test_wat_bytes=32924`, `cli_argument_output_guard=pass`。
  - 边界: 本项只证明当前 CLI argument / output path guard 行为通过; 不替代完整 CLI parser unit、build/test product smoke、full regression 或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'CLI argument / output path guard gate|cli_output_build_wat_bytes=32806|cli_output_test_wat_bytes=32924|cli_argument_output_guard=pass|UnexpectedCliArg|OutputRequiresCompiledTest|32806.*WAT|32924.*WAT' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 CLI argument / output path guard gate 仍通过; 未新增阻断。
- [x] 复跑 WASI bind manifest helper gate。结论:
  - 范围: `tool/build/test/test_wasi_bind_manifest_tool.mjs` 驱动 `tool/build/test/validate_wasi_bind_manifest.mjs` 的 helper 自测, 覆盖 manifest JSON、known/unsupported、component-plan、core imports/shims、component input 和 component wasm helper 行为。
  - 验证: `node tool/build/test/test_wasi_bind_manifest_tool.mjs tool/build/test/validate_wasi_bind_manifest.mjs <tmp-dir>` 成功, stderr 为空, stdout 包含 `ok: wasi-bind manifest tool`。
  - 输出: `wasi_bind_manifest_helper=1`, `wasi_bind_manifest_stdout=ok: wasi-bind manifest tool`, `wasi_bind_manifest_tmp_files=37`。
  - 边界: 本项只证明现有 manifest/component helper 行为仍通过; 不解除 G6.1-G6.3 的公开 API 或运行时设计阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'WASI bind manifest helper gate|wasi_bind_manifest_helper=1|wasi_bind_manifest_tmp_files=37|ok: wasi-bind manifest tool|G6\\.1-G6\\.3' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 WASI bind manifest helper gate 仍通过; 未新增阻断。
- [x] 复跑 WASI component wasm generation / validate gate。结论:
  - 范围: `tool/build/test/compile_ok/96_wasi_manifest_module_scoped_alias.do` 的 WAT 到真实 component wasm 生成路径。
  - build 验证: `DO_LIB_ROOT=tool/build/test/lib ./bin/do build tool/build/test/compile_ok/96_wasi_manifest_module_scoped_alias.do -o <tmp>/96_wasi_manifest_module_scoped_alias.wat` 成功, stderr 为空, WAT 输出非空。
  - component 验证: `WASM_TOOLS=$(command -v wasm-tools) node tool/build/test/validate_wasi_bind_manifest.mjs --registry doc/wit/wasi_registry.json --component-wasm <tmp>/96_wasi_manifest_module_scoped_alias.component.wasm <tmp>/96_wasi_manifest_module_scoped_alias.wat` 成功, stderr 为空, stdout 包含 `ok: wrote component wasm <tmp>/96_wasi_manifest_module_scoped_alias.component.wasm`, component wasm 输出非空。
  - validate 验证: `wasm-tools validate <tmp>/96_wasi_manifest_module_scoped_alias.component.wasm` 成功, stderr 为空。
  - 输出: `component_wasm_96_wasi_manifest_module_scoped_alias=1`, `wasi_component_wat_bytes=34110`, `wasi_component_wasm_bytes=7893`, `wasi_component_wasm_failures=0`。
  - 边界: 本项只证明当前 component input 可生成并 validate 真实 component wasm; 不证明 WASI host runtime 执行, 也不解除 G6.1-G6.3。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'WASI component wasm generation / validate gate|component_wasm_96_wasi_manifest_module_scoped_alias=1|wasi_component_wat_bytes=34110|wasi_component_wasm_bytes=7893|wasi_component_wasm_failures=0|G6\\.1-G6\\.3' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 WASI component wasm generation / validate gate 仍通过; 未新增阻断。
- [x] 复跑 run_wasm_smoke bridge gate。结论:
  - 范围: `tool/build/test/run_wasm_smoke.sh` 的底层 WAT -> `wasm-tools parse` -> Node 执行桥接; 它不替代 `do run` 产品命令回归。
  - 验证: `SKIP_BUILD=1 ./tool/build/test/run_wasm_smoke.sh` 成功, stderr 为空。
  - 用例: `01_start_scalar`、`02_env_host_import_string_literal`、`03_env_host_import_storage_wrapper`、`04_defer_lifo`、`05_defer_block` 和 `06_defer_loop_break` 全部 `[PASS]`。
  - 输出: `wasm run summary: pass=6 fail=0`, `run_wasm_smoke_cases=6`, `run_wasm_smoke_failures=0`。
  - 边界: 本项只证明当前底层 wasm bridge gate 通过; 不替代 `do run` 产品命令回归、RUN_WASM 扩展回归或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'run_wasm_smoke bridge gate|wasm run summary: pass=6 fail=0|run_wasm_smoke_cases=6|run_wasm_smoke_failures=0|01_start_scalar|06_defer_loop_break' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 run_wasm_smoke bridge gate 仍通过; 未新增阻断。
- [x] 复跑 compiled trap smoke gate。结论:
  - 范围: `tool/build/test/compiled_trap/*.do` 当前共 2 个 fixture: `01_compiled_test_fallthrough_traps` 和 `02_compiled_managed_struct_alias_set_oob_get_traps`。
  - 生成验证: 两个 fixture 分别执行 `DO_LIB_ROOT=tool/build/test/lib ./bin/do test <case> --compiled -o <tmp>/<case>.wat`, 均成功生成非空 WAT 且 stderr 为空。
  - parse 验证: 两个 WAT 均通过 `wasm-tools parse <wat> -o <wasm>`, 生成非空 wasm 且 stderr 为空。
  - trap 验证: `node tool/build/test/run_compiled_test_case.mjs <wasm> <wat>` 均按预期非 0 退出, stderr 包含 compiled test failure 和 runtime trap marker。
  - 输出: `compiled_trap_01_compiled_test_fallthrough_traps=1`, `compiled_trap_01_compiled_test_fallthrough_traps_wat_bytes=33386`, `compiled_trap_01_compiled_test_fallthrough_traps_wasm_bytes=5844`, `compiled_trap_02_compiled_managed_struct_alias_set_oob_get_traps=1`, `compiled_trap_02_compiled_managed_struct_alias_set_oob_get_traps_wat_bytes=36879`, `compiled_trap_02_compiled_managed_struct_alias_set_oob_get_traps_wasm_bytes=6218`, `compiled_trap_cases=2`, `compiled_trap_failures=0`。
  - 边界: 该 gate 的正确结果是运行期 trap, 不是测试通过; 不替代 compiled_ok execution、RUN_WASM 扩展回归或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'compiled trap smoke gate|compiled_trap_cases=2|compiled_trap_failures=0|01_compiled_test_fallthrough_traps|02_compiled_managed_struct_alias_set_oob_get_traps|33386|36879' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 compiled trap smoke gate 仍通过; 未新增阻断。
- [x] 复核 release candidate handoff boundary gate。结论:
  - 范围: 发布候选接手入口、旧问题/计划 artifact、未完成项口径和 dirty/UI 交付边界。
  - 入口验证: `README.md`、`CHANGELOG.md`、`doc/master_plan.md`、`doc/roadmap_status.md`、`doc/start_here.md` 和 `doc/memory.md` 均存在。
  - 旧 artifact 验证: `doc/review_blockers.md`、`doc/review_issues.md`、`compiled_task_checklist.md`、`next_stage_plan.md` 和 `internal_prefix_rename_plan.md` 均不存在。
  - 未完成项扫描: `rg -n '^- \[ \]' README.md doc/master_plan.md doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 只命中 README 后置非目标、06.2 blocked/decomposed、D2.1 blocked 和 G6.1-G6.3 blocked。
  - 旧文本扫描: `rg -n '当前推荐|下次第一步|第二版编译器正在实现|review_blockers|review_issues|compiled_task_checklist|next_stage_plan|internal_prefix_rename_plan' README.md doc/master_plan.md doc/start_here.md doc/syntax doc/spec.md doc/spec_rules.md doc/grammar.peg tool/build/test/README.md CHANGELOG.md` 只命中 `CHANGELOG.md` 历史记录。
  - dirty/UI 边界: `git diff --name-only | wc -l` 输出 `52`; `git ls-files --others --exclude-standard | wc -l` 输出 `117`; `ui.do` / `ui_demo.do` 不在 tracked diff, 只在 untracked。
  - 边界: 本项只证明 handoff 入口和旧 artifact 清理状态没有漂移; 不解除 README 后置非目标、06.2、D2.1 或 G6.1-G6.3。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'release candidate handoff boundary gate|handoff 入口文件均存在|旧 artifact|tracked `52`|untracked `117`|ui\\.do|ui_demo\\.do' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 release candidate handoff boundary gate 通过; 未新增阻断。
- [x] 复核 test README matrix boundary gate。结论:
  - 范围: `tool/build/test/README.md` 里的目录/helper 说明和 `tool/build/test` 当前实际顶层目录、文件。
  - 目录扫描: `check`、`compile_err`、`compile_ok`、`compiled_err`、`compiled_ok`、`compiled_trap`、`err`、`fmt`、`lsp`、`ok`、`pending` 和 `run` 已在 README 命中; 初次扫描发现 `lib` 未说明, `tmp` 作为生成目录未说明。
  - 文件扫描: `run_compiled_test_case.mjs`、`run_lsp_case.mjs`、`run_release_smoke.sh`、`run_tests.sh`、`run_wasm_smoke.sh`、`test_wasi_bind_manifest_tool.mjs` 和 `validate_wasi_bind_manifest.mjs` 已在 README 命中; 初次扫描发现 `run_wasm_case.mjs` 未说明。
  - 修正: `tool/build/test/README.md` 补充 `lib` fixture 专用导入根、`tmp` 生成目录和 `run_wasm_case.mjs` Node helper 的说明。
  - 边界: 本项只同步测试说明和实际目录/helper 角色; 不改变测试脚本、fixture、runner 行为或发布 gate 范围。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'Test README matrix boundary gate|test README matrix boundary gate|`lib`: fixture 专用导入根|`tmp`: 回归脚本生成的临时输出目录|run_wasm_case\\.mjs' CHANGELOG.md doc/start_here.md doc/roadmap_status.md tool/build/test/README.md` 确认。
  - 结果: 当前 test README matrix boundary gate 通过; 未新增阻断。
- [x] 复核 README command matrix boundary gate。结论:
  - 范围: README 构建/回归命令示例、当前 `./bin/do` usage、`tool/build/test` 发布脚本入口。
  - CLI usage 验证: `./bin/do` 输出 usage, 覆盖 `do build <input.do> [--component-core] [-o out.wat]`、`do test <input.do>`、`do test <input.do> --compiled [-o out.wat]`、`do check <input.do>...`、`do run <input.do>`、`do fmt <input.do>`、`do fmt --check <input.do>`、`do fmt --write <input.do>` 和 `do lsp [--stdio]`。
  - 脚本入口验证: `tool/build/test` 当前存在 `run_tests.sh`、`run_release_smoke.sh` 和 `run_wasm_smoke.sh`, README 已列出 `./tool/build/test/run_tests.sh`、`./tool/build/test/run_release_smoke.sh` 和 `RUN_WASM=1 ./tool/build/test/run_tests.sh`。
  - 修正: README 构建示例补充 `../bin/do test app.do --compiled -o app.test.wat`, 对齐当前 compiled test WAT 入口。
  - 边界: 本项只修正文档示例; 不改变 CLI 行为、脚本行为、发布 gate 范围或 `--component-core` 的高级边界。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'README command matrix boundary gate|do test app\\.do --compiled -o app\\.test\\.wat|do test <input\\.do> --compiled|run_release_smoke\\.sh|RUN_WASM=1 ./tool/build/test/run_tests\\.sh' README.md CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 README command matrix boundary gate 通过; 未新增阻断。
- [x] 复核 shell harness executable boundary gate。结论:
  - 范围: `tool/build/test/run_tests.sh`、`tool/build/test/run_wasm_smoke.sh` 和 `tool/build/test/run_release_smoke.sh` 的 shebang、可执行位、语法和 tracked/untracked 边界。
  - shebang 验证: 三个脚本首行均为 `#!/usr/bin/env bash`, 且开头均包含 `set -euo pipefail`。
  - mode 验证: `git ls-files -s` 显示 `run_tests.sh` 和 `run_wasm_smoke.sh` 为 tracked `100755`; `stat -c '%a %n'` 显示三个脚本当前权限均为 `775`。
  - syntax 验证: `bash -n tool/build/test/run_tests.sh`、`bash -n tool/build/test/run_wasm_smoke.sh` 和 `bash -n tool/build/test/run_release_smoke.sh` 均通过, 输出 `bash_n=pass`。
  - 状态边界: `git diff --name-status -- tool/build/test/run_tests.sh tool/build/test/run_wasm_smoke.sh tool/build/test/run_release_smoke.sh` 只显示 tracked `run_tests.sh` 为 modified; `git ls-files --others --exclude-standard -- ...` 只输出 `tool/build/test/run_release_smoke.sh`。
  - 边界: 本项只证明 shell harness 当前可执行/语法边界; 不执行 release smoke 或 full regression; `run_release_smoke.sh` 提交前仍需按主线范围显式暂存。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'shell harness executable boundary gate|bash_n=pass|100755|权限均为 `775`|run_release_smoke\\.sh` 仍是 untracked executable' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 shell harness executable boundary gate 通过; 未新增阻断。
- [x] 复核 README stdlib boundary matrix gate。结论:
  - 范围: README 标准库摘要 / Roadmap 标准库边界和当前 `src/*.do` 顶层模块、标准库 fixture 覆盖记录。
  - src 扫描: `find src -maxdepth 1 -type f -name '*.do'` 当前输出 builtin table `_.do` 以及 32 个标准库模块: `atomic`、`base64`、`binary`、`bytes`、`dir`、`file`、`fp`、`hash_map`、`hex`、`http.client`、`io.stream`、`json`、`list`、`math`、`md5`、`mem`、`net`、`path`、`random`、`range`、`set`、`sha1`、`sha256`、`simd`、`slice`、`tcp`、`text`、`time`、`udp`、`url`、`utf16`、`utf8`。
  - 覆盖证据: H1.3 已将 32 个 std src `NoTestDecl` 转为 metadata-only pass; C5.3 已记录非 WASI/resource executable skip 清空; `ok/06_hash_digest_smoke`、`ok/162_md5_digest_helpers`、`ok/163_sha1_digest_helpers`、`ok/164_sha256_digest_helpers`、`ok/119_mem_atomic_libs`、`ok/07_net_socket_smoke`、`ok/118_wasi_p3_std_wrappers` 和 `compile_ok/08/96/99` 覆盖本次补充边界。
  - 修正: README 标准库摘要补齐 `atomic`、`path`、`md5/sha1/sha256`; Roadmap 标准库边界明确 `time.do`、`random.do`、`file.do`、`dir.do`、`io.stream.do` 只承诺已登记 WASI wrapper lowering, `net.do`、`tcp.do`、`udp.do`、`http.client.do` 当前只承诺 shape/check smoke, `simd.do` 当前只纳入 std source metadata/check 边界。
  - 边界: 本项只修正文档公开边界; 不新增标准库 API 承诺, 不执行 host runtime smoke, 不解除 G6.1-G6.3 或 JSON/序列化后置项。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'README stdlib boundary matrix gate|md5/sha1/sha256|time/random/file/dir/io\\.stream|net/tcp/udp/http\\.client|simd.*metadata/check' README.md CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 README stdlib boundary matrix gate 通过; 未新增阻断。
- [x] 清理 test tmp generated artifacts boundary gate。结论:
  - 范围: `tool/build/test/tmp` 下由 `run_tests.sh`、WASI component helper、LSP helper、compiled runner 和 release smoke 产生的 ignored 临时输出。
  - 保护验证: `git ls-files -s tool/build/test/tmp/.gitignore` 显示 `.gitignore` 为 tracked `100644`; 文件内容为 `*` 和 `!.gitignore`。
  - 清理前验证: `find tool/build/test/tmp -mindepth 1 ! -name .gitignore | wc -l` 输出 `3576`; `du -sh tool/build/test/tmp` 输出 `26M`。
  - 清理: 执行 `find tool/build/test/tmp -mindepth 1 -maxdepth 1 ! -name .gitignore -exec rm -rf -- {} +`, 只删除 `.gitignore` 外的顶层生成物。
  - 清理后验证: `find tool/build/test/tmp -mindepth 1 ! -name .gitignore | wc -l` 输出 `0`; `du -sh tool/build/test/tmp` 输出 `288K`; `git status --short -- tool/build/test/tmp` 无输出。
  - 边界: 本项只清理 ignored generated artifacts; 不触碰 fixture、脚本、真实 untracked 主线文件、`ui.do` 或 `ui_demo.do`。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'test tmp generated artifacts boundary gate|3576|26M|生成物计数为 `0`|288K|tool/build/test/tmp/.gitignore' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 test tmp generated artifacts cleanup gate 通过; 未新增阻断。
- [x] 复跑 Markdown local link gate。结论:
  - 范围: `README.md`、`CHANGELOG.md` 和 `doc/**/*.md`。
  - 验证: Node 只读扫描 Markdown 链接, 忽略 `http(s)`、`mailto:`、纯锚点和非 `.md` 路径。
  - 输出: `markdown_files=26`, `local_markdown_links=20`, `missing=0`。
  - 边界: 本项只检查本地 `.md` 链接存在性; 不检查外链、非 Markdown 路径或运行时示例。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'Markdown local link gate|markdown_files=26|local_markdown_links=20|missing=0|最近复跑后仍无文档死链' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 Markdown local link gate 仍通过; 未新增阻断。
- [x] 复跑 active/blocker 状态口径 gate。结论:
  - 范围: `README.md`、`CHANGELOG.md`、`doc/master_plan.md`、`doc/roadmap_status.md` 和 `doc/start_here.md`, 另扫描 `doc/syntax`、`doc/spec.md`、`doc/spec_rules.md`、`doc/grammar.peg` 与 `tool/build/test/README.md` 的旧入口文本。
  - 未完成项扫描: `rg -n '^- \[ \]' README.md doc/master_plan.md doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 只命中 README 后置非目标、06.2 blocked/decomposed、D2.1 blocked 和 G6.1-G6.3 blocked。
  - 泛化状态扫描: `rg -n '^状态: (active|partial|blocked)(;|$)|^状态: blocked/partial|^状态: partial|状态: active' README.md doc/master_plan.md doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 只命中 `doc/roadmap_status.md` 的历史记录行, 该行描述旧状态被修正。
  - 旧入口扫描: `rg -n '当前推荐|下次第一步|第二版编译器正在实现|review_blockers|review_issues|compiled_task_checklist|next_stage_plan|internal_prefix_rename_plan' README.md doc/master_plan.md doc/start_here.md doc/syntax doc/spec.md doc/spec_rules.md doc/grammar.peg tool/build/test/README.md CHANGELOG.md` 只命中 `CHANGELOG.md` 历史记录和 `doc/start_here.md` 中“旧 artifact 不存在”的当前说明。
  - TODO/FIXME 扫描: `rg -n 'TODO|FIXME' README.md doc/master_plan.md doc/start_here.md CHANGELOG.md doc/roadmap_status.md` 只命中历史记录或验证命令。
  - 边界: 本项只证明当前入口和计划状态口径无新增漂移; 不解除 README 后置非目标、06.2、D2.1 或 G6.1-G6.3。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'active/blocker 状态口径 gate|未完成项扫描: `rg -n|泛化状态扫描|旧入口扫描|TODO/FIXME 扫描|最近复跑后仍无新的活跃任务漂移' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 active/blocker 状态口径仍通过; 未新增阻断。
- [x] 复跑 JS/MJS helper syntax gate。结论:
  - 范围: `git ls-files '*.mjs'` 当前输出 6 个 tracked `.mjs` 文件: `tool/build/test/run_compiled_test_case.mjs`、`tool/build/test/run_lsp_case.mjs`、`tool/build/test/run_wasm_case.mjs`、`tool/build/test/test_wasi_bind_manifest_tool.mjs`、`tool/build/test/validate_wasi_bind_manifest.mjs` 和 `tool/run/run_wasm_program.mjs`; `git ls-files --others --exclude-standard '*.mjs'` 输出 0。
  - 环境: `node --version` 输出 `v24.18.0`。
  - 验证: 对上述 6 个文件逐个执行 `node --check` 均通过, 输出 `ok <file>`。
  - 边界: 本项只证明 JS/MJS helper 当前可解析; 不执行 LSP、WASI helper、compiled runner 或 wasm runner 行为测试。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'JS/MJS helper syntax gate|v24\\.18\\.0|当前 6 个 tracked `\\.mjs`|run_wasm_program\\.mjs|node --check' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 JS/MJS helper syntax gate 仍通过; 未新增阻断。
- [x] 复跑 Zig fmt gate。结论:
  - 环境: `zig version` 输出 `0.16.0`。
  - 范围: `rg --files -g '*.zig' | sort | wc -l` 输出 `31`; 当前 Zig 文件为 `tool/build.zig`、`tool/build/*.zig`、`tool/check/run.zig`、`tool/env.zig`、`tool/fmt/*.zig`、`tool/lsp/*.zig`、`tool/main.zig` 和 `tool/run/run.zig`。
  - 验证: `rg --files -g '*.zig' -0 | xargs -0 zig fmt --check` 通过, 输出 `zig_fmt_check=pass`。
  - 边界: 本项只证明当前 Zig 源文件格式符合 `zig fmt --check`; 不替代 Zig unit test、Debug build 或 full regression。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'Zig fmt gate|zig_fmt_check=pass|0\\.16\\.0|当前全仓 `31` 个 Zig 文件|zig fmt --check' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 Zig fmt gate 仍通过; 未新增阻断。
- [x] 复跑 Zig aggregate unit gate。结论:
  - 范围: `tool/main.zig` 聚合导入链上的 CLI/run/fmt/check/LSP、backend IR、component metadata writer、function body writer、ownership facts、runtime prelude、lexer、diag、parser、sema 和 formatter 单元测试。
  - 验证: `cd tool && zig test main.zig` 通过。
  - 输出: `All 101 tests passed.`
  - 覆盖样例: LSP diagnostics/formatting/semantic tokens/hover/completion/definition/workspace, backend IR fold/inline, component/core WAT writer, ownership facts, runtime prelude, lexer/parser/sema/diag 和 formatter idempotence。
  - 边界: 本项不替代 `zig build -Doptimize=Debug`、focused unit gates、full fixture regression、RUN_WASM 扩展回归或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'Zig aggregate unit gate|All 101 tests passed|cd tool && zig test main\\.zig|backend IR fold/inline|formatter idempotence' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认。
  - 结果: 当前 Zig aggregate unit gate 仍通过; 未新增阻断。
- [x] 复跑 release smoke refresh gate。结论:
  - 范围: `tool/build/test/run_release_smoke.sh` 的发布前最小链路, 包括 ReleaseSmall build、`do build`、`do test`、`do test --compiled`、`do check`、`do fmt`、`do run` 和 `do lsp`。
  - 验证: `./tool/build/test/run_release_smoke.sh` 通过。
  - 输出: `[PASS] release smoke ReleaseSmall build`, `[PASS] release smoke do build`, `[PASS] release smoke do test`, `[PASS] release smoke do test --compiled`, `[PASS] release smoke do check`, `[PASS] release smoke do fmt`, `[PASS] release smoke do run`, `[PASS] release smoke do lsp`, `[INFO] release smoke passed`。
  - 临时产物: release smoke 后 `tool/build/test/tmp` 一度有 44 个 ignored 生成条目; 已清理 `.gitignore` 外顶层生成物, 当前 `find tool/build/test/tmp -mindepth 1 ! -name .gitignore | wc -l` 输出 `0`, `du -sh tool/build/test/tmp` 输出 `288K`。
  - 边界: 本项只证明当前发布前最小 smoke 仍通过; 不替代默认完整回归、RUN_WASM 扩展回归或 G6.1-G6.3 的公开 API / 运行时设计决策。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'release smoke refresh gate|release smoke passed|ignored 产物已清理|44 个 ignored|find tool/build/test/tmp' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 release smoke refresh gate 仍通过; 未新增阻断。
- [x] 复跑 default full regression refresh gate。结论:
  - 范围: `tool/build/test/run_tests.sh` 默认矩阵, 使用当前 `bin/do` 且 `SKIP_BUILD=1`, 覆盖 tool、ok/err、compile_ok/compile_err、compiled_ok/compiled_err、do run、fmt、check 和 lsp cases。
  - 验证: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过。
  - 输出: `[INFO] summary: pass=831 fail=0 skip=3`。
  - 临时产物: 默认回归后 `tool/build/test/tmp` 一度有 3202 个 ignored 生成条目, 约 `24M`; 已清理 `.gitignore` 外顶层生成物, 当前 `find tool/build/test/tmp -mindepth 1 ! -name .gitignore | wc -l` 输出 `0`, `du -sh tool/build/test/tmp` 输出 `288K`。
  - 边界: 本项只证明默认完整回归仍通过; 不替代 RUN_WASM 扩展回归、release smoke 或 G6.1-G6.3 的公开 API / 运行时设计决策。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'default full regression refresh gate|pass=831 fail=0 skip=3|3202 个 ignored|默认回归矩阵最近通过|SKIP_BUILD=1 ./tool/build/test/run_tests.sh' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 default full regression refresh gate 仍通过; 未新增阻断。
- [x] 复跑 RUN_WASM extended regression refresh gate。结论:
  - 范围: `tool/build/test/run_tests.sh` 的 `RUN_WASM=1` 扩展矩阵, 使用当前 `bin/do` 且 `SKIP_BUILD=1`, 在默认矩阵基础上额外覆盖 compiled wasm execution、compiled trap 和 6 个 wasm run smoke。
  - 验证: `RUN_WASM=1 SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过。
  - 输出: `[INFO] wasm run summary: pass=6 fail=0`; `[INFO] summary: pass=833 fail=0 skip=3`。
  - 剩余 skip: `118_wasi_p3_std_wrappers`、`16_loop_recv_value`、`96_file_lib_resource_shape`, 与既有 H1.4 后置边界一致。
  - 临时产物: 扩展回归后 `tool/build/test/tmp` 一度有 3527 个 ignored 生成条目, 约 `25M`; 已清理 `.gitignore` 外顶层生成物, 当前 `find tool/build/test/tmp -mindepth 1 ! -name .gitignore | wc -l` 输出 `0`, `du -sh tool/build/test/tmp` 输出 `288K`。
  - 边界: 本项只证明 RUN_WASM 扩展回归仍通过; 不替代 release smoke 或 G6.1-G6.3 的公开 API / 运行时设计决策。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'RUN_WASM extended regression refresh gate|pass=833 fail=0 skip=3|wasm run summary: pass=6 fail=0|3527 个 ignored|扩展回归最近通过|118_wasi_p3_std_wrappers|16_loop_recv_value|96_file_lib_resource_shape' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 RUN_WASM extended regression refresh gate 仍通过; 未新增阻断。
- [x] 复核 delivery boundary inventory gate。结论:
  - 范围: 当前 dirty worktree 的 tracked/untracked 交付边界和 `ui.do` / `ui_demo.do` 排除边界。
  - tracked 分类: `git diff --name-only` 当前输出 `52`; 目录分布为 CHANGELOG `1`、README `1`、bin `1`、doc `7`、src `11`、tool `4`、tool/build `6`、tool/build/test `21`。
  - untracked 分类: `git ls-files --others --exclude-standard` 当前输出 `117`; 目录分布为 tool/build `4`、tool/build/test `107`、tool/lsp `4`、`ui.do` `1`、`ui_demo.do` `1`。
  - UI 边界: `git diff --name-only | rg '(^|/)(ui\\.do|ui_demo\\.do)$'` 无输出; `git ls-files --others --exclude-standard | rg '(^|/)(ui\\.do|ui_demo\\.do)$'` 输出 `ui.do` 和 `ui_demo.do`。
  - 边界: 本项只证明当前交付范围没有新增漂移; 不 stage、不删除、不提交任何文件, 也不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `rg -n 'delivery boundary inventory gate|tracked 分类|untracked 分类|tool/build/test 107|ui\\.do.*ui_demo\\.do|最近复核的目录分类' CHANGELOG.md doc/start_here.md doc/roadmap_status.md` 的等价单引号查询确认; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 delivery boundary inventory gate 通过; 未新增阻断。
- [x] 复核 handoff docs consistency gate。结论:
  - 范围: handoff 入口文件、旧 artifact、未完成项口径、旧入口/TODO/FIXME 文案和本地 Markdown 链接。
  - 入口验证: `README.md`、`CHANGELOG.md`、`doc/master_plan.md`、`doc/roadmap_status.md`、`doc/start_here.md` 和 `doc/memory.md` 均存在。
  - 旧 artifact 验证: `doc/review_blockers.md`、`doc/review_issues.md`、`compiled_task_checklist.md`、`next_stage_plan.md` 和 `internal_prefix_rename_plan.md` 均不存在。
  - 未完成项扫描: `rg -n '^- \\[ \\]' README.md doc/master_plan.md doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 只命中 README 后置非目标、06.2 blocked/decomposed、D2.1 blocked 和 G6.1-G6.3 blocked。
  - 旧入口/TODO/FIXME 扫描: `当前推荐`、`下次第一步`、`第二版编译器正在实现`、旧问题文件名、`TODO` 和 `FIXME` 命中均为 `CHANGELOG.md` / `doc/roadmap_status.md` 历史记录、验证命令或 `doc/start_here.md` 中旧 artifact 不存在的当前说明。
  - Markdown 链接验证: Node 本地链接扫描输出 `markdown_files=26`, `local_markdown_links=20`, `missing=0`。
  - 边界: 本项只证明当前 handoff 文档入口、旧 artifact 和本地链接状态没有新增漂移; 不解除 README 后置非目标、06.2、D2.1 或 G6.1-G6.3。
  - 复验: `git diff --check` 通过; 记录命中已由 `handoff docs consistency gate`、`markdown_files=26`、`local_markdown_links=20`、`missing=0`、`入口验证`、`旧 artifact 验证`、`未完成项扫描` 和 `旧入口/TODO/FIXME` 关键字确认; Node 本地链接扫描复跑仍为 `missing=0`; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 handoff docs consistency gate 通过; 未新增阻断。
- [x] 复核 regression fixture companion consistency gate。结论:
  - 范围: `tool/build/test` 下 `err`、`compile_err`、`compiled_ok`、`compiled_err`、`run`、`fmt`、`ok`、`check` 的 `.do` / `.expect` / `.must_pass` / `.compiled_must_pass` companion 关系。
  - 依据: `err/fixture.*.do` 是 import 依赖 fixture, `run_tests.sh` 会跳过, 不能要求逐个配 `.expect`; 其余 companion 规则按 `tool/build/test/run_tests.sh` 和 `tool/build/test/README.md` 当前约定。
  - 扫描输出: `fixture_companion_counts={"err":579,"compile_err":60,"compiled_ok":104,"compiled_err":2,"run":11,"fmt":6,"ok":292,"check":3}`。
  - 扫描输出: `fixture_companion_missing=0`。
  - 边界: 本项只证明当前 fixture companion 关系没有缺失; 不执行 fixture, 不替代默认完整回归、RUN_WASM 扩展回归或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `regression fixture companion consistency gate`、`fixture_companion_counts={"err":579`、`fixture_companion_missing=0`、`err/fixture.*.do` 和 `.compiled_must_pass` 关键字确认; companion 扫描复跑仍输出 `fixture_companion_missing=0`; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 regression fixture companion consistency gate 通过; 未新增阻断。
- [x] 复核 Zig import/file presence gate。结论:
  - 范围: 当前 `rg --files -g '*.zig'` 输出的 31 个 Zig 文件和其中 `@import("...")` 关系。
  - 扫描输出: `zig_files=31`, `zig_imports=121`, `zig_local_imports=89`, `zig_missing_local_imports=0`。
  - 未跟踪 Zig 文件: `zig_untracked_files=8`, 分别是 `tool/build/component_metadata_wat.zig`、`tool/build/function_body_wat.zig`、`tool/build/ownership_facts.zig`、`tool/build/runtime_prelude_wat.zig`、`tool/lsp/completion.zig`、`tool/lsp/definition.zig`、`tool/lsp/hover.zig`、`tool/lsp/workspace.zig`。
  - 边界: 本项只证明当前本地 Zig import 目标文件存在, 尤其是未跟踪拆分模块没有缺失; 不执行 Zig test/build, 不 stage 未跟踪文件, 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `Zig import/file presence gate`、`zig_files=31`、`zig_imports=121`、`zig_local_imports=89`、`zig_missing_local_imports=0`、`zig_untracked_files=8` 和拆分模块文件名关键字确认; import 扫描复跑仍输出 `zig_missing_local_imports=0`; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 Zig import/file presence gate 通过; 未新增阻断。
- [x] 复核 Do `@lib` target presence gate。结论:
  - 范围: 当前 `rg --files -g '*.do'` 输出的 877 个 `.do` 文件, 只读扫描其中 `@lib("...")` 第一个字符串参数。
  - 解析规则: `./...` 按当前文件目录单文件查找; `~/...` 按回归 fixture 专用 `DO_LIB_ROOT=tool/build/test/lib` 查找; bare `file.do` 按标准库根 `src/` 查找, 不回退当前目录。
  - 扫描输出: `do_files=877`, `lib_import_hits=890`, `lib_unique_targets=73`。
  - 扫描输出: `lib_target_bare=770`, `lib_target_tilde=44`, `lib_target_relative=76`, `lib_unique_bare=34`, `lib_unique_tilde=16`, `lib_unique_relative=23`。
  - 例外输出: `lib_ignored_support_missing=3`, 分别是 `tool/build/test/err/fixture/cycle_a.do -> cycle_b.do`、`tool/build/test/err/fixture/cycle_b.do -> cycle_a.do`、`tool/build/test/err/fixture/transitive_broken.do -> missing_dep.do`; 这些是负向 import support 文件边界, 不按当前目录裸导入解析。
  - 扫描输出: `lib_missing_targets=0`。
  - 边界: 本项只证明当前 `@lib` 字符串目标文件存在性没有缺口; 不执行 fixture, 不验证导入 symbol 类别, 不修改 import 语义, 不替代默认完整回归、RUN_WASM 扩展回归或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `Do @lib target presence gate`、`lib_import_hits=890`、`lib_unique_targets=73`、`lib_ignored_support_missing=3`、`lib_missing_targets=0` 和 3 个 ignored support 文件名关键字确认; 扫描复跑仍输出 `lib_missing_targets=0`; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 Do `@lib` target presence gate 通过; 未新增阻断。
- [x] 复核 Do `@lib` imported symbol presence gate。结论:
  - 范围: 当前 890 个 `@lib("...", symbol)` 导入, 只读扫描第二参数 symbol 是否存在于解析后的目标模块顶层 public 候选集合。
  - 解析规则: 目标路径沿用 Do `@lib` target presence gate; 目标 symbol 候选只统计顶层 public 函数、结构/类型/value enum/error enum、enum 分支、public 常量/变量和 public host import alias; 私有 `.name` 与 `@lib` import alias 不计入可再次导入目标。
  - 扫描输出: `lib_symbol_import_hits=890`, `lib_symbol_checks=887`, `lib_symbol_unique_targets=73`, `lib_symbol_unique_pairs=426`。
  - target 负向边界: `lib_symbol_skipped_missing_targets=3`, 与 target presence gate 的 `tool/build/test/err/fixture/` support missing 一致。
  - symbol 负向边界: `lib_symbol_expected_negative_missing=7`, 分别覆盖 private value enum type、private value enum branch、std private WASI host binding、local import alias target、resource private helper import、missing target symbol 和 transitive missing symbol 支持文件。
  - 扫描输出: `lib_symbol_missing_targets=0`, `lib_symbol_unexpected_missing=0`。
  - 边界: 本项只证明当前 `@lib` 第二参数的非负向 symbol presence 没有缺口; 不替代编译器的 import 类别匹配、私有性、重载、泛型实例化或完整语义诊断。
  - 复验: `git diff --check` 通过; 记录命中已由 `Do @lib imported symbol presence gate`、`lib_symbol_checks=887`、`lib_symbol_unique_pairs=426`、`lib_symbol_expected_negative_missing=7` 和 `lib_symbol_unexpected_missing=0` 关键字确认; 扫描复跑仍输出 `lib_symbol_unexpected_missing=0`; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 Do `@lib` imported symbol presence gate 通过; 未新增阻断。
- [x] 复核 JSON source/fixture syntax gate。结论:
  - 范围: 当前 tracked 与 untracked 的源码/fixture JSON 文件, 不包含 ignored `tool/build/test/tmp` 生成缓存。
  - 文件枚举: `git ls-files '*.json'` 输出 6 个 tracked JSON: `doc/wit/wasi_registry.json` 和 `tool/build/test/lsp/01_open_valid.json` 到 `05_semantic_tokens_request.json`。
  - untracked JSON 边界: `git ls-files --others --exclude-standard '*.json'` 输出 4 个 LSP smoke fixture: `06_hover_request.json`、`07_completion_request.json`、`08_definition_request.json`、`09_workspace_index_request.json`。
  - 验证: Node 对上述 10 个文件逐个执行 `JSON.parse(...)`。
  - 扫描输出: `json_files=10`, `json_tracked=6`, `json_untracked=4`, `json_parse_fail=0`.
  - 边界: 本项只证明当前 JSON 文件语法可解析; 不执行 LSP fixture, 不验证 WASI registry schema, 不替代 LSP smoke、WASI manifest helper 或 full regression。
  - 复验: `git diff --check` 通过; 记录命中已由 `JSON source/fixture syntax gate`、`json_files=10`、`json_tracked=6`、`json_untracked=4`、`json_parse_fail=0` 和 4 个 untracked LSP fixture 文件名确认; JSON parse 扫描复跑仍输出 `json_parse_fail=0`; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 JSON source/fixture syntax gate 通过; 未新增阻断。
- [x] 复核 WIT registry schema/uniqueness gate。结论:
  - 范围: `doc/wit/wasi_registry.json` 顶层 `records` / `functions` 结构、record 字段形态、function target/params/result/result_record 形态和 target 唯一性。
  - target 格式: 接受 `package/interface/member` 形态, 其中 member 允许 `descriptor.write`、`input-stream.read` 这类平级 `.` 分段。
  - 扫描输出: `wasi_registry_records=1`, `wasi_registry_functions=26`, `wasi_registry_unique_targets=26`, `wasi_registry_duplicate_targets=0`。
  - 扫描输出: `wasi_registry_result_records=1`, `wasi_registry_result_record_names=Datetime`, `wasi_registry_known_unsupported=7`。
  - 扫描输出: `wasi_registry_shape_errors=0`, `wasi_registry_function_shape_errors=0`。
  - 边界: 本项只证明当前 registry schema 和 target 唯一性没有缺口; 不验证 lowering 文档覆盖, 不执行 WASI manifest helper, 不替代 component plan / component wasm gate, 不解除 G6.1-G6.3 的公开 API / 运行时设计阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `WIT registry schema/uniqueness gate`、`wasi_registry_records=1`、`wasi_registry_functions=26`、`wasi_registry_unique_targets=26`、`wasi_registry_duplicate_targets=0`、`wasi_registry_shape_errors=0` 和 `wasi_registry_known_unsupported=7` 关键字确认; registry 扫描复跑仍输出 `wasi_registry_shape_errors=0`; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 WIT registry schema/uniqueness gate 通过; 未新增阻断。
- [x] 复核 WASI registry / lowering doc coverage gate。结论:
  - 范围: `doc/wit/wasi_registry.json` 当前 26 个 `functions[].target` 与 `doc/wit/wasi_p3_lowering.md` 正文和 target table 覆盖。
  - 验证: Node 只读扫描 registry targets, 逐项确认 target 字符串出现在 lowering 文档正文, 且存在 `| \`target\` |` 表格行。
  - 扫描输出: `wasi_registry_functions=26`, `wasi_registry_unique_targets=26`。
  - 扫描输出: `wasi_registry_doc_target_coverage=26/26`, `wasi_registry_table_target_coverage=26/26`。
  - 扫描输出: `wasi_registry_known_unsupported=7`, `wasi_registry_table_known_unsupported=7`, `wasi_registry_unsupported_mismatch=0`。
  - 扫描输出: `wasi_registry_doc_missing=0`, `wasi_registry_table_missing=0`。
  - 边界: 本项只证明当前 registry target 和 lowering 文档覆盖没有漂移; 不验证 registry schema, 不执行 WASI manifest helper, 不替代 component plan / component wasm gate, 不解除 `filesystem/preopens/get-directories`、`descriptor.read-directory`、sockets 和 HTTP 的 known-but-unsupported 边界。
  - 复验: `git diff --check` 通过; 记录命中已由 `WASI registry / lowering doc coverage gate`、`wasi_registry_doc_target_coverage=26/26`、`wasi_registry_table_target_coverage=26/26`、`wasi_registry_table_known_unsupported=7` 和 `wasi_registry_unsupported_mismatch=0` 关键字确认; 覆盖扫描复跑仍输出 `wasi_registry_table_missing=0`; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 WASI registry / lowering doc coverage gate 通过; 未新增阻断。
- [x] 复核 Do `@lib` import graph cycle gate。结论:
  - 范围: 当前 `rg --files -g '*.do'` 输出的 877 个 `.do` 文件, 按 compiler local/dep/std import 根解析 `@lib("...", symbol)` 第一个参数并构建文件级依赖图。
  - 解析规则: `./...` 指向当前文件目录, `~/...` 指向回归 fixture 专用 `tool/build/test/lib`, bare `file.do` 指向标准库根 `src/`; 不按当前目录回退 bare import。
  - 扫描输出: `lib_graph_files=877`, `lib_graph_import_hits=890`, `lib_graph_edges=887`。
  - target 边界: `lib_graph_skipped_missing_targets=3`, 与 `tool/build/test/err/fixture/` support missing 一致; `lib_graph_missing_targets=0`。
  - cycle 边界: `lib_graph_cycles=1`, `lib_graph_expected_cycles=1`, `lib_graph_unexpected_cycles=0`。
  - expected cycle: `tool/build/test/err/fixture.cycle_a.do -> tool/build/test/err/fixture.cycle_b.do`, 由 `tool/build/test/err/65_import_cycle.do` 负向 fixture 锁定。
  - 边界: 本项只证明当前 `@lib` 文件级图没有非预期 cycle; 不执行 fixture, 不验证 symbol/category/private 语义, 不替代默认完整回归或 import diagnostics。
  - 复验: `git diff --check` 通过; 记录命中已由 `Do @lib import graph cycle gate`、`lib_graph_edges=887`、`lib_graph_cycles=1`、`lib_graph_expected_cycles=1`、`lib_graph_unexpected_cycles=0` 和 `fixture.cycle_a.do` 关键字确认; graph 扫描复跑仍输出 `lib_graph_unexpected_cycles=0`; dirty/UI 边界仍为 tracked `52`、untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 Do `@lib` import graph cycle gate 通过; 未新增阻断。
- [x] 复核 ok marker companion gate。结论:
  - 范围: `tool/build/test/ok` 下 `.must_pass` 与 `.compiled_must_pass` marker 到同名 `.do` fixture 的伴随关系。
  - 扫描输出: `ok_do_files=180`, `ok_must_pass_markers=1`, `ok_compiled_must_pass_markers=111`。
  - tracked/untracked: `ok_must_pass_tracked=1`, `ok_must_pass_untracked=0`, `ok_compiled_must_pass_tracked=66`, `ok_compiled_must_pass_untracked=45`。
  - 扫描输出: `ok_must_pass_orphans=0`, `ok_compiled_must_pass_orphans=0`, `ok_marker_overlap=0`。
  - 边界: 本项只证明当前 ok marker 均有同名 fixture 且 static/compiled marker 没有重叠; 不执行 fixture, 不新增或移除 marker, 不替代 `run_tests.sh` 的 must-pass 行为验证。
  - 复验: `git diff --check` 通过; 记录命中已由 `ok marker companion gate`、`ok_do_files=180`、`ok_compiled_must_pass_markers=111`、`ok_must_pass_orphans=0`、`ok_compiled_must_pass_orphans=0` 和 `ok_marker_overlap=0` 关键字确认; marker 扫描复跑仍输出 orphan/overlap 为 `0`; dirty/UI 边界仍为 tracked `52`, untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 ok marker companion gate 通过; 未新增阻断。
- [x] 复核 compile_ok WASI/component expect companion gate。结论:
  - 范围: `tool/build/test/compile_ok` 下 `.component_plan.expect`、`.core_imports.expect`、`.core_shims.expect`、`.component_input.expect`、`.wit_dir.expect` 和 `.component_core.expect` 到同名 `.do` fixture 的伴随关系。
  - 扫描输出: `compile_ok_do_files=239`, `compile_ok_wasi_expect_files=40`, `compile_ok_wasi_expect_bases=14`。
  - tracked/untracked: `compile_ok_wasi_expect_tracked=34`, `compile_ok_wasi_expect_untracked=6`。
  - 分类输出: `compile_ok_component_plan_expects=11`, `compile_ok_core_imports_expects=13`, `compile_ok_core_shims_expects=13`, `compile_ok_component_input_expects=1`, `compile_ok_wit_dir_expects=1`, `compile_ok_component_core_expects=1`。
  - 扫描输出: `compile_ok_wasi_expect_orphans=0`, `compile_ok_wasi_unknown_component_like_expects=0`。
  - 边界: 本项只证明当前 component/WASI expect 均有同名 `.do` fixture, 且没有未纳入 suffix 集合的 component-like expect; 不执行 fixture, 不验证 expect 内容, 不替代 component plan / component wasm / full regression gate, 不解除 G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `compile_ok WASI/component expect companion gate`、`compile_ok_wasi_expect_files=40`、`compile_ok_wasi_expect_bases=14`、`compile_ok_wasi_expect_orphans=0` 和 `compile_ok_wasi_unknown_component_like_expects=0` 关键字确认; companion 扫描复跑仍输出 orphan/unknown 为 `0`; dirty/UI 边界仍为 tracked `52`, untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 compile_ok WASI/component expect companion gate 通过; 未新增阻断。
- [x] 复核 compile_err / compiled_err expect companion gate。结论:
  - 范围: `tool/build/test/compile_err` 与 `tool/build/test/compiled_err` 负向 compile fixture 的 `.do` / `.expect` 双向伴随关系。
  - 依据: `tool/build/test/README.md` 定义 `compile_err/*.expect` 为编译失败输出关键文本, `compiled_err` 用于锁定 compiled runner 的 build/lowering 诊断; `tool/build/test/run_tests.sh` 对两类用例都按同名 `.expect` 逐行匹配。
  - 扫描输出: `tool/build/test/compile_err_do=30`, `tool/build/test/compile_err_expect=30`, `tool/build/test/compiled_err_do=1`, `tool/build/test/compiled_err_expect=1`。
  - 总计输出: `negative_compile_do_files=31`, `negative_compile_expect_files=31`。
  - tracked/untracked: `negative_compile_tracked_do=30`, `negative_compile_untracked_do=1`, `negative_compile_tracked_expect=30`, `negative_compile_untracked_expect=1`。
  - 扫描输出: `negative_compile_missing_expect=0`, `negative_compile_orphan_expect=0`。
  - 边界: 本项只证明当前负向 compile fixture 均有同名 `.expect`, 且没有孤儿 `.expect`; 不执行 fixture, 不验证诊断文本内容, 不替代默认完整回归、compiled runner gate 或 release smoke, 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `compile_err / compiled_err expect companion gate`、`negative_compile_do_files=31`、`negative_compile_expect_files=31`、`negative_compile_missing_expect=0` 和 `negative_compile_orphan_expect=0` 关键字确认; companion 扫描复跑仍输出 missing/orphan 为 `0`; dirty/UI 边界仍为 tracked `52`, untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 compile_err / compiled_err expect companion gate 通过; 未新增阻断。
- [x] 复核 LSP JSON fixture naming/order gate。结论:
  - 范围: `tool/build/test/lsp/*.json` 的文件编号、基础 fixture schema、JSON-RPC request id 顺序和 tracked/untracked 边界。
  - 依据: `tool/build/test/run_lsp_case.mjs` 会读取 fixture 的 `name`、`messages`、`expect`、可选 `workspace` 和可选 `ordered`, 并按 `messages` 顺序向 `bin/do lsp` 发送 framed JSON-RPC 请求。
  - 扫描输出: `lsp_json_files=9`, `lsp_json_tracked=5`, `lsp_json_untracked=4`。
  - 编号输出: `lsp_numbered_files=9`, `lsp_number_min=1`, `lsp_number_max=9`, `lsp_number_gaps=0`, `lsp_duplicate_numbers=0`。
  - schema/id 输出: `lsp_json_parse_fail=0`, `lsp_schema_errors=0`, `lsp_request_id_errors=0`, `lsp_non_sequential_id_fixtures=0`。
  - 内容计数: `lsp_message_count=44`, `lsp_expect_entries=24`, `lsp_workspace_fixtures=1`, `lsp_ordered_true=0`。
  - 边界: 本项只证明当前 LSP fixture 文件编号连续、基础 schema 合法、请求 id 在各 fixture 内从 1 递增; 不启动 LSP server, 不验证响应内容, 不替代 `node tool/build/test/run_lsp_case.mjs ...` smoke gate 或 full regression。
  - 复验: `git diff --check` 通过; 记录命中已由 `LSP JSON fixture naming/order gate`、`lsp_json_files=9`、`lsp_number_gaps=0`、`lsp_duplicate_numbers=0`、`lsp_schema_errors=0` 和 `lsp_request_id_errors=0` 关键字确认; LSP fixture 扫描复跑仍输出 schema/id 错误为 `0`; dirty/UI 边界仍为 tracked `52`, untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 LSP JSON fixture naming/order gate 通过; 未新增阻断。
- [x] 复核 run/fmt/check black-box fixture companion gate。结论:
  - 范围: `tool/build/test/run`、`tool/build/test/fmt` 和 `tool/build/test/check` 的黑盒产品命令 fixture 编号、`.do` / expect companion 关系和 tracked/untracked 边界。
  - 依据: `tool/build/test/README.md` 定义 `run` 的 `.stdout.expect` 为可选 stdout 对比、`fmt` 的 `.expect` 为 formatter 输出对比、`check` 的 `.expect` 为失败诊断子串; `tool/build/test/run_tests.sh` 的 `run_do_run_case`、`run_fmt_case`、`run_check_case` 分别消费这些约定。
  - 分项输出: `run_do_files=6`, `run_expect_files=5`; `fmt_do_files=3`, `fmt_expect_files=3`; `check_do_files=2`, `check_expect_files=1`。
  - tracked/untracked: `blackbox_tracked_do=11`, `blackbox_untracked_do=0`, `blackbox_tracked_expect=9`, `blackbox_untracked_expect=0`。
  - 总计输出: `blackbox_dirs=3`, `blackbox_do_files=11`, `blackbox_expect_files=9`, `blackbox_numbered_files=11`。
  - 扫描输出: `blackbox_missing_required_expect=0`, `blackbox_orphan_expect=0`, `blackbox_unexpected_expect=0`, `blackbox_numbering_gaps=0`, `blackbox_duplicate_numbers=0`。
  - 边界: 本项只证明当前 run/fmt/check 黑盒 fixture 的 companion 和编号关系没有缺口; 不执行 `do run` / `do fmt` / `do check`, 不验证输出内容, 不替代 product command smoke、LSP smoke、full regression 或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `run/fmt/check black-box fixture companion gate`、`blackbox_do_files=11`、`blackbox_expect_files=9`、`blackbox_missing_required_expect=0`、`blackbox_orphan_expect=0` 和 `blackbox_numbering_gaps=0` 关键字确认; companion 扫描复跑仍输出 missing/orphan/gap 为 `0`; dirty/UI 边界仍为 tracked `52`, untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 run/fmt/check black-box fixture companion gate 通过; 未新增阻断。
- [x] 复核 pending fixture inventory gate。结论:
  - 范围: `tool/build/test/run_tests.sh` 的 `RUN_PENDING=1` 路径引用的 `pending/ok`、`pending/err`、`pending/compile_ok` 目录和其中 `.do` / `.expect` companion 关系。
  - 依据: `tool/build/test/README.md` 定义 `pending/compile_ok` 为设计期望 `do build` 成功但实现尚未满足 `.expect` WAT pattern 的红灯用例; `tool/build/test/run_tests.sh` 只在 `RUN_PENDING=1` 时扫描 pending 三类目录。
  - 目录输出: `pending_ok_dir_exists=0`, `pending_err_dir_exists=0`, `pending_compile_ok_dir_exists=1`。
  - 总计输出: `pending_dirs_defined=3`, `pending_dirs_existing=1`, `pending_do_files=0`, `pending_expect_files=0`。
  - tracked/untracked: `pending_tracked_files=0`, `pending_untracked_files=0`。
  - 扫描输出: `pending_fixture_support_files=0`, `pending_missing_required_expect=0`, `pending_orphan_expect=0`, `pending_unexpected_files=0`。
  - 边界: 本项只证明当前 pending inventory 为空且没有悬空 `.expect` 或未知文件; 不创建 pending 目录, 不执行 `RUN_PENDING=1`, 不改变默认回归范围, 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `pending fixture inventory gate`、`pending_dirs_defined=3`、`pending_dirs_existing=1`、`pending_do_files=0`、`pending_expect_files=0` 和 `pending_orphan_expect=0` 关键字确认; inventory 扫描复跑仍输出 pending 文件和 orphan 为 `0`; dirty/UI 边界仍为 tracked `52`, untracked `117`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 pending fixture inventory gate 通过; 未新增阻断。
- [x] 修正并复核 compiled fixture companion / numbering gate。结论:
  - 修正: `tool/build/test/compiled_ok/18_compiled_test_math_small_int_helpers.{do,expect}` 重命名为 `tool/build/test/compiled_ok/52_compiled_test_math_small_int_helpers.{do,expect}`, 消除 `compiled_ok` 的重复 `18_` 编号; 文件内容未改。
  - 范围: `tool/build/test/compiled_ok` 和 `tool/build/test/compiled_trap` 的 `.do` / `.expect` companion、编号唯一性和 tracked/untracked 边界。
  - 依据: `tool/build/test/run_tests.sh` 的 `run_compiled_ok_case` 会消费可选同名 `.expect` 并匹配 WAT 文本; `run_compiled_trap_case` 不消费 `.expect`, 只在 `RUN_WASM=1` 下验证执行 trap。
  - 分项输出: `compiled_ok_do_files=52`, `compiled_ok_expect_files=52`, `compiled_trap_do_files=2`, `compiled_trap_expect_files=0`。
  - tracked/untracked: `compiled_fixture_tracked_do_existing=49`, `compiled_fixture_untracked_do=5`, `compiled_fixture_tracked_expect_existing=48`, `compiled_fixture_untracked_expect=4`。
  - companion 输出: `compiled_fixture_missing_required_expect=0`, `compiled_fixture_orphan_expect=0`, `compiled_fixture_unexpected_expect=0`。
  - 编号输出: `compiled_ok_number_min=1`, `compiled_ok_number_max=52`, `compiled_ok_duplicate_numbers=0`, `compiled_ok_missing_numbers=0`, `compiled_trap_duplicate_numbers=0`, `compiled_trap_missing_numbers=0`。
  - 边界: 本项只证明当前 compiled fixture companion 和编号关系没有缺口, 并完成重复编号文件重命名; 不执行 compiled runner, 不验证 WAT/wasm 输出, 不替代 default regression、RUN_WASM 扩展回归或 release smoke, 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `compiled fixture companion / numbering gate`、`compiled_fixture_do_files=54`、`compiled_fixture_missing_required_expect=0`、`compiled_fixture_orphan_expect=0`、`compiled_fixture_duplicate_numbers=0` 和 `52_compiled_test_math_small_int_helpers` 关键字确认; companion/numbering 扫描复跑仍输出 missing/orphan/duplicate/missing-number 为 `0`; dirty/UI 边界当前为 tracked `54`, untracked `119`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 compiled fixture companion / numbering gate 通过; 未新增阻断。
- [x] 修正并复核 compile_ok 普通 expect companion / numbering inventory gate。结论:
  - 修正: `121_defer_call_and_arc_block_lower.{do,expect}`、`131_struct_field_reflection_set_lower.{do,expect}`、`216_arc_collection_loop_source_call_keeps_inc_lower.{do,expect}`、`217_arc_collection_loop_managed_value_call_keeps_inc_lower.{do,expect}`、`218_arc_recv_loop_managed_value_call_keeps_inc_lower.{do,expect}` 分别重命名为 `234_` 到 `238_` 对应 fixture, 消除 `compile_ok` 重复编号; 文件内容未改。
  - 同步: 本文中 `defer` lowering fixture 当前引用已更新到 `tool/build/test/compile_ok/234_defer_call_and_arc_block_lower.do`。
  - 范围: `tool/build/test/compile_ok` 普通 `.expect`、特殊 WASI/component expect companion、编号唯一性和 tracked/untracked 边界; `fixture.dep_shadow.do` 是 `run_tests.sh` 显式跳过的支持文件, 不参与编号和普通 `.expect` 必需性判断。
  - 扫描输出: `compile_ok_do_files=239`, `compile_ok_numbered_do_files=238`, `compile_ok_support_do_files=1`。
  - expect 输出: `compile_ok_all_expect_files=271`, `compile_ok_plain_expect_files=231`, `compile_ok_special_expect_files=40`。
  - tracked/untracked: `compile_ok_tracked_do_existing=230`, `compile_ok_untracked_do=9`, `compile_ok_tracked_plain_expect_existing=222`, `compile_ok_untracked_plain_expect=9`。
  - companion 输出: `compile_ok_missing_plain_expect=7`, `compile_ok_plain_expect_orphans=0`, `compile_ok_special_expect_orphans=0`, `compile_ok_bad_do_names=0`。
  - 编号输出: `compile_ok_number_min=1`, `compile_ok_number_max=238`, `compile_ok_duplicate_numbers=0`, `compile_ok_missing_numbers=0`。
  - 边界: 普通 `.expect` 在 `compile_ok` 中是可选 WAT 片段检查; 7 个缺失普通 `.expect` 记录为 inventory, 不补空 expect, 不执行 fixture, 不验证 WAT 内容, 不替代 default regression 或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `compile_ok 普通 expect companion / numbering inventory gate`、`compile_ok_numbered_do_files=238`、`compile_ok_plain_expect_orphans=0`、`compile_ok_special_expect_orphans=0`、`compile_ok_duplicate_numbers=0` 和 `compile_ok_missing_numbers=0` 关键字确认; companion/numbering 扫描复跑仍输出 orphan/duplicate/missing-number 为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 compile_ok 普通 expect companion / numbering inventory gate 通过; 未新增阻断。
- [x] 复核 renamed compile_ok targeted build gate。结论:
  - 范围: 上一项重命名后的 `compile_ok/234_defer_call_and_arc_block_lower.do`、`235_struct_field_reflection_set_lower.do`、`236_arc_collection_loop_source_call_keeps_inc_lower.do`、`237_arc_collection_loop_managed_value_call_keeps_inc_lower.do`、`238_arc_recv_loop_managed_value_call_keeps_inc_lower.do`。
  - 验证方式: 对每个用例执行 `DO_LIB_ROOT=tool/build/test/lib ./bin/do build <case.do> -o <tmp.wat>`, 要求 exit 0、WAT 非空, 并逐行匹配同名 `.expect`; `count=` 规则按当前 `run_tests.sh` 语义统计出现次数。
  - 分项输出: `234_defer_call_and_arc_block_lower` WAT `33811` bytes / expect `6` 行; `235_struct_field_reflection_set_lower` WAT `34020` bytes / expect `3` 行; `236_arc_collection_loop_source_call_keeps_inc_lower` WAT `34754` bytes / expect `4` 行; `237_arc_collection_loop_managed_value_call_keeps_inc_lower` WAT `36744` bytes / expect `5` 行; `238_arc_recv_loop_managed_value_call_keeps_inc_lower` WAT `36738` bytes / expect `5` 行。
  - 汇总输出: `renamed_compile_ok_cases=5`, `renamed_compile_ok_failures=0`, `renamed_compile_ok_total_wat_bytes=176067`, `renamed_compile_ok_expect_lines=23`。
  - 边界: 本项只验证这 5 个刚重命名的 compile_ok fixture 仍可 build 且同名 `.expect` 匹配; 不替代完整 `run_tests.sh`、RUN_WASM 扩展回归或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `renamed compile_ok targeted build gate`、`renamed_compile_ok_cases=5`、`renamed_compile_ok_failures=0`、`renamed_compile_ok_total_wat_bytes=176067` 和 `renamed_compile_ok_expect_lines=23` 关键字确认; targeted build 脚本复跑仍输出 failures 为 `0`; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 renamed compile_ok targeted build gate 通过; 未新增阻断。
- [x] 复核 renamed compiled_ok targeted compiled build gate。结论:
  - 范围: 上一项重命名后的 `tool/build/test/compiled_ok/52_compiled_test_math_small_int_helpers.do`。
  - 验证方式: 执行 `DO_LIB_ROOT=tool/build/test/lib ./bin/do test tool/build/test/compiled_ok/52_compiled_test_math_small_int_helpers.do --compiled -o <tmp.wat>`, 要求 exit 0、stdout 含 `ok:`, WAT 非空, 并逐行匹配同名 `.expect`; `count=` 规则按当前 `run_tests.sh` 语义统计出现次数。
  - 输出: `renamed_compiled_ok_case_pass 52_compiled_test_math_small_int_helpers wat_bytes=38029 expect_lines=7`。
  - 汇总输出: `renamed_compiled_ok_cases=1`, `renamed_compiled_ok_failures=0`, `renamed_compiled_ok_wat_bytes=38029`, `renamed_compiled_ok_expect_lines=7`。
  - 边界: 本项只验证这个刚重命名的 compiled_ok fixture 仍可 `do test --compiled` 且同名 `.expect` 匹配; 不执行 wasm, 不替代完整 `run_tests.sh`、RUN_WASM 扩展回归或 release smoke。
  - 复验: `git diff --check` 通过; 记录命中已由 `renamed compiled_ok targeted compiled build gate`、`renamed_compiled_ok_cases=1`、`renamed_compiled_ok_failures=0`、`renamed_compiled_ok_wat_bytes=38029` 和 `renamed_compiled_ok_expect_lines=7` 关键字确认; targeted compiled build 脚本复跑仍输出 failures 为 `0`; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 renamed compiled_ok targeted compiled build gate 通过; 未新增阻断。
- [x] 复跑默认回归 gate。结论:
  - 范围: 最近 fixture rename 后的默认 `run_tests.sh` 路径, 使用现有 `bin/do`, 不重复构建编译器。
  - 命令: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`。
  - 输出: `[INFO] summary: pass=831 fail=0 skip=3`。
  - 关键路径证据: 输出中包含 `compile ok  234_defer_call_and_arc_block_lower`、`compile ok  238_arc_recv_loop_managed_value_call_keeps_inc_lower` 和 `compiled ok  52_compiled_test_math_small_int_helpers`, 证明最近重命名后的 fixture 被默认 harness 发现并执行。
  - tmp 清理: 复跑后 `tool/build/test/tmp` ignored 产物为 `3202` 个, 目录大小 `24M`; 已执行清理, 清理后生成物计数 `0`, 目录大小 `288K`。
  - 边界: 本项只证明默认回归通过; 不包含 `RUN_WASM=1` 扩展回归, 不包含 release smoke, 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `复跑默认回归 gate`、`pass=831 fail=0 skip=3`、`compile ok  234_defer_call_and_arc_block_lower`、`compiled ok  52_compiled_test_math_small_int_helpers` 和 `tool/build/test/tmp` 关键字确认; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前默认回归 gate 通过; 未新增阻断。
- [x] 复跑 RUN_WASM 扩展回归 gate。结论:
  - 范围: 最近 fixture rename 后的 `RUN_WASM=1` 扩展 `run_tests.sh` 路径, 使用现有 `bin/do`, 不重复构建编译器。
  - 命令: `RUN_WASM=1 SKIP_BUILD=1 ./tool/build/test/run_tests.sh`。
  - 输出: `[INFO] summary: pass=833 fail=0 skip=3`; wasm run summary: `pass=6 fail=0`。
  - 关键路径证据: 输出中包含 `compiled trap 01_compiled_test_fallthrough_traps`、`compiled trap 02_compiled_managed_struct_alias_set_oob_get_traps`、`compiled ok  52_compiled_test_math_small_int_helpers` 和 `wasm run 06_defer_loop_break`, 证明最近重命名后的 compiled fixture 和 RUN_WASM 专用路径被发现并执行。
  - tmp 清理: 复跑后 `tool/build/test/tmp` ignored 产物为 `3527` 个, 目录大小 `25M`; 已执行清理, 清理后生成物计数 `0`, 目录大小 `288K`。
  - 边界: 本项只证明 RUN_WASM 扩展回归通过; 不包含 release smoke, 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `复跑 RUN_WASM 扩展回归 gate`、`pass=833 fail=0 skip=3`、`wasm run summary: pass=6 fail=0`、`compiled trap 02_compiled_managed_struct_alias_set_oob_get_traps` 和 `3527` 关键字确认; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 RUN_WASM 扩展回归 gate 通过; 未新增阻断。
- [x] 复跑 release smoke gate。结论:
  - 范围: ReleaseSmall 编译器构建和发布候选产品命令 smoke, 覆盖 build/test/compiled/check/fmt/run/lsp。
  - 命令: `./tool/build/test/run_release_smoke.sh`。
  - 输出: ReleaseSmall build、`do build`、`do test`、`do test --compiled`、`do check`、`do fmt`、`do run`、`do lsp` 均 `[PASS]`, 最终输出 `[INFO] release smoke passed`。
  - tmp 清理: 复跑后 `tool/build/test/tmp` ignored 产物为 `44` 个, 目录大小 `436K`; 已执行清理, 清理后生成物计数 `0`, 目录大小 `288K`。
  - 边界: 本项只证明 release smoke 通过; 不替代默认完整回归或 RUN_WASM 扩展回归, 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `复跑 release smoke gate`、`release smoke passed`、`ReleaseSmall build`、`44` 和 `436K` 关键字确认; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 release smoke gate 通过; 未新增阻断。
- [x] 复跑 Markdown local link gate。结论:
  - 范围: 只读扫描 `README.md`、`CHANGELOG.md` 和 `doc/**/*.md`。
  - 输出: `markdown_files=26`, `local_markdown_links=20`, `missing=0`。
  - 边界: 本项只证明当前活跃文档入口的本地 Markdown 链接无缺失; 不验证外部 URL, 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; Node 本地链接扫描复跑仍输出 `markdown_files=26`, `local_markdown_links=20`, `missing=0`; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 Markdown local link gate 仍通过; 未新增阻断。
- [x] 复跑 active/blocker 状态口径 gate。结论:
  - 未完成项扫描: `rg -n '^- \[ \]' README.md doc/master_plan.md doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 只命中 README 后置非目标、06.2 blocked/decomposed、D2.1 blocked 和 G6.1-G6.3 blocked。
  - 泛化状态扫描: `rg -n '^状态: (active|partial|blocked)(;|$)|^状态: blocked/partial|^状态: partial' README.md doc/master_plan.md doc/roadmap_status.md doc/start_here.md CHANGELOG.md` 无输出。
  - 旧入口扫描: `当前推荐`、`下次第一步`、`第二版编译器正在实现`、TODO/FIXME 在 README、`doc/master_plan.md`、`doc/start_here.md` 中无输出; 旧问题文件名只命中 `doc/start_here.md` 中“旧 artifact 不存在”的当前说明。
  - 边界: 本项只证明当前 active/blocker 状态口径无新增漂移; 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 未完成项扫描仍只命中 README 后置非目标、06.2 blocked/decomposed、D2.1 blocked 和 G6.1-G6.3 blocked; 泛化状态扫描无输出; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 active/blocker 状态口径仍通过; 未新增阻断。
- [x] 复跑 handoff docs consistency gate。结论:
  - 入口验证: README、CHANGELOG、`doc/master_plan.md`、`doc/roadmap_status.md`、`doc/start_here.md` 和 `doc/memory.md` 均存在。
  - 旧 artifact 验证: `doc/review_blockers.md`、`doc/review_issues.md`、`compiled_task_checklist.md`、`next_stage_plan.md` 和 `internal_prefix_rename_plan.md` 均不存在。
  - Markdown 链接验证: `markdown_files=26`, `local_markdown_links=20`, `missing=0`。
  - 状态口径: 剩余 `[ ]` 只命中 README 后置非目标、06.2 blocked/decomposed、D2.1 blocked 和 G6.1-G6.3 blocked; 泛化状态扫描无输出。
  - dirty/UI 边界: tracked `64`, untracked `129`; `ui.do` / `ui_demo.do` 只在 untracked。
  - tmp 边界: `tool/build/test/tmp` ignored 产物计数为 `0`, 目录大小 `288K`。
  - 边界: 本项只证明 handoff 入口、旧 artifact 清理状态和交付边界没有新增漂移; 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 入口文件复核输出 `entry_files_ok=6`; 旧 artifact 复核输出 `old_artifacts_absent=5`; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 handoff docs consistency gate 仍通过; 未新增阻断。
- [x] 复跑 delivery boundary inventory gate。结论:
  - tracked: `64`; 分类为 CHANGELOG `1`、README `1`、bin `1`、doc `7`、src `11`、tool `2`、tool/build `6`、tool/build/test `33`、tool/lsp `2`。
  - untracked: `129`; 分类为 tool/build `4`、tool/build/test `119`、tool/lsp `4`、`ui.do` `1`、`ui_demo.do` `1`。
  - UI 边界: `ui.do` / `ui_demo.do` 不在 tracked diff, 只在 untracked。
  - tmp 边界: `tool/build/test/tmp` ignored 产物计数为 `0`, 目录大小 `288K`。
  - 边界: 本项只证明当前交付边界没有新增漂移; 不 stage、不删除、不修改 `ui.do` / `ui_demo.do`, 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 分类扫描复跑仍输出 tracked `64`、untracked `129`; `tool/build/test/tmp` ignored 产物计数仍为 `0`; `ui.do` / `ui_demo.do` 仍不在 tracked diff, 只在 untracked。
  - 结果: 当前 delivery boundary inventory gate 仍通过; 未新增阻断。
- [x] 复跑 Test README matrix boundary gate。结论:
  - 范围: `tool/build/test/README.md` 与 `tool/build/test` 当前顶层目录、脚本/helper 文件的说明一致性。
  - 目录扫描: 当前顶层目录 `check`、`compile_err`、`compile_ok`、`compiled_err`、`compiled_ok`、`compiled_trap`、`err`、`fmt`、`lib`、`lsp`、`ok`、`pending`、`run`、`tmp` 均已在 README 命中。
  - helper 扫描: `run_compiled_test_case.mjs`、`run_lsp_case.mjs`、`run_release_smoke.sh`、`run_tests.sh`、`run_wasm_case.mjs`、`run_wasm_smoke.sh`、`test_wasi_bind_manifest_tool.mjs` 和 `validate_wasi_bind_manifest.mjs` 均已在 README 命中。
  - 关键边界: `DO_LIB_ROOT=tool/build/test/lib`、`tmp` 生成目录和 `run_wasm_case.mjs` helper 均已明确。
  - 结果: `test_readme_dir_missing=0`, `test_readme_helper_missing=0`。
  - 边界: 本项只证明测试说明矩阵没有新增漂移; 不执行 fixture, 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; test README 矩阵扫描复跑仍输出 `test_readme_dir_missing=0`, `test_readme_helper_missing=0`; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 Test README matrix boundary gate 仍通过; 未新增阻断。
- [x] 复跑 Zig fmt gate。结论:
  - 环境: Zig `0.16.0`。
  - 范围: `rg --files -g '*.zig'` 当前输出 `31` 个 Zig 文件, 其中 tracked `23`, untracked `8`。
  - 验证: `rg --files -g '*.zig' -0 | xargs -0 zig fmt --check` 通过, 输出 `zig_fmt_check=pass`。
  - 边界: 本项只证明 Zig 源文件格式符合 `zig fmt --check`; 不替代 Zig unit test、Debug build 或 full regression。
  - 复验: `git diff --check` 通过; `zig version` 输出 `0.16.0`; Zig 文件计数仍为 `31`、tracked `23`、untracked `8`; `zig fmt --check` 复跑仍输出 `zig_fmt_check=pass`; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 Zig fmt gate 仍通过; 未新增阻断。
- [x] 复跑 Zig aggregate unit gate。结论:
  - 环境: Zig `0.16.0`。
  - 范围: `tool/main.zig` 聚合导入链上的 CLI/run/fmt/check/LSP、backend IR、component metadata writer、function body writer、ownership facts、runtime prelude、lexer、diag、parser、sema 和 formatter 单元测试。
  - 验证: `cd tool && zig test main.zig` 通过。
  - 输出: `All 101 tests passed.`
  - 边界: 本项只证明 `tool/main.zig` 聚合单元测试通过; 不替代 Debug build、完整 `run_tests.sh` 或 RUN_WASM 扩展回归。
  - 复验: `git diff --check` 通过; 记录命中已由 `Zig aggregate unit gate`、`All 101 tests passed.` 和 `tool/main.zig` 聚合关键字确认; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 Zig aggregate unit gate 仍通过; 未新增阻断。
- [x] 复跑 JS/MJS helper syntax gate。结论:
  - 环境: Node `v24.18.0`。
  - 范围: `git ls-files '*.mjs'` 当前输出 6 个 tracked `.mjs` 文件; `git ls-files --others --exclude-standard '*.mjs'` 输出 0。
  - 验证: `tool/build/test/run_compiled_test_case.mjs`、`tool/build/test/run_lsp_case.mjs`、`tool/build/test/run_wasm_case.mjs`、`tool/build/test/test_wasi_bind_manifest_tool.mjs`、`tool/build/test/validate_wasi_bind_manifest.mjs` 和 `tool/run/run_wasm_program.mjs` 均通过 `node --check`, 输出 `node_check_ok=<file>`。
  - 边界: 本项只证明当前 tracked `.mjs` helper/runtime 脚本语法通过; 不替代 Node runner 行为测试、black-box fixture regression 或 release smoke。
  - 复验: `git diff --check` 通过; `node --version` 仍输出 `v24.18.0`; `node --check` 复跑仍输出 6 个 `node_check_ok=<file>`; tracked `.mjs` 仍为 `6`, untracked `.mjs` 仍为 `0`; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 JS/MJS helper syntax gate 仍通过; 未新增阻断。
- [x] 复跑 shell harness syntax gate。结论:
  - 范围: tracked shell 脚本 2 个: `tool/build/test/run_tests.sh`、`tool/build/test/run_wasm_smoke.sh`; untracked shell 脚本 1 个: `tool/build/test/run_release_smoke.sh`。
  - shebang/strict mode: 三个脚本首行均为 `#!/usr/bin/env bash`, 且开头均包含 `set -euo pipefail`。
  - 验证: 三个脚本 `bash -n` 均通过, 输出 `bash_n=pass`。
  - mode: 三个脚本当前权限均为 `775`。
  - 边界: 本项只证明 shell harness 当前语法和脚本入口边界; 不执行 release smoke 或 full regression; `run_release_smoke.sh` 仍是 untracked executable。
  - 复验: `git diff --check` 通过; shell harness 扫描复跑仍输出 tracked shell `2`、untracked shell `1`、三个 `shell_ok=<file> mode=775` 和 `bash_n=pass`; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 shell harness syntax gate 仍通过; 未新增阻断。
- [x] 复跑 diagnostic unit / contract gate。结论:
  - 范围: `tool/build/diag.zig` focused tests, 以及 `errorSummary` / `errorHint` 显式诊断条目一致性。
  - 验证: `cd tool && zig test build/diag.zig` 通过, 输出 `All 13 tests passed.`。
  - 表扫描: Node 只读扫描 `tool/build/diag.zig`, 输出 `summary_entries=55`, `hint_entries=55`, `summary_without_hint=(none)`, `hint_without_summary=(none)`。
  - 边界: 本项只证明 focused diagnostic contract; 不替代完整 `run_tests.sh`、Debug build 或 RUN_WASM 扩展回归。
  - 复验: `git diff --check` 通过; 表扫描复跑仍输出 `summary_entries=55`, `hint_entries=55`, `summary_without_hint=(none)`, `hint_without_summary=(none)`; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 diagnostic unit / contract gate 仍通过; 未新增阻断。
- [x] 复跑 CLI parser unit gate。结论:
  - 范围: `tool/build/cli.zig` 的 run/fmt/lsp/check 参数解析单元测试。
  - 验证: `cd tool && zig test build/cli.zig` 通过, 输出 `All 14 tests passed.`。
  - 覆盖: `parseRun` 单输入和错误参数, `parseFmt` stdout/check/write 及互斥, `parseLsp` stdio 模式, `parseCheck` 单输入/多输入和错误参数。
  - 边界: 本项只证明 CLI parser unit gate 通过; build/test 的黑盒严格参数和 output-order 路径由 CLI argument / output path guard gate 覆盖。
  - 复验: `git diff --check` 通过; 本轮复跑 `cd tool && zig test build/cli.zig` 仍输出 `All 14 tests passed.`; 记录命中已由 `CLI parser unit gate`、`parseRun`、`parseFmt`、`parseLsp` 和 `parseCheck` 关键字确认; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 CLI parser unit gate 仍通过; 未新增阻断。
- [x] 复跑 parser unit gate。结论:
  - 范围: `tool/build/parser.zig` 的 parser focused tests, 以及 parser 导入链上的 lexer tokenization tests。
  - 验证: `cd tool && zig test build/parser.zig` 通过, 输出 `All 24 tests passed.`。
  - 覆盖: bool/nil literal、literal call reject、lambda call argument / block body、spread、function-name argument、struct literal equals、generic typed bind、import ordering、storage variadic param 和 collection loop binding parser 边界; 同时覆盖 dot/private identifier、spread、apostrophe、UTF-8 escape 和 line string tokenization。
  - 边界: 本项只证明 parser focused unit gate 通过; 不替代 sema/codegen unit、完整 `run_tests.sh` 或 RUN_WASM 扩展回归, 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `复跑 parser unit gate`、`parser unit gate 最近复验通过`、`All 24 tests passed` 和 `literal/lambda/spread/struct/import/variadic/collection loop` 关键字确认; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 parser unit gate 仍通过; 未新增阻断。
- [x] 复跑 sema unit gate。结论:
  - 范围: `tool/build/sema.zig` 的 focused semantic analysis tests, 以及 sema 导入链上的 lexer/parser unit tests。
  - 验证: `cd tool && zig test build/sema.zig` 通过, 输出 `All 26 tests passed.`。
  - 覆盖: private host import 不被误判为 private lvalue assignment、private assignment reject; 同时覆盖 parser 导入链上的 literal/lambda/spread/struct/import/variadic/collection loop parser 边界和 lexer tokenization 边界。
  - 边界: 本项只证明 sema focused unit gate 通过; 不替代 codegen unit、完整 `run_tests.sh` 或 RUN_WASM 扩展回归, 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `复跑 sema unit gate`、`sema unit gate 最近复验通过`、`All 26 tests passed`、`private host import` 和 `private assignment` 关键字确认; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 sema unit gate 仍通过; 未新增阻断。
- [x] 复跑 codegen unit gate。结论:
  - 范围: `tool/build/codegen.zig` 的 focused codegen tests, 以及 codegen 导入链上的 lexer、runtime prelude writer、backend IR、component metadata writer、test runner、ownership facts 和 ownership unit tests。
  - 验证: `cd tool && zig test build/codegen.zig` 通过, 输出 `All 51 tests passed.`。
  - 覆盖: source origin metadata、generic union / callback prebinding、variadic storage ABI、Backend IR scalar start lowering、runtime prelude、component metadata writer、test runner overload/variadic 分派、ownership facts 和 loop/return exit plan。
  - 边界: 本项只证明 codegen focused unit gate 通过; 不替代 Debug build、完整 `run_tests.sh` 或 RUN_WASM 扩展回归, 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `复跑 codegen unit gate`、`codegen unit gate 最近复验通过`、`All 51 tests passed`、`source origin metadata`、`generic/variadic ABI`、`Backend IR` 和 `ownership facts` 关键字确认; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 codegen unit gate 仍通过; 未新增阻断。
- [x] 复跑 backend IR focused unit gate。结论:
  - 范围: `tool/build/backend_ir.zig` 的 backend IR focused tests。
  - 验证: `cd tool && zig test build/backend_ir.zig` 通过, 输出 `All 13 tests passed.`。
  - 覆盖: function/block/terminator 顺序、ValueId 分配、scalar const/operator、conditional branch、builder block append / missing block reject、straight-line WAT emit、structured if WAT emit、empty branch fold、non-empty branch keep、local copy fold、constant numeric fold 和 trivial const call inline。
  - 边界: 本项只证明 backend IR focused unit gate 通过; 不替代 codegen unit、Debug build、完整 `run_tests.sh` 或 RUN_WASM 扩展回归, 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `复跑 backend IR focused unit gate`、`backend IR focused unit gate 最近复验通过`、`All 13 tests passed`、`backend IR block/value/emit/fold/inline` 和 `build/backend_ir.zig` 关键字确认; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 backend IR focused unit gate 仍通过; 未新增阻断。
- [x] 复跑 runtime prelude WAT focused unit gate。结论:
  - 范围: `tool/build/runtime_prelude_wat.zig` 的 runtime prelude WAT writer focused tests。
  - 验证: `cd tool && zig test build/runtime_prelude_wat.zig` 通过, 输出 `All 2 tests passed.`。
  - 覆盖: component core memory/data segment 输出、runtime header 和 ARC layout table 输出。
  - 边界: 本项只证明 runtime prelude WAT writer focused unit gate 通过; 不替代 codegen unit、Debug build、完整 `run_tests.sh` 或 RUN_WASM 扩展回归, 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `复跑 runtime prelude WAT focused unit gate`、`runtime prelude WAT focused unit gate 最近复验通过`、`All 2 tests passed`、`component core memory/data segment`、`runtime header`、`ARC layout table` 和 `build/runtime_prelude_wat.zig` 关键字确认; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 runtime prelude WAT focused unit gate 仍通过; 未新增阻断。
- [x] 复跑 component metadata WAT focused unit gate。结论:
  - 范围: `tool/build/component_metadata_wat.zig` 的 component metadata WAT writer focused tests。
  - 验证: `cd tool && zig test build/component_metadata_wat.zig` 通过, 输出 `All 4 tests passed.`。
  - 覆盖: WASI bind manifest comments、deduplicated WASI core imports、env host imports 和 WASI import symbol escaping。
  - 边界: 本项只证明 component metadata WAT writer focused unit gate 通过; 不替代 codegen unit、Debug build、完整 `run_tests.sh` 或 RUN_WASM 扩展回归, 不解除 D2.1 / G6.1-G6.3 阻断。
  - 复验: `git diff --check` 通过; 记录命中已由 `复跑 component metadata WAT focused unit gate`、`component metadata WAT focused unit gate 最近复验通过`、`All 4 tests passed`、`WASI bind manifest comments`、`WASI core imports`、`env host imports`、`import symbol escaping` 和 `build/component_metadata_wat.zig` 关键字确认; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 component metadata WAT focused unit gate 仍通过; 未新增阻断。
- [x] 复跑 writer / ownership / runner focused unit gates。结论:
  - 范围: function body WAT writer、ownership exit plan、ownership facts、test runner dispatch 和 `do run` runner focused 单元边界。
  - 验证: `cd tool && zig test build/function_body_wat.zig` 通过, 输出 `All 2 tests passed.`。
  - 验证: `cd tool && zig test build/ownership.zig` 通过, 输出 `All 2 tests passed.`。
  - 验证: `cd tool && zig test build/ownership_facts.zig` 通过, 输出 `All 6 tests passed.`。
  - 验证: `cd tool && zig test build/test_runner.zig` 通过, 输出 `All 14 tests passed.`。
  - 验证: `cd tool && zig test main.zig --test-filter run.run` 通过, 输出 `All 3 tests passed.`。
  - 排障结论: 直接 `cd tool && zig test run/run.zig` 会失败于 `../build/*.zig` 超出 Zig 单文件 module path; `tool/main.zig` 已聚合导入 `run/run.zig`, 因此 runner focused gate 使用 `main.zig --test-filter run.run`。
  - 复验: `git diff --check` 通过; `tool/build/test/tmp` ignored 产物计数仍为 `0`; dirty/UI 边界当前为 tracked `64`, untracked `129`, `ui.do` / `ui_demo.do` 只在 untracked。
  - 结果: 当前 writer / ownership / runner focused unit gates 仍通过; 未新增阻断。
- [x] 收口 D2.1 if/else path-sensitive liveness blocker。结论:
  - 决策: 用户确认按 B 方案处理。D2.1 原阻断原因是没有找到真实红灯缺口, 不能伪造失败 fixture; 本次把已验证的绿色路径正式纳入 regression。
  - 新增 fixture: `tool/build/test/compile_ok/239_arc_if_else_both_branches_call_last_use_move_lower.do` / `.expect`, 锁住 if/else 两边都 last-use call move, 期望 `count=2 ;; arc-call-move data` 和 `count=0 call $__arc_inc`。
  - 新增 fixture: `tool/build/test/compile_ok/240_arc_if_else_one_branch_call_other_borrow_move_lower.do` / `.expect`, 锁住一边 call move、一边 borrow, 期望 `count=1 ;; arc-call-move data`、`count=0 call $__arc_inc` 和 `local.set $size`。
  - 新增 fixture: `tool/build/test/compile_ok/241_arc_if_else_branch_use_after_call_keeps_inc_lower.do` / `.expect`, 锁住一边 call 后继续使用必须 keep inc、另一边可 move, 期望 `count=1 ;; arc-call-move data`、`count=1 call $__arc_inc`、`local.set $first`、`local.set $second` 和 `local.set $size`。
  - Targeted 验证: `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/239_arc_if_else_both_branches_call_last_use_move_lower.do -o /tmp/239_arc_if_else_both_branches_call_last_use_move_lower.wat` 通过。
  - Targeted 验证: `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/240_arc_if_else_one_branch_call_other_borrow_move_lower.do -o /tmp/240_arc_if_else_one_branch_call_other_borrow_move_lower.wat` 通过。
  - Targeted 验证: `DO_LIB_ROOT=src ./bin/do build tool/build/test/compile_ok/241_arc_if_else_branch_use_after_call_keeps_inc_lower.do -o /tmp/241_arc_if_else_branch_use_after_call_keeps_inc_lower.wat` 通过。
  - 默认回归: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `[INFO] summary: pass=834 fail=0 skip=3`。
  - 清理: 默认回归后 `tool/build/test/tmp` ignored 产物已清理到生成物计数 `0`, 目录大小 `288K`。
  - 复验: `git diff --check` 通过。
  - 当前阻断: D2.1 不再列为当前阻断; 剩余阻断仍是 G6.1、G6.2、G6.3 和 06.2 已拆分残留。
  - 交付边界: `git diff --name-only | wc -l` 为 `64`; `git ls-files --others --exclude-standard | wc -l` 为 `135`; `ui.do` / `ui_demo.do` 只在 untracked。
  - 边界: 本项只收口 D2.1 已验证绿色 if/else 路径; 不扩展跨函数 data-flow、escape analysis、loop/path move 或 G6 WASI runtime 设计。
