// @ts-check

/**
 * @typedef {Object} UiNode
 * @property {string | null} textContent
 * @property {string} className
 * @property {Record<string, string>} style
 * @property {(type: string, listener: (...args: any[]) => unknown, options?: unknown) => void} addEventListener
 * @property {(type: string, listener: (...args: any[]) => unknown, options?: unknown) => void} removeEventListener
 * @property {(...children: UiNode[]) => void} append
 * @property {() => void} remove
 */

/**
 * The document adapter is intentionally smaller than the browser `Document`.
 * The runtime only needs element creation; the returned value is checked at
 * the binding boundary as a `UiNode`.
 *
 * @typedef {Object} DocumentAdapter
 * @property {(tag: string) => unknown} createElement
 */

/**
 * @template T
 * @typedef {Object} SignalHandle
 * @property {number} id
 * @property {boolean} disposed
 * @property {Set<ReactiveSubscriber>} subscribers
 * @property {() => T} get
 * @property {(next: T) => void} set
 * @property {() => void} dispose
 */

/**
 * @typedef {Object} ReactiveSubscriber
 * @property {boolean} disposed
 * @property {Set<ReactiveSource>} dependencies
 * @property {(source: ReactiveSource) => void} track
 * @property {() => void} invalidate
 * @property {() => void} dispose
 */

/** @typedef {SignalHandle<any> | ComputedHandle<any>} ReactiveSource */

/**
 * @template T
 * @typedef {Object} ComputedHandle
 * @property {boolean} disposed
 * @property {Set<ReactiveSource>} dependencies
 * @property {Set<ReactiveSubscriber>} subscribers
 * @property {() => T} get
 * @property {() => void} invalidate
 * @property {() => void} dispose
 */

/**
 * @typedef {Object} EffectHandle
 * @property {boolean} disposed
 * @property {Set<ReactiveSource>} dependencies
 * @property {Set<ReactiveSubscriber>} subscribers
 * @property {() => void} run
 * @property {() => void} invalidate
 * @property {() => void} dispose
 */

/** @typedef {SignalHandle<any> | ComputedHandle<any> | EffectHandle} ReactiveResource */

/**
 * @typedef {Object} Scope
 * @property {number} id
 * @property {string} name
 * @property {string} key
 * @property {Scope | null} parent
 * @property {Map<string, Scope>} children
 * @property {Map<string, any>} states
 * @property {Map<string, any>} derived
 * @property {Map<string, any>} effects
 * @property {Set<any>} resources
 * @property {Array<() => unknown>} cleanups
 * @property {Record<string, unknown>} meta
 * @property {UiNode | null} root
 * @property {boolean} disposed
 * @property {<T>(key: string, initial: T) => SignalHandle<T>} signal
 * @property {<T>(key: string, fn: () => T) => ComputedHandle<T>} computed
 * @property {(fn: () => unknown) => void} cleanup
 * @property {() => void} dispose
 */

/** @typedef {(scope: Scope, ...args: unknown[]) => unknown} DoFunction */
/** @typedef {Record<string, DoFunction>} DoModule */

/**
 * @typedef {Object} RuntimeOptions
 * @property {DocumentAdapter} [document]
 * @property {DoModule | null} [module]
 */

/**
 * @typedef {Object} Runtime
 * @property {<T>(fn: () => T) => T} batch
 * @property {<T>(name: string, scope: Scope, ...args: unknown[]) => T | undefined} callDo
 * @property {(tag: string) => UiNode} createElement
 * @property {(name: string, key: string, parent?: Scope | null) => Scope} createScope
 * @property {(scope: Scope) => void} disposeScope
 * @property {(scope: Scope, keyOrFn: string | (() => unknown), maybeFn?: () => unknown) => EffectHandle} effect
 * @property {(componentName: string, key: string, parent?: Scope | null) => Scope} mount
 * @property {(scope: Scope, fn: () => unknown) => void} onCleanup
 * @property {(scope: Scope, node: UiNode, functionName: string) => (...args: any[]) => unknown} onClick
 * @property {(parent: UiNode, ...children: UiNode[]) => UiNode} append
 * @property {(scope: Scope, node: UiNode, functionName: string) => EffectHandle} bindText
 * @property {(scope: Scope, node: UiNode, name: string, functionName: string) => EffectHandle} bindAttr
 * @property {(scope: Scope, node: UiNode, name: string, functionName: string) => EffectHandle} bindStyle
 * @property {(nextModule: DoModule | null) => void} setModule
 * @property {(id: number) => Scope | undefined} getScope
 */

/**
 * @param {RuntimeOptions} [options]
 * @returns {Runtime}
 */
export function createRuntime({ document, module = null } = {}) {
    if (!document || typeof document.createElement !== "function") {
        throw new TypeError("ui runtime requires a document adapter");
    }

    let nextScopeId = 1;
    let nextSignalId = 1;
    let nextBindingId = 1;
    /** @type {ReactiveNode | null} */
    let activeObserver = null;
    let batchDepth = 0;
    let flushing = false;
    /** @type {Set<ReactiveNode>} */
    const pending = new Set();
    /** @type {Map<number, Scope>} */
    const scopes = new Map();
    let doModule = module;

    /** @param {ReactiveNode} node */
    function schedule(node) {
        if (node.disposed) return;
        pending.add(node);
        if (batchDepth === 0) flush();
    }

    function flush() {
        if (flushing) return;
        flushing = true;
        try {
            while (pending.size > 0) {
                const current = [...pending];
                pending.clear();
                for (const node of current) {
                    if (!node.disposed) node.runOrInvalidate();
                }
            }
        } finally {
            flushing = false;
        }
    }

    /**
     * @template T
     * @param {() => T} fn
     * @returns {T}
     */
    function batch(fn) {
        batchDepth += 1;
        try {
            return fn();
        } finally {
            batchDepth -= 1;
            if (batchDepth === 0) flush();
        }
    }

    class ReactiveNode {
        /** @param {Scope} owner */
        constructor(owner) {
            this.owner = owner;
            /** @type {Set<ReactiveSource>} */
            this.dependencies = new Set();
            /** @type {Set<ReactiveSubscriber>} */
            this.subscribers = new Set();
            this.disposed = false;
        }

        /** @param {ReactiveSource} source */
        track(source) {
            if (this.disposed || source.disposed) return;
            if (this.dependencies.has(source)) return;
            this.dependencies.add(source);
            source.subscribers.add(this);
        }

        disconnectSources() {
            for (const source of this.dependencies) {
                source.subscribers.delete(this);
            }
            this.dependencies.clear();
        }

        disconnectSubscribers() {
            for (const subscriber of this.subscribers) {
                subscriber.dependencies.delete(
                    /** @type {ReactiveSource} */ (/** @type {unknown} */ (this))
                );
            }
            this.subscribers.clear();
        }

        invalidate() {}

        runOrInvalidate() {}

        dispose() {
            if (this.disposed) return;
            this.disposed = true;
            pending.delete(this);
            this.disconnectSources();
            this.disconnectSubscribers();
            this.owner?.resources.delete(
                /** @type {ReactiveResource} */ (/** @type {unknown} */ (this))
            );
        }
    }

    /** @template T */
    class Signal {
        /**
         * @param {Scope} owner
         * @param {string} key
         * @param {T} initial
         */
        constructor(owner, key, initial) {
            this.id = nextSignalId++;
            this.owner = owner;
            this.key = key;
            this.value = initial;
            this.version = 0;
            /** @type {Set<ReactiveSubscriber>} */
            this.subscribers = new Set();
            this.disposed = false;
        }

        /** @returns {T} */
        get() {
            if (this.disposed) return /** @type {T} */ (this.value);
            if (activeObserver) activeObserver.track(this);
            return /** @type {T} */ (this.value);
        }

        /** @param {T} next */
        set(next) {
            if (this.disposed || Object.is(this.value, next)) return;
            this.value = next;
            this.version += 1;
            for (const subscriber of [...this.subscribers]) {
                subscriber.invalidate();
            }
        }

        dispose() {
            if (this.disposed) return;
            this.disposed = true;
            for (const subscriber of this.subscribers) {
                subscriber.dependencies.delete(this);
            }
            this.subscribers.clear();
            this.owner.states.delete(this.key);
            this.owner.resources.delete(this);
        }
    }

    /** @template T */
    class Computed extends ReactiveNode {
        /**
         * @param {Scope} owner
         * @param {string} key
         * @param {() => T} fn
         */
        constructor(owner, key, fn) {
            super(owner);
            this.key = key;
            this.fn = fn;
            this.value = undefined;
            this.dirty = true;
        }

        /** @returns {T} */
        get() {
            if (this.disposed) return /** @type {T} */ (this.value);
            if (activeObserver) activeObserver.track(this);
            if (this.dirty) this.recompute();
            return /** @type {T} */ (this.value);
        }

        invalidate() {
            if (this.disposed || this.dirty) return;
            this.dirty = true;
            for (const subscriber of [...this.subscribers]) {
                subscriber.invalidate();
            }
        }

        recompute() {
            this.disconnectSources();
            const previous = activeObserver;
            activeObserver = this;
            try {
                this.value = this.fn();
                this.dirty = false;
            } finally {
                activeObserver = previous;
            }
        }

        runOrInvalidate() {
            this.invalidate();
        }
    }

    class Effect extends ReactiveNode {
        /**
         * @param {Scope} owner
         * @param {string} key
         * @param {() => unknown} fn
         */
        constructor(owner, key, fn) {
            super(owner);
            this.key = key;
            this.fn = fn;
        }

        run() {
            if (this.disposed) return;
            this.disconnectSources();
            const previous = activeObserver;
            activeObserver = this;
            try {
                this.fn();
            } finally {
                activeObserver = previous;
            }
        }

        invalidate() {
            schedule(this);
        }

        runOrInvalidate() {
            this.run();
        }
    }

    class ScopeRecord {
        /**
         * @param {string} name
         * @param {string} key
         * @param {Scope | null} parent
         */
        constructor(name, key, parent) {
            this.id = nextScopeId++;
            this.name = name;
            this.key = key;
            this.parent = parent;
            /** @type {Map<string, Scope>} */
            this.children = new Map();
            /** @type {Map<string, Signal<any>>} */
            this.states = new Map();
            /** @type {Map<string, Computed<any>>} */
            this.derived = new Map();
            /** @type {Map<string, Effect>} */
            this.effects = new Map();
            /** @type {Set<ReactiveResource>} */
            this.resources = new Set();
            /** @type {Array<() => unknown>} */
            this.cleanups = [];
            /** @type {Record<string, unknown>} */
            this.meta = Object.create(null);
            /** @type {UiNode | null} */
            this.root = null;
            this.disposed = false;

            if (parent) parent.children.set(key, this);
            scopes.set(this.id, this);
        }

        /**
         * @template T
         * @param {string} key
         * @param {T} initial
         * @returns {Signal<T>}
         */
        signal(key, initial) {
            if (this.disposed) return /** @type {Signal<T>} */ (this.states.get(key));
            const existing = this.states.get(key);
            if (existing) return existing;
            const signal = new Signal(this, key, initial);
            this.states.set(key, signal);
            this.resources.add(signal);
            return signal;
        }

        /**
         * @template T
         * @param {string} key
         * @param {() => T} fn
         * @returns {Computed<T>}
         */
        computed(key, fn) {
            if (this.disposed) return /** @type {Computed<T>} */ (this.derived.get(key));
            const existing = this.derived.get(key);
            if (existing) return existing;
            const computed = new Computed(this, key, fn);
            this.derived.set(key, computed);
            this.resources.add(computed);
            return computed;
        }

        /** @param {() => unknown} fn */
        cleanup(fn) {
            if (this.disposed) {
                fn();
                return;
            }
            this.cleanups.push(fn);
        }

        dispose() {
            if (this.disposed) return;
            this.disposed = true;

            for (const child of [...this.children.values()]) {
                child.dispose();
            }

            for (const resource of [...this.resources].reverse()) {
                resource.dispose();
            }

            for (const cleanup of [...this.cleanups].reverse()) {
                cleanup();
            }

            this.children.clear();
            this.states.clear();
            this.derived.clear();
            this.effects.clear();
            this.cleanups.length = 0;
            if (this.parent?.children.get(this.key) === this) {
                this.parent.children.delete(this.key);
            }
            scopes.delete(this.id);
        }
    }

    /**
     * @param {string} name
     * @param {string} key
     * @param {Scope | null} [parent]
     * @returns {Scope}
     */
    function createScope(name, key, parent = null) {
        return new ScopeRecord(name, key, parent);
    }

    /**
     * @param {Scope} scope
     * @param {string | (() => unknown)} keyOrFn
     * @param {() => unknown} [maybeFn]
     * @returns {Effect}
     */
    function effect(scope, keyOrFn, maybeFn) {
        const key = typeof keyOrFn === "function" ? `effect:${nextBindingId++}` : keyOrFn;
        const fn = typeof keyOrFn === "function" ? keyOrFn : maybeFn;
        if (typeof fn !== "function") {
            throw new TypeError("effect requires a callback");
        }
        const existing = scope.effects.get(key);
        if (existing) return existing;
        const node = new Effect(scope, key, fn);
        scope.effects.set(key, node);
        scope.resources.add(node);
        node.run();
        return node;
    }

    /**
     * @template T
     * @param {string} name
     * @param {Scope} scope
     * @param {...unknown} args
     * @returns {T | undefined}
     */
    function callDo(name, scope, ...args) {
        if (scope.disposed) return undefined;
        const fn = doModule?.[name];
        if (typeof fn !== "function") {
            throw new Error(`missing do function: ${name}`);
        }
        return /** @type {T} */ (fn(scope, ...args));
    }

    /**
     * @template T
     * @param {Scope} scope
     * @param {() => T} read
     * @param {(value: T) => void} apply
     * @returns {Effect}
     */
    function bindValue(scope, read, apply) {
        const key = `binding:${nextBindingId++}`;
        return effect(scope, key, () => {
            if (scope.disposed) return;
            apply(read());
        });
    }

    /**
     * @template T
     * @param {Scope} scope
     * @param {UiNode} node
     * @param {string} functionName
     * @param {(node: UiNode, value: T) => void} apply
     * @returns {Effect}
     */
    function bindDerived(scope, node, functionName, apply) {
        const derived = scope.computed(`derived:${nextBindingId++}`, () =>
            /** @type {T} */ (callDo(functionName, scope))
        );
        return bindValue(scope, () => derived.get(), (value) => apply(node, value));
    }

    /**
     * @param {Scope} scope
     * @param {UiNode} node
     * @param {string} type
     * @param {string} functionName
     * @returns {(...args: any[]) => unknown}
     */
    function onEvent(scope, node, type, functionName) {
        const listener = () => {
            if (scope.disposed) return;
            batch(() => callDo(functionName, scope));
        };
        node.addEventListener(type, listener);
        scope.cleanup(() => node.removeEventListener(type, listener));
        return listener;
    }

    /**
     * @param {string} componentName
     * @param {string} key
     * @param {Scope | null} [parent]
     * @returns {Scope}
     */
    function mount(componentName, key, parent = null) {
        const scope = createScope(componentName, key, parent);
        const root = /** @type {UiNode} */ (callDo(componentName, scope));
        scope.root = root;
        return scope;
    }

    /** @type {Runtime} */
    const runtime = {
        batch,
        callDo,
        createElement: (tag) => /** @type {UiNode} */ (document.createElement(tag)),
        createScope,
        disposeScope: (scope) => scope.dispose(),
        effect,
        mount,
        onCleanup: (scope, fn) => scope.cleanup(fn),
        onClick: (scope, node, functionName) => onEvent(scope, node, "click", functionName),
        append: (parent, ...children) => {
            parent.append(...children);
            return parent;
        },
        bindText: (scope, node, functionName) =>
            bindDerived(scope, node, functionName, (target, value) => {
                const nextValue = value == null ? value : String(value);
                if (target.textContent !== nextValue) target.textContent = nextValue;
            }),
        bindAttr: (scope, node, name, functionName) =>
            bindDerived(scope, node, functionName, (target, value) => {
                const targetRecord = /** @type {Record<string, unknown>} */ (target);
                if (targetRecord[name] !== value) targetRecord[name] = value;
            }),
        bindStyle: (scope, node, name, functionName) =>
            bindDerived(scope, node, functionName, (target, value) => {
                const nextValue = String(value);
                if (target.style[name] !== nextValue) target.style[name] = nextValue;
            }),
        setModule: (nextModule) => {
            doModule = nextModule;
        },
        getScope: (id) => scopes.get(id),
    };

    return runtime;
}
