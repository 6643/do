echo_bytes = @lib("~/test.multi_return_pair.do", echo_bytes)

test "compiled imported storage binding call last use move" {
    data [u8] = .{1, 2, 3}
    out [u8] = echo_bytes(data)
    if @eq(out, .{1, 2, 3}) return
}
