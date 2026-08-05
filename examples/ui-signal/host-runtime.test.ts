import assert from "node:assert/strict";
import test from "node:test";

import { createHostInstance } from "./host-runtime.js";

type Listener = (event: unknown) => void;

class FakeEventTarget {
    private readonly listeners = new Map<string, Set<Listener>>();

    addEventListener(type: string, listener: Listener): void {
        let listeners = this.listeners.get(type);
        if (!listeners) {
            listeners = new Set();
            this.listeners.set(type, listeners);
        }
        listeners.add(listener);
    }

    removeEventListener(type: string, listener: Listener): void {
        this.listeners.get(type)?.delete(listener);
    }

    emit(type: string, event: unknown = { type }): void {
        for (const listener of this.listeners.get(type) ?? []) listener(event);
    }

    firstListener(type: string): Listener {
        const listener = this.listeners.get(type)?.values().next().value;
        assert.notEqual(listener, undefined);
        return listener;
    }

    listenerCount(type: string): number {
        return this.listeners.get(type)?.size ?? 0;
    }
}

function createDispatcher() {
    const calls: Array<{ signatureId: number; callbackId: number; event: unknown }> = [];
    return {
        calls,
        dispatcher: {
            invoke(signatureId: number, callbackId: number, event: unknown): number {
                calls.push({ signatureId, callbackId, event });
                return 0;
            },
        },
    };
}

async function flushMicrotasks(): Promise<void> {
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
}

test("subscription dispatches while live and unsubscribe removes its listener", () => {
    const target = new FakeEventTarget();
    const { calls, dispatcher } = createDispatcher();
    const instance = createHostInstance(dispatcher);
    const subscription = instance.subscribe(target, "tick", 3, 7);

    target.emit("tick", { value: 1 });
    assert.deepEqual(calls, [{ signatureId: 3, callbackId: 7, event: { value: 1 } }]);

    instance.unsubscribe(subscription);
    instance.unsubscribe(subscription);

    assert.equal(target.listenerCount("tick"), 0);
    target.emit("tick", { value: 2 });
    assert.equal(calls.length, 1);
});

test("a listener retained by the host cannot dispatch after unsubscribe", () => {
    const target = new FakeEventTarget();
    const { calls, dispatcher } = createDispatcher();
    const instance = createHostInstance(dispatcher);
    const subscription = instance.subscribe(target, "tick", 4, 9);
    const lateListener = target.firstListener("tick");

    instance.unsubscribe(subscription);
    lateListener({ value: "late" });

    assert.equal(calls.length, 0);
});

test("dispose removes every listener, rejects late callbacks, and cannot be reopened", () => {
    const firstTarget = new FakeEventTarget();
    const secondTarget = new FakeEventTarget();
    const { calls, dispatcher } = createDispatcher();
    const instance = createHostInstance(dispatcher);
    instance.subscribe(firstTarget, "tick", 1, 2);
    instance.subscribe(secondTarget, "change", 1, 3);
    const lateListener = secondTarget.firstListener("change");

    instance.dispose();
    instance.dispose();

    assert.equal(firstTarget.listenerCount("tick"), 0);
    assert.equal(secondTarget.listenerCount("change"), 0);
    firstTarget.emit("tick");
    lateListener({ value: "late" });
    assert.equal(calls.length, 0);
    assert.throws(() => instance.subscribe(firstTarget, "tick", 1, 4), /disposed/);
});

test("event pump does no work while idle and drains one queued batch", async () => {
    const { dispatcher } = createDispatcher();
    const instance = createHostInstance(dispatcher);
    const received: unknown[] = [];
    let drainCount = 0;
    let pump = instance.createEventPump(12, {
        drain(instanceId) {
            assert.equal(instanceId, 12);
            drainCount += 1;
            for (;;) {
                const event = pump.nextEvent();
                if (event === undefined) return;
                received.push(event);
            }
        },
    });

    await flushMicrotasks();
    assert.equal(drainCount, 0);

    pump.enqueue({ type: "first" });
    pump.enqueue({ type: "second" });
    assert.equal(drainCount, 0);

    await flushMicrotasks();
    assert.equal(drainCount, 1);
    assert.deepEqual(received, [{ type: "first" }, { type: "second" }]);
});

test("event pump schedules a later drain instead of reentering while draining", async () => {
    const { dispatcher } = createDispatcher();
    const instance = createHostInstance(dispatcher);
    let activeDrains = 0;
    let maxActiveDrains = 0;
    const received: unknown[] = [];
    let pump = instance.createEventPump(13, {
        drain() {
            activeDrains += 1;
            maxActiveDrains = Math.max(maxActiveDrains, activeDrains);
            const event = pump.nextEvent();
            if (event !== undefined) received.push(event);
            if (received.length === 1) pump.enqueue({ type: "later" });
            activeDrains -= 1;
        },
    });

    pump.enqueue({ type: "first" });
    await flushMicrotasks();

    assert.equal(maxActiveDrains, 1);
    assert.deepEqual(received, [{ type: "first" }, { type: "later" }]);
});

test("disposing an instance drops queued events before their scheduled drain", async () => {
    const { dispatcher } = createDispatcher();
    const instance = createHostInstance(dispatcher);
    let drainCount = 0;
    const pump = instance.createEventPump(14, {
        drain() {
            drainCount += 1;
        },
    });

    pump.enqueue({ type: "pending" });
    instance.dispose();
    await flushMicrotasks();

    assert.equal(drainCount, 0);
    assert.equal(pump.nextEvent(), undefined);
});
