const std = @import("std");

const Allocator = std.mem.Allocator;

pub const AbiTypeError = error{
    EmptyResult,
    EmptyVariant,
    DuplicateFieldName,
    DuplicateVariantName,
    DuplicateVariantTag,
    InvalidName,
};

pub const AbiTypeKind = enum {
    unit,
    scalar,
    text,
    tuple,
    record,
    option,
    result,
    variant,
    list,
    resource,
};

pub const ScalarKind = enum {
    bool,
    u8,
    u16,
    u32,
    u64,
    i8,
    i16,
    i32,
    i64,
    f32,
    f64,
};

pub const ResourceMode = enum {
    own,
    borrow,
};

pub const FieldSpec = struct {
    name: []const u8,
    value: *const AbiType,
};

pub const FieldRef = struct {
    name: []const u8,
    value: *const AbiType,
};

pub const VariantSpec = struct {
    tag: u32,
    name: []const u8,
    payload: ?*const AbiType,
};

const Field = struct {
    name: []u8,
    value: AbiType,
};

const VariantCase = struct {
    tag: u32,
    name: []u8,
    payload: ?*AbiType,
};

const ResourceShape = struct {
    name: []u8,
    mode: ResourceMode,
};

const ResultShape = struct {
    ok: ?*AbiType,
    err: ?*AbiType,
};

const Shape = union(AbiTypeKind) {
    unit: void,
    scalar: ScalarKind,
    text: void,
    tuple: []AbiType,
    record: []Field,
    option: *AbiType,
    result: ResultShape,
    variant: []VariantCase,
    list: *AbiType,
    resource: ResourceShape,
};

pub const AbiType = struct {
    allocator: Allocator,
    shape: Shape,

    pub fn unit(allocator: Allocator) AbiType {
        return .{ .allocator = allocator, .shape = .{ .unit = {} } };
    }

    pub fn scalar(allocator: Allocator, value: ScalarKind) AbiType {
        return .{ .allocator = allocator, .shape = .{ .scalar = value } };
    }

    pub fn text(allocator: Allocator) AbiType {
        return .{ .allocator = allocator, .shape = .{ .text = {} } };
    }

    pub fn resource(allocator: Allocator, name: []const u8, mode: ResourceMode) (AbiTypeError || Allocator.Error)!AbiType {
        try validate_name(name);
        return .{
            .allocator = allocator,
            .shape = .{ .resource = .{
                .name = try allocator.dupe(u8, name),
                .mode = mode,
            } },
        };
    }

    pub fn tuple(allocator: Allocator, values: []const *const AbiType) (AbiTypeError || Allocator.Error)!AbiType {
        const items = try clone_values(allocator, values);
        return .{ .allocator = allocator, .shape = .{ .tuple = items } };
    }

    pub fn record(allocator: Allocator, fields: []const FieldSpec) (AbiTypeError || Allocator.Error)!AbiType {
        try validate_field_specs(fields);
        var items = try allocator.alloc(Field, fields.len);
        var initialized: usize = 0;
        errdefer {
            for (items[0..initialized]) |*field| deinit_field(allocator, field);
            allocator.free(items);
        }
        for (fields, 0..) |spec, index| {
            items[index] = try clone_field(allocator, spec);
            initialized += 1;
        }
        return .{ .allocator = allocator, .shape = .{ .record = items } };
    }

    pub fn option(allocator: Allocator, value: *const AbiType) (AbiTypeError || Allocator.Error)!AbiType {
        return .{
            .allocator = allocator,
            .shape = .{ .option = try clone_ptr(allocator, value) },
        };
    }

    pub fn result(
        allocator: Allocator,
        ok: ?*const AbiType,
        err: ?*const AbiType,
    ) (AbiTypeError || Allocator.Error)!AbiType {
        if (ok == null and err == null) return error.EmptyResult;
        var owned_ok: ?*AbiType = null;
        var owned_err: ?*AbiType = null;
        errdefer {
            free_ptr(allocator, owned_ok);
            free_ptr(allocator, owned_err);
        }
        owned_ok = try clone_optional_ptr(allocator, ok);
        owned_err = try clone_optional_ptr(allocator, err);
        return .{
            .allocator = allocator,
            .shape = .{ .result = .{ .ok = owned_ok, .err = owned_err } },
        };
    }

    pub fn variant(allocator: Allocator, cases: []const VariantSpec) (AbiTypeError || Allocator.Error)!AbiType {
        try validate_variant_specs(cases);
        var items = try allocator.alloc(VariantCase, cases.len);
        var initialized: usize = 0;
        errdefer {
            for (items[0..initialized]) |*case| deinit_variant_case(allocator, case);
            allocator.free(items);
        }
        for (cases, 0..) |spec, index| {
            items[index] = try clone_variant_case(allocator, spec);
            initialized += 1;
        }
        return .{ .allocator = allocator, .shape = .{ .variant = items } };
    }

    pub fn list(allocator: Allocator, value: *const AbiType) (AbiTypeError || Allocator.Error)!AbiType {
        return .{
            .allocator = allocator,
            .shape = .{ .list = try clone_ptr(allocator, value) },
        };
    }

    pub fn kind(self: *const AbiType) AbiTypeKind {
        return switch (self.shape) {
            .unit => .unit,
            .scalar => .scalar,
            .text => .text,
            .tuple => .tuple,
            .record => .record,
            .option => .option,
            .result => .result,
            .variant => .variant,
            .list => .list,
            .resource => .resource,
        };
    }

    pub fn scalar_kind(self: *const AbiType) ?ScalarKind {
        return switch (self.shape) {
            .scalar => |value| value,
            else => null,
        };
    }

    pub fn resource_mode(self: *const AbiType) ?ResourceMode {
        return switch (self.shape) {
            .resource => |value| value.mode,
            else => null,
        };
    }

    pub fn list_element(self: *const AbiType) ?*const AbiType {
        return switch (self.shape) {
            .list => |value| value,
            else => null,
        };
    }

    pub fn record_field_count(self: *const AbiType) ?usize {
        return switch (self.shape) {
            .record => |fields| fields.len,
            else => null,
        };
    }

    pub fn record_field_at(self: *const AbiType, index: usize) ?FieldRef {
        return switch (self.shape) {
            .record => |fields| if (index < fields.len) .{
                .name = fields[index].name,
                .value = &fields[index].value,
            } else null,
            else => null,
        };
    }

    pub fn validate(self: *const AbiType) AbiTypeError!void {
        switch (self.shape) {
            .unit, .scalar, .text => {},
            .tuple => |values| {
                for (values) |*value| try value.validate();
            },
            .record => |fields| {
                for (fields, 0..) |*field, index| {
                    try validate_name(field.name);
                    for (fields[0..index]) |previous| {
                        if (std.mem.eql(u8, previous.name, field.name)) return error.DuplicateFieldName;
                    }
                    try field.value.validate();
                }
            },
            .option => |value| try value.validate(),
            .result => |value| {
                if (value.ok == null and value.err == null) return error.EmptyResult;
                if (value.ok) |ok| try ok.validate();
                if (value.err) |err| try err.validate();
            },
            .variant => |cases| {
                if (cases.len == 0) return error.EmptyVariant;
                for (cases, 0..) |*case, index| {
                    try validate_name(case.name);
                    for (cases[0..index]) |previous| {
                        if (previous.tag == case.tag) return error.DuplicateVariantTag;
                        if (std.mem.eql(u8, previous.name, case.name)) return error.DuplicateVariantName;
                    }
                    if (case.payload) |payload| try payload.validate();
                }
            },
            .list => |value| try value.validate(),
            .resource => |value| try validate_name(value.name),
        }
    }

    pub fn eql(self: *const AbiType, other: *const AbiType) bool {
        return eql_shape(self.shape, other.shape);
    }

    pub fn clone(self: *const AbiType, allocator: Allocator) (AbiTypeError || Allocator.Error)!AbiType {
        try self.validate();
        return switch (self.shape) {
            .unit => AbiType.unit(allocator),
            .scalar => |value| AbiType.scalar(allocator, value),
            .text => AbiType.text(allocator),
            .tuple => |values| blk: {
                var pointers = try allocator.alloc(*const AbiType, values.len);
                defer allocator.free(pointers);
                for (values, 0..) |*value, index| pointers[index] = value;
                break :blk try AbiType.tuple(allocator, pointers);
            },
            .record => |fields| blk: {
                var specs = try allocator.alloc(FieldSpec, fields.len);
                defer allocator.free(specs);
                for (fields, 0..) |*field, index| specs[index] = .{ .name = field.name, .value = &field.value };
                break :blk try AbiType.record(allocator, specs);
            },
            .option => |value| AbiType.option(allocator, value),
            .result => |value| AbiType.result(
                allocator,
                if (value.ok) |ok| ok else null,
                if (value.err) |err| err else null,
            ),
            .variant => |cases| blk: {
                var specs = try allocator.alloc(VariantSpec, cases.len);
                defer allocator.free(specs);
                for (cases, 0..) |*case, index| specs[index] = .{
                    .tag = case.tag,
                    .name = case.name,
                    .payload = if (case.payload) |payload| payload else null,
                };
                break :blk try AbiType.variant(allocator, specs);
            },
            .list => |value| AbiType.list(allocator, value),
            .resource => |value| AbiType.resource(allocator, value.name, value.mode),
        };
    }

    pub fn deinit(self: *AbiType) void {
        switch (self.shape) {
            .unit, .scalar, .text => {},
            .tuple => |values| {
                for (values) |*value| value.deinit();
                self.allocator.free(values);
            },
            .record => |fields| {
                for (fields) |*field| deinit_field(self.allocator, field);
                self.allocator.free(fields);
            },
            .option => |value| free_ptr(self.allocator, value),
            .result => |value| {
                free_ptr(self.allocator, value.ok);
                free_ptr(self.allocator, value.err);
            },
            .variant => |cases| {
                for (cases) |*case| deinit_variant_case(self.allocator, case);
                self.allocator.free(cases);
            },
            .list => |value| free_ptr(self.allocator, value),
            .resource => |value| self.allocator.free(value.name),
        }
        self.shape = .{ .unit = {} };
    }
};

fn validate_name(name: []const u8) AbiTypeError!void {
    if (name.len == 0) return error.InvalidName;
}

fn validate_field_specs(fields: []const FieldSpec) AbiTypeError!void {
    for (fields, 0..) |field, index| {
        try validate_name(field.name);
        for (fields[0..index]) |previous| {
            if (std.mem.eql(u8, previous.name, field.name)) return error.DuplicateFieldName;
        }
    }
}

fn validate_variant_specs(cases: []const VariantSpec) AbiTypeError!void {
    if (cases.len == 0) return error.EmptyVariant;
    for (cases, 0..) |case, index| {
        try validate_name(case.name);
        for (cases[0..index]) |previous| {
            if (previous.tag == case.tag) return error.DuplicateVariantTag;
            if (std.mem.eql(u8, previous.name, case.name)) return error.DuplicateVariantName;
        }
    }
}

fn clone_values(allocator: Allocator, values: []const *const AbiType) (AbiTypeError || Allocator.Error)![]AbiType {
    var items = try allocator.alloc(AbiType, values.len);
    var initialized: usize = 0;
    errdefer {
        for (items[0..initialized]) |*item| item.deinit();
        allocator.free(items);
    }
    for (values, 0..) |value, index| {
        items[index] = try value.clone(allocator);
        initialized += 1;
    }
    return items;
}

fn clone_field(allocator: Allocator, spec: FieldSpec) (AbiTypeError || Allocator.Error)!Field {
    const name = try allocator.dupe(u8, spec.name);
    errdefer allocator.free(name);
    return .{ .name = name, .value = try spec.value.clone(allocator) };
}

fn clone_variant_case(allocator: Allocator, spec: VariantSpec) (AbiTypeError || Allocator.Error)!VariantCase {
    const name = try allocator.dupe(u8, spec.name);
    errdefer allocator.free(name);
    return .{ .tag = spec.tag, .name = name, .payload = try clone_optional_ptr(allocator, spec.payload) };
}

fn clone_ptr(allocator: Allocator, source: *const AbiType) (AbiTypeError || Allocator.Error)!*AbiType {
    const value = try allocator.create(AbiType);
    errdefer allocator.destroy(value);
    value.* = try source.clone(allocator);
    return value;
}

fn clone_optional_ptr(allocator: Allocator, source: ?*const AbiType) (AbiTypeError || Allocator.Error)!?*AbiType {
    if (source) |value| return try clone_ptr(allocator, value);
    return null;
}

fn free_ptr(allocator: Allocator, value: ?*AbiType) void {
    if (value) |child| {
        child.deinit();
        allocator.destroy(child);
    }
}

fn deinit_field(allocator: Allocator, field: *Field) void {
    allocator.free(field.name);
    field.value.deinit();
}

fn deinit_variant_case(allocator: Allocator, case: *VariantCase) void {
    allocator.free(case.name);
    free_ptr(allocator, case.payload);
}

fn eql_shape(lhs: Shape, rhs: Shape) bool {
    return switch (lhs) {
        .unit => rhs == .unit,
        .scalar => |value| switch (rhs) {
            .scalar => |other| value == other,
            else => false,
        },
        .text => rhs == .text,
        .tuple => |values| switch (rhs) {
            .tuple => |other| eql_values(values, other),
            else => false,
        },
        .record => |fields| switch (rhs) {
            .record => |other| eql_fields(fields, other),
            else => false,
        },
        .option => |value| switch (rhs) {
            .option => |other| value.eql(other),
            else => false,
        },
        .result => |value| switch (rhs) {
            .result => |other| eql_optional(value.ok, other.ok) and eql_optional(value.err, other.err),
            else => false,
        },
        .variant => |cases| switch (rhs) {
            .variant => |other| eql_variants(cases, other),
            else => false,
        },
        .list => |value| switch (rhs) {
            .list => |other| value.eql(other),
            else => false,
        },
        .resource => |value| switch (rhs) {
            .resource => |other| value.mode == other.mode and std.mem.eql(u8, value.name, other.name),
            else => false,
        },
    };
}

fn eql_values(lhs: []const AbiType, rhs: []const AbiType) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |left, right| if (!left.eql(&right)) return false;
    return true;
}

fn eql_fields(lhs: []const Field, rhs: []const Field) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |left, right| {
        if (!std.mem.eql(u8, left.name, right.name) or !left.value.eql(&right.value)) return false;
    }
    return true;
}

fn eql_optional(lhs: ?*AbiType, rhs: ?*AbiType) bool {
    if (lhs == null or rhs == null) return lhs == null and rhs == null;
    return lhs.?.eql(rhs.?);
}

fn eql_variants(lhs: []const VariantCase, rhs: []const VariantCase) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |left, right| {
        if (left.tag != right.tag or !std.mem.eql(u8, left.name, right.name) or
            !eql_optional(left.payload, right.payload)) return false;
    }
    return true;
}

test "ABI type constructors cover every logical kind" {
    var unit = AbiType.unit(std.testing.allocator);
    defer unit.deinit();
    var scalar = AbiType.scalar(std.testing.allocator, .u32);
    defer scalar.deinit();
    var text = AbiType.text(std.testing.allocator);
    defer text.deinit();
    var resource = try AbiType.resource(std.testing.allocator, "ticket", .own);
    defer resource.deinit();
    var tuple = try AbiType.tuple(std.testing.allocator, &.{ &scalar, &text });
    defer tuple.deinit();
    var record = try AbiType.record(std.testing.allocator, &.{
        .{ .name = "value", .value = &scalar },
        .{ .name = "ticket", .value = &resource },
    });
    defer record.deinit();
    var optional = try AbiType.option(std.testing.allocator, &text);
    defer optional.deinit();
    var result = try AbiType.result(std.testing.allocator, null, &text);
    defer result.deinit();
    var variant = try AbiType.variant(std.testing.allocator, &.{
        .{ .tag = 0, .name = "none", .payload = null },
        .{ .tag = 1, .name = "value", .payload = &scalar },
    });
    defer variant.deinit();
    var list = try AbiType.list(std.testing.allocator, &scalar);
    defer list.deinit();

    try std.testing.expectEqual(AbiTypeKind.unit, unit.kind());
    try std.testing.expectEqual(AbiTypeKind.scalar, scalar.kind());
    try std.testing.expectEqual(AbiTypeKind.text, text.kind());
    try std.testing.expectEqual(AbiTypeKind.resource, resource.kind());
    try std.testing.expectEqual(AbiTypeKind.tuple, tuple.kind());
    try std.testing.expectEqual(AbiTypeKind.record, record.kind());
    try std.testing.expectEqual(AbiTypeKind.option, optional.kind());
    try std.testing.expectEqual(AbiTypeKind.result, result.kind());
    try std.testing.expectEqual(AbiTypeKind.variant, variant.kind());
    try std.testing.expectEqual(AbiTypeKind.list, list.kind());
}

test "ABI type equality compares recursive shapes and ownership modes" {
    var scalar = AbiType.scalar(std.testing.allocator, .u32);
    defer scalar.deinit();
    var left = try AbiType.tuple(std.testing.allocator, &.{&scalar});
    defer left.deinit();
    var right = try AbiType.tuple(std.testing.allocator, &.{&scalar});
    defer right.deinit();
    try std.testing.expect(left.eql(&right));

    var different = AbiType.scalar(std.testing.allocator, .i64);
    defer different.deinit();
    var changed = try AbiType.tuple(std.testing.allocator, &.{&different});
    defer changed.deinit();
    try std.testing.expect(!left.eql(&changed));

    var owned = try AbiType.resource(std.testing.allocator, "ticket", .own);
    defer owned.deinit();
    var borrowed = try AbiType.resource(std.testing.allocator, "ticket", .borrow);
    defer borrowed.deinit();
    try std.testing.expect(!owned.eql(&borrowed));
}

test "ABI type validation rejects empty result and variant shapes" {
    try std.testing.expectError(
        error.EmptyResult,
        AbiType.result(std.testing.allocator, null, null),
    );
    try std.testing.expectError(
        error.EmptyVariant,
        AbiType.variant(std.testing.allocator, &.{}),
    );
}

test "ABI variant validation rejects duplicate tags and names" {
    var scalar = AbiType.scalar(std.testing.allocator, .u32);
    defer scalar.deinit();
    try std.testing.expectError(
        error.DuplicateVariantTag,
        AbiType.variant(std.testing.allocator, &.{
            .{ .tag = 1, .name = "first", .payload = null },
            .{ .tag = 1, .name = "second", .payload = &scalar },
        }),
    );
    try std.testing.expectError(
        error.DuplicateVariantName,
        AbiType.variant(std.testing.allocator, &.{
            .{ .tag = 1, .name = "same", .payload = null },
            .{ .tag = 2, .name = "same", .payload = &scalar },
        }),
    );
}

test "ABI type validation rejects empty field and resource names" {
    var scalar = AbiType.scalar(std.testing.allocator, .u32);
    defer scalar.deinit();
    try std.testing.expectError(
        error.InvalidName,
        AbiType.record(std.testing.allocator, &.{.{ .name = "", .value = &scalar }}),
    );
    try std.testing.expectError(
        error.InvalidName,
        AbiType.resource(std.testing.allocator, "", .own),
    );
}
