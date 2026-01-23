// 结构体定义参考
User {
    id   i32
    name Text
}

// 函数实现
get_id(user User) i32 {
    return get(user, .id)
}

// 泛型约束
#T{id: i32}
identity(val T) T {
    // 获取字段到变量
    .{id, name} = get(val, .{.id, .name})
    print("User id: ${id}, name: ${name}")
    return val
}

to_string(u User) Text {
    return "ID: ${get(u, .id)}"
}

test "function and struct integration" {
    // 实例化：Type.{ ... }
    u = User.{
        id: 42,
        name: "Alice"
    }
    
    id = get_id(u)
    
    if eq(id, 42) {
        print("Function call success")
    }
    
    // 泛型调用
    v = identity<i32>(100)
}

// 多返回值 (Tuple)
parse_pair(input Text) Tuple<i32, i32> {
    return .{1, 2}
}

test "multi-return handling" {
    // 处理 Tuple 返回值
    pair = parse_pair("data")
    x = get(pair, 0)
    y = get(pair, 1)
}

fn write_log(text Text) {
    file = open("log.txt")
    // 无论函数如何退出，都会执行关闭
    defer close(file)
    write(file, text)
}

test "defer" {
    write_log("Hello, world!")
}
