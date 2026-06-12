JsonError = @lib("json.do", JsonError)
from_json = @lib("json.do", from_json)

Payload {
    name text = ""
    raw [u8] = .{}
}

test "json from_json decodes text and bytes" {
    got = from_json<Payload>("{\"name\":\"amy\",\"raw\":\"A\\u00DF\"}")
    if @is(got, Payload) {
        raw = @get(got, .raw)
        ok bool = true
        ok = @and(ok, @eq(@get(got, .name), "amy"))
        ok = @and(ok, @eq(@len(raw), 3))
        ok = @and(ok, @eq(@get(raw, 0), 65))
        ok = @and(ok, @eq(@get(raw, 1), 195))
        ok = @and(ok, @eq(@get(raw, 2), 159))
        if ok return
    }
}
