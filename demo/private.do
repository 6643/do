// 私有变量
.abc = 1

// 私有结构
.User{
    // 私有字段
    .id u8
}

// 私有函数
.find_user(id u8) User | nil {
    print(id)
    return nil
}

// 私有联合
.Shape =
        | Circle{r f64} = 1
        | Square{w f64, h f64}
        | Triangle{a f32, b f32, c f32}
        | Other = 110
        | error
        | bool
