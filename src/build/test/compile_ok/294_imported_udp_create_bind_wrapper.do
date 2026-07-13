// G6.3: public udp wrappers from lib/udp.do (create/bind/close).
create_udp_v4 = @lib("udp.do", create_udp_v4)
bind_udp_v4 = @lib("udp.do", bind_udp_v4)
close_udp = @lib("udp.do", close_udp)
ipv4_socket_address = @lib("udp.do", ipv4_socket_address)
UdpSocket = @lib("udp.do", UdpSocket)
UdpError = @lib("udp.do", UdpError)
Ipv4SocketAddress = @lib("udp.do", Ipv4SocketAddress)

start() {
    r UdpSocket | UdpError = create_udp_v4()
    if @is(r, UdpError) return
    s UdpSocket = r
    a Ipv4SocketAddress = ipv4_socket_address(127, 0, 0, 1, 8080)
    e UdpError | nil = bind_udp_v4(s, a)
    _ = e
    close_udp(s)
    return
}
