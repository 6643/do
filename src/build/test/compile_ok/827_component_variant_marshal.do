choose(value u32) -> u32 | nil {
    return value
}

read_event() -> u32 | nil {
    return 1
}

start() {
    selected u32 | nil = choose(1)
    _ = selected
    event u32 | nil = read_event()
    _ = event
}
