only_one = @fixture/arity_only_one.do/only_one

test "import func arity mismatch" {
    only_one(1, 2)
    return
}
