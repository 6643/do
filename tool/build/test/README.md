# do build 回归测试

这个目录存放当前编译器/构建产物的黑盒回归测试，目录结构已按当前实现扁平化。
当前这里只承载 build 回归测试；若将来单独落 `do test` 命令，再另设 `tool/test/`。

目录说明:

- `ok`: 当前实现已支持, 且期望 `do test` 成功的 `.do` 用例.
- `err`: 当前实现已支持, 且期望 `do test` 失败的 `.do` 用例.
- `err/*.expect`: 失败输出包含的关键文本(逐行匹配子串).
- `compile_ok`: 期望 `do build <input.do> -o out.wat` 成功的用例.
- `compile_err`: 期望 `do build <input.do> -o out.wat` 失败的用例.
- `compile_err/*.expect`: 编译失败输出包含的关键文本.
- `run_tests.sh`: 编译 `tool` 下的编译器, 然后执行 `do test` 与编译模式两类用例.
- `do test` 输出约定: 每个测试打印 `test "name" ... ok`, 最后打印汇总 `ok: N passed; 0 failed`.

同步原则:

- 以 `doc/spec.md` 第 7 章为准维护用例.
- 语法错误统一按 parser 诊断契约处理: 首个错误立即停止, 输出文件/行/列、源码位置和支持的正确语法示例.
- 可保留少量语法错误烟测, 只用于锁定诊断输出格式.

执行:

```bash
./tool/build/test/run_tests.sh
```

可选:

- `ZIG_BIN=/path/to/zig ./tool/build/test/run_tests.sh`
- `SKIP_BUILD=1 ./tool/build/test/run_tests.sh`
