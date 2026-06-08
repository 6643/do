TcpError error = TcpClosed | TcpUnsupportedAddress | TcpHostFailure

TcpListener {
    .fd i32
}

TcpStream {
    .fd i32
}

is_tcp_closed(err TcpError) -> bool {
    return @eq(err, TcpClosed)
}
