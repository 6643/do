// @ts-check

import { createRuntime } from "./runtime.mjs";
import { createCounterModule } from "./counter-do.mjs";

/** @typedef {import("./runtime.mjs").UiNode} UiNode */

const runtime = createRuntime({ document });
runtime.setModule(createCounterModule(runtime));

const app = runtime.createScope("app", "app");
const mountNode = /** @type {UiNode} */ (
    /** @type {unknown} */ (document.querySelector("#mount"))
);
const status = /** @type {UiNode} */ (
    /** @type {unknown} */ (document.querySelector("#status"))
);
const removeSecond = /** @type {UiNode & {disabled: boolean}} */ (
    /** @type {unknown} */ (document.querySelector("#remove-second"))
);
const listNode = /** @type {UiNode} */ (
    /** @type {unknown} */ (document.querySelector("#item-list"))
);
const addItem = /** @type {UiNode} */ (
    /** @type {unknown} */ (document.querySelector("#add-item"))
);
const reverseItems = /** @type {UiNode} */ (
    /** @type {unknown} */ (document.querySelector("#reverse-items"))
);
const detailsNode = /** @type {UiNode} */ (
    /** @type {unknown} */ (document.querySelector("#details"))
);
const toggleDetails = /** @type {UiNode} */ (
    /** @type {unknown} */ (document.querySelector("#toggle-details"))
);

const first = runtime.mount("counter_render", "first", app);
const second = runtime.mount("counter_render", "second", app);
const firstRoot = /** @type {UiNode} */ (first.root);
const secondRoot = /** @type {UiNode} */ (second.root);
mountNode.append(firstRoot, secondRoot);
runtime.each(app, listNode, "list_items", "list_item_key", "list_item_render");
runtime.ifBlock(app, detailsNode, "show_details", "details_on", "details_off");
runtime.onClick(app, addItem, "list_add");
runtime.onClick(app, reverseItems, "list_reverse");
runtime.onClick(app, toggleDetails, "toggle_details");

/** @returns {void} */
const removeListener = () => {
    runtime.disposeScope(second);
    removeSecond.disabled = true;
    status.textContent = "The second child scope was disposed.";
};

removeSecond.addEventListener("click", removeListener, { once: true });
runtime.onCleanup(app, () => removeSecond.removeEventListener("click", removeListener));
