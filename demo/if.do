// 入口
_statr(){
    // 局部变量
    age = 18
    has_auth = true

    // 短路
    if eq(abc, 19) return
    if always_true() return
    if has_auth return

    if has_auth {
        print("A has auth)
    }else{
        print("A not auth)
    }

    if gt(age, 18) {

    }else if lt(age, 18) {

    }else{

    }

    item = find_user(1)
    // 匹配类型
    if User := item return

    // 匹配并绑定
    if User(user) := item {
        print(get(user, .id))
    }



    // 匹配并解构age
    if User{age} := item {
        print(age)
    }

}

User{
    id u32
    age u8
}

find_user(id u8) User|nil {
    return User{id: 123, age: 18}
}
