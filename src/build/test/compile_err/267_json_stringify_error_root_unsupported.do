JsonError = @lib("json.do", JsonError)
InvalidJson = @lib("json.do", InvalidJson)
json_stringify = @lib("json.do", stringify)

start() {
    value JsonError = InvalidJson
    got = json_stringify(value)
    if @is(got, JsonError) return
    return
}
