import {
    ArcAllocator,
    blockIndexOf,
    packSlotClassState,
    unpackSlotClassState,
} from "./arc_allocator";

function assertEqual<T>(actual: T, expected: T) {
    if (actual !== expected) {
        throw new Error(`expected ${String(expected)}, got ${String(actual)}`);
    }
}

function assertDeepEqual(actual: unknown, expected: unknown) {
    const actualText = JSON.stringify(actual);
    const expectedText = JSON.stringify(expected);
    if (actualText !== expectedText) {
        throw new Error(`expected ${expectedText}, got ${actualText}`);
    }
}

function assertThrows(fn: () => void, pattern: RegExp) {
    try {
        fn();
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        if (!pattern.test(message)) {
            throw new Error(`expected error ${pattern}, got ${message}`);
        }
        return;
    }

    throw new Error(`expected error ${pattern}`);
}

function testPackSlotClassState() {
    const packed = packSlotClassState(0x1234_5678, 0x9abc_def0);
    assertDeepEqual(unpackSlotClassState(packed), {
        headBlock: 0x1234_5678,
        cursorBlock: 0x9abc_def0,
    });
}

function testSmallAllocUsesBitmapAndCursor() {
    const allocator = new ArcAllocator();
    const first = allocator.alloc(16);
    const second = allocator.alloc(16);

    assertEqual(blockIndexOf(first), blockIndexOf(second));
    assertEqual(first.slotIndex, 0);
    assertEqual(second.slotIndex, 1);

    allocator.free(first);

    const state = allocator.slotClassState(first.slotUnits);
    assertEqual(state.cursorBlock, blockIndexOf(first));

    const reused = allocator.alloc(16);
    assertEqual(blockIndexOf(reused), blockIndexOf(first));
    assertEqual(reused.slotIndex, 0);
}

function testSmallBlockReturnsToFreeSpan() {
    const allocator = new ArcAllocator();
    const first = allocator.alloc(16);
    const second = allocator.alloc(16);

    allocator.free(first);
    allocator.free(second);

    assertEqual(allocator.freeSpanAt(0)?.spanLen, 64);
}

function testLargeAllocSplitsAndMergesSpan() {
    const allocator = new ArcAllocator();
    const large = allocator.alloc(2048);

    assertEqual(blockIndexOf(large), 0);
    assertEqual(large.kind, "large");
    assertEqual(allocator.freeSpanAt(3)?.spanLen, 61);

    allocator.free(large);

    assertEqual(allocator.freeSpanAt(0)?.spanLen, 64);
}

function testRejectsDoubleFree() {
    const allocator = new ArcAllocator();
    const handle = allocator.alloc(16);
    allocator.free(handle);

    assertThrows(() => allocator.free(handle), /double free/);
}

testPackSlotClassState();
testSmallAllocUsesBitmapAndCursor();
testSmallBlockReturnsToFreeSpan();
testLargeAllocSplitsAndMergesSpan();
testRejectsDoubleFree();

console.log("arc allocator tests passed");
