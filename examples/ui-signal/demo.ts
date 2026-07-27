import { createCounterModule } from "./counter-do.js";
import { createDeepModule } from "./deep-do.js";
import { createRuntime } from "./runtime.js";
import type { Scope, UiNode } from "./runtime.js";

type ButtonNode = UiNode & { disabled: boolean };

function requireNode(selector: string): UiNode {
    const node = document.querySelector(selector);
    if (!node) throw new Error(`missing demo node: ${selector}`);
    return node as unknown as UiNode;
}

function requireRoot(scope: Scope): UiNode {
    if (!scope.root) throw new Error(`component did not create a root: ${scope.name}`);
    return scope.root;
}

const runtime = createRuntime({ document });
runtime.setModule({
    ...createCounterModule(runtime),
    ...createDeepModule(runtime),
});

const app = runtime.createScope("app", "app");
const mountNode = requireNode("#mount");
const status = requireNode("#status");
const removeSecond = requireNode("#remove-second") as ButtonNode;
const listNode = requireNode("#item-list");
const addItem = requireNode("#add-item");
const reverseItems = requireNode("#reverse-items");
const detailsNode = requireNode("#details");
const toggleDetails = requireNode("#toggle-details");
const deepOrderList = requireNode("#deep-order-list");
const deepAddOrder = requireNode("#deep-add-order");
const deepReverseOrders = requireNode("#deep-reverse-orders");

const first = runtime.mount("counter_render", "first", app);
const second = runtime.mount("counter_render", "second", app);
const firstRoot = requireRoot(first);
const secondRoot = requireRoot(second);
mountNode.append(firstRoot, secondRoot);
runtime.each(app, listNode, "list_items", "list_item_key", "list_item_render");
runtime.show(app, detailsNode, "show_details", "details_on", "details_off");
runtime.onClick(app, addItem, "list_add");
runtime.onClick(app, reverseItems, "list_reverse");
runtime.onClick(app, toggleDetails, "toggle_details");
runtime.each(app, deepOrderList, "deep_orders", "deep_order_key", "deep_order_render");
runtime.onClick(app, deepAddOrder, "deep_add_order");
runtime.onClick(app, deepReverseOrders, "deep_reverse_orders");

/** @returns {void} */
const removeListener = () => {
    runtime.disposeScope(second);
    removeSecond.disabled = true;
    status.textContent = "The second child scope was disposed.";
};

removeSecond.addEventListener("click", removeListener, { once: true });
runtime.onCleanup(app, () => removeSecond.removeEventListener("click", removeListener));
