sum_branch = @lib("./fixture.self_tail_branch.do", sum_branch)

test "imported self tail if else tco" {
    out i32 = sum_branch(5, 0, true)
    if @eq(out, 15) return
}
