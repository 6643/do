JsonError error = Bad

User {
    id i32 = 0
}

find_field_value_at(bytes [u8], offset usize, name text) -> usize | JsonError | nil {
    return offset
}

parse_value(seed i32, bytes [u8], offset usize) -> i32 | JsonError {
    return seed
}

#T
parse_object(seed T, bytes [u8], offset usize) -> T | JsonError {
    out T = seed
    loop field = fields(T) {
        value_offset = find_field_value_at(bytes, offset, @field_name(field))
        if @is(value_offset, JsonError) return value_offset
        if @eq(value_offset, nil) continue
        parsed = parse_value(@field_get(out, field), bytes, value_offset)
        if @is(parsed, JsonError) return parsed
        out = @field_set(out, field, parsed)
    }
    return out
}

start() {
    user User = User{}
    _ = parse_object(user, "{}", 0)
    return
}
