json_stringify = @lib("json.do", stringify)

User {
    id i32
    name text | nil
}

test "json stringify nullable nil field" {
    user User = User{id = 7, name = nil}
    got = json_stringify(user)
    expect [u8] = "{\"id\":7,\"name\":null}"
    if @eq(got, expect) return
}

test "json stringify nullable value field" {
    user User = User{id = 7, name = "amy"}
    got = json_stringify(user)
    expect [u8] = "{\"id\":7,\"name\":\"amy\"}"
    if @eq(got, expect) return
}
