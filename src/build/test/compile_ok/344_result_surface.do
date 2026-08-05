parse_flag(value bool) -> Result<bool, u8> {
    return Ok(value)
}

start() {
    result Result<bool, u8> = parse_flag(false)
    if @is(result, Ok) {
        flag bool = result
    } else {
        code u8 = result
    }
}
