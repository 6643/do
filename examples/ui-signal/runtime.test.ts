import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { createCounterModule } from "./counter-do.js";
import { createDeepModule } from "./deep-do.js";
import { createRuntime } from "./runtime.js";
import type { Context, DoModule, Runtime, Scope, UiNode } from "./runtime.js";

/** @typedef {(event: {type: string, target: FakeNode}) => void} FakeListener */

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

/**
 * @typedef {UiNode & {
 *     _itemScope: Scope,
 *     _deep: {
 *         name: UiNode,
 *         city: UiNode,
 *         lines: UiNode,
 *         renderRuns: number
 *     }
 * }} DeepOrderRoot
 */

/**
 * @typedef {UiNode & {
 *     _itemScope: Scope,
 *     _deep: {
 *         product: UiNode,
 *         quantity: UiNode,
 *         price: UiNode,
 *         renderRuns: number
 *     }
 * }} DeepLineRoot
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

test("runtime uses framework-neutral graph vocabulary", () => {
    const source = readFileSync(new URL("./runtime.ts", import.meta.url), "utf8");

    for (const legacyName of [
        ["Re", "active", "Node"].join(""),
        ["Re", "active", "Source"].join(""),
        ["Re", "active", "Subscriber"].join(""),
        ["Re", "active", "Resource"].join(""),
    ]) {
        assert.equal(source.includes(legacyName), false, `legacy name remains: ${legacyName}`);
    }

    for (const currentName of [
        "GraphNode",
        "StateSource",
        "StateObserver",
        "OwnedResource",
    ]) {
        assert.equal(source.includes(currentName), true, `new name missing: ${currentName}`);
    }
});

test("deep module uses record names without a data suffix", () => {
    const source = readFileSync(new URL("./deep-do.ts", import.meta.url), "utf8");

    for (const legacyName of [
        ["Order", "Data"].join(""),
        ["Line", "Data"].join(""),
        ["ORDER", "_DATA"].join(""),
        ["LINE", "_DATA"].join(""),
        ["order", "Data"].join(""),
        ["line", "Data"].join(""),
        ["deepOrder", "Data"].join(""),
        ["deepLine", "Data"].join(""),
    ]) {
        assert.equal(source.includes(legacyName), false, `legacy name remains: ${legacyName}`);
    }

    for (const currentName of [
        "Order",
        "Line",
        "ORDERS",
        "LINES",
        "getOrder",
        "getLine",
        "deepOrder",
        "deepLine",
    ]) {
        assert.equal(source.includes(currentName), true, `new name missing: ${currentName}`);
    }
});

test("do dispatch receives a Context handle and runtime uses data records", () => {
    const source = readFileSync(new URL("./runtime.ts", import.meta.url), "utf8");

    for (const className of [
        "class GraphNode",
        "class State",
        "class Computed",
        "class Effect",
        "class ScopeRecord",
    ]) {
        assert.equal(source.includes(className), false, `class remains: ${className}`);
    }

    for (const functionName of [
        "function create_state",
        "function state_get",
        "function state_set",
        "function create_computed",
        "function create_effect",
        "function create_scope",
        "function scope_dispose",
    ]) {
        assert.equal(source.includes(functionName), true, `data function missing: ${functionName}`);
    }

    const { runtime, app } = setup();
    let received = /** @type {Context | null} */ (null);
    runtime.setModule({
        probe(context) {
            received = context;
            return context;
        },
    });

    const result = runtime.callDo("probe", app);
    assert.equal(result, runtime.getContext(app));
    assert.equal(received, runtime.getContext(app));
    assert.notEqual(received, app);
    assert.equal(received?.id, app.id);
});

test("createRuntime only assembles an explicit runtime store and API", () => {
    const source = readFileSync(new URL("./runtime.ts", import.meta.url), "utf8");
    const createStart = source.indexOf("export function createRuntime");
    assert.equal(createStart >= 0, true);

    const createBody = source.slice(createStart);
    for (const nestedFunction of [
        "function schedule",
        "function create_state",
        "function create_scope",
        "function scope_dispose",
        "function each",
        "function show",
        "function callDo",
    ]) {
        assert.equal(
            createBody.includes(nestedFunction),
            false,
            `runtime implementation remains nested: ${nestedFunction}`
        );
    }

    assert.equal(source.includes("function create_runtime_store"), true);
    assert.equal(source.includes("function create_runtime_api"), true);
});

test("Context owns metadata and resolves parent lifecycle", () => {
    const { runtime, app } = setup();
    const parent = runtime.getContext(app);
    const child = runtime.createScope("child", "child", app);
    const childContext = runtime.getContext(child);

    runtime.setMeta(childContext, "renderRuns", 1);

    assert.equal(runtime.getMeta(childContext, "renderRuns", 0), 1);
    assert.equal(runtime.getParentContext(childContext), parent);

    runtime.disposeScope(child);

    assert.equal(runtime.getMeta(childContext, "renderRuns", 0), undefined);
    assert.equal(runtime.getParentContext(childContext), undefined);
});

test("runtime exposes state access without a Scope method", () => {
    const { runtime, app } = setup();
    assert.equal(runtime.getState(app, "count", 0), 0);

    runtime.setState(app, "count", 1);

    assert.equal(runtime.getState(app, "count", 0), 1);
    const legacyScope = /** @type {Scope & {state?: unknown}} */ (
        /** @type {unknown} */ (app)
    );
    assert.equal(typeof legacyScope.state, "undefined");
});

test("state updates independent text, class, style, and derived bindings", () => {
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
    runtime.getState(counter, "count", 0);
    const count = counter.states.get("count");

    root._demo.button.dispatchEvent("click");
    assert.equal(root._demo.value.textContent, "1");
    assert.equal(root._demo.button.listenerCount("click"), 1);

    runtime.batch(() => {
        runtime.setState(counter, "count", 2);
        runtime.disposeScope(counter);
    });

    assert.equal(counter.disposed, true);
    assert.equal(root.parentNode, null);
    assert.equal(root._demo.button.listenerCount("click"), 0);
    assert.equal(count.subscribers.size, 0);

    runtime.setState(counter, "count", 3);
    root._demo.button.dispatchEvent("click");
    assert.equal(root._demo.value.textContent, "1");
});

test("disposing a child removes only its subscription to a parent-owned state", () => {
    const { runtime, app } = setup();
    runtime.getState(app, "shared", 0);
    const shared = app.states.get("shared");
    const child = runtime.createScope("child", "child", app);
    let updates = 0;

    runtime.effect(child, () => {
        runtime.getState(app, "shared", 0);
        updates += 1;
    });

    assert.equal(updates, 1);
    assert.equal(shared.subscribers.size, 1);

    runtime.disposeScope(child);

    assert.equal(shared.disposed, false);
    assert.equal(shared.subscribers.size, 0);
    runtime.setState(app, "shared", 1);
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
    runtime.getState(app, "items", ["a", "b"]);
    /** @type {DoModule} */
    const module = {
        items(context) {
            return runtime.getState(context, "items", ["a", "b"]);
        },
        item_key(_context, item) {
            return item;
        },
        item_text(context) {
            return `${runtime.getEachItem(context)}:${runtime.getEachIndex(context)}`;
        },
        item_click(context) {
            const clicks = runtime.getMeta(context, "clicks", 0) ?? 0;
            runtime.setMeta(context, "clicks", clicks + 1);
        },
        item_render(context) {
            const renderCount = runtime.getMeta(context, "renderCount", 0) ?? 0;
            runtime.setMeta(context, "renderCount", renderCount + 1);
            const node = runtime.createElement("li");
            const scope = runtime.getScope(context.id);
            if (scope) node._itemScope = scope;
            runtime.ref(context, node, "item");
            runtime.bindText(context, node, "item_text");
            runtime.onClick(context, node, "item_click");
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

    runtime.setState(app, "items", ["b", "a"]);

    assert.equal(list.children[0], second);
    assert.equal(list.children[1], first);
    assert.equal(first.textContent, "a:1");
    assert.equal(second.textContent, "b:0");
    assert.equal(firstScope.meta.renderCount, 1);
    assert.equal(secondScope.meta.renderCount, 1);

    runtime.setState(app, "items", ["b"]);

    assert.equal(firstScope.disposed, true);
    assert.equal(first.parentNode, null);
    assert.equal(first.listenerCount("click"), 0);
    assert.equal(runtime.getRef(firstScope, "item"), undefined);
    assert.equal(runtime.getEachItem(firstScope), undefined);
    assert.equal(runtime.getEachIndex(firstScope), undefined);
    assert.equal(secondScope.disposed, false);
    assert.equal(list.children[0], second);
});

test("show reuses a branch and disposes it on switch", () => {
    const { runtime, app } = setup();
    const container = runtime.createElement("div");
    runtime.getState(app, "show", true);
    runtime.getState(app, "tick", 0);
    const show = app.states.get("show");
    const tick = app.states.get("tick");
    let thenRenders = 0;
    let elseRenders = 0;
    let cleanups = 0;
    /** @type {DoModule} */
    const module = {
        show(context) {
            runtime.getState(context, "tick", 0);
            return runtime.getState(context, "show", true);
        },
        then_render(context) {
            thenRenders += 1;
            const node = runtime.createElement("p");
            const scope = runtime.getScope(context.id);
            if (scope) node._branchScope = scope;
            runtime.ref(context, node, "branch");
            runtime.onClick(context, node, "noop");
            runtime.onCleanup(context, () => {
                cleanups += 1;
            });
            return node;
        },
        else_render(context) {
            elseRenders += 1;
            const node = runtime.createElement("p");
            const scope = runtime.getScope(context.id);
            if (scope) node._branchScope = scope;
            runtime.ref(context, node, "branch");
            return node;
        },
        noop() {},
    };
    runtime.setModule(module);

    runtime.show(app, container, "show", "then_render", "else_render");

    const thenRoot = container.children[0];
    const thenScope = thenRoot._branchScope;
    assert.equal(thenRenders, 1);
    assert.equal(elseRenders, 0);
    assert.equal(runtime.getRef(thenScope, "branch"), thenRoot);

    runtime.setState(app, "tick", 1);

    assert.equal(thenRenders, 1);
    assert.equal(container.children[0], thenRoot);

    runtime.setState(app, "show", false);

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

test("nested paths update only their leaf bindings and keyed child scopes", () => {
    const runtime = createRuntime({ document: new FakeDocument() });
    runtime.setModule(createDeepModule(runtime));
    const app = runtime.createScope("app", "app");
    const orders = runtime.createElement("section");

    runtime.each(app, orders, "deep_orders", "deep_order_key", "deep_order_render");

    const firstOrder = /** @type {DeepOrderRoot} */ (orders.children[0]);
    const secondOrder = /** @type {DeepOrderRoot} */ (orders.children[1]);
    const firstOrderScope = firstOrder._itemScope;
    const secondOrderScope = secondOrder._itemScope;
    const firstOrderDemo = firstOrder._deep;
    const secondOrderDemo = secondOrder._deep;
    const firstLine = /** @type {DeepLineRoot} */ (firstOrderDemo.lines.children[0]);
    const firstLineScope = firstLine._itemScope;
    const firstLineDemo = firstLine._deep;

    assert.equal(firstOrderDemo.name.textContent, "Ada Lovelace | effect runs 1");
    assert.equal(firstOrderDemo.city.textContent, "London | effect runs 1");
    assert.equal(secondOrderDemo.name.textContent, "Grace Hopper | effect runs 1");
    assert.equal(firstLineDemo.product.textContent, "Compiler | effect runs 1");
    assert.equal(firstLineDemo.quantity.textContent, "2 | effect runs 1");

    runtime.callDo("deep_change_name", firstOrderScope);

    assert.equal(firstOrderDemo.name.textContent, "Ada Byron Lovelace | effect runs 2");
    assert.equal(firstOrderDemo.city.textContent, "London | effect runs 1");
    assert.equal(secondOrderDemo.name.textContent, "Grace Hopper | effect runs 1");
    assert.equal(firstLineDemo.quantity.textContent, "2 | effect runs 1");

    runtime.callDo("deep_increment_quantity", firstLineScope);

    assert.equal(firstLineDemo.product.textContent, "Compiler | effect runs 1");
    assert.equal(firstLineDemo.quantity.textContent, "3 | effect runs 2");
    assert.equal(firstOrderDemo.name.textContent, "Ada Byron Lovelace | effect runs 2");

    const reusedLine = firstLine;
    runtime.callDo("deep_add_line", firstOrderScope);

    assert.equal(firstOrderDemo.lines.children.length, 3);
    assert.equal(firstOrderDemo.lines.children[0], reusedLine);
    assert.equal(reusedLine._deep.renderRuns, 1);
    assert.equal(secondOrderDemo.name.textContent, "Grace Hopper | effect runs 1");
});

test("counter module drives keyed list and conditional branch exports", () => {
    const { runtime, app } = setup();
    const list = runtime.createElement("ul");
    const details = runtime.createElement("div");

    runtime.each(app, list, "list_items", "list_item_key", "list_item_render");
    runtime.show(app, details, "show_details", "details_on", "details_off");

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
