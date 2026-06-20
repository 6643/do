# B2 sema 冻结审查问题

状态: pending user decision; issue 1-4 fixed

范围: 对照 `doc/spec_rules.md`、`doc/spec.md`、`doc/syntax/*.md`、`tool/build/sema.zig` 和 `tool/build/codegen.zig` 的静态语义边界。

原则: 本文件只收集待决问题; 不改正式语法和语义规则正文。用户选定并落地后, 删除本文件。

## 1. 绑定遮蔽和同名规则没有完整落地

状态: fixed by option b

分级: P1

证据:

- `doc/spec_rules.md:547` 到 `doc/spec_rules.md:548` 规定 `TypedBind` 永远声明新绑定, 同名可见绑定必须报重复声明或遮蔽错误; 参数、lambda 参数和 loop 绑定也不能遮蔽外层可见绑定。
- `doc/spec_rules.md:583` 到 `doc/spec_rules.md:597` 规定函数参数、lambda 参数和 loop 绑定不能使用 `_name`, 且不得与可见普通函数族名、函数 import alias 或 host import alias 同名。
- `tool/build/sema.zig:7036` 到 `tool/build/sema.zig:7048` 只校验 loop lhs 的基本形态和 `_name` 禁止, 没有检查同一 loop 头重复绑定。
- `tool/build/sema.zig:7050` 到 `tool/build/sema.zig:7145` 的赋值约束只跟踪赋值创建的局部名和 loop 绑定赋值, 没有把函数参数、lambda 参数或可见函数名预先放入作用域冲突表。

正例:

```do
helper() -> i32 {
    return 1
}

start() {
    value i32 = helper()
    xs [i32] = .{1}
    loop item, index = xs {
        _ = index
        _ = item
    }
    return
}
```

反例:

```do
helper() -> i32 {
    return 1
}

f(helper i32, helper i32) -> i32 {
    return helper
}

start() {
    value i32 = 0
    xs [i32] = .{1}
    loop value, value = xs {
        return
    }
    return
}
```

当前风险: 规则文档已经进入严格 no-shadow 设计, 但实现仍允许参数遮蔽函数名、重复参数、lambda 参数遮蔽、loop 绑定遮蔽和 loop 头重复名。后续 JSON / field reflection / ownership 分析会依赖稳定绑定身份, 这个缺口会放大。

选项:

- a. 放宽文档, 允许参数、lambda 和 loop 局部遮蔽外层名字。
- b. 按文档实现严格 no-shadow: sema 在进入函数体、lambda 体、loop 体前把参数、loop 绑定和可见 callable/import 名加入作用域检查; 同一参数列表和同一 loop 头禁止重复非 `_` 名。

推荐: b

原因: 用户已经选定“向上查找, 已声明变量不允许再声明”的语义。严格规则也更利于后续 field reflection 展开和 ownership 分析, 避免同名绑定导致诊断和 lowering 指向不稳定。

落地:

- `tool/build/sema.zig` 已禁止函数参数重复、参数遮蔽可见函数/顶层值/import alias、lambda 参数重复、lambda 参数遮蔽可见局部/函数/顶层值/import alias, 以及 loop 绑定重复或遮蔽可见绑定。
- 新增 err fixture `310` 到 `316` 覆盖重复函数参数、参数遮蔽函数、重复 lambda 参数、lambda 参数遮蔽局部、重复 loop 绑定、loop 绑定遮蔽局部、参数遮蔽顶层值。
- 同步已有 ok fixture 和 `src/md5.do`、`src/sha1.do`、`src/sha256.do`、`src/net.do` 的参数命名, 避免继续依赖遮蔽。
- 验证: `SKIP_BUILD=1 ./tool/build/test/run_tests.sh` 通过, 摘要 `pass=684 fail=0 skip=70`。

## 2. 字段反射 metadata 来源没有 sema 级校验

状态: fixed by option b

分级: P1

证据:

- `doc/spec_rules.md:1003` 到 `doc/spec_rules.md:1014` 规定 `fields(TypeOrTypeParam)` 只能作为单绑定 loop source, field 绑定只能来自 `fields(...)`, `@field_get/@field_set` 必须基于该 metadata 静态展开。
- `doc/spec_rules.md:1214` 规定 `FieldReflectFuncName` 只能通过固定 `@field_*` 形态使用, 字段元数据来源必须是 `fields(TypeOrTypeParam)` 循环绑定。
- `tool/build/sema.zig:6458` 到 `tool/build/sema.zig:6464` 当前只按 token 形态接受 `fields(UpperIdent)`, 没有确认类型存在、是否 struct、是否当前泛型类型参数。
- 当前非法 field metadata 用法会落到 `NoMatchingCall`、`UnsupportedExpr` 或 `InvalidLoopHeader` 这类泛化诊断, 而不是字段反射规则自己的 sema 错误。

正例:

```do
User {
    id i32
    name text
}

test "struct fields each" {
    user User = .{ .id = 1, .name = "a" }
    loop field = fields(User) {
        name text = @field_name(field)
        value = @field_get(user, field)
        _ = name
        _ = value
    }
    return
}
```

反例:

```do
User {
    id i32
}

test "bad field metadata" {
    fake i32 = 0
    name text = @field_name(fake)
    return
}
```

当前风险: `@field_get(target, field)` 的结果要触发静态重载分派, 前提是 `field` 的 provenance 已知。若 sema 不先保证 `field` 一定来自 `fields(Struct)` 展开, codegen 只能用后期形态匹配兜底, 错误位置和错误种类都会漂移。

选项:

- a. 保持当前后期兜底, 只在 codegen 或 test runner 中失败。
- b. 增加 sema 级字段 metadata 校验: `fields(...)` 必须引用已知 struct 或实例化后的 struct 类型参数; `@field_name/@field_index/@field_has_default/@field_get/@field_set` 的 field 参数必须是当前字段反射 loop 的绑定; `@field_set` 必须匹配同名自赋值语句形态。

推荐: b

原因: 字段反射是 JSON 自动序列化的关键路径, 需要在 sema 层固定来源、作用域和诊断, 不能依赖 codegen 后期 `NoMatchingCall`。

落地:

- `tool/build/sema.zig` 已新增字段反射 provenance 校验: `fields(...)` 来源必须是本模块结构体、当前函数泛型类型参数或导入 upper alias; `@field_name/@field_index/@field_has_default/@field_get/@field_set` 的 field 参数必须来自当前可见字段反射 loop 绑定。
- `@field_set` 已在 sema 层限制为 `target = @field_set(target, field, value)` 同名自赋值形态。
- `tool/build/diag.zig` 已新增 `InvalidFieldReflection` 文案, 避免非法字段反射继续漂移到 `NoMatchingCall` 或 `UnsupportedExpr`。
- 新增 err fixture `317` 到 `321` 覆盖未知 `fields` 类型、非 struct 来源、非 field metadata 传入 `@field_name/@field_get`、以及 `@field_set` 非自赋值。
- 验证: `./tool/build/test/run_tests.sh` 通过, 摘要 `pass=689 fail=0 skip=70`。

## 3. `@is(value, A | B)` 文档承诺大于实现

状态: fixed by option b

分级: P1

证据:

- `doc/spec_rules.md:907` 规定 `TargetType` 可为联合类型表达式, 例如 `@is(value, A | B)`。
- `doc/syntax/union.md:68` 到 `doc/syntax/union.md:71` 把“判断多个非 nil 分支”写成正式示例。
- 当前 `tool/build/codegen.zig:6992` 到 `tool/build/codegen.zig:7005` 只在 true 分支追加直接 `@is` 收窄结果, 没有看见对 `A | B` 目标集合的完整 union 目标展开和剩余分支扣减。
- 实测多 payload union 使用 `@is(a, User | Admin)` 或收窄后直接把值当作 payload 使用时, 仍容易落到泛化 `NoMatchingCall`。

正例:

```do
User {
    id i32
}

load(found bool) -> User | nil {
    if found return .{ .id = 1 }
    return nil
}

start() {
    user User | nil = load(true)
    if @is(user, User) {
        value User = user
        _ = value
    }
    return
}
```

反例:

```do
User {
    id i32
}

Admin {
    id i32
}

start() {
    value User | Admin | nil = nil
    if @is(value, User | Admin) {
        return
    }
    return
}
```

当前风险: 文档允许目标集合, 但实现的 union layout、收窄和 payload 使用没有完整覆盖。后续如果 JSON 或错误处理依赖多分支收窄, 会出现“规则看似可用, 一到 lower 就失败”的裂缝。

选项:

- a. 立即实现完整 `@is(value, A | B)` 目标集合: target 分支可达性检查、true/false 双向扣减、payload 使用和 fixture。
- b. v1 先限制 `@is` 的顶层目标只能是单个可达非 nil 类型; `A | B` 目标集合移到 future, 同步删改正式示例和测试期待。

推荐: b

原因: 单目标 `@is(value, Type)` 已能覆盖当前 JSON / nullable / error enum 主要需求。先限制规则可以减少 union lowering 一次性扩张, 等多 payload union layout 稳定后再恢复目标集合。

落地:

- `doc/spec_rules.md`、`doc/syntax/builtin.md`、`doc/syntax/union.md` 和 `doc/grammar.peg` 已把 v1 `@is` target 收敛为顶层单个类型表达式; `@is(value, A | B)` 目标集合改为 future。
- `tool/build/sema.zig` 已为 `@is` 增加单目标校验, 同时保留普通类型位和 type args 内部的 union/nullable 解析。
- `tool/build/test/ok/68_is_union_type_set.do` 已改为单目标正例; 新增 err fixture `322_is_union_target` 覆盖 `@is(v, i32 | i64)` 非法。
- 验证: `./tool/build/test/run_tests.sh` 通过, 摘要 `pass=690 fail=0 skip=70`。

## 4. 复合条件和 enum/nil 收窄文档强于当前 lowering

状态: fixed by option b

分级: P1

证据:

- `doc/spec_rules.md:906` 规定条件位 `@and/@or/@not` 可以携带并组合 `@is` 收窄证明。
- `doc/spec_rules.md:911` 到 `doc/spec_rules.md:913` 规定 guard 和 `else if` 后续路径可继承安全反向信息。
- `doc/spec_rules.md:914` 到 `doc/spec_rules.md:915` 规定 `@eq/@ne` 可对 `nil` 和 enum 分支触发收窄。
- `tool/build/codegen.zig:6979` 到 `tool/build/codegen.zig:7005` 当前只追加 `nil` 比较收窄和直接 true 分支 `@is` 收窄, 没有完整复合条件证明引擎, 也没有在这一层看到 enum 分支 `@eq/@ne` 收窄。

正例:

```do
User {
    id i32
}

start() {
    value User | nil = nil
    if @eq(value, nil) return
    user User = value
    _ = user
    return
}
```

反例:

```do
FileError error = FileNotFound | FileClosed

start() {
    value FileError | nil = FileClosed
    if @eq(value, FileClosed) {
        err FileError = value
        _ = err
    }
    return
}
```

当前风险: 文档已经描述了较强的 proof composition, 但实现仍是局部特例。若按文档写复杂条件, 代码可能只在简单 nullable struct 上通过, 在多分支 union、enum error 或复合条件中失败。

选项:

- a. 实现条件 proof engine: `@and/@or/@not`、guard、`else if`、`@eq/@ne nil/enum` 都在同一套 narrowing fact 中表达。
- b. v1 只承诺直接条件位 `@is(value, Type)` 和 `@eq/@ne(value, nil)` 的单非 nil 分支收窄; enum 分支和复合条件 proof 作为 future。

推荐: b

原因: proof engine 影响 parser 条件位、sema 定型、codegen local facts 和诊断, 不适合夹在 JSON 主线里一次性做大。先把 v1 承诺收窄到当前稳定子集更容易闭环。

落地:

- `doc/spec_rules.md`、`doc/syntax/builtin.md`、`doc/syntax/union.md` 和 `doc/grammar.peg` 已把 v1 收窄承诺限制为直接条件头 `@is(value, Type)` 以及直接条件头 `@eq/@ne(value, nil)` 的单非 nil 分支。
- `@and/@or/@not` v1 只组合普通 bool; parser 已禁止在逻辑条件参数根部直接写 `@is(...)`, 避免复合条件看起来会传播收窄。
- enum 分支值比较只保留值比较语义, 不承诺类型收窄; 更强 proof engine 保留到 future。
- 新增 err fixture `323_is_inside_logic_condition` 覆盖 `if @and(@is(value, User), ready())` 非法。

## 5. 普通多 payload union 的可用边界没有冻结

状态: fixed by option b

分级: P1

证据:

- `doc/syntax/union.md:79` 规定 union lowering 使用统一 runtime tag representation。
- `doc/spec_rules.md:907`、`doc/spec_rules.md:915`、`doc/spec_rules.md:919` 到 `doc/spec_rules.md:922` 都默认 union、enum error 和分支收窄可以统一工作。
- 当前 compile fixture 已覆盖 nullable struct、scalar error nil tag 等局部场景, 但普通 `User | bool`、`i32 | i64`、`User | Admin | nil` 这类多 payload union 在 payload 使用和收窄后使用上仍有缺口。
- 本轮实测 `FileError | nil` 即使没有任何 `@is/@eq` 条件, 也能直接绑定到 `FileError`; 这说明 error enum union 的 payload 使用边界仍过宽, 需要在本项冻结支持矩阵时单独处理, 不能把它误判成 enum 分支 proof 已实现。

正例:

```do
User {
    id i32
}

start() {
    value User | nil = nil
    if @eq(value, nil) return
    user User = value
    _ = user
    return
}
```

反例:

```do
User {
    id i32
}

start() {
    value User | bool = false
    if @is(value, User) {
        user User = value
        _ = user
    }
    return
}
```

当前风险: 如果文档继续把任意 flat union 当作已冻结能力, 标准库 JSON / error / result 风格 API 会自然写出多 payload union, 最终在 codegen 阶段暴露非局部失败。

选项:

- a. 把多 payload union 作为 B2/B4 的必修实现项, 补齐 layout、payload extract、narrowing 和 compile fixture。
- b. v1 明确冻结支持矩阵: nullable 单 payload、error enum union、已验证 scalar 子集先稳定; 任意多 payload union 标记为未冻结, 不让标准库依赖。

推荐: b

原因: 当前主线是冻结语义和减少返工。先冻结可验证矩阵, 再在阶段 C/D 按 JSON 和 ownership 的真实需求扩大 union 能力。

落地:

- `doc/spec_rules.md` 和 `doc/syntax/union.md` 已明确 v1 支持矩阵: union 可出现在指定类型位, 使用统一 payload + tag lowering; payload 使用必须先经过直接 `@is` 或单非 nil 路径收窄。
- 未收窄 union 不再隐式匹配 payload 类型; `FileError | nil` 不能直接赋给 `FileError`。
- `tool/build/codegen.zig` 的 scalar/error payload 提取已和 struct payload 提取一致, 必须先存在当前路径的 `narrowed_union_locals` 事实。
- 新增 compile_err fixture `18_union_payload_requires_narrowing` 覆盖未收窄 union payload 裸用。
- 字段反射 loop body 的 locals 收集已同步 guard return 和 guard break/continue 的 false-path narrowing, 避免 JSON `from_json` 在 `if @eq(value_offset, nil) continue` 后丢失 payload 事实。
- 新增 compile_ok fixture `227_field_reflection_nil_continue_payload_lower` 覆盖 `fields(T)`、nullable/error union guard、`parse_value` 和 `@field_set` 的组合 lowering。
- targeted 验证: `cd tool && zig test build/codegen.zig`、`cd tool && zig build -Doptimize=Debug`、JSON compiled 组 `133/136/137/141/143/144/145/146/147` 已通过。
- full regression: `./tool/build/test/run_tests.sh` 通过, 摘要 `pass=694 fail=0 skip=70`。

## 6. 若干非法语义只报泛化诊断

分级: P2

证据:

- `tool/build/diag.zig:419`、`tool/build/diag.zig:425`、`tool/build/diag.zig:431` 已有 `InvalidLoopHeader`、`InvalidTypeRef`、`NoMatchingCall` 等通用诊断。
- 字段反射非法来源、未知 `fields(Type)`、错误显式 type args、field builtin 错位等目前多落到 `NoMatchingCall` 或 `UnsupportedExpr`, 不能直接说明触犯了哪条 sema 规则。
- `doc/spec_rules.md:1221` 到 `doc/spec_rules.md:1225` 要求语法错误诊断展示可接受形态; sema 级错误也应尽量指向当前规则, 避免用户误判成普通函数重载失败。

正例:

```do
User {
    id i32
}

test "valid field reflection" {
    loop field = fields(User) {
        name text = @field_name(field)
        _ = name
    }
    return
}
```

反例:

```do
test "unknown fields type" {
    loop field = fields(Unknown) {
        name text = @field_name(field)
        _ = name
    }
    return
}
```

当前风险: 这不是语义是否接受的问题, 而是错误阶段和错误信息不够具体。若先不处理, 也不能阻断语言冻结; 但会降低 fixture 的定位价值。

选项:

- a. 继续复用泛化诊断, 只保证非法代码失败。
- b. 在 B2.5 选定语义后补更窄的 sema 诊断, 例如字段反射非法来源、未知字段反射类型、非法 type arg arity、不可收窄 `@is` 目标。

推荐: b

原因: 不需要先设计大量错误码, 但关键路径要有可读诊断。字段反射和 narrowing 是后续 JSON / union 主线的调试入口, 值得补最小专用错误。

## 当前推荐执行顺序

1. 先处理问题 1: 绑定遮蔽和重复名。它影响所有后续语义。
2. 再处理问题 2: 字段反射 metadata 来源。它直接影响 JSON 自动序列化。
3. 然后处理问题 3、4、5: union / narrowing 先收缩 v1 文档承诺, 不急着扩实现。
4. 最后处理问题 6: 在已选定语义上补诊断和 fixture。

## B2.2 备注

本次聚焦审查没有发现“sema 已经稳定实现但正式文档完全未定义”的独立 P1 规则。当前主要问题相反: 文档承诺强于 sema / codegen 的落地范围。若后续 B2.5 实现时发现新的隐式 sema 行为, 再追加到本文件或直接同步到正式规则。
