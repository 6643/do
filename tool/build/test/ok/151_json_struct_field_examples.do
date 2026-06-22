JsonError = @lib("json.do", JsonError)
json_stringify = @lib("json.do", stringify)
from_json = @lib("json.do", from_json)

json_bytes_eq(value [u8] | JsonError, expect [u8]) -> bool {
    if @is(value, JsonError) return false
    return @eq(value, expect)
}

Address {
    city text = "unknown"
    zip i32 = 100
    verified bool = true
}

User {
    id i32 = 1
    name text = "guest"
    active bool = true
    address Address = Address{}
}

test "json stringify struct nested default field examples" {
    address Address = Address{city = "paris"}
    user User = User{name = "amy", address = address}
    got = json_stringify(user)
    expect [u8] = "{\"id\":1,\"name\":\"amy\",\"active\":true,\"address\":{\"city\":\"paris\",\"zip\":100,\"verified\":true}}"
    if json_bytes_eq(got, expect) return
}

test "json from_json keeps struct nested default field examples" {
    got = from_json<User>("{\"name\":\"bob\",\"address\":{\"zip\":75001}}")
    if @is(got, User) {
        address = @get(got, .address)
        ok bool = true
        ok = @and(ok, @eq(@get(got, .id), 1))
        ok = @and(ok, @eq(@get(got, .name), "bob"))
        ok = @and(ok, @eq(@get(got, .active), true))
        ok = @and(ok, @eq(@get(address, .city), "unknown"))
        ok = @and(ok, @eq(@get(address, .zip), 75001))
        ok = @and(ok, @eq(@get(address, .verified), true))
        if ok return
    }
}
