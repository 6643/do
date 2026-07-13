host_file_read = @host("wasi:filesystem/types@0.3.0", "descriptor.read", (descriptor, filesize, filesize) -> result<tuple<list<u8>,bool>,error-code>)

start() {
    data [u8] = .{}
    done bool = false
    status i32 = 0
    data, done, status = host_file_read(1, 16, 0)
    return
}
