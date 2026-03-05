# do 集成回归测试

目录说明:

- `cases/ok`: 期望编译成功的 `.do` 用例.
- `cases/err`: 期望编译失败的 `.do` 用例.
- `cases/err/*.expect`: 失败输出必须包含的关键文本(逐行匹配子串).
- `cases/compile_ok`: 期望 `do <input.do> -o out.wat` 成功的用例.
- `cases/compile_err`: 期望 `do <input.do> -o out.wat` 失败的用例.
- `cases/compile_err/*.expect`: 编译失败输出必须包含的关键文本.
- `run_tests.sh`: 编译 `bin/do`, 然后执行 `do test` 与编译模式两类用例.
- `do test` 输出约定: 每个测试打印 `test "name" ... ok`, 最后打印汇总 `ok: N passed; 0 failed`.

执行:

```bash
./tests/do/run_tests.sh
```

可选:

- `ZIG_BIN=/path/to/zig ./tests/do/run_tests.sh`
