JsonError error = Bad

User {
    name text | nil
}

append_bytes(out [u8], part [u8]) -> [u8] {
    return out
}

encode_value(value text, depth usize) -> [u8] | JsonError {
    return value
}

#T
encode_value(value T | nil, depth usize) -> [u8] | JsonError {
    if @eq(value, nil) return "null"
    return encode_value(value, depth)
}

#T
stringify_depth(value T, depth usize) -> [u8] | JsonError {
    out [u8] = .{}
    loop field = fields(T) {
        encoded = encode_value(@field_get(value, field), depth)
        if @is(encoded, JsonError) return encoded
        out = append_bytes(out, encoded)
    }
    return out
}

#T
stringify(value T) -> [u8] | JsonError {
    return stringify_depth(value, 1)
}

start() {
    user User = User{name = nil}
    _ = stringify(user)
    return
}
