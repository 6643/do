_start() {
    id = 1
    if eq(id, 1) {
        print("id==1")
    } else {
        print("id!=1")
    }

    count = if eq(id, 122) { 1 } else { 2 }
    print(count)

    // 联合类型解构
    // find 返回 User | nil
    if User(u) := find_user(id) {
        print(get(u, .name)) 
    } else {
        print("Not found")
    }

    // nil 检查
    u = find_user(id)
    if nil := u {
        print("User is nil")
    }
}

find_user(id i32) User | nil {
    // 模拟逻辑
    => nil
}

User {
    name text
}