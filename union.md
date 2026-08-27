Result<T | E> = Ok(T) | Err(E)
Result<T> = Ok(T) | Err(T)

Option<T> = Some(T) | nil

ByteKind<u8> = ByteSpace(1) | ByteDigit(2) | ByteLetter(3)

Message = Quit | Text([u8]) | Binary([u8]) | TcpAddr(IpSocketAddress)

// 无载荷
// 单载荷
// 多载荷
E = A | B(i32) | C(i32, i64)

// 类型, 值绑定
ByteKind<u8> = ByteSpace(1) | ByteDigit(2) | ByteLetter(3)

match e{
A => print("A")

}

• 本阶段计划已完成闭环，新增并验证了固定的 mixed scalar-list record lower route：

demo:marshal-record-mixed-scalar-list-lower/api.write@1.0.0/lower

验证结果：

- Zig 单测：625/625
- 集成回归：1328 pass，0 fail，3 skip
- ReleaseSmall、release smoke、GC default gate：通过，76 fixtures
- G5c residual gate：通过
- 75 个新增 shell 脚本语法检查通过
- 两个新 Rust runner 定向格式检查通过
- wasm-tools 1.255.0
- git diff --check 通过
- 文档已同步：doc/pending_blocked.md、doc/roadmap_status.md
