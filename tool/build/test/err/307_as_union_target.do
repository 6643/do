User {
    id i32
}

Admin {
    id i32
}

find_actor(kind i32) -> User | Admin {
    user User = User{id = 1}
    admin Admin = Admin{id = 2}
    if @eq(kind, 1) return user
    return admin
}

test "as union target invalid" {
    value User | Admin = find_actor(1)
    actor User | Admin = @as(value, User | Admin)
    return
}
