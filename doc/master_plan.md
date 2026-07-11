# do 编译器主计划

状态: v1 子集发布候选已收口, 剩余 G6 blocked residual
更新时间: 2026-07-07

本文是后续阶段的总规划入口, 用来回答“接下来按什么顺序做、每个阶段拆哪些小任务、每项怎么验收”。实时完成状态、阻塞原因和验证证据记录在 `doc/roadmap_status.md`。

## 0. 当前基线

已完成并可作为后续依赖的能力:

- 规范入口、语义规则、语法速查、PEG、内存模型和 WASI lowering 文档已拆分。
- `do build`, `do test`, `do test --compiled`, `do check`, `do run`, `do fmt`, `do lsp` 第一版已落地。
- 当前 `do lsp` 是 diagnostics + formatting + semantic tokens + 最小函数 hover + 最小 completion + 最小 definition stdio server。
- 当前 `do fmt` 是 stdout / check-only line-based formatter。
- 当前 `do check` 只做 lexer/parser/sema/import diagnostics, 不编译、不运行。
- 当前 `get / pkg / push` 包管理线暂停, 不作为默认后续任务。
- 最近完整回归基线: `./tool/build/test/run_tests.sh` 为 `pass=886 fail=0 skip=3`。

- 最近扩展回归基线: `RUN_WASM=1 ./tool/build/test/run_tests.sh` 为 `pass=833 fail=0 skip=3`。

当前禁止默认推进:

- 不重开 get / pkg / push, 除非用户明确要求。
- 不去掉内部函数 `@` 前缀。
- 不默认推进 direct wasm binary emitter。
- 不默认推进完整 WASI / Component Model; 该线放到阶段 G。
- 不大规模重写 parser / sema / codegen; 必须先拆成阶段计划和可回归小任务。

## 1. 推进协议

1. 每次只推进一个小任务。
2. 每个小任务必须能独立验证。
3. 完成一个小任务后, 立即同步 `doc/roadmap_status.md`。
4. 阻塞时, 在对应小任务下写清停止点、证据、影响和恢复条件。
5. 语法或语义变化必须同步 `doc/spec_rules.md`、`doc/grammar.peg`、相关 `doc/syntax/*.md` 和回归测试。
6. 工具行为变化必须同步 `README.md`、`tool/build/test/README.md` 和黑盒 fixture。
7. 文档清理只能删除过期入口和过期规则; 不能删除仍被 `doc/start_here.md`、`doc/roadmap_status.md` 或 README 引用的文件。

## 2. 阶段顺序和当前状态

历史主线顺序:

1. 阶段 A: 工具链体验补齐。
2. 阶段 B: 语法和语义冻结审查。
3. 阶段 C: 标准库与 JSON / 基础库收口。
4. 阶段 D: ARC / ownership / FBIP 深化。
5. 阶段 E: 后端 IR 和 codegen 稳定化。
6. 阶段 F: LSP 编辑器体验升级。
7. 阶段 G: WASI / Component Model 最后处理。
8. 阶段 H: 发布前治理。
9. 阶段 I: 后续语言能力扩展。

当前状态:

- 阶段 A、B、C、E、F、H 已完成。
- 阶段 D 的 D1-D5 可推进项已完成; D2.1 已按用户确认的 B 方案绿色 regression 收口, 阶段 D 当前无剩余 blocked 残留。
- 阶段 G 的 G1-G5 和 G6.4 已完成; G6.1、G6.3 仍等待公开 API 决策; G6.2 因当前无 async/Future runtime 暂时阻断。
- 阶段 I 已完成: I1 递归 / self-tail TCO 与 I2 `Tuple<...>` 第一版均已收口; 后置边界已记录。
- 用户说 `go` / `next` 时, 默认按第 12 节执行: 先检查发布候选回归、文档漂移或可独立收口的小项; 没有新小项时不绕过 G6 阻断。

## 3. 阶段 A: 工具链体验补齐

状态: done

目标: 让日常开发、编辑器集成和 CI 检查有稳定入口。

当前已完成:

- `do check <input.do>`
- `do fmt <input.do>`
- `do fmt --check <input.do>`
- `do lsp [--stdio]` diagnostics + formatting + semantic tokens + hover + completion + definition
- `do run <input.do>`

### A1. LSP formatting 第一版

状态: done

范围:

- 实现 `textDocument/formatting`。
- 返回全量 `TextEdit`, 覆盖整个文档。
- 复用 `tool/fmt/format.zig` 的格式化结果。
- LSP initialize capability 暴露 `documentFormattingProvider: true`。

暂不覆盖:

- range formatting。
- on-type formatting。
- 不做增量 edit。
- 不改变 `do fmt` 当前 stdout / check-only 行为。

拆分:

- [x] A1.1 新增 formatting 请求 LSP fixture, 先红灯验证当前不支持。
- [x] A1.2 扩展 LSP protocol helper, 能编码 formatting response 和全量 range。
- [x] A1.3 在 `tool/lsp/run.zig` 接入 `textDocument/formatting` handler。
- [x] A1.4 让 `tool/build/test/run_lsp_case.mjs` 能断言 response result。
- [x] A1.5 同步 README、`tool/build/test/README.md` 和 `doc/roadmap_status.md`。

主要文件:

- `tool/lsp/run.zig`
- `tool/lsp/protocol.zig`
- `tool/fmt/format.zig`
- `tool/build/test/run_lsp_case.mjs`
- `tool/build/test/lsp/*.json`
- `README.md`
- `tool/build/test/README.md`
- `doc/roadmap_status.md`

验收:

- `node tool/build/test/run_lsp_case.mjs ./bin/do tool/build/test/lsp/<formatting-case>.json`
- `bash -n tool/build/test/run_tests.sh`
- `cd tool && zig test main.zig`
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`

### A2. LSP semantic tokens 第一版

状态: done

范围:

- 实现 `textDocument/semanticTokens/full`。
- initialize response 暴露 semantic tokens legend。
- token 类别固定为 keyword、type、function、parameter、variable、field、property、string、number、comment、operator、builtin。
- 第一版允许基于 lexer + 当前文件轻量语义信息实现。

不做:

- 不做 delta tokens。
- 不做跨文件 workspace index。
- 不做高亮主题适配。

拆分:

- [x] A2.1 固定 legend 顺序和 token modifier 空集合。
- [x] A2.2 新增纯 token builder 单元测试, 覆盖 delta line / delta start 编码。
- [x] A2.3 接入当前文件 lexer token 分类。
- [x] A2.4 对 builtin `@xxx`、类型名、函数名和字段名做最小语义覆盖。
- [x] A2.5 新增 LSP fixture 检查 initialize legend 和 token data 非空。
- [x] A2.6 同步 README、测试说明和 `doc/roadmap_status.md`。

验收:

- `cd tool && zig test main.zig`
- `node tool/build/test/run_lsp_case.mjs ./bin/do tool/build/test/lsp/<semantic-tokens-case>.json`
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`

### A3. `do fmt --write`

状态: done

范围:

- 支持 `do fmt --write <input.do>` 原地写回单文件。
- 写入前先生成完整 formatted buffer。
- 已格式化文件再次执行必须幂等。

不做:

- 不做多文件批量。
- 不做 stdin/stdout 自动模式。
- 不做语法感知 formatter 重写。

拆分:

- [x] A3.1 为 CLI 增加 `--write` 解析红灯测试。
- [x] A3.2 在 formatter runner 中实现原地写回。
- [x] A3.3 新增临时目录黑盒测试, 验证写回内容和幂等。
- [x] A3.4 同步 README、测试说明和 `doc/roadmap_status.md`。

验收:

- `cd tool && zig test build/cli.zig`
- `cd tool && zig test main.zig`
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`

### A4. `do check` 多文件批量

状态: done

范围:

- 支持 `do check a.do b.do`。
- 按命令行顺序检查。
- 任一文件失败则最终 exit 1。
- 成功文件保持静默。

不做:

- 不做并发。
- 不做 watch。
- 不做 workspace mode。
- 不做多诊断聚合。

拆分:

- [x] A4.1 为多个 input 的 CLI parsing 增加红灯测试。
- [x] A4.2 调整 `tool/check/run.zig`, 顺序执行每个文件。
- [x] A4.3 黑盒 fixture 覆盖全部成功、后一个失败、前一个失败后仍继续或 fail-fast 的明确策略。
- [x] A4.4 同步 README、测试说明和 `doc/roadmap_status.md`。

验收:

- `cd tool && zig test build/cli.zig`
- `cd tool && zig test main.zig`
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`

### A5. 工具链收口检查

范围:

- 检查 README 中所有用户命令是否真实可执行或明确标注边界。
- 检查 `tool/build/test/run_tests.sh` 是否覆盖 check/fmt/lsp/run 的当前能力。
- 检查 `doc/start_here.md` 的下一步入口是否和本计划一致。

拆分:

- [x] A5.1 扫描 README、start_here、roadmap_status 的命令和边界描述。
- [x] A5.2 修正过期的工具链描述。
- [x] A5.3 执行 full regression 并记录摘要。

验收:

- `rg -n "do get|do push|completion|hover|definition|formatting" README.md doc/start_here.md doc/roadmap_status.md`
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`

阶段 A 完成标准:

- `do fmt` 支持 check、stdout 和 write。
- `do check` 支持单文件和多文件前端诊断。
- `do lsp` 至少支持 diagnostics、formatting、semantic tokens、最小函数 hover、最小 completion 和最小 definition。
- README、测试说明、roadmap 和 start_here 同步。

## 4. 阶段 B: 语法和语义冻结审查

目标: 把 v1 源码语法和静态语义边界固定下来, 减少后续实现返工。

### B1. grammar / parser 差异审查

范围:

- 对比 `doc/grammar.peg`、`doc/syntax/*.md` 和 `tool/build/parser.zig`。
- 覆盖顶层声明、表达式、lambda、return、多返回、line string、comment、loop、defer、import。
- 审查问题先输出到独立问题文件; 用户选定后同步落地并删除已解决的问题文件。

拆分:

- [x] B1.1 列出 PEG 有而 parser 没有的语法。
- [x] B1.2 列出 parser 有而 PEG 没有的语法。
- [x] B1.3 列出文档示例与 parser 行为冲突的语法。
- [x] B1.4 每个问题给正例、反例、选项 a/b/... 和推荐。
- [x] B1.5 用户选定后, 再同步 grammar、parser、doc 和 fixture。

验收:

- 已处理问题文件删除, 不保留过期语法问题清单。
- 已落地决定都有对应 `ok` 或 `err` fixture。
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`

### B2. spec_rules / sema 差异审查

范围:

- 对比 `doc/spec_rules.md`、`doc/spec.md`、`doc/syntax/*.md` 和 `tool/build/sema.zig` / imports 相关实现。
- 覆盖命名、作用域、重声明、遮蔽、重载、泛型、union、error、field reflection、loop binding、参数可变性。

拆分:

- [x] B2.1 列出文档定义但 sema 未实现的规则。
- [x] B2.2 列出 sema 已实现但文档未定义的规则。
- [x] B2.3 列出测试期望和文档冲突的规则。
- [x] B2.4 每个问题给正例、反例、选项 a/b/... 和推荐。
- [x] B2.5 用户选定后, 再同步 spec_rules、实现和 fixture。

验收:

- sema 审查结果先进入独立问题文件, 用户选定并落地后删除已解决问题文件。
- 每个落地决定绑定到 err/ok/compile fixture。
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`

### B3. 语法文档治理

范围:

- 清理 `doc/syntax/`、`doc/spec_examples.md` 和过期文档中的过期规则残留。
- 保留仍被入口文档引用的当前文档。

拆分:

- [x] B3.1 扫描 start_here、README、roadmap_status 的文档引用。
- [x] B3.2 找出已被当前规则替代的设计描述。
- [x] B3.3 更新或删除过期描述。
- [x] B3.4 用 `rg` 检查死链和过期规则关键字。

验收:

- `rg -n "<过期规则关键字>" README.md CHANGELOG.md doc`
- `git diff --check -- README.md CHANGELOG.md doc`

### B4. 语法冻结回归包

范围:

- 为 B1/B2 中每个已选定规则补最小正反例。
- err fixture 必须包含 `.expect`。
- compile fixture 必须覆盖 parser/sema/codegen 中实际会受影响的边界。

拆分:

- [x] B4.1 为 parser-only 规则补 `tool/build/test/err` 或 `ok`。
- [x] B4.2 为语义规则补 `ok` / `err`。
- [x] B4.3 为 codegen 相关规则补 `compile_ok` / `compile_err` 或 `compiled_ok`。
- [x] B4.4 回归并记录摘要。

验收:

- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`

阶段 B 完成标准:

- `doc/spec.md` 仍只作为入口, 不堆细则。
- `doc/spec_rules.md`、`doc/grammar.peg`、`doc/syntax/*.md` 与 parser/sema 行为一致。
- 不再存在未处理的语法歧义清单。

## 5. 阶段 C: 标准库与核心库收口

目标: 让当前语言能力有稳定的基础库承载, 特别是 JSON、bytes、text、list、map、math。

### C1. JSON stringify / from_json 收口

范围:

- 支持普通 struct、text、[u8]、bool、i32、字段级 `T | nil` stringify、嵌套 struct、默认字段。
- 支持 `from_json<User>(bytes)` 和 `from_json(bytes) -> T | JsonError` 方向的最终签名, 以当前语法规则为准。

不做:

- 不做任意 union 自动序列化。
- 不做循环引用。
- 不做流式 parser。
- 不做容错 JSON 方言。

拆分:

- [x] C1.1 盘点现有 JSON fixture 和 skip 原因。
- [x] C1.2 固定 `stringify` 支持矩阵和错误边界。
- [x] C1.3 固定 `from_json` 支持矩阵和错误边界。
- [x] C1.4 为 struct 字段、嵌套字段、默认字段补正例。
- [x] C1.5 为不支持类型补反例和诊断。
- [x] C1.6 同步 `src/json.do`、相关核心声明和文档。

验收:

- `tool/build/test/ok/133_*` 到后续 JSON fixture 延伸通过。
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`

### C2. 字段反射 API 收口

范围:

- 固定 `fields(Type)`。
- 固定 `@field_name(field)`、`@field_index(field)`、`@field_has_default(field)`、`@field_get(target, field)`、`@field_set(target, field, value)`。
- 字段类型选择依靠 `@field_get(...)` 在编译期展开后的静态结果触发重载分派。
- v1 不提供 `@field_type`、`@field_default_value` 或 `@field_default_type`; 只有被 JSON 或序列化证明必要时, 再单独重新评估默认值相关 API。

不做:

- 不做运行时反射对象逃逸。
- 不做动态字段名 set/get。
- 不把 field 设计成任意可变运行时对象。

拆分:

- [x] C2.1 固定 Field 的编译期/运行期边界。
- [x] C2.2 固定 `@field_get(target, field)` 的静态展开、重载分派和异构字段接收边界。
- [x] C2.3 固定 `@field_set(target, field, value)` 的同名自赋值 lowering 和类型约束。
- [x] C2.4 用 JSON fixture 验证 field API 足够表达序列化。
- [x] C2.5 同步 spec_rules、syntax/struct 和测试。

验收:

- struct reflection fixture 通过。
- JSON fixture 通过。
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`

### C3. bytes / text 边界

范围:

- UTF-8 校验。
- bytes_of / text_from。
- 长度、切片、空值和错误边界。
- 明确 `[T]` 作为不可变底层 array 的规则是否已被当前语义完全覆盖。

不做:

- 不做 Unicode grapheme。
- 不做 locale。
- 不做 regex。

拆分:

- [x] C3.1 盘点 `src/bytes.do` 和 `src/text.do` 当前 shape 与测试。
- [x] C3.2 补 bytes/text 转换正例。
- [x] C3.3 补非法 UTF-8 或非法转换反例。
- [x] C3.4 同步 spec_rules 和 syntax/type。

验收:

- 对应 ok/err/compiled_ok fixture 通过。
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`

### C4. list / set / hash_map 常用操作从 skip 收回

范围:

- 对当前 skip 的集合 fixture 分批处理。
- 先覆盖静态类型和 API 形态, 再覆盖 compiled execution。

不做:

- 不做高性能 hash table 优化。
- 不做复杂 iterator trait。

拆分:

- [x] C4.1 输出 skip 分类: 语法缺口、sema 缺口、codegen 缺口、runtime 缺口。
- [x] C4.2 先收回 List 基础操作。
- [x] C4.3 再收回 Set 基础操作。
- [x] C4.4 再收回 HashMap 基础操作。
- [x] C4.5 更新 NoTestDecl 或 skip 原因。

验收:

- skip 数减少或每个剩余 skip 有原因。
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`

### C5. math / encoding / hash 基础库一致性

范围:

- md5 / sha / base64 / hex / binary / path / url 的可执行子集。
- 固定公开函数签名和错误类型。

不做:

- 不做加密安全承诺。
- 不做完整 URL 标准兼容。
- 不做 host 依赖。

拆分:

- [x] C5.1 盘点 `src/*.do` 中只有 shape 没有测试的文件。
- [x] C5.2 为纯函数库补 `do test` fixture。
- [x] C5.3 为需要 codegen / imported helper 链支持的库补 compiled fixture。
- [x] C5.4 README 或 spec_rules 只记录稳定公开边界。

验收:

- 对应 `src/*.do` 有实际 test fixture 或 compiled fixture。
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`

阶段 C 完成标准:

- JSON 覆盖普通 struct 序列化和反序列化。
- field reflection API 足够支撑序列化。
- `src/*.do` 核心基础库不再只是 shape。
- `NoTestDecl` 标准库文件减少, 剩余项有明确原因。

## 6. 阶段 D: ARC / Ownership / FBIP 深化

目标: 在不改变源码值语义的前提下, 把内存管理从当前保守子集推进到可解释、可优化、可回归的 ownership pipeline。

### D1. ownership facts 统一入口

范围:

- 把 last-use、loop-carried、field-read、escape 信息整理为一个内部 facts 模块。
- 让 codegen 消费 facts, 而不是在多个局部重复推断。

不做:

- 不一次性重写 codegen。
- 不改变当前保守行为。

拆分:

- [x] D1.1 盘点当前 last-use / move 判断分散点。
- [x] D1.2 设计 `ownership_facts` 数据结构。
- [x] D1.3 把一个现有判断迁移到 facts。
- [x] D1.4 用现有 ARC fixture 锁住 WAT 不回退。

验收:

- focused Zig tests。
- existing compile_ok / compiled_ok ARC 子集通过。

### D2. 跨 block data-flow 最小版

范围:

- if/else、guard return、fallthrough、break/continue 的 managed local liveness。
- 只在函数内分析。

不做:

- 不做跨函数。
- 不做全局 escape analysis。

拆分:

- [x] D2.1 为 if/else 两边不同使用路径补红灯 fixture。未找到真实红灯缺口, 已经用户确认按 B 方案绿色 regression 收口到 compile_ok `239` 到 `241`。
- [x] D2.2 为 guard return 后续路径补红灯 fixture。
- [x] D2.3 实现函数内 data-flow 最小 pass。
- [x] D2.4 回归 ARC WAT pattern 和 compiled execution。

验收:

- 新增 compile_ok / compiled_ok 通过。
- `RUN_WASM=1 SKIP_BUILD=1 ./tool/build/test/run_tests.sh`

### D3. 字段读取 move 扩展

状态: done

范围:

- 只对 fresh owner / 唯一 owner 可证明场景放开。
- helper/shared-source 字段读取继续保守。
- 当前 D3 剩余目标是把已有 codegen-local field-get 决策迁移到 `ownership_facts`, 不重复实现旧 `03.5/03.6` 字段读取 move 能力。

不做:

- 不按语法末次使用直接放开。
- 不对 borrowed / shared source move。

拆分:

- [x] D3.0 对齐当前 D3 计划与历史字段读取 move 实现, 明确哪些小项已由旧 03.5/03.6 满足, 哪些仍需要迁移到 `ownership_facts`。
- [x] D3.1 补 fresh owner 字段读取可 move 正例。已有 compile_ok `202`、`204`、`207`、`210` 和 compiled_ok `39` 到 `42` 覆盖。
- [x] D3.2 补 shared source 字段读取必须 copy 反例。已有 compile_ok `206`、`213`、`214`、`215` 覆盖参数、helper/shared-source、loop-carried source 和同语句多字段读取拒绝边界。
- [x] D3.3 在 facts 中表达 source ownership。
- [x] D3.4 codegen 根据 facts 选择 move / copy。

验收:

- ARC WAT pattern。
- compiled execution。
- full regression。

### D4. 函数参数 ownership contract

范围:

- 明确参数默认可变性。
- 明确消耗 / 借用 / 返回 ownership 边界。
- 与当前“函数参数可重新赋值”的决定保持一致。

不做:

- 不引入用户可见 borrow 语法。
- 不引入复杂 lifetime 标注。

拆分:

- [x] D4.1 审查当前参数赋值和 call lowering 行为。
- [x] D4.2 在 `doc/spec_rules.md` 固定参数 ownership 规则。
- [x] D4.3 补参数 move/copy 正反例。
- [x] D4.4 同步 codegen tests。

验收:

- spec_rules + codegen tests。
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`

### D5. FBIP reuse 第一版

范围:

- `rc == 1` 的 storage / managed struct update 原地复用。
- 失败时保守回退 COW。

不做:

- 不做全局 escape analysis。
- 不做跨函数唯一性证明。

拆分:

- [x] D5.1 固定 reuse eligibility 规则。
- [x] D5.2 补 `rc == 1` 可 reuse WAT pattern。
- [x] D5.3 补 `rc > 1` 必须 COW 反例。
- [x] D5.4 实现最小 helper 和 lowering。
- [x] D5.5 补 trap smoke。

验收:

- WAT helper 调用。
- compiled behavior。
- ARC trap smoke。

阶段 D 完成标准:

- `doc/memory.md` ownership 章节与实现一致。
- 每类优化都有保守回退和反例测试。
- 不因优化改变源码值语义。

## 7. 阶段 E: 后端 IR 和 codegen 稳定化

目标: 降低 WAT 字符串 codegen 的复杂度, 为优化和未来 binary/component 输出留边界。

### E1. 扩展 backend IR 到当前标量表达式

范围:

- locals、constants、numeric op、comparison、branch、return。

不做:

- 不全量替换 codegen。
- 不接 managed storage。

拆分:

- [x] E1.1 扩展 `tool/build/backend_ir.zig` 指令集合。
- [x] E1.2 补 IR builder 单元测试。
- [x] E1.3 补 WAT emitter 单元测试或 fixture。

验收:

- `cd tool && zig test build/backend_ir.zig`

### E2. 一个小型 compiled_ok 走 IR lowering

范围:

- 选择一个标量 start 或 compiled test。
- 用 feature gate 或窄入口接入 IR lowering。

不做:

- 不迁移 managed storage。
- 不改变现有 `.expect`。

拆分:

- [x] E2.1 选定最小 compiled_ok case。
- [x] E2.2 新增 IR lowering 路径。
- [x] E2.3 对比 WAT 输出和执行结果。

验收:

- 目标 fixture 通过。
- full regression 通过。

### E3. IR peephole 扩展

范围:

- redundant local copy。
- const fold。
- trivial call inline。

不做:

- 不做跨函数复杂内联。
- 不做循环优化。

拆分:

- [x] E3.1 为 const fold 补 IR test。
- [x] E3.2 为 local copy fold 补 IR test。
- [x] E3.3 为 trivial call inline 补 IR test。
- [x] E3.4 如已接入 E2, 增加 WAT pattern 验证。

验收:

- backend_ir tests。
- WAT pattern。

### E4. WAT emitter 边界清理

范围:

- 把 runtime prelude、function body、component metadata 输出分段。
- 降低 `tool/build/codegen.zig` 单点复杂度。

不做:

- 不做 direct wasm binary emitter。
- 不改变公开 WAT 输出语义。

拆分:

- [x] E4.1 盘点 codegen 输出片段边界。
- [x] E4.2 抽出 runtime prelude writer。
- [x] E4.3 抽出 function body writer。
- [x] E4.4 抽出 component metadata writer。
- [x] E4.5 full regression。

验收:

- full regression。
- diff 不包含无关重排。

### E5. direct wasm binary emitter 重新评估

范围:

- 只做决策文档。
- 前置是 E1-E4 完成后再评估。

拆分:

- [x] E5.1 评估继续 WAT 的成本。
- [x] E5.2 评估 direct binary emitter 的收益和测试代价。
- [x] E5.3 给出继续保留、实验性引入或正式引入的推荐。

验收:

- 决策记录落地。
- 不默认实现。

阶段 E 完成标准:

- codegen 复杂度有可见下降。
- IR 有实际 lowering 使用点。
- WAT 文本仍是稳定公开输出, 除非另立项。

## 8. 阶段 F: LSP 编辑器体验升级

目标: 把 diagnostics / formatting / semantic tokens 之后的 LSP 做到可日常编辑。

前置:

- 如果 A1 已完成, F 不再重复 document formatting。
- 如果 A2 已完成, F 不再重复 semantic tokens。

### F1. hover 最小版

范围:

- 对当前文件内顶层函数声明和函数调用回查返回基础签名。

不做:

- 不做文档注释。
- 不做跨模块深度搜索。
- 不做类型、字段、局部绑定 hover。

拆分:

- [x] F1.1 设计 hover 内容格式。
- [x] F1.2 新增 hover fixture。
- [x] F1.3 接入当前文件 symbol lookup。
- [x] F1.4 同步 README 和 roadmap。

验收:

- LSP hover fixture。
- full regression。

### F2. completion 最小版

范围:

- 当前文件内可见类型名、函数名和字段段候选。

不做:

- 不做排序打分。
- 不做 snippet。
- 不做 workspace index。
- 不做局部绑定 completion。

拆分:

- [x] F2.1 completion item 编码测试。
- [x] F2.2 当前文件 symbol collection。
- [x] F2.3 字段 completion 最小支持。
- [x] F2.4 fixture 回归。

验收:

- LSP completion fixture。
- full regression。

### F3. go-to definition 最小版

范围:

- 当前文件顶层类型 / 函数。

不做:

- 不做 workspace index。
- 不做 imported module 深跳转。
- 不做字段 / 局部绑定 definition。

拆分:

- [x] F3.1 location 编码测试。
- [x] F3.2 symbol span collection。
- [x] F3.3 definition fixture。

验收:

- LSP definition fixture。
- full regression。

### F4. workspace index 第一版

范围:

- 打开 workspace 后索引 `.do` 文件的 top-level symbols。

不做:

- 不做增量 file watcher。
- 不做项目包管理。

拆分:

- [x] F4.1 定义 workspace root 输入。
- [x] F4.2 扫描 `.do` 文件 top-level symbols。
- [x] F4.3 completion / definition 复用 index。
- [x] F4.4 多文件 LSP fixture。

验收:

- 多文件 fixture。
- full regression。

### F5. rename 评估

范围:

- 只评估是否进入 v1。
- 若没有可靠 symbol index, 不实现。

拆分:

- [x] F5.1 列出 rename 误改风险。
- [x] F5.2 给出 v1 是否支持的推荐。

验收:

- 决策记录落地。

阶段 F 完成标准:

- 编辑器只需启动 `do lsp` 即可获得 diagnostics、formatting、semantic tokens、hover、completion 和基础导航。
- LSP fixture 覆盖常用请求。

## 9. 阶段 G: WASI / Component Model 最后处理

目标: 在主线稳定后, 完整处理 host ABI、component lowering、resource 和 result-area。

### G1. binding source / alias 规则冻结

范围:

- `@wasi` source、alias、module scoped identity。
- 与 manifest registry 一致。

拆分:

- [x] G1.1 审查 `doc/wit/wasi_p3_lowering.md` 与实现。
- [x] G1.2 审查 `doc/wit/wasi_registry.json` 与 manifest tool。
- [x] G1.3 补 alias 正反例。

验收:

- manifest tool。
- compile_ok。

### G2. result-area lowering 完整化

范围:

- 已登记 WASI result 子集。
- component plan / core imports / core shims 一致。

不做:

- 不做 future / stream async。

拆分:

- [x] G2.1 盘点已登记 result target。
- [x] G2.2 补 result-area lowering fixture。
- [x] G2.3 补 component plan/core shims 验证。

验收:

- component plan / core imports / core shims。
- full regression。

### G3. resource lifecycle

范围:

- descriptor / input-stream / output-stream 资源句柄表达与 wrapper 边界。
- file / dir 先保留显式 close；stream 当前只保留 read/check_write/write/flush wrapper，不提供 close_stream。
- 明确资源不是 ARC GC 对象。

不做:

- 不做自动 GC。
- 不做隐式 host resource drop。
- 不提前引入未登记的 stream close/drop 语义。

拆分:

- [x] G3.1 固定 resource handle 表达。
- [x] G3.2 固定 close/drop 错误边界。
- [x] G3.3 std wrapper compiled_ok。

验收:

- std wrapper compiled_ok。
- full regression。

### G4. variant / flags / list<record> 支持评估

范围:

- 针对当前 WASI registry 中需要的类型逐项评估。

拆分:

- [x] G4.1 variant 支持评估。
- [x] G4.2 flags 支持评估。
- [x] G4.3 list<record> 支持评估。
- [x] G4.4 输出最小实现计划或明确后置。

验收:

- 分项决策和最小实现计划。

### G5. component builder 输入到真实 component wasm

范围:

- 从现有 component input dir 生成验证通过的 component wasm。

拆分:

- [x] G5.1 固定本机工具链要求。
- [x] G5.2 生成 component wasm。
- [x] G5.3 `wasm-tools validate`。
- [x] G5.4 接入可选回归 gate。

验收:

- `wasm-tools component embed`, `wasm-tools component new` 和顶层 `wasm-tools validate`。

### G6. 后置复杂 WIT 类型分批展开

范围:

- G5 已证明真实 component wasm 路径后, 按依赖顺序扩展复杂 WIT 类型。
- 每一项先设计公开 wrapper 和 ownership 边界, 再决定是否落地 codegen。

拆分:

- [ ] G6.1 preopens `list<tuple<descriptor,string>>` / wrapper struct 设计。blocked, 需要用户确认公开 API。
- [ ] G6.2 `descriptor.read-directory` stream/future 设计。blocked, 当前语言/运行时没有 async / Future / Task 支持, 需要未来 async/Future runtime 与 resource stream 设计。
- [ ] G6.3 sockets resource + variant 设计。blocked, 需要 socket resource wrapper 和 address variant 映射决策。
- [x] G6.4 public flags API 是否需要公开。

验收:

- 每项都有 registry 证据、公开 API 边界、测试计划和明确做/不做结论。

阶段 G 完成标准:

- `doc/wit/wasi_p3_lowering.md` 与实现一致。
- WASI 不再只是 manifest/plan, 而能覆盖最小真实 component path。

## 10. 阶段 H: 发布前治理

目标: 在宣布 v1 前, 清理债务、固定版本边界、提高回归可信度。

### H1. skip 用例审计

范围:

- 所有 skip fixture 分类。
- 标注保留、转 pass、删除。

拆分:

- [x] H1.1 输出 skip 列表。
- [x] H1.2 按语法、sema、codegen、runtime、外部工具分类。
- [x] H1.3 选择一批低风险 skip 转 pass。
- [x] H1.4 为剩余 skip 写原因。

验收:

- skip 数减少或每个 skip 有原因。
- full regression。

### H2. 文档死链和过期规则扫描

范围:

- README、CHANGELOG.md、doc。

拆分:

- [x] H2.1 扫描 markdown 链接。
- [x] H2.2 扫描过期入口、过期规则和删除文件引用。
- [x] H2.3 修正或删除过期文档。

验收:

- `rg` 检查过期入口、过期规则、删除文件引用。
- `git diff --check -- README.md CHANGELOG.md doc`

### H3. 错误诊断一致性审查

范围:

- `tool/build/diag.zig`。
- `.expect` 诊断片段。
- parser / sema / imports 的错误格式。

拆分:

- [x] H3.1 列出错误 code 和 message。
- [x] H3.2 找出同类错误不一致的地方。
- [x] H3.3 修正实现或 `.expect`。
- [x] H3.4 full regression。

验收:

- err / compile_err 全量通过。

### H4. release smoke

范围:

- ReleaseSmall build。
- sample app build/test/check/fmt/run/lsp smoke。

当前选定输入:

- build: `tool/build/test/compile_ok/01_start_entry_valid.do`。
- test: `tool/build/test/ok/01_path_get_single.do`。
- compiled test: `tool/build/test/compiled_ok/01_compiled_test_entry.do`。
- check: `tool/build/test/check/01_valid.do`。
- fmt: `tool/build/test/fmt/01_struct_func_indent.do` 与同名 `.expect`。
- run: `tool/build/test/run/01_start_scalar.do`。
- lsp: `tool/build/test/lsp/*.json`。

拆分:

- [x] H4.1 确定 smoke 输入文件。
- [x] H4.2 新增 release smoke script 或文档化命令。
- [x] H4.3 在本机执行并记录结果。

验收:

- Debug 和 ReleaseSmall 都可构建。
- smoke 通过。

### H5. 版本说明

范围:

- README v1 boundary。
- 已知非目标。
- 下一阶段计划。

拆分:

- [x] H5.1 汇总已完成能力。
- [x] H5.2 汇总 v1 非目标。
- [x] H5.3 写下一阶段计划。

验收:

- README 和 roadmap_status 一致。

阶段 H 完成标准:

- Debug 和 ReleaseSmall 都可构建。
- full regression 和 smoke 都通过。
- 文档、代码、测试没有明显双源冲突。

## 11. 阶段 I: 后续语言能力扩展

状态: done

目标: 在 v1 子集发布候选稳定后, 分批补齐两个高价值语言能力: 递归 / self-tail TCO, 以及源码层 `Tuple<...>` 类型语法。阶段 I 不解除 G6.1-G6.3 的 WASI/API 阻断, 也不默认重开 get / pkg / push 或 direct wasm binary emitter。

### I1. 递归与 self-tail TCO

评估:

- 递归本身是语言表达力缺口, 对 JSON、树、解析器和递归数据处理都直接有价值。
- 风险集中在函数解析 / 重载候选 / 泛型实例化 / codegen 调用图 / ARC cleanup。不能只让 parser 接受自调用就宣布支持。
- TCO 推荐先做 self-tail call lowering 到 `loop`, 不依赖 Wasm tail-call proposal。这样输出仍是当前 WAT 主路径, 也不要求运行时或宿主支持新特性。
- 第一版不做 mutual TCO、general TCO、闭包递归或跨模块泛型递归展开。泛型递归必须有明确的实例化上限或诊断, 防止无限 monomorphization。
- Tail position 先限定为 `return f(args)` 和所有分支都以同一 self-tail call 结束的简单形态。带 `defer`、managed local、ARC release 或多返回的场景必须先有单独回归证明 cleanup 顺序正确。

推荐方案:

- 先支持直接递归和互递归的普通函数调用解析 / sema / codegen。
- 再支持 self-tail recursion 优化, 把 `return f(new_args)` 降成参数重赋值 + loop continue。
- 递归支持和 TCO 分开验收: 递归正确性先过, TCO 只改变可证明的尾递归 WAT pattern。

拆分:

- [x] I1.1 盘点当前递归行为。结论: 普通直接递归和互递归当前已能走通 compiled WAT/wasm 路径; 参数侧已定型的泛型递归当前可执行, 仅靠左侧目标类型反推的形态仍报 `NoMatchingCall`; 递归未命中 overload 已补 compiled_err 负例。
- [x] I1.2 固定递归语义规则。`doc/spec_rules.md` 已固定普通直接/互递归、递归未命中 overload 报 `NoMatchingCall`、参数侧已知 concrete type 的泛型递归可执行, 以及“只靠左侧目标类型反推 direct type param”当前仍拒绝的边界; 本 slice 不引入新语法, `doc/grammar.peg` 无需变更。
- [x] I1.3 落地递归调用支持。已补 `compiled_ok/53`–`57`、`ok/182`–`187` 和 `compile_ok/242`–`245` 回归, 覆盖递归求和、互递归奇偶判断、递归错误分支、`start()` build lowering、参数侧已定型的泛型递归、factorial、`if/else` 分支递归和 imported recursion; 已登记递归静态 runner 矩阵已收口。**后置**: 更复杂 control-flow / aggregate 递归形态。
- [x] I1.4 落地 self-tail TCO 第一版。已补 `compile_ok/246`/`247`/`252`/`254`/`255`/`257`/`258`、`compiled_ok/58`–`64`、`ok/188`/`189`, 覆盖 scalar、`if/else`、guard、generic、imported 及 generic/imported `if/else` self-tail path 的 loop lowering。**后置**: 更复杂 cleanup/aggregate self-tail。
- [x] I1.5 扩展 TCO 边界或明确后置。已补 `compile_ok/248`–`251`/`253`/`256` 六条边界回归, 固定 `defer`、storage local、managed struct、多返回、`if/else+defer`、guard+defer 的“不优化”策略; 更激进放开前保持保守。
- [x] I1.6 同步 README、语法文档、测试说明和回归摘要。README、`tool/build/test/README.md`、`doc/start_here.md`、`doc/roadmap_status.md` 和 `CHANGELOG.md` 已对齐阶段 I 回归矩阵; 递归 / self-tail TCO 不引入新语法。

验收:

- `cd tool && zig test main.zig`
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`
- 针对 TCO 的 `compile_ok` WAT pattern 明确区分 optimized self-tail 与 non-tail call。

### I2. `Tuple<bool, u8>` 源码层 Tuple 类型

评估:

- 当前源码层没有 Tuple 类型; 只有 `@wasi` host 签名里的小写 `tuple<...>` WIT 类型。二者不能混用, 否则会把外部 ABI 类型泄漏到普通 do 源码。
- 不推荐用 `(bool, u8)` 作为类型语法, 因为当前括号已经用于函数类型参数、函数调用、表达式分组和多返回语境, 容易引入歧义。
- 不推荐第一版支持裸 `(true, 7)` tuple literal, 因为它会和多返回表达式、调用实参列表、return list 的心智模型冲突。
- 推荐 `Tuple<T0, T1, ...>` 作为源码层大写内建泛型类型, 例如 `Tuple<bool, u8>`。大写 `Tuple` 与 WIT 小写 `tuple<...>` 大小写区分, 也符合当前命名类型 / 泛型类型参数写法。
- 第一版建议固定 2 个及以上元素, 构造使用类型化位置构造器: `Tuple<bool, u8>{flag, code}`。读取使用数字位置索引: `@get(pair, 0)` / `@get(pair, 1)`。不支持 `Tuple<bool, u8>{v0 = flag, v1 = code}` 这种命名字段构造, 也不支持 `.v0/.v1` 字段段访问。
- 代价是需要把 `Tuple` 设为保留类型名或内建类型名。若用户已有 `Tuple` 结构体, 后续实现必须给出明确冲突诊断。

推荐方案:

- 先做类型和构造器, 不做 tuple literal、destructuring、pattern matching 或匿名字段名。
- 作为编译器内建泛型 record lower 到现有 struct-like layout, 复用字段访问、ARC、storage 和 type args 规则。
- 与多返回保持边界: 多返回仍是函数 ABI / return list; `Tuple<A, B>` 是单个值。

示例:

```do
make_pair(flag bool, code u8) -> Tuple<bool, u8> {
    return Tuple<bool, u8>{flag, code}
}

test "tuple pair" {
    pair Tuple<bool, u8> = make_pair(true, 7)
    ok bool = @get(pair, 0)
    code u8 = @get(pair, 1)
    return
}
```

拆分:

- [x] I2.1 固定 `Tuple` 规格。第一版固定为源码层大写内建泛型类型 `Tuple<T0, T1, ...>`: arity 下限为 2, 当前不设上限; 允许嵌套 `Tuple<Tuple<i32, bool>, u8>`; 允许作为单值类型出现在局部绑定、参数、单返回、struct 字段、`[Tuple<...>]` storage 元素和 union 分支。构造固定为按类型参数顺序的位置构造器 `Tuple<T0, T1, ...>{v0, v1, ...}`，实参数量必须与 arity 完全一致; 第一版不支持命名字段构造。读取固定为 `@get(tuple_value, <index>)`，其中 `<index>` 必须是编译期整数字面量，范围是 `0..arity-1`; 第一版不支持 `.v0/.v1` 字段段访问，也不支持 `@set(tuple_value, <index>, value)` 数字索引写入。`Tuple` 作为用户可写源码类型名进入保留内建类型集合，不能再被普通类型声明或 import alias 占用; 小写 `tuple<...>` 继续只保留给 WIT / `@wasi` 签名，不进入普通源码类型位。
- [x] I2.2 更新 grammar / parser。`Tuple<...>` 已通过现有大写类型名 + type args 路径进入 `ValueTypeExpr`、`InlineValueTypeExpr`、`ParamTypeExpr` 和 type args；parser 额外接受 `Tuple<bool, u8>{true, 7}` 这类位置构造器语法，并在 typed bind 左侧把小写 `tuple<bool, u8>` 拒绝为 `InvalidTypeRef`。`doc/grammar.peg` 已同步 `TupleCtor` / `TupleAggBody`; 本项只保证 parser 层接受该语法, 不代表 sema/codegen 已经理解 `Tuple` 构造与访问语义。
- [x] I2.3 更新 sema。`checkTupleCtorArity` / `checkTupleGetIndex` 已落地: 位置构造 arity (含嵌套) 与明显字面量类型不匹配报 `InvalidTypedLiteral`; 越界/非字面量索引报 `InvalidPathIndex`; arity 下限与小写 `tuple` 报 `InvalidTypeRef`; 命名字段由 parser 报 `InvalidStructLiteral`; 尾逗号不计入 arity。
- [x] I2.4 更新 codegen。已完成 local/struct/return/param multi-value、嵌套叶子 ABI 展平与标量叶子 `[Tuple<...>]` storage 内联 pack (scheme A): `compile_ok/259`–`268`、`compiled_ok/65`–`73`。**后置阻断**: managed payload 叶子 storage (`[Tuple<Point, u8>]` / `[Tuple<text, u8>]`)、`@get(storage, i, j)` path chaining、loop 绑定上的 `@get(v, N)` 数字索引读取 (当前均 `NoMatchingCall`)。
- [x] I2.5 补正反例回归。正例: `compile_ok/259`–`268`、`compiled_ok/65`–`73` (静态 runner 不解释 `Tuple`)。反例: `err/330`、`compile_err/331`–`338`、`err/334`。
- [x] I2.6 同步 README、`doc/syntax/type.md`、`doc/spec_rules.md`、`doc/grammar.peg` 和测试说明。阶段 I 关闭; 后置边界记入 `doc/roadmap_status.md`。

验收:

- `cd tool && zig test main.zig`
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`
- Tuple 正反例必须同时覆盖 `do test`、`do build` WAT pattern 和错误诊断。

## 12. 当前下一步

当前状态:

1. 阶段 H 已完成最终验证; 当前无新的未记录阻断。
2. D2.1 已按用户确认的 B 方案绿色 regression 收口, 阶段 D 当前无剩余 blocked 残留。
3. G6.1/G6.3 仍等待用户决策; G6.2 因当前无 async/Future runtime 暂时阻断, 不在未确认 API/运行时边界前扩 codegen。
4. 阶段 I 已完成 (I1 递归/self-tail TCO + I2 `Tuple<...>` 第一版); 后置边界见 `doc/roadmap_status.md`。下一阶段默认回到 G6 决策项或发布候选回归维护。

推荐理由:

- 阶段 B 已把 grammar / parser、spec_rules / sema、语法文档治理和语法冻结回归包全部收口。
- C1.1 已确认现有 JSON fixture 和 skip 边界; C1.2 已固定 stringify 支持矩阵; C1.3 已固定 from_json struct-root 支持矩阵和错误边界; C1.4 已补 struct/nested/default 正例; C1.5 已补不支持类型反例和诊断; C1.6 已完成 JSON 源码、core 声明和文档一致性核查。
- C1 是当前标准库最靠近用户价值的能力, 也会反向验证字段反射和类型边界。
- C2.1 已固定 Field 元数据只存在于编译期字段反射循环内, 不能作为普通值绑定、传参或逃逸; C2.2 已固定 `@field_get` 的静态展开、重载分派和异构字段接收边界; C2.3 已固定 `@field_set` 的同名自赋值 lowering 和类型约束; C2.4 已用 JSON compiled fixture 验证 field API 足够表达当前序列化/反序列化路径; C2.5 已完成字段反射规则和测试说明同步。
- C3.1 已盘点 bytes/text 的公开 API、UTF-8 边界和测试矩阵; C3.2 已把 `ok/121_source_text_type.do` 升级为 compiled bytes/text 转换正例; C3.3 已把 `ok/98_utf_lib.do` 升级为 compiled UTF-8/UTF-16 正反例并补 union storage payload lowering 回归; C3.4 已同步 `spec_rules` 和 `syntax/type` 的 bytes/text/utf8/utf16 规则。
- C4.1 已确认当前集合 skip 没有 parser/语法缺口, `do check` 全部通过; C4.2 已把 `49_list_storage_items`、`56_list_del`、`65_list_add_variadic` 固定为 compiled 必过用例并从 skip 收回; C4.3 已把 `113_set_common_ops` 固定为 compiled 必过用例并收回; C4.4 已把 `36_hash_map_lib_ops`、`37_hash_map_set_missing_key`、`57_hash_map_del`、`115_hash_map_common_wrappers` 固定为 compiled 必过用例并收回; C4.5 已收回 8 个漏网 compiled 可执行用例, 并更新剩余 skip / NoTestDecl 分类。C5.1 已完成 `src/*.do` 覆盖盘点; C5.2 已为 `binary.do`、`path.do` 非 variadic helper、`url.do` encode 子集、`range.do`、`slice.do` 访问 helper、`bytes.do` sequence helper 和 `hex.do` encode 子集补 executable fixture; C5.3 已完成基础库 executable/compiled fixture 收口; C5.4 已把 README/spec_rules 收窄到当前稳定公开边界。H1.3 已把标准库源码 `NoTestDecl` 从 skip 改为 metadata-only pass, H1.4 已为剩余 3 个 skip 记录原因和恢复条件, H2.1 已确认当前 markdown 本地链接无缺失, H2.2 已发现 README Roadmap 状态漂移, H2.3 已修正 README 过期状态描述, H3.1 已列出 55 个显式诊断 code/message, H3.2/H3.3 已修复 `InvalidReturnStmt` summary/hint 不一致, H3.4 full regression 已通过, H4 release smoke 已通过, H5.1 已把当前 v1 已完成能力汇总到 README, H5.2 已把 v1 非目标单独汇总到 README, H5.3 已把下一阶段计划写入 README, 阶段 H 最终验证已通过, 当前默认完整回归为 `pass=874 fail=0 skip=3`; `RUN_WASM=1` 扩展回归为 `pass=833 fail=0 skip=3`; `16/96/118` 等 recv/WASI/resource wrapper 继续后置。阶段 C 已完成, D1-D5 可推进项已完成, D2.1 已按用户确认 B 方案绿色 regression 收口, E1-E5 已完成, 阶段 F 已完成到 rename 评估并决定 v1 不支持 rename; G1-G5 已完成; G6.1、G6.3 已按阻断记录等待用户决策; G6.2 因当前无 async/Future runtime 暂时阻断; G6.4 已完成 public flags API 决策。

执行方式:

- 用户说 `go` / `next` 时, 默认先检查是否有新的发布候选回归、文档漂移或可独立收口的小项。
- 完成任一子项后, 立即在 `doc/roadmap_status.md` 记录进度和验证。
- 若没有新的可独立收口小项, 不绕过当前阻断: G6.1/G6.3 需要用户决策; G6.2 需要未来 async/Future runtime 支持。
- 若阶段 D 暴露出需要用户决策的 ownership / ARC / FBIP 语义冲突, 先写入 `doc/roadmap_status.md` 的阻塞记录, 不直接扩大源码语法能力。
