# CHANGELOG

## [2026-03-05 21:52:07] [type: docs] [scope: doc-grammar-peg]
- [新增 `doc/grammar.peg`, 以 PEG 形式收敛 Program/TopLevel/Stmt/Expr/Type 主干语法, 作为 `doc/syntax.md` 的机器可读草案.]
- [语法文件补齐词法层(关键字/标识符/注释/空白)与常用符号规则, 便于后续 parser 对齐与自动化校验.]

## [2026-03-05 21:38:51] [type: docs] [scope: example-tuple-all-in-one-spec]
- [新增 `example/tuple.do` tuple 语法总览单文件, 集中收纳 TupleLit 与多返回值策略关系的规则与示例.]
- [文件保持"设计规则注释 + 可执行正向示例"结构, 并通过 `do test example/tuple.do` 定向验证.]

## [2026-03-05 21:00:57] [type: chore] [scope: full-regression-after-example-expr]
- [执行 `./tests/do/run_tests.sh` 全量回归, 验证新增 `example/import.do` 与 `example/expr.do` 后基线稳定.]
- [回归结果 `pass=55 fail=0`, `ok/err/compile_ok/compile_err` 四类用例全部通过.]

## [2026-03-05 20:54:29] [type: docs] [scope: example-expr-all-in-one-spec]
- [新增 `example/expr.do` 表达式语法总览单文件, 集中收纳 Call/Do/AsyncCtrl/Struct/List/Map/Tuple/Brace/Literal 规则与示例.]
- [文件保持"设计规则注释 + 可执行正向示例"结构, 并通过 `do test example/expr.do` 定向验证.]

## [2026-03-05 20:50:36] [type: docs] [scope: example-import-all-in-one-spec]
- [新增 `example/import.do` import 语法总览单文件, 集中收纳 ImportDecl/ImportItem/重命名/FFI 混合导入规则.]
- [文件保持"设计规则注释 + 可执行正向示例"结构, 并通过 `do test example/import.do` 定向验证.]

## [2026-03-05 20:15:08] [type: chore] [scope: full-regression-after-example-series]
- [执行 `./tests/do/run_tests.sh` 全量回归, 验证新增 `example/if.do` 与 `example/async.do` 后基线稳定.]
- [回归结果 `pass=55 fail=0`, `ok/err/compile_ok/compile_err` 四类用例全部通过.]

## [2026-03-05 20:10:33] [type: docs] [scope: example-async-all-in-one-spec]
- [新增 `example/async.do` async 语法总览单文件, 集中收纳 `do` 并发入口与 Future 控制面规则.]
- [文件保持"设计规则注释 + 可执行正向示例"结构, 并通过 `do test example/async.do` 定向验证.]

## [2026-03-05 20:04:09] [type: docs] [scope: example-if-all-in-one-spec]
- [新增 `example/if.do` if 语法总览单文件, 集中收纳 IfStmt/IfTypePattern 规则与单值条件约束.]
- [文件保持"设计规则注释 + 可执行正向示例"结构, 并通过 `do test example/if.do` 定向验证.]

## [2026-03-05 19:59:49] [type: docs] [scope: example-match-all-in-one-spec]
- [新增 `example/match.do` match 语法总览单文件, 集中收纳 MatchStmt/Pattern/PatternFields 规则与单值目标位约束.]
- [文件保持"设计规则注释 + 可执行正向示例"结构, 并通过 `do test example/match.do` 定向验证.]

## [2026-03-05 19:57:14] [type: docs] [scope: example-loop-all-in-one-spec]
- [新增 `example/loop.do` loop 语法总览单文件, 集中收纳 LoopStmt/LoopCond/LoopBind 规则与头部约束.]
- [文件保持"设计规则注释 + 可执行正向示例"结构, 并通过 `do test example/loop.do` 定向验证.]

## [2026-03-05 19:53:21] [type: docs] [scope: example-struct-all-in-one-spec]
- [新增 `example/struct.do` 结构语法总览单文件, 集中收纳 Struct/Alias/TypeSetAlias 设计规则与示例.]
- [文件保持"设计规则注释 + 可执行正向示例"结构, 并通过 `do test example/struct.do` 定向验证.]

## [2026-03-05 19:48:27] [type: docs] [scope: example-func-runnable-snippets]
- [example/func.do 将 `.normalize_name(name Text) Text { ... }` 从注释示例提升为可执行函数声明, 保持 do 文件内函数样例可直接运行.]
- [example/func.do 将 `total = add(a, b, c)` 形态落到 test 代码中(`total_flat = add(a, b, c)`), 作为可运行的扁平调用示例.]

## [2026-03-05 19:31:18] [type: docs] [scope: example-func-all-in-one-spec]
- [重构 `example/func.do` 为函数语法总览单文件, 集中收纳 `5/5.1/5.2` 的函数声明语法, 约束规则, 重载优先级与扁平化设计示例.]
- [文件保持"设计规则注释 + 可执行正向示例"结构, 既可集中查阅语法设计, 也可用 `do test` 做快速验证.]

## [2026-03-05 19:18:04] [type: docs] [scope: example-func-positive]
- [新增 `example/func.do` 正向示例, 聚焦函数声明与调用, 并在文件头标注使用类型与语法表达式设计点.]
- [示例覆盖 `CallExpr`/`ArrowExprList`/`ReturnExprList` 与 `if` 条件调用形态, 用于按主题拆分后的 `func` 参考模板.]

## [2026-03-05 19:06:00] [type: chore] [scope: final-full-regression-after-wait-zero-arg]
- [执行 `./tests/do/run_tests.sh` 全量回归, 验证新增 `39_wait_no_arg_arity` 后基线稳定.]
- [回归结果 `pass=55 fail=0`, 覆盖 `ok/err/compile_ok/compile_err` 四类用例全部通过.]

## [2026-03-05 19:00:59] [type: test] [scope: wait-no-arg-arity]
- [tests/do/cases/err 新增 `39_wait_no_arg_arity.do(.expect)`, 覆盖内建 `wait` 调用 0 参数时的 arity 错误路径.]
- [用例断言 `AsyncCtrlArity`, 固化 `wait` 仅允许 1 或 2 参数的下界约束.]

## [2026-03-05 18:58:22] [type: chore] [scope: full-regression-after-wait-any-all-cases]
- [执行 `./tests/do/run_tests.sh` 全量回归, 验证新增 `37_wait_any_user_func_mismatch_arity` 与 `38_wait_all_user_func_mismatch_arity` 后基线稳定.]
- [回归结果 `pass=54 fail=0`, 覆盖 `ok/err/compile_ok/compile_err` 四类用例全部通过.]

## [2026-03-05 18:54:58] [type: test] [scope: wait-all-user-func-mismatch-arity]
- [tests/do/cases/err 新增 `38_wait_all_user_func_mismatch_arity.do(.expect)`, 覆盖同名用户函数 `wait_all` 签名不匹配时回退内建 `wait_all` arity 规则.]
- [用例断言 `AsyncCtrlArity`, 防止 `hasUserFuncMatch` 在 `wait_all` 路径误匹配放行.]

## [2026-03-05 18:48:41] [type: test] [scope: wait-any-user-func-mismatch-arity]
- [tests/do/cases/err 新增 `37_wait_any_user_func_mismatch_arity.do(.expect)`, 覆盖同名用户函数 `wait_any` 签名不匹配时回退内建 `wait_any` arity 规则.]
- [用例断言 `AsyncCtrlArity`, 防止 `hasUserFuncMatch` 在 `wait_any` 路径误匹配放行.]

## [2026-03-05 18:45:45] [type: chore] [scope: full-regression-after-wait-mismatch-case]
- [执行 `./tests/do/run_tests.sh` 全量回归, 验证新增 `36_wait_user_func_mismatch_arity` 后基线稳定.]
- [回归结果 `pass=52 fail=0`, 覆盖 `ok/err/compile_ok/compile_err` 四类用例全部通过.]

## [2026-03-05 18:39:45] [type: test] [scope: wait-user-func-mismatch-arity]
- [tests/do/cases/err 新增 `36_wait_user_func_mismatch_arity.do(.expect)`, 覆盖同名用户函数 `wait` 签名不匹配时回退内建 `wait` arity 规则.]
- [用例断言 `AsyncCtrlArity`, 防止 `hasUserFuncMatch` 在 `wait` 路径误匹配放行.]

## [2026-03-05 18:37:22] [type: chore] [scope: final-full-regression-baseline]
- [执行 `./tests/do/run_tests.sh` 全量回归, 覆盖 `ok/err/compile_ok/compile_err` 四类用例.]
- [回归结果 `pass=51 fail=0`, 含 `err/33`、`err/34`、`err/35` 全部通过, 基线稳定.]

## [2026-03-05 18:34:19] [type: docs] [scope: done-arity-error-semantics-clarify]
- [doc/syntax.md 在 `7.2` 与 `12.3` 补充 `done` arity 错误语义: 无同名可匹配普通函数时, `0` 参数报 `DoneCallNeedsArg`, `>1` 参数报 `DoneCallArity`.]
- [文档约束与 `sema.checkAsyncControlArity` 及现有 `err/12`、`err/33` 回归断言保持一致.]

## [2026-03-05 18:29:28] [type: chore] [scope: full-regression-after-cancel-status-cases]
- [执行 `./tests/do/run_tests.sh` 全量回归, 验证新增 `34_cancel_user_func_mismatch_arity` 与 `35_status_user_func_mismatch_arity` 后基线稳定.]
- [回归结果 `pass=51 fail=0`, `ok/err/compile_ok/compile_err` 四类用例全部通过.]

## [2026-03-05 18:25:16] [type: test] [scope: status-user-func-mismatch-arity]
- [tests/do/cases/err 新增 `35_status_user_func_mismatch_arity.do(.expect)`, 覆盖同名用户函数 `status` 签名不匹配时回退内建 `status(f)` arity 规则.]
- [用例断言 `AsyncCtrlArity`, 防止 `hasUserFuncMatch` 在 `status` 路径误匹配放行.]

## [2026-03-05 18:21:00] [type: test] [scope: cancel-user-func-mismatch-arity]
- [tests/do/cases/err 新增 `34_cancel_user_func_mismatch_arity.do(.expect)`, 覆盖同名用户函数 `cancel` 签名不匹配时回退内建 `cancel(f)` arity 规则.]
- [用例断言 `AsyncCtrlArity`, 防止 `hasUserFuncMatch` 在 `cancel` 路径误匹配放行.]

## [2026-03-05 18:17:17] [type: chore] [scope: full-regression-after-done-arity-case]
- [执行 `./tests/do/run_tests.sh` 全量回归, 验证新增 `33_done_user_func_mismatch_arity` 后基线稳定.]
- [回归结果 `pass=49 fail=0`, `ok/err/compile_ok/compile_err` 四类用例全部通过.]

## [2026-03-05 18:11:50] [type: test] [scope: done-user-func-mismatch-arity]
- [tests/do/cases/err 新增 `33_done_user_func_mismatch_arity.do(.expect)`, 覆盖同名用户函数 `done` 签名不匹配时回退内建 `done(f)` arity 规则.]
- [用例断言 `DoneCallArity`, 防止 `hasUserFuncMatch` 在 `done` 路径发生误匹配放行.]

## [2026-03-05 18:03:46] [type: docs] [scope: async-builtin-fallback-signatures]
- [doc/syntax.md 对齐 `7.2` 与 `12.3`: 无同名可匹配普通函数时, 内建 `done/wait/wait_one/wait_any/wait_all/cancel/status` 全量签名规则固定生效.]
- [补充 `wait(f)|wait(ms,f)` 与 `wait_*` 形态的回退签名清单, 统一文档与 sema 的参数校验口径.]

## [2026-03-05 17:59:23] [type: docs] [scope: syntax-bracelit-ebnf-alignment]
- [doc/syntax.md 在 `Expr` 产生式补充 `BraceLit`/`BraceItems`, 对齐 parser 已支持的裸花括号表达式语法.]
- [doc/syntax.md 增加 `BraceLit` 两种合法形态示例与混用非法规则, 明确 `{ExprList}` 与 `{PairList}` 不可混写.]

## [2026-03-05 17:48:54] [type: chore] [scope: full-regression-run-tests]
- [执行 `./tests/do/run_tests.sh` 全量回归, 覆盖 ok/err/compile_ok/compile_err 四类用例.]
- [回归结果 `pass=48 fail=0`, 含新增 `31_invalid_brace_expr_mixed` 与 `32_async_control_user_func_mismatch` 均通过.]

## [2026-03-05 17:44:24] [type: docs] [scope: async-ctrl-arity-hint-fallback]
- [compiler/src/main.zig 更新 `AsyncCtrlArity` hint, 明确同名普通函数仅在实参数匹配时优先, 不匹配时回退内建控制面参数规则.]
- [诊断文案与 `hasUserFuncMatch` 行为对齐, 降低 `wait/wait_one` 同名函数场景下的理解偏差.]

## [2026-03-05 17:37:07] [type: test] [scope: async-control-user-func-mismatch]
- [tests/do/cases/err 新增 `32_async_control_user_func_mismatch.do(.expect)`, 覆盖同名用户函数签名不匹配时回退内建 `wait_one` arity 校验路径.]
- [用例断言固定为 `AsyncCtrlArity`, 防止 `hasUserFuncMatch` 误放行导致控制面规则失效.]

## [2026-03-05 17:20:49] [type: fix] [scope: brace-expr-diagnostic-split]
- [compiler/src/parser.zig 将裸花括号 `k:v` 路径错误从 `InvalidMapLiteral` 分流为 `InvalidBraceExpr`, 保持 `Map<...>{...}` 仍使用 `InvalidMapLiteral`.]
- [compiler/src/main.zig 新增 `InvalidBraceExpr` 的定位/摘要/hint, 并同步 tests/do/cases/err/31_invalid_brace_expr_mixed.expect 断言.]

## [2026-03-05 17:03:20] [type: fix] [scope: brace-expr-invalid-mixed-regression]
- [tests/do/cases/err 新增 `31_invalid_brace_expr_mixed.do(.expect)`, 覆盖裸花括号表达式中 `k:v` 与单项混用的非法路径.]
- [固定期望错误为 `InvalidMapLiteral`, 保障 `.x` 字段选择批量参数能力引入后的非法输入回归可验证.]

## [2026-03-05 16:52:46] [type: fix] [scope: parser-dot-selector-brace-expr]
- [compiler/src/parser.zig 新增裸花括号表达式解析, 支持 `{.name, .age}` 与 `{k: v}` 作为普通表达式参与调用参数与赋值 RHS.]
- [tests/do/cases/ok/14_dot_selector_batch_expr.do 新增回归, 覆盖 `.x` 字段选择批量参数与批量更新表达式写法.]

## [2026-03-05 16:45:34] [type: docs] [scope: dot-ident-dual-role]
- [doc/syntax.md 将前置 `.` 标识符规则统一为双语义: 私有命名位与字段选择符共存.]
- [doc/syntax.md 更新绑定规则与收窄示例, 明确 `get(u, .name)` 和 `{.name}` 字段选择写法合法.]

## [2026-03-05 16:07:12] [type: fix] [scope: async-control-name-user-func]
- [compiler/src/sema.zig 异步控制参数校验改为"无同名可匹配普通函数时才应用内建控制面规则", 允许 `done/wait/wait_one/wait_any/wait_all/cancel/status` 作为普通函数名.]
- [compiler/src/parser.zig 导入项冲突名校验仅保留关键字互斥, 允许 `{wait, done, status} := @(\"...\")` 直接导入.]
- [compiler/src/main.zig 诊断提示同步更新: `InvalidImportDecl` 冲突名提示改为仅关键字.]
- [doc/syntax.md 同步规则: 导入名与关键字互斥, 内建控制面与同名普通函数按签名匹配优先级共存.]
- [tests/do/cases/ok 新增 `12_async_control_name_as_user_func.do` 与 `13_import_async_control_names_plain.do` 回归用例.]

## [2026-03-05 15:34:26] [type: fix] [scope: sema-loop-header-depth-scan]
- [compiler/src/sema.zig 对齐 loop 头部扫描策略: `findLoopBlockOpen/findLoopBindAssign` 增加括号/花括号/尖括号深度感知, 避免把条件表达式内部 `{}` 误判为循环体起始.]
- [语义检查与 parser loop 头部识别口径保持一致, 降低 cond 含结构体字面量场景下的误判风险.]

## [2026-03-05 15:22:14] [type: fix] [scope: parser-loop-header-brace-aware]
- [compiler/src/parser.zig 调整 loop 头部识别顺序, 先解析 cond/bind 表达式, 再定位循环体 `{`, 修复 cond 中结构体字面量误判.]
- [tests/do/cases/ok/11_loop_cond_bool_predicates.do 新增回归, 覆盖 `loop is_valid(User{...})` 与 `loop has(user_map, uid)` 两种 bool 条件形态.]

## [2026-03-05 15:08:58] [type: docs] [scope: loop-condition-bool-semantics]
- [doc/syntax.md 明确 `loop cond {}` 仅要求条件表达式返回 `bool`, 不限制函数参数个数.]
- [doc/syntax.md 在 `loop` 章节补充 `has(user_map, uid)` 与 `is_valid(user)` 条件示例, 统一谓词语义表达.]

## 2026-03-05 13:52:20 | fix | loop-cond-expression-full-consume

- `compiler/src/parser.zig` 收紧 `loop cond {}` 头部校验: 条件位表达式必须完整消费到 `{` 前, 残留 token 统一报 `InvalidLoopHeader`.
- `tests/do/cases/ok/07_loop_header_forms.do` 条件循环示例更新为函数调用式布尔条件: `loop lt(count, 3) { ... }`.
- 新增反例: `tests/do/cases/err/30_invalid_loop_condition_operator_style.do(.expect)`, 覆盖 `loop count < 3 { ... }` 头部残留路径.
- 回归通过: `./tests/do/run_tests.sh(pass=42 fail=0)`.

## 2026-03-05 13:43:03 | docs | syntax-ebnf-conflict-alignment

- `doc/syntax.md` 对齐 `AssignStmt` 与解构章节口径: `AssignStmt` 增补 `DestructureLValue "=" Expr`, 与 `{x, y} = value` 写法一致.
- `doc/syntax.md` 修正 `LoopStmt` EBNF 产生式, 条件循环与绑定循环形态补齐 `Stmt* "}"` 体结构.
- `doc/syntax.md` 将 `loop` 条件示例和冻结条款改为函数调用式布尔条件(`loop lt(count, 3) { ... }`), 去除 `<` 比较符号示例.
- 文档自检通过: 语法章节内 `语句/解构/loop` 三处规则口径一致, 无新增实现差异描述.

## 2026-03-05 13:35:03 | fix | match-header-tail-guard

- `compiler/src/parser.zig` 为 `match` 头部新增尾随校验: 目标表达式后必须直接进入 `{`, 其余残留 token 统一报 `InvalidMatchHeader`.
- `compiler/src/main.zig` 新增 `InvalidMatchHeader` 诊断摘要与 hint, 错误定位锚定到 `match` 关键字.
- 新增回归: `tests/do/cases/err/29_invalid_match_header_trailing_token.do(.expect)`, 覆盖 `match x bad { ... }` 头部残留路径.
- 回归通过: `./tests/do/run_tests.sh(pass=41 fail=0)`.

## 2026-03-05 13:25:25 | fix | if-header-tail-strict-guard

- `compiler/src/parser.zig` 收紧 `if` 头部尾随校验: 条件表达式后若非块体, 按同一行单语句做完整消费校验, 残留 token 统一报 `InvalidIfHeader`.
- `compiler/src/parser.zig` 新增 `findLineEnd/findTopLevelAssignEq/isOneLineIfStmtKeyword` 辅助函数, 使 `if` 头部与单行体边界判定可验证.
- 新增回归: `tests/do/cases/err/28_invalid_if_header_trailing_stmt_before_block.do(.expect)`, 覆盖 `if ge(a, b) and(ok_flag) { ... }` 头部残留路径.
- 回归通过: `./tests/do/run_tests.sh(pass=40 fail=0)`.

## 2026-03-05 13:10:20 | fix | lexer-float-and-line-comment

- `compiler/src/lexer.zig` 新增单行注释词法规则: `//` 到行尾全部跳过, 不再参与语法解析.
- `compiler/src/lexer.zig` 新增浮点字面量词法识别: `Digit+ "." Digit+` 作为单个 `number` token 产出.
- `doc/syntax.md` 新增 `2.4 注释与数值字面量`, 固化 `//` 注释与浮点字面量词法写法.
- 新增回归: `tests/do/cases/ok/10_float_and_comment_lexing.do`, 覆盖“注释内括号噪声 + 浮点字面量 + 行尾注释”组合路径.
- 回归通过: `./tests/do/run_tests.sh(pass=39 fail=0)`.

## 2026-03-05 13:01:37 | fix | assign-rhs-tail-guard

- `compiler/src/parser.zig` 收紧赋值语句 RHS 解析边界: 按当前语句边界截断 RHS, 解析后必须完整消费, 尾随残留 token 统一报 `InvalidAssignExpr`.
- `compiler/src/parser.zig` `parseAssignStmt` 返回值改为 RHS 结束位, 避免重复扫描 RHS 内 token.
- 新增回归: `tests/do/cases/err/27_invalid_assign_rhs_tail.do(.expect)`, 覆盖 `x = 1 foo` 这类尾随垃圾 token 不再静默通过.
- 回归通过: `./tests/do/run_tests.sh(pass=38 fail=0)`.

## 2026-03-05 12:50:47 | fix | parser-test-body-syntax-validation

- `compiler/src/parser.zig` 顶层分发新增 `test` 声明解析路径, `test` 代码块复用函数体语句校验链(`if/match/loop/assign/expr`).
- `compiler/src/parser.zig` 新增 `InvalidTestDecl` 头部校验收敛, `test` 声明缺失字符串名或块体时在 parser 阶段直接报错.
- 新增回归: `tests/do/cases/err/26_invalid_struct_literal_in_test_body.do(.expect)`, 覆盖 `do test` 下 `test` 体非法结构体字面量不再静默通过.
- 回归通过: `./tests/do/run_tests.sh(pass=37 fail=0)`.

## 2026-03-05 09:31:22 | feat | type-decl-naming-guard

- `compiler/src/sema.zig` 新增顶层类型声明命名校验: `Struct/Union/Alias/TypeSetAlias` 左值名称必须满足 `UpperCamel + 字母数字`.
- `compiler/src/main.zig` 新增 `InvalidTypeDeclName` 诊断摘要与修复提示, 明确自建类型命名约束.
- `doc/syntax.md` 更新“类型命名/类型声明”规则, 固化自建类型声明名规范.
- 新增回归: `tests/do/cases/ok/09_type_decl_name_valid.do`.
- 新增反例: `tests/do/cases/err/23_invalid_type_decl_name_struct.do(.expect)`, `24_invalid_type_decl_name_alias.do(.expect)`, `25_invalid_type_decl_name_typeset_alias.do(.expect)`.
- 回归通过: `tests/do/run_tests.sh(pass=36 fail=0)`.

## 2026-03-04 23:19:42 | refactor | future-wait-timeout-naming

- `compiler/src/sema.zig` 调整异步控制参数规则: `wait` 支持 `1|2` 参数, `wait_one/wait_any/wait_all` 调整为 `>=2` 参数且首参数为超时值.
- `compiler/src/main.zig` 更新 `AsyncCtrlArity` 提示与异步控制定位 token 集, 移除 `wait_timeout/*_timeout` 控制名依赖.
- `compiler/src/parser.zig` 更新 import 冲突名集合, 控制面收敛为 `done/wait/wait_one/wait_any/wait_all/cancel/status`.
- `doc/syntax.md` 与 `README.md` 同步控制面语法: 去除 `wait_timeout/wait_*_timeout`, 改为 `wait(ms, f)` 与 `wait_one/wait_any/wait_all(ms, ...)`.
- 更新回归: `tests/do/cases/ok/08_future_wait_many_controls.do`; 新增 `tests/do/cases/err/22_invalid_wait_arity.do(.expect)`; `21_invalid_wait_many_timeout_arity.do` 改为 `wait_one(f1)` 参数错误路径.
- 回归通过: `tests/do/run_tests.sh(pass=32 fail=0)`.

## 2026-03-04 23:07:55 | feat | future-wait-timeout-controls

- `compiler/src/sema.zig` 扩展异步控制参数约束: 新增 `wait_one_timeout/wait_any_timeout/wait_all_timeout` 形态, 参数个数统一为 `>= 2`.
- `compiler/src/main.zig` 更新 `AsyncCtrlArity` 诊断提示, 明确三组 `*_timeout` 控制函数的参数规则.
- `compiler/src/parser.zig` 扩展 import 冲突名集合, 新增 `wait_one_timeout/wait_any_timeout/wait_all_timeout`, 冲突导入需显式重命名.
- `doc/syntax.md` 与 `README.md` 同步控制面定义、EBNF、约束与示例, 固化多 Future 超时等待语法.
- 更新回归: `tests/do/cases/ok/08_future_wait_many_controls.do`; 新增 `tests/do/cases/err/21_invalid_wait_many_timeout_arity.do(.expect)`.
- 回归通过: `tests/do/run_tests.sh(pass=31 fail=0)`.

## 2026-03-04 22:58:26 | feat | future-wait-many-controls

- `compiler/src/sema.zig` 扩展异步控制函数参数校验: `wait_one/wait_any/wait_all` 统一要求 `>= 1` 个参数, 不满足时报 `AsyncCtrlArity`.
- `compiler/src/main.zig` 更新 `AsyncCtrlArity` 诊断提示, 明确 `wait/cancel/status=1`, `wait_timeout=2`, `wait_one/wait_any/wait_all>=1`.
- `compiler/src/parser.zig` 更新 import 冲突名集合, 新增 `wait_one/wait_any/wait_all`, 冲突项需显式重命名.
- `doc/syntax.md` 与 `README.md` 同步控制面定义与 EBNF, 固化 `wait_one/wait_any/wait_all` 语法与约束.
- 新增回归: `tests/do/cases/ok/08_future_wait_many_controls.do`, `tests/do/cases/err/20_invalid_wait_many_arity.do(.expect)`.
- 回归通过: `tests/do/run_tests.sh(pass=30 fail=0)`.

## 2026-03-04 22:51:42 | fix | typed-literal-requires-braces

- `doc/syntax.md` 补充集合字面量规则: `List/Map/Tuple` 统一使用完整写法 `Type<...>{...}`, 空值固定写 `Type<...>{}`.
- `compiler/src/main.zig` 为 `InvalidTypedLiteral` 增加专用诊断摘要与修复提示, 明确缺失 `{}` 的修复方向.
- 新增回归 `tests/do/cases/err/19_invalid_typed_literal_missing_brace.do(.expect)`, 覆盖 `Map<i32, i32>` 无 `{}` 的不完整表达式路径.
- 回归通过: `tests/do/run_tests.sh(pass=28 fail=0)`.

## 2026-03-04 22:47:41 | feat | loop-header-cond-iter-range

- `doc/syntax.md` 扩展 loop 语法: 支持 `loop cond {}` 与 `loop v := iterable {}`/`loop v, i := iterable {}` 头部形态, 并补充 `range(...)` 迭代示例.
- `compiler/src/parser.zig` 新增 loop 头部解析校验: 支持块循环/条件循环/绑定迭代三类头部, 非法头部统一报 `InvalidLoopHeader`.
- `compiler/src/sema.zig` 增加全 token 流 loop 头部约束检查, 覆盖 `test` 声明体与函数体两种上下文.
- `compiler/src/main.zig` 新增 `InvalidLoopHeader` 诊断摘要与 hint, 错误定位锚定到 `loop` 关键字位点.
- 新增回归: `tests/do/cases/ok/07_loop_header_forms.do`, `tests/do/cases/err/18_invalid_loop_header.do(.expect)`.
- 回归通过: `tests/do/run_tests.sh(pass=27 fail=0)`.

## 2026-03-04 22:10:23 | refactor | test-strategy-do-side-only

- `compiler/src/{lexer,parser,sema,main,cmd/test}.zig` 移除全部 Zig `test` 代码块, 编译器源码不再承载单元测试代码.
- `tests/do/run_tests.sh` 扩展为双通道回归: `do test <file.do>` + `do <file.do> -o out.wat` 编译模式.
- 新增 `tests/do/cases/compile_ok` 与 `tests/do/cases/compile_err` 用例目录, 覆盖 `_start` 入口规则(缺失/签名错误/重复定义).
- 新增 do 侧错误用例: `DoneCallNeedsArg`, `InvalidIfPatternBind`, `UnterminatedString`, `NoTestDecl`, `InvalidTestDecl`.
- `tests/do/README.md` 同步更新目录与执行口径说明.
- 回归通过: `tests/do/run_tests.sh(pass=25 fail=0)`.

## 2026-03-04 21:59:27 | refactor | cli-test-subcommand-module-split

- 新增 `compiler/src/cmd/test.zig`, 将 `do test <input.do>` 的顶层测试收集与报告输出逻辑独立为命令模块.
- `compiler/src/main.zig` 的 `test_mode` 分支改为调用 `cmd_test.run(...)`, CLI 入口只保留参数解析与错误诊断分发.
- `collectTopLevelTests` 单测迁移到 `cmd/test.zig`, 保持 `test` 声明扫描行为覆盖.
- 回归通过: `zig test src/{main,parser,sema,lexer}.zig`, `tests/do/run_tests.sh(pass=16 fail=0)`.

## 2026-03-04 21:50:24 | docs | syntax-fully-positive-style

- `doc/syntax.md` 规范文本改为全正向表达风格: 规则统一使用“固定语法/闭集/互斥/触发条件”描述, 移除否定式约束语句.
- `doc/syntax.md` 删除 `if/do/match` 章节中的反例块, 示例区仅保留可直接执行的规范写法.
- `doc/syntax.md` 术语与约束同步正向化: `不可变` 统一为 `只读`, `不可重叠` 改为 `交集为空`, `as` 规则改为“按普通标识符使用”.

## 2026-03-04 21:42:05 | docs | syntax-whitelist-style

- `doc/syntax.md` 新增“规范表达策略”, 明确语法规则默认采用白名单表述(`只支持/固定为/必须`), 未列出写法按未定义处理.
- `doc/syntax.md` 将 import、函数约束、重载、绑定、if/match、异步入口、类型转换等章节改写为正向约束表达, 降低“禁止条款”噪音.
- 保留高冲突反例为显式提示: `do(...)`, `done()`, `if check_auth(user)`, `match decode(msg)` 等误用路径.

## 2026-03-04 21:27:19 | docs | syntax-v1-freeze

- `doc/syntax.md` 版本头由 `v0.8` 升级为 `v1.0` 冻结口径, 新增“版本状态”章节, 明确文档与实现的一致性约束.
- `doc/syntax.md` 强化 import 规则: 冲突名必须显式重命名, 并固定 `ImportSymbol` 与 `ImportValue/ImportType/ImportFunc` 的重命名方式.
- `doc/syntax.md` 强化类型转换规则: `as` 非关键字, 转换统一走普通函数调用, 明确 `to_i8(i32) => i8` 与 `to_i8(i64) => i8` 重载约束.
- `README.md` 同步异步控制面为 `done/wait/wait_timeout/cancel/status`, 并标记语法基线为 `v1.0` 冻结.

## 2026-03-04 21:10:06 | docs | changelog-entry-wording-cleanup

- 清理 `CHANGELOG.md` 中与语言入口约定易混淆的历史主入口文案描述, 统一改为 `_start(...)` 或“编译器 CLI 入口函数”.
- CI 历史记录中的分支触发描述统一为 `push(default-branch)`, 避免与语言入口名混淆.

## 2026-03-04 21:05:04 | chore | unit-tests-start-entry-alignment

- `compiler/src/{parser,sema,main}.zig` 单测样例源码中的入口函数样例统一替换为 `_start(...)`, 与入口约定保持一致.
- 保留编译器 CLI 进程入口函数不变, 避免影响工具本身启动行为.
- 修复 `main.zig` 的“缺少 `_start`”校验用例为 `helper()`, 保持断言语义准确.
- 回归通过: `zig test compiler/src/main.zig`, `./tests/do/run_tests.sh(pass=16 fail=0)`.

## 2026-03-04 21:03:18 | chore | tests-start-entry-alignment

- `tests/do/cases/err` 中历史入口测试函数统一替换为 `_start()`, 与“程序入口固定为 `_start`”约定保持一致.
- 保持错误断言位点稳定: 既有 `.expect` 文件无需改动, 所有错误用例仍按原位置触发.
- 回归通过: `./tests/do/run_tests.sh(pass=16 fail=0)`.

## 2026-03-04 20:59:04 | refactor | parser-dispatch-by-syntax-kind

- `compiler/src/parser.zig` 将函数声明解析流程拆分为专用入口 `parseTopLevelFuncDecl`, 由 `parseProgram` 在顶层统一分发调用.
- `compiler/src/parser.zig` 将函数体扫描重构为语句分发器 `parseBodyStmt`, 并拆出 `parseIfStmt/parseMatchStmt/parseLoopStmt/parseAssignStmt` 专用处理函数.
- 保持现有语义不变: `if/match` 条件位采集与赋值 RHS 表达式校验逻辑沿用原规则, 但执行路径改为按语法构件函数分发.
- 回归通过: `zig test compiler/src/{lexer,parser,sema,main}.zig`, `./tests/do/run_tests.sh(pass=16 fail=0)`.

## 2026-03-04 20:50:26 | fix | import-conflict-rename-guard

- `doc/syntax.md` 导入规则新增冲突名约束: import 项本地名禁止使用关键字与 `done/wait/wait_timeout/cancel/status`, 冲突时必须显式重命名.
- `compiler/src/parser.zig` 新增 import 局部名冲突校验, `{if}`/`{wait}` 等写法统一报 `InvalidImportDecl`, `{kw_if:if}` 等显式重命名写法可通过.
- `compiler/src/sema.zig` 的 async 参数检查与 if 模式绑定检查新增 import 声明段跳过逻辑, 避免将 import 项误判为语句语义错误.
- `compiler/src/main.zig` 更新 `InvalidImportDecl` 提示文案, 明确冲突名需显式重命名.
- 新增回归: `tests/do/cases/ok/06_import_conflict_rename.do`, `tests/do/cases/err/11_import_conflict_name.do(.expect)`, parser/sema 单测补齐冲突名与重命名路径.
- 回归通过: `zig test compiler/src/{lexer,parser,sema,main}.zig`, `./tests/do/run_tests.sh(pass=16 fail=0)`.

## 2026-03-04 20:32:04 | feat | import-ffi-mixed-items

- `doc/syntax.md` 更新导入语法, `ImportItem` 扩展为 `ImportSymbol/ImportValue/ImportType/ImportFunc`, 支持在同一 import 块声明外部值、外部类型、外部函数签名.
- `compiler/src/parser.zig` 落地 import 项语法校验: 支持 `{sqrt}`、`{m_sqrt:sqrt}`、`key Text`、`WasiIovec{...}`、`fd_write(i32, WasiIovec, i32, i32) => i32`, 并在非法项时报 `InvalidImportDecl`.
- `compiler/src/main.zig` 新增 `InvalidImportDecl` 诊断摘要与修复提示, 错误定位优先锚到 `@`.
- 新增回归: `tests/do/cases/ok/05_ffi_import_mixed.do`, `tests/do/cases/err/10_invalid_import_decl.do(.expect)`, parser 单测覆盖合法/非法 import 混合项.
- 回归通过: `zig test compiler/src/{lexer,parser,sema,main}.zig`, `./tests/do/run_tests.sh(pass=14 fail=0)`.

## 2026-03-04 20:14:10 | refactor | conversion-func-and-as-non-keyword

- `doc/syntax.md` 移除 `as` 关键字与 `CastExpr` 专用转换语法, 类型转换统一为普通函数调用, 新增 `to_i8(i32)/to_i8(i64)` 重载示例与冻结条款.
- `compiler/src/parser.zig` 删除 `as(T, value)` 专用解析分支与 `cast` 表达式节点, `as` 从关键字集合移除, `as(...)` 现在按普通函数调用解析.
- `compiler/src/main.zig` 清理 `InvalidCastExpr` 定位与诊断文案, 单测改为 `InvalidDoExpr` 定位校验, 避免继续输出旧转换语法提示.
- `tests/do` 删除 `err/02_invalid_cast_expr` 失败用例, 新增 `ok/04_convert_by_function.do` 验证“转换函数重载 + `as` 作为普通函数名”路径.
- 回归通过: `zig test compiler/src/{lexer,parser,sema,main}.zig`, `./tests/do/run_tests.sh(pass=12 fail=0)`.

## 2026-03-04 17:03:43 | feat | start-entry-and-do-test-runner

- `compiler/src/main.zig` 在编译模式强制入口函数为 `_start() { ... }`, 规则为“必须存在且仅存在 1 个 `_start`, 且签名必须无参无返回”.
- 新增入口校验错误类型与诊断映射: `MissingStartEntry/InvalidStartEntrySig/DuplicateStartEntry`.
- `compiler/src/main.zig` 新增 `do test <file.do>` 子命令执行器, 扫描顶层 `test "name" { ... }` 并输出 `test "name" ... ok` 与汇总行.
- `tests/do/run_tests.sh` 切换为统一使用 `do test xxx.do` 路径执行用例, 与新测试入口保持一致.
- `tests/do` 用例同步: `ok` 集合改为顶层 `test` 风格; `err/01` 调整为函数体内 `if` 头部非法用例以稳定触发 `InvalidIfHeader`.
- 按请求删除 `.github` 目录并确认不存在工作流目录.
- 回归通过: `zig test compiler/src/main.zig|parser.zig|sema.zig|lexer.zig`, `./tests/do/run_tests.sh(pass=12 fail=0)`.

## 2026-03-04 16:54:54 | feat | do-test-command-and-output

- `compiler/src/main.zig` 新增 `do test <input.do>` 子命令, 在同一编译前端校验通过后执行顶层 `test "name" { ... }` 声明并输出测试进度.
- 测试输出新增固定格式: `test "xxx" ... ok`, 并在末尾输出汇总 `ok: N passed; 0 failed`.
- `compiler/src/main.zig` 新增顶层测试声明收集器, 支持解析多个 `test` 块并按声明顺序执行.
- CLI 与诊断扩展: 新增 `MissingTestInputPath/NoTestDecl/InvalidTestDecl` 的错误摘要与提示信息.
- `tests/do/run_tests.sh` 切换为统一通过 `do test xxx.do` 执行用例, `ok` 用例同步改为顶层 `test` 风格.
- 按请求删除 `.github` 目录, 停用此前新增的 GitHub Actions 工作流配置.
- 回归通过: `zig test compiler/src/main.zig|parser.zig|sema.zig|lexer.zig` 与 `./tests/do/run_tests.sh(pass=12 fail=0)`.

## 2026-03-04 16:47:49 | refactor | ci-split-unit-and-integration

- `.github/workflows/do-integration.yml` 新增 `zig-unit` job, 按矩阵分别执行 `compiler/src/lexer.zig|parser.zig|sema.zig|main.zig` 的 `zig test`.
- `do-integration` job 增加 `needs: zig-unit`, 将入口级集成回归收敛为“单测通过后再执行”.
- CI 结果呈现拆分为“编译器单测”与“do 集成回归”两层, 失败域更清晰.
- 本地对齐复验通过: 四个 `zig test` 目标全通过, `./tests/do/run_tests.sh` 结果 `pass=12 fail=0`.

## 2026-03-04 16:46:21 | feat | github-actions-do-integration

- 新增 `.github/workflows/do-integration.yml`, 接入 GitHub Actions 自动化回归.
- 触发条件覆盖 `push`(default-branch)、`pull_request`、`workflow_dispatch`.
- CI 使用 `mlugg/setup-zig@v1` 安装 Zig `0.15.1`, 并执行 `ZIG_BIN=zig ./tests/do/run_tests.sh`.
- CI 任务包含 `zig version` 输出与脚本执行步骤, 与本地回归入口保持一致.
- 本地复验 `./tests/do/run_tests.sh`: `pass=12 fail=0`.

## 2026-03-04 16:43:19 | feat | do-integration-regression-harness

- 新增 `tests/do/run_tests.sh`, 建立 `do` 入口级回归框架: 先构建 `bin/do`, 再执行成功/失败用例并校验 `exit code` 与关键输出.
- 新增 `tests/do/cases/ok` 成功用例 3 条, 覆盖 import-only、`done(f,)` 尾逗号、多返回先接收后 `if/match` 正常路径.
- 新增 `tests/do/cases/err` 失败用例 9 条及 `.expect` 断言, 覆盖 `if` 头部、`as`、结构/集合字面量、多返回条件位、不可变重复绑定、私有左值等关键边界.
- 新增 `tests/do/README.md`, 固化目录约定与执行方式, 支持 `ZIG_BIN` 覆盖.
- 实测 `./tests/do/run_tests.sh` 结果: `pass=12 fail=0`.

## 2026-03-04 16:35:55 | fix | multireturn-condition-callsite-location

- `compiler/src/sema.zig` 将 `if/match` 条件位多返回错误定位改为调用表达式位点, 不再固定落在语句关键字起点.
- `checkSingleValuePositions` 改为携带 token 流并记录直接调用节点的 `start_tok`, `MultiReturnInIfCondition/MultiReturnInIfBindRhs/MultiReturnInMatchTarget/AmbiguousConditionCallReturnArity` 统一指向触发调用.
- 新增 `DirectCallSite` 结构, 直接调用识别同时返回函数调用信息与 token 索引.
- 新增 2 条回归测试, 验证 `if pair(...)` 定位到 `pair`(`line=6,col=8`), `match pair(...)` 定位到 `pair`(`line=6,col=11`).
- 回归通过: `zig test compiler/src/sema.zig`, `zig test compiler/src/main.zig`, `zig build -Doptimize=Debug`.

## 2026-03-04 16:32:41 | refactor | diagnostic-nearest-failed-token

- `compiler/src/parser.zig` 新增 `ErrorSite` 上报接口(`takeLastErrorSite`), 在 `if` 头部、`as`、结构/集合字面量、调用参数等失败点写入最近触发 token 位置.
- `compiler/src/sema.zig` 新增 `ErrorSite` 上报接口, 在 `done/wait/cancel/status` 参数错误、`if` 模式绑定错误、私有左值与不可变重复绑定等失败点写入最近触发 token 位置.
- `compiler/src/main.zig` 诊断输出优先消费 `parser/sema` 提供的精确位点, 从“关键词起点”升级为“失败上下文最近 token”.
- 验证样例定位精度提升: `if ok bad {` 指向 `bad`, `as(1, 2)` 指向 `1`, `_x` 重复绑定指向第二次声明.
- 回归通过: `zig test compiler/src/parser.zig`, `zig test compiler/src/sema.zig`, `zig test compiler/src/main.zig`, `zig build -Doptimize=Debug`.

## 2026-03-04 16:29:14 | feat | cli-diagnostic-location-hint

- `compiler/src/main.zig` 编译失败路径改为分阶段诊断输出(`lex/parse/sema/codegen/io`), 失败时统一 `exit(1)`, 移除默认堆栈噪音.
- 新增错误诊断格式: `error[Name] + path:line:col + hint + 行内指针`, 直接定位语法问题.
- 新增错误摘要与规则建议映射, 覆盖 `if` 头部、`as` 转换、结构/集合字面量、async 控制参数等高频错误.
- 新增 token/source 级定位器, 支持 `UnterminatedString` 与多类 parser/sema 错误的最小可用定位.
- `compiler/src/main.zig` 增加 2 条诊断辅助测试, `zig test compiler/src/main.zig` 全量通过.

## 2026-03-04 16:25:45 | fix | parser-sema-syntax-guard

- `compiler/src/parser.zig` 强化函数体表达式语法校验: 赋值 RHS 进入表达式解析, 非法 `as/Struct/List/Map` 字面量不再静默通过.
- `compiler/src/parser.zig` 修复 `if` 头部校验: 拒绝 `if ok bad { ... }` 形态的无效头部残留 token.
- `compiler/src/parser.zig` 修复 `as(T, value)` 目标类型约束, 非类型目标统一报 `InvalidCastExpr`.
- `compiler/src/parser.zig` 收紧字面量规则: `Struct` 仅接受命名参数, `List/Tuple` 仅接受表达式列表, `Map` 仅接受键值对.
- `compiler/src/parser.zig` 支持调用参数尾逗号, `done(f,)` 等合法语法可通过.
- `compiler/src/parser.zig` 顶层计数补齐 `ImportDecl`, import-only 文件不再误报 `NoTopLevelDecl`.
- `compiler/src/sema.zig` 修复 async 控制调用参数计数, 尾逗号不再被误判为额外参数.
- 新增回归测试: `lexer` 增至 2 条, `parser` 增至 9 条, `sema` 增至 22 条, 全量通过.

## 2026-03-04 16:08:06 | refactor | if-match-header-ast

- `compiler/src/parser.zig` 将 `if/match` 条件位提取从按行截断改为表达式级解析, 消除跨行头部的误判路径.
- 新增 `parseExpr` 族函数用于条件位结构化解析, 支持直接调用、`do`、`as`、字面量与常见复合字面量的最小解析.
- `if a { ... }` 场景增加保护回退, 避免把 `a` 误判为 `a{...}` 结构体字面量.
- `compiler/src/sema.zig` 测试扩展到 12 条, 新增跨行 `if/match` 多返回拒绝用例.
- 验证通过: `zig test compiler/src/sema.zig` 与 `zig build -Doptimize=ReleaseSmall`.

## 2026-03-04 16:01:29 | feat | parser-sema-single-value-check

- `compiler/src/parser.zig` 升级为最小结构化解析: 产出函数签名表(`name/参数匹配范围/返回位数`)与 `if/match` 条件位直接调用点表.
- `compiler/src/parser.zig` 新增顶层深度约束, 仅在顶层识别函数声明, 避免 `test {}` 等块内调用被误判为函数定义.
- `compiler/src/sema.zig` 新增基于签名表的单值位语义检查: 禁止多返回函数直接出现在 `if` 条件位、`if` 模式绑定 RHS、`match` 目标位.
- `compiler/src/main.zig` 与 `compiler/src/sema.zig` 同步切换到新 `parseProgram(allocator, tokens, source_len)` 接口并正确释放 Program 资源.
- `compiler/src/sema.zig` 测试扩展到 10 条, 覆盖 `if/match` 多返回拒绝与先接收再使用通过路径.

## 2026-03-04 15:46:21 | feat | syntax-sema-hardening

- 收窄并固化 `doc/syntax.md`: 增加“13. 本轮收窄条件示例”, 覆盖 `done(fid)`, `if` 类型模式绑定, Future 控制面, `_a` 同域唯一, 导入重命名, 箭头多表达式返回, `.x` 私有标识符边界.
- 异步语义文案去除外显 `Task` 控制层描述, 外部控制接口统一为 `Future`.
- `compiler/src/sema.zig` 新增最小语义检查落地: 禁止 `done()`, 校验 `wait/wait_timeout/cancel/status` 参数个数, `if P := expr` 限定为类型模式, 禁止 `.x` 作为赋值左值, 拒绝同作用域 `_a` 重复绑定.
- `compiler/src/sema.zig` 增加 6 条单测覆盖关键边界与通过路径.
- `compiler/src/main.zig` 同步接入 token 级语义检查调用.

## 2026-03-04 15:07:22 | docs | binding-mutability

- 新增绑定可变性约束: `_xxx` 为不可变绑定, `a` 为可变绑定.
- `doc/syntax.md` 的 2.1、6.1 新增 `_` 丢弃位与不可变赋值规则说明.
- `doc/syntax.md` 新增 `12.7 绑定可变性` 冻结条款.

## 2026-03-04 15:05:02 | docs | single-value-if-match

- 新增硬约束: `if` 条件位和 `match` 目标位必须是单值表达式.
- 禁止在 `if/match` 位置直接使用多返回值表达式.
- 要求多返回函数先显式接收, 再在 `if/match` 中使用.
- `doc/syntax.md` 的 6.2、9、12.6 已同步示例与冻结条款.

## 2026-03-04 14:14:37 | docs | multi-return-no-paren

- 在保留 Go 多返回模式下, 将函数返回声明固定为无括号列表写法.
- `doc/syntax.md` 升级到 `v0.8`, 使用 `divmod(a i32, b i32) i32, i32 { ... }`.
- 同步恢复多返回语句与接收语法: `return a, b` 与 `x, y = f(...)`.
- 保持多返回与 `Tuple` 分离语义, 不做隐式互转.

## 2026-03-04 14:11:52 | docs | tuple-return

- 回退 Go 风格多返回值语法, 采纳 Tuple 多值方案.
- `doc/syntax.md` 升级到 `v0.7`, 函数声明恢复单返回类型.
- 多值返回改为 `Tuple<T...>` + 解构接收 `{a, b} = f(...)`.
- 移除 `a, b = f(...)` 与 `return a, b` 语法描述.

## 2026-03-04 14:08:08 | docs | multi-return

- `doc/syntax.md` 升级到 `v0.6`, 引入 Go 风格多返回值语法.
- 函数返回声明支持 `(T1, T2, ...)`, 返回语句支持 `return a, b, ...`.
- 赋值语句支持多返回接收: `x, y = f(...)`, 并支持 `_` 丢弃位.
- 固化多返回与 `Tuple` 分离语义, 不做隐式互转.

## 2026-03-04 14:01:10 | docs | close-conflicts

- 删除临时冲突文档 `doc/conflicts.md`.
- 将 `C01-C05` 最终结论收敛到 `doc/syntax.md` 新增的“12. 冻结决策”章节.
- 语法基线以 `doc/syntax.md` 为唯一收敛入口.

## 2026-03-04 13:58:30 | docs | conflicts-c05

- 按一问一答流程将 `C05` 主项标记为 `[x]`.
- 固化结论: `IntLit -> i32`, `FloatLit -> f64`, 显式转换唯一语法 `as(T, value)`.

## 2026-03-04 13:57:23 | docs | cast-syntax

- 按一问一答流程确认并标记 `C05.3 = [x]`.
- 显式转换语法冻结为 `as(T, value)`.
- `doc/syntax.md` 同步新增 `CastExpr` 与转换规则说明.

## 2026-03-04 13:55:04 | docs | conflicts-c04

- 按一问一答流程将 `C04` 主项标记为 `[x]`.
- 固化结论: 导入统一 `{...} := @("path")`, 仅顶层可用, 支持标准库与相对路径, 禁止隐式全局导入.

## 2026-03-04 13:54:08 | docs | conflicts-c04.3

- 按一问一答流程确认并标记 `C04.3 = [x]`.
- 结论: 禁止隐式全局导入.

## 2026-03-04 13:53:08 | docs | import-path-string

- 导入路径语法统一为字符串形式: `{...} := @("path")`.
- `doc/syntax.md` 示例改为 `@("math")`, `@("../redis")`, `@("./http_client")`.
- `doc/conflicts.md` 的 `C04.2/C04.4` 描述同步为字符串路径导入风格.

## 2026-03-04 13:46:58 | docs | import-syntax

- 导入语法改为解构绑定: `{...} := @source`.
- `doc/syntax.md` 增加多位置导入定义: 标准库路径(`@std/...`)与相对路径(`@./...`, `@../...`).
- `doc/conflicts.md` 标记 `C04.2` 与 `C04.4` 已确认.

## 2026-03-04 13:42:50 | docs | conflicts-c04.1

- 按一问一答流程确认并标记 `C04.1 = [x]`.
- 结论: `@` 仅允许顶层语句起始位置.

## 2026-03-04 13:42:02 | docs | async-controls

- 按用户确认将 `C03` 全部子项标记为已通过, 主项改为 `[x]`.
- `doc/syntax.md` 升级到 `v0.5`, 异步控制面收敛为 `done/wait/wait_timeout/cancel/status`.
- 移除异步控制语法中的 `retry` 及旧聚合等待控制写法.
- 新增并固化内部语义约束: 取消在安全点生效, 且必须执行 `defer` 清理.

## 2026-03-04 13:40:20 | docs | conflicts-c03.2

- 按一问一答流程确认并标记 `C03.2 = [x]`.
- 结论: 保留外部接口 `done(future) -> bool`.

## 2026-03-04 13:39:47 | docs | conflicts-c03.1

- 按一问一答流程确认并标记 `C03.1 = [x]`.
- 结论: 外部最小控制面集合已冻结.

## 2026-03-04 13:38:14 | docs | conflicts-c02

- 按一问一答流程将 `C02` 主项标记为 `[x]`.
- 固化结论: 共享存储 + `RC==1` 原地写 + `RC>1` clone 写 + 用户语义值隔离.

## 2026-03-04 13:36:07 | docs | conflicts-c02.5

- 按一问一答流程确认并标记 `C02.5 = [x]`.
- 结论: COW 示例用例确认为行为基准.

## 2026-03-04 13:35:26 | docs | conflicts-c02.4

- 按一问一答流程确认并标记 `C02.4 = [x]`.
- 结论: 用户可见语义必须保持值隔离.

## 2026-03-04 13:34:45 | docs | conflicts-c02.3

- 按一问一答流程确认并标记 `C02.3 = [x]`.
- 结论: `RC > 1` 时写入必须先 clone 再写.

## 2026-03-04 13:34:15 | docs | conflicts-c02.2

- 按一问一答流程确认并标记 `C02.2 = [x]`.
- 结论: `RC == 1` 时写入走原地更新.

## 2026-03-04 13:33:45 | docs | conflicts-c02.1

- 按一问一答流程确认并标记 `C02.1 = [x]`.
- 结论: 受管对象允许共享底层存储, 写路径走 COW.

## 2026-03-04 13:30:00 | docs | overload-resolution

- 按用户给定 5 条决策完成 `C01` 收敛并标记为已解决.
- 新增并冻结规则: 具体类型优先, 类型集重叠报错, 同文件签名约束重叠禁用, 变参按固定前缀长度决议.
- 同步 `doc/syntax.md` 的 5.1 重载规则与示例.
- 冻结字面量默认类型: `IntLit -> i32`, `FloatLit -> f64`.

## 2026-03-04 13:20:08 | docs | conflicts-c01.4

- 按一问一答流程确认并标记 `C01.4 = [x]`.
- 结论: 变参匹配始终排在固定参数匹配之后.

## 2026-03-04 13:18:45 | docs | conflicts-c01.3

- 按一问一答流程确认并标记 `C01.3 = [x]`.
- 决策: 删除结构约束 `#T{...}`, 仅保留 `#T: ...` 类型限制与函数签名约束.
- `doc/syntax.md` 升级到 `v0.4`, 同步移除 `TypeShapeConstraint` 与相关示例.

## 2026-03-04 13:13:00 | docs | conflicts-c01.2

- 按一问一答流程确认并标记 `C01.2 = [x]`.
- 结论: 非泛型精确匹配优先于泛型匹配.

## 2026-03-04 13:12:11 | docs | conflicts-c01.1

- 按一问一答流程确认并标记 `C01.1 = [x]`.
- 结论: 重载决议顺序必须全局固定, 不随文件或上下文变化.

## 2026-03-04 13:10:58 | docs | conflicts-flow

- `doc/conflicts.md` 的 `C01` 回退为未确认状态.
- 撤销一次性定稿写法, 改为一问一答逐项确认流程.
- 后续仅在用户给出单项决策后标注对应 `[x]`.

## 2026-03-04 13:08:07 | docs | conflicts-c01

- 完成 `doc/conflicts.md` 的 `C01` 冲突收敛并标记为已解决.
- 固化重载决议顺序: 非泛型精确匹配 -> 泛型精确匹配 -> 变参匹配.
- 固化并列消歧规则: 约束超集优先, 仍并列时报 `AmbiguousOverload`.
- 补充示例判定结果: 示例 A 报二义性, 示例 B 选择固定参数版本.

## 2026-03-04 13:06:42 | docs | conflicts-checklist

- `doc/conflicts.md` 改为"主冲突 + 子分支"全量勾选格式.
- 每个冲突新增 `Cxx.n` 子项, 支持部分完成后先打勾.
- 已确认规则区同步改为 `[x]` 复选状态.

## 2026-03-04 13:00:55 | docs | conflicts

- 新增 `doc/conflicts.md` 作为临时冲突跟踪文档.
- 将当前语法争议拆分为可逐条关闭的 `C01` 到 `C05`.
- 收敛本轮已确认规则到同一文档, 便于后续逐条删除冲突项.

## 2026-03-04 12:29:46 | chore | build-output

- `compiler/build.zig` 固定安装前缀到项目根目录。
- `zig build` 产物输出从 `compiler/zig-out/bin/do` 调整为 `bin/do`。
- `README.md` 构建产物路径说明同步更新为 `bin/do`。

## 2026-03-04 12:25:29 | fix | arraylist-api

- 适配 Zig 0.15 的 `std.ArrayList` API 变更。
- `compiler/src/lexer.zig` 改为 `initCapacity/deinit(allocator)/append(allocator,...)/toOwnedSlice(allocator)`。
- 修复词法阶段在新工具链上的编译失败。

## 2026-03-04 12:24:07 | fix | zig-0.15

- 适配 Zig 0.15 标准输出 API: `std.io.getStdOut` 改为 `std.fs.File.stdout().writer(...)`。
- `compiler/src/main.zig` 的成功输出与 `printUsage` 均改为 `writer.interface.print + flush`。
- 修复 `zig build` 在当前工具链上的后续编译错误。

## 2026-03-04 12:22:27 | fix | build-api

- 修复 `compiler/build.zig` 与当前 Zig API 不兼容问题。
- `addExecutable` 从 `root_source_file` 改为 `root_module` 写法。
- 通过 `b.createModule` 传入 `src/main.zig`、`target`、`optimize` 参数。

## 2026-03-04 12:14:39 | chore | build-layout

- 将构建入口从根目录移动到 `compiler/build.zig`。
- 删除根目录 `build.zig` 与 `build.sh`, 收敛为单一 Zig 构建路径。
- `README.md` 构建命令改为 `cd compiler && zig build -Doptimize=ReleaseSmall`。
- 目录结构说明新增 `compiler/build.zig`。

## 2026-03-04 12:13:03 | chore | build

- 新增根目录 `build.zig`, 建立 Zig 官方构建入口。
- 构建目标固定为 `compiler/src/main.zig`, 可执行名为 `do`。
- 增加 `run` step, 支持 `zig build run -- <args>` 透传参数。
- 更新 `README.md` 构建说明, 同时保留 `zig build` 与 `./build.sh` 两条路径。

## 2026-03-04 12:10:18 | feat | compiler-src

- 新增 `compiler/src` 扁平模块: `lexer.zig`, `parser.zig`, `sema.zig`, `codegen.zig`。
- 重写 `compiler/src/main.zig` 为真实编译入口流程: 读源文件 -> 词法 -> 语法 -> 语义 -> 生成 WAT。
- 更新 `build.sh` 构建路径为 `compiler/src/main.zig` 并输出到 `bin/do`。
- 更新 `README.md` 的目录结构与构建说明, 明确 `compiler/src` 与 `lib` 扁平化约束。

## 2026-03-04 12:07:08 | chore | root-layout

- 目录结构收敛为: `doc`, `bin`, `lib`, `compiler/src`。
- 将原 `do/doc`, `do/bin`, `do/lib` 提升到根目录并删除中间层目录。
- 删除空 `zig/` 目录, 新增 `compiler/src/main.zig` 作为编译器入口文件。
- 更新 `build.sh` 路径为 `compiler/src/main.zig -> bin/do`。
- 更新 `README.md` 的文档与目录路径说明为新结构。

## 2026-03-04 11:59:33 | docs | root

- 重命名日志文件: `.dev.log.md` -> `CHANGELOG.md`。
- 重命名语法目录: `do/spec` -> `do/doc`，并删除 `spec` 下残留 `.do` 与 `README.md`。
- 同步更新文档引用到 `do/doc/syntax.md`。

## 2026-03-03

### docs: gc 方案升级到 v5.0

1. 重写 `gc.md`，确认主路径为“编译器隐式插入 `inc/dec` + Perceus 复用”。
2. 增加生命周期插桩规则: 赋值、调用、返回、分支合流、循环回边、作用域清理。
3. 增加运行时策略: RC 溢出 side table、迭代式 worklist 释放、cycle fallback 触发条件。
4. 明确默认元数据配置为 B (`u16 RC + u16 TypeID`)。

### docs: README 对齐运行时模型

1. 补充“隐式 RC 生命周期管理”说明。
2. 修正 WASM 分页描述为 `64KB page + 4KB 子页`。
3. 增加“循环回收兜底”说明，避免和 v5 GC 设计不一致。

### docs: 放弃 move 语言设计

1. `gc.md` 删除 `move` 术语，改为“末次使用优化”描述。
2. `README.md` 同步删除 `move` 表述，保持对外语义仅为值传递。

### docs: 明确最终不引入循环 GC

1. `gc.md` 升级到 v5.1，移除 cycle fallback 章节。
2. 新增 Future/Task/FFI 去环约束: ID 关联、禁止双向强引用、FFI 显式 close。
3. 将验证策略改为“无环图校验 + CI 门禁”，不实现 cycle collector。
4. `README.md` 同步改为“无环运行时图”描述。
5. 本条作为新基线，覆盖当日早些时候“循环回收兜底”方向。

### docs: 新增无色异步语义规范

1. 新增 `do/spec/async.md`，定义 `do` 为唯一并发入口。
2. 固化 Future 控制面语义: `done/any_done/all_done/cancel/retry/set_timeout`。
3. 明确单线程异步可行条件: 协作调度 + 非阻塞宿主接口。
4. 明确边界: 纯计算可弱依赖运行时，真实 I/O 异步不能脱离宿主事件源。
5. `README.md` 增加异步语义规范入口。

### docs: 新增 COW 大小数据界分规则

1. `gc.md` 在运行时章节新增 `COW 与大小数据界分`。
2. 固化初始界分阈值为 `64B`，定义小数据直拷与大数据共享+COW路径。
3. 补充写路径规则: `RC==1` 原地改，`RC>1` 先 clone 再改。
4. 增加可执行判定伪代码，作为编译器与运行时统一策略。
5. `README.md` 同步增加“大小数据分层策略”摘要。
6. 补充“特殊边界限制”: 高写频结构、读多写少结构、FFI 跨边界可变内存策略。

### spec: 语法一致性收敛

1. `future.do` 统一为单一异步语法: `do call(...)`，移除并行备选写法。
2. `match.do` 移除守卫/谓词式模式，改为纯模式匹配示例。
3. `Text/List` 命名统一为大写受管类型。
4. 清理 `.{}` / `Type.{}` 旧写法，统一为 `{}` / `Type{}`。
5. `loop` 标签位置已统一，按当期语法基线执行。
6. `union.do` 将 `Error` 统一为类型与构造器命名。
7. `struct.do` 回退私有声明风格: 移除 `private` 关键字，私有字段恢复为前置 `.`。
8. `fn.do` 新增私有函数示例: 采用前置 `.` 的 `.normalize_name`，并由公有函数调用。

### docs: 新增语法基线规范

1. 新增 `do/spec/syntax.md`，固化语法解析基线与 EBNF。
2. 明确私有字段/私有函数采用前置 `.`，不使用 `private`。
3. 明确并发入口唯一为 `do call(...)`，移除 `do(...)` 形式。
4. 明确 `match` 不使用守卫语法，不在模式中写谓词表达式。
5. 明确解构统一 `{a, b}`，不再使用 `.{a, b}`。
6. `README.md` 增加语法基线入口，避免后续语法分叉。

### spec: match 语法改为纯语句分派

1. 取消 `match` 赋值语法: 不再支持 `n = match ...`。
2. 分支分隔符统一为 `=>`，支持 `=> { ... }` 与 `=> stmt`。
3. `do/spec/match.do` 全部示例改为语句式 `match`。
4. `do/spec/union.do` 的 `x = match ...` 示例同步改为语句式分派。
5. `do/spec/match.do` 重新整理为基线示例集: 覆盖 `Type(var)`、`Type{field}`、字面量模式与 `_` 兜底。

### spec: 移除旧语法示例, 保留最小最新基线

1. 新增 `do/spec/README.md`，声明规范最小集合。
2. 仅保留 `syntax.md`、`async.md`、`match.do`、`future.do`。
3. 移除历史示例文件: `bit/fn/if/import/list/loop/map/struct/text/tuple/union`。
4. `README.md` 增加最小规范集合入口，防止旧示例回流。

## 2026-03-04

### spec: loop 标签位置调整

1. `loop` 标签语法固定为 `{` 右侧: `loop { 'label ... }`。
2. `do/spec/syntax.md` 的 EBNF 与示例已对齐为右置标签形式。
3. 本条覆盖旧记录中的标签前置表述，避免后续实现歧义。

### docs: syntax.md 展示每一种用法

1. `do/spec/syntax.md` 升级到 `v0.3`，重组为“语法定义 + 对应最小示例”结构。
2. 补齐顶层声明示例: `import/type/func/test` 全覆盖。
3. 补齐语句示例: `assign/if(loop+label)/break/continue/return/defer/match` 全覆盖。
4. 补齐表达式示例: `call/do/lambda/struct/list/map/tuple/literal` 全覆盖。
5. 保持现有基线不变: `loop { 'label ... }`、`match` 语句化、`do call(...)` 唯一入口。

### docs: syntax 用法分项命名

1. `do/spec/syntax.md` 将各章节示例统一改为“用法命名”格式。
2. 为顶层、类型、函数、if、loop、表达式、解构、match 分别增加可引用名称。
3. 在代码块内加对应注释标签，便于评审、测试和实现映射。

### docs: syntax 用法命名内嵌化

1. 删除所有外部“用法命名”列表，避免规范正文重复。
2. 用法命名统一改为代码内注释，格式固定为 `// 序号. 中文(English)`。
3. `loop` 区域同步采用内嵌命名，保留右置标签基线 `loop { 'label ... }`。

### docs: syntax 英文命名统一为两段式

1. 代码内注释英文名统一为 `Domain.Name`，不再使用连字符风格。
2. 命名收敛示例: `Loop.Basic`、`Pattern.Wildcard`、`Stmt.Assign`。
3. 保留注释格式不变: `// 序号. 中文(English)`。

### spec: 恢复函数泛型约束与重载规则

1. `do/spec/syntax.md` 的 `FuncDecl` 恢复函数级泛型约束: `FuncName<TypeParams>(...)`。
2. 函数示例新增 `Func.GenericConstraint`，明确函数泛型约束未被移除。
3. 新增 `5.1 函数重载规则`: 支持同名重载, 禁止仅返回类型重载, 精确类型优先于泛型。
4. 明确重载歧义处理: 同优先级候选在编译期报错, 不使用隐式数值拓宽参与决议。
5. `README.md` 核心理念同步增加“函数式与重载”说明。

### spec: 函数泛型约束切换为 # 前置语法

1. `do/spec/syntax.md` 的函数声明改为 `FuncConstraint* + FuncDecl` 组合。
2. 新增两类约束: 结构约束与函数签名约束。
3. 移除函数级 `<T: ...>` 写法, 统一改为 `TypeVar` 自动引入。
4. 重载优先级改为: 精确类型 > `#` 约束泛型 > 无约束泛型。
5. `README.md` 同步声明: 类型泛型用 `Name<T>`, 函数泛型用 `#` 前置约束。
6. 本条覆盖上一条中“函数级 `<T: ...>`”描述, 以 `#` 前置约束为新基线。

### spec: 增加类型集约束与聚合模式

1. `do/spec/syntax.md` 新增 `TypeSetAliasDecl` 与 `TypeSetExpr`，支持 `SignedInt = i8 | i16 | ...`。
2. 函数约束新增 `TypeSetConstraint`: `#T: i8 | i16 | ...` 与 `#T: SignedInt`。
3. 新增区分规则: `TypeSetAliasDecl` 右侧必须含 `|`, 避免与普通 `AliasDecl` 混淆。
4. 函数示例补齐类型集字面量与聚合别名两种用法。
5. `README.md` 核心理念同步声明“类型集约束与聚合别名”。

### spec: 函数签名约束去除形参名

1. `FuncSigConstraint` 改为仅类型签名: `name(TypeList?) => RetType`。
2. 约束示例统一为 `#min(T, T) => T`、`#to_text(T) => Text`。
3. 增加规则: 函数签名约束只写类型列表, 不写形参名。

### spec: 同类型不定参数与调用扁平化

1. `do/spec/syntax.md` 的参数语法新增 `VariadicParam`: `name ...Type`。
2. 明确限制: 不定参数只能在末尾, 且实参类型必须与 `...Type` 一致。
3. 重载示例中的聚合调用统一为扁平写法: `add(a, b, c)`。
4. 新增 `5.2` 章节, 定义扁平化等价: `f(f(x1, x2), x3)` => `f(x1, x2, x3)`。
5. 约束边界: 仅当目标函数纯且满足结合律时可做该改写, 否则保持原结构。
6. `README.md` 核心理念同步新增“同类型不定参数”说明。

### spec: 扁平化白名单基线

1. `do/spec/syntax.md` 新增 `5.3` 章节, 固化默认扁平化白名单。
2. 白名单函数为 `add/mul/and/or`, 并按类型收窄适用范围。
3. 明确 `f32/f64` 的 `add/mul` 默认禁止自动扁平化。
4. 非白名单函数保持原调用结构, 编译器不做自动改写。
5. `README.md` 补充“自动扁平化仅对白名单启用”说明。

### spec: 扁平化改为签名驱动

1. 删除白名单章节与白名单规则, 不再通过函数名控制扁平化.
2. 扁平化能力改为由签名决定: `f(a T, b T, rest ...T) T` 即支持该重载实例扁平化.
3. `5.2` 规则改为签名判定路径: 满足签名可改写, 不满足则保持原结构.
4. `README.md` 同步改为“是否可扁平化由函数签名决定”.
5. 本条覆盖上一条“扁平化白名单基线”方向.

### spec: 结构体泛型约束移除 Any

1. `TypeParam` 改为 `Ident [ ":" TypeSetRef ]`, 结构体泛型约束仅允许类型集引用。
2. 明确不支持 `Any` 关键字, 无约束泛型参数直接写 `T`。
3. 示例从 `Box<T: Any>` 改为 `Box<T>`。
4. 新增类型集约束结构体示例: `Counter<T: i8 | i16 | i32 | i64>`。
5. 明确结构体不承载函数能力约束, 函数签名约束仅放在函数 `#` 区域。
6. `README.md` 同步补充“结构体泛型不支持 Any”。

### spec: 异步语法并入 syntax 并移除 async.md

1. `do/spec/syntax.md` 第 7 章新增异步控制语法: `done/any_done/all_done/cancel/retry/set_timeout`。
2. 异步核心语义并入 `syntax.md`: `do` 单入口, Future 控制规则, 取消与重试约束。
3. `do/spec/async.md` 删除, 不再作为独立规范文件。
4. `do/spec/README.md` 调整最小基线列表, 移除 `async.md` 引用。
5. `README.md` 异步说明改为指向 `do/spec/syntax.md`。

### docs: 移除 .do 规范示例并重命名目录

1. 删除 `do/spec` 下剩余 `.do` 文件: `future.do`、`match.do`。
2. 删除 `do/spec/README.md`。
3. 目录从 `do/spec` 重命名为 `do/doc`，保留 `syntax.md` 作为唯一基线文档。
4. `README.md` 路径引用同步更新为 `do/doc/syntax.md`。
5. 本条覆盖“最小规范集合包含 spec/README 与 .do 示例”的旧方向。
