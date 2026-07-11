User {
    name [u8]
}

make_name_bytes() -> [u8] {
    return "amy"
}

test "set final value expr" {
    user = User{name = "tom"}
    user = @set(user, .name, "amy")
    user = @set(user, .name, make_name_bytes())
    expected [u8] = "amy"
    if @eq(@get(user, .name), expected) return
    return
}
