UserProfile {
    id u32
}

UserId = i32
NumberLike = i8 | i16 | i32

test "type decl names valid" {
    _u = UserId
    _n = NumberLike
    return
}
