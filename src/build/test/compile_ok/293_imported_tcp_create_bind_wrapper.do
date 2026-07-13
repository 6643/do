// G6.3: public tcp wrappers from lib/tcp.do (create/bind/close).
create_tcp_v4 = @lib("tcp.do", create_tcp_v4)
bind_tcp_v4 = @lib("tcp.do", bind_tcp_v4)
close_tcp = @lib("tcp.do", close_tcp)
ipv4_socket_address = @lib("tcp.do", ipv4_socket_address)
TcpSocket = @lib("tcp.do", TcpSocket)
TcpError = @lib("tcp.do", TcpError)
Ipv4SocketAddress = @lib("tcp.do", Ipv4SocketAddress)

start() {
    r TcpSocket | TcpError = create_tcp_v4()
    if @is(r, TcpError) return
    s TcpSocket = r
    a Ipv4SocketAddress = ipv4_socket_address(127, 0, 0, 1, 8080)
    e TcpError | nil = bind_tcp_v4(s, a)
    _ = e
    close_tcp(s)
    return
}
