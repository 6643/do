test "loop recv value" {
    loop v = recv(ch) {
        consume(v)
    }
}
