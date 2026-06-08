Box = @lib("~/test.box.do", Box)
make_box = @lib("~/test.box.do", make_box)

start() {
    box Box = make_box()
    return
}
