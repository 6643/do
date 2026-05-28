test "storage literal non-empty" {
    xs [u32] = .{7, 12, 17, 22}

    ok bool = true
    ok = and(ok, eq(len(xs), 4))
    ok = and(ok, eq(at(xs, 0), 7))
    ok = and(ok, eq(at(xs, 3), 22))
    if ok return
}
