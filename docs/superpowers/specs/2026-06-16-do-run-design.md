# `do run` 第一版设计

## 目标

为 `do` 编译器增加第一版 `do run <input.do>` 命令, 让当前可执行的 core wasm 子集可以通过用户侧单命令直接运行。

这一版只解决“把现有可运行的 build 子集跑起来”这个问题, 不提前承诺完整 runtime、WASI 或 component 执行能力。

## 当前现场

当前仓库已经有一条可工作的 wasm 执行桥接链:

1. `do build <input.do> -o out.wat`
2. `wasm-tools parse out.wat -o out.wasm`
3. `node tool/build/test/run_wasm_case.mjs out.wasm`

相关证据:

- `tool/main.zig` 当前只有 `build` / `test` 命令。
- `tool/build/test/run_wasm_smoke.sh` 已按上面的三段式执行 `tool/build/test/run/*.do`。
- `tool/build/test/run_wasm_case.mjs` 已能实例化 wasm、提供最小 `env` imports, 并调用 `_start`。
- `tool/build/test/run/*.do` 已覆盖 `start()`、`@env("log")`、字符串 / `[u8]` wrapper 和 `defer` 顺序。

这说明第一版 `do run` 不需要先发明新的执行模型, 而应先把现有可验证链路产品化。

## 非目标

这一版明确不做:

- `@wasi` / WIT / component 执行
- 直接 wasm binary emitter
- 内置 wasm runtime
- 通用 host import 注册系统
- 用户自定义 `@env` 宿主表
- 命令行参数透传给 wasm 程序
- 稳定 stdin / stderr / exit code 扩展协议

## 方案比较

### 方案 A: 直接复用现有三段式桥接

命令执行:

1. `do run input.do`
2. 内部调用现有 build 逻辑产出临时 `.wat`
3. 调用 `wasm-tools parse`
4. 调用 Node runner 执行 `_start`

优点:

- 与现有 smoke/test 证据完全一致
- 实现最小
- 风险最低

缺点:

- 依赖 `wasm-tools` 和 `node`
- 仍然是外部桥接, 不是内置 runtime

### 方案 B: 先做内置 Zig runtime

优点:

- 命令更“完整”
- 少一个外部 Node 依赖

缺点:

- 需要立刻定义 wasm 执行器、宿主导入、memory 访问和 trap 语义
- 明显超出 07.1 的最小收口范围

### 方案 C: 先不做 `do run`, 继续只保留测试脚本

优点:

- 零新增实现

缺点:

- Roadmap 的 07.1 无法前进
- 用户侧仍只能手拼三段式命令

## 推荐

推荐方案 A。

理由:

1. 它完全复用仓内已经被 `run_wasm_smoke.sh` 证明可工作的链路。
2. 它把新增范围限制在 CLI 编排和错误处理, 不碰语义、codegen 和 runtime 设计。
3. 它给后续真正的 runtime 设计留出了替换空间: 将来可以替换 Node runner, 但 `do run` 命令形态不必变。

## 用户可见行为

### 命令形态

```bash
do run <input.do>
```

第一版不支持:

```bash
do run <input.do> -- arg1
do run <input.do> -o out.wat
do run <input.do> --component-core
```

### 成功路径

`do run app.do` 成功时:

1. 编译输入文件
2. 生成临时 `.wat`
3. 转成临时 `.wasm`
4. 执行导出的 `_start`
5. 把 runner 收集到的 stdout 输出到终端

### 失败路径

失败分为三类:

1. 编译失败
   - 直接复用现有 `do build` 诊断
2. 环境缺失
   - `wasm-tools` 不存在
   - `node` 不存在
3. 执行失败
   - 缺少 `_start`
   - Node runner / WebAssembly instantiate 失败
   - `_start` trap

第一版要求失败时返回非零退出码, 并把原因打印到 stderr。

## 支持范围

### 支持的源码边界

第一版只承诺当前 `tool/build/test/run/*.do` 所代表的 build 子集, 也就是:

- `start()`
- 当前 core 表达式 / 控制流子集
- 现有能 lower 到 core wasm 的代码
- runner 已显式提供的最小 `env` imports

### 支持的宿主 imports

第一版 runner 内建以下 `env` imports:

- `add`
- `dep_add`
- `log`

这里的含义是“当前 `do run` 自带的最小测试宿主表”, 不是对语言级 `@env` 的通用承诺。

### 明确拒绝的边界

遇到以下情况时, 第一版可以直接失败:

- 使用 `@wasi`
- 依赖 runner 未实现的 `@env`
- 需要 component / component-core 执行
- 需要 stdin/argv 等进程接口

## 实现设计

### CLI

在 `tool/main.zig` 增加:

- `run` 子命令

在新模块中增加:

- `parseRun(args)` 只接受一个输入文件

### 执行流程

建议新增 `tool/run/run.zig`, 负责:

1. 解析 CLI
2. 读取源码并复用现有 build 前端 / codegen 路径
3. 写临时 `.wat`
4. 调 `wasm-tools parse`
5. 调 Node runner
6. 透传 stdout/stderr 和退出码

这里不应复制 `do build` 的编译逻辑, 而应尽量复用 `tool/build/run.zig` / `tool/build/codegen.zig` 的现有入口或可抽取辅助函数。

### JS runner

建议不要直接复用测试目录下的脚本路径作为产品入口。

推荐做法:

1. 保留 `tool/build/test/run_wasm_case.mjs` 作为测试脚本
2. 在 `tool/run/` 下新增面向 `do run` 的正式 runner
3. 两者初版逻辑可以相同, 但产品入口与测试入口分离

这样后续扩展 `do run` 时不会把测试脚本契约意外固化成产品接口。

### 临时文件

第一版使用临时目录保存中间产物:

- `<tmp>/do-run-XXXX/out.wat`
- `<tmp>/do-run-XXXX/out.wasm`

命令结束后清理临时目录。

## 测试设计

第一版至少需要三层验证:

1. CLI 解析测试
   - `do run` 缺参数
   - `do run` 多参数
2. 黑盒 smoke
   - 复用 `tool/build/test/run/*.do`
   - 增加 `do run` 直接调用路径, 不再只测脚本三段式
3. 环境失败路径
   - 缺 `wasm-tools`
   - 缺 `node`

## 风险与回滚

### 风险

1. 把测试桥接脚本直接固化为产品接口, 导致后续难替换
2. 错误处理不统一, 用户看到的是 Node/wasm-tools 原始噪声
3. 后续有人误以为 `do run` 已支持通用 `@env` / `@wasi`

### 控制方式

1. 文档和 CLI usage 中明确“第一版只支持当前 core wasm smoke 子集”
2. 产品 runner 与测试 runner 分离
3. 对不支持能力尽量给出清晰错误

### 回滚

若实现后发现边界仍不稳, 可以只回滚 `run` 子命令入口, 不影响 `build` / `test` / `run_wasm_smoke.sh` 现有链路。

## 验收标准

满足以下条件即可视为 07.1 第一阶段完成:

1. `do run <input.do>` 已可运行当前 smoke 子集
2. stdout 与现有 `tool/build/test/run/*.stdout.expect` 一致
3. 缺 `wasm-tools` / `node` 时有明确失败信息
4. 文档已明确这是最小桥接方案, 不包含 WASI / component 支持
