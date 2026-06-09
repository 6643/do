# 结构

## 结构体声明

```do
// public 结构体声明
User {
    id i64
    name text
    active bool
}

// private 结构体声明
.InternalUser {
    id i64
}
```

## 字段默认值

```do
// 标量、文本和连续存储字段默认值
Config {
    port u16 = 8080
    name text = "app"
    flags [u8] = .{1, 2, 3}
}

// 行字符串字段默认值
Page {
    title text =
        \\home
        \\page
}
```

规则: 构造器字段集合由 sema 统一校验。unknown field、duplicate field 和 missing required field 都是错误; 有默认值的字段按声明顺序求值并填入。

## 私有字段

```do
// private 字段声明
User {
    id i64
    .token text
}

// private 字段构造时使用实际字段名
new_user(id i64, token text) -> User {
    return User{id = id, token = token}
}
```

## 泛型结构

```do
// 单类型参数结构
#T
Box {
    value T
}

// 多类型参数结构
#K
#V
Entry {
    key K
    value V
}
```

## 构造

```do
User{}                                      // 空 typed 构造
User{id = 1, name = "tom", active = true}   // typed 字段构造
User{id = 1, name = "tom", active = true,}  // typed 字段构造带尾逗号

user User = .{id = 1, name = "tom", active = true} // 推导结构构造
box Box<i32> = .{value = 1}                        // 泛型结构推导构造
```

规则: 字段名只禁止关键字、声明专用名、路径 primitive 名 `get/set` 和保留类型名。`len/add/to_i32` 这类 core builtin 名可作为字段实际名, 因 core 调用必须带 `@` 前缀。

## 字段读取和更新

```do
name text = @get(user, .name)          // 字段读取
first_name text = @get(users, 0, .name) // 索引后字段读取

user = @set(user, .name, "amy")                         // 字段更新
users = @set(users, 0, .name, "amy")                    // 索引后字段更新
counter = @set(counter, .count, (value i32) => @add(value, 1)) // lambda 更新
```
