UdpError error = UdpClosed | UdpUnsupportedAddress | UdpHostFailure

UdpSocket {
    .fd i32
}

is_udp_closed(err UdpError) -> bool {
    return @eq(err, UdpClosed)
}
