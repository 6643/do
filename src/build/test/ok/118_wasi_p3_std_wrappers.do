Datetime = @lib("time.do", Datetime)
unix_ms = @lib("time.do", unix_ms)
monotonic_now = @lib("time.do", monotonic_now)
Random = @lib("random.do", Random)
random_u64 = @lib("random.do", random_u64)
random_bytes = @lib("random.do", random_bytes)
File = @lib("file.do", File)
FileError = @lib("file.do", FileError)
FileClosed = @lib("file.do", FileClosed)
FileLinkFailed = @lib("file.do", FileLinkFailed)
is_file_closed = @lib("file.do", is_file_closed)
read_file = @lib("file.do", read_file)
write_file = @lib("file.do", write_file)
link_file = @lib("file.do", link_file)
open_file_at = @lib("file.do", open_file_at)
close_file = @lib("file.do", close_file)
Dir = @lib("dir.do", Dir)
DirError = @lib("dir.do", DirError)
DirClosed = @lib("dir.do", DirClosed)
is_dir_closed = @lib("dir.do", is_dir_closed)
open_dir_at = @lib("dir.do", open_dir_at)
close_dir = @lib("dir.do", close_dir)
create_dir_at = @lib("dir.do", create_dir_at)
remove_dir_at = @lib("dir.do", remove_dir_at)
InputStream = @lib("io.stream.do", InputStream)
OutputStream = @lib("io.stream.do", OutputStream)
StreamError = @lib("io.stream.do", StreamError)
StreamClosed = @lib("io.stream.do", StreamClosed)
is_stream_closed = @lib("io.stream.do", is_stream_closed)
read_stream = @lib("io.stream.do", read_stream)
check_write_stream = @lib("io.stream.do", check_write_stream)
write_stream = @lib("io.stream.do", write_stream)
flush_stream = @lib("io.stream.do", flush_stream)
TcpSocket = @lib("tcp.do", TcpSocket)
TcpError = @lib("tcp.do", TcpError)
TcpClosed = @lib("tcp.do", TcpClosed)
is_tcp_closed = @lib("tcp.do", is_tcp_closed)
create_tcp_v4 = @lib("tcp.do", create_tcp_v4)
bind_tcp_v4 = @lib("tcp.do", bind_tcp_v4)
close_tcp = @lib("tcp.do", close_tcp)
Ipv4SocketAddress = @lib("tcp.do", Ipv4SocketAddress)
UdpSocket = @lib("udp.do", UdpSocket)
UdpError = @lib("udp.do", UdpError)
UdpClosed = @lib("udp.do", UdpClosed)
is_udp_closed = @lib("udp.do", is_udp_closed)
create_udp_v4 = @lib("udp.do", create_udp_v4)
bind_udp_v4 = @lib("udp.do", bind_udp_v4)
close_udp = @lib("udp.do", close_udp)
HttpRequest = @lib("http.client.do", HttpRequest)
HttpResponse = @lib("http.client.do", HttpResponse)
HttpClientError = @lib("http.client.do", HttpClientError)
HttpTimeout = @lib("http.client.do", HttpTimeout)
is_http_timeout = @lib("http.client.do", is_http_timeout)

accept_datetime(value Datetime) {
    return
}

accept_random(value Random) {
    return
}

accept_file(value File) {
    return
}

accept_dir(value Dir) {
    return
}

open_dir_shape(parent Dir, path text) -> Dir | DirError {
    return open_dir_at(parent, path)
}

close_dir_shape(dir Dir) -> nil {
    close_dir(dir)
    return
}

create_dir_shape(parent Dir, path text) -> DirError | nil {
    return create_dir_at(parent, path)
}

remove_dir_shape(parent Dir, path text) -> DirError | nil {
    return remove_dir_at(parent, path)
}

accept_input_stream(value InputStream) {
    return
}

accept_output_stream(value OutputStream) {
    return
}

accept_tcp_socket(value TcpSocket) {
    return
}

accept_udp_socket(value UdpSocket) {
    return
}

// Shape-only wrappers for G6.3 create/bind/close (no true host I/O in do test).
create_tcp_shape() -> TcpSocket | TcpError {
    return create_tcp_v4()
}

bind_tcp_shape(sock TcpSocket, addr Ipv4SocketAddress) -> TcpError | nil {
    return bind_tcp_v4(sock, addr)
}

close_tcp_shape(sock TcpSocket) -> nil {
    close_tcp(sock)
    return
}

create_udp_shape() -> UdpSocket | UdpError {
    return create_udp_v4()
}

bind_udp_shape(sock UdpSocket, addr Ipv4SocketAddress) -> UdpError | nil {
    return bind_udp_v4(sock, addr)
}

close_udp_shape(sock UdpSocket) -> nil {
    close_udp(sock)
    return
}

accept_http_request(value HttpRequest) {
    return
}

accept_http_response(value HttpResponse) {
    return
}

test "wasi p3 std wrapper shapes" {
    ok bool = true
    file_err FileError = FileClosed
    file_link_err FileError = FileLinkFailed
    file_outcome FileError | nil = nil
    dir_err DirError = DirClosed
    stream_err StreamError = StreamClosed
    stream_outcome StreamError | nil = nil
    tcp_err TcpError = TcpClosed
    udp_err UdpError = UdpClosed
    http_err HttpClientError = HttpTimeout

    ok = @and(ok, @eq(file_outcome, nil))
    ok = @and(ok, is_file_closed(file_err))
    ok = @and(ok, @eq(file_link_err, FileLinkFailed))
    ok = @and(ok, is_dir_closed(dir_err))
    ok = @and(ok, is_stream_closed(stream_err))
    ok = @and(ok, @eq(stream_outcome, nil))
    ok = @and(ok, is_tcp_closed(tcp_err))
    ok = @and(ok, is_udp_closed(udp_err))
    ok = @and(ok, is_http_timeout(http_err))
    if ok return
}
