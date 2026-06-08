a_value = @lib("~/test.func_collision_a.do", value)
b_value = @lib("~/test.func_collision_b.do", value)

test "compiled imported helper names are module scoped" {
    if @and(@eq(a_value(), 1), @eq(b_value(), 2)) return
}
