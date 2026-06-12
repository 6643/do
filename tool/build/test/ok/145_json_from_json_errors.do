JsonError = @lib("json.do", JsonError)
InvalidJson = @lib("json.do", InvalidJson)
ExpectedValue = @lib("json.do", ExpectedValue)
from_json = @lib("json.do", from_json)

User {
    id i32 = 0
    active bool = false
}

test "json from_json rejects trailing bytes" {
    got = from_json<User>("{\"id\":7} false")
    if @eq(got, InvalidJson) return
}

test "json from_json rejects field type mismatch" {
    got = from_json<User>("{\"id\":\"bad\",\"active\":true}")
    if @eq(got, ExpectedValue) return
}
