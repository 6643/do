import { ArcCowRuntime, LIST_U32_TYPE } from "./arc_cow_runtime";

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

function testSharedListSetClonesBackingObject() {
    const runtime = new ArcCowRuntime();
    const original = runtime.allocList(LIST_U32_TYPE, [1, 2, 3]);
    const shared = runtime.share(original);
    const originalOffset = runtime.allocationOf(original).offset;

    const updated = runtime.setListItem(shared, 1, 9);

    assertDeepEqual(runtime.listItems(original), [1, 2, 3]);
    assertDeepEqual(runtime.listItems(updated), [1, 9, 3]);
    assertEqual(runtime.allocationOf(original).offset, originalOffset);
    assertEqual(runtime.allocationOf(updated).offset === originalOffset, false);
    assertEqual(runtime.rcOf(original), 1);
    assertEqual(runtime.rcOf(updated), 1);
}

function testUniqueListSetReusesBackingObject() {
    const runtime = new ArcCowRuntime();
    const original = runtime.allocList(LIST_U32_TYPE, [1, 2, 3]);
    const originalOffset = runtime.allocationOf(original).offset;

    const updated = runtime.setListItem(original, 1, 9);

    assertEqual(updated, original);
    assertEqual(runtime.allocationOf(updated).offset, originalOffset);
    assertDeepEqual(runtime.listItems(updated), [1, 9, 3]);
    assertEqual(runtime.rcOf(updated), 1);
}

function testSharedListPutClonesWhenCapacityEnough() {
    const runtime = new ArcCowRuntime();
    const original = runtime.allocList(LIST_U32_TYPE, [1, 2], 4);
    const shared = runtime.share(original);

    const updated = runtime.putListItem(shared, 3);

    assertDeepEqual(runtime.listItems(original), [1, 2]);
    assertDeepEqual(runtime.listItems(updated), [1, 2, 3]);
    assertEqual(runtime.rcOf(original), 1);
    assertEqual(runtime.rcOf(updated), 1);
}

function testUniqueListPutGrowsWhenCapacityFull() {
    const runtime = new ArcCowRuntime();
    const original = runtime.allocList(LIST_U32_TYPE, [1, 2], 2);
    const originalOffset = runtime.allocationOf(original).offset;

    const updated = runtime.putListItem(original, 3);

    assertEqual(updated === original, false);
    assertEqual(runtime.isAlive(original), false);
    assertEqual(runtime.allocationOf(updated).offset === originalOffset, false);
    assertDeepEqual(runtime.listItems(updated), [1, 2, 3]);
}

testSharedListSetClonesBackingObject();
testUniqueListSetReusesBackingObject();
testSharedListPutClonesWhenCapacityEnough();
testUniqueListPutGrowsWhenCapacityFull();

console.log("arc cow runtime tests passed");
