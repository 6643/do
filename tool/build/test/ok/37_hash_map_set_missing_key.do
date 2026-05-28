HashMap = @/hash_map.do/HashMap
set = @/hash_map.do/set
MissingKey = @/hash_map.do/MissingKey
Text = @/text.do/Text

test "hash map set missing key" {
    m HashMap<Text, i32> = HashMap<Text, i32>{}
    result = set(m, "a", 1)
    if eq(result, MissingKey) return
}
