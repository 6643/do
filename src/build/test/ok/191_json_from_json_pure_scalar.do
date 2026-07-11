from_json = @lib("json.do", from_json)

// Pure-scalar struct: field-reflect `out = @field_set(out, field, parsed)` must
// mutate the outer `out.*` locals (not a field-loop scoped shadow).
Cell {
    n u8 = 0
    flag bool = false
}

test "from_json pure scalar struct fields" {
    got = from_json<Cell>("{\"n\":42,\"flag\":true}")
    if @is(got, Cell) {
        ok bool = true
        ok = @and(ok, @eq(@get(got, .n), 42))
        ok = @and(ok, @eq(@get(got, .flag), true))
        if ok return
    }
}
