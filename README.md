# do 语言

> 当前仓库状态: v1 子集发布候选已收口; 后续默认只处理发布阻断回归、文档漂移或已确认的 G6 / 运行时决策项。

`do` 是一种面向 wasm 环境的值语义编程语言，当前仓库已收口第二版编译器的 v1 可验证子集，后续功能按本文的下一阶段计划推进。

## 核心理念

- **纯值语义**: 变量传递即拷贝，消除指针复杂度。
- **Perceus / FBIP 方向**: 目标是在唯一引用 (`rc == 1`) 时优先复用对象并做原地修改；当前已覆盖 ownership exit plan、死 alias 消除、保守 last-use move 子集、参数/字段 ownership facts 和 D5 最小 `rc == 1` reuse / `rc > 1` COW 回退。完整 ownership IR、跨函数唯一性证明、escape analysis 和 region 仍按 `doc/roadmap_status.md` 后置。
- **隐式 ARC 生命周期管理**: 编译器当前已覆盖 managed storage / struct 的基础 `inc/dec`、局部释放、return ownership、部分 COW 写路径、死 alias `inc/dec` 相消、direct managed last-use move 子集和 managed struct 最小 clone/reuse lowering；跨函数唯一性证明和借用/共享来源字段读取 move 仍未完成。
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
- **目录结构**: `src/` 工具链与编译器源码, `lib/` builtin/core 总表与标准库, `bin/do` 唯一二进制。

## 目录结构

```txt
doc/            语法, 语义和运行时设计文档
bin/            zig 编译出的 do 编译器二进制
lib/            do builtin/core 总表与标准库
src/            工具链与编译器源码 (原 tool/)
src/main.zig    唯一二进制 CLI 分派入口
src/build.zig   Zig 构建入口
src/build/      do build 逻辑实现和编译器源码
src/check/      do check 前端诊断命令实现
src/run/        do run 命令实现和 wasm 执行桥接
src/build/test/ 当前编译器/构建产物回归测试
src/fmt/        do fmt 命令实现和格式化核心
src/lsp/        do lsp diagnostics + formatting + semantic tokens + hover + completion + definition server 实现
```

## 文档入口

- 当前接手入口: `doc/start_here.md`
- 总规划: `doc/master_plan.md`
- 执行状态和验证证据: `doc/roadmap_status.md`
- **待处理与阻断**: `doc/pending_blocked.md` (G6 / 语言缺口 / deferred / skip)
- 历史变更摘要: `CHANGELOG.md`

## 当前 v1 子集摘要

- 语言前端: 当前 parser / sema 已覆盖结构体、错误枚举、value enum、plain union / nullable union、字段反射、lambda、泛型约束、同名重载、同类型 variadic、`loop`、`defer`、import / host import 和 `test` 声明的回归子集; 普通直接递归、互递归、参数侧已定型的泛型递归和 self-tail TCO 第一版已补回归, 仅靠左侧目标类型反推的泛型递归仍后置; 源码层 `Tuple<T0, T1, ...>` 位置构造 + `@get` 数字索引已落地 (local/struct/return/param/nested/标量与 managed/`text` 叶子 storage、pure-scalar struct 嵌套子槽、`@get(storage, i, j)` path chaining, 以及 loop 绑定上的 `@get(v, N)`); 含 managed 字段的 struct 直接子槽仍 `UnsupportedTupleStorageLeaf` (见 `doc/pending_blocked.md` P1)。
- 内存与所有权: 已落地 managed handle、对象头、layout table、ARC `inc/dec/release`、ownership exit plan、死 alias 消除、保守 last-use move、字段/参数 ownership facts 和 managed struct 最小 clone/reuse lowering; Tuple storage pack 合成 layout 负责 managed 叶子 clone/free。
- 标准库: 已验证 JSON struct stringify/from_json、bytes/text/utf8/utf16、hex/base64/url、math/binary/mem/atomic/range/slice/path/fp/list/set/hash_map/hash、md5/sha1/sha256 等基础库; time/random/file/dir/io.stream 只承诺已登记 WASI wrapper lowering; net/tcp/udp/http.client 只承诺当前 shape/check smoke, 真实 host I/O 后置。
- 后端与 WASI: 公开输出仍以 WAT 为主; 当前 build/test 子集已覆盖标量、结构体 flatten、storage/text ARC handle、多返回、基础 `@get/@set/@put`、WASI result-area/resource-drop lowering、component plan/core imports/core shims/component input 和真实 component wasm validate gate。
- 工具链: `do build`、`do test`、`do test --compiled`、`do check`、`do run`、`do fmt` 和 `do lsp` 第一版均已落地; LSP 当前覆盖 diagnostics、formatting、semantic tokens、hover、completion、definition 和最小 workspace index。
- 验证入口: 默认完整回归基线为 `pass=915 fail=0 skip=3`; `RUN_WASM=1` 扩展回归基线为 `pass=833 fail=0 skip=3` (未在本轮重跑); 发布前 smoke 入口是 `./src/build/test/run_release_smoke.sh`。


## v1 非目标

- 不提供完整 ownership IR、跨函数唯一性证明、escape analysis、region 或激进 loop/path move; 当前继续使用已验证的 `OwnershipFacts` 子集和保守回退。
- 不引入 direct wasm binary emitter; `do build` 和 `do test --compiled` 继续输出 WAT, 执行链路继续通过 `wasm-tools parse`。
- 不承诺完整 WASI / Component Model 运行时; preopens list-of-tuple-resource、read-directory stream/future(当前无 async/Future runtime)、sockets resource + variant、HTTP async resource 和真实 host runtime 继续后置。
- 不提供完整自动序列化; JSON 当前只承诺已验证的 struct 字段 stringify/from_json 子集, error/enum/union/复杂 storage 自动支持继续后置。
- 不重开 get / pkg / push 包管理线。
- 不把 `do fmt` 扩展成多文件批量、stdin/stdout 自动模式、range/on-type 或完整语法感知 formatter。
- 不把 `do lsp` 扩展成完整语言服务; v1 不支持 rename、references graph、import-aware 跨模块跳转、增量 workspace index 或完整字段/local definition。
- 不把 `do run` 描述成 WASI / Component Model / 自定义 host runtime; 当前只覆盖 core wasm smoke 子集。

## 下一阶段计划

默认推进顺序与接手细则见 `doc/start_here.md` 与 `doc/master_plan.md` §12。摘要:

1. **发布候选维护**: `./src/build/test/run_tests.sh`、`./src/build/test/run_release_smoke.sh`、必要时 `RUN_WASM=1 ./src/build/test/run_tests.sh`; 只修阻断发布的回归或文档漂移。
2. **WASI / Component Model 决策 (G6)**: 先确认 preopens API、read-directory 所需 async/Future runtime、sockets resource + variant 映射, 再落 codegen 或标准库 wrapper。
3. **Host runtime smoke**: G6 决策后补真实 file/dir/stream/socket/http host smoke, 再逐步收回 `16/96/118` 相关后置 skip。
4. **JSON / 序列化扩展**: 以字段反射与已验证 struct JSON 为基础, 再定 error/enum/union/storage 自动序列化边界。
5. **Ownership 深化**: runtime 边界稳定后再重开完整 ownership IR、跨函数唯一性证明、escape analysis、region 与更激进 move/reuse。
6. **编辑器与格式化增强**: LSP rename/references、import-aware definition、range/on-type formatting、语法感知 formatter — v1 后单独推进。
7. **后端输出实验**: direct wasm binary emitter 仅作并行评估, 不替换 WAT 主输出与 golden 基线。
8. **可选 (需单独授权)**: 见 `doc/pending_blocked.md` — 如 P1 managed struct Tuple 子槽、codegen 垂直再拆、ownership/JSON/LSP 等 deferred 项。

## 构建

```bash
cd src
zig build -Doptimize=ReleaseSmall
# 产物: bin/do

# 编译
../bin/do build app.do -o app.wat

# 运行 do 文件中的 test 声明
../bin/do test app.do
../bin/do test app.do --compiled -o app.test.wat

# 只检查 lexer/parser/sema/import diagnostics, 不编译或运行
../bin/do check app.do
../bin/do check a.do b.do

# 运行带 start() 入口的 do 程序
../bin/do run app.do

# do run 第一版依赖本机 wasm-tools 与 node
# 当前边界: build -> WAT -> wasm-tools parse -> node 执行 core wasm smoke 子集

# 格式化并输出到 stdout
../bin/do fmt app.do

# 只检查是否已经格式化
../bin/do fmt --check app.do

# 原地写回格式化结果
../bin/do fmt --write app.do

# 启动 LSP stdio server
../bin/do lsp
../bin/do lsp --stdio

# do lsp 发布打开文档的 lexer/parser/sema/import diagnostics, 并支持 formatting、semantic tokens、最小函数 hover、最小 completion、最小 definition、initialize workspace root 记录和 workspace 顶层符号扫描
# 当前边界: 仍不包含 rename; hover 只覆盖当前文件函数声明/调用签名; completion 不做排序、snippet 或字段 receiver 类型收窄; definition 不做 import-aware resolution、字段或 local 跳转; workspace index 只扫描 file root 一层 `.do` 顶层函数/类型

# 仓库回归
cd ..
./src/build/test/run_tests.sh

# 发布前 smoke: ReleaseSmall 构建 + build/test/check/fmt/run/lsp 最小链路
./src/build/test/run_release_smoke.sh

# 启用 wasm 执行、compiled wasm 和 trap/smoke 增量 gate
RUN_WASM=1 ./src/build/test/run_tests.sh
```
## 开发计划 (Roadmap)

状态口径: `已完成` 表示当前编译器和回归测试已覆盖对应 v1 子集; `暂跳过` 表示当前缺少前置条件或现阶段不作为主目标, 原因记录在 `doc/roadmap_status.md`; `最后处理` 表示明确后置到主线稳定后再单独收口。WASI / Component Model 放到最后单独处理。

### 已完成
- [x] **规范基线**: `doc/spec.md` 是规范入口；`doc/syntax/` 已按功能拆分语法设计；`doc/grammar.peg` 保留 parser PEG；`doc/spec_rules.md` 保留语义约束、示例标签和 `defer` 规则。
- [x] **编译器前端主线**: Parser / Sema 已覆盖当前回归正在使用的 build/test 子集，包括 Struct、Lambda、guard `if`、`loop`、泛型约束、聚合字面量、import / host import 和测试声明；这表示当前回归子集可用，不表示前端语法/语义边界已经全部封顶。
- [x] **递归与 self-tail TCO 第一版子集**: 已覆盖普通直接递归、互递归、参数侧已知 concrete type 的泛型递归，以及 self-tail scalar / `if/else` / guard / generic / imported lowering；`src/build/test/compile_ok/248_*` 到 `258_*` 继续锁住 `defer`、storage local、managed struct、多返回和 cleanup 相关的不优化边界，且“只靠左侧目标类型反推”的泛型递归仍按 `NoMatchingCall` 后置。
- [x] **源码层 `Tuple<...>` 第一版子集**: 已覆盖位置构造 `Tuple<T0, T1, ...>{...}`、编译期数字索引 `@get` (含 loop 绑定与 `@get(storage, i, j)` path chaining)、struct field、return/param multi-value ABI、嵌套叶子 ABI、标量与 managed/`text` 叶子 `[Tuple<...>]` storage pack；sema 诊断覆盖 arity / 越界 / 非字面量索引 / 小写 `tuple` 误用；裸 struct 等非 packable 叶子 storage 报 `UnsupportedTupleStorageLeaf`。
- [x] **`defer` 基础语法和前端校验**: 支持 `defer abc()` 和 `defer { ... }`；本地和导入函数调用都会校验 cleanup 调用返回 `nil`。
- [x] **`defer` 完整控制流与 ARC**: `defer` 的 LIFO cleanup、跨 `return/break/continue` lowering、cleanup 块内控制流限制和 ARC release 顺序已由 `src/build/test/compile_ok/142_*` 到 `150_*` 及 `src/build/test/err/267_*`、`274_*`、`288_*` 到 `305_*` 覆盖，状态见 `doc/roadmap_status.md`。
- [x] **运行时内存模型**: 已按 `doc/memory.md` 收敛 v1 managed handle、对象头、`type_id`、layout table 和 ARC `inc/dec/release` 管理。
- [x] **内存分配器**: 已按 `doc/memory_layout_structs.md` 收敛 1KB block、bitmap small block、large span、free span split / merge 和空 small block 回收。
- [x] **ARC / Ownership / FBIP 当前子集**: 已落地 `src/build/ownership.zig`、`src/build/ownership_facts.zig`、死 alias 消除、保守 last-use move、参数 ownership contract、字段读取 move facts 接入和 managed struct 最小 clone/reuse lowering；完整 ownership IR / 跨函数唯一性证明仍不是当前 v1 子集。
- [x] **标准库边界**: 当前稳定公开子集聚焦已验证的纯 do 库与少量已登记 wrapper，包括 JSON 的结构体字段 stringify/from_json、bytes/text/utf8/utf16、hex/base64/url、math/binary/mem/atomic/range/slice/path/fp/list/set/hash_map/hash、md5/sha1/sha256 等基础库；`time.do`、`random.do`、`file.do`、`dir.do`、`io.stream.do` 只承诺已登记 WASI wrapper lowering；`net.do`、`tcp.do`、`udp.do`、`http.client.do` 当前只承诺 shape/check smoke, 真实 host I/O 继续后置；`simd.do` 当前只纳入 std source metadata/check 边界；完整 I/O 执行能力、真实网络 host ABI、通用自动序列化和复杂 resource/variant/future/component 输出继续归入后续阶段。
- [x] **WAT 代码生成子集**: `do build` / `do test --compiled` 当前可验证的 WAT 输出已覆盖标量、value enum carrier、结构体 flatten、storage / text ARC handle、多返回和基础 `@get/@set/@put`；这不表示完整后端优化或直接 wasm 二进制输出已经完成。
- [x] **后端 IR 和 codegen 稳定化**: 已完成 backend instruction model、基础控制流优化、copy fold、trivial inline、runtime prelude / function body / component metadata writer 拆分和 direct wasm binary emitter 重新评估；当前继续保留 WAT 文本作为主输出和 golden 基线。
- [x] **测试入口**: `do build`、`do test` 和 `do test --compiled` 作为用户侧黑盒入口已落地；仓库级完整回归入口是 `./src/build/test/run_tests.sh`。默认入口已覆盖 `compile_ok` 中的 WIT / component plan、component input、component core 和可用时的 embed/validate gate；`RUN_WASM=1` 在此基础上额外执行 wasm run、compiled wasm 执行、compiled trap 和 wasm smoke。
- [x] **`do check` 第一版**: `do check <input.do>...` 已落地为前端诊断命令; 当前复用 LSP diagnostics collector, 覆盖 lexer/parser/sema/import diagnostics, 支持按命令行顺序检查多个文件, 不编译、不运行、不要求 `start()` 或 `test` 声明。
- [x] **`do run` 第一版桥接**: `do run <input.do>` 已落地为产品命令，当前走 `do build` 同源 WAT 编译、`wasm-tools parse` 转 wasm、`node src/run/run_wasm_program.mjs` 执行；覆盖当前 core wasm smoke 子集，不包含 WASI / Component Model / 自定义 host runtime。
- [x] **`do fmt` 第一版**: `do fmt <input.do>`、`do fmt --check <input.do>` 和 `do fmt --write <input.do>` 已落地; 当前支持 stdout 输出、检查和单文件原地写回; 回归覆盖 stdout、write、idempotence 和 `error[FormatMismatch]`。
- [x] **`do lsp` 第一版**: `do lsp [--stdio]` 已落地为 diagnostics + formatting + semantic tokens + hover + completion + definition LSP stdio server; 当前发布 lexer/parser/sema/import diagnostics, 支持 formatting、semantic tokens、当前文件函数 hover、当前文件函数/类型/字段段 completion、当前文件函数/类型 definition、initialize workspace root 记录和 workspace 顶层符号扫描; completion / definition 已复用 workspace 顶层函数/类型 index, 仍不提供 rename。

### 暂跳过
- [ ] **完整 ownership IR / 跨函数唯一性证明**: 当前 v1 子集走增量 `OwnershipFacts` 和保守回退; 完整 ownership graph、跨函数 data-flow、escape analysis、region 和更激进的 loop/path move 仍后置, 原因见 `doc/roadmap_status.md`。
- [ ] **direct wasm binary emitter**: 已评估但不作为当前主路径引入; 当前继续保留可验证 WAT 文本输出、`wasm-tools parse` 桥接和 WAT golden 回归, 原因见 `doc/roadmap_status.md`。
- [ ] **生态工具剩余项**: get / pkg / push 等工具链能力暂跳过, 原因见 `doc/roadmap_status.md`。

### 最后处理
- [ ] **WASI / Component Model FFI**: 当前已完成 `@wasi` binding 的 `source + alias` 身份规则、已登记 result-area lowering、component plan/core imports/core shims、component input dir 和真实 component wasm 生成/validate gate；G6 的 preopens list-of-tuple-resource、read-directory stream/future(当前无 async/Future runtime)、sockets resource + variant 仍因公开 API 或运行时设计未定而阻断。
