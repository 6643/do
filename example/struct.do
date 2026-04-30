// struct 语法设计总览(集中版)
// 使用类型: i32, Text, TypeExpr, TypeSetExpr
// 语法设计表达式: StructDecl, AliasDecl, TypeSetAliasDecl, StructLit, Destructure
//
// ## 4. 类型声明
// TypeDecl          := StructDecl | UnionDecl | AliasDecl | TypeSetAliasDecl
//
// StructDecl        := TypeName [ "<" TypeParams ">" ] "{" FieldDecl* "}"
// FieldDecl         := FieldName TypeExpr
// FieldName         := Ident
//
// UnionDecl         := TypeName "=" Variant ("|" Variant)+
// Variant           := TypeName [ "{" VariantFields "}" ]
// VariantFields     := VariantField ("," VariantField)* [","]
// VariantField      := Ident TypeExpr
//
// AliasDecl         := TypeName "=" TypeExpr
// TypeSetAliasDecl  := TypeName "=" TypeSetExpr
// TypeSetExpr       := TypeExpr ("|" TypeExpr)+
//
// TypeParams        := TypeParam ("," TypeParam)* [","]
// TypeParam         := Ident [ ":" TypeSetRef ]
// TypeSetRef        := TypeName | TypeSetExpr
// TypeExpr          := TypeName
//                   | TypeName "<" TypeList ">"
//                   | "(" TypeExpr ")"
// TypeList          := TypeExpr ("," TypeExpr)* [","]
// TypeName          := Ident
//
// 区分规则:
// 1. `TypeSetAliasDecl` 右侧必须至少包含 1 个 `|`.
// 2. `UnionDecl` 用于代数数据类型变体, `TypeSetAliasDecl` 用于约束类型集合.
// 3. 结构体泛型参数约束只允许类型集引用 `TypeSetRef`.
// 4. 无约束泛型参数直接写 `T`; 约束位只使用 `TypeSetRef`.
// 5. 函数能力约束统一放在函数 `#` 约束区.
// 6. 自建类型声明名遵循 `UpperCamel` + 字母数字集合.
//
// 设计示例(语法设计, 注释保真):
// 1. 结构体声明(Type.Struct)
// User {
//     id u32
//     .aid u32
//     name Text
// }
//
// 2. 无约束泛型结构体(Type.StructGenericFree)
// Box<T> {
//     value T
// }
//
// 3. 类型集约束结构体(Type.StructGenericTypeSet)
// Counter<T: i8 | i16 | i32 | i64> {
//     value T
// }
//
// 4. 联合类型声明(Type.Union)
// Shape = Circle{r f64} | Square{w f64, h f64}
//
// 5. 联合类型声明-结果类型(Type.UnionResult)
// Result = Ok{value i32} | Err{msg Text}
//
// 6. 类型别名(Type.Alias)
// UserId = u64
//
// 7. 类型集别名(Type.TypeSetAlias)
// SignedInt = i8 | i16 | i32 | i64
//
// 8. 聚合类型集别名(Type.TypeSetAliasAggregate)
// Number = SignedInt | u8 | u16 | u32 | u64 | f32 | f64
//
// ----
// 可执行正向示例(当前实现可解析子集):

User {
    id i32
    .aid i32
    name Text
}

Audit {
    actor Text
    action Text
}

UserId = i32
SignedInt = i8 | i16 | i32 | i64

new_user(id i32, name Text) User => User{id: id, .aid: id, name: name}
rename_user(u User, name Text) User => set(u, {.name: name})
pair_user(a User, b User) User, User => a, b

test "struct syntax design in one file" {
    uid UserId = 1
    u = new_user(uid, "tom")
    v = rename_user(u, "neo")
    left, right = pair_user(u, v)

    {name} = get(v, {.name})
    patch = {.name: "eve"}
    v2 = set(v, patch)
    log = Audit{actor: "tester", action: "rename"}

    if left return
    if right return
    if name return
    if v2 return
    if log return
}
