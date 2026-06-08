make_bytes = @lib("~/test.multi_return_pair.do", make_bytes)

start() {
    out [u8] = make_bytes()
    return
}
