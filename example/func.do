// func 语法设计总览(集中版)
// 使用类型: i32, bool, Text, TypeExpr, MultiReturnSpec, VariadicParam
// 语法设计表达式: FuncDecl, FuncConstraint, ArrowExprList, ReturnExprList, CallExpr, IfCondExpr
//
// ## 5. 函数声明
// FuncDecl            := FuncConstraint* FuncName "(" Params? ")" [ReturnSpec] (Block | "=>" ArrowExprList)
// FuncConstraint      := "#" (FuncSigConstraint | TypeSetConstraint)
// FuncSigConstraint   := Ident "(" TypeList? ")" "=>" ReturnSpec
// TypeSetConstraint   := TypeVar ":" (TypeSetExpr | TypeName)
// TypeVar             := Ident
// FuncName            := Ident
// ReturnSpec          := TypeExpr | MultiReturnSpec
// MultiReturnSpec     := TypeExpr "," TypeExpr ("," TypeExpr)*
// ArrowExprList       := Expr ("," Expr)* [","]
// Params              := VariadicParam [","]
//                    | ParamList ["," VariadicParam] [","]
//                    | ParamList [","]
// ParamList           := Param ("," Param)*
// Param               := Ident TypeExpr
// VariadicParam       := Ident "..." TypeExpr
//
// 约束规则:
// 1. `#` 约束只作用于其后紧邻的 1 个函数声明.
// 2. `TypeVar` 通过约束和函数参数自动引入.
// 3. 约束中出现的 `TypeVar` 必须在函数签名中可解.
// 4. 约束语法固定为 `#T: ...` 或函数签名约束 `#f(T1, T2, ...) => R`.
// 5. `#T: ...` 支持直接类型集字面量和类型集别名.
// 6. 类型集约束用于"限制一类类型", 例如 `i8 | i16 | i32 | i64`.
// 7. 未满足约束时, 编译期报错.
// 8. `FuncSigConstraint` 采用类型列表位形.
// 9. `VariadicParam` 只能出现在参数列表末尾.
// 10. 变长参数位的所有实参类型与 `...` 后类型保持一致.
// 11. 变长参数函数可接收 `>= 固定参数个数` 的实参数量.
// 12. 当签名满足 `f(a T, b T, rest ...T) T` 时, 该重载实例支持扁平化语义.
// 13. 扁平化能力由签名形态直接决定.
// 14. 支持 Go 风格多返回值声明: `f(...) T1, T2, ...`.
// 15. 多返回声明写法为 `f(...) T1, T2, ...`.
// 16. 箭头函数支持多表达式: `=> e1, e2, ...`, 返回位数需与 `ReturnSpec` 一致.
//
// 设计示例(语法设计, 注释保真):
// 1. 私有函数-块体(Func.PrivateBlock)
// 示例已放到下方可执行代码区.
//
// 2. 公有函数-块体(Func.PublicBlock)
// format_user_name(u User) Text {
//     return .normalize_name(get(u, .name))
// }
//
// 3. 箭头表达式函数(Func.ArrowExpr)
// sum(a i32, b i32) i32 => add(a, b)
//
// 4. 无返回类型函数(Func.NoReturnType)
// log_info(msg Text) {
//     print(msg)
// }
//
// 4.1 多返回值函数(Func.MultiReturn)
// divmod(a i32, b i32) i32, i32 {
//     q = div(a, b)
//     r = rem(a, b)
//     return q, r
// }
//
// 4.2 箭头多表达式返回(Func.ArrowMultiExpr)
// pair(a i32, b i32) i32, i32 => a, b
//
// 5. 类型限制泛型函数(Func.Constraint.TypeLimit)
// #T: User | Result
// echo_entity(a T) T => a
//
// 6. 函数签名约束泛型函数(Func.Constraint.Callable)
// #min(T, T) => T
// min_abc(a T, b T) => min(a, b)
//
// 7. 类型集约束-字面量(Func.Constraint.TypeSetLiteral)
// #T: i8 | i16 | i32 | i64
// abs(a T) T {
//     if lt(a, 0) return sub(0, a)
//     return a
// }
//
// 8. 类型集约束-聚合别名(Func.Constraint.TypeSetAlias)
// #T: SignedInt
// neg(a T) T => sub(0, a)
//
// 9. 同类型变长参数函数(Func.Variadic.SameType)
// add(a i32, b i32, rest ...i32) i32 => reduce_add(a, b, rest)
//
// ### 5.1 函数重载规则
// 规则:
// 1. 允许同名重载, 由参数个数和参数类型区分.
// 2. 重载决议键固定为参数列表(个数+类型).
// 3. 决议顺序全局固定, 与文件或上下文无关.
// 4. 解析优先级: 精确类型 > `#` 约束泛型 > 无约束泛型.
// 5. `具体类型` 与 `类型集约束` 重叠时, `具体类型` 优先.
// 6. 同名同签名位形的两个类型集约束若存在交集, 编译期报错.
// 7. 同一文件中, 同名函数签名约束重载必须互斥(交集为空).
// 8. 多个变参候选并列时, 固定参数前缀更长者优先.
// 9. 若多个候选同优先级仍并列, 编译期报 `AmbiguousOverload`.
// 10. 重载决议按实参已定型类型直接匹配.
// 11. 字面量先按默认类型定型后再参与重载决议.
//
// 设计示例(语法设计, 注释保真):
// 1. 按参数个数重载(Func.Overload.Arity)
// sum(a i32, b i32) i32 => add(a, b)
// sum(a i32, b i32, c i32) i32 => add(a, b, c)
//
// 2. 按参数类型重载(Func.Overload.ParamType)
// to_text(n i32) Text => itoa(n)
// to_text(b bool) Text {
//     if b return "true"
//     return "false"
// }
//
// 3. 精确类型优先于约束泛型(Func.Overload.Priority)
// stringify(a Text) Text => a
// #to_text(T) => Text
// stringify(a T) Text => to_text(a)
//
// 4. 具体类型优先于类型集(Func.Overload.ConcreteOverTypeSet)
// show(x i32) Text => "i32"
// #T: SignedInt
// show(x T) Text => "signed"
//
// 5. 多变参冲突时固定前缀更长优先(Func.Overload.VariadicPrefix)
// merge(a i32, rest ...i32) i32 => fold_add(a, rest)
// merge(a i32, b i32, rest ...i32) i32 => fold_add2(a, b, rest)
//
// ### 5.2 同类型变长参数与扁平化
// 规则:
// 1. 对同一目标函数和同一重载实例, 可写多参数调用: `add(a, b, c, d)`.
// 2. 若该重载签名满足 `f(a T, b T, rest ...T) T`, 则允许扁平化.
// 3. 扁平化等价: `f(f(x1, x2), x3)` => `f(x1, x2, x3)`.
// 4. 扁平化改写触发条件为签名满足该形态.
//
// 设计示例(语法设计, 注释保真):
// 1. 手写扁平调用(Variadic.FlatCall)
// 示例已放到下方 test 中: `total_flat = add(a, b, c)`.
//
// 2. 等价改写前(Variadic.NestedCall)
// total = add(add(a, b), c)
//
// 3. 签名满足时的改写后(Variadic.Normalize)
// 示例已放到下方 test 中: `total_flat = add(a, b, c)`.
//
// ----
// 可执行正向示例(当前实现可解析子集):

add_i32(a i32, b i32) i32 => add(a, b)
trim(s Text) Text => s
always_true() bool => true
swap(a i32, b i32) i32, i32 => b, a
label(s Text) Text => s
add(a i32, b i32, c i32) i32 => add(add(a, b), c)

.normalize_name(name Text) Text {
    return trim(name)
}

sum_and_label(a i32, b i32) i32, Text {
    total = add_i32(a, b)
    return total, "ok"
}

test "func syntax design in one file" {
    x = add_i32(1, 2)
    a, b = swap(3, 4)
    c = 5
    total, tag = sum_and_label(a, b)
    total_flat = add(a, b, c)
    name = label("demo")
    normalized = .normalize_name(name)

    if always_true() return
    if x return
    if total return
    if total_flat return
    if tag return
    if name return
    if normalized return
}
