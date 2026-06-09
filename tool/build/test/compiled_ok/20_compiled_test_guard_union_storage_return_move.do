GuardError error = Bad

copy_until_end(bytes [u8]) -> [u8] | GuardError {
    out [u8] = .{}
    i usize = 0
    loop {
        if @eq(i, @len(bytes)) return out
        out = @put(out, @get(bytes, i))
        i = @add(i, 1)
    }
}

test "compiled guard union storage return move" {
    first_input [u8] = .{1, 2, 3}
    second_input [u8] = .{4, 5, 6}
    first = copy_until_end(first_input)
    second = copy_until_end(second_input)
    expect_first [u8] = .{1, 2, 3}
    expect_second [u8] = .{4, 5, 6}

    ok bool = true
    ok = @and(ok, @eq(first, expect_first))
    ok = @and(ok, @eq(second, expect_second))
    if ok return
}
