helper = @lib("./imported_text_helper.do", helper)

relay(value text) -> text {
    return helper(value)
}

start() {}
