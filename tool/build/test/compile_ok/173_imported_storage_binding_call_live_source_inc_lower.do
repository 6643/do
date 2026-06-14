echo_bytes = @lib("~/test.multi_return_pair.do", echo_bytes)

start() {
    data [u8] = "abc"
    out [u8] = echo_bytes(data)
    again usize = @len(data)
    return
}
