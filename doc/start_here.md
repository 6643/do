# 下次启动入口

这是当前主线的接手入口。下次启动时, 先按这个顺序读:

1. [README.md](/home/_/._/do/README.md)
2. [CHANGELOG.md](/home/_/._/do/CHANGELOG.md)
3. [doc/master_plan.md](/home/_/._/do/doc/master_plan.md)
4. [doc/roadmap_status.md](/home/_/._/do/doc/roadmap_status.md)
5. [doc/memory.md](/home/_/._/do/doc/memory.md)

## 当前停点

- v1 子集发布候选已收口。
- 默认回归矩阵最近通过: `./tool/build/test/run_tests.sh`, 摘要 `pass=901 fail=0 skip=3`; 阶段 I (I1 递归/self-tail TCO + I2 `Tuple<...>`) 已关闭, 后置边界见下文与 `doc/roadmap_status.md`。

- 扩展回归最近通过: `RUN_WASM=1 SKIP_BUILD=1 ./tool/build/test/run_tests.sh`, 摘要 `pass=833 fail=0 skip=3`, `wasm run summary: pass=6 fail=0`; 最近一次复跑验证了 fixture rename 后的 RUN_WASM 路径和 compiled trap smoke, 本次复跑后的 `tool/build/test/tmp` ignored 产物已清理到 `0`。
- Release smoke 最近通过: `./tool/build/test/run_release_smoke.sh`, ReleaseSmall、build/test/compiled/check/fmt/run/lsp 全部 `[PASS]`, 输出 `[INFO] release smoke passed`; 本次 smoke 产生 `tool/build/test/tmp` ignored 产物 44 个、目录大小 `436K`, 已清理到生成物计数 `0`, 目录大小 `288K`。
- Repo-wide diff whitespace gate 最近通过: `git diff --check`。
- Markdown local link gate 最近通过: 只读扫描 `README.md`、`CHANGELOG.md` 和 `doc/**/*.md`, 输出 `markdown_files=26`, `local_markdown_links=20`, `missing=0`; 最近复跑后仍无文档死链。
- Active/blocker 状态口径 gate 最近通过: 剩余 `[ ]` 只指向 README 后置非目标、06.2 blocked/decomposed 和 G6.1-G6.3 blocked; `active/partial/blocked` 旧状态口径无输出; 最近复跑后仍无新的活跃任务漂移。
- Release candidate handoff boundary gate 最近通过: handoff 入口文件均存在; `doc/review_blockers.md`、`doc/review_issues.md`、`compiled_task_checklist.md`、`next_stage_plan.md` 和 `internal_prefix_rename_plan.md` 均不存在; Markdown 本地链接扫描 `markdown_files=26`, `local_markdown_links=20`, `missing=0`; dirty/UI 边界当前为 tracked `64`、untracked `135`, `ui.do` / `ui_demo.do` 只在 untracked。
- Test README matrix boundary gate 最近通过: `tool/build/test/README.md` 已覆盖当前 14 个顶层目录、8 个脚本/helper 文件、`lib` 专用导入根、`tmp` 生成目录和 `run_wasm_case.mjs` helper; `test_readme_dir_missing=0`, `test_readme_helper_missing=0`。
- Test tmp generated artifacts cleanup gate 最近通过: `tool/build/test/tmp` 除 tracked `.gitignore` 外已清空, 生成物计数为 `0`。
- README command matrix boundary gate 最近通过: README 构建示例已覆盖 `do test --compiled -o`, 对齐 `./bin/do` 当前 usage。
- README stdlib boundary matrix gate 最近通过: README 标准库边界已补齐 `atomic`、`path`、`md5/sha1/sha256`, 并明确 `time/random/file/dir/io.stream`、`net/tcp/udp/http.client`、`simd` 的当前边界。
- Zig fmt gate 最近通过: Zig `0.16.0`; `rg --files -g '*.zig' -0 | xargs -0 zig fmt --check` 通过, 当前全仓 Zig 文件数为 31, 其中 tracked `23`, untracked `8`。
- Zig aggregate unit gate 最近通过: Zig `0.16.0`; `cd tool && zig test main.zig` 为 101/101, 输出 `All 101 tests passed.`, 覆盖 CLI/run/fmt/check/LSP、backend/writer/ownership、lexer/parser/sema/diag 和 formatter 聚合单元测试。
- Zig Debug build gate 最近通过: Zig `0.16.0`; `cd tool && zig build -Doptimize=Debug` 成功。
- JS/MJS helper syntax gate 最近通过: Node `v24.18.0`; `node --check` 覆盖当前 6 个 tracked `.mjs` helper/runtime 脚本, 且无 untracked JS/MJS; 输出 `node_check_ok` 覆盖 `run_compiled_test_case.mjs`、`run_lsp_case.mjs`、`run_wasm_case.mjs`、`test_wasi_bind_manifest_tool.mjs`、`validate_wasi_bind_manifest.mjs` 和 `tool/run/run_wasm_program.mjs`。
- Shell harness syntax gate 最近通过: `bash -n` 覆盖 2 个 tracked `.sh` 脚本 `tool/build/test/run_tests.sh`、`tool/build/test/run_wasm_smoke.sh` 和 1 个 untracked `.sh` 脚本 `tool/build/test/run_release_smoke.sh`; 输出 `bash_n=pass`。
- Shell harness executable boundary gate 最近通过: 三个 shell harness 均有 bash shebang、`set -euo pipefail`、`bash -n` 通过且当前权限为 `775`; `run_release_smoke.sh` 仍是 untracked executable。
- LSP smoke fixture gate 最近通过: `tool/build/test/lsp/*.json` 共 9 个用例全部通过。
- do fmt fixture gate 最近通过: `tool/build/test/fmt/*.do` 共 3 个用例全部通过, 覆盖 stdout `.expect` 对比、幂等、`--check`、`--write` 和 `error[FormatMismatch]`。
- do run product command gate 最近通过: `tool/build/test/run/*.do` 共 6 个用例全部通过, 并覆盖缺失 `wasm-tools` / `node` 的 `error[MissingExternalTool]` 诊断。
- do check product command gate 最近通过: `tool/build/test/check/*.do` 共 2 个用例全部通过, 并覆盖多文件全部成功、后一个失败、前一个失败后继续检查后续输入。
- do build product command smoke gate 最近通过: `compile_ok/01_start_entry_valid.do` 成功生成非空 WAT (`32806` bytes), `compile_err/01_missing_start_entry.do` 失败并匹配 `.expect` 的 2 行诊断。
- do test product command smoke gate 最近通过: `ok/01_path_get_single.do` 静态测试通过, `compiled_ok/01_compiled_test_entry.do` 生成 `32924` bytes WAT / `5638` bytes wasm, 并通过 `wasm-tools parse` 和 Node runner 执行; `do test -o` 无 `--compiled` 返回 `OutputRequiresCompiledTest`。
- CLI argument / output path guard gate 最近通过: `build -o <out> <input>` 生成 `32806` bytes WAT, `test --compiled -o <out> <input>` 生成 `32924` bytes WAT; build/run 非法参数返回 `UnexpectedCliArg`, `test -o` 无 `--compiled` 返回 `OutputRequiresCompiledTest`。
- WASI bind manifest helper gate 最近通过: `node tool/build/test/test_wasi_bind_manifest_tool.mjs tool/build/test/validate_wasi_bind_manifest.mjs <tmp-dir>` 输出 `ok: wasi-bind manifest tool`, 自测临时目录生成 37 个文件; 这不解除 G6.1-G6.3 阻断。
- WASI component wasm generation / validate gate 最近通过: `96_wasi_manifest_module_scoped_alias` 生成 `34110` bytes WAT 和 `7893` bytes component wasm, `wasm-tools validate` 通过, 摘要 `component_wasm_96_wasi_manifest_module_scoped_alias=1`, `wasi_component_wasm_failures=0`; 这不解除 G6.1-G6.3 阻断。
- run_wasm_smoke bridge gate 最近通过: `SKIP_BUILD=1 ./tool/build/test/run_wasm_smoke.sh` 输出 `01_start_scalar` 到 `06_defer_loop_break` 共 6 个 wasm run `[PASS]`, 摘要 `wasm run summary: pass=6 fail=0`。
- compiled trap smoke gate 最近通过: `tool/build/test/compiled_trap/*.do` 共 2 个 fixture 均生成并 parse WAT 成功, Node compiled runner 执行均按预期非 0 trap。
- diagnostic unit / contract gate 最近通过: `cd tool && zig test build/diag.zig` 为 13/13, 输出 `All 13 tests passed.`; `errorSummary` / `errorHint` 显式条目均为 55 且互相无缺口。
- CLI parser unit gate 最近复验通过: `cd tool && zig test build/cli.zig` 为 14/14, 输出 `All 14 tests passed.`, 覆盖 run/fmt/lsp/check 参数解析; `doc/roadmap_status.md` 已补齐该 gate 的复验记录。
- lexer / tokenization unit gate 最近通过: `cd tool && zig test build/lexer.zig` 为 10/10, 覆盖 dot/private 标识符、spread、apostrophe、UTF-8 escape 和 line string tokenization。
- parser unit gate 最近复验通过: `cd tool && zig test build/parser.zig` 为 24/24, 输出 `All 24 tests passed.`, 覆盖 literal/lambda/spread/struct/import/variadic/collection loop parser 边界; 该 gate 同时执行 parser 导入的 lexer tests。
- sema unit gate 最近复验通过: `cd tool && zig test build/sema.zig` 为 26/26, 输出 `All 26 tests passed.`, 覆盖 private host import/private assignment 语义边界; 该 gate 同时执行 sema 导入链上的 lexer/parser tests。
- codegen unit gate 最近复验通过: `cd tool && zig test build/codegen.zig` 为 51/51, 输出 `All 51 tests passed.`, 覆盖 origin metadata、generic/variadic ABI、Backend IR、runtime prelude、component metadata、test runner 和 ownership facts。
- backend IR focused unit gate 最近复验通过: `cd tool && zig test build/backend_ir.zig` 为 13/13, 输出 `All 13 tests passed.`, 覆盖 block/value/emit/fold/inline 边界。
- runtime prelude WAT focused unit gate 最近复验通过: `cd tool && zig test build/runtime_prelude_wat.zig` 为 2/2, 输出 `All 2 tests passed.`, 覆盖 component core memory/data segment、runtime header 和 ARC layout table 输出边界。
- component metadata WAT focused unit gate 最近复验通过: `cd tool && zig test build/component_metadata_wat.zig` 为 4/4, 输出 `All 4 tests passed.`, 覆盖 WASI bind manifest comments、WASI core imports、env host imports 和 import symbol escaping。
- writer / ownership / runner focused unit gates 最近复验通过: `function_body_wat` 2/2、`ownership` 2/2、`ownership_facts` 6/6、`test_runner` 14/14、`main.zig --test-filter run.run` 3/3; `tool/run/run.zig` 通过聚合入口验证, 直接 `zig test run/run.zig` 不是当前 Zig module path 下的有效 gate。
- 剩余 3 个 skip 的边界最近复核通过: `16_loop_recv_value`、`96_file_lib_resource_shape`、`118_wasi_p3_std_wrappers` 均 `do check` 通过; `do test` 分别返回 `0 failed` 且 `3/1/1 skipped`。
- 当前没有新的未记录阻断。
- Delivery boundary inventory gate 最近通过: tracked `64`, untracked `135`; tracked 分类为 CHANGELOG `1`、README `1`、bin `1`、doc `7`、src `11`、tool `2`、tool/build `6`、tool/build/test `33`、tool/lsp `2`; untracked 增加 D2.1 `239` 到 `241` 六个 compile_ok fixture, 且 `ui.do` / `ui_demo.do` 仍只在 untracked; `tool/build/test/tmp` ignored 产物计数为 `0`, 目录大小 `288K`。
- Handoff docs consistency gate 最近通过: handoff 入口文件均存在; 旧 artifact 均不存在; Markdown 本地链接扫描 `markdown_files=26`, `local_markdown_links=20`, `missing=0`; 剩余 `[ ]` 只指向 README 后置非目标、06.2 blocked/decomposed 和 G6.1-G6.3 blocked。
- Regression fixture companion consistency gate 最近通过: `fixture_companion_missing=0`, 当前计数为 `{"err":579,"compile_err":60,"compiled_ok":104,"compiled_err":2,"run":11,"fmt":6,"ok":292,"check":3}`。
- Zig import/file presence gate 最近通过: Zig 文件数 `31`, `zig_imports=121`, `zig_local_imports=89`, `zig_missing_local_imports=0`; 当前未跟踪 Zig 文件数 `8`。
- Do `@lib` target presence gate 最近通过: `.do` 文件数 `877`, `lib_import_hits=890`, `lib_unique_targets=73`, `lib_ignored_support_missing=3`, `lib_missing_targets=0`; 3 个 ignored 项均为 `tool/build/test/err/fixture/` 下负向支持文件边界。
- Do `@lib` imported symbol presence gate 最近通过: `lib_symbol_checks=887`, `lib_symbol_unique_pairs=426`, `lib_symbol_expected_negative_missing=7`, `lib_symbol_unexpected_missing=0`; 7 个 expected negative 均为 `err` 负向导入用例或支持文件边界。
- JSON source/fixture syntax gate 最近通过: 当前 tracked/untracked JSON 共 `10` 个, `json_tracked=6`, `json_untracked=4`, `json_parse_fail=0`; 4 个 untracked JSON 均为 LSP smoke fixture。
- WIT registry schema/uniqueness gate 最近通过: `wasi_registry_records=1`, `wasi_registry_functions=26`, `wasi_registry_unique_targets=26`, `wasi_registry_duplicate_targets=0`, `wasi_registry_shape_errors=0`; known unsupported 仍为 `7`。
- WASI registry / lowering doc coverage gate 最近通过: `wasi_registry_doc_target_coverage=26/26`, `wasi_registry_table_target_coverage=26/26`, `wasi_registry_table_known_unsupported=7`, `wasi_registry_unsupported_mismatch=0`。
- Do `@lib` import graph cycle gate 最近通过: `lib_graph_edges=887`, `lib_graph_cycles=1`, `lib_graph_expected_cycles=1`, `lib_graph_unexpected_cycles=0`; 唯一 cycle 是 `err/65_import_cycle.do` 的负向 fixture。
- ok marker companion gate 最近通过: `ok_do_files=191`, `ok_must_pass_markers=1`, `ok_compiled_must_pass_markers=117`, `ok_must_pass_orphans=0`, `ok_compiled_must_pass_orphans=0`, `ok_marker_overlap=0`。
- compile_ok WASI/component expect companion gate 最近通过: `compile_ok_wasi_expect_files=40`, `compile_ok_wasi_expect_bases=14`, `compile_ok_wasi_expect_orphans=0`, `compile_ok_wasi_unknown_component_like_expects=0`。
- compile_err / compiled_err expect companion gate 最近通过: `negative_compile_do_files=31`, `negative_compile_expect_files=31`, `negative_compile_missing_expect=0`, `negative_compile_orphan_expect=0`。
- LSP JSON fixture naming/order gate 最近通过: `lsp_json_files=9`, `lsp_number_gaps=0`, `lsp_duplicate_numbers=0`, `lsp_schema_errors=0`, `lsp_request_id_errors=0`。
- run/fmt/check black-box fixture companion gate 最近通过: `blackbox_do_files=11`, `blackbox_expect_files=9`, `blackbox_missing_required_expect=0`, `blackbox_orphan_expect=0`, `blackbox_numbering_gaps=0`。
- pending fixture inventory gate 最近通过: `pending_dirs_defined=3`, `pending_dirs_existing=1`, `pending_do_files=0`, `pending_expect_files=0`, `pending_orphan_expect=0`。
- compiled fixture companion / numbering gate 最近通过: 已将重复编号的 `18_compiled_test_math_small_int_helpers.{do,expect}` 重命名为 `52_compiled_test_math_small_int_helpers.{do,expect}`; 并新增 `53_compiled_test_direct_and_mutual_recursion.{do,expect}`、`54_compiled_test_generic_recursive_known_arg.{do,expect}`、`55_compiled_test_recursive_factorial.{do,expect}`、`56_compiled_test_recursive_if_else.{do,expect}`、`57_compiled_test_imported_recursive_factorial.{do,expect}`、`58_compiled_test_self_tail_scalar_tco.{do,expect}`、`59_compiled_test_self_tail_if_else_tco.{do,expect}`、`60_compiled_test_self_tail_guard_tco.{do,expect}`、`61_compiled_test_generic_self_tail_tco.{do,expect}`、`62_compiled_test_imported_self_tail_scalar_tco.{do,expect}`、`63_compiled_test_generic_self_tail_if_else_tco.{do,expect}`、`64_compiled_test_imported_self_tail_if_else_tco.{do,expect}`、`65_compiled_test_tuple_pair.{do,expect}`、`66_compiled_test_tuple_struct_field.{do,expect}`、`67_compiled_test_tuple_return.{do,expect}`、`68_compiled_test_tuple_param.{do,expect}` 与 `compiled_err/02`、`03` 两个递归负例; `compiled_fixture_do_files=68`, `compiled_fixture_missing_required_expect=0`, `compiled_fixture_orphan_expect=0`, `compiled_fixture_duplicate_numbers=0`, `compiled_fixture_missing_numbers=0`。
- compile_ok 普通 expect companion / numbering inventory gate 最近通过: 已将 5 组重复编号 fixture 重命名到 `234_` 到 `238_`, 并新增 D2.1 `239_` 到 `241_`、I1 `242_` 到 `258_` 以及 I2 `259_` 到 `262_`; `compile_ok_numbered_do_files=262`, `compile_ok_plain_expect_orphans=0`, `compile_ok_special_expect_orphans=0`, `compile_ok_duplicate_numbers=0`, `compile_ok_missing_numbers=0`。

- renamed compile_ok targeted build gate 最近通过: `renamed_compile_ok_cases=5`, `renamed_compile_ok_failures=0`, `renamed_compile_ok_total_wat_bytes=176067`, `renamed_compile_ok_expect_lines=23`。
- renamed compiled_ok targeted compiled build gate 最近通过: `renamed_compiled_ok_cases=1`, `renamed_compiled_ok_failures=0`, `renamed_compiled_ok_wat_bytes=38029`, `renamed_compiled_ok_expect_lines=7`。
- D2.1 if/else path-sensitive liveness closure gate 最近通过: 用户确认 B 方案后新增 compile_ok `239` 到 `241`, targeted build 全部通过, 作为绿色 regression 收口, 不再列为当前阻断。
- 默认回归 gate 最近通过: `./tool/build/test/run_tests.sh`, 摘要 `pass=901 fail=0 skip=3`; 回归生成的 `tool/build/test/tmp` ignored 产物已清理到 `0`。

- RUN_WASM 扩展回归 gate 最近通过: `RUN_WASM=1 SKIP_BUILD=1 ./tool/build/test/run_tests.sh`, 摘要 `pass=833 fail=0 skip=3`, `wasm run summary: pass=6 fail=0`; 回归生成的 `tool/build/test/tmp` ignored 产物已清理到 `0`。
- 阶段 I 已完成: I1 递归 / self-tail TCO 与 I2 `Tuple<...>` 第一版均已收口 (I1.1–I1.6、I2.1–I2.6 全部 [x]); 后置边界见「当前阻断」与 `doc/roadmap_status.md`。


## 下一步规则

- 用户说 `go` / `next` 时, 先检查发布候选回归、文档漂移或可独立收口的小项。
- 完成一个小任务后, 立即同步 [doc/roadmap_status.md](/home/_/._/do/doc/roadmap_status.md) 和必要的 [CHANGELOG.md](/home/_/._/do/CHANGELOG.md)。
- 如果没有新的可独立收口小项, 不绕过当前阻断: G6.1/G6.3 需要用户决策; G6.2 需要未来 async/Future runtime 支持。

## 当前阻断

- G6.1: preopens `list<tuple<descriptor,string>>` 公开 API 未确认。
- G6.2: `descriptor.read-directory` 暂时阻断; 当前语言/运行时没有 async / Future / Task 支持, 不能把 WIT stream/future 降成假同步 API。
- G6.3: sockets resource + variant 需要 socket wrapper 和 address variant 映射决策。
- 06.2: 已拆到 G2-G6; result-area/resource/variant 已完成, 剩余部分由 G6.1-G6.3 承接。
- I2 后置 (阶段已关闭, 非发布阻断): managed payload / `text` 叶子 `[Tuple]` storage、`@get(storage, i, j)` path chaining、loop 绑定上的 `@get(v, N)` 仍报 `NoMatchingCall`。

## 当前计划候选

- 阶段 I 已关闭; 默认维护发布候选回归, 或等待 G6 决策。
- I1 已完成边界: 普通直接/互递归、参数侧已定型泛型递归、self-tail scalar/`if/else`/guard/generic/imported TCO; 仅靠左侧目标类型反推的泛型递归仍 `NoMatchingCall`; `defer`/storage/managed/多返回/cleanup 不优化。
- I2 已完成边界: 源码层 `Tuple<T0, T1, ...>` 位置构造 + `@get` 数字索引; local/struct/return/param/nested/标量叶子 storage; sema 诊断 `InvalidTypedLiteral`/`InvalidPathIndex`/`InvalidTypeRef`。
- I2 后置 (不阻断): managed payload / `text` 叶子 storage、`@get(storage, i, j)` path chaining、loop 绑定 `@get(v, N)`。


## 当前边界

- get / pkg / push 包管理线已暂停, 不作为默认后续任务。
- 不去掉内部函数 `@` 前缀。
- 不默认推进 direct wasm binary emitter; 当前继续保留 WAT 主输出和 golden 基线。
- `do run` 当前只覆盖 core wasm smoke 子集, 依赖本机 `wasm-tools` 与 `node`; 不描述成 WASI / Component Model / 自定义 host runtime。
- `do fmt` 当前覆盖 stdout/check-only/write 单文件格式化; 不描述成多文件批量、stdin/stdout 自动模式或语法感知 formatter。
- `do lsp` 当前覆盖 diagnostics、formatting、semantic tokens、hover、completion、definition 和最小 workspace index; v1 明确不支持 rename, 不描述成完整语言服务。
- `do check` 当前覆盖单文件和多文件 lexer/parser/sema/import diagnostics; 不描述成 build/codegen/test runner/watch/multi-diagnostic 命令。

## 当前未提交交付范围

- 当前 dirty worktree 是累计主线成果, 不是单一文档变更; 下次提交前必须重新核对 `git diff --name-only` 和 `git ls-files --others --exclude-standard`。
- 最近复核的 dirty 范围: `git diff --name-only | wc -l` 为 64; `git ls-files --others --exclude-standard | wc -l` 为 135。
- 最近复核的目录分类: tracked 为 CHANGELOG `1`、README `1`、bin `1`、doc `7`、src `11`、tool `2`、tool/build `6`、tool/build/test `33`、tool/lsp `2`; untracked 增加 D2.1 `239` 到 `241` 六个 compile_ok fixture, 且 `ui.do` / `ui_demo.do` 仍只在 untracked。
- 已跟踪改动覆盖 README/CHANGELOG/规划文档、`bin/do`、stdlib、compiler、LSP、WASI/component fixture、ARC/backend IR fixture 和测试脚本。
- 未跟踪改动覆盖 component/WAT 拆分模块、ownership/runtime prelude 模块、compile/compiled/LSP/stdlib regression fixture、release smoke 脚本和 LSP hover/completion/definition/workspace 模块。
- `ui.do` 和 `ui_demo.do` 当前只在 untracked 列表中, 不在 tracked diff; 不属于当前主线, 没有用户明确要求时不要 stage、修改或删除。

## 变更边界

- 只有语法、语义或文档治理任务需要时, 才同步 `doc/spec.md`、`doc/spec_rules.md`、`doc/grammar.peg` 和 `doc/syntax/`。
- 不是当前主线的 `ui.do`、`ui_demo.do`、`js/` 不要顺手改。
