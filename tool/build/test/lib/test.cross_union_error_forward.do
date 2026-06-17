CrossError error = Bad

.parse_digit(byte u8) -> u16 | CrossError {
    if @and(@ge(byte, 48), @le(byte, 57)) return @as(u16, @sub(byte, 48))
    return Bad
}

forward_error(byte u8) -> [u8] | CrossError {
    out [u8] = .{}
    parsed = parse_digit(byte)
    if @is(parsed, CrossError) return parsed
    return out
}
