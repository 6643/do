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
                    allocation.max_items == layout.max_items) {
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
    _ = program;
    return error.TraceIncomplete;
}

fn same(left: []const u8, right: []const u8) bool {
    return std.mem.eql(u8, left, right);
}
