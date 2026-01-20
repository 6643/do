// 在 do 语言中，每个文件都被视为一个隐式的结构体布局
// 只有非 . 开头的成员才会被导出

// 1. 导入标准库 (查找项目 lib/ 或内置 lib/)
// 编译器执行：math_mod = #math; _pi = get(math_mod, ._pi)
// 注意：_pi 在 math.do 中定义为公有只读，但在当前文件因前置 _ 变为只读
{_pi} = #math

// 2. 导入当前项目 lib 下的特定文件 (通过字符串路径)
// 返回该文件导出的结构体实例
{get} = #client.do

// 3. 导入相对路径文件
{Config} = #config.do

// 支持多行字符串路径 (适用于超长路径或动态生成的路径说明)
{LongMod} = #name_component.do


// 4. 导入外部包 (带参数的类型函数)
{request} = #httpclient.zhangsan.2601.do


// 5. FFI 结构体与函数映射 (保持之前的设计)
WasiIovec = #wasi_snapshot_preview1.WasiIovec {
    buf_ptr i32
    buf_len i32
}

fd_write = #wasi_snapshot_preview1.fd_write(i32, WasiIovec, i32, i32) -> i32

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