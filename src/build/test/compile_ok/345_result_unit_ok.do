complete(ok bool) -> Result<nil, u8> {
    if ok {
        return Ok()
    }
    return Err(7)
}

start() {
    result Result<nil, u8> = complete(true)
    if @is(result, Err) {
        code u8 = result
    }
}
