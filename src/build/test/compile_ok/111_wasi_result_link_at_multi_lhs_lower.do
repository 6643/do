host_file_link_at = @wasi("filesystem/types/descriptor.link-at", (descriptor, path-flags, text, borrow<descriptor>, text) -> result<_, error-code>)

start() {
    status i32 = 0
    _, status = host_file_link_at(1, 0, "old.txt", 2, "new.txt")
    return
}
