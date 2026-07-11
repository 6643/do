pair = @lib("~/test.multi_return_pair.do", pair)

via_chain(x i32) -> i32, bool {
    return pair(x)
}
