export interface UiNode {
    textContent: string | null;
    className: string;
    style: Record<string, string>;
    children: UiNode[];
    parentNode: UiNode | null;
    addEventListener(type: string, listener: (...args: any[]) => unknown, options?: unknown): void;
    removeEventListener(type: string, listener: (...args: any[]) => unknown, options?: unknown): void;
    dispatchEvent(type: string): void;
    listenerCount(type: string): number;
    append(...children: UiNode[]): void;
    replaceChildren(...children: UiNode[]): void;
    remove(): void;
    focus(): void;
    focused: boolean;
    _demo: unknown;
    _itemScope?: Scope;
    _branchScope?: Scope;
}

export interface DocumentAdapter {
    createElement(tag: string): unknown;
}

export interface Context {
    readonly id: number;
}

export interface GraphNode {
    owner: Scope;
    type: "computed" | "effect";
    disposed: boolean;
    dependencies: Set<StateSource>;
    subscribers: Set<StateObserver>;
}

export type StateObserver = GraphNode;

export interface StateHandle<T = unknown> {
    id: number;
    owner: Scope;
    key: string;
    value: T;
    version: number;
    type: "state";
    disposed: boolean;
    subscribers: Set<StateObserver>;
}

export interface ComputedHandle<T = unknown> extends GraphNode {
    type: "computed";
    key: string;
    fn: () => T;
    value: T | undefined;
    dirty: boolean;
}

export interface EffectHandle extends GraphNode {
    type: "effect";
    key: string;
    fn: () => unknown;
}

export type StateSource = StateHandle<any> | ComputedHandle<any>;
export type OwnedResource = StateHandle<any> | ComputedHandle<any> | EffectHandle;

export interface Scope {
    id: number;
    context: Context;
    name: string;
    key: string;
    parent: Scope | null;
    children: Map<string, Scope>;
    states: Map<string, StateHandle<any>>;
    derived: Map<string, ComputedHandle<any>>;
    effects: Map<string, EffectHandle>;
    resources: Set<OwnedResource>;
    cleanups: Array<() => unknown>;
    meta: Record<string, unknown>;
    refs: Map<string, UiNode>;
    refCleanups: Map<string, () => void>;
    root: UiNode | null;
    disposed: boolean;
}

export type RuntimeOwner = Scope | Context;
export type DoFunction = (context: Context, ...args: unknown[]) => unknown;
export type DoModule = Record<string, DoFunction>;

export interface RuntimeOptions {
    document?: DocumentAdapter;
    module?: DoModule | null;
}

export interface Runtime {
    batch<T>(fn: () => T): T;
    callDo<T>(name: string, owner: RuntimeOwner, ...args: unknown[]): T | undefined;
    createElement(tag: string): UiNode;
    createScope(name: string, key: string, parent?: RuntimeOwner | null): Scope;
    getState<T>(owner: RuntimeOwner, key: string, initial: T): T;
    setState<T>(owner: RuntimeOwner, key: string, next: T): void;
    getContext(owner: RuntimeOwner): Context;
    getParentContext(owner: RuntimeOwner): Context | undefined;
    getMeta<T>(owner: RuntimeOwner, key: string, initial: T): T | undefined;
    setMeta<T>(owner: RuntimeOwner, key: string, value: T): void;
    disposeScope(owner: RuntimeOwner): void;
    effect(owner: RuntimeOwner, keyOrFn: string | (() => unknown), maybeFn?: () => unknown): EffectHandle;
    mount(componentName: string, key: string, parent?: RuntimeOwner | null): Scope;
    onCleanup(owner: RuntimeOwner, fn: () => unknown): void;
    onClick(owner: RuntimeOwner, node: UiNode, functionName: string): (...args: any[]) => unknown;
    ref(owner: RuntimeOwner, node: UiNode, key: string): UiNode;
    getRef(owner: RuntimeOwner, key: string): UiNode | undefined;
    getEachItem(owner: RuntimeOwner): unknown;
    getEachIndex(owner: RuntimeOwner): number | undefined;
    each(owner: RuntimeOwner, container: UiNode, itemsFunction: string, keyFunction: string, renderFunction: string): EffectHandle;
    show(owner: RuntimeOwner, container: UiNode, conditionFunction: string, thenFunction: string, elseFunction?: string | null): EffectHandle;
    append(parent: UiNode, ...children: UiNode[]): UiNode;
    bindText(owner: RuntimeOwner, node: UiNode, functionName: string): EffectHandle;
    bindAttr(owner: RuntimeOwner, node: UiNode, name: string, functionName: string): EffectHandle;
    bindStyle(owner: RuntimeOwner, node: UiNode, name: string, functionName: string): EffectHandle;
    setModule(nextModule: DoModule | null): void;
    getScope(id: number): Scope | undefined;
}

interface RuntimeStore {
    document: DocumentAdapter;
    doModule: DoModule | null;
    nextScopeId: number;
    nextStateId: number;
    nextBindingId: number;
    activeObserver: GraphNode | null;
    batchDepth: number;
    flushing: boolean;
    pending: Set<GraphNode>;
    scopes: Map<number, Scope>;
    contexts: Map<number, Context>;
}

const each_item_key = "__ui_each_item";
const each_index_key = "__ui_each_index";

function create_runtime_store(document: DocumentAdapter, doModule: DoModule | null): RuntimeStore {
    return {
        document,
        doModule,
        nextScopeId: 1,
        nextStateId: 1,
        nextBindingId: 1,
        activeObserver: null,
        batchDepth: 0,
        flushing: false,
        pending: new Set(),
        scopes: new Map(),
        contexts: new Map(),
    };
}

function schedule(store: RuntimeStore, node: GraphNode): void {
    if (node.disposed) return;
    store.pending.add(node);
    if (store.batchDepth === 0) flush(store);
}

function flush(store: RuntimeStore): void {
    if (store.flushing) return;
    store.flushing = true;
    try {
        while (store.pending.size > 0) {
            const pending = [...store.pending];
            store.pending.clear();
            for (const node of pending) if (!node.disposed) run_graph_node(store, node);
        }
    } finally {
        store.flushing = false;
    }
}

function batch<T>(store: RuntimeStore, fn: () => T): T {
    store.batchDepth += 1;
    try {
        return fn();
    } finally {
        store.batchDepth -= 1;
        if (store.batchDepth === 0) flush(store);
    }
}

function create_graph_node(owner: Scope, type: "computed" | "effect"): GraphNode {
    return { owner, type, dependencies: new Set(), subscribers: new Set(), disposed: false };
}

function graph_track(node: GraphNode, source: StateSource): void {
    if (node.disposed || source.disposed || node.dependencies.has(source)) return;
    node.dependencies.add(source);
    source.subscribers.add(node);
}

function graph_disconnect_sources(node: GraphNode): void {
    for (const source of node.dependencies) source.subscribers.delete(node);
    node.dependencies.clear();
}

function graph_disconnect_subscribers(node: GraphNode): void {
    for (const subscriber of node.subscribers) subscriber.dependencies.delete(node as StateSource);
    node.subscribers.clear();
}

function observer_invalidate(store: RuntimeStore, observer: StateObserver): void {
    if (observer.type === "computed") {
        computed_invalidate(store, observer as ComputedHandle);
        return;
    }
    effect_invalidate(store, observer as EffectHandle);
}

function graph_dispose(store: RuntimeStore, node: GraphNode): void {
    if (node.disposed) return;
    node.disposed = true;
    store.pending.delete(node);
    graph_disconnect_sources(node);
    graph_disconnect_subscribers(node);
    node.owner.resources.delete(node as OwnedResource);
}

function run_graph_node(store: RuntimeStore, node: GraphNode): void {
    if (node.type === "computed") computed_invalidate(store, node as ComputedHandle);
    else effect_run(store, node as EffectHandle);
}

function create_state<T>(store: RuntimeStore, owner: Scope, key: string, initial: T): StateHandle<T> {
    return { id: store.nextStateId++, owner, key, value: initial, version: 0, type: "state", subscribers: new Set(), disposed: false };
}

function state_get<T>(store: RuntimeStore, state: StateHandle<T>): T {
    if (!state.disposed && store.activeObserver) graph_track(store.activeObserver, state);
    return state.value;
}

function state_set<T>(store: RuntimeStore, state: StateHandle<T>, next: T): void {
    if (state.disposed || Object.is(state.value, next)) return;
    state.value = next;
    state.version += 1;
    for (const subscriber of [...state.subscribers]) observer_invalidate(store, subscriber);
}

function state_dispose(state: StateHandle<any>): void {
    if (state.disposed) return;
    state.disposed = true;
    for (const subscriber of state.subscribers) subscriber.dependencies.delete(state);
    state.subscribers.clear();
    state.owner.states.delete(state.key);
    state.owner.resources.delete(state);
}

function create_computed<T>(owner: Scope, key: string, fn: () => T): ComputedHandle<T> {
    return { ...create_graph_node(owner, "computed"), type: "computed", key, fn, value: undefined, dirty: true };
}

function computed_get<T>(store: RuntimeStore, computed: ComputedHandle<T>): T {
    if (!computed.disposed && store.activeObserver) graph_track(store.activeObserver, computed);
    if (!computed.disposed && computed.dirty) computed_recompute(store, computed);
    return computed.value as T;
}

function computed_invalidate(store: RuntimeStore, computed: ComputedHandle<any>): void {
    if (computed.disposed || computed.dirty) return;
    computed.dirty = true;
    for (const subscriber of [...computed.subscribers]) observer_invalidate(store, subscriber);
}

function computed_recompute<T>(store: RuntimeStore, computed: ComputedHandle<T>): void {
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

function create_effect(owner: Scope, key: string, fn: () => unknown): EffectHandle {
    return { ...create_graph_node(owner, "effect"), type: "effect", key, fn };
}

function effect_run(store: RuntimeStore, effect: EffectHandle): void {
    if (effect.disposed) return;
    graph_disconnect_sources(effect);
    const previous = store.activeObserver;
    store.activeObserver = effect;
    try {
        effect.fn();
    } finally {
        store.activeObserver = previous;
    }
}

function effect_invalidate(store: RuntimeStore, effect: EffectHandle): void {
    schedule(store, effect);
}

function dispose_resource(store: RuntimeStore, resource: OwnedResource): void {
    if (resource.type === "state") state_dispose(resource);
    else graph_dispose(store, resource);
}

function create_scope(store: RuntimeStore, name: string, key: string, parent: Scope | null): Scope {
    const id = store.nextScopeId++;
    const context: Context = Object.freeze({ id });
    const scope: Scope = {
        id,
        context,
        name,
        key,
        parent,
        children: new Map(),
        states: new Map(),
        derived: new Map(),
        effects: new Map(),
        resources: new Set(),
        cleanups: [],
        meta: Object.create(null) as Record<string, unknown>,
        refs: new Map(),
        refCleanups: new Map(),
        root: null,
        disposed: false,
    };
    if (parent) parent.children.set(key, scope);
    store.scopes.set(id, scope);
    store.contexts.set(id, context);
    return scope;
}

function is_scope(owner: RuntimeOwner): owner is Scope {
    return "states" in owner;
}

function resolve_scope(store: RuntimeStore, owner: RuntimeOwner): Scope | undefined {
    if (is_scope(owner)) return owner;
    if (store.contexts.get(owner.id) !== owner) return undefined;
    return store.scopes.get(owner.id);
}

function require_scope(store: RuntimeStore, owner: RuntimeOwner): Scope {
    const scope = resolve_scope(store, owner);
    if (!scope) throw new TypeError("runtime owner is missing or disposed");
    return scope;
}

function get_context(store: RuntimeStore, owner: RuntimeOwner): Context {
    if (is_scope(owner)) return owner.context;
    if (store.contexts.get(owner.id) !== owner) throw new TypeError("invalid runtime Context");
    return owner;
}

function get_parent_context(store: RuntimeStore, owner: RuntimeOwner): Context | undefined {
    return resolve_scope(store, owner)?.parent?.context;
}

function get_meta<T>(store: RuntimeStore, owner: RuntimeOwner, key: string, initial: T): T | undefined {
    const scope = resolve_scope(store, owner);
    if (!scope || scope.disposed) return undefined;
    const value = scope.meta[key];
    return value === undefined ? initial : value as T;
}

function set_meta<T>(store: RuntimeStore, owner: RuntimeOwner, key: string, value: T): void {
    const scope = resolve_scope(store, owner);
    if (!scope || scope.disposed) return;
    scope.meta[key] = value;
}

function scope_computed<T>(scope: Scope, key: string, fn: () => T): ComputedHandle<T> {
    const existing = scope.derived.get(key) as ComputedHandle<T> | undefined;
    if (existing) return existing;
    const computed = create_computed(scope, key, fn);
    scope.derived.set(key, computed);
    scope.resources.add(computed);
    return computed;
}

function scope_cleanup(scope: Scope, fn: () => unknown): void {
    if (scope.disposed) {
        fn();
        return;
    }
    scope.cleanups.push(fn);
}

function scope_dispose(store: RuntimeStore, scope: Scope): void {
    if (scope.disposed) return;
    scope.disposed = true;
    for (const child of [...scope.children.values()]) scope_dispose(store, child);
    for (const resource of [...scope.resources].reverse()) dispose_resource(store, resource);
    for (const cleanup of [...scope.cleanups].reverse()) cleanup();
    scope.children.clear();
    scope.states.clear();
    scope.derived.clear();
    scope.effects.clear();
    scope.refs.clear();
    scope.refCleanups.clear();
    scope.cleanups.length = 0;
    if (scope.parent?.children.get(scope.key) === scope) scope.parent.children.delete(scope.key);
    store.scopes.delete(scope.id);
    store.contexts.delete(scope.id);
}

function create_scope_handle(store: RuntimeStore, name: string, key: string, parent: RuntimeOwner | null = null): Scope {
    return create_scope(store, name, key, parent ? require_scope(store, parent) : null);
}

function get_state_record<T>(store: RuntimeStore, owner: RuntimeOwner, key: string, initial: T): StateHandle<T> | undefined {
    const scope = require_scope(store, owner);
    if (scope.disposed) return undefined;
    const existing = scope.states.get(key) as StateHandle<T> | undefined;
    if (existing) return existing;
    const state = create_state(store, scope, key, initial);
    scope.states.set(key, state);
    scope.resources.add(state);
    return state;
}

function get_state<T>(store: RuntimeStore, owner: RuntimeOwner, key: string, initial: T): T {
    const state = get_state_record(store, owner, key, initial);
    return state ? state_get(store, state) : undefined as T;
}

function set_state<T>(store: RuntimeStore, owner: RuntimeOwner, key: string, next: T): void {
    const state = get_state_record(store, owner, key, next);
    if (state) state_set(store, state, next);
}

function ref(store: RuntimeStore, owner: RuntimeOwner, node: UiNode, key: string): UiNode {
    if (!key.trim()) throw new TypeError("ref key must not be empty");
    const scope = resolve_scope(store, owner);
    if (!scope || scope.disposed) return node;
    scope.refCleanups.get(key)?.();
    scope.refs.set(key, node);
    const cleanup = (): void => {
        if (scope.refs.get(key) !== node) return;
        scope.refs.delete(key);
        scope.refCleanups.delete(key);
    };
    scope.refCleanups.set(key, cleanup);
    scope_cleanup(scope, cleanup);
    return node;
}

function get_ref(store: RuntimeStore, owner: RuntimeOwner, key: string): UiNode | undefined {
    const scope = resolve_scope(store, owner);
    return scope && !scope.disposed ? scope.refs.get(key) : undefined;
}

function get_each_item(store: RuntimeStore, owner: RuntimeOwner): unknown {
    const scope = resolve_scope(store, owner);
    return scope && !scope.disposed ? get_state(store, scope, each_item_key, undefined) : undefined;
}

function get_each_index(store: RuntimeStore, owner: RuntimeOwner): number | undefined {
    const value = get_each_item_value(store, owner, each_index_key);
    return typeof value === "number" ? value : undefined;
}

function get_each_item_value(store: RuntimeStore, owner: RuntimeOwner, key: string): unknown {
    const scope = resolve_scope(store, owner);
    return scope && !scope.disposed ? get_state(store, scope, key, undefined) : undefined;
}

function normalize_each_key(value: unknown): string {
    const type = typeof value;
    if (type !== "string" && type !== "number" && type !== "boolean" && type !== "bigint") {
        throw new TypeError("each keys must be primitive values");
    }
    return `${type}:${String(value)}`;
}

function each(store: RuntimeStore, owner: RuntimeOwner, container: UiNode, itemsFunction: string, keyFunction: string, renderFunction: string): EffectHandle {
    const scope = require_scope(store, owner);
    const bindingId = store.nextBindingId++;
    const records = new Map<string, { key: string; scope: Scope; root: UiNode }>();
    return effect(store, scope, `each:${bindingId}`, () => {
        const items = call_do<unknown>(store, itemsFunction, scope);
        if (!Array.isArray(items)) throw new TypeError("each source must return an array");
        const descriptors: Array<{ key: string; item: unknown; index: number }> = [];
        const seen = new Set<string>();
        for (let index = 0; index < items.length; index += 1) {
            const item = items[index];
            const key = normalize_each_key(call_do(store, keyFunction, scope, item, index));
            if (seen.has(key)) throw new Error(`duplicate each key: ${key}`);
            seen.add(key);
            descriptors.push({ key, item, index });
        }
        const nextRecords = new Map<string, { key: string; scope: Scope; root: UiNode }>();
        const nextRoots: UiNode[] = [];
        for (const descriptor of descriptors) {
            const existing = records.get(descriptor.key);
            const itemScope = existing?.scope ?? create_scope_handle(store, `each:${bindingId}`, `each:${bindingId}:${descriptor.key}`, scope);
            set_state(store, itemScope, each_item_key, descriptor.item);
            set_state(store, itemScope, each_index_key, descriptor.index);
            let root = existing?.root;
            if (!root) {
                try {
                    root = call_do<UiNode>(store, renderFunction, itemScope) as UiNode;
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
        for (const [key, record] of records) if (!nextRecords.has(key)) scope_dispose(store, record.scope);
        records.clear();
        for (const [key, record] of nextRecords) records.set(key, record);
        container.append(...nextRoots);
    });
}

function show(store: RuntimeStore, owner: RuntimeOwner, container: UiNode, conditionFunction: string, thenFunction: string, elseFunction: string | null = null): EffectHandle {
    const scope = require_scope(store, owner);
    const bindingId = store.nextBindingId++;
    let active: { name: string; scope: Scope; root: UiNode } | null = null;
    return effect(store, scope, `show:${bindingId}`, () => {
        const condition = call_do(store, conditionFunction, scope);
        if (typeof condition !== "boolean") throw new TypeError("if condition must return a boolean");
        const branchName = condition ? "then" : "else";
        if (active?.name === branchName) return;
        if (active) scope_dispose(store, active.scope);
        container.replaceChildren();
        active = null;
        const renderFunction = condition ? thenFunction : elseFunction;
        if (!renderFunction) return;
        const branchScope = create_scope_handle(store, `show:${bindingId}`, `show:${bindingId}:${branchName}`, scope);
        try {
            const root = call_do<UiNode>(store, renderFunction, branchScope) as UiNode;
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

function effect(store: RuntimeStore, owner: RuntimeOwner, keyOrFn: string | (() => unknown), maybeFn?: () => unknown): EffectHandle {
    const scope = require_scope(store, owner);
    const key = typeof keyOrFn === "function" ? `effect:${store.nextBindingId++}` : keyOrFn;
    const fn = typeof keyOrFn === "function" ? keyOrFn : maybeFn;
    if (!fn) throw new TypeError("effect requires a callback");
    const existing = scope.effects.get(key);
    if (existing) return existing;
    const node = create_effect(scope, key, fn);
    scope.effects.set(key, node);
    scope.resources.add(node);
    effect_run(store, node);
    return node;
}

function call_do<T>(store: RuntimeStore, name: string, owner: RuntimeOwner, ...args: unknown[]): T | undefined {
    const scope = resolve_scope(store, owner);
    if (!scope || scope.disposed) return undefined;
    const fn = store.doModule?.[name];
    if (!fn) throw new Error(`missing do function: ${name}`);
    return fn(scope.context, ...args) as T;
}

function bind_value<T>(store: RuntimeStore, owner: RuntimeOwner, read: () => T, apply: (value: T) => void): EffectHandle {
    const scope = require_scope(store, owner);
    return effect(store, scope, `binding:${store.nextBindingId++}`, () => {
        if (!scope.disposed) apply(read());
    });
}

function bind_derived<T>(store: RuntimeStore, owner: RuntimeOwner, node: UiNode, functionName: string, apply: (node: UiNode, value: T) => void): EffectHandle {
    const scope = require_scope(store, owner);
    const derived = scope_computed(scope, `derived:${store.nextBindingId++}`, () => call_do<T>(store, functionName, scope) as T);
    return bind_value(store, scope, () => computed_get(store, derived), (value) => apply(node, value));
}

function on_event(store: RuntimeStore, owner: RuntimeOwner, node: UiNode, type: string, functionName: string): (...args: any[]) => unknown {
    const scope = require_scope(store, owner);
    const listener = (): void => {
        if (!scope.disposed) batch(store, () => call_do(store, functionName, scope));
    };
    node.addEventListener(type, listener);
    scope_cleanup(scope, () => node.removeEventListener(type, listener));
    return listener;
}

function mount(store: RuntimeStore, componentName: string, key: string, parent: RuntimeOwner | null = null): Scope {
    const scope = create_scope_handle(store, componentName, key, parent);
    scope.root = call_do<UiNode>(store, componentName, scope) as UiNode;
    return scope;
}

function dispose_scope_owner(store: RuntimeStore, owner: RuntimeOwner): void {
    const scope = resolve_scope(store, owner);
    if (scope) scope_dispose(store, scope);
}

function on_cleanup(store: RuntimeStore, owner: RuntimeOwner, fn: () => unknown): void {
    const scope = resolve_scope(store, owner);
    if (scope) scope_cleanup(scope, fn);
}

function create_element(store: RuntimeStore, tag: string): UiNode {
    return store.document.createElement(tag) as UiNode;
}

function append(parent: UiNode, ...children: UiNode[]): UiNode {
    parent.append(...children);
    return parent;
}

function bind_text(store: RuntimeStore, owner: RuntimeOwner, node: UiNode, functionName: string): EffectHandle {
    return bind_derived(store, owner, node, functionName, (target, value) => {
        const next = value == null ? null : String(value);
        if (target.textContent !== next) target.textContent = next;
    });
}

function bind_attr(store: RuntimeStore, owner: RuntimeOwner, node: UiNode, name: string, functionName: string): EffectHandle {
    return bind_derived(store, owner, node, functionName, (target, value) => {
        const record = target as unknown as Record<string, unknown>;
        if (record[name] !== value) record[name] = value;
    });
}

function bind_style(store: RuntimeStore, owner: RuntimeOwner, node: UiNode, name: string, functionName: string): EffectHandle {
    return bind_derived(store, owner, node, functionName, (target, value) => {
        const next = String(value);
        if (target.style[name] !== next) target.style[name] = next;
    });
}

function create_runtime_api(store: RuntimeStore): Runtime {
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
        setModule: (nextModule) => { store.doModule = nextModule; },
        getScope: (id) => store.scopes.get(id),
    };
}

export function createRuntime({ document, module = null }: RuntimeOptions = {}): Runtime {
    if (!document || typeof document.createElement !== "function") {
        throw new TypeError("ui runtime requires a document adapter");
    }
    return create_runtime_api(create_runtime_store(document, module));
}
