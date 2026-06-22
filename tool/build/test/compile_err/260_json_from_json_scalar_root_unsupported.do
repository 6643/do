JsonError = @lib("json.do", JsonError)
from_json = @lib("json.do", from_json)

start() {
    got = from_json<i32>("7")
    if @is(got, i32) return
    return
}
