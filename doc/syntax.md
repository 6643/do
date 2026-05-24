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
3. 保持无色异步, 并发入口固定为 `do f(...)`.
4. 只保留必要控制流: `if/else`, `loop`, `return`, `defer`.

---

## 2. 词法与命名

### 2.1 标识符

1. 可变标识符: `name`, `user_id`.
2. 只读标识符: 前置 `_` 且后接字母, 例如 `_uid`, `_config`.
3. 丢弃位标识符: `_`.
4. 前置 `.` 标识符用于声明位表示私有声明, 或用于路径表达式表示字段路径段.
5. 循环标签: 前置 `'`, 例如 `'outer`.
6. 私有函数, 私有变量, 私有常量和私有结构体只在声明时写前置 `.`, 模块内读取, 写入和调用都不再写 `.`.
7. 私有字段声明时写前置 `.`, 路径表达式访问字段时统一写字段路径段 `.field`.
8. `Ident` 包含普通标识符和只读标识符; 单独 `_` 不属于 `Ident`, 只作为丢弃位.
9. 只读标识符格式固定为 `_` 后接字母, 再接字母/数字/下划线.
10. `__` 和 `_1` 不是合法标识符.

### 2.2 词法终结符

```ebnf
Ident         := LowerIdent | UpperIdent | ReadonlyIdent
LowerIdent    := [a-z][A-Za-z0-9_]*
UpperIdent    := [A-Z][A-Za-z0-9_]*
ReadonlyIdent := "_" [A-Za-z][A-Za-z0-9_]*

IntLit        := [0-9]+
FloatLit      := [0-9]+ "." [0-9]+
String        := NormalString | RawString
NormalString  := "\"" StringChar* "\""
StringChar    := NormalChar | EscapeSeq
NormalChar    := ? any character except '"', '\', LF, CR ?
EscapeSeq     := "\\" ("\"" | "\\" | "n" | "r" | "t")
RawString     := "\"\"\"" RawChar* "\"\"\""
RawChar       := ? any character sequence not containing '"""' ?
BlockComment  := "/*" CommentChar* "*/"
CommentChar   := ? any character sequence not containing '*/' ?
```

规则:

1. `_` 是丢弃位, 不是 `Ident`.
2. `__` 和 `_1` 非法.
3. 类型声明名必须使用 `UpperIdent`.
4. 普通变量, 函数和字段名使用 `LowerIdent` 或 `ReadonlyIdent`.
5. 外部路径段允许 `LowerIdent` 和 `UpperIdent`, 例如 `@mongo/client/Client`.
6. 字符串支持 `\"`, `\\`, `\n`, `\r`, `\t` 转义.
7. 当前版本不支持 `\u1234` 这类 Unicode escape.
8. 普通字符串不允许裸换行.
9. `"""..."""` 是多行 raw string, 保留内容, 不处理转义, 不自动裁剪首尾换行或缩进.
10. `/* ... */` 是块注释, 不作为字符串.
11. 块注释不支持嵌套.

### 2.3 类型与字面量

1. 基础类型: `i8`, `i16`, `i32`, `i64`, `isize`, `u8`, `u16`, `u32`, `u64`, `usize`, `f32`, `f64`, `bool`, `nil`, `Text`.
2. 基础泛型类型: `List`, `Map`, `Tuple`, `Future`.
3. 结构体/类型别名/联合类型声明名固定为 `UpperCamel`.
4. 所有字面量都没有默认类型.
5. 字面量必须由上下文唯一确定类型, 否则编译错误.
6. 显式定型写法固定为基础类型构造或类型构造, 例如 `i32(1)`, `usize(1)`, `f32(0.5)`, `Text("tom")`.
7. `nil` 是 unit 类型及其唯一值, 只能出现在 `nil` 返回类型或包含 `nil` 的联合类型中.
8. 标准预置状态/错误值: `Timeout`, `Pending`, `Running`, `Done`, `Canceled`, `Failed`.

### 2.4 关键字

`if else loop break continue return defer do test`

---

## 3. 顶层结构

```ebnf
Program        := TopLevel*
TopLevel       := TypeDecl | FuncDecl | ValueDecl | ExternBindDecl | TestDecl

ValueDecl      := TopName [TypeExpr] "=" Expr
ExternBindDecl := TopName "=" ExternBind
ExternBind     := ExternPath [ExternSig]
ExternSig      := "(" Params? ")" "->" ReturnSpec
ExternPath     := "@" PathSegment ("/" PathSegment)+
PathSegment    := Ident
TopName        := Ident | "." Ident

TestDecl       := "test" String Block
Block          := "{" Stmt* "}"
```

```do
sqrt = @math/sqrt
abc = @math/abs
MongoClient = @mongo/client/Client
add_point = @env/add_point(ptr usize, len usize) -> nil
```

外部绑定规则:

1. `name = @path/symbol` 是单符号外部绑定, 不引入 `import` 关键字.
2. 左侧 `name` 是本地顶层名; 右侧最后一段是外部公开符号名.
3. 重命名通过左侧完成, 例如 `abc = @math/abs`.
4. 无签名绑定走模块解析, 顺序固定为: `./*.do`, `lib/*.do`, `std/*.do`.
5. `name = @module/symbol(a A, b B) -> R` 是宿主外部函数绑定, 不走模块文件解析.
6. 只有签名且本地没有函数体的外部函数绑定表示宿主提供.
7. 无签名绑定用于类型, 值, 函数或模块公开符号, 由目标符号定义决定.
8. 外部绑定不会自动并入本地同名函数族, 需要本地显式转发.
9. 核心库默认可见, 不通过外部绑定手动导入.
10. 外部只读静态值绑定到本地时, 本地名也必须是只读标识符.
11. 外部可变值绑定到本地时, 本地名不能是只读标识符.
12. 本地顶层值声明支持全局变量和全局常量; 前置 `_` 的顶层值是只读常量.
13. 顶层值声明必须由显式类型或右侧表达式唯一确定类型.
14. 顶层 `name = @path/symbol` 按外部绑定解析; 其他 `name [Type] = expr` 按本地顶层值声明解析.
15. 顶层值初始化不是启动时代码, 不在程序启动时执行.
16. 普通顶层变量初始化只能使用无函数调用的静态常量表达式.
17. 顶层只读常量初始化允许函数调用; 调用表达式必须在编译期执行.
18. 编译期执行的函数不得依赖运行时输入, `do`, 可变顶层值, 或无法在编译期执行的外部宿主能力.
19. 顶层初始化依赖图必须无环.
20. 普通顶层值可在函数内更新; 前置 `_` 的顶层值不可更新.
21. 同一模块内所有顶层名字共享同一名字空间.
22. 类型, 顶层值, 外部绑定和函数族都占用顶层名字.
23. 同名函数声明可组成函数族, 这是唯一允许的顶层同名例外.
24. 外部绑定不得与已有顶层名字同名, 也不会自动加入函数族.
25. 需要把外部函数融合进本地函数族时, 必须使用不同本地名绑定外部符号, 再写本地转发函数.
26. 顶层名字比较时忽略前置 `.` 的可见性标记; `Name` 与 `.Name` 视为同名冲突.

静态常量表达式:

1. 静态常量表达式可使用字面量, 显式类型构造, `.{...}` 聚合字面量, `StructLit`, 以及已声明只读顶层值引用.
2. `.{...}` 和 `StructLit` 内部也必须全部是静态常量表达式.
3. 顶层只读常量初始化可在静态常量表达式中包含函数调用; 该调用在编译期求值.
4. 字段默认值支持静态常量表达式, 可引用本模块只读顶层值或外部只读静态值绑定.
5. 字段默认值不直接执行函数; 需要函数结果时先绑定为顶层只读常量.
6. 静态常量表达式不包括 `get/set`, `do`, lambda, 或可变顶层值引用.
7. 跨模块静态常量依赖图必须无环.
8. 顶层值初始化不能绑定 lambda; 顶层函数必须使用函数声明语法.

```do
abcd i32 = run_fn()    // 不合法: 普通顶层变量不能用函数调用初始化
_abcd i32 = run_fn()   // 合法: 顶层只读常量在编译期执行 run_fn()
```

---

## 4. 类型声明

```ebnf
TypeDecl     := StructDecl | AliasDecl

StructDecl   := TypeName [ "<" TypeParams ">" ] "{" FieldDecl* "}"
FieldDecl    := FieldName TypeExpr ["=" Expr]
FieldName    := Ident | "." Ident

AliasDecl    := TypeName "=" TypeExpr
TypeExpr     := UnionExpr
UnionExpr    := TypeAtom ("|" TypeAtom)*
TypeAtom     := TypeName
             | TypeName "<" TypeList ">"
             | "(" TypeExpr ")"
             | LiteralType
LiteralType  := IntLit | FloatLit | String | "true" | "false" | "nil"
TypeList     := TypeExpr ("," TypeExpr)* [","]

TypeParams   := TypeParam ("," TypeParam)* [","]
TypeParam    := Ident [ ":" UnionExpr ]
TypeName     := TopName
```

规则:

1. `|` 用于真正的联合类型.
2. 联合成员只包含已存在类型或字面量类型.
3. 不支持内联 ADT 变体声明.
4. `Result = Ok | Err` 是联合类型, 前提是 `Ok` 与 `Err` 已存在.
5. `Status = "pending" | "running" | "done"` 是字面量联合.
6. `TypeParam` 约束使用同一套联合类型表达式.
7. `Error` 是特殊保留类型名, 表示当前模块的错误聚合类型.
8. 模块内所有以 `Error` 结尾的联合类型自动归入当前模块 `Error`.
9. 不需要也不允许手动声明 `Error = ...`.
10. 联合成员中的状态/错误变体值共享模块顶层名字空间, 同一模块内不得重复.
11. `eq(value, Variant)` 用于判断具体变体值, 真分支内收窄为该变体.
12. `is(Type, value)` 用于判断联合分支类型, 真分支内收窄为该类型.
13. 类型声明只允许出现在顶层结构中, 函数内部不允许声明结构体或类型别名.
14. 前置 `.` 的类型声明是私有类型, 只能在当前模块内引用.
15. 公开函数或公开外部绑定的签名不得暴露私有类型.
16. 结构体字段名比较时忽略前置 `.` 的可见性标记; 同一结构体内 `name` 与 `.name` 视为同名冲突.
17. 私有字段只能在声明该结构体的模块内通过 `get/set` 访问.
18. 外部模块不能通过字段路径访问私有字段.
19. 所有结构体字段都可声明默认值.
20. 构造结构体时, 没有默认值的字段必须显式初始化.
21. 有默认值的字段可在构造时省略, 省略时使用字段默认值.
22. 外部模块构造公开结构体时不能显式初始化私有字段; 私有字段必须有默认值才能被省略.
23. 字段默认值不是运行时代码, 只支持静态常量表达式.
24. 字段默认值由字段类型提供上下文定型, 可引用本模块只读顶层值或外部只读静态值绑定.
25. 未声明默认值的字段不会自动初始化.
26. 结构体构造字段名不写前置 `.`, 按忽略可见性标记后的字段名匹配.
27. 声明模块内部可初始化私有字段; 外部模块不能初始化私有字段.
28. 结构体是纯数据载体, 字段不支持绑定函数, 方法或可调用值.
29. 结构体字段类型不支持函数类型; Lambda 不允许作为结构体字段值.

```do
User {
    id u32
    name Text
}

.InternalUser {
    .token Text = ""
    age u8
}

Game {
    id u32
    name Text
}

_def_game Game = .{id: 0, name: ""}

UserWithDefault {
    id u8 = 123
    name Text
    favorite_game Game = _def_game
    games List<Game> = .{_def_game}
    games2 List<Game> = .{.{id: 0, name: ""}}
}

MaybeUser = User | nil
Status = "pending" | "running" | "done"
SignedInt = i8 | i16 | i32 | i64
FileError = AccessDenied | FileNotFound | DiskFull
HttpError = OK | NotFound | ServerError

handle_error(err Error) {
    if eq(err, AccessDenied) {
        return
    }
    if is(HttpError, err) {
        return
    }
}
```

---

## 5. 函数声明

```ebnf
FuncDecl            := FuncConstraint* FuncName "(" Params? ")" FuncResult FuncBody
FuncResult          := ["->" ReturnSpec]
FuncBody            := Block | "=>" ArrowExprList
FuncConstraint      := "#" (FuncSigConstraint | TypeConstraint)
FuncSigConstraint   := Ident "(" TypeList? ")" "->" ReturnSpec
TypeConstraint      := TypeVar ":" UnionExpr
TypeVar             := Ident
FuncName            := TopName
ReturnSpec          := "nil" | TypeExpr | MultiReturnSpec
MultiReturnSpec     := TypeExpr "," TypeExpr ("," TypeExpr)*
ArrowExprList       := Expr ("," Expr)* [","]
Params              := ParamList [","]
ParamList           := Param ("," Param)*
Param               := Ident TypeExpr
LambdaParams        := LambdaParamList [","]
LambdaParamList     := LambdaParam ("," LambdaParam)*
LambdaParam         := Ident [TypeExpr]
```

规则:

1. 块体函数可省略 `-> ReturnSpec`; 省略时返回类型默认为 `nil`.
2. 表达式体函数可省略 `-> ReturnSpec`; 省略时由 `=>` 右侧表达式推断返回类型.
3. 表达式体 `=>` 右侧只能是表达式或表达式列表.
4. 块体不支持尾表达式隐式返回.
5. 非 `nil` 返回的块体函数必须在所有返回路径显式 `return` 对应值.
6. `nil` 返回的块体函数允许自然结束, `return`, `return nil`, 或 `return` 一个结果为 `nil` 的表达式.
7. `-> nil` 表示 unit 返回; 省略返回类型的块体函数与显式 `-> nil` 等价.
8. `do f(...)` 启动并发任务并返回 `Future<R | Error>`; 若 `R` 已包含 `Error`, 不重复加入.
9. Lambda 是匿名函数表达式, 使用同一套返回类型规则: 块体省略返回类型默认 `nil`, 表达式体可推断返回类型.
10. Lambda 只能直接用于签名已知的回调参数位置; 当前版本不引入通用函数类型, 不支持绑定, 存储或作为普通用户函数参数类型声明.
11. 外部函数绑定必须显式写 `-> ReturnSpec`.
12. 公开函数即使省略返回类型, 也必须导出推断后的签名元数据, 供文档和 LSP 使用; 私有函数不要求导出给外部消费.
13. `#f(T) -> R` 表示结构化能力约束, 只声明需求, 不提供实现.
14. 同名函数族只在当前模块内形成; 外部绑定不会自动合并.
15. 具体实现优先于约束默认实现, 约束默认实现之间不得重叠.
16. 无约束泛型默认实现可以存在, 但不得掩盖重叠的约束默认实现.
17. 普通顶层声明默认对外公开.
18. 前置 `.` 的顶层声明是私有声明, 不对外公开.
19. 函数声明只允许出现在顶层结构中, 函数内部不允许声明函数.
20. 函数参数是新绑定, 不得遮蔽外层可见绑定, 同一参数列表内不得重名.
21. 需要在函数内部复用命名逻辑时, 提升为顶层私有函数.

并发规则:

1. `Future<T>` 表示一个可等待, 可取消, 可设置超时的并发任务结果.
2. `do f(a, b)` 启动并发任务; 若 `f(a, b) -> T`, 则 `do f(a, b)` 的类型是 `Future<T | Error>`.
3. 若 `T` 已包含 `Error`, `do` 不重复加入 `Error`.
4. `await(Future<T>) -> T`.
5. `cancel(Future<T>) -> nil`.
6. `timeout(Future<T>, usize) -> Future<T>`, 单位是毫秒.
7. 并发层错误如 `Canceled`, `Timeout`, `Failed` 都归入 `Error`.
8. 不引入独立 `Duration` 类型; 超时参数直接使用毫秒数.
9. `ms(n usize) -> usize`, `sec(n usize) -> usize`, `day(n usize) -> usize` 是核心库预置辅助函数.
10. `ms(1000)` 与 `1000` 等价; `day(1)` 等价于 `24 * 60 * 60 * 1000`.
11. 不支持 `100ms` 或 `1s` 这类时间字面量.

```do
.normalize_name(name Text) -> Text {
    return trim(name)
}

format_user_name(u User) -> Text => normalize_name(get(u, .name))

sum(a i32, b i32) => add(a, b)

divmod(a i32, b i32) -> i32, i32 {
    q i32 = div(a, b)
    r i32 = rem(a, b)
    return q, r
}

log_info(msg Text) -> nil {
    print(msg)
    return nil
}

log_debug(msg Text) {
    print(msg)
}

nil_result() -> nil {
    return nil
}

nil_result2() {
    return
}

nil_result3() {
    return nil_result()
}

#show(T) -> Text
stringify(x T) -> Text => show(x)

update_name(user User, name Text) -> User => set(user, .name, name)
```

### 5.1 函数族决议

规则:

1. 同名重载允许存在于当前模块.
2. 决议顺序固定: 具体类型 > 约束默认实现 > 无约束泛型.
3. 具体实现与约束实现同时可用时, 具体实现优先.
4. 同层约束默认实现若有交集, 声明期报错.
5. 字面量没有默认类型, 只能在唯一上下文中定型或显式构造.

---

## 6. 语句

```ebnf
Stmt           := AssignStmt
               | IfStmt
               | LoopStmt
               | BreakStmt
               | ContinueStmt
               | ReturnStmt
               | DeferStmt
               | ExprStmt

AssignStmt     := ExplicitBind | BindOrUpdate
ExplicitBind   := Ident TypeExpr "=" Expr
BindOrUpdate   := LValueList "=" Expr
LValueList     := LValue ("," LValue)*
LValue         := Ident | "_"

ReturnStmt     := "return" [ReturnExprList]
ReturnExprList := Expr ("," Expr)* [","]
DeferStmt      := "defer" (Expr | Block)
ExprStmt       := Expr
```

规则:

1. 绑定可由左侧显式类型创建, 例如 `name Text = "tom"`.
2. 未声明标识符第一次出现在赋值左侧时可创建绑定, 前提是右侧能唯一推断其类型.
3. 已声明标识符出现在赋值左侧时表示更新已有绑定.
4. 赋值左侧先从当前作用域向外查找同名绑定; 找到最近绑定则更新该绑定.
5. 查找不到同名绑定时, 在当前作用域创建新绑定.
6. 显式类型声明在当前作用域创建绑定, 但不得与任意外层可见绑定同名.
7. 任何新绑定都不得遮蔽外层可见绑定, 包括参数, 推断创建和多左值创建.
8. 多重作用域存在同名绑定时, 更新最近的可见绑定.
9. 前置 `_` 的只读标识符首次绑定后不可更新, 即使从外层查找到也不可更新.
10. `_` 是丢弃位, 不创建绑定.
11. 无法为新绑定唯一推断类型时报编译错误.
12. 新绑定可从右侧已定型表达式推断类型; 裸字面量不能单独作为推断来源.
13. 多左值赋值先求值右侧表达式并固定结果, 再从左到右处理左侧绑定/更新.
14. 同一作用域内禁止重复声明同名绑定.
15. `return` 不带表达式时只能用于 `nil` 返回上下文.
16. `return nil` 与 `return` 在 `nil` 返回上下文中等价.
17. `return expr` 中 `expr` 的结果为 `nil` 时, 与 `return nil` 等价.
18. Lambda 块体使用同一套 `nil` 返回规则.
19. Lambda 不能绑定到顶层值或局部变量.
20. 函数内部不允许声明函数或结构体; 需要命名复用时使用顶层私有函数.
15. 多左值赋值左侧同一绑定名不得重复出现; `_` 可重复.
16. 多左值赋值只接收函数多返回结果, 不自动展开 `Tuple`, `List` 或 `Struct`.
17. 多左值数量必须与函数返回值数量一致.
18. 多返回表达式不能作为单值表达式使用.
19. 多返回表达式只允许出现在多左值赋值右侧, 或 `return` 的完整返回位中.
20. 需要把多返回作为值传递时, 必须显式构造 `Tuple`.
21. `return` 不做多返回混合展开; 多返回表达式若用于 `return`, 必须单独占据整个 `return`.
22. `return` 的返回位数量和每位类型必须与当前函数返回签名一致.
23. `return e1, e2` 是显式返回表达式列表, 每个表达式必须是单值表达式.
24. 单个多返回表达式可整体匹配当前函数返回签名.
25. 表达式体 `=>` 不做多返回混合展开; 多返回表达式若用于表达式体, 必须单独占据整个表达式体.
26. 表达式体返回位数量和每位类型必须与函数返回签名一致.
27. 表达式体函数省略返回类型时, 单值表达式推断单返回类型.
28. 表达式体函数省略返回类型时, 独占整个表达式体的多返回表达式可推断多返回签名.
29. `=> e1, e2` 是显式返回表达式列表, 每个表达式必须是单值表达式.
30. 单个多返回表达式可整体匹配或推断多返回签名.
31. 不存在默认零值.
32. `defer` 只在当前作用域离开时执行, 不参与控制流决策.
33. `defer` 按后进先出执行.
34. `defer` 的表达式/块只做收尾动作, 不允许 `return` / `break` / `continue`.

```do
name Text = "tom"
age i32 = 0

name = "bob"

count = len(users)
q, r = divmod(i32(10), i32(3))
cat = get(item, .category)

count i32 = 0
loc_count = add(count, 1)
count = loc_count

defer print("cleanup")
defer {
    close(file)
    print("closed")
}

return nil
```

### 6.1 if 语句

```ebnf
IfStmt         := "if" Expr Block ["else" Block]
               | "if" Expr Stmt
```

规则:

1. `if` 条件位必须是单值布尔表达式.
2. 不支持 if 内解构.
3. 不支持模式分支.
4. `is(Type, value)` 用于类型判断和收窄.
5. `eq(value, literal)` 用于字面量和 `nil` 判断.
6. `if is(Type, value)` 的真分支内, `value` 收窄为 `Type`.
7. `if eq(value, literal)` 的真分支内, `value` 收窄为该字面量类型或 `nil`.

```do
if eq(user, nil) {
    return nil
}

if is(User, user) {
    print(get(user, .name))
}
```

### 6.2 loop 语句

```ebnf
LoopStmt       := "loop" "{" [Label] Stmt* "}"
               | "loop" LoopCond "{" [Label] Stmt* "}"
               | "loop" LoopBind "=" LoopSource "{" [Label] Stmt* "}"
LoopCond       := Expr
LoopBind       := Ident | Ident "," Ident
LoopSource     := Expr
BreakStmt      := "break" [Label]
ContinueStmt   := "continue" [Label]
Label          := "'" Ident
```

规则:

1. `loop cond {}` 是条件循环.
2. `loop bind = source {}` 是遍历循环.
3. 迭代源必须能被编译器适配成 iterator; 内部按 `next(iterator) -> item, done` 消费, `done = true` 表示结束.
4. `List`, `Map`, `range`, `Stream`, `Event` 是预置可迭代源.
5. 其他类型若无法适配成 iterator, 编译错误.
6. 单绑定取元素值.
7. 双绑定取 key/index 在前, value 在后; `List` 为 `index, value`, `Map` 为 `key, value`, `range` 为 `index`.
8. `loop` 不做异常排除式匹配.
9. 标签写在左大括号右侧: `loop { 'outer ... }`.
10. `break` 和 `continue` 都可带标签; 不带标签时作用当前循环.

```do
loop user = users {
    print(get(user, .name))
}

loop i, user = users {
    print(i)
    print(get(user, .name))
}

loop key, val = user_map {
    print(key, val)
}

loop eq(count, 10) {
    count = add(count, 1)
}

loop { 'outer
    loop x = xs {
        if eq(x, nil) break 'outer
        if eq(x, 0) continue
        if skip_outer(x) continue 'outer
        print(x)
    }
}
```

---

## 7. 表达式与字面量

```ebnf
Expr           := CallExpr
               | DoExpr
               | LambdaExpr
               | DotBraceLit
               | StructLit
               | Ident
               | Literal

CallExpr       := Callee "(" Args? ")"
Callee         := Ident
Args           := Expr ("," Expr)* [","]
DoExpr         := "do" CallExpr
LambdaExpr     := "(" LambdaParams? ")" LambdaTail
LambdaTail     := ["->" ReturnSpec] (Block | "=>" ArrowExprList)

PathKey        := "." Ident
DotBraceLit    := ".{" DotBraceItems? "}"
DotBraceItems  := DotBraceItem ("," DotBraceItem)* [","]
DotBraceItem   := Ident ":" Expr
               | Expr
               | Expr ":" Expr

StructLit      := TypeName "{" StructFields? "}"
StructFields   := StructField ("," StructField)* [","]
StructField    := Ident ":" Expr

Literal        := IntLit | FloatLit | String | "true" | "false" | "nil"
```

表达式形态示例:

1. `CallExpr`: `add(a, b)` 表示函数调用.
2. `DoExpr`: `do fetch_user(id)` 表示启动并发任务, 返回包含 `Error` 的 `Future<T | Error>`.
3. `LambdaExpr`: `(user) => set(user, .name, "tom")` 表示匿名函数表达式, 只能直接用于签名已知的回调参数位置.
4. `DotBraceLit`: `.{1, 2, 3}` 表示上下文定型聚合字面量.
5. `StructLit`: `User{name: "tom"}` 表示显式结构体构造.
6. `Ident`: `user` 表示本地标识符引用.
7. `Literal`: `1`, `"tom"`, `true`, `nil` 表示字面量.

聚合字面量规则:

1. `.{...}` 是上下文定型聚合字面量, 类型必须由左侧声明, 参数位, 返回位或其他上下文唯一确定.
2. `.{id: 1, name: "tom"}` 用于结构体字段构造.
3. `.{1, 2, 3}` 用于 `List` 或 `Tuple` 构造.
4. `.{"a": 1, "b": 2}` 用于 `Map` 构造.
5. `.{...}` 不用于批量字段读取或批量字段更新.
6. `.{...}` 按目标类型解释: `Struct` 使用 `Ident ":" Expr`, `Map` 使用 `Expr ":" Expr`.
7. 无目标类型或多个解释同时成立时报编译错误.
8. `DotBraceItem` 解析优先级固定为: `Ident ":" Expr`, `Expr ":" Expr`, `Expr`.
9. `.{...}` 是已知结构体目标类型的短写, 不能单独反推出结构体名.
10. `StructLit` 显式指定名义结构体类型, 可用于函数返回类型推断.
11. `StructLit` 不能显式初始化外部模块的私有字段.
12. `StructLit` 和目标类型为结构体的 `DotBraceLit` 使用同一套字段匹配和私有字段权限规则.

项形态示例:

1. `Ident ":" Expr`: `.{name: "tom"}` 表示结构体字段构造项.
2. `Expr`: `.{1}` 表示 `List` 或 `Tuple` 元素项.
3. `Expr ":" Expr`: `.{"a": 1}` 表示 `Map` 键值项.

```do
u User = .{id: 1, name: "tom"}
xs List<i32> = .{1, 2, 3}
kv Map<Text, i32> = .{"a": 1, "b": 2}
t Tuple<i32, Text> = .{1, "ok"}
```

### 7.1 字面量规则

1. 所有字面量都没有默认类型.
2. 字面量必须由上下文唯一确定类型, 或显式构造.
3. `nil` 只能定型为 `nil` 或包含 `nil` 的联合类型.
4. 上下文定型来源包括: `ExplicitBind` 左侧类型, 可唯一推断的绑定目标, 函数参数唯一候选, 返回位, `.{...}` 聚合目标类型, 显式类型构造.
5. 上下文无法唯一确定字面量类型时编译错误.

### 7.2 访问与更新

1. 不支持 `obj.field`.
2. `PathKey` 是通用路径段表达式, 字段路径段固定写 `.field`.
3. `PathKey` 不是普通 `Expr`, 只能出现在路径参数位置或路径列表 `.{...}` 的路径段位置.
4. 路径参数位置可混用字段路径段, List index 和 Map key.
5. 字段路径段使用 `.field`; List index 使用整数表达式; Map key 使用键类型表达式.
6. 编译器按当前路径目标类型解释每个路径段: 结构体接受字段段, `List<T>` 接受整数 index, `Map<K,V>` 接受 `K` 类型 key.
7. 路径型函数不使用不定参数; path 必须作为一个显式聚合参数传入.
8. 单段路径可直接传 `PathKey`, 例如 `get(user, .name)`.
9. 多段路径必须传 `.{...}` 路径列表, 例如 `get(state, .{.users, usize(0), .name})`.
10. 不支持批量读取; 多字段读取需多次调用 `get`.
11. `set(target, path, value)` 更新路径值.
12. `update(target, path, updater)` 使用同型更新函数 `(old T) -> T`.
13. 不支持批量更新; 多字段更新需多次调用 `set` 或 `update`.
14. 私有字段路径段只能在声明该结构体的模块内使用; 使用时同样写 `.field`.

```do
name Text = get(user, .name)
first User = get(users, usize(0))
user = set(user, .name, "tom")
users = set(users, usize(0), user)

name = get(user, .name)
age = get(user, .age)
user = set(user, .name, "bob")
user = set(user, .age, 18)

state = set(state, .{.user, .address, .city}, "Paris")
name = get(state, .{.users, usize(0), .name})
state = set(state, .{.users, usize(0), .name}, "tom")

arr = update(user_arr, usize(3), (user) => set(user, .name, "tom"))

arr2 = update(user_arr, usize(3), (user User) -> User {
    return set(user, .name, concat("[]", get(user, .name)))
})
```

### 7.3 布尔与类型判断

1. `is(Type, value)` 只接受类型作为第 1 个参数.
2. `eq(value, literal)` 用于字面量、`nil` 和普通相等判断.
3. `and/or/not` 是短路控制函数.
4. 不支持中缀运算符.

---

## 8. 与其他规范关系

1. 异步语法与控制语义见本文件第 7 章.
2. 内存与 COW 策略见 `gc.md`.
3. 运行时调度实现细节见独立文档.
