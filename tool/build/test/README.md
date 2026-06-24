# do toolchain 回归测试

这个目录存放当前编译器/构建产物的黑盒回归测试，目录结构已按当前实现扁平化。
当前覆盖 `do build`、`do test`、第一版 `do check` 诊断命令、第一版 `do run` 产品命令、第一版 `do fmt` 产品命令和第一版 `do lsp` 产品命令; `do lsp` 现已覆盖 formatting 和 semantic tokens。

目录说明:

- `ok`: 当前实现已支持, 且期望 `do test` 成功的 `.do` 用例.
- `err`: 当前实现已支持, 且期望 `do test` 失败的 `.do` 用例.
- `err/*.expect`: 失败输出包含的关键文本(逐行匹配子串).
- `compile_ok`: 期望 `do build <input.do> -o out.wat` 成功的用例.
- `compile_err`: 期望 `do build <input.do> -o out.wat` 失败的用例.
- `compile_err/*.expect`: 编译失败输出包含的关键文本.
- `compile_ok` 中的 WASI binding manifest 约定: `;; wasi-bind source="entry" alias="name" target="package/interface/member" params="..." result="..."` 表示入口模块声明, `source="module-path"` 表示递归导入模块声明; 同名 alias 必须结合 source 判断身份. 含 `wasi-bind` 的 WAT 会额外通过 `validate_wasi_bind_manifest.mjs --registry doc/wit/wasi_registry.json` 检查字段格式、WIT 类型尖括号平衡、已知 target 的签名和 `source + alias` 唯一性; `--json` 模式会输出后续 BindingResolve 可消费的 `bindings[]`, 并为已知 scalar/record/list<u8> binding、`descriptor.sync` result-area binding、`descriptor.write` result-area binding、`descriptor.read` result-area binding、`descriptor.link-at` result-area binding、`descriptor.open-at` result-area binding、`descriptor.create-directory-at/remove-directory-at` result-area binding、`descriptor.drop` resource-drop binding、`input-stream.read` result-area binding 与 `output-stream.check-write/write/flush` result-area binding 生成 `shim.lowering` 计划; `descriptor.read-directory` 已知但因 `stream/future` 结果暂标记为 unsupported, `preopens.get-directories` 已知但因 `list<tuple<descriptor,string>>` 暂标记为 unsupported, `tcp-socket.create/bind` 与 `udp-socket.create/bind` 已知但因 WIT variant/resource 暂标记为 unsupported, `http/client.send` 已知但因 HTTP request/response resource 和 async result 暂标记为 unsupported; `--component-plan` 模式只接受全部已知且可 lower 的 binding, 输出后续 component builder 可消费的 `schema_version/imports/shims`; `--core-imports` 会从同一严格计划生成去重后的 `cm32p2` core import WAT 片段; `--core-shims` 会额外生成 per-alias core shim WAT 片段; `--component-input-dir <dir>` 会把 `core.wat`、`core_component.wat`、`component_plan.json`、`core_imports.wat`、`core_shims.wat` 和 `wit/` 聚合成后续 component builder 的单目录输入; `core_component.wat` 与 `do build --component-core` 输出都会移除普通 `memory` 导出, 只保留 component ABI 需要的 `cm32p2_memory` 导出.
- `compile_ok/*.component_plan.expect`: 可选的 WASI component-plan 期望文件; 存在时 `run_tests.sh` 会对该用例生成 `--component-plan` JSON, 并逐行匹配期望子串; 对单个 WIT package 的用例, 随后还会生成 `--wit` 输出, 在 `wasm-tools` 可用时用 `wasm-tools component wit` 解析验证. 只给全部 binding 都已知、可 lower 且当前 WIT emitter 能表达的用例添加这个文件; 当前已覆盖 clocks/random 这类普通函数以及 `descriptor.sync` / `descriptor.write` / `descriptor.read` / `descriptor.link-at` / `descriptor.open-at` / `descriptor.create-directory-at` / `descriptor.remove-directory-at` / `descriptor.drop` / `input-stream.read` / `output-stream.check-write` / `output-stream.write` / `output-stream.flush` resource method。
- `compile_ok/*.wit_dir.expect`: 可选的 WASI WIT package directory 期望文件; 存在时 `run_tests.sh` 会对该用例生成 `--wit-dir <tmp-dir>` 输出, 并在 `wasm-tools` 可用时用 `wasm-tools component wit <tmp-dir>` 解析验证, 再逐行匹配期望子串. 该文件用于跨多个 WIT package 的 manifest, 例如同时导入 `wasi:clocks` 和 `wasi:random` 时, 单文件 `--wit` 不能表达完整依赖图, 目录输出会生成 `world.wit` 和 `deps/<package>/<package>.wit`。
- `compile_ok/*.core_imports.expect`: 可选的 WASI core import 片段期望文件; 存在时 `run_tests.sh` 会对该用例生成 `--core-imports` WAT 片段, 并逐行匹配期望子串. 它锁定 component builder 后续要嵌入的 core import ABI; direct codegen 只支持已登记 scalar/record/list<u8> 子集、`descriptor.sync` 的 statement-position ignore / `_,status` 多左值读取、`descriptor.write` 的 statement-position ignore / `written,status` 多左值读取, `descriptor.read` 的 `data,done,status` 多左值读取, `descriptor.link-at` 的 direct string literal 或 Do `text` local/param path / `_,status` 多左值读取, `descriptor.open-at` 的 direct string literal 或 Do `text` local/param path / `descriptor,status` 多左值读取, `descriptor.create-directory-at/remove-directory-at` 的 Do `text` local/param path / `_,status` 多左值读取, `descriptor.drop` 的 resource-drop direct import, `input-stream.read` 的 `data,status` 多左值读取, 以及 `output-stream.check-write` 的 `allowed,status`、`output-stream.write/flush` 的 `_,status` 多左值读取, 不表示全部 `@wasi` 都可执行.
- `compile_ok/*.core_shims.expect`: 可选的 WASI core shim 片段期望文件; 存在时 `run_tests.sh` 会对该用例生成 `--core-shims` WAT 片段, 并逐行匹配期望子串. record-result shim 目前只转发 canonical ABI result-area 指针; Do record 返回桥接仍属于后续 codegen/component builder 工作.
- `compile_ok/*.component_input.expect`: 可选的 WASI component builder 输入目录期望文件; 存在时 `run_tests.sh` 会对该用例生成 `--component-input-dir <tmp-dir>` 输出, 逐行匹配 `metadata.json`、`component_plan.json`、`core_imports.wat`、`core_shims.wat` 和 WIT 目录解析结果中的关键文本. 在 `wasm-tools` 可用时, 还会解析 `wit/` 目录、把 `core_shims.wat` 包成临时 module 做 WAT parse, 并用 `core_component.wat` 执行 `wasm-tools component embed` -> `wasm-tools component new` -> `wasm-tools validate`。该目录本身仍只是 builder 输入, 真实 component wasm 是测试中从该目录派生出的验证产物。
- `compile_ok/*.component_core.expect`: 可选的 `do build --component-core` 期望文件; 存在时 `run_tests.sh` 会生成 component-ready core WAT, 确认它不再导出普通 `memory`, 并在同用例已有 component input gate 且 `wasm-tools` 可用时执行 `component embed` -> `component new` -> `validate`。这个模式仍输出 core WAT, 不直接写 `.component.wasm`。
- `compile_ok/104_*` 到 `124_*` 锁定当前 build 子集里 `ErrorEnum | nil` 的 `i32` 编码、非托管 struct 参数 flatten、资源构造用的 `UnmanagedStruct | ErrorEnum` 返回 flatten, `text` typed literal / 参数位 / 返回位的 ARC storage handle lowering, `file.do/write_file` 通过 `descriptor.write` result-area 多左值读取的标准库 wrapper lowering, `file.do/flush_file` 通过 `descriptor.sync` 的 `_,status` 读取的标准库 wrapper lowering, `file.do/read_file` 通过 `descriptor.read` result-area 多左值读取的标准库 wrapper lowering, `file.do/link_file` 通过 `descriptor.link-at` result-area 多左值读取的标准库 wrapper lowering, raw `descriptor.open-at` result-area 多左值读取, `file.do/open_file_at` 通过 `descriptor.open-at` 得到 `File | FileError` 的标准库 wrapper lowering, `file.do/close_file` 通过 `descriptor.drop` resource-drop core import 返回 `nil` 的标准库 wrapper lowering, `dir.do/open_dir_at` 通过 `descriptor.open-at` 得到 `Dir | DirError` 的标准库 wrapper lowering, `dir.do/close_dir` 通过 `descriptor.drop` resource-drop core import 返回 `nil` 的标准库 wrapper lowering, `dir.do/create_dir_at/remove_dir_at` 通过 `descriptor.create-directory-at/remove-directory-at` 得到 `DirError | nil` 的标准库 wrapper lowering, `io.stream.do/read_stream` 通过 `input-stream.read` result-area 多左值读取的标准库 wrapper lowering, 以及 `io.stream.do/check_write_stream/write_stream/flush_stream` 通过 `output-stream.check-write/write/flush` result-area 多左值读取的标准库 wrapper lowering；这不是任意 union、完整文本 runtime 或完整 WASI component 输出支持。
- 字段反射回归矩阵: `err/317` 到 `321` 覆盖 unknown/non-struct source、metadata 来源和 `@field_set` 同名自赋值要求; `err/324`、`325` 覆盖字段元数据不能作为普通值或普通实参逃逸; `compile_err/269`、`270` 覆盖具体 `@field_get` 的异构绑定和调用错配; `compile_err/271`、`272` 覆盖具体 `@field_set` 的异构写入和 guard 后 value 类型错配; `compile_ok/228` 覆盖 `@field_get` 触发具体重载分派; `compile_ok/229` 覆盖同构字段未 guard 写入; `ok/136`、`137`、`141`、`143` 到 `151` 的 JSON compiled fixture 覆盖 `src/json.do` 基于字段反射的 struct stringify/from_json 路径。
- `compiled_ok`: 期望 `do test <input.do> --compiled -o out.wat` 成功生成 compiled test WAT 的用例; 当前覆盖普通 block 函数调用、单表达式箭头函数调用、私有函数声明调用、单返回调用结果的标量推断绑定、导入函数调用、导入标量常量、导入标准库函数体内的本模块常量/helper 调用和 guard return. `RUN_WASM=1` 时会额外 parse, 并通过 `run_compiled_test_case.mjs` 逐个执行 `__test_N` export, 输出 `test "name" ... ok` 与汇总.
- `compiled_err`: 期望 `do test <input.do> --compiled -o out.wat` 失败的用例, 用于锁定 compiled runner 的 build/lowering 诊断.
- `compiled_trap`: 期望 compiled test WAT 可生成和 parse, 但执行 `__test_N` export 时触发 trap 的用例; 只在 `RUN_WASM=1` 下执行.
- `check`: 期望 `do check <input.do>...` 执行的黑盒用例; 无 `.expect` 时要求成功且 stdout/stderr 都为空, 有 `.expect` 时要求失败并逐行匹配 stderr 子串。`run_tests.sh` 还覆盖多输入全部成功、后一个失败、前一个失败后继续检查后续输入并最终失败。`do check` 只检查 lexer/parser/sema/import diagnostics, 不编译、不运行、不要求 `start()` 或 `test` 声明。
- `run`: 期望 `do run <input.do>` 成功执行的黑盒 smoke 用例; 默认 `./tool/build/test/run_tests.sh` 会逐个运行这些用例, 若存在同名 `.stdout.expect` 则逐行对比 stdout, 并要求 stderr 为空。
- `fmt`: 期望 `do fmt <input.do>` 成功输出格式化结果的用例; 默认 `./tool/build/test/run_tests.sh` 会逐个运行这些用例, 若存在同名 `.expect` 则逐行对比 stdout, 并要求 stderr 为空。每个 `fmt` 用例还会复跑一次输出以校验 idempotence, 对同一输入执行 `do fmt --check` 校验格式化命中与 mismatch 诊断, 并用临时文件执行 `do fmt --write` 校验原地写回内容和幂等。
- `lsp/*.json`: JSON-RPC smoke fixtures, 由 `run_lsp_case.mjs` 执行。每个 fixture 会向 `bin/do lsp` 发送 framed LSP messages, 并检查 initialize response、publishDiagnostics、formatting response、semantic tokens response 或诊断清空输出。
- `run_wasm_smoke.sh`: 底层 WAT -> `wasm-tools parse` -> Node 执行桥接验证脚本, 只在 `RUN_WASM=1 ./tool/build/test/run_tests.sh` 或手动调用时执行; 它保留为桥接链路 smoke, 不替代产品命令 `do run` 回归。
- `run_tests.sh`: 编译 `tool` 下的编译器, 然后执行 `do test`、编译模式、`do check`、`do run`、`do fmt` 和 `do lsp` 黑盒用例.
- `do test` 输出约定: 每个测试打印 `test "name" ... ok`、`test "name" ... failed` 或 `test "name" ... skipped`; 最后打印汇总 `ok: N passed; 0 failed; M skipped` 或 `failed: N passed; F failed; M skipped`. 默认静态 runner 遇到未支持控制流、导入调用或复杂表达式时输出 `skipped`; 已支持断言确定失败或进入 `unknown` 时输出 `failed`. `ok/*.must_pass` 标记该同名 `.do` 用例不允许输出 skipped, 用于逐步收回静态 runner 已支持语义的旧 skip. `ok/*.compiled_must_pass` 标记该同名 `.do` 用例允许静态 runner skip, 但 `run_tests.sh` 必须通过 `do test --compiled` 生成 WAT、parse wasm 并执行 `__test_N` 通过。
- `do test --compiled` 输出约定: 生成 WAT 文件, 其中每个 `test "name" { ... }` 会写入 `;; compiled-test N "name"` manifest 注释, lower 成内部 `__test_N` 函数并导出同名 export, `_start` 仍依次调用它们; 测试体执行到 `return` 表示通过, 落到块末尾会触发 `unreachable`.

同步原则:

- 以 `doc/spec_rules.md` 第 7 章为准维护用例.
- 语法错误统一按 parser 诊断契约处理: 首个错误立即停止, 输出文件/行/列、源码位置和支持的正确语法示例.
- 可保留少量语法错误烟测, 只用于锁定诊断输出格式.

执行:

```bash
./tool/build/test/run_tests.sh
```

`run_tests.sh` 会调用 Node 执行 `test_wasi_bind_manifest_tool.mjs`, 并在遇到 WASI binding manifest 时执行 `validate_wasi_bind_manifest.mjs`; 因此当前完整回归需要可用的 `node`.
`do run` 用例还需要可用的 `wasm-tools` 和 `node`; 脚本会额外覆盖二者缺失时的 `error[MissingExternalTool]` 诊断。`do lsp` smoke 用例需要可用的 `node` 来驱动 JSON-RPC stdio。

可选:

- `ZIG_BIN=/path/to/zig ./tool/build/test/run_tests.sh`
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`
- `RUN_WASM=1 ./tool/build/test/run_tests.sh`
