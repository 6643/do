Text = [u8]

empty() -> Text {
    return storage()
}

is_empty(s Text) -> bool {
    return eq(len(s), 0)
}
