User = @./fixture.private_field_user.do/User

test "import private field ctor" {
    _user User = User{id = 1}
    return
}
