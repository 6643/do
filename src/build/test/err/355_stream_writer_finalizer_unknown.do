async produce() -> nil {
    close(1)
}

test "finalizer requires a tracked writer" {}
