// import 语法设计总览(集中版)
// 使用类型: Text, i32, ImportType, ImportFunc
// 语法设计表达式: ImportDecl, ImportItem, ImportSymbol, ImportValue, ImportType, ImportFunc
//
// ## 3. 顶层结构-导入
// ImportDecl      := "{" ImportItem ("," ImportItem)* [","] "}" ":=" "@" "(" String ")"
// ImportItem      := ImportSymbol | ImportValue | ImportType | ImportFunc
// ImportSymbol    := Ident [ ":" Ident ]
// ImportValue     := Ident TypeExpr
// ImportType      := TypeName "{" ImportFieldList? "}"
// ImportFieldList := ImportField ("," ImportField)* [","]
// ImportField     := Ident TypeExpr
// ImportFunc      := Ident "(" ImportTypeList? ")" "=>" TypeExpr
// ImportTypeList  := TypeExpr ("," TypeExpr)* [","]
//
// 导入规则:
// 1. 导入只使用解构绑定语法: `{item, ...} := @source`.
// 2. 导入语法固定为 `@` 解构绑定: `{...} := @("path")`.
// 3. `ImportItem` 支持 4 类: `ImportSymbol`/`ImportValue`/`ImportType`/`ImportFunc`.
// 4. 符号导入支持重命名: `{local:exported}`.
// 5. `ImportFunc` 采用纯类型位形, 例如 `fd_write(i32, WasiIovec, i32, i32) => i32`.
// 6. `ImportType` 仅用于声明外部布局字段, 例如 `WasiIovec{buf_ptr i32, buf_len i32}`.
// 7. 导入项本地名与关键字互斥, 冲突名必须显式重命名.
// 8. `source` 统一写字符串路径, 支持标准库与相对路径.
//
// 设计示例(语法设计, 注释保真):
// 1. 基础导入
// {sqrt, pow} := @("math")
//
// 2. 符号重命名
// {m_sqrt:sqrt, m_pow:pow} := @("math")
//
// 3. FFI 混合导入
// {
//     key Text,
//     WasiIovec{buf_ptr i32, buf_len i32},
//     fd_write(i32, WasiIovec, i32, i32) => i32,
// } := @("wasi_snapshot_preview1")
//
// 4. 冲突名重命名
// {
//     kw_if:if,
//     ffi_wait(i32, i32) => i32,
// } := @("ffi_mod")
//
// ----
// 可执行正向示例(当前实现可解析子集):

{sqrt, pow} := @("math")
{m_sqrt:sqrt, m_pow:pow} := @("math")

{
    key Text,
    WasiIovec{buf_ptr i32, buf_len i32},
    fd_write(i32, WasiIovec, i32, i32) => i32,
} := @("wasi_snapshot_preview1")

{
    kw_if:if,
    ffi_wait(i32, i32) => i32,
} := @("ffi_mod")

test "import syntax design in one file" {
    a = sqrt(4)
    b = m_sqrt(9)
    c = key
    if a return
    if b return
    if c return
}
