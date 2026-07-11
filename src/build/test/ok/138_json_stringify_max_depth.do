JsonMaxDepth = @lib("json.do", MaxDepth)
json_stringify_with_depth = @lib("json.do", stringify_with_depth)

Address {
    city text
}

User {
    id i32
    address Address
}

test "json stringify max depth" {
    address Address = Address{city = "paris"}
    user User = User{id = 7, address = address}
    got = json_stringify_with_depth(user, 1)
    if @eq(got, JsonMaxDepth) return
}
