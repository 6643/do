Result<T | E> = Ok(T) | Err(E)
Result<T> = Ok(T) | Err(T)

ByteKind<u8> = ByteSpace(1) | ByteDigit(2) | ByteLetter(3)

Message = Quit | Text([u8]) | Binary([u8]) | TcpAddr(IpSocketAddress)
Message<nil | [u8] | IpSocketAddress> = Quit(nil) | Text([u8]) | Binary([u8]) | TcpAddr(IpSocketAddress)
