make_byte_pair = @lib("~/test.multi_return_pair.do", make_byte_pair)

start() {
    first [u8] = "first"
    second [u8] = "second"
    first, second = make_byte_pair()
    return
}
