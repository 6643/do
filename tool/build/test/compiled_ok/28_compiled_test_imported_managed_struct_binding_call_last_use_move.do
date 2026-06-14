Box = @lib("~/test.box.do", Box)
echo_box = @lib("~/test.box.do", echo_box)

test "compiled imported managed struct binding call last use move" {
    bytes [u8] = .{1, 2, 3}
    box Box = Box{value = bytes}
    out Box = echo_box(box)
    value [u8] = @get(out, .value)
    if @eq(value, .{1, 2, 3}) return
}
