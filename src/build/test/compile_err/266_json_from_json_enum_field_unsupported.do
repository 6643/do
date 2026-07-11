JsonError = @lib("json.do", JsonError)
from_json = @lib("json.do", from_json)

Kind u8 = KindA(1) | KindB(2)

User {
    kind Kind = KindA
}

start() {
    got = from_json<User>("{\"kind\":1}")
    if @is(got, JsonError) return
    return
}
