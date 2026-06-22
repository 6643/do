JsonError = @lib("json.do", JsonError)
json_stringify = @lib("json.do", stringify)

start() {
    value u64 = 7
    got = json_stringify(value)
    if @is(got, JsonError) return
    return
}
