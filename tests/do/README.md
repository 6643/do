# do 集成回归测试

目录说明:

- `cases/ok`: 期望编译成功的 `.do` 用例.
- `cases/err`: 期望编译失败的 `.do` 用例.
- `cases/err/*.expect`: 失败输出必须包含的关键文本(逐行匹配子串).
- `run_tests.sh`: 编译 `bin/do`, 然后通过 `do test xxx.do` 执行所有用例.
- `do test` 输出约定: 每个测试打印 `test "name" ... ok`, 最后打印汇总 `ok: N passed; 0 failed`.

执行:

```bash
./tests/do/run_tests.sh
```

可选:

- `ZIG_BIN=/path/to/zig ./tests/do/run_tests.sh`
