# do 语言详细规则 (spec rules v1)

## 0. 状态

1. 规范入口是 `doc/spec.md`。
2. 语法设计速查按功能拆分在 `doc/syntax/`。
3. parser 可执行文法单独维护在 `doc/grammar.peg`。
4. 本文保留语义规则、静态约束和测试约定。
5. 语义规则章节供 sema/test 执行。
6. v1 运行时内存模型以 `doc/memory.md` 为准; `doc/arc.md` 保留长期 ARC/Perceus/并发优化草案。

## 1. 分层模型

1. `PEG` 只定义可解析结构，不承载类型推导或收窄推理。
2. 静态约束只定义可通过规则，不重复书写 parser 结构。
3. 能在 `PEG` 层无符号表地判定的语法边界必须放进 `PEG`；`PEG` 应尽量强硬，静态约束只承载需要类型、作用域、可见性或数据流信息的判断。
4. 运行层按 `builtin -> core -> std` 分层；依赖只能向下。
5. `builtin` 是编译器/Wasm/host 桥接层，提供 special form 与底层 primitive；`core` 和 `std` 通过它使用这些能力。
6. `core` 是默认可见核心库，封装 `builtin` 并提供语言最小可用函数值、数值函数、结构字段操作与连续存储 primitive。
7. `std` 是可导入标准库，基于 `core` 提供扩展能力。
8. `is/not` 属于 `builtin` special form；`and/or` 在 `bool` 条件和 `bool` 表达式上属于 `builtin` special form，在整数参数上属于 core 位运算固定调用名。源码调用都必须写成 `@name(...)`。
9. `get/set` 是 `core` 路径 primitive 的保留调用形态，源码调用必须写成 `@get/@set(...)`；它们不是普通函数族，字段段 `.name` 只在该形态里出现。
10. `fields(TypeOrTypeParam)` 是字段反射循环源 special form，只能出现在 `loop field = fields(TypeOrTypeParam) { ... }` 头部；`fields` 不是普通函数名，也没有 `@fields(...)` 形态。
11. `@field_name/@field_index/@field_has_default/@field_get/@field_set` 是字段反射内建调用名，只能配合 `fields(TypeOrTypeParam)` 产生的编译器字段元数据使用，不进入普通函数声明、重载、遮蔽或 import alias。
12. `eq/ne/lt/le/gt/ge`、`add/sub/mul/div/rem`、`and/or/xor/shl/shr/rotl/rotr/clz/ctz/popcnt`、`abs/neg/sqrt/ceil/floor/trunc/nearest/min/max/copysign`、`len`、`put` 与 `load_u8/load_i8/load_u16_le/load_i16_le/load_u32_le/load_i32_le/load_u64_le/load_i64_le` 由 `core` 以固定内建调用名提供，源码调用必须写成 `@name(...)`。这些名字不支持用户或标准库按同名函数重载补充新参数签名，也不能被遮蔽或重写。数值转换统一使用 builtin `@as(Type, value)`。集合或领域扩展必须使用非 core 名，例如 `list_add(xs List<T>, value T, rest ...T) -> List<T>`、`hash_put(m HashMap<K, V>, key K, value V) -> HashMap<K, V>`、`same_user(a User, b User) -> bool`。
13. 数值、位运算与浮点基础函数（如 `@add/@sub/@mul/@div/@rem/@and/@shl/@rotl/@clz/@popcnt/@abs/@sqrt/@min`）属于 `core` 固定函数名，由 `builtin` primitive 支撑；默认算术签名是 core 原始签名，`@add/@sub/@mul/@div` 源码调用可写同类型 2 个及以上参数，也可在尾部使用 `...rest` 展开；`@rem` 只接受整数标量，源码调用同样可写同类型 2 个及以上参数；`@clz/@ctz/@popcnt` 只接受一个整数标量参数；`@abs` 只接受一个 signed integer 或 `f32/f64` 参数，signed integer 返回对应 unsigned 类型，`f32/f64` 返回同类型，不提供 `@abs(u*)` identity 签名；`@min/@max` 接受同类型整数或浮点标量的 2 个及以上参数，返回同类型，源码 3+ 参数按左折叠处理；`@neg/@sqrt/@ceil/@floor/@trunc/@nearest` 只接受一个 `f32/f64` 参数，`@copysign` 只接受两个同类型 `f32/f64` 参数。调用解析只在 core 固定签名内完成，不收集用户同名候选。编译到 wasm 时，这些 `@` core 调用按静态类型直接 lower 到对应 wasm 指令或固定 select 序列，例如 `u64` 上的 `@div` 使用 `i64.div_u`，`f64` 上的 `@mul` 使用 `f64.mul`，`u32` 上的位运算 `@and` 使用 `i32.and`，`u64` 上的 `@ctz` 使用 `i64.ctz`，`f32` 上的 `@abs` 使用 `f32.abs`，`i32` 上的 `@min` 使用 `i32.lt_s + select`，`f64` 上的 `@copysign` 使用 `f64.copysign`。
14. `[T]` 是 `core` 连续存储 primitive，表示任意多个连续的 `T` 值；它携带运行时长度信息，用于 `@len/@get/@set/@load_*` 边界检查与集合循环遍历；它不是高层集合类型，没有内建默认 `to_text`；标准库或用户库可用它实现 `List/HashMap` 等普通泛型结构体，并为这些集合类型自行提供 `to_text` 重载。
15. `text` 是源码层文本基础类型，底层表示仍可复用 `[u8]`，但语义上要求内容是有效 UTF-8。普通字符串和行字符串默认产生 `text`；普通字符串里的 `\xNN` 先解码成字节，再校验整体 UTF-8。`"\xFF"` 这类非法 UTF-8 文本不成立；原始字节写 `[u8] = .{255}`。在 `[u8]` 目标上下文中，有效字符串字面量也可作为对应 UTF-8 字节序列使用。`[u8]` 继续表示原始字节，不保证 UTF-8。普通函数可用 `text` 作为参数或返回类型；在已知目标类型为 `text` 的绑定位、参数位和返回位，字符串字面量会 lower 成 ARC storage handle。`text` 与 `[u8]` 的边界使用显式库函数，例如 `bytes_of(s text) -> [u8]` 与 `text_from(bytes [u8]) -> text | Utf8Error`。`@len/@get/@set/@put/loop` 仍只面向 `[T]` 连续存储 primitive；`text` 的字节长度、字符数量和切片由 `src/text.do` 提供专用函数，避免和 `[u8]` 的长度语义混淆。
16. 时间换算函数（如 `ms/sec/day`）属于 `std` 时间库。
17. `Error` 是编译器内部合成的诊断/工具聚合视图，只聚合当前可达模块中所有对外可见的 `error` 枚举类型；它不承接 primitive trap / safety failure，源码类型位不能直接写 `Error`。
18. `[T]` 的 `@get([T], usize) -> T` 与 `@set([T], usize, T) -> [T]` 是前置条件索引操作；索引越界是 runtime trap / safety failure，不作为源码可见错误返回。`[u8]` 的 little-endian 定宽读取使用 `@load_u8/@load_i8/@load_u16_le/@load_i16_le/@load_u32_le/@load_i32_le/@load_u64_le/@load_i64_le`，参数固定为 `([u8], usize)`，返回对应标量类型；这些调用直接 lower 到 wasm `load8/load16/load/load64` 指令，不通过标准库手工拼字节。big-endian 读取仍由 `std` 显式组合实现。
19. 标量数值转换使用 `@as(Type, value)`，其中 `Type` 只能是 `u8/u16/u32/u64/usize/isize/i8/i16/i32/i64/f32/f64`，`value` 必须是标量数值表达式。`@as(Type, value)` 由编译器按静态类型 lower 到 wasm conversion/wrap/extend/trunc/promote/demote 指令；它不进入普通函数重载、声明、alias、绑定、参数或接口约束名字空间。
20. 可能失败的文本解析、显式 UTF-8 校验或安全数值窄化使用普通库函数名，返回目标类型与具体错误枚举；这些失败属于普通转换错误，不归入 primitive safety failure。例如 `parse_i32(s text) -> i32 | ConvertError` 或库自定义领域名。`[u8]` 参与的文本转换与解析使用普通非 core 名，例如 `to_text`、`parse_i32` 或库自定义领域名。
21. `to_text` 是普通 `to_*` 名，第一版 `std` 只承诺基础值和标准库中明确声明的具体类型重载；不提供任意 `Struct`、`Union` 或合成 `Error` 的通用展示重载。用户库可为自定义具体类型提供 `to_text(T) -> text` 重载。`std` 不提供默认函数值 `to_text`；用户可以为具体命名函数类型显式定义普通重载，例如 `#F = (i32) -> text` 后写 `to_text(f F) -> text`。第一版不定义运行时函数值的通用稳定文本展示。
22. `core` 的数值转换可由编译器按静态签名 lower 到内部实现；这只是实现策略，不开放这些 core 名的声明或重载。`to_text` 不在 core 固定名集合内，以普通标准库/用户函数提供。
23. 每个具体 `to_text` 重载的输出格式必须稳定；`std` 已声明的具体重载保证相同输入在相同版本内输出一致，用户库自定义重载的稳定性由定义该重载的库承担。
24. 字符串输出使用带双引号的源码字符串形态，并按字节转义必要内容；`"`、`\`、换行、回车、tab 和不可打印字节可用 `\xNN` 形式表示。
25. `nil/bool/number` 输出使用源码 token 风格，例如 `nil`、`true`、`false`、`123`、`3.14`；不做本地化、人类化或分组格式。浮点数使用最短 round-trip 十进制表示，不保留源码原始写法；非有限浮点值固定展示为 `nan`、`inf`、`-inf`，它们只属于 `to_text` 文本输出。
26. 第一版不承诺 `std` 通用 `Struct/Union` 展示；若诊断、文档工具或某个显式具体重载需要展示结构体，可采用字段构造风格并只按结构体声明顺序展示 public 字段。枚举分支值的诊断展示直接使用源码里的分支原名，例如 `NotFound`、`FileClosed`；不额外拼接所属枚举类型名，也不引入 `Type:Branch` 这类额外展示格式。合成 `Error` 只用于诊断/工具视图。该格式只是文本输出，不是源码构造语法。
27. 函数名和签名可用于编译器诊断、文档或调试工具输出；普通源码里的函数值文本化只通过用户显式定义的具体函数签名 `to_text(f F) -> text` 重载获得，不由语言或 `std` 默认提供。
28. `do` 目前只作为未来扩展保留关键字，已经进入 `ReservedWord`，不能作为普通名字；v1 没有可用 `do` 语法产生式。`defer` 是已落地 statement 关键字，不能作为普通名字；语义是离开当前词法区域时执行 cleanup。
29. 网络库属于 `std`；本版只定义地址、TCP listener/stream、UDP socket 等值形态。真实 `listen/connect/accept/read/write/send/receive/close` 等 host ABI 能承载 buffer 和资源句柄后再由标准库封装；源码层的 `recv` 已保留给消费循环 special form，不作为普通库函数名。
30. `src/_.do` 是 builtin/core 声明总表，编译器隐式加载，不作为 local import 目标，也不需要在普通源码中引用；它记录默认可见的 builtin special form、core primitive 声明和 core 普通函数签名，不承载 `std` 实现。


## 2. 词法与命名

### 2.1 标识符与字面量

词法 token 形态与 parser 可执行主文法统一维护在 `doc/grammar.peg`；本节只保留命名约束与字面量语义规则。

规则:
1. 丢弃位只写 `_`；普通标识符使用 `LowerIdent`、`UpperIdent` 或 `ReadonlyIdent`。
2. 只读标识符写作前置 `_` 加 `LowerIdent` 主体，例如 `_name`、`_ready2`、`_file_name`。`ReadonlyIdent` 只检查整个 token 是否满足该形态，不再对主体追加 `ReservedName`、`BuiltinSpecialName`、`ReservedCoreAccessName` 或 `BaseTypeName` 排除；因此 `_if`、`_add`、`_bool` 合法，`_Name`、`_GameName`、`_Error` 非法。
3. `UpperIdent` 用于类型名、类型参数名和枚举分支值，命名风格采用 UpperCamel；缩写按普通词处理，例如 `HttpServer`、`UserId`。
4. 顶层私有声明使用前置 `.`，例如 `.internal_name`；前置点只表示声明可见性，声明完成后的实际 name 不含点，同模块内使用时不写点，例如声明 `.state i32 = 0`，读写都写 `state`。
5. 字段路径段使用前置 `.`, 例如 `.name`。点前缀标识符只允许一个前置点；去点后的主体必须完整满足 `LowerIdent` 或 `UpperIdent`，内部不能再出现 `.`，因此 `.a.b` 不是合法字段段或私有声明名。
6. 循环标签使用前置 `#`, 例如 `#outer`。
7. 普通字符串写成单行 `"..."`。
8. 普通字符串支持 `\"`, `\\`, `\n`, `\r`, `\t`, `\xNN`；escape 解码后的字符串字面量必须形成有效 UTF-8 文本，默认定型为 `text`。
9. 普通字符串在 `[u8]` 目标上下文中可作为对应 UTF-8 字节序列使用；非法 UTF-8 原始字节不能用字符串字面量表达，必须写成 `[u8]` 聚合，例如 `.{255}`。`[u8]` 变量和聚合仍表示原始字节，不承担 UTF-8 不变量。需要从任意 `[u8]` 构造 `text` 时，使用 `src/text.do` 的 `text_from(bytes [u8]) -> text | Utf8Error` 显式校验。
10. 行字符串使用 Zig 风格 `\\text`，内容从 `\\` 后开始到行尾结束。
11. 连续行字符串由 lexer 合并为单个 `LineStringToken`，形成一个多行字符串值；各行之间用 `\n` 连接，源码缩进不进入字符串值。
12. 行字符串按源码文本保留，不解释转义；合并后的内容仍必须是有效 UTF-8 文本。若要表达任意非 UTF-8 字节，使用 `[u8]` 聚合。
13. 行字符串只在 PEG 明确列出的 `RhsExpr` 根位直接出现；因此顶层值、局部绑定、赋值和字段默认值可以在 `=` 后同行或换行接 `LineStringBlock`。`return` 位置不直接接收行字符串；需要返回行字符串时，先在 `RhsExpr` 根位绑定到局部值，再返回该绑定。结构体构造字段初始化、普通调用参数和聚合元素也不直接接收行字符串；需要作为字段值、参数或元素时，先在表达式根位绑定到局部值，再使用该绑定。普通表达式必须和 `=`、`return` 或 `=>` 保持在同一语句行；只有 `LineStringBlock` 可在 `RhsExpr` 根位换到下一行。
14. 行字符串不直接作为调用参数或聚合元素；需要传参或放入聚合时，先在表达式根位绑定到局部值，再使用该绑定。
15. 字符串值中的空行必须显式写成空内容行字符串 `\\`；源码空行和注释行都会打断 `LineStringBlock`。
16. raw 文本使用行字符串 `\\text`。
17. 注释在词法阶段剔除并保留后续 parser 所需的行号边界；行注释写作整行 `// ...`，`//` 前只能有空格或制表符，不能跟在声明或语句 token 后面；块注释写作单层 `/* ... */`，也只能作为独立注释块，不能插在 token 中间或行尾。
18. 注释只在普通源码模式识别；普通字符串与行字符串内容中的 `//`、`/*`、`*/` 都按文本保留。行字符串 `\\...` 从 `\\` 后开始一直保留到行尾，不被 `//` 截断。
19. lexer 把 `CRLF`、`CR` 与 `LF` 都作为等价行边界处理；token 自身携带归一后的 line/col metadata。
20. parser 输入是 token 流；空格、制表符和换行不作为独立 token 保留，PEG 中的 `DeclSep` / `LineGap` / `StmtGap` / `SoftGap` 是相邻 token line metadata 的关系谓词，不是实体 token，也不能写成可重复消费项。
21. 顶层声明与块内语句使用换行分隔；一行一个声明或语句。
22. 关键字按整 token 匹配，不做前缀匹配；例如 `dof` 是一个 `Ident`，不是 `do` + `f`。

### 2.2 保留词与保留标识符

```
if else loop break continue return defer do
true false nil
```

以上保留词只用于语言保留位置。

内建 special form 名（仅用于对应内建调用位置）:

```
is and or not
recv
```

core 路径 primitive 保留调用名（仅用于对应路径调用位置）:

```
get set
```

core 固定函数名（只能通过 `@name(...)` 调用；声明、alias、绑定、参数和接口约束位保留）:

```
eq ne lt le gt ge
add sub mul div rem
and or xor
shl shr rotl rotr
clz ctz popcnt
abs neg sqrt
ceil floor trunc nearest
min max copysign
len put
load_u8 load_i8
load_u16_le load_i16_le
load_u32_le load_i32_le
load_u64_le load_i64_le
```

声明专用名（仅用于顶层声明位置）:

```
start test
```

保留类型名（普通名字中保留；循环标签例外）:

```
i8 i16 i32 i64
u8 u16 u32 u64
isize usize
f32 f64
bool
text
char
Error
```

其中 `Error` 继续列在这个展示块里，只表示该名字被语言/编译器占用；它进入 `ReservedTypeName` / `ReservedName`，但不是 `BaseTypeName`，不能作为源码类型位直接使用。`text` 是普通源码基础类型。`char` 当前只作为 WIT ABI 签名里的类型 token 使用，不是 Do 普通源码类型名，并按 WIT-only 保留名处理，不能作为普通 lower 名、字段名、普通 lower 导入别名或函数名。


### 2.3 Token 契约

1. 语法文法以 token 流为输入；空格、制表符和换行不作为实体 token 保留，本文 PEG 中的 `NL`、`LineGap`、`StmtGap` 都表示基于相邻 token `line` metadata 的行边界谓词。`...` 可作为单个词法 token；`->` 与 `=>` 可由相邻 symbol token 组合识别，不要求 lexer 产出独立箭头 token。PEG 中的字符串字面量、`ReservedName`、`ReservedWord`、`BuiltinSpecialName`、`ReservedCoreAccessName`、`BaseTypeName` 与同类谓词都按完整 token 匹配，不做字符前缀匹配；因此 `dof` 是一个 `LowerIdent`，不会先匹配成 `do`。
2. 前置点私有名（如 `.internal_user`、`.InternalUser`）与字段段（如 `.name`）属于点前缀标识符族；PEG 使用 `DotLowerIdent` / `DotUpperIdent` 表示这类单 token 形态，文法按语义位区分它们，而不是靠字符串切分推断。
3. `DotLowerIdent` 表示 lexeme 形如 `.lower_ident` 的单个 token；`DotUpperIdent` 表示 lexeme 形如 `.UpperIdent` 的单个 token；`DotReservedName` 表示去点后属于 `ReservedName` 的点前缀标识符 token。
4. `.{` 保持为 `.` 与 `{` 两个 token，避免与字段段混淆。
5. 文法中的 `PathSeg`、`FlatFileSeg` 与 import 路径规则属于 import 位专用解析，不参与普通表达式 token 解释。import 文件名只有遇到 `.do/` 时结束；`.do.` 不结束文件名。
6. `ErrorEnumName` 是完整 lexeme 谓词：该 token 必须满足 `UpperIdent`，以 `Error` 结尾，并且不等于 `Error` 本身；`DotErrorEnumName` 按去点后的 lexeme 使用同一判断。


## 3. 模块、导入与可见性

本章只处理模块边界、导入形态、可见性和顶层名字空间。函数重载规则见函数章节，类型 alias 与 union 规则见类型章节。

1. 类型声明名使用 `UpperIdent`，风格为 UpperCamel；普通函数名使用非保留 `LowerIdent`；私有普通函数声明名使用 `.lower_name`；字段名使用 `LowerIdent`，私有字段声明名使用 `.lower_ident`，同一结构体内字段按去点后的实际 name 唯一。字段实际 name 不能是关键字、core 路径 primitive 名、声明专用名或保留类型名；例如 `get`、`set`、`test`、`i32`、`bool` 都不能作为字段名。`len/add/popcnt` 这类只能通过 `@name(...)` 调用的 core 固定函数名可以作为字段实际 name。
2. 私有类型名出现在类型声明左侧（`DeclTypeName`）；类型引用位统一去点。
3. 私有声明在声明位使用前置 `.`；`.` 只表示可见性，去点后的部分才是实际 name；访问时统一去点（字段路径段除外）。
4. builtin special form 名、core 路径 primitive 名、core 固定函数名、声明专用名与保留类型名不得用于顶层声明、导入别名、参数名或局部绑定。字段实际 name 按字段保留集合处理，允许复用 `len/add/popcnt` 这类 core 固定函数名。core 固定函数名只在调用位按固定 core 规则使用；不能声明同名普通函数，不能通过 local function import alias 或 host import alias 引入同名符号，也不能在当前模块用普通函数声明显式包装成同名新签名。
5. 顶层名字共享同一名字空间；仅同名函数族允许重名。枚举分支值也是顶层 public 值名，必须参与同一命名冲突检查。普通类型名可以使用 `NotFound`、`Ready` 这类看起来像枚举分支值的 `UpperIdent`，只要当前可见范围里没有同名枚举分支值、错误枚举类型名或同类 type import alias。同一模块内类型声明名、type import alias、顶层模块级可变变量名、顶层常量名、value import alias、readonly import alias、host import alias、普通函数声明和函数 import alias 的签名先整体收集，再检查字段类型、类型实参、初始化表达式、函数签名、函数体、lambda 体、测试体和接口函数约束；因此顶层类型、值与函数声明顺序不影响可见性。
   ```do decl ok
   UserBox {
       value User
   }

   User {
       id i32
   }
   ```
6. 公开签名使用 public 类型。
7. 保留词、builtin special form 名、core 路径 primitive 名、声明专用名与保留类型名只用于语言保留位置；普通 lower 名不得使用这些实际 name。字段名、字段初始化名和字段路径段只排除字段保留集合；`len/add/popcnt` 等 `@` core 名在字段位合法。循环标签名是独立命名空间，只按循环标签规则排除 `ReservedWord`。
8. import 只允许出现在顶层连续前置区块；一旦开始出现 `TypeDecl`、`FuncDecl`、`ValueDecl`、`start` 或 `test`，后面就不能再出现 import。
9. import 左侧只有 alias；local import 左侧没有额外私有前缀规则。`UpperImportDecl` 左侧使用 upper alias，统一承载 public 类型、public enum 类型与 public enum 分支值 import；`ReadonlyImportDecl` 左侧使用 `ReadonlyIdent`，`ValueImportDecl` 左侧使用 `LowerIdent`，`HostImportDecl` 左侧使用 `LowerIdent` 或私有 `.LowerIdent`。alias 只负责在当前模块里提供一个可用名字；真正的目标声明类别仍由右侧导入目标决定。`*Error` 后缀 alias 只允许指向实际 `ErrorEnumDecl` 错误枚举类型，不允许指向普通类型、value enum 类型或 enum 分支值；例如 `FileError = @lib("./fs_error.do", FileError)` 合法，`UserError = @lib("./user.do", User)` 与 `NotFoundError = @lib("./fs_error.do", NotFound)` 非法。`ValueImportDecl` 导入 public lower 符号：包括普通函数族和 public 模块级可变变量。host import 左侧允许普通 lower 名或私有 lower 名，例如 `console_log = @env("console_log", (i32, i32) -> nil)` 与 `.host_now = @wasi("clocks/system-clock/now", () -> u64)` 合法，`_console_log = @env("console_log", (i32, i32) -> nil)` 与 `ConsoleLog = @env("console_log", (i32, i32) -> nil)` 非法。host import alias 在同一 source module 内唯一；入口模块和递归导入模块可以各自使用同名 alias，因为 WASI binding identity 是 `source + alias`。core 固定函数名不能作为 local function import alias 或 host import alias；若目标模块或 host 也有同名符号，当前文件必须选择非 core alias，例如 `host_add = @env("add", (i32, i32) -> i32)`。
10. import alias 是当前模块可见的顶层 alias，可用于当前模块源码里的类型引用或调用引用，但它不是新的 import target，也不是对外导出的新声明；其他文件不能把这个 alias 再当作 local import 目标。local import 右侧只能指向目标文件中直接声明的原始 public 顶层声明，不能指向 `LocalImportDecl` 或 `HostImportDecl` 引入的 alias。
11. imported public type 可以出现在当前文件的 public API 源码签名中；无论源码里通过哪个 alias 引用，对外 API 模型、文档和诊断都展示来源文件的 canonical source 与原始 public 类型名，不展示当前模块的本地 import alias。同一个 canonical source 经不同 alias 导入后仍是同一个类型，可直接互相赋值、传参和返回。
    ```do program ok
    // user.do
    User {
        id i32
    }

    // main.do
    Profile = @lib("./user.do", User)

    load() -> Profile {
        return .{id = 1}
    }
    ```
    上例源码合法；`Profile` 只是当前模块里的本地 alias，对外 API 展示必须归一到 `user.do` 里的 `User`，不能把 `Profile` 展示成可从 `main.do` 再导入的类型。
12. imported declaration 在当前模块里始终只是对原始 public 声明的本地命名，不生成新的独立类型或独立值身份。
    ```do program err
    // user.do
    User {
        id i32
    }

    // profile.do
    Profile = @lib("./user.do", User)

    // main.do
    User = @lib("./user.do", User)
    Profile = @lib("./profile.do", Profile)
    ```
    上例最后一行非法，因为 `profile.do` 里的 `Profile` 是 import alias，不是原始 public 声明。
    导入 public 模块级可变变量时，当前模块里的 lower alias 仍指向来源模块的同一份存储；读取 alias 看到的是原变量当前值，写入 alias 等同于写入原变量，不生成副本。
13. 同一模块内，同一个原始 public 声明最多只允许导入一次；是否改名不影响判重，例如 `User = @lib("./user.do", User)` 与 `Profile = @lib("./user.do", User)` 不能同时出现。
14. local import 的 alias/target 结构匹配不是字面同名约束：`UpperImportDecl` 统一承载 public 普通类型、public enum 类型与 public enum 分支值 import；这三类 upper import 由语义阶段按解析到的目标符号类别区分。`ReadonlyImportDecl` 只匹配顶层常量，`ValueImportDecl` 匹配 public lower 符号，也就是普通函数族与 public 模块级可变变量。alias 可以自由改名，不要求原名先发生冲突，但改名后仍必须符合对应命名规则。
15. local import 必须接受被导入符号的命名限制：导入 public 普通类型、public enum 类型或 public enum 分支值时 alias 写 `UpperImportName`；其中 `*Error` alias 只能指向错误枚举类型，不能指向普通类型、value enum 类型或 enum 分支值。导入顶层常量时 public alias 只能写 `ReadonlyIdent`，不允许写成普通 `LowerIdent`；导入普通函数族或 public 模块级可变变量时 alias 写 `LowerIdent`。允许同类别改名，例如 `Profile = @lib("./user.do", User)`、`AUser = @lib("./auth_user.do", User)`、`FileReadError = @lib("./fs_error.do", FileError)`、`NotFound = @lib("./fs_error.do", NotFound)`、`Missing = @lib("./fs_error.do", NotFound)`、`meta = @lib("./fs.meta.do", read_meta)`、`counter = @lib("./state.do", counter)` 合法；`profile = @lib("./user.do", User)`、`UserError = @lib("./user.do", User)`、`file_error = @lib("./fs_error.do", FileError)`、`not_found = @lib("./fs_error.do", NotFound)`、`NotFoundError = @lib("./fs_error.do", NotFound)`、`Meta = @lib("./fs.meta.do", read_meta)`、`Profile = @lib("./fs.meta.do", read_meta)`、`Counter = @lib("./state.do", counter)` 非法。改名后的 alias 和当前文件已有顶层声明、其他 import alias 或 enum 分支值同名时，按普通命名冲突直接报错，不提供覆盖或阴影规则。
16. local import 目标是来源 `.do` 文件的 public 顶层声明。
17. local import 只支持三种入口：`@lib("./file.do", name)` 为当前文件目录单文件查找，`@lib("~/vendor.name.do", name)` 为外部依赖根目录单文件查找，`@lib("file.do", name)` 为标准库根目录单文件查找。
    正例:
    ```do fragment ok
    User = @lib("./user.do", User)
    User2 = @lib("./if.case.do", User)
    MongoClient = @lib("~/tom.mongo.do", Client)
    Client2 = @lib("~/tom.2024.db.do", Client)
    Client3 = @lib("~/2024.mongo.do", Client)
    Client4 = @lib("~/tom.mongo.2024.do", Client)
    _default_port = @lib("~/tom.mongo.config.do", _default_port)
    NotFound = @lib("~/tom.fs.error.do", NotFound)
    run = @lib("match.do", run)
    now = @lib("time.do", now)
    read_meta = @lib("fs.meta.do", read_meta)
    ```
    反例:
    ```do fragment err
    User = @lib("./model/user.do", User)
    helper = @lib("./2024.helper.do", helper)
    helper = @lib("./_internal.do", helper)
    User = @lib("./user", User)
    MongoClient = @lib("~/mongo/client.do", Client)
    MongoClient = @lib("~/_tom.mongo.do", Client)
    MongoClient = @lib("~/mongo_db.do", Client)
    MongoClient = @lib("~/Tom.mongo.do", Client)
    MongoClient = @lib("~/../tom.mongo.do", Client)
    not_found = @lib("~/tom.fs.error.do", NotFound)
    NotFoundError = @lib("~/tom.fs.error.do", NotFound)
    default_port = @lib("~/tom.mongo.config.do", _default_port)
    read_meta = @lib("fs/meta.do", read_meta)
    helper = @lib("_text.do", helper)
    tool = @lib("2024.tool.do", run)
    now = @lib("/time.do", now)
    play = @lib("lib/goods.do", play)
    ```
    local import 路径只出现在 `@lib` 第一个编译期字符串参数里。当前目录入口写作 `./...`，标准库入口不写前缀，外部依赖入口写作 `~/...`。当前目录导入只接受“当前目录下的单文件模块”；必须显式写 `.do` 扩展名，不允许 `@lib("./user", User)` 这类省略写法，也不允许 `@lib("./model/user.do", User)` 或 `@lib("../user.do", User)` 这类分层/回退写法。相对导入和标准库导入都允许在单个文件名里使用平级 `.` 分段，例如 `@lib("./user.profile.do", User)`、`@lib("fs.meta.do", read_meta)`；这里的 `.` 只是单文件名的一部分，不表示目录层级。模块文件名段只负责定位模块，不复用声明名的关键字/内建名排除规则，因此 `@lib("./if.case.do", User)`、`@lib("match.do", run)` 这类写法合法。所有这些平级分段都仍然按 `PathSeg` 解释，因此每一段都必须以小写字母开头，也不允许以下划线开头；纯数字段只放宽给外部依赖入口，`@lib("./2024.helper.do", helper)`、`@lib("2024.tool.do", run)` 这类相对/标准库写法仍然非法。import 左侧只有 alias，没有额外可见性前缀；alias 只在当前模块里提供名字，不会变成可再次转发导入的新目标。第一版不再提供项目固定根导入前缀；项目内跨文件导入统一使用 `./...` 组织。外部依赖入口使用 `~/...`，默认映射到用户依赖根 `~/.do/lib/*`；源码语义层不允许把它改指向别的根目录，后续若需要镜像或缓存切换，只能作为工具链实现配置扩展处理，不改变源码语法。`~/...` 不允许子目录，`~/` 后面直接就是依赖文件；依赖文件名使用至少两段平级 `.` 分段，例如 `tom.mongo.do`、`tom.mongo_db.do`、`fast_http.client.request.do` 都合法，其中每一段既可以是普通 `PathSeg`，也可以是纯数字段，例如 `tom.2024.db.do`、`2024.mongo.do`、`tom.mongo.2024.do`、`2024.2025.mongo.do`、`tom.mongo.2601.do` 都合法。这里的纯数字段不承载额外版本语义，只要整体满足 `DepNameSeg` 就按普通依赖文件名处理，不再额外限制数字段的位置、数量或是否相邻。依赖名至少两段，即 `vendor.name` 起步，也允许继续追加更多段；普通名字段允许 `_`，纯数字段只接受数字本身，例如 `tom2.mongo_db3.do`、`fast_http.client.request.do`、`tom.2024.db.do`、`2024.mongo.do`、`tom.mongo.2024.do`、`2024.2025.mongo.do`、`tom.mongo.2601.do` 合法。外部依赖入口与其他 local import 一样，复用同一导入类别规则：public 普通类型、public enum 类型、public enum 分支值、public 只读常量和 public 普通函数/值都可以导入，只要左侧 alias 类别匹配目标声明类别。标准库继续使用 `@lib("file.do", name)` 这类无额外前缀写法，例如 `@lib("math.do", clamp_i32)`、`@lib("fs.meta.do", read_meta)`；标准库同样只接受单文件模块，不支持 `@lib("fs/meta.do", read_meta)` 这类分层写法。标准库导入必须显式写 `.do` 扩展名，不引入 `@lib("math", clamp_i32)`、`@lib("time", now)` 这类逻辑模块缩写。标准库根永远由编译器绑定，不允许被项目目录中的同名文件覆盖。三类 local import 都只允许导入目标文件里直接声明的 public 顶层声明，不允许绕过模块边界导入 private 声明，也不允许把别的 import alias 当作目标再次导入。
18. import 路径段默认统一使用 `PathSeg`；`@lib("./file.do", symbol)` 与标准库 `@lib("file.do", symbol)` 的文件段使用 `FlatFileSeg`，也就是单文件名里的平级 `.` 分段，不支持 `/` 分层。`@lib("~/vendor.name.do", symbol)` 的依赖文件段使用 `DepNameSeg`，也就是至少两段 `DepPathSeg` 的平级 `.` 分段，并允许继续追加更多段；`DepPathSeg` 可以是普通 `PathSeg` 或纯数字段，因此依赖名允许 `_`，也允许 `2024` 这类全数字段。`@lib("~/...", symbol)` 不接受额外目录段。
19. local import 使用显式 symbol import：`alias = @lib("./file.do", symbol)`、`alias = @lib("~/vendor.name.do", symbol)`、`alias = @lib("file.do", symbol)`；目标模块会递归加载其自身依赖。第一版不支持省略第二参数的整文件或命名空间导入。
20. 模块依赖图是无环图；local import 会递归解析目标模块，缺失目标符号或任意层级的 import cycle 都是错误。
21. host import 使用 inline ABI 签名，并由编译器桥接到宿主实现；当前支持 `@env("name", sig)` 和 `@wasi("package/interface/member", sig)` 两个分支。`@env` 是标量宿主函数边界，只允许单个宿主函数名，不支持 `"console/log"` 这类多段路径，也不支持 `"console.log"` 这类平级 `.` 分段名字。`@wasi` 按 WASI 0.3 / Phase 3 方向对齐 Wasm component/WIT 的外部签名，目标字符串写作 `package/interface/member`，例如 `"filesystem/types/descriptor.write"`、`"clocks/system-clock/now"`、`"random/random/get-random-u64"`；这里的 `package`、`interface` 和 `member` 只是外部 WIT 目标定位，不是 do 源码模块导入，也不要求写 `.do`。host import 目标名只负责定位宿主实现，不复用源码里的关键字、内建名或声明专用名排除规则，因此 `@env("add", ...)`、`@env("if", ...)` 这类名字可以出现；本地冲突仍然只由左侧 alias 和普通命名规则控制。host import alias 左侧可写 `name` 或 `.name`；声明为 `.name` 时只在当前模块内可用, 模块内调用仍写 `name(...)`, 生成的 binding manifest 也使用去掉私有前缀后的 alias。host import alias 可按普通 `CallExpr` 的 `name(...)` 形态直接调用，但它不进入普通函数族，也不支持按参数类型重载；同一个本地 alias 只能绑定一个 host import 签名，不能把多个 host import 或 host import + 普通函数声明并到同一个同名重载族里。host import alias 也不参与函数名值位解析、不能作为函数值，也不能作为接口函数约束名。host import 当前只表达宿主函数边界，不支持 `@env("count", i32)` 这类宿主全局标量导入；其他文件若需要同一个宿主函数，必须各自直接声明对应的 host import。
    正例:
    ```do fragment ok
    console_log = @env("console_log", (i32, i32) -> nil)
    host_add = @env("add", (i32, i32) -> i32)
    host_if = @env("if", (i32) -> nil)
    .host_file_write = @wasi("filesystem/types/descriptor.write", (descriptor, list<u8>, filesize) -> result<filesize, error-code>)
    .host_file_read = @wasi("filesystem/types/descriptor.read", (descriptor, filesize, filesize) -> result<tuple<list<u8>, bool>, error-code>)

    Datetime {
        seconds i64
        nanoseconds u32
    }

    .host_now = @wasi("clocks/system-clock/now", () -> Datetime)
    ```
    反例:
    ```do fragment err
    console_log = @env("console/log", (i32, i32) -> nil)
    console_log = @env("console.log", (i32, i32) -> nil)
    page_size = @env("page_size")
    is_ready = @env("is_ready", () -> bool)
    host_abs_i32 = @env("abs_i32", (i32) -> i32)
    host_abs_i64 = @env("abs_i64", (i64) -> i64)
    count = @env("count", i32)
    host_file_write = @wasi("filesystem.do/types/descriptor.write", (descriptor, list<u8>, filesize) -> result<filesize, error-code>)
    host_file_write = @wasi("filesystem/types", (descriptor, list<u8>, filesize) -> result<filesize, error-code>)
    ```
22. `@env` 宿主函数名遵循 `PathSeg`，仅允许小写字母、数字与单个下划线分词；下划线不能连续出现，也不能出现在开头或结尾。`@wasi` 的 `package`、`interface` 和 `member` 使用 WIT 名字，可用 `.` 表示 WIT 名字里的平级分段，也可用 `-` 表达外部名字，例如 `system-clock`、`descriptor.write`、`descriptor.link-at`。当前 `@wasi` 不在源码里写 WIT 版本号；版本选择属于工具链依赖解析和组件绑定问题，不放进 host import 语法。
23. host import 签名是 ABI 声明，必须 inline 写在导入语句里。`@env` 参数只允许 `i32/i64/f32/f64`，不支持 `bool`；返回只允许 `nil` 或单个 `i32/i64/f32/f64`，同样不支持 `bool`，也不支持 `@env("pair", () -> i32, i32)` 这类多返回签名。`do build` 当前输出 core WAT 时会把 `@env` 函数导入降成普通 Wasm import，例如 `(import "env" "add" (func $host_add ...))`。当普通字符串字面量直接作为 `@env` 调用实参出现，且该位置正好对应连续两个 `i32` ABI 参数时，`do build` 会把字面量解码为 UTF-8 data segment，导出 linear memory，并在调用位传入 `ptr,len`。`do build` 也支持 `s text = "..."` 这类 typed text literal binding，并把 `text` 局部、参数和返回值作为 ARC storage handle 传递；底层 payload 复用 `[u8]` 布局并保持有效 UTF-8 语义，但这仍不是完整文本 runtime，例如 Unicode 操作和任意表达式位置的字符串字面量 lowering 仍要按具体能力逐步落地。当单个 `[u8]` 或 `text` storage local/参数作为 `@env` 调用实参出现，且该位置同样对应连续两个 `i32` ABI 参数时，`do build` 会把它展开为 storage payload 的 data pointer 与当前 `len`；这用于标准库 wrapper 把字节缓冲或文本传给宿主，不表示源码层暴露裸 pointer。该展开不适用于 `[i32]`、结构体或任意标量 local。direct `@lib(...)` 导入函数内部出现的 host 字符串字面量、`text` storage wrapper 和 `[u8]` wrapper 调用也按同一规则参与当前 WAT 模块的 data segment 与 host call lowering。`@wasi` 参数和返回使用 WIT type：普通 WIT 名字、`list<T>`、`result<T, E>`、`tuple<A, B, ...>`、`option<T>`、`borrow<T>`、`own<T>`、`_`，以及当前模块中直接声明的 public do 结构体名。do 结构体名在 `@wasi` 签名里只表示 WIT `record` 的本地镜像，字段名、顺序和字段类型必须与目标 WIT record 可验证地一致；它不是新的 WIT 类型声明，也不能用来表达 WIT `resource`、`variant`、`flags` 或 `result`。`@wasi` 只是外部签名声明；标准库面向 do 源码的公开 API 仍应包装成普通 do 类型、结构和错误枚举，例如把 WIT `result<filesize, error-code>` 转成 `usize | FileError` 或更具体的公开函数返回设计，而不是把 WIT `result<...>` 当作普通源码类型到处传播。当前 `do build` 已允许入口模块和递归导入模块中的合法 `@wasi` 声明进入私有 binding manifest，并在 core WAT 中输出 `;; wasi-bind source="entry" alias="name" target="package/interface/member" params="..." result="..."` 或 `;; wasi-bind source="module-path" alias="name" target="package/interface/member" params="..." result="..."` 记录，供后续 component/WIT lowering 消费；`params` 是逗号分隔的 WIT 参数类型文本，空参数写成空字符串，`result` 是单个 WIT 返回类型文本。`source="entry"` 固定表示编译入口模块，导入模块使用解析后的模块路径。`@wasi` alias 仍是模块内局部名字，因此后续 binding generator 必须同时使用 `source + alias` 定位声明，不能只看 `alias`。当前语义层只对已经进入最小 registry 的 WASI target 做精确 `params/result` 校验；如果已知 target 的返回是已登记的 WIT record 镜像，例如 `clocks/system-clock/now -> Datetime`，还会检查 Do struct 字段名、顺序和字段类型；未知 target 只做 WIT 类型语法校验，不能视为可执行绑定。P3 lowering 细节见 `doc/wit/wasi_p3_lowering.md`。`validate_wasi_bind_manifest.mjs --json` 会输出已知 binding 的 `resolved` 和 `shim` 信息；其中 scalar 参数 + scalar 返回、已登记 record 返回、已登记 `list<u8>` 返回或已登记 `descriptor.sync` / `descriptor.write` / `descriptor.read` / `descriptor.link-at` result-area 形态会带 `shim.lowering`，记录 component import 身份、concrete cm32p2 core import、canonical ABI core 参数/返回，以及 Do 结果布局。`--component-plan` 只接受全部已知且可 lower 的 binding，并输出 component builder 可消费的 imports/shims 计划；遇到未知 target 或复杂 WIT 签名会失败。`--wit` 复用同一严格入口，为单个 WIT package 生成 imports world；当前覆盖普通函数 imports 和已登记的 `descriptor.sync` / `descriptor.write` / `descriptor.read` / `descriptor.link-at` resource-method WIT 输出用例；如果输出跨多个 WIT package 或遇到尚未登记的 resource-method 形态，则先失败，直到后续支持目录/package graph 和更多 method 输出。`--core-imports` 也复用同一严格入口，生成去重后的 `cm32p2` core import WAT 片段，用于锁定后续 component builder 要嵌入的导入 ABI。`--core-shims` 在此基础上生成按 `source + alias` 命名的 canonical ABI shim 片段。当前 `do build` 已把已登记的 scalar/record/list<u8> 子集和 `result<_,error-code>` / `result<filesize,error-code>` / `result<tuple<list<u8>,bool>,error-code>` 裸调用接入 direct codegen：scalar result 直接接 core result；`Datetime` 这类 record-result 使用预留 result-area scratch 调用 `cm32p2` import，再按字段 load 成 Do 的 flattened struct 返回；`descriptor.sync` 的 `result<_,error-code>` 允许 statement position 忽略结果，也允许显式多左值读取为 `_, status = host_file_sync(...)`，其中 `status i32 == 0` 表示 ok，非 0 表示 `error-code` 枚举索引加 1；`descriptor.write` 的 `result<filesize,error-code>` 允许 statement position 忽略结果，也允许显式多左值读取为 `written, status = host_file_write(...)`，其中 `written u64` 接收 ok payload，`status i32 == 0` 表示 ok，非 0 表示 `error-code` 枚举索引加 1；`descriptor.read` 的 `result<tuple<list<u8>,bool>,error-code>` 允许显式三左值读取为 `data, done, status = host_file_read(...)`，其中 `data [u8]` 接收 ok payload 的 `list<u8>` 拷贝，`done bool` 接收 ok payload 的 bool，`status i32 == 0` 表示 ok，非 0 表示 `error-code` 枚举索引加 1；`descriptor.link-at` 的 `result<_,error-code>` 允许显式多左值读取为 `_, status = host_file_link_at(old_file, flags, old_path, new_file, new_path)`，两个 WIT `string` 参数接受直接字符串字面量或 Do `text` local/param 并降成 canonical ABI `ptr,len`；`[u8]` 不会被当作 WIT `string`。`status i32 == 0` 表示 ok，非 0 表示 `error-code` 枚举索引加 1；单值绑定、返回位或普通表达式位仍不允许。这个能力不表示所有 WASI 都已可执行；未知 target 或 `result/resource/variant/flags` 等复杂签名在源码直接调用 `@wasi` alias，或经由导入的标准库 wrapper 调用链触达该 alias 时，仍会报 `UnsupportedWasiHostImport`，避免把 WIT resource/result 错误生成为普通 core call。第一版不支持先声明 `#F = (...) -> ...`，再写 `name F = @env("foo")` 或 `name F = @wasi("...")` 这种 host import 缩写。
    补充: 当前 `cm32p2` canonical ABI 下，WIT record 返回值使用间接结果区；例如 `clocks/system-clock/now -> Datetime` 的 core import 形态是 `params = ["i32"], results = []`，由调用方传入结果区指针，再按 Do record layout 读取字段。scalar 返回值仍直接映射到 core result，例如 `u64 -> i64`。当前 build 子集里，非托管结构体参数按字段 flatten，例如 `File{ .id i64 }` 参数降成 `$file.id i64`；单值 union 返回、union 局部和多返回列表中的 union 类型使用统一 payload+tag lowering: 先按分支顺序输出各分支 payload slot, 最后跟一个 `i32` runtime tag；`nil` tag 固定为 0, 非 `nil` 分支按源码分支顺序从 1 开始。标量、错误枚举和 managed storage 分支各占一个 payload slot；非 managed struct 分支按字段 flatten 后占多个 payload slot。例如 `FileError | nil` lowering 为错误 payload 加 tag, `File | FileError` lowering 为 `File.id` payload、错误 payload 和 tag。`@is(value, TypeExpr)` 读取 tag 判断类型分支；`@eq(value, nil)` / `@ne(value, nil)` 读取 tag 判断 `nil` 值分支。显式多返回 `return` 和同 ABI 函数调用透传都按展开后的 ABI slots 对齐。
    补充: `descriptor.drop` 这类 resource-drop 不是 WIT 普通 resource-method 调用；标准库内部可用 `.host_file_drop = @wasi("filesystem/types/descriptor.drop", (descriptor) -> nil)` 表达当前 direct lowering, codegen 生成 `[resource-drop]descriptor` core import。公开 close wrapper 固定为 `close_file(file File) -> nil` / `close_dir(dir Dir) -> nil` 这类显式 cleanup 函数；当前 resource-drop 没有普通错误结果, wrapper 调用后直接 `return`。该能力只表示 direct core import lowering, 不表示完整 component resource lifetime 已完成。
    正例:
    ```do fragment ok
    console_log = @env("console_log", (i32, i32) -> nil)
    file2_stat = @env("file2_stat", (i32) -> i32)

    log_bytes(data [u8]) {
        console_log(data)
        return
    }

    .host_file_sync = @wasi("filesystem/types/descriptor.sync", (descriptor) -> result<_, error-code>)
    .host_file_link = @wasi("filesystem/types/descriptor.link-at", (descriptor, path-flags, text, borrow<descriptor>, text) -> result<_, error-code>)
    ```
    反例:
    ```do fragment err
    set_flag = @env("set_flag", (bool) -> nil)
    is_ready = @env("is_ready", () -> bool)
    log = @env("_log", (i32) -> nil)
    log = @env("log__file", (i32) -> nil)
    log = @env("log_", (i32) -> nil)
    log = @env("log", ([u8]) -> nil)
    pair = @env("pair", () -> i32, i32)
    host_file_read = @wasi("filesystem/types/descriptor.read", (descriptor) -> result<list<u8>>)
    #F = (i32, i32) -> nil
    console_log F = @env("console_log")
    ```
24. 导入函数 alias 携带来源函数签名的参数形状和返回位数；导入多返回函数调用与本地多返回函数调用遵循同一放置规则。
25. 公开内建常量采用前置 `_` 和类型前缀命名：`_i8_max`、`_i8_min`、`_u32_max`、`_usize_max`、`_f32_pi`、`_f64_tau`；不采用 `max_i8`、`pi_f32` 或无 `_` 的常量名。整数边界常量按所有源码基础整数类型补齐 `_type_min/_type_max`；浮点常量第一版只放可用普通十进制字面量稳定表达的数学常量，例如 `_f32_e/_f32_pi/_f32_half_pi/_f32_tau/_f32_sqrt2` 与对应 `f64` 版本，不引入需要科学计数或特殊字面量的 `_f32_max/_f64_inf/_f64_nan`。

26. import 路径段使用 `PathSeg`；路径段由小写字母开头，可含数字，单词之间用单个 `_` 分隔。文件 stem 使用最后一个 `.do/` 作为扩展名边界；`FlatFileSeg` / `DepNameSeg` 中的 `!FileExtSlash` 用于避免把最终 `.do/` 扩展名边界误解析成普通平级分段。只有 `.do/` 结束文件名，`.do.` 仍只是文件名里的普通平级分段。


## 4. 类型系统

本章定义类型位可出现的形态、类型声明、结构体、enum/error enum、union/nil、函数类型边界和类型大小约束。

1. `List/HashMap` 等库类型由 `std` 或用户库定义，并按普通 `StructRefType` 解析；`[u8]` 是 core storage 类型表达式 `[T]` 的具体实例，不是可声明或可导入的命名类型。
2. 只有 `StructDecl` 支持前置 `#T` 声明泛型类型参数；`StructDecl` 的类型参数只表达数据类型，不接受函数类型约束；`EnumDecl` 不支持泛型声明；源码没有顶层类型别名声明。`TypeArgs` 按声明顺序绑定类型参数，数量必须与声明的类型参数数量完全一致；没有前置类型参数的本地 `StructDecl` 不接受 `TypeArgs`。
    ```do program ok
    #T
    #U
    Pair {
        left T
        right U
    }

    test "generic type args arity" {
        p = Pair<i32, bool>{left = 1, right = true}
        return
    }

    User {
        id i32
    }

    test "direct nullable type" {
        u User | nil = nil
        return
    }

    FileError error = NotFound | PermissionDenied
    OrderStatus i8 = OrderCreated(1) | OrderPaid(2)

    test "enum type no type args" {
        err FileError = NotFound
        status OrderStatus = OrderCreated
        return
    }
    ```
    反例:
    ```do program err
    #T
    #U
    Pair {
        left T
        right U
    }

    test "generic type args missing" {
        p = Pair<i32>{left = 1, right = 2}
        return
    }

    test "generic type args extra" {
        p = Pair<i32, bool, i64>{left = 1, right = true}
        return
    }

    User {
        id i32
    }

    test "non generic struct type args" {
        u = User<i32>{id = 1}
        return
    }

    FileError error = NotFound | PermissionDenied
    OrderStatus i8 = OrderCreated(1) | OrderPaid(2)

    test "enum type args" {
        err FileError<i32> = NotFound
        status OrderStatus<i32> = OrderCreated
        return
    }
    ```
3. 普通类型位写类型特征本身，不接受外层无意义括号；写 `x i32`、`f F`、`#F = (i32) -> i32`，不写 `x (i32)`、`f (F)`、`#F = ((i32) -> i32)`。普通固定数据参数使用 `ParamTypeExpr`，可写平铺 union/nullable；变参元素、lambda 参数、`FuncType` 参数和接口约束参数不接收 union/nullable。返回位、字段、局部绑定、storage 元素和 type args 使用 `ValueTypeExpr`。函数类型只在前置类型约束 RHS、绑定函数参数位和接口函数约束参数位使用；源码没有顶层函数类型别名声明，`ValueDecl`、字段、局部绑定、storage 和函数返回位不直接承载函数类型。
   ```do decl ok name=callback_param_only
   #F = (i32) -> i32
   apply(f F) -> i32 {
       return f(1)
   }
   ```
   ```do decl err name=optional_callback_param
   #F = (i32) -> i32
   maybe_apply(f F | nil) -> i32 | nil {
       if @eq(f, nil) return nil
       return f(1)
   }
   ```
   ```do fragment err name=callback_struct_field
   #F = (i32) -> i32
   Handler {
       f F | nil
   }
   ```
4. `TypeArgs` 入口同样写类型特征本身，不接受外层括号分组、匿名函数类型或尾逗号；写 `List<i32>`、`List<i32 | nil>`，不写 `List<(i32)>`、`List<(i32 | nil)>`、`List<() -> i32>` 或 `List<i32,>`。函数类型先用紧贴的 `#F = ...` 约束命名，再在函数参数位直接用 `F`，不要把函数类型放进 `ValueDecl`、字段、局部绑定、storage、type args、union 或函数返回位。
5. `nil` 同时承担值位与签名位语义，但在语法上仍是同一个 token：
   - 值位 `nil`：空值分支，可作为表达式值参与赋值、返回和传给已知 nullable 形参；无目标类型的裸 `nil` 不能作为用户函数实参。
   - `nil` 没有默认类型；`x = nil` 这类无目标类型绑定非法，需写 `x T | nil = nil`，或放在字段、返回、聚合初始化等已知目标类型位置。
   - 联合类型位 `T | nil`：声明可空值分支，`nil` 固定写在 union 末位。它仍是类型表达式，不是 `-> nil` 的缩写。
   - 返回签名位 `-> nil`：声明无返回值上下文。
   - 裸类型位 `nil` 非法；`(nil)` 这种只包一层括号的写法也非法；参数、字段、局部绑定和类型约束不能只写 `nil`。
   - 同一个 union 内 `nil` 分支最多出现一次，必须写在末位，且 union 至少还有一个非 `nil` 分支；`(nil)` 不能当作合法替身。
   - 同一个 union 内所有分支按类型身份唯一；`i32 | i32`、`User | User` 这类重复分支非法；普通类型位不支持外层无意义括号，`(i32) | i32` 直接非法。
   - union 是类似 enum 的平铺类型集合，不做嵌套和展开归一化。已知 nullable/union 类型或绑定为 union 的类型参数，不能再作为另一个 union 的分支写入 `A | B`。需要组合时在目标类型位直接写一个新的平铺 union，例如 `User | FileError | nil`。
   - 普通固定数据参数可写 union/nullable，例如 `emit(value text | nil)`；变参元素、lambda 参数、匿名函数类型参数和接口函数约束参数仍不接收 union/nullable。
   - `()-> T | nil` 返回空分支时必须写 `return nil`；`()-> nil` 可写 `return` 或 `return nil`。
   - 泛型字段需要空分支时，在字段声明位写 `value T | nil`，实例化仍写 `Box<i32>`；构造值可写 `Box<i32>{value = nil}`。
6. 联合返回位要求右侧表达式自身先定型到唯一分支。
7. 结构体值必须有有限静态大小；非空值字段不能形成结构体布局闭环。`T | nil`、`[T]` 和普通索引/id 字段会打断结构体大小依赖；直接字段 `next Node` 或互相嵌套字段 `A.b B` / `B.a A` 不会打断。源码没有顶层类型别名声明，不能通过别名间接打断或隐藏布局闭环。
    ```do decl ok
    Node {
        next Node | nil
    }

    GraphNode {
        next_index usize | nil
    }

    Graph {
        nodes [GraphNode]
    }
    ```
    反例:
    ```do decl err
    Node {
        next Node
    }

    A {
        b B
    }

    B {
        a A
    }
    ```
8. `ErrorEnumDecl` 声明 public 错误枚举，名称使用 `ErrorEnumName`，允许 `CError` 这类一字母前缀名，不支持私有 `.XxxError error = ...` 声明；`ErrorEnumName` 只能用于错误枚举声明，不能用于 `StructDecl` 或 `ValueEnumDecl`；右侧分支使用裸 `EnumBranchName` 值名，例如 `FileError error = FileNotFound | FilePermissionDenied`。错误枚举右侧分支是值，不是类型。
9. `ValueEnumDecl` 声明带整数承载值的 enum，名称使用普通 `DeclTypeName`，承载类型只接收 `BaseIntType`；public value enum 写 `OrderStatus i8 = OrderCreated(1) | OrderPaid(2)`，private value enum 写 `.InternalStatus i8 = Ready(1) | .Hidden(2)`。private value enum 类型和 private enum 分支值只能在当前模块文件内使用，不能导入，也不能通过 import alias 间接导出；同模块内引用 private 类型或 private 分支时使用去点后的实际名，例如 `InternalStatus` 与 `Hidden`。右侧每个分支都必须显式给出整数值，承载值必须落在该 `BaseIntType` 的范围内，且同一 enum 内承载值唯一。enum 分支实际 name 不得与当前可见类型名、enum 类型名、其他 enum 分支名或同类 import alias 重名。
10. enum 类型可出现在类型位、返回位、字段、局部绑定、storage 元素、type args、`is` 目标和函数参数位。enum 分支值只出现在值位，可赋值、返回或用 `eq/ne` 精确比较；源码只写裸 `UpperIdent`，不支持 `Type.Branch` 或其他 `xxx.xxx` 限定名写法（字段路径段除外）。
11. 错误枚举不能聚合已知错误枚举或 enum 类型；例如 `AppError error = FileError | NetworkError` 非法，因为错误枚举右侧只接收分支值。源码没有顶层类型别名声明。需要组合多个错误来源时，在返回、字段、局部绑定、普通固定数据参数或 storage/type args 里直接写具体来源，例如 `[u8] | FileError | NetworkError`。
12. 源码类型位不能直接写合成 `Error`；返回、字段、局部绑定、type args、storage 元素和类型约束都使用具体错误枚举类型。Primitive trap / safety failure 不属于 `Error`，不能通过返回 `Error` 捕获。
13. public enum 分支值是可导入的 public 值；private enum 分支值只能在声明所在模块文件内使用。跨文件构造或精确比较 public 分支值时导入该分支值。enum 分支值导入时可以改名以避免冲突，本地 alias 仍写 `UpperImportName`，但 alias 不能使用 `*Error` 后缀；例如 `FileMissing = @lib("fs.do", FileNotFound)` 合法，`file_missing = @lib("fs.do", FileNotFound)` 与 `FileNotFoundError = @lib("fs.do", FileNotFound)` 非法。
14. union 不做展开规范化，也不能嵌套。源码没有顶层类型别名声明。需要组合类型时，在返回、字段、局部绑定、普通固定数据参数、storage 元素或 type args 里直接写平铺 union；需要给外部声明改名时，只能在 import 左侧直接改名；需要 `UserId` 与 `OrderId` 这类强类型时，用单字段 struct 等显式数据结构表达。源码直接写出的重复分支仍非法，例如 `User | User`、`User | nil | nil` 非法。
    ```do program ok
    // user.do
    User {
        id i32
    }

    // main.do
    Profile = @lib("./user.do", User)
    load() -> Profile | nil {
        return nil
    }
    ```
    上例合法；type import alias 可以直接参与返回、字段、局部绑定、storage 元素和 type args 里的 union。如果想给外部声明换名，必须在 import 左侧直接给出最终名字。

15. 泛型结构体声明的每个类型参数至少出现在一个字段类型里；不支持没有字段承载的 phantom type 参数。能力约束放在使用该类型的函数上。


## 5. 表达式、字面量与定型

本章定义值表达式、字面量、聚合构造、字段默认值和定型来源。调用定型和 lambda 目标匹配见函数章节。

1. 算术、比较和逻辑组合使用函数或 `builtin` 判断族表达。
2. 字面量无默认类型，由上下文唯一定型或显式类型标注。
3. `TypedAggLit` 只按结构体字段构造解释；`InferredAggLit` 在目标为结构体时使用字段构造，在目标为 `[T]` 时可使用元素构造（例如 `.{1, 2, 3}`）。
4. 显式标量类型通过绑定位、参数位、返回位或已知目标上下文提供。
5. 无上下文或多重解释冲突时报编译错误。
6. 定型来源只有两类：左侧或外层上下文提供已知目标类型，或右侧表达式自身能唯一推出类型。
7. 普通字符串和行字符串默认定型为 `text`；在 `[u8]` 目标上下文中可定型为 UTF-8 字节序列。build lowering 已覆盖普通字符串字面量在 `text` 绑定位、函数参数位和返回位的 ARC storage handle 生成。
8. 普通字符串和行字符串都表示 UTF-8 文本；普通字符串支持 `\xNN` 等转义，但 escape 解码后必须形成有效 UTF-8；行字符串按源码文本保留且不解释转义。若目标类型为 `[u8]`，同一字面量按 UTF-8 字节序列使用。非 UTF-8 原始字节使用 `[u8]` 聚合表达。行字符串只在表达式根位使用；调用参数或聚合元素需要先绑定再引用。
9. 裸 `{...}` 不是表达式；聚合值写成 `.{...}` 或 `Type{...}`。
10. `.{...}` 省略目标聚合类型，由左侧标注、既有绑定、参数或返回上下文唯一确定。
11. `Type{...}` 在右侧显式给出聚合类型，可用于创建新绑定。
12. `name Type = .{...}` 与 `name = Type{...}` 是等价的创建形式。
13. `Type{...}` 的 `Type` 是具名类型及其类型参数；泛型结构体的 typed constructor 必须写完整 `TypeArgs`。若左侧或外层已有目标类型，可用 `.{...}` 省略整个目标聚合类型；不能写裸泛型名 `Box{...}` 再由目标类型反推 `Box<i32>`。
    ```do program ok
    #T
    Box {
        value T
    }

    test "generic struct ctor forms" {
        b1 = Box<i32>{value = 1}
        b2 Box<i32> = Box<i32>{value = 1}
        b3 Box<i32> = .{value = 1}
        return
    }
    ```
    反例:
    ```do program err
    #T
    Box {
        value T
    }

    test "generic struct ctor missing type args" {
        b Box<i32> = Box{value = 1}
        return
    }
    ```
14. 结构体字段声明位的 `.field` 表示私有；字段真实名字仍是 `field`，同一结构体内同一字段写作 `field` 或 `.field`。
15. 当前模块内构造结构体时，字段初始化使用裸字段名 `field = value`；即使字段声明为 private，构造项也不写 `.field = value`；`.field` 只出现在路径位或声明位。
16. 外部模块构造 public struct 时只填写 public 字段，不能读取、写入或显式初始化 private 字段的实际 name。若 public struct 含任意无默认值 private 字段，外部模块不能用 `Type{...}` 或目标类型已知的 `.{...}` 构造该类型，只能通过定义模块提供的函数获得值；例如 `File { .id i64 }` 这类资源句柄必须由 `open_file(path)` 或同模块构造函数桥接。若所有 private 字段都有默认值，外部可以只填写 public 字段构造，private 字段使用定义模块给出的默认值；但外部仍不能写 `token = ...` 这类 private 字段实际名。字段默认值由定义模块负责维护，不暴露 private 字段写权限。`List/HashMap` 这类普通容器若要禁止外部直接构造，应至少保留一个无默认值 private 字段，并通过 `empty_list(seed)`、`list_from_items(data)`、`empty_hash_map(key, value)`、`hash_map_from_parts(keys, values)` 这类 public API 构造。
17. `TypedAggLit` 的 body 只接受字段项；`InferredAggLit` 可接受字段项或元素项，元素项仅在目标上下文为 `[T]` 时成立。
18. 同一个聚合字面量 body 内字段项和元素项不得混用；`.{a = 1, 2}` 非法。
19. 结构体字段构造使用 `field = value`。
    字段初始化名、`=` 和普通表达式起点保持在同一字段初始化项里；字段名和 `=` 之间不能换行，`=` 后的普通表达式也不能换行。
20. 字段默认值在结构体构造时求值；默认表达式结果类型与字段类型一致。
21. 结构体构造发生在 CTFE 上下文时，字段默认值也走 CTFE；运行时构造可执行运行时默认表达式。
22. 源码层大写 `Tuple<T0, T1, ...>` 是编译器内建泛型类型, 不是用户可重定义的普通结构体名。`Tuple` 进入保留内建类型集合, 不能再被普通类型声明或 import alias 占用。小写 `tuple<...>` 只保留给 WIT / `@wasi` 签名, 不能出现在普通源码类型位; 误用报 `InvalidTypeRef`。
23. `Tuple` 第一版规则:
    - arity 下限为 2, 当前不设上限; `Tuple<>` / `Tuple<T>` 报 `InvalidTypeRef`。
    - 构造固定为位置构造器 `Tuple<T0, T1, ...>{v0, v1, ...}`, 实参数量必须与 arity 完全一致; 不匹配报 `InvalidTypedLiteral`。命名字段构造 `Tuple<...>{v0 = ...}` 第一版不支持, 当前前端可在 parser 阶段报 `InvalidStructLiteral`。
    - 读取固定为 `@get(tuple_value, <compile-time-int>)`, 索引必须是编译期整数字面量且落在 `0..arity-1`; 越界或非字面量索引报 `InvalidPathIndex`。第一版不支持 `.v0/.v1` 字段段访问, 也不支持 `@set(tuple_value, <index>, value)` 数字索引写入。
    - 允许嵌套 `Tuple<Tuple<i32, bool>, u8>`, 以及作为局部绑定、参数、单返回、struct 字段和标量叶子 `[Tuple<...>]` storage 元素。
    - 标量叶子 storage 采用内联 pack (scheme A): 元素按叶子 payload 连续写入 storage data, 不是 managed handle。
    - 当前后置边界: managed payload 叶子的 storage、`text` 等 managed 叶子 storage、`@get(storage, i, j)` path chaining, 以及 `loop v, i = items { @get(v, 0) }` 对 loop 绑定的数字索引读取; 这些边界当前仍报 `NoMatchingCall`。
    - 元素类型不匹配的位置构造当前仍可能落到 `NoMatchingCall`; 后续可收敛为更精确的类型诊断。

## 6. 绑定、赋值与作用域

本章定义局部绑定、只读绑定、丢弃位、参数和 loop 绑定的读写规则，以及模块级值的读写边界。

1. 赋值左侧先查最近可见绑定；命中则更新，未命中则创建。
2. 未命中时创建新绑定，右侧表达式已经能唯一确定类型；新绑定创建使用已定型右侧表达式，`.{...}` 在存在目标类型上下文时使用。
3. 命中已有绑定时，既有绑定类型为右侧表达式提供目标上下文，例如 `y = 3` 中 `3` 由 `y` 的类型定型。若该绑定在当前控制流路径上已有收窄类型，赋值会清除旧收窄，并按右侧表达式在既有声明类型内重新确定当前静态类型。
4. 绑定与赋值规则作用于块内局部绑定，以及当前可见的模块级可变变量和它们的 value import alias；顶层常量仍只作为只读数据声明，不绑定函数值。
5. 局部绑定名使用非保留 `LowerIdent` 或 `ReadonlyIdent`；`LowerIdent` 绑定名不得使用任何 `ReservedName`，也不得与当前可见普通函数族名、函数 import alias 或 host import alias 同名。`ReadonlyIdent` 不用于函数名，且其主体不参与 `ReservedName` 排除；`_if`、`_add`、`_bool` 这类只读绑定合法，`_Error` 非法。`UpperIdent` 用于类型名、类型参数名、enum 分支值和同类 import alias。
6. `UpperValueExpr` 只接收 `EnumBranchName` 形态；最终符号类别由语义阶段解析，值位只允许解析为已声明或已导入的 enum 分支值，普通类型名不得作为值表达式。
   ```do decl err
   User {
       id i32
   }

   NotFound = User | nil

   load() -> NotFound {
       return nil
   }

   bad() -> NotFound {
       return NotFound
   }
   ```
7. `TypedBind` 永远声明新绑定；如果同名绑定已可见，编译器报告重复声明或遮蔽错误。局部 `TypedBind` 只承载普通数据类型，不接收函数类型；即使通过 `F`、`Callback` 等名字展开后命中函数类型，也同样非法。
8. 局部声明绑定（如 `TypedBind`）不得遮蔽外层可见绑定；顶层常量、模块级可变变量以及它们各自的 import alias 都算外层可见绑定，局部 `TypedBind` 不能用同名 `_name` 或同名 `LowerIdent` 重新声明。函数参数、lambda 参数和 loop 绑定位同样不得遮蔽外层可见绑定；同一参数列表和同一 loop 头内也不得重复使用同名非 `_` 绑定。源码里不存在“最近作用域同名优先”规则。
9. 局部 `_name` 是运行期只读绑定；首次绑定满足普通定型规则。
10. `_name` 首次绑定后保持只读。
11. `_name = expr` 形式在 `_name` 未命中可见绑定时创建只读绑定；创建前同样不得遮蔽外层可见绑定。若已命中既有 `_name`，则按只读重赋值报错；命中顶层 `ValueDecl` 或 readonly import alias 时也按只读重赋值报错，不创建新的局部 `_name`。
12. 只读绑定的“首次绑定或重赋值”由语义阶段根据当前作用域符号表判定，不由 PEG 拆分。
13. 命中当前可见模块级可变变量或其 value import alias 时，赋值直接更新对应模块存储，不创建新的局部绑定。通过 import 引入的模块级可变变量同样按原存储读写。
14. `_` 为丢弃位；在赋值左侧通过 `DiscardTarget` 出现，在 loop 绑定位按 loop 语法出现；函数参数和 lambda 参数不能使用 `_`。`_` 不进入 `BindName`、`ParamName` 或 `ExprIdent`，不创建绑定，不能作为值表达式读取，也不能 `return _`。多个 `_` 彼此独立，只表示逐位丢弃。
15. 局部绑定采用块作用域；`if`、`loop`、lambda 体内创建的绑定只在该块内可见。
16. 函数参数是可写本地绑定；命中后赋值会更新当前参数绑定，不创建新的局部绑定。`loop` 头部绑定是只读循环绑定，循环体内不能给该绑定赋值；需要修改元素时更新源集合，或先声明新的局部绑定承接计算结果。`_name` 仍是只读绑定；参数名和 loop 绑定位不能写 `_name`。lambda 参数不支持 `_name`，并按 lambda 当前支持的函数体子集处理。
   ```do decl ok
   make() -> i32 {
       return 1
   }

   pair() -> i32, bool {
       return 1, true
   }

   use() {
       _ = make()
       _, _ = pair()
       return
   }
   ```
   反例:
   ```do decl err
   make() -> i32 {
       return 1
   }

   bad() -> i32 {
       _ = make()
       return _
   }
   ```
17. 函数参数和 lambda 参数必须使用 `LowerIdent`，不能使用 `_` 丢弃参数，也不能使用 `_name` 这类 `ReadonlyIdent`；参数名不得与当前可见普通函数族名、函数 import alias 或 host import alias 同名。
   ```do decl ok
   use(x i32) -> i32 {
       return x
   }
   ```
   反例:
   ```do fragment err
   use(_x i32) -> i32 {
       return _x
   }

   result = map(xs, (_x i32) -> i32 => _x)
   ```
18. loop 绑定位使用 `LowerIdent` 或 `_`，不能使用 `_name` 这类 `ReadonlyIdent`；非 `_` 的 loop 绑定名不得与当前可见普通函数族名、函数 import alias 或 host import alias 同名；`_name` 用于顶层常量和局部只读绑定。
   ```do stmt ok
   loop value, index = xs {
       consume(index, value)
   }
   ```
   反例:
   ```do stmt err
   loop _value, _index = xs {
       consume(_index, _value)
   }
   ```
19. 顶层 `ValueDecl` 分两类: `ReadonlyIdent` 顶层常量和模块级可变变量。模块级可变变量声明位可写 public `LowerIdent` 或 private `DotLowerIdent`；private 只影响导入可见性，声明后的实际 name 去点，同模块内读写不写点。顶层值都必须显式写类型标注；写 `_name Type = expr`、`name Type = expr` 或 `.name Type = expr`，不支持由 RHS 反推顶层值类型。
20. `ReadonlyIdent` 顶层常量可出现在值表达式位，但不可被重新赋值；模块级可变变量在其可见范围内可被赋值。`ReadonlyIdent` 主体不参与 `ReservedName` 排除，因此 `_if`、`_add`、`_bool` 这类顶层常量名也合法；`_Error` 不是合法 `ReadonlyIdent`。public 模块级可变变量使用普通非保留 `LowerIdent`，private 模块级可变变量在声明位使用非保留 `DotLowerIdent`，使用位仍写去点后的普通 `LowerIdent`。
21. 函数参数的 ownership 进入函数体后按本地绑定处理, 但其来源事实标记为 `param_or_import`。参数可以被重新赋值; 对 managed 参数重新赋值时, 旧参数 handle 必须先按当前本地绑定释放, 新值接管该参数名。调用点按 caller 侧 liveness 决定传参 ownership: 如果实参是 managed local 且调用后不再使用, 可作为 last-use move 传入并清零 caller source; 如果 caller 后续仍使用该实参, 调用前必须 copy/inc。callee 不能因为参数在本函数体内语法末次使用就把 caller 仍可能持有的结构体字段或共享来源字段 move 出去; 参数字段读取保持 copy/inc, 除非未来有更强的跨函数唯一性证明。`loop` 头部绑定不参与这条参数可写规则, 仍是只读循环绑定。

## 7. 函数、调用、重载与返回

本章定义普通函数、函数名值位、lambda、调用定型、重载、不定参数、spread、表达式语句和返回/多返回规则。

1. `LambdaExpr` 只出现在普通调用实参位，以及 PEG 明确列出的 primitive value 位，例如 `@set(target, path..., lambda)` 的最终 value 位；语法形如 `(x i32) => @add(x, 1)`、`(x i32) -> i32 => @add(x, 1)`、`(x i32) -> i32 { ... }`，以及目标返回类型已知为 `nil` 时的省略写法 `(x i32) { ... }`。
2. `LambdaExpr` 可读取顶层常量、可读写当前可见的模块级可变变量，并可调用当前可见函数；它不形成闭包，不能捕获外层局部绑定，也不能绑定到变量或作为值返回。访问模块级名字不算捕获。
3. 顶层函数的 `=>` 函数体是函数声明短写，不是 `LambdaExpr`，不产生可传递函数值。
4. 函数名可在已有目标 `FuncType` 的值位作为函数值传递，仅用于高阶函数实参。
5. lambda 参数类型可省略；省略时必须由已选调用候选的目标 `FuncType` 提供参数类型，不能由 lambda body 反推。
6. lambda 返回类型可省略；省略时要求目标 `FuncType` 的返回类型已经完全确定，并在调用候选已选定、参数类型已确定后由 lambda body 检查是否匹配该返回类型；lambda body 不能绑定目标函数类型里的泛型返回参数。若目标返回类型确定为 `nil`，块体 lambda 可进一步省略 `-> nil`，直接写成 `(x T) { ... }`。
7. 块体 lambda 内的 `return` 只返回当前 lambda，不返回外层函数或测试体。
8. 调用表达式的 callee 只接受 `LowerIdent`；函数声明名、函数 import alias 和 host import alias 也使用 `LowerIdent`，私有函数调用时去掉声明位的前置 `.`。语义上，callee 必须解析为当前可见函数族名字、当前可见 host import alias，或当前静态类型已经确定为命名函数类型 `F` 的局部名；局部绑定名、函数参数名、lambda 参数名和 loop 绑定位不得与当前可见普通函数族名、函数 import alias 或 host import alias 同名，因此 callee 不存在“局部函数值”和“顶层可调用 lower 符号”同名优先级规则。函数类型约束必须作为单一形参类型 `F` 使用，不支持 `F | nil` 形参或可选回调 callee 规则；需要回调时直接传入已定型为 `F` 的函数值。例如 `.double(...)` 是声明写法，调用写 `double(...)`；`.double(...)` 调用非法。host import alias 只支持这种直接调用形态，不进入普通函数值解析。
9. 函数族唯一性由去掉声明位前置 `.` 后的函数名与参数类型序列决定；返回类型不参与重载身份，不能通过不同返回类型构成重载；普通函数重载只在当前模块的普通函数声明之间形成。同一实际函数名不能混合 public 与 private overload；若存在 `convert(...)`，就不能再声明 `.convert(...)`，反之亦然。带接口函数签名约束 `#name(...) -> Return` 的接口函数不参与普通函数重载，也不和其他接口函数彼此重载；接口函数的实际函数名在当前模块内必须唯一，不能和普通函数声明、函数 import alias 或 host import alias 共用同名。函数 import alias 不参与本地重载拼装；`alias = @lib("./file.do", name)` 绑定的是目标模块里实际函数名 `name` 对应的 public 普通函数族，它可以是单个声明，也可以是目标模块内已经存在的同名 public 普通重载族，但不包含目标模块内同名 private overload 或同名接口函数。但同一个 alias 仍只能指向一个来源模块里的这一个实际函数名，不能靠多个 import 把不同来源或不同实际名字的人为拼成同名重载族。函数 import alias 也不能和当前模块的普通函数声明同名共存；若需要同时保留两者，必须改其中一方的名字。host import alias 同样不能和当前模块的普通函数声明、函数 import alias 或其他 host import alias 同名共存。同一实际函数名配合同一参数类型序列对应唯一定义。普通固定数据参数使用 `ParamTypeExpr`，可写平铺 union/nullable；变参元素、函数类型约束参数和接口约束参数仍不接收 union/nullable。enum 类型是普通参数类型，可参与重载；enum 分支值不是类型，不能写在参数类型位。调用时只按实参的静态参数类型序列精确选择，不做 nullable/union 包含关系扩展。
    ```do program ok
    pick(x i32) -> i32 {
        return x
    }

    pick(x i64) -> i64 {
        return x
    }

    test "overload by input type" {
        a i32 = 1
        b = pick(a)
        return
    }

    to_json(user User) -> [u8] {
        return "{}"
    }

    to_json(game Game) -> [u8] {
        return "{}"
    }

    // ops.do
    format(x i32) -> [u8] {
        return "i32"
    }

    format(x i64) -> [u8] {
        return "i64"
    }

    // main.do
    format = @lib("./ops.do", format)

    show_i32(x i32) -> [u8] {
        return format(x)
    }
    ```
    反例:
    ```do program err
    pick(x i32) -> i32 {
        return x
    }

    pick(x i32) -> bool {
        return @gt(x, 0)
    }

    test "return type is not overload key" {
        v = pick(1)
        return
    }

    from_json(bytes [u8]) -> User {
        return User{}
    }

    from_json(bytes [u8]) -> Game {
        return Game{}
    }

    format_i32 = @lib("./ops_i32.do", format)
    format_i32 = @lib("./ops_i64.do", format)

    clamp_i32 = @lib("./math_i32.do", clamp_i32)
    clamp_i64 = @lib("./math_i64.do", clamp_i64)

    clamp_i32 = @lib("./math_i32.do", clamp_i32)
    clamp_i64(x i64, low i64, high i64) -> i64 {
        if @lt(x, low) return low
        if @gt(x, high) return high
        return x
    }

    FileError error = FileNotFound | FilePermissionDenied
    NetworkError error = NetworkTimeout | NetworkClosed

    handle(err FileError) -> [u8] {
        return "file"
    }

    handle(err NetworkError) -> [u8] {
        return "network"
    }
    ```
    推荐:
    ```do decl ok
    #T
    from_json(bytes [u8]) -> T | JsonError {
        return .{}
    }

    read_user(bytes [u8]) -> User | JsonError {
        return from_json<User>(bytes)
    }
    ```
    `to_json(User) -> [u8]` / `to_json(Game) -> [u8]` 这类接口已经可以靠参数重载表达；真正想借返回类型区分的通常只有 `from_json([u8]) -> User` / `from_json([u8]) -> Game` 这类同输入不同输出接口。规范仍不让返回值参与重载，也不靠左侧目标类型反推普通调用；这类泛型解码入口应写成单个 `#T from_json(bytes [u8]) -> T | JsonError`，调用点用显式类型实参 `from_json<User>(bytes)` 绑定 `T`。这样目标类型仍在调用表达式内可见，不把 `x = from_json(text)`、`save(from_json(text))`、`return from_json(text)` 这类调用扩展成上下文敏感候选选择。
10. 不定参数参与函数族唯一性；`rest ...T` 的签名尾部记作 `...T`，不同于单个 `T`。
11. 重载调用先让输入实参定型，再用实参的静态参数类型序列精确挑选候选；参数类型必须完全一致才匹配，不按 union/nullable 包含关系扩展候选。同名同 arity 下，具体参数签名与泛型 fallback 可以共存；存在精确具体签名时优先选择具体签名，只有没有具体匹配时才实例化泛型 fallback。两个泛型声明若同名且同 arity，直接视为重复或歧义并在声明期拒绝。
12. 若函数名与参数个数只对应唯一候选，该候选的参数类型可为实参字面量提供上下文。
13. 若存在多个同名同参数个数候选，实参必须先各自定型，再用实参静态类型序列选择唯一候选；`User | nil` 静态值只匹配同样写作 `User | nil` 的形参，不会因为包含 `User` 分支而匹配 `User` 形参。若函数需要处理可空或结果集合，要么声明同形状 union/nullable 形参，要么在调用前用 `is/eq/ne` 收窄到单一类型。
14. 外层期望类型只用于检查已选中调用的返回值类型；返回类型不参与候选选择，重载选择只看实参静态类型序列。`nil` 字面量只能传给唯一候选中目标类型已知为 nullable 的形参；无目标或候选不唯一时不能靠裸 `nil` 反推。运行期调用先完成调用目标解析和候选选择，再按源码从左到右求值实参表达式；`...rest` 在其源码位置求值并展开；普通函数调用、函数类型值调用和 host import 调用都遵守同一顺序。
15. lambda 实参参与重载选择时，只提供参数个数、显式参数类型和显式返回类型；lambda body 不参与重载候选选择。
16. 调用候选唯一确定后，lambda body 才进入类型检查；省略的 lambda 参数类型从目标 `FuncType` 补齐。省略的 lambda 返回类型只在目标返回类型已经完全确定时可由 body 检查推出；若省略返回类型会绑定目标函数类型中的泛型返回参数，必须显式写 `-> Return`。
17. 不定参数候选匹配固定前缀实参数量后，剩余实参逐个按 `...T` 的 `T` 定型；`rest ...T` 接收 0 个或多个尾部实参，函数体内的 `rest` 绑定类型为 `[T]`；第一版只支持同类型不定参数。同名函数族中固定 arity 候选和不定参数候选同时匹配时，固定 arity 候选优先；多个不定参数候选同时匹配时，固定前缀更长的候选优先。同名不定参数声明若固定前缀长度和参数类型序列相同，则签名重复，声明非法；返回类型不参与区分。
   变参元素类型同样属于参数位，实际类型不得是 union/nullable；`collect(rest ...User | nil)` 非法。若 `...F` 中的 `F` 解析为函数类型约束名，语法可进入 `VariadicElemType` 的名字分支，但语义上会形成 `[F]` rest 绑定；由于函数类型不能作为 storage 元素类型，该声明按 storage/function-type 规则拒绝，不为变参入口额外设计特判。接口约束里的变参元素复用同一参数位规则。
18. `...expr` 只在函数调用实参位生效，只能出现在实参列表最后，一次调用最多一个展开。
19. `...expr` 的表达式必须定型为 `[T]` 或库定义同类型连续序列，且目标函数的对应实参位必须落在 `...T` 尾部；固定参数、host import 固定 ABI 参数和非变参 import 目标都不能接收展开实参。`@add/@sub/@mul/@div/@rem` 的 core 原始数值调用接收尾部展开时，展开前必须已有两个固定实参；这些 core 名不接受用户或标准库补充的同名变参重载。非 core 普通变参函数仍按普通变参规则匹配。
20. 展开调用只匹配被调函数最后一个不定参数位；展开后不能再接普通实参。
21. 不定参数声明写作 `rest ...T`，只能出现在函数参数列表最后，且一个函数最多一个不定参数。
22. 不定参数在函数体内的绑定类型是 `[T]`，可为空，可用于 `loop` 或在调用尾部写作 `...rest` 转发。
23. lambda 参数不支持不定参数；host import 参数不支持不定参数。
24. 函数名在值位解析为函数值时，必须由上下文提供目标 `FuncType`；调用位仍只接受裸 `LowerIdent(...)`，不支持任意表达式直接作 callee。上下文目标类型必须是命名函数类型 `F`，不能是 nullable/union。候选集合同时包含当前文件可见函数和已导入函数族，并按函数名加参数类型序列选择唯一声明。host import alias 不进入这里的函数名值位候选集合，只支持直接调用。目标 `FuncType` 含未绑定类型参数时，函数名实参可按唯一候选的参数类型与返回类型绑定这些类型参数；同一调用的多个函数名实参按实参顺序从左到右绑定，任一步无法唯一选择或产生冲突都报告 `NoMatchingCall`。
25. lambda 参数省略类型时，必须先由函数名、实参数量、非 lambda 实参、lambda 显式签名或唯一候选确定目标 `FuncType`；目标类型必须是命名函数类型 `F`，不能是 nullable/union。lambda body 只用于检查返回值，不参与参数类型反推。
26. lambda 返回类型省略时，只允许目标函数类型的返回类型已经完全确定；body 只用于检查该确定返回类型。若省略返回类型会绑定目标函数类型中的泛型返回参数，必须显式写 `-> Return`；lambda body 不参与重载候选选择或泛型返回求解。
27. 块体 lambda 拥有独立返回边界；其 `return` 只结束当前 lambda 调用。
28. 函数名值位若缺少目标 `FuncType`（例如 `f = inc`），无论该名字是否只有一个候选，都报告 `NoMatchingCall`。
29. 函数名值位若目标 `FuncType` 不唯一（例如 `use(inc)` 且 `use` 自身重载且都可接收函数参数），报告 `NoMatchingCall`。

30. `return` 位数与类型匹配函数返回签名。
31. 任何已选中签名为多返回的直接 `CallExpr` 都只能作为多左值赋值的完整右侧，或作为同位数函数的完整返回透传位；完整返回透传位包括块体函数里的 `return other()`，以及表达式体函数或 lambda 里的 `=> other()` 唯一根表达式。这包括本地普通函数、导入普通函数族、当前静态类型已收窄为命名函数类型的函数值 callee，以及后续版本可能加入的多返回 special form。该位置的根表达式必须是直接调用，且返回位数与目标位数一致；外层括号不视为“直接调用”，因此 `return (pair())`、`a, b = (pair())`、`=> (pair())` 这类写法也非法。`=> other(), x` 不是完整透传位，而是普通返回列表，`other()` 不能在其中展开。
32. 多返回调用不能出现在单变量赋值右侧、普通调用实参、聚合元素、嵌套表达式或 `if/loop` 条件位；先显式拆分，再把单个值放入这些位置。
33. 多返回函数内写 `return a, b` 时，逗号分隔的是当前函数要返回的多个单值；写 `return other()` 时，`other()` 必须是等位数多返回调用。`return` 与 `=>` 的返回列表都使用同一行内逗号分隔，不接受逗号换行或尾逗号；写 `return a, b`、`pair() -> i32, bool => a, b`，不写 `return a,\n b`、`pair() -> i32, bool => a,\n b` 或 `return a, b,`。`return` 位置不直接接收行字符串；需要返回行字符串内容时，先把行字符串绑定到局部值，再返回该绑定。
34. 多返回签名按顶层逗号分隔；每个返回项各自是完整 `ValueTypeExpr`，返回项内部可以包含联合类型。返回签名不接受尾逗号；写 `-> A, B`，不写 `-> A, B,`。返回项不接收函数类型；即使函数类型已命名为 `F`，也不能写 `-> F` 或 `-> T | F`。
35. `FuncType` 中一旦匹配到 `->`，`->` 后的顶层逗号归属 `InlineReturnSpec`，用于分隔返回项；返回项内部的 `|` 仍归属该返回项的 `InlineValueTypeExpr`。例如 `() -> i8, bool | i32` 表示返回两个值：`i8` 与 `bool | i32`。
36. 匿名函数类型只作为函数前置类型约束局部名使用；`#F = (...) -> ...` 绑定紧随其后的一个函数，不会进入顶层类型名字空间，也不能从其他文件 import 函数类型名字。函数参数中的函数类型只允许写成紧贴约束块声明的 `F`；`F | nil`、`F | i32`、`T | F` 这类 nullable/union 参数都非法。`ValueDecl`、字段、局部绑定、storage 元素、type args 与函数返回位不直接承载函数类型。匿名函数类型不能直接作为外层 union 分支。需要可选回调时用普通数据状态字段或调用方分支控制是否传入回调，不通过函数参数位的 `F | nil` 或函数字段表达。
37. 表达式体函数与块体函数都遵循同一返回匹配规则。
38. `nil` 返回上下文允许 `return` 与 `return nil` 等价。
39. `-> T | nil` 的函数在返回 `nil` 分支时必须显式写 `return nil`；裸 `return` 只适用于 `-> nil` 返回上下文。
40. 本地普通函数可省略返回类型；省略时等价并规范化为 `-> nil`。
41. host import、接口约束和其他显式签名位置都要求显式返回类型。
42. 省略返回类型的表达式体函数仍按 `-> nil` 检查，右侧若产生非 `nil` 值则报错。
43. 普通函数声明有显式返回类型时必须写 `->`；`f() T { ... }` 和 `f() T => expr` 这类 no-arrow 返回写法非法。
    ```do decl ok
    inc(x i32) -> i32 {
        return @add(x, 1)
    }

    ready() -> bool => true
    ```
    反例:
    ```do fragment err
    inc_bad(x i32) i32 => @add(x, 1)

    ready_bad() bool {
        return true
    }
    ```

44. 表达式语句只接收普通 `CallExpr`，并且选中的调用返回必须是 `-> nil`；有返回值的表达式必须绑定、赋值、返回或在多左值中显式丢弃，不能作为表达式语句静默丢弃。
45. 普通函数允许直接递归和互递归；顶层函数收集先完成名字和签名建表，再进入函数体检查，因此 `countdown(...)` / `is_even(...)` / `is_odd(...)` 这类同模块普通递归调用合法。递归调用仍按普通重载规则选候选，命中错误签名时报告 `NoMatchingCall`。泛型递归当前只支持不依赖返回上下文反推的形态，例如参数侧已经有已知 concrete type 的调用，像 `seed i32 = 9; generic_countdown(2, seed)`。仅靠左侧目标类型反推 direct type param 的写法，例如 `out i32 = generic_countdown(2, 9)`，当前仍按 `NoMatchingCall` 边界拒绝；后续若要放开，必须先明确是否允许返回上下文参与这类 direct type param 推导。
46. self-tail TCO 第一版只优化可证明的 `return self(new_args)` 形态到参数重赋值 + loop continue, 不依赖 Wasm tail-call proposal, 也不承诺 mutual/general TCO。当前已覆盖 scalar、`if/else`、guard、generic 与 imported self-tail path。遇到 `defer`、storage local、managed struct、多返回、`if/else` 分支 + `defer` 或 guard + `defer` 时, 第一版明确不优化, 仍按普通递归 call 生成。

## 8. 泛型与接口约束

本章定义结构体泛型、函数前置约束块、函数类型约束、接口函数约束和泛型求解规则。

1. 类型声明与 type import alias 按去掉声明位前置 `.` 后的实际 name 唯一；例如 `.InternalUser` 与 `InternalUser` 不能同时作为类型名出现。函数或结构体前置约束块里的局部约束名共享一个局部名字空间；同一约束块内不得重复声明同名 `#T` 或 `#F = ...`，也不得和当前可见的类型声明名、错误枚举类型名、type import alias 或枚举分支值同名。约束块局部名不提供遮蔽规则；需要泛型类型参数时使用不冲突的 `T/U/F/Q` 这类局部名。
2. 只有 `StructDecl` 支持前置 `#T` 声明泛型类型参数；`StructDecl` 的类型参数只表达数据类型，不接受函数类型约束；`EnumDecl` 不支持泛型声明；源码没有顶层类型别名声明。`TypeArgs` 按声明顺序绑定类型参数，数量必须与声明的类型参数数量完全一致；没有前置类型参数的本地 `StructDecl` 不接受 `TypeArgs`。
    ```do program ok
    #T
    #U
    Pair {
        left T
        right U
    }

    test "generic type args arity" {
        p = Pair<i32, bool>{left = 1, right = true}
        return
    }

    User {
        id i32
    }

    test "direct nullable type" {
        u User | nil = nil
        return
    }

    FileError error = NotFound | PermissionDenied
    OrderStatus i8 = OrderCreated(1) | OrderPaid(2)

    test "enum type no type args" {
        err FileError = NotFound
        status OrderStatus = OrderCreated
        return
    }
    ```
    反例:
    ```do program err
    #T
    #U
    Pair {
        left T
        right U
    }

    test "generic type args missing" {
        p = Pair<i32>{left = 1, right = 2}
        return
    }

    test "generic type args extra" {
        p = Pair<i32, bool, i64>{left = 1, right = true}
        return
    }

    User {
        id i32
    }

    test "non generic struct type args" {
        u = User<i32>{id = 1}
        return
    }

    FileError error = NotFound | PermissionDenied
    OrderStatus i8 = OrderCreated(1) | OrderPaid(2)

    test "enum type args" {
        err FileError<i32> = NotFound
        status OrderStatus<i32> = OrderCreated
        return
    }
    ```
```do decl ok name=callback_param_only
#F = (i32) -> i32
apply(f F) -> i32 {
    return f(1)
}
```
```do decl err name=optional_callback_param
#F = (i32) -> i32
maybe_apply(f F | nil) -> i32 | nil {
    if @eq(f, nil) return nil
    return f(1)
}
```
```do fragment err name=callback_struct_field
#F = (i32) -> i32
Handler {
    f F | nil
}
```
3. `#T` 是普通数据类型参数声明，只声明未知数据类型参数名，不提供能力约束；普通类型参数的实际绑定结果必须是数据类型，不能是 `#F = FuncType` 声明出的函数类型，也不能是接口约束本身。当前不支持受限数据类型参数或派生候选集合；需要具体 union 时，直接在返回位、字段、局部绑定、storage 元素或 type args 里写平铺 union；依赖未知类型参数的派生 union 第一版不提供局部命名语法。`#F = FuncType` 是函数声明前的函数类型约束，RHS 只接收匿名函数类型，不接收普通具体类型、联合类型或已有函数类型约束名。结构体声明前只支持 `#T` 这类普通数据类型参数，不支持 `= ...` 形式或函数类型约束。`#name(...) -> Return` 是函数声明前的接口函数签名约束。
4. 约束块绑定紧随其后的一个函数或结构体；绑定完成后不继续作用于后续声明，后续声明若需要同名约束必须重复写约束块。同名约束在不同绑定声明中是局部名；同一约束块内普通类型参数名和函数类型约束名共享局部名字空间，不能重复，也不能遮蔽当前可见类型名、错误枚举类型名、type import alias 或 enum 分支值。顶层不支持共享函数类型 alias；只写 `#F = (...) -> ...` 不会把 `F` 带到下一个声明，后续声明必须重新写自己的紧贴约束块。约束块内不允许给已有函数类型约束再起局部别名、可选别名或 storage 包装别名；`#F = (...) -> ...` 之后不能再写 `#G = F`、`#G = F | nil` 或 `#G = [F]`。函数类型约束必须在绑定函数的参数类型里至少出现一次，且只能以单一参数类型 `F` 出现，不能作为 nullable/union 参数出现。每条函数类型约束都必须至少有一个对应函数参数在函数体里按该函数类型签名被实际调用，或被传给另一个同签名且自身合法的函数；这里的同签名按实际 `FuncType` 签名比较，不按两个声明里的局部约束名字符串比较。唯一例外是用户显式为具体命名函数类型定义的函数值文本化重载 `to_text(f F) -> text`；只有这个签名可把函数值当作不透明值处理而不调用。`debug_func(f F) -> text`、`inspect(f F) -> text` 这类名字没有例外，必须调用或转发。若回调返回值携带类型参数，返回值必须被返回、赋值、传参，或用 `_ = f(...)` 显式丢弃，裸调用后隐式丢弃不算实际使用；多返回回调的显式丢弃仍按多左值赋值规则逐位匹配，不能用单个 `_` 丢弃整个多返回结果。绑定函数时，每个无等号普通数据类型参数都必须能从参数侧信息唯一求解；普通数据泛型可以只做传递、包装或返回，不要求虚构接口能力约束。绑定结构体时，每个无等号普通数据类型参数都必须在该结构体字段类型里至少出现一次；未被字段实际使用的结构体类型参数非法。普通类型参数只是局部泛型名，不参与函数名唯一性判断。接口函数约束只绑定函数声明，不能绑定结构体；接口函数约束前必须至少已有一个同块普通类型参数声明，且每条接口函数约束都必须引用同块里更早声明的至少一个普通类型参数名；不支持纯具体签名断言。具体函数直接按普通可见函数规则调用。约束块不能绑定 alias、enum、value 或 import 声明。
5. 同一约束块内约束名唯一；同一个名字一旦在当前约束块里声明，就不能再以另一种约束形态重复声明。接口函数约束按函数名和参数类型序列唯一，返回类型不参与唯一性判断；同名但参数类型序列不同的接口函数约束允许并存，表示同一次接口实例化要求当前可见普通函数族里同时存在这些参数签名；这只是能力要求，不让绑定出来的接口函数参与普通重载。因此同名同参数的接口约束不能只靠返回值不同并存，这种约束组合本身就不存在。普通类型参数名和函数类型约束名不得与当前可见具体类型名、错误枚举类型名、type import alias 或 enum 分支值重名；若当前已可见 `User` 这类结构体、`FileError` 这类错误枚举、`Profile` 这类 type import alias，或 `FileNotFound` 这类 enum 分支值，都不能再写成 `#User`、`#User = (...) -> ...`、`#FileError`、`#FileError = (...) -> ...`、`#Profile`、`#Profile = (...) -> ...`、`#FileNotFound` 或 `#FileNotFound = (...) -> ...`。若同一约束块内有多个函数类型约束，且它们按实际 `FuncType` 参数类型序列与返回签名完全一致，也视为重复声明，非法。
6. 约束独立成行，必须连续贴合其绑定的声明头；约束与声明之间不能有空行或注释行。若需要注释，放在整个约束块之前。函数类型约束和接口函数签名约束本身必须单行 inline；签名内部不允许换行。
7. 函数约束列表先写所有无等号的普通类型参数声明；随后写本地 `#F = FuncType` 函数类型约束，并按 RHS 依赖顺序只引用更早声明的普通类型参数；最后写接口函数签名约束。PEG 不再接收 `#Name = ValueTypeExpr`。
8. 类型参数名使用 `PublicTypeName` 形态，接口函数名使用非保留 `LowerIdent`；因此类型参数名不能使用错误枚举名形态，`#FileError`、`#ResultError` 这类写法非法。
9. 普通类型参数名使用当前可见 UpperIdent 名字、`core` 预导入类型名和保留类型名之外的新名字；不能遮蔽同文件声明或 import 引入的具体类型名、错误枚举类型名、enum 分支值或同类 import alias。该限制同时适用于结构体前置类型参数和函数前置普通类型参数。
10. 函数声明的每个无等号普通数据类型参数都必须能从参数侧信息求解：要么直接出现在某个参数类型里，要么虽只出现在返回位，但能通过同一约束块里的函数类型约束或接口函数约束、结合其他已由参数定住的类型参数继续解出。多个前置约束可以对同一个类型参数联合求解；只有联合后的绑定唯一且一致时，该泛型声明才成立。普通数据类型参数的求解结果必须是数据类型；即使当前可见普通函数族里存在 `to_text(F) -> text` 这类接收函数类型的实现，也不能把 `T` 求解成函数类型 `F` 来满足 `#to_text(T) -> text`。普通调用只从已定型实参与由这些实参触发的前置约束推导无等号普通数据类型参数；不能只靠调用点左侧目标类型反向推断。若某个无等号普通数据类型参数既不出现在参数位，也不能经由这些约束从参数侧唯一解出，则该泛型声明只能通过显式调用类型实参实例化，调用写作 `name<TypeArgs>(args)`，例如 `from_json<User>(bytes)`；未写显式类型实参的 `name(args)` 仍按参数侧信息推导，不使用返回上下文。显式调用类型实参只用于普通泛型函数调用，不用于 builtin、core 固定调用、host import、函数值调用或非泛型普通函数；类型实参数量必须与声明的普通数据类型参数数量一致。函数名作为函数值实参时，可在目标 `FuncType` 中按唯一函数候选的参数类型与返回类型绑定类型参数。泛型签名比较按类型参数结构做 alpha 等价，局部类型参数名不进入重载身份。普通函数重载只看参数签名，不看返回类型；参数签名完全一致而只靠返回类型区分的同名函数非法。带接口函数签名约束的绑定函数是接口函数，不参与普通函数重载；接口函数实际名必须独立，不能和普通函数族、函数 import alias、host import alias 或另一个接口函数共用同名。只有不带接口函数约束的普通函数声明才进入普通函数族；单独使用 `#F = FuncType` 的函数仍按普通函数处理。同名普通函数族中，具体参数签名可与同 arity 泛型 fallback 共存；调用时先尝试精确具体候选，再用泛型 fallback 实例化。两个泛型声明若同名同 arity，直接视为重复或歧义并在声明期拒绝；返回类型不参与区分。当前语言不支持函数类型作为独立顶层名字、字段类型、局部绑定类型、storage 元素类型或返回类型；函数类型只在函数参数位与前置类型约束里命名和使用；`ValueDecl`、字段、局部绑定、storage 和函数返回位不接收函数类型。命名函数类型约束的 lambda 实参可省略参数类型，但返回类型绑定泛型参数时必须显式写出。
11. `#F = FuncType` 的 RHS 只能是匿名函数类型；该函数类型内部的参数位和返回位可引用同一约束块内更早声明的数据类型参数，不允许前向引用后续 `#U`，也不从 RHS 隐式声明类型参数。`#F = FuncType` 的 RHS 不能在任何层级引用另一个函数类型约束名，因此不能写 `#G = F`、`#G = F | nil` 或 `#G = [F]` 来表达函数类型别名、可选回调别名或函数 storage 包装。可选回调不通过函数参数位表达；需要时由调用方分支选择是否调用，或用普通数据结构承载状态。比如 `#F = () -> i8, bool | i32` 约束 `F` 为无参函数类型，返回 `i8` 与 `bool | i32` 两个值。
12. 泛型函数体中对数据类型参数调用函数时，由对应接口函数签名约束提供能力；`#T` 只声明数据类型参数。
13. 接口约束里的函数名只能引用当前文件可见的非保留普通函数名，且不得等于该约束块最终绑定函数的实际函数名；即使前面已经存在同名可见重载族，也不能用 `#show(T) -> [u8]` 约束紧随其后的 `show(...)`。builtin special form 名、core 固定调用名、host import alias、声明专用名和保留类型名不能作为接口约束名，因此 `#is(...)`、`#recv(...)`、`#get(...)`、`#set(...)`、`#eq(...)`、`#add(...)`、`#len(...)`、`#put(...)`、`#start(...)`、`#test(...)`、`#text(...)`、`#string(...)`、`#char(...)` 非法。泛型若需要加法、长度、相等或排序能力，必须定义或 import 非 core 普通函数族，例如 `#combine(T, T) -> T`、`#size(T) -> usize`、`#same(T, T) -> bool` 或 `#before(T, T) -> bool`。`copy` 不属于内建能力；若要写 `#copy(T) -> T`，当前文件必须显式定义或 import 一个可见的普通 `copy` 函数族；`std` 和用户模块需要显式 import。
    通过 local import 或标准库 import 引入的函数 alias，同样算当前文件可见的普通函数名，可以写进接口约束；若该 alias 绑定的是目标模块里现成的同名重载族，则它在接口约束里也按这个重载族参与匹配。同文件 private 普通函数在声明位写 `.name`，但接口约束位与调用位都使用去点后的实际名字 `name`；跨文件 private 函数仍然不可见，不能拿来满足接口约束。`host import` 虽然也在当前文件里形成 `LowerIdent` 名字，但它不属于普通函数族，不能作为接口约束名。
    接口约束也支持尾部变参签名，例如 `#sum(T, T, ...T) -> T`；匹配时复用普通函数族的变参签名规则。尾部变参位里的元素类型使用 `VariadicElemType`，因此 `#copy_boxes(...Box<T>) -> [Box<T>]` 这类复合类型变参合法；但变参元素仍属于参数位，实际类型不得是 union/nullable；`#collect(...T | nil) -> i32` 非法。
    type import alias 参与接口约束匹配时，归一到来源 public 类型身份后比较。接口约束参数位复用普通参数类型表达式，实际类型不得是 union/nullable，因此 `#has_user(T | nil) -> bool` 非法。`[T]`、`Box<T>`、公开 type import alias 和更深组合合法，前提是最终参数类型本身不是 union/nullable。匹配时每个参数位的类型都必须完全一致。
    接口约束返回位使用 inline 返回签名，可写 `-> nil`、单返回或多返回，但签名内部不允许换行；这里的单返回也包含联合类型单返回，例如 `-> T | nil` 或 `-> [u8] | FileError`，它们仍然算一位返回，不是多返回。多返回时每一位返回槽仍然各自复用 inline 类型表达式，因此 `-> T | nil, bool` 是合法的两位返回。匹配时返回位数与每一位返回类型也都必须完全一致。
    接口约束写出的整条参数签名必须和被约束的实际函数声明签名完全一致；`#count(...T)` 只匹配 `count(rest ...T)`，不匹配 `count(first T, rest ...T)`，`#sum(T, T, ...T)` 也不匹配 `sum(T, T, T)`。同一个接口约束里的同一个类型参数只绑定一个具体数据类型，并贯穿该约束整条签名；因此 `#same(T, T)` 要求两个参数位都是同一个具体数据类型，`#echo(T) -> T` 也要求参数位和返回位绑定到同一个具体数据类型，`#pair(T) -> T, T` 则要求所有对应返回位保持同一个具体数据类型。
    同一约束块里先由 `#T`、`#U` 等声明出的类型参数在后续所有接口函数约束和最终函数签名中共享；接口约束不会为每一条 `#name(...) -> ...` 重新引入一份局部同名类型参数。接口函数约束里的不同类型参数按名字独立绑定；若同一条 `#name(...) -> ...` 同时出现 `T` 和 `U`，它们可以在某次实例化里分别落成不同具体数据类型，例如 `#cast(T) -> U` 可以绑定成 `T = i32`、`U = i64`。这种独立绑定规则只作用于 `#name(...) -> ...` 接口函数约束，和 `#F = (T) -> U` 的函数类型约束保持一致。
    接口约束声明的是泛型可用的能力边界，不要求在泛型声明阶段就覆盖类型参数的所有潜在具体数据类型。`#U` 只声明数据类型参数；`#copy_i32(U) -> U` 表示只有当某次实例化把 `U` 绑定成某个具体数据类型，且当前可见同名函数族中存在完全匹配的 `copy_i32(ThatType) -> ThatType` 时，该次实例化才合法。若当前绑定下找不到匹配签名，则该次实例化或调用报错。同一约束块里的多条接口函数约束可以对同名类型参数联合求解；接口函数约束按集合求解，书写顺序不影响语义；只有把这些约束放在一起后仍能得到唯一且一致的数据类型绑定，该次实例化才合法。
    接口函数约束只由当前可见的普通函数族或函数 import alias 指向的普通函数族满足；匹配时只看当前绑定后的具体参数签名与返回签名是否完全一致，函数族里额外存在其他合法重载不会破坏该约束。带接口函数签名约束的接口函数不进入普通函数族，也不能作为另一个接口函数约束的实现候选；因此 v1 不做接口函数递归满足求解。
    接口函数约束中的类型参数必须先由同一函数约束块内更早的 `#T` 声明；每条接口函数约束都必须实际引用至少一个同块类型参数，并且必须在绑定函数体内被同名调用实际使用；实际使用要求该调用在当前绑定下匹配这条接口约束的参数和返回签名；只出现同名但签名不对应的普通调用不算使用；不能只作为隐藏的可调用类型限制存在；`#name(...) -> Return` 不隐式声明类型参数。具体参数和返回都已定死的普通调用不写接口约束，直接按当前可见函数族解析。

## 9. 判断族与类型收窄

### 9.1 Builtin 成员

`is`, `and`, `or`, `not`

### 9.2 Core 成员

`eq`, `ne`, `lt`, `le`, `gt`, `ge`

### 9.3 规则

1. `builtin` 判断族按 special form 规则解析。
2. `core` 预定义判断函数族以默认可见固定调用名提供；用户和标准库不能为 `eq/ne/lt/le/gt/ge` 补充同名参数签名，也不能声明、导入、遮蔽或重写这些名字。
3. 判断族返回 `bool`。
4. `@and/@or/@not` 在 `bool` 条件和 `bool` 表达式上采用短路求值；`@and/@or` 接受 2 个及以上 `bool` 参数并按左到右求值，但不接受 `...rest` 展开，所有参数必须在源码中静态列出；`@not` 固定 1 个 `bool` 参数且不接受 `...rest`。当 `@and/@or` 的目标类型或首参静态类型不是 `bool` 时，它们按整数位运算 primitive 解析，固定 2 个同类型整数参数，分别 lower 到 wasm `and/or` 指令；`@xor` 只表示整数位运算，固定 2 个同类型整数参数。v1 不实现复合条件 proof engine：`@and/@or/@not` 可以出现在条件位, 但参数不能直接使用 `@is(...)`; 它们只组合普通 `bool` 条件, 不携带或传播类型收窄事实。离开条件位后，它们也只是普通 `bool` 组合。和 `if` 条件头一样，每个参数最外层都不接受无意义括号。
5. `@is(value, TargetType)` 是 builtin special form，不进入普通函数重载。它只作为 `if` / `loop` 条件头的直接根表达式合法；不能嵌套在 `@and/@or/@not` 里，也不能单独作为普通 `Expr` 出现在绑定、赋值、返回、普通函数实参、聚合元素或表达式语句里。写 `if @is(v, User)`, 不写 `if (@is(v, User))`、`if @and(@is(v, User), ready())` 或 `ok bool = @is(v, User)`。`value` 的静态类型必须已经显式暴露候选集合，例如 `[u8] | FileError`、`User | nil` 或 `User | Order`；若 `value` 的静态类型只是单独的普通数据类型参数 `T`，没有可扣减候选集合，则不能写 `@is(value, T)`。`TargetType` 使用 `IsTypeExpr`，v1 顶层只能是单个普通类型表达式或当前约束块可见的局部数据类型参数名；`@is(value, A | B)` 目标集合保留到后续 union lowering 完整后再启用。语义阶段负责判断该名字的类别和可收窄性。`TargetType` 必须和 `value` 的静态类型有交集且是真正收窄，不能覆盖 `value` 的全部静态类型；真分支收窄到 `TargetType`，假分支按原静态类型扣除 `TargetType` 后继续收窄；`TargetType` 不接受外层无意义括号，写 `@is(value, T)`，不写 `@is(value, (T))` 或 `@is(value, A | B)`；函数类型不进入 union 候选集合，因此不能写 `@is(value, F)` 或 `@is(value, () -> i32)`。
6. `@is` 的顶层目标分支不接受 `nil`；`nil`、字符串、数字、`FileNotFound` 这类值判断使用 `@eq/@ne`，`@is(value, nil)` 与 `@is(value, T | nil)` 视为非法写法。嵌套在 type args 或 storage element 内部的 `nil` 允许出现，例如 `@is(value, Box<User | nil>)` 判断的是外层 `Box<...>` 分支，不是 `nil` 分支。局部类型参数作为 `@is` 顶层目标时，实例化后也必须满足顶层不含 `nil`；若 `T` 被绑定为 `User | nil`，则 `@is(value, T)` 在该次实例化中报错。
7. `@as(Type, value)` 是 builtin special form, 不进入普通函数重载。它只做标量数值转换, `Type` 只能是 `u8/u16/u32/u64/usize/isize/i8/i16/i32/i64/f32/f64`; 例如 `n u64 = @as(u64, count)`。union 分支值通过条件收窄后直接使用原变量, 例如 `if @is(v, User) { return v }`。
8. 所有带括号的 builtin special form 都允许末尾 trailing comma；`recv(ch,)` 与 `recv(ch)` 等价。尾逗号不改变参数数量。
9. guard 形式 `if @eq(value, nil) return/break/continue` 退出后，若 `value` 的静态 union 恰好包含一个非 `nil` 分支, 后续路径可把 `value` 收窄到该非 `nil` 分支。`break/continue` 产生的收窄只传播到同一轮 loop 内仍可继续执行的后续语句，不传播到 loop 外。其他条件的 guard 后续路径收窄保留到 future。
10. 普通块体 `if` 默认只在分支内部收窄。v1 已稳定的块体收窄只有直接根条件 `@is(value, Type)` 的 true 分支, 以及直接根条件 `@eq/@ne(value, nil)` 的单非 `nil` 分支；复合条件、enum 分支值和更强的结构化退出 proof engine 保留到 future。
11. `else if` 只按每个分支自己的直接根条件做局部收窄；跨分支反向事实继承保留到 future。
12. 未收窄的 union 值不能因为包含某个分支而匹配该分支类型。`value FileError | nil` 不能直接赋给 `err FileError`, 也不能直接传给 `need_error(err FileError)`；必须先用直接条件头 `@is(value, FileError)` 或已承诺的单非 `nil` 收窄路径证明当前分支。函数调用、返回、绑定和 `@field_get` 后续重载分派都按当前路径的静态类型匹配, 不做隐式 union payload 提取。
13. `@eq/@ne` 做相等与不等判断；可用于 `nil`、字面量、枚举分支值与一般值比较，并可作为普通 `bool` 表达式赋值、返回或传参。core 提供基础类型默认签名；用户类型若需要领域相等判断，使用非 core 普通函数名，例如 `same_user(user User, other User) -> bool` 与 `different_user(user User, other User) -> bool`。`@eq(value, nil)`、`@eq(value, EnumBranch)` 这类 union 分支判断由判断族的 core 定型路径处理，不对应用户可声明的 union 参数签名。函数值不支持 `@eq/@ne` 身份比较。
14. `@eq/@ne` 在 `CondExpr` 中只有直接根条件 `@eq(value, nil)` / `@ne(value, nil)` 触发 v1 路径收窄, 且只在 `value` 的静态 union 恰好包含一个非 `nil` 分支时把非 nil 路径收窄到该分支类型；若静态类型是 `T | ErrorEnum | nil` 或 `A | B | nil` 这类多非 nil 分支，排除 `nil` 后仍保留剩余 union，不能自动当作 `T` 使用。普通数字、字符串、`bool` 字面量和枚举分支值只做值比较，不触发类型分支收窄；`@eq(v, FileNotFound)` 只比较值，不代表整个 `FileError`。`@eq/@ne` 的结果离开当前条件表达式后不携带证明，赋给 `bool` 绑定后只保留普通布尔值。
15. `@lt/@le/@gt/@ge` 适用于可排序类型；它们不携带类型收窄证明。数组边界守卫应放在 `@get/@set` 前面用于避免 runtime trap，但不改变 `@get/@set` 的返回类型。
16. `@eq/@ne` 对标量、`bool` 与普通聚合值使用值语义；若聚合值包含函数值字段，则整值比较非法。用户库实现的集合或字节文本类型若暴露为结构体值，也按其公开语义参与比较。
17. 用户类型需要业务相等或排序时，定义领域函数或普通非 core 函数族，例如 `same_user`、`user_before`、`compare_user`；不能重载 `eq/ne/lt/le/gt/ge`。
18. `@is(value, FileError)` 这类具体 enum 类型判断有效，按 union 成员类型测试处理。
19. `@eq/@ne` 始终只做精确值比较，不把任何联合类型名当作类型测试的替代。
20. `ErrorEnumName` 类型名可出现在类型位或 `@is(value, FileError)` 这类条件位中。
21. enum 分支名是值，可用于赋值、返回和 `@eq/@ne` 比较；右侧分支值不是类型，不能写进 union 类型表达式。


## 10. 数值函数族


1. `add/sub/mul/div/rem` 属于 `core` 固定调用名，默认可见；用户和标准库不能为这些名字定义同名重载，也不能声明、导入、遮蔽或重写这些名字。向量、集合或领域数值能力必须使用非 core 名，例如 `vec_add(a Vec2, b Vec2) -> Vec2` 或 `list_add(xs List<T>, value T, rest ...T) -> List<T>`。
2. core 原始数值调用只接受同类型参数，参数个数为 2 个及以上；尾部使用 `...rest` 展开时，展开前也必须已有至少两个固定实参，例如 `@add(a, b, ...rest)`。展开后仍按二参左结合规约；不存在用户补充的同名函数分支。
3. `@add(a, b, c)` 等价于 `@add(@add(a, b), c)`；`@add(a, b, ...rest)` 在展开后同样按左结合二参链执行。
4. `@mul(a, b, c)` 等价于 `@mul(@mul(a, b), c)`。
5. `@sub(a, b, c)` 等价于 `@sub(@sub(a, b), c)`。
6. `@div(a, b, c)` 等价于 `@div(@div(a, b), c)`。
7. `@rem(a, b, c)` 等价于 `@rem(@rem(a, b), c)`。
8. 整数 `div/rem` 的除零、整数算术溢出是前置条件失败；运行时触发 runtime trap / safety failure，不作为源码可见错误返回。常量表达式若能在编译期证明失败，编译期报错。
9. 浮点 `div/rem` 不用错误枚举表达非有限结果；`nan/inf/-inf` 作为浮点值进入后续计算和 `to_text` 输出规则。
10. 需要 wrapping、saturating 或 checked 数值语义时，后续由普通库函数族显式提供，不改变 `add/sub/mul/div/rem` 的默认语义。
11. 数值 core 名不能作为接口函数约束名；泛型若需要加法能力，使用非 core 普通函数名，例如 `#combine(T, T) -> T`，并由当前可见普通函数族提供完全一致的实现签名。`#add(T, T) -> T`、`#add(T, T, ...T) -> T`、`#mul(T, T) -> T` 这类约束都非法。


## 11. 路径 primitive: get/set

### 11.1 定位

1. `get/set` 是 core 路径 primitive 保留调用名，不可重载也不可遮蔽；它们只在 `CoreAccessExpr` 的路径调用形态中出现。
2. `@get/@set` 的路径调用形态使用 `CoreAccessExpr`，例如 `@get(x, .name)`、`@get(users, 0, .name)`、`@set(x, .name, value)`、`@set(users, 0, .name, value)`；该形态只按 core 的 struct 字段与 `[T]` 连续存储原语分派，不进行普通重载候选收集。
3. `@put` 是 core 固定调用名，只表示 `[T]` 连续存储追加 `@put([T], value T, rest ...T) -> [T]`；用户和标准库不能为 `put` 补充插入、键写入或其他同名重载。`update/del` 不进入 core 默认能力，是普通库函数名。
4. `@get/@set` 是 `[T]` 连续存储相关的路径 primitive；`@len([T]) -> usize` 与 `@put([T], value, rest...) -> [T]` 是 core 固定调用名，不为用户类型补充新签名重载。集合循环第一版只直接接受 `[T]`；`std` 或用户库若要支持循环，必须提供返回 `[T]` 的显式视图函数。
5. 底层原语只有两类：结构字段 `@get(T, .name)` / `@set(T, .name, v)`，以及连续存储索引 `@get([T], usize)` / `@set([T], usize, v)`；`std` 或用户库可在此基础上组合更高层操作。
6. 多段结构路径使用扁平参数形态；字段/索引路径统一从 `get/set` 进入，集合设计由库层承载。
7. 结构字段读写统一只走路径形态，例如 `@get(x, .name)` 与 `@set(x, .name, value)`。
8. 库层插入、键写入或集合追加不能使用 core 名 `put` 或 `add` 扩展；必须使用非 core 名。`List` 的尾部追加使用 `list_add(xs List<T>, value T, rest ...T) -> List<T>`，`HashMap` 的键写入使用 `hash_put(m HashMap<K, V>, key K, value V) -> HashMap<K, V>`。
9. `del` 可用于列表索引删除、映射 key 删除或其他库自定义删除语义。
10. `update` 作为普通库函数定义；需要时可由 `std` 基于 `get/set` 和显式边界判断提供。
11. `put`、`and/or/xor/shl/shr/rotl/rotr/clz/ctz/popcnt`、`abs/neg/sqrt/ceil/floor/trunc/nearest/min/max/copysign` 是 core 固定调用名，不是普通库函数名，不能被用户或标准库重载、遮蔽、导入为 alias 或写入接口约束。标量数值转换使用 builtin `@as(Type, value)`，不再提供按目标类型拆分的 core 固定转换名。`update/del` 是普通库函数名，可按普通函数族规则定义重载；同名同签名重复声明非法，未来 `std` 新增同名签名时按普通导入/重载冲突处理。

### 11.2 路径形态

1. 单段字段路径写作 `FieldSeg`，例如 `.name`。
2. 多段路径写作扁平实参，例如 `@get(users, 0, .name)` 或 `@set(users, @add(i, 1), .name, value)`。
3. `get/set` 的 PEG 先锁定最小参数数量；`get` 把 target 之后的参数解析成扁平 `CoreAccessArgList`；`set` 在语法层固定第一个实参为 target、最后一个实参为 value、中间一项或多项为路径段。字段段是单个 `DotLowerIdent` token，只出现在路径段；lambda 只出现在 `set` 的最终 value 位；索引表达式先保留为 `Expr`。
4. `@get` 使用 `@get(target, path...)` 形态；第一个参数是 target，后续参数全部按路径解释。
5. `@set` 使用 `@set(target, path..., value)` 形态；第一个参数是 target，最后一个参数是待写入 value，其他参数按路径解释。
6. `@set` 的路径/value 边界先按 syntactic argument 位置确定，再按类型解释路径：`arg[0]` 是 target，`arg[last]` 是最终 value，`arg[1..last)` 是路径段。路径段至少一个；若保留最终 value 后没有路径段，或路径段解释完成后的当前位置类型不能接收该 value，则报类型错误。最终 value 可以是普通表达式或一参 lambda 实参形态，例如 `@set(user, .name, "amy")`、`@set(user, .name, to_text())`、`@set(user, .name, (name [u8]) => @put(name, "!"))`。当最终 value 是一参 lambda 时，`@set(target, path..., lambda)` 表示路径更新：先求出旧终点值 `old = @get(target, path...)`，再求 `new = lambda(old)`，最后写回 `@set(target, path..., new)`；lambda 参数类型必须能接收旧终点值，lambda 返回值必须能写回同一终点类型。字段段 `.other` 只在路径位合法，不能作为最终 value 或普通 value 表达式直接出现。
7. 路径段按当前位置类型解释：当前位置是结构体时，下一个路径参数必须是字段段；当前位置是 `[T]` 时，下一个路径参数必须是能定型为 `usize` 的索引表达式；`[T]` 连续存储的索引由 core 函数处理，不通过结构路径暴露。因为 `@set` 已经固定保留最后一个参数为 `value`，`@set(xs, i, value)` 中 `i` 是索引段，`value` 是待写入值；少于 `target + path + value` 的 `@set(xs, i)` 形态由 PEG 最小参数数量直接拒绝。
8. `@set(target, path..., value)` 至少包含一个路径段和一个最终值；`@get(target, path...)` 至少包含一个路径段。
9. 路径段单段为 `PathArg`，分为字段段与索引段：字段段是单个 `DotLowerIdent` token；索引段是定型到 `usize` 的 `Expr`。
10. 路径段是 `get/set` 的原语级语法，不暴露为 `core` 或 `std` 的值类型。
11. `FieldSeg` 不作为普通参数类型暴露；`@get(user, "name")` 只是表达式参数，只有路径当前位置是 `[T]` 且该表达式能定型为 `usize` 时才可作为索引段，不触发用户重载。
12. 字段段只用于结构体字段访问；索引段只用于 `[T]` 连续存储索引访问，不触发库类型扩展。
13. 复杂表达式段在路径求值时直接计算；字段段按 `.lower_ident` 展示，索引段按其可读表达展示。
14. 索引段允许 `Expr`，但只有目标类型是 `[T]` 或路径当前位置是 `[T]` 时才合法；普通 struct 字段段使用 `.lower_ident`。
15. 私有字段路径段在声明该结构体的模块内使用。
16. `@get/@set` 的求值顺序不同于普通调用的“全部实参先求值”：target 先求值；`@get` 把 target 之后的所有参数作为路径段，`@set` 先把 target 之后的最后一个参数固定为最终 `value`，再把中间参数作为路径段；路径从左到右推进。只有当当前位置是 `[T]` 时，才求值当前索引表达式并立即做边界检查；若该索引越界，立即触发 runtime trap / safety failure，后续路径段不再求值。`@set(target, path..., value)` 的最终 `value` 表达式只在完整路径全部成功后求值；若路径检查失败，`value` 不求值。

### 11.3 调用示例

```do stmt ok name=path_call_examples
name [u8] = @get(user, .name)
state = @set(state, .user, .name, "tom")
item = @get(user, .abc, @add(i, 1), .name)
```

`@get/@set` 是路径 primitive 保留调用名，不提供用户声明示例；声明同名普通函数是保留名错误。`@len` 是 core 固定调用名，只用于 core 支持的连续存储长度读取，不支持用户类型按普通重载规则提供 `len(x T) -> usize`。

### 11.4 返回与失败语义

1. `@get(target, path)` 返回路径终点值类型 `V`。
2. `@set(target, path, value)` 返回原始目标类型 `T`。
3. 字段段直接返回字段值类型；字段不存在在编译期报类型错误。
4. 含索引段时，`get/set` 的索引段是前置条件操作；索引越界触发 runtime trap / safety failure，不作为源码可见错误返回。常量索引若能在编译期证明越界，编译期报错。
5. `value` 位置不接收多返回调用；若需要使用多返回结果，先用多左值赋值拆出单值，再作为 `value` 传入。
6. 如果终点类型本身包含 `nil`，`get` 返回的 `nil` 一定是业务值；缺失或越界不通过 `nil` 表达。
7. `@get([T], usize) -> T` 是 core 连续存储索引读取；`@set([T], usize, T) -> [T]` 是 core 连续存储索引写入。
8. 集合循环在 `0..@len(source)` 生成的 `usize` 位置上调用 `@get([T], usize)`；该范围由语言生成，不越界，因此循环绑定类型是 `T`。
9. `set` 只更新既有路径。
10. `Struct` 支持字段段 `get/set`；是否支持 `update/del/list_add/hash_put` 等高层操作由具体库函数决定，不由语法层限定。
11. `List/HashMap` 作为普通库类型存在；`list_get/hash_get/list_add/hash_put/update/del/clear` 等扩展操作由 `std` 或用户库以普通函数提供，不接入内建 `get/set/len/put`。即使当前模块用 import alias 把它们重命名，canonical type identity 仍然指向 `@lib("list.do", List)` 或 `@lib("hash_map.do", HashMap)`，不能绕过直接路径或直接循环限制。
12. `List` 作为循环源时使用库显式提供的 `items(xs) -> [T]`；`HashMap` 作为循环源时使用库显式提供的 `keys(m)`、`values(m)` 或 `entries(m)` 这类返回 `[T]` 视图的函数。

### 11.5 字段反射 primitive

1. 字段反射第一版只提供编译器拥有的不透明字段元数据；源码不能声明、构造、存储或返回 `Field` 结构体，也没有 `any` 类型参与字段值接收。
2. `fields(TypeOrTypeParam)` 只作为单绑定 loop source 使用，写作 `loop field = fields(User) { ... }` 或泛型函数实例内的 `loop field = fields(T) { ... }`。它不是普通函数调用，不能写在赋值、返回、调用实参或 `@fields(...)` 位置。
3. `TypeOrTypeParam` 使用已声明结构体的实际类型名，或当前泛型函数的单个类型参数名；私有结构体在同模块内也按去点后的实际类型名引用。泛型参数只在实例化后绑定到具体结构体时合法，并在该具体结构体上做编译期展开。当前 v1 文法不在 `fields(...)` 里接收泛型 type args，因此 `fields(Box<T>)`、`fields([T])` 和 `fields(T | nil)` 都不是字段反射源。
4. 字段反射循环在编译期按可见字段展开，顺序为结构体声明顺序。同一模块内可见 public 与 private 字段；跨模块只可见 public 字段。
5. 循环绑定 `field` 是编译器元数据绑定，只能作为 `@field_name/@field_index/@field_has_default/@field_get/@field_set` 的字段参数使用；不能作为普通值绑定、普通函数实参、返回值、结构字段或集合元素逃逸。
6. `@field_name(field) -> text` 返回字段实际 name，不含 private 字段声明位前置点。
7. `@field_index(field) -> usize` 返回当前可见字段序列里的 0-based index；它不是跨版本稳定 schema id，也不用于持久化格式。
8. `@field_has_default(field) -> bool` 只表示字段声明是否带默认值，不暴露默认值表达式或默认值类型。
9. `@field_get(target, field)` 在每一次编译期展开后直接 lower 成具体字段读取，结果类型是该字段的静态类型；它不返回 `any`，也不会在运行时携带字段类型标签。`@field_get(...)` 作为普通调用实参时按该字段静态类型参与重载分派，例如 `encode_value(@field_get(value, field))` 会在每个字段展开点选择对应的 `encode_value` 重载。
10. 对具体 `fields(User)` 循环里的 `@field_get` 使用点，编译器会用当前可静态判定的字段 guard 过滤候选字段。当前 guard 子集包括 `@field_name/@field_index/@field_has_default` 与字面量之间的 `@eq/@ne`，以及这些 bool 结果上的 `@and/@or/@not`。未 guard 的异构字段不能统一绑定到一个无类型局部；作为普通函数实参时，被调函数族必须能为所有候选字段类型找到可匹配候选。
11. `@field_set(target, field, value)` 在每一次编译期展开后直接 lower 成具体字段写入，`value` 必须能定型为该字段静态类型。当前 build lowering 只支持 `target = @field_set(target, field, value)` 这种同名自赋值语句形态。对具体 `fields(User)` 循环里的 `@field_set` 使用点，value 必须能写入当前 guard 过滤后的所有候选字段；未 guard 的异构字段写入只有在 value 同时匹配全部候选字段类型时才成立。
12. 处理异构字段时，推荐先用具体类型重载承接 `@field_get`，或用 `@field_name` / `@field_index` 写可静态判定的分支，再在分支内绑定字段值或执行 `@field_set`。不要把不同字段类型统一塞进一个无类型 `value` 绑定。
13. v1 不提供 `@field_type`、`@field_default_value` 或 `@field_default_type`。需要序列化时，使用 `fields(TypeOrTypeParam)` 枚举字段，再通过 `@field_get` 调用具体类型编码函数；泛型序列化函数可以写成 `#T stringify(value T) -> [u8] | JsonError` 并在函数体内使用 `fields(T)`。


## 12. 控制流

本章定义 `if`、guard、`loop`、`break/continue`、循环标签、消费循环和未来保留的控制流关键字。

1. `if` 的条件位是单值 `bool`，且条件头最外层不接受无意义括号。任何已经定型为单值 `bool` 的表达式都可以直接作为条件，例如局部 `bool` 绑定、返回单值 `bool` 的函数调用、条件位 builtin `and/or/not/is` 的结果，以及 core 普通函数 `eq/ne` 的结果；返回非 `bool` 的函数调用不能直接作为条件，需要先用 `eq/ne/is` 等谓词表达成 `bool`。
   ```do program ok
   ok bool = true

   ready() -> bool {
       return true
   }

   count() -> i32 {
       return 1
   }

   test "if condition bool expr" {
       if ok return
       if ready() return
       if @eq(count(), 1) return
       return
   }
   ```
   反例:
   ```do program err
   test "if condition non bool call" {
       if count() return
       return
   }
   ```
   ```do program err
   test "if condition outer paren" {
       if (ok) return
       return
   }
   ```
   重载调用仍遵循普通调用定型规则：`if` 的 `bool` 条件目标不参与实参定型或候选选择；先按实参类型选唯一候选，再检查该候选是否返回单值 `bool`。
   ```do program ok
   ready_value(x i32) -> bool {
       return true
   }

   ready_value(x i64) -> i64 {
       return x
   }

   test "if condition overload typed arg" {
       x i32 = 1
       if ready_value(x) return
       return
   }
   ```
   反例:
   ```do program err
   ready_lit(x i32) -> bool {
       return true
   }

   ready_lit(x i64) -> bool {
       return true
   }

   test "if condition overload literal ambiguous" {
       if ready_lit(1) return
       return
   }
   ```
2. `defer` 的语法只接受两种形态:
   ```do fragment design
   abc() -> nil {
       return
   }

   test "defer call syntax" {
       defer abc()
       return
   }

   test "defer block syntax" {
       defer {
           abc()
       }
       return
   }
   ```
   PEG 片段:
   ```peg
   DeferStmt <- 'defer' (DeferCall / DeferBlock)
   DeferCall <- CallExpr
   DeferBlock <- Block
   ```
   `defer` 注册当前词法区域的 cleanup；离开该区域时执行，覆盖正常落出、`return`、`break` 和 `continue`。同一区域内多个 `defer` 按 LIFO 执行，后注册先执行。`defer abc()` 的调用结果必须是 `nil`；`defer { ... }` 的 block 等价于 `() -> nil` cleanup block，不能返回值。返回语义固定为: `return` 先按普通表达式/多返回规则求值并锁定返回槽，随后执行离开路径上的 cleanup，cleanup 不能修改已经锁定的返回值。cleanup block 内声明的 managed local 按普通 block 退出规则释放；cleanup 先于被离开区域的 ARC fallthrough/return/break/continue release 执行。cleanup 错误不做隐式传播、丢弃、聚合或覆盖；需要业务处理的 cleanup 失败必须在主流程里显式调用并显式处理。
3. `break/continue` 标签引用当前可见循环标签。
4. `loop` 支持三种形态：
   - 无限循环：`loop { ... }`。
   - 集合循环：`loop value, index = source { ... }`；第一绑定位是值，第二绑定位是 `usize` 位置，二者都可写 `_` 丢弃，也可同时写 `loop _, _ = source` 表示只按元素数量执行循环体。
   - 消费循环：`loop value = recv(ch) { ... }` 或 `loop value, count = recv(ch) { ... }`；右侧使用专用 `recv(...)` 形态，`recv` 不是普通函数名。当前 build lowering 只覆盖 `[T]` source 的 storage-backed receive 形态，按 `0..@len(ch)` 顺序消费已有元素；真实 channel/stream receive ABI 后续单独扩展。第二绑定位是 `usize` 接收计数，只对进入循环体的 receive 结果计数，从 0 开始；正常结束不进入循环体，也不绑定计数。
   - 字段反射循环：`loop field = fields(User) { ... }` 或泛型函数实例内的 `loop field = fields(T) { ... }`；右侧使用专用 `fields(TypeOrTypeParam)` 形态，`fields` 不是普通函数名。循环体按可见字段做编译期展开，不是运行时 iterator。
   v1 不提供单独的条件循环关键字、`for-in` 语法或通用 iterator 协议；条件循环用 `loop { if @not(cond) break ... }` 表达，库集合通过返回 `[T]` 的显式视图参与集合循环。集合循环使用 `=` 连接绑定与源。
5. 集合循环源类型第一版只接受 `[T]`；循环按 `0..@len(source)` 的索引顺序读取值，并在该范围内用 core 路径 primitive `@get([T], usize) -> T` 取得元素。该范围由语言生成，不越界，因此循环体内的元素绑定类型是 `T`。`List<T>`、`HashMap<K, V>` 等标准库结构体不直接作为集合循环源，需要通过 `items(list)`、`keys(m)`、`values(m)` 或 `entries(m)` 这类返回 `[T]` 的视图函数。这个限制按 canonical type identity 判断，不按当前文件的 import alias 文本判断；`MyList = @lib("list.do", List)` 后，`MyList<T>` 仍不能直接循环。`range(...)` 这类标准库函数若返回 `[T]`，即可直接用于集合循环。
6. 集合循环的右侧表达式在进入循环前求值一次，后续循环使用该源值。
7. 集合循环中的 `v` 是 `[T]` 的元素类型 `T`；若 `T` 本身包含 `nil`，循环中的 `nil` 是业务值。
8. 消费循环预留给流、通道等无长度来源；真实 channel/stream receive 中，`nil` 表示正常结束，不进入循环体，`T` 和具体错误枚举分支值都进入循环体。若 `recv(ch)` 的结果类型是 `T | RecvError | nil`，非 `_` 的第一绑定位在循环体内的类型是 `T | RecvError`，用户必须显式判断错误枚举分支值；当 `recv` 可能返回错误枚举分支值时，`loop _ = recv(ch)` 与 `loop _, count = recv(ch)` 非法，避免静默丢弃错误。若 `recv(ch)` 只可能返回 `T | nil`，则 `_` 可以用于丢弃接收到的普通值。`T` 排除 `nil` 类型。消费循环若写第二绑定位，其类型固定为 `usize`，表示本次进入循环体的 receive 计数；错误枚举分支值也算一次进入循环体并递增计数，正常结束的 `nil` 不计数。当前 build lowering 阶段的 storage-backed receive 不实现阻塞、挂起或外部消息拉取；它只把 `[T]` source 当作有限输入序列消费。
9. `len` 是 core 固定调用名，`get` 是 core 路径 primitive 保留调用名；标准库或用户库若要支持集合循环，提供返回 `[T]` 的视图函数。
10. 普通结构体不直接满足集合循环源条件。
11. `[u8]` 是连续字节 storage，可以直接作为集合循环源；映射遍历由库提供可迭代 `[T]` 视图。
12. 单行 `if` 是 guard 语法，接 `return`、`break` 或 `continue`。
13. `else if` 跟在块体 `if` 后；guard `if` 不接 `else`。
14. 循环标签使用独立前置行 `#name`，标注紧随其后的 `loop`。标签名是独立命名空间，只排除 `ReservedWord`；`#add`、`#len`、`#test`、`#i32`、`#bool` 这类名字可作为标签，不参与内建调用名、声明专用名或保留类型名解析。
15. `:=` 不是当前语法；`if Type(x) := expr` 这类模式绑定写法已删除，不能出现在源码中。


## 13. 编译期、入口与运行时边界

本章定义顶层值 CTFE、模块级可变变量初始化、`start` 入口和 host/build 运行时边界。

详细正例、反例与回归提取素材见 `./spec_examples.md` 的对应章节。本节只保留主规范规则。

1. 顶层常量初始化在编译期求值出结果；模块级可变变量的初始值也必须在编译期求值出结果，并作为该模块静态存储的初始状态。顶层值名先整体收集，因此初始化表达式可引用同一模块里源码顺序更靠后的顶层常量或模块级可变变量初始值；求值按依赖图执行，依赖图必须无环。
2. 顶层值 CTFE 求值路径由可 CTFE 的本地表达式与普通函数组成；递归与循环受编译期求值预算限制。CTFE 调用链禁止写模块级可变变量及其 import alias；普通函数可以被 CTFE 调用，但在 CTFE 上下文里只能读取顶层常量、读取模块级可变变量初始值、调用可 CTFE 函数，不能执行模块级可变变量赋值。
3. host import 属于运行时边界；build 时宿主与运行时宿主可以不同。
4. 普通函数、`start`、`test` 测试声明和 lambda 在运行时可读取顶层常量，可读写当前可见的模块级可变变量，并可调用当前可见函数。若普通函数被顶层初始化或 CTFE 字段默认值调用，则按 CTFE 副作用限制检查，不能写模块级可变变量。访问模块级名字不算捕获，不形成闭包；闭包问题只对应捕获外层局部绑定，而当前 lambda 仍不支持这种捕获。
5. `ReadonlyIdent` 顶层常量可出现在值表达式位，但不可被重新赋值；模块级可变变量在其可见范围内可被赋值。`ReadonlyIdent` 主体不参与 `ReservedName` 排除，因此 `_if`、`_add`、`_bool` 这类顶层常量名也合法；`_Error` 不是合法 `ReadonlyIdent`。public 模块级可变变量使用普通非保留 `LowerIdent`，private 模块级可变变量在声明位使用非保留 `DotLowerIdent`，使用位仍写去点后的普通 `LowerIdent`。
6. 编译入口只写作 `start() { ... }`，无参数且无返回，且顶层只允许 1 个；wasm 导出名 `_start` 是编译器生成细节。`start` 是声明专用入口，不接受普通函数的显式 `-> nil` 或表达式体写法。
7. 字段默认值按构造上下文求值；顶层常量构造要求字段默认值可 CTFE，运行时构造允许运行时默认值。字段默认值处于 CTFE 上下文时，同样禁止通过调用链写模块级可变变量及其 import alias。

## 14. 标准库草案边界


1. `std` 只通过显式 local import 使用，例如 `path_join = @lib("path.do", join)`；标准库函数仍是普通函数，不进入 `core` 固定调用名集合，也不能补充或遮蔽 `get/set/eq/ne/lt/le/gt/ge/add/sub/mul/div/rem/and/or/xor/shl/shr/rotl/rotr/clz/ctz/popcnt/abs/neg/sqrt/ceil/floor/trunc/nearest/min/max/copysign/len/put/load_*` 这些 core 名。集合或领域能力必须使用非 core 名，例如 `list_add`、`hash_put`、`url_encode`。
2. 已落地的纯 do 基础库不依赖 host ABI，可在当前版本直接实现和测试。当前基础组包括：`src/math.do` 数学/位运算辅助，`src/binary.do` 定宽整数大小端读写，`src/mem.do` `[u8]` 缓冲区读写/复制/填充辅助，`src/atomic.do` 基于 `[u8]` 的 u32 原子语义辅助，`src/bytes.do` 字节序列处理，`src/text.do` 的 `text`/`[u8]` 边界与文本辅助，`src/utf8.do`、`src/utf16.do` 编码校验与编解码，`src/hex.do`、`src/base64.do`、`src/url.do`、`src/json.do` 编码/转义库，`src/path.do` 路径字符串辅助，`src/range.do` 范围生成，`src/slice.do` checked storage 切片，`src/fp.do` 高阶组合函数，`src/list.do`、`src/set.do`、`src/hash_map.do` 集合封装，以及 `src/md5.do`、`src/sha1.do`、`src/sha256.do` 这类纯计算库。
3. `src/math.do` 属于 `std` 数值辅助库，不改变 core 算术、位运算和浮点 primitive 语义；只保留比 core 多出实际语义的辅助，例如所有整数类型的 `_type_min/_type_max` 边界常量、`_f32_e/_f32_pi/_f32_half_pi/_f32_tau/_f32_sqrt2` 与对应 `f64` 数学常量、`wrap_u32/add_wrap_u32/mul_wrap_u32`、`bit_at_u32/bit_not_u32`、`clamp_i8/clamp_i16/clamp_i32/clamp_i64/clamp_isize`、`clamp_u8/clamp_u16/clamp_u32/clamp_u64/clamp_usize`、`add_saturating_u32/sub_saturating_u32/mul_saturating_u32`、`add_checked_u32/mul_checked_u32`。`std` 不提供只是套一层 core 的纯转发函数；`@and/@or/@xor/@shl/@shr/@rotl/@rotr/@clz/@ctz/@popcnt/@abs/@neg/@sqrt/@ceil/@floor/@trunc/@nearest/@min/@max/@copysign` 直接在源码中调用。checked API 使用调用者提供的 fallback 加 `bool` 结果，避免引入 zero value。
4. `src/binary.do` 属于 `std` 字节编解码辅助库，提供 `read_u16_le/read_u16_be/read_u32_le/read_u32_be/read_u64_le/read_u64_be` 与 `write_u16_le/write_u16_be/write_u32_le/write_u32_be/write_u64_le/write_u64_be` 这类显式大小端函数；little-endian read 包装 core `@load_*_le`，big-endian read 显式组合字节；越界仍由底层 storage 前置条件处理，不返回额外错误枚举。`src/mem.do` 属于 `std` 缓冲区辅助库，公开 `mem_len/mem_can_access/mem_read_*/mem_write_*/mem_read_bytes/mem_write_bytes/mem_fill/mem_copy` 及对应 `_or` checked 包装；little-endian 定宽 read 包装 core `@load_*_le`，未带 `_or` 的函数遵守前置条件，带 `_or` 的函数在越界时返回 fallback 或原 buffer 加 `false`。当前 `mem.do` 的内存载体是 `[u8]`，不暴露裸指针或线性内存 index。
5. `src/atomic.do` 属于 `std` 原子语义辅助库，当前公开 u32 little-endian 形态的 `atomic_load_u32/atomic_store_u32/atomic_exchange_u32/atomic_compare_exchange_u32/atomic_fetch_add_u32/atomic_fetch_sub_u32/atomic_fetch_or_u32/atomic_fetch_and_u32/atomic_fetch_xor_u32`。第一版实现基于 `[u8]` 和 `mem.do` 锁定 API 与返回值形态，不承诺生成硬件 shared-memory atomic 指令；未来若编译器引入真实 shared memory/atomic lowering，优先保持这些公开函数签名不变。
6. `src/bytes.do` 面向原始 `[u8]`，提供 `is_empty/copy/concat/repeat_byte/slice/slice_or/take/take_or/drop/drop_or/first/first_or/last/last_or/starts_with/ends_with/contains/index_of/last_index_of/trim_left_byte/trim_byte/trim_right_byte/replace` 这类字节序列辅助；`src/text.do` 不声明 `Text` 类型，公开 `bytes_of(s text) -> [u8]`、`text_from(bytes [u8]) -> text | Utf8Error`、`byte_len(s text) -> usize`、`char_len(s text) -> usize | Utf8Error` 作为 `text` 与 `[u8]` 的显式边界，并继续提供 `is_empty/is_valid_utf8/validate_utf8/count_utf8/copy/concat/repeat_byte/starts_with/ends_with/contains/index_of/last_index_of/slice_or/take/take_or/drop/drop_or/first/first_or/last/last_or/trim_left_byte/trim_byte/trim_right_byte/replace` 这类 `[u8]` 文本辅助。`src/utf8.do` 公开 `Utf8Error`、`Utf8Decode` 以及 `decode_at/code_at/size_at/encode/validate/is_valid/count`；`src/utf16.do` 公开 `Utf16Error`、`Utf16Decode` 以及同名 UTF-16 code unit 辅助。UTF-8 与 UTF-16 库错误是普通 `Utf8Error` / `Utf16Error` union 返回，不是 primitive safety failure；成功 payload 需要按实际 union 分支分别使用 `@is(value, text)`、`@is(value, usize)`、`@is(value, Utf8Decode)`、`@is(value, Utf16Decode)`、`@is(value, u32)`、`@is(value, [u8])`、`@is(value, [u16])` 或 `@eq(value, nil)` 收窄后再做 payload 字段读取、`@len/@get` 或值比较。非法 UTF-8 原始字节必须用 `[u8]` 聚合输入，例如 `.{255}`；非法 UTF-16 surrogate 必须用 `[u16]` 聚合输入。`text` 的源码字面量和行字符串仍必须满足有效 UTF-8。`first/last` 是前置条件包装，`first_or/last_or` 在空 `[u8]` 时返回 fallback 加 `false`。
7. `src/hex.do` 提供 `encode/encode_upper/decode`，错误通过 `HexError` 的具体分支值返回；`src/base64.do` 提供 `encode/encode_raw/encode_url/encode_raw_url/decode/decode_raw/decode_url/decode_raw_url`，并保留 `Encoding/new/with_padding/without_padding/encode_with/decode_with` 用于显式 alphabet 和 padding 策略；`src/url.do` 提供 `url_encode/url_decode`；`src/json.do` 提供 JSON 字符串层面的 `escape/quote/unescape`，并提供 `stringify(value T) -> [u8] | JsonError`、`stringify_with_depth(value T, max_depth usize) -> [u8] | JsonError` 和 `from_json(bytes [u8]) -> T | JsonError` 的结构体字段序列化/反序列化入口。`from_json` 调用必须显式绑定目标类型，例如 `from_json<User>(bytes)`。这些签名和下列支持矩阵是当前稳定公开边界，不表示语言拥有通用 `Serialize/Deserialize` 协议、运行时 JSON AST 或任意类型自动序列化兜底。`stringify/stringify_with_depth` 默认最大嵌套深度为 128；深度耗尽返回 `JsonError` 的 `MaxDepth` 分支。`from_json` 当前不承诺嵌套深度上限，也不通过 `MaxDepth` 表达解析深度错误。当前 `stringify` 按可见字段声明顺序输出 object，字段名使用 JSON string quote，字段值编码覆盖 `i32`、`text`、`[u8]`、`bool`、嵌套结构体以及字段级 `T | nil`；嵌套结构体通过字段反射和普通重载递归编码。当前 `from_json` 的 root 只覆盖可默认构造的结构体 object 解码：实现会先构造目标类型的默认 seed，因此目标 struct 必须能通过 `.{}` 构造；字段值覆盖 `i32`、`text`、`[u8]`、`bool` 以及嵌套结构体；缺失字段保留构造默认值；顶层 `from_json<i32>("7")`、`from_json<text>("\"x\"")` 这类 scalar root 暂不属于 v1 支持矩阵。v1 不自动支持非 `i32` 整数宽度、任意 union、value enum、error、map/list 抽象类型或非 `[u8]` storage 的 JSON 序列化/反序列化；需要这些类型时，用户应先写具体转换或专用 wrapper。不声明 JSON AST。上述库都以 `[u8]` 为主要输入输出，错误分支值判断使用 `eq/ne`。
8. `src/path.do` 是纯字节路径字符串辅助库，当前只做语法级路径拼接和拆分，不访问文件系统；提供 `is_absolute/is_empty/join/basename/dirname/extname`。这些函数不判断路径是否存在，也不处理工作目录、符号链接、权限或平台文件系统状态。
9. `src/range.do` 提供 `range_usize/range_i32/repeat_usize/repeat_i32` 这类生成 `[T]` 的基础函数；区间统一为左闭右开 `[from, end)`。当前只提供明确类型后缀的函数，不引入依赖返回值反推的泛型 range。
10. `src/slice.do` 是 `[T]` 的 checked 切片辅助库，`slice/take/drop` 在越界或区间非法时返回 `SliceError`，`slice_or/take_or/drop_or` 使用 fallback 加 `bool`；`first/last` 是前置条件包装，`first_or/last_or` 在空 storage 时返回 fallback 加 `false`。它不改变 core `get/set` 的前置条件语义，只为调用者提供显式 checked 包装。
11. 高阶组合函数属于 `std`，不属于 `core`；`src/fp.do` 承载通用函数式组合工具，例如 `apply(value, f)`、`tap(value, f)`、`repeat(value, times, f)`、基于 `[T]` 的 `map/filter/fold/reduce/find/find_index/any/all/count` 与 `pipe(...)`。`pipe` 用固定 arity 重载提供异构串联，不引入类型级函数链或异构不定参数。每个重载用具名函数类型约束表达相邻步骤，例如 `#F = (A) -> B`、`#G = (B) -> C` 与 `pipe(value A, f F, g G) -> C`；标准库提供 1 到 8 段 `pipe` 重载。`rest ...T` 仍只表达同类型不定参数，不能表达 `(A) -> B, (B) -> C, ...` 这种异构类型链。`find/reduce` 使用 fallback checked API：`find(xs [T], fallback T, p P) -> T, bool`、`find(xs [T], fallback T, env E, p P) -> T, bool`、`reduce(xs [T], fallback T, p P) -> T, bool`。失败或空序列返回 `fallback, false`；命中或成功归约返回真实值与 `true`。因为语言没有 zero value，fallback 由调用者显式提供；若 `T` 本身包含 `nil`，`bool` 用于区分业务 `nil` 与未命中。
12. `src/list.do` 提供 `empty_list(seed)/list_from_items(data)/items/list_len/list_is_empty/list_index_of/list_has/list_get/list_get_or/list_first/list_first_or/list_last/list_last_or/list_set/list_set_or/list_add/update/update_or/del/del_or/clear` 等基础集合操作，并为 `List<T>` 提供薄封装的 `map/filter/fold/reduce/find/find_index/any/all/count`，内部通过 `items(list) -> [T]` 复用 `src/fp.do` 的 `[T]` 序列算法。`list_add(xs List<T>, value T, rest ...T) -> List<T>` 表示尾部追加，内部通过 core storage `@put([T], value, rest...)` 更新私有 storage。`List<T>` 不接入内建 `@len/@get/@set/@put`，需要循环时通过 `items(list) -> [T]` 视图。`List<T>` 带无默认值 private storage 字段，外部模块不能直接写 `List<T>{}` 或 `.{}` 构造；空 list 通过 `empty_list(seed)` 提供类型种子，已有 storage 通过 `list_from_items(data)` 包装。`list_get/list_first/list_last/list_set/update/del` 是前置条件包装；`list_get_or/list_first_or/list_last_or/list_set_or/update_or/del_or` 是普通 `std` checked API，越界或空 list 时返回 fallback 或原 list，并返回 `false`；其内部实现不绑定 core checked primitive。core 中不存在 `get_or/set_or` 保留形态，这些 `_or` 名字只是标准库普通函数名。
13. `src/set.do` 提供基于 `[T]` 和 `@eq` 值语义的简单集合封装：`empty_set(seed)/set_from_items(seed, data)/set_len/set_is_empty/items/set_has/set_add/set_add_many/set_del/set_union/set_intersection/set_difference/clear`。`Set<T>` 带无默认值 private storage 字段，外部模块不能直接构造内部状态；空 set 通过 `empty_set(seed)` 提供类型种子。当前实现是线性扫描集合，用于先锁定 API 和语义，不承诺哈希性能。
14. 删除闭包捕获后，`map/filter/find/find_index/any/all/count/update` 提供显式 `env` 重载，例如 `map(xs, env, (x, env) => ...)`。
15. `src/hash_map.do` 提供 `empty_hash_map(key, value)/hash_map_from_parts(keys, values)/hash_len/hash_is_empty/hash_has/hash_get/hash_get_or/hash_set/hash_set_or/keys/values/has/hash_put/update/update_or/del/del_or/clear/entries` 等基础映射操作；`HashMap<K, V>` 带无默认值 private storage 字段，外部模块不能直接写 `HashMap<K, V>{}` 或 `.{}` 构造；空 map 通过 `empty_hash_map(key, value)` 提供 key/value 类型种子，已有 key/value storage 通过 `hash_map_from_parts(keys, values)` 包装。`HashMap<K, V>` 不接入内建 `len/get/set/put`；`keys/values/entries` 返回 `[T]` 视图用于循环。`hash_get/hash_set/update/del` 是前置条件包装；`hash_get_or/hash_set_or/update_or/del_or` 是普通 `std` checked API，缺 key 时返回 fallback 或原 map，并返回 `false`；`clear` 返回同 key/value 类型的空 map。其内部实现不绑定 core checked primitive。core 中不存在 `get_or/set_or` 保留形态，这些 `_or` 名字只是标准库普通函数名。
16. 当前 `src/hash_map.do` 是标准库语义草案实现，可用连续 key/value 存储先锁定公开 API；真实 hash bucket、冲突处理和扩容策略后续在不改变公开函数族的前提下替换内部实现。
17. `src/net.do` 只承载 `SocketAddr` 及地址构造/读取/判断函数。
18. `src/tcp.do` 承载 `TcpError`、`TcpListener`、`TcpStream` 等 do 层类型形态。`src/udp.do` 承载 `UdpError`、`UdpSocket` 等 do 层类型形态。它们当前不在源码里手写 `wasi:sockets/*` 的 raw `host_` ABI 边界，真实 I/O API 留到 host ABI lowering、WIT resource 生命周期和 stream ownership 规则明确后实现。
19. `src/file.do`、`src/dir.do`、`src/io.stream.do`、`src/tcp.do`、`src/udp.do`、`src/http.client.do` 这类涉及 WIT `resource`、`result`、`variant`、`flags` 或异步 future 的模块，公开 API 只暴露 do 层类型、错误枚举和多返回值形态。已登记且已 lower 的私有 `@wasi` binding 可以写在对应标准库模块内部，例如 `src/file.do` 当前用 `descriptor.read/write/sync/link-at/open-at/drop` 包装成 `read_file/write_file/flush_file/link_file/open_file_at/close_file`，`src/dir.do` 当前用 `descriptor.open-at/create-directory-at/remove-directory-at/drop` 包装成 `open_dir_at/create_dir_at/remove_dir_at/close_dir`，`src/io.stream.do` 当前用 `input-stream.read` 和 `output-stream.check-write/write/flush` 包装成 `read_stream/check_write_stream/write_stream/flush_stream`。`File`、`Dir`、`InputStream` 和 `OutputStream` 当前统一表达为带私有 `.id i64` 字段的 do 层不透明句柄结构；外部模块只能接收和传递这些值，不能构造、读取或修改 `.id`，也不能假定它们由 ARC 自动关闭。进入私有 `@wasi` 调用时，wrapper 显式读取 `.id` 并按已登记 ABI 收窄为 WIT resource handle；资源生命周期继续由公开 wrapper 函数表达。`StreamError` 是 wrapper-local 错误枚举：WIT `stream-error` 当前只对应 `StreamClosed`，`StreamReadFailed` / `StreamCheckWriteFailed` / `StreamWriteFailed` / `StreamFlushFailed` 只用于标准库 wrapper 内部的故障分类；`output-stream.check-write` 只是 capacity query，不是写操作；当前没有 `close_stream` 公开 API。未登记或尚不能 lower 的复杂 WIT 签名仍不写进可导入标准库源码，例如 `tuple<input-stream, output-stream>`、`future-incoming-response`。原因是这些 WIT type 还不是普通 do 源码公开类型，当前也不能全部由 `do build` 降成普通 core WAT。后续 P3 component lowering 实现后，可以由标准库私有绑定层或编译器生成层继续承接 raw WIT 签名，再由公开函数包装成 do 自己的结构、枚举和多返回值形态。
20. `std` 中需要 host 能力的库按两层落地：公开层只暴露 do 自己的结构、枚举和函数形态，例如 `Datetime`、`now() -> Datetime`、`File`、`FileError`、`close_file(...) -> nil`。已经按 WASI 0.3 draft 校准且不泄漏 raw WIT 公开类型的 wrapper 可以先放在对应标准库模块里，并用私有 host import 声明承载, 例如 `.host_now = @wasi("clocks/system-clock/now", () -> Datetime)`、`.host_random_u64 = @wasi("random/random/get-random-u64", () -> u64)`、`.host_random_bytes = @wasi("random/random/get-random-bytes", (u64) -> list<u8>)`、`.host_input_read = @wasi("io/streams/input-stream.read", (input-stream, u64) -> result<list<u8>,stream-error>)`、`.host_output_check_write = @wasi("io/streams/output-stream.check-write", (output-stream) -> result<u64,stream-error>)`、`.host_output_write = @wasi("io/streams/output-stream.write", (output-stream, list<u8>) -> result<_,stream-error>)`。WIT `list<u8>` 可在标准库边界映射为 do 的 `[u8]`，WIT `result<list<u8>,stream-error>`、`result<u64,stream-error>` 和 `result<_,stream-error>` 这类已登记 result-area 形态可在私有 wrapper 内转成 do 多返回值和具体错误枚举；WIT resource-drop 没有普通错误结果, 公开 close/drop wrapper 必须返回 `nil`。不允许把 WIT `resource`、`result`、`variant`、`flags` 作为普通公开类型泄漏。这保证源码层不绑定宿主细节，后续替换底层 lowering 时不影响普通调用者。第一版不新增集中式 `wasi.do` 边界文件。host import alias 仍不是 local import 目标；其他文件不能写 `host_now = @lib("time.do", host_now)`，只能导入 `now = @lib("time.do", now)` 这类公开包装函数。当前 `do build` 可以通过导入公开 wrapper 收集其所在模块的 `@wasi` binding manifest；已登记的 scalar/record/list<u8> wrapper 和少量已登记 result-area wrapper 可以 lower 到 core WAT，未知或复杂 WIT 签名 wrapper 在实际调用时仍会被拒绝。
    ```do fragment ok
    Datetime {
        seconds i64
        nanoseconds u32
    }

    .host_now = @wasi("clocks/system-clock/now", () -> Datetime)

    now() -> Datetime {
        return host_now()
    }
    ```
22. 这与 Go/Rust/Zig 的标准库分层方向一致：地址类型、TCP listener/stream 和 UDP socket 分离；差异是 `do` 的最终目标是 wasm，因此系统调用能力必须由宿主桥接提供。
23. host resource 使用不透明句柄值表达，不暴露指针或引用；第一版不新增 `opaque` 顶层语法，标准库用 public struct + private fields 封装句柄，例如 `File { .id i64 }`。外部模块可以持有和传递 `File`，但不能读取、改写或构造 `.id`，也不能通过 `File{}` 或 `file File = .{}` 伪造空句柄，只能通过定义模块提供的函数获得有效值；需要空状态时写 `File | nil`。若暂时通过 `@env` 标量 ABI 承载句柄，字段可用 `i64` 表达，但定义模块必须保证存入 public 句柄值的 id 满足非负且有效的不变量，host 返回的负数或 invalid sentinel 必须在模块边界转成具体错误枚举分支值，不能进入 `File`。WIT resource-drop 没有普通错误结果, 因此 `close_file` / `close_dir` 这类 close/drop wrapper 固定返回 `nil`, 可以作为显式 cleanup；必须由业务处理的失败仍放在显式 `flush_*`、`sync_*`、`write_*`、`read_*`、`open_*`、`create_*`、`remove_*` 等有 status/result 的函数里返回具体错误枚举。`defer` 不隐式传播、丢弃、聚合或覆盖原返回错误；body error 与 cleanup 调用顺序仍由源码显式保存和判断。对返回错误枚举的 resource API，closed handle 是普通 enum 分支值；enum 分支值仍是顶层裸 `UpperIdent`，因此标准库应直接使用足以区分领域的分支原名，例如 `FileClosed`、`TcpClosed`。


## 15. 测试声明模型


1. 测试写作顶层声明，语法只允许 `test "name" { ... }`；`test` 是声明专用名，不接受普通函数的显式 `-> nil` 或表达式体写法。
   ```do program ok
   test "list add" {
       xs [i32] = .{1, 2}
       return
   }
   ```
   反例:
   ```do program err
   test "list add" => nil

   test "list add" -> nil {
       return
   }
   ```
2. 测试块的返回语义等价于 `() -> nil`；本版测试失败通过条件、诊断或 compiled runner trap 触发，不通过返回合成 `Error` 表达。
3. `return` 或 `return nil` 表示通过。
4. 测试声明可就近放在被测声明旁边，保持模块内就近测试。
5. 默认 `do test <input.do>` 当前保留静态 runner，输出三态: `ok` 表示测试体静态执行到通过条件或显式 `return`；`failed` 表示已支持的静态断言确定失败，或断言表达式进入 `unknown`；`skipped` 表示测试体依赖静态 runner 尚未支持的控制流、导入调用、复杂表达式或 lowering 能力。静态 runner 遇到 `failed` 返回非零，只有 `ok/skipped` 时返回零。`do test <input.do> --compiled -o out.wat` 是 opt-in compiled runner 输出路径: 每个测试块写入 `;; compiled-test N "name"` manifest 注释, lower 成内部 `__test_N` 函数并导出同名 export, `_start` 仍依次调用这些函数；测试体执行到 `return` 表示通过, 控制流落到测试块末尾会执行 `unreachable` 作为失败 trap。测试 harness 可逐个调用 `__test_N` export 并用 manifest 定位到源码测试名。后续默认 runner 可迁移到 compiled 执行, 但不改变测试声明语法。
6. 执行模型由测试 runner 决定；runner 可支持“同环境连续执行”和“每例新环境执行”两种模式。
7. `test` 声明不参与模块 public API 导出。


## 16. PEG 主文法

parser 可执行 PEG 单独维护在 `doc/grammar.peg`。该文件按 token 流定义主文法; lexer 层剔除空格、制表符和换行; `DeclSep` / `LineGap` / `StmtGap` / `SoftGap` 都是相邻 token line metadata 的关系谓词或空隙谓词, 不是实体 token, 也不能写成可重复消费项。

`WitType` 只出现在 `@wasi(...)` 的 host import 签名里；其中 `char` 等尚未进入 Do 源码类型系统的 WIT 标量名只是 ABI 边界 token。WIT `string` 映射到 Do 源码 `text`，标准库在和原始字节交互时必须显式使用 `[u8]` 转换边界。

`ReservedWord` 是语言控制流与字面量保留词，不能作为普通 `LowerIdent` 名字使用。`BuiltinSpecialName` 是编译器 special form 名，只能按对应 `@name(...)` 内建形态、`RecvExpr` 形态或 `fields(TypeOrTypeParam)` 循环源形态调用，不能作为裸函数值，不能进入普通 `CallExpr` 候选集，也不能参与普通函数重载；它也不能用于普通函数声明名、普通 lower 导入别名、普通参数名或普通 lower 局部绑定名。`ReservedCoreAccessName` 当前只包含 `get/set`，它们只在 `@get/@set` 路径 primitive 调用形态中使用，不是普通函数族。`FieldReflectFuncName` 是字段反射内建调用名，只能通过 `@field_name/@field_index/@field_has_default/@field_get/@field_set` 固定形态使用，字段元数据来源必须是 `fields(TypeOrTypeParam)` 循环绑定。`CoreFixedFuncName` 是 core 固定函数调用名，只能在 `CoreFixedCallExpr` 中通过 `@name(...)` 调用，不能作为普通函数声明名、普通 lower 导入别名、普通参数名、普通 lower 局部绑定名或接口函数约束名，也不能参与普通函数重载；但它不进入字段保留集合，字段可使用 `len/add/popcnt` 这类实际 name。`update/del/to_text` 不属于 `CoreFixedFuncName`，仍是普通库函数名。`FieldReservedName` 是字段名、字段初始化名和字段路径段的保留集合，只排除关键字、`get/set`、声明专用名和保留类型名。`recv` 只在消费循环的 `RecvExpr` 中使用，不是普通函数名；`fields` 只在字段反射循环源中使用，不是普通函数名。`DeclOnlyName` 属于声明专用名，只能分别作为顶层入口声明 `start() { ... }` 与顶层测试声明 `test "name" { ... }`，不能出现在普通值位或调用位。`ReservedTypeName` 属于保留类型名，不能作为普通 lower 名、字段名、普通 lower 导入别名或函数名；其中 `text` 是源码基础类型，`Error` 是编译器内部合成视图名，不进入 `BaseTypeName`，也不能作为源码类型位；`char` 当前只在 WIT ABI 签名里可用，不进入普通源码类型系统，但作为 WIT-only 名字仍在普通源码名字空间保留。循环标签名按独立命名空间处理。以上这些保留规则都不追溯到 `ReadonlyIdent` 主体，因此 `_if`、`_add`、`_bool` 仍可作为只读名字；`_Error` 不是 `_` + `LowerIdent`，非法。

`src/_.do` 只放默认可见的 builtin/core 声明表。`std` 类型与库函数继续放在各自模块里，不写入这张表。


## 17. 诊断与测试约定

### 17.1 语法错误诊断

1. 任意位置出现语法错误时，编译器立即停止。
2. 语法错误诊断包含文件、行、列、源码行和错误位置指示。
3. 语法错误诊断只展示该位置允许的语法形式和正确示例；示例只展示可接受形态。
4. 编译器只接受本文列出的写法；其他输入触发语法错误诊断。
5. 语法错误测试保留少量 parser 诊断烟测，用于锁定“首错停止 + 位置 + 正确语法示例”的输出契约。
6. 语义、类型和语言契约错误仍可维护针对性 `err` 用例，例如类型不匹配、不可见名字、导出边界、重复声明和协议不满足。
7. 当前 typecheck 第一阶段验证导入函数别名调用的重载实参数量，并验证本文件 lambda 实参对本地函数重载的参数形状匹配；完整参数类型、跨模块 lambda 目标类型和泛型返回推导后续纳入同一阶段。

### 17.2 示例与测试提取

详细 fenced code 约定、命名约定与扩展示例统一维护在 `./spec_examples.md`。本节只保留主规范要求。

1. 规范示例可展示合法 `ok` 写法与错误 `err` 反例；`ok` 表示应接受，`err` 表示应拒绝。
2. `err` 反例只展示触发错误的最小形态；编译器在错误位置报告诊断，并展示对应的合法语法形态。
3. 错误回归放在 `tool/build/test/err` 或 `tool/build/test/compile_err`；合法示例放在 `tool/build/test/ok` 或 `tool/build/test/compile_ok`。本文新增 `do err` 反例进入实现主干前，应同步为对应错误回归或明确标记为文档反例。
4. 新增或修改示例必须使用显式层级标签与状态标签，例如 `do program ok`、`do decl err`、`do stmt ok`；遗留 `do ok` 仅作存量兼容，并在触达时迁移。


## 18. 非目标


1. 本版不承诺 timezone、calendar、duration 类型或本地化时间格式化；`src/time.do` 当前只提供已声明的基础时间戳、单调时钟和毫秒换算辅助。
