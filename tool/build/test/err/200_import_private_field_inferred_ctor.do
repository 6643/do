User = @./fixture.private_field_user.do/User

test "import private field inferred ctor" {
    _user User = .{id = 1}
    return
}
