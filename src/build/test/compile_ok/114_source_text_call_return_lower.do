echo(value text) -> text {
    return value
}

make_text() -> text {
    return "abc"
}

start() {
    made text = make_text()
    echoed text = echo("xy")
    return
}
