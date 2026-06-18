json_stringify = @lib("json.do", stringify)

User {
    id i32
    name text | nil
}

start() {
    user User = User{id = 7, name = nil}
    _ = json_stringify(user)
    return
}
