json_stringify = @lib("json.do", stringify)

User {
    id i32
    name text
    active bool
}

test "json stringify struct fields" {
    user User = User{id = 7, name = "amy", active = true}
    got = json_stringify(user)
    expect [u8] = "{\"id\":7,\"name\":\"amy\",\"active\":true}"
    if @eq(got, expect) return
}
