User = @./fixture.private_field_default_user.do/User

test "import private default field explicit ctor" {
    _user User = User{id = 1, token = 2}
    return
}
