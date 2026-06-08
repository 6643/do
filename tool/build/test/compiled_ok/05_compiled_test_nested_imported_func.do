via_chain = @lib("~/test.import_chain.do", via_chain)

test "compiled nested imported func" {
    n i32 = 0
    ok bool = false
    n, ok = via_chain(13)
    if @and(@eq(n, 13), ok) return
}
