Box = @lib("~/test.box.do", Box)
echo_box = @lib("~/test.box.do", echo_box)

start() {
    bytes [u8] = "abc"
    box Box = Box{value = bytes}
    out Box = echo_box(box)
    again [u8] = @get(box, .value)
    return
}
