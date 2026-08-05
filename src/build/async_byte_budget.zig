const std = @import("std");

pub const Error = error{
    ByteSizeOverflow,
    ByteBudgetExceeded,
    ByteBudgetLimitBelowUsage,
    ReservationAlreadyFinalized,
    AllocationAlreadyReleased,
    AllocationInvariantViolation,
};

pub const ByteBudget = struct {
    limit: u64,
    committed: u64 = 0,
    reserved: u64 = 0,

    pub fn init(limit: u64) ByteBudget {
        return .{ .limit = limit };
    }

    pub fn configure(self: *ByteBudget, limit: u64) Error!void {
        const accounted = try checked_add(self.committed, self.reserved);
        if (limit < accounted) return error.ByteBudgetLimitBelowUsage;
        self.limit = limit;
    }

    pub fn reserve(self: *ByteBudget, bytes: u64) Error!Reservation {
        const accounted = try checked_add(self.committed, self.reserved);
        const next = try checked_add(accounted, bytes);
        if (next > self.limit) return error.ByteBudgetExceeded;

        self.reserved += bytes;
        return .{ .budget = self, .bytes = bytes };
    }

    pub fn limit_bytes(self: *const ByteBudget) u64 {
        return self.limit;
    }

    pub fn committed_bytes(self: *const ByteBudget) u64 {
        return self.committed;
    }

    pub fn reserved_bytes(self: *const ByteBudget) u64 {
        return self.reserved;
    }

    pub fn available_bytes(self: *const ByteBudget) u64 {
        const accounted = self.committed + self.reserved;
        return self.limit - accounted;
    }
};

pub const Reservation = struct {
    budget: *ByteBudget,
    bytes: u64,
    state: State = .active,

    const State = enum { active, committed, rolled_back };

    pub fn commit(self: *Reservation) Error!Allocation {
        if (self.state != .active) return error.ReservationAlreadyFinalized;
        if (self.budget.reserved < self.bytes) return error.AllocationInvariantViolation;

        self.budget.reserved -= self.bytes;
        self.budget.committed = checked_add(self.budget.committed, self.bytes) catch {
            self.budget.reserved += self.bytes;
            return error.ByteSizeOverflow;
        };
        self.state = .committed;
        return .{ .budget = self.budget, .bytes = self.bytes };
    }

    pub fn rollback(self: *Reservation) Error!void {
        if (self.state != .active) return error.ReservationAlreadyFinalized;
        if (self.budget.reserved < self.bytes) return error.AllocationInvariantViolation;
        self.budget.reserved -= self.bytes;
        self.state = .rolled_back;
    }
};

pub const Allocation = struct {
    budget: *ByteBudget,
    bytes: u64,
    released: bool = false,
    owner: ?*anyopaque = null,

    pub fn release(self: *Allocation) Error!void {
        if (self.released) return error.AllocationAlreadyReleased;
        if (self.budget.committed < self.bytes) return error.AllocationInvariantViolation;
        self.budget.committed -= self.bytes;
        self.released = true;
    }
};

pub const FixedAllocationPool = struct {
    budget: *ByteBudget,
    allocation_bytes: u64,
    active_allocations: u64 = 0,

    pub fn init(budget: *ByteBudget, allocation_bytes: u64) FixedAllocationPool {
        return .{ .budget = budget, .allocation_bytes = allocation_bytes };
    }

    pub fn live_count(self: *const FixedAllocationPool) u64 {
        return self.active_allocations;
    }

    pub fn acquire(self: *FixedAllocationPool) Error!Allocation {
        var reservation = try self.budget.reserve(self.allocation_bytes);
        var allocation = reservation.commit() catch |err| {
            _ = reservation.rollback() catch {};
            return err;
        };
        allocation.owner = @ptrCast(self);
        self.active_allocations = std.math.add(u64, self.active_allocations, 1) catch {
            try allocation.release();
            return error.ByteSizeOverflow;
        };
        return allocation;
    }

    pub fn release(self: *FixedAllocationPool, allocation: *Allocation) Error!void {
        if (self.active_allocations == 0) return error.AllocationInvariantViolation;
        if (allocation.owner == null or allocation.owner.? != @as(*anyopaque, @ptrCast(self))) {
            return error.AllocationInvariantViolation;
        }
        try allocation.release();
        self.active_allocations -= 1;
    }
};

const VariableBackingKind = enum { text, list };

const VariableAllocationPool = struct {
    budget: *ByteBudget,
    header_bytes: u64,
    element_bytes: u64,
    kind: VariableBackingKind,
    active_allocations: u64 = 0,

    fn init(
        budget: *ByteBudget,
        header_bytes: u64,
        element_bytes: u64,
        kind: VariableBackingKind,
    ) VariableAllocationPool {
        return .{
            .budget = budget,
            .header_bytes = header_bytes,
            .element_bytes = element_bytes,
            .kind = kind,
        };
    }

    fn live_count(self: *const VariableAllocationPool) u64 {
        return self.active_allocations;
    }

    fn bytes_for(self: *const VariableAllocationPool, extent: u64) Error!u64 {
        return switch (self.kind) {
            .text => bytes_for_text_backing(self.header_bytes, extent),
            .list => bytes_for_list_backing(self.header_bytes, self.element_bytes, extent),
        };
    }

    fn acquire(self: *VariableAllocationPool, extent: u64) Error!Allocation {
        const bytes = try self.bytes_for(extent);
        var reservation = try self.budget.reserve(bytes);
        var allocation = reservation.commit() catch |err| {
            _ = reservation.rollback() catch {};
            return err;
        };
        allocation.owner = @ptrCast(self);
        self.active_allocations = std.math.add(u64, self.active_allocations, 1) catch {
            try allocation.release();
            return error.ByteSizeOverflow;
        };
        return allocation;
    }

    fn release(self: *VariableAllocationPool, allocation: *Allocation) Error!void {
        if (self.active_allocations == 0) return error.AllocationInvariantViolation;
        if (allocation.owner == null or allocation.owner.? != @as(*anyopaque, @ptrCast(self))) {
            return error.AllocationInvariantViolation;
        }
        try allocation.release();
        self.active_allocations -= 1;
    }
};

pub const TextBackingPool = struct {
    pool: VariableAllocationPool,

    pub fn init(budget: *ByteBudget, header_bytes: u64) TextBackingPool {
        return .{ .pool = VariableAllocationPool.init(budget, header_bytes, 1, .text) };
    }

    pub fn live_backings(self: *const TextBackingPool) u64 {
        return self.pool.live_count();
    }

    pub fn acquire(self: *TextBackingPool, utf8_bytes: u64) Error!Allocation {
        return self.pool.acquire(utf8_bytes);
    }

    pub fn release(self: *TextBackingPool, allocation: *Allocation) Error!void {
        return self.pool.release(allocation);
    }
};

pub const ListBackingPool = struct {
    pool: VariableAllocationPool,

    pub fn init(budget: *ByteBudget, header_bytes: u64, element_bytes: u64) ListBackingPool {
        return .{ .pool = VariableAllocationPool.init(budget, header_bytes, element_bytes, .list) };
    }

    pub fn live_backings(self: *const ListBackingPool) u64 {
        return self.pool.live_count();
    }

    pub fn acquire(self: *ListBackingPool, capacity: u64) Error!Allocation {
        return self.pool.acquire(capacity);
    }

    pub fn release(self: *ListBackingPool, allocation: *Allocation) Error!void {
        return self.pool.release(allocation);
    }
};

pub const CanonicalBufferPool = struct {
    pool: FixedAllocationPool,

    pub fn init(budget: *ByteBudget, header_bytes: u64, payload_bytes: u64) Error!CanonicalBufferPool {
        const bytes = try bytes_for_canonical_buffer(header_bytes, payload_bytes);
        return .{ .pool = FixedAllocationPool.init(budget, bytes) };
    }

    pub fn live_buffers(self: *const CanonicalBufferPool) u64 {
        return self.pool.live_count();
    }

    pub fn acquire(self: *CanonicalBufferPool) Error!Allocation {
        return self.pool.acquire();
    }

    pub fn release(self: *CanonicalBufferPool, allocation: *Allocation) Error!void {
        return self.pool.release(allocation);
    }
};

pub fn bytes_for_task_frame(header_bytes: u64, payload_bytes: u64) Error!u64 {
    return checked_add(header_bytes, payload_bytes);
}

pub fn bytes_for_queue_slots(slot_bytes: u64, slots: u64) Error!u64 {
    return checked_mul(slot_bytes, slots);
}

pub fn bytes_for_text_backing(header_bytes: u64, utf8_bytes: u64) Error!u64 {
    return checked_add(header_bytes, utf8_bytes);
}

pub fn bytes_for_list_backing(header_bytes: u64, elem_bytes: u64, capacity: u64) Error!u64 {
    return checked_add(header_bytes, try checked_mul(elem_bytes, capacity));
}

pub fn bytes_for_canonical_buffer(header_bytes: u64, payload_bytes: u64) Error!u64 {
    return checked_add(header_bytes, payload_bytes);
}

fn checked_add(left: u64, right: u64) Error!u64 {
    return std.math.add(u64, left, right) catch error.ByteSizeOverflow;
}

fn checked_mul(left: u64, right: u64) Error!u64 {
    return std.math.mul(u64, left, right) catch error.ByteSizeOverflow;
}
