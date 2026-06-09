User {
    id i32
    name text = "tom"
    active bool
}

test "struct field reflection metadata and get" {
    user User = User{id = 7, active = true}
    seen_id bool = false
    seen_name bool = false
    seen_active bool = false

    loop field = fields(User) {
        if @and(@eq(@field_index(field), 0), @eq(@field_name(field), "id")) {
            id_value = @field_get(user, field)
            if @eq(id_value, 7) {
                seen_id = true
            }
        }
        if @and(@eq(@field_index(field), 1), @eq(@field_name(field), "name")) {
            name_value = @field_get(user, field)
            if @and(@field_has_default(field), @eq(name_value, "tom")) {
                seen_name = true
            }
        }
        if @and(@eq(@field_index(field), 2), @eq(@field_name(field), "active")) {
            active_value = @field_get(user, field)
            if @and(@not(@field_has_default(field)), @eq(active_value, true)) {
                seen_active = true
            }
        }
    }

    if @and(seen_id, seen_name, seen_active) return
}
