# 内部前缀重命名设计

## 1. 目标

将仓库内所有编译器生成的内部符号、测试导出名、运行时内部属性名，从旧内部前缀统一重命名为新前缀 `__`。

本次是一次性收敛，不保留兼容别名，不做双写，不保留旧名字兜底。

## 2. 背景

当前仓库内部前缀过长，主要分布在以下几类位置:

1. 编译器生成的 wasm 全局、局部、label、helper 名称。
2. compiled test 导出的测试函数名与测试 harness 匹配规则。
3. JS runtime 挂在 DOM 元素上的内部属性。
4. 文档中对上述内部名字的实现约定说明。

已经确认的真实落点包括:

1. `tool/build/codegen.zig`
2. `tool/build/test/run_compiled_test_case.mjs`
3. `tool/build/test/README.md`
4. `doc/spec_rules.md`
5. `doc/memory.md`
6. `doc/implementation_plan.md`
7. `js/runtime.js`

## 3. 变更规则

统一规则:

1. 所有内部前缀都改为 `__`。
2. 旧前缀后面的语义部分保持不变，只去掉中间那段 `do_`。
3. 这条规则同时作用于:
   - wasm global / local / func / label 名称
   - compiled test export 名称
   - JS runtime 内部属性名
   - 文档中的实现约定与示例

映射示例:

1. `__test_0`
2. `__heap_base`
3. `__arc_alloc`
4. `__loop_break_3`
5. `__field_continue_2_1`
6. `__handlers`

对应旧名字都只是去掉 `do_` 这一段，不改变后续语义段。

## 4. 范围

纳入本次变更:

1. `tool/build/codegen.zig` 中所有内部符号生成与引用。
2. compiled test harness 对测试导出名的识别、排序与回退逻辑。
3. regression fixture 和 `.expect` 中固化的内部名字。
4. `js/runtime.js` 中运行时内部属性名。
5. `doc/` 与测试 README 中仍在描述当前实现的相关文档。

不纳入本次变更:

1. 语言名 `do`。
2. 文件扩展名 `.do`。
3. CLI 命令 `do`。
4. 用户源码语法、关键字、标准库 API 名。
5. 仓库名、目录名、历史 commit。

## 5. 兼容策略

不做兼容。

具体约束:

1. 不接受新旧前缀并存。
2. 不添加 alias、双 regex、双属性读写。
3. 改完后，仓库实现层只认新前缀。

## 6. 风险与处理

### 6.1 compiled test runner 失配

风险:
`run_compiled_test_case.mjs` 目前按旧测试导出名前缀做正则匹配和排序，若只改 codegen 不改 harness，会导致 compiled test 找不到测试函数。

处理:
同步修改 codegen 导出名、runner 正则、fallback 名称和相关 `.expect`。

### 6.2 文档与实现漂移

风险:
如果只改代码，不改 `doc/spec_rules.md`、`doc/memory.md`、`doc/implementation_plan.md` 等文档，会继续传播旧实现名。

处理:
把仍然描述“当前实现”的文档一起同步到新前缀。

### 6.3 JS runtime 内部属性不一致

风险:
`js/runtime.js` 内部属性若仍保留旧前缀，后续如果编译产物或辅助工具按新约定读写，会产生运行时不一致。

处理:
同步改成新属性名，不保留旧属性回退。

## 7. 验收标准

满足以下条件才算完成:

1. 受影响实现文件全部改为新前缀。
2. 相关测试 fixture、`.expect`、README、实现文档同步完成。
3. `rg -n "__do_" tool js doc` 无残留，若设计文档本身需要描述旧前缀，则单独排除该设计文件。
4. `./tool/build/test/run_tests.sh` 通过。

## 8. 实施顺序

推荐顺序:

1. 先改 compiled test 相关测试，制造失败基线。
2. 再改 `tool/build/codegen.zig` 与 `tool/build/test/run_compiled_test_case.mjs`。
3. 再改 `.expect`、README、实现文档。
4. 最后做全量检索与回归测试。

## 9. 非目标

本次不顺手做以下事情:

1. 不重构命名体系之外的 codegen 结构。
2. 不调整用户可见语法设计。
3. 不引入新的 runtime helper 或测试协议。
4. 不处理与这次前缀收敛无关的脏工作树内容。
