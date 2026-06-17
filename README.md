# do 语言

> 当前仓库状态: 第二版编译器正在实现。

`do` 是一种面向 wasm 环境的值语义编程语言，当前仓库聚焦第二版编译器与 v1 语言/运行时子集。

## 核心理念

- **纯值语义**: 变量传递即拷贝，消除指针复杂度。
- **Perceus / FBIP 方向**: 目标是在唯一引用 (`rc == 1`) 时优先复用对象并做原地修改；当前已覆盖 ownership exit plan、死 alias 消除和保守 last-use move 子集，完整 FBIP `reuse` 仍按 `doc/roadmap_status.md` 后置。
- **隐式 ARC 生命周期管理**: 编译器当前已覆盖 managed storage / struct 的基础 `inc/dec`、局部释放、return ownership、部分 COW 写路径、死 alias `inc/dec` 相消和 direct managed last-use move 子集；跨函数唯一性证明、借用/共享来源字段读取 move 和 FBIP `reuse` 仍未完成。
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
tool/check/      do check 前端诊断命令实现
tool/run/        do run 命令实现和 wasm 执行桥接
tool/build/test/ 当前编译器/构建产物回归测试
tool/get/        do get 逻辑预留目录
tool/push/       do push 逻辑预留目录
tool/fmt/        do fmt 命令实现和格式化核心
tool/lsp/        do lsp diagnostics-only server 实现
tool/test/       do test 逻辑预留目录
```

## 文档入口

- 当前接手入口: `doc/start_here.md`
- 总规划: `doc/master_plan.md`
- 执行状态和验证证据: `doc/roadmap_status.md`
- 历史变更摘要: `CHANGELOG.md`

## 构建

```bash
cd tool
zig build -Doptimize=ReleaseSmall
# 产物: bin/do

# 编译
../bin/do build app.do -o app.wat

# 运行 do 文件中的 test 声明
../bin/do test app.do

# 只检查 lexer/parser/sema/import diagnostics, 不编译或运行
../bin/do check app.do

# 运行带 start() 入口的 do 程序
../bin/do run app.do

# do run 第一版依赖本机 wasm-tools 与 node
# 当前边界: build -> WAT -> wasm-tools parse -> node 执行 core wasm smoke 子集

# 格式化并输出到 stdout
../bin/do fmt app.do

# 只检查是否已经格式化
../bin/do fmt --check app.do

# 启动 diagnostics-only LSP stdio server
../bin/do lsp
../bin/do lsp --stdio

# do lsp 第一版只发布打开文档的 lexer/parser/sema/import diagnostics
# 当前边界: 不包含 completion、hover、definition、rename 或 formatting

# 仓库回归
cd ..
./tool/build/test/run_tests.sh

# 启用 wasm 执行、compiled wasm 和 trap/smoke 增量 gate
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
- [x] **测试入口**: `do build`、`do test` 和 `do test --compiled` 作为用户侧黑盒入口已落地；仓库级完整回归入口是 `./tool/build/test/run_tests.sh`。默认入口已覆盖 `compile_ok` 中的 WIT / component plan、component input、component core 和可用时的 embed/validate gate；`RUN_WASM=1` 在此基础上额外执行 wasm run、compiled wasm 执行、compiled trap 和 wasm smoke。
- [x] **`do check` 第一版**: `do check <input.do>` 已落地为前端诊断命令; 当前复用 LSP diagnostics collector, 覆盖 lexer/parser/sema/import diagnostics, 不编译、不运行、不要求 `start()` 或 `test` 声明。
- [x] **`do run` 第一版桥接**: `do run <input.do>` 已落地为产品命令，当前走 `do build` 同源 WAT 编译、`wasm-tools parse` 转 wasm、`node tool/run/run_wasm_program.mjs` 执行；覆盖当前 core wasm smoke 子集，不包含 WASI / Component Model / 自定义 host runtime。
- [x] **`do fmt` 第一版**: `do fmt <input.do>` 和 `do fmt --check <input.do>` 已落地; 当前只输出格式化结果或做检查, 不做原地写回; 回归覆盖 stdout、idempotence 和 `error[FormatMismatch]`。
- [x] **`do lsp` 第一版**: `do lsp [--stdio]` 已落地为 diagnostics-only LSP stdio server; 当前发布 lexer/parser/sema/import diagnostics, 不提供 completion、hover、definition、rename 或 formatting。

### 暂跳过
- [x] **`defer` 完整控制流与 ARC**: `defer` 的 LIFO cleanup、跨 `return/break/continue` lowering、cleanup 块内控制流限制和 ARC release 顺序已由 `tool/build/test/compile_ok/142_*` 到 `150_*` 及 `tool/build/test/err/267_*`、`274_*`、`288_*` 到 `305_*` 覆盖，状态见 `doc/roadmap_status.md`。
- [ ] **ARC / Perceus 完整分析**: 当前已落地 `tool/build/ownership.zig`、死 alias 消除和保守 last-use move 子集；完整 ownership IR / data-flow、跨函数唯一性证明和 FBIP `reuse` 仍未完成, 原因见 `doc/roadmap_status.md`。
- [ ] **后端优化**: 当前保留可验证 WAT lowering；backend instruction model、WAT peephole、小函数内联、`@get/@set` 专门内联优化和 WASM 二进制输出仍待补, 原因见 `doc/roadmap_status.md`。
- [ ] **生态工具剩余项**: get / push 等工具链能力暂跳过, 原因见 `doc/roadmap_status.md`。

### 最后处理
- [ ] **WASI / Component Model FFI**: 当前只保留已登记 `@wasi` manifest、shim、component-core 输入与标准库 wrapper 子集；完整 binding source / alias、component lowering、result-area、resource / variant / future 支持放到最后单独审查。
