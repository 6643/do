test "text escape runtime" {
    line [u8] = \\a\\nb
    ok bool = true
    ok = @and(ok, @eq("\x61", "a"))
    ok = @and(ok, @eq("a\n", "\x61\x0A"))
    ok = @and(ok, @eq("\"", "\x22"))
    ok = @and(ok, @eq("\\", "\x5C"))
    ok = @and(ok, @eq("\xE4\xB8\xAD", "中"))
    ok = @and(ok, @eq(line, "a\\\\nb"))
    if ok return
}
