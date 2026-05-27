test "loop label break" {
#outer
    loop {
        loop {
            break #outer
        }
    }
}
