HashMap = @/hash_map.do/HashMap
hash_map_del = @/hash_map.do/del

test "hash map del import" {
    m HashMap<Text, i32> = HashMap<Text, i32>{}
    m = hash_map_del(m, "a")
    return
}
