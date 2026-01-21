// 1. 命名联合 (Named Union / Tagged Union)
// 类似 Rust 的 Enum，每个分支可以携带数据
Shape = Circle{r f64} | Square{w f64, h f64}

// 2. 匿名联合 (Anonymous Union)
// 常用于简单的逻辑判断或可选值
Result = i32 | nil
ErrorUnion = Text | error


test "named union match" {
    s = Circle{r: 10.5}
    
    area = match s {
        Circle{r}: mul(3.14, r, r)
        Square{w, h}: mul(w, h)
    }

    if Circle{r} := s {
        print("Radius: ${r}")
    }
}

test "anonymous union and nil" {
    // 实例化可选值
    val i32 | nil = 100
    
    // 使用 match 处理 nil
    msg = match val {
        i32(v): "Value is ${v}"
        nil:    "No value"
    }

    // 快捷解构
    if i32(v) := val {
        print("Got value: ${v}")
    }
}

test "error handling pattern" {
    // 联合类型作为错误处理机制
    res Text | error = "Success Content"
    
    output = match res {
        Text(t): t
        error(e): "Failed: ${e}"
    }
    
    // 模拟失败
    fail_res Text | error = error("Network Timeout")
    if error(e) := fail_res {
        print("Error occurred: ${e}")
    }
}