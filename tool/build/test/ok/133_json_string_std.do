JsonError = @lib("json.do", JsonError)
json_escape = @lib("json.do", escape)
json_quote = @lib("json.do", quote)
json_unescape = @lib("json.do", unescape)

json_bytes_eq(value [u8] | JsonError, expect [u8]) -> bool {
    if @is(value, JsonError) return false
    return @eq(value, expect)
}

test "json string standard escapes" {
    controls [u8] = .{34, 92, 8, 12, 10, 13, 9, 1}
    escaped [u8] = json_escape(controls)
    quoted [u8] = json_quote(controls)
    special_input [u8] = .{92, 34, 92, 92, 92, 47, 92, 98, 92, 102, 92, 110, 92, 114, 92, 116}
    special = json_unescape(special_input)
    unicode_ascii_input [u8] = "\\u0041\\u00DF\\u20AC"
    unicode_ascii = json_unescape(unicode_ascii_input)
    unicode_pair_input [u8] = "\\uD83D\\uDE00"
    unicode_pair = json_unescape(unicode_pair_input)
    expect_escaped [u8] = .{92, 34, 92, 92, 92, 98, 92, 102, 92, 110, 92, 114, 92, 116, 92, 117, 48, 48, 48, 49}
    expect_quoted [u8] = .{34, 92, 34, 92, 92, 92, 98, 92, 102, 92, 110, 92, 114, 92, 116, 92, 117, 48, 48, 48, 49, 34}
    expect_special [u8] = .{34, 92, 47, 8, 12, 10, 13, 9}
    expect_ascii [u8] = .{65, 195, 159, 226, 130, 172}
    expect_pair [u8] = .{240, 159, 152, 128}

    ok bool = true
    ok = @and(ok, @eq(escaped, expect_escaped))
    ok = @and(ok, @eq(quoted, expect_quoted))
    ok = @and(ok, json_bytes_eq(special, expect_special))
    ok = @and(ok, json_bytes_eq(unicode_ascii, expect_ascii))
    ok = @and(ok, json_bytes_eq(unicode_pair, expect_pair))
    if ok return
}
