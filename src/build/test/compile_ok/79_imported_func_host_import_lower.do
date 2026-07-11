use_host_add = @lib("~/test.multi_return_pair.do", use_host_add)

start() {
    y i32 = use_host_add(4)
    return
}
