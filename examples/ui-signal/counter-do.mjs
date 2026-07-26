// @ts-check

/** @typedef {import("./runtime.mjs").Runtime} Runtime */
/** @typedef {import("./runtime.mjs").Scope} Scope */
/** @typedef {import("./runtime.mjs").UiNode} UiNode */
/** @typedef {Record<string, (scope: Scope, ...args: unknown[]) => unknown>} DoModule */
/** @typedef {UiNode & {_itemScope: Scope}} ListDemoNode */

/**
 * @typedef {Object} CounterDemo
 * @property {UiNode} button
 * @property {UiNode} summary
 * @property {UiNode} value
 * @property {() => number} renderCount
 */

/**
 * @param {Runtime} ui
 * @returns {DoModule}
 */
export function createCounterModule(ui) {
    /** @type {DoModule} */
    const module = {
        /** @param {Scope} scope @returns {void} */
        counter_increment(scope) {
            const count = scope.signal("count", 0);
            count.set(count.get() + 1);
            ui.getRef(scope, "increment_button")?.focus();
        },

        /** @param {Scope} scope @returns {string} */
        counter_text(scope) {
            return String(scope.signal("count", 0).get());
        },

        /** @param {Scope} scope @returns {string} */
        counter_class(scope) {
            return scope.signal("count", 0).get() === 0
                ? "counter empty"
                : "counter active";
        },

        /** @param {Scope} scope @returns {string} */
        counter_color(scope) {
            return scope.signal("count", 0).get() === 0 ? "gray" : "green";
        },

        /** @param {Scope} scope @returns {string} */
        counter_summary(scope) {
            const name = scope.signal("name", "counter").get();
            const count = scope.signal("count", 0).get();
            const enabled = scope.signal("enabled", true).get();
            return enabled ? `${name}: ${count}` : "disabled";
        },

        /** @param {Scope} scope @returns {UiNode} */
        counter_render(scope) {
            const renderCount = typeof scope.meta.renderCount === "number"
                ? scope.meta.renderCount
                : 0;
            scope.meta.renderCount = renderCount + 1;
            scope.signal("count", 0);
            scope.signal("name", "counter");
            scope.signal("enabled", true);

            const root = /** @type {UiNode & {_demo: CounterDemo}} */ (ui.createElement("article"));
            const value = ui.createElement("strong");
            const summary = ui.createElement("p");
            const button = ui.createElement("button");
            button.textContent = "+";

            ui.ref(scope, button, "increment_button");
            ui.bindText(scope, value, "counter_text");
            ui.bindText(scope, summary, "counter_summary");
            ui.bindAttr(scope, root, "className", "counter_class");
            ui.bindStyle(scope, root, "color", "counter_color");
            ui.onClick(scope, button, "counter_increment");
            ui.onCleanup(scope, () => root.remove());
            ui.append(root, value, summary, button);

            root._demo = {
                button,
                summary,
                value,
                renderCount: () => typeof scope.meta.renderCount === "number"
                    ? scope.meta.renderCount
                    : 0,
            };
            return root;
        },

        /** @param {Scope} scope @returns {string[]} */
        list_items(scope) {
            return scope.signal("items", ["alpha", "beta"]).get();
        },

        /**
         * @param {Scope} _scope
         * @param {unknown} item
         * @returns {string}
         */
        list_item_key(_scope, item) {
            return String(item);
        },

        /** @param {Scope} scope @returns {string} */
        list_item_text(scope) {
            return `${String(ui.getEachItem(scope))} (#${ui.getEachIndex(scope)})`;
        },

        /** @param {Scope} scope @returns {void} */
        list_add(scope) {
            const items = scope.signal("items", ["alpha", "beta"]).get();
            let nextIndex = typeof scope.meta.nextItem === "number"
                ? scope.meta.nextItem
                : 1;
            let item = `item-${nextIndex}`;
            while (items.includes(item)) {
                nextIndex += 1;
                item = `item-${nextIndex}`;
            }
            scope.meta.nextItem = nextIndex + 1;
            scope.signal("items", ["alpha", "beta"]).set([...items, item]);
        },

        /** @param {Scope} scope @returns {void} */
        list_reverse(scope) {
            const items = scope.signal("items", ["alpha", "beta"]).get();
            scope.signal("items", ["alpha", "beta"]).set([...items].reverse());
        },

        /** @param {Scope} scope @returns {void} */
        list_remove(scope) {
            const parent = scope.parent;
            if (!parent) return;
            const item = ui.getEachItem(scope);
            const items = parent.signal("items", ["alpha", "beta"]).get();
            parent.signal("items", ["alpha", "beta"]).set(
                items.filter((candidate) => !Object.is(candidate, item))
            );
        },

        /** @param {Scope} scope @returns {UiNode} */
        list_item_render(scope) {
            const renderCount = typeof scope.meta.renderCount === "number"
                ? scope.meta.renderCount
                : 0;
            scope.meta.renderCount = renderCount + 1;
            const root = /** @type {ListDemoNode} */ (ui.createElement("li"));
            const label = ui.createElement("span");
            const remove = ui.createElement("button");
            remove.textContent = "Remove";
            root._itemScope = scope;

            ui.ref(scope, remove, "remove_button");
            ui.bindText(scope, label, "list_item_text");
            ui.onClick(scope, remove, "list_remove");
            ui.append(root, label, remove);
            return root;
        },

        /** @param {Scope} scope @returns {boolean} */
        show_details(scope) {
            return scope.signal("showDetails", true).get();
        },

        /** @param {Scope} scope @returns {void} */
        toggle_details(scope) {
            const visible = scope.signal("showDetails", true);
            visible.set(!visible.get());
        },

        /** @param {Scope} scope @returns {UiNode} */
        details_on(scope) {
            return renderDetails(ui, scope, "details visible");
        },

        /** @param {Scope} scope @returns {UiNode} */
        details_off(scope) {
            return renderDetails(ui, scope, "details hidden");
        },
    };

    return module;
}

/**
 * @param {Runtime} ui
 * @param {Scope} scope
 * @param {string} text
 * @returns {UiNode}
 */
function renderDetails(ui, scope, text) {
    const node = ui.createElement("p");
    node.textContent = text;
    ui.ref(scope, node, "details");
    return node;
}
