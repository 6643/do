abort(writer StreamWriter<i32>, reason i32) -> nil {
    return
}

produce(writer StreamWriter<i32>) -> nil {
    abort(writer, 1)
}

test "ordinary abort cannot satisfy writer lease" {}
