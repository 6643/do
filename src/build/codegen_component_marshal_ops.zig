//! Ordered synchronous canonical-memory operations.
//!
//! This module is deliberately an execution-independent boundary. It turns a
//! measured marshal tree into a fixed operation order and validates arithmetic
//! used by a future WAT emitter. It does not emit WAT, access memory, or run a
//! host call.
const std = @import("std");
const marshal = @import("codegen_component_marshal_plan.zig");
const wit_layout = @import("wit_abi_layout.zig");

pub const MemoryOperation = enum {
    read_gc_span,
    flatten_gc_fields,
    validate_linear_range,
    cabi_realloc_alloc,
    copy_to_linear,
    canonical_call,
    copy_from_linear,
    construct_gc_value,
    publish_gc_root,
    cabi_realloc_free,
};

pub const CopyShape = enum {
    scalar,
    text_bytes,
    list_elements,
    map_entries,
    record_fields,
};

pub const ManagedTextField = struct {
    field_index: u32,
    pointer_offset: u32,
    length_offset: u32,
};

pub const ScalarListElementKind = enum {
    byte,
    u32,
};

pub const ManagedScalarListField = struct {
    field_index: u32,
    pointer_offset: u32,
    length_offset: u32,
    element_kind: ScalarListElementKind,
    element_byte_size: u32,
    element_alignment: u32,
    element_stride: u32,
    capacity: u32,
};

pub const ManagedScalarListPairLower = struct {
    first: ManagedScalarListField,
    second: ManagedScalarListField,
};

pub const ManagedTextScalarListPairLower = struct {
    text: ManagedTextField,
    first: ManagedScalarListField,
    second: ManagedScalarListField,
};

pub const ManagedTextByteU32ListLower = struct {
    text: ManagedTextField,
    bytes: ManagedScalarListField,
    values: ManagedScalarListField,
};

pub const ManagedMixedScalarListLower = struct {
    text: ManagedTextField,
    scalar_list: ManagedScalarListField,
};

pub const MemoryPlan = struct {
    direction: marshal.Direction,
    copy_shape: CopyShape,
    element_stride: u32,
    scalar_core_type: ?wit_layout.CoreWord = null,
    element_core_type: ?wit_layout.CoreWord = null,
    result_area_pointer_offset: ?u32 = null,
    result_area_length_offset: ?u32 = null,
    record_field_count: u32 = 0,
    record_indirect: ?wit_layout.IndirectMeasurement = null,
    record_managed_text_lower: bool = false,
    managed_text_fields: [2]ManagedTextField = undefined,
    managed_text_field_count: u8 = 0,
    record_managed_scalar_list_lower: bool = false,
    managed_scalar_list_field: ?ManagedScalarListField = null,
    record_managed_scalar_list_pair_lower: bool = false,
    managed_scalar_list_pair_lower: ?ManagedScalarListPairLower = null,
    record_managed_text_scalar_list_pair_lower: bool = false,
    managed_text_scalar_list_pair_lower: ?ManagedTextScalarListPairLower = null,
    record_managed_text_byte_u32_list_lower: bool = false,
    managed_text_byte_u32_list_lower: ?ManagedTextByteU32ListLower = null,
    record_managed_mixed_scalar_list_lower: bool = false,
    managed_mixed_scalar_list_lower: ?ManagedMixedScalarListLower = null,
    record_mixed_text_two_u32_lists_lift: bool = false,
    map_pair_byte_size: ?u32 = null,
    map_pair_alignment: ?u32 = null,
    map_key_offset: ?u32 = null,
    map_value_offset: ?u32 = null,
    operations: []const MemoryOperation,
};

const ManagedTextFields = struct {
    fields: [2]ManagedTextField,
    count: u8,
};

pub fn build_sync_memory_plan(plan: *const marshal.SyncValuePlan) !MemoryPlan {
    try marshal.validate_sync_value_plan(plan);
    const measured = plan.root.measured orelse return error.MeasuredLayoutRequired;

    switch (plan.root.kind) {
        .scalar => {
            _ = plan.root.scalar_kind orelse return error.UnsupportedMarshalShape;
            return .{
                .direction = plan.direction,
                .copy_shape = .scalar,
                .element_stride = 0,
                .scalar_core_type = measured.core_type orelse return error.MeasuredScalarCoreTypeMissing,
                .operations = &scalar_operations,
            };
        },
        .text => return .{
            .direction = plan.direction,
            .copy_shape = .text_bytes,
            .element_stride = 1,
            .result_area_pointer_offset = measured.pointer_offset,
            .result_area_length_offset = measured.length_offset,
            .operations = operations_for(plan.direction),
        },
        .list => {
            if (plan.root.children.len != 1) return error.MeasuredChildMissing;
            const child = plan.root.children[0].measured orelse return error.MeasuredChildMissing;
            const stride = measured.element_stride orelse return error.MeasuredElementStrideMissing;
            const element_core_type = if (stride == 1 and child.core_type == null)
                null
            else if (stride == 4 and child.byte_size == 4 and child.alignment == 4 and child.core_type == .i32)
                wit_layout.CoreWord.i32
            else
                return error.UnsupportedMarshalShape;
            return .{
                .direction = plan.direction,
                .copy_shape = .list_elements,
                .element_stride = stride,
                .element_core_type = element_core_type,
                .result_area_pointer_offset = measured.pointer_offset,
                .result_area_length_offset = measured.length_offset,
                .operations = operations_for(plan.direction),
            };
        },
        .map => {
            if (plan.root.children.len != 2) return error.MeasuredChildCountMismatch;
            const map_measured = plan.root.measured orelse return error.MeasuredLayoutRequired;
            const stride = map_measured.element_stride orelse return error.MeasuredElementStrideMissing;
            const pair_size = map_measured.map_pair_byte_size orelse return error.MeasuredElementByteSizeMissing;
            const pair_alignment = map_measured.map_pair_alignment orelse return error.MeasuredElementAlignmentMissing;
            try validate_map_node(&plan.root, stride, pair_size, pair_alignment);
            return .{
                .direction = plan.direction,
                .copy_shape = .map_entries,
                .element_stride = stride,
                .result_area_pointer_offset = map_measured.pointer_offset,
                .result_area_length_offset = map_measured.length_offset,
                .map_pair_byte_size = pair_size,
                .map_pair_alignment = pair_alignment,
                .map_key_offset = map_measured.map_key_offset,
                .map_value_offset = map_measured.map_value_offset,
                .operations = map_operations_for(plan.direction),
            };
        },
        .record => {
            if (plan.root.children.len == 0 or plan.root.children.len > std.math.maxInt(u32)) {
                return error.UnsupportedMarshalShape;
            }
            const managed_text = if (plan.direction == .lower)
                managed_text_fields_for_root(&plan.root)
            else
                null;
            const managed_text_lower = managed_text != null;
            const managed_mixed_scalar_list = if (plan.direction == .lower)
                managed_mixed_scalar_list_lower_for_root(&plan.root)
            else
                null;
            const managed_scalar_list_pair = if (plan.direction == .lower)
                managed_scalar_list_pair_lower_for_root(&plan.root)
            else
                null;
            const managed_text_scalar_list_pair = if (plan.direction == .lower)
                managed_text_scalar_list_pair_lower_for_root(&plan.root)
            else
                null;
            const managed_text_byte_u32_list = if (plan.direction == .lower)
                managed_text_byte_u32_list_lower_for_root(&plan.root)
            else
                null;
            const managed_scalar_list = if (plan.direction == .lower and !managed_text_lower and managed_scalar_list_pair == null)
                managed_scalar_list_field_for_root(&plan.root)
            else
                null;
            const mixed_text_two_u32_lists_lift = plan.direction == .lift and
                record_is_mixed_text_two_u32_lists_lift(&plan.root);
            if (plan.direction == .lift) {
                try validate_record_lift_node(&plan.root, true);
            } else if (managed_mixed_scalar_list == null and managed_scalar_list_pair == null and
                managed_text_scalar_list_pair == null and managed_text_byte_u32_list == null and
                !managed_text_lower and managed_scalar_list == null)
            {
                try validate_record_lower_node(&plan.root, managed_text_lower);
            }
            const record_indirect = plan.root.measured.?.indirect;
            if (record_indirect) |indirect| {
                if (plan.direction != .lower or indirect.core_words.len != 1 or
                    indirect.core_words[0] != .i32 or indirect.allocation != .cabi_realloc or
                    indirect.free != .cabi_realloc)
                {
                    return error.UnsupportedMarshalShape;
                }
            }
            var managed_text_fields: [2]ManagedTextField = undefined;
            var managed_text_field_count: u8 = 0;
            if (managed_text) |fields| {
                managed_text_fields = fields.fields;
                managed_text_field_count = fields.count;
            }
            return .{
                .direction = plan.direction,
                .copy_shape = .record_fields,
                .element_stride = 0,
                .record_field_count = @intCast(plan.root.children.len),
                .record_indirect = record_indirect,
                .record_managed_text_lower = managed_text_lower,
                .managed_text_fields = managed_text_fields,
                .managed_text_field_count = managed_text_field_count,
                .record_managed_scalar_list_lower = managed_scalar_list != null,
                .managed_scalar_list_field = managed_scalar_list,
                .record_managed_scalar_list_pair_lower = managed_scalar_list_pair != null,
                .managed_scalar_list_pair_lower = managed_scalar_list_pair,
                .record_managed_text_scalar_list_pair_lower = managed_text_scalar_list_pair != null,
                .managed_text_scalar_list_pair_lower = managed_text_scalar_list_pair,
                .record_managed_text_byte_u32_list_lower = managed_text_byte_u32_list != null,
                .managed_text_byte_u32_list_lower = managed_text_byte_u32_list,
                .record_managed_mixed_scalar_list_lower = managed_mixed_scalar_list != null,
                .managed_mixed_scalar_list_lower = managed_mixed_scalar_list,
                .record_mixed_text_two_u32_lists_lift = mixed_text_two_u32_lists_lift,
                .operations = if (record_indirect != null)
                    &record_indirect_lower_operations
                else if (managed_text_scalar_list_pair != null)
                    &record_managed_text_scalar_list_pair_lower_operations
                else if (managed_text_byte_u32_list != null)
                    &record_managed_text_scalar_list_pair_lower_operations
                else if (managed_scalar_list_pair != null)
                    &record_managed_scalar_list_pair_lower_operations
                else if (managed_mixed_scalar_list != null)
                    &record_managed_mixed_scalar_list_lower_operations
                else if (managed_text_field_count == 2)
                    &record_managed_text_lower_multi_operations
                else if (managed_text_lower)
                    &record_managed_text_lower_operations
                else if (managed_scalar_list != null)
                    &record_managed_scalar_list_lower_operations
                else if (mixed_text_two_u32_lists_lift)
                    &record_mixed_text_two_u32_lists_lift_operations
                else if (plan.direction == .lower)
                    &record_lower_operations
                else
                    &record_lift_operations,
            };
        },
    }
}

pub fn record_contains_text(node: *const marshal.MarshalNode) bool {
    if (node.kind == .text) return true;
    for (node.children) |*child| {
        if (record_contains_text(child)) return true;
    }
    return false;
}

pub fn record_contains_list(node: *const marshal.MarshalNode) bool {
    if (node.kind == .list) return true;
    for (node.children) |*child| {
        if (record_contains_list(child)) return true;
    }
    return false;
}

pub fn record_contains_u32_list(node: *const marshal.MarshalNode) bool {
    if (node.kind == .list and node.children.len == 1 and node.children[0].scalar_kind == .u32) return true;
    for (node.children) |*child| {
        if (record_contains_u32_list(child)) return true;
    }
    return false;
}

pub fn record_contains_byte_list(node: *const marshal.MarshalNode) bool {
    if (node.kind == .list and node.children.len == 1 and node.children[0].scalar_kind == .u8) return true;
    for (node.children) |*child| {
        if (record_contains_byte_list(child)) return true;
    }
    return false;
}

pub fn record_is_mixed_text_two_u32_lists_lift(node: *const marshal.MarshalNode) bool {
    if (node.kind != .record or node.children.len != 4) return false;
    const root = node.measured orelse return false;
    if (root.byte_size != 28 or root.alignment != 4 or root.indirect != null) return false;

    const code = &node.children[0];
    if (code.kind != .scalar or code.scalar_kind != .u32) return false;
    const code_facts = code.measured orelse return false;
    if (code_facts.offset != 0 or code_facts.byte_size != 4 or code_facts.alignment != 4 or
        code_facts.core_type != .i32)
    {
        return false;
    }

    const label = &node.children[1];
    if (label.kind != .text) return false;
    const label_facts = label.measured orelse return false;
    if (label_facts.offset != 4 or label_facts.byte_size != 8 or label_facts.alignment != 4 or
        label_facts.pointer_offset != 0 or label_facts.length_offset != 4)
    {
        return false;
    }

    return is_mixed_text_two_u32_list_field(&node.children[2], 12, 3) and
        is_mixed_text_two_u32_list_field(&node.children[3], 20, 2);
}

fn is_mixed_text_two_u32_list_field(node: *const marshal.MarshalNode, offset: u32, capacity: u32) bool {
    if (node.kind != .list or node.children.len != 1) return false;
    const facts = node.measured orelse return false;
    if (facts.offset != offset or facts.byte_size != 8 or facts.alignment != 4 or
        facts.pointer_offset != 0 or facts.length_offset != 4 or facts.element_stride != 4 or
        facts.element_byte_size != 4 or facts.element_alignment != 4 or facts.capacity != capacity)
    {
        return false;
    }
    const element = &node.children[0];
    if (element.kind != .scalar or element.scalar_kind != .u32) return false;
    const element_facts = element.measured orelse return false;
    return element_facts.offset == 0 and element_facts.byte_size == 4 and
        element_facts.alignment == 4 and element_facts.core_type == .i32;
}

fn validate_record_lift_node(node: *const marshal.MarshalNode, is_root: bool) !void {
    if (node.kind != .record or node.children.len == 0) return error.UnsupportedMarshalShape;
    const measured = node.measured orelse return error.MeasuredChildMissing;
    if (measured.indirect != null) return error.UnsupportedMarshalShape;
    for (node.children) |*child| {
        switch (child.kind) {
            .scalar => try validate_flat_record_scalar(child),
            .record => try validate_record_lift_node(child, false),
            .text => {
                const facts = child.measured orelse return error.MeasuredChildMissing;
                if (facts.pointer_offset == null or facts.length_offset == null) {
                    return error.MeasuredResultAreaPointerMissing;
                }
            },
            .list => {
                if (!is_root) return error.UnsupportedMarshalShape;
                if (child.children.len == 1 and child.children[0].scalar_kind == .u8) {
                    try validate_byte_list_lift_node(child);
                } else {
                    try validate_u32_list_lift_node(child);
                }
            },
            .map => return error.UnsupportedMarshalShape,
        }
    }
}

fn validate_map_node(
    node: *const marshal.MarshalNode,
    stride: u32,
    pair_size: u32,
    pair_alignment: u32,
) !void {
    if (node.kind != .map or node.children.len != 2) return error.UnsupportedMarshalShape;
    if (node.canonical_shape != .ptr_len or stride < pair_size or pair_alignment == 0) {
        return error.UnsupportedMarshalShape;
    }
    const measured = node.measured orelse return error.MeasuredChildMissing;
    if (measured.byte_size != 8 or measured.alignment != 4 or
        measured.pointer_offset == null or measured.length_offset == null or
        measured.capacity == null)
    {
        return error.UnsupportedMarshalShape;
    }
    const key = &node.children[0];
    if (key.kind != .scalar and key.kind != .text) return error.UnsupportedMarshalShape;
    const key_facts = key.measured orelse return error.MeasuredChildMissing;
    const value = &node.children[1];
    const value_facts = value.measured orelse return error.MeasuredChildMissing;
    if (key_facts.byte_size == 0 or value_facts.byte_size == 0 or
        key_facts.offset > pair_size -| key_facts.byte_size or
        value_facts.offset > pair_size -| value_facts.byte_size)
    {
        return error.UnsupportedMarshalShape;
    }
}

fn validate_byte_list_lift_node(node: *const marshal.MarshalNode) !void {
    if (node.kind != .list or node.children.len != 1) return error.UnsupportedMarshalShape;
    const facts = node.measured orelse return error.MeasuredChildMissing;
    if (facts.byte_size != 8 or facts.alignment != 4 or
        facts.pointer_offset != 0 or facts.length_offset != 4 or facts.element_stride != 1)
    {
        return error.UnsupportedMarshalShape;
    }
    const element = &node.children[0];
    if (element.kind != .scalar or element.scalar_kind != .u8) return error.UnsupportedMarshalShape;
    const element_facts = element.measured orelse return error.MeasuredChildMissing;
    if (element_facts.byte_size != 1 or element_facts.alignment != 1) {
        return error.UnsupportedMarshalShape;
    }
}

fn validate_u32_list_lift_node(node: *const marshal.MarshalNode) !void {
    if (node.kind != .list or node.children.len != 1) return error.UnsupportedMarshalShape;
    const facts = node.measured orelse return error.MeasuredChildMissing;
    if (facts.byte_size != 8 or facts.alignment != 4 or
        facts.pointer_offset != 0 or facts.length_offset != 4 or facts.element_stride != 4)
    {
        return error.UnsupportedMarshalShape;
    }
    const element = &node.children[0];
    if (element.kind != .scalar or element.scalar_kind != .u32) return error.UnsupportedMarshalShape;
    const element_facts = element.measured orelse return error.MeasuredChildMissing;
    if (element_facts.byte_size != 4 or element_facts.alignment != 4 or element_facts.core_type != .i32) {
        return error.UnsupportedMarshalShape;
    }
}

fn validate_record_lower_node(node: *const marshal.MarshalNode, allow_managed_text: bool) !void {
    if (node.kind != .record or node.children.len == 0) return error.UnsupportedMarshalShape;
    _ = node.measured orelse return error.MeasuredChildMissing;
    for (node.children, 0..) |*child, index| {
        switch (child.kind) {
            .scalar => try validate_flat_record_scalar(child),
            .record => {
                if ((child.measured orelse return error.MeasuredChildMissing).indirect != null) {
                    return error.UnsupportedMarshalShape;
                }
                try validate_record_lower_node(child, false);
            },
            .text => {
                if (!allow_managed_text or (index != 1 and index != 2)) return error.UnsupportedMarshalShape;
                try validate_managed_text_child(child);
            },
            else => return error.UnsupportedMarshalShape,
        }
    }
}

fn managed_text_fields_for_root(node: *const marshal.MarshalNode) ?ManagedTextFields {
    if (node.kind != .record or (node.children.len != 2 and node.children.len != 3)) return null;
    if ((node.measured orelse return null).indirect != null) return null;
    const scalar = &node.children[0];
    if (scalar.kind != .scalar or scalar.scalar_kind != .u32) return null;
    const scalar_facts = scalar.measured orelse return null;
    if (scalar_facts.core_type != .i32) return null;

    var fields: [2]ManagedTextField = undefined;
    for (node.children[1..], 0..) |*text, field_slot| {
        if (text.kind != .text) return null;
        const facts = text.measured orelse return null;
        if (!has_managed_text_layout(text)) return null;
        fields[field_slot] = .{
            .field_index = @intCast(field_slot + 1),
            .pointer_offset = facts.pointer_offset orelse return null,
            .length_offset = facts.length_offset orelse return null,
        };
    }
    return .{ .fields = fields, .count = @intCast(node.children.len - 1) };
}

fn managed_scalar_list_field_for_root(node: *const marshal.MarshalNode) ?ManagedScalarListField {
    if (node.kind != .record or node.children.len != 2) return null;
    if ((node.measured orelse return null).indirect != null) return null;

    const code = &node.children[0];
    if (code.kind != .scalar or code.scalar_kind != .u32) return null;
    const code_facts = code.measured orelse return null;
    if (code_facts.core_type != .i32 or code_facts.byte_size != 4 or code_facts.alignment != 4) return null;

    return managed_scalar_list_field_for_child(&node.children[1], 1, 4);
}

fn managed_scalar_list_pair_lower_for_root(node: *const marshal.MarshalNode) ?ManagedScalarListPairLower {
    if (node.kind != .record or node.children.len != 3) return null;
    const root_facts = node.measured orelse return null;
    if (root_facts.indirect != null or root_facts.byte_size != 20 or root_facts.alignment != 4) return null;

    const code = &node.children[0];
    if (code.kind != .scalar or code.scalar_kind != .u32) return null;
    const code_facts = code.measured orelse return null;
    if (code_facts.offset != 0 or code_facts.byte_size != 4 or code_facts.alignment != 4 or code_facts.core_type != .i32) {
        return null;
    }

    const first = managed_scalar_list_field_for_child(&node.children[1], 1, 4) orelse return null;
    const second = managed_scalar_list_field_for_child(&node.children[2], 2, 12) orelse return null;
    if (first.element_kind != .u32 or second.element_kind != .u32) return null;
    return .{ .first = first, .second = second };
}

fn managed_text_scalar_list_pair_lower_for_root(node: *const marshal.MarshalNode) ?ManagedTextScalarListPairLower {
    if (node.kind != .record or node.children.len != 4) return null;
    const root_facts = node.measured orelse return null;
    if (root_facts.indirect != null or root_facts.byte_size != 28 or root_facts.alignment != 4) return null;

    const code = &node.children[0];
    if (code.kind != .scalar or code.scalar_kind != .u32) return null;
    const code_facts = code.measured orelse return null;
    if (code_facts.offset != 0 or code_facts.byte_size != 4 or code_facts.alignment != 4 or code_facts.core_type != .i32) {
        return null;
    }

    const label = &node.children[1];
    if (label.kind != .text or !has_managed_text_layout(label)) return null;
    const label_facts = label.measured orelse return null;
    if (label_facts.offset != 4 or label_facts.pointer_offset.? != 0 or label_facts.length_offset.? != 4) return null;

    const first = managed_scalar_list_field_for_child(&node.children[2], 2, 12) orelse return null;
    const second = managed_scalar_list_field_for_child(&node.children[3], 3, 20) orelse return null;
    if (first.element_kind != .u32 or second.element_kind != .u32) return null;
    return .{
        .text = .{
            .field_index = 1,
            .pointer_offset = label_facts.pointer_offset.?,
            .length_offset = label_facts.length_offset.?,
        },
        .first = first,
        .second = second,
    };
}

fn managed_text_byte_u32_list_lower_for_root(node: *const marshal.MarshalNode) ?ManagedTextByteU32ListLower {
    if (node.kind != .record or node.children.len != 4) return null;
    const root_facts = node.measured orelse return null;
    if (root_facts.indirect != null or root_facts.byte_size != 28 or root_facts.alignment != 4) return null;

    const code = &node.children[0];
    if (code.kind != .scalar or code.scalar_kind != .u32) return null;
    const code_facts = code.measured orelse return null;
    if (code_facts.offset != 0 or code_facts.byte_size != 4 or code_facts.alignment != 4 or code_facts.core_type != .i32) {
        return null;
    }

    const label = &node.children[1];
    if (label.kind != .text or !has_managed_text_layout(label)) return null;
    const label_facts = label.measured orelse return null;
    if (label_facts.offset != 4 or label_facts.pointer_offset.? != 0 or label_facts.length_offset.? != 4) return null;

    const bytes = managed_scalar_list_field_for_child(&node.children[2], 2, 12) orelse return null;
    const values = managed_scalar_list_field_for_child(&node.children[3], 3, 20) orelse return null;
    if (bytes.element_kind != .byte or values.element_kind != .u32) return null;
    if (bytes.capacity != 4 or values.capacity != 3) return null;
    return .{
        .text = .{
            .field_index = 1,
            .pointer_offset = label_facts.pointer_offset.?,
            .length_offset = label_facts.length_offset.?,
        },
        .bytes = bytes,
        .values = values,
    };
}

fn managed_scalar_list_field_for_child(
    node: *const marshal.MarshalNode,
    field_index: u32,
    expected_offset: u32,
) ?ManagedScalarListField {
    if (node.kind != .list or node.children.len != 1) return null;
    const payload_facts = node.measured orelse return null;
    if (payload_facts.offset != expected_offset or payload_facts.byte_size != 8 or payload_facts.alignment != 4 or
        payload_facts.pointer_offset != 0 or payload_facts.length_offset != 4)
    {
        return null;
    }
    const element = &node.children[0];
    if (element.kind != .scalar) return null;
    const element_facts = element.measured orelse return null;
    const kind = switch (element.scalar_kind orelse return null) {
        .u8 => ScalarListElementKind.byte,
        .u32 => ScalarListElementKind.u32,
        else => return null,
    };
    const expected_size: u32 = switch (kind) {
        .byte => 1,
        .u32 => 4,
    };
    const expected_alignment: u32 = expected_size;
    if (element_facts.byte_size != expected_size or element_facts.alignment != expected_alignment or
        (kind == .u32 and element_facts.core_type != .i32) or
        (kind == .byte and element_facts.core_type != null)) return null;
    const element_stride = payload_facts.element_stride orelse return null;
    if (element_stride != expected_size) return null;
    const element_byte_size = payload_facts.element_byte_size orelse return null;
    const element_alignment = payload_facts.element_alignment orelse return null;
    const capacity = payload_facts.capacity orelse return null;
    if (element_byte_size != expected_size or element_alignment != expected_alignment or capacity == 0) return null;

    return .{
        .field_index = field_index,
        .pointer_offset = payload_facts.pointer_offset orelse return null,
        .length_offset = payload_facts.length_offset orelse return null,
        .element_kind = kind,
        .element_byte_size = element_byte_size,
        .element_alignment = element_alignment,
        .element_stride = element_stride,
        .capacity = capacity,
    };
}

fn managed_mixed_scalar_list_lower_for_root(node: *const marshal.MarshalNode) ?ManagedMixedScalarListLower {
    if (node.kind != .record or node.children.len != 3) return null;
    const root_facts = node.measured orelse return null;
    if (root_facts.indirect != null or root_facts.byte_size != 20 or root_facts.alignment != 4) return null;

    const code = &node.children[0];
    if (code.kind != .scalar or code.scalar_kind != .u32) return null;
    const code_facts = code.measured orelse return null;
    if (code_facts.offset != 0 or code_facts.byte_size != 4 or code_facts.alignment != 4 or code_facts.core_type != .i32) {
        return null;
    }

    const label = &node.children[1];
    if (label.kind != .text or label.measured == null or !has_managed_text_layout(label)) return null;
    const label_facts = label.measured.?;
    if (label_facts.offset != 4 or label_facts.pointer_offset.? != 0 or label_facts.length_offset.? != 4) return null;

    const payload = &node.children[2];
    if (payload.kind != .list or payload.children.len != 1) return null;
    const payload_facts = payload.measured orelse return null;
    if (payload_facts.offset != 12 or payload_facts.byte_size != 8 or payload_facts.alignment != 4 or
        payload_facts.pointer_offset != 0 or payload_facts.length_offset != 4 or
        payload_facts.capacity == null or payload_facts.capacity.? == 0)
    {
        return null;
    }
    const element = &payload.children[0];
    if (element.kind != .scalar) return null;
    const element_facts = element.measured orelse return null;
    const element_kind = switch (element.scalar_kind orelse return null) {
        .u8 => ScalarListElementKind.byte,
        .u32 => ScalarListElementKind.u32,
        else => return null,
    };
    const expected_size: u32 = switch (element_kind) {
        .byte => 1,
        .u32 => 4,
    };
    if (element_facts.byte_size != expected_size or element_facts.alignment != expected_size or
        (element_kind == .byte and element_facts.core_type != null) or
        (element_kind == .u32 and element_facts.core_type != .i32)) return null;
    if (payload_facts.element_byte_size != expected_size or
        payload_facts.element_stride != expected_size or
        payload_facts.element_alignment != expected_size) return null;

    return .{
        .text = .{
            .field_index = 1,
            .pointer_offset = label_facts.pointer_offset.?,
            .length_offset = label_facts.length_offset.?,
        },
        .scalar_list = .{
            .field_index = 2,
            .pointer_offset = payload_facts.pointer_offset.?,
            .length_offset = payload_facts.length_offset.?,
            .element_kind = element_kind,
            .element_byte_size = payload_facts.element_byte_size.?,
            .element_alignment = payload_facts.element_alignment.?,
            .element_stride = payload_facts.element_stride.?,
            .capacity = payload_facts.capacity.?,
        },
    };
}

fn has_managed_text_layout(node: *const marshal.MarshalNode) bool {
    const facts = node.measured orelse return false;
    return facts.pointer_offset != null and facts.length_offset != null and
        facts.byte_size == 8 and facts.alignment == 4;
}

fn validate_managed_text_child(node: *const marshal.MarshalNode) !void {
    if (node.kind != .text or !has_managed_text_layout(node)) return error.UnsupportedMarshalShape;
}

fn validate_flat_record_scalar(child: *const marshal.MarshalNode) !void {
    if (child.kind != .scalar) return error.UnsupportedMarshalShape;
    switch (child.scalar_kind orelse return error.UnsupportedMarshalShape) {
        .u32, .u64, .i64 => {},
        else => return error.UnsupportedMarshalShape,
    }
    const facts = child.measured orelse return error.MeasuredChildMissing;
    if (facts.core_type == null) return error.MeasuredScalarCoreTypeMissing;
}

pub fn validate_linear_span(pointer: u32, length: u32, memory_size: u32) !void {
    if (pointer > memory_size) return error.PointerOutOfBounds;
    if (length > memory_size - pointer) return error.LengthOutOfBounds;
}

pub fn copy_byte_count(length: u32, stride: u32) !u32 {
    if (stride == 0) return error.InvalidCopyStride;
    const total = @as(u64, length) * @as(u64, stride);
    if (total > std.math.maxInt(u32)) return error.CopyByteCountOverflow;
    return @as(u32, @intCast(total));
}

fn operations_for(direction: marshal.Direction) []const MemoryOperation {
    return switch (direction) {
        .lower => &lower_operations,
        .lift => &lift_operations,
    };
}

fn map_operations_for(direction: marshal.Direction) []const MemoryOperation {
    return switch (direction) {
        .lower => &map_lower_operations,
        .lift => &map_lift_operations,
    };
}

const lower_operations = [_]MemoryOperation{
    .read_gc_span,
    .validate_linear_range,
    .cabi_realloc_alloc,
    .copy_to_linear,
    .canonical_call,
    .cabi_realloc_free,
};

const lift_operations = [_]MemoryOperation{
    .canonical_call,
    .validate_linear_range,
    .copy_from_linear,
    .construct_gc_value,
    .publish_gc_root,
    .cabi_realloc_free,
};

const scalar_operations = [_]MemoryOperation{
    .canonical_call,
};

const map_lower_operations = [_]MemoryOperation{
    .read_gc_span,
    .validate_linear_range,
    .cabi_realloc_alloc,
    .copy_to_linear,
    .canonical_call,
    .cabi_realloc_free,
};

const map_lift_operations = [_]MemoryOperation{
    .canonical_call,
    .validate_linear_range,
    .copy_from_linear,
    .construct_gc_value,
    .publish_gc_root,
    .cabi_realloc_free,
};

const record_lower_operations = [_]MemoryOperation{
    .read_gc_span,
    .flatten_gc_fields,
    .canonical_call,
};

const record_indirect_lower_operations = [_]MemoryOperation{
    .read_gc_span,
    .validate_linear_range,
    .cabi_realloc_alloc,
    .flatten_gc_fields,
    .canonical_call,
    .cabi_realloc_free,
};

const record_managed_text_lower_operations = [_]MemoryOperation{
    .read_gc_span,
    .cabi_realloc_alloc,
    .copy_to_linear,
    .canonical_call,
    .cabi_realloc_free,
};

const record_managed_text_lower_multi_operations = [_]MemoryOperation{
    .read_gc_span,
    .cabi_realloc_alloc,
    .copy_to_linear,
    .cabi_realloc_alloc,
    .copy_to_linear,
    .canonical_call,
    .cabi_realloc_free,
    .cabi_realloc_free,
};

const record_managed_scalar_list_lower_operations = [_]MemoryOperation{
    .read_gc_span,
    .validate_linear_range,
    .cabi_realloc_alloc,
    .copy_to_linear,
    .canonical_call,
    .cabi_realloc_free,
};

const record_managed_scalar_list_pair_lower_operations = [_]MemoryOperation{
    .read_gc_span,
    .validate_linear_range,
    .cabi_realloc_alloc,
    .copy_to_linear,
    .validate_linear_range,
    .cabi_realloc_alloc,
    .copy_to_linear,
    .canonical_call,
    .cabi_realloc_free,
    .cabi_realloc_free,
};

const record_managed_text_scalar_list_pair_lower_operations = [_]MemoryOperation{
    .read_gc_span,
    .cabi_realloc_alloc,
    .copy_to_linear,
    .validate_linear_range,
    .cabi_realloc_alloc,
    .copy_to_linear,
    .validate_linear_range,
    .cabi_realloc_alloc,
    .copy_to_linear,
    .canonical_call,
    .cabi_realloc_free,
    .cabi_realloc_free,
    .cabi_realloc_free,
};

const record_managed_mixed_scalar_list_lower_operations = [_]MemoryOperation{
    .read_gc_span,
    .validate_linear_range,
    .cabi_realloc_alloc,
    .copy_to_linear,
    .validate_linear_range,
    .cabi_realloc_alloc,
    .copy_to_linear,
    .canonical_call,
    .cabi_realloc_free,
    .cabi_realloc_free,
};

const record_lift_operations = [_]MemoryOperation{
    .canonical_call,
    .validate_linear_range,
    .copy_from_linear,
    .construct_gc_value,
    .publish_gc_root,
};

const record_mixed_text_two_u32_lists_lift_operations = [_]MemoryOperation{
    .canonical_call,
    .validate_linear_range,
    .validate_linear_range,
    .validate_linear_range,
    .validate_linear_range,
    .copy_from_linear,
    .copy_from_linear,
    .copy_from_linear,
    .construct_gc_value,
    .publish_gc_root,
    .cabi_realloc_free,
    .cabi_realloc_free,
    .cabi_realloc_free,
};

test "marshal operation plan preserves lower and lift ordering" {
    try std.testing.expectEqual(MemoryOperation.read_gc_span, lower_operations[0]);
    try std.testing.expectEqual(MemoryOperation.cabi_realloc_free, lower_operations[5]);
    try std.testing.expectEqual(MemoryOperation.canonical_call, lift_operations[0]);
    try std.testing.expectEqual(MemoryOperation.publish_gc_root, lift_operations[4]);
}

test "marshal operation plan admits only the measured managed-text record lower root" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var label = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer label.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "label", .value = &label },
    });
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-managed-lower@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 12,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .text = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .byte_size = 8,
                .alignment = 4,
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } } },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);
    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expect(memory_plan.record_managed_text_lower);
    try std.testing.expectEqual(@as(u8, 1), memory_plan.managed_text_field_count);
    try std.testing.expectEqual(ManagedTextField{ .field_index = 1, .pointer_offset = 0, .length_offset = 4 }, memory_plan.managed_text_fields[0]);
    try std.testing.expectEqual(@as(usize, 5), memory_plan.operations.len);
    try std.testing.expectEqual(MemoryOperation.canonical_call, memory_plan.operations[3]);
    try std.testing.expectEqual(MemoryOperation.cabi_realloc_free, memory_plan.operations[4]);
}

test "marshal operation plan orders two managed-text lower fields" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var label = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer label.deinit();
    var note = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer note.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "label", .value = &label },
        .{ .name = "note", .value = &note },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-managed-lower-multi@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 20,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
                .{ .name = "note", .offset = 12, .byte_size = 8, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .text = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .byte_size = 8,
                .alignment = 4,
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } } },
            .{ .layout = .{ .text = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .byte_size = 8,
                .alignment = 4,
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } } },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expectEqual(@as(u8, 2), memory_plan.managed_text_field_count);
    try std.testing.expectEqual(ManagedTextField{ .field_index = 1, .pointer_offset = 0, .length_offset = 4 }, memory_plan.managed_text_fields[0]);
    try std.testing.expectEqual(ManagedTextField{ .field_index = 2, .pointer_offset = 0, .length_offset = 4 }, memory_plan.managed_text_fields[1]);
    try std.testing.expectEqual(@as(usize, 8), memory_plan.operations.len);
    try std.testing.expectEqual(MemoryOperation.read_gc_span, memory_plan.operations[0]);
    try std.testing.expectEqual(MemoryOperation.cabi_realloc_alloc, memory_plan.operations[1]);
    try std.testing.expectEqual(MemoryOperation.copy_to_linear, memory_plan.operations[2]);
    try std.testing.expectEqual(MemoryOperation.cabi_realloc_alloc, memory_plan.operations[3]);
    try std.testing.expectEqual(MemoryOperation.copy_to_linear, memory_plan.operations[4]);
    try std.testing.expectEqual(MemoryOperation.canonical_call, memory_plan.operations[5]);
    try std.testing.expectEqual(MemoryOperation.cabi_realloc_free, memory_plan.operations[6]);
    try std.testing.expectEqual(MemoryOperation.cabi_realloc_free, memory_plan.operations[7]);
}

test "marshal operation plan rejects text outside the managed-text root positions" {
    var first = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer first.deinit();
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var last = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer last.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "first", .value = &first },
        .{ .name = "code", .value = &code },
        .{ .name = "last", .value = &last },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-managed-lower-invalid@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 20,
            .alignment = 4,
            .fields = &.{
                .{ .name = "first", .offset = 0, .byte_size = 8, .alignment = 4, .indirect = null },
                .{ .name = "code", .offset = 8, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "last", .offset = 12, .byte_size = 8, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .text = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .byte_size = 8,
                .alignment = 4,
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } } },
            .{ .layout = .{ .scalar = .{ .offset = 8, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .text = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .byte_size = 8,
                .alignment = 4,
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } } },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    try std.testing.expectError(error.UnsupportedMarshalShape, build_sync_memory_plan(&plan));
}

test "marshal operation plan admits measured scalar direct calls" {
    var value = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal@1.0.0",
        .world = "probe",
        .member = "api.scalar",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    }, &value, .lower, .{ .layout = .{ .scalar = .{
        .offset = 0,
        .byte_size = 4,
        .alignment = 4,
        .core_type = .i32,
    } } });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expectEqual(CopyShape.scalar, memory_plan.copy_shape);
    try std.testing.expectEqual(@as(usize, 1), memory_plan.operations.len);
    try std.testing.expectEqual(MemoryOperation.canonical_call, memory_plan.operations[0]);
}

test "marshal operation plan admits measured u32 list copies" {
    var element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer element.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &element);
    defer value.deinit();
    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal@1.0.0",
        .world = "probe",
        .member = "api.send",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:4444444444444444444444444444444444444444444444444444444444444444",
    }, &value, .lower, .{ .layout = .{ .list = .{
        .pointer_offset = 0,
        .length_offset = 4,
        .element_byte_size = 4,
        .element_stride = 4,
        .element_alignment = 4,
        .ticket_offset = 0,
        .capacity = 4,
        .accepted_lengths = &.{ 0, 1, 2, 3, 4 },
        .allocation = .cabi_realloc,
        .free = .cabi_realloc,
    } }, .children = &.{.{ .layout = .{ .scalar = .{
        .offset = 0,
        .byte_size = 4,
        .alignment = 4,
        .core_type = .i32,
    } } }} });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expectEqual(CopyShape.list_elements, memory_plan.copy_shape);
    try std.testing.expectEqual(@as(u32, 4), memory_plan.element_stride);
    try std.testing.expectEqual(@as(usize, 6), memory_plan.operations.len);
}

test "marshal operation plan admits a measured scalar map pair-list" {
    var key = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer key.deinit();
    var value = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer value.deinit();
    var map = try @import("wit_abi_types.zig").AbiType.map(std.testing.allocator, &key, &value);
    defer map.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-map@1.0.0",
        .world = "probe",
        .member = "api.lookup",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:5555555555555555555555555555555555555555555555555555555555555555",
    }, &map, .lower, .{
        .layout = .{ .map = .{
            .pointer_offset = 0,
            .length_offset = 4,
            .element_byte_size = 8,
            .element_stride = 8,
            .element_alignment = 4,
            .key = .{ .offset = 0, .byte_size = 4, .alignment = 4 },
            .value = .{ .offset = 4, .byte_size = 4, .alignment = 4 },
            .capacity = 4,
            .accepted_lengths = &.{ 0, 1, 4 },
            .allocation = .cabi_realloc,
            .free = .cabi_realloc,
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .scalar = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expectEqual(CopyShape.map_entries, memory_plan.copy_shape);
    try std.testing.expectEqual(@as(u32, 8), memory_plan.element_stride);
    try std.testing.expectEqual(@as(usize, 6), memory_plan.operations.len);
    try std.testing.expectEqual(MemoryOperation.read_gc_span, memory_plan.operations[0]);
    try std.testing.expectEqual(MemoryOperation.copy_to_linear, memory_plan.operations[3]);
    try std.testing.expectEqual(MemoryOperation.canonical_call, memory_plan.operations[4]);
    try std.testing.expectEqual(MemoryOperation.cabi_realloc_free, memory_plan.operations[5]);
}

test "marshal operation plan admits a bounded u32 list record lower" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer element.deinit();
    var payload = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &element);
    defer payload.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "payload", .value = &payload },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-u32-list-lower@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 12,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "payload", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .list = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .element_byte_size = 4,
                .element_stride = 4,
                .element_alignment = 4,
                .ticket_offset = 0,
                .capacity = 3,
                .accepted_lengths = &.{ 0, 1, 2, 3 },
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } }, .children = &.{.{ .layout = .{ .scalar = .{
                .offset = 0,
                .byte_size = 4,
                .alignment = 4,
                .core_type = .i32,
            } } }} },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expectEqual(CopyShape.record_fields, memory_plan.copy_shape);
    try std.testing.expect(memory_plan.record_managed_scalar_list_lower);
    try std.testing.expectEqual(ScalarListElementKind.u32, memory_plan.managed_scalar_list_field.?.element_kind);
    try std.testing.expectEqual(@as(u32, 4), memory_plan.managed_scalar_list_field.?.element_stride);
    try std.testing.expectEqual(@as(u32, 3), memory_plan.managed_scalar_list_field.?.capacity);
    try std.testing.expectEqual(@as(usize, 6), memory_plan.operations.len);
}

test "marshal operation plan admits a bounded two u32 list record lower" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var first_element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer first_element.deinit();
    var first = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &first_element);
    defer first.deinit();
    var second_element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer second_element.deinit();
    var second = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &second_element);
    defer second.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "first", .value = &first },
        .{ .name = "second", .value = &second },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-two-u32-lists-lower@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:two-u32-list-record-lower-v1",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 20,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "first", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
                .{ .name = "second", .offset = 12, .byte_size = 8, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .list = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .element_byte_size = 4,
                .element_stride = 4,
                .element_alignment = 4,
                .ticket_offset = 0,
                .capacity = 3,
                .accepted_lengths = &.{ 0, 1, 2, 3 },
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } }, .children = &.{.{ .layout = .{ .scalar = .{
                .offset = 0,
                .byte_size = 4,
                .alignment = 4,
                .core_type = .i32,
            } } }} },
            .{ .layout = .{ .list = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .element_byte_size = 4,
                .element_stride = 4,
                .element_alignment = 4,
                .ticket_offset = 0,
                .capacity = 2,
                .accepted_lengths = &.{ 0, 1, 2 },
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } }, .children = &.{.{ .layout = .{ .scalar = .{
                .offset = 0,
                .byte_size = 4,
                .alignment = 4,
                .core_type = .i32,
            } } }} },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expectEqual(CopyShape.record_fields, memory_plan.copy_shape);
    try std.testing.expect(memory_plan.record_managed_scalar_list_pair_lower);
    const pair = memory_plan.managed_scalar_list_pair_lower orelse unreachable;
    try std.testing.expectEqual(@as(u32, 1), pair.first.field_index);
    try std.testing.expectEqual(@as(u32, 2), pair.second.field_index);
    try std.testing.expectEqual(ScalarListElementKind.u32, pair.first.element_kind);
    try std.testing.expectEqual(ScalarListElementKind.u32, pair.second.element_kind);
    try std.testing.expectEqual(@as(u32, 3), pair.first.capacity);
    try std.testing.expectEqual(@as(u32, 2), pair.second.capacity);
    try std.testing.expectEqual(@as(usize, 10), memory_plan.operations.len);
    const expected = [_]MemoryOperation{
        .read_gc_span,
        .validate_linear_range,
        .cabi_realloc_alloc,
        .copy_to_linear,
        .validate_linear_range,
        .cabi_realloc_alloc,
        .copy_to_linear,
        .canonical_call,
        .cabi_realloc_free,
        .cabi_realloc_free,
    };
    try std.testing.expectEqualSlices(MemoryOperation, &expected, memory_plan.operations);
}

test "marshal operation plan admits a bounded byte-list record through the shared route" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u8);
    defer element.deinit();
    var payload = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &element);
    defer payload.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "payload", .value = &payload },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-byte-list-lower@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 12,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "payload", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .byte_list = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .element_byte_size = 1,
                .element_stride = 1,
                .element_alignment = 1,
                .capacity = 4,
                .accepted_lengths = &.{ 0, 1, 2, 3, 4 },
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } } },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expect(memory_plan.record_managed_scalar_list_lower);
    try std.testing.expectEqual(ScalarListElementKind.byte, memory_plan.managed_scalar_list_field.?.element_kind);
    try std.testing.expectEqual(@as(u32, 1), memory_plan.managed_scalar_list_field.?.element_stride);
    try std.testing.expectEqual(@as(u32, 4), memory_plan.managed_scalar_list_field.?.capacity);
    try std.testing.expectEqual(@as(usize, 6), memory_plan.operations.len);
}

test "marshal operation plan admits a bounded mixed text and byte-list record lower" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var label = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer label.deinit();
    var element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u8);
    defer element.deinit();
    var payload = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &element);
    defer payload.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "label", .value = &label },
        .{ .name = "payload", .value = &payload },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-mixed-scalar-list-lower@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:mixed-scalar-list-record-lower-v1",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 20,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
                .{ .name = "payload", .offset = 12, .byte_size = 8, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .text = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .byte_size = 8,
                .alignment = 4,
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } } },
            .{ .layout = .{ .byte_list = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .element_byte_size = 1,
                .element_stride = 1,
                .element_alignment = 1,
                .capacity = 4,
                .accepted_lengths = &.{ 0, 1, 2, 3, 4 },
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } } },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expect(memory_plan.record_managed_mixed_scalar_list_lower);
    const mixed = memory_plan.managed_mixed_scalar_list_lower orelse unreachable;
    try std.testing.expectEqual(@as(u32, 1), mixed.text.field_index);
    try std.testing.expectEqual(@as(u32, 2), mixed.scalar_list.field_index);
    try std.testing.expectEqual(ScalarListElementKind.byte, mixed.scalar_list.element_kind);
    try std.testing.expectEqual(@as(u32, 1), mixed.scalar_list.element_stride);
    try std.testing.expectEqual(@as(u32, 4), mixed.scalar_list.capacity);
    try std.testing.expectEqual(@as(usize, 10), memory_plan.operations.len);
    const expected = [_]MemoryOperation{
        .read_gc_span,
        .validate_linear_range,
        .cabi_realloc_alloc,
        .copy_to_linear,
        .validate_linear_range,
        .cabi_realloc_alloc,
        .copy_to_linear,
        .canonical_call,
        .cabi_realloc_free,
        .cabi_realloc_free,
    };
    try std.testing.expectEqualSlices(MemoryOperation, &expected, memory_plan.operations);
}

test "marshal operation plan admits exact mixed text byte/u32 lists and rejects capacity drift" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var label = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer label.deinit();
    var byte_element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u8);
    defer byte_element.deinit();
    var bytes = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &byte_element);
    defer bytes.deinit();
    var value_element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer value_element.deinit();
    var values = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &value_element);
    defer values.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "label", .value = &label },
        .{ .name = "bytes", .value = &bytes },
        .{ .name = "values", .value = &values },
    });
    defer value.deinit();

    var plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-mixed-text-byte-u32-lists-lower@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:mixed-text-byte-u32-lists-record-lower-v1",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 28,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
                .{ .name = "bytes", .offset = 12, .byte_size = 8, .alignment = 4, .indirect = null },
                .{ .name = "values", .offset = 20, .byte_size = 8, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .text = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .byte_size = 8,
                .alignment = 4,
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } } },
            .{ .layout = .{ .byte_list = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .element_byte_size = 1,
                .element_stride = 1,
                .element_alignment = 1,
                .capacity = 4,
                .accepted_lengths = &.{ 0, 1, 2, 3, 4 },
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } } },
            .{ .layout = .{ .list = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .element_byte_size = 4,
                .element_stride = 4,
                .element_alignment = 4,
                .ticket_offset = 0,
                .capacity = 3,
                .accepted_lengths = &.{ 0, 1, 2, 3 },
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } }, .children = &.{.{ .layout = .{ .scalar = .{
                .offset = 0,
                .byte_size = 4,
                .alignment = 4,
                .core_type = .i32,
            } } }} },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expect(memory_plan.record_managed_text_byte_u32_list_lower);
    const mixed = memory_plan.managed_text_byte_u32_list_lower orelse unreachable;
    try std.testing.expectEqual(ScalarListElementKind.byte, mixed.bytes.element_kind);
    try std.testing.expectEqual(ScalarListElementKind.u32, mixed.values.element_kind);
    try std.testing.expectEqual(@as(u32, 4), mixed.bytes.capacity);
    try std.testing.expectEqual(@as(u32, 3), mixed.values.capacity);
    try std.testing.expectEqual(@as(usize, 13), memory_plan.operations.len);
    const expected = [_]MemoryOperation{
        .read_gc_span,
        .cabi_realloc_alloc,
        .copy_to_linear,
        .validate_linear_range,
        .cabi_realloc_alloc,
        .copy_to_linear,
        .validate_linear_range,
        .cabi_realloc_alloc,
        .copy_to_linear,
        .canonical_call,
        .cabi_realloc_free,
        .cabi_realloc_free,
        .cabi_realloc_free,
    };
    try std.testing.expectEqualSlices(MemoryOperation, &expected, memory_plan.operations);

    plan.root.children[2].measured.?.capacity = 5;
    plan.root.children[3].measured.?.capacity = 4;
    try std.testing.expectError(error.UnsupportedMarshalShape, build_sync_memory_plan(&plan));
}

test "marshal operation plan admits a bounded mixed text and u32-list record lower" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var label = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer label.deinit();
    var element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer element.deinit();
    var payload = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &element);
    defer payload.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "label", .value = &label },
        .{ .name = "payload", .value = &payload },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-mixed-text-u32-list-lower@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:mixed-text-u32-list-record-lower-v1",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 20,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
                .{ .name = "payload", .offset = 12, .byte_size = 8, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .text = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .byte_size = 8,
                .alignment = 4,
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } } },
            .{
                .layout = .{ .list = .{
                    .pointer_offset = 0,
                    .length_offset = 4,
                    .element_byte_size = 4,
                    .element_stride = 4,
                    .element_alignment = 4,
                    .ticket_offset = 0,
                    .capacity = 3,
                    .accepted_lengths = &.{ 0, 1, 2, 3 },
                    .allocation = .cabi_realloc,
                    .free = .cabi_realloc,
                } },
                .children = &.{.{ .layout = .{ .scalar = .{
                    .offset = 0,
                    .byte_size = 4,
                    .alignment = 4,
                    .core_type = .i32,
                } } }},
            },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expect(memory_plan.record_managed_mixed_scalar_list_lower);
    const mixed = memory_plan.managed_mixed_scalar_list_lower orelse unreachable;
    try std.testing.expectEqual(@as(u32, 1), mixed.text.field_index);
    try std.testing.expectEqual(@as(u32, 2), mixed.scalar_list.field_index);
    try std.testing.expectEqual(ScalarListElementKind.u32, mixed.scalar_list.element_kind);
    try std.testing.expectEqual(@as(u32, 4), mixed.scalar_list.element_byte_size);
    try std.testing.expectEqual(@as(u32, 4), mixed.scalar_list.element_alignment);
    try std.testing.expectEqual(@as(u32, 4), mixed.scalar_list.element_stride);
    try std.testing.expectEqual(@as(u32, 3), mixed.scalar_list.capacity);
    try std.testing.expectEqual(@as(usize, 10), memory_plan.operations.len);
    const expected = [_]MemoryOperation{
        .read_gc_span,
        .validate_linear_range,
        .cabi_realloc_alloc,
        .copy_to_linear,
        .validate_linear_range,
        .cabi_realloc_alloc,
        .copy_to_linear,
        .canonical_call,
        .cabi_realloc_free,
        .cabi_realloc_free,
    };
    try std.testing.expectEqualSlices(MemoryOperation, &expected, memory_plan.operations);
}

test "marshal operation plan admits a bounded mixed text and two u32-list record lower" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var label = @import("wit_abi_types.zig").AbiType.text(std.testing.allocator);
    defer label.deinit();
    var first_element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer first_element.deinit();
    var first = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &first_element);
    defer first.deinit();
    var second_element = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer second_element.deinit();
    var second = try @import("wit_abi_types.zig").AbiType.list(std.testing.allocator, &second_element);
    defer second.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "label", .value = &label },
        .{ .name = "first", .value = &first },
        .{ .name = "second", .value = &second },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-mixed-text-two-u32-lists-lower@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wasm-tools-1.255.0",
        .schema_hash = "sha256:mixed-text-two-u32-lists-record-lower-v1",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 28,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "label", .offset = 4, .byte_size = 8, .alignment = 4, .indirect = null },
                .{ .name = "first", .offset = 12, .byte_size = 8, .alignment = 4, .indirect = null },
                .{ .name = "second", .offset = 20, .byte_size = 8, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .text = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .byte_size = 8,
                .alignment = 4,
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } } },
            .{ .layout = .{ .list = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .element_byte_size = 4,
                .element_stride = 4,
                .element_alignment = 4,
                .ticket_offset = 0,
                .capacity = 3,
                .accepted_lengths = &.{ 0, 1, 2, 3 },
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } }, .children = &.{.{ .layout = .{ .scalar = .{
                .offset = 0,
                .byte_size = 4,
                .alignment = 4,
                .core_type = .i32,
            } } }} },
            .{ .layout = .{ .list = .{
                .pointer_offset = 0,
                .length_offset = 4,
                .element_byte_size = 4,
                .element_stride = 4,
                .element_alignment = 4,
                .ticket_offset = 0,
                .capacity = 2,
                .accepted_lengths = &.{ 0, 1, 2 },
                .allocation = .cabi_realloc,
                .free = .cabi_realloc,
            } }, .children = &.{.{ .layout = .{ .scalar = .{
                .offset = 0,
                .byte_size = 4,
                .alignment = 4,
                .core_type = .i32,
            } } }} },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expect(memory_plan.record_managed_text_scalar_list_pair_lower);
    const mixed = memory_plan.managed_text_scalar_list_pair_lower orelse unreachable;
    try std.testing.expectEqual(@as(u32, 1), mixed.text.field_index);
    try std.testing.expectEqual(@as(u32, 2), mixed.first.field_index);
    try std.testing.expectEqual(@as(u32, 3), mixed.second.field_index);
    try std.testing.expectEqual(@as(u32, 3), mixed.first.capacity);
    try std.testing.expectEqual(@as(u32, 2), mixed.second.capacity);
    try std.testing.expectEqual(@as(usize, 13), memory_plan.operations.len);
    const expected = [_]MemoryOperation{
        .read_gc_span,
        .cabi_realloc_alloc,
        .copy_to_linear,
        .validate_linear_range,
        .cabi_realloc_alloc,
        .copy_to_linear,
        .validate_linear_range,
        .cabi_realloc_alloc,
        .copy_to_linear,
        .canonical_call,
        .cabi_realloc_free,
        .cabi_realloc_free,
        .cabi_realloc_free,
    };
    try std.testing.expectEqualSlices(MemoryOperation, &expected, memory_plan.operations);
}

test "marshal operation plan admits measured scalar record lift" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var count = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer count.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "count", .value = &count },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record@1.0.0",
        .world = "probe",
        .member = "api.read",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:5555555555555555555555555555555555555555555555555555555555555555",
    }, &value, .lift, .{
        .layout = .{ .record = .{
            .byte_size = 8,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "count", .offset = 4, .byte_size = 4, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .scalar = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expectEqual(CopyShape.record_fields, memory_plan.copy_shape);
    try std.testing.expectEqual(@as(u32, 2), memory_plan.record_field_count);
    try std.testing.expectEqual(@as(usize, 5), memory_plan.operations.len);
    try std.testing.expectEqual(MemoryOperation.canonical_call, memory_plan.operations[0]);
    try std.testing.expectEqual(MemoryOperation.publish_gc_root, memory_plan.operations[4]);
}

test "marshal operation plan admits measured nested scalar record lift" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var count = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u64);
    defer count.deinit();
    var header = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "count", .value = &count },
    });
    defer header.deinit();
    var status = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .i64);
    defer status.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "header", .value = &header },
        .{ .name = "status", .value = &status },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record-nested@1.0.0",
        .world = "probe",
        .member = "api.read",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:7777777777777777777777777777777777777777777777777777777777777777",
    }, &value, .lift, .{
        .layout = .{ .record = .{
            .byte_size = 32,
            .alignment = 8,
            .fields = &.{
                .{ .name = "header", .offset = 0, .byte_size = 16, .alignment = 8, .indirect = null },
                .{ .name = "status", .offset = 16, .byte_size = 8, .alignment = 8, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .record = .{
                .byte_size = 16,
                .alignment = 8,
                .fields = &.{
                    .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                    .{ .name = "count", .offset = 8, .byte_size = 8, .alignment = 8, .indirect = null },
                },
            } }, .children = &.{
                .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
                .{ .layout = .{ .scalar = .{ .offset = 8, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
            } },
            .{ .layout = .{ .scalar = .{ .offset = 16, .byte_size = 8, .alignment = 8, .core_type = .i64 } } },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expectEqual(CopyShape.record_fields, memory_plan.copy_shape);
    try std.testing.expectEqual(marshal.Direction.lift, memory_plan.direction);
    try std.testing.expectEqual(@as(u32, 2), memory_plan.record_field_count);
    try std.testing.expectEqual(@as(usize, 5), memory_plan.operations.len);
}

test "marshal operation plan admits measured scalar record lower" {
    var code = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer code.deinit();
    var count = @import("wit_abi_types.zig").AbiType.scalar(std.testing.allocator, .u32);
    defer count.deinit();
    var value = try @import("wit_abi_types.zig").AbiType.record(std.testing.allocator, &.{
        .{ .name = "code", .value = &code },
        .{ .name = "count", .value = &count },
    });
    defer value.deinit();

    const plan = try marshal.build_sync_value_plan_with_layout(std.testing.allocator, .{
        .package = "demo:marshal-record@1.0.0",
        .world = "probe",
        .member = "api.write",
        .revision = "wit-resolver-v1",
        .schema_hash = "sha256:6666666666666666666666666666666666666666666666666666666666666666",
    }, &value, .lower, .{
        .layout = .{ .record = .{
            .byte_size = 8,
            .alignment = 4,
            .fields = &.{
                .{ .name = "code", .offset = 0, .byte_size = 4, .alignment = 4, .indirect = null },
                .{ .name = "count", .offset = 4, .byte_size = 4, .alignment = 4, .indirect = null },
            },
        } },
        .children = &.{
            .{ .layout = .{ .scalar = .{ .offset = 0, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
            .{ .layout = .{ .scalar = .{ .offset = 4, .byte_size = 4, .alignment = 4, .core_type = .i32 } } },
        },
    });
    defer marshal.deinit_sync_value_plan(std.testing.allocator, plan);

    const memory_plan = try build_sync_memory_plan(&plan);
    try std.testing.expectEqual(CopyShape.record_fields, memory_plan.copy_shape);
    try std.testing.expectEqual(marshal.Direction.lower, memory_plan.direction);
    try std.testing.expectEqual(@as(u32, 2), memory_plan.record_field_count);
    try std.testing.expectEqual(@as(usize, 3), memory_plan.operations.len);
    try std.testing.expectEqual(MemoryOperation.read_gc_span, memory_plan.operations[0]);
    try std.testing.expectEqual(MemoryOperation.flatten_gc_fields, memory_plan.operations[1]);
    try std.testing.expectEqual(MemoryOperation.canonical_call, memory_plan.operations[2]);
}
