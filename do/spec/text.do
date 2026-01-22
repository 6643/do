test "string literals" {
    // 1. 单行字符串
    name = "ZhangSan"

    // 2. 多行字符串 (Zig 风格)
    // 每一行以 \\ 开始，自动保留换行，不需要引号
    bio = 
        \\Hello, my name is ${name}.
        \\I am a developer of the do programming language.
        \\This is a multi-line string.

    // 3. 嵌套插值
    info = "Bio: ${bio}"

    print(info)
}