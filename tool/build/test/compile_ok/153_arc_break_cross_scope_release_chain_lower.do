start() {
#outer
    loop {
        outer [u8] = "outer"
        loop {
            inner [u8] = "inner"
            break #outer
        }
    }
    return
}
