// counter-do.ts
function createCounterModule(ui) {
  const module = {
    counter_increment(context) {
      const count = ui.getState(context, "count", 0);
      ui.setState(context, "count", count + 1);
      ui.getRef(context, "increment_button")?.focus();
    },
    counter_text(context) {
      return String(ui.getState(context, "count", 0));
    },
    counter_class(context) {
      return ui.getState(context, "count", 0) === 0 ? "counter empty" : "counter active";
    },
    counter_color(context) {
      return ui.getState(context, "count", 0) === 0 ? "gray" : "green";
    },
    counter_summary(context) {
      const name = ui.getState(context, "name", "counter");
      const count = ui.getState(context, "count", 0);
      const enabled = ui.getState(context, "enabled", true);
      return enabled ? `${name}: ${count}` : "disabled";
    },
    counter_render(context) {
      const renderCount = ui.getMeta(context, "renderCount", 0) ?? 0;
      ui.setMeta(context, "renderCount", renderCount + 1);
      ui.getState(context, "count", 0);
      ui.getState(context, "name", "counter");
      ui.getState(context, "enabled", true);
      const root = ui.createElement("article");
      const value = ui.createElement("strong");
      const summary = ui.createElement("p");
      const button = ui.createElement("button");
      button.textContent = "+";
      ui.ref(context, button, "increment_button");
      ui.bindText(context, value, "counter_text");
      ui.bindText(context, summary, "counter_summary");
      ui.bindAttr(context, root, "className", "counter_class");
      ui.bindStyle(context, root, "color", "counter_color");
      ui.onClick(context, button, "counter_increment");
      ui.onCleanup(context, () => root.remove());
      ui.append(root, value, summary, button);
      root._demo = {
        button,
        summary,
        value,
        renderCount: () => ui.getMeta(context, "renderCount", 0) ?? 0
      };
      return root;
    },
    list_items(context) {
      return ui.getState(context, "items", ["alpha", "beta"]);
    },
    list_item_key(_context, item) {
      return String(item);
    },
    list_item_text(context) {
      return `${String(ui.getEachItem(context))} (#${ui.getEachIndex(context)})`;
    },
    list_add(context) {
      const items = ui.getState(context, "items", ["alpha", "beta"]);
      let nextIndex = ui.getMeta(context, "nextItem", 1) ?? 1;
      let item = `item-${nextIndex}`;
      while (items.includes(item)) {
        nextIndex += 1;
        item = `item-${nextIndex}`;
      }
      ui.setMeta(context, "nextItem", nextIndex + 1);
      ui.setState(context, "items", [...items, item]);
    },
    list_reverse(context) {
      const items = ui.getState(context, "items", ["alpha", "beta"]);
      ui.setState(context, "items", [...items].reverse());
    },
    list_remove(context) {
      const parent = ui.getParentContext(context);
      if (!parent)
        return;
      const item = ui.getEachItem(context);
      const items = ui.getState(parent, "items", ["alpha", "beta"]);
      ui.setState(parent, "items", items.filter((candidate) => !Object.is(candidate, item)));
    },
    list_item_render(context) {
      const renderCount = ui.getMeta(context, "renderCount", 0) ?? 0;
      ui.setMeta(context, "renderCount", renderCount + 1);
      const root = ui.createElement("li");
      const label = ui.createElement("span");
      const remove = ui.createElement("button");
      remove.textContent = "Remove";
      const scope = ui.getScope(context.id);
      if (scope)
        root._itemScope = scope;
      ui.ref(context, remove, "remove_button");
      ui.bindText(context, label, "list_item_text");
      ui.onClick(context, remove, "list_remove");
      ui.append(root, label, remove);
      return root;
    },
    show_details(context) {
      return ui.getState(context, "showDetails", true);
    },
    toggle_details(context) {
      const visible = ui.getState(context, "showDetails", true);
      ui.setState(context, "showDetails", !visible);
    },
    details_on(context) {
      return renderDetails(ui, context, "details visible");
    },
    details_off(context) {
      return renderDetails(ui, context, "details hidden");
    }
  };
  return module;
}
function renderDetails(ui, context, text) {
  const node = ui.createElement("p");
  node.textContent = text;
  ui.ref(context, node, "details");
  return node;
}
export {
  createCounterModule
};
