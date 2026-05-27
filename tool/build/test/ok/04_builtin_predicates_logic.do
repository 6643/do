is_one(a i32) bool {
    return and(eq(a, 1), not(ne(a, 1)))
}

test "builtin predicates logic" {
    if is_one(1) return
}
