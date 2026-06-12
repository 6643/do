# Compiled 路径任务清单

更新时间: 2026-06-12

## 1. 当前目标

记录事项:

1. 用工作树现场证据刷新回归结果、阶段状态和主线描述。
2. 复核已落地的 JSON、lambda、变量声明和 `loop` 只读规则在摘要页、入口页与清单页中的同步状态, 并清理 `doc/` 目录中的过期双源与残留噪音。

阻塞规则: 如果出现真实底层阻塞, 停止继续扩大修复范围, 在本文件追加阻塞原因、方案选项、推荐方案和验证口径。

## 2. 详细清单

### 2.1 `35_list_lib_ops.do --compiled`

闭环状态:

1. [x] `tool/build/test/ok/35_list_lib_ops.compiled_must_pass` 存在, 该用例进入 compiled 必过集合。
2. [x] 覆盖 `List<T>` 具体化、`[T]` storage 具体化、`rest ...T`、collection loop、managed struct `@set` 写回、多返回赋值和 `@put` concrete elem type 发射。

证据:

- `tool/build/test/ok/35_list_lib_ops.do:10-51` 覆盖 `list lib ops`、`list lib len`、`list lib get`、`list lib get_or`、`list lib set_or missing` 这 5 个测试块。
- `src/list.do:90-99` 的 `list_add(...)` 覆盖 `rest ...T`、`loop item, _ = rest { ... }` 和 `@put(next_data, item)`。
- `src/list.do:109-112` 的 `list_set_or(...)` 与 `tool/build/test/ok/35_list_lib_ops.do:42,49` 的 `value, ok = list_get_or(...)`、`next, ok = list_set_or(...)` 锁多返回赋值。
- `tool/build/codegen.zig:4156-4335` 覆盖 `emitMultiResultAssignment(...)` / `emitMultiResultLhsSet(...)`。
- `tool/build/codegen.zig` 对 `std.debug.print` 的检索无命中。

### 2.2 `114_list_common_ops.do --compiled`

闭环状态:

1. [x] `tool/build/test/ok/114_list_common_ops.compiled_must_pass` 存在, 该用例进入 compiled 必过集合。
2. [x] 覆盖 `List<T>` common ops、`items(xs)` storage expression、union-return 与 `nil` 比较、storage 内容比较。

证据:

- `tool/build/test/ok/114_list_common_ops.do:14-40` 覆盖 `list_add(empty, 4, 5, 4)`、`missing = list_index_of(xs, 9)`、`list_items(xs)`、`list_items(cleared)` 和 `@eq(missing, nil)`。
- `tool/build/codegen.zig:4156-4335` 覆盖多返回赋值。
- `tool/build/codegen.zig:5273-5395` 覆盖 `emitUnionNilComparison(...)` / `emitUnionPayloadComparisonCall(...)`。
- `tool/build/codegen.zig:2268,2796,2904,4758,4847` 覆盖 storage 聚合字面量和 storage 内容比较发射。

### 2.3 `19_lambda_callback_site.do --compiled`

闭环状态:

1. [x] `tool/build/test/ok/19_lambda_callback_site.compiled_must_pass` 存在, 该用例进入 compiled 必过集合。
2. [x] 覆盖 callback site concrete instance、lambda 参数 alias、返回类型和 callback binding 一致性。

证据:

- `tool/build/test/ok/19_lambda_callback_site.do:5-17` 覆盖 `map(xs, (x i32) => ...)` 与 `map(xs, step, (x i32, step i32) => ...)`。
- `tool/build/codegen.zig:9785-9863` 覆盖 `collectGenericFuncInstancesInRange(...)`、`collectGenericFuncInstancesInCallArgs(...)` 和字段反射 loop 内递归收集。

### 2.4 `61_lambda_block_return.do --compiled`

闭环状态:

1. [x] `tool/build/test/ok/61_lambda_block_return.compiled_must_pass` 存在, 该用例进入 compiled 必过集合。
2. [x] 覆盖 `(x i32) -> T { return ... }` block lambda 返回路径。

证据:

- `tool/build/test/ok/61_lambda_block_return.do:5-9` 覆盖 `map(xs, (x i32) -> i32 { return @add(x, 1) })`。
- `tool/build/codegen.zig:9785-9863` 覆盖 callback 实参中的 generic instance 收集路径。

### 2.5 清理和回归

闭环状态和剩余项:

1. [x] `tool/build/codegen.zig` 中无临时 `std.debug.print`。
2. [x] `emitBody(...)` 命中只剩正常 lowering 调用点或定义位; `errdefer` 命中只剩资源清理路径。
3. [x] `tool/build/test/compile_ok/30_storage_u8_alias_write_inc_lower.do/.expect` 锁 typed storage binding 的 `@set/@put` 写路径。
4. [x] `tool/build/test/compile_ok/53_arc_managed_struct_overwrite_release_lower.do/.expect` 锁 managed struct local overwrite-release 路径。
5. [x] `./tool/build/test/run_tests.sh` 现场结果记录为 `pass=557 fail=0 skip=70`。
6. [ ] 确认工作树中只包含本任务相关变更

证据:

- `tool/build/test/compile_ok/30_storage_u8_alias_write_inc_lower.expect:11-25` 覆盖 `__do_storage_overwrite_tmp` 与 `;; arc-overwrite-release next`。
- `tool/build/test/compile_ok/53_arc_managed_struct_overwrite_release_lower.expect:1-14` 覆盖 `;; arc-overwrite-release box`。
- `tool/build/codegen.zig:3897-3918` 显示 `emitMultiResultAssignment(...)`、`emitManagedLocalAssignment(...)` 排在 `inferredStructBinding(...)` 前面。
- `tool/build/codegen.zig:4422-4480` 显示 `emitReplaceManagedLocalFromTmp(...)` 和 `emitManagedLocalAssignment(...)` 的 overwrite-release 发射路径。
- `git status --short` 现场仍有 `README.md`、`doc/spec*.md`、`doc/syntax/*.md`、`doc/memory*.md`、`doc/roadmap_status.md`、`src/file.do`、`src/io.stream.do`、`src/json.do`、`tool/build/{codegen,diag,imports,parser,sema}.zig`、多组 `tool/build/test/{ok,err,compile_ok}` 用例，以及 `docs/`、`js/`、`ui.do`、`ui_demo.do` 等并行改动; `2.5.6` 继续未勾选。

## 3. 主线恢复点

### 3.1 已同步语法/语义面

1. JSON 泛型解码:
   - `doc/syntax/generic.md:56-57` 展示 `from_json<User>(bytes)`。
   - `doc/spec_rules.md:764,930,1204` 固定 `#T from_json(bytes [u8]) -> T | JsonError`、不走返回上下文反推、调用点显式类型实参。
   - 回归锚点: `tool/build/test/ok/141_json_struct_from_json.do`、`143_json_from_json_defaults.do`、`144_json_from_json_nested.do`、`145_json_from_json_errors.do`、`146_json_from_json_text_and_bytes.do` 及同名 `*.compiled_must_pass`。
2. block lambda / nil block sugar:
   - `doc/syntax/expression.md:90-113` 展示 `(x i32) -> i32 { ... }`、`(x i32) { ... }` 和表达式体 lambda。
   - `doc/spec_rules.md:658-665` 固定 callback-site、参数/返回类型省略和 `(x T) { ... }` 的目标 `FuncType` 约束。
   - 回归锚点: `tool/build/test/ok/147_lambda_block_nil_return.do`、`148_lambda_block_nil_sugar.do`、`19_lambda_callback_site.do` 及同名 `*.compiled_must_pass`。
3. 参数、typed bind 和 `loop` 绑定:
   - `doc/syntax/function.md:55-67` 固定参数必须显式写类型, 参数绑定可重新赋值。
   - `doc/syntax/control.md:118` 固定 `name Type = expr` 永远声明新绑定, 不得重声明或遮蔽外层可见绑定。
   - `doc/spec_rules.md:598,639` 固定参数可写、`loop` 绑定只读、loop 绑定位不能用 `_name`。
   - 回归锚点: `tool/build/test/compile_ok/141_param_reassign_lower.do`、`tool/build/test/err/298_loop_binding_assign.do`、`299_loop_second_binding_assign.do`、`300_func_param_missing_type.do`、`301_generic_param_missing_type.do`、`302_inferred_binding_redeclare.do`、`303_local_shadow_typed_bind.do` 及对应 `.expect`。
4. 示例覆盖:
   - `doc/spec_examples.md:355-531` 覆盖 `参数显式类型`、`局部重声明与遮蔽`、`loop 绑定只读` 和 `lambda`。
   - `doc/spec_examples.md:682-683` 属于 `defer` 冲突证据, 不并入上述正例链。

### 3.2 规范入口和文档边界

1. 规范入口:
   - `doc/spec.md:1-28` 只保留入口、阅读路径和维护规则; 详细规则落在 `doc/spec_rules.md`, parser PEG 落在 `doc/grammar.peg`, 正反例落在 `doc/spec_examples.md`, 当前正确语法速查落在 `doc/syntax/`。
   - `doc/spec.md:61-65` 固定 union 只以内联平铺类型表达式出现、顶层 type alias / union alias 已取消、`loop` 分为无限循环/集合循环/消费循环/字段反射循环, 以及 `@wasi` 是 WIT binding。
2. `doc/syntax/README.md` 导航:
   - `doc/syntax/README.md:1-4,19-24` 写明 `doc/syntax/` 按功能拆分, 本页只保留导航与占位速查。
   - 词法、命名和保留名的详细规则以 `doc/spec_rules.md` 第 2 章和 `doc/grammar.peg` 为准。
3. 过期问题文件:
   - `doc/review_blockers.md`、`doc/review_issues.md`、`doc/memory_layout_questions.md`、`doc/syntax.md` 的仓内检索只命中 `doc/compiled_task_checklist.md`。
   - `doc/memory_layout_questions.md` 已删除; allocator/layout 阅读路径由 `doc/spec.md:12-17,24-25`、`README.md:71-72`、`doc/roadmap_status.md:7-32` 指向 `doc/memory.md` 和 `doc/memory_layout_structs.md`。
4. 长期草案和原型:
   - `doc/spec.md:14` 把 `doc/arc.md` 标成长期 ARC/Perceus/并发优化草案。
   - `doc/implementation_plan.md:50-52` 把 `doc/arc.ts`、`doc/arc_allocator.ts`、`doc/arc_object_runtime.ts`、`doc/arc_cow_runtime.ts` 标成分析/验证原型, 不作为当前编译器实现权威来源。
   - `doc/arc.ts:89`、`doc/arc_allocator.ts:140`、`doc/arc_object_runtime.ts:20-21`、`doc/arc_cow_runtime.ts:19` 的 `Map<` 命中都是 TypeScript 原型里的容器代码。

### 3.3 README / Roadmap 证据和冲突

1. README 基线:
   - `README.md:5-23` 固定仓库定位、核心理念、规范入口、WASI / WIT lowering 入口、程序入口和目录结构。
   - `README.md:67,77,83` 的 roadmap 分组是 `已完成`、`暂跳过`、`最后处理`; `README.md:69,74` 明确前端和 WAT 代码生成只代表当前回归子集可用。
   - `README.md:73` 与 `doc/roadmap_status.md:54` 都使用 `HashMap` 和“网络类型形态”, 不使用库类型 `Map`。
2. 运行时内存和 allocator:
   - `README.md:71-72` 锚到 `doc/roadmap_status.md:7-32` 的两个 `done` 段。
   - 实现锚点是 `tool/build/codegen.zig` 的 `__do_arc_payload/__do_arc_rc/__do_arc_type_id/__do_arc_inc/__do_arc_dec/__do_arc_release`、`__do_arc_alloc_small/__do_arc_alloc_large/__do_free_span_find/__do_free_span_split_tail/__do_free_span_merge_neighbors/__do_arc_release_small/__do_arc_release_large`。
   - 回归锚点包括 `tool/build/test/compile_ok/22_arc_bump_alloc_runtime_prelude.do`、`31_arc_allocator_split_runtime_prelude.do`、`43_arc_empty_small_block_reclaims_free_span_runtime_prelude.do`、`47_arc_struct_layout_table_runtime_prelude.do`、`121_defer_call_and_arc_block_lower.do`。
3. 标准库边界:
   - `doc/roadmap_status.md:50-64` 把 `[u8]`、`List`、`HashMap`、IO、网络类型形态和 `text` runtime 的 core / std / runtime 边界记为 `done`。
   - `src/bytes.do`、`src/text.do`、`src/list.do`、`src/hash_map.do` 提供普通 std 形态与 helper。
   - `src/file.do`、`src/dir.do`、`src/io.stream.do` 通过私有 `.host_* = @wasi(...)` 承接已登记 binding, 对外暴露 do 层资源结构、错误枚举和 wrapper 函数。
   - `src/tcp.do`、`src/udp.do`、`src/http.client.do` 只停在 do 层类型与错误形态, 不在源码接口层暴露复杂 raw WIT host ABI。
4. WIT / WASI gate:
   - `doc/spec.md:65` 固定 `@wasi` 是 WIT binding, 不是普通 core Wasm import。
   - `doc/roadmap_status.md:82-94` 把 WASI / Component Model 标成 `deferred`, 并保留 `doc/wit/wasi_p3_lowering.md`、`doc/wit/wasi_registry.json`、`validate_wasi_bind_manifest.mjs`、`run_tests.sh` gate 和相关 wrapper/component-input 用例。
   - `tool/build/test/README.md:15-20` 和 `tool/build/test/run_tests.sh:380-720` 覆盖 `component_plan`、`wit_dir`、`core_imports`、`core_shims`、`component_input`、`component_core` 这些默认 `compile_ok` gate。
5. `RUN_WASM=1` 冲突:
   - `README.md:75` 把 `RUN_WASM=1` 写成“额外执行 wasm run、compiled wasm 执行、compiled trap 和可用时的 component/embed/validate gate”。
   - `tool/build/test/run_tests.sh:837,911-1012,1033` 只把 compiled wasm 执行、`compiled_trap` 和 `run_wasm_smoke.sh` 放进 `RUN_WASM=1` 分支。
   - `tool/build/test/run_tests.sh:380-720` 显示 component-plan/core-imports/core-shims/component-input/component-core gate 默认就在 `compile_ok` 分支里执行。
   - 结论: README 把默认 component gate 和 `RUN_WASM=1` 增量 gate 写在同一句, 与脚本接线不一致。
6. `defer` 冲突:
   - `README.md:70` 把 `defer` 基础语法和前端校验列为已完成; `README.md:78` 把完整控制流与 ARC 列为暂跳过; `doc/spec_rules.md:41` 把 `defer` 记为已落地 statement 关键字。
   - 回归锚点: `tool/build/test/ok/127_defer_syntax_static.do`、`129_imported_defer_nil.do`、`tool/build/test/compile_ok/121_defer_call_and_arc_block_lower.do`。
   - `doc/spec_examples.md:682-683` 先给出 `## defer` cleanup 示例, 紧接着又写“v1 没有可用 `defer` 语句”。
   - 结论: `doc/spec_examples.md:683` 与 README、`doc/spec_rules.md:41`、`doc/syntax/control.md` 和 `127/129/121` 回归现状冲突; 这里保留为待清理冲突, 不并入已完成证据链。

### 3.4 回归和工作树边界

1. 已执行回归:
   - `./tool/build/test/run_tests.sh` 的现场记录为 `pass=557 fail=0 skip=70`。
   - 覆盖新增用例: `tool/build/test/compile_ok/141_param_reassign_lower.do`, 以及 `tool/build/test/err/297_union_alias_removed.do` 到 `303_local_shadow_typed_bind.do`。
2. compiled 锁文件:
   - `tool/build/test/ok/35_list_lib_ops.compiled_must_pass`
   - `tool/build/test/ok/114_list_common_ops.compiled_must_pass`
   - `tool/build/test/ok/19_lambda_callback_site.compiled_must_pass`
   - `tool/build/test/ok/61_lambda_block_return.compiled_must_pass`
3. codegen 清理:
   - `tool/build/codegen.zig` 检索不到 `std.debug.print`。
   - `emitBody(...)` 的命中是正常 lowering 调用点或定义位; `errdefer` 的命中停在 allocator、owned-name、arraylist 等资源清理路径, 不属于排障期临时诊断。
4. 工作树范围:
   - `git status --short` 仍列出文档链路、标准库实现、编译器实现、回归用例和未跟踪目录/文件的并行变更。
   - `2.5.6` 保持未勾选, 不把工作树范围收敛伪装成已完成。

## 4. 阻塞记录

1. 无 `P0/P1` 阻塞。

2. `P2` 文档冲突: `RUN_WASM=1` gate 描述。

   证据:
   - `README.md:75` 写 `RUN_WASM=1` 会额外执行 wasm run、compiled wasm 执行、compiled trap 和可用时的 component/embed/validate gate。
   - `tool/build/test/run_tests.sh:380-720` 显示 component-plan/core-imports/core-shims/component-input/component-core gate 位于默认 `compile_ok` 分支。
   - `tool/build/test/run_tests.sh:837,911-1012,1033` 显示 `RUN_WASM=1` 分支只新增 compiled wasm 执行、`compiled_trap` 和 `run_wasm_smoke.sh`。

   影响:
   - README 把默认 component gate 和 `RUN_WASM=1` 增量 gate 写在同一句, 容易误导回归范围判断。
   - 不影响当前 checklist 收紧, 因为冲突已显式记录。

   选项:
   - a. 修改 `README.md:75`, 把 component/embed/validate gate 从 `RUN_WASM=1` 增量描述里移出, 改成默认 `compile_ok` gate。
   - b. 修改 `tool/build/test/run_tests.sh`, 让 component/embed/validate gate 真正只在 `RUN_WASM=1` 下执行。

   推荐:
   - 选 a。脚本当前默认 gate 覆盖更强, 只需要修正文档描述。

3. `P2` 文档冲突: `defer` 示例页状态。

   证据:
   - `README.md:70` 把 `defer` 基础语法和前端校验列为已完成。
   - `README.md:78` 把 `defer` 完整控制流与 ARC 列为暂跳过。
   - `doc/spec_rules.md:41` 把 `defer` 记为已落地 statement 关键字。
   - `doc/spec_examples.md:682-683` 先给出 `## defer` cleanup 示例, 又写“v1 没有可用 `defer` 语句”。
   - 回归锚点是 `tool/build/test/ok/127_defer_syntax_static.do`、`129_imported_defer_nil.do`、`tool/build/test/compile_ok/121_defer_call_and_arc_block_lower.do`。

   影响:
   - `doc/spec_examples.md:683` 与 README、`doc/spec_rules.md:41` 和回归现状冲突。
   - `doc/spec_examples.md` 的 `defer` 小节不能作为当前正例链路引用。

   选项:
   - a. 修改 `doc/spec_examples.md:683`, 改成现行状态: 基础语法和前端校验可用, 完整控制流与 ARC 仍暂跳过。
   - b. 保留该段为历史反例, 明确标注“旧 v1 草案反例”, 并从当前正例链路移走。
   - c. 回退 README / spec_rules / 测试, 重新声明 `defer` 不可用。

   推荐:
   - 选 a。README、`doc/spec_rules.md` 和回归已经证明基础 `defer` 可用, 应同步示例页状态; 完整控制流与 ARC 继续按 `README.md:78` 暂跳过。

4. 边界: 不在本文件内修改语法设计文件、README 或实现文件; 上述两项只作为后续清理的明确问题记录。

## 5. 收口条件

1. `2.5.6` 只有在 `git status --short` 不再包含非本任务并行变更时才能勾选。
2. `README.md:75` 按 `RUN_WASM=1 gate 描述` 的推荐方案修正后, 删除或更新对应冲突记录。
3. `doc/spec_examples.md:683` 按 `defer 示例页状态` 的推荐方案修正后, 删除或更新对应冲突记录。
4. 任何语法、语义、测试或 README 变更完成后, 重新运行 `./tool/build/test/run_tests.sh`, 并用新的现场结果替换 `2.5.5` 与 `3.4.1` 的回归记录。
