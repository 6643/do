JsonError = @lib("json.do", JsonError)
ExpectedObject = @lib("json.do", ExpectedObject)
ExpectedColon = @lib("json.do", ExpectedColon)
ExpectedComma = @lib("json.do", ExpectedComma)
UnexpectedEnd = @lib("json.do", UnexpectedEnd)
from_json = @lib("json.do", from_json)

User {
    id i32 = 0
    active bool = false
}

json_expected_object(value User | JsonError) -> bool {
    if @is(value, JsonError) return @eq(value, ExpectedObject)
    return false
}

json_expected_colon(value User | JsonError) -> bool {
    if @is(value, JsonError) return @eq(value, ExpectedColon)
    return false
}

json_expected_comma(value User | JsonError) -> bool {
    if @is(value, JsonError) return @eq(value, ExpectedComma)
    return false
}

json_unexpected_end(value User | JsonError) -> bool {
    if @is(value, JsonError) return @eq(value, UnexpectedEnd)
    return false
}

test "json from_json rejects non object root" {
    got = from_json<User>("false")
    if json_expected_object(got) return
}

test "json from_json rejects missing colon" {
    got = from_json<User>("{\"id\" 7}")
    if json_expected_colon(got) return
}

test "json from_json rejects missing comma" {
    got = from_json<User>("{\"id\":7 \"active\":true}")
    if json_expected_comma(got) return
}

test "json from_json rejects truncated field value" {
    got = from_json<User>("{\"id\":")
    if json_unexpected_end(got) return
}
