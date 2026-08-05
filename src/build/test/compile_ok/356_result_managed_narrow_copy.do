choose(ok bool) -> Result<text, text> {
    if ok {
        return Ok("yes")
    }
    return Err("no")
}

start() {
    result Result<text, text> = choose(true)
    if @is(result, Ok) {
        value text = result
    }
}
