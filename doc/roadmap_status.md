# Roadmap 执行状态

更新时间: 2026-06-15

执行原则: 按 `README.md` Roadmap 自上而下推进; 如果某项卡住或需要跳过, 必须在本文记录原因和后续恢复条件。

## 01. 运行时内存模型

状态: done

结论: v1 managed handle、对象头、`type_id`、layout table 和 ARC 管理已落地到当前 build 子集。

证据:

- `doc/memory.md` 已定义 handle、0 sentinel、对象头 `rc/type_id`、layout table、ARC 插桩和 release worklist。
- `tool/build/codegen.zig` 已生成 `__arc_payload`、`__arc_rc`、`__arc_type_id`、`__arc_inc`、`__arc_dec`、`__arc_release` 和 layout helper。
- `tool/build/test/compile_ok/22_arc_bump_alloc_runtime_prelude.do` 到 `47_arc_struct_layout_table_runtime_prelude.do` 覆盖 allocator、对象头、refcount、release worklist 和 layout table。
- `tool/build/test/compile_ok/48_arc_managed_struct_alloc_lower.do` 到 `74_arc_storage_multi_return_duplicate_local_inc.do` 覆盖 managed struct、storage handle、局部 release、return move/copy 和多返回 ownership。
- `tool/build/test/compile_ok/121_defer_call_and_arc_block_lower.do` 覆盖 `defer` cleanup 先于被离开区域 ARC release 的 lowering 顺序。

## 02. 内存分配器

状态: done

结论: v1 allocator 的 1KB block、bitmap small block、large span、free span split/merge 和空 small block 回收已落地到当前 build 子集。

证据:

- `doc/memory_layout_structs.md` 已定义 `SlotClassState`、`SmallBlock`、`LargeBlock`、`FreeBlock` 和 managed `Object` 布局。
- `tool/build/codegen.zig` 已生成 `__arc_alloc_small`、`__arc_alloc_large`、`__free_span_find`、`__free_span_split_tail`、`__free_span_merge_neighbors`、`__arc_release_small` 和 `__arc_release_large`。
- `tool/build/test/compile_ok/31_arc_allocator_split_runtime_prelude.do` 到 `43_arc_empty_small_block_reclaims_free_span_runtime_prelude.do` 覆盖 small/large allocation、slot class state、slot reuse、large span reclaim、free span reuse、unlink、split、merge 和 empty small block reclaim。

## defer 完整控制流与 ARC

状态: done

结论: `defer` 的 LIFO cleanup、跨 `return/break/continue` lowering、cleanup block 内 managed locals release 和基础 ARC release 顺序已落地到当前 build 子集。

证据:

- `tool/build/test/compile_ok/142_defer_lifo_multiple_cleanups_lower.do` 到 `150_defer_recv_loop_control_lower.do` 覆盖 cleanup 顺序、return、guard return、break、continue、labeled break、cleanup block、collection loop 和 recv loop。
- `tool/build/test/err/267_defer_call_requires_nil.do`、`274_imported_defer_call_requires_nil.do`、`288_defer_block_return.do`、`289_defer_block_break.do`、`290_defer_block_continue.do`、`304_defer_intrinsic_call.do`、`305_defer_non_call_expr.do` 覆盖非法 cleanup 形态。
- `tool/build/codegen.zig` 的 `emitDeferCleanupStack(...)`、`emitDeferCleanupStackThrough(...)`、`emitReturnStmt(...)`、`emitGuardReturnIf(...)` 和 `emitLoopControlJump(...)` 是当前 lowering 锚点。
- `./tool/build/test/run_tests.sh` 当前回归摘要为 `pass=652 fail=0 skip=70`。

## 03. ARC / Perceus 完整分析

状态: in_progress

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
- loop / collection loop / recv loop / field reflection loop 内的 call 参数 move 仍保持保守，避免把 loop-carried source 误判成末次使用。
- 还没有 FBIP `reuse`、escape analysis 或 region。

继续条件:

- 若继续扩字段读取 move，先设计唯一拥有 / alias 证明，不能只按语法末次使用放开。
- 若继续扩 loop 内 move，先建立 loop-carried source 分析或更强的 data-flow 边界。
- FBIP `reuse` 必须在 ownership、mutability 和 COW 回退条件都明确后单独推进。

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

## 05. 后端优化

状态: skipped

跳过原因: 当前后端以 token-level WAT 字符串生成和分支式 lowering 为主, 入口仍是 `emitWat*` 输出 `.wat` 文本。控制流优化、`@get/@set` 内联、小函数内联和 WASM binary emitter 都需要先拆出稳定 IR 或 backend instruction model; 直接在现有字符串 emission 中做 peephole/inline 会和 ARC ownership 分析缺口叠加, 风险高且难验证。

当前已保留的正确性能力:

- `if/else/else if`、`loop`、`break/continue` 和 `return` 的 WAT lowering。
- `@get/@set/@put`、storage、managed struct、multi-return 和 imported wrapper 的 WAT lowering。
- `do build` 和 `do test --compiled` 的 WAT 输出。

恢复条件:

- 先建立 IR / backend instruction model, 或至少建立独立 optimization pass 输入输出。
- 为控制流优化、小函数内联、`@get/@set` 内联和 binary output 各自补 compile/run 回归。

## 06. WASI / Component Model FFI

状态: deferred

延后原因: 用户已明确要求 WASI 不是现阶段目标, 放到最后处理。

当前保留的守门能力:

- `doc/wit/wasi_p3_lowering.md` 固定当前 `@wasi` / WIT / component lowering 的 compiler-facing 合同, 明确哪些 binding 已可 lower, 哪些仍是 unsupported。
- `doc/wit/wasi_registry.json` 是当前已登记 WIT target / record mirror registry, 供 manifest 校验与 component-plan 工具消费。
- `tool/build/test/validate_wasi_bind_manifest.mjs` 已能对 `wasi-bind` manifest 做 registry 校验, 并生成 `--json`、`--component-plan`、`--wit`、`--core-imports`、`--core-shims` 和 `--component-input-dir` 产物。
- `tool/build/test/run_tests.sh` 已把 `doc/wit/wasi_registry.json` 接入 WASI manifest / component-input / component-core 回归 gate。
- `tool/build/test/ok/118_wasi_p3_std_wrappers.do` 与相关 `compile_ok/*.component_*` 用例覆盖当前公开 wrapper 子集和 component builder 输入验证链。

## 07. 生态工具

状态: skipped

跳过原因: `do run` 需要先确定执行策略, 例如内置 wasm runtime、外部 `wasm-tools + node` 桥接, 或后续 component runtime; LSP、fmt、get / push 也缺少当前 spec 中的命令语义、输入输出契约和回归口径。直接实现会把工具接口固化在未定义行为上。

恢复条件:

- 为 `do run` 明确执行环境、依赖策略、stdout/stderr/exit 行为和 host import 支持范围。
- 为 fmt 明确格式化规范和稳定输出回归。
- 为 LSP 明确最小能力集, 例如诊断、跳转或补全的优先顺序。
- 为 get / push 明确包源、版本、认证和发布/回滚规则。
