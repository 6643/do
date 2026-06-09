TestError error = Bad

.parse_digit(byte u8) -> u16 | TestError {
    if @and(@ge(byte, 48), @le(byte, 57)) return @to_u16(@sub(byte, 48))
    return Bad
}

value(byte u8) -> u16 {
    parsed = parse_digit(byte)
    if @is(parsed, TestError) return 0
    return @add(parsed, 1)
}
