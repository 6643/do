Map = @/hash_map.do/Map
empty = @/hash_map.do/empty
set = @/hash_map.do/set
MissingKey = @/hash_map.do/MissingKey
Text = @/text.do/Text

test "hash map set missing key" {
    m Map<Text, i32> = empty()
    result = set(m, "a", 1)
    if eq(result, MissingKey) return
}
