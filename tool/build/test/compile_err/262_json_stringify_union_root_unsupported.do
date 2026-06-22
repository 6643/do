JsonError = @lib("json.do", JsonError)
json_stringify = @lib("json.do", stringify)

start() {
    value i32 | text = 7
    got = json_stringify(value)
    if @is(got, JsonError) return
    return
}
