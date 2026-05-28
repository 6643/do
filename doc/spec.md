# do 语言规范 (spec v1)

## 0. 状态

1. 本文是 `do` 的单文件规范。
2. 第 3 章 `PEG` 是 parser 可执行文法。
3. 第 6 章是静态约束，供 sema/test 执行。
4. 本文是 do 的单文件规范。

## 1. 分层边界

1. `PEG` 只定义可解析结构，不承载类型推导或收窄推理。
2. 静态约束只定义可通过规则，不重复书写 parser 结构。
3. 运行层按 `native -> core -> std` 分层；依赖只能向下。
4. `native` 是编译器/Wasm/host 桥接层，提供 special form 与底层 primitive；`core` 和 `std` 通过它使用这些能力。
5. `core` 是默认可见核心库，封装 `native` 并提供语言最小可用函数值、数值函数、结构字段操作与连续存储 primitive。
6. `std` 是可导入标准库，基于 `core` 提供扩展能力。
7. `is/and/or/not` 属于 `native` special form。
8. `eq/ne/lt/le/gt/ge` 由 `core` 预定义并固定提供。
9. 数值与位运算基础函数（如 `add/sub/mul/div/rem`）属于 `core`，由 `native` primitive 支撑；`add/sub/mul/div/rem` 接收同类型 2 个及以上参数。
10. `[T]` 是 `core` 连续存储 primitive，表示任意多个连续的 `T` 值；它不是集合类型，也不携带长度信息，标准库或用户库可用它实现 `List/HashMap` 等普通泛型结构体或类型别名。
11. `Text` 不是 `core` 预导入类型；标准库里它按 `Text = [u8]` 的别名形态提供，底层就是字节序列。
12. 时间换算函数（如 `ms/sec/day`）属于 `std` 时间库。
13. `Error` 由编译器合成，聚合当前可达模块中所有对外可见的 `*Error` 联合类型，以及内建运行时错误分支。
14. `to_*` 是统一转换函数族；数值类型之间的 `to_*` 转换属于 `core`，`Text` 参与的 `to_*` 解析重载属于 `std`。
15. 可证明总成功的 `to_*` 转换返回目标类型，可能失败的窄化转换返回 `T | Error`；例如 `to_i8(Text) -> i8 | Error`。
16. `to_text` 属于 `std` 的通用可视化函数，覆盖基础值、`Struct`、`Union`，以及编译器暴露的函数引用（若该值形态存在）；输出稳定可读文本，仅用于展示，不承担序列化职责。
17. `core` 的数值转换由编译器按静态签名 lower 到内部实现；`std` 的 `to_*` / `to_text` 以普通标准库函数提供，并可由 `core` 组合实现。
18. `to_text` 的输出格式必须稳定；相同输入在相同版本内输出一致。
19. 字符串输出必须带必要转义。
20. `Struct` 采用字段构造风格；`Union` 统一按 `Type.Branch` 展示，`Error` 统一按 `Error.Branch` 展示。
21. 函数引用若参与展示，只输出可读名称。
22. 本版只预留 `do` 语法位；并发语义作为后续版本或标准库能力扩展。
23. 网络库属于 `std`；本版只定义地址、TCP listener/stream、UDP socket 等值形态。真实 `listen/connect/accept/read/write/send/recv/close` 等 host ABI 能承载 buffer 和资源句柄后再由标准库封装。

## 2. 词法与命名

### 2.1 标识符与字面量

```ebnf
LowerIdent    := [a-z][a-z0-9]* ("_" [a-z0-9]+)*
UpperIdent    := [A-Z][A-Za-z0-9]*
ErrorTypeName := [A-Z][A-Za-z0-9]* "Error"
ReadonlyIdent := "_" LowerIdent
Ident         := LowerIdent | UpperIdent | ReadonlyIdent
PathSeg       := [a-z] ([a-z0-9]* ('_' [a-z0-9]+)*)?

IntLit        := [0-9]+
FloatLit      := [0-9]+ "." [0-9]+
StringToken   := NormalString | LineStringLine
NormalString  := "\"" StringChar* "\""
StringChar    := NormalChar | EscapeSeq
NormalChar    := ? any character except '"', '\', LF, CR ?
EscapeSeq     := "\\" ("\"" | "\\" | "n" | "r" | "t")
LineStringLine := "\\\\" LineStringChar*
LineStringChar := ? any character except LF, CR ?
```

规则:

1. 丢弃位只写 `_`；普通标识符使用 `LowerIdent`、`UpperIdent` 或 `ReadonlyIdent`。
2. 只读标识符写作前置 `_` 加小写名，例如 `_name`。
3. `UpperIdent` 用于类型名、类型参数名和错误分支值，命名风格采用 UpperCamel；缩写按普通词处理，例如 `HttpServer`、`UserId`。
4. 顶层私有声明使用前置 `.`，例如 `.internal_name`。
5. 字段路径段使用前置 `.`, 例如 `.name`。
6. 循环标签使用前置 `#`, 例如 `#outer`。
7. 普通字符串写成单行 `"..."`。
8. 支持转义：`\"`, `\\`, `\n`, `\r`, `\t`。
9. 行字符串使用 Zig 风格 `\\text`，内容从 `\\` 后开始到行尾结束。
10. 连续行字符串可组成多行字符串值，各行之间用 `\n` 连接；源码缩进不进入字符串值。
11. 表达式位置可读取 `LineStringBlock`；它由一个或多个连续行字符串组成。
12. 多行 `LineStringBlock` 出现在明确等待表达式的位置。
13. 字符串值中的空行必须显式写成空内容行字符串 `\\`；源码空行会打断 `LineStringBlock`。
14. 行字符串不解释转义；`\\a\nb` 的内容是字面文本 `a\nb`。
15. raw 文本使用行字符串 `\\text`。
16. 块注释写作单层 `/* ... */`。
17. lexer 在 token 化前将 `CRLF` 与 `CR` 归一化为 `LF`；parser 只接收统一的 `NL` token。
18. parser 输入是 token 流；空格与制表符在词法阶段剔除，换行保留为 `NL` token。
19. 顶层声明与块内语句使用换行分隔；一行一个声明或语句。
20. 关键字按整 token 匹配，不做前缀匹配；例如 `dof` 是一个 `Ident`，不是 `do` + `f`。
21. `Text/List/HashMap` 等库类型由 `std` 或用户库定义，并按普通 `RefTypeName` 解析；其中 `Text` 的标准形态是 `[u8]` 别名。
22. `LambdaExpr` 只出现在调用实参位，作为回调表达式；语法形如 `(x i32) => add(x, 1)`、`(x i32) -> i32 => add(x, 1)` 或 `(x i32) -> i32 { ... }`。
23. `LambdaExpr` 只读自身参数、体内绑定、顶层常量和当前可见函数，不形成闭包，不能捕获外层局部绑定，也不能绑定到变量或作为值返回。
24. 顶层函数的 `=>` 函数体是函数声明短写，不是 `LambdaExpr`，不产生可传递函数值。
25. 函数名可在已有目标 `FuncType` 的值位作为函数值传递，例如高阶函数实参、字段初始化或返回位。
26. lambda 参数类型可省略；省略时必须由已选调用候选的目标 `FuncType` 提供参数类型，不能由 lambda body 反推。
27. lambda 返回类型可省略；省略时在调用候选已选定、参数类型已确定后，由 lambda body 推出返回类型。
28. 块体 lambda 内的 `return` 只返回当前 lambda，不返回外层函数或测试体。
29. 算术、比较和逻辑组合使用函数或 `native` 判断族表达。
30. import 路径段使用 `PathSeg`；路径段由小写字母开头，可含数字，单词之间用单个 `_` 分隔。

### 2.2 保留词与保留标识符

```
if else loop break continue return defer do test
is and or not
true false nil
```

以上保留词只用于语言保留位置。

保留标识符（仅用于保留位置）:

```
eq ne lt le gt ge
```

保留类型名（仅用于保留位置）:

```
Error
```

## 3. PEG 主文法

> 说明：此处按 token 流的可执行文法给出。lexer 层剔除空格/制表符并保留 `NL`。

```peg
Program          <- TopDeclList EOF
EOF              <- !.

TopDeclList      <- DeclSep? TopDecl (DeclSep TopDecl)* DeclSep?
DeclSep          <- NL+
LineGap          <- NL
SoftGap          <- NL*
CommaSep         <- SoftGap ',' SoftGap
TrailComma       <- SoftGap ','

TopDecl          <- TypeDecl
                  / FuncDecl
                  / ImportDecl
                  / ValueDecl
                  / TestDecl

ValueDecl        <- ConstName TypeAnn? '=' Expr
ConstName        <- ReadonlyIdent
TypeAnn          <- TypeExpr

ImportDecl       <- ImportName '=' ImportRef
ImportName       <- UpperIdent / LowerIdent / ReadonlyIdent
ImportRef        <- LocalImport / HostImport
LocalImport      <- '@' ModuleFile '/' ImportTarget
HostImport       <- '@' HostPath HostSig
ImportTarget     <- UpperIdent / LowerIdent / ReadonlyIdent
ModuleFile       <- ProjectLibFile / StdFile / RelativeFile
ProjectLibFile   <- '~/' ModulePath '.do'
StdFile          <- '/' ModulePath '.do'
RelativeFile     <- ModulePath '.do'
ModulePath       <- PathSeg ('/' PathSeg)*
HostPath         <- PathSeg ('/' PathSeg)*
HostSig          <- '(' SoftGap AbiParamList? SoftGap ')' SoftGap '->' SoftGap AbiReturn
AbiParamList     <- AbiType (CommaSep AbiType)* TrailComma?
AbiReturn        <- 'nil' / AbiType
AbiType          <- 'i32' / 'i64' / 'f32' / 'f64'

TestDecl         <- 'test' String Block

TypeDecl         <- GenericStructDecl / StructDecl / ErrorDecl / AliasDecl
GenericStructDecl <- TypeConstraintList StructDecl
StructDecl       <- DeclTypeName '{' StmtGap? FieldDeclList? StmtGap? '}'
ErrorDecl        <- ErrorTypeName '=' ErrorBranchList
AliasDecl        <- DeclTypeName '=' TypeExpr
ErrorBranchList  <- ErrorBranchName (SoftGap '|' SoftGap ErrorBranchName)*
ErrorBranchName  <- UpperIdent
DeclTypeName     <- PublicTypeName / PrivateTypeName
PublicTypeName   <- UpperIdent
PrivateTypeName  <- '.' UpperIdent
FieldDeclList    <- FieldDecl (StmtGap FieldDecl)* StmtGap?
FieldDecl        <- FieldName TypeExpr FieldDefault?
FieldDefault     <- '=' Expr
FieldName        <- PublicFieldName / PrivateFieldName
PublicFieldName  <- LowerIdent
PrivateFieldName <- '.' LowerIdent

RefTypeName      <- PublicTypeName

TypeExpr         <- UnionExpr
UnionExpr        <- TypeAtom ('|' TypeAtom)*
TypeAtom         <- BaseType
                  / StorageType
                  / FuncType
                  / RefTypeName TypeArgs?
                  / '(' SoftGap TypeExpr SoftGap ')'
                  / LiteralType
FuncType         <- '(' SoftGap TypeExprList? SoftGap ')' SoftGap '->' SoftGap ReturnSpec
TypeArgs         <- '<' SoftGap TypeExpr (CommaSep TypeExpr)* TrailComma? SoftGap '>'
StorageType      <- '[' SoftGap TypeExpr SoftGap ']'
BaseType         <- 'i8' / 'i16' / 'i32' / 'i64'
                  / 'u8' / 'u16' / 'u32' / 'u64'
                  / 'isize' / 'usize'
                  / 'f32' / 'f64'
                  / 'bool'
LiteralType      <- IntLit / FloatLit / String / 'true' / 'false' / 'nil'
String           <- NormalString / LineStringBlock
LineStringBlock  <- LineStringLine (LineGap LineStringLine)*

FuncDecl         <- FuncConstraintList? FuncName '(' SoftGap ParamList? SoftGap ')' FuncResult FuncBody
FuncName         <- PublicFuncName / PrivateFuncName
PublicFuncName   <- !ReservedDeclName LowerIdent
PrivateFuncName  <- '.' PublicFuncName
FuncResult       <- (SoftGap '->' SoftGap ReturnSpec)?
ReturnSpec       <- MultiReturnSpec / 'nil' / TypeExpr
MultiReturnSpec  <- TypeExpr CommaSep TypeExpr (CommaSep TypeExpr)*
FuncBody         <- Block / '=>' ArrowExprList
ArrowExprList    <- Expr (CommaSep Expr)* TrailComma?

FuncConstraintList <- TypeConstraintList FuncSigConstraintLine*
TypeConstraintList <- TypeConstraintLine+
TypeConstraintLine <- '#' TypeParamName (SoftGap '=' SoftGap UnionExpr)? LineGap
FuncSigConstraintLine <- '#' ConstraintFuncName '(' SoftGap ConstraintParamList? SoftGap ')' SoftGap '->' SoftGap ReturnSpec LineGap
TypeParamName    <- UpperIdent
ConstraintFuncName <- LowerIdent
ConstraintParamList <- ConstraintFixedParamList (CommaSep ConstraintVariadicParam)? TrailComma?
                  / ConstraintVariadicParam TrailComma?
ConstraintFixedParamList <- TypeExpr (CommaSep TypeExpr)*
ConstraintVariadicParam <- '...' TypeExpr
TypeExprList     <- TypeExpr (CommaSep TypeExpr)* TrailComma?

ParamList        <- FixedParamList (CommaSep VariadicParam)? TrailComma?
                  / VariadicParam TrailComma?
FixedParamList   <- Param (CommaSep Param)*
Param            <- ParamName TypeExpr
VariadicParam    <- ParamName VariadicType
VariadicType     <- '...' TypeExpr
ParamName        <- LowerIdent / '_'

Block            <- '{' StmtGap? StmtList? StmtGap? '}'
StmtList         <- Stmt (StmtGap Stmt)* StmtGap?
StmtGap          <- NL+

Stmt             <- IfStmt
                  / LoopLabelStmt
                  / LoopStmt
                  / BreakStmt
                  / ContinueStmt
                  / ReturnStmt
                  / DeferStmt
                  / AssignStmt
                  / ExprStmt

AssignStmt       <- TypedBind '=' Expr
                  / LValueList '=' Expr
TypedBind        <- BindName TypeExpr
LValueList       <- LValue (CommaSep LValue)*
LValue           <- BindName / '_'
BindName         <- LowerIdent / ReadonlyIdent

ReturnStmt       <- 'return' ReturnTail?
ReturnTail       <- Expr (CommaSep Expr)* TrailComma?
DeferStmt        <- 'defer' (Expr / Block)
ExprStmt         <- Expr

IfStmt           <- 'if' Expr Block ElseTail?
                  / 'if' Expr GuardStmt
ElseTail         <- SoftGap 'else' SoftGap (IfStmt / Block)
GuardStmt        <- ReturnStmt / BreakStmt / ContinueStmt

LoopLabelStmt    <- LoopLabel LineGap LoopStmt
LoopStmt         <- 'loop' LoopHead? LoopBlock
LoopHead         <- LoopCollection / LoopConsumer
LoopCollection   <- LoopBindName CommaSep LoopBindName '=' Expr
LoopConsumer     <- LoopBindName '=' RecvExpr
RecvExpr         <- 'recv' '(' SoftGap Expr SoftGap ')'
LoopBindName     <- LowerIdent / '_'
LoopBlock        <- '{' StmtGap? StmtList? StmtGap? '}'
LoopLabel        <- '#' Ident
BreakStmt        <- 'break' LoopLabel?
ContinueStmt     <- 'continue' LoopLabel?

Expr             <- DoExpr
                  / PredExpr
                  / CoreAccessExpr
                  / CallExpr
                  / InferredAggLit
                  / TypedAggLit
                  / ParenExpr
                  / Ident
                  / Literal

DoExpr           <- 'do' CallExpr
ParenExpr        <- '(' SoftGap Expr SoftGap ')'

PredExpr         <- IsExpr
                  / EqExpr
                  / NeExpr
                  / LtExpr
                  / LeExpr
                  / GtExpr
                  / GeExpr
                  / AndExpr
                  / OrExpr
                  / NotExpr

IsExpr           <- 'is' '(' SoftGap Expr CommaSep TypeExpr SoftGap ')'
EqExpr           <- 'eq' '(' SoftGap Expr CommaSep Expr SoftGap ')'
NeExpr           <- 'ne' '(' SoftGap Expr CommaSep Expr SoftGap ')'
LtExpr           <- 'lt' '(' SoftGap Expr CommaSep Expr SoftGap ')'
LeExpr           <- 'le' '(' SoftGap Expr CommaSep Expr SoftGap ')'
GtExpr           <- 'gt' '(' SoftGap Expr CommaSep Expr SoftGap ')'
GeExpr           <- 'ge' '(' SoftGap Expr CommaSep Expr SoftGap ')'
AndExpr          <- 'and' '(' SoftGap Expr CommaSep Expr SoftGap ')'
OrExpr           <- 'or' '(' SoftGap Expr CommaSep Expr SoftGap ')'
NotExpr          <- 'not' '(' SoftGap Expr SoftGap ')'

CoreAccessExpr   <- GetExpr / SetExpr
GetExpr          <- 'get' '(' SoftGap Expr CommaSep PathArgList SoftGap ')'
SetExpr          <- 'set' '(' SoftGap Expr CommaSep SetArgList SoftGap ')'

PathArgList      <- PathArg (CommaSep PathArg)* TrailComma?
PathArg          <- FieldSeg / IndexSeg
SetArgList       <- SetArg (CommaSep SetArg)+ TrailComma?
SetArg           <- FieldSeg / Expr
IndexSeg         <- Expr
FieldSeg         <- '.' LowerIdent

CallExpr         <- Callee '(' SoftGap ArgList? SoftGap ')'
Callee           <- Ident
ArgList          <- FixedArgList (CommaSep SpreadArg)? TrailComma?
                  / SpreadArg TrailComma?
FixedArgList     <- Arg (CommaSep Arg)*
Arg              <- LambdaArg / Expr
LambdaArg        <- LambdaExpr
SpreadArg        <- '...' Expr

LambdaExpr       <- '(' SoftGap LambdaParamList? SoftGap ')' SoftGap LambdaTail
LambdaParamList  <- LambdaParam (CommaSep LambdaParam)* TrailComma?
LambdaParam      <- ParamName (SoftGap TypeExpr)?
LambdaTail       <- ReturnTailAnn? (Block / '=>' ArrowExprList)
ReturnTailAnn    <- SoftGap '->' SoftGap ReturnSpec

InferredAggLit   <- '.' InferredAggBody
TypedAggLit      <- TypeCtor TypedAggBody
TypeCtor         <- RefTypeName TypeArgs?
InferredAggBody  <- '{' SoftGap (FieldInitList / AggExprList)? SoftGap '}'
TypedAggBody     <- '{' SoftGap FieldInitList? SoftGap '}'
FieldInitList    <- FieldInit (CommaSep FieldInit)* TrailComma?
FieldInit        <- FieldInitName SoftGap '=' SoftGap Expr
FieldInitName    <- LowerIdent
AggExprList      <- Expr (CommaSep Expr)* TrailComma?

Literal          <- IntLit / FloatLit / String / 'true' / 'false' / 'nil'

ReservedDeclName <- 'eq' / 'ne' / 'lt' / 'le' / 'gt' / 'ge'
NL               <- '\n'
```

## 4. 判断族

### 4.1 Native 成员

`is`, `and`, `or`, `not`

### 4.2 Core 成员

`eq`, `ne`, `lt`, `le`, `gt`, `ge`

### 4.3 规则

1. `native` 判断族按 special form 规则解析。
2. `core` 预定义判断函数族固定提供。
3. 判断族返回 `bool`。
4. `and/or/not` 采用短路求值，并参与控制流收窄；`and/or` 按左到右传播收窄，`not` 反转收窄信息。
5. `is(value, TypeSet)` 做类型集合判断；`TypeSet` 可为非字面量类型表达式或联合类型表达式，真分支触发类型收窄。
6. `is` 的第二参数是类型表达式或联合类型表达式；`nil`、字符串、数字、`FileNotFound` 这类值判断使用 `eq/ne`。
7. guard 形式 `if cond return/break/continue` 退出后，后续路径中使用 `cond` 的反向信息继续收窄。
8. 普通块体 `if` 只在分支内部收窄，不把“块内必定退出”分析带到后续语句；后续语句收窄只由 guard 形式提供。
9. `else if` 支持跨分支收窄：后一分支继承前面条件的反向信息。
10. `eq/ne` 做相等与不等判断；可用于 `nil`、字面量、错误分支值与一般值比较。
11. `eq/ne` 对明确联合分支值触发收窄；`nil` 只是其中一种值分支。
12. `lt/le/gt/ge` 适用于可排序类型。
13. `eq/ne` 对标量、`bool` 与普通聚合值使用值语义；用户库实现的集合或字节文本类型若暴露为结构体值，也按其公开语义参与比较。
14. 用户类型需要业务相等或业务排序时，应定义领域函数，不覆盖 `eq/ne/lt/le/gt/ge`。
15. `Error` 是编译器合成的特殊错误聚合类型，`is(value, Error)` 用于测试值是否落入该聚合。
16. `is(value, FileError)` 这类具体联合类型判断同样有效，按联合成员测试处理。
17. `eq/ne` 始终只做精确值比较，不把 `Error` 或任何联合类型名当作类型测试的替代。
18. `*Error` 类型名出现在类型位或 `is(value, *Error)` 中。
19. `*Error` 的分支名是值，可用于赋值、返回和 `eq/ne` 比较。

## 4.4 数值函数族

1. `add/sub/mul/div/rem` 属于 `core`，默认可见。
2. 这些函数只接受同类型参数，参数个数为 2 个及以上。
3. `add(a, b, c)` 等价于 `add(add(a, b), c)`。
4. `mul(a, b, c)` 等价于 `mul(mul(a, b), c)`。
5. `sub(a, b, c)` 等价于 `sub(sub(a, b), c)`。
6. `div(a, b, c)` 等价于 `div(div(a, b), c)`。
7. `rem(a, b, c)` 等价于 `rem(rem(a, b), c)`。
8. 数值函数族可在泛型约束中写作 `#add(T, ...T) -> T`。

## 5. 结构操作族

### 5.1 定位

1. `get/set` 是语言识别的结构访问形式，语法上使用 `CoreAccessExpr`，语义上按开放结构操作协议分派。
2. `core` 只提供 struct 字段路径和 `[T]` 连续存储的基础读写 primitive；`std` 或用户库可通过可见的 `get/set` 定义接入对应类型。
3. `put/update/del/len/at` 是普通开放函数族，由 `core`、`std` 或用户库按普通函数定义具体重载。
4. 多段结构路径使用扁平参数形态；字段/索引路径统一从 `get/set` 进入，集合设计由库层承载。
5. 结构字段读写统一只走 `get/set` 路径形态，例如 `get(x, .name)`、`set(x, .name, value)`。
6. `put` 可用于集合追加、插入、键写入或其他库自定义更新语义；例如 `List` 可把 `put(xs, value, rest ...T)` 作为批量追加重载。
7. `del` 可用于列表索引删除、映射 key 删除或其他库自定义删除语义。
8. `update` 作为普通库函数定义；需要时可由 `std` 基于 `get/set` 提供。

### 5.2 路径形态

1. 单段字段路径写作 `FieldSeg`，例如 `.name`。
2. 多段路径写作扁平实参，例如 `get(users, 0, .name)` 或 `set(users, add(i, 1), .name, value)`。
3. `get` 使用 `PathArgList`，全部尾部参数都是路径段。
4. `set` 使用 `SetArgList`，第一个参数是目标值，尾部参数列表最后一项是待写入值，之前的所有项都是路径段。
5. `set(target, path..., value)` 至少包含一个路径段和一个待写入值；PEG 不用贪婪 `PathArgList` 切分最终值。
6. 路径段单段为 `PathArg`，分为字段段与索引段：字段段是前置点加单个 `LowerIdent`；索引段是 `Expr`。
7. 路径段是 `get/set` 的原语级语法，不暴露为 `core` 或 `std` 的值类型。
8. 字段段只用于结构体字段访问；索引段只用于 `[T]` 连续存储或库类型定义的索引访问。
9. 复杂表达式段在路径求值时直接计算；字段段按 `.lower_ident` 展示，索引段按其可读表达展示。

### 5.3 调用示例

```do
name Text = get(user, .name)
state = set(state, .user, .name, "tom")
item = get(user, .abc, add(i, 1), .name)
```

```do
Text = [u8]
```

### 5.4 返回与失败语义

1. `get(target, path)` 的返回按路径段决定：
   - 只含字段段时返回 `V`，其中 `V` 是路径终点值类型。
   - 含任意索引段时返回 `V | nil`。
2. 字段段直接返回字段值类型；字段不存在在编译期报类型错误。
3. 含索引段时，索引越界、键不存在、路径中途取不到值，返回 `nil`；普通结构访问缺失返回 `nil`。
4. 如果终点类型本身包含 `nil`，`get` 的缺失 `nil` 与业务 `nil` 共用同一值层表示；需要区分时由业务类型显式建模。
5. `at(target, index) -> V` 表示在调用方已满足有效位置前提下读取值；安全查询仍使用 `get(target, index) -> V | nil`。
6. 集合循环在 `0..len(source)` 生成的 `usize` 位置上调用 `at`；支持集合循环的类型保证该范围内 `at` 返回 `V`。
7. `set(target, path, value) -> T | Error`，其中 `Error` 是 4.3 定义的合成错误聚合类型，`T` 是原始目标类型。
8. `set` 只更新既有路径。
9. `set` 遇到字段不存在、索引越界、用户集合键不存在或联合类型当前分支不匹配路径时返回 `Error`。
10. `Struct` 支持 `get/set`；是否支持 `put/update/del` 由具体库函数决定，不由语法层限定。
11. `List/HashMap` 作为普通库类型存在；对应操作由 `std` 或用户库以普通函数提供。
12. `HashMap` 作为循环源时使用库显式提供的 `keys(m)`、`values(m)` 或 `entries(m)` 这类返回可循环集合的函数。

## 6. 静态约束

### 6.1 命名、导入与可见性

1. 类型声明名使用 `UpperIdent`，风格为 UpperCamel；普通函数名使用 `LowerIdent`；私有普通函数声明名使用 `.lower_name`；字段名使用 `LowerIdent`。
2. 私有类型名出现在类型声明左侧（`DeclTypeName`）；类型引用位统一去点。
3. 私有声明在声明位使用前置 `.`；访问时统一去点（字段路径段除外）。
4. core 保留判断函数名由语言预定义；`get/set` 使用结构访问语法并按协议分派，`put/update/del/len/at` 可按普通重载规则扩展。
5. 顶层名字共享同一名字空间；仅同名函数族允许重名。
6. 公开签名使用 public 类型。
7. 保留词与保留类型名 `Error` 只用于语言保留位置。
8. 顶层类型声明可使用前置 `#T` / `#T = TypeSet` 声明泛型类型参数；`TypeArgs` 按声明顺序绑定类型参数。
9. import 出现在顶层。
10. import 左侧使用 `ImportName`，可以是 `UpperIdent`、`LowerIdent` 或 `ReadonlyIdent`，再按目标声明类别做后续校验。
11. import alias 是当前文件内名字；其他文件从原模块导入所需声明。
12. imported public type 可以出现在当前文件的 public API 中，但其 canonical source 仍指向来源文件。
13. imported declaration 只在当前文件内使用；对外暴露时通过本文件定义的新类型或新函数封装。
14. import alias 与目标声明类别对应：类型用 `UpperIdent`，函数用 `LowerIdent`，常量用 `ReadonlyIdent`；`*Error` 分支值是特殊 `UpperIdent` 值，导入时也使用 `UpperIdent`；host import 当前只表示函数，左侧使用 `LowerIdent`。
15. local import 目标是来源 `.do` 文件的 public 顶层声明。
16. local import 只支持三种入口：`@path/file.do/name` 为当前文件目录向下查找，`@~/path/file.do/name` 为当前项目 `/lib` 目录向下查找，`@/path/file.do/name` 为标准库根目录向下查找。
17. import 路径段统一使用 `PathSeg`。
18. local import 使用显式 symbol import：`name = @path/file.do/symbol`；目标模块会递归加载其自身依赖。
19. 模块依赖图是无环图；local import 会递归解析目标模块，缺失目标符号或任意层级的 import cycle 都是错误。
20. host import 使用 `@env/console_log(...) -> nil` 这类形式，并由编译器桥接到宿主实现；`@` 后的路径是宿主命名空间或模块路径。
21. host import 签名是 ABI 签名；参数使用 `i32/i64/f32/f64`，返回使用 `nil` 或单个 `i32/i64/f32/f64`。
22. 函数族唯一性由函数名与参数类型序列决定；同一函数名配合同一参数类型序列对应唯一定义。
23. 不定参数参与函数族唯一性；`rest ...T` 的签名尾部记作 `...T`，不同于单个 `T`。
24. 公开内建常量采用前置 `_` 和类型前缀命名：`_i8_max`、`_i8_min`、`_f32_pi`、`_f64_pi`；不采用 `max_i8`、`pi_f32` 或无 `_` 的常量名。

### 6.2 定型与字面量

1. 字面量无默认类型，由上下文唯一定型或显式类型标注。
2. `nil` 只能定型为 `nil` 或包含 `nil` 的联合类型。
3. `TypedAggLit` 只按结构体字段构造解释；`InferredAggLit` 在目标为结构体时使用字段构造，在目标为 `[T]` 时可使用元素构造（例如 `.{1, 2, 3}`）。
4. 显式标量类型通过绑定位、参数位、返回位或已知目标上下文提供。
5. 无上下文或多重解释冲突时报编译错误。
6. 定型来源只有两类：左侧或外层上下文提供已知目标类型，或右侧表达式自身能唯一推出类型。
7. 重载调用先让输入实参定型，再用实参类型序列挑选候选。
8. 若函数名与参数个数只对应唯一候选，该候选的参数类型可为实参字面量提供上下文。
9. 若存在多个同名同参数个数候选，实参必须先各自定型，再用实参类型序列选择唯一候选。
10. 外层期望类型只用于检查已选中调用的返回值类型，重载选择只看实参类型序列。
11. lambda 实参参与重载选择时，只提供参数个数、显式参数类型和显式返回类型；lambda body 不参与重载候选选择。
12. 调用候选唯一确定后，lambda body 才进入类型检查；省略的 lambda 参数类型从目标 `FuncType` 补齐，省略的 lambda 返回类型可在此阶段推出。
13. 不定参数候选匹配固定前缀实参数量后，剩余实参逐个按 `...T` 的 `T` 定型；第一版只支持同类型不定参数。
14. `...expr` 只在函数调用实参位生效，只能出现在实参列表最后，一次调用最多一个展开。
15. `...expr` 的表达式必须定型为 `[T]` 或库定义同类型连续序列，且目标参数为 `...T`。
16. 展开调用只匹配被调函数最后一个不定参数位；展开后不能再接普通实参。
17. 普通字符串和行字符串同样无默认类型；字符串字面量由目标类型上下文定型。
18. 字符串字面量可在目标类型为 `[u8]` 或库定义文本类型时由上下文定型；语法层按库类型解析。
19. 裸 `{...}` 不是表达式；聚合值写成 `.{...}` 或 `Type{...}`。
20. `.{...}` 省略目标聚合类型，由左侧标注、既有绑定、参数或返回上下文唯一确定。
21. `Type{...}` 在右侧显式给出聚合类型，可用于创建新绑定。
22. `name Type = .{...}` 与 `name = Type{...}` 是等价的创建形式。
23. `Type{...}` 的 `Type` 是具名类型及其类型参数。
24. 联合返回位要求右侧表达式自身先定型到唯一分支。
25. 结构体字段声明位的 `.field` 表示私有；字段真实名字仍是 `field`，同一结构体内同一字段写作 `field` 或 `.field`。
26. 当前模块内构造结构体时，字段初始化使用裸字段名 `field = value`；`.field` 出现在路径位或声明位。
27. 外部模块构造 public struct 时填写 public 字段；private 字段由默认值提供。
28. `TypedAggLit` 的 body 只接受字段项；`InferredAggLit` 可接受字段项或元素项，元素项仅在目标上下文为 `[T]` 时成立。
29. 结构体字段构造使用 `field = value`。
30. 字段默认值在结构体构造时求值；默认表达式结果类型与字段类型一致。
31. 结构体构造发生在 CTFE 上下文时，字段默认值也走 CTFE；运行时构造可执行运行时默认表达式。
32. `Tuple` 按普通泛型结构体字段构造解释；库若定义 `Tuple`，同样采用字段构造。
33. `ErrorDecl` 声明错误分支集合，名称使用 `ErrorTypeName`，右侧分支使用裸 `UpperIdent` 值名，例如 `FileError = FileNotFound | PermissionDenied`。
34. 普通 union 由类型表达式组成；错误分支集合只通过 `ErrorDecl` 声明。
35. `*Error` 类型名用于类型位；值位使用具体分支值。
36. `*Error` 分支值是可导入的 public 值；跨文件构造或精确比较分支值时导入该分支值。
37. `*Error` 分支值导入时可以改名以避免冲突，本地别名使用 `UpperIdent`。

### 6.3 绑定与赋值

1. 赋值左侧先查最近可见绑定；命中则更新，未命中则创建。
2. 未命中时创建新绑定，右侧表达式已经能唯一确定类型；新绑定创建使用已定型右侧表达式，`.{...}` 在存在目标类型上下文时使用。
3. 命中已有绑定时，既有绑定类型为右侧表达式提供目标上下文，例如 `y = 3` 中 `3` 由 `y` 的类型定型。
4. 绑定与赋值规则只适用于块内局部绑定；顶层 `ValueDecl` 只作为常量声明。
5. 局部绑定名使用 `LowerIdent` 或 `ReadonlyIdent`；`ReadonlyIdent` 不用于函数名；`UpperIdent` 用于类型名、类型参数名、错误分支值和同类 import alias。
6. `TypedBind` 永远声明新绑定；如果同名绑定已可见，编译器报告重复声明或遮蔽错误。
7. 新绑定不得遮蔽外层可见绑定。
8. 局部 `_name` 是运行期只读绑定；首次绑定满足普通定型规则。
9. `_name` 首次绑定后保持只读。
10. `_` 为丢弃位。
11. 局部绑定采用块作用域；`if`、`loop`、lambda 体内创建的绑定只在该块内可见。
12. 函数参数、lambda 参数和 `loop` 绑定是普通可变本地绑定；参数赋值只改变当前调用帧。
13. 参数位使用 `_` 表示丢弃参数；该参数仍计入函数签名的参数个数和类型序列。
14. 参数位与 loop 绑定位使用 `LowerIdent` 或 `_`；`_name` 用于顶层常量和局部只读绑定。
15. 不定参数声明写作 `rest ...T`，只能出现在函数参数列表最后，且一个函数最多一个不定参数。
16. 不定参数在函数体内的绑定类型是 `[T]`，可用于 `loop` 或在调用尾部写作 `...rest` 转发。
17. lambda 参数不支持不定参数；host import 参数不支持不定参数。
18. 函数名在值位解析为函数值时，必须由上下文提供目标 `FuncType`；候选集合同时包含当前文件可见函数和已导入函数族，并按函数名加参数类型序列选择唯一声明。
19. lambda 参数省略类型时，必须先由函数名、实参数量、非 lambda 实参、lambda 显式签名或唯一候选确定目标 `FuncType`；lambda body 只用于检查返回值，不参与参数类型反推。
20. lambda 返回类型省略时，可由 body 推出返回类型或绑定目标函数类型中的返回类型参数；该结果不参与重载候选选择。
21. 块体 lambda 拥有独立返回边界；其 `return` 只结束当前 lambda 调用。
22. 函数名值位若缺少目标 `FuncType`（例如 `f = inc`）且该名字对应多个重载候选，报告 `NoMatchingCall`。
23. 函数名值位若目标 `FuncType` 不唯一（例如 `use(inc)` 且 `use` 自身重载且都可接收函数参数），报告 `NoMatchingCall`。

### 6.4 返回与多返回

1. `return` 位数与类型匹配函数返回签名。
2. 多返回结果出现在多左值赋值右侧，或完整返回位。
3. 多返回出现在多左值赋值右侧或完整返回位；在单个实参、聚合元素和单变量赋值右侧先显式拆分。
4. 表达式体函数与块体函数都遵循同一返回匹配规则。
5. `nil` 返回上下文允许 `return` 与 `return nil` 等价。
6. `test` 块具有固定的 `nil` 返回上下文；`return` 只用于提前结束当前 `test`，不携带返回值或多返回。
7. 本地普通函数可省略返回类型；省略时等价并规范化为 `-> nil`。
8. host import、接口约束和其他显式签名位置都要求显式返回类型。
9. 省略返回类型的表达式体函数仍按 `-> nil` 检查，右侧若产生非 `nil` 值则报错。

### 6.5 控制流

1. `if` 的条件位是单值 `bool`。
2. `defer` 体使用普通表达式或块内副作用语句。
3. `break/continue` 标签引用当前可见循环标签。
4. `loop` 支持三种形态：
   - 无限循环：`loop { ... }`。
   - 集合循环：`loop v, i = source { ... }`；`v` 是值，`i` 是 `usize` 位置，二者都可写 `_` 丢弃。
   - 消费循环：`loop v = recv(ch) { ... }`；右侧使用 `recv(...)`，`recv(ch)` 定型为 `T | nil | Error`。
   集合循环使用 `=` 连接绑定与源。
5. 集合循环源类型 `S` 解析为 `len(S) -> usize` 与 `at(S, usize) -> V`，循环按 `0..len(source)` 的索引顺序读取值；`range(...)` 这类标准库函数只要返回满足该协议的值，就可以直接用于集合循环。
6. 集合循环的右侧表达式在进入循环前求值一次，后续循环使用该源值。
7. 集合循环中的 `v` 在协议成立前提下是 `V`，不是 `V | nil` 或 `V | Error`。
8. 消费循环用于流、通道等无长度来源；`nil` 表示正常结束，`Error` 表示失败，`T` 排除 `nil` 类型。
9. `List<T>` 是库类型；标准库或用户库若要支持集合循环，提供 `len/at` 协议函数。
10. `Text` 与其他实现了 `len/at` 协议的库类型可以直接作为集合循环源；映射遍历由库提供可迭代视图。
11. 单行 `if` 是 guard 语法，接 `return`、`break` 或 `continue`。
12. `else if` 跟在块体 `if` 后；guard `if` 不接 `else`。
13. 循环标签使用独立前置行 `#name`，标注紧随其后的 `loop`。

### 6.6 路径约束

1. `get/set` 的路径在类型上逐段解释：
   - 结构体接收字段段。
   - `[T]` 连续存储的索引由 core 函数处理，不通过结构路径暴露。
2. 私有字段路径段在声明该结构体的模块内使用。
3. 字段段写作 `.lower_ident`。
4. 索引段允许 `Expr`，但只有目标类型声明了对应结构操作时才合法；普通 struct 字段段使用 `.lower_ident`。

### 6.7 编译期约束

1. 顶层 `ValueDecl` 使用 `ReadonlyIdent`，表示全局常量。
2. 顶层常量初始化在编译期求值出结果，可引用其他顶层常量并调用普通函数；整条求值路径可 CTFE，依赖图无环。
3. 顶层常量 CTFE 求值路径由可 CTFE 的本地表达式与普通函数组成；递归与循环受编译期求值预算限制。
4. host import 属于运行时边界；build 时宿主与运行时宿主可以不同。
5. 普通函数、`test` 和 lambda 可读取顶层常量，可调用当前可见函数。
6. 编译入口写作 `start()`，无参数且无返回；wasm 导出名 `_start` 是编译器生成细节。
7. 字段默认值按构造上下文求值；顶层常量构造要求字段默认值可 CTFE，运行时构造允许运行时默认值。
8. `#T` 是无约束类型参数；`#T = TypeSet` 是受限类型参数；`#name(...) -> Return` 是函数声明前的接口函数签名约束。
9. 类型约束绑定紧随其后的一个函数或结构体；接口函数约束绑定函数。
10. 约束独立成行，连续贴合其绑定的声明头。
11. 函数约束列表先写所有类型约束，再写接口函数约束。
12. 类型参数名使用 `UpperIdent`，接口函数名使用 `LowerIdent`。
13. 类型参数名使用当前可见类型名、`core` 预导入类型名和保留类型名之外的新名字。
14. 每个类型参数至少出现在一个参数类型里。
15. 类型集合由当前可见的具体类型表达式和已声明类型参数组成。
16. 泛型函数体中对类型参数调用函数时，由对应接口函数签名约束提供能力；`#T` 只声明泛型类型参数。
17. 接口约束里的函数名只从当前文件可见名字解析；`core` 默认可见，`std` 和用户模块需要显式 import。
18. 泛型结构体声明类型参数；能力约束放在使用该类型的函数上。

### 6.8 标准库草案边界

1. `lib/net.do` 只承载 `SocketAddr` 及地址构造/读取/判断函数。
2. `lib/tcp.do` 只承载 `TcpError`、`TcpListener`、`TcpStream` 等类型形态。
3. `lib/udp.do` 只承载 `UdpError`、`UdpSocket` 等类型形态。
4. TCP/UDP 的实际 I/O 留到 host ABI 扩展后实现；原因是当前 host import ABI 只表达 `i32/i64/f32/f64/nil`。
5. 后续若扩展 host ABI，应先定义资源句柄、buffer 传递、错误编码和关闭语义，再在 `std` 中提供普通 do 函数封装。
6. 这与 Go/Rust/Zig 的标准库分层方向一致：地址类型、TCP listener/stream 和 UDP socket 分离；差异是 `do` 的最终目标是 wasm，因此系统调用能力必须由宿主桥接提供。
7. `lib/binary.do` 属于 `std` 字节编解码辅助库；hash/encoding 库按需显式 import。
8. 高阶组合函数属于 `std`，不属于 `core`；例如 `lib/pipe.do` 提供同类型串联 `pipe(value T, funcs ...(T) -> T) -> T`。
9. `lib/list.do` 提供 `len/items/at/get/put/set/update/del/clear` 等基础集合操作，以及 `map/filter/fold/reduce/find/find_index/any/all/count` 等函数式集合工具；这些函数基于 `List<T>`、lambda callback 和 `len/at/put` 实现。
10. 删除闭包捕获后，`map/filter/find/find_index/any/all/count/update` 提供显式 `env` 重载，例如 `map(xs, env, (x, env) => ...)`。
11. `lib/hash_map.do` 提供 `len/keys/values/has/get/put/set/update/del/entries` 等基础映射操作；`update/del` 只作用于既有 key，缺失时返回 `MapError`。
12. 当前 `lib/hash_map.do` 是标准库语义草案实现，可用连续 key/value 存储先锁定公开 API；真实 hash bucket、冲突处理和扩容策略后续在不改变公开函数族的前提下替换内部实现。

## 7. 诊断与测试约定

### 7.1 语法错误诊断

1. 任意位置出现语法错误时，编译器立即停止。
2. 语法错误诊断包含文件、行、列、源码行和错误位置指示。
3. 语法错误诊断只展示该位置允许的语法形式和正确示例；示例只展示可接受形态。
4. 编译器只接受本文列出的写法；其他输入触发语法错误诊断。
5. 语法错误测试保留少量 parser 诊断烟测，用于锁定“首错停止 + 位置 + 正确语法示例”的输出契约。
6. 语义、类型和语言契约错误仍可维护针对性 `err` 用例，例如类型不匹配、不可见名字、导出边界、重复声明和协议不满足。
7. 当前 typecheck 第一阶段验证导入函数别名调用的重载实参数量，并验证本文件 lambda 实参对本地函数重载的参数形状匹配；完整参数类型、跨模块 lambda 目标类型和泛型返回推导后续纳入同一阶段。

### 7.2 示例与测试提取

1. 规范示例只展示合法写法。
2. 语法或语义错误不在本文列反例；编译器在错误位置报告诊断，并展示对应的合法语法形态。
3. 错误回归放在 `tool/build/test/err` 或 `tool/build/test/compile_err`；合法示例放在 `tool/build/test/ok` 或 `tool/build/test/compile_ok`。
4. 建议统一采用如下 fenced code 块约定，便于脚本提取合法示例：

````markdown
```do ok name=path_get_single
name = get(user, .name)
```

```do ok name=path_index_expr_segment
first_name = get(users, 0, .name)
```

```do ok name=path_index_call_expr_segment
first_name = get(users, add(i, 1), .name)
```

```do ok name=put_list_append
xs List<i32> = List<i32>{}
xs = put(xs, 1, 2, 3)
```

```do ok name=list_set_vs_put
xs List<i32> = List<i32>{}
xs = put(xs, 1)
xs = put(xs, 2)
xs = set(xs, 1, 9)
xs = put(xs, 8)
```

```do ok name=list_del
xs List<i32> = List<i32>{}
xs = put(xs, 1)
xs = put(xs, 2)
xs = del(xs, 0)
```

```do ok name=list_update
xs List<i32> = List<i32>{}
xs = put(xs, 1)
xs = put(xs, 2)
xs = update(xs, 1, (x i32) -> i32 => add(x, 40))
```

```do ok name=put_map_key
m HashMap<Text, i32> = HashMap<Text, i32>{}
m = put(m, "a", 1)
```

```do ok name=hash_map_del
m HashMap<Text, i32> = HashMap<Text, i32>{}
m = put(m, "a", 1)
m = del(m, "a")
```

```do ok name=hash_map_update
m HashMap<Text, i32> = HashMap<Text, i32>{}
m = put(m, "a", 1)
m = update(m, "a", (x i32) -> i32 => add(x, 40))
```

```do ok name=put_struct_field
user = put(user, .name, "tom")
```
````

5. 新语法进入主干前，必须补对应 `tool/build/test` 用例并更新本文。
6. `loop` 支持无限循环 `loop { ... }`、集合循环 `loop v, i = xs` / `loop _, i = xs` / `loop v, _ = xs`，以及消费循环 `loop v = recv(ch)`；集合源由可见库提供 `len(source) -> usize` 与 `at(source, usize) -> V`。
7. 建议同时覆盖下列正例:

````markdown
```do ok name=call_multiline_trailing_comma
x = add(
    a,
    b,
)
```

```do ok name=private_type_decl_left_dot
.InternalUser = User | nil
```

```do ok name=open_func_get
get(a User, name Text) -> User {
    return a
}
```

```do ok name=import_relative_type
User = @user_profile.do/User
```

```do ok name=import_project_lib_value
hash = @~/hash_map.do/hash
```

```do ok name=import_std_value
now = @/time.do/now
```

```do ok name=import_std_const
_f32_pi = @/math.do/_f32_pi
```

```do ok name=host_import_abi
console_log = @env/console_log(i32, i32) -> nil
```

```do ok name=func_omit_nil_return
log(msg Text) {
    return
}
```

```do ok name=func_param_mutable
inc(x i32) -> i32 {
    x = add(x, 1)
    return x
}
```

```do ok name=param_update_does_not_escape
inc(x i32) -> i32 {
    x = add(x, 1)
    return x
}

keep(a i32) -> i32 {
    _next i32 = inc(a)
    return a
}
```

```do ok name=lambda_param_mutable
map(xs, (x i32) -> i32 {
    x = add(x, 1)
    return x
})
```

```do ok name=test_return_nil
test "early return" {
    if ok return
    return
}
```

```do ok name=test_return_explicit_nil
test "explicit nil" {
    return nil
}
```

```do ok name=overload_typed_arg_selects_candidate
foo(x i32) -> i32 {
    return x
}

foo(x i64) -> i64 {
    return x
}

a i32 = 1
b i32 = foo(a)
```

```do ok name=typed_bind_drives_call
#T = i8 | i32
double(x T) -> T {
    return x
}

a i8 = 12
b = double(a)
```

```do ok name=is_value_type_guard
v = to_i8(1234)
if is(v, Error) return
a = double(v)
```

```do ok name=is_union_type_set
if is(v, i32 | i64) return
```

```do ok name=eq_nil_guard_narrows
if eq(v, nil) return
name = get(v, .name)
```

```do ok name=and_propagates_narrowing
if and(ne(v, nil), eq(get(v, .name), "tom")) return
```

```do ok name=error_branch_value
FileError = FileNotFound | PermissionDenied | Unknown
v i32 | FileError = FileNotFound
if eq(v, FileNotFound) return
```

```do ok name=multi_return_assign
div_mod(a i32, b i32) -> i32, i32 {
    return 1, 2
}

q, r = div_mod(7, 3)
```

```do ok name=multi_return_passthrough
div_mod(a i32, b i32) -> i32, i32 {
    return 1, 2
}

wrap() -> i32, i32 {
    return div_mod(7, 3)
}
```

```do ok name=struct_explicit_value
Pair {
    a i32
    b i32
}

t Pair = .{a = 1, b = 2}
```

```do ok name=func_constraint_prefix_line
#T = i32 | i64
#add(T, ...T) -> T
sum(a T, b T) -> T {
    return add(a, b)
}
```

```do ok name=core_numeric_variadic
#T = i32 | i64
#add(T, ...T) -> T
sum_many(first T, rest ...T) -> T {
    return add(first, ...rest)
}

a i32 = add(1, 2, 3)
b i32 = mul(2, 3, 4)
c i32 = sub(10, 3, 2)
d i32 = div(24, 3, 2)
e i32 = rem(29, 5, 2)
```

```do ok name=generic_type_param_unconstrained
#T
#U
map(xs List<T>, f (T) -> U) -> List<U> {
    ys List<U> = .{}

    loop x, _ = xs {
        y U = f(x)
        ys = put(ys, y)
    }

    return ys
}
```

```do ok name=generic_type_param_inline_env
#T
#U
map_env(xs List<T>, step i32, f (T) -> U) -> List<U> {
    ys List<U> = .{}

    loop x, _ = xs {
        y U = f(x)
        ys = put(ys, y)
    }

    return ys
}
```

```do ok name=list_functional_ops
list_map = @/list.do/map
list_filter = @/list.do/filter
list_fold = @/list.do/fold

xs List<i32> = List<i32>{}
step i32 = 1
ys List<i64> = list_map(xs, (x i32) -> i64 => to_i64(add(x, 1)))
even List<i32> = list_filter(xs, (x i32) -> bool => eq(rem(x, 2), 0))
sum i32 = list_fold(xs, 0, (acc i32, x i32) -> i32 => add(acc, x))
shifted List<i32> = list_map(xs, step, (x i32, step i32) -> i32 => add(x, step))
```

```do ok name=std_pipe_same_type_chain
pipe = @/pipe.do/pipe

result i32 = pipe(
    2,
    (x i32) -> i32 => add(x, 1),
    (x i32) -> i32 => mul(x, 3),
)
```

```do ok name=generic_struct_list_storage
#T
List {
    .len usize = 0
    .items [T] = .{}
}
```

`.{}` 与 `.{v1, v2, ...}` 可在已知目标类型为 `[T]` 时构造连续存储；由目标类型提供 `T`，用户代码只通过库函数操作它。

```do ok name=generic_struct_map_storage
#K
#V
HashMap {
    .len usize = 0
    .keys [K] = .{}
    .vals [V] = .{}
}
```

`List/HashMap` 在这里只是普通库类型示例，不是保留类型名，也不享有特殊字面量 body。

```do ok name=loop_recv_value
loop v = recv(ch) {
    consume(v)
}
```

```do ok name=loop_infinite_break
loop {
    break
}
```

```do ok name=loop_each_index_value
xs List<i32> = List<i32>{}
loop v, i = xs {
    consume(i, v)
}
```

```do ok name=loop_each_discard_index
xs List<i32> = List<i32>{}
loop _, i = xs {
    consume(i)
}
```

```do ok name=loop_each_discard_value
xs List<i32> = List<i32>{}
loop v, _ = xs {
    consume(v)
}
```

```do ok name=loop_text_direct
Text = @/text.do/Text
s Text = "abc"
loop v, i = s {
    consume(i, v)
}
```

```do ok name=inferred_struct_ctor
Point {
    x i32
    y i32
}

p Point = .{x = 1, y = 2}
```

```do ok name=typed_struct_ctor
Config {
    a i32
    b i32
}

config = Config{a = 1, b = 2}
```

```do ok name=union_from_typed_ctor
x User | nil = User{name = "tom"}
```

```do ok name=struct_field_equals
Handle {
    fd i32
}

handle = Handle{fd = 0}
```

```do ok name=generic_struct_field_ctor
#T
Box {
    value T
}

x = Box<i32>{value = 1}
```

```do ok name=return_multiline_generic_ctor
#T
Box {
    value T
}

#T
make(value T) -> Box<T> {
    return Box<T>{
        value = value,
    }
}
```

```do ok name=struct_field_ctor_inferred_type
Counter {
    len usize
}

count Counter = .{len = 0}
```

```do ok name=field_default_runtime
now = @env/now() -> i64

User {
    created_at i64 = now()
}

make_user() -> User {
    return User{}
}
```

```do ok name=if_guard_return
if ok return
```

```do ok name=else_if_chain
if a {
    return 1
} else if b {
    return 2
} else {
    return 3
}
```

```do ok name=loop_label_break
#outer
loop {
    loop {
        break #outer
    }
}
```

```do ok name=line_string_single
str Text = \\abc
```

```do ok name=line_string_multi
str Text =
    \\abc
    \\def
```

```do ok name=line_string_explicit_blank_line
str Text =
    \\abc
    \\
    \\def
```

```do ok name=line_string_no_escape
str Text = \\a\nb
```

```do ok name=lambda_callback_site
result = map(xs, (x i32) -> i32 => add(x, 1))
```

```do ok name=lambda_explicit_env
step i32 = 1
result = map(xs, step, (x i32, step i32) => add(x, step))
```

```do ok name=func_name_value_target_select
inc(x i32) -> i32 { return add(x, 1) }
inc(x i64) -> i64 { return add(x, 1) }
apply(f (i32) -> i32) -> i32 { return f(1) }
v = apply(inc)
```

```do ok name=import_func_name_value_target_select
inc = @fixture/import_overload_func.do/inc
apply(f (i32) -> i32) -> i32 { return f(1) }
v = apply(inc)
```

```do err name=func_name_value_no_target
inc(x i32) -> i32 { return add(x, 1) }
inc(x i64) -> i64 { return add(x, 1) }
f = inc
```

```do ok name=generic_variadic_sum
#T
#add(T, ...T) -> T
add_many(first T, rest ...T) -> T {
    out T = first
    loop x, _ = rest {
        out = add(out, x)
    }
    return out
}
```

```do ok name=variadic_spread_call
print_all(prefix Text, rest ...Text) {
    print(prefix, ...rest)
}
```

```do ok name=top_const_read
_step i32 = 1

inc(x i32) -> i32 {
    return add(x, _step)
}
```
````

## 8. 非目标

1. 本版只预留标准库时间接口（如 `ms/sec/day`）的语法位。
