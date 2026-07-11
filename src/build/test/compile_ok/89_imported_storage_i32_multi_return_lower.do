make_nums = @lib("~/test.i32_storage.do", make_nums)
pair_nums = @lib("~/test.i32_storage.do", pair_nums)

start() {
    xs [i32] = make_nums()
    a [i32] = .{}
    b [i32] = .{}
    a, b = pair_nums()
    return
}
