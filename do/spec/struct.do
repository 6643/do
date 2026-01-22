// 静态结构体定义
Role {
    name Text   //公有，可读写
    id   u32    //公有，可读写
}

// 泛型结构体 (无逻辑，纯布局模板)
User<T> {
    _uid  u32       //公有，可读
    .aid   u32      //私有，可读写
    name  Text      //公有，可读写
    age   u8        //公有，可读写
    goods list<T>   //公有，可读写
}

test "static struct instantiation" {
    // 实例化时，编译器根据 <u32> 查找或生成对应的结构体 ID
    u = User<u32>{
        _uid: 1
        aid: 1001,
        name: "ZhangSan",
    }

    if eq(get(u, .aid), 1001) {
        print("Static Generic User success")
    }

    // 显式解构
    .{name, age} = get(u, {name, age})
    print("User name: ${name}, age: ${age}")


    // 显式设置
    u = set(u, .name, "LiSi")
    u = set(u, .age, 20)
    print(u)

    // 批量设置
    u = set(u, {.name: "LiSi", .age: 20})
    print(u)

    // 批量设置
    u = set(u, {.name: "LiSi", .age: 20})
    print(u)





}

test "nested static structs" {
    r = list<Role>{
        Role{name: "Admin", id: 1},
        Role{name: "User", id: 2}
    }
    
    // 嵌套也遵循静态特化
    au = User<Role>{goods: r, name: "ZhangSan", age: 40, _uid: 1002}

    if eq(get(au, .goods, 0, .name), "Admin") {
        print("Nested Static Struct success")
    }

    // 显式设置
    set(au, .goods, 0, .name, "Boos")
    print(au)

    // 批量设置
    set(au, .goods, 0, {.name: "Boos", .id: 2})
    print(au)


    // 批量设置
    set(au, .goods, .{
        0: {.name: "Boos", .id: 2}, 
        1: {.name: "Boos", .id: 2}
    })
    
    // 批量设置
    set(au, .{
        .name: "LiSi", 
        .age: 20,
        .goods: {
            0: {.name: "Boos22", .id: 22}, 
            1: {.name: "Boos23", .id: 23}
        }
    })
    print(au)
}

// 显式返回
add_age(u User) User => set(u, .age, add(u.age, 1))
// 隐式返回, 返回值自动推导
// add_age(u User) => set(u, .age, add(u.age, 1))


test "struct and function integration" {
    u = User<u32>{
        _uid: 1
        aid: 1001,
        name: "ZhangSan",
    }
    u = add_age(u)
    print(u)
}


default_user() User {

    // 自动推导类型   
    => .{
        .name: "LiSi",
        .age: 20
    }
}


// 局部更新（你之前的 set 函数的另一种写法）
new_user_add_age(u User) => User{ ...u, age: add(.age, 1) }

test "struct and function integration" {
    u = User<u32>{
        _uid: 1
        aid: 1001,
        name: "ZhangSan",
    }
    u = new_user_add_age(u)
    print(u)
}