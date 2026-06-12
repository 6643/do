JsonError = @lib("json.do", JsonError)
from_json = @lib("json.do", from_json)

User {
    id i32 = 0
    name text = ""
    active bool = false
}

test "json struct from_json explicit type args" {
    got = from_json<User>("{\"id\":7,\"name\":\"amy\",\"active\":true}")
    if @is(got, User) {
        ok bool = true
        ok = @and(ok, @eq(@get(got, .id), 7))
        ok = @and(ok, @eq(@get(got, .name), "amy"))
        ok = @and(ok, @eq(@get(got, .active), true))
        if ok return
    }
}
