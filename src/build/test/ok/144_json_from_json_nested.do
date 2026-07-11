JsonError = @lib("json.do", JsonError)
from_json = @lib("json.do", from_json)

Address {
    city text = ""
    zip i32 = 0
}

User {
    id i32 = 0
    address Address = Address{}
    active bool = false
}

test "json from_json nested struct" {
    got = from_json<User>("{\"id\":7,\"address\":{\"city\":\"paris\",\"zip\":75001},\"active\":true}")
    if @is(got, User) {
        address = @get(got, .address)
        ok bool = true
        ok = @and(ok, @eq(@get(got, .id), 7))
        ok = @and(ok, @eq(@get(address, .city), "paris"))
        ok = @and(ok, @eq(@get(address, .zip), 75001))
        ok = @and(ok, @eq(@get(got, .active), true))
        if ok return
    }
}
