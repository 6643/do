import { type Allocation } from "./arc_allocator";
import { ArcObjectRuntime, type LayoutEntry, type ObjectHandle } from "./arc_object_runtime";

export const LIST_U32_TYPE = 100;

const LIST_U32_LAYOUT: LayoutEntry = {
    typeId: LIST_U32_TYPE,
    name: "List<u32>",
    managedFieldNames: [],
};

type ListRecord = {
    items: number[];
    cap: number;
};

export class ArcCowRuntime {
    private runtime = new ArcObjectRuntime([LIST_U32_LAYOUT]);
    private lists = new Map<ObjectHandle, ListRecord>();

    allocList(typeId: number, items: number[], cap = items.length): ObjectHandle {
        if (cap < items.length) {
            throw new Error("list cap smaller than len");
        }

        const handle = this.runtime.allocObject(typeId, this.listPayloadBytes(cap));
        this.lists.set(handle, {
            items: [...items],
            cap,
        });
        return handle;
    }

    share(handle: ObjectHandle): ObjectHandle {
        this.expectList(handle);
        this.runtime.inc(handle);
        return handle;
    }

    setListItem(handle: ObjectHandle, index: number, value: number): ObjectHandle {
        const list = this.expectList(handle);
        if (index < 0 || index >= list.items.length) {
            throw new Error("list index out of bounds");
        }

        const writable = this.ensureUnique(handle, list.items.length);
        const writableList = this.expectList(writable);
        writableList.items[index] = value;
        return writable;
    }

    putListItem(handle: ObjectHandle, value: number): ObjectHandle {
        const list = this.expectList(handle);
        const nextLen = list.items.length + 1;
        const writable = this.ensureUnique(handle, nextLen);
        const writableList = this.expectList(writable);
        writableList.items.push(value);
        return writable;
    }

    listItems(handle: ObjectHandle): number[] {
        return [...this.expectList(handle).items];
    }

    rcOf(handle: ObjectHandle): number {
        return this.runtime.rcOf(handle);
    }

    isAlive(handle: ObjectHandle): boolean {
        return this.runtime.isAlive(handle);
    }

    allocationOf(handle: ObjectHandle): Allocation {
        return this.runtime.allocationOf(handle);
    }

    private ensureUnique(handle: ObjectHandle, requiredLen: number): ObjectHandle {
        const list = this.expectList(handle);
        const needsClone = this.runtime.rcOf(handle) > 1;
        const needsGrow = requiredLen > list.cap;

        if (!needsClone && !needsGrow) return handle;

        const nextCap = needsGrow ? Math.max(requiredLen, list.cap * 2, 1) : list.cap;
        const next = this.allocList(LIST_U32_TYPE, list.items, nextCap);
        this.runtime.dec(handle);
        if (!this.runtime.isAlive(handle)) {
            this.lists.delete(handle);
        }
        return next;
    }

    private expectList(handle: ObjectHandle): ListRecord {
        if (!this.runtime.isAlive(handle)) {
            throw new Error(`unknown or released list ${handle}`);
        }

        const list = this.lists.get(handle);
        if (list === undefined) throw new Error(`missing list payload ${handle}`);
        return list;
    }

    private listPayloadBytes(cap: number): number {
        return 8 + cap * 4;
    }
}
