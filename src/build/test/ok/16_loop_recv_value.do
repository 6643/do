test "loop recv value" {
    loop v = recv(ch) {
        consume(v)
    }
}

test "loop recv trailing comma" {
    loop v = recv(ch,) {
        consume(v)
    }
}

test "loop recv value and count" {
    loop v, i = recv(ch) {
        consume(v)
        consume(i)
    }
}
