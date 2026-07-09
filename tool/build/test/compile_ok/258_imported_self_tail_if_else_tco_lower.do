sum_branch = @lib("~/test.self_tail_branch.do", sum_branch)

start() {
    out i32 = sum_branch(5, 0, true)
    return
}
