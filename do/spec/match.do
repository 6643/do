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
        i8(1): 1
        i8(2): 2
        i8(a): a + 1
        User(u): u.age + 10
        // 字段解构简写
        User{.age}: .age + 10
        Book(b): b.price
        _: 0
    }

    print(n)
}
