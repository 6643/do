#T
field_count(value T) -> usize {
    count usize = 0
    loop field = fields(T) {
        count = @add(count, 1)
    }
    return count
}

User {
    id i32
    name text
    active bool
}

test "generic fields reflection" {
    user User = User{id = 1, name = "amy", active = true}
    if @eq(field_count(user), 3) return
}
