// 简化模式定义
Role {
    name Text
    id   u32
}

User {
    id    u32
    name  Text
    .age  u8
    ._uid u32    // 字段定义保持一致
    role  Role
}

test "full lifecycle with set" {
    _admin_role = set(Role, {
        .name: "Admin",
        .id: 1
    })

    user = set(User, {
        .id: 1001,
        .name: "ZhangSan",
        .age: 18,
        ._uid: 8888,
        .role: _admin_role
    })

    _name = get(user, .name)
    
    // 多级路径保留方括号，单级路径省略
    user = set(user, {
        .name: "LiSi",
        [.role, .name]: "SuperAdmin"
    })

    count = 0
    _final_result = loop {
        if eq(count, 10) {
            count -> 
        }
        count = add(count, 1)
        <- 
    }

    => _final_result
}
