User {
    id i32
}

test "non generic struct type args" {
    u = User<i32>{id = 1}
    return
}
