# Do Wasm Mainline Implementation Plan

> 状态: 阶段计划与实现记录。`doc/spec.md` 是语言规范入口, `doc/spec_rules.md` 是详细规则, `doc/roadmap_status.md` 记录当前 roadmap 项状态；本文件不作为当前阻塞清单或权威规则来源。

## P0: Phase 1, 规范冻结与残留清理

目标: 固化当前已定语法, 收敛命名和文档残留。

范围:
- `doc/spec.md`
- `doc/spec_rules.md`
- `doc/grammar.peg`
- `doc/spec_examples.md`
- `src/*.do`
- `tool/build/test/**/*`

验收:
- 源码和测试中的普通类型命名使用当前 Do 源码标量: `u8/u16/u32/u64/usize/i8/i16/i32/i64/isize/f32/f64/bool/text`。
- `text` 与 `[u8]` 的边界保持明确: `text` 是 UTF-8 文本, `[u8]` 是原始字节。
- `@lib(...)`, `@env(...)`, `@wasi(...)` 的语法在规范, 诊断和测试中一致。
- `./tool/build/test/run_tests.sh` 通过。

## P1: Phase 2, Host ABI 最小闭环

目标: 先打通 `@env(...)` 标量 host import, 不引入 WASI 复杂类型。

范围:
- `tool/build/parser.zig`
- `tool/build/sema.zig`
- `tool/build/codegen.zig`
- `tool/build/diag.zig`
- `tool/build/test/compile_ok/*`
- `tool/build/test/compile_err/*`

能力:
- 支持 `host_now = @env("now", () -> i64)`。
- 支持 `host_log = @env("log", (i32, i32) -> nil)`。
- 支持 `host_add = @env("add", (i32, i32) -> i32)`。
- build 阶段只允许 `i32/i64/f32/f64` 参数, 返回只允许 `i32/i64/f32/f64` 或 `nil`。
- build 阶段拒绝 host import arity mismatch。
- build 阶段拒绝把 `nil` 返回 host call 绑定到值。

验收:
- WAT 中生成正确 `(import "env" "...")`。
- `start` 中可调用 host import 并设置标量局部变量。
- 错误场景有稳定诊断。

## P1: Phase 2.5, ARC runtime 基座

目标: 把 `doc/memory.md`、`doc/memory_layout_structs.md` 和 TypeScript 文档原型里的 managed handle、allocator、layout table、ARC release 与 COW 规则接入编译器/runtime 设计。

说明: 这里提到的 TypeScript 文档原型只用于分析/验证设计, 不作为当前编译器实现的权威来源; 当前权威边界仍以 `doc/memory.md`、`doc/memory_layout_structs.md`、`doc/roadmap_status.md` 和实际回归为准。

范围:
- `doc/memory.md`
- `doc/memory_layout_structs.md`
- `tool/build/sema.zig`
- `tool/build/codegen.zig`
- 后续 runtime support 文件
- `tool/build/test/compile_ok/*`
- `tool/build/test/compile_err/*`

原则:
- 源码层不暴露 pointer/reference/retain/release/free。
- managed handle 是内部 `u32`。
- `Object` 公共头只包含 `rc u32 + type_id u32`; `len/cap` 放进具体 payload。
- 64KB wasm page 切成 64 个 1KB allocator block。
- small object 使用 bitmap small block, large object 使用连续 block span。
- `dec` 到 0 后通过显式 release worklist 释放 managed child, 不递归释放。
- COW 写入保持值语义: `rc == 1` 且容量足够时可复用, `rc > 1` 或容量不足时 clone/grow。

当前已完成:
- `doc/arc_allocator.ts`
- `doc/arc_object_runtime.ts`
- `doc/arc_cow_runtime.ts`
- `do build` 会在 WAT 中输出 ARC runtime heap prelude:
  - `;; arc-runtime block_size=1024 object_header=8`
  - `global $__do_heap_base`
  - `global $__do_heap_cursor`
  - heap base 位于静态 data 后, 并按 1KB block 对齐。
- `do build` 会输出最小内部 ARC runtime primitives:
  - `__do_memory_grow_to(end)` 按 64KB wasm page 扩容, grow 失败时 trap。
  - `__do_arc_alloc(payload_bytes, type_id)` 作为 allocator v1: 先按 `object_bytes < 1024` 分流到 `__do_arc_alloc_small` / `__do_arc_alloc_large`。
  - `__do_arc_alloc_small` 已写入 SmallBlock header、bitmap 和 Object, 并通过 slot class 外置状态扫描/复用同规格 SmallBlock 的空 slot; 如果链上没有空 slot, 再新建 1KB SmallBlock 并挂到对应 slot class 链。
  - slot class 状态已有通用内存表, `slot_units` 映射到该规格 SmallBlock 链表头; `$__do_slot_class_4` 只是当前 WAT 回归保留的 4 号规格镜像。
  - `__do_arc_alloc_large` 已写入 LargeBlock `cap = 1`、`span_len` 和 Object header; 分配时优先复用 free span, 命中更大 span 时会 split tail, 否则按 `span_len * 1024` 推进 heap cursor。
  - `__do_arc_release(object)` 作为 release worklist v1: 当前通过 layout helper 扫 managed child offset, child `dec` 到 0 时进入固定容量 worklist, drain 时再逐个释放。
  - layout helper 保留 `[u8]` 的 `type_id = 1` 且 managed child count 为 0; 同时已能从源码结构声明生成含 managed 字段的 struct layout 分支, 输出 `type_id`、payload size 和 managed field offset。
  - `__do_arc_release(object)` 回收当前 object 时能在 small object 场景反推 SmallBlock/slot 后清 bitmap; 当 SmallBlock bitmap 为空时, 会从 slot class 链摘除并转成 1KB FreeBlock; large span 释放后会进入 free span list 并做相邻 span merge。
  - `__do_arc_inc(object)` / `__do_arc_dec(object)` 作为 refcount primitives v1; `dec` 到 0 时先 push release worklist, 再 drain worklist。
  - managed handle 的内部 `0` 值作为未初始化 sentinel; `__do_arc_inc(0)` 返回 `0`, `__do_arc_dec(0)` no-op, 仅用于 codegen/runtime 安全处理未进入分支的块 local, 不作为源码可见 0 值。
  - `__do_arc_payload(object)` / `__do_arc_rc(object)` / `__do_arc_type_id(object)` 作为对象头访问 helpers。
- `do build` 中 `[u8]` 字符串字面量局部已经使用 managed handle 最小 lowering:
  - 局部变量保存 object handle, 不再拆成 `.ptr/.len` 双局部。
  - payload 布局为 `len u32 + cap u32 + bytes`。
  - `alias [u8] = data` 这类 typed binding 会对 RHS managed handle 执行 `__do_arc_inc`, 让新局部持有独立引用。
  - `@len([u8])` 从 managed payload 读取。
  - `@get([u8], index)` 和 `@load_*([u8], offset)` 从 managed payload 读取, 并调用 `__do_storage_check_range` 做 runtime bounds check。
  - `@set([u8], index, value)` 和 `@put([u8], value)` 已有 COW lowering:
    - `@set` 在 `rc == 1` 时原地写入, 否则分配新 storage 并复制旧 bytes 后写入目标 byte。
    - `@put` 在 `rc == 1 && len < cap` 时原地追加并更新 len, 否则分配新 storage 并复制旧 bytes 后追加。
    - 当写入源变量和目标变量不同名时, codegen 会先对源 object 调用 `__do_arc_inc` 并丢弃返回值, 让 helper 走 clone/grow 路径, 避免污染仍可读取的旧变量; helper 返回后再 `__do_arc_dec` 源 object, 平衡临时引用。
- `do build` 中含 managed 字段的 typed struct binding 已有最小 managed object lowering:
  - 局部变量保存 struct object handle。
  - payload 按 struct layout 写入字段。
  - 写入 managed child 字段时会先 `__do_arc_inc(child)`, 让外层 struct 持有独立引用。
  - `alias Box = box` 这类 managed struct typed binding 会对 RHS managed handle 执行 `__do_arc_inc`, 让新局部持有独立引用。
  - `@get(struct, .field)` 已能按 layout payload offset 读取 managed struct 字段; managed child 字段读取后会 `__do_arc_inc(child)`。
  - `@set(struct, .field, value)` 已能按 layout payload offset 更新 managed struct 字段; managed child 字段更新时先把 RHS 单次求值到内部 scratch local, 直接 local RHS 会 `inc`, 已返回 owned handle 的 RHS 不重复 `inc`; 随后 `dec` 旧 child, 最后写入 payload。
- `return` / guard return / fallthrough 前已有最小 managed local release lowering:
  - 显式 `return` 前按局部声明逆序对非返回值的 `[u8]` 和 managed struct handle 调用 `__do_arc_dec`。
  - `return x` 直接返回 managed local 时按 ownership move 处理; callee 不释放 `x`, 返回 handle 交给调用方持有。
  - `make(x [u8]) -> [u8]` 和 `move_box(box Box) -> Box` 这类 managed 返回签名已进入 build 函数表, WAT 中返回值降为 `i32` handle。
  - `if condition return` guard 分支会先释放当前 managed locals, 再执行 `return`。
  - 最小 `if condition { ... }` / `else` / `else if` build lowering 已接入; 块内 `return` 复用当前 managed local 清理路径。
  - `if/else/else if` 块内 local 会递归收集到函数级 WAT local 表; 未进入分支时 managed local 保持内部 0 sentinel, 后续清理 no-op。
  - 块内声明的 managed local 在块正常落出时会执行 `arc-block-release`, 释放后写回 0 sentinel, 避免外层清理重复释放。
  - 最小 `loop { ... }` build lowering 已接入; loop body 内 `return` 复用当前 managed local 清理路径, body 正常落出时执行块作用域释放后回跳。
  - loop body 内的 `break` / `continue` lowering 已接入; 跳转前释放 loop body 递归收集到的 managed locals 并写回 0 sentinel。
  - 普通 `if/else` 分支合流中覆盖外层 managed local 的场景已验证; branch local 会在块落出时 release, 外层 handle 通过 overwrite 规则保持 ownership 平衡。
  - loop 内嵌套 `if/else` 的 `break/continue` 回边清理已验证; 跳转前按 loop body 递归 local set 释放, 未进入的块 local 依赖 0 sentinel no-op。
  - 函数末尾没有显式 `return` 时, fallthrough 路径会释放当前 managed locals。
  - 该路径会触发 struct layout release worklist, 从而释放 managed child 字段。
- 多返回值 build lowering 已有最小闭环:
  - `foo() -> i32, bool { return 1, true }` 会生成 WAT multi-result 函数签名。
  - `return other_multi()` 支持同 arity、同结果类型的用户函数多返回透传。
  - `a, ok = foo()` 支持预声明标量局部的多左值接收, 按 WAT 栈顺序反向 `local.set`。
  - `[u8]` 和含 managed 字段的 struct 支持多返回 ownership move; callee 直接返回 managed local 时不释放返回值, caller 多左值接收 managed handle 时通过内部 scratch local 走 overwrite-release 规则。
  - `return data, data` 这类重复返回同一 managed local 的场景, 第一个结果按 move 处理, 后续结果会插入 `__do_arc_inc`, 让调用方持有的多个返回值都有对应引用计数。
- direct `@lib(...)` 用户函数 build lowering 已有最小闭环:
  - entry 模块中从 `start` 可达的 direct import 用户函数会按 import alias 加入当前 WAT 模块函数表; 只声明但未调用的 import 不会强行 lower。
  - 导入函数可被 `start` 直接调用, 也可经本模块普通函数间接调用; 导入函数内部继续调用本模块 import alias 时, build 会递归收集可达目标函数。
  - direct import 用户函数支持标量多返回、多左值接收和 `[u8]` managed 多返回 ownership。
  - 已加载模块中的 `[u8]` 字符串字面量会进入同一个 字符串字面量 data context, 因此 direct import 函数可分配并返回 `[u8]` storage handle。
  - 已加载模块中的 `@env(...)` host imports 会按 alias 去重后统一发射, 因此 direct import 函数可调用其模块内声明的 env host function。
  - direct import struct 类型会进入 build struct/layout 表; alias 与原类型名不一致时, 当前会同时登记 alias 与原名, 让 entry alias local 和 imported function body 都能识别 managed struct layout, 并复用同一个 `type_id`。
  - imported managed struct 返回值可绑定到 entry alias local, 并可用 `@get(value, .field)` 读取 managed 字段。
  - 当前仍未覆盖更复杂的跨模块名称冲突。
- `[u8]` 参数调用已有最小 ownership lowering:
  - `take(x [u8]) -> i32` 这类 build 函数签名会把参数降为 managed handle param。
  - callee 中 `[u8]` 参数会登记为 storage local, 因此可用于 `@len/@get/@load_*`。
  - call site 传入直接 managed local 时会先 `__do_arc_inc`, callee 在 return/fallthrough 清理路径中 `dec` 参数。
- `[u8]` managed local overwrite 已有最小 release lowering:
  - `x = "..."` 会先 `__do_arc_dec(x)` 释放旧 storage, 再分配并绑定新的字节 storage。
  - `x = @set(x, ...)` / `x = @put(x, ...)` 会先完成 RHS 写入并保存到内部 scratch local, 再比较新旧 handle; 只有返回了不同 handle 时才 `dec` 旧值, 最后写回 `x`。
  - 该路径避免 RHS 仍需读取旧 handle 时提前释放, 同时覆盖 COW clone/grow 后的旧 backing 释放。
- 标量 `[T]` local storage build lowering 已有第一段闭环:
  - `xs [i32] = .{10, 20, 30}` 这类标量聚合 literal 会降为 managed storage handle, payload 仍为 `len u32 + cap u32 + data`。
  - `@len(xs)` 读取元素个数; `@get(xs, i)` 按元素宽度计算 data offset, 并复用 storage bounds check。
  - `make() -> [i32]` 和 `first(xs [i32]) -> i32` 这类函数参数/返回签名已进入 build 函数表; 参数会登记为 storage local, 调用点按 managed handle ownership 执行 `arc_inc`。
  - `xs = @set(xs, i, value)` / `xs = @put(xs, value)` 对标量 `[T]` 已有按元素宽度的 COW 写路径; RC 为 1 时复用当前 handle, 否则 clone 当前元素数据后写入。
  - 标量 `[T]` 已覆盖普通函数单返回、多返回和 direct `@lib(...)` 导入函数返回路径。
  - 当前覆盖标量 local literal/read/write、普通函数参数/返回和 direct import 返回路径, 不代表 managed 元素 storage 已完成。
- managed 元素 storage 已有最小 literal/get/release 闭环:
  - `xs [Box] = .{box}` 会使用 managed storage type id, literal 写入直接 managed local 时执行 `arc_inc`, 让 storage 持有元素引用。
  - `@get(xs, i)` 读取 managed 元素 handle 后执行 `arc_inc`, 让调用方持有返回值。
  - storage release 在 type id 命中 managed storage 时按 `len` 遍历 data 区, 对每个元素 handle 执行 `dec_no_drain`; 元素自身的 managed 字段仍由对应对象 layout 释放。
  - `@set` 覆盖 managed 元素时会在可写 storage slot 上先 `dec` 旧元素, 再按 RHS ownership 规则写入新元素; clone 路径会对 copied element handles 逐个 `arc_inc`。
  - `@put` 追加 managed 元素时会在 clone/grow 路径 retain copied elements, 并对直接 managed local RHS 执行 `arc_inc`。
- managed struct handle overwrite 已有最小 release lowering:
  - `box = next_box` 会先对 RHS managed handle 执行 `__do_arc_inc`, 再保存到内部 scratch local。
  - 写回前比较新旧 handle; 只有 handle 不同时才 `dec` 旧 struct object, 最后把 scratch handle 写回目标局部。

未完成:
- Phase 2.5 当前没有已知的 build lowering 阻断项; 后续若把消费循环从当前 `[T]` storage-backed lowering 扩展到真实 channel/stream receive ABI, 需要按同一 ARC cleanup 规则补独立回归。

验收:
- compiler IR 能区分 inline / managed / function symbol。
- codegen/runtime 有可调用的 internal ARC primitives 或等价 lowering。
- managed object release 能按 layout table 释放 managed 字段。
- `[T]` 写入路径能表达 COW 决策。
- double free、unknown handle、layout 缺失作为 runtime safety failure/trap 处理。
- 文档侧验证通过:
  ```bash
  bun doc/arc.ts
  bun doc/arc_allocator.test.ts
  bun doc/arc_object_runtime.test.ts
  bun doc/arc_cow_runtime.test.ts
  tsc --noEmit --target ES2020 --module commonjs doc/arc.ts doc/arc_allocator.ts doc/arc_allocator.test.ts doc/arc_object_runtime.ts doc/arc_object_runtime.test.ts doc/arc_cow_runtime.ts doc/arc_cow_runtime.test.ts
  ```

## P1: Phase 3, 内存与文本 ABI

目标: 为 `[u8]` 和 `text` 跨 host 边界建立最低可执行模型。

范围:
- `tool/build/codegen.zig`
- `tool/build/sema.zig`
- `src/mem.do`
- `src/text.do`
- `tool/build/test/compile_ok/*`
- `tool/build/test/compile_err/*`

原则:
- host 边界不直接传 `text`。
- host 边界优先使用标量 `ptr,len`。
- 字符串字面量必须先落入 wasm memory, 再通过 wrapper 传递。
- 核心编译器只处理线性内存和标量, 标准库负责文本/字节封装。

当前已完成:
- `do build` 输出 `(memory (export "memory") 1)`。
- 直接 `host_log("abc")` 会把字符串字面量解码成 UTF-8 data segment, 并在调用位传入 `ptr,len`。
- `[u8]` storage local / param 可在 host import 调用位展开为 payload data pointer 和元素长度:
  ```do
  host_log = @env("log", (i32, i32) -> nil)

  log_bytes(data [u8]) {
      host_log(data)
      return
  }
  ```
- direct `@lib(...)` 导入函数内部的 host 字符串字面量 也会参与同一个 字符串字面量 data context, 因此导入 wrapper 可生成正确 data segment。
- `text` 可作为普通函数参数和返回类型进入 build lowering；`s text = "abc"`、`return "abc"`、`echo("abc")` 这类已知目标类型为 `text` 的字面量位置会生成 ARC storage handle。
- `text` 完整文本 runtime 仍留给后续文本库与 ABI 细化；当前不把 `text` 当作 `[u8]` 自动参与 `@len/@get/@set/@put/loop`。

验收:
- WAT 中有 memory/export memory。
- 字节或字符串字面量可分配到 data segment。
- wrapper 能把 `ptr,len` 传给 host import。

## P1: Phase 4, Wasm Codegen 主路径

目标: 常用 `start` 程序可生成可运行 WAT。

范围:
- `tool/build/codegen.zig`
- `tool/build/sema.zig`
- `tool/build/test/compile_ok/*`
- `tool/build/test/compile_err/*`

优先能力:
- 标量局部变量和赋值。
- 函数调用。
- `if` 和 `return`。
- 基础算术。
- struct 字段 `get/set` 的明确 lowering。
- `[T]` 最小连续存储模型。

当前已完成:
- 新增独立 smoke harness:
  ```bash
  ./tool/build/test/run_wasm_smoke.sh
  ```
- harness 会将 `.do` 编译为 WAT, 通过 `wasm-tools parse` 转 wasm, 再用 Node WebAssembly 实例化并执行 `_start`。
- `run_tests.sh` 已提供 opt-in gate:
  ```bash
  RUN_WASM=1 ./tool/build/test/run_tests.sh
  ```
- 已覆盖:
  - 无 host import 的标量 `_start`。
  - `@env("log", (i32, i32) -> nil)` 字符串字面量 `ptr,len` 调用。
  - `[u8]` wrapper 展开为 `ptr,len` 后调用 host import。
- 当前 smoke harness 是 Phase 4 执行闭环, 不替代完整 `do test` 编译执行迁移。

验收:
- `start` 程序可被 wasmtime 或等价工具执行。
- host import 能被调用。
- compile fixture 覆盖主要 lowering。

## P4: Phase 5, `do test` 编译执行迁移

目标: 从静态 test runner 逐步迁移到编译后执行测试。

范围:
- `tool/build/test_runner.zig`
- `tool/main.zig`
- `tool/build/run.zig`
- `tool/build/test/run_tests.sh`

策略:
- 短期保留静态 runner。
- 中期新增 compiled test runner。
- 长期让 `do test` 通过 wasm 执行结果判定。

当前已完成:
- 已提供 opt-in wasm 执行 smoke gate `RUN_WASM=1 ./tool/build/test/run_tests.sh`, 用于持续验证 `do build` 产物可被真实 wasm runtime 执行。
- 该 gate 当前只执行 `tool/build/test/run/*.do` 的 `_start` 程序, 不等价于 `test "name" { ... }` 声明的编译执行。
- 已新增 opt-in compiled test 输出路径:
  ```bash
  do test sample.do --compiled -o sample.wat
  ```
  每个 `test "name" { ... }` 会写入 `;; compiled-test N "name"` manifest 注释, lower 成内部 `__do_test_N` 函数并导出同名 export, `_start` 依次调用这些测试函数。测试体执行到 `return` 表示通过; 若控制流落到测试块末尾, 生成的 WAT 会执行 `unreachable` 作为失败 trap。
- `tool/build/test/compiled_ok` 固化 compiled test WAT 结构; `RUN_WASM=1 ./tool/build/test/run_tests.sh` 会对这些用例执行 WAT parse, 并通过 `run_compiled_test_case.mjs` 逐个调用 `__do_test_N` export, 输出 `test "name" ... ok` 与汇总。
- compiled runner 已覆盖普通 block 函数调用、单表达式箭头函数调用、私有函数声明调用和单返回调用结果的标量推断绑定, 例如 `keep(a bool) -> bool => a` 可在 `test` 体内作为 guard 条件执行, `.double(...)` 声明可按 `double(...)` 调用, `got = double(3)` 可推断为标量局部并写入调用结果。
- `tool/build/test/compiled_err` 固化 compiled runner 的 lowering 诊断; 当前已覆盖 test body 通过导入 wrapper 触达 `@wasi` alias 时提前报 `UnsupportedWasiHostImport`。
- `tool/build/test/compiled_trap` 固化 compiled test 失败表达; 测试体落到块末尾时, 单独执行对应 `__do_test_N` export 会触发 wasm trap, harness 会用 manifest 中的源码测试名输出失败行。
- `tool/build/test/ok/*.compiled_must_pass` 已作为迁移标记接入 `run_tests.sh`: 默认静态 runner 仍可输出 skip, 但带标记用例必须通过 `do test --compiled` 生成 WAT, 再经 `wasm-tools parse` 和 `run_compiled_test_case.mjs` 执行通过。当前已有 21 个 `ok` 用例用该路径从静态 skip 收回为 compiled pass, 覆盖集合循环、text/storage、value enum、泛型约束、defer 语法和 `src/math.do` 常量/helper 等切片。

待完成:
- 将 compiled test runner 从 opt-in 输出路径推进到默认执行路径; 当前默认 `do test` 仍保留静态 runner。
- 为失败测试增加更细的报告 ABI; 当前 compiled runner 只用 `unreachable` trap 表达失败, 已能按 `__do_test_N` 单例执行并通过 manifest 定位到源码测试名, 但还没有失败位置回传。
- 逐步把复杂控制流测试从静态解释迁移到编译后执行。

验收:
- 复杂控制流和标准库函数不再依赖静态模拟。
- 旧静态 runner 覆盖的测试继续通过。

## P3: Phase 6, WASI 0.3 / Phase 3 封装

目标: 在 Host ABI, memory 和 codegen 主路径稳定后, 直接按 WASI 0.3 / Phase 3 方向封装 WASI；不再维护 WASI Preview 2 兼容设计。

当前状态: `P3-a` 的公开 API 边界已收敛；`P3-b` 已完成一组可验证的 direct lowering 切片, 并已有 `--component-input-dir` / `do build --component-core` 到 `wasm-tools component embed/new/validate` 的最小 component 生成验证链；`P3-c` 已有 `time/random/file` 部分 wrapper、`dir.open_dir_at/close_dir/create_dir_at/remove_dir_at` wrapper 和 `io.stream` input/output stream wrapper。不能把这些切片等同于 WASI P3 封装完成；正式 `.component.wasm` 输出命令、完整 resource/result lowering、root `open_file`、dir 读取遍历与 tcp/udp/http 仍未完成。

范围:
- `src/time.do`
- `src/random.do`
- `src/file.do`
- `src/dir.do`
- `src/io.stream.do`
- `src/tcp.do`
- `src/udp.do`
- `src/http.client.do`
- 必要的 `@wasi(...)` 解析和 codegen 支持

原则:
- P3 后置, 不阻塞 P0/P1 主线。
- 不支持 Preview 2 专用接口名或桥接语义；若 0.3 draft 与旧接口不同，以 0.3 draft 为准。
- WIT 复杂类型不直接暴露给普通用户。
- 当前 `src/*.do` 不把涉及 `resource/result/variant/flags/future` 的 raw WIT 签名暴露为公开 API；已登记且已能 lower 的签名可以作为标准库模块内部 `.host_* = @wasi(...)` 私有 binding。
- 标准库公开层封装 resource/result/variant/list，只暴露 do 自己的结构、错误枚举和函数返回形态。
- 用户只看到 Do 类型, 例如 `File`, `FileError`, `Datetime`。

### P3-a: 标准库 raw WIT 泄漏清理

状态: 已完成当前边界收敛。

范围:
- 公开 API 不暴露 WIT `resource/result/variant/flags/future` 作为普通 do 类型。
- 已登记且已能 lower 的 raw `@wasi(...)` host 签名可以集中留在对应标准库模块内部, 只作为私有 host binding。
- 保留 do 层公开结构、错误枚举、多返回值和当前已能表达的包装函数。

验收:
- `src` 中涉及 raw WIT 复杂签名的内容只允许出现在标准库内部 `.host_* = @wasi(...)` binding, 例如 `src/io.stream.do` 的 `input-stream.read` 和 `output-stream.check-write/write/flush`。
- 公开标准库 API 不把 WIT `resource/result/variant/flags/future` 当成普通 do 源码类型暴露。
- `doc/spec_rules.md` 明确记录当前只保留 do 层公开类型和后续私有绑定层方向。

### P3-b: 私有 WASI binding / component lowering

状态: 进行中。已完成当前可验证边界: 合法 `@wasi(...)` 声明可进入 `do build` 的私有 binding manifest；manifest 已带 `source/alias/target/params/result` 字段，避免不同模块的同名 host alias 混淆，并让后续 binding generator 不再重新切割签名字符串。含 `wasi-bind` 的 compile WAT 已接入 `validate_wasi_bind_manifest.mjs`，用于检查 manifest 字段格式、WIT 类型尖括号平衡和 `source + alias` 唯一性；同一工具的 `--json` 模式会输出 `bindings[]`，作为后续 BindingResolve/Component lowering 的第一层机器可读输入，并为已知 scalar/record/list<u8> binding 和已登记的 `descriptor.sync/write/read/link-at/open-at/create-directory-at/remove-directory-at/drop`、`input-stream.read`、`output-stream.check-write/write/flush` result-area binding 生成 `shim.lowering` 计划；`filesystem/types/descriptor.read-directory`、`filesystem/preopens/get-directories`、`sockets/types/tcp-socket.create/bind`、`sockets/types/udp-socket.create/bind` 与 `http/client/send` 已按 WASI 0.3 签名登记为 known target，但它们涉及 `stream/future`、`list<tuple<descriptor,string>>`、WIT resource、WIT variant 或 async 资源调用，当前 `--json` 只做签名解析并标记 `shim.kind = "unsupported"`。`--component-plan` 模式只接受全部已知且可 lower 的 binding，输出去重后的 component imports 与 per-alias shims，遇到 unknown target 或 known-but-unsupported 复杂 WIT 签名都会失败；`--core-imports` 从同一严格计划生成去重后的 `cm32p2` core import WAT 片段；`--core-shims` 进一步生成 per-alias canonical ABI shim 片段，用来固定 component builder 的下一层输入。语义层已对 `doc/wit/wasi_registry.json` 当前登记的已知 WASI target 做最小签名 registry 校验；manifest 工具也会对已知 target 做同样的 `params/result` 复核。未知 target 暂时仍只做语法级 WIT 类型校验。入口模块导入标准库 wrapper 时, 被导入模块里的 `@wasi(...)` 声明也会进入 manifest。`doc/wit/wasi_p3_lowering.md` 已固定第一版 WIT -> Do 映射、resource ownership 和 component lowering 验证顺序。当前 `do build` 已能把已登记的 scalar/record/list<u8> WASI 调用 lower 成 `cm32p2` core import 和 Do-level wrapper bridge，并能按已登记形态处理 `result<_,error-code>`、`result<filesize,error-code>`、`result<tuple<list<u8>,bool>,error-code>`、`result<descriptor,error-code>`、`result<list<u8>,stream-error>`、`result<u64,stream-error>` 和 `result<_,stream-error>`；`descriptor.link-at/open-at/create-directory-at/remove-directory-at` 额外支持 Do `text` local/param 路径参数, WIT `string` 参数会降成 canonical ABI `ptr,len`, `[u8]` 不作为 WIT `string`, 结果读取仅支持显式多左值形态。未知 target 或复杂 `result/resource/stream/future/list<tuple<...>>/variant/async` 签名在实际调用链触达时仍会报 `UnsupportedWasiHostImport`。真实 component 输出和完整 resource/result/stream/future/list-of-tuple/variant/async lowering 仍未完成。

范围:
- 明确 `@wasi(...)` 如何从 WIT 签名降到 Wasm component ABI。
- 明确 WIT `resource/result/variant/flags/list/tuple/option/borrow/own` 与 do 内部表示的映射。
- 明确私有 binding 层是编译器生成, 还是标准库不可导入的私有文件。
- 明确 resource 生命周期和 ownership 规则。

当前已验收:
- `do build` 不再对合法 `@wasi(...)` 声明一律报 `UnsupportedWasiHostImport`。
- 语义层会拒绝 registry 当前已知 WASI target 的签名不匹配声明, 例如 `clocks/system-clock/now` 不能声明成 `() -> u64`, `filesystem/types/descriptor.read-directory` 也不能声明成普通 `result<_,error-code>`。
- 语义层会校验已登记 WIT record mirror 的 Do struct 字段名、顺序和字段类型；当前覆盖 `clocks/system-clock/now -> Datetime { seconds i64, nanoseconds u32 }`。
- `do build` 会把入口模块和递归导入模块中的合法 `@wasi(...)` 声明写入 core WAT 的 `;; wasi-bind source="..." alias="..." target="..." params="..." result="..."` manifest；`source + alias` 才是唯一 binding 身份。
- `doc/wit/wasi_registry.json` 已记录当前最小 WASI target / record mirror registry；`tool/build/test/validate_wasi_bind_manifest.mjs` 会在回归中读取该 registry 并验证含 `wasi-bind` 的 compile WAT, 避免 manifest 格式回退到不可机器消费的文本；`--json` 输出已经覆盖 `source/alias/target/params/result/identity/known/record/resolved/shim`。当前 shim plan v1 把 scalar params + scalar result、registered record result、registered `list<u8>` result、registered `descriptor.sync -> result<_,error-code>`、registered `descriptor.write -> result<filesize,error-code>`、registered `descriptor.read -> result<tuple<list<u8>,bool>,error-code>`、registered `descriptor.link-at -> result<_,error-code>`、registered `descriptor.open-at -> result<descriptor,error-code>`、registered `input-stream.read -> result<list<u8>,stream-error>`、registered `output-stream.check-write -> result<u64,stream-error>` 或 registered `output-stream.write/flush -> result<_,stream-error>` result-area 形态标为可 lower，复杂 WIT 签名显式标为 `unsupported`；可 lower 的条目带 `shim.lowering`，记录 component import 身份、concrete cm32p2 core import、canonical ABI core 参数/返回，以及 Do 结果布局。`--component-plan` 输出 `schema_version/imports/shims`，并在发现 unknown/unsupported binding 时失败，避免后续 component builder 接收半可执行计划。
- `cm32p2` record result 已按 `wasm-tools component embed --dummy` 校准为间接结果区: `() -> Datetime` 的 core import 参数是 `["i32"]`, 返回是 `[]`; scalar result 仍直接返回, 例如 `u64 -> i64`。
- `tool/build/test/compile_ok/08_wasi_std_import_binding_manifest.component_plan.expect` 已把真实 `do build` 产物接到 `--component-plan` 校验；该路径还会生成 `--wit` 输出, 并在 `wasm-tools` 可用时用 `wasm-tools component wit` 解析验证。`tool/build/test/compile_ok/08_wasi_std_import_binding_manifest.core_imports.expect` 进一步锁定真实标准库 wrapper 对应的 `cm32p2` core import WAT 片段；`tool/build/test/compile_ok/08_wasi_std_import_binding_manifest.core_shims.expect` 锁定 per-alias canonical ABI shim 片段。后续新增可 lower 的标准库 wrapper 时, 应补对应 component-plan/core-imports/core-shims 期望。
- `tool/build/test/validate_wasi_bind_manifest.mjs --component-input-dir <dir>` 已把同一严格计划聚合成后续 component builder 的单目录输入: `core.wat`、`core_component.wat`、`component_plan.json`、`core_imports.wat`、`core_shims.wat`、`wit/` 和 `metadata.json`。`core_component.wat` 会移除普通 `memory` 导出, 只保留 component ABI 需要的 `cm32p2_memory`, 避免 `wasm-tools component new` 因 multiple memories 拒绝。`do build --component-core -o out.wat` 也能直接输出同样 component-ready 的 core WAT, 但仍不直接写 `.component.wasm`。`tool/build/test/compile_ok/96_wasi_manifest_module_scoped_alias.component_input.expect` 和 `.component_core.expect` 固化跨 `wasi:clocks` / `wasi:random` 多 package、跨 source 同 alias 的 builder 输入形态；这些 gate 会在 `wasm-tools` 可用时解析 WIT 目录、parse core shim module, 并执行 `component embed` -> `component new` -> `validate`。这个目录本身仍不是最终 component wasm, 但已能派生并验证最小真实 component。
- `tool/build/test/compile_ok/97_unmanaged_struct_return_lower.do` 固化纯标量结构返回 ABI: 非 ARC struct 按字段 flatten 成多结果, 调用侧再按字段逆序写回结构局部。
- `tool/build/test/compile_ok/98_imported_wasi_record_wrapper_lower.do` 已覆盖 `time.do/unix_ms -> now -> host_now` 的导入链: `host_now` 使用预留 result-area scratch 调用 `cm32p2|wasi:clocks/system-clock/now`, 再按 `Datetime` 字段 load 成 Do 层 flattened struct 返回。
- `doc/wit/wasi_p3_lowering.md` 明确当前 compiler-facing lowering 边界: `@wasi` 是 WIT binding 声明；已登记 scalar/record/list<u8> 子集可以 lower 到 core WAT, 但完整 component 输出仍需要后续 component lowering。
- `tool/build/test/compile_ok/99_imported_wasi_list_u8_wrapper_lower.do` 已覆盖 `random.do/random_bytes -> host_random_bytes` 的导入链: `host_random_bytes(u64) -> list<u8>` 使用 canonical result-area `ptr,len`, 再拷贝成 Do `[u8]` ARC storage。
- `tool/build/test/compile_ok/100_wasi_result_unit_statement_lower.do` 已覆盖 `filesystem/types/[method]descriptor.sync` 的 `result<_,error-code>` statement-position 调用；`tool/build/test/compile_ok/107_wasi_result_unit_status_multi_lhs_lower.do` 已覆盖 `_, status = host_file_sync(...)` 的显式状态读取, 其中 `status == 0` 表示 ok, 非 0 表示 `error-code` 枚举索引加 1。
- `tool/build/test/compile_ok/101_wasi_result_filesize_statement_lower.do` 已覆盖 `filesystem/types/[method]descriptor.write` 的 `result<filesize,error-code>` statement-position 调用: `[u8]` buffer 在调用位降成 `ptr,len`, 返回 result-area 可按语句位忽略；同用例已接入 component-plan、WIT resource method、core-imports 和 core-shims gates。
- `tool/build/test/compile_ok/102_wasi_result_filesize_multi_lhs_lower.do` 已覆盖 `descriptor.write` 的显式多左值读取: `written u64, status i32` 分别接收 ok payload 与 `error-code + 1` 状态, `status == 0` 表示 ok；单值绑定仍由 `tool/build/test/compile_err/259_wasi_result_single_value_forbidden.do` 拒绝。
- `tool/build/test/compile_ok/109_wasi_result_read_multi_lhs_lower.do` 已覆盖 `descriptor.read` 的显式多左值读取: `data [u8], done bool, status i32` 分别接收 ok payload 的字节列表、bool 与 `error-code + 1` 状态, `status == 0` 表示 ok。
- `tool/build/test/compile_ok/111_wasi_result_link_at_multi_lhs_lower.do` 已覆盖 `descriptor.link-at` 的显式多左值读取: 两个 WIT `string` 参数支持直接字符串字面量或 Do `text` local/param, 并在调用位降成 canonical ABI `ptr,len`; `[u8]` 不作为 WIT `string`; `_, status` 接收 `error-code + 1` 状态, `status == 0` 表示 ok。同用例已接入 component-plan、WIT resource method、core-imports 和 core-shims gates。
- `tool/build/test/compile_ok/120_wasi_result_descriptor_open_at_multi_lhs_lower.do` 已覆盖 `descriptor.open-at` 的显式多左值读取: WIT `string` 路径支持直接字符串字面量或 Do `text` local/param, 并在调用位降成 canonical ABI `ptr,len`; `descriptor i32, status i32` 分别接收 ok descriptor handle 与 `error-code + 1` 状态。同用例已接入 component-plan、WIT resource method、core-imports 和 core-shims gates。
- `tool/build/test/compile_ok/115_wasi_result_stream_read_multi_lhs_lower.do` 已覆盖 `io/streams/[method]input-stream.read` 的显式多左值读取: `data [u8], status i32` 分别接收 ok payload 的字节列表与 `stream-error + 1` 状态, `status == 0` 表示 ok。同用例已接入 component-plan、WIT resource method、core-imports 和 core-shims gates。
- `tool/build/test/compile_ok/117_wasi_result_output_check_write_multi_lhs_lower.do` 已覆盖 `io/streams/[method]output-stream.check-write` 的显式多左值读取: `allowed u64, status i32` 分别接收 ok payload 与 `stream-error + 1` 状态。同用例已接入 component-plan、WIT resource method、core-imports 和 core-shims gates。
- `tool/build/test/compile_ok/118_wasi_result_output_write_flush_status_lower.do` 已覆盖 `io/streams/[method]output-stream.write` 和 `io/streams/[method]output-stream.flush` 的显式 `_, status` 读取。同用例已接入 component-plan、WIT resource method、core-imports 和 core-shims gates。
- `tool/build/test/compile_ok/112_source_text_literal_lower.do` 已覆盖 build 端 `s text = "..."` 的 ARC storage handle lowering: 字符串字面量进入 data segment, 局部值按 managed handle 分配和释放；`tool/build/test/compile_ok/114_source_text_call_return_lower.do` 进一步覆盖 `text` 参数和返回位的字面量 lowering，例如 `return "abc"` 与 `echo("xy")`。这不是完整文本 runtime。
- `src/file.do/write_file(file File, data [u8], offset usize) -> FileError | nil` 已接到 `descriptor.write` 多左值桥；`src/file.do/flush_file(file File) -> FileError | nil` 已接到 `descriptor.sync` 的 `_,status` 桥；`src/file.do/read_file(file File, offset usize, size usize) -> [u8], bool, FileError | nil` 已接到 `descriptor.read` 的 `data,done,status` 桥；`src/file.do/link_file(old_file File, old_path text, new_file File, new_path text) -> FileError | nil` 已接到 `descriptor.link-at` 的 `_,status` 桥；`src/file.do/open_file_at(dir File, path text) -> File | FileError` 已接到 `descriptor.open-at` 的 `descriptor,status` 桥；`src/file.do/close_file(file File) -> FileError | nil` 已接到 `descriptor.drop` 的 `[resource-drop]descriptor` direct core import, 成功调用后返回 `nil`。`write/flush/read/link` wrapper 用 `file_status_to_error` 把 status 转成公开 `FileError | nil`；`open_file_at` 只在 status 为 0 时构造 `File`, 失败时返回 `FileOpenFailed`；`close_file` 当前无普通错误 payload。`src/dir.do/open_dir_at(parent Dir, path text) -> Dir | DirError` 已复用 `descriptor.open-at` 并设置 `directory` open flag；`src/dir.do/close_dir(dir Dir) -> DirError | nil` 已复用 `descriptor.drop` resource-drop direct lowering；`src/dir.do/create_dir_at(parent Dir, path text) -> DirError | nil` 与 `src/dir.do/remove_dir_at(parent Dir, path text) -> DirError | nil` 已分别复用 `descriptor.create-directory-at/remove-directory-at` 的 `_,status` 桥。`src/io.stream.do/read_stream(stream InputStream, size usize) -> [u8], StreamError | nil` 已接到 `input-stream.read` 的 `data,status` 桥；`src/io.stream.do/check_write_stream(stream OutputStream) -> u64, StreamError | nil`、`write_stream(stream OutputStream, data [u8]) -> StreamError | nil` 和 `flush_stream(stream OutputStream) -> StreamError | nil` 已分别接到 `output-stream.check-write/write/flush` 桥。stream wrapper 用 `stream_status_to_error` 把 status 转成公开 `StreamError | nil`。`tool/build/test/ok/96_file_lib_resource_shape.do` 与 `tool/build/test/ok/118_wasi_p3_std_wrappers.do` 固化公开 API 形状；`tool/build/test/compile_ok/103_wasi_file_write_std_manifest.do` 固化标准库导入链中的 `src/file.do/host_file_read`、`src/file.do/host_file_sync`、`src/file.do/host_file_write` 与 `src/file.do/host_file_link_at` manifest/component-plan/core-import/core-shim。
- `tool/build/test/compile_ok/104_error_nil_union_return_lower.do`、`110_imported_file_read_wrapper_lower.do`、`116_imported_stream_read_wrapper_lower.do`、`119_imported_stream_output_wrapper_lower.do`、`136_union_nullable_struct_tag_lower.do`、`137_union_scalar_error_nil_tag_lower.do` 和 `138_union_managed_error_nil_tag_lower.do` 固化当前 build 子集的 union 返回与 union 局部编码: payload slots 后跟 `i32` runtime tag, `nil = 0`, 非 `nil` 分支按源码顺序从 1 开始。单值返回和多返回列表中的直接 union 类型使用同一 payload+tag ABI; 多返回显式值 return 与同 ABI 函数调用透传都按展开后的 ABI slots 对齐。
- `tool/build/test/compile_ok/105_imported_file_write_wrapper_lower.do` 固化 `write_sample -> file.do/write_file -> descriptor.write` 的真实导入 wrapper lowering；`tool/build/test/compile_ok/108_imported_file_flush_wrapper_lower.do` 固化 `flush_sample -> file.do/flush_file -> descriptor.sync` 的真实导入 wrapper lowering；`tool/build/test/compile_ok/110_imported_file_read_wrapper_lower.do` 固化 `read_sample -> file.do/read_file -> descriptor.read` 的真实导入 wrapper lowering；`tool/build/test/compile_ok/113_imported_file_link_wrapper_lower.do` 固化 `link_sample -> file.do/link_file -> descriptor.link-at` 的真实导入 wrapper lowering；`tool/build/test/compile_ok/116_imported_stream_read_wrapper_lower.do` 固化 `read_sample -> io.stream.do/read_stream -> input-stream.read` 的真实导入 wrapper lowering；`tool/build/test/compile_ok/119_imported_stream_output_wrapper_lower.do` 固化 `check/write/flush sample -> io.stream.do output wrapper -> output-stream.check-write/write/flush` 的真实导入 wrapper lowering；`tool/build/test/compile_ok/123_imported_dir_open_close_wrapper_lower.do` 固化 `open/close dir sample -> dir.do/open_dir_at/close_dir -> descriptor.open-at/drop` 的真实导入 wrapper lowering；`tool/build/test/compile_ok/124_imported_dir_create_remove_wrapper_lower.do` 固化 `create/remove dir sample -> dir.do/create_dir_at/remove_dir_at -> descriptor.create-directory-at/remove-directory-at` 的真实导入 wrapper lowering；`tool/build/test/compile_ok/106_unmanaged_struct_param_get_lower.do` 固化非托管结构体参数 flatten, 例如 `File{ .id i64 }` 参数降成 `$file.id i64`。
- `do build` 会拒绝未知或复杂 `@wasi` alias 的实际调用链, 避免把 WIT resource/result 错误生成为普通 core call。
- `tool/build/test/test_wasi_bind_manifest_tool.mjs` 已固定 `filesystem/types/descriptor.read-directory`、`filesystem/preopens/get-directories`、`sockets/types/tcp-socket.create/bind`、`sockets/types/udp-socket.create/bind` 和 `http/client/send` 的 known-but-unsupported 行为: `--json` 解析出 registry signature, `--component-plan` 必须拒绝, 防止 stream/future、list-of-tuple resource、sockets variant/resource 或 HTTP async resource 签名被误当成普通 lowerable binding。

待完成:
- 增加正式 `do build --component` 或等价命令, 直接写出 `.component.wasm`; 同时把临时 registry 替换为真实 WIT package resolver。
- 完整可执行 file/dir I/O 闭环仍需要 WASI host 运行验证；root `open_file/open_dir` 依赖 `preopens.get-directories` 的 list-of-tuple resource lowering, `descriptor.read-directory` 还需要 stream/future/resource lifetime lowering 后才能公开成 `read_dir` wrapper；tcp/udp 还需要 WIT variant/resource lowering 后才能把 `tcp-socket.create/bind` 和 `udp-socket.create/bind` 包装成公开 API；HTTP client 还需要 request/response resource 与 async result lowering 后才能把 `http/client.send` 包装成公开 API。

### P3-c: 标准库公开 WASI wrapper

状态: 未完成；`time/random` 和 `file` 的部分 wrapper 已有，`open_file_at` 已接入 `descriptor.open-at`，`close_file` 已接入 `descriptor.drop` resource-drop direct lowering，`dir.open_dir_at/close_dir/create_dir_at/remove_dir_at` 已接入 `descriptor.open-at/drop/create-directory-at/remove-directory-at`，`io.stream/read_stream`、`check_write_stream/write_stream/flush_stream` 已分别接入 `input-stream.read` 与 `output-stream.check-write/write/flush`，但 root `open_file`、dir 读取遍历与 tcp/udp/http 仍未完成。

范围:
- `time.now()/time.resolution()`。
- `random.random_u64()/random.random_bytes()` 当前已有 build lowering；真实 component/runtime 执行仍依赖后续 component 输出。
- `file.open_file/open_file_at/read_file/write_file/flush_file/close_file`。
- `dir.open_dir_at/close_dir/create_dir_at/remove_dir_at/read_dir`。
- `io.stream` 的 input/output stream 公开读写包装。
- `tcp/udp/http.client` 的资源型公开 API。

验收:
- `time.now()` 可通过 WASI wrapper 工作。
- `open_file_at/read_file/write_file/flush_file/close_file` 与 `open_dir_at/close_dir/create_dir_at/remove_dir_at` 可通过 WASI wrapper 工作；root `open_file` / root `open_dir` 需要先确定默认目录 / preopen 选择策略。
- stream/tcp/udp/http API 不泄漏 raw WIT 类型。
- 错误集合具体, 不使用超级 union。

## P1: Phase 7, 标准库收敛

目标: 标准库只保留当前编译器语义能支撑的 API, 并用 fixture 固化。

范围:
- `src/*.do`
- `tool/build/test/ok/*`
- `tool/build/test/err/*`
- `doc/spec_examples.md`

当前已完成:
- 已删除没有任何公开 API 的零字节 std 占位模块: `aes.do`、`csv.do`、`heap.do`、`http.do`、`io.do`、`ipv4.do`、`ipv6.do`、`log.do`、`ring.do`、`stream.do`、`websocket.do`、`xml.do`。
- 当前保留的 `src/*.do` 要么提供纯 do 基础库 API, 要么提供 Phase 6/P3 前置的 do 层公开类型形态, 不再用空文件表达未来计划。
- `tool/build/test/ok/130_static_unsupported_skip.must_pass` 已把静态 runner 可判定的 `loop { break }` 从 skip 收回为 pass；更复杂的标签循环、条件循环和导入函数执行仍保留 skip。
- `tool/build/test/compile_ok/140_imported_math_const_lower.do` 固化 build 端导入 std 标量常量的 lowering；`tool/build/test/compiled_ok/17_compiled_test_math_constants.do` 固化 `src/math.do` 整数和浮点常量在 compiled test 路径中的可执行形态；`tool/build/test/compiled_ok/18_compiled_test_math_small_int_helpers.do` 固化 `src/math.do` 小整数 bit/clamp helper 在 compiled test 路径中的可执行形态, 包括导入函数体内的本模块常量和 helper 调用。

验收:
- `list/hash_map/set/range/text/bytes/mem/atomic/math` 的 API 与当前语法一致。
- 核心/内建函数不参与重载。
- 无不可执行占位 API 混入主线测试。
- `./tool/build/test/run_tests.sh` 通过。

## 执行顺序

1. P0 Phase 1。
2. P1 Phase 2。
3. P1 Phase 2.5。
4. P1 Phase 3。
5. P1 Phase 4。
6. P1 Phase 7。
7. P4 Phase 5。
8. P3 Phase 6。

每个阶段都必须先补回归, 再改实现, 最后运行阶段验证和全量回归。
