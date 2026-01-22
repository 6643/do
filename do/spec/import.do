
// 动态路径导入示例
{_pi} = #("math")
{get} = #("lib/client.do")
{Config} = #("./config.do")
{version} = #("./local_utils.do")

// 动态路径导入示例
{request} = #("httpclient.zhangsan.2601.do")


// ffi
// {WasiIovec{buf_ptr i32, buf_len i32}, fd_write(i32, WasiIovec, i32, i32) -> i32}
{WasiIovec, fd_write} = #("wasi_snapshot_preview1")


test "import as struct destructuring" {
    // 这里的 _pi 是从 #math 结构体中解构出来的
    radius = 10.5
    area = mul(_pi, radius, radius)
    
    // 使用解构出来的 get 函数
    response = get("https://example.com")

    // 动态路径导入示例
    // 这种写法在编译期会被解析为常量结构体
    local_mod = #local_utils.do
    val = get(local_mod, version)
}


