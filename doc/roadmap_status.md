# Roadmap 执行状态

更新时间: 2026-06-09

执行原则: 按 `README.md` Roadmap 自上而下推进; 如果某项卡住或需要跳过, 必须在本文记录原因和后续恢复条件。

## 01. 运行时内存模型

状态: done

结论: v1 managed handle、对象头、`type_id`、layout table 和 ARC 管理已落地到当前 build 子集。

证据:

- `doc/memory.md` 已定义 handle、0 sentinel、对象头 `rc/type_id`、layout table、ARC 插桩和 release worklist。
- `tool/build/codegen.zig` 已生成 `__do_arc_payload`、`__do_arc_rc`、`__do_arc_type_id`、`__do_arc_inc`、`__do_arc_dec`、`__do_arc_release` 和 layout helper。
- `tool/build/test/compile_ok/22_arc_bump_alloc_runtime_prelude.do` 到 `47_arc_struct_layout_table_runtime_prelude.do` 覆盖 allocator、对象头、refcount、release worklist 和 layout table。
- `tool/build/test/compile_ok/48_arc_managed_struct_alloc_lower.do` 到 `74_arc_storage_multi_return_duplicate_local_inc.do` 覆盖 managed struct、storage handle、局部 release、return move/copy 和多返回 ownership。
- `tool/build/test/compile_ok/121_defer_call_and_arc_block_lower.do` 覆盖 `defer` cleanup 先于被离开区域 ARC release 的 lowering 顺序。

## 02. 内存分配器

状态: done

结论: v1 allocator 的 1KB block、bitmap small block、large span、free span split/merge 和空 small block 回收已落地到当前 build 子集。

证据:

- `doc/memory_layout_structs.md` 已定义 `SlotClassState`、`SmallBlock`、`LargeBlock`、`FreeBlock` 和 managed `Object` 布局。
- `tool/build/codegen.zig` 已生成 `__do_arc_alloc_small`、`__do_arc_alloc_large`、`__do_free_span_find`、`__do_free_span_split_tail`、`__do_free_span_merge_neighbors`、`__do_arc_release_small` 和 `__do_arc_release_large`。
- `tool/build/test/compile_ok/31_arc_allocator_split_runtime_prelude.do` 到 `43_arc_empty_small_block_reclaims_free_span_runtime_prelude.do` 覆盖 small/large allocation、slot class state、slot reuse、large span reclaim、free span reuse、unlink、split、merge 和 empty small block reclaim。

## 03. ARC / Perceus 完整分析

状态: skipped

跳过原因: 当前编译器仍以 token-level lowering 为主, 没有独立 IR、ownership graph 或 data-flow pass。完整静态插入、冗余 `inc/dec` 消除、末次使用优化和 FBIP `reuse` 需要先建立 ownership IR; 直接在现有 codegen 分支里硬补会把优化逻辑混入语法扫描, 风险高且难验证。

当前已保留的正确性能力:

- managed storage / managed struct 的 `inc/dec`。
- return move / copy 的基础 ownership。
- 局部变量 fallthrough、return、break、continue 和 `defer` cleanup 的 release 顺序。

恢复条件:

- 先设计并落地 compiler ownership IR 或等价 data-flow pass。
- 为冗余消除、last-use move 和 FBIP `reuse` 分别补 WAT expect 与 compiled/run 用例。

## 04. 标准库边界

状态: done

结论: `[u8]`、`List`、`Map`、IO、网络和 `text` runtime 的 core / std / runtime 边界已收敛到当前 v1 子集。完整 I/O 执行能力和复杂 WIT lowering 不在本项内, 继续归入最后的 WASI / Component Model。

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

延后原因: 用户已明确要求 WASI 不是现阶段目标, 放到最后处理。当前只保留已登记 `@wasi` manifest、shim、component-core 输入与标准库 wrapper 子集作为守门。

## 07. 生态工具

状态: skipped

跳过原因: `do run` 需要先确定执行策略, 例如内置 wasm runtime、外部 `wasm-tools + node` 桥接, 或后续 component runtime; LSP、fmt、get / push 也缺少当前 spec 中的命令语义、输入输出契约和回归口径。直接实现会把工具接口固化在未定义行为上。

恢复条件:

- 为 `do run` 明确执行环境、依赖策略、stdout/stderr/exit 行为和 host import 支持范围。
- 为 fmt 明确格式化规范和稳定输出回归。
- 为 LSP 明确最小能力集, 例如诊断、跳转或补全的优先顺序。
- 为 get / push 明确包源、版本、认证和发布/回滚规则。
