sum_branch = @lib("~/test.self_tail_branch.do", sum_branch)

test "compiled imported self tail if else tco" {
    out i32 = sum_branch(5, 0, true)
    if @eq(out, 15) return
}
