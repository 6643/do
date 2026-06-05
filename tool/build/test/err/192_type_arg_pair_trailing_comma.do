#T
#U
Pair {
    left T
    right U
}

test "type arg pair trailing comma" {
    p Pair<i32, bool,> = Pair<i32, bool,>{left = 1, right = true}
    return
}
