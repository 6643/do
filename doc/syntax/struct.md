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

规则: `.token` 只出现在字段声明位和路径位; 同模块构造 private 字段时使用实际字段名 `token = ...`, 不写 `.token = ...`。外部模块不能显式初始化、读取或更新 private 字段; 若 public struct 含无默认值 private 字段, 外部只能通过定义模块提供的构造函数获得值。

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
// 空 typed 构造
User{}

// typed 字段构造
User{id = 1, name = "tom", active = true}

// typed 字段构造带尾逗号
User{id = 1, name = "tom", active = true,}

// 推导结构构造
user User = .{id = 1, name = "tom", active = true}

// 泛型结构推导构造
box Box<i32> = .{value = 1}
```

规则: 字段名只禁止关键字、声明专用名、路径 primitive 名 `get/set` 和保留类型名。`len/add/to_i32` 这类 core builtin 名可作为字段实际名, 因 core 调用必须带 `@` 前缀。

## 字段读取和更新

```do
// 字段读取
name text = @get(user, .name)

// 索引后字段读取
first_name text = @get(users, 0, .name)

// 字段更新
user = @set(user, .name, "amy")

// 索引后字段更新
users = @set(users, 0, .name, "amy")

// lambda 更新
counter = @set(counter, .count, (value i32) => @add(value, 1))
```

## 字段反射

```do
User {
    id i32
    name text = "tom"
    active bool
}

test "struct fields each" {
    user User = User{id = 7, active = true}

    loop field = fields(User) {
        name text = @field_name(field)
        index usize = @field_index(field)
        has_default bool = @field_has_default(field)

        if @eq(name, "id") {
            id_value i32 = @field_get(user, field)
        }
        if @eq(name, "name") {
            name_value text = @field_get(user, field)
        }
    }
    return
}

#T
to_json_object(value T) -> [u8] {
    out [u8] = .{}
    loop field = fields(T) {
        out = append_json_field(out, @field_name(field), @field_get(value, field))
    }
    return out
}
```

规则: `fields(TypeOrTypeParam)` 按声明顺序枚举当前模块可见字段; `TypeOrTypeParam` 可以是具体结构体名, 也可以是泛型函数实例中已绑定为具体结构体的单个类型参数名。`fields` 不是运行时 iterator, 循环体按字段在编译期展开。`@field_index` 是可见字段序列中的 0-based index, 不是持久化 schema id。`@field_get/@field_set` 的结果按每个字段静态定型, 不返回 `any`; `@field_get(value, field)` 作为实参时会按字段静态类型自然触发普通重载分派。异构字段推荐交给具体类型重载处理, 或先用 `@field_name` / `@field_index` 分支, 再在分支内绑定具体类型。
