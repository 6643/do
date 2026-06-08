export const BLOCK_SIZE = 1024;
export const WASM_PAGE_SIZE = 64 * 1024;
export const BLOCKS_PER_PAGE = WASM_PAGE_SIZE / BLOCK_SIZE;
export const SMALL_BLOCK_HEADER_BYTES = 8;
export const LARGE_BLOCK_HEADER_BYTES = 8;
export const OBJECT_HEADER_BYTES = 8;
export const ALIGNMENT = 4;

const NONE_BLOCK = 0xffff_ffff;

type FreeBlock = {
    kind: "free";
    spanLen: number;
    nextFree: number;
};

type FreeContBlock = {
    kind: "free_cont";
};

type SmallBlock = {
    kind: "small";
    cap: number;
    slotUnits: number;
    nextBlock: number;
    bitmap: number[];
};

type LargeBlock = {
    kind: "large";
    spanLen: number;
};

type LargeContBlock = {
    kind: "large_cont";
};

type Block = FreeBlock | FreeContBlock | SmallBlock | LargeBlock | LargeContBlock;

export type Allocation = {
    kind: "small" | "large";
    offset: number;
    bytes: number;
    slotUnits: number;
    slotIndex: number;
};

export type SlotClassView = {
    headBlock: number;
    cursorBlock: number;
};

export function packSlotClassState(headBlock: number, cursorBlock: number): bigint {
    return (BigInt(headBlock >>> 0) << 32n) | BigInt(cursorBlock >>> 0);
}

export function unpackSlotClassState(state: bigint): SlotClassView {
    return {
        headBlock: Number((state >> 32n) & 0xffff_ffffn),
        cursorBlock: Number(state & 0xffff_ffffn),
    };
}

export function blockIndexOf(allocation: Pick<Allocation, "offset">): number {
    return Math.floor(allocation.offset / BLOCK_SIZE);
}

function alignUp(value: number, alignment: number): number {
    return Math.ceil(value / alignment) * alignment;
}

function bitmapBytes(cap: number): number {
    return Math.ceil(cap / 8);
}

function smallDataStart(cap: number): number {
    return alignUp(SMALL_BLOCK_HEADER_BYTES + bitmapBytes(cap), ALIGNMENT);
}

function smallUsedBytes(slotSize: number, cap: number): number {
    return smallDataStart(cap) + cap * slotSize;
}

function smallCapForSlot(slotSize: number): number {
    const maxByHeader = Math.floor((BLOCK_SIZE - SMALL_BLOCK_HEADER_BYTES) / slotSize);

    for (let cap = maxByHeader; cap >= 1; cap -= 1) {
        if (smallUsedBytes(slotSize, cap) <= BLOCK_SIZE) return cap;
    }

    return 0;
}

function blockStart(blockIndex: number): number {
    return blockIndex * BLOCK_SIZE;
}

function blockPayloadOffset(blockIndex: number, cap: number, slotIndex: number, slotSize: number): number {
    return blockStart(blockIndex) + smallDataStart(cap) + slotIndex * slotSize;
}

function getBit(bitmap: number[], slotIndex: number): boolean {
    return ((bitmap[Math.floor(slotIndex / 32)] >>> (slotIndex % 32)) & 1) === 1;
}

function setBit(bitmap: number[], slotIndex: number) {
    bitmap[Math.floor(slotIndex / 32)] |= 1 << (slotIndex % 32);
}

function clearBit(bitmap: number[], slotIndex: number) {
    bitmap[Math.floor(slotIndex / 32)] &= ~(1 << (slotIndex % 32));
}

function popcountWord(word: number): number {
    let value = word >>> 0;
    let count = 0;

    while (value !== 0) {
        value &= value - 1;
        count += 1;
    }

    return count;
}

function usedCount(block: SmallBlock): number {
    return block.bitmap.reduce((total, word) => total + popcountWord(word), 0);
}

function findFreeSlot(block: SmallBlock): number | null {
    for (let slot = 0; slot < block.cap; slot += 1) {
        if (!getBit(block.bitmap, slot)) return slot;
    }

    return null;
}

export class ArcAllocator {
    private blocks: Block[];
    private slotClasses = new Map<number, bigint>();
    private readonly emptySlotClassState = packSlotClassState(NONE_BLOCK, NONE_BLOCK);

    constructor() {
        this.blocks = Array.from({ length: BLOCKS_PER_PAGE }, () => ({ kind: "free_cont" }));
        this.writeFreeSpan(0, BLOCKS_PER_PAGE);
    }

    alloc(payloadBytes: number): Allocation {
        const objectBytes = alignUp(OBJECT_HEADER_BYTES + payloadBytes, ALIGNMENT);
        const slotUnits = Math.ceil(objectBytes / ALIGNMENT);
        const slotSize = slotUnits * ALIGNMENT;
        const cap = smallCapForSlot(slotSize);

        if (cap > 1) {
            return this.allocSmall(slotUnits, slotSize, cap, payloadBytes);
        }

        return this.allocLarge(objectBytes, payloadBytes, slotUnits);
    }

    free(allocation: Allocation) {
        if (allocation.kind === "small") {
            this.freeSmall(allocation);
            return;
        }

        this.freeLarge(allocation);
    }

    slotClassState(slotUnits: number): SlotClassView {
        return unpackSlotClassState(this.slotClasses.get(slotUnits) ?? this.emptySlotClassState);
    }

    freeSpanAt(blockIndex: number): FreeBlock | null {
        const block = this.blocks[blockIndex];
        return block.kind === "free" ? block : null;
    }

    private allocSmall(slotUnits: number, slotSize: number, cap: number, payloadBytes: number): Allocation {
        const state = this.slotClassState(slotUnits);
        const startBlock = state.cursorBlock !== NONE_BLOCK ? state.cursorBlock : state.headBlock;
        const found = this.findSmallBlockWithSlot(startBlock, slotUnits);

        if (found !== null) {
            return this.allocFromSmallBlock(found, slotUnits, slotSize, payloadBytes);
        }

        const blockIndex = this.allocFreeSpan(1);
        const head = this.slotClassState(slotUnits).headBlock;
        const bitmapWordCount = Math.ceil(cap / 32);
        const block: SmallBlock = {
            kind: "small",
            cap,
            slotUnits,
            nextBlock: head,
            bitmap: Array.from({ length: bitmapWordCount }, () => 0),
        };

        this.blocks[blockIndex] = block;
        this.setSlotClassState(slotUnits, blockIndex, blockIndex);
        return this.allocFromSmallBlock(blockIndex, slotUnits, slotSize, payloadBytes);
    }

    private allocFromSmallBlock(blockIndex: number, slotUnits: number, slotSize: number, payloadBytes: number): Allocation {
        const block = this.expectSmallBlock(blockIndex);
        const slotIndex = findFreeSlot(block);
        if (slotIndex === null) throw new Error("small block is full");

        setBit(block.bitmap, slotIndex);
        const state = this.slotClassState(slotUnits);
        this.setSlotClassState(slotUnits, state.headBlock, blockIndex);

        return {
            kind: "small",
            offset: blockPayloadOffset(blockIndex, block.cap, slotIndex, slotSize),
            bytes: payloadBytes,
            slotUnits,
            slotIndex,
        };
    }

    private freeSmall(allocation: Allocation) {
        const blockIndex = blockIndexOf(allocation);
        const rawBlock = this.blocks[blockIndex];
        if (rawBlock.kind !== "small") throw new Error("double free");
        const block = rawBlock;

        if (!getBit(block.bitmap, allocation.slotIndex)) {
            throw new Error("double free");
        }

        clearBit(block.bitmap, allocation.slotIndex);

        if (usedCount(block) === 0) {
            this.removeSmallBlockFromClass(block.slotUnits, blockIndex);
            this.writeFreeSpan(blockIndex, 1);
            this.mergeFreeSpanAround(blockIndex);
            return;
        }

        const state = this.slotClassState(block.slotUnits);
        this.setSlotClassState(block.slotUnits, state.headBlock, blockIndex);
    }

    private allocLarge(objectBytes: number, payloadBytes: number, slotUnits: number): Allocation {
        const totalBytes = LARGE_BLOCK_HEADER_BYTES + objectBytes;
        const spanLen = Math.ceil(totalBytes / BLOCK_SIZE);
        const blockIndex = this.allocFreeSpan(spanLen);

        this.blocks[blockIndex] = {
            kind: "large",
            spanLen,
        };

        for (let i = 1; i < spanLen; i += 1) {
            this.blocks[blockIndex + i] = { kind: "large_cont" };
        }

        return {
            kind: "large",
            offset: blockStart(blockIndex) + LARGE_BLOCK_HEADER_BYTES,
            bytes: payloadBytes,
            slotUnits,
            slotIndex: 0,
        };
    }

    private freeLarge(allocation: Allocation) {
        const blockIndex = blockIndexOf(allocation);
        const block = this.blocks[blockIndex];
        if (block.kind !== "large") throw new Error("double free");

        this.writeFreeSpan(blockIndex, block.spanLen);
        this.mergeFreeSpanAround(blockIndex);
    }

    private findSmallBlockWithSlot(startBlock: number, slotUnits: number): number | null {
        const seen = new Set<number>();
        let blockIndex = startBlock;

        while (blockIndex !== NONE_BLOCK && !seen.has(blockIndex)) {
            seen.add(blockIndex);
            const block = this.expectSmallBlock(blockIndex);

            if (block.slotUnits === slotUnits && findFreeSlot(block) !== null) {
                return blockIndex;
            }

            blockIndex = block.nextBlock;
        }

        const state = this.slotClassState(slotUnits);
        blockIndex = state.headBlock;

        while (blockIndex !== NONE_BLOCK && !seen.has(blockIndex)) {
            seen.add(blockIndex);
            const block = this.expectSmallBlock(blockIndex);

            if (block.slotUnits === slotUnits && findFreeSlot(block) !== null) {
                return blockIndex;
            }

            blockIndex = block.nextBlock;
        }

        return null;
    }

    private allocFreeSpan(requiredLen: number): number {
        for (let blockIndex = 0; blockIndex < this.blocks.length; blockIndex += 1) {
            const block = this.blocks[blockIndex];
            if (block.kind !== "free" || block.spanLen < requiredLen) continue;

            const remaining = block.spanLen - requiredLen;
            if (remaining > 0) {
                this.writeFreeSpan(blockIndex + requiredLen, remaining);
            }

            for (let i = 0; i < requiredLen; i += 1) {
                this.blocks[blockIndex + i] = { kind: "large_cont" };
            }

            return blockIndex;
        }

        throw new Error("out of memory");
    }

    private writeFreeSpan(blockIndex: number, spanLen: number) {
        this.blocks[blockIndex] = {
            kind: "free",
            spanLen,
            nextFree: NONE_BLOCK,
        };

        for (let i = 1; i < spanLen; i += 1) {
            this.blocks[blockIndex + i] = { kind: "free_cont" };
        }
    }

    private mergeFreeSpanAround(blockIndex: number) {
        const start = this.findFreeSpanStart(blockIndex);
        const current = this.expectFreeBlock(start);
        let mergedStart = start;
        let mergedLen = current.spanLen;

        const prev = this.findPreviousFreeSpan(start);
        if (prev !== null) {
            const prevBlock = this.expectFreeBlock(prev);
            mergedStart = prev;
            mergedLen += prevBlock.spanLen;
        }

        const next = mergedStart + mergedLen;
        if (next < this.blocks.length && this.blocks[next].kind === "free") {
            mergedLen += this.expectFreeBlock(next).spanLen;
        }

        this.writeFreeSpan(mergedStart, mergedLen);
    }

    private findFreeSpanStart(blockIndex: number): number {
        for (let i = blockIndex; i >= 0; i -= 1) {
            if (this.blocks[i].kind === "free") return i;
            if (this.blocks[i].kind !== "free_cont") break;
        }

        throw new Error("free span head not found");
    }

    private findPreviousFreeSpan(blockIndex: number): number | null {
        if (blockIndex === 0) return null;

        for (let i = blockIndex - 1; i >= 0; i -= 1) {
            const block = this.blocks[i];
            if (block.kind === "free") {
                return i + block.spanLen === blockIndex ? i : null;
            }

            if (block.kind !== "free_cont") return null;
        }

        return null;
    }

    private removeSmallBlockFromClass(slotUnits: number, targetBlock: number) {
        const state = this.slotClassState(slotUnits);
        let previous = NONE_BLOCK;
        let current = state.headBlock;

        while (current !== NONE_BLOCK) {
            const block = this.expectSmallBlock(current);
            if (current === targetBlock) {
                const next = block.nextBlock;

                if (previous === NONE_BLOCK) {
                    const cursor = state.cursorBlock === targetBlock ? next : state.cursorBlock;
                    this.setSlotClassState(slotUnits, next, cursor);
                } else {
                    this.expectSmallBlock(previous).nextBlock = next;
                    const cursor = state.cursorBlock === targetBlock ? state.headBlock : state.cursorBlock;
                    this.setSlotClassState(slotUnits, state.headBlock, cursor);
                }

                return;
            }

            previous = current;
            current = block.nextBlock;
        }
    }

    private setSlotClassState(slotUnits: number, headBlock: number, cursorBlock: number) {
        this.slotClasses.set(slotUnits, packSlotClassState(headBlock, cursorBlock));
    }

    private expectSmallBlock(blockIndex: number): SmallBlock {
        const block = this.blocks[blockIndex];
        if (block.kind !== "small") throw new Error(`expected small block at ${blockIndex}`);
        return block;
    }

    private expectFreeBlock(blockIndex: number): FreeBlock {
        const block = this.blocks[blockIndex];
        if (block.kind !== "free") throw new Error(`expected free block at ${blockIndex}`);
        return block;
    }
}
