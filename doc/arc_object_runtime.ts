import { ArcAllocator, type Allocation } from "./arc_allocator";

export type ObjectHandle = number;

export type LayoutEntry = {
    typeId: number;
    name: string;
    managedFieldNames: string[];
};

type ObjectRecord = {
    allocation: Allocation;
    rc: number;
    typeId: number;
    managedChildren: ObjectHandle[];
};

export class ArcObjectRuntime {
    private nextHandle = 1;
    private objects = new Map<ObjectHandle, ObjectRecord>();
    private layouts = new Map<number, LayoutEntry>();

    readonly allocator: ArcAllocator;

    constructor(layouts: LayoutEntry[], allocator = new ArcAllocator()) {
        this.allocator = allocator;

        for (const layout of layouts) {
            if (this.layouts.has(layout.typeId)) {
                throw new Error(`duplicate layout type_id ${layout.typeId}`);
            }
            this.layouts.set(layout.typeId, layout);
        }
    }

    allocObject(typeId: number, payloadBytes: number, managedChildren: ObjectHandle[] = []): ObjectHandle {
        const layout = this.expectLayout(typeId);
        if (layout.managedFieldNames.length !== managedChildren.length) {
            throw new Error(`managed field count mismatch for ${layout.name}`);
        }

        for (const child of managedChildren) {
            this.expectObject(child);
        }

        const handle = this.nextHandle;
        this.nextHandle += 1;

        this.objects.set(handle, {
            allocation: this.allocator.alloc(payloadBytes),
            rc: 1,
            typeId,
            managedChildren: [...managedChildren],
        });

        return handle;
    }

    inc(handle: ObjectHandle) {
        const object = this.expectObject(handle);
        object.rc += 1;
    }

    dec(handle: ObjectHandle) {
        const releaseStack = [handle];

        while (releaseStack.length > 0) {
            const current = releaseStack.pop();
            if (current === undefined) continue;

            const object = this.expectObject(current);
            object.rc -= 1;

            if (object.rc < 0) {
                throw new Error(`released object ${current}`);
            }
            if (object.rc > 0) continue;

            this.objects.delete(current);
            this.allocator.free(object.allocation);

            for (const child of object.managedChildren) {
                releaseStack.push(child);
            }
        }
    }

    rcOf(handle: ObjectHandle): number {
        return this.expectObject(handle).rc;
    }

    isAlive(handle: ObjectHandle): boolean {
        return this.objects.has(handle);
    }

    liveCount(): number {
        return this.objects.size;
    }

    allocationOf(handle: ObjectHandle): Allocation {
        return this.expectObject(handle).allocation;
    }

    private expectObject(handle: ObjectHandle): ObjectRecord {
        const object = this.objects.get(handle);
        if (object === undefined) throw new Error(`unknown or released object ${handle}`);
        return object;
    }

    private expectLayout(typeId: number): LayoutEntry {
        const layout = this.layouts.get(typeId);
        if (layout === undefined) throw new Error(`unknown type_id ${typeId}`);
        return layout;
    }
}
