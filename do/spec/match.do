User {
    age   i8
    name  text
}

Book {
    id     i32
    price  i32
}

_start() {
    // 联合类型变量
    abc i8 | User | Book = 1

    n = match abc {
        // 匹配类型为i8的常量1
        i8(1): 1
        // 匹配类型为i8的常量2
        i8(2): 2
        // 匹配类型为i8并绑定到变量a
        i8(a): a + 1
        // 匹配类型为User并绑定到变量u
        User(u): u.age + 10
        // 字段解构简写
        User{.age}: .age + 10
        // 匹配类型为Book并绑定到变量b
        Book(b): get(b, .price)
        // 匹配其他类型
        _: 0
    }

    print(n)
}
