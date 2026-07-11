a_value = @lib("~/test.host_collision_a.do", value)
b_value = @lib("~/test.host_collision_b.do", value)

test "compiled imported host aliases are module scoped" {
    if @and(@eq(a_value(), 1), @eq(b_value(), 2)) return
}
