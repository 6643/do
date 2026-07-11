JsonError = @lib("json.do", JsonError)
json_stringify = @lib("json.do", stringify)

json_bytes_eq(value [u8] | JsonError, expect [u8]) -> bool {
    if @is(value, JsonError) return false
    return @eq(value, expect)
}

User {
    id i32
    name text
    active bool
}

test "json stringify struct fields" {
    user User = User{id = 7, name = "amy", active = true}
    got = json_stringify(user)
    expect [u8] = "{\"id\":7,\"name\":\"amy\",\"active\":true}"
    if json_bytes_eq(got, expect) return
}
