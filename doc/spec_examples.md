# do 语言规范示例附录

本文件只保留与 `doc/spec_rules.md` 当前版本一致的扩展示例和测试提取约定。已经合并进主规范的历史决策题面不再保留。

## fenced code 约定

示例 fenced code 使用显式层级和状态标签:

````md
```do program ok
...
```

```do decl err
...
```
````

- `ok` 表示应接受。
- `err` 表示应拒绝。
- `program` 表示完整文件示例。
- `decl` 表示顶层声明片段。
- `stmt` 表示块内语句片段。
- `expr` 表示表达式片段。

## 表达式根位与顶层值

```do program ok
_hello [u8] =
    \\hello
    \\world

say() -> [u8] {
    text [u8] =
        \\hello
        \\world
    return text
}
```

```do decl err
x i32 =
    1

bad() -> i32 {
    return
        1
}
```

普通表达式必须和 `=`、`return` 或 `=>` 保持在同一语句行；只有 `RhsExpr` 的 `LineStringBlock` 可从 `=` 后换到下一行。`return` 位置不直接接收行字符串。

```do program ok
pair() -> i32, bool => 1, true

pair_block() -> i32, bool {
    return 1, true
}
```

```do decl err
pair() -> i32, bool => 1,
    true

pair_block() -> i32, bool {
    return 1,
        true
}
```

`return` 与 `=>` 的多返回列表都使用同一行内逗号分隔。

```do program ok
User {
    name [u8]
}

make() -> User {
    return User{
        name = "tom",
    }
}
```

```do program err
User {
    name [u8]
}

make() -> User {
    return User{
        name =
            "tom",
    }
}
```

```do program err
User {
    name [u8]
}

make() -> User {
    return User{
        name
            = "tom",
    }
}
```

结构体字段初始化 `field = value` 中, 字段名、`=` 和普通表达式起点必须保持在同一字段初始化项里。

```do program ok
User {
    bio [u8] =
        \\hello
        \\world
}
```

```do program err
User {
    bio [u8]
}

make() -> User {
    return User{
        bio =
            \\hello
            \\world,
    }
}
```

```do program err
xs [[u8]] = .{
    \\hello
    \\world,
}
```

字段默认值走 `RhsExpr`, 可以直接使用行字符串；结构体构造字段初始化和聚合元素不直接接收行字符串，需要先绑定到局部值。

```do program ok
message_with_code() -> [u8], i32 {
    text [u8] =
        \\hello
        \\world
    return text, 200
}
```

```do decl err
message() -> [u8] {
    return
        \\hello
        \\world
}
```

`return` 位置不直接接收行字符串；单返回和多返回都需要先绑定到局部值，再返回该绑定。

```do program ok
.state i32 = 0

next() -> i32 {
    state = @add(state, 1)
    return state
}
```

```do program err
.state i32 = 0

next() -> i32 {
    .state = @add(.state, 1)
    return .state
}
```

顶层 private value 只在声明位使用前置 `.`；同模块内读写使用去点后的实际 name。

## 约束块

### 未知数据类型接口

```do program ok
to_text(x i32) -> text {
    return "i32"
}

#T
#to_text(T) -> text
show(x T) -> text {
    return to_text(x)
}
```

```do decl err
#to_text(i32) -> text
show_i32(x i32) -> text {
    return to_text(x)
}
```

```do program ok
#T
id(x T) -> T {
    return x
}

test "generic id" {
    i i32 = 1
    x = id(i)
    return
}
```

无等号 `#T` 只声明未知数据类型参数。函数上的未知数据类型参数只要能从参数侧唯一求解，就可以只出现在参数或返回类型里；函数体需要调用 `T` 的能力时，才必须通过函数类型约束或接口函数约束承载。接口函数约束必须引用同块更早声明的数据类型参数；不支持 `#to_text(i32) -> text` 这类具体函数签名存在性断言。

### 数据类型参数和具体 union

```do decl ok
to_text(x i32) -> text {
    return "i32"
}

User {
    id i32
}

#T
#to_text(T) -> text
show_value(x T) -> text {
    return to_text(x)
}

choose_user(value User | nil) -> text {
    if @eq(value, nil) return "none"
    return "user"
}
```

函数约束块里的 `#T` 只声明未知数据类型参数。需要具体 union 时，直接在返回位、字段、局部绑定、storage 元素或 type args 里写平铺 union；依赖未知类型参数的派生 union 第一版不提供局部命名语法。

### 函数类型约束

```do program ok
inc(x i32) -> i32 {
    return @add(x, 1)
}

#F = (i32) -> i32
apply(f F) -> i32 {
    return f(1)
}

test "apply function value" {
    x = apply(inc)
    return
}
```

```do decl err
#F = (i32) -> i32
#G = F
apply(f G) -> i32 {
    return f(1)
}
```

函数类型约束只通过 `#F = (...) -> ...` 声明，不允许给已有函数类型约束再起局部别名。

### 泛型回调约束

```do program ok
#T
#F = (T) -> T
apply_one(x T, f F) -> T {
    return f(x)
}
```

```do program ok
#T
pass_through(x T) -> T {
    return x
}
```

`#F = (T) -> T` 表示未来传入的函数值必须符合这个签名，并且它可以承载 `T` 的求解。只有 `#T`、没有函数类型约束或接口函数约束的函数也可以成立，前提是所有普通数据类型参数都能从参数侧唯一求解，且函数体不调用未声明的能力。

### 数据或函数二选一参数

```do decl err
#F = (i32) -> i32
accept(x F | i32) -> i32 {
    if @is(x, F) return x(1)
    return x
}
```

```do decl err
#T
#F = (T) -> T
accept(x T | F) -> T {
    if @is(x, F) return x(1)
    return x
}
```

函数类型只允许作为参数位的单一 `F` 使用。`F | nil`、`F | i32`、`i32 | F`、`T | F` 和 `F | T` 都非法；v1 不支持可选回调参数，也不支持数据或函数二选一参数。

### 变参 union 元素

```do program ok
User {
    id i32
}

collect(rest ...User) -> i32 {
    return 0
}
```

```do decl err
User {
    id i32
}

collect(rest ...User | nil) -> i32 {
    return 0
}
```

```do decl err
#T
#collect(...T | nil) -> i32
use(x T) -> i32 {
    return collect(x)
}
```

变参元素类型属于参数位，实际类型不得是 union/nullable。`rest ...User | nil` 非法。需要处理可空元素时，把 union 放在 storage 元素里，例如参数写 `xs [User | nil]`，或让调用方先过滤/收窄后再传入 `rest ...User`。

### 参数显式类型

```do decl ok
id(value i32) -> i32 {
    return value
}
```

```do decl err
id(value) -> i32 {
    return value
}
```

函数参数必须显式写类型；`value` 这类只写参数名的形式非法。这个规则同样适用于泛型函数声明里的普通参数。

```do decl err
#T
identity(value) -> T {
    return value
}
```

### 局部重声明与遮蔽

```do stmt ok
name text = "a"
name = "b"
```

```do stmt err
name = "a"
name text = "b"
```

```do stmt err
a i32 = 1
{
    a bool = false
}
```

`name Type = expr` 永远声明新绑定；当前作用域或任何外层可见作用域里只要已经有同名绑定，都不能再次写 typed bind，必须改用 `name = expr` 赋值。局部声明也不能遮蔽外层局部绑定、函数参数、loop 绑定、模块级变量或顶层常量。

### loop 绑定只读

```do stmt err
xs [i32] = .{1}
loop value, index = xs {
    value = value
}
```

```do stmt err
xs [i32] = .{1}
loop value, index = xs {
    index = 1
}
```

集合循环和消费循环的头部绑定都是只读绑定；需要修改结果时，先声明新的局部绑定，或更新源集合。

## is / eq / ne

```do program ok
User {
    id i32
}

load_user() -> User | nil {
    return nil
}

use() -> i32 {
    value = load_user()
    if @eq(value, nil) return 0
    if @is(value, User) return 1
    return 0
}
```

```do decl err
#T
use(value T) -> T {
    if @is(value, T) return value
    return value
}
```

`@is(value, T)` 只有在 `value` 的静态类型已经显式暴露候选集合时才构成真正收窄。单独的未知数据类型参数 `T` 没有可扣减候选集合，因此不能写 `@is(value, T)`。

```do program ok
ready() -> bool {
    return true
}

count() -> i32 {
    return 1
}

check() -> bool {
    return @and(ready(), @eq(count(), 1))
}
```

```do program err
User {
    id i32
}

ready() -> bool {
    return true
}

load_user() -> User | nil {
    return nil
}

check() -> bool {
    v = load_user()
    return @and(@is(v, User), ready())
}
```

`is` 只能作为条件头的直接根表达式。普通 `bool` 表达式可以使用 `and/or/not`, 但参数中不能直接出现 `is`; 复合条件 proof engine 保留到 future。

```do stmt ok
if @eq(err, NotFound) return
```

`eq/ne` 做值判断。`nil` 只能用 `eq/ne` 判断，不能写进 `is` 的第二参数。

## lambda

```do program ok
tap = @lib("fp.do", tap)

test "lambda block nil return" {
    value i32 = 1
    next = tap(value, (x i32) -> nil {
        _ = @add(x, 1)
        return
    })
    if @eq(next, 1) return
}
```

```do program ok
tap = @lib("fp.do", tap)

test "lambda block nil sugar" {
    value i32 = 1
    next = tap(value, (x i32) {
        _ = @add(x, 2)
        return
    })
    if @eq(next, 1) return
}
```

block lambda 的目标返回类型若已经确定为 `nil`，可以省略 `-> nil` 直接写 `(x T) { ... }`。若省略参数类型，则仍必须由已选中的目标 `FuncType` 提供参数类型。

## 错误枚举

```do program ok
FileError error = FileNotFound | FilePermissionDenied
NetworkError error = NetworkTimeout | NetworkClosed

sync_file(path [u8]) -> [u8] | FileError | NetworkError {
    return NetworkTimeout
}
```

```do decl err
FileError error = FileNotFound | FilePermissionDenied
NetworkError error = NetworkTimeout | NetworkClosed

AppError error = FileError | NetworkError
```

错误枚举右侧只接收 enum 分支值，不接收已知错误枚举类型。源码没有顶层错误聚合别名；需要组合多个错误来源时, 在返回位、字段或局部绑定里直接写具体来源；参数位仍不接收这种 union。

## 函数值展示

```do program ok
#F = (i32) -> text
to_text(f F) -> text {
    return "fn(i32) -> text"
}
```

```do program err
#F = (i32) -> text
debug(f F) -> text {
    _ = f(1)
    return to_text(f)
}
```

第二个例子只有在当前可见范围里已经显式定义 `to_text(F) -> text` 时才成立；语言和 `std` 不提供默认函数值展示。

## import

```do program ok
User = @lib("./user.do", User)
Profile = @lib("./profile.user.do", User)
MongoClient = @lib("~/tom.mongo.do", Client)
Client2 = @lib("~/tom.2024.db.do", Client)
abs_i32 = @lib("math.do", abs_i32)
console_log = @env("console_log", (i32, i32) -> nil)

Datetime {
    seconds i64
    nanoseconds u32
}

host_now = @wasi("clocks/system-clock/now", () -> Datetime)
```

```do program err
User = @lib("./model/user.do", User)
User = @lib("./user", User)
MongoClient = @lib("~/mongo/client.do", Client)
tool = @lib("2024.tool.do", run)
now = @lib("/time.do", now)
console_log = @env("console/log", (i32, i32) -> nil)
```

local import 只支持 `@lib("file.do", symbol)` 双参数形态里的当前目录单文件、外部依赖根单文件和标准库单文件三类入口。host import 支持固定 `@env("host_name", (...) -> ...)` 和 WIT 目标形态 `@wasi("package/interface/member", (...) -> ...)`；host import alias 只在当前模块内使用，不是 local import target。

## get / set

```do stmt ok
name [u8] = @get(user, .name)
next = @set(user, .name, "tom")
```

```do stmt err
name, ok = @get(user, .name)
```

`get/set` 是 core 路径 primitive 调用，不参与普通重载。`get` 返回单值，不能用多左值接收；`set` 返回更新后的 target。

## 多返回

```do decl ok
pair() -> i32, bool {
    return 1, true
}

use() -> i32, bool {
    return pair()
}
```

```do stmt err
x = pair()
print(pair())
```

多返回调用只能作为多左值赋值的完整右侧，或作为同位数函数的完整 `return` 透传位。

## defer

```do program ok
FileError error = FileOpenFailed | FileFlushFailed

File {
    .id i64
}

open_file(path [u8]) -> File | FileError {
    return File{id = 1}
}

flush_file(file File) -> FileError | nil {
    return nil
}

close_file(file File) -> nil {
    return
}

use(path [u8]) -> FileError | nil {
    file_result = open_file(path)
    if @is(file_result, FileError) return file_result
    file File = file_result

    defer close_file(file)

    flush_err = flush_file(file)
    if @is(flush_err, FileError) return flush_err
    return nil
}
```

```do decl err
bad(file File) -> FileError | nil {
    defer flush_file(file)
    return nil
}
```

`defer` 已支持返回 `nil` 的 cleanup call 和 cleanup block。返回错误枚举的 cleanup 不能放进 `defer`；资源 cleanup 失败必须由源码显式保存和处理。`defer` 不隐式传播、丢弃、聚合或覆盖原返回错误。

```do program ok
cleanup() -> nil {
    return
}

use_loop() {
    loop {
        defer cleanup()
        if @eq(1, 1) break
        continue
    }
    return
}
```

## CTFE

```do program ok
double(x i32) -> i32 {
    return @add(x, x)
}

_size i32 = double(21)
```

```do program ok
state i32 = 0

next() -> i32 {
    state = @add(state, 1)
    return state
}
```

```do program err
state i32 = 0

bump() -> i32 {
    state = @add(state, 1)
    return state
}

_init i32 = bump()
```

```do program err
state i32 = 0

next() -> i32 {
    state = @add(state, 1)
    return state
}

Box {
    value i32 = next()
}

_box Box = Box{}
```

顶层值初始化和顶层常量构造字段默认值处于 CTFE 上下文。CTFE 调用链可以读取模块级值, 但不能写模块级可变变量或它们的 import alias。

## 测试声明

```do program ok
test "list add" {
    xs [i32] = .{1, 2}
    return
}
```

```do program err
test "list add" => nil

test "list add" -> nil {
    return
}
```

测试声明只允许 `test "name" { ... }`。
