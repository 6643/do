test "string literals" {
    // 1. 单行字符串
    name = "ZhangSan"

    // 2. 嵌套插值
    info = "Bio: ${bio}"

    print(info)
}

test "multi-line string specification" {
    // 1. 基础用法：左侧对齐不受代码缩进影响
    // 定界符 \\ 之前的缩进会被忽略
    sql = 
        \\SELECT *
        \\FROM users
        \\WHERE id = 1
    print(sql)

    // 2. 插值支持：保持扁平
    table = "orders"
    query = 
        \\SELECT * FROM ${table}
        \\LIMIT 10

    print(query)

    // 3. 包含特殊字符：无需转义引号
    // 适合书写 JSON, HTML 等原始文本
    json_snippet =
        \\{
        \\  "name": "do_lang",
        \\  "features": ["simple", "flat"]
        \\}

    print(json_snippet)

    // 4. 空行表达
    // 仅需一个 \\ 后接换行即可表达空行，增强视觉连续性
    poem =
        \\First line
        \\
        \\Third line (after an empty line)
    print(poem)
}
