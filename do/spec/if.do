_start() {
    id = 1
    if id == 1 {
        print("id==1")
    } else {
        print("id!=1")
    }

    count = if id == 1 { 1 } else { 2 }
    
    // 联合类型解构
    // find 返回 User | nil
    if User(u) := find_user(id) {
        print(u.name) 
    } else {
        print("Not found")
    }

    // 显式 nil 检查
    u = find_user(id)
    if u == nil {
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