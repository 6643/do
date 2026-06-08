import { blockIndexOf } from "./arc_allocator";
import { ArcObjectRuntime, type LayoutEntry } from "./arc_object_runtime";

const LEAF_TYPE = 1;
const BOX_TYPE = 2;

const layouts: LayoutEntry[] = [
    { typeId: LEAF_TYPE, name: "Leaf", managedFieldNames: [] },
    { typeId: BOX_TYPE, name: "Box", managedFieldNames: ["value"] },
];

function assertEqual<T>(actual: T, expected: T) {
    if (actual !== expected) {
        throw new Error(`expected ${String(expected)}, got ${String(actual)}`);
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

function testIncThenDecKeepsObjectAlive() {
    const runtime = new ArcObjectRuntime(layouts);
    const handle = runtime.allocObject(LEAF_TYPE, 16);

    assertEqual(runtime.rcOf(handle), 1);

    runtime.inc(handle);
    runtime.dec(handle);

    assertEqual(runtime.rcOf(handle), 1);
    assertEqual(runtime.isAlive(handle), true);
}

function testDecToZeroFreesAllocation() {
    const runtime = new ArcObjectRuntime(layouts);
    const handle = runtime.allocObject(LEAF_TYPE, 16);
    const offset = runtime.allocationOf(handle).offset;

    runtime.dec(handle);

    assertEqual(runtime.isAlive(handle), false);

    const reused = runtime.allocObject(LEAF_TYPE, 16);
    assertEqual(runtime.allocationOf(reused).offset, offset);
}

function testParentDropDecsManagedChild() {
    const runtime = new ArcObjectRuntime(layouts);
    const child = runtime.allocObject(LEAF_TYPE, 16);

    runtime.inc(child);
    const parent = runtime.allocObject(BOX_TYPE, 4, [child]);

    assertEqual(runtime.rcOf(child), 2);

    runtime.dec(parent);

    assertEqual(runtime.rcOf(child), 1);
    runtime.dec(child);
    assertEqual(runtime.isAlive(child), false);
}

function testNestedReleaseUsesWorklist() {
    const runtime = new ArcObjectRuntime(layouts);
    let current = runtime.allocObject(LEAF_TYPE, 0);

    for (let i = 0; i < 1200; i += 1) {
        current = runtime.allocObject(BOX_TYPE, 4, [current]);
    }

    runtime.dec(current);

    assertEqual(runtime.liveCount(), 0);
}

function testRejectsDoubleDecAfterRelease() {
    const runtime = new ArcObjectRuntime(layouts);
    const handle = runtime.allocObject(LEAF_TYPE, 16);

    runtime.dec(handle);

    assertThrows(() => runtime.dec(handle), /released|unknown/);
}

function testAllocatorSlotReusedAfterObjectRelease() {
    const runtime = new ArcObjectRuntime(layouts);
    const first = runtime.allocObject(LEAF_TYPE, 16);
    const firstAllocation = runtime.allocationOf(first);

    runtime.dec(first);

    const second = runtime.allocObject(LEAF_TYPE, 16);
    const secondAllocation = runtime.allocationOf(second);

    assertEqual(blockIndexOf(secondAllocation), blockIndexOf(firstAllocation));
    assertEqual(secondAllocation.slotIndex, firstAllocation.slotIndex);
}

testIncThenDecKeepsObjectAlive();
testDecToZeroFreesAllocation();
testParentDropDecsManagedChild();
testNestedReleaseUsesWorklist();
testRejectsDoubleDecAfterRelease();
testAllocatorSlotReusedAfterObjectRelease();

console.log("arc object runtime tests passed");
