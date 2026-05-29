/**
 * do 语言 WASM 运行时内存效率计算脚本
 *
 * 功能：计算在 4KB 页面下，不同 Slot 规格的内存利用率。
 * 公式：(格数 * (Slot大小 - 元数据)) / 4096
 */

const PAGE_SIZE = 4096;

interface Config {
    name: string;
    meta: number;
}

const CONFIGS: Record<string, Config> = {
    A: { name: "极简型", meta: 2 },
    B: { name: "紧凑型", meta: 4 },
    C: { name: "标准型", meta: 8 },
};

const SLOT_SIZES = [
    8, 12, 16, 20, 24, 32, 40, 48, 56, 64, 72, 80, 96, 112, 128, 144, 160, 192, 224, 256, 320, 384, 448, 512, 768, 1024,
];

function runAnalysis(configKey: string) {
    const config = CONFIGS[configKey];
    console.log(`\n### 配置 ${configKey}：${config.name} (Meta=${config.meta}B, Page=${PAGE_SIZE}B)`);

    const tableData = SLOT_SIZES.map((slotSize) => {
        const n = Math.floor(PAGE_SIZE / slotSize);
        const tailWaste = PAGE_SIZE % slotSize;
        const payload = slotSize - config.meta;
        const netUsage = (n * payload) / PAGE_SIZE;
        const usagePercent = (netUsage * 100).toFixed(1) + "%૭";

        return {
            "Slot Size": slotSize,
            "N (Count)": n,
            Payload: payload,
            "Tail Waste": tailWaste,
            Efficiency: usagePercent,
        };
    });

    console.table(tableData);
}

// 默认生成三套配置的对比
runAnalysis("A");
runAnalysis("B");
runAnalysis("C");

const abc = () => {
    let count = 0;
    const a = () => {
        count++;
        console.log(count);
    };

    console.log(count);
    a();
    a();

    a();
    a();
    a();
    a();
};

/*
// 兄弟
a = @.a.do/a
b = @.a/b.do/b

// lib > std
c = @c.do/c



pi = @user.math.do/pi
pi = @/math.do/pi


.
.
├── tool/                   # 编译器与工具逻辑
│   ├── build.zig
│   ├── run/                # do run 的逻辑实现 (运行工具)
│   ├── build/              # do build 的逻辑实现 (编译工具)
│   ├── get/                # do get 的逻辑实现 (下载工具)
│   ├── push/               # do push 的逻辑实现 (上传工具)
│   ├── fmt/                # do fmt 的逻辑实现 (格式化工具)
│   └── lsp/                # do lsp 的逻辑实现 (语言服务)
├── src/                    # builtin/core/std
├── bin/                    # 产物 (编译出的唯一工具)
│   └── do                  # 这是唯一的二进制文件，它包含了上述所有功能

*/
