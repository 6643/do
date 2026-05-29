# do 语言##(第二版编译器正在实现)

`do` 是一种专为 wasm 环境设计的编程语言，旨在提供极致的性能与简洁的开发体验。

## 🌟 核心理念

- **纯值语义**: 变量传递即拷贝，消除指针复杂度。
- **Perceus 优化**: 实现 FBIP 优化。当对象引用计数 (RC) 为 1 时，自动转化为原地修改。
- **隐式 RC 生命周期管理**: 编译器在 IR 阶段自动插入 `inc/dec`，并做冗余消除与末次使用优化。
- **静态泛型特化**: 类型采用 `Name<T>`，函数采用 `#` 约束前置行，并支持类型集约束与聚合别名（如 `SignedInt = i8 | i16 | i32 | i64`）。结构体泛型的无约束类型参数直接写 `T`。编译时通过 Monomorphization 生成具体代码与唯一 `typeid`。
- **函数式与重载**: 函数是一等值，支持约束泛型函数与同名重载；重载只按参数签名决议。
- **同类型不定参数**: 支持 `rest ...T` 形态的同类型可变参数调用，聚合函数可写成 `add(a, b, c)`，是否可扁平化完全由函数签名决定。
- **显式数据流**: 成员访问统一使用 `get`/`set` 函数和显式路径，控制流保持显式。这确保了编译器能确定地分析引用计数和原地修改机会。
- **大小写语义**: 基础类型小写，类型名与绑定名遵循 `doc/spec.md` 的命名规则。
- **WASM 原生**: 基于 WASM 64KB page 和 4KB 子页架构优化。小对象使用 Slab 分配，大对象使用连续页面分配。
- **大小数据分层策略**: 基础/小对象直接拷贝，大对象采用共享 + COW（初始阈值 64B）。
- **运行时资源管理**: 采用显式资源释放和 ID 关联，目标是不引入循环 GC。
- **语言规范基线**: 语法、内建判断族、核心库特型与静态约束统一见 `doc/spec.md`。
- **程序入口固定**: 可执行程序入口函数固定为 `_start() { ... }`，`main` 不是入口函数。
- **目录结构**: `tool/build` 编译器源码, `src` builtin/core 总表与标准库, `bin/do` 唯一二进制。

## 📁 目录结构

```txt
doc/            语法, 语义和运行时设计文档
bin/            zig 编译出的 do 编译器二进制
src/            do builtin/core 总表与标准库
tool/main.zig    唯一二进制 CLI 分派入口
tool/build.zig   Zig 构建入口
tool/build/      do build 逻辑实现和编译器源码
tool/run/        do run 逻辑预留目录
tool/build/test/ 当前编译器/构建产物回归测试
tool/get/        do get 逻辑预留目录
tool/push/       do push 逻辑预留目录
tool/fmt/        do fmt 逻辑预留目录
tool/lsp/        do lsp 逻辑预留目录
tool/test/       do test 逻辑预留目录
```

## 🔧 构建

```bash
cd tool
zig build -Doptimize=ReleaseSmall
# 产物: bin/do

# 编译
../bin/do build app.do -o app.wat

# 运行 do 文件中的 test 声明
../bin/do test app.do
```
## 🛠 开发计划 (Roadmap)

### 阶段一：运行时基石 (Runtime Foundation)
- [ ] **内存分配器**: 实现 `doc/rc.md` 描述的 64KB/4KB 分页架构与 Slab 分配器。
- [ ] **对象模型**: 实现统一对象头 (Header)，支持 TypeID 与 RC 管理。
- [ ] **库层边界**: `Text`, `List`, `Map` 的具体实现归入标准库/运行时边界，语言规则以 `doc/spec.md` 为准。
- [ ] **FFI**: 实现基于 WASI 的宿主互操作接口。

### 阶段二：编译器前端 (Compiler Frontend)
- [ ] **语法解析**: 实现 Parser，支持当前 `doc/spec.md` 中的 Struct, Lambda, guard `if`, `loop`, 泛型约束和聚合字面量语法。
- [ ] **语义分析**: 实现类型推导与泛型单态化 (Monomorphization)。
- [ ] **Perceus 分析**: 实现静态引用计数分析，自动插入 `inc`/`dec` 并识别原地复用点 (`reuse`)。

### 阶段三：编译器后端 (Compiler Backend)
- [ ] **WASM 代码生成**: 将 IR 编译为 WAT/WASM 二进制。
- [ ] **控制流优化**: 针对 `if/else` 生成高效的分支跳转代码。
- [ ] **内联优化**: 针对小函数与属性访问 (`get`/`set`) 进行激进内联。

### 阶段四：工具链与生态 (Tooling & Ecosystem)
- [ ] **CLI 工具**: `do build`, `do test`, `do run`。
- [ ] **LSP 服务**: 提供代码补全、跳转与实时错误检查。
- [ ] **标准库**: 完善 IO 和网络支持。
