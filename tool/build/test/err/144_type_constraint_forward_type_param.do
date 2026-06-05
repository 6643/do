#T = U | i32
#U
Pair {
    left T
    right U
}

test "type constraint forward type param" {
    p = Pair<i32, i32>{left = 1, right = 2}
    return
}
