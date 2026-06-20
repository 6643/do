JsonError = @lib("json.do", JsonError)
json_stringify = @lib("json.do", stringify)

json_bytes_eq(value [u8] | JsonError, expect [u8]) -> bool {
    if @is(value, JsonError) return false
    return @eq(value, expect)
}

User {
    id i32
    name text | nil
}

test "json stringify nullable nil field" {
    user User = User{id = 7, name = nil}
    got = json_stringify(user)
    expect [u8] = "{\"id\":7,\"name\":null}"
    if json_bytes_eq(got, expect) return
}

test "json stringify nullable value field" {
    user User = User{id = 7, name = "amy"}
    got = json_stringify(user)
    expect [u8] = "{\"id\":7,\"name\":\"amy\"}"
    if json_bytes_eq(got, expect) return
}
