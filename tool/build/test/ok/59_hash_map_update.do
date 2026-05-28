HashMap = @/hash_map.do/HashMap
Text = @/text.do/Text
hash_get = @/hash_map.do/get
hash_put = @/hash_map.do/put
hash_update = @/hash_map.do/update
MissingKey = @/hash_map.do/MissingKey

test "hash map update existing key" {
    m HashMap<Text, i32> = HashMap<Text, i32>{}
    m = hash_put(m, "score", 2)
    m = hash_update(m, "score", (x i32) -> i32 => add(x, 40))

    if eq(hash_get(m, "score"), 42) return
}

test "hash map update missing key" {
    m HashMap<Text, i32> = HashMap<Text, i32>{}
    result = hash_update(m, "score", (x i32) -> i32 => add(x, 1))

    if eq(result, MissingKey) return
}
