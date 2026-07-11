hex_encode = @lib("hex.do", encode)
hex_encode_upper = @lib("hex.do", encode_upper)

test "hex encode helpers" {
    ok bool = true
    ok = @and(ok, @eq(hex_encode(.{}), ""))
    ok = @and(ok, @eq(hex_encode(.{0, 15, 16, 255}), "000f10ff"))
    ok = @and(ok, @eq(hex_encode_upper(.{0, 15, 16, 255}), "000F10FF"))
    if ok return
}
