const std = @import("std");
const abi_types = @import("wit_abi_types.zig");

const Allocator = std.mem.Allocator;

pub const LayoutError = error{
    WrongRootKind,
    InvalidAlignment,
    MisalignedOffset,
    OffsetOverflow,
    LayoutOutOfBounds,
    DuplicateField,
    DuplicateTag,
    DuplicateName,
    MissingPayloadMetadata,
    MissingIndirectMetadata,
    ScalarTypeMismatch,
    InvalidStride,
    InvalidCapacity,
    InvalidListLength,
    MissingOwnedSlot,
    BorrowedResource,
    NestedListElement,
    UnsupportedListElement,
    MissingListStorageActions,
};

pub const CoreWord = enum { i32, i64 };
pub const AllocationAction = enum { none, cabi_realloc };
pub const FreeAction = enum { none, cabi_realloc };

pub const PayloadMeasurement = struct {
    offset: u32,
    byte_size: u32,
    alignment: u32,
    core_type: CoreWord,
};

pub const VariantCaseMeasurement = struct {
    name: []const u8,
    tag: u32,
    payload_required: bool,
    payload: ?PayloadMeasurement,
};

pub const VariantMeasurement = struct {
    tag_offset: u32,
    payload_offset: u32,
    byte_size: u32,
    alignment: u32,
    cases: []const VariantCaseMeasurement,
};

pub const IndirectMeasurement = struct {
    core_words: []const CoreWord,
    allocation: AllocationAction,
    free: FreeAction,
};

pub const FieldMeasurement = struct {
    name: []const u8,
    offset: u32,
    byte_size: u32,
    alignment: u32,
    indirect: ?IndirectMeasurement,
};

pub const RecordMeasurement = struct {
    byte_size: u32,
    alignment: u32,
    fields: []const FieldMeasurement,
};

pub const ListLayoutMeasurement = struct {
    pointer_offset: u32,
    length_offset: u32,
    element_byte_size: u32,
    element_stride: u32,
    element_alignment: u32,
    ticket_offset: u32,
    capacity: u32,
    accepted_lengths: []const u32,
    allocation: AllocationAction,
    free: FreeAction,
};

pub const OwnedSlot = struct {
    index: u32,
    offset: u32,
};

pub const OwnedSlotIterator = struct {
    index: u32,
    length: u32,
    stride: u32,
    ticket_offset: u32,

    pub fn next(self: *OwnedSlotIterator) ?OwnedSlot {
        if (self.index >= self.length) return null;
        const slot: OwnedSlot = .{
            .index = self.index,
            .offset = @as(u32, @intCast(@as(u64, self.ticket_offset) + @as(u64, self.index) * self.stride)),
        };
        self.index += 1;
        return slot;
    }
};

pub const ListLayoutPlan = struct {
    allocator: Allocator,
    pointer_offset: u32,
    length_offset: u32,
    element_byte_size: u32,
    element_stride: u32,
    element_alignment: u32,
    ticket_offset: u32,
    capacity: u32,
    accepted_lengths: []u32,
    allocation: AllocationAction,
    free: FreeAction,

    pub fn init(
        allocator: Allocator,
        value: *const abi_types.AbiType,
        measured: ListLayoutMeasurement,
    ) (LayoutError || abi_types.AbiTypeError || Allocator.Error)!ListLayoutPlan {
        if (value.kind() != .list) return error.WrongRootKind;
        try value.validate();
        const element = value.list_element() orelse return error.UnsupportedListElement;
        if (element.kind() == .list) return error.NestedListElement;
        if (element.kind() != .record) return error.UnsupportedListElement;
        const field_count = element.record_field_count() orelse return error.UnsupportedListElement;
        if (field_count == 0) return error.MissingOwnedSlot;
        if (field_count != 1) return error.UnsupportedListElement;
        const field = element.record_field_at(0) orelse return error.MissingOwnedSlot;
        if (field.value.kind() == .list) return error.NestedListElement;
        if (field.value.kind() != .resource) return error.MissingOwnedSlot;
        switch (field.value.resource_mode() orelse return error.MissingOwnedSlot) {
            .own => {},
            .borrow => return error.BorrowedResource,
        }
        try validate_list_measurement(measured);

        const accepted_lengths = try allocator.dupe(u32, measured.accepted_lengths);
        errdefer allocator.free(accepted_lengths);
        return .{
            .allocator = allocator,
            .pointer_offset = measured.pointer_offset,
            .length_offset = measured.length_offset,
            .element_byte_size = measured.element_byte_size,
            .element_stride = measured.element_stride,
            .element_alignment = measured.element_alignment,
            .ticket_offset = measured.ticket_offset,
            .capacity = measured.capacity,
            .accepted_lengths = accepted_lengths,
            .allocation = measured.allocation,
            .free = measured.free,
        };
    }

    pub fn deinit(self: *ListLayoutPlan) void {
        if (self.accepted_lengths.len != 0) self.allocator.free(self.accepted_lengths);
        self.accepted_lengths = &.{};
    }

    pub fn validate_length(self: *const ListLayoutPlan, length: u32) LayoutError!void {
        if (length > self.capacity) return error.InvalidListLength;
        for (self.accepted_lengths) |accepted| {
            if (accepted == length) return;
        }
        return error.InvalidListLength;
    }

    pub fn validate_runtime_length(self: *const ListLayoutPlan, length: u32) LayoutError!void {
        if (length > self.capacity) return error.InvalidListLength;
    }

    pub fn owned_slot_iterator(self: *const ListLayoutPlan, length: u32) LayoutError!OwnedSlotIterator {
        try self.validate_runtime_length(length);
        return .{
            .index = 0,
            .length = length,
            .stride = self.element_stride,
            .ticket_offset = self.ticket_offset,
        };
    }
};

pub const ScalarMeasurement = struct {
    offset: u32,
    byte_size: u32,
    alignment: u32,
    core_type: CoreWord,
};

pub const VariantCasePlan = struct {
    name: []u8,
    tag: u32,
    payload: ?PayloadMeasurement,
};

pub const RecordFieldPlan = struct {
    name: []u8,
    offset: u32,
    byte_size: u32,
    alignment: u32,
    indirect: ?IndirectMeasurement,
};

pub const LayoutPlan = struct {
    allocator: Allocator,
    byte_size: u32,
    alignment: u32,
    scalar_measurement: ?ScalarMeasurement,
    variant_cases: []VariantCasePlan,
    record_fields: []RecordFieldPlan,

    pub fn scalar(
        allocator: Allocator,
        value: *const abi_types.AbiType,
        measured: ScalarMeasurement,
    ) (LayoutError || abi_types.AbiTypeError || Allocator.Error)!LayoutPlan {
        if (value.kind() != .scalar) return error.WrongRootKind;
        try value.validate();
        try validate_container(measured.byte_size, measured.alignment);
        const expected = scalar_measurement(value.scalar_kind() orelse return error.WrongRootKind);
        if (measured.core_type != expected.core_type or
            measured.byte_size != expected.byte_size or
            measured.alignment != expected.alignment)
        {
            return error.ScalarTypeMismatch;
        }
        if (!is_aligned(measured.offset, measured.alignment)) return error.MisalignedOffset;
        if (measured.offset > std.math.maxInt(u32) - measured.byte_size) return error.OffsetOverflow;
        return .{
            .allocator = allocator,
            .byte_size = measured.byte_size,
            .alignment = measured.alignment,
            .scalar_measurement = measured,
            .variant_cases = &.{},
            .record_fields = &.{},
        };
    }

    pub fn variant(
        allocator: Allocator,
        value: *const abi_types.AbiType,
        measured: VariantMeasurement,
    ) (LayoutError || abi_types.AbiTypeError || Allocator.Error)!LayoutPlan {
        if (value.kind() != .variant) return error.WrongRootKind;
        try value.validate();
        try validate_container(measured.byte_size, measured.alignment);
        if (!is_aligned(measured.tag_offset, @min(measured.alignment, 4))) return error.MisalignedOffset;
        try check_region(measured.tag_offset, 4, measured.byte_size);
        if (measured.cases.len == 0) return error.MissingPayloadMetadata;

        var cases = try allocator.alloc(VariantCasePlan, measured.cases.len);
        var initialized: usize = 0;
        errdefer {
            for (cases[0..initialized]) |*case| allocator.free(case.name);
            allocator.free(cases);
        }
        for (measured.cases, 0..) |case, index| {
            try validate_variant_case(measured, case, index);
            cases[index] = .{
                .name = try allocator.dupe(u8, case.name),
                .tag = case.tag,
                .payload = case.payload,
            };
            initialized += 1;
        }
        return .{
            .allocator = allocator,
            .byte_size = measured.byte_size,
            .alignment = measured.alignment,
            .scalar_measurement = null,
            .variant_cases = cases,
            .record_fields = &.{},
        };
    }

    pub fn record(
        allocator: Allocator,
        value: *const abi_types.AbiType,
        measured: RecordMeasurement,
    ) (LayoutError || abi_types.AbiTypeError || Allocator.Error)!LayoutPlan {
        if (value.kind() != .record) return error.WrongRootKind;
        try value.validate();
        try validate_container(measured.byte_size, measured.alignment);
        if (measured.fields.len == 0) return error.MissingPayloadMetadata;

        var fields = try allocator.alloc(RecordFieldPlan, measured.fields.len);
        var initialized: usize = 0;
        errdefer {
            for (fields[0..initialized]) |*field| allocator.free(field.name);
            allocator.free(fields);
        }
        for (measured.fields, 0..) |field, index| {
            try validate_field(measured, field, index);
            fields[index] = .{
                .name = try allocator.dupe(u8, field.name),
                .offset = field.offset,
                .byte_size = field.byte_size,
                .alignment = field.alignment,
                .indirect = field.indirect,
            };
            initialized += 1;
        }
        return .{
            .allocator = allocator,
            .byte_size = measured.byte_size,
            .alignment = measured.alignment,
            .scalar_measurement = null,
            .variant_cases = &.{},
            .record_fields = fields,
        };
    }

    pub fn deinit(self: *LayoutPlan) void {
        for (self.variant_cases) |case| self.allocator.free(case.name);
        if (self.variant_cases.len != 0) self.allocator.free(self.variant_cases);
        for (self.record_fields) |field| self.allocator.free(field.name);
        if (self.record_fields.len != 0) self.allocator.free(self.record_fields);
        self.variant_cases = &.{};
        self.record_fields = &.{};
    }
};

fn validate_container(byte_size: u32, alignment: u32) LayoutError!void {
    if (byte_size == 0 or !is_power_of_two(alignment)) return error.InvalidAlignment;
    if (byte_size % alignment != 0) return error.InvalidAlignment;
}

fn validate_list_measurement(measured: ListLayoutMeasurement) LayoutError!void {
    if (measured.capacity == 0) return error.InvalidCapacity;
    if (measured.element_byte_size == 0 or !is_power_of_two(measured.element_alignment)) return error.InvalidAlignment;
    if (measured.element_byte_size % measured.element_alignment != 0) return error.InvalidAlignment;
    if (measured.element_stride == 0) return error.InvalidStride;
    if (measured.element_stride < measured.element_byte_size or
        measured.element_stride % measured.element_alignment != 0)
    {
        return error.InvalidStride;
    }
    if (!is_aligned(measured.pointer_offset, 4) or !is_aligned(measured.length_offset, 4)) {
        return error.MisalignedOffset;
    }
    if (measured.pointer_offset > std.math.maxInt(u32) - 4 or
        measured.length_offset > std.math.maxInt(u32) - 4)
    {
        return error.OffsetOverflow;
    }
    if (measured.pointer_offset == measured.length_offset) return error.LayoutOutOfBounds;
    if (!is_aligned(measured.ticket_offset, 4)) return error.MisalignedOffset;
    if (measured.ticket_offset > std.math.maxInt(u32) - 4 or
        measured.ticket_offset + 4 > measured.element_byte_size)
    {
        return if (measured.ticket_offset > std.math.maxInt(u32) - 4) error.OffsetOverflow else error.LayoutOutOfBounds;
    }
    if (measured.allocation == .none or measured.free == .none) return error.MissingListStorageActions;
    if (measured.accepted_lengths.len == 0 or measured.accepted_lengths[0] != 0) return error.InvalidListLength;
    var previous: u32 = 0;
    for (measured.accepted_lengths, 0..) |length, index| {
        if (length > measured.capacity or (index != 0 and length <= previous)) return error.InvalidListLength;
        previous = length;
    }
    const last_slot_end = @as(u64, measured.ticket_offset) +
        @as(u64, measured.capacity - 1) * measured.element_stride + 4;
    if (last_slot_end > std.math.maxInt(u32)) return error.OffsetOverflow;
}

fn scalar_measurement(kind: abi_types.ScalarKind) PayloadMeasurement {
    return switch (kind) {
        .u64, .i64, .f64 => .{ .offset = 0, .byte_size = 8, .alignment = 8, .core_type = .i64 },
        else => .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 },
    };
}

fn validate_variant_case(measured: VariantMeasurement, case: VariantCaseMeasurement, index: usize) LayoutError!void {
    if (case.name.len == 0) return error.DuplicateName;
    for (measured.cases[0..index]) |previous| {
        if (previous.tag == case.tag) return error.DuplicateTag;
        if (std.mem.eql(u8, previous.name, case.name)) return error.DuplicateName;
    }
    if (case.payload_required and case.payload == null) return error.MissingPayloadMetadata;
    if (case.payload) |payload| try validate_payload(measured.byte_size, payload);
}

fn validate_field(measured: RecordMeasurement, field: FieldMeasurement, index: usize) LayoutError!void {
    if (field.name.len == 0) return error.DuplicateField;
    for (measured.fields[0..index]) |previous| {
        if (std.mem.eql(u8, previous.name, field.name)) return error.DuplicateField;
    }
    if (!is_power_of_two(field.alignment)) return error.InvalidAlignment;
    if (!is_aligned(field.offset, field.alignment)) return error.MisalignedOffset;
    try check_region(field.offset, field.byte_size, measured.byte_size);
    if (field.indirect) |indirect| {
        if (indirect.core_words.len == 0) return error.MissingIndirectMetadata;
    }
}

fn validate_payload(container_size: u32, payload: PayloadMeasurement) LayoutError!void {
    if (payload.byte_size == 0 or !is_power_of_two(payload.alignment)) return error.InvalidAlignment;
    if (!is_aligned(payload.offset, payload.alignment)) return error.MisalignedOffset;
    try check_region(payload.offset, payload.byte_size, container_size);
}

fn check_region(offset: u32, byte_size: u32, container_size: u32) LayoutError!void {
    if (offset > std.math.maxInt(u32) - byte_size) return error.OffsetOverflow;
    if (offset + byte_size > container_size) return error.LayoutOutOfBounds;
}

fn is_power_of_two(value: u32) bool {
    return value != 0 and (value & (value - 1)) == 0;
}

fn is_aligned(value: u32, alignment: u32) bool {
    return alignment != 0 and value % alignment == 0;
}

const c_min_list_measurement = ListLayoutMeasurement{
    .pointer_offset = 64,
    .length_offset = 68,
    .element_byte_size = 4,
    .element_stride = 4,
    .element_alignment = 4,
    .ticket_offset = 0,
    .capacity = 3,
    .accepted_lengths = &.{ 0, 1, 3 },
    .allocation = .cabi_realloc,
    .free = .cabi_realloc,
};

test "list resource producer layout accepts measured facts and iterates owned slots" {
    var ticket = try abi_types.AbiType.resource(std.testing.allocator, "ticket", .own);
    defer ticket.deinit();
    var entry = try abi_types.AbiType.record(std.testing.allocator, &.{
        .{ .name = "ticket", .value = &ticket },
    });
    defer entry.deinit();
    var list = try abi_types.AbiType.list(std.testing.allocator, &entry);
    defer list.deinit();

    var plan = try ListLayoutPlan.init(std.testing.allocator, &list, c_min_list_measurement);
    defer plan.deinit();
    try std.testing.expectEqual(@as(u32, 64), plan.pointer_offset);
    try std.testing.expectEqual(@as(u32, 68), plan.length_offset);
    try std.testing.expectEqual(@as(u32, 4), plan.element_stride);
    try std.testing.expectEqual(@as(u32, 4), plan.element_alignment);
    try std.testing.expectEqual(@as(u32, 0), plan.ticket_offset);
    try std.testing.expectEqual(@as(u32, 3), plan.capacity);
    try std.testing.expectEqual(AllocationAction.cabi_realloc, plan.allocation);
    try std.testing.expectEqual(FreeAction.cabi_realloc, plan.free);

    var slots = try plan.owned_slot_iterator(3);
    try std.testing.expectEqual(@as(u32, 0), slots.next().?.offset);
    try std.testing.expectEqual(@as(u32, 4), slots.next().?.offset);
    try std.testing.expectEqual(@as(u32, 8), slots.next().?.offset);
    try std.testing.expect(slots.next() == null);
}

test "list resource producer layout rejects a non-list root" {
    var value = abi_types.AbiType.scalar(std.testing.allocator, .u32);
    defer value.deinit();
    try std.testing.expectError(
        error.WrongRootKind,
        ListLayoutPlan.init(std.testing.allocator, &value, c_min_list_measurement),
    );
}

test "list resource producer layout rejects zero stride and misaligned words" {
    var ticket = try abi_types.AbiType.resource(std.testing.allocator, "ticket", .own);
    defer ticket.deinit();
    var entry = try abi_types.AbiType.record(std.testing.allocator, &.{.{ .name = "ticket", .value = &ticket }});
    defer entry.deinit();
    var list = try abi_types.AbiType.list(std.testing.allocator, &entry);
    defer list.deinit();

    var zero_stride = c_min_list_measurement;
    zero_stride.element_stride = 0;
    try std.testing.expectError(error.InvalidStride, ListLayoutPlan.init(std.testing.allocator, &list, zero_stride));

    var misaligned = c_min_list_measurement;
    misaligned.pointer_offset = 66;
    try std.testing.expectError(error.MisalignedOffset, ListLayoutPlan.init(std.testing.allocator, &list, misaligned));
}

test "list resource producer layout rejects lengths outside the closed descriptor bound" {
    var ticket = try abi_types.AbiType.resource(std.testing.allocator, "ticket", .own);
    defer ticket.deinit();
    var entry = try abi_types.AbiType.record(std.testing.allocator, &.{.{ .name = "ticket", .value = &ticket }});
    defer entry.deinit();
    var list = try abi_types.AbiType.list(std.testing.allocator, &entry);
    defer list.deinit();
    var plan = try ListLayoutPlan.init(std.testing.allocator, &list, c_min_list_measurement);
    defer plan.deinit();

    try plan.validate_length(0);
    try plan.validate_length(1);
    try plan.validate_length(3);
    try std.testing.expectError(error.InvalidListLength, plan.validate_length(2));
    try std.testing.expectError(error.InvalidListLength, plan.validate_length(4));
    try std.testing.expectError(error.InvalidListLength, plan.validate_length(std.math.maxInt(u32)));
}

test "dynamic list producer layout accepts every runtime length within capacity" {
    var ticket = try abi_types.AbiType.resource(std.testing.allocator, "ticket", .own);
    defer ticket.deinit();
    var entry = try abi_types.AbiType.record(std.testing.allocator, &.{.{ .name = "ticket", .value = &ticket }});
    defer entry.deinit();
    var list = try abi_types.AbiType.list(std.testing.allocator, &entry);
    defer list.deinit();

    var plan = try ListLayoutPlan.init(std.testing.allocator, &list, c_min_list_measurement);
    defer plan.deinit();
    for (0..4) |length| {
        try plan.validate_runtime_length(@intCast(length));
        var slots = try plan.owned_slot_iterator(@intCast(length));
        var index: u32 = 0;
        while (slots.next()) |slot| : (index += 1) {
            try std.testing.expectEqual(index * 4, slot.offset);
        }
        try std.testing.expectEqual(@as(u32, @intCast(length)), index);
    }
    try std.testing.expectError(error.InvalidListLength, plan.validate_runtime_length(4));
    try std.testing.expectError(error.InvalidListLength, plan.validate_runtime_length(std.math.maxInt(u32)));
    try std.testing.expectError(error.InvalidListLength, plan.validate_length(2));
}

test "dynamic list producer layout keeps storage and element guards" {
    var ticket = try abi_types.AbiType.resource(std.testing.allocator, "ticket", .own);
    defer ticket.deinit();
    var entry = try abi_types.AbiType.record(std.testing.allocator, &.{.{ .name = "ticket", .value = &ticket }});
    defer entry.deinit();
    var list = try abi_types.AbiType.list(std.testing.allocator, &entry);
    defer list.deinit();

    var zero_stride = c_min_list_measurement;
    zero_stride.element_stride = 0;
    try std.testing.expectError(error.InvalidStride, ListLayoutPlan.init(std.testing.allocator, &list, zero_stride));

    var misaligned = c_min_list_measurement;
    misaligned.pointer_offset = 66;
    try std.testing.expectError(error.MisalignedOffset, ListLayoutPlan.init(std.testing.allocator, &list, misaligned));

    var borrowed_ticket = try abi_types.AbiType.resource(std.testing.allocator, "ticket", .borrow);
    defer borrowed_ticket.deinit();
    var borrowed_entry = try abi_types.AbiType.record(std.testing.allocator, &.{.{ .name = "ticket", .value = &borrowed_ticket }});
    defer borrowed_entry.deinit();
    var borrowed_list = try abi_types.AbiType.list(std.testing.allocator, &borrowed_entry);
    defer borrowed_list.deinit();
    try std.testing.expectError(error.BorrowedResource, ListLayoutPlan.init(std.testing.allocator, &borrowed_list, c_min_list_measurement));
}

test "list resource producer layout rejects nested and borrowed elements" {
    var scalar = abi_types.AbiType.scalar(std.testing.allocator, .u32);
    defer scalar.deinit();
    var nested = try abi_types.AbiType.list(std.testing.allocator, &scalar);
    defer nested.deinit();
    var nested_list = try abi_types.AbiType.list(std.testing.allocator, &nested);
    defer nested_list.deinit();
    try std.testing.expectError(
        error.NestedListElement,
        ListLayoutPlan.init(std.testing.allocator, &nested_list, c_min_list_measurement),
    );

    var borrowed_ticket = try abi_types.AbiType.resource(std.testing.allocator, "ticket", .borrow);
    defer borrowed_ticket.deinit();
    var borrowed_entry = try abi_types.AbiType.record(std.testing.allocator, &.{.{ .name = "ticket", .value = &borrowed_ticket }});
    defer borrowed_entry.deinit();
    var borrowed_list = try abi_types.AbiType.list(std.testing.allocator, &borrowed_entry);
    defer borrowed_list.deinit();
    try std.testing.expectError(
        error.BorrowedResource,
        ListLayoutPlan.init(std.testing.allocator, &borrowed_list, c_min_list_measurement),
    );
}

test "list resource producer layout rejects an element without an owned slot" {
    var value = abi_types.AbiType.scalar(std.testing.allocator, .u32);
    defer value.deinit();
    var entry = try abi_types.AbiType.record(std.testing.allocator, &.{.{ .name = "value", .value = &value }});
    defer entry.deinit();
    var list = try abi_types.AbiType.list(std.testing.allocator, &entry);
    defer list.deinit();
    try std.testing.expectError(
        error.MissingOwnedSlot,
        ListLayoutPlan.init(std.testing.allocator, &list, c_min_list_measurement),
    );
}

test "measured variant layout accepts the pinned resource event facts" {
    var ticket = try abi_types.AbiType.resource(std.testing.allocator, "ticket", .own);
    defer ticket.deinit();
    var event = try abi_types.AbiType.variant(std.testing.allocator, &.{
        .{ .tag = 0, .name = "ticket", .payload = &ticket },
        .{ .tag = 1, .name = "idle", .payload = null },
        .{ .tag = 2, .name = "failed", .payload = null },
    });
    defer event.deinit();

    var plan = try LayoutPlan.variant(std.testing.allocator, &event, .{
        .tag_offset = 0,
        .payload_offset = 4,
        .byte_size = 8,
        .alignment = 4,
        .cases = &.{
            .{ .name = "ticket", .tag = 0, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
            .{ .name = "idle", .tag = 1, .payload_required = false, .payload = null },
            .{ .name = "failed", .tag = 2, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
        },
    });
    defer plan.deinit();
    try std.testing.expectEqual(@as(u32, 8), plan.byte_size);
    try std.testing.expectEqual(@as(u32, 4), plan.alignment);
    try std.testing.expectEqual(@as(usize, 3), plan.variant_cases.len);
}

test "measured record layout accepts the pinned optional string facts" {
    var text = abi_types.AbiType.text(std.testing.allocator);
    defer text.deinit();
    var optional = try abi_types.AbiType.option(std.testing.allocator, &text);
    defer optional.deinit();
    var error_payload = try abi_types.AbiType.record(std.testing.allocator, &.{
        .{ .name = "payload", .value = &optional },
    });
    defer error_payload.deinit();

    var plan = try LayoutPlan.record(std.testing.allocator, &error_payload, .{
        .byte_size = 32,
        .alignment = 8,
        .fields = &.{.{
            .name = "payload",
            .offset = 16,
            .byte_size = 16,
            .alignment = 8,
            .indirect = .{
                .core_words = &.{ .i32, .i64, .i32 },
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            },
        }},
    });
    defer plan.deinit();
    try std.testing.expectEqual(@as(u32, 32), plan.byte_size);
    try std.testing.expectEqual(@as(u32, 16), plan.record_fields[0].offset);
}

test "measured scalar layout accepts the pinned Future<i64> payload facts" {
    var value = abi_types.AbiType.scalar(std.testing.allocator, .i64);
    defer value.deinit();
    var plan = try LayoutPlan.scalar(std.testing.allocator, &value, .{
        .offset = 16,
        .byte_size = 8,
        .alignment = 8,
        .core_type = .i64,
    });
    defer plan.deinit();
    try std.testing.expect(plan.scalar_measurement != null);
    try std.testing.expectEqual(@as(u32, 16), plan.scalar_measurement.?.offset);
    try std.testing.expectEqual(CoreWord.i64, plan.scalar_measurement.?.core_type);
}

test "measured scalar layout rejects a mismatched alignment" {
    var value = abi_types.AbiType.scalar(std.testing.allocator, .i64);
    defer value.deinit();
    try std.testing.expectError(error.MisalignedOffset, LayoutPlan.scalar(std.testing.allocator, &value, .{
        .offset = 12,
        .byte_size = 8,
        .alignment = 8,
        .core_type = .i64,
    }));
}

test "measured scalar layout rejects a mismatched core width" {
    var value = abi_types.AbiType.scalar(std.testing.allocator, .i64);
    defer value.deinit();
    try std.testing.expectError(error.ScalarTypeMismatch, LayoutPlan.scalar(std.testing.allocator, &value, .{
        .offset = 16,
        .byte_size = 4,
        .alignment = 4,
        .core_type = .i32,
    }));
}

test "measured variant layout rejects duplicate tags" {
    var value = abi_types.AbiType.scalar(std.testing.allocator, .u32);
    defer value.deinit();
    var event = try abi_types.AbiType.variant(std.testing.allocator, &.{
        .{ .tag = 0, .name = "first", .payload = &value },
        .{ .tag = 1, .name = "second", .payload = &value },
    });
    defer event.deinit();
    try std.testing.expectError(
        error.DuplicateTag,
        LayoutPlan.variant(std.testing.allocator, &event, .{
            .tag_offset = 0,
            .payload_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .cases = &.{
                .{ .name = "first", .tag = 0, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
                .{ .name = "second", .tag = 0, .payload_required = true, .payload = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } },
            },
        }),
    );
}

test "measured layout rejects misalignment and offset overflow" {
    var value = abi_types.AbiType.scalar(std.testing.allocator, .u32);
    defer value.deinit();
    var record = try abi_types.AbiType.record(std.testing.allocator, &.{.{ .name = "value", .value = &value }});
    defer record.deinit();
    try std.testing.expectError(
        error.MisalignedOffset,
        LayoutPlan.record(std.testing.allocator, &record, .{
            .byte_size = 8,
            .alignment = 4,
            .fields = &.{.{ .name = "value", .offset = 2, .byte_size = 4, .alignment = 4, .indirect = null }},
        }),
    );
    try std.testing.expectError(
        error.OffsetOverflow,
        LayoutPlan.record(std.testing.allocator, &record, .{
            .byte_size = std.math.maxInt(u32) - 3,
            .alignment = 4,
            .fields = &.{.{ .name = "value", .offset = std.math.maxInt(u32) - 3, .byte_size = 4, .alignment = 4, .indirect = null }},
        }),
    );
}

test "measured variant layout rejects missing payload metadata" {
    var value = abi_types.AbiType.scalar(std.testing.allocator, .u32);
    defer value.deinit();
    var event = try abi_types.AbiType.variant(std.testing.allocator, &.{.{ .tag = 0, .name = "value", .payload = &value }});
    defer event.deinit();
    try std.testing.expectError(
        error.MissingPayloadMetadata,
        LayoutPlan.variant(std.testing.allocator, &event, .{
            .tag_offset = 0,
            .payload_offset = 4,
            .byte_size = 8,
            .alignment = 4,
            .cases = &.{.{ .name = "value", .tag = 0, .payload_required = true, .payload = null }},
        }),
    );
}
