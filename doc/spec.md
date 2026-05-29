# do 语言规范 (spec v1)

## 0. 状态

1. 本文是 `do` 的单文件规范。
2. 第 3 章 `PEG` 是 parser 可执行文法。
3. 第 6 章是静态约束，供 sema/test 执行。
4. 本文是 do 的单文件规范。

## 1. 分层边界

1. `PEG` 只定义可解析结构，不承载类型推导或收窄推理。
2. 静态约束只定义可通过规则，不重复书写 parser 结构。
3. 能在 `PEG` 层无符号表地判定的语法边界必须放进 `PEG`；`PEG` 应尽量强硬，静态约束只承载需要类型、作用域、可见性或数据流信息的判断。
4. 运行层按 `builtin -> core -> std` 分层；依赖只能向下。
5. `builtin` 是编译器/Wasm/host 桥接层，提供 special form 与底层 primitive；`core` 和 `std` 通过它使用这些能力。
6. `core` 是默认可见核心库，封装 `builtin` 并提供语言最小可用函数值、数值函数、结构字段操作与连续存储 primitive。
7. `std` 是可导入标准库，基于 `core` 提供扩展能力。
8. `is/and/or/not` 属于 `builtin` special form。
9. `eq/ne/lt/le/gt/ge` 由 `core` 预定义并固定提供。
10. 数值与位运算基础函数（如 `add/sub/mul/div/rem`）属于 `core`，由 `builtin` primitive 支撑；`add/sub/mul/div/rem` 接收同类型 2 个及以上参数。
11. `[T]` 是 `core` 连续存储 primitive，表示任意多个连续的 `T` 值；它不是集合类型，也不携带长度信息，没有内建默认 `to_text`；标准库或用户库可用它实现 `List/HashMap` 等普通泛型结构体或类型别名，并为这些集合类型自行提供 `to_text` 重载。
12. `Text` 不是 `core` 预导入类型；标准库里它按 `Text = [u8]` 的别名形态提供，底层就是字节序列，但值语义要求内容为有效 UTF-8；`Text` 的 `len/at` 按 UTF-8 字节计数和索引，直接集合循环 `loop v, i = text` 中 `v` 是 `u8` 字节。普通字符串本身就是字节序列，可用 `\xNN` 表达任意字节；若上下文要求 `Text`，则需通过 UTF-8 校验。`std` 提供 `to_text(Text) -> Text`，输出按字符串规则带双引号并转义。
13. 时间换算函数（如 `ms/sec/day`）属于 `std` 时间库。
14. `Error` 由编译器合成，聚合当前可达模块中所有对外可见的 `*Error` 联合类型，以及内建运行时错误分支。
15. `to_*` 是统一转换函数族，不属于内建函数名，不进入 `ReservedDeclName`；数值类型之间的 `to_*` 转换属于 `core`，`Text` 参与的 `to_*` 解析重载属于 `std`，用户库也可定义具体 `to_*` 重载。
16. 可证明总成功的 `to_*` 转换返回目标类型，可能失败的窄化转换返回 `T | Error`；例如 `to_i8(Text) -> i8 | Error`。
17. `to_text` 是普通 `to_*` 名，`std` 提供基础值、`Struct`、`Union` 以及编译器暴露的函数引用（若该值形态存在）的通用可视化重载；用户库可为自定义类型提供 `to_text(T) -> Text` 重载。
18. `core` 的数值转换可由编译器按静态签名 lower 到内部实现，但这只是实现策略，不把具体 `to_*` 名字提升为内建保留名；`std` 的 `to_*` / `to_text` 以普通标准库函数提供，并可由 `core` 组合实现。
19. `to_text` 的输出格式必须稳定；`std` 重载保证相同输入在相同版本内输出一致，用户库自定义重载的稳定性由定义该重载的库承担。
20. 字符串输出使用带双引号的源码字符串形态，并按字节转义必要内容；`"`、`\`、换行、回车、tab 和不可打印字节可用 `\xNN` 形式表示。
21. `nil/bool/number` 输出使用源码 token 风格，例如 `nil`、`true`、`false`、`123`、`3.14`；不做本地化、人类化或分组格式。浮点数使用最短 round-trip 十进制表示，不保留源码原始写法；非有限浮点值固定展示为 `nan`、`inf`、`-inf`，它们只属于 `to_text` 文本输出。
22. `Struct` 采用字段构造风格，只按结构体声明顺序展示 public 字段；没有 public 字段时展示 `Type{}`。`Union` 统一按 `Type:Branch` 展示，`Error` 统一按 `Error:Branch` 展示；该格式只是文本输出，不是源码构造语法。
23. 函数引用若参与展示，输出名称加签名以区分重载，例如 `inc(i32) -> i32`、`map([T], (T) -> U) -> [U]`；多返回按 `-> A, B` 展示，空返回按 `-> nil` 展示。
24. 本版只预留 `do` 语法位；并发语义作为后续版本或标准库能力扩展。
25. 网络库属于 `std`；本版只定义地址、TCP listener/stream、UDP socket 等值形态。真实 `listen/connect/accept/read/write/send/recv/close` 等 host ABI 能承载 buffer 和资源句柄后再由标准库封装。
26. `src/_.do` 是 builtin/core 声明总表，编译器隐式加载，不作为 local import 目标，也不需要在普通源码中引用；它只记录默认可见的内建/核心签名，不承载 `std` 实现。

## 2. 词法与命名

### 2.1 标识符与字面量

```peg
LowerIdent     <- [a-z][a-z0-9]* ('_' [a-z0-9]+)*
UpperIdent     <- [A-Z][A-Za-z0-9]*
ErrorTypeName  <- [A-Z][A-Za-z0-9]* 'Error'
ReadonlyIdent  <- '_' (LowerIdent / UpperIdent)
Ident          <- LowerIdent / UpperIdent / ReadonlyIdent
PathSeg        <- [a-z] ([a-z0-9]* ('_' [a-z0-9]+)*)?

IntLit         <- [0-9]+
FloatLit       <- [0-9]+ '.' [0-9]+
StringToken    <- NormalString / LineStringLine
NormalString   <- '"' StringChar* '"'
StringChar     <- NormalChar / EscapeSeq
NormalChar     <- ? any character except '"', '\', LF, CR ?
EscapeSeq      <- '\\' ('"' / '\\' / 'n' / 'r' / 't' / 'x' HexDigit HexDigit)
HexDigit       <- [0-9A-Fa-f]
LineStringLine <- '\\\\' LineStringChar*
LineStringChar <- ? any character except LF, CR ?
```

本节定义词法 token 形态与命名约束；第 3 章在这些 token 之上定义 parser 可执行主文法。

规则:

1. 丢弃位只写 `_`；普通标识符使用 `LowerIdent`、`UpperIdent` 或 `ReadonlyIdent`。
2. 只读标识符写作前置 `_` 加标识符主体，主体可为 `LowerIdent` 或 `UpperIdent`，例如 `_name`、`_Name`、`_GameName`。
3. `UpperIdent` 用于类型名、类型参数名和错误分支值，命名风格采用 UpperCamel；缩写按普通词处理，例如 `HttpServer`、`UserId`。
4. 顶层私有声明使用前置 `.`，例如 `.internal_name`。
5. 字段路径段使用前置 `.`, 例如 `.name`。
6. 循环标签使用前置 `#`, 例如 `#outer`。
7. 普通字符串写成单行 `"..."`。
8. 普通字符串支持 `\"`, `\\`, `\n`, `\r`, `\t`, `\xNN`；按字节解释，不要求结果是有效 UTF-8。
9. 普通字符串在 `[u8]` 目标上下文中产生对应字节序列；在 `Text` 或库定义文本类型上下文中需通过 UTF-8 校验。
10. 行字符串使用 Zig 风格 `\\text`，内容从 `\\` 后开始到行尾结束。
11. 连续行字符串可组成多行字符串值，各行之间用 `\n` 连接；源码缩进不进入字符串值。
12. 行字符串按字节保留，不解释转义。
13. 行字符串用于表达式根位；可出现在 `=` 右侧、`return` 右侧、字段默认值右侧等明确等待表达式的位置。
14. 行字符串作为调用参数或聚合元素时，必须独占参数行或元素行，不与同一行其他 token 混排。
15. 字符串值中的空行必须显式写成空内容行字符串 `\\`；源码空行会打断 `LineStringBlock`。
16. raw 文本使用行字符串 `\\text`。
17. 块注释写作单层 `/* ... */`。
18. lexer 在 token 化前将 `CRLF` 与 `CR` 归一化为 `LF`；parser 只接收统一的 `NL` token。
19. parser 输入是 token 流；空格与制表符在词法阶段剔除，换行保留为 `NL` token。
20. 顶层声明与块内语句使用换行分隔；一行一个声明或语句。
21. 关键字按整 token 匹配，不做前缀匹配；例如 `dof` 是一个 `Ident`，不是 `do` + `f`。
22. `Text/List/HashMap` 等库类型由 `std` 或用户库定义，并按普通 `RefTypeName` 解析；其中 `Text` 的标准形态是 `[u8]` 别名。
23. `LambdaExpr` 只出现在调用实参位，作为回调表达式；语法形如 `(x i32) => add(x, 1)`、`(x i32) -> i32 => add(x, 1)` 或 `(x i32) -> i32 { ... }`。
24. `LambdaExpr` 只读自身参数、体内绑定、顶层常量和当前可见函数，不形成闭包，不能捕获外层局部绑定，也不能绑定到变量或作为值返回。
25. 顶层函数的 `=>` 函数体是函数声明短写，不是 `LambdaExpr`，不产生可传递函数值。
26. 函数名可在已有目标 `FuncType` 的值位作为函数值传递，例如高阶函数实参、字段初始化或返回位。
27. lambda 参数类型可省略；省略时必须由已选调用候选的目标 `FuncType` 提供参数类型，不能由 lambda body 反推。
28. lambda 返回类型可省略；省略时在调用候选已选定、参数类型已确定后，由 lambda body 推出返回类型。
29. 块体 lambda 内的 `return` 只返回当前 lambda，不返回外层函数或测试体。
30. 算术、比较和逻辑组合使用函数或 `builtin` 判断族表达。
31. import 路径段使用 `PathSeg`；路径段由小写字母开头，可含数字，单词之间用单个 `_` 分隔。

### 2.2 保留词与保留标识符

```
if else loop break continue return defer do
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

### 2.3 Token 契约

1. 语法文法以 token 流为输入；本文出现的 `NL`、`->`、`=>`、`...` 都是词法层明确输出的 token 形态。
2. 前置点私有名（如 `.internal_user`、`.InternalUser`）与字段段（如 `.name`）属于点前缀标识符族；文法按语义位区分它们，而不是靠字符串切分推断。
3. `.{` 保持为 `.` 与 `{` 两个 token，避免与字段段混淆。
4. 文法中的 `PathSeg`、`ModulePath` 与 import 路径规则属于 import 位专用解析，不参与普通表达式 token 解释。

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

ValueDecl        <- ConstName TypeAnn? '=' RhsExpr
ConstName        <- ReadonlyIdent
TypeAnn          <- TypeExpr
RhsExpr          <- SoftGap Expr

ImportDecl       <- HostImportDecl / LocalImportDecl
HostImportDecl   <- LowerIdent '=' HostImport
LocalImportDecl  <- TypeImportDecl / ValueImportDecl
TypeImportDecl   <- UpperIdent '=' TypeImport
ValueImportDecl  <- LowerIdent '=' ValueImport
TypeImport       <- '@' ModuleFile '/' UpperIdent
ValueImport      <- '@' ModuleFile '/' ValueImportTarget
ValueImportTarget <- LowerIdent / ReadonlyIdent
HostImport       <- '@' HostPath HostSig
ModuleFile       <- ProjectSrcFile / StdFile / RelativeFile
ProjectSrcFile   <- '~/' ModulePath '.do'
StdFile          <- '/' ModulePath '.do'
RelativeFile     <- ModulePath '.do'
ModulePath       <- PathSeg ('/' PathSeg)*
HostPath         <- PathSeg ('/' PathSeg)*
HostSig          <- '(' SoftGap AbiParamList? SoftGap ')' SoftGap '->' SoftGap AbiReturn
AbiParamList     <- AbiType (CommaSep AbiType)* TrailComma?
AbiReturn        <- 'nil' / AbiType
AbiType          <- 'i32' / 'i64' / 'f32' / 'f64'

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
FieldDefault     <- '=' RhsExpr
FieldName        <- PublicFieldName / PrivateFieldName
PublicFieldName  <- LowerIdent
PrivateFieldName <- '.' LowerIdent

RefTypeName      <- !'Error' PublicTypeName

TypeExpr         <- UnionExpr
UnionExpr        <- TypeAtom ('|' TypeAtom)*
TypeAtom         <- BaseType
                  / StorageType
                  / FuncType
                  / RefTypeName TypeArgs?
                  / '(' SoftGap TypeExpr SoftGap ')'
                  / NilType
                  / SynthErrorType
FuncType         <- '(' SoftGap TypeExprList? SoftGap ')' SoftGap '->' SoftGap ReturnSpec
TypeArgs         <- '<' SoftGap TypeExpr (CommaSep TypeExpr)* TrailComma? SoftGap '>'
StorageType      <- '[' SoftGap TypeExpr SoftGap ']'
BaseType         <- 'i8' / 'i16' / 'i32' / 'i64'
                  / 'u8' / 'u16' / 'u32' / 'u64'
                  / 'isize' / 'usize'
                  / 'f32' / 'f64'
                  / 'bool'
NilType          <- 'nil'
SynthErrorType   <- 'Error'
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

AssignStmt       <- TypedBind '=' RhsExpr
                  / LValueList '=' RhsExpr
TypedBind        <- BindName TypeExpr
LValueList       <- LValue (CommaSep LValue)*
LValue           <- BindName / '_'
BindName         <- LowerIdent / ReadonlyIdent

ReturnStmt       <- 'return' ReturnTail?
ReturnTail       <- SoftGap Expr (CommaSep Expr)* TrailComma?
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
LoopLabel        <- '#' LowerIdent
BreakStmt        <- 'break' LoopLabel?
ContinueStmt     <- 'continue' LoopLabel?

Expr             <- DoExpr
                  / PredExpr
                  / CoreAccessExpr
                  / CallExpr
                  / InferredAggLit
                  / TypedAggLit
                  / ParenExpr
                  / ErrorBranchValueExpr
                  / ExprIdent
                  / Literal

ErrorBranchValueExpr <- UpperIdent
ExprIdent        <- LowerIdent / ReadonlyIdent
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
SetExpr          <- 'set' '(' SoftGap Expr CommaSep PathArgList CommaSep Expr SoftGap ')'

PathArgList      <- PathArg (CommaSep PathArg)* TrailComma?
PathArg          <- FieldSeg / IndexSeg
IndexSeg         <- Expr
FieldSeg         <- '.' LowerIdent

CallExpr         <- Callee '(' SoftGap ArgList? SoftGap ')'
Callee           <- LowerIdent
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

ReservedDeclName <- 'is' / 'and' / 'or' / 'not'
                  / 'eq' / 'ne' / 'lt' / 'le' / 'gt' / 'ge'
                  / 'add' / 'sub' / 'mul' / 'div' / 'rem'
                  / 'get' / 'set' / 'len' / 'at'
NL               <- '\n'
```

`ReservedDeclName` 包含所有内建函数名。它们不可重载、不可遮蔽，不能用于普通函数声明名、导入别名或局部绑定名；其中只有 `get/set` 的 `CoreAccessExpr` 路径调用形态由 PEG 固定边界。`put/update/del` 与具体 `to_*` 名字不属于内建函数名，不进入 `ReservedDeclName`。

`src/_.do` 只放默认可见的 builtin/core 声明表。`std` 类型与库函数继续放在各自模块里，不写入这张表。

## 4. 判断族

### 4.1 Native 成员

`is`, `and`, `or`, `not`

### 4.2 Core 成员

`eq`, `ne`, `lt`, `le`, `gt`, `ge`

### 4.3 规则

1. `builtin` 判断族按 special form 规则解析。
2. `core` 预定义判断函数族固定提供。
3. 判断族返回 `bool`。
4. `and/or/not` 采用短路求值，并参与控制流收窄；`and/or` 按左到右传播收窄，`not` 反转收窄信息。
5. `is(value, TypeSet)` 做类型集合判断；`TypeSet` 可为类型表达式或联合类型表达式，真分支触发类型收窄。
6. `is` 的第二参数是类型表达式或联合类型表达式；`nil`、字符串、数字、`FileNotFound` 这类值判断使用 `eq/ne`，`is(value, nil)` 视为非法写法。
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

1. `get/set` 是内建函数名，不可重载也不可遮蔽；它们只在 `CoreAccessExpr` 的路径调用形态中出现。
2. `get/set` 的路径调用形态使用 `CoreAccessExpr`，例如 `get(x, .name)`、`set(x, .name, value)`；该形态按开放结构操作协议分派。
3. `put/update/del` 是普通开放函数族，由 `core`、`std` 或用户库按普通函数定义具体重载。
4. `len/at` 是集合循环内建协议函数，不可重载也不可遮蔽；`loop` 只要求其签名满足 `len(S) -> usize` 与 `at(S, usize) -> V`。
5. 底层原语只有两类：结构字段 `get(T, .name)` / `set(T, .name, v)`，以及连续存储索引 `get([T], usize)` / `set([T], usize, v)`；`std` 或用户库可在此基础上组合更高层操作。
6. 多段结构路径使用扁平参数形态；字段/索引路径统一从 `get/set` 进入，集合设计由库层承载。
7. 结构字段读写统一只走 `get/set` 路径形态，例如 `get(x, .name)`、`set(x, .name, value)`。
8. `put` 可用于集合追加、插入、键写入或其他库自定义更新语义；例如 `List` 可把 `put(xs, value, rest ...T)` 作为批量追加重载。
9. `del` 可用于列表索引删除、映射 key 删除或其他库自定义删除语义。
10. `update` 作为普通库函数定义；需要时可由 `std` 基于 `get/set` 提供。

### 5.2 路径形态

1. 单段字段路径写作 `FieldSeg`，例如 `.name`。
2. 多段路径写作扁平实参，例如 `get(users, 0, .name)` 或 `set(users, add(i, 1), .name, value)`。
3. `get` 使用 `PathArgList`，全部尾部参数都是路径段。
4. `set` 使用 `set(target, path..., value)` 形态：最后一项是待写入值，之前的所有项都是路径段。
5. `set(target, path..., value)` 至少包含一个路径段和一个待写入值；文法中路径段与最终值显式分位。
6. 路径段单段为 `PathArg`，分为字段段与索引段：字段段是前置点加单个 `LowerIdent`；索引段是 `Expr`。
7. 路径段是 `get/set` 的原语级语法，不暴露为 `core` 或 `std` 的值类型。
8. `FieldSeg` 不作为普通参数类型暴露；`get(user, "name")` 只是索引段表达式，只有内建协议支持该目标类型时合法，不触发用户重载。
9. 字段段只用于结构体字段访问；索引段只用于 `[T]` 连续存储或库类型定义的索引访问。
10. 复杂表达式段在路径求值时直接计算；字段段按 `.lower_ident` 展示，索引段按其可读表达展示。

### 5.3 调用示例

```do
name Text = get(user, .name)
state = set(state, .user, .name, "tom")
item = get(user, .abc, add(i, 1), .name)
```

`get/set` 是内建函数名，不提供用户声明示例；声明同名普通函数是保留名错误。

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
11. `List/HashMap` 作为普通库类型存在；`put/update/del/clear` 等扩展操作由 `std` 或用户库以普通函数提供，`get/set/len/at` 若适用则走内建协议入口。
12. `HashMap` 作为循环源时使用库显式提供的 `keys(m)`、`values(m)` 或 `entries(m)` 这类返回可循环集合的函数。

## 6. 静态约束

### 6.1 命名、导入与可见性

1. 类型声明名使用 `UpperIdent`，风格为 UpperCamel；普通函数名使用 `LowerIdent`；私有普通函数声明名使用 `.lower_name`；字段名使用 `LowerIdent`。
2. 私有类型名出现在类型声明左侧（`DeclTypeName`）；类型引用位统一去点。
3. 私有声明在声明位使用前置 `.`；访问时统一去点（字段路径段除外）。
4. 调用表达式的 callee 只接受 `LowerIdent`；函数声明名和函数 import alias 也使用 `LowerIdent`，私有函数调用时去掉声明位的前置 `.`。
5. core 保留判断函数名由语言预定义；内建函数名不得用于顶层声明、导入别名或局部遮蔽。
6. `get/set` 的路径形态按“字段原语 + 索引原语”分派，不进行普通重载候选收集。
7. 顶层名字共享同一名字空间；仅同名函数族允许重名。
8. `put/update/del` 与具体 `to_*` 名字仍是普通库函数名，`std` 与用户库可按普通函数族规则定义重载；同名同签名重复声明非法，未来 `std` 新增同名签名时按普通导入/重载冲突处理。
9. 公开签名使用 public 类型。
10. 保留词与保留类型名 `Error` 只用于语言保留位置。
11. 只有 `StructDecl` 支持前置 `#T` / `#T = TypeSet` 声明泛型类型参数；`AliasDecl` 与 `ErrorDecl` 当前不支持泛型声明；`TypeArgs` 按声明顺序绑定类型参数。
12. import 出现在顶层。
13. import 左侧由 PEG 按导入类别直接约束：`TypeImportDecl` 左侧使用 `UpperIdent`；`ValueImportDecl` 与 `HostImportDecl` 左侧使用 `LowerIdent`。
14. import alias 是当前文件内名字；其他文件从原模块导入所需声明。
15. imported public type 可以出现在当前文件的 public API 中，但其 canonical source 仍指向来源文件。
16. imported declaration 只在当前文件内使用；对外暴露时通过本文件定义的新类型或新函数封装。
17. local import 的 alias/target 结构匹配由 PEG 直接约束：`UpperIdent = @.../UpperIdent` 或 `LowerIdent = @.../(LowerIdent|ReadonlyIdent)`；其中 `UpperIdent = @.../UpperIdent` 的最终符号类别由语义阶段按导出符号表判定（public 类型或 public `*Error` 分支值）。对 `UpperIdent` 目标不提供 `LowerIdent` 别名导入形态。
18. local import 的目标符号允许 `ReadonlyIdent`，用于导入来源模块公开常量（例如 `_f32_pi`）；但本地 alias 仍使用 `LowerIdent`。
19. local import 目标是来源 `.do` 文件的 public 顶层声明。
20. local import 只支持三种入口：`@path/file.do/name` 为当前文件目录向下查找，`@~/path/file.do/name` 为当前项目 `/src` 目录向下查找，`@/path/file.do/name` 为标准库根目录向下查找。
21. import 路径段统一使用 `PathSeg`。
22. local import 使用显式 symbol import：`name = @path/file.do/symbol`；目标模块会递归加载其自身依赖。
23. 模块依赖图是无环图；local import 会递归解析目标模块，缺失目标符号或任意层级的 import cycle 都是错误。
24. host import 使用 `@env/console_log(...) -> nil` 这类形式，并由编译器桥接到宿主实现；`@` 后的路径是宿主命名空间或模块路径。
25. host import 路径段同样遵循 `PathSeg`，仅允许小写开头与下划线分词。
26. host import 签名是 ABI 签名；参数使用 `i32/i64/f32/f64`，返回使用 `nil` 或单个 `i32/i64/f32/f64`。
27. 函数族唯一性由函数名与参数类型序列决定；同一函数名配合同一参数类型序列对应唯一定义。
28. 不定参数参与函数族唯一性；`rest ...T` 的签名尾部记作 `...T`，不同于单个 `T`。
29. 公开内建常量采用前置 `_` 和类型前缀命名：`_i8_max`、`_i8_min`、`_f32_pi`、`_f64_pi`；不采用 `max_i8`、`pi_f32` 或无 `_` 的常量名。

### 6.2 定型与字面量

1. 字面量无默认类型，由上下文唯一定型或显式类型标注。
2. `nil` 同时承担值位与签名位语义，但在语法上仍是同一个 token：
   - 值位 `nil`：空值分支，可作为表达式值参与赋值、参数与返回。
   - 联合类型位 `T | nil`：声明可空值分支。
   - 返回签名位 `-> nil`：声明无返回值上下文。
   - `()-> T | nil` 返回空分支时必须写 `return nil`；`()-> nil` 可写 `return` 或 `return nil`。
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
18. 普通字符串和行字符串都生成字节序列；普通字符串支持 `\xNN` 等转义，行字符串按字节保留且不解释转义。普通字符串和行字符串可在目标类型为 `[u8]` 或库定义文本类型时由上下文定型；若目标是 `Text` 或库定义文本类型，内容必须通过 UTF-8 校验。行字符串参与调用参数或聚合元素时必须独占参数行或元素行。
19. 裸 `{...}` 不是表达式；聚合值写成 `.{...}` 或 `Type{...}`。
20. `.{...}` 省略目标聚合类型，由左侧标注、既有绑定、参数或返回上下文唯一确定。
21. `Type{...}` 在右侧显式给出聚合类型，可用于创建新绑定。
22. `name Type = .{...}` 与 `name = Type{...}` 是等价的创建形式。
23. `Type{...}` 的 `Type` 是具名类型及其类型参数。
24. 联合返回位要求右侧表达式自身先定型到唯一分支。
25. 结构体字段声明位的 `.field` 表示私有；字段真实名字仍是 `field`，同一结构体内同一字段写作 `field` 或 `.field`。
26. 当前模块内构造结构体时，字段初始化使用裸字段名 `field = value`；即使字段声明为 private，构造项也不写 `.field = value`；`.field` 只出现在路径位或声明位。
27. 外部模块构造 public struct 时填写 public 字段；private 字段由默认值提供。
28. `TypedAggLit` 的 body 只接受字段项；`InferredAggLit` 可接受字段项或元素项，元素项仅在目标上下文为 `[T]` 时成立。
29. 同一个聚合字面量 body 内字段项和元素项不得混用；`.{a = 1, 2}` 非法。
30. 结构体字段构造使用 `field = value`。
31. 字段默认值在结构体构造时求值；默认表达式结果类型与字段类型一致。
32. 结构体构造发生在 CTFE 上下文时，字段默认值也走 CTFE；运行时构造可执行运行时默认表达式。
33. `Tuple` 按普通泛型结构体字段构造解释；库若定义 `Tuple`，同样采用字段构造。
34. `ErrorDecl` 声明错误分支集合，名称使用 `ErrorTypeName`，右侧分支使用裸 `UpperIdent` 值名，例如 `FileError = FileNotFound | PermissionDenied`。
35. 普通 union 由类型表达式组成；错误分支集合只通过 `ErrorDecl` 声明。
36. `*Error` 类型名用于类型位；值位使用具体分支值，且源码只写裸 `UpperIdent`，不支持 `Type.Branch`、`Error.Branch` 或其他 `xxx.xxx` 限定名写法（字段路径段除外）。
37. `*Error` 分支值是可导入的 public 值；跨文件构造或精确比较分支值时导入该分支值。
38. `*Error` 分支值导入时可以改名以避免冲突，本地别名使用 `UpperIdent`。

### 6.3 绑定与赋值

1. 赋值左侧先查最近可见绑定；命中则更新，未命中则创建。
2. 未命中时创建新绑定，右侧表达式已经能唯一确定类型；新绑定创建使用已定型右侧表达式，`.{...}` 在存在目标类型上下文时使用。
3. 命中已有绑定时，既有绑定类型为右侧表达式提供目标上下文，例如 `y = 3` 中 `3` 由 `y` 的类型定型。
4. 绑定与赋值规则只适用于块内局部绑定；顶层 `ValueDecl` 只作为常量声明。
5. 局部绑定名使用 `LowerIdent` 或 `ReadonlyIdent`，且不得与内建函数名冲突；`ReadonlyIdent` 不用于函数名；`UpperIdent` 用于类型名、类型参数名、错误分支值和同类 import alias。
6. `UpperIdent` 在值位只允许作为已声明或已导入的 `*Error` 分支值；普通类型名不得作为值表达式。
7. `TypedBind` 永远声明新绑定；如果同名绑定已可见，编译器报告重复声明或遮蔽错误。
8. 局部声明绑定（如 `TypedBind`）不得遮蔽外层可见绑定；函数参数、lambda 参数和 loop 绑定位允许与外层同名，并按最近作用域解析。
9. 局部 `_name` 是运行期只读绑定；首次绑定满足普通定型规则。
10. `_name` 首次绑定后保持只读。
11. `_name = expr` 形式在 `_name` 未命中可见绑定时创建只读绑定；若已命中既有 `_name`，则按只读重赋值报错。
12. 只读绑定的“首次绑定或重赋值”由语义阶段根据当前作用域符号表判定，不由 PEG 拆分。
13. `_` 为丢弃位。
14. 局部绑定采用块作用域；`if`、`loop`、lambda 体内创建的绑定只在该块内可见。
15. 函数参数、lambda 参数和 `loop` 绑定是普通可变本地绑定；参数赋值只改变当前调用帧。
16. 参数位使用 `_` 表示丢弃参数；该参数仍计入函数签名的参数个数和类型序列。
17. 参数位与 loop 绑定位使用 `LowerIdent` 或 `_`；`_name` 用于顶层常量和局部只读绑定。
18. 不定参数声明写作 `rest ...T`，只能出现在函数参数列表最后，且一个函数最多一个不定参数。
19. 不定参数在函数体内的绑定类型是 `[T]`，可用于 `loop` 或在调用尾部写作 `...rest` 转发。
20. lambda 参数不支持不定参数；host import 参数不支持不定参数。
21. 函数名在值位解析为函数值时，必须由上下文提供目标 `FuncType`；候选集合同时包含当前文件可见函数和已导入函数族，并按函数名加参数类型序列选择唯一声明。
22. lambda 参数省略类型时，必须先由函数名、实参数量、非 lambda 实参、lambda 显式签名或唯一候选确定目标 `FuncType`；lambda body 只用于检查返回值，不参与参数类型反推。
23. lambda 返回类型省略时，可由 body 推出返回类型或绑定目标函数类型中的返回类型参数；该结果不参与重载候选选择。
24. 块体 lambda 拥有独立返回边界；其 `return` 只结束当前 lambda 调用。
25. 函数名值位若缺少目标 `FuncType`（例如 `f = inc`）且该名字对应多个重载候选，报告 `NoMatchingCall`。
26. 函数名值位若目标 `FuncType` 不唯一（例如 `use(inc)` 且 `use` 自身重载且都可接收函数参数），报告 `NoMatchingCall`。

### 6.4 返回与多返回

1. `return` 位数与类型匹配函数返回签名。
2. 多返回结果出现在多左值赋值右侧，或完整返回位。
3. 多返回出现在多左值赋值右侧或完整返回位；在单个实参、聚合元素和单变量赋值右侧先显式拆分。
4. 多返回签名按顶层逗号分隔；每个返回项各自是完整 `TypeExpr`，返回项内部可以包含联合类型。
5. 表达式体函数与块体函数都遵循同一返回匹配规则。
6. `nil` 返回上下文允许 `return` 与 `return nil` 等价。
7. `-> T | nil` 的函数在返回 `nil` 分支时必须显式写 `return nil`；裸 `return` 只适用于 `-> nil` 返回上下文。
8. 本地普通函数可省略返回类型；省略时等价并规范化为 `-> nil`。
9. host import、接口约束和其他显式签名位置都要求显式返回类型。
10. 省略返回类型的表达式体函数仍按 `-> nil` 检查，右侧若产生非 `nil` 值则报错。

### 6.5 控制流

1. `if` 的条件位是单值 `bool`。
2. `defer` 体使用普通表达式或块内副作用语句。
3. `break/continue` 标签引用当前可见循环标签。
4. `loop` 支持三种形态：
   - 无限循环：`loop { ... }`。
   - 集合循环：`loop v, i = source { ... }`；`v` 是值，`i` 是 `usize` 位置，二者都可写 `_` 丢弃。
   - 消费循环：`loop v = recv(ch) { ... }`；右侧使用 `recv(...)`，`recv(ch)` 定型为 `T | nil | Error`。
   集合循环使用 `=` 连接绑定与源。
5. 集合循环源类型 `S` 解析为内建 `len(S) -> usize` 与 `at(S, usize) -> V` 协议函数，循环按 `0..len(source)` 的索引顺序读取值；`range(...)` 这类标准库函数只要返回满足该协议的值，就可以直接用于集合循环。
6. 集合循环的右侧表达式在进入循环前求值一次，后续循环使用该源值。
7. 集合循环中的 `v` 在协议成立前提下是 `V`，不是 `V | nil` 或 `V | Error`。
8. 消费循环用于流、通道等无长度来源；`nil` 表示正常结束，`Error` 表示失败，`T` 排除 `nil` 类型。
9. `len/at` 是内建协议函数名，不是普通函数族；标准库或用户库若要支持集合循环，只能提供满足协议的实现。
10. 若 `len(S)` 不返回 `usize`，或 `at(S, usize)` 不返回单值 `V`，类型 `S` 不满足集合循环协议。
11. `Text` 与其他实现了 `len/at` 协议的库类型可以直接作为集合循环源；映射遍历由库提供可迭代视图。
12. 单行 `if` 是 guard 语法，接 `return`、`break` 或 `continue`。
13. `else if` 跟在块体 `if` 后；guard `if` 不接 `else`。
14. 循环标签使用独立前置行 `#name`，标注紧随其后的 `loop`。

### 6.6 路径约束

1. `get/set` 的路径形态不参与普通重载；字段段/索引段只是内建路径调用参数形态，最终按 core 原语或内建协议分派。
2. `get/set` 的路径在类型上逐段解释：
   - 结构体接收字段段。
   - `[T]` 连续存储的索引由 core 函数处理，不通过结构路径暴露。
3. 私有字段路径段在声明该结构体的模块内使用。
4. 字段段写作 `.lower_ident`。
5. 索引段允许 `Expr`，但只有目标类型声明了对应结构操作时才合法；普通 struct 字段段使用 `.lower_ident`。

### 6.7 编译期约束

1. 顶层 `ValueDecl` 使用 `ReadonlyIdent`，表示全局常量。
2. 顶层常量初始化在编译期求值出结果，可引用其他顶层常量并调用普通函数；整条求值路径可 CTFE，依赖图无环。
3. 顶层常量 CTFE 求值路径由可 CTFE 的本地表达式与普通函数组成；递归与循环受编译期求值预算限制。
4. host import 属于运行时边界；build 时宿主与运行时宿主可以不同。
5. 普通函数、`.test_*` 测试函数和 lambda 可读取顶层常量，可调用当前可见函数。
6. `ReadonlyIdent` 顶层常量可出现在值表达式位，但不可被重新赋值。
7. 编译入口写作 `start()`，无参数且无返回；wasm 导出名 `_start` 是编译器生成细节。
8. 字段默认值按构造上下文求值；顶层常量构造要求字段默认值可 CTFE，运行时构造允许运行时默认值。
9. `#T` 是无约束类型参数；`#T = TypeSet` 是受限类型参数；`#name(...) -> Return` 是函数声明前的接口函数签名约束。
10. 类型约束绑定紧随其后的一个函数或结构体；接口函数约束绑定函数。
11. 约束独立成行，连续贴合其绑定的声明头。
12. 函数约束列表先写所有类型约束，再写接口函数约束。
13. 类型参数名使用 `UpperIdent`，接口函数名使用 `LowerIdent`。
14. 类型参数名使用当前可见类型名、`core` 预导入类型名和保留类型名之外的新名字。
15. 每个类型参数至少出现在一个参数类型里。
16. 类型集合由当前可见的具体类型表达式和已声明类型参数组成。
17. 泛型函数体中对类型参数调用函数时，由对应接口函数签名约束提供能力；`#T` 只声明泛型类型参数。
18. 接口约束里的函数名只从当前文件可见名字解析；`core` 默认可见，`std` 和用户模块需要显式 import。
19. 泛型结构体声明类型参数；能力约束放在使用该类型的函数上。

### 6.8 标准库草案边界

1. `src/net.do` 只承载 `SocketAddr` 及地址构造/读取/判断函数。
2. `src/tcp.do` 只承载 `TcpError`、`TcpListener`、`TcpStream` 等类型形态。
3. `src/udp.do` 只承载 `UdpError`、`UdpSocket` 等类型形态。
4. TCP/UDP 的实际 I/O 留到 host ABI 扩展后实现；原因是当前 host import ABI 只表达 `i32/i64/f32/f64/nil`。
5. 后续若扩展 host ABI，应先定义资源句柄、buffer 传递、错误编码和关闭语义，再在 `std` 中提供普通 do 函数封装。
6. 这与 Go/Rust/Zig 的标准库分层方向一致：地址类型、TCP listener/stream 和 UDP socket 分离；差异是 `do` 的最终目标是 wasm，因此系统调用能力必须由宿主桥接提供。
7. `src/binary.do` 属于 `std` 字节编解码辅助库；hash/encoding 库按需显式 import。
8. 高阶组合函数属于 `std`，不属于 `core`；例如 `src/pipe.do` 提供同类型串联 `pipe(value T, funcs ...(T) -> T) -> T`。
9. `src/list.do` 提供 `items/put/update/del/clear` 等基础集合操作，以及 `map/filter/fold/reduce/find/find_index/any/all/count` 等函数式集合工具；`List<T>` 对内建 `len/at/get/set` 协议的支持不通过普通同名函数声明暴露。
10. 删除闭包捕获后，`map/filter/find/find_index/any/all/count/update` 提供显式 `env` 重载，例如 `map(xs, env, (x, env) => ...)`。
11. `src/hash_map.do` 提供 `keys/values/has/put/update/del/entries` 等基础映射操作；`HashMap<K, V>` 对内建 `len/at/get/set` 协议的支持不通过普通同名函数声明暴露；`update/del` 只作用于既有 key，缺失时返回 `MapError`。
12. 当前 `src/hash_map.do` 是标准库语义草案实现，可用连续 key/value 存储先锁定公开 API；真实 hash bucket、冲突处理和扩容策略后续在不改变公开函数族的前提下替换内部实现。

### 6.9 测试函数模型

1. 测试写作顶层私有函数，命名使用 `.test_` 前缀，例如 `.test_list_put_variadic`。
2. 测试函数签名固定为 `() -> Error | nil`。
3. 测试函数返回 `nil` 表示通过，返回 `Error` 表示失败。
4. 测试函数可就近放在被测声明旁边，保持模块内就近测试。
5. 执行模型由测试 runner 决定；runner 可支持“同环境连续执行”和“每例新环境执行”两种模式。
6. `.test_` 函数不参与模块 public API 导出。

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
4. 必须统一采用如下 fenced code 块约定，便于脚本提取合法示例：

   - `do program ok`: 完整 `Program` 正例
   - `do fragment ok`: 未声明细分层级的片段正例（兼容旧格式）
   - `do decl ok`: 顶层声明片段正例
   - `do stmt ok`: 语句片段正例
   - `do expr ok`: 表达式片段正例
   - 兼容规则：旧格式 `do ok` 视为 `do fragment ok`，仅用于存量兼容，禁止新增

5. 新增或修改示例必须使用显式层级标签（`do program ok` / `do fragment ok` / `do decl ok` / `do stmt ok` / `do expr ok`）；遗留 `do ok` 仅作兼容，并在触达时迁移。

````markdown
```do stmt ok name=path_get_single
name = get(user, .name)
```

```do stmt ok name=path_index_expr_segment
first_name = get(users, 0, .name)
```

```do stmt ok name=path_index_call_expr_segment
first_name = get(users, add(i, 1), .name)
```

```do stmt ok name=put_list_append
xs List<i32> = List<i32>{}
xs = put(xs, 1, 2, 3)
```

```do stmt ok name=list_set_vs_put
xs List<i32> = List<i32>{}
xs = put(xs, 1)
xs = put(xs, 2)
xs = set(xs, 1, 9)
xs = put(xs, 8)
```

```do stmt ok name=list_del
xs List<i32> = List<i32>{}
xs = put(xs, 1)
xs = put(xs, 2)
xs = del(xs, 0)
```

```do stmt ok name=list_update
xs List<i32> = List<i32>{}
xs = put(xs, 1)
xs = put(xs, 2)
xs = update(xs, 1, (x i32) -> i32 => add(x, 40))
```

```do stmt ok name=put_map_key
m HashMap<Text, i32> = HashMap<Text, i32>{}
m = put(m, "a", 1)
```

```do stmt ok name=hash_map_del
m HashMap<Text, i32> = HashMap<Text, i32>{}
m = put(m, "a", 1)
m = del(m, "a")
```

```do stmt ok name=hash_map_update
m HashMap<Text, i32> = HashMap<Text, i32>{}
m = put(m, "a", 1)
m = update(m, "a", (x i32) -> i32 => add(x, 40))
```

```do stmt ok name=put_struct_field
user = put(user, .name, "tom")
```
````

6. 新语法进入主干前，必须补对应 `tool/build/test` 用例并更新本文。
7. `loop` 支持无限循环 `loop { ... }`、集合循环 `loop v, i = xs` / `loop _, i = xs` / `loop v, _ = xs`，以及消费循环 `loop v = recv(ch)`；集合源由内建协议函数提供 `len(source) -> usize` 与 `at(source, usize) -> V`。
8. 建议同时覆盖下列正例:

````markdown
```do stmt ok name=call_multiline_trailing_comma
x = add(
    a,
    b,
)
```

```do decl ok name=private_type_decl_left_dot
.InternalUser = User | nil
```

```do decl ok name=import_relative_type
User = @user_profile.do/User
```

```do decl ok name=import_project_lib_value
hash = @~/hash_map.do/hash
```

```do decl ok name=import_std_value
now = @/time.do/now
```

```do decl ok name=import_std_const
f32_pi = @/math.do/_f32_pi
```

```do decl ok name=host_import_abi
console_log = @env/console_log(i32, i32) -> nil
```

```do decl ok name=func_omit_nil_return
log(msg Text) {
    return
}
```

```do decl ok name=func_param_mutable
inc(x i32) -> i32 {
    x = add(x, 1)
    return x
}
```

```do fragment ok name=param_update_does_not_escape
inc(x i32) -> i32 {
    x = add(x, 1)
    return x
}

keep(a i32) -> i32 {
    _next i32 = inc(a)
    return a
}
```

```do stmt ok name=lambda_param_mutable
map(xs, (x i32) -> i32 {
    x = add(x, 1)
    return x
})
```

```do decl ok name=test_return_nil
.test_early_return() -> Error | nil {
    if ok return nil
    return nil
}
```

```do decl ok name=test_return_explicit_nil
.test_explicit_nil() -> Error | nil {
    return nil
}
```

```do fragment ok name=overload_typed_arg_selects_candidate
foo(x i32) -> i32 {
    return x
}

foo(x i64) -> i64 {
    return x
}

a i32 = 1
b i32 = foo(a)
```

```do fragment ok name=typed_bind_drives_call
#T = i8 | i32
double(x T) -> T {
    return x
}

a i8 = 12
b = double(a)
```

```do stmt ok name=is_value_type_guard
v = to_i8(1234)
if is(v, Error) return
a = double(v)
```

```do stmt ok name=is_union_type_set
if is(v, i32 | i64) return
```

```do stmt ok name=eq_nil_guard_narrows
if eq(v, nil) return
name = get(v, .name)
```

```do stmt ok name=and_propagates_narrowing
if and(ne(v, nil), eq(get(v, .name), "tom")) return
```

```do fragment ok name=error_branch_value
FileError = FileNotFound | PermissionDenied | Unknown
v i32 | FileError = FileNotFound
if eq(v, FileNotFound) return
```

```do fragment ok name=multi_return_assign
div_mod(a i32, b i32) -> i32, i32 {
    return 1, 2
}

q, r = div_mod(7, 3)
```

```do decl ok name=multi_return_passthrough
div_mod(a i32, b i32) -> i32, i32 {
    return 1, 2
}

wrap() -> i32, i32 {
    return div_mod(7, 3)
}
```

```do fragment ok name=struct_explicit_value
Pair {
    a i32
    b i32
}

t Pair = .{a = 1, b = 2}
```

```do decl ok name=func_constraint_prefix_line
#T = i32 | i64
#add(T, ...T) -> T
sum(a T, b T) -> T {
    return add(a, b)
}
```

```do fragment ok name=core_numeric_variadic
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

```do decl ok name=generic_type_param_unconstrained
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

```do decl ok name=generic_type_param_inline_env
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

```do fragment ok name=list_functional_ops
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

```do fragment ok name=std_pipe_same_type_chain
pipe = @/pipe.do/pipe

result i32 = pipe(
    2,
    (x i32) -> i32 => add(x, 1),
    (x i32) -> i32 => mul(x, 3),
)
```

```do decl ok name=generic_struct_list_storage
#T
List {
    .len usize = 0
    .items [T] = .{}
}
```

`.{}` 与 `.{v1, v2, ...}` 可在已知目标类型为 `[T]` 时构造连续存储；由目标类型提供 `T`，用户代码只通过库函数操作它。

```do decl ok name=generic_struct_map_storage
#K
#V
HashMap {
    .len usize = 0
    .keys [K] = .{}
    .vals [V] = .{}
}
```

`List/HashMap` 在这里只是普通库类型示例，不是保留类型名，也不享有特殊字面量 body。

```do stmt ok name=loop_recv_value
loop v = recv(ch) {
    consume(v)
}
```

```do stmt ok name=loop_infinite_break
loop {
    break
}
```

```do stmt ok name=loop_each_index_value
xs List<i32> = List<i32>{}
loop v, i = xs {
    consume(i, v)
}
```

```do stmt ok name=loop_each_discard_index
xs List<i32> = List<i32>{}
loop _, i = xs {
    consume(i)
}
```

```do stmt ok name=loop_each_discard_value
xs List<i32> = List<i32>{}
loop v, _ = xs {
    consume(v)
}
```

```do fragment ok name=loop_text_direct
Text = @/text.do/Text
s Text = "abc"
loop v, i = s {
    consume(i, v)
}
```

```do fragment ok name=inferred_struct_ctor
Point {
    x i32
    y i32
}

p Point = .{x = 1, y = 2}
```

```do fragment ok name=typed_struct_ctor
Config {
    a i32
    b i32
}

config = Config{a = 1, b = 2}
```

```do stmt ok name=union_from_typed_ctor
x User | nil = User{name = "tom"}
```

```do fragment ok name=struct_field_equals
Handle {
    fd i32
}

handle = Handle{fd = 0}
```

```do fragment ok name=generic_struct_field_ctor
#T
Box {
    value T
}

x = Box<i32>{value = 1}
```

```do decl ok name=return_multiline_generic_ctor
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

```do fragment ok name=struct_field_ctor_inferred_type
Counter {
    len usize
}

count Counter = .{len = 0}
```

```do decl ok name=field_default_runtime
now = @env/now() -> i64

User {
    created_at i64 = now()
}

make_user() -> User {
    return User{}
}
```

```do stmt ok name=if_guard_return
if ok return
```

```do stmt ok name=else_if_chain
if a {
    return 1
} else if b {
    return 2
} else {
    return 3
}
```

```do stmt ok name=loop_label_break
#outer
loop {
    loop {
        break #outer
    }
}
```

```do stmt ok name=line_string_single
str Text = \\abc
```

```do stmt ok name=line_string_multi
str Text =
    \\abc
    \\def
```

```do stmt ok name=line_string_explicit_blank_line
str Text =
    \\abc
    \\
    \\def
```

```do stmt ok name=line_string_no_escape
str Text = \\a\nb
```

```do stmt ok name=line_string_arg_own_line
log(
    \\abc
)

name = add(prefix,
    \\abc
)
```

```do stmt ok name=lambda_callback_site
result = map(xs, (x i32) -> i32 => add(x, 1))
```

```do stmt ok name=lambda_explicit_env
step i32 = 1
result = map(xs, step, (x i32, step i32) => add(x, step))
```

```do fragment ok name=func_name_value_target_select
inc(x i32) -> i32 { return add(x, 1) }
inc(x i64) -> i64 { return add(x, 1) }
apply(f (i32) -> i32) -> i32 { return f(1) }
v = apply(inc)
```

```do fragment ok name=import_func_name_value_target_select
inc = @fixture/import_overload_func.do/inc
apply(f (i32) -> i32) -> i32 { return f(1) }
v = apply(inc)
```

```do err name=func_name_value_no_target
inc(x i32) -> i32 { return add(x, 1) }
inc(x i64) -> i64 { return add(x, 1) }
f = inc
```

```do decl ok name=generic_variadic_sum
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

```do decl ok name=variadic_spread_call
print_all(prefix Text, rest ...Text) {
    print(prefix, ...rest)
}
```

```do decl ok name=top_const_read
_step i32 = 1

inc(x i32) -> i32 {
    return add(x, _step)
}
```
````

## 8. 非目标

1. 本版只预留标准库时间接口（如 `ms/sec/day`）的语法位。
