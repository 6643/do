json_stringify = @lib("json.do", stringify)

Address {
    city text
    zip i32
}

User {
    id i32
    address Address
    active bool
}

test "json stringify nested struct fields" {
    address Address = Address{city = "paris", zip = 75001}
    user User = User{id = 7, address = address, active = true}
    got = json_stringify(user)
    expect [u8] = "{\"id\":7,\"address\":{\"city\":\"paris\",\"zip\":75001},\"active\":true}"
    if @eq(got, expect) return
}
