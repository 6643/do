cleanup_outer() -> nil {
    return
}

cleanup_inner() -> nil {
    return
}

start() {
#outer
    loop {
        outer_data [u8] = "outer"
        defer cleanup_outer()
        loop {
            inner_data [u8] = "inner"
            defer cleanup_inner()
            break #outer
        }
    }
    return
}
