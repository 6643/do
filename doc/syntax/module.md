# 模块和值

## import

```do
// 当前目录类型导入
User = @lib("./user.do", User)

// 标准库类型导入
List = @lib("list.do", List)

// 外部依赖类型导入
DepUser = @lib("~/acme.user.do", User)

// 只读值导入
_limit = @lib("./config.do", _limit)

// 函数或全局变量导入
load_user = @lib("./user.do", load_user)
```

## host import

```do
// public host 函数导入
host_now = @host("env", "now", () -> i64)

// 带参数和返回值的 host 函数导入
host_add = @host("env", "add", (i32, i32) -> i32)

// private host 函数导入
.host_log = @host("env", "log", (i32, i32) -> nil)
```

## 顶层值

```do
// 全局不可变常量
_limit i32 = 10

// 全局变量
counter i32 = 0

// 全局私有变量
.state i32 = 1
```

## 行字符串值

```do
// 全局不可变文本常量, 值来自行字符串
_hello text =
    \\hello
    \\world
```

## 顶层组合

```do
// 导入类型
User = @lib("./user.do", User)

// 导入函数
load_user = @lib("./user.do", load_user)

// 全局不可变常量
_limit i32 = 10

// 全局变量
counter i32 = 0

start() {
    // 局部绑定
    user User = load_user()

    // 全局变量赋值
    counter = @add(counter, @get(user, .id))
    return
}
```
