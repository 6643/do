JsonError = @lib("json.do", JsonError)
InvalidJson = @lib("json.do", InvalidJson)
from_json = @lib("json.do", from_json)

User {
    status JsonError = InvalidJson
}

start() {
    got = from_json<User>("{\"status\":\"InvalidJson\"}")
    if @is(got, JsonError) return
    return
}
