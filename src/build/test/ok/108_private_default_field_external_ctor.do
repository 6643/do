User = @lib("./fixture.private_field_user.do", User)

test "private default field external ctor" {
    _user User = User{id = 1}
    _other User = .{id = 2}
    return
}
