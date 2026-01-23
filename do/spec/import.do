
// 动态路径导入示例
.{_pi} = #("math")
.{get} = #("lib/client.do")
.{Config} = #("./config.do")
.{version} = #("./local_utils.do")

// 动态路径导入示例
.{request} = #("httpclient.zhangsan.2601.do")


// ffi
// {WasiIovec{buf_ptr i32, buf_len i32}, fd_write(i32, WasiIovec, i32, i32) => i32}
.{WasiIovec, fd_write} = #("wasi_snapshot_preview1")

