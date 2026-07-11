User = @lib("./fixture.private_field_default_user.do", User)

test "import private field set" {
    user User = User{id = 1}
    _next User = @set(user, .token, 2)
    return
}
