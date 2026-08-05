export interface HostEventTarget {
    addEventListener(type: string, listener: (event: unknown) => void): void;
    removeEventListener(type: string, listener: (event: unknown) => void): void;
}

export interface StaticCallbackDispatcher {
    invoke(signatureId: number, callbackId: number, event: unknown): number;
}

export interface EventPumpDispatcher {
    drain(instanceId: number): void;
}

declare const subscription_brand: unique symbol;

export interface HostSubscription {
    readonly [subscription_brand]: void;
}

export interface EventPump {
    enqueue(event: unknown): void;
    nextEvent(): unknown | undefined;
    dispose(): void;
}

export interface DoHostInstance {
    subscribe(
        target: HostEventTarget,
        eventType: string,
        signatureId: number,
        callbackId: number
    ): HostSubscription;
    unsubscribe(subscription: HostSubscription): void;
    createEventPump(instanceId: number, dispatcher: EventPumpDispatcher): EventPump;
    dispose(): void;
}

interface LiveSubscription {
    target: HostEventTarget;
    eventType: string;
    listener: (event: unknown) => void;
    generation: number;
    live: boolean;
}

interface HostStore {
    dispatcher: StaticCallbackDispatcher;
    disposed: boolean;
    generation: number;
    subscriptions: Map<HostSubscription, LiveSubscription>;
    pumps: Set<EventPumpStore>;
}

interface EventPumpStore {
    instanceId: number;
    dispatcher: EventPumpDispatcher;
    events: unknown[];
    disposed: boolean;
    scheduled: boolean;
    draining: boolean;
}

function unsubscribe(store: HostStore, subscription: HostSubscription): void {
    const entry = store.subscriptions.get(subscription);
    if (!entry || !entry.live) return;

    // Mark inactive before asking the host to detach, so a late host call cannot dispatch.
    entry.live = false;
    entry.target.removeEventListener(entry.eventType, entry.listener);
    store.subscriptions.delete(subscription);
}

function subscribe(
    store: HostStore,
    target: HostEventTarget,
    eventType: string,
    signatureId: number,
    callbackId: number
): HostSubscription {
    if (store.disposed) throw new Error("do host instance is disposed");

    const subscription = Object.freeze({}) as HostSubscription;
    const entry: LiveSubscription = {
        target,
        eventType,
        generation: store.generation,
        live: true,
        listener: (event) => {
            if (store.disposed || !entry.live || entry.generation !== store.generation) return;
            store.dispatcher.invoke(signatureId, callbackId, event);
        },
    };
    store.subscriptions.set(subscription, entry);
    target.addEventListener(eventType, entry.listener);
    return subscription;
}

function schedulePump(store: HostStore, pump: EventPumpStore): void {
    if (store.disposed || pump.disposed || pump.scheduled || pump.draining || pump.events.length === 0) return;

    pump.scheduled = true;
    queueMicrotask(() => {
        pump.scheduled = false;
        if (store.disposed || pump.disposed || pump.events.length === 0) return;

        pump.draining = true;
        try {
            pump.dispatcher.drain(pump.instanceId);
        } finally {
            pump.draining = false;
            schedulePump(store, pump);
        }
    });
}

function disposePump(store: HostStore, pump: EventPumpStore): void {
    if (pump.disposed) return;

    pump.disposed = true;
    pump.events.length = 0;
    store.pumps.delete(pump);
}

function createEventPump(store: HostStore, instanceId: number, dispatcher: EventPumpDispatcher): EventPump {
    if (store.disposed) throw new Error("do host instance is disposed");

    const pump: EventPumpStore = {
        instanceId,
        dispatcher,
        events: [],
        disposed: false,
        scheduled: false,
        draining: false,
    };
    store.pumps.add(pump);
    return {
        enqueue: (event) => {
            if (store.disposed || pump.disposed) return;
            pump.events.push(event);
            schedulePump(store, pump);
        },
        nextEvent: () => {
            if (store.disposed || pump.disposed) return undefined;
            return pump.events.shift();
        },
        dispose: () => disposePump(store, pump),
    };
}

function dispose(store: HostStore): void {
    if (store.disposed) return;

    store.disposed = true;
    store.generation += 1;
    for (const subscription of [...store.subscriptions.keys()]) unsubscribe(store, subscription);
    for (const pump of [...store.pumps]) disposePump(store, pump);
}

export function createHostInstance(dispatcher: StaticCallbackDispatcher): DoHostInstance {
    const store: HostStore = {
        dispatcher,
        disposed: false,
        generation: 1,
        subscriptions: new Map(),
        pumps: new Set(),
    };
    return {
        subscribe: (target, eventType, signatureId, callbackId) =>
            subscribe(store, target, eventType, signatureId, callbackId),
        unsubscribe: (subscription) => unsubscribe(store, subscription),
        createEventPump: (instanceId, eventDispatcher) => createEventPump(store, instanceId, eventDispatcher),
        dispose: () => dispose(store),
    };
}
