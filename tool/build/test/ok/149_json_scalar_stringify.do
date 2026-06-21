JsonError = @lib("json.do", JsonError)
json_stringify = @lib("json.do", stringify)

json_bytes_eq(value [u8] | JsonError, expect [u8]) -> bool {
    if @is(value, JsonError) return false
    return @eq(value, expect)
}

test "json stringify top level scalar values" {
    int_value = json_stringify(7)
    neg_value = json_stringify(-12)
    true_value = json_stringify(true)
    false_value = json_stringify(false)
    text_value = json_stringify("amy")
    raw [u8] = .{65, 34}
    bytes_value = json_stringify(raw)

    ok bool = true
    ok = @and(ok, json_bytes_eq(int_value, "7"))
    ok = @and(ok, json_bytes_eq(neg_value, "-12"))
    ok = @and(ok, json_bytes_eq(true_value, "true"))
    ok = @and(ok, json_bytes_eq(false_value, "false"))
    ok = @and(ok, json_bytes_eq(text_value, "\"amy\""))
    ok = @and(ok, json_bytes_eq(bytes_value, "\"A\\\"\""))
    if ok return
}
