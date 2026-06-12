# do 语言

> 当前仓库状态: 第二版编译器正在实现。

`do` 是一种面向 wasm 环境的值语义编程语言，当前仓库聚焦第二版编译器与 v1 语言/运行时子集。

## 核心理念

- **纯值语义**: 变量传递即拷贝，消除指针复杂度。
- **Perceus / FBIP 方向**: 目标是在唯一引用 (`rc == 1`) 时优先复用对象并做原地修改；当前只保留 v1 正确性子集，完整 FBIP `reuse` 仍按 `doc/roadmap_status.md` 暂跳过。
- **隐式 ARC 生命周期管理**: 编译器当前已覆盖 managed storage / struct 的基础 `inc/dec`、局部释放、return ownership 和部分 COW 写路径；完整冗余消除与末次使用优化仍按 `doc/roadmap_status.md` 暂跳过。
- **静态泛型特化**: 类型采用 `Name<T>`，函数采用 `#` 约束前置行，并支持受约束泛型接口。结构体泛型的无约束类型参数直接写 `#T` 紧贴结构声明。编译时通过 Monomorphization 生成具体代码与唯一 `type_id`。
- **函数值与重载**: 普通函数名可在有目标 `FuncType` 的上下文中解析为函数值；lambda 只出现在回调槽位。支持约束泛型函数与同名重载；重载只按参数签名决议。
- **同类型不定参数**: 支持 `rest ...T` 形态的同类型可变参数调用，core 聚合函数可写成 `@add(a, b, c)`，是否可扁平化完全由函数签名决定。
- **显式数据流**: 成员访问统一使用 `@get/@set(...)` 路径 primitive 和显式路径，控制流保持显式。这确保了编译器能确定地分析 ARC 生命周期和原地修改机会。
- **大小写语义**: 基础类型小写，类型名与绑定名遵循 `doc/spec_rules.md` 的命名规则。
- **WASM 原生**: Wasm memory grow 以 64KB page 为粒度，v1 allocator 在 page 内切成 64 个 1KB block；小对象使用 bitmap small block，大对象使用连续 block span。
- **大小数据分层策略**: 基础/小对象直接拷贝，大对象采用共享 + COW（初始阈值 64B）。
- **运行时资源管理方向**: 对 host 资源采用显式释放和 ID 关联的设计方向，目标是不引入循环 GC。
- **语言规范基线**: 规范入口见 `doc/spec.md`; 语法设计见 `doc/syntax/README.md`; parser PEG 见 `doc/grammar.peg`; 语义、内建判断族、核心库特型与静态约束见 `doc/spec_rules.md`。
- **WASI / WIT lowering 入口**: `@wasi` / WIT / component lowering 的当前 compiler-facing 合同见 `doc/wit/wasi_p3_lowering.md`; 当前已登记 target / record mirror registry 见 `doc/wit/wasi_registry.json`。
- **程序入口固定**: 源码入口声明固定为 `start() { ... }`，`main` 不是入口函数；构建输出会导出 wasm `_start`。
- **目录结构**: `tool/build` 编译器源码, `src` builtin/core 总表与标准库, `bin/do` 唯一二进制。

## 目录结构

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

## 构建

```bash
cd tool
zig build -Doptimize=ReleaseSmall
# 产物: bin/do

# 编译
../bin/do build app.do -o app.wat

# 运行 do 文件中的 test 声明
../bin/do test app.do

# 仓库回归
cd ..
./tool/build/test/run_tests.sh

# 启用 wasm / compiled / component 相关 gate
RUN_WASM=1 ./tool/build/test/run_tests.sh
```
## 开发计划 (Roadmap)

状态口径: `已完成` 表示当前编译器和回归测试已覆盖对应 v1 子集; `暂跳过` 表示当前缺少前置条件或现阶段不作为主目标, 原因记录在 `doc/roadmap_status.md`; `最后处理` 表示明确后置到主线稳定后再单独收口。WASI / Component Model 放到最后单独处理。

### 已完成
- [x] **规范基线**: `doc/spec.md` 是规范入口；`doc/syntax/` 已按功能拆分语法设计；`doc/grammar.peg` 保留 parser PEG；`doc/spec_rules.md` 保留语义约束、示例标签和 `defer` 规则。
- [x] **编译器前端主线**: Parser / Sema 已覆盖当前回归正在使用的 build/test 子集，包括 Struct、Lambda、guard `if`、`loop`、泛型约束、聚合字面量、import / host import 和测试声明；这表示当前回归子集可用，不表示前端语法/语义边界已经全部封顶。
- [x] **`defer` 基础语法和前端校验**: 支持 `defer abc()` 和 `defer { ... }`；本地和导入函数调用都会校验 cleanup 调用返回 `nil`。
- [x] **运行时内存模型**: 已按 `doc/memory.md` 收敛 v1 managed handle、对象头、`type_id`、layout table 和 ARC `inc/dec/release` 管理。
- [x] **内存分配器**: 已按 `doc/memory_layout_structs.md` 收敛 1KB block、bitmap small block、large span、free span split / merge 和空 small block 回收。
- [x] **标准库边界**: `[u8]`、`List`、`HashMap`、IO、网络类型形态和 `text` runtime 已归入 core / std / runtime 边界；完整 I/O 执行能力和真实网络 host ABI 继续归入后续 WASI / Component Model。
- [x] **WAT 代码生成子集**: `do build` / `do test --compiled` 当前可验证的 WAT 输出已覆盖标量、value enum carrier、结构体 flatten、storage / text ARC handle、多返回和基础 `@get/@set/@put`；这不表示完整后端优化或直接 wasm 二进制输出已经完成。
- [x] **测试入口**: `do build`、`do test` 和 `do test --compiled` 作为用户侧黑盒入口已落地；仓库级完整回归入口是 `./tool/build/test/run_tests.sh`。`RUN_WASM=1` 会在该入口上额外执行 wasm run、compiled wasm 执行、compiled trap 和可用时的 component/embed/validate gate。

### 暂跳过
- [ ] **`defer` 完整控制流与 ARC**: `defer` 的 LIFO cleanup、跨 `return/break/continue` lowering、cleanup 块内控制流限制和 ARC release 顺序的剩余状态在 `doc/roadmap_status.md` 中跟踪。
- [ ] **ARC / Perceus 完整分析**: 当前已有 managed storage `inc/dec`、局部释放和 `defer` cleanup 顺序；完整静态插入、冗余消除、末次使用优化和 FBIP `reuse` 暂跳过, 原因见 `doc/roadmap_status.md`。
- [ ] **后端控制流和优化**: guard `break/continue`、带标签循环、集合/消费循环 lowering、`if/else`、`@get/@set` 和小函数内联优化暂跳过；WAT 输出已可用, WASM 二进制输出仍待补, 原因见 `doc/roadmap_status.md`。
- [ ] **生态工具**: `do run`、LSP、fmt、get / push 等工具链能力暂跳过, 原因见 `doc/roadmap_status.md`。

### 最后处理
- [ ] **WASI / Component Model FFI**: 当前只保留已登记 `@wasi` manifest、shim、component-core 输入与标准库 wrapper 子集；完整 binding source / alias、component lowering、result-area、resource / variant / future 支持放到最后单独审查。
