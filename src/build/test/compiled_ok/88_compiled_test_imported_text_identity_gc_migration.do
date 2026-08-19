helper = @lib("~/gc.imported_text_helper.do", helper)

test "compiled imported text identity preserves value" {
    value text = "hello"
    alias text = helper(value)
    if @eq(alias, "hello") return
}
