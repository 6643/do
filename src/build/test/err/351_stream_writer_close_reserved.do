close(writer StreamWriter<i32>) -> nil {
    return
}

async produce(writer StreamWriter<i32>) -> nil {
    close(writer)
}

test "ordinary close cannot satisfy writer lease" {}
