JsonError = @lib("json.do", JsonError)
json_stringify = @lib("json.do", stringify)

start() {
    values [i32] = .{}
    got = json_stringify(values)
    if @is(got, JsonError) return
    return
}
