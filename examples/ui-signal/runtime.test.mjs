import assert from "node:assert/strict";
import test from "node:test";

import { createRuntime } from "./runtime.mjs";
import { createCounterModule } from "./counter-do.mjs";

class FakeNode {
    constructor(tag) {
        this.tagName = tag;
        this.children = [];
        this.parentNode = null;
        this.textContent = "";
        this.className = "";
        this.style = {};
        this.listeners = new Map();
        this._demo = null;
    }

    append(...children) {
        for (const child of children) {
            child.parentNode = this;
            this.children.push(child);
        }
    }

    remove() {
        if (!this.parentNode) return;
        const siblings = this.parentNode.children;
        const index = siblings.indexOf(this);
        if (index >= 0) siblings.splice(index, 1);
        this.parentNode = null;
    }

    addEventListener(type, listener) {
        let listeners = this.listeners.get(type);
        if (!listeners) {
            listeners = new Set();
            this.listeners.set(type, listeners);
        }
        listeners.add(listener);
    }

    removeEventListener(type, listener) {
        this.listeners.get(type)?.delete(listener);
    }

    dispatchEvent(type) {
        for (const listener of this.listeners.get(type) ?? []) {
            listener({ type, target: this });
        }
    }

    listenerCount(type) {
        return this.listeners.get(type)?.size ?? 0;
    }
}

class FakeDocument {
    createElement(tag) {
        return new FakeNode(tag);
    }
}

function setup() {
    const runtime = createRuntime({ document: new FakeDocument() });
    const module = createCounterModule(runtime);
    runtime.setModule(module);
    const app = runtime.createScope("app", "app");
    const host = runtime.createElement("main");
    return { runtime, module, app, host };
}

test("signal updates independent text, class, style, and derived bindings", () => {
    const { runtime, app, host } = setup();
    const counter = runtime.mount("counter_render", "first", app);
    host.append(counter.root);

    assert.equal(counter.root._demo.value.textContent, "0");
    assert.equal(counter.root.className, "counter empty");
    assert.equal(counter.root.style.color, "gray");
    assert.equal(counter.root._demo.summary.textContent, "counter: 0");
    assert.equal(counter.root._demo.renderCount(), 1);

    counter.root._demo.button.dispatchEvent("click");

    assert.equal(counter.root._demo.value.textContent, "1");
    assert.equal(counter.root.className, "counter active");
    assert.equal(counter.root.style.color, "green");
    assert.equal(counter.root._demo.summary.textContent, "counter: 1");
    assert.equal(counter.root._demo.renderCount(), 1);
});

test("disposing a child scope removes its listeners, effects, derived values, and DOM", () => {
    const { runtime, app, host } = setup();
    const counter = runtime.mount("counter_render", "child", app);
    host.append(counter.root);
    const count = counter.signal("count", 0);

    counter.root._demo.button.dispatchEvent("click");
    assert.equal(counter.root._demo.value.textContent, "1");
    assert.equal(counter.root._demo.button.listenerCount("click"), 1);

    runtime.batch(() => {
        count.set(2);
        runtime.disposeScope(counter);
    });

    assert.equal(counter.disposed, true);
    assert.equal(counter.root.parentNode, null);
    assert.equal(counter.root._demo.button.listenerCount("click"), 0);
    assert.equal(count.subscribers.size, 0);

    count.set(3);
    counter.root._demo.button.dispatchEvent("click");
    assert.equal(counter.root._demo.value.textContent, "1");
});

test("disposing a child removes only its subscription to a parent-owned signal", () => {
    const { runtime, app } = setup();
    const shared = app.signal("shared", 0);
    const child = runtime.createScope("child", "child", app);
    let updates = 0;

    runtime.effect(child, () => {
        shared.get();
        updates += 1;
    });

    assert.equal(updates, 1);
    assert.equal(shared.subscribers.size, 1);

    runtime.disposeScope(child);

    assert.equal(shared.disposed, false);
    assert.equal(shared.subscribers.size, 0);
    shared.set(1);
    assert.equal(updates, 1);
});
