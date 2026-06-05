User {
    id u32
}

put(a User, name [u8]) -> User {
    return a
}

test "core put decl" {}
