# 模块和值

## import

```do
User = @lib("./user.do", User)        // 当前目录类型导入
List = @lib("list.do", List)          // 标准库类型导入
DepUser = @lib("~/acme.user.do", User) // 外部依赖类型导入

_limit = @lib("./config.do", _limit)  // 只读值导入
load_user = @lib("./user.do", load_user) // 函数或全局变量导入
```

## host import

```do
host_now = @env("now", () -> i64)          // public host 函数导入
host_add = @env("add", (i32, i32) -> i32)  // 带参数和返回值的 host 函数导入
.host_log = @env("log", (i32, i32) -> nil) // private host 函数导入
```

## 顶层值

```do
_limit i32 = 10 // 全局不可变常量
counter i32 = 0 // 全局变量
.state i32 = 1  // 全局私有变量
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
User = @lib("./user.do", User)           // 导入类型
load_user = @lib("./user.do", load_user) // 导入函数

_limit i32 = 10 // 全局不可变常量
counter i32 = 0 // 全局变量

start() {
    user User = load_user()                  // 局部绑定
    counter = @add(counter, @get(user, .id)) // 全局变量赋值
    return
}
```
