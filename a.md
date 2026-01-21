User{
    id i32
    age u8
    name Text
}

Tuple<i32, f64>{100, 3.14}


Array<i32, 3>{10, 20, 30}
Array<i32>{10, 20, 30}

arr1 = set(Array<i32, 5>, [1, 2, 3, 4, 5])
arr2 = set(Array<i32>, [10, 20, 30])

Map<i32, f64>{100: 3.14}
Map<i32, f64>{}


m = set(Map<i32, i32>, {
    0: 0,
    12: 1222,
})


t = set(Tuple<i32, bool>, [1, true])


t = Tuple<i32, bool>{1, true}




// Union
Shape = Circle{r f64} | Square{w f64, h f64}
Result = i32 | nil
ErrorUnion = Text | error




继续按计划开发, 并对结果进行,验证,测试, 修复. 

功能细化拆分, 使用卫语句优化.


