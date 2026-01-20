# do Programming Language

`do` 是一种专为 WebAssembly (WASM) 环境设计的编程语言，旨在提供极致的性能与简洁的开发体验。

## 🌟 核心理念

- **纯值语义**: 变量传递即拷贝，消除指针复杂度。
- **Perceus 优化**: 实现 FBIP (Functional But In-Place) 优化。当对象引用计数 (RC) 为 1 时，自动转化为原地修改，性能媲美 C 语言。
- **静态泛型特化**: 采用 `Name<T>` 语法，编译时通过 Monomorphization 生成具体类型代码与唯一 `typeid`。类型定义不参与运行时计算。
- **显式数据流**: 严禁使用 `.` 运算符访问成员，强制使用 `get`/`set` 函数。这确保了编译器能 100% 确定地分析引用计数和原地修改机会。
- **大小写语义**: 基础类型小写（`i32`, `u8`, `f64`），堆分配/受管类型大写（`Text`, `List`, `Map`, `User`）。
- **元空间符号 (#)**: 所有与编译器指令、外部导入、FFI 或编译时约束相关的操作统一使用 `#` 前缀。
- **WASM 原生**: 针对 WASM 4KB 分页架构进行深度优化。小对象使用 Slab 分配，大对象使用连续页面分配。

## 🛠 开发计划 (Roadmap) 

### 第一阶段：底层引擎与 WASM 指令映射 (Zig 实现) ✅
*目标：建立编译器后端，将 WASM 的原始威力通过内建函数 (Intrinsics) 暴露给 `do`。*

1.  **内存原子操作与 FFI**
    - [x] `mem_size()` / `mem_grow(delta)`: 线性内存容量控制。
    - [x] `get_u8(ptr, offset)` / `set_u32(ptr, offset, val)`: 原始类型读写。
    - [ ] **FFI 绑定**: `fd_write = #wasi.fd_write(...) -> i32`。
    - [ ] **FFI 结构体**: `WasiIovec = #wasi.WasiIovec { .buf_ptr i32, .buf_len i32 }`。
    - [x] `mem_copy(dst, src, len)` / `mem_fill(ptr, val, len)`: 块级内存优化指令。
2.  **高性能位计算与异常**
    - [x] `ctz(i32)` / `clz(i32)`: 用于分配器中快速检索位图空闲位。
    - [x] `popcnt(i32)`: 统计位图中已分配槽位。
    - [x] `unreachable()`: 触发 WASM 陷阱。
3.  **内建数学、逻辑与位运算**
    - [x] **算术原语**: `add`, `sub`, `mul`, `div`, `rem`。
    - [x] **比较原语**: `eq`, `ne`, `gt`, `ge`, `lt`, `le`。
    - [x] **逻辑与位运算**: `and`, `or`, `not`, `xor`, `shl`, `shr`, `sar` (编译时根据类型自动分发)。
    - [x] **数学指令**: `sqrt`, `ceil`, `floor`, `trunc`。

### 第二阶段：语言特性与静态特化 (Zig 实现) 🚧 (当前进度)
*目标：定义 `do` 的语法语义，实现静态泛型和基础字面量支持。*

1.  **编译器原语 (Compiler Primitives)**
    - [x] **Struct<T>**: 静态布局定义与 Monomorphization。
    - [x] **Tuple<T...>** (新增): 匿名有序结构，支持 `t = set(Tuple<i32, bool>, [1, true])` 列表初始化与 `(a, b) = t` 解构。
    - [x] **Union Types** (新增): 核心联合类型 `A | B`。直接支持 `val | nil` 和 `val | error`，移除 `Option` / `Result` 泛型包装，实现空指针优化 (NPO)。
    - [x] **Array<T, N>**: 编译期定长内存块，支持 `set(Array<T>, [...])` 初始化。
    - [x] **编译时反射 (Comptime Reflection)**: 拒绝运行时反射 (RTTI)。在编译期遍历类型字段生成代码，保持 WASM 极小体积。
2.  **字面量与语义**
    - [ ] **文本字面量**: 支持 `"` 单行与 `\\` 多行字符串 (Zig 风格)。
    - [ ] **作用域管理**: 无需显式 `drop`，基于作用域自动插入 `dec_rc`。
    - [ ] **编译时约束 (#)**: 如 `#to_string(T) -> Text` 鸭子类型检查。

### 第三阶段：系统层自举 - System Layer (do 实现)
*目标：利用 `do` 语言实现高性能运行时。*

1.  **内存管理 (`do/lib/mem.do`)**
    - [ ] **Slab 分配器**: 处理小对象 (< 2KB)，$O(1)$ 查找空闲槽位。
    - [ ] **大对象管理**: 分配连续的 4KB 页面，确保内存布局扁平。
2.  **引用计数与 Perceus 优化 (`do/lib/rc.do`)**
    - [ ] **Drop Glue**: 编译器根据类型生成的 `dec_rc` 递归清理逻辑。
    - [ ] **FBIP 核心**: 实现原地修改算法。

### 第四阶段：核心标准库 - Standard Library (do 实现)
*目标：提供开发者可用的高层抽象，核心类型自举。*

1.  **核心类型 (Self-hosted)**:
    - **Slice<T>**: 结构体 `{ ptr, len }`，编译器提供切片语法糖支持。
    - **Text**: 包装 `Slice<u8>`，实现 UTF-8 处理逻辑。
    - **List<T>**: 动态数组 `{ ptr, len, cap }`，实现扩容策略。
    - **Map<K, V>**: 哈希表算法实现。
2.  **API 设计**:
    - **重载 (Overloading)**: 利用 `do` 语言的重载机制，为标准库类型实现 `set` / `get`，底层调用编译器原语。
3.  **数学扩展**: `math.do` 封装。
