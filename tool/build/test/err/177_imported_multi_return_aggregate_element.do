pair = @./fixture.import_multi_return.do/pair

test "imported multi return aggregate element" {
    xs [i32] = .{pair(1)}
    return
}
