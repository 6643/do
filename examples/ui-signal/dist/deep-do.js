// deep-do.ts
var ORDERS = {
  "order-1001": {
    name: "Ada Lovelace",
    city: "London",
    lines: ["line-compiler", "line-runtime"]
  },
  "order-1002": {
    name: "Grace Hopper",
    city: "New York",
    lines: ["line-debugger"]
  }
};
var LINES = {
  "line-compiler": { product: "Compiler", quantity: 2, price: 120 },
  "line-runtime": { product: "Runtime", quantity: 1, price: 80 },
  "line-debugger": { product: "Debugger", quantity: 3, price: 60 }
};
function createDeepModule(ui) {
  const module = {
    deep_orders(context) {
      return ui.getState(context, "orders.structure", Object.keys(ORDERS));
    },
    deep_order_key(_context, item) {
      return String(item);
    },
    deep_customer_name(context) {
      return readLeaf(ui, context, "customer.name", getOrder(ui, context).name);
    },
    deep_shipping_city(context) {
      return readLeaf(ui, context, "shipping.city", getOrder(ui, context).city);
    },
    deep_change_name(context) {
      const order = getOrder(ui, context);
      const current = ui.getState(context, "customer.name", order.name);
      const next = current === order.name ? "Ada Byron Lovelace" : order.name;
      ui.setState(context, "customer.name", next);
    },
    deep_change_city(context) {
      const order = getOrder(ui, context);
      const current = ui.getState(context, "shipping.city", order.city);
      ui.setState(context, "shipping.city", current === "London" ? "Paris" : "London");
    },
    deep_line_ids(context) {
      return ui.getState(context, "lines.structure", getOrder(ui, context).lines);
    },
    deep_line_key(_context, item) {
      return String(item);
    },
    deep_line_product(context) {
      return readLeaf(ui, context, "product.name", getLine(ui, context).product);
    },
    deep_line_quantity(context) {
      return readLeaf(ui, context, "quantity", getLine(ui, context).quantity);
    },
    deep_line_price(context) {
      return readLeaf(ui, context, "price", getLine(ui, context).price);
    },
    deep_increment_quantity(context) {
      const current = ui.getState(context, "quantity", getLine(ui, context).quantity);
      ui.setState(context, "quantity", current + 1);
    },
    deep_add_line(context) {
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
    deep_remove_line(context) {
      const parent = ui.getParentContext(context);
      if (!parent)
        return;
      const item = ui.getEachItem(context);
      const current = ui.getState(parent, "lines.structure", getOrder(ui, parent).lines);
      ui.setState(parent, "lines.structure", current.filter((candidate) => !Object.is(candidate, item)));
    },
    deep_add_order(context) {
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
    deep_reverse_orders(context) {
      const current = ui.getState(context, "orders.structure", Object.keys(ORDERS));
      ui.setState(context, "orders.structure", [...current].reverse());
    },
    deep_order_render(context) {
      const orderId = String(ui.getEachItem(context));
      const order = ORDERS[orderId] ?? {
        name: `New order ${orderId}`,
        city: "Unassigned",
        lines: []
      };
      ui.setMeta(context, "deepOrderId", orderId);
      ui.setMeta(context, "deepOrder", order);
      const renderRuns = ui.getMeta(context, "deepRenderRuns", 0) ?? 0;
      ui.setMeta(context, "deepRenderRuns", renderRuns + 1);
      const root = ui.createElement("article");
      root.className = "deep-order";
      const scope = ui.getScope(context.id);
      if (scope)
        root._itemScope = scope;
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
    deep_line_render(context) {
      const lineId = String(ui.getEachItem(context));
      const line = LINES[lineId] ?? { product: "New line", quantity: 1, price: 0 };
      ui.setMeta(context, "deepLineId", lineId);
      ui.setMeta(context, "deepLine", line);
      const renderRuns = ui.getMeta(context, "deepRenderRuns", 0) ?? 0;
      ui.setMeta(context, "deepRenderRuns", renderRuns + 1);
      const root = ui.createElement("li");
      const scope = ui.getScope(context.id);
      if (scope)
        root._itemScope = scope;
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
        renderRuns: renderRuns + 1
      };
      return root;
    }
  };
  return module;
}
function addField(ui, parent, context, label, functionName) {
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
function button(ui, text) {
  const node = ui.createElement("button");
  node.textContent = text;
  return node;
}
function getOrder(ui, context) {
  const orderId = ui.getMeta(context, "deepOrderId", "") || "order-1001";
  return ORDERS[orderId] ?? { name: `New order ${orderId}`, city: "Unassigned", lines: [] };
}
function getLine(ui, context) {
  const lineId = ui.getMeta(context, "deepLineId", "") || "line-compiler";
  return LINES[lineId] ?? { product: "New line", quantity: 1, price: 0 };
}
function readLeaf(ui, context, path, initial) {
  const runs = ui.getMeta(context, "deepEffectRuns", Object.create(null)) ?? Object.create(null);
  const nextRuns = (runs[path] ?? 0) + 1;
  runs[path] = nextRuns;
  ui.setMeta(context, "deepEffectRuns", runs);
  return `${String(ui.getState(context, path, initial))} | effect runs ${nextRuns}`;
}
export {
  createDeepModule
};
