# do 语言语法规范 (v1.0 冻结)

## 0. 版本状态

1. 本文是 `do` 语法 `v1.0` 冻结规范.
2. `compiler/src` 的 parser/sema 行为以本文为准.
3. 新语法进入主干前必须先补 `tests/do` 集成用例.
4. 规范与实现保持单一口径: 先修文档, 再修实现.

### 0.1 规范表达策略

1. 语法规则默认使用白名单表达: `只支持/固定为/必须`.
2. 语法集合由本文产生式与规则完整定义, 编译器按该集合验收.
3. 示例统一给出规范写法, 便于直接对照实现.
4. 新增语法时同时给出唯一基线写法与最小可运行示例.

## 1. 设计目标

1. 语法路径最短, 解析规则稳定, 避免同义多写法.
2. 以值语义为外观, 语法层聚焦值与函数调用表达.
3. 保持无色异步, 并发入口唯一为 `do call(...)`.
4. 保留语言特色, 私有成员/私有函数采用前置 `.`.

---

## 2. 词法与命名

### 2.1 标识符

1. 可变标识符: `name`, `user_id`.
2. 只读标识符: 前置 `_`, 例如 `_uid`, `_config`.
3. 丢弃位标识符: `_`.
4. 前置 `.` 标识符支持双语义: 顶层私有函数/私有字段命名位, 以及字段选择符(如 `.name`), 例如 `.aid`, `.normalize_name`.
5. 循环标签: 前置 `'`, 例如 `'outer`.

### 2.2 类型命名

1. 基础类型小写: `i32`, `u32`, `f64`, `bool`, `nil`.
2. 受管类型大写: `Text`, `List`, `Map`, `User`, `Future`.
3. 类型位统一使用 `Text/List`; `text/list` 按普通标识符处理.
4. 自建类型声明名(Struct/Union/Alias/TypeSetAlias 的左值)固定为 `UpperCamel`.
5. 自建类型声明名仅允许字母数字, 首字母必须是大写字母.

### 2.3 关键字

`if else loop break continue return defer match do test`

### 2.4 注释与数值字面量

1. 单行注释语法固定为 `// comment`, 作用域到行尾.
2. 整数字面量语法固定为 `Digit+`.
3. 浮点字面量语法固定为 `Digit+ "." Digit+`.

---

## 3. 顶层结构

```ebnf
Program        := TopLevel*
TopLevel       := TypeDecl | FuncDecl | ImportDecl | TestDecl

ImportDecl     := "{" ImportItem ("," ImportItem)* [","] "}" ":=" "@" "(" String ")"
ImportItem     := ImportSymbol | ImportValue | ImportType | ImportFunc
ImportSymbol   := Ident [ ":" Ident ]
ImportValue    := Ident TypeExpr
ImportType     := TypeName "{" ImportFieldList? "}"
ImportFieldList := ImportField ("," ImportField)* [","]
ImportField    := Ident TypeExpr
ImportFunc     := Ident "(" ImportTypeList? ")" "=>" TypeExpr
ImportTypeList := TypeExpr ("," TypeExpr)* [","]

TestDecl       := "test" String Block
Block          := "{" Stmt* "}"
```

```do
// 1. 导入声明(TopLevel.Import)
{sqrt, pow} := @("math")

// 1.0 导入重命名(TopLevel.Import.Rename)
{m_sqrt:sqrt, m_pow:pow} := @("math")

// 1.1 相对路径导入-父级(TopLevel.Import.RelativeParent)
{redis_get, redis_set} := @("../redis")

// 1.2 相对路径导入-同级(TopLevel.Import.RelativeLocal)
{request, response} := @("./http_client")

// 1.3 FFI 导入-值/外部类型/外部函数签名(TopLevel.Import.FfiShape)
{
    key Text,
    WasiIovec{buf_ptr i32, buf_len i32},
    fd_write(i32, WasiIovec, i32, i32) => i32,
} := @("wasi_snapshot_preview1")

// 1.4 冲突名显式重命名(TopLevel.Import.RenameConflict)
{
    kw_if:if,
    ffi_wait(i32, i32) => i32,
} := @("ffi_mod")

// 2. 类型声明(TopLevel.Type)
User {
    id u32
}

// 3. 函数声明(TopLevel.Func)
sum(a i32, b i32) i32 => add(a, b)

// 4. 测试声明(TopLevel.Test)
test "sum basic" {
    out = sum(1, 2)
    assert_eq(out, 3)
}
```

导入规则:

1. 导入只使用解构绑定语法: `{item, ...} := @source`.
2. 导入语法固定为 `@` 解构绑定: `{...} := @("path")`.
3. `ImportItem` 支持 4 类: `ImportSymbol`/`ImportValue`/`ImportType`/`ImportFunc`.
4. 符号导入支持重命名: `{local:exported}`.
5. `ImportFunc` 采用纯类型位形, 例如 `fd_write(i32, WasiIovec, i32, i32) => i32`.
6. `ImportType` 仅用于声明外部布局字段, 例如 `WasiIovec{buf_ptr i32, buf_len i32}`.
7. `ImportItem` 的本地名(每项第 1 个标识符)与关键字互斥.
8. 遇到冲突名一律显式重命名.
9. `ImportSymbol` 重命名语法固定为 `{local:exported}`.
10. `ImportValue/ImportType/ImportFunc` 通过改写本地声明名重命名, 例如 `ffi_wait(...) => i32`.
11. FFI 场景推荐把常量、外部类型、外部函数声明集中在同一个 import 块中.
12. `source` 统一写为字符串路径: `@("path")`.
13. `path` 支持两类位置:
14. 标准库路径: `@("math")`, `@("io")`, `@("wasi_snapshot_preview1")`.
15. 相对路径: `@("./http_client")`, `@("../redis")`.
16. 导入项支持尾逗号.

---

## 4. 类型声明

```ebnf
TypeDecl          := StructDecl | UnionDecl | AliasDecl | TypeSetAliasDecl

StructDecl        := TypeName [ "<" TypeParams ">" ] "{" FieldDecl* "}"
FieldDecl         := FieldName TypeExpr
FieldName         := Ident | "." Ident

UnionDecl         := TypeName "=" Variant ("|" Variant)+
Variant           := TypeName [ "{" VariantFields "}" ]
VariantFields     := VariantField ("," VariantField)* [","]
VariantField      := Ident TypeExpr

AliasDecl         := TypeName "=" TypeExpr
TypeSetAliasDecl  := TypeName "=" TypeSetExpr
TypeSetExpr       := TypeExpr ("|" TypeExpr)+

TypeParams        := TypeParam ("," TypeParam)* [","]
TypeParam         := Ident [ ":" TypeSetRef ]
TypeSetRef        := TypeName | TypeSetExpr
TypeExpr          := TypeName
                  | TypeName "<" TypeList ">"
                  | "(" TypeExpr ")"
TypeList          := TypeExpr ("," TypeExpr)* [","]
TypeName          := Ident
```

区分规则:

1. `TypeSetAliasDecl` 右侧必须至少包含 1 个 `|`.
2. `UnionDecl` 用于代数数据类型变体, `TypeSetAliasDecl` 用于约束类型集合.
3. 结构体泛型参数约束只允许类型集引用 `TypeSetRef`.
4. 无约束泛型参数直接写 `T`; 约束位只使用 `TypeSetRef`.
5. 函数能力约束统一放在函数 `#` 约束区.
6. 自建类型声明名遵循 `UpperCamel` + 字母数字集合.

```do
// 1. 结构体声明(Type.Struct)
User {
    id u32
    .aid u32
    name Text
}

// 2. 无约束泛型结构体(Type.StructGenericFree)
Box<T> {
    value T
}

// 3. 类型集约束结构体(Type.StructGenericTypeSet)
Counter<T: i8 | i16 | i32 | i64> {
    value T
}

// 4. 联合类型声明(Type.Union)
Shape = Circle{r f64} | Square{w f64, h f64}

// 5. 联合类型声明-结果类型(Type.UnionResult)
Result = Ok{value i32} | Err{msg Text}

// 6. 类型别名(Type.Alias)
UserId = u64

// 7. 类型集别名(Type.TypeSetAlias)
SignedInt = i8 | i16 | i32 | i64

// 8. 聚合类型集别名(Type.TypeSetAliasAggregate)
Number = SignedInt | u8 | u16 | u32 | u64 | f32 | f64
```

---

## 5. 函数声明

```ebnf
FuncDecl            := FuncConstraint* FuncName "(" Params? ")" [ReturnSpec] (Block | "=>" ArrowExprList)
FuncConstraint      := "#" (FuncSigConstraint | TypeSetConstraint)
FuncSigConstraint   := Ident "(" TypeList? ")" "=>" ReturnSpec
TypeSetConstraint   := TypeVar ":" (TypeSetExpr | TypeName)
TypeVar             := Ident
FuncName            := Ident | "." Ident
ReturnSpec          := TypeExpr | MultiReturnSpec
MultiReturnSpec     := TypeExpr "," TypeExpr ("," TypeExpr)*
ArrowExprList       := Expr ("," Expr)* [","]
Params              := VariadicParam [","]
                   | ParamList ["," VariadicParam] [","]
                   | ParamList [","]
ParamList           := Param ("," Param)*
Param               := Ident TypeExpr
VariadicParam       := Ident "..." TypeExpr
```

约束规则:

1. `#` 约束只作用于其后紧邻的 1 个函数声明.
2. `TypeVar` 通过约束和函数参数自动引入.
3. 约束中出现的 `TypeVar` 必须在函数签名中可解.
4. 约束语法固定为 `#T: ...` 或函数签名约束 `#f(T1, T2, ...) => R`.
5. `#T: ...` 支持直接类型集字面量和类型集别名.
6. 类型集约束用于“限制一类类型”, 例如 `i8 | i16 | i32 | i64`.
7. 未满足约束时, 编译期报错.
8. `FuncSigConstraint` 采用类型列表位形.
9. `VariadicParam` 只能出现在参数列表末尾.
10. 变长参数位的所有实参类型与 `...` 后类型保持一致.
11. 变长参数函数可接收 `>= 固定参数个数` 的实参数量.
12. 当签名满足 `f(a T, b T, rest ...T) T` 时, 该重载实例支持扁平化语义.
13. 扁平化能力由签名形态直接决定.
14. 支持 Go 风格多返回值声明: `f(...) T1, T2, ...`.
15. 多返回声明写法为 `f(...) T1, T2, ...`.
16. 箭头函数支持多表达式: `=> e1, e2, ...`, 返回位数需与 `ReturnSpec` 一致.

```do
// 1. 私有函数-块体(Func.PrivateBlock)
.normalize_name(name Text) Text {
    return trim(name)
}

// 2. 公有函数-块体(Func.PublicBlock)
format_user_name(u User) Text {
    return .normalize_name(get(u, .name))
}

// 3. 箭头表达式函数(Func.ArrowExpr)
sum(a i32, b i32) i32 => add(a, b)

// 4. 无返回类型函数(Func.NoReturnType)
log_info(msg Text) {
    print(msg)
}

// 4.1 多返回值函数(Func.MultiReturn)
divmod(a i32, b i32) i32, i32 {
    q = div(a, b)
    r = rem(a, b)
    return q, r
}

// 4.2 箭头多表达式返回(Func.ArrowMultiExpr)
pair(a i32, b i32) i32, i32 => a, b

// 5. 类型限制泛型函数(Func.Constraint.TypeLimit)
#T: User | Result
echo_entity(a T) T => a

// 6. 函数签名约束泛型函数(Func.Constraint.Callable)
#min(T, T) => T
min_abc(a T, b T) => min(a, b)

// 7. 类型集约束-字面量(Func.Constraint.TypeSetLiteral)
#T: i8 | i16 | i32 | i64
abs(a T) T {
    if lt(a, 0) return sub(0, a)
    return a
}

// 8. 类型集约束-聚合别名(Func.Constraint.TypeSetAlias)
#T: SignedInt
neg(a T) T => sub(0, a)

// 9. 同类型变长参数函数(Func.Variadic.SameType)
add(a i32, b i32, rest ...i32) i32 => reduce_add(a, b, rest)
```

### 5.1 函数重载规则

规则:

1. 允许同名重载, 由参数个数和参数类型区分.
2. 重载决议键固定为参数列表(个数+类型).
3. 决议顺序全局固定, 与文件或上下文无关.
4. 解析优先级: 精确类型 > `#` 约束泛型 > 无约束泛型.
5. `具体类型` 与 `类型集约束` 重叠时, `具体类型` 优先.
6. 同名同签名位形的两个类型集约束若存在交集, 编译期报错.
7. 同一文件中, 同名函数签名约束重载必须互斥(交集为空).
8. 多个变参候选并列时, 固定参数前缀更长者优先.
9. 若多个候选同优先级仍并列, 编译期报 `AmbiguousOverload`.
10. 重载决议按实参已定型类型直接匹配.
11. 字面量先按默认类型定型后再参与重载决议.

```do
// 1. 按参数个数重载(Func.Overload.Arity)
sum(a i32, b i32) i32 => add(a, b)
sum(a i32, b i32, c i32) i32 => add(a, b, c)

// 2. 按参数类型重载(Func.Overload.ParamType)
to_text(n i32) Text => itoa(n)
to_text(b bool) Text {
    if b return "true"
    return "false"
}

// 3. 精确类型优先于约束泛型(Func.Overload.Priority)
stringify(a Text) Text => a
#to_text(T) => Text
stringify(a T) Text => to_text(a)

// 4. 具体类型优先于类型集(Func.Overload.ConcreteOverTypeSet)
show(x i32) Text => "i32"
#T: SignedInt
show(x T) Text => "signed"

// 5. 多变参冲突时固定前缀更长优先(Func.Overload.VariadicPrefix)
merge(a i32, rest ...i32) i32 => fold_add(a, rest)
merge(a i32, b i32, rest ...i32) i32 => fold_add2(a, b, rest)
```

### 5.2 同类型变长参数与扁平化

规则:

1. 对同一目标函数和同一重载实例, 可写多参数调用: `add(a, b, c, d)`.
2. 若该重载签名满足 `f(a T, b T, rest ...T) T`, 则允许扁平化.
3. 扁平化等价: `f(f(x1, x2), x3)` => `f(x1, x2, x3)`.
4. 扁平化改写触发条件为签名满足该形态.

```do
// 1. 手写扁平调用(Variadic.FlatCall)
total = add(a, b, c)

// 2. 等价改写前(Variadic.NestedCall)
total = add(add(a, b), c)

// 3. 签名满足时的改写后(Variadic.Normalize)
total = add(a, b, c)
```

---

## 6. 语句

```ebnf
Stmt           := AssignStmt
               | IfStmt
               | LoopStmt
               | BreakStmt
               | ContinueStmt
               | MatchStmt
               | ReturnStmt
               | DeferStmt
               | ExprStmt

AssignStmt     := LValueList "=" Expr
               | DestructureLValue "=" Expr
DestructureLValue := "{" LValueList [","] "}"
LValueList     := LValue ("," LValue)*
LValue         := Ident | "_"

ReturnStmt     := "return" [ReturnExprList]
ReturnExprList := Expr ("," Expr)* [","]
DeferStmt      := "defer" Expr
ExprStmt       := Expr
```

### 6.1 基础语句用法

```do
// 1. 赋值语句(Stmt.Assign)
x = 1

// 1.0 只读绑定(Stmt.Assign.ImmutableBind)
_limit = 10

// 1.1 多返回接收(Stmt.Assign.MultiReturn)
q, r = divmod(10, 3)
// 2. 延迟执行(Stmt.Defer)
defer close(file)
// 3. 表达式语句(Stmt.Expr)
print(x)
// 4. 返回语句(Stmt.Return)
return x
// 4.0 空返回语句(Stmt.Return.Empty)
return
// 4.1 多值返回语句(Stmt.Return.Multi)
return q, r
```

赋值与绑定约束:

1. `a = expr`: 绑定或更新可变标识符 `a`.
2. `_a = expr`: 创建只读绑定 `_a`, 生命周期内保持只读.
3. 丢弃位 `_` 用于接收占位.
4. `.x` 支持双语义: 顶层私有函数名/结构私有字段名, 以及字段选择符(如 `get(u, .name)`).
5. `_a` 在同一作用域内只能声明 1 次, 重复声明为编译错误.

多返回约束:

1. `a, b = f()` 左值数量必须与 `f` 返回值数量一致.
2. 左值可使用 `_` 占位无需接收的返回位.
3. 多返回值调用保持多值形态.
4. 需要容器值时显式构造 `Tuple<...>{...}`.

### 6.2 if 语句

```ebnf
IfStmt         := "if" Expr Block ["else" Block]
               | "if" IfTypePattern ":=" Expr Block ["else" Block]
               | "if" Expr Stmt
IfTypePattern  := TypeName "(" Ident ")"
               | TypeName "{" PatternFields? "}"
```

约束:

1. `if` 条件位必须是单值表达式.
2. 多返回函数结果先接收再使用, `if` 条件位只接收单值.
3. 若函数返回多值, 必须先接收到变量后再在 `if` 中使用.
4. `if P := expr` 的 `P` 仅允许类型模式(`Type(...)` 或 `Type{...}`).
5. `if P := expr` 的 `expr` 必须是单值表达式, `f_multi(...)` 直接使用为编译错误.

```do
// 1. 条件分支-块体(If.ExprBlock)
if gt(age, 18) {
    print("adult")
} else {
    print("minor")
}

// 2. 模式绑定分支(If.PatternBind)
if User{age} := item {
    print(age)
}

// 3. 单行短路分支(If.OneLine)
if is_ok(x) return x

// 4. 多返回先接收再判断(If.MultiReturnBindThenUse)
ok, code = check_auth(user)
if ok {
    print(code)
}
```

### 6.3 loop 语句

```ebnf
LoopStmt       := "loop" "{" [Label] Stmt* "}"
               | "loop" LoopCond "{" Stmt* "}"
               | "loop" LoopBind ":=" Expr "{" Stmt* "}"
LoopCond       := Expr
LoopBind       := Ident | Ident "," Ident
Label          := "'" Ident
BreakStmt      := "break" [Label]
ContinueStmt   := "continue" [Label]
```

约束:

1. `loop cond {}` 的 `cond` 只要求结果为 `bool`.
2. `cond` 可为任意返回 `bool` 的表达式, 不限制函数参数个数.

```do
// 1. 基础块循环(Loop.Basic)
loop {
    if done(fid) break
    tick()
}

// 2. 条件循环(Loop.Cond)
count = 0
loop lt(count, 3) {
    print("count = $count")
    count = add(count, 1)
}

// 2.1 条件循环-二元谓词(Loop.Cond.BinaryPredicate)
loop has(user_map, uid) {
    break
}

// 2.2 条件循环-一元谓词(Loop.Cond.UnaryPredicate)
loop is_valid(user) {
    break
}

// 3. 集合迭代-值与索引(Loop.IterListWithIndex)
list_a = List<i8>{1, 2, 3}
loop val, index := list_a {
    print(val, index)
}

// 4. 集合迭代-仅值(Loop.IterListValueOnly)
loop val := list_a {
    print(val)
}

// 5. 映射迭代(Loop.IterMapKeyValue)
map_a = Map<i32, i32>{}
loop key, val := map_a {
    print(key, val)
}

// 6. range 递增迭代(Loop.IterRangeAsc)
loop i := range(1, 10, 1) {
    print(i)
}

// 7. range 递减迭代(Loop.IterRangeDesc)
loop i := range(10, 1, 2) {
    print(i)
}

// 8. 右置标签循环(Loop.LabelRightSide)
loop { 'outer
    loop {
        // 9. 无标签继续(Continue.NoLabel)
        if need_skip() continue
        // 10. 带标签跳出(Break.WithLabel)
        if need_exit() break 'outer
        work()
    }
}
```

---

## 7. 表达式与字面量

```ebnf
Expr           := CallExpr
               | DoExpr
               | AsyncCtrlExpr
               | LambdaExpr
               | BraceLit
               | StructLit
               | ListLit
               | MapLit
               | TupleLit
               | Ident
               | Literal

CallExpr       := Ident "(" Args? ")"
Args           := Expr ("," Expr)* [","]
DoExpr         := "do" CallExpr
AsyncCtrlExpr  := DoneExpr
               | WaitExpr
               | WaitOneExpr
               | WaitAnyExpr
               | WaitAllExpr
               | CancelExpr
               | StatusExpr
DoneExpr       := "done" "(" Expr ")"
WaitExpr       := "wait" "(" Expr ["," Expr] ")"
WaitOneExpr    := "wait_one" "(" Expr "," Expr ("," Expr)* [","] ")"
WaitAnyExpr    := "wait_any" "(" Expr "," Expr ("," Expr)* [","] ")"
WaitAllExpr    := "wait_all" "(" Expr "," Expr ("," Expr)* [","] ")"
CancelExpr     := "cancel" "(" Expr ")"
StatusExpr     := "status" "(" Expr ")"
LambdaExpr     := "|" Params? "|" Expr

BraceLit       := "{" BraceItems? "}"
BraceItems     := ExprList | PairList

StructLit      := TypeName "{" NamedArgs? "}"
NamedArgs      := NamedArg ("," NamedArg)* [","]
NamedArg       := Ident ":" Expr

ListLit        := "List" "<" TypeExpr ">" "{" ExprList? "}"
MapLit         := "Map" "<" TypeExpr "," TypeExpr ">" "{" PairList? "}"
TupleLit       := "Tuple" "<" TypeList ">" "{" ExprList? "}"

ExprList       := Expr ("," Expr)* [","]
PairList       := Pair ("," Pair)* [","]
Pair           := Expr ":" Expr

Literal        := IntLit | FloatLit | String | "true" | "false" | "nil"
```

```do
// 1. 函数调用表达式(Expr.Call)
y = add(1, 2)

// 2. 并发表达式(Expr.Do)
f = do login(cx, 1, "token")

// 3. Lambda 表达式(Expr.Lambda)
inc = |n i32| add(n, 1)
z = inc(3)

// 4. 结构体字面量(Expr.StructLit)
u = User{id: 1, name: "tom"}
// 4.1 花括号表达式-表达式列表(Expr.BraceList)
fields = {.name, .age}
// 4.2 花括号表达式-键值对列表(Expr.BracePair)
patch = {0: 10, 1: 20}
// 5. 列表字面量(Expr.ListLit)
xs = List<i32>{1, 2, 3}
// 6. 映射字面量(Expr.MapLit)
kv = Map<Text, i32>{"a": 1, "b": 2}
// 6.1 空映射字面量(Expr.MapLitEmpty)
empty_map = Map<i32, i32>{}
// 7. 元组字面量(Expr.TupleLit)
t = Tuple<i32, Text>{1, "ok"}

// 8. 布尔字面量(Expr.LiteralBool)
ok = true
// 9. 空值字面量(Expr.LiteralNil)
none = nil

// 10. Future 控制表达式(Expr.AsyncControl)
done_flag = done(f)
out = wait(f)
out2 = wait(1000, f)
one = wait_one(1000, f1, f2, f3)
any = wait_any(1000, f1, f2, f3)
all = wait_all(1000, f1, f2, f3)
cancel(f)
s = status(f)

// 11. 类型转换函数调用(Expr.ConvertCall)
to_i8(v i32) i8 => v
to_i8(v i64) i8 => v

i8_v = to_i8(n32)
i64_v = to_i64(n32)
f64_v = to_f64(i64_v)
```

字面量默认类型:

1. `IntLit` 默认类型为 `i32`.
2. `FloatLit` 默认类型为 `f64`.

集合字面量规则:

1. `List/Map/Tuple` 采用完整字面量写法: `Type<...>{...}`.
2. 空集合写法固定为 `Type<...>{}`.
3. `BraceLit` 只支持纯 `ExprList` 或纯 `PairList`, 不支持混用.
4. `BraceLit` 混用示例 `{.name: "tom", .age}` 语法无效.

类型转换规则:

1. `as` 作为普通标识符参与解析.
2. 数值转换采用显式函数调用.
3. 转换函数是普通函数, 推荐命名: `to_i8/to_i16/to_i32/to_i64/to_f32/to_f64`.
4. 同名转换函数允许按参数类型重载, 例如 `to_i8(i32) => i8`, `to_i8(i64) => i8`.
5. 转换函数声明与调用统一走普通函数规则.
6. `to_*` 是命名约定.
7. `as` 可作为普通标识符, 例如函数名 `as(...)`.

### 7.1 并发入口约束

```do
// 固定写法
a = do fetch_user(1)
```

语义:

1. `f(args...)` 在当前执行流内同步执行, 返回普通结果.
2. `do f(args...)` 创建异步执行单元并返回 `Future<T>`.
3. 并发入口固定为 `do f(args...)`.

### 7.2 Future 控制语法

规则:

1. `done(f) -> bool`: 查询 Future 是否终态.
2. `wait(f) -> T | Error`: 等待 Future 完成并返回结果.
3. `wait(ms, f) -> T | Timeout | Error`: 带超时等待结果.
4. `wait_one(ms, f1, f2, ..., fn) -> T | Timeout | Error`: 等待多个 Future 中首个完成结果.
5. `wait_any(ms, f1, f2, ..., fn) -> T | Timeout | Error`: 等待多个 Future 中任意一个完成结果.
6. `wait_all(ms, f1, f2, ..., fn) -> List<T> | Timeout | Error`: 等待多个 Future 全部完成结果.
7. `cancel(f) -> bool`: 发起协作取消请求, 幂等.
8. `status(f) -> Pending | Running | Done | Canceled | Failed`: 查询 Future 状态.

约束:

1. 内建控制面函数集合固定为 `done/wait/wait_one/wait_any/wait_all/cancel/status`.
2. `wait` 表示等待完成并返回结果.
3. `wait` 参数个数固定为 `1` 或 `2`; `2` 参数形态的第 1 个参数为超时值.
4. `wait_one/wait_any/wait_all` 至少接收 `2` 个参数, 第 1 个参数为超时值.
5. 取消生效点由任务安全点检查.
6. 取消后必须执行 `defer` 清理逻辑.
7. 允许声明同名普通函数; 当存在同名且签名可匹配的普通函数时, 按普通函数解析.
8. 无同名可匹配普通函数时, 内建控制面签名固定为:
9. `done(f)`.
10. `wait(f)` 或 `wait(ms, f)`.
11. `wait_one(ms, f1, ..., fn)` 且 `n >= 1`.
12. `wait_any(ms, f1, ..., fn)` 且 `n >= 1`.
13. `wait_all(ms, f1, ..., fn)` 且 `n >= 1`.
14. `cancel(f)`.
15. `status(f)`.
16. 无同名可匹配普通函数时, `done` 参数个数固定为 `1`: `0` 参数报 `DoneCallNeedsArg`, `>1` 参数报 `DoneCallArity`.

```do
// 1. 创建异步任务(Async.Spawn)
fa = do login(cx, 1, "token")
fb = do fetch_profile(cx, 1)

// 2. 查询与等待(Async.QueryWait)
ready = done(fa)
out = wait(fa)
out2 = wait(1000, fb)
one = wait_one(1000, fa, fb)
any = wait_any(1000, fa, fb)
all = wait_all(1000, fa, fb)

// 3. 取消与状态(Async.CancelStatus)
cancel(fb)
st = status(fb)
```

---

## 8. 解构规则

规则:

1. 解构左值写法固定为 `{a, b} = expr`.
2. 批量字段访问参数使用 `{.name, .age}`.
3. 批量更新统一使用 `{key: value, ...}`.

```do
// 1. 批量字段读取解构(Destructure.FieldBatchGet)
{name, age} = get(u, {.name, .age})
// 2. 直接解包(Destructure.DirectUnpack)
{x, y} = point
// 3. 批量更新(Destructure.BatchSet)
xs = set(xs, {0: 10, 1: 20})
```

---

## 9. match 规则

```ebnf
MatchStmt      := "match" Expr "{" MatchArm* "}"
MatchArm       := Pattern "=>" (Block | Stmt) [","]
Pattern        := "_"
               | TypeName "(" Ident ")"
               | TypeName "{" PatternFields? "}"
               | Literal

PatternFields  := PatternField ("," PatternField)* [","]
PatternField   := Ident
```

约束:

1. `match` 分支模式固定为 `_`/类型模式/字面量模式.
2. 复杂谓词放在分支体内部语句中.
3. `match` 作为语句节点使用.
4. 复杂条件放到分支语句内部处理.
5. `match` 目标位必须是单值表达式.
6. 多返回函数结果先接收再使用, `match` 目标位只接收单值.
7. 若函数返回多值, 必须先接收到变量后再 `match`.

```do
match x {
    // 1. 类型绑定模式(Pattern.TypeBind)
    User(u) => print(u),
    // 2. 结构字段模式(Pattern.StructFields)
    Book{price} => {
        if gt(price, 100) print("high")
    }
    // 3. 字面量模式(Pattern.Literal)
    0 => print("zero"),
    // 4. 通配符模式(Pattern.Wildcard)
    _ => print("other")
}

tag, payload = decode(msg)
match tag {
    0 => print("ok"),
    _ => print("other"),
}
```

---

## 10. 分隔符与格式约束

1. 列表, 映射, 结构体字面量使用逗号分隔.
2. 最后一项允许尾逗号.
3. 语义分隔以显式分隔符和语法结构为准, 换行用于排版.
4. 新增语法糖必须先给出等价的单一基线写法.

示例:

```do
u = User{
    id: 1,
    name: "tom",
}
```

---

## 11. 与其他规范关系

1. 异步语法与控制语义已内嵌在本文第 7 章.
2. 内存与 COW 策略见 `gc.md`.
3. 运行时调度实现细节见独立文档.

---

## 12. 冻结决策

### 12.1 重载决议

1. 决议顺序全局固定.
2. 非泛型精确匹配优先于泛型匹配.
3. 约束语法位使用 `#T: ...` 与函数签名约束.
4. 变参匹配顺序在固定参数匹配之后.
5. 具体类型与类型集重叠时, 具体类型优先.
6. 类型集约束重叠时报编译错误.
7. 同文件签名约束重载必须互斥(交集为空).
8. 多变参候选并列时, 固定前缀更长优先.
9. 同优先级并列候选报 `AmbiguousOverload`.
10. 字面量先按默认类型定型后参与重载.

### 12.2 COW 写入语义

1. 受管对象允许共享底层存储.
2. `RC == 1` 时原地写.
3. `RC > 1` 时 clone 后写.
4. 用户可见语义必须保持值隔离.

### 12.3 异步控制面

1. 外部最小控制面: `done/wait/wait_one/wait_any/wait_all/cancel/status`.
2. 控制面函数集合收敛为 `done/wait/wait_one/wait_any/wait_all/cancel/status`.
3. `wait` 调用参数个数范围为 `1..2`; `2` 参数形态第 1 个参数固定为超时值.
4. `wait_one/wait_any/wait_all` 调用参数个数范围为 `>= 2`, 且第 1 个参数固定为超时值.
5. 取消为幂等信号, 在任务安全点生效.
6. 取消后必须执行 `defer` 清理.
7. 所有控制面统一作用于 `Future`.
8. 允许声明同名普通函数; 当存在同名且签名可匹配的普通函数时, 按普通函数解析.
9. 无同名可匹配普通函数时, 内建控制面签名固定为:
10. `done(f)`.
11. `wait(f)` 或 `wait(ms, f)`.
12. `wait_one(ms, f1, ..., fn)` 且 `n >= 1`.
13. `wait_any(ms, f1, ..., fn)` 且 `n >= 1`.
14. `wait_all(ms, f1, ..., fn)` 且 `n >= 1`.
15. `cancel(f)`.
16. `status(f)`.
17. 无同名可匹配普通函数时, `done` 参数个数固定为 `1`: `0` 参数报 `DoneCallNeedsArg`, `>1` 参数报 `DoneCallArity`.

### 12.4 导入语法

1. 导入统一语法: `{...} := @("path")`.
2. `@` 仅允许顶层语句起始位置.
3. 导入通过显式顶层声明引入, 无隐式全局导入机制.
4. `ImportItem` 固定为 `ImportSymbol`/`ImportValue`/`ImportType`/`ImportFunc`.
5. `ImportFunc` 采用类型位形: `name(T1, T2, ...) => R`.
6. 导入项本地名只与关键字互斥.
7. 冲突名必须显式重命名: `ImportSymbol` 用 `{local:exported}`, 其他项改写为安全本地名.
8. 支持标准库与相对路径导入.
9. 导出同名冲突通过解构重命名解决: `{local:exported}`.

### 12.5 数值与转换

1. 数值转换只通过显式转换函数调用完成.
2. 整数字面量默认类型为 `i32`.
3. 浮点字面量默认类型为 `f64`.
4. 类型转换语法位使用普通函数调用.
5. 推荐使用 `to_i8/to_i16/to_i32/to_i64/to_f32/to_f64` 命名转换函数.
6. 同名转换函数按参数类型重载, 示例: `to_i8(i32) => i8`, `to_i8(i64) => i8`.
7. `as` 按普通标识符使用.

### 12.6 多返回值策略

1. 支持 Go 风格多返回值声明与接收.
2. 函数声明使用无括号返回列表: `f(...) T1, T2, ...`.
3. 返回语句支持 `return` 或 `return e1, e2, ...`.
4. 接收语句支持 `a, b, ... = f(...)`.
5. 多返回值与 `Tuple` 通过显式构造/解构转换.
6. `if` 条件位与 `match` 目标位仅接受单值表达式.
7. 多返回函数在 `if/match` 中必须先显式接收再使用.

### 12.7 绑定可变性

1. 可变绑定使用普通标识符: `a`.
2. 只读绑定使用前缀 `_`: `_a`.
3. 丢弃位 `_` 用于占位接收.
4. 只读绑定初始化后保持只读, 再赋值为编译错误.
5. `_a` 在同一作用域内只声明 1 次, 重复声明为编译错误.
6. `.x` 支持双语义: 顶层私有函数名/结构私有字段名, 以及字段选择符(如 `get(u, .name)`).

### 12.8 loop 头部

1. `loop` 头部固定支持 3 类: `loop {}`, `loop cond {}`, `loop bind := iterable {}`.
2. `bind` 固定支持 `v` 或 `v, i` 两种形态.
3. `iterable` 位置支持标识符与调用表达式, 例如 `list_a`, `map_a`, `range(1, 10, 1)`.
4. 条件循环支持任意返回 `bool` 的表达式, 不限制函数参数个数.
5. 条件位谓词可按语义命名, 例如 `loop has(user_map, uid) { ... }`, `loop is_valid(user) { ... }`.
6. 标签语法沿用 `loop { 'outer ... }`, 与新头部写法并存.

---

## 13. 本轮收窄条件示例

```do
// 1. done 必须单参数(Done.WithArgOnly)
fid = do login(cx, 1, "token")
if done(fid) return

// 2. if 模式绑定必须是类型模式(If.PatternTypeOnly)
if User{age} := item {
    print(age)
}

// 2.1 多返回值先接收再用于 if(If.MultiReturnBindFirst)
ok, code = check_auth(user)
if ok {
    print(code)
}

// 3. 异步控制统一作用于 Future(Async.FutureOnlyControl)
f = do fetch_user(1)
cancel(f)
st = status(f)
out = wait(1000, f)

// 4. 只读绑定同域唯一(Bind.ImmutableUniqueInScope)
_limit = 10
loop {
    _limit_inner = 20
    break
}

// 5. 导入冲突使用解构重命名(Import.RenameOnConflict)
{m_sqrt:sqrt, m_pow:pow} := @("math")

// 6. 箭头函数支持多表达式返回(Func.ArrowMultiExpr)
pair(a i32, b i32) i32, i32 => a, b

// 7. .x 双语义: 私有命名位 + 字段选择符(Private.DotDualRole)
User {
    .aid u32
    name Text
}

.normalize_name(name Text) Text => trim(name)
{name} = get(u, {.name})
```
