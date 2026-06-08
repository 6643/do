User {
    name [u8]
}

test "compiled inferred storage get" {
    expected [u8] = "tom"
    user = User{name = expected}
    name = @get(user, .name)
    if @eq(@len(name), 3) return
}
