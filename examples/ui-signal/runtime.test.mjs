// @ts-check

import assert from "node:assert/strict";
import test from "node:test";

import { createRuntime } from "./runtime.mjs";
import { createCounterModule } from "./counter-do.mjs";

/** @typedef {import("./runtime.mjs").Runtime} Runtime */
/** @typedef {import("./runtime.mjs").Scope} Scope */
/** @typedef {import("./runtime.mjs").UiNode} UiNode */
/** @typedef {(event: {type: string, target: FakeNode}) => void} FakeListener */
/** @typedef {Record<string, (scope: Scope, ...args: unknown[]) => unknown>} DoModule */

/**
 * @typedef {UiNode & {
 *     _demo: {
 *         button: UiNode,
 *         summary: UiNode,
 *         value: UiNode,
 *         renderCount: () => number
 *     }
 * }} CounterRoot
 */

class FakeNode {
    /** @param {string} tag */
    constructor(tag) {
        this.tagName = tag;
        /** @type {FakeNode[]} */
        this.children = [];
        /** @type {FakeNode | null} */
        this.parentNode = null;
        /** @type {string | null} */
        this.textContent = "";
        /** @type {string} */
        this.className = "";
        /** @type {Record<string, string>} */
        this.style = {};
        /** @type {Map<string, Set<FakeListener>>} */
        this.listeners = new Map();
        /** @type {unknown} */
        this._demo = null;
        this.focused = false;
    }

    /** @param {...FakeNode} children */
    append(...children) {
        for (const child of children) {
            if (child.parentNode) {
                const oldSiblings = child.parentNode.children;
                const oldIndex = oldSiblings.indexOf(child);
                if (oldIndex >= 0) oldSiblings.splice(oldIndex, 1);
            }
            child.parentNode = this;
            this.children.push(child);
        }
    }

    /** @param {...FakeNode} children */
    replaceChildren(...children) {
        for (const child of this.children) child.parentNode = null;
        this.children.length = 0;
        this.append(...children);
    }

    remove() {
        if (!this.parentNode) return;
        const siblings = this.parentNode.children;
        const index = siblings.indexOf(this);
        if (index >= 0) siblings.splice(index, 1);
        this.parentNode = null;
    }

    focus() {
        this.focused = true;
    }

    /**
     * @param {string} type
     * @param {FakeListener} listener
     */
    addEventListener(type, listener) {
        let listeners = this.listeners.get(type);
        if (!listeners) {
            listeners = new Set();
            this.listeners.set(type, listeners);
        }
        listeners.add(listener);
    }

    /**
     * @param {string} type
     * @param {FakeListener} listener
     */
    removeEventListener(type, listener) {
        this.listeners.get(type)?.delete(listener);
    }

    /** @param {string} type */
    dispatchEvent(type) {
        for (const listener of this.listeners.get(type) ?? []) {
            listener({ type, target: this });
        }
    }

    /** @param {string} type */
    listenerCount(type) {
        return this.listeners.get(type)?.size ?? 0;
    }
}

class FakeDocument {
    /** @param {string} tag */
    createElement(tag) {
        return new FakeNode(tag);
    }
}

/** @returns {{runtime: Runtime, module: Record<string, unknown>, app: Scope, host: UiNode}} */
function setup() {
    const runtime = createRuntime({ document: new FakeDocument() });
    const module = createCounterModule(runtime);
    runtime.setModule(module);
    const app = runtime.createScope("app", "app");
    const host = runtime.createElement("main");
    return { runtime, module, app, host };
}

/** @param {Scope} scope @returns {CounterRoot} */
function counterRoot(scope) {
    return /** @type {CounterRoot} */ (/** @type {unknown} */ (scope.root));
}

test("signal updates independent text, class, style, and derived bindings", () => {
    const { runtime, app, host } = setup();
    const counter = runtime.mount("counter_render", "first", app);
    const root = counterRoot(counter);
    host.append(root);

    assert.equal(root._demo.value.textContent, "0");
    assert.equal(root.className, "counter empty");
    assert.equal(root.style.color, "gray");
    assert.equal(root._demo.summary.textContent, "counter: 0");
    assert.equal(root._demo.renderCount(), 1);

    root._demo.button.dispatchEvent("click");

    assert.equal(root._demo.value.textContent, "1");
    assert.equal(root.className, "counter active");
    assert.equal(root.style.color, "green");
    assert.equal(root._demo.summary.textContent, "counter: 1");
    assert.equal(root._demo.renderCount(), 1);
    assert.equal(root._demo.button.focused, true);
    assert.equal(runtime.getRef(counter, "increment_button"), root._demo.button);
});

test("disposing a child scope removes its listeners, effects, derived values, and DOM", () => {
    const { runtime, app, host } = setup();
    const counter = runtime.mount("counter_render", "child", app);
    const root = counterRoot(counter);
    host.append(root);
    const count = counter.signal("count", 0);

    root._demo.button.dispatchEvent("click");
    assert.equal(root._demo.value.textContent, "1");
    assert.equal(root._demo.button.listenerCount("click"), 1);

    runtime.batch(() => {
        count.set(2);
        runtime.disposeScope(counter);
    });

    assert.equal(counter.disposed, true);
    assert.equal(root.parentNode, null);
    assert.equal(root._demo.button.listenerCount("click"), 0);
    assert.equal(count.subscribers.size, 0);

    count.set(3);
    root._demo.button.dispatchEvent("click");
    assert.equal(root._demo.value.textContent, "1");
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

test("refs are scoped, replaceable, and removed with their owner", () => {
    const { runtime, app } = setup();
    const first = runtime.createElement("button");
    const second = runtime.createElement("button");

    assert.equal(runtime.ref(app, first, "button"), first);
    assert.equal(runtime.getRef(app, "button"), first);
    assert.equal(app.refs.size, 1);

    runtime.ref(app, second, "button");
    assert.equal(runtime.getRef(app, "button"), second);
    assert.equal(app.refs.size, 1);

    runtime.disposeScope(app);

    assert.equal(runtime.getRef(app, "button"), undefined);
    assert.equal(app.refs.size, 0);
});

test("each reuses keyed item scopes and disposes removed items", () => {
    const { runtime, app } = setup();
    const list = runtime.createElement("ul");
    const items = app.signal("items", ["a", "b"]);
    /** @type {DoModule} */
    const module = {
        items() {
            return items.get();
        },
        item_key(_scope, item) {
            return item;
        },
        item_text(scope) {
            return `${runtime.getEachItem(scope)}:${runtime.getEachIndex(scope)}`;
        },
        item_click(scope) {
            const clicks = typeof scope.meta.clicks === "number" ? scope.meta.clicks : 0;
            scope.meta.clicks = clicks + 1;
        },
        item_render(scope) {
            const renderCount = typeof scope.meta.renderCount === "number"
                ? scope.meta.renderCount
                : 0;
            scope.meta.renderCount = renderCount + 1;
            const node = runtime.createElement("li");
            node._itemScope = scope;
            runtime.ref(scope, node, "item");
            runtime.bindText(scope, node, "item_text");
            runtime.onClick(scope, node, "item_click");
            return node;
        },
    };
    runtime.setModule(module);

    runtime.each(app, list, "items", "item_key", "item_render");

    const first = list.children[0];
    const second = list.children[1];
    const firstScope = first._itemScope;
    const secondScope = second._itemScope;
    assert.equal(list.children.length, 2);
    assert.equal(first.textContent, "a:0");
    assert.equal(second.textContent, "b:1");
    assert.equal(firstScope.meta.renderCount, 1);
    assert.equal(secondScope.meta.renderCount, 1);

    items.set(["b", "a"]);

    assert.equal(list.children[0], second);
    assert.equal(list.children[1], first);
    assert.equal(first.textContent, "a:1");
    assert.equal(second.textContent, "b:0");
    assert.equal(firstScope.meta.renderCount, 1);
    assert.equal(secondScope.meta.renderCount, 1);

    items.set(["b"]);

    assert.equal(firstScope.disposed, true);
    assert.equal(first.parentNode, null);
    assert.equal(first.listenerCount("click"), 0);
    assert.equal(runtime.getRef(firstScope, "item"), undefined);
    assert.equal(runtime.getEachItem(firstScope), undefined);
    assert.equal(runtime.getEachIndex(firstScope), undefined);
    assert.equal(secondScope.disposed, false);
    assert.equal(list.children[0], second);
});

test("ifBlock reuses a branch and disposes it on switch", () => {
    const { runtime, app } = setup();
    const container = runtime.createElement("div");
    const show = app.signal("show", true);
    const tick = app.signal("tick", 0);
    let thenRenders = 0;
    let elseRenders = 0;
    let cleanups = 0;
    /** @type {DoModule} */
    const module = {
        show() {
            tick.get();
            return show.get();
        },
        then_render(scope) {
            thenRenders += 1;
            const node = runtime.createElement("p");
            node._branchScope = scope;
            runtime.ref(scope, node, "branch");
            runtime.onClick(scope, node, "noop");
            runtime.onCleanup(scope, () => {
                cleanups += 1;
            });
            return node;
        },
        else_render(scope) {
            elseRenders += 1;
            const node = runtime.createElement("p");
            node._branchScope = scope;
            runtime.ref(scope, node, "branch");
            return node;
        },
        noop() {},
    };
    runtime.setModule(module);

    runtime.ifBlock(app, container, "show", "then_render", "else_render");

    const thenRoot = container.children[0];
    const thenScope = thenRoot._branchScope;
    assert.equal(thenRenders, 1);
    assert.equal(elseRenders, 0);
    assert.equal(runtime.getRef(thenScope, "branch"), thenRoot);

    tick.set(1);

    assert.equal(thenRenders, 1);
    assert.equal(container.children[0], thenRoot);

    show.set(false);

    const elseRoot = container.children[0];
    const elseScope = elseRoot._branchScope;
    assert.equal(thenScope.disposed, true);
    assert.equal(thenRoot.parentNode, null);
    assert.equal(thenRoot.listenerCount("click"), 0);
    assert.equal(runtime.getRef(thenScope, "branch"), undefined);
    assert.equal(cleanups, 1);
    assert.equal(elseRenders, 1);
    assert.equal(runtime.getRef(elseScope, "branch"), elseRoot);

    runtime.disposeScope(app);

    assert.equal(elseScope.disposed, true);
    assert.equal(runtime.getRef(elseScope, "branch"), undefined);
});

test("counter module drives keyed list and conditional branch exports", () => {
    const { runtime, app } = setup();
    const list = runtime.createElement("ul");
    const details = runtime.createElement("div");

    runtime.each(app, list, "list_items", "list_item_key", "list_item_render");
    runtime.ifBlock(app, details, "show_details", "details_on", "details_off");

    assert.equal(list.children.length, 2);
    assert.equal(details.children[0].textContent, "details visible");

    const firstRoot = list.children[0];
    const firstScope = firstRoot._itemScope;
    runtime.callDo("list_reverse", app);
    assert.equal(list.children[1], firstRoot);
    assert.equal(firstScope.meta.renderCount, 1);

    runtime.callDo("list_add", app);
    assert.equal(list.children.length, 3);

    runtime.callDo("list_remove", firstScope);
    assert.equal(firstScope.disposed, true);
    assert.equal(firstRoot.parentNode, null);

    runtime.callDo("toggle_details", app);
    assert.equal(details.children[0].textContent, "details hidden");
});
