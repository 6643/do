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

test "raw multi-line" {
    // 这种语法非常适合存放 HTML, SQL 或 原始文本
    html = 
        \\<div>
        \\  <h1>Title</h1>
        \\</div>

    print(html)
}

