JsonError = @lib("json.do", JsonError)
from_json = @lib("json.do", from_json)
json_stringify = @lib("json.do", stringify)

json_bytes_eq(value [u8] | JsonError, expect [u8]) -> bool {
    if @is(value, JsonError) return false
    return @eq(value, expect)
}

// Include a managed `text` field so from_json uses the managed-struct path
// (pure scalar-only structs hit a separate field_set return bug, not json u8).
Cell {
    n u8 = 0
    label text = ""
    flag bool = false
}

test "json stringify u8 struct field" {
    cell Cell = Cell{n = 7, label = "x", flag = true}
    got = json_stringify(cell)
    expect [u8] = "{\"n\":7,\"label\":\"x\",\"flag\":true}"
    if json_bytes_eq(got, expect) return
}

test "json from_json u8 struct field" {
    got = from_json<Cell>("{\"n\":42,\"label\":\"y\",\"flag\":false}")
    if @is(got, Cell) {
        ok bool = true
        ok = @and(ok, @eq(@get(got, .n), 42))
        ok = @and(ok, @eq(@get(got, .label), "y"))
        ok = @and(ok, @eq(@get(got, .flag), false))
        if ok return
    }
}
