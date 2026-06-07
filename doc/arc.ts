/**
 * do 语言 WASM 运行时 ARC / 小对象规格效率分析脚本。
 *
 * 目标:
 * - 按当前 memory_layout_structs.md 草案计算 1KB SmallBlock 利用率。
 * - 估算不同 payload 大小落入 slot class 后的 internal fragmentation。
 * - 验证小对象规格至少能放 2 个 slot; 只能放 1 个的规格应走 LargeBlock。
 *
 * 运行:
 *   bun doc/arc.ts
 *   tsc --noEmit --target ES2020 --module commonjs doc/arc.ts
 */

const WASM_PAGE_SIZE = 64 * 1024;
const BLOCK_SIZE = 1024;
const ALIGNMENT = 4;

// Object = rc u32 + type_id u32 + data
const OBJECT_HEADER_BYTES = 8;

// SmallBlock compact layout:
// cap u8 + slot_units u8 + flags u8 + pad u8 + next_block u32
const SMALL_BLOCK_HEADER_BYTES = 8;

// LargeBlock = cap u8 + pad[3]u8 + span_len u32
const LARGE_BLOCK_HEADER_BYTES = 8;

const MIN_SLOT_SIZE = 8;
const MAX_SLOT_SIZE = 512;

const CANDIDATE_SLOT_SIZES = Array.from(
    { length: (MAX_SLOT_SIZE - MIN_SLOT_SIZE) / ALIGNMENT + 1 },
    (_, index) => MIN_SLOT_SIZE + index * ALIGNMENT,
);

const SAMPLE_PAYLOADS = [
    0, 1, 4, 8, 12, 16, 20, 24, 32, 48, 64, 96, 128, 192, 256, 384, 512,
];

type SlotAnalysis = {
    slot: number;
    slotUnits: number;
    small: "yes" | "no";
    cap: number;
    headerBytes: number;
    bitmapBytes: number;
    dataStart: number;
    remainingBytes: number;
    objectPayloadBytes: number;
    payloadEfficiency: string;
};

function alignUp(value: number, alignment: number): number {
    return Math.ceil(value / alignment) * alignment;
}

function percent(numerator: number, denominator: number): string {
    if (denominator === 0) return "0.0%";
    return `${((numerator / denominator) * 100).toFixed(1)}%`;
}

function bitmapBytes(cap: number): number {
    return Math.ceil(cap / 8);
}

function dataStart(cap: number, headerBytes = SMALL_BLOCK_HEADER_BYTES): number {
    return alignUp(headerBytes + bitmapBytes(cap), ALIGNMENT);
}

function usedBlockBytes(slotSize: number, cap: number, headerBytes = SMALL_BLOCK_HEADER_BYTES): number {
    return dataStart(cap, headerBytes) + cap * slotSize;
}

function maxCapForSlot(slotSize: number, headerBytes = SMALL_BLOCK_HEADER_BYTES): number {
    const maxByHeader = Math.floor((BLOCK_SIZE - headerBytes) / slotSize);

    for (let cap = maxByHeader; cap >= 1; cap -= 1) {
        if (usedBlockBytes(slotSize, cap, headerBytes) <= BLOCK_SIZE) return cap;
    }

    return 0;
}

function allSlotAnalyses(): SlotAnalysis[] {
    return CANDIDATE_SLOT_SIZES.map((slotSize) => analyzeSlot(slotSize));
}

function selectedSlotAnalyses(): SlotAnalysis[] {
    const byCap = new Map<number, SlotAnalysis>();

    for (const analysis of allSlotAnalyses()) {
        if (analysis.cap <= 1) continue;

        const existing = byCap.get(analysis.cap);
        if (
            existing === undefined ||
            analysis.remainingBytes < existing.remainingBytes ||
            (analysis.remainingBytes === existing.remainingBytes && analysis.slot < existing.slot)
        ) {
            byCap.set(analysis.cap, analysis);
        }
    }

    return Array.from(byCap.values()).sort((a, b) => a.slot - b.slot);
}

function chooseSlot(objectBytes: number): SlotAnalysis | null {
    for (const analysis of selectedSlotAnalyses()) {
        if (analysis.slot >= objectBytes) return analysis;
    }

    return null;
}

function analyzeSlot(slotSize: number): SlotAnalysis {
    const cap = maxCapForSlot(slotSize);
    const bitmap = bitmapBytes(cap);
    const data = dataStart(cap);
    const remainingBytes = BLOCK_SIZE - usedBlockBytes(slotSize, cap);
    const objectPayloadBytes = Math.max(0, slotSize - OBJECT_HEADER_BYTES);
    const payloadBytesPerBlock = objectPayloadBytes * cap;

    return {
        slot: slotSize,
        slotUnits: slotSize / ALIGNMENT,
        small: cap > 1 ? "yes" : "no",
        cap,
        headerBytes: SMALL_BLOCK_HEADER_BYTES,
        bitmapBytes: bitmap,
        dataStart: data,
        remainingBytes,
        objectPayloadBytes,
        payloadEfficiency: percent(payloadBytesPerBlock, BLOCK_SIZE),
    };
}

function analyzePayload(payloadBytes: number) {
    const objectBytes = alignUp(OBJECT_HEADER_BYTES + payloadBytes, ALIGNMENT);
    const slot = chooseSlot(objectBytes);

    if (slot === null) {
        const totalBytes = LARGE_BLOCK_HEADER_BYTES + objectBytes;
        const spanLen = Math.ceil(totalBytes / BLOCK_SIZE);

        return {
            payloadBytes,
            objectBytes,
            mode: "large",
            slot: "-",
            cap: 1,
            spanLen,
            internalWaste: spanLen * BLOCK_SIZE - totalBytes,
            payloadEfficiency: percent(payloadBytes, spanLen * BLOCK_SIZE),
        };
    }

    return {
        payloadBytes,
        objectBytes,
        mode: "small",
        slot: slot.slot,
        slotUnits: slot.slotUnits,
        cap: slot.cap,
        spanLen: 1,
        internalWaste: slot.slot - objectBytes,
        remainingBytes: slot.remainingBytes,
        payloadEfficiency: percent(payloadBytes * slot.cap, BLOCK_SIZE),
    };
}

function printConstants() {
    console.log("## Constants");
    console.table([
        { name: "WASM_PAGE_SIZE", value: WASM_PAGE_SIZE },
        { name: "BLOCK_SIZE", value: BLOCK_SIZE },
        { name: "ALIGNMENT", value: ALIGNMENT },
        { name: "OBJECT_HEADER_BYTES", value: OBJECT_HEADER_BYTES },
        { name: "SMALL_BLOCK_HEADER_BYTES", value: SMALL_BLOCK_HEADER_BYTES },
        { name: "LARGE_BLOCK_HEADER_BYTES", value: LARGE_BLOCK_HEADER_BYTES },
        { name: "MIN_SLOT_SIZE", value: MIN_SLOT_SIZE },
        { name: "MAX_SLOT_SIZE", value: MAX_SLOT_SIZE },
    ]);
}

function printSlotAnalysis() {
    console.log("\n## SmallBlock selected slot classes");
    console.table(selectedSlotAnalyses());
}

function printAllSlotAnalysis() {
    console.log("\n## SmallBlock all 4B-step candidates");
    console.table(allSlotAnalyses());
}

function printPayloadAnalysis() {
    console.log("\n## Payload size-class analysis");
    console.table(SAMPLE_PAYLOADS.map((payloadBytes) => analyzePayload(payloadBytes)));
}

printConstants();
printSlotAnalysis();
printPayloadAnalysis();
printAllSlotAnalysis();
