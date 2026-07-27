// runtime.ts
var each_item_key = "__ui_each_item";
var each_index_key = "__ui_each_index";
function create_runtime_store(document, doModule) {
  return {
    document,
    doModule,
    nextScopeId: 1,
    nextStateId: 1,
    nextBindingId: 1,
    activeObserver: null,
    batchDepth: 0,
    flushing: false,
    pending: new Set,
    scopes: new Map,
    contexts: new Map
  };
}
function schedule(store, node) {
  if (node.disposed)
    return;
  store.pending.add(node);
  if (store.batchDepth === 0)
    flush(store);
}
function flush(store) {
  if (store.flushing)
    return;
  store.flushing = true;
  try {
    while (store.pending.size > 0) {
      const pending = [...store.pending];
      store.pending.clear();
      for (const node of pending)
        if (!node.disposed)
          run_graph_node(store, node);
    }
  } finally {
    store.flushing = false;
  }
}
function batch(store, fn) {
  store.batchDepth += 1;
  try {
    return fn();
  } finally {
    store.batchDepth -= 1;
    if (store.batchDepth === 0)
      flush(store);
  }
}
function create_graph_node(owner, type) {
  return { owner, type, dependencies: new Set, subscribers: new Set, disposed: false };
}
function graph_track(node, source) {
  if (node.disposed || source.disposed || node.dependencies.has(source))
    return;
  node.dependencies.add(source);
  source.subscribers.add(node);
}
function graph_disconnect_sources(node) {
  for (const source of node.dependencies)
    source.subscribers.delete(node);
  node.dependencies.clear();
}
function graph_disconnect_subscribers(node) {
  for (const subscriber of node.subscribers)
    subscriber.dependencies.delete(node);
  node.subscribers.clear();
}
function observer_invalidate(store, observer) {
  if (observer.type === "computed") {
    computed_invalidate(store, observer);
    return;
  }
  effect_invalidate(store, observer);
}
function graph_dispose(store, node) {
  if (node.disposed)
    return;
  node.disposed = true;
  store.pending.delete(node);
  graph_disconnect_sources(node);
  graph_disconnect_subscribers(node);
  node.owner.resources.delete(node);
}
function run_graph_node(store, node) {
  if (node.type === "computed")
    computed_invalidate(store, node);
  else
    effect_run(store, node);
}
function create_state(store, owner, key, initial) {
  return { id: store.nextStateId++, owner, key, value: initial, version: 0, type: "state", subscribers: new Set, disposed: false };
}
function state_get(store, state) {
  if (!state.disposed && store.activeObserver)
    graph_track(store.activeObserver, state);
  return state.value;
}
function state_set(store, state, next) {
  if (state.disposed || Object.is(state.value, next))
    return;
  state.value = next;
  state.version += 1;
  for (const subscriber of [...state.subscribers])
    observer_invalidate(store, subscriber);
}
function state_dispose(state) {
  if (state.disposed)
    return;
  state.disposed = true;
  for (const subscriber of state.subscribers)
    subscriber.dependencies.delete(state);
  state.subscribers.clear();
  state.owner.states.delete(state.key);
  state.owner.resources.delete(state);
}
function create_computed(owner, key, fn) {
  return { ...create_graph_node(owner, "computed"), type: "computed", key, fn, value: undefined, dirty: true };
}
function computed_get(store, computed) {
  if (!computed.disposed && store.activeObserver)
    graph_track(store.activeObserver, computed);
  if (!computed.disposed && computed.dirty)
    computed_recompute(store, computed);
  return computed.value;
}
function computed_invalidate(store, computed) {
  if (computed.disposed || computed.dirty)
    return;
  computed.dirty = true;
  for (const subscriber of [...computed.subscribers])
    observer_invalidate(store, subscriber);
}
function computed_recompute(store, computed) {
  graph_disconnect_sources(computed);
  const previous = store.activeObserver;
  store.activeObserver = computed;
  try {
    computed.value = computed.fn();
    computed.dirty = false;
  } finally {
    store.activeObserver = previous;
  }
}
function create_effect(owner, key, fn) {
  return { ...create_graph_node(owner, "effect"), type: "effect", key, fn };
}
function effect_run(store, effect) {
  if (effect.disposed)
    return;
  graph_disconnect_sources(effect);
  const previous = store.activeObserver;
  store.activeObserver = effect;
  try {
    effect.fn();
  } finally {
    store.activeObserver = previous;
  }
}
function effect_invalidate(store, effect) {
  schedule(store, effect);
}
function dispose_resource(store, resource) {
  if (resource.type === "state")
    state_dispose(resource);
  else
    graph_dispose(store, resource);
}
function create_scope(store, name, key, parent) {
  const id = store.nextScopeId++;
  const context = Object.freeze({ id });
  const scope = {
    id,
    context,
    name,
    key,
    parent,
    children: new Map,
    states: new Map,
    derived: new Map,
    effects: new Map,
    resources: new Set,
    cleanups: [],
    meta: Object.create(null),
    refs: new Map,
    refCleanups: new Map,
    root: null,
    disposed: false
  };
  if (parent)
    parent.children.set(key, scope);
  store.scopes.set(id, scope);
  store.contexts.set(id, context);
  return scope;
}
function is_scope(owner) {
  return "states" in owner;
}
function resolve_scope(store, owner) {
  if (is_scope(owner))
    return owner;
  if (store.contexts.get(owner.id) !== owner)
    return;
  return store.scopes.get(owner.id);
}
function require_scope(store, owner) {
  const scope = resolve_scope(store, owner);
  if (!scope)
    throw new TypeError("runtime owner is missing or disposed");
  return scope;
}
function get_context(store, owner) {
  if (is_scope(owner))
    return owner.context;
  if (store.contexts.get(owner.id) !== owner)
    throw new TypeError("invalid runtime Context");
  return owner;
}
function get_parent_context(store, owner) {
  return resolve_scope(store, owner)?.parent?.context;
}
function get_meta(store, owner, key, initial) {
  const scope = resolve_scope(store, owner);
  if (!scope || scope.disposed)
    return;
  const value = scope.meta[key];
  return value === undefined ? initial : value;
}
function set_meta(store, owner, key, value) {
  const scope = resolve_scope(store, owner);
  if (!scope || scope.disposed)
    return;
  scope.meta[key] = value;
}
function scope_computed(scope, key, fn) {
  const existing = scope.derived.get(key);
  if (existing)
    return existing;
  const computed = create_computed(scope, key, fn);
  scope.derived.set(key, computed);
  scope.resources.add(computed);
  return computed;
}
function scope_cleanup(scope, fn) {
  if (scope.disposed) {
    fn();
    return;
  }
  scope.cleanups.push(fn);
}
function scope_dispose(store, scope) {
  if (scope.disposed)
    return;
  scope.disposed = true;
  for (const child of [...scope.children.values()])
    scope_dispose(store, child);
  for (const resource of [...scope.resources].reverse())
    dispose_resource(store, resource);
  for (const cleanup of [...scope.cleanups].reverse())
    cleanup();
  scope.children.clear();
  scope.states.clear();
  scope.derived.clear();
  scope.effects.clear();
  scope.refs.clear();
  scope.refCleanups.clear();
  scope.cleanups.length = 0;
  if (scope.parent?.children.get(scope.key) === scope)
    scope.parent.children.delete(scope.key);
  store.scopes.delete(scope.id);
  store.contexts.delete(scope.id);
}
function create_scope_handle(store, name, key, parent = null) {
  return create_scope(store, name, key, parent ? require_scope(store, parent) : null);
}
function get_state_record(store, owner, key, initial) {
  const scope = require_scope(store, owner);
  if (scope.disposed)
    return;
  const existing = scope.states.get(key);
  if (existing)
    return existing;
  const state = create_state(store, scope, key, initial);
  scope.states.set(key, state);
  scope.resources.add(state);
  return state;
}
function get_state(store, owner, key, initial) {
  const state = get_state_record(store, owner, key, initial);
  return state ? state_get(store, state) : undefined;
}
function set_state(store, owner, key, next) {
  const state = get_state_record(store, owner, key, next);
  if (state)
    state_set(store, state, next);
}
function ref(store, owner, node, key) {
  if (!key.trim())
    throw new TypeError("ref key must not be empty");
  const scope = resolve_scope(store, owner);
  if (!scope || scope.disposed)
    return node;
  scope.refCleanups.get(key)?.();
  scope.refs.set(key, node);
  const cleanup = () => {
    if (scope.refs.get(key) !== node)
      return;
    scope.refs.delete(key);
    scope.refCleanups.delete(key);
  };
  scope.refCleanups.set(key, cleanup);
  scope_cleanup(scope, cleanup);
  return node;
}
function get_ref(store, owner, key) {
  const scope = resolve_scope(store, owner);
  return scope && !scope.disposed ? scope.refs.get(key) : undefined;
}
function get_each_item(store, owner) {
  const scope = resolve_scope(store, owner);
  return scope && !scope.disposed ? get_state(store, scope, each_item_key, undefined) : undefined;
}
function get_each_index(store, owner) {
  const value = get_each_item_value(store, owner, each_index_key);
  return typeof value === "number" ? value : undefined;
}
function get_each_item_value(store, owner, key) {
  const scope = resolve_scope(store, owner);
  return scope && !scope.disposed ? get_state(store, scope, key, undefined) : undefined;
}
function normalize_each_key(value) {
  const type = typeof value;
  if (type !== "string" && type !== "number" && type !== "boolean" && type !== "bigint") {
    throw new TypeError("each keys must be primitive values");
  }
  return `${type}:${String(value)}`;
}
function each(store, owner, container, itemsFunction, keyFunction, renderFunction) {
  const scope = require_scope(store, owner);
  const bindingId = store.nextBindingId++;
  const records = new Map;
  return effect(store, scope, `each:${bindingId}`, () => {
    const items = call_do(store, itemsFunction, scope);
    if (!Array.isArray(items))
      throw new TypeError("each source must return an array");
    const descriptors = [];
    const seen = new Set;
    for (let index = 0;index < items.length; index += 1) {
      const item = items[index];
      const key = normalize_each_key(call_do(store, keyFunction, scope, item, index));
      if (seen.has(key))
        throw new Error(`duplicate each key: ${key}`);
      seen.add(key);
      descriptors.push({ key, item, index });
    }
    const nextRecords = new Map;
    const nextRoots = [];
    for (const descriptor of descriptors) {
      const existing = records.get(descriptor.key);
      const itemScope = existing?.scope ?? create_scope_handle(store, `each:${bindingId}`, `each:${bindingId}:${descriptor.key}`, scope);
      set_state(store, itemScope, each_item_key, descriptor.item);
      set_state(store, itemScope, each_index_key, descriptor.index);
      let root = existing?.root;
      if (!root) {
        try {
          root = call_do(store, renderFunction, itemScope);
        } catch (error) {
          scope_dispose(store, itemScope);
          throw error;
        }
        itemScope.root = root;
        scope_cleanup(itemScope, () => root?.remove());
      }
      const record = { key: descriptor.key, scope: itemScope, root };
      nextRecords.set(descriptor.key, record);
      nextRoots.push(root);
    }
    for (const [key, record] of records)
      if (!nextRecords.has(key))
        scope_dispose(store, record.scope);
    records.clear();
    for (const [key, record] of nextRecords)
      records.set(key, record);
    container.append(...nextRoots);
  });
}
function show(store, owner, container, conditionFunction, thenFunction, elseFunction = null) {
  const scope = require_scope(store, owner);
  const bindingId = store.nextBindingId++;
  let active = null;
  return effect(store, scope, `show:${bindingId}`, () => {
    const condition = call_do(store, conditionFunction, scope);
    if (typeof condition !== "boolean")
      throw new TypeError("if condition must return a boolean");
    const branchName = condition ? "then" : "else";
    if (active?.name === branchName)
      return;
    if (active)
      scope_dispose(store, active.scope);
    container.replaceChildren();
    active = null;
    const renderFunction = condition ? thenFunction : elseFunction;
    if (!renderFunction)
      return;
    const branchScope = create_scope_handle(store, `show:${bindingId}`, `show:${bindingId}:${branchName}`, scope);
    try {
      const root = call_do(store, renderFunction, branchScope);
      branchScope.root = root;
      scope_cleanup(branchScope, () => root.remove());
      container.append(root);
      active = { name: branchName, scope: branchScope, root };
    } catch (error) {
      scope_dispose(store, branchScope);
      throw error;
    }
  });
}
function effect(store, owner, keyOrFn, maybeFn) {
  const scope = require_scope(store, owner);
  const key = typeof keyOrFn === "function" ? `effect:${store.nextBindingId++}` : keyOrFn;
  const fn = typeof keyOrFn === "function" ? keyOrFn : maybeFn;
  if (!fn)
    throw new TypeError("effect requires a callback");
  const existing = scope.effects.get(key);
  if (existing)
    return existing;
  const node = create_effect(scope, key, fn);
  scope.effects.set(key, node);
  scope.resources.add(node);
  effect_run(store, node);
  return node;
}
function call_do(store, name, owner, ...args) {
  const scope = resolve_scope(store, owner);
  if (!scope || scope.disposed)
    return;
  const fn = store.doModule?.[name];
  if (!fn)
    throw new Error(`missing do function: ${name}`);
  return fn(scope.context, ...args);
}
function bind_value(store, owner, read, apply) {
  const scope = require_scope(store, owner);
  return effect(store, scope, `binding:${store.nextBindingId++}`, () => {
    if (!scope.disposed)
      apply(read());
  });
}
function bind_derived(store, owner, node, functionName, apply) {
  const scope = require_scope(store, owner);
  const derived = scope_computed(scope, `derived:${store.nextBindingId++}`, () => call_do(store, functionName, scope));
  return bind_value(store, scope, () => computed_get(store, derived), (value) => apply(node, value));
}
function on_event(store, owner, node, type, functionName) {
  const scope = require_scope(store, owner);
  const listener = () => {
    if (!scope.disposed)
      batch(store, () => call_do(store, functionName, scope));
  };
  node.addEventListener(type, listener);
  scope_cleanup(scope, () => node.removeEventListener(type, listener));
  return listener;
}
function mount(store, componentName, key, parent = null) {
  const scope = create_scope_handle(store, componentName, key, parent);
  scope.root = call_do(store, componentName, scope);
  return scope;
}
function dispose_scope_owner(store, owner) {
  const scope = resolve_scope(store, owner);
  if (scope)
    scope_dispose(store, scope);
}
function on_cleanup(store, owner, fn) {
  const scope = resolve_scope(store, owner);
  if (scope)
    scope_cleanup(scope, fn);
}
function create_element(store, tag) {
  return store.document.createElement(tag);
}
function append(parent, ...children) {
  parent.append(...children);
  return parent;
}
function bind_text(store, owner, node, functionName) {
  return bind_derived(store, owner, node, functionName, (target, value) => {
    const next = value == null ? null : String(value);
    if (target.textContent !== next)
      target.textContent = next;
  });
}
function bind_attr(store, owner, node, name, functionName) {
  return bind_derived(store, owner, node, functionName, (target, value) => {
    const record = target;
    if (record[name] !== value)
      record[name] = value;
  });
}
function bind_style(store, owner, node, name, functionName) {
  return bind_derived(store, owner, node, functionName, (target, value) => {
    const next = String(value);
    if (target.style[name] !== next)
      target.style[name] = next;
  });
}
function create_runtime_api(store) {
  return {
    batch: (fn) => batch(store, fn),
    callDo: (name, owner, ...args) => call_do(store, name, owner, ...args),
    createElement: (tag) => create_element(store, tag),
    createScope: (name, key, parent = null) => create_scope_handle(store, name, key, parent),
    getState: (owner, key, initial) => get_state(store, owner, key, initial),
    setState: (owner, key, next) => set_state(store, owner, key, next),
    getContext: (owner) => get_context(store, owner),
    getParentContext: (owner) => get_parent_context(store, owner),
    getMeta: (owner, key, initial) => get_meta(store, owner, key, initial),
    setMeta: (owner, key, value) => set_meta(store, owner, key, value),
    disposeScope: (owner) => dispose_scope_owner(store, owner),
    effect: (owner, keyOrFn, maybeFn) => effect(store, owner, keyOrFn, maybeFn),
    mount: (componentName, key, parent = null) => mount(store, componentName, key, parent),
    onCleanup: (owner, fn) => on_cleanup(store, owner, fn),
    onClick: (owner, node, functionName) => on_event(store, owner, node, "click", functionName),
    ref: (owner, node, key) => ref(store, owner, node, key),
    getRef: (owner, key) => get_ref(store, owner, key),
    getEachItem: (owner) => get_each_item(store, owner),
    getEachIndex: (owner) => get_each_index(store, owner),
    each: (owner, container, itemsFunction, keyFunction, renderFunction) => each(store, owner, container, itemsFunction, keyFunction, renderFunction),
    show: (owner, container, conditionFunction, thenFunction, elseFunction = null) => show(store, owner, container, conditionFunction, thenFunction, elseFunction),
    append,
    bindText: (owner, node, functionName) => bind_text(store, owner, node, functionName),
    bindAttr: (owner, node, name, functionName) => bind_attr(store, owner, node, name, functionName),
    bindStyle: (owner, node, name, functionName) => bind_style(store, owner, node, name, functionName),
    setModule: (nextModule) => {
      store.doModule = nextModule;
    },
    getScope: (id) => store.scopes.get(id)
  };
}
function createRuntime({ document, module = null } = {}) {
  if (!document || typeof document.createElement !== "function") {
    throw new TypeError("ui runtime requires a document adapter");
  }
  return create_runtime_api(create_runtime_store(document, module));
}
export {
  createRuntime
};
