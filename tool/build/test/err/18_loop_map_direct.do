test "loop map direct" {
    m Map<Text, i32> = Map<Text, i32>{}
    loop v, k = m {
        consume(k, v)
    }
}
