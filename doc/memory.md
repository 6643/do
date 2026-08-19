# do v1 内存模型

**状态**: Wasm GC 是 Do 唯一选定的 managed-memory 后端。当前已准入同步路径的
G5b ARC/GC 等价性矩阵为 23 行全绿；另有一个资源 `Result` 取消终态通过
GC/线性 Component backend-neutral oracle。编译器仍含 ARC 实现代码和未准入路径,
因此全局 runtime migration 尚未完成。

**目标**: 在不向用户暴露指针或引用的前提下, 为 Wasm lowering、`[T]`、`text`、
结构体、host ABI、Future/Stream 和 Component/WIT 资源提供统一边界。

**关系**: `doc/spec.md` 是规范入口, `doc/spec_rules.md` 定义源码语义, 本文定义
运行时表示和编译器实现边界。GC-first 决策见
`doc/design/2026-08-11-gc-first-memory-decision.md`。

## 1. 源码契约

1. 源码只有值语义, 不暴露 pointer、reference、`ref<T>`、`own<T>` 或
   `borrow<T>`。
2. 用户不写 retain、release、free、GC root 或 allocator 操作。
3. 赋值、传参、返回、字段读取和集合读取保持值语义。内部表示不改变可观察结果。
4. 已发布值不可变。`@set`、`@put`、字段更新和标准库更新返回新的逻辑值。
5. 编译器只能在证明对象唯一且未逃逸时复用内部 storage。该优化不能改变旧值
   可观察、错误、取消或资源释放行为。
6. GC 只管理 Do 分配。WIT resource 的 owned transfer、direct-call borrow 和
   drop 是 compiler/ABI 合约, 不由 GC finalizer 隐式完成。

## 2. 值表示

### 2.1 Inline 值

以下值可作为 Core Wasm 标量或小型 inline aggregate 传递:

1. `bool`、整数、浮点和 `usize`。
2. `nil`。
3. enum/error 分支值和值枚举分支值。
4. 不含 managed 字段且静态大小不超过 `64B` 的结构体。
5. 命名函数值和无捕获 lambda 的静态函数符号。

### 2.2 GC-managed 值

`text`、`[T]`、大结构体和包含 managed 字段的结构体使用 runtime-private
Wasm GC references 表示。变量、参数和返回传递的是内部 reference, 不复制
payload。

这些 reference 不可被源码观察、比较、算术运算、转成整数或直接传给 host。
内部 null/sentinel 只用于 lowering, 不构成源码 zero value。

### 2.3 GC 生命周期

GC 根据可达性回收 Do object。编译器负责在局部、frame、table 和 continuation
中保持必要 root, 但不为普通赋值、调用、分支或作用域退出生成 source-value
`inc/dec`。

GC 回收没有确定的源码可见时刻。因此 host resource、文件、socket、stream endpoint
和任何需要确定性关闭的外部能力都必须通过显式 close/drop 或 Component ABI terminal
cleanup 处理。

## 3. `[T]` 和 copy-on-write

`[T]` 是有运行时长度的连续值序列, 源码不暴露 backing pointer。

```do
xs [u8] = .{1, 2, 3}
n usize = @len(xs)
v u8 = @get(xs, 0)
ys [u8] = @set(xs, 1, 9)
zs [u8] = @put(xs, 4)
```

规则如下:

1. `@get(xs, i)` 和 `@set(xs, i, value)` 要求 `i < @len(xs)`。越界是 safety
   failure/trap。
2. `@set` 和 `@put` 产生新逻辑值, 不能修改仍可观察的旧值。
3. 只读传参、赋值和返回不复制 list payload。
4. 写路径可以在唯一、未逃逸且容量/布局允许时复用内部 object; 否则分配并复制。
5. 含 managed child 的 list clone 或重建由 GC tracing 负责 child reachability;
   compiler 不生成 child retain/release。
6. 当前并不承诺 public mutable list、builder 或 reserve API。循环追加的大数据
   场景应先通过专门的 builder/preallocation 设计解决, 不能改变值语义。

## 4. `text` 和结构体

`text` 是有效 UTF-8 值, 不等同于任意 `[u8]`。字符串字面量产生 `text`; 非法
UTF-8 原始数据必须使用 `[u8]`。文本拼接、切片和替换返回新逻辑值。

GC backend 使用 runtime-private UTF-8 byte sequence 表示 `text`, 使用 typed
struct/array 表示 managed struct 和 list。具体 Wasm GC type、字段布局、array
element type 和 nullability 是 codegen 细节, 不属于源码 ABI。

```do
User {
    id u64
    name text
}
```

含 managed 字段或超过 inline 阈值的 struct 是 GC-managed value。私有字段只影响
源码可见性、构造权限和不变量, 不改变 GC 的可达性规则。

当前 GC 同步切片另外准入直接局部对象的一层嵌套 managed-struct 路径:
`@get(outer, .inner, .leaf)` 读取子结构标量叶子, `@set(outer, .inner, .leaf, value)`
重建子结构和外层结构并保留旧值。动态路径、超过一层的路径、producer expression、
async、resource 和 host/WIT 形状仍不在此准入范围。

```do
File {
    .id i64
}
```

`File` 离开作用域不会自动 close host resource。定义模块必须提供显式 close/drop
操作, 并按 API 契约处理其错误。

## 5. 函数、Future 和 Stream

1. 命名函数值和无捕获 lambda 不需要 GC allocation。
2. 后续若支持捕获闭包, 闭包环境是 GC-managed object, 并需要独立的 capture 和
   cycle semantics 设计。
3. `Future<T>`、`Stream<T>` 的 source contract 不变。其 frame、waitable、buffer
   和 continuation storage 必须在 GC backend 中保持可达, 并在 terminal cleanup
   时解除 Component/WIT resource ownership。当前已有 bounded
   `Future<nil>` sequential-await 与 private resource `Result` terminal slices:
   `--p3-wait-for-component` 和 `--p3-async-component` 分别使用 GC-traced
   frame/table；资源 drop 仍由 Component boundary 负责。资源取消 slice 另以
   同一 Rust/Wasmtime host 比较 GC Component 与 hand-authored linear Component
   的终态观测。上述证据不等同于普通 GC sync async admission, 也不覆盖
   `Stream<T>`、通用 async-call 或一般 resource shapes。
4. 取消只清理 guest/Component state, 不回滚已发出的 host side effect。

## 6. Linear Memory 和 Component Boundary

Wasm linear memory 是 runtime implementation detail。源码不暴露地址。

1. `@load_*([u8], offset)` 是 checked `[u8]` value operation, 不是裸 pointer
   load。
2. `@store_*`、可见 shared memory、公开 atomic pointer API 都不属于 v1。
3. `text`、`[u8]`、list 和 struct 进入 host 时由 compiler 或 std wrapper 做
   explicit ABI marshaling。
4. Wasm GC references 不跨 Component/WIT boundary。canonical ABI values 在边界
   copied 或 marshaled。
5. resource handle 不等同于 GC reference。其 `own`、`borrow`、drop 和 async
   liveness 由内部 `OwnershipPlan` / `AsyncPlan` 处理。

## 7. Public Non-goals

1. 不引入 general pointer、reference、`ref<T>`、`own<T>`、`borrow<T>` 或
   lifetime syntax。
2. 不用 GC finalizer 替代 resource close/drop。
3. 不承诺任意 WIT nested borrow 在 list、record、future 或 stream 中可用; 每个
   shape 必须经过 pinned Component capability gate。
4. 不把 Wasm GC typed references 暴露为 Do source values。
5. 不把 COW optimization 解释为公开 mutability 或 reference semantics。

## 8. Implementation Migration

GC-first 是目标规范。以下 ARC implementation debt 仍需单独的 compiler/runtime
migration, 完成前不得宣称 default `do build` 已使用 full GC:

1. `src/build/runtime_arc_wat.zig` 和 `src/build/runtime_prelude_wat.zig`。
2. `src/build/codegen_ownership.zig` 及 ARC scope-exit release plans。
3. storage layout、alias、overwrite、return 和 loop 的 ARC-specific WAT tests。
4. GC-managed list/text/struct lowering, GC frame roots, Component boundary
   marshaling, and the full regression matrix.

历史 ARC object layout、allocator、`rc == 1` reuse 和 `inc/dec` 规则不再是
v1 规范。它们保留在源码、changelog 和 dated plans 中作为迁移证据。

## 9. Required Verification

GC migration implementation must prove at least:

1. Read-only passing of large managed values does not copy payload.
2. Shared value update preserves the old logical value.
3. Unique local update may reuse storage only without observable mutation.
4. GC roots keep managed values alive across branches, loops, `Future` and
   `Stream` suspension.
5. GC collection never substitutes for WIT resource drop or cancellation
   terminal cleanup.
6. Component ABI lift/lower never leaks a GC reference across the boundary.
7. Full compiler regression, Component assembly and host execution pass on the
   selected toolchain.
