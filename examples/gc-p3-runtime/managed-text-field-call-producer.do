Box {
    value text
    tag i32
}

make_text() -> text {
    return "fresh"
}

replace(box Box) -> Box {
    return @set(box, .value, make_text())
}

start() {}
