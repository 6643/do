via_chain = @lib("~/test.import_chain.do", via_chain)

start() {
    n i32 = 0
    ok bool = false
    n, ok = via_chain(13)
    return
}
