# do 语言规范示例附录

本文件只保留与 `doc/spec.md` 当前版本一致的扩展示例和测试提取约定。已经合并进主规范的历史决策题面不再保留。

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
    state = add(state, 1)
    return state
}
```

```do program err
.state i32 = 0

next() -> i32 {
    .state = add(.state, 1)
    return .state
}
```

顶层 private value 只在声明位使用前置 `.`；同模块内读写使用去点后的实际 name。

## 约束块

### 未知数据类型接口

```do program ok
to_text(x i32) -> [u8] {
    return "i32"
}

#T
#to_text(T) -> [u8]
show(x T) -> [u8] {
    return to_text(x)
}
```

```do decl err
#to_text(i32) -> [u8]
show_i32(x i32) -> [u8] {
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

无等号 `#T` 只声明未知数据类型参数。函数上的未知数据类型参数只要能从参数侧唯一求解，就可以只出现在参数或返回类型里；函数体需要调用 `T` 的能力时，才必须通过函数类型约束或接口函数约束承载。接口函数约束必须引用同块更早声明的数据类型参数；不支持 `#to_text(i32) -> [u8]` 这类具体函数签名存在性断言。

### 非法受限和派生约束

```do decl err
to_text(x i32) -> [u8] {
    return "i32"
}

#T = i32 | i64
#to_text(T) -> [u8]
show_number(x T) -> [u8] {
    return to_text(x)
}
```

```do decl err
User {
    id i32
}

to_text(x User) -> [u8] {
    return "user"
}

#T
#Q = T | User
#to_text(T) -> [u8]
choose(fallback T, value Q) -> [u8] {
    if is(value, User) return "user"
    return to_text(fallback)
}
```

函数约束块里不支持 `#T = A | B` 受限数据类型参数，也不支持 `#Q = T | User` 这类局部派生候选集合。具体 union 需要命名时使用普通顶层 union alias；依赖未知类型参数的派生 union 第一版不提供局部命名语法。

### 函数类型约束

```do program ok
inc(x i32) -> i32 {
    return add(x, 1)
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
    if is(x, F) return x(1)
    return x
}
```

```do decl err
#T
#F = (T) -> T
accept(x T | F) -> T {
    if is(x, F) return x(1)
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

MaybeUser = User | nil

collect(rest ...MaybeUser) -> i32 {
    return 0
}
```

```do decl err
User {
    id i32
}

#MaybeUser = User | nil
collect(rest ...MaybeUser) -> i32 {
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

变参元素类型属于参数位，实际类型不得是 union/nullable。`rest ...User | nil` 和通过 `MaybeUser = User | nil` 间接写出的 `rest ...MaybeUser` 都非法。需要处理可空元素时，把 union 放在 storage 元素里，例如参数写 `xs [User | nil]`，或让调用方先过滤/收窄后再传入 `rest ...User`。

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
    if eq(value, nil) return 0
    if is(value, User) return 1
    return 0
}
```

```do decl err
#T
use(value T) -> T {
    if is(value, T) return value
    return value
}
```

`is(value, T)` 只有在 `value` 的静态类型已经显式暴露候选集合时才构成真正收窄。单独的未知数据类型参数 `T` 没有可扣减候选集合，因此不能写 `is(value, T)`。

```do program ok
User {
    id i32
}

ready() -> bool {
    return true
}

load_user() -> User | nil {
    return nil
}

use() -> i32 {
    v = load_user()
    if and(is(v, User), ready()) return 1
    return 0
}
```

```do program ok
ready() -> bool {
    return true
}

count() -> i32 {
    return 1
}

check() -> bool {
    return and(ready(), eq(count(), 1))
}
```

```do program err
User {
    id i32
}

ready() -> bool {
    return true
}

check(v User | nil) -> bool {
    return and(is(v, User), ready())
}
```

`is` 只能出现在条件位, 或嵌套在条件位的 `and/or/not` 参数里。普通 `bool` 表达式可以使用 `and/or/not`, 但参数中不能间接出现 `is`。函数参数位也不接收 `User | nil`；需要判断 union 时，让函数返回 union，或先在调用方的局部值里判断后再传入单一类型。

```do stmt ok
if eq(err, NotFound) return
```

`eq/ne` 做值判断。`nil` 只能用 `eq/ne` 判断，不能写进 `is` 的第二参数。

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

```do decl err
FileError error = FileNotFound | FilePermissionDenied
NetworkError error = NetworkTimeout | NetworkClosed

App = FileError | NetworkError
```

错误枚举右侧只接收 enum 分支值，不接收已知错误枚举类型；也不能通过普通 union alias 把多个错误枚举重新命名成新的纯错误聚合。需要组合多个错误来源时, 在返回位、字段或局部绑定里直接写具体来源；参数位仍不接收这种 union。

## 函数值展示

```do program ok
#F = (i32) -> [u8]
to_text(f F) -> [u8] {
    return "fn(i32) -> [u8]"
}
```

```do program err
#F = (i32) -> [u8]
debug(f F) -> [u8] {
    _ = f(1)
    return to_text(f)
}
```

第二个例子只有在当前可见范围里已经显式定义 `to_text(F) -> [u8]` 时才成立；语言和 `std` 不提供默认函数值展示。

## import

```do program ok
User = @./user.do/User
Profile = @./profile.user.do/User
MongoClient = @~/tom.mongo.do/Client
Client2 = @~/tom.2024.db.do/Client
abs = @math.do/abs
console_log = @env/console_log(i32, i32) -> nil
```

```do program err
User = @./model/user.do/User
User = @./user/User
MongoClient = @~/mongo/client.do/Client
tool = @2024.tool.do/run
now = @/time.do/now
console_log = @env/console/log(i32, i32) -> nil
```

local import 只支持当前目录单文件、外部依赖根单文件和标准库单文件三类入口。host import 第一版只支持固定 `@env/host_name(...) -> ...`。

## get / set

```do stmt ok
name [u8] = get(user, .name)
next = set(user, .name, "tom")
```

```do stmt err
name, ok = get(user, .name)
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
FileError error = FileOpenFailed | FileFlushFailed | FileCloseFailed

File {
    .id i64
}

open_file(path [u8]) -> File | FileError {
    return File{id = 1}
}

flush_file(file File) -> FileError | nil {
    return nil
}

close_file(file File) -> FileError | nil {
    return nil
}

use(path [u8]) -> FileError | nil {
    file_result = open_file(path)
    if is(file_result, FileError) return file_result
    file File = file_result

    flush_err = flush_file(file)
    close_err = close_file(file)

    if is(flush_err, FileError) return flush_err
    return close_err
}
```

```do decl err
bad(file File) -> FileError | nil {
    defer {
        _ = close_file(file)
    }

    return nil
}
```

v1 没有可用 `defer` 语句。资源 cleanup 必须显式调用，并由源码显式保存和处理 close error；如果后续版本启用 `defer`，也不隐式传播、丢弃、聚合或覆盖原返回错误。

## CTFE

```do program ok
double(x i32) -> i32 {
    return add(x, x)
}

_size i32 = double(21)
```

```do program ok
state i32 = 0

next() -> i32 {
    state = add(state, 1)
    return state
}
```

```do program err
state i32 = 0

bump() -> i32 {
    state = add(state, 1)
    return state
}

_init i32 = bump()
```

```do program err
state i32 = 0

next() -> i32 {
    state = add(state, 1)
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
