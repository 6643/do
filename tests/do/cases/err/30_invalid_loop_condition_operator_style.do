test "invalid loop condition operator style" {
    count = 0
    loop count < 3 {
        count = add(count, 1)
    }
}
