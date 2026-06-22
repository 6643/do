JsonError = @lib("json.do", JsonError)
from_json = @lib("json.do", from_json)

User {
    values [i32] = .{}
}

start() {
    got = from_json<User>("{\"values\":[1,2]}")
    if @is(got, JsonError) return
    return
}
