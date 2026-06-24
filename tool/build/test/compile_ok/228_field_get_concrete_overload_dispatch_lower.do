User {
    id i32
    name text
}

append_bytes(out [u8], part [u8]) -> [u8] {
    return out
}

encode_value(value i32) -> [u8] {
    return "int"
}

encode_value(value text) -> [u8] {
    return value
}

start() {
    user User = User{id = 7, name = "amy"}
    out [u8] = .{}
    loop field = fields(User) {
        out = append_bytes(out, encode_value(@field_get(user, field)))
    }
    return
}
