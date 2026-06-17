# Roadmap 执行状态

更新时间: 2026-06-17

执行原则: 按 `README.md` Roadmap 自上而下推进; 如果某项卡住或需要跳过, 必须在本文记录原因和后续恢复条件。

推进协议:

1. 每个阶段必须拆成可验证的小任务, 写入本文件对应阶段的 `阶段内小任务`。
2. 每次只推进一个小任务; 未完成当前小任务前, 不切到同阶段其他任务或下一阶段。
3. 小任务完成后, 立即把状态从 `[ ]` 改为 `[x]`, 并补充验证命令或阻塞原因。
4. 如果遇到阻塞, 在该小任务后标注 `blocked`, 写清阻塞证据、停止点和恢复条件。
5. 提交或交付前, 必须确认本文件的状态与代码、测试和文档同步。

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

当前结论: `do run <input.do>` 第一版已落地, 执行策略固定为外部 `wasm-tools + node` 桥接。`do fmt <input.do>` 第一版已落地, 当前只支持 stdout 输出和 `--check` 检查, 不做原地写回。`07.3 do lsp` 已完成阶段计划, 推荐先落地 diagnostics-only stdio server。get / push 仍缺少当前 spec 中的命令语义、输入输出契约和回归口径, 继续跳过。

`do run` 当前边界:

- 编译路径: 复用 `do build` 同源 WAT 编译 helper。
- 执行路径: 写临时 WAT, 调用 `wasm-tools parse` 生成 wasm, 再由 `node tool/run/run_wasm_program.mjs` 执行。
- 依赖策略: 本机 PATH 必须可找到 `wasm-tools` 和 `node`; 缺失时输出 `error[MissingExternalTool]: <tool> not found`。
- 行为边界: stdout/stderr/exit status 透传子进程结果; 当前只覆盖 `tool/build/test/run/*.do` 的 core wasm smoke 子集。
- 不包含: WASI / Component Model runtime、自定义 host runtime、内置 wasm runtime、真实网络或完整资源 ABI。

`do fmt` 当前边界:

- 命令形态: `do fmt <input.do>` 输出格式化后的源码到 stdout; `do fmt --check <input.do>` 只检查输入是否已格式化。
- 格式化范围: 第一版 line-based formatter, 覆盖 CRLF/CR -> LF、尾随空白清理、基于 `{}` 的 4 空格缩进、最终单换行和当前行字符串缩进保留策略。
- 回归范围: `tool/build/test/fmt/*.do` / `.expect` 覆盖 stdout、idempotence 和 `error[FormatMismatch]`。
- 不包含: 原地写回、范围格式化、语法感知 comment/string brace 解析、LSP formatter 接入。

剩余跳过原因: get / push 直接实现会把工具接口固化在未定义行为上。

恢复条件:

- 按 `docs/superpowers/plans/2026-06-17-lsp-07-3.md` 推进 LSP diagnostics-only 第一版。
- 为 get / push 明确包源、版本、认证和发布/回滚规则。

阶段内小任务:

- [x] 07.1 落地 `do run` 第一版执行环境、依赖策略、stdout/stderr/exit 行为和 host import 支持范围。验证: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, `do run missing wasm-tools`、`do run missing node` 和 6 个 `do run` smoke case 均执行, 摘要 `pass=666 fail=0 skip=70`。
- [x] 07.2.1 明确 fmt 格式化规范和稳定输出回归。验证: `docs/superpowers/specs/2026-06-17-fmt-design.md` 已定义 `do fmt <input.do>`、`do fmt --check <input.do>`、stdout/check-only、idempotence、fixture `.expect` 和缺口边界; `docs/superpowers/plans/2026-06-17-fmt-07-2.md` 已拆出 CLI、formatter core、runner、fixture 回归和文档同步任务。
- [x] 07.2.2 实现 `do fmt` CLI contract。验证: `cd tool && zig test build/cli.zig` 通过 `6/6`; `cd tool && zig test main.zig` 通过 `3/3`; `cd tool && zig build -Doptimize=Debug` 通过。当前 `tool/fmt/run.zig` 仅为最小 runner 骨架, 真实格式化输出继续按 Task 2/3 推进。
- [x] 07.2.3 实现 pure formatter core。验证: `tool/fmt/format.zig` 已新增 `formatSource(allocator, source)` 和三条 focused tests; `cd tool && zig test fmt/format.zig` 通过 `3/3`; `cd tool && zig test main.zig` 通过 `3/3`。
- [x] 07.2.4 实现 `tool/fmt/run.zig` 命令 runner。验证: `cd tool && zig test fmt/format.zig` 通过 `3/3`; `cd tool && zig test main.zig` 通过 `3/3`; `cd tool && zig build -Doptimize=Debug` 通过; 临时文件实测 `do fmt` stdout 输出、`do fmt --check` 成功和 mismatch `error[FormatMismatch]` 均符合计划。
- [x] 07.2.5 接入 fixture 回归、idempotence 和 `--check` 覆盖。验证: `tool/build/test/fmt/01_struct_func_indent.do`、`tool/build/test/fmt/02_comments_line_strings.do`、`tool/build/test/fmt/03_control_blocks.do` 及其 `.expect` 已接入 `tool/build/test/run_tests.sh`; `bash -n tool/build/test/run_tests.sh` 通过; `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, `fmt` 段三例均通过, 总摘要 `pass=669 fail=0 skip=70`。
- [x] 07.2.6 同步 README、start_here 和最终验证。验证: `README.md` 已记录 `do fmt <input.do>`、`do fmt --check <input.do>` 和 stdout/check-only 边界; `doc/start_here.md` 下一步已切到 `07.3 LSP`; 最终验证通过: `cd tool && zig test build/cli.zig` 6/6, `cd tool && zig test fmt/format.zig` 3/3, `cd tool && zig build -Doptimize=Debug`, `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 摘要 `pass=669 fail=0 skip=70`。
- [x] 07.3.0 明确 LSP 最小能力集和诊断来源。结论: 第一版只做 diagnostics-only stdio server, 不做 completion / hover / definition / rename / formatting; 诊断来源复用 lexer/parser/sema/imports fail-fast 链路, 当前每个 document 最多发布一个编译诊断。验证: `docs/superpowers/plans/2026-06-17-lsp-07-3.md`。
- [ ] 07.3.1 固定 `do lsp [--stdio]` CLI contract。计划: `docs/superpowers/plans/2026-06-17-lsp-07-3.md` Task 1。
- [ ] 07.3.2 暴露结构化 compiler diagnostics。计划: `docs/superpowers/plans/2026-06-17-lsp-07-3.md` Task 2。
- [ ] 07.3.3 实现纯 LSP diagnostics collector。计划: `docs/superpowers/plans/2026-06-17-lsp-07-3.md` Task 3。
- [ ] 07.3.4 实现最小 JSON-RPC/LSP protocol helper。计划: `docs/superpowers/plans/2026-06-17-lsp-07-3.md` Task 4。
- [ ] 07.3.5 实现 `do lsp` stdio server。计划: `docs/superpowers/plans/2026-06-17-lsp-07-3.md` Task 5。
- [ ] 07.3.6 接入 LSP smoke regression harness。计划: `docs/superpowers/plans/2026-06-17-lsp-07-3.md` Task 6。
- [ ] 07.3.7 同步 README、测试说明、roadmap 和 start_here。计划: `docs/superpowers/plans/2026-06-17-lsp-07-3.md` Task 7。
- [ ] 07.4 明确 get / push 包源、版本、认证和发布/回滚规则。前置: 包管理规范。
