bad() -> i32, i32 => 1

test "multi return arrow passthrough requires call" {
    a, b = bad()
    return
}
