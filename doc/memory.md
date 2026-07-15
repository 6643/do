# do v1 内存模型

**状态**: v1 实现规格草案
**目标**: 在不向用户暴露指针/引用的前提下, 为 Wasm lowering、`[T]`、`text`、结构体、ARC、host ABI 和未来 store/atomic 设计提供统一边界。
**关系**: `doc/spec.md` 是规范入口; `doc/spec_rules.md` 定义源码语义; 本文定义运行时表示和编译器实现边界 (v1 权威规格)。

---

## 1. 设计原则

1. 源码层只有值语义, 不暴露 pointer/reference/borrow。
2. 受管内存由编译器和 runtime 管理, 用户代码不写 `retain/release/free`。
3. `@get/@set/@put`、标准库集合写入和结构字段写入都保持值语义; 原地修改只能是 `RC == 1` 时的实现优化。
4. 第一版只面向单线程 Wasm core module; shared memory、真实 atomic 指令、component resource lifetime 是后续阶段。
5. runtime failure 和源码可见错误分离: 越界、非法 layout、double free 这类是 safety failure/trap, 不通过 `Error` 或普通错误枚举返回。

---

## 2. 源码值分类

### 2.1 Inline 值

以下值默认 inline 存放, 不进入 ARC object:

1. `bool`、整数、浮点、`usize`。
2. `nil`。
3. error enum 分支值和值枚举分支值。
4. host resource 的标量句柄字段, 例如 `File { .id i64 }` 中的 `.id`。
5. 没有受管字段且静态大小不超过 `64B` 的结构体。
6. 命名函数值和无捕获 lambda 的函数值。当前没有闭包环境, 因此函数值只是静态函数符号/索引, 不进入 ARC object。

### 2.2 Managed 值

以下值通过 managed handle 表示:

1. `[T]` 连续存储。
2. `text` UTF-8 文本。
3. 含 managed 字段的结构体。
4. 没有 managed 字段但静态大小大于 `64B` 的结构体。
5. 后续若引入带捕获闭包, 闭包环境必须作为 managed 对象单独设计; v1 不支持。

### 2.3 分类不改变源码语义

Inline 和 managed 只是实现分类。源码里赋值、传参、返回、字段写入和集合写入都按值语义理解。

```do
xs2 [u8] = @set(xs, 0, 65)
```

语义上 `xs2` 是一个新值。实现上如果 `xs` 的 backing object 唯一, 编译器可以复用并原地写入; 如果共享, 必须 clone 后写入。

---

## 3. Managed Handle 与对象头

### 3.1 Handle

Managed 值在源码变量中表现为一个不透明 handle。handle 不可被源码观察、比较、加减或传给 host。

v1 在 Wasm32 中可用 `u32` 表示 handle。handle 指向 `Object` 起点, 也就是对象头起点。源码不能观察 handle 数值, codegen/runtime 只把它当成内部 managed object 地址。

内部 handle `0` 保留为未初始化 sentinel。Wasm local 默认是 0, 因此编译器可以把条件分支内声明的 managed local 提前声明到函数级 WAT local 表; 如果分支未进入, 清理阶段对 0 执行 `inc/dec` 必须 no-op。这个 0 sentinel 不构成源码层 zero value, 也不能被用户观察。

### 3.2 对象头

v1 默认对象头只保存 ARC 和 layout 所需的公共字段:

| 字段 | 类型 | 含义 |
| --- | --- | --- |
| `rc` | `u32` | 引用计数 |
| `type_id` | `u32` | 布局表索引 |

说明:

1. 先使用 `u32` RC, 不引入 side table 溢出机制。
2. `type_id` 指向编译器生成的 layout table。
3. 公共对象头不保存 `len/cap`。`text`、`[T]` 和 managed struct 的 payload 解释由 `type_id -> layout table` 决定。
4. `text` 的 byte length 放在 `Object.data` 起点。
5. `[T]` 的 `len/cap` 放在 `Object.data` 起点: `len: u32` @0, `cap: u32` @4, 元素数据从 offset 8 起 (共 8 字节 payload header)。
6. 固定布局 managed struct 不需要 `len/cap`, payload 字节布局完全由 layout table 决定。
7. header 压缩到 `u16/u16`、尾部 reference count、状态化 header 都是 v2 优化。
8. 编译器侧与上述 layout 对齐的纯 WAT 访问在 `src/build/wat_storage.zig` (`STORAGE_PAYLOAD_HEADER_BYTES = 8`, `type_id` `[u8]`-style=`1` / managed-storage=`65535`); 类型/元素宽度分类在 `src/build/type_name.zig`; 业务 `@set/@put`/COW 编排仍在 `src/build/codegen_api.zig` / `src/build/codegen_pipeline.zig` / `src/build/codegen_storage_layout.zig`。

### 3.3 Layout Table

每个 `type_id` 至少需要记录:

1. payload 大小和对齐。
2. managed 字段偏移列表。
3. object data kind: `text_data`、`list_data` 或 `struct_data`。
4. `[T]` 元素大小。
5. `[T]` 元素是否含 managed 子值。
6. drop/trace 函数入口或等价布局描述。

释放时 runtime 通过 `type_id` 找到 layout, 对 managed 字段或 managed 元素执行 `dec`。结构字段的 managed child 列表既包含 `text`、`[T]` 这类直接 managed payload 字段，也包含字段类型自身是 managed struct 的字段；后者按字段 handle 做一次 `dec`，由被引用结构体自己的 layout 继续释放内部 managed 字段。

---

## 4. `[T]` 连续存储

### 4.1 语义

`[T]` 表示任意多个连续的 `T` 值, 携带运行时长度。源码层不暴露 backing pointer。

```do
xs [u8] = .{1, 2, 3}
n usize = @len(xs)
v u8 = @get(xs, 0)
ys [u8] = @set(xs, 1, 9)
zs [u8] = @put(xs, 4)
```

### 4.2 操作规则

1. `@len(xs)` 读取 list payload 起点的 `len`。
2. `@get(xs, i)` 要求 `i < len`; 越界是 safety failure/trap。
3. `@set(xs, i, value)` 要求 `i < len`; 返回更新后的 `[T]` 值。
4. `@put(xs, value, rest...)` 返回追加后的 `[T]` 值。
5. `loop value, index = xs` 编译为 `0..@len(xs)` 范围内的 `@get(xs, index)`, 语言生成的 index 不越界。
6. 元素地址 lowering: `payload + 8 + i * elem_bytes` (见 `src/build/wat_storage.zig` 的 `emitStorageElementPtrFromLocal`); scheme-A `[Tuple<...>]` pack 见 `src/build/type_name.zig` 的 `tupleScalarLeafStorageByteWidth` / `tupleHasManagedPackLeaf` 与 `src/build/wat_payload.zig`。每个元素是定宽 **树状** 布局 (直接子槽子区域); 嵌套 Tuple / 未来 struct 槽保持嵌套语义, **永不** 在类型或 API 上拍平为扁平 Tuple。managed 叶槽为 4 字节 handle; 含 managed 叶槽的 storage 使用 `is_storage_pack` layout 做 clone/free 叶子 inc/dec。

### 4.3 COW

写入 `[T]` 时:

1. 若 backing object `rc == 1` 且容量足够, 可以原地修改。
2. 若 `rc > 1`, 必须 clone 后修改。
3. 若容量不足, 分配新 backing object。
4. 如果元素 `T` 含 managed 子值, clone、set、put、free 都必须正确执行元素级 `inc/dec`。

写入结果仍然是值语义:

```text
set(xs, index, value):
  if rc(xs) == 1:
      mutate xs backing in place
      return xs
  else:
      next = clone(xs)
      dec(xs)
      mutate next
      return next

put(xs, value):
  if rc(xs) == 1 and len(xs) < cap(xs):
      append in place
      return xs
  else:
      next = clone/grow(xs)
      dec(xs)
      append next
      return next
```

`rc > 1` 的 clone 不能破坏旧值; 旧值仍可继续读取。唯一值扩容时可以释放旧 backing, 因为没有其他活引用。

---

## 5. `text`

### 5.1 语义

`text` 是有效 UTF-8 文本值。源码层 `text` 不等同于任意 `[u8]`。

1. 字符串字面量默认产生 `text`。
2. 普通字符串的 `\xNN` 先解码为字节, 再校验整体 UTF-8。
3. 非法 UTF-8 原始字节必须用 `[u8]` 表达。
4. `text` 没有 `@get/@set/@put` core 操作。

### 5.2 表示

v1 使用 managed UTF-8 byte storage 表示 `text`:

1. `Object.data` 起点保存 `len u32`, 表示 UTF-8 字节数。
2. `len` 后面紧跟 UTF-8 bytes。
3. `text` 视为不可变值; 文本拼接、切片、替换返回新 `text` 或新 `[u8]`。

### 5.3 与 `[u8]` 边界

1. `bytes_of(s text) -> [u8]` 返回 UTF-8 字节值。实现可共享不可变 backing, 但一旦 `[u8]` 写入必须 COW。
2. `text_from(bytes [u8]) -> text | Utf8Error` 必须校验 UTF-8。
3. host ABI 若需要 `ptr,len`, 由 compiler/std 在边界进行 marshaling, 不把指针暴露给源码。

---

## 6. 结构体

### 6.1 Inline Struct

无 managed 字段且静态大小不超过 `64B` 的结构体 inline copy。

```do
Point {
    x f32
    y f32
}
```

### 6.2 Managed Struct

以下结构体使用 managed object:

1. 含 managed 字段。
2. 静态大小大于 `64B`。

```do
User {
    id u64
    name text
}
```

释放 `User` 时 layout table 指示 runtime 对 `name` 执行 `dec`。

### 6.3 私有字段

私有字段只影响源码可见性、构造权限和不变量维护, 不改变内存布局规则。

```do
File {
    .id i64
}
```

外部模块不能构造或改写 `.id`; runtime 不因为 `File` 离开作用域自动 close host resource。资源 cleanup 仍由显式 `close_file(file)` 处理。

---

## 7. 函数值与闭包

1. 命名函数值是静态函数符号/索引, 不进入 ARC object。
2. 无捕获 lambda 可降成静态函数符号/索引, 不进入 ARC object。
3. v1 不支持捕获局部变量的闭包环境。
4. 若未来支持闭包捕获, 闭包环境必须是 managed object, 并且需要单独处理捕获变量生命周期和环引用问题。

### 7.1 Swift ARC 对照

Do v1 借鉴 Swift ARC 的自动生命周期管理和 COW 思路, 但不引入 Swift 的 class/reference type、weak/unowned 或捕获闭包生命周期模型。当前 lambda 不捕获局部变量, 因此不会形成闭包环境对象, 也不会产生闭包强引用环。

---

## 8. ARC 插桩规则

ARC 插桩在 compiler IR 阶段完成。源码不出现这些操作。

### 8.1 赋值

```do
a = b
```

1. 若 `b` 是 managed 且赋值后仍会被使用, 先 `inc(b)`。
2. 若 `a` 原值是 managed, 覆盖前 `dec(a_old)`。
3. 自赋值和别名路径必须先保护右值, 再释放左值。

### 8.2 调用

1. 实参调用后不再使用: 视为 move, 调用前不插 `inc`。
2. 实参调用后仍使用: 调用前 `inc`。
3. callee 对入参按自身局部生命周期 `dec`。
4. 返回值所有权转移给调用方, callee 不对返回对象额外 `dec`。

### 8.3 控制流

1. 分支合流在边上做 ARC 平衡。
2. 循环回边必须保证每轮 managed 变量净计数平衡。
3. `return`、`break`、`continue` 和未来 `defer` 都必须经过清理块。

### 8.4 释放

1. `dec` 到 0 后进入 release worklist。
2. release worklist 迭代处理, 禁止递归释放深结构。
3. 释放对象时根据 layout table 对 managed 字段和 managed 元素逐项 `dec`。
4. 释放完成后把 object allocation 归还给 allocator; small object slot 可以复用, 空 small block 可以转回 free span。
5. double free、unknown handle、layout 缺失属于 runtime safety failure。

### 8.5 字段读取 move 的唯一拥有 / alias 证明

字段读取 move 指从 managed struct 读取 managed 字段时, 不对字段 handle 执行 `inc`, 而是把该字段 handle 转移给读取结果, 并立即把源结构体对应字段写回 0 sentinel。这样源结构体后续释放时不会再 `dec` 已转移的字段。

这个优化不能只依赖语法末次使用。下面的情况即使 `user` 在语法上最后一次出现, 也不能证明字段可 move:

```do
take_name(user User) -> text {
    return @get(user, .name)
}
```

`user` 是参数, caller 侧可能仍持有同一个 managed object 的值语义副本; callee 不能把参数字段清空后返回。这个场景必须保守 `inc` 字段。

可行路径对比:

1. 仅按语法末次使用放开字段读取 move: 禁止。它会误伤参数、借用源、helper/shared-source、loop-carried source 和同语句多次读取。
2. 只放开本地 fresh-owner 证明: v1 采用。只在可证明源结构体由当前函数体内新建 struct literal 唯一拥有、没有别名、读取后不再使用时 move。
3. 完整 ownership graph / data-flow: 后续再做。它可以覆盖跨 block、跨函数和更复杂循环, 但必须先有独立 IR 或数据流模型。

v1 字段读取 move 的证明条件:

1. 源必须是当前函数体内的 direct managed struct local, 且由同一函数体内的 struct literal 初始化。
2. 源不能是参数、导入函数返回值、普通 helper 返回值、union payload、借用/共享来源、field meta helper 产生的间接源, 或 loop-carried source。
3. 从源声明结束到字段读取开始, 源标识符不能再次出现; 这包括 alias 绑定、传参、字段读取、字段写入和任何普通表达式使用。
4. 字段读取表达式之后, 当前语句剩余部分和当前 body 剩余部分都不能再使用源。
5. 活跃作用域内不能有已注册 `defer`; `defer` cleanup 会改变离开路径, v1 不在该场景证明字段转移。
6. 读取字段必须是 managed 字段; inline 字段不需要 ARC move。
7. 字段读取 move 只能发生在受控上下文中: return / guard return、受控 binding / assignment, 或能证明读取后马上离开源生命周期的 field reflection 展开分支。
8. 循环内默认不能 move loop-carried source。只有字段读取所在路径确定 `return` / guard `return` / `break` 后不再进入下一轮, 才能考虑放开。
9. 同一语句内从同一源读取多个 managed 字段暂不放开; 必须等 ownership IR 能表达逐字段 zeroing 和多结果转移后再做。

实现效果必须满足:

1. move 路径: load 字段 handle, 不 `inc`, 立即把源字段写 0 sentinel, 结果值接管该 handle。
2. copy 路径: load 字段 handle 后执行 `inc`, 源字段保持不变。
3. 源结构体离开作用域时, layout release 只能 `dec` 仍留在源结构体中的 managed 字段。
4. 读取结果进入普通 return / binding / assignment ownership 流程, 由现有 cleanup 或 return ownership 负责释放或转移。

03.6 已补齐的回归:

1. 允许: fresh local struct literal 的 direct `@get(user, .field)` return move。
2. 允许: fresh local struct literal 的 `@field_get(user, field)` return move。
3. 拒绝: 参数字段读取 move, 继续保守 `inc`。
4. 拒绝: active `defer` 作用域内字段读取 move。
5. 拒绝: 字段读取后源仍被使用。
6. 拒绝: 非退出路径的 loop-carried source 字段读取 move。
7. 拒绝: helper/shared-source 字段读取 move。
8. 拒绝: 同一语句内从同一源读取多个 managed 字段 move。

对应证据: compile_ok `202` 到 `215` 覆盖字段读取 move 的允许/拒绝 lowering 边界, compiled_ok `39` 到 `42` 覆盖 fresh local direct `@get`、field reflection `@field_get`、binding 和 assignment 的执行路径。

### 8.6 loop-carried source 与 loop 内 call 参数 move

当前 loop 内 call 参数 move 采用全局保守门: `emitBody(...)` 只在 `loop_ctx == null` 时设置 `allow_call_arg_last_use_move = true`。普通 loop、collection loop、recv loop 和 field reflection loop 都会构造 `LoopControl`, 因此 loop body 内普通 call 参数默认不能触发 direct managed last-use move。

当前证据:

1. 普通 loop: `emitLoopBlock(...)` 为 body 构造 `LoopControl`, body 可回到同一 `loop` 标签; 即使某个 source 在当前语句后没有语法使用, 下一轮仍可能继续需要它。
2. collection loop: `emitCollectionLoopBlock(...)` 为 value / index 建立每轮 body, managed value 从 storage 元素 load 后立即 `inc`, value binding 是每轮借用出来的本地句柄, source storage 仍属于循环源。
3. recv loop: `emitRecvLoopBlock(...)` 和 collection loop 同形, value / count 每轮重建, managed value 也在 load 后 `inc`。
4. field reflection loop: 每个字段分支有独立 `LoopControl` 和 scoped cleanup; 已允许的字段读取 move 只在 return / guard return 等离开路径内成立。
5. 现有回归 `166`、`167`、compiled `24` 锁住普通 loop 内 call 参数继续 `inc`; `214` 锁住非退出 loop-carried 字段读取不 move。
6. `216` 到 `218` 锁住 collection loop source、collection loop managed value binding 和 recv loop managed value binding 作为 call 参数时继续 `inc`, 不出现 `arc-call-move`。

设计结论:

1. 03.7 阶段不直接放开 loop body 内 call 参数 move。
2. collection / recv 的 value binding 视为 borrowed per-iteration source, 不能作为可 move source。
3. collection / recv 的 source storage 是 loop-carried source, 不能在 body 内按语法末次使用 move。
4. 只有 path 确定离开循环且不会进入下一轮时, 才能考虑局部放开, 例如当前路径确定 `return` 或确定 `break` 到目标 loop 外层。
5. `continue` 路径永远不是 move 放开路径, 因为它直接进入下一轮。
6. 有 active `defer`、source 来自参数/import/helper/shared-source、source 在同语句后续或 body 后续仍可达使用时, 继续保守 `inc`。

后续最小分析需要同时证明:

1. source origin: local fresh-owned source, 且不是参数、helper/shared-source、collection/recv value、hidden loop source 或外层 loop-carried source。
2. path exit: move 表达式之后当前控制路径必须确定 `return` 或 `break` 离开承载该 source 的循环; 不能 fallthrough 或 `continue`。
3. use-after: move 后当前语句剩余部分、当前 block 剩余可达语句和相关 cleanup 都不能再使用 source。
4. cleanup: active `defer` 和 loop control release chain 不会访问已 move source。
5. field granularity: 同一语句多字段 move 仍等 ownership IR 后再做。

03.7.2 回归已补充, 不改 codegen:

1. collection loop 内用外层 storage / managed struct 做 call 参数, 继续 `inc`, 不出现 `arc-call-move`。
2. collection loop 的 managed value binding 做 call 参数, 继续 `inc`, 不出现 `arc-call-move`。
3. recv loop 的 managed value binding 做 call 参数, 继续 `inc`, 不出现 `arc-call-move`。
4. 验证命令: `SKIP_BUILD=1 ./src/build/test/run_tests.sh`, 结果 `pass=658 fail=0 skip=70`。

03.7.3 设计已收敛到最小 LoopMoveAnalysis 输入/输出:

1. 普通 loop 中 `break` / `return` 路径是否允许 move, 先以设计用例记录, 不在没有 path analysis 前放开。
2. 输入必须显式包含 source origin、path exit、use-after 和 cleanup 四类证明材料。
3. 输出只能是局部 allow / reject 和拒绝原因, 不能静默扩大到 collection / recv value、helper/shared-source 或 active defer source。

### 8.7 LoopMoveAnalysis 最小输入/输出

`LoopMoveAnalysis` 是 03.7.4 之前的设计边界, 不是完整 ownership IR。它只回答一个问题: 在 loop body 内某个 managed 值候选点, 是否可以把现有保守 `inc` 改成 move。默认结果必须是 reject。

调用位置:

1. 只在 `loop_ctx != null` 且候选点原本会因为 `allow_call_arg_last_use_move = false` 保守 `inc` 时考虑。
2. 候选点先限定为 direct managed call argument。字段读取 move、collection / recv value binding、union payload、多字段 move 和 variadic spread 不纳入最小子集。
3. 分析发生在 emit 前, 输出只影响当前候选点是否生成 `arc-call-move` 与 zero local, 不能改变 release plan 或 cleanup 顺序。

最小输入:

1. candidate: `source_name`、`actual_name`、source type、表达式 token range、当前语句 token range。
2. loop frame: 当前 `LoopControl`、父级 loop chain、目标 `break_label` / `continue_label`、当前 loop body range。
3. function body frame: `body_start`、`body_end`、当前语句之后的可达 token range。
4. source origin: 显式分类为 `fresh_local`、`param_or_import`、`helper_shared`、`collection_value`、`recv_value`、`loop_source`、`union_payload`、`compiler_temp` 或 `unknown`。
5. path exit: 候选点之后当前路径的出口分类, 只能是 `return`, `guard_return`, `break_current_or_outer`, `continue`, `fallthrough`, `nested_unknown`。
6. use-after: 当前语句剩余部分、当前 block 剩余可达语句、目标 break 外层后续语句是否再次使用 source。
7. cleanup: 当前 `defer_ctx` 是否已有已注册 defer, loop control release chain 是否会释放或读取 source, source 是否在 active cleanup 可见。

source origin 规则:

1. 只有 `fresh_local` 可以进入 allow 判断。`fresh_local` 必须来自当前函数体内直接构造或已证明唯一拥有的本地 managed 值。
2. `param_or_import`、`helper_shared`、`collection_value`、`recv_value`、`loop_source`、`union_payload`、`compiler_temp` 和 `unknown` 一律 reject。
3. 现有 `LocalSet` 还没有完整 origin enum, 只靠 `source_name`、`appendBorrowedLocal(...)` 和 token 形态不足以证明唯一拥有。03.7.4 若要实现, 先补显式 origin 元数据, 不能只按名字或语法末次使用放开。

path exit 规则:

1. `return` / `guard_return` 可以作为离开函数路径, 但仍必须通过 source origin、use-after 和 cleanup 证明。
2. `break_current_or_outer` 只有在目标 break 离开承载该 source 的 loop, 且 break 目标之后没有 source 可达使用时才可以进入 allow 判断。
3. `continue` 永远 reject, 因为它直接进入下一轮。
4. `fallthrough` 永远 reject, 因为当前 loop 可能继续下一轮。
5. `nested_unknown` 永远 reject, 包括嵌套 if / loop 无法证明所有路径都离开承载 loop 的情况。

use-after 规则:

1. 候选表达式结束到当前语句结束之间不能再使用 source。
2. 当前语句结束到当前 block 结束之间的可达路径不能再使用 source。
3. 如果出口是 break, break 目标之后到 source 生命周期结束之间不能再使用 source。
4. 同一语句多个候选点引用同一 actual local 时一律 reject, 等完整 ownership IR 表达逐点 move 后再放开。

cleanup 规则:

1. 只要 active `defer_ctx` 中已有已注册 defer, 一律 reject。
2. loop control release chain 会释放的 local 不能在同一路径提前 move, 除非 release plan 能显式 skip 并证明 cleanup 不访问 source。
3. 03.7.4 不修改 release plan, 因此 cleanup 证明不完整时必须 reject。

最小输出:

```text
LoopMoveDecision {
    action = allow | reject
    reason = fresh_exit_return | fresh_exit_break | origin_not_unique | path_not_exit | use_after | cleanup_visible | unsupported_candidate
    source_name
    actual_name
}
```

allow 的全部必要条件:

1. candidate 是 direct managed call argument。
2. source origin 是 `fresh_local`。
3. path exit 是 `return` / `guard_return`, 或可证明离开承载 source loop 的 `break_current_or_outer`。
4. use-after 三段扫描都无 source 使用。
5. cleanup 不可见, 或已有 release plan 能显式 skip source。03.7.4 尚未修改 release plan, 因此当前只能接受 cleanup 不可见。

03.7.4 的落地判断:

1. 若不补显式 origin 元数据和 break 目标后 use-after 扫描, 不应放开任何 loop 内 move。
2. 若只补 return / guard return 路径, 可以先用 fresh local + no active defer + no use-after 的最小子集试点。
3. 若 break 路径需要跨 loop frame / block 后续扫描, 证据不足时应延后到完整 ownership IR。

### 8.8 03.7.4 loop 内 return / break move 结论

03.7.4 结论: 当前不落地 loop 内 return / break 退出路径的局部 move, 继续保持 loop body 内 call 参数保守 `inc`。后续在 03.8 决定 ownership facts / IR 路径。

不落地的证据:

1. `Local` 只有 `name`、`source_name`、`ty`、`emit_decl` 和 `release_on_scope_exit`, `StructLocal` / `StorageLocal` / `UnionLocal` 也只有 `source_name` 形态信息, 没有 8.7 要求的显式 source origin enum。
2. `appendBorrowedLocal(...)` 和 `appendOwnedLocal(...)` 只影响 local 登记方式, 不能区分 `fresh_local`、`param_or_import`、`helper_shared`、`collection_value`、`recv_value`、`loop_source` 和 `compiler_temp`。
3. loop header 中 collection / recv value binding 通过 `appendBorrowedLocal(...)` 登记, emit 阶段又在每轮 load 后 `inc`; 这些 value 仍应视为 borrowed per-iteration source。
4. `directManagedCallLastUseMoveSource(...)` 只检查 `allow_last_use_move`、active defer 和 token range use-after, 不检查 source origin。
5. `emitBody(...)` 当前用 `loop_ctx == null` 作为 loop 内 call 参数 move 的全局门。去掉这个门之前, 必须有替代分析覆盖 source origin、path exit、use-after 和 cleanup。
6. `emitLoopControlJump(...)` 对 break / continue 会执行 defer cleanup、block locals release 和 loop control release chain, 当前没有针对已 move source 的 skip/证明机制。
7. `buildLoopControlExitPlan(...)` 的 loop control release plan 对 frames 内 locals 使用空 skip list, 不能表达某条 break 路径已经 move 掉某个 source。
8. 现有 `bodyCanReachEnd(...)`、`loopBodyCanBreakCurrentLoop(...)` 和 `breakTargetsCurrentLoop(...)` 只能帮助判断可达性或 break 目标, 不能证明 break 目标之后到 source 生命周期结束之间无 use-after。

return-only 子集也暂不落地:

1. return / guard return 作为 path exit 足够强, 但 source origin 仍缺显式证明。
2. 现有 token 扫描能排除部分同 block 后续使用, 但不能把参数、import/helper 返回值、loop source 和 compiler temp 与 fresh local 稳定区分。
3. 在没有 source origin enum 前放开 return-only move, 会把 8.7 的 `origin_not_unique` 风险变成实现缺陷。

03.8 决策输入:

1. 先决定是否增加 ownership/source-origin 元数据, 或直接进入完整 ownership IR / graph / data-flow。
2. 若选增量路径, 第一小步必须是给 `Local` / managed source 增加明确 origin 分类, 并补只读回归证明不会改变现有 lowering。
3. 若选完整 IR 路径, 第一小步必须是定义 ownership node、edge、exit path、cleanup 和 loop-carried source 的 IR 边界。
4. 在 path/cleanup facts 完成前, 不新增 loop 内 `arc-call-move`。

### 8.9 03.8 ownership IR / source-origin 决策

03.8 结论: 现在不一次性引入完整 ownership IR / graph / data-flow pass。先走增量 `OwnershipFacts` / source-origin metadata 路径, 但把数据形态设计成未来可迁移到完整 IR。完整 IR 作为触发条件保留, 不作为当前下一步。

推荐路径 A: 增量 source-origin metadata。

1. 先给 managed source 建立显式 `SourceOrigin`, 最小覆盖 `fresh_local`、`param_or_import`、`helper_shared`、`collection_value`、`recv_value`、`loop_source`、`union_payload`、`compiler_temp` 和 `unknown`。
2. 第一阶段只读采集和传递 origin, 不改变 lowering, 不新增 loop 内 `arc-call-move`。
3. origin 默认必须是 `unknown` / reject, 不能靠名字、token 位置或 `appendBorrowedLocal(...)` 推断唯一拥有。
4. 只在 origin 采集稳定后, 再判断是否给 return-only loop 路径增加更小的 allow 子集。

路径 A 的依据:

1. 当前主要硬缺口是 `Local` / `StructLocal` / `StorageLocal` / `UnionLocal` 没有显式 origin, 这是 03.7.4 不落地 loop move 的第一个阻断点。
2. `directManagedCallLastUseMoveSource(...)` 已经有局部候选点和 use-after 扫描入口, 但缺 origin 事实; 先补 facts 比重写 emit pipeline 风险低。
3. `emitBody(...)` 仍保留 `loop_ctx == null` 的全局门, source-origin 第一阶段不触碰该门, 所以可用现有回归锁住行为不漂移。
4. 该路径符合当前扁平 codegen 结构, 变更小, 易回滚, 也能为后续 IR 提供真实字段和迁移经验。

路径 A 的限制:

1. 它不能单独解决 `break` 目标后的 use-after 扫描。
2. 它不能单独解决 loop control release chain 的 skip 证明。
3. 它不能表达同一语句多个候选点的逐点 move 顺序。
4. 所以后续如果要放开 loop move, 还必须补 path/cleanup facts。

路径 B: 现在直接引入完整 ownership IR / graph / data-flow pass。

1. 需要定义 ownership node、edge、alias、move、copy、release、cleanup 和 exit path。
2. 需要构建函数内 CFG, 覆盖 `return`、guard return、fallthrough、block exit、break、continue、defer cleanup、collection loop 和 recv loop。
3. 需要让 `ownership.zig` 的 release plan 从 graph/data-flow 结果生成或校验。
4. 需要迁移现有 token-range last-use、field get move、union payload move 和 release skip 逻辑。

路径 B 暂不作为当前下一步的原因:

1. 当前目标只是继续收窄 ARC move 边界, 不是重写 lowering 架构。
2. 完整 IR 会同时触碰 local 收集、emit、release plan、defer、loop 和测试期望, 单步风险过大。
3. 现有回归已经覆盖大量保守子集, 直接迁移会扩大验证面, 不符合每次推进一个小任务的协议。
4. 在缺 source-origin 事实的情况下直接建 graph, 容易把 origin 问题藏到 edge 推断里, 反而更难审查。

完整 IR 的启动触发条件:

1. source-origin metadata 已落地, 但 path/cleanup facts 仍无法表达某个必要优化。
2. loop `break` / `continue`、`defer` cleanup 和 release plan skip 需要统一证明, 局部 helper 已经开始互相复制逻辑。
3. FBIP `reuse` 或 COW 需要跨 block / loop / call 的唯一性证明, 增量 facts 无法稳定回答。
4. 现有 token-range use-after 扫描出现不可维护的 false allow 或 false reject。

03.8 后续小任务:

1. 03.8.1 增加只读 `SourceOrigin` 元数据, 默认 `unknown`, 不改变 lowering。
2. 03.8.2 盘点并标注现有 move candidate 的 origin 来源, 继续保持旧输出。
3. 03.8.3 设计 path/cleanup facts 与 release plan skip 的最小接口, 再决定是否允许 return-only loop move。
4. 03.8.4 若 03.8.3 仍无法表达, 先收口完整 ownership IR 的启动边界与阻断条件, 暂不落实现。

### 8.10 03.8.1 SourceOrigin 只读元数据落地

03.8.1 结论: `src/build/codegen_api.zig` / `src/build/codegen_pipeline.zig` / `src/build/gen_types.zig` 已增加只读 `SourceOrigin` 元数据, 默认 `unknown`, 当前不改变任何 lowering 或 move 判定。

当前已落地的 origin 标注:

1. 函数参数的 managed local / storage / managed struct 入口标为 `param_or_import`。
2. collection loop 的 value binding 标为 `collection_value`。
3. recv loop 的 value binding 标为 `recv_value`。
4. 隐式 `__loop_source_*` storage local 标为 `loop_source`。
5. 明确的 compiler temp, 包括 `__loop_index_*`、`__loop_count_*`、union payload helper 和显式 `__*` 临时 local, 标为 `compiler_temp` 或 `union_payload`。
6. 其他现有 local 先保持 `unknown`, 不做超出证据的推断。

本轮故意不做的事:

1. 不把 `appendOwnedLocal(...)` 一律当成 `fresh_local` 事实来源。像 loop index、field helper 和编译器内部名字都可能走 owned 路径, 不能直接等同唯一拥有。
2. 不修改 `directManagedCallLastUseMoveSource(...)`、`fieldGetLastUseMoveSource(...)`、`emitBody(...)` 或任何 move allow 条件。
3. 不修改 `ownership.zig` 的 release plan 结构。

### 8.11 03.8.2 move candidate origin 盘点

03.8.2 结论: 当前 move candidate helper 已统一携带显式 `SourceOrigin`, 但只做盘点和传递, 不改变任何 lowering 或 `arc-call-move` 生成条件。

已盘点的 candidate family:

1. `directManagedLastUseMoveSource(...)` 使用 `Local` 的 origin。
2. `directManagedCallLastUseMoveSource(...)` 使用 `Local` 的 origin。
3. `directManagedUnionBindingCallMoveSource(...)` 使用 `Local` 的 origin。
4. `fieldGetLastUseMoveSource(...)` 使用 `StructLocal` 的 origin。

当前仍保持不变的部分:

1. `directManagedLocalExprName(...)` / `findLocalOrigin(...)` 的证明边界不变。
2. `fieldGetLastUseMoveSource(...)` 仍只在现有 `allow_field_read_move` 条件下工作。
3. `emitBody(...)`、`emitGetCall(...)`、`emitFieldGetCall(...)` 的 lowering 输出保持原样。

验证证据:

1. 新增 `src/build/codegen_api.zig` / `src/build/codegen_pipeline.zig` / `src/build/gen_types.zig` 内部 Zig 单测, 覆盖 `unknown` 默认值、`param_or_import`、`loop_source` 和 `compiler_temp` 标注。
2. `cd src && zig test build/codegen_api.zig` 结果为 `All 1 tests passed.`。
3. `SKIP_BUILD=1 ./src/build/test/run_tests.sh` 必须继续保持现有摘要不变, 证明 lowering 未漂移。

### 8.12 03.8.3 path/cleanup facts 最小接口

03.8.3 结论: `src/build/ownership.zig` 已显式引入 `PathCleanupFacts`, 并把 release-plan skip 从 ad hoc `skip_names` 收敛到统一的 path facts 接口; `src/build/codegen_api.zig` / `src/build/codegen_pipeline.zig` / `src/build/gen_types.zig` 已切到新接口, 但当前仍只传默认 facts, 不改变 lowering, 也不放开 loop 内 `arc-call-move`。

本轮已落地的最小接口:

1. `PathCleanupFacts { cleanup_visible, release_skip_names }` 作为局部 exit plan 的统一输入。
2. `buildReturnExitPlanWithFacts(...)`、`buildGuardReturnExitPlanWithFacts(...)`、`buildFallthroughExitPlanWithFacts(...)`、`buildBlockExitPlanWithFacts(...)` 作为 facts 版 builder。
3. `LoopFrame` 增加 `path_facts`, 允许每层 loop-control frame 独立携带 release skip 信息。
4. `buildLoopControlExitPlan(...)` 已读取 `frame.path_facts.release_skip_names` 参与 release step 生成。

当前故意保持不变的边界:

1. `emitBody(...)` 仍然使用 `loop_ctx == null` 作为 loop 内 call 参数 move 的全局门。
2. `collectLoopControlFrames(...)` 当前传入的是空 `path_facts`, 所以 loop break / continue 的 release 输出不变。
3. return / guard return 的 skip 语义只是换成 facts 承载, 现有 `move_names` 行为不变。
4. 还没有把 `cleanup_visible` 和真实 defer cleanup 可见性接到新的 move allow 判定里。

验证证据:

1. `cd src && zig test build/ownership.zig` 结果 `All 2 tests passed.`。
2. `cd src && zig test build/codegen_api.zig` 结果 `All 13 tests passed.`。
3. `SKIP_BUILD=1 ./src/build/test/run_tests.sh` 必须继续保持绿色, 证明 lowering 未漂移。

### 8.13 03.8.4 完整 ownership IR 启动边界

03.8.4 结论: 当前不启动完整 ownership IR / graph / data-flow 实现, 只把启动条件和阻断条件写清楚。现阶段仍留在 `PathCleanupFacts` 这一层。

当前仍然阻断 return-only loop move 的点:

1. `cleanup_visible` 还没有接入 move allow 判定。
2. `emitBody(...)` 仍然依赖 `loop_ctx == null` 作为 loop 内 call 参数 move 的全局门。
3. `break` / `continue` 目标之后到 source 生命周期结束之间, 仍没有稳定的 use-after 扫描。
4. 同一语句多候选点的逐点 move 顺序仍无法表达。

因此完整 ownership IR 只在以下条件满足时才启动:

1. path/cleanup facts 无法继续扩展承载所需证明。
2. loop cleanup / defer cleanup / release skip 的证明逻辑开始在局部 helper 中重复蔓延。
3. 需要跨 block / loop / call 的统一唯一性证明。
4. 现有 token-range use-after 扫描出现不可维护的 false allow 或 false reject。

本轮故意不做的事:

1. 不新增 ownership node / edge / alias / move / copy / release graph。
2. 不修改 `emitBody(...)` 的 loop 内 call 参数 move 门。
3. 不放开任何新的 `arc-call-move`。

### 8.14 D1.2 ownership facts 数据结构

D1.2 结论: 已新增内部 `ownership_facts` 数据结构, 只记录 move / copy / release-skip 决策所需事实。D1.2 完成时暂未接入 `codegen_api.zig`; D1.3 已把普通 call 参数 last-use move 判断接入 facts helper, 仍不改变当前保守 lowering。

当前数据结构:

1. `src/build/ownership_facts.zig` 定义 `SourceOrigin`, 镜像当前 codegen-local origin 分类, 为后续迁移 `Local` / `StructLocal` / `StorageLocal` / `UnionLocal` 的 origin 字段做准备。
2. `MoveCandidateKind` 覆盖 direct、call arg、union-binding call arg、field get、field set、return value 和 dead alias 这几类当前分散判断。
3. `MoveContext` 统一承载 body / statement / arg / args token range、`PathCleanupFacts`、defer 可见性、loop 上下文和 allow gate。
4. `MoveUseWindows` 显式承载 fresh source gap、after expr、after arg、after stmt 和 body rest, 避免 D1.3 继续把 use-after window 隐式散落在各 helper。
5. `MoveDecision` 显式区分 accept / reject, reject 使用 `MoveRejectReason`; accept 携带 zero source、zero field 和 release-skip action。

当前 D1.2 完成时故意保持不变的边界:

1. `src/build/codegen_api.zig` / `src/build/codegen_pipeline.zig` / `src/build/gen_types.zig` 仍使用原有 `directManagedLastUseMoveSource(...)`、`directManagedCallLastUseMoveSource(...)`、`directManagedUnionBindingCallMoveSource(...)` 和 `fieldGetLastUseMoveSource(...)`。
2. `emitBody(...)` 仍使用 `loop_ctx == null` 作为 loop 内 call 参数 move 的全局门。
3. 不放开新的 move 场景, 不改变任何 WAT pattern。

验证证据:

1. RED: `cd src && zig test build/ownership_facts.zig` 失败于 `use of undeclared identifier 'MoveCandidate'`。
2. GREEN: `cd src && zig test build/ownership_facts.zig` 结果为 `All 4 tests passed.`。
3. 聚合验证: `cd src && zig test main.zig` 结果为 `All 56 tests passed.`。

### 8.15 D1.3 call 参数 move 判断迁移到 facts

D1.3 结论: 普通用户函数 call 参数 last-use move 的 allow/defer/use-after 判断已从 `directManagedCallLastUseMoveSource(...)` 迁移到 `ownership_facts.decideCallArgMove(...)`。迁移只改变内部判断入口, 不改变 WAT lowering。

当前实现:

1. `src/build/ownership_facts.zig` 新增 `decideCallArgMove(...)`, 对 `.call_arg` candidate 统一判断 disabled、defer visible、after-arg use、after-stmt use 和 body-rest use。
2. `src/build/codegen_api.zig` / `src/build/codegen_pipeline.zig` / `src/build/gen_types.zig` 新增 `ownership_facts` import 和 `factsSourceOrigin(...)` 显式映射, 暂不整体搬迁 codegen-local `SourceOrigin`。
3. `directManagedCallLastUseMoveSource(...)` 仍负责 direct managed local 识别、source/origin 查找和旧返回结构构造; move 是否接受改由 `MoveCandidate` + `decideCallArgMove(...)` 决定。

当前故意保持不变的边界:

1. `emitBody(...)` 仍使用 `loop_ctx == null` 作为 loop 内 call 参数 move 的全局门。
2. union-binding call、field-get、field-set、return move 和 dead alias 仍未迁移到 facts helper。
3. 不放开新的 `arc-call-move`, 不改变 source 清零和 `arc_inc` emit 位置。

验证证据:

1. RED: `cd src && zig test build/ownership_facts.zig` 失败于 `use of undeclared identifier 'decideCallArgMove'`。
2. GREEN: `cd src && zig test build/ownership_facts.zig` 结果为 `All 5 tests passed.`。
3. Focused codegen: `cd src && zig test build/codegen_api.zig` 结果为 `All 30 tests passed.`。
4. ARC WAT pattern: `161_arc_storage_bare_call_last_use_move_lower` 仍包含 `arc-call-move data`; `162_arc_storage_param_call_live_source_inc_lower` 仍不包含 `arc-call-move data`。
5. Full regression: `SKIP_BUILD=1 ./src/build/test/run_tests.sh` 结果为 `pass=784 fail=0 skip=35`。

---

## 9. Linear Memory 与 host ABI

### 9.1 Linear Memory

Wasm linear memory 是 runtime 实现细节。源码不暴露地址。

1. `@load_*([u8], offset)` 是从 `[u8]` backing storage 中读取定宽 little-endian 值, 不是裸指针 load。
2. codegen 可以把它 lower 到 wasm load 指令, 但前提是 compiler 已经把 `[u8]` handle 解成 backing pointer 并执行边界检查。
3. v1 不提供 `@store_*` core primitive。`mem_write_*` 继续返回新的 `[u8]` 值。
4. v1 不把 `mem.do`/`atomic.do` 降成真实 shared-memory store/atomic 指令。

### 9.2 Host ABI

1. `@host("env", member, sig)` v1 只承载标量 ABI 和字符串字面量 `ptr,len` lowering。
2. `text`、`[u8]`、`List<T>`、结构体传给 host 时必须通过显式 ABI lowering 或标准库 wrapper marshaling。
3. host resource 用不透明标量句柄封装在 private 字段中, 不暴露 pointer。
4. WASI component/P3 的 `list/string/record/resource/result/variant` lowering 属于后续阶段; 公开标准库 API 不泄漏 raw WIT resource/result/variant。

---

## 10. v1 不做的事

1. 不支持源码 pointer/reference。
2. 不支持捕获闭包。
3. 不支持循环 GC。
4. 不支持真实 shared-memory atomic lowering。
5. 不支持裸 `@store_*`。
6. 不实现 region allocator 作为语义要求。
7. 不实现 u16 header 压缩、RC side table、Const/Unique/Local/Shared 多状态 header。

---

## 11. 后续优化

这些属于 v2 或更晚阶段, 不进入 v1 正确性闭环:

1. Perceus/FBIP 唯一性复用增强。
2. escape analysis, 将非逃逸对象下沉到栈或 region。
3. header 压缩与小对象 slab。
4. shared memory 与真实 atomic 指令。
5. component model 资源生命周期集成。
6. 闭包环境和捕获变量生命周期设计。

### 11.1 03.9 / D5.1 FBIP reuse 最小设计边界

03.9 结论: `FBIP reuse` 只作为实现优化讨论, 不能改变源码层值语义。当前先收口最小设计边界, 暂不落实现。

`reuse` 的目标:

1. 在 `[T]`、`text` backing 和 managed struct payload 的写路径中, 复用当前 object/backing, 减少 clone 或重新分配。
2. `reuse` 只优化 allocation / copy 成本, 不改变 ARC 对外语义, 也不改变 `@set/@put`、字段写入或集合写入的结果值。

最小允许条件:

1. 当前对象 `rc == 1`。
2. 写路径本来就允许原地更新, 或可在当前 object 上安全完成 overwrite / append / field replace。
3. 被写目标在源码层不可观察到中间状态。
4. 若 payload 含 managed 子值, 新旧 child 的 retain / release 顺序仍满足现有 ARC 规则。
5. 写路径必须同时有保守 COW / clone 回退分支; 没有回退分支的直接 payload 写入不能标记为 FBIP reuse。
6. 跨变量写入必须有 alias protection: 当源码 source local 和 target local 不是同一个 handle local 时, 在调用 runtime helper 或执行写分支前临时 `inc` source, 写入完成后再 `dec` source, 防止仍可见旧值被 runtime `rc == 1` 误判为唯一对象。

mutability 边界:

1. 源码层仍然只有值语义, 没有用户可见 mutable reference。
2. `reuse` 不是“对象变成可变”, 而是“编译器在唯一拥有时选择原地实现”。
3. 共享别名、borrowed source、import/param helper source、loop-carried source 不能只凭静态 origin 被当成唯一对象; 它们最多进入带 runtime `rc == 1` 检查和 COW 回退的写路径。
4. `rc == 1` 只能决定当前写 helper 的分支, 不能反向放宽 field-get move、call 参数 move、return move 或 loop 内 move。

COW 回退条件:

1. 只要 `rc > 1`, 必须回退到 clone / grow 路径。
2. 即使 `rc == 1`, 只要容量不足、layout 不支持原地替换、或 child release 次序无法稳定证明, 也必须回退。
3. 任何可能把旧值可观察行为改掉的情况, 都必须回退到现有 COW / overwrite 逻辑。
4. 若 clone 分支需要复制 managed child, clone 后必须 `inc` 被复制 child; 若原地 overwrite managed child, 必须先把 RHS 放入 scratch local, 再在新旧 child 不同的时候 `dec` 旧 child, 最后写入新 child。

`rc == 1` 的使用边界:

1. `rc == 1` 只是必要条件, 不是充分条件。
2. 不能把临时 `inc/dec` 摆动、defer cleanup 可见性、或 call 边界上的短暂唯一性当作稳定唯一拥有。
3. `rc == 1` 的判断只能用于当前写路径本地决策, 不能推出跨 block / loop / call 的长期唯一性。
4. 对 storage `@set/@put`, 当前合格复用分支是: index/range 或 len/cap 条件先通过; `rc == 1` 且 `@put` 时 `len < cap`; 然后原地写 element / append 并更新 len。否则 clone / grow 后写入。
5. 对 managed struct field update, D5 合格形态必须是 `rc == 1` 时原地替换字段, `rc > 1` 时分配新 struct object、复制其他字段并按 managed child 规则 retain/release; 当前仅有直接 payload 写入的路径不算完整 FBIP reuse 实现。

当前明确不做:

1. 不把 `reuse` 扩大成通用 mutability 模型。
2. 不把 `reuse` 用到 loop move、call 参数 move、或 return-only move 判定。
3. 不为 `reuse` 启动完整 ownership IR 实现; 若后续发现仅靠局部 `rc == 1` + 现有 ownership facts 无法稳定证明, 再回到 03.8.4 的完整 IR 启动条件。
4. 不为 D5.1 修改用户可见语法、`@set/@put` 返回值语义、函数参数 ownership contract 或 loop binding 规则。

---

## 12. 实施顺序

4. 已有 compiler WAT runtime prelude: 输出 1KB 对齐的 `__heap_base` 和可变 `__heap_cursor`。
5. 已有最小 WAT runtime primitives:
   - `__memory_grow_to(end)`。
   - `__arc_alloc(payload_bytes, type_id)` allocator v1: 先按 `object_bytes < 1024` 分流到 `__arc_alloc_small` / `__arc_alloc_large`。
   - `__arc_alloc_small` 已写入 SmallBlock header、bitmap 和 Object, 并通过 slot class 外置状态扫描/复用同规格 SmallBlock 的空 slot; 如果链上没有空 slot, 再新建 1KB SmallBlock 并挂到对应 slot class 链。
   - slot class 状态已有通用内存表, `slot_units` 映射到该规格 SmallBlock 链表头; `$__slot_class_4` 只是当前 WAT 回归保留的 4 号规格镜像。
   - `__arc_alloc_large` 已写入 LargeBlock `cap = 1`、`span_len` 和 Object header; 分配时优先复用 free span, 命中更大 span 时会 split tail, 否则按 `span_len * 1024` 推进 heap cursor。
   - `__arc_release(object)` release worklist v1: 当前通过 layout helper 扫 managed child offset, child `dec` 到 0 时进入固定容量 worklist, drain 时再逐个释放。
   - layout helper 保留 `[u8]` 的 `type_id = 1` 且 managed child count 为 0; 同时已能从源码结构声明生成含 managed 字段或嵌套 managed struct 字段的 struct layout 分支, 输出 `type_id`、payload size 和 managed field offset。
   - `__arc_release(object)` 回收当前 object 时能在 small object 场景反推 SmallBlock/slot 后清 bitmap; 当 SmallBlock bitmap 为空时, 会从 slot class 链摘除并转成 1KB FreeBlock; large span 释放后会进入 free span list 并做相邻 span merge。
   - `__arc_inc(object)` / `__arc_dec(object)` refcount v1; `dec` 到 0 时先 push release worklist, 再 drain worklist。
   - `__arc_payload(object)` / `__arc_rc(object)` / `__arc_type_id(object)` header accessor。
6. 已有 `[u8]` 字符串字面量和 alias binding 的 build 最小 lowering: 局部变量保存 managed handle, payload 为 `len u32 + cap u32 + bytes`; `alias [u8] = data` 会对 RHS 执行 `inc`; `@len/@get/@load_*` 从 payload 读取, `@get/@load_*` 已插入 bounds check。
7. 已有 `[u8]` 写路径的 COW lowering:
   - `@set` 在 `RC == 1` 时原地写入, 否则 clone 后写入。
   - `@put` 在 `RC == 1 && len < cap` 时原地追加并更新 len, 否则 clone/grow 后追加。
   - 跨变量写入前 codegen 会先 `inc` 源 object, 防止 runtime helper 把仍可见的旧变量当唯一 object 原地修改; helper 返回后再 `dec` 源 object, 平衡临时引用。
8. 下一步给 compiler IR 增加值分类: inline / managed / function symbol。
9. 已能生成 struct type layout table: 从源码结构声明生成 managed field offset 表, `[u8]` 内置 layout 仍作为 type_id 1 保留。
10. 已有含 managed 字段 struct 的最小 allocation/get/set lowering: 局部变量保存 struct object handle, payload 按 layout 读写字段, managed child 字段写入前会按 RHS 所有权执行必要 `inc`, typed alias binding 会 `inc` RHS handle, 更新时会把 RHS 单次求值到 scratch local, 再 `dec` 旧 child 并写入新 child。
11. 已有显式 `return`、guard return、最小 `if/else/else if` 块内 return 和 fallthrough 前的最小 managed local release lowering: 按局部声明逆序对非返回值的 `[u8]` 和 managed struct handle 调用 `dec`; `return x` 直接返回 managed local 时按 ownership move 处理, callee 不释放 `x`。
12. `if/else/else if` 和最小 `loop` 块内声明的 managed local 会在块正常落出时释放并写回 0 sentinel; 如果块内提前 `return`, 当前 return 清理路径已经释放该 local, 后续块末尾释放处于不可达路径。loop body 内的 `break/continue` 会先释放 loop body 递归收集到的 managed locals, 再跳转到 break/continue label。复杂循环回边平衡仍是后续项。
13. 已有独立 ownership exit plan foundation: `src/build/ownership.zig` 先构造 `return`、guard `return`、fallthrough、block exit 和 `break/continue` 的 `ExitPlan` / `ReleaseStep`，再由 `src/build/codegen_api.zig` / `src/build/codegen_pipeline.zig` / `src/build/gen_types.zig` 消费这些 steps 发出 `__arc_dec` 和必要的 0 sentinel 写回。当前这只是退出路径清理边界，不等于完整 ownership IR，也不做 escape analysis 或 region。
14. 已有死 alias `inc/dec` 相消: 对后续不再使用的 managed alias 绑定，不再生成无意义的 alias retain/release；相关 WAT 回归已锁住 live-source 场景继续保守。
15. 已有保守 last-use move 子集: direct storage / managed struct overwrite、用户函数 call 参数、binding、assignment、return call、union guard / nil expr、plain struct field read、field reflection read 和 managed struct field write，在可证明本地末次使用且当前 `defer` / loop 边界安全时跳过部分冗余 `inc` 并清空 source。参数、借用、helper/shared-source 字段读取、loop-carried source 仍保持保守。
16. 已有 `[u8]` 参数调用的最小 ownership lowering: call site 对非 move 的直接 managed local 实参执行 `inc`, callee 把 `[u8]` 参数登记为 storage local并在清理路径中 `dec`。
17. 已有 `[u8]` 和 managed struct 覆盖赋值的 release lowering: 字符串 overwrite 先释放旧 storage; `@set/@put` overwrite 和 managed struct handle overwrite 先把 RHS 写入 scratch local, 再按新旧 handle 是否相同决定是否释放旧值。
18. 已有通用 `[T]` 的 `@len/@get/@set/@put` handle lowering，以及 managed 元素 storage 的 literal/get/release/set/put 最小闭环。
19. 已有 `text` runtime 表示和 `[u8]` 边界函数的当前 v1 子集；`text` 仍不自动等同于 `[u8]`。
20. 已有字段读取 move 的唯一拥有 / alias 证明设计和实现边界: v1 只允许本地 fresh-owner 且 alias-free 的字段读取 move; 参数、借用、helper/shared-source、loop-carried source 和同语句多字段读取继续保守。后续继续扩展时, 必须先按 8.5 边界保留拒绝/允许回归。
21. 最后再评估 `@store_*`、真实 atomic 和 host/WASI 复杂 ABI。

---

## 13. 必测边界

1. 覆盖写: `a = b` 且 `a/b` 可能别名。
2. 分支合流: 两个分支返回或保存同一 managed 值。
3. 循环回边: 循环中反复更新 `[T]` 不泄漏。
4. 深链释放: 万级嵌套结构释放不栈溢出。
5. managed 字段释放: struct 包含 text/list 时正确 dec。
6. COW: 共享 `[T]` 写入不影响旧值。
7. text: 非法 UTF-8 不能进入 `text`。
8. host resource: wrapper 离开作用域不自动 close, 显式 close 错误不丢失。
