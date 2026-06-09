ReadError error = Bad

load(flag i32) -> [u8] | ReadError | nil {
    if @eq(flag, 0) return nil
    if @eq(flag, 1) return Bad
    data [u8] = .{}
    return data
}

start() {
    result [u8] | ReadError | nil = load(2)
    if @is(result, ReadError) return
    if @eq(result, nil) return
    return
}
