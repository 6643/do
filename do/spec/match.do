User {
    age   i8
    name  text
}

Book {
    id     i32
    price  i32
    stock  i32
}

_start() {
    abc i8 | User | Book = 1

    n = match abc {
        // 匹配类型为i8的常量1
        i8(1): 1,
        // 匹配类型为i8并绑定到变量a
        i8(a): a + 1,
        // 自动绑定变量 u
        User(u): get(u, .age) + 10,
        // 自动绑定变量 age
        User{age}: age + 10,
        _: 0,
    }

    print(n)
}

test "match shorthand and predicates" {
    n = match abc {
        // 1. 直接判断 (Implicit Predicate)
        User{ id: 101, price: gt(price, 50) }: mul(price, 2),

        // 2. 匿名函数 (Lambda Match)
        User{ age: a => gt(a, 20), price }: mul(price, 2),

        // 3. 值限制 (Value Match)
        User{ name: "Admin", stock: gt(stock, 0) }: 1111,
        
        // 4. 列表查找与解构 (List Search Pattern)
        // 语法: find( Lambda解构 => 谓词 )
        User{ 
            books: find(.{stock: s} => gt(s, 0)) 
        }: mul(s, 10),

        // 5. 复杂集合判断 (仅检查 boolean)
        User{ 
            books: any(books, b => gt(get(b, .stock), 0))
        }: 2222,

        // 6. 全对象捕获与结构约束 (Capture + Constraints)
        // 语义: 将 User 对象绑定到 u，同时要求其满足 id 和 price 的约束
        User(u){ 
            id: 101, 
            price: gt(price, 50) 
        }: set(u, .price, 0), // 返回修改后的 u

        _: 0,
    }
}
