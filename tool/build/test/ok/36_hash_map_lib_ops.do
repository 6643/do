HashMap = @/hash_map.do/HashMap
len = @/hash_map.do/len
get = @/hash_map.do/get
put = @/hash_map.do/put
has = @/hash_map.do/has

test "hash map lib ops" {
    m HashMap<Text, i32> = HashMap<Text, i32>{}
    m = put(m, "a", 1)
    m = put(m, "b", 2)
    return
}

test "hash map len" {
    m HashMap<Text, i32> = HashMap<Text, i32>{}
    m = put(m, "a", 1)
    m = put(m, "b", 2)
    if eq(len(m), 2) return
}

test "hash map get" {
    m HashMap<Text, i32> = HashMap<Text, i32>{}
    m = put(m, "a", 1)
    expected i32 = 1
    if eq(get(m, "a"), expected) return
}

test "hash map has" {
    m HashMap<Text, i32> = HashMap<Text, i32>{}
    m = put(m, "b", 2)
    if has(m, "b") return
}
