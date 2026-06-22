JsonError = @lib("json.do", JsonError)
from_json = @lib("json.do", from_json)

User {
    value i32 | text = 7
}

start() {
    got = from_json<User>("{\"value\":7}")
    if @is(got, JsonError) return
    return
}
