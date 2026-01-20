
Tuple<i32, f64>{100, 3.14};
Array<i32, 3>{10, 20, 30};
Array<i32>{10, 20, 30};
Map<i32, f64>{100: 3.14};
Map<i32, f64>{};

// Union
Shape = Circle{r f64} | Square{w f64, h f64}
Result = i32 | nil
ErrorUnion = Text | error




继续按计划开发, 并对结果进行,验证,测试, 修复. 

功能细化拆分, 使用卫语句优化.


