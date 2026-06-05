User {
    id u32
}

len(a User) -> u32 {
    return get(a, .id)
}

test "core len decl" {}
