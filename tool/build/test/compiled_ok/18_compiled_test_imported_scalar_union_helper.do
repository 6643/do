value = @lib("~/test.imported_scalar_union_helper.do", value)

test "compiled imported scalar union helper" {
    if @eq(value(50), 3) return
}
