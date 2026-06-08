.InternalUser = User | nil

User {
    name [u8]
}

test "private type decl left dot" {
    user = User{name = "tom"}
    name = @get(user, .name)
    expected [u8] = "tom"
    if @eq(name, expected) return
}
