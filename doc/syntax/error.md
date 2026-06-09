# 错误

## 错误枚举

```do
FileError error = FileNotFound | FilePermissionDenied | FileClosed // 文件错误枚举

ParseError error = ParseEmpty | ParseInvalid // 解析错误枚举
```

## 错误返回

```do
// 文件读取错误返回
read_file(path text) -> [u8] | FileError {
    return FileNotFound
}

// 解析错误返回
parse(input text) -> i32 | ParseError {
    return ParseInvalid
}

// 错误或 nil 返回
load(path text) -> [u8] | FileError | nil {
    return nil
}
```

## 错误分支判断

```do
result [u8] | FileError = read_file("a.txt") // 错误联合绑定

// 判断错误分支
if @is(result, FileError) {
    return result
}

// 判断值分支
if @is(result, [u8]) {
    return result
}
```

## 多错误返回

```do
// 多错误来源直接写在返回类型里
load_config(path text) -> [u8] | FileError | ParseError | nil {
    return nil
}
```
