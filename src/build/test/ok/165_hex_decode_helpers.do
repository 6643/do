HexError = @lib("hex.do", HexError)
HexInvalidLength = @lib("hex.do", InvalidLength)
HexInvalidDigit = @lib("hex.do", InvalidDigit)
hex_decode = @lib("hex.do", decode)

hex_bytes_eq(value [u8] | HexError, expect [u8]) -> bool {
    if @is(value, HexError) return false
    return @eq(value, expect)
}

hex_is_invalid_length(value [u8] | HexError) -> bool {
    if @is(value, HexError) return @eq(value, HexInvalidLength)
    return false
}

hex_is_invalid_digit(value [u8] | HexError) -> bool {
    if @is(value, HexError) return @eq(value, HexInvalidDigit)
    return false
}

test "hex decode helpers" {
    decoded = hex_decode("000f10ff")
    mixed = hex_decode("48656C6c6f")
    bad_len = hex_decode("f")
    bad_digit = hex_decode("0g")

    ok bool = true
    ok = @and(ok, hex_bytes_eq(decoded, .{0, 15, 16, 255}))
    ok = @and(ok, hex_bytes_eq(mixed, "Hello"))
    ok = @and(ok, hex_is_invalid_length(bad_len))
    ok = @and(ok, hex_is_invalid_digit(bad_digit))
    if ok return
}
