# do v1 内存模型

**状态**: v1 实现规格草案
**目标**: 在不向用户暴露指针/引用的前提下, 为 Wasm lowering、`[T]`、`text`、结构体、ARC、host ABI 和未来 store/atomic 设计提供统一边界。
**关系**: `doc/spec.md` 是规范入口; `doc/spec_rules.md` 定义源码语义; 本文定义运行时表示和编译器实现边界; `doc/arc.md` 保留长期 ARC/Perceus/并发优化设想; `doc/arc_*.ts` 只是文档侧分析/验证原型, 不作为 v1 权威实现规格。

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
5. `[T]` 的 `len/cap` 放在 `Object.data` 起点。
6. 固定布局 managed struct 不需要 `len/cap`, payload 字节布局完全由 layout table 决定。
7. header 压缩到 `u16/u16`、尾部 reference count、状态化 header 都是 v2 优化。

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

---

## 9. Linear Memory 与 host ABI

### 9.1 Linear Memory

Wasm linear memory 是 runtime 实现细节。源码不暴露地址。

1. `@load_*([u8], offset)` 是从 `[u8]` backing storage 中读取定宽 little-endian 值, 不是裸指针 load。
2. codegen 可以把它 lower 到 wasm load 指令, 但前提是 compiler 已经把 `[u8]` handle 解成 backing pointer 并执行边界检查。
3. v1 不提供 `@store_*` core primitive。`mem_write_*` 继续返回新的 `[u8]` 值。
4. v1 不把 `mem.do`/`atomic.do` 降成真实 shared-memory store/atomic 指令。

### 9.2 Host ABI

1. `@env` v1 只承载标量 ABI 和字符串字面量 `ptr,len` lowering。
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

---

## 12. 实施顺序

以下 `doc/arc_*.ts` 只是文档侧分析/验证原型: 用来验证 slot class、allocator、release worklist 和 COW 行为。当前权威边界仍以本文、`doc/memory_layout_structs.md`、`doc/roadmap_status.md` 和编译器回归为准。

1. 已有文档侧 allocator 原型: `doc/arc_allocator.ts`。
2. 已有文档侧 Object/LayoutTable/ARC release 原型: `doc/arc_object_runtime.ts`。
3. 已有文档侧 COW 值语义原型: `doc/arc_cow_runtime.ts`。
4. 已有 compiler WAT runtime prelude: 输出 1KB 对齐的 `__do_heap_base` 和可变 `__do_heap_cursor`。
5. 已有最小 WAT runtime primitives:
   - `__do_memory_grow_to(end)`。
   - `__do_arc_alloc(payload_bytes, type_id)` allocator v1: 先按 `object_bytes < 1024` 分流到 `__do_arc_alloc_small` / `__do_arc_alloc_large`。
   - `__do_arc_alloc_small` 已写入 SmallBlock header、bitmap 和 Object, 并通过 slot class 外置状态扫描/复用同规格 SmallBlock 的空 slot; 如果链上没有空 slot, 再新建 1KB SmallBlock 并挂到对应 slot class 链。
   - slot class 状态已有通用内存表, `slot_units` 映射到该规格 SmallBlock 链表头; `$__do_slot_class_4` 只是当前 WAT 回归保留的 4 号规格镜像。
   - `__do_arc_alloc_large` 已写入 LargeBlock `cap = 1`、`span_len` 和 Object header; 分配时优先复用 free span, 命中更大 span 时会 split tail, 否则按 `span_len * 1024` 推进 heap cursor。
   - `__do_arc_release(object)` release worklist v1: 当前通过 layout helper 扫 managed child offset, child `dec` 到 0 时进入固定容量 worklist, drain 时再逐个释放。
   - layout helper 保留 `[u8]` 的 `type_id = 1` 且 managed child count 为 0; 同时已能从源码结构声明生成含 managed 字段或嵌套 managed struct 字段的 struct layout 分支, 输出 `type_id`、payload size 和 managed field offset。
   - `__do_arc_release(object)` 回收当前 object 时能在 small object 场景反推 SmallBlock/slot 后清 bitmap; 当 SmallBlock bitmap 为空时, 会从 slot class 链摘除并转成 1KB FreeBlock; large span 释放后会进入 free span list 并做相邻 span merge。
   - `__do_arc_inc(object)` / `__do_arc_dec(object)` refcount v1; `dec` 到 0 时先 push release worklist, 再 drain worklist。
   - `__do_arc_payload(object)` / `__do_arc_rc(object)` / `__do_arc_type_id(object)` header accessor。
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
13. 已有 `[u8]` 参数调用的最小 ownership lowering: call site 对直接 managed local 实参执行 `inc`, callee 把 `[u8]` 参数登记为 storage local 并在清理路径中 `dec`。
14. 已有 `[u8]` 和 managed struct 覆盖赋值的最小 release lowering: 字符串 overwrite 先释放旧 storage; `@set/@put` overwrite 和 managed struct handle overwrite 先把 RHS 写入 scratch local, 再按新旧 handle 是否相同决定是否释放旧值。
15. 继续接入分支合流、循环回边平衡、通用 `[T]` allocation/release lowering。
16. 按 handle 模型重写通用 `[T]` 的 `@len/@get/@set/@put` lowering。
17. 接入 `text` runtime 表示和 `[u8]` 边界函数。
18. 插入 ARC 生命周期操作并做基础相消优化。
19. 补通用 `@set/@put` 的写路径释放平衡; 当前只覆盖 `[u8]` 跨变量写入的临时 `inc/dec` 和 `[u8]` 覆盖赋值条件释放。
20. 最后再评估 `@store_*`、真实 atomic 和 host/WASI 复杂 ABI。

文档侧验证入口:

```bash
bun doc/arc.ts
bun doc/arc_allocator.test.ts
bun doc/arc_object_runtime.test.ts
bun doc/arc_cow_runtime.test.ts
tsc --noEmit --target ES2020 --module commonjs doc/arc.ts doc/arc_allocator.ts doc/arc_allocator.test.ts doc/arc_object_runtime.ts doc/arc_object_runtime.test.ts doc/arc_cow_runtime.ts doc/arc_cow_runtime.test.ts
```

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
