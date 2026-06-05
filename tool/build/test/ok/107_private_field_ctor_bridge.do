User = @./fixture.private_field_user.do/User
new_user = @./fixture.private_field_user.do/new_user

test "private field ctor bridge" {
    _user User = new_user(1)
    return
}
