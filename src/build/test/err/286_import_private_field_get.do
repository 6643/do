User = @lib("./fixture.private_field_default_user.do", User)

test "import private field get" {
    user User = User{id = 1}
    _token i32 = @get(user, .token)
    return
}
