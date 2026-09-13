const std = @import("std");
const producer_contract = @import("codegen_component_producer_contract.zig");
const mapping_probe = @import("codegen_component_producer_mapping_probe.zig");

pub const LifecycleError = error{
    InvalidIdentity,
    InvalidContract,
    InvalidMapping,
    UnsupportedProbeBound,
    InvalidGroupCount,
    InvalidAsset,
    DuplicateAcquire,
    AcquireAfterCancel,
    WriteAfterCancel,
    WriteIncomplete,
    TransferBeforeWrite,
    DuplicateTransfer,
    TransferAfterCancel,
    AssetNotOwned,
    GuestReleaseAfterTransfer,
    DuplicateRelease,
    InvalidReleaseOrder,
    CleanupBeforeAssets,
    CleanupStageMismatch,
    CleanupAfterTerminal,
    DuplicateCancel,
    CancelAfterTerminal,
    TerminalBeforeAssets,
    TerminalBeforeCleanup,
    DuplicateTerminal,
    TraceIncomplete,
};

pub const AssetKind = enum { resource, list_backing };
pub const Disposition = enum { transfer_to_host, release_after_copy };
pub const AssetState = enum { absent, guest_owned, transferred, released };
pub const TerminalState = enum { active, cancel_requested, completed };

pub const AssetId = struct { group_index: u32, asset_index: u32 };

pub const AssetSpec = struct {
    kind: AssetKind,
    disposition: Disposition,
    path: []const []const u8,
};

pub const Model = struct {
    assets: [64]AssetSpec,
    asset_count: u32,
    group_count: u32,
    assets_per_group: u32,
};

pub const LifecycleEvent = union(enum) {
    acquire: AssetId,
    write_complete: u32,
    transfer_commit: u32,
    cancel: void,
    release: AssetId,
    cleanup_stage: producer_contract.CleanupStage,
    terminal: void,
};

pub const LifecycleProgram = struct {
    route_id: []const u8,
    contract: producer_contract.ProducerContract,
    mapping: mapping_probe.TemplateFact,
    events: []const LifecycleEvent,
};

pub const ProgramReport = struct {
    route_id: []const u8,
    group_count: u32,
    assets_per_group: u32,
    asset_count: u32,
};

pub const TraceObservation = struct {
    acquired_count: u32,
    transferred_count: u32,
    released_count: u32,
    cleanup_stage_count: u32,
    group_count: u32,
    asset_count: u32,
    terminal_state: TerminalState,
};

pub fn validate_program(program: LifecycleProgram) LifecycleError!ProgramReport {
    if (program.route_id.len == 0 or !same(program.route_id, program.mapping.route_id)) {
        return error.InvalidIdentity;
    }

    const model = try build_model(program);

    return .{
        .route_id = program.route_id,
        .group_count = model.group_count,
        .assets_per_group = model.assets_per_group,
        .asset_count = model.asset_count,
    };
}

pub fn derive_model_for_test(program: LifecycleProgram) LifecycleError!Model {
    if (program.route_id.len == 0 or !same(program.route_id, program.mapping.route_id)) {
        return error.InvalidIdentity;
    }
    return build_model(program);
}

fn build_model(program: LifecycleProgram) LifecycleError!Model {
    producer_contract.validate_contract(program.contract) catch return error.InvalidContract;
    if (program.mapping.ownership.len == 0 or program.mapping.frames.len == 0) {
        return error.InvalidGroupCount;
    }
    _ = mapping_probe.validate_facts(program.mapping) catch return error.InvalidMapping;

    const group_count = std.math.cast(u32, program.mapping.ownership.len) orelse
        return error.UnsupportedProbeBound;
    if (program.contract.batch_count) |batch_count| {
        if (batch_count != group_count) return error.InvalidGroupCount;
    } else if (group_count != 1) {
        return error.InvalidGroupCount;
    }
    if (group_count == 0 or group_count > 64) return error.UnsupportedProbeBound;

    var schema: [64]AssetSpec = undefined;
    var schema_count: u32 = 0;
    for (program.contract.ownership.leaves) |leaf| {
        if (schema_count >= 64) return error.UnsupportedProbeBound;
        schema[schema_count] = .{ .kind = .resource, .disposition = .transfer_to_host, .path = leaf.path };
        schema_count += 1;
    }
    for (program.contract.list_allocations) |allocation| {
        if (schema_count >= 64) return error.UnsupportedProbeBound;
        schema[schema_count] = .{ .kind = .list_backing, .disposition = .release_after_copy, .path = allocation.path };
        schema_count += 1;
    }

    switch (program.contract.payload) {
        .list => |layout| {
            var covered = false;
            for (program.contract.list_allocations) |allocation| {
                if (allocation.pointer_offset == layout.pointer_offset and
                    allocation.length_offset == layout.length_offset and
                    allocation.element_stride == layout.element_stride and
                    allocation.max_items == layout.max_items)
                {
                    covered = true;
                    break;
                }
            }
            if (!covered) {
                if (schema_count >= 64) return error.UnsupportedProbeBound;
                schema[schema_count] = .{ .kind = .list_backing, .disposition = .release_after_copy, .path = &.{} };
                schema_count += 1;
            }
        },
        else => {},
    }
    if (schema_count == 0) return error.InvalidAsset;
    const asset_count = std.math.mul(u32, group_count, schema_count) catch
        return error.UnsupportedProbeBound;
    if (asset_count > 64) return error.UnsupportedProbeBound;

    var assets: [64]AssetSpec = undefined;
    for (0..group_count) |group_index| {
        const base = group_index * @as(usize, @intCast(schema_count));
        for (0..schema_count) |asset_index| {
            assets[base + asset_index] = schema[asset_index];
        }
    }
    return .{ .assets = assets, .asset_count = asset_count, .group_count = group_count, .assets_per_group = schema_count };
}

pub fn asset_bit(model: Model, id: AssetId) LifecycleError!u8 {
    if (id.group_index >= model.group_count or id.asset_index >= model.assets_per_group) {
        return error.InvalidAsset;
    }
    const index = std.math.add(u32, std.math.mul(u32, id.group_index, model.assets_per_group) catch return error.InvalidAsset, id.asset_index) catch
        return error.InvalidAsset;
    if (index >= model.asset_count or index >= model.assets.len) return error.InvalidAsset;
    return std.math.cast(u8, index) orelse return error.InvalidAsset;
}

pub fn run(program: LifecycleProgram) LifecycleError!TraceObservation {
    _ = try validate_program(program);
    const model = try derive_model_for_test(program);

    var acquired_mask: u64 = 0;
    var transferred_mask: u64 = 0;
    var released_mask: u64 = 0;
    var written_groups: u64 = 0;
    var transferred_groups: u64 = 0;
    var acquisition_order: [64]u8 = undefined;
    var acquisition_len: u8 = 0;
    var cleanup_cursor: usize = 0;
    var terminal_state: TerminalState = .active;
    var acquired_count: u32 = 0;
    var transferred_count: u32 = 0;
    var released_count: u32 = 0;
    var cleanup_stage_count: u32 = 0;

    for (program.events) |event| {
        switch (event) {
            .acquire => |id| {
                if (terminal_state != .active) return error.AcquireAfterCancel;
                const bit = try asset_bit(model, id);
                const mask = bit_mask(bit);
                if ((acquired_mask & mask) != 0) return error.DuplicateAcquire;
                const group_mask = try group_bit(model, id.group_index);
                if ((written_groups & group_mask) != 0) return error.WriteIncomplete;
                acquired_mask |= mask;
                acquisition_order[acquisition_len] = bit;
                acquisition_len += 1;
                acquired_count += 1;
            },
            .write_complete => |group_index| {
                if (terminal_state != .active) return error.WriteAfterCancel;
                const group_mask = try group_bit(model, group_index);
                var complete = true;
                for (0..model.assets_per_group) |asset_index| {
                    const bit = try asset_bit(model, .{
                        .group_index = group_index,
                        .asset_index = @intCast(asset_index),
                    });
                    if (!is_guest_owned(acquired_mask, transferred_mask, released_mask, bit)) {
                        complete = false;
                        break;
                    }
                }
                if (!complete) return error.WriteIncomplete;
                written_groups |= group_mask;
            },
            .transfer_commit => |group_index| {
                if (terminal_state != .active) return error.TransferAfterCancel;
                const group_mask = try group_bit(model, group_index);
                if ((transferred_groups & group_mask) != 0) return error.DuplicateTransfer;
                if ((written_groups & group_mask) == 0) return error.TransferBeforeWrite;

                for (0..model.assets_per_group) |asset_index| {
                    const bit = try asset_bit(model, .{
                        .group_index = group_index,
                        .asset_index = @intCast(asset_index),
                    });
                    if (!is_guest_owned(acquired_mask, transferred_mask, released_mask, bit)) {
                        return error.WriteIncomplete;
                    }
                }

                for (0..model.assets_per_group) |asset_index| {
                    const global_index = @as(usize, @intCast(group_index)) *
                        @as(usize, @intCast(model.assets_per_group)) + asset_index;
                    const bit = try asset_bit(model, .{
                        .group_index = group_index,
                        .asset_index = @intCast(asset_index),
                    });
                    const mask = bit_mask(bit);
                    switch (model.assets[global_index].kind) {
                        .resource => {
                            transferred_mask |= mask;
                            transferred_count += 1;
                        },
                        .list_backing => {
                            released_mask |= mask;
                            released_count += 1;
                        },
                    }
                }
                transferred_groups |= group_mask;
            },
            .cancel => {
                switch (terminal_state) {
                    .active => terminal_state = .cancel_requested,
                    .cancel_requested => return error.DuplicateCancel,
                    .completed => return error.CancelAfterTerminal,
                }
            },
            .release => |id| {
                const bit = try asset_bit(model, id);
                const mask = bit_mask(bit);
                if ((transferred_mask & mask) != 0) return error.GuestReleaseAfterTransfer;
                if ((released_mask & mask) != 0) return error.DuplicateRelease;
                if ((acquired_mask & mask) == 0) return error.AssetNotOwned;

                var cursor: usize = 0;
                while (cursor < acquisition_len) : (cursor += 1) {
                    if (acquisition_order[cursor] != bit) continue;
                    var later = cursor + 1;
                    while (later < acquisition_len) : (later += 1) {
                        if (is_guest_owned(
                            acquired_mask,
                            transferred_mask,
                            released_mask,
                            acquisition_order[later],
                        )) return error.InvalidReleaseOrder;
                    }
                    break;
                }
                released_mask |= mask;
                released_count += 1;
            },
            .cleanup_stage => |stage| {
                if (terminal_state == .completed) return error.CleanupAfterTerminal;
                if (has_guest_assets(model, acquired_mask, transferred_mask, released_mask)) {
                    return error.CleanupBeforeAssets;
                }
                if (cleanup_cursor >= program.contract.terminal.cleanup_order.len or
                    program.contract.terminal.cleanup_order[cleanup_cursor] != stage)
                {
                    return error.CleanupStageMismatch;
                }
                cleanup_cursor += 1;
                cleanup_stage_count += 1;
            },
            .terminal => {
                switch (terminal_state) {
                    .completed => return error.DuplicateTerminal,
                    .active, .cancel_requested => {},
                }
                if (has_guest_assets(model, acquired_mask, transferred_mask, released_mask)) {
                    return error.TerminalBeforeAssets;
                }
                if (!all_groups_finalized(model, transferred_mask, released_mask) or
                    cleanup_cursor != program.contract.terminal.cleanup_order.len)
                {
                    return error.TerminalBeforeCleanup;
                }
                terminal_state = .completed;
            },
        }
    }

    if (terminal_state != .completed) return error.TraceIncomplete;
    return .{
        .acquired_count = acquired_count,
        .transferred_count = transferred_count,
        .released_count = released_count,
        .cleanup_stage_count = cleanup_stage_count,
        .group_count = model.group_count,
        .asset_count = model.asset_count,
        .terminal_state = terminal_state,
    };
}

fn bit_mask(bit: u8) u64 {
    return @as(u64, 1) << @intCast(bit);
}

fn group_bit(model: Model, group_index: u32) LifecycleError!u64 {
    if (group_index >= model.group_count or group_index >= 64) return error.InvalidAsset;
    return bit_mask(@intCast(group_index));
}

fn is_guest_owned(acquired_mask: u64, transferred_mask: u64, released_mask: u64, bit: u8) bool {
    const mask = bit_mask(bit);
    return (acquired_mask & mask) != 0 and
        (transferred_mask & mask) == 0 and
        (released_mask & mask) == 0;
}

fn has_guest_assets(model: Model, acquired_mask: u64, transferred_mask: u64, released_mask: u64) bool {
    for (0..model.asset_count) |index| {
        if (is_guest_owned(acquired_mask, transferred_mask, released_mask, @intCast(index))) return true;
    }
    return false;
}

fn all_groups_finalized(model: Model, transferred_mask: u64, released_mask: u64) bool {
    for (0..model.asset_count) |index| {
        const mask = bit_mask(@intCast(index));
        if ((transferred_mask & mask) == 0 and (released_mask & mask) == 0) return false;
    }
    return true;
}

fn same(left: []const u8, right: []const u8) bool {
    return std.mem.eql(u8, left, right);
}
