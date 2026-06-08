# 全面审查问题清单

状态: 非 WASI 主线问题 01-06 已处理; 问题 07 WASI 延后。

范围: 当前工作树相对 HEAD 的非 WASI 主线问题优先; WASI 相关只放最后。

当前验证:

- `./tool/build/test/run_tests.sh`: `pass=542 fail=0`
- `zig test tool/build/lexer.zig`: 9/9 passed
- `zig test tool/build/parser.zig`: 19/19 passed
- `zig test tool/build/test_runner.zig`: 13/13 passed
- `zig test tool/build/sema.zig`: 0 tests passed
- `cd tool && zig build test`: 无 `test` step
- `RUN_WASM=1 ./tool/build/test/run_tests.sh`: 本轮未运行; WASI 按非现阶段目标延后。

## 处理顺序

推荐顺序:

1. 问题 01: 跨模块函数/host import 符号身份丢失
2. 问题 02: 根模块 `.field` 扫描误报
3. 问题 03: 导入模块未完整 parse/sema
4. 问题 04: `to_isize` 保留名漏项
5. 问题 05: CLI `-o` 参数顺序不一致
6. 问题 06: 文档与源码边界残留不一致
7. 问题 07: WASI 残余风险最后处理

当前处理状态: 问题 01-06 已处理; 问题 07 按非现阶段目标延后。

## 问题 01: 跨模块函数/host import 符号身份丢失

分级: P1

状态: done

结论: 不能按裸函数名或裸 host alias 在全局 WAT 命名空间去重。模块 A 和模块 B 的内部 `helper` 或 `host` 是不同身份, 但当前 codegen 会合并。

证据:

- `tool/build/codegen.zig:5724` 递归收集导入函数。
- `tool/build/codegen.zig:5765` 用 `findFuncDecl(out.items, visit.name)` 按裸名去重。
- `tool/build/codegen.zig:2961` 收集模块 env host import。
- `tool/build/codegen.zig:2974` 用 `findHostImport(out.items, host_import.alias)` 按裸 alias 去重。

反例:

```do
// a.do
value() -> i32 {
    return helper()
}

helper() -> i32 {
    return 1
}

// b.do
value() -> i32 {
    return helper()
}

helper() -> i32 {
    return 2
}

// main.do
a_value = @lib("./a.do", value)
b_value = @lib("./b.do", value)

start() {
    x i32 = a_value()
    y i32 = b_value()
    return
}
```

当前风险: 生成 WAT 只保留一个 `$helper`, `a_value` 和 `b_value` 都调用同一个 `$helper`。

正例:

```wat
(func $__mod_a__value (result i32)
  call $__mod_a__helper)

(func $__mod_a__helper (result i32)
  i32.const 1)

(func $__mod_b__value (result i32)
  call $__mod_b__helper)

(func $__mod_b__helper (result i32)
  i32.const 2)
```

选项: A

- A. 给所有导入模块函数和 host import 生成模块限定内部符号名, 调用点通过模块身份解析到限定符号。
- B. 禁止可达导入模块出现同名内部函数或同名 host alias。
- C. 导入函数只允许直接 public wrapper, 不递归收集内部函数。

推荐: A。它符合模块边界语义, 不强迫标准库和用户模块全局避名, 也不会减少可表达能力。B 是临时规避, C 会破坏普通 wrapper 能力。

验收:

- 添加两个导入模块同名 `helper()` 的 compile_ok 或 compiled_ok 用例。
- 添加两个导入模块同名 `host = @env(...)` 但不同 field 的 compile_ok 用例。
- WAT 里不同模块符号必须不同, 调用点必须指向各自模块符号。

处理结果:

- `tool/build/codegen.zig` 使用模块限定内部符号名收集导入模块函数和 env host import。
- 函数调用和 host import 调用按 token 所属模块优先解析到对应 `source_name/source_alias`。

验证:

- `tool/build/test/compiled_ok/14_compiled_test_imported_helper_collision.do`
- `tool/build/test/compiled_ok/15_compiled_test_imported_host_collision.do`

## 问题 02: 根模块 `.field` 扫描误报

分级: P1

状态: done

结论: `checkPrivateLValueAssign` 只按同一行后续 `=` 判断 private lvalue, 没有按括号、调用参数和聚合字面量深度排除 `@get(..., .field)`。

证据:

- `tool/build/sema.zig:105` `checkPrivateLValueAssign`
- `tool/build/sema.zig:112` 在同一行查找 `=`
- `tool/build/sema.zig:116` 直接报 `PrivateIdentCannotBeLValue`
- 已命中源码: `src/base64.do:29`, `src/hash_map.do:136`, `src/simd.do:30`

反例:

```do
S {
    a i32
    b i32
}

test "field segment before later named arg" {
    s S = S{a = 1, b = 2}
    t S = S{a = @get(s, .a), b = 3}
    if @eq(@get(t, .a), 1) return
}
```

当前结果: `.a` 被误报 `PrivateIdentCannotBeLValue`。

正例:

```do
test "field segment before later named arg" {
    s S = S{a = 1, b = 2}
    t S = S{a = @get(s, .a), b = 3}
    if @eq(@get(t, .a), 1) return
}
```

期望结果: 通过。

选项: B

- A. 让 `checkPrivateLValueAssign` 做深度感知, 只检查真正的赋值左侧 token。
- B. 复用 parser 产出的 statement/value expr 边界, 不再用全文件 token 扫描判断 lvalue。
- C. 放宽所有 `.lower` 的 lvalue 检查。

推荐: A 或 B。短期推荐 A, 变更小且可直接修复当前误报; 后续推荐 B, 把 token 扫描收敛到 parser/sema 结构边界。C 不推荐, 会放过真实 private lvalue 错误。

验收:

- 新增 ok 用例覆盖 `S{a = @get(s, .a), b = 3}`。
- 保留 err 用例覆盖 `.name = value` 仍报错。
- `src/base64.do`, `src/hash_map.do`, `src/simd.do` 作为根模块至少能走到 `NoTestDecl` 或自身真实测试结果, 不再在 `.field` 误报。

处理结果:

- `tool/build/sema.zig` 的 private lvalue 检查收敛为行首左值 + 同行顶层赋值判断, 不再把 RHS 调用参数里的 `.field` 当作左值。
- 标准库源码自检已纳入 `run_tests.sh`, 继续保留 `.name = value` 负例。

验证:

- `tool/build/test/ok/125_field_segment_before_named_arg.do`
- `tool/build/test/err/37_private_lvalue_assign.do`
- `./tool/build/test/run_tests.sh` 的 `std src` 段

## 问题 03: 导入模块未完整 parse/sema

分级: P1

状态: done

结论: 根模块会 parse 和 sema, 但导入模块只 tokenize 并做局部导入/符号检查。这会让无效标准库源码在被导入时通过, 导致测试假绿。

证据:

- `tool/build/run.zig:77` 根模块 parse。
- `tool/build/run.zig:83` 根模块 sema。
- `tool/build/imports.zig:260` 导入模块只读取并 tokenize。
- `tool/build/imports.zig:286` 后续只做 import/声明类别相关检查。

反例:

```bash
DO_LIB_ROOT=src ./bin/do test src/base64.do
```

当前结果: `src/base64.do:29` 报 `PrivateIdentCannotBeLValue`。

但外部导入 `with_padding = @lib("base64.do", with_padding)` 并调用可以通过。

正例:

```bash
for f in src/*.do; do
  DO_LIB_ROOT=src ./bin/do test "$f"
done
```

期望: 有测试的库运行测试; 无测试的普通库最多报 `NoTestDecl`; 不应出现语法/语义错误被导入路径绕过。

选项: A

- A. `imports.checkAndLoad` 对每个导入模块执行 parse + sema, 并把 program 缓存在 `ModuleRecord` 或单独缓存。
- B. 增加一套导入模块专用 sema 子集, 只补当前漏检项。
- C. 只给 `src/*.do` 加单文件自检脚本, 不改导入模块语义检查。

推荐: A。导入模块也是源码模块, 应该使用同一套 parser/sema 规则。B 会继续制造两套语义边界。C 可作为测试补充, 不能替代根因修复。

验收:

- 新增导入模块含非法 `.field` 误用的 err 用例, 从外部导入时也失败。
- 标准库单文件自检纳入 `run_tests.sh` 或新增明确脚本。
- 修复后 `src/*.do` 自检只剩预期的空文件/注释表边界。

处理结果:

- `imports.checkAndLoad` 对读取到的导入模块执行 `parser.parseProgram` 与 `sema.checkProgram`。
- `run_tests.sh` 对 `src/*.do` 做单文件自检, 并显式跳过元数据说明表 `src/_.do`。
- `src/list.do`, `src/set.do`, `src/http.client.do` 已清理到能通过完整 parse/sema; 无测试 std 模块只保留 `NoTestDecl` 边界。

验证:

- `tool/build/test/err/265_imported_module_full_sema.do`
- `./tool/build/test/run_tests.sh` 的 `std src` 段

## 问题 04: `to_isize` 保留名漏项

分级: P2

状态: done

结论: `to_isize` 在 parser/codegen/spec/core 表里存在, 但 sema 保留名集合漏掉它, 导致可以声明同名普通函数。

证据:

- `tool/build/parser.zig:2272` 标量转换名包含 `to_isize`。
- `tool/build/codegen.zig:5169` core 调用名包含 `to_isize`。
- `tool/build/sema.zig:6272` `isBuiltinSpecialOrCoreName` 缺少 `to_isize`。

反例:

```do
to_isize(x i32) -> isize {
    return @to_isize(x)
}

test "decl allowed" {
    return
}
```

当前结果: 声明可以通过。

正例:

```do
test "core convert" {
    i i8 = 1
    y isize = @to_isize(i)
    if @eq(y, 1) return
}
```

期望: `@to_isize(...)` 可用, 但普通声明 `to_isize(...)`、导入 alias `to_isize = ...`、参数名 `to_isize` 都按 core 保留名拒绝。

选项: A

- A. 把 `to_isize` 加入 sema 所有 core/special 保留名集合。
- B. 从 spec/parser/codegen 移除 `to_isize`, 暂不支持 signed pointer-size 转换。

推荐: A。`isize` 类型已被实现和测试使用, core 表也已经声明 `@to_isize`; 补齐保留名比删能力更一致。

验收:

- 新增 err 用例: `to_isize(x i32) -> isize` 声明报保留名。
- 新增 ok 用例: `@to_isize(1)` 正常。

处理结果:

- `tool/build/sema.zig` 已把 `to_isize` 加入 builtin/core 调用名和声明保留名集合。
- `doc/spec.md` 已把 `to_isize` 补入 core 固定转换名集合。

验证:

- `tool/build/test/err/266_core_to_isize_decl.do`
- `tool/build/test/ok/126_core_to_isize_convert.do`

## 问题 05: CLI `-o` 参数顺序不一致

分级: P2

状态: done

结论: `do build -o out input.do` 会成功但输出到默认 `out.wat`; `do test --compiled -o out input.do` 又能正确输出到指定路径。CLI 行为不一致, 且静默忽略用户给的路径。

证据:

- `tool/build/cli.zig:10` `parseBuild` 支持扫描输入前的选项。
- `tool/build/cli.zig:58` `parseOutputPath` 从固定下标 2 开始扫。

反例:

```bash
./bin/do build -o /tmp/custom.wat /tmp/main.do
```

当前结果: 写到 `out.wat`, `/tmp/custom.wat` 不存在。

正例:

```bash
./bin/do build -o /tmp/custom.wat /tmp/main.do
./bin/do build /tmp/main.do -o /tmp/custom.wat
```

期望: 两种顺序要么都正确, 要么前一种明确报 CLI 语法错误; 不能静默写默认路径。

选项: A

- A. `parseBuild/parseTest` 单次扫描时同时解析 input/output/options, 删除独立固定下标扫描。
- B. 明确禁止 input 前的 `-o`, 并在遇到时直接报错。

推荐: A。当前解析器已经接受选项前置, 继续做成一致的自由顺序更符合实际 CLI 使用。

验收:

- 增加 CLI 单元或 shell 回归覆盖 `build -o out input.do`。
- 覆盖 `test --compiled -o out input.do` 不回退。

处理结果:

- `tool/build/cli.zig` 在 `parseBuild/parseTest` 单次扫描中同时解析 input、output 和选项。
- `run_tests.sh` 增加 `cli output_order` 回归, 覆盖 build 和 compiled test 的前置 `-o`。

验证:

- `./tool/build/test/run_tests.sh` 的 `cli output_order` 段

## 问题 06: 文档与源码边界残留不一致

分级: P3

状态: done

结论: 文档主体基本已经跟上 `@core` 语法, 但 README 和 `src/_.do` 的定位仍容易误导。

证据:

- `README.md:13` 仍写“成员访问统一使用 `get`/`set` 函数”。
- `doc/spec.md:1626` 写 `src/_.do` 只放 builtin/core 声明表。
- `src/_.do:1` 实际全是注释, 作为普通源码会 `EmptyProgram`。
- `src/leb128.do` 是未跟踪空文件, 单文件自检为 `EmptySource`。

反例:

```bash
DO_LIB_ROOT=src ./bin/do test src/_.do
DO_LIB_ROOT=src ./bin/do test src/leb128.do
```

当前结果: `src/_.do` 报 `EmptyProgram`; `src/leb128.do` 报 `EmptySource`。

正例: A

```md
src/_.do 是 core 能力说明表, 不是普通 import 目标, 不参与普通源码测试。
成员访问使用 `@get/@set(...)`, 不是普通 `get/set` 函数。
```

选项:

- A. 文档明确 `src/_.do` 是注释说明表并在标准库自检中跳过它; 删除或填充 `src/leb128.do`。
- B. 把 `src/_.do` 改成可解析的声明表语法, 让它能作为普通模块通过。

推荐: A。当前编译器并不真实加载 `src/_.do` 作为源码声明, 强行做成普通模块会引入伪语义。`src/leb128.do` 若没有实现, 应删除或移入 pending。

验收:

- README 改成 `@get/@set`。
- 标准库自检脚本显式跳过说明表文件, 或说明其非源码性质。
- 空文件不留在 `src/*.do` 的普通库集合里。

处理结果:

- `README.md` 已改成 `@get/@set(...)` 路径 primitive。
- `src/_.do` 声明自身是 builtin/core 注释说明表, 非普通 import 目标。
- `run_tests.sh` 标准库自检显式跳过 `src/_.do`; 当前 `src/leb128.do` 不在普通库集合内。

验证:

- `README.md`
- `src/_.do`
- `./tool/build/test/run_tests.sh` 的 `std src` 段

## 问题 07: WASI 残余风险

分级: P3

状态: deferred

结论: 本轮不作为优先目标。已有 `RUN_WASM=1` 回归通过, 但 WASI/component lowering 仍是大面变更, 等非 WASI 主线收敛后再处理。

建议: 延后

- 暂不扩展 WASI 范围。
- 只保留现有回归作为守门。
- 等问题 01-06 处理完后, 再单独审查 WASI binding source/alias、component-core 和 result-area lowering。

推荐: 延后。
