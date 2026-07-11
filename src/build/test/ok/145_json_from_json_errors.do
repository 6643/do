JsonError = @lib("json.do", JsonError)
InvalidJson = @lib("json.do", InvalidJson)
ExpectedValue = @lib("json.do", ExpectedValue)
from_json = @lib("json.do", from_json)

User {
    id i32 = 0
    active bool = false
}

json_invalid_json(value User | JsonError) -> bool {
    if @is(value, JsonError) return @eq(value, InvalidJson)
    return false
}

json_expected_value(value User | JsonError) -> bool {
    if @is(value, JsonError) return @eq(value, ExpectedValue)
    return false
}

test "json from_json rejects trailing bytes" {
    got = from_json<User>("{\"id\":7} false")
    if json_invalid_json(got) return
}

test "json from_json rejects field type mismatch" {
    got = from_json<User>("{\"id\":\"bad\",\"active\":true}")
    if json_expected_value(got) return
}
