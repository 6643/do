JsonError = @lib("json.do", JsonError)
from_json = @lib("json.do", from_json)

Config {
    port i32 = 9000
    name text = "main"
    active bool = true
}

test "json from_json keeps missing i32 default" {
    got = from_json<Config>("{\"name\":\"api\"}")
    if @is(got, Config) {
        if @eq(@get(got, .port), 9000) return
    }
}

test "json from_json decodes present text field" {
    got = from_json<Config>("{\"name\":\"api\"}")
    if @is(got, Config) {
        if @eq(@get(got, .name), "api") return
    }
}

test "json from_json keeps missing bool default" {
    got = from_json<Config>("{\"name\":\"api\"}")
    if @is(got, Config) {
        if @eq(@get(got, .active), true) return
    }
}
