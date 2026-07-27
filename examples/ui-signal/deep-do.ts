import type { Context, DoModule, Runtime, Scope, UiNode } from "./runtime.js";

interface Order { name: string; city: string; lines: string[]; }
interface Line { product: string; quantity: number; price: number; }

const ORDERS: Record<string, Order> = {
    "order-1001": {
        name: "Ada Lovelace",
        city: "London",
        lines: ["line-compiler", "line-runtime"],
    },
    "order-1002": {
        name: "Grace Hopper",
        city: "New York",
        lines: ["line-debugger"],
    },
};

const LINES: Record<string, Line> = {
    "line-compiler": { product: "Compiler", quantity: 2, price: 120 },
    "line-runtime": { product: "Runtime", quantity: 1, price: 80 },
    "line-debugger": { product: "Debugger", quantity: 3, price: 60 },
};

/**
 * This module models the future do-facing shape with stable path keys:
 * `customer.name`, `shipping.city`, `lines.structure`, and
 * `product.name` are separate runtime State entries. It intentionally uses
 * ordinary static exports and Context handles instead of closures.
 *
 */
export function createDeepModule(ui: Runtime): DoModule {
    const module: DoModule = {
        deep_orders(context: Context): string[] {
            return ui.getState(context, "orders.structure", Object.keys(ORDERS));
        },

        deep_order_key(_context: Context, item: unknown): string {
            return String(item);
        },

        deep_customer_name(context: Context): string {
            return readLeaf(ui, context, "customer.name", getOrder(ui, context).name);
        },

        deep_shipping_city(context: Context): string {
            return readLeaf(ui, context, "shipping.city", getOrder(ui, context).city);
        },

        deep_change_name(context: Context): void {
            const order = getOrder(ui, context);
            const current = ui.getState(context, "customer.name", order.name);
            const next = current === order.name ? "Ada Byron Lovelace" : order.name;
            ui.setState(context, "customer.name", next);
        },

        deep_change_city(context: Context): void {
            const order = getOrder(ui, context);
            const current = ui.getState(context, "shipping.city", order.city);
            ui.setState(context, "shipping.city", current === "London" ? "Paris" : "London");
        },

        deep_line_ids(context: Context): string[] {
            return ui.getState(context, "lines.structure", getOrder(ui, context).lines);
        },

        deep_line_key(_context: Context, item: unknown): string {
            return String(item);
        },

        deep_line_product(context: Context): string {
            return readLeaf(ui, context, "product.name", getLine(ui, context).product);
        },

        deep_line_quantity(context: Context): string {
            return readLeaf(ui, context, "quantity", getLine(ui, context).quantity);
        },

        deep_line_price(context: Context): string {
            return readLeaf(ui, context, "price", getLine(ui, context).price);
        },

        deep_increment_quantity(context: Context): void {
            const current = ui.getState(context, "quantity", getLine(ui, context).quantity);
            ui.setState(context, "quantity", current + 1);
        },

        deep_add_line(context: Context): void {
            const current = ui.getState(context, "lines.structure", getOrder(ui, context).lines);
            let nextNumber = ui.getMeta(context, "nextLineNumber", 1) ?? 1;
            let nextKey = `line-extra-${nextNumber}`;
            while (current.includes(nextKey)) {
                nextNumber += 1;
                nextKey = `line-extra-${nextNumber}`;
            }
            ui.setMeta(context, "nextLineNumber", nextNumber + 1);
            ui.setState(context, "lines.structure", [...current, nextKey]);
        },

        deep_remove_line(context: Context): void {
            const parent = ui.getParentContext(context);
            if (!parent) return;
            const item = ui.getEachItem(context);
            const current = ui.getState(parent, "lines.structure", getOrder(ui, parent).lines);
            ui.setState(
                parent,
                "lines.structure",
                current.filter((candidate) => !Object.is(candidate, item))
            );
        },

        deep_add_order(context: Context): void {
            const current = ui.getState(context, "orders.structure", Object.keys(ORDERS));
            let nextNumber = ui.getMeta(context, "nextOrderNumber", 1003) ?? 1003;
            let nextKey = `order-${nextNumber}`;
            while (current.includes(nextKey)) {
                nextNumber += 1;
                nextKey = `order-${nextNumber}`;
            }
            ui.setMeta(context, "nextOrderNumber", nextNumber + 1);
            ui.setState(context, "orders.structure", [...current, nextKey]);
        },

        deep_reverse_orders(context: Context): void {
            const current = ui.getState(context, "orders.structure", Object.keys(ORDERS));
            ui.setState(context, "orders.structure", [...current].reverse());
        },

        deep_order_render(context: Context): UiNode {
            const orderId = String(ui.getEachItem(context));
            const order = ORDERS[orderId] ?? {
                name: `New order ${orderId}`,
                city: "Unassigned",
                lines: [],
            };
            ui.setMeta(context, "deepOrderId", orderId);
            ui.setMeta(context, "deepOrder", order);
            const renderRuns = ui.getMeta(context, "deepRenderRuns", 0) ?? 0;
            ui.setMeta(context, "deepRenderRuns", renderRuns + 1);

            const root = ui.createElement("article") as UiNode & { _itemScope?: Scope; _deep: Record<string, unknown> };
            root.className = "deep-order";
            const scope = ui.getScope(context.id);
            if (scope) root._itemScope = scope;

            const heading = ui.createElement("h3");
            heading.textContent = `Order ${orderId}`;
            const renderInfo = ui.createElement("p");
            renderInfo.className = "deep-render-info";
            renderInfo.textContent = `order render runs ${renderRuns + 1}`;

            const fields = ui.createElement("div");
            fields.className = "deep-fields";
            const name = addField(ui, fields, context, "customer.name", "deep_customer_name");
            const city = addField(ui, fields, context, "shipping.city", "deep_shipping_city");

            const actions = ui.createElement("div");
            actions.className = "toolbar";
            const changeName = button(ui, "Change name");
            const changeCity = button(ui, "Change city");
            const addLine = button(ui, "Add line");
            ui.onClick(context, changeName, "deep_change_name");
            ui.onClick(context, changeCity, "deep_change_city");
            ui.onClick(context, addLine, "deep_add_line");
            ui.append(actions, changeName, changeCity, addLine);

            const linesTitle = ui.createElement("h4");
            linesTitle.textContent = "lines.structure";
            const lines = ui.createElement("ul");
            lines.className = "deep-lines";
            ui.each(context, lines, "deep_line_ids", "deep_line_key", "deep_line_render");

            ui.append(root, heading, renderInfo, fields, actions, linesTitle, lines);
            root._deep = { name, city, lines, renderRuns: renderRuns + 1 };
            return root;
        },

        deep_line_render(context: Context): UiNode {
            const lineId = String(ui.getEachItem(context));
            const line = LINES[lineId] ?? { product: "New line", quantity: 1, price: 0 };
            ui.setMeta(context, "deepLineId", lineId);
            ui.setMeta(context, "deepLine", line);
            const renderRuns = ui.getMeta(context, "deepRenderRuns", 0) ?? 0;
            ui.setMeta(context, "deepRenderRuns", renderRuns + 1);

            const root = ui.createElement("li") as UiNode & { _itemScope?: Scope; _deep: Record<string, unknown> };
            const scope = ui.getScope(context.id);
            if (scope) root._itemScope = scope;
            root.className = "deep-line";

            const fields = ui.createElement("div");
            fields.className = "deep-line-fields";
            const product = addField(ui, fields, context, "product.name", "deep_line_product");
            const quantity = addField(ui, fields, context, "quantity", "deep_line_quantity");
            const price = addField(ui, fields, context, "price", "deep_line_price");

            const actions = ui.createElement("div");
            actions.className = "toolbar";
            const increment = button(ui, "+ quantity");
            const remove = button(ui, "Remove");
            ui.onClick(context, increment, "deep_increment_quantity");
            ui.onClick(context, remove, "deep_remove_line");
            ui.append(actions, increment, remove);
            ui.append(root, fields, actions);

            root._deep = {
                product,
                quantity,
                price,
                renderRuns: renderRuns + 1,
            };
            return root;
        },
    };
    return module;
}

function addField(ui: Runtime, parent: UiNode, context: Context, label: string, functionName: string): UiNode {
    const row = ui.createElement("div");
    row.className = "deep-field";
    const labelNode = ui.createElement("span");
    labelNode.className = "deep-field-label";
    labelNode.textContent = label;
    const valueNode = ui.createElement("code");
    ui.bindText(context, valueNode, functionName);
    ui.append(row, labelNode, valueNode);
    ui.append(parent, row);
    return valueNode;
}

function button(ui: Runtime, text: string): UiNode {
    const node = ui.createElement("button");
    node.textContent = text;
    return node;
}

function getOrder(ui: Runtime, context: Context): Order {
    const orderId = ui.getMeta(context, "deepOrderId", "") || "order-1001";
    return ORDERS[orderId] ?? { name: `New order ${orderId}`, city: "Unassigned", lines: [] };
}

function getLine(ui: Runtime, context: Context): Line {
    const lineId = ui.getMeta(context, "deepLineId", "") || "line-compiler";
    return LINES[lineId] ?? { product: "New line", quantity: 1, price: 0 };
}

function readLeaf<T>(ui: Runtime, context: Context, path: string, initial: T): string {
    const runs = ui.getMeta<Record<string, number>>(context, "deepEffectRuns", Object.create(null)) ?? Object.create(null);
    const nextRuns = (runs[path] ?? 0) + 1;
    runs[path] = nextRuns;
    ui.setMeta(context, "deepEffectRuns", runs);
    return `${String(ui.getState(context, path, initial))} | effect runs ${nextRuns}`;
}
