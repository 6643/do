random_bytes = @lib("random.do", random_bytes)

start() {
    data [u8] = random_bytes(4)
    count usize = @len(data)
    return
}
