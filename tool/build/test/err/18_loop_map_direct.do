test "loop map direct" {
    m HashMap<Text, i32> = HashMap<Text, i32>{}
    loop v, k = m {
        consume(k, v)
    }
}
