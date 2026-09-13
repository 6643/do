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

    producer_contract.validate_contract(program.contract) catch return error.InvalidContract;

    // These counts are derived from borrowed mapping facts. Check them before
    // the mapping validator so missing model dimensions have their own error.
    if (program.mapping.ownership.len == 0 or program.mapping.frames.len == 0) {
        return error.InvalidGroupCount;
    }

    _ = mapping_probe.validate_facts(program.mapping) catch return error.InvalidMapping;

    const group_count = program.contract.batch_count orelse 1;
    const assets_per_group = std.math.cast(u32, program.mapping.ownership.len) orelse
        return error.UnsupportedProbeBound;
    if (group_count == 0 or assets_per_group == 0) return error.InvalidGroupCount;
    const asset_count = std.math.mul(u32, group_count, assets_per_group) catch
        return error.UnsupportedProbeBound;

    return .{
        .route_id = program.route_id,
        .group_count = group_count,
        .assets_per_group = assets_per_group,
        .asset_count = asset_count,
    };
}

pub fn run(program: LifecycleProgram) LifecycleError!TraceObservation {
    _ = program;
    return error.TraceIncomplete;
}

fn same(left: []const u8, right: []const u8) bool {
    return std.mem.eql(u8, left, right);
}
