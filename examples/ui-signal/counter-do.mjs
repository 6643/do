// @ts-check

/** @typedef {import("./runtime.mjs").Runtime} Runtime */
/** @typedef {import("./runtime.mjs").Scope} Scope */
/** @typedef {import("./runtime.mjs").UiNode} UiNode */
/** @typedef {Record<string, (scope: Scope, ...args: unknown[]) => unknown>} DoModule */

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
    };

    return module;
}
