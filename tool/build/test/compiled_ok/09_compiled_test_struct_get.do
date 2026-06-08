User {
    id i32
}

test "compiled struct get" {
    user = User{id = 7}
    got = @get(user, .id)
    if @eq(got, 7) return
}
