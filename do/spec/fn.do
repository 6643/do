// 结构体定义参考
User {
    id   i32
    name Text
}

// 函数签名 (用于声明或约束)
// get_id(User) -> i32

// 函数实现 (无 ->)
get_id(user User) i32 {
    => get(user, .id)
}

// 泛型约束
#T{id: i32}
identity(val T) T {
    //获取字段到变量
    .{id, name} = get(val, .{.id, .name})
    print("User id: ${id}, name: ${name}")
    => val
}

to_string(u User) Text {
    => "ID: ${get(u, .id)}"
}

test "function and struct integration" {
    // 使用新字面量语法
    u = User{
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
    => {1, 2}
}

test "multi-return handling" {
    // 处理 Tuple 返回值，不使用解构
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