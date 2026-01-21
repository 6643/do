// 结构体定义参考
User {
    id   i32
    name Text
}

// 函数签名 (用于声明或约束)
// get_id(User) -> i32

// 函数实现 (无 ->)
get_id(user User) i32 {
    return user.id
}

// 泛型函数
identity<T>(val T) T {
    return val
}

// 匿名返回/隐式返回示例
to_string(u User) Text {
    return "ID: ${u.id}"
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
    return Tuple<i32, i32>{1, 2}
}

test "multi-return handling" {
    // 显式处理 Tuple 返回值，不使用解构
    pair = parse_pair("data")
    x = pair.0
    y = pair.1
}
