// 静态结构体定义
Role {
    name Text
    id   u32
}

// 泛型结构体 (无逻辑，纯布局模板)
User<T> {
    id    T
    name  Text
    .age  u8
    ._uid u32
}

test "static struct instantiation" {
    // 实例化时，编译器根据 <u32> 查找或生成对应的结构体 ID
    u = set(User<u32>, {
        .id: 1001,
        .name: "ZhangSan",
        .age: 18,
        ._uid: 8888
    })

    if eq(get(u, .id), 1001) {
        print("Static Generic User success")
    }
}

test "nested static structs" {
    r = set(Role, { .name: "Admin", .id: 1 })
    
    // 嵌套也遵循静态特化
    AdminUser = User<Role>
    au = set(AdminUser, { .id: r, .name: "Boss" })
}