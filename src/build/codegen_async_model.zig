const std = @import("std");
const lexer = @import("lexer.zig");
const codegen_collect_functions = @import("codegen_collect_functions.zig");
const codegen_emit_async = @import("codegen_emit_async.zig");
const codegen_model = @import("codegen_model.zig");

pub const AwaitSite = struct {
    token_index: usize,
    live_slots: []const FrameSlot,
    active_defers: []const DeferSite = &.{},
};

pub const FrameSlotStorage = enum {
    i32,
    i64,
    f32,
    f64,
    waitable,
    unsupported,
};

pub const FrameSlot = struct {
    name: []const u8,
    storage: FrameSlotStorage,
};

pub const FutureReadState = enum {
    readable,
    read_pending,
    cancel_pending,
    terminal,
    dropped,
};

pub const FutureReadOutcome = enum {
    pending,
    ready,
    dropped,
};

pub const FutureCancelOutcome = enum {
    pending,
    ready,
};

pub const FutureReadLifecycle = struct {
    state: FutureReadState = .readable,

    pub fn begin_read(self: *FutureReadLifecycle) !void {
        if (self.state != .readable) return error.FutureReadUnavailable;
        self.state = .read_pending;
    }

    pub fn observe_read(self: *FutureReadLifecycle, outcome: FutureReadOutcome) !void {
        if (self.state != .read_pending) return error.FutureReadNotPending;
        switch (outcome) {
            .pending => {},
            .ready, .dropped => self.state = .terminal,
        }
    }

    pub fn request_cancel(self: *FutureReadLifecycle, outcome: FutureCancelOutcome) !void {
        if (self.state != .read_pending) return error.FutureReadNotPending;
        self.state = switch (outcome) {
            .pending => .cancel_pending,
            .ready => .terminal,
        };
    }

    pub fn observe_cancel(self: *FutureReadLifecycle) !void {
        if (self.state != .cancel_pending) return error.FutureCancelNotPending;
        self.state = .terminal;
    }

    pub fn drop(self: *FutureReadLifecycle) !void {
        switch (self.state) {
            .read_pending, .cancel_pending => return error.FutureReadStillPending,
            .dropped => return error.FutureReadAlreadyDropped,
            .readable, .terminal => self.state = .dropped,
        }
    }
};

pub const ResultFutureState = enum {
    created,
    pending,
    ready,
    cancel_pending,
    terminal,
    dropped,
};

pub const ResultFutureLifecycle = struct {
    state: ResultFutureState = .created,
    operation_count: u32 = 0,
    external_effect_count: u32 = 0,
    drop_count: u32 = 0,

    pub fn begin(self: *ResultFutureLifecycle) !void {
        switch (self.state) {
            .created => {
                self.state = .pending;
                self.operation_count += 1;
            },
            .dropped => return error.ResultFutureAlreadyDropped,
            else => return error.ResultFutureAlreadyStarted,
        }
    }

    pub fn observe(self: *ResultFutureLifecycle, outcome: FutureReadOutcome) !void {
        if (self.state != .pending) return error.ResultFutureNotPending;
        switch (outcome) {
            .pending => {},
            .ready => self.state = .ready,
            .dropped => return error.ResultFutureHostDropped,
        }
    }

    pub fn commit_external_effect(self: *ResultFutureLifecycle) !void {
        if (self.state != .pending) return error.ResultFutureNotPending;
        if (self.external_effect_count != 0) return error.ResultExternalEffectAlreadyCommitted;
        self.external_effect_count = 1;
    }

    pub fn request_cancel(self: *ResultFutureLifecycle, outcome: FutureCancelOutcome) !void {
        if (self.state != .pending) return error.ResultFutureNotPending;
        self.state = switch (outcome) {
            .pending => .cancel_pending,
            .ready => .terminal,
        };
    }

    pub fn observe_cancel(self: *ResultFutureLifecycle) !void {
        if (self.state != .cancel_pending) return error.ResultFutureCancelNotPending;
        self.state = .terminal;
    }

    pub fn consume(self: *ResultFutureLifecycle) !void {
        if (self.state != .ready) return error.ResultFutureNotReady;
        self.state = .terminal;
    }

    pub fn drop(self: *ResultFutureLifecycle) !void {
        switch (self.state) {
            .created, .pending, .cancel_pending => return error.ResultFutureStillPending,
            .ready => return error.ResultFutureNotConsumed,
            .terminal => {
                self.state = .dropped;
                self.drop_count += 1;
            },
            .dropped => return error.ResultFutureAlreadyDropped,
        }
    }
};

pub const StreamReaderState = enum {
    readable,
    read_pending,
    item_ready,
    eof,
    cancel_pending,
    terminal,
    dropped,
};

pub const StreamReaderReadOutcome = enum {
    pending,
    item,
    eof,
};

pub const StreamReaderLifecycle = struct {
    state: StreamReaderState = .readable,

    pub fn begin_read(self: *StreamReaderLifecycle) !void {
        if (self.state != .readable) return error.StreamReaderUnavailable;
        self.state = .read_pending;
    }

    pub fn observe_read(self: *StreamReaderLifecycle, outcome: StreamReaderReadOutcome) !void {
        if (self.state != .read_pending) return error.StreamReaderReadNotPending;
        self.state = switch (outcome) {
            .pending => .read_pending,
            .item => .item_ready,
            .eof => .eof,
        };
    }

    pub fn consume_item(self: *StreamReaderLifecycle) !void {
        if (self.state != .item_ready) return error.StreamReaderItemUnavailable;
        self.state = .readable;
    }

    pub fn request_cancel(self: *StreamReaderLifecycle) !void {
        if (self.state != .read_pending) return error.StreamReaderReadNotPending;
        self.state = .cancel_pending;
    }

    pub fn observe_cancel(self: *StreamReaderLifecycle) !void {
        if (self.state != .cancel_pending) return error.StreamReaderCancelNotPending;
        self.state = .terminal;
    }

    pub fn drop(self: *StreamReaderLifecycle) !void {
        switch (self.state) {
            .read_pending, .cancel_pending => return error.StreamReaderStillPending,
            .item_ready => return error.StreamReaderItemNotConsumed,
            .dropped => return error.StreamReaderAlreadyDropped,
            .readable, .eof, .terminal => self.state = .dropped,
        }
    }
};

pub const DeferSite = struct {
    token_index: usize,
    body_start: usize = 0,
    body_end: usize = 0,
};

pub const ResumeState = struct {
    id: u32,
    token_index: usize,
    live_slots: []const FrameSlot,
    active_defers: []const DeferSite,
};

pub const FrameModel = struct {
    resume_states: []ResumeState,
    cleanup_state: u32,

    pub fn collect(allocator: std.mem.Allocator, await_sites: []const AwaitSite) !FrameModel {
        if (await_sites.len >= std.math.maxInt(u32)) return error.TooManyAwaitStates;

        var resume_states = try allocator.alloc(ResumeState, await_sites.len);
        var initialized: usize = 0;
        errdefer {
            for (resume_states[0..initialized]) |state| {
                allocator.free(state.live_slots);
                allocator.free(state.active_defers);
            }
            allocator.free(resume_states);
        }

        for (await_sites, 0..) |await_site, index| {
            resume_states[index] = .{
                .id = @intCast(index + 1),
                .token_index = await_site.token_index,
                .live_slots = try allocator.dupe(FrameSlot, await_site.live_slots),
                .active_defers = try allocator.dupe(DeferSite, await_site.active_defers),
            };
            initialized += 1;
        }
        return .{
            .resume_states = resume_states,
            .cleanup_state = @intCast(await_sites.len + 1),
        };
    }

    pub fn collect_body(
        allocator: std.mem.Allocator,
        tokens: []const lexer.Token,
        body_start: usize,
        body_end: usize,
        params: []const FrameSlot,
    ) !FrameModel {
        var bindings: std.ArrayList(ScopedBinding) = .empty;
        defer bindings.deinit(allocator);
        try bindings.ensureUnusedCapacity(allocator, params.len);
        for (params) |slot| bindings.appendAssumeCapacity(.{ .slot = slot });

        var defers: std.ArrayList(ScopedDefer) = .empty;
        defer defers.deinit(allocator);

        var await_sites: std.ArrayList(AwaitSite) = .empty;
        defer {
            for (await_sites.items) |await_site| {
                allocator.free(await_site.live_slots);
                allocator.free(await_site.active_defers);
            }
            await_sites.deinit(allocator);
        }

        var depth: usize = 0;
        var idx = body_start;
        while (idx < body_end) : (idx += 1) {
            if (tok_eq(tokens[idx], "{")) {
                depth += 1;
                continue;
            }
            if (tok_eq(tokens[idx], "}")) {
                if (depth > 0) depth -= 1;
                trim_bindings_to_depth(&bindings, depth);
                trim_defers_to_depth(&defers, depth);
                continue;
            }
            if (tok_eq(tokens[idx], "defer")) {
                try defers.append(allocator, .{
                    .token_index = idx,
                    .body_start = idx + 1,
                    .body_end = defer_body_end(tokens, idx + 1, body_end),
                    .depth = depth,
                });
                continue;
            }
            if (is_await_name(tokens[idx])) {
                const live_slots = try collect_visible_slots(allocator, bindings.items);
                const active_defers = collect_active_defers(allocator, defers.items) catch |err| {
                    allocator.free(live_slots);
                    return err;
                };
                await_sites.append(allocator, .{
                    .token_index = idx,
                    .live_slots = live_slots,
                    .active_defers = active_defers,
                }) catch |err| {
                    allocator.free(live_slots);
                    allocator.free(active_defers);
                    return err;
                };
                continue;
            }
            if (!is_line_start(tokens, body_start, idx)) continue;
            const slot = typed_binding_slot(tokens, idx, body_end) orelse continue;
            try bindings.append(allocator, .{ .slot = slot, .depth = depth });
        }

        return collect(allocator, await_sites.items);
    }

    pub fn deinit(self: *FrameModel, allocator: std.mem.Allocator) void {
        for (self.resume_states) |state| {
            allocator.free(state.live_slots);
            allocator.free(state.active_defers);
        }
        allocator.free(self.resume_states);
        self.* = undefined;
    }
};

pub fn emit_resume_dispatch(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    frame: FrameModel,
) !void {
    for (frame.resume_states) |state| {
        const branch = try std.fmt.allocPrint(
            allocator,
            "  local.get $async_state\n  i32.const {d}\n  i32.eq\n  if\n    br $async_resume_{d}\n  end\n",
            .{ state.id, state.id },
        );
        defer allocator.free(branch);
        try out.appendSlice(allocator, branch);
    }
    try out.appendSlice(allocator, "  br $async_cleanup\n");
}

pub const FrameLayoutSlot = struct {
    name: []const u8,
    storage: FrameSlotStorage,
    offset: u32,
};

pub const FrameLayout = struct {
    state_offset: u32 = 0,
    waitable_set_offset: u32 = 4,
    cleanup_flags_offset: u32 = 8,
    completion_value_offset: u32 = 12,
    size: u32,
    slots: []FrameLayoutSlot,

    pub fn collect(allocator: std.mem.Allocator, frame: FrameModel) !FrameLayout {
        var slots: std.ArrayList(FrameLayoutSlot) = .empty;
        errdefer slots.deinit(allocator);

        var offset: u64 = 16;
        for (frame.resume_states) |state| {
            for (state.live_slots) |slot| {
                if (slot.storage == .unsupported) return error.UnsupportedAsyncFrameSlot;
                if (slot.storage == .waitable) continue;
                if (find_layout_slot(slots.items, slot.name)) |existing| {
                    if (existing.storage != slot.storage) return error.AsyncFrameSlotStorageMismatch;
                    continue;
                }
                const alignment = frame_slot_alignment(slot.storage);
                offset = try align_frame_offset(offset, alignment);
                if (offset > std.math.maxInt(u32)) return error.AsyncFrameTooLarge;
                try slots.append(allocator, .{
                    .name = slot.name,
                    .storage = slot.storage,
                    .offset = @intCast(offset),
                });
                offset += frame_slot_size(slot.storage);
            }
        }
        offset = try align_frame_offset(offset, 8);
        if (offset > std.math.maxInt(u32)) return error.AsyncFrameTooLarge;
        return .{ .size = @intCast(offset), .slots = try slots.toOwnedSlice(allocator) };
    }

    pub fn deinit(self: *FrameLayout, allocator: std.mem.Allocator) void {
        allocator.free(self.slots);
        self.* = undefined;
    }
};

fn find_layout_slot(slots: []const FrameLayoutSlot, name: []const u8) ?FrameLayoutSlot {
    for (slots) |slot| {
        if (std.mem.eql(u8, slot.name, name)) return slot;
    }
    return null;
}

fn frame_slot_alignment(storage: FrameSlotStorage) u64 {
    return switch (storage) {
        .i32, .f32 => 4,
        .i64, .f64 => 8,
        .waitable, .unsupported => unreachable,
    };
}

fn frame_slot_size(storage: FrameSlotStorage) u64 {
    return switch (storage) {
        .i32, .f32 => 4,
        .i64, .f64 => 8,
        .waitable, .unsupported => unreachable,
    };
}

fn align_frame_offset(offset: u64, alignment: u64) !u64 {
    const remainder = offset % alignment;
    if (remainder == 0) return offset;
    return std.math.add(u64, offset, alignment - remainder) catch error.AsyncFrameTooLarge;
}

pub fn align_frame_size(size: u32, alignment: u32) !u32 {
    if (alignment == 0) return error.InvalidAsyncFrameAlignment;
    const aligned = try align_frame_offset(size, alignment);
    if (aligned > std.math.maxInt(u32)) return error.AsyncFrameTooLarge;
    return @intCast(aligned);
}

test "generic frame size helper aligns to the requested boundary" {
    try std.testing.expectEqual(@as(u32, 16), try align_frame_size(12, 8));
    try std.testing.expectEqual(@as(u32, 24), try align_frame_size(17, 8));
    try std.testing.expectError(error.InvalidAsyncFrameAlignment, align_frame_size(12, 0));
}

pub const AsyncFunctionPlan = struct {
    name: []const u8,
    source_name: []const u8,
    frame: FrameModel,
    layout: FrameLayout,

    pub fn deinit(self: *AsyncFunctionPlan, allocator: std.mem.Allocator) void {
        self.layout.deinit(allocator);
        self.frame.deinit(allocator);
        self.* = undefined;
    }
};

pub const AsyncFunctionModel = AsyncFunctionPlan;

pub fn collect_async_functions(
    allocator: std.mem.Allocator,
    functions: []const codegen_model.FuncDecl,
) ![]AsyncFunctionPlan {
    var async_functions: std.ArrayList(AsyncFunctionPlan) = .empty;
    errdefer {
        for (async_functions.items) |*function| function.deinit(allocator);
        async_functions.deinit(allocator);
    }

    for (functions) |function| {
        if (!is_async_function(function)) continue;

        const param_slots = try allocator.alloc(FrameSlot, function.params.len);
        defer allocator.free(param_slots);
        for (function.params, 0..) |param, idx| {
            param_slots[idx] = .{
                .name = param.name,
                .storage = frame_slot_storage_from_type(param.ty),
            };
        }

        var frame = try FrameModel.collect_body(
            allocator,
            function.tokens,
            function.body_start,
            function.body_end,
            param_slots,
        );
        var frame_owned = true;
        errdefer if (frame_owned) frame.deinit(allocator);
        var layout = try FrameLayout.collect(allocator, frame);
        var layout_owned = true;
        errdefer if (layout_owned) layout.deinit(allocator);
        try async_functions.append(allocator, .{
            .name = function.name,
            .source_name = function.source_name,
            .frame = frame,
            .layout = layout,
        });
        frame_owned = false;
        layout_owned = false;
    }

    return async_functions.toOwnedSlice(allocator);
}

pub fn free_async_function_plans(allocator: std.mem.Allocator, plans: []AsyncFunctionPlan) void {
    for (plans) |*plan| plan.deinit(allocator);
    allocator.free(plans);
}

const ScopedBinding = struct {
    slot: FrameSlot,
    depth: usize = 0,
};

const ScopedDefer = struct {
    token_index: usize,
    body_start: usize,
    body_end: usize,
    depth: usize = 0,
};

fn is_await_name(token: lexer.Token) bool {
    return tok_eq(token, "await") or tok_eq(token, "await_all") or tok_eq(token, "await_any");
}

fn is_async_function(function: codegen_model.FuncDecl) bool {
    if (function.is_async or function.resumable or body_contains_async_operation(function.tokens, function.body_start, function.body_end)) return true;
    if (function.start_idx == 0 or function.start_idx >= function.tokens.len) return false;
    const modifier = function.tokens[function.start_idx - 1];
    const name = function.tokens[function.start_idx];
    return modifier.line == name.line and tok_eq(modifier, "async");
}

fn body_contains_async_operation(tokens: []const lexer.Token, start_idx: usize, end_idx: usize) bool {
    var idx = start_idx;
    while (idx < end_idx) : (idx += 1) {
        if (tok_eq(tokens[idx], "Future") or tok_eq(tokens[idx], "await") or
            (idx + 1 < end_idx and tok_eq(tokens[idx], "@") and
                (tok_eq(tokens[idx + 1], "async") or tok_eq(tokens[idx + 1], "await") or
                    tok_eq(tokens[idx + 1], "cancel")))) return true;
    }
    return false;
}

fn is_line_start(tokens: []const lexer.Token, body_start: usize, idx: usize) bool {
    return idx == body_start or
        tokens[idx - 1].line != tokens[idx].line or
        tok_eq(tokens[idx - 1], "{");
}

fn typed_binding_slot(tokens: []const lexer.Token, start_idx: usize, body_end: usize) ?FrameSlot {
    if (tokens[start_idx].kind != .ident or start_idx + 2 >= body_end) return null;
    if (tokens[start_idx + 1].kind != .ident) return null;

    var idx = start_idx + 2;
    while (idx < body_end and tokens[idx].line == tokens[start_idx].line) : (idx += 1) {
        if (tok_eq(tokens[idx], "=")) return .{
            .name = tokens[start_idx].lexeme,
            .storage = frame_slot_storage_from_type(tokens[start_idx + 1].lexeme),
        };
        if (tok_eq(tokens[idx], "(") or tok_eq(tokens[idx], "{")) return null;
    }
    return null;
}

fn trim_bindings_to_depth(bindings: *std.ArrayList(ScopedBinding), depth: usize) void {
    while (bindings.items.len > 0 and bindings.items[bindings.items.len - 1].depth > depth) {
        _ = bindings.pop();
    }
}

fn trim_defers_to_depth(defers: *std.ArrayList(ScopedDefer), depth: usize) void {
    while (defers.items.len > 0 and defers.items[defers.items.len - 1].depth > depth) {
        _ = defers.pop();
    }
}

fn collect_visible_slots(allocator: std.mem.Allocator, bindings: []const ScopedBinding) ![]const FrameSlot {
    var slots = try allocator.alloc(FrameSlot, bindings.len);
    for (bindings, 0..) |binding, idx| slots[idx] = binding.slot;
    return slots;
}

pub fn frame_slot_storage_from_type(ty: []const u8) FrameSlotStorage {
    if (std.mem.eql(u8, ty, "Future")) return .waitable;
    if (std.mem.eql(u8, ty, "i64") or std.mem.eql(u8, ty, "u64")) return .i64;
    if (std.mem.eql(u8, ty, "f32")) return .f32;
    if (std.mem.eql(u8, ty, "f64")) return .f64;
    if (std.mem.eql(u8, ty, "bool") or
        std.mem.eql(u8, ty, "i8") or std.mem.eql(u8, ty, "u8") or
        std.mem.eql(u8, ty, "i16") or std.mem.eql(u8, ty, "u16") or
        std.mem.eql(u8, ty, "i32") or std.mem.eql(u8, ty, "u32") or
        std.mem.eql(u8, ty, "isize") or std.mem.eql(u8, ty, "usize"))
    {
        return .i32;
    }
    return .unsupported;
}

pub fn frame_slot_storage_core_wasm_type(storage: FrameSlotStorage) ?[]const u8 {
    return switch (storage) {
        .i32 => "i32",
        .i64 => "i64",
        .f32 => "f32",
        .f64 => "f64",
        .waitable, .unsupported => null,
    };
}

fn collect_active_defers(allocator: std.mem.Allocator, defers: []const ScopedDefer) ![]const DeferSite {
    var sites = try allocator.alloc(DeferSite, defers.len);
    for (defers, 0..) |defer_site, idx| sites[idx] = .{
        .token_index = defer_site.token_index,
        .body_start = defer_site.body_start,
        .body_end = defer_site.body_end,
    };
    return sites;
}

fn defer_body_end(tokens: []const lexer.Token, start_idx: usize, body_end: usize) usize {
    if (start_idx >= body_end) return start_idx;
    const line = tokens[start_idx].line;
    var idx = start_idx;
    while (idx < body_end and tokens[idx].line == line) : (idx += 1) {}
    return idx;
}

fn tok_eq(token: lexer.Token, text: []const u8) bool {
    return std.mem.eql(u8, token.lexeme, text);
}

test "await sites receive distinct resume states and one cleanup state" {
    const first_slots = [_]FrameSlot{.{ .name = "request", .storage = .i32 }};
    const second_slots = [_]FrameSlot{
        .{ .name = "request", .storage = .i32 },
        .{ .name = "response", .storage = .i64 },
    };
    const await_sites = [_]AwaitSite{
        .{ .token_index = 12, .live_slots = &first_slots },
        .{ .token_index = 24, .live_slots = &second_slots },
    };

    var model = try FrameModel.collect(std.testing.allocator, &await_sites);
    defer model.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), model.resume_states.len);
    try std.testing.expectEqual(@as(u32, 1), model.resume_states[0].id);
    try std.testing.expectEqual(@as(u32, 2), model.resume_states[1].id);
    try std.testing.expectEqual(@as(usize, 12), model.resume_states[0].token_index);
    try std.testing.expectEqual(@as(usize, 2), model.resume_states[1].live_slots.len);
    try std.testing.expectEqual(@as(u32, 3), model.cleanup_state);
}

test "body collector captures visible bindings at each await" {
    const tokens = try lexer.tokenize(std.testing.allocator,
        \\outer i32 = 1
        \\await(outer)
        \\{
        \\    inner i32 = 2
        \\    await_all(outer, inner)
        \\}
    );
    defer std.testing.allocator.free(tokens);

    const params = [_]FrameSlot{.{ .name = "input", .storage = .i32 }};
    var model = try FrameModel.collect_body(std.testing.allocator, tokens, 0, tokens.len, &params);
    defer model.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), model.resume_states.len);
    try std.testing.expectEqualStrings("input", model.resume_states[0].live_slots[0].name);
    try std.testing.expectEqualStrings("outer", model.resume_states[0].live_slots[1].name);
    try std.testing.expectEqual(@as(usize, 3), model.resume_states[1].live_slots.len);
    try std.testing.expectEqualStrings("inner", model.resume_states[1].live_slots[2].name);
}

test "body collector classifies scalar frame slots" {
    const tokens = try lexer.tokenize(std.testing.allocator,
        \\small i32 = 1
        \\large u64 = 2
        \\ratio f32 = 3.0
        \\precise f64 = 4.0
        \\pending Future<nil> = nil
        \\await(pending)
    );
    defer std.testing.allocator.free(tokens);

    var model = try FrameModel.collect_body(std.testing.allocator, tokens, 0, tokens.len, &.{});
    defer model.deinit(std.testing.allocator);

    const slots = model.resume_states[0].live_slots;
    try std.testing.expectEqual(@as(usize, 5), slots.len);
    try std.testing.expectEqual(FrameSlotStorage.i32, slots[0].storage);
    try std.testing.expectEqual(FrameSlotStorage.i64, slots[1].storage);
    try std.testing.expectEqual(FrameSlotStorage.f32, slots[2].storage);
    try std.testing.expectEqual(FrameSlotStorage.f64, slots[3].storage);
    try std.testing.expectEqual(FrameSlotStorage.waitable, slots[4].storage);
}

test "body collector recognizes a declaration after an inline block open" {
    const tokens = try lexer.tokenize(std.testing.allocator,
        \\if true { inner i32 = 2
        \\    await(inner)
        \\}
    );
    defer std.testing.allocator.free(tokens);

    var model = try FrameModel.collect_body(std.testing.allocator, tokens, 0, tokens.len, &.{});
    defer model.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), model.resume_states.len);
    try std.testing.expectEqual(@as(usize, 1), model.resume_states[0].live_slots.len);
    try std.testing.expectEqualStrings("inner", model.resume_states[0].live_slots[0].name);
}

test "body collector keeps only lexically active defers at each await" {
    const tokens = try lexer.tokenize(std.testing.allocator,
        \\defer release(root)
        \\{
        \\    defer close(inner)
        \\    await(pending)
        \\}
        \\await(done)
    );
    defer std.testing.allocator.free(tokens);

    var model = try FrameModel.collect_body(std.testing.allocator, tokens, 0, tokens.len, &.{});
    defer model.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), model.resume_states.len);
    try std.testing.expectEqual(@as(usize, 2), model.resume_states[0].active_defers.len);
    try std.testing.expectEqual(@as(usize, 1), model.resume_states[1].active_defers.len);
    try std.testing.expectEqual(@as(usize, 0), model.resume_states[1].active_defers[0].token_index);
    try std.testing.expectEqual(@as(usize, 1), model.resume_states[1].active_defers[0].body_start);
    try std.testing.expectEqual(@as(usize, 5), model.resume_states[1].active_defers[0].body_end);
}

test "resume dispatch emits one branch per state and a cleanup fallback" {
    const await_sites = [_]AwaitSite{
        .{ .token_index = 10, .live_slots = &.{} },
        .{ .token_index = 20, .live_slots = &.{} },
    };
    var frame = try FrameModel.collect(std.testing.allocator, &await_sites);
    defer frame.deinit(std.testing.allocator);
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);

    try emit_resume_dispatch(std.testing.allocator, &out, frame);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "local.get $async_state") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "br $async_resume_1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "br $async_resume_2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "br $async_cleanup") != null);
}

test "frame layout stores resume state and deduplicated scalar live slots" {
    const first_slots = [_]FrameSlot{
        .{ .name = "delay", .storage = .i64 },
        .{ .name = "flag", .storage = .i32 },
    };
    const second_slots = [_]FrameSlot{
        .{ .name = "delay", .storage = .i64 },
        .{ .name = "ratio", .storage = .f64 },
    };
    const await_sites = [_]AwaitSite{
        .{ .token_index = 10, .live_slots = &first_slots },
        .{ .token_index = 20, .live_slots = &second_slots },
    };
    var frame = try FrameModel.collect(std.testing.allocator, &await_sites);
    defer frame.deinit(std.testing.allocator);

    var layout = try FrameLayout.collect(std.testing.allocator, frame);
    defer layout.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 0), layout.state_offset);
    try std.testing.expectEqual(@as(u32, 4), layout.waitable_set_offset);
    try std.testing.expectEqual(@as(u32, 8), layout.cleanup_flags_offset);
    try std.testing.expectEqual(@as(u32, 12), layout.completion_value_offset);
    try std.testing.expectEqual(@as(usize, 3), layout.slots.len);
    try std.testing.expectEqualStrings("delay", layout.slots[0].name);
    try std.testing.expectEqual(@as(u32, 16), layout.slots[0].offset);
    try std.testing.expectEqual(@as(u32, 40), layout.size);
}

test "async function collector captures parameters and locals at await" {
    const tokens = try lexer.tokenize(std.testing.allocator,
        \\async wait(input i32) -> nil {
        \\    pending i32 = 1
        \\    await(pending)
        \\}
    );
    defer std.testing.allocator.free(tokens);

    const functions = [_]codegen_model.FuncDecl{.{
        .name = "wait",
        .source_name = "wait",
        .params = &.{.{ .name = "input", .ty = "i32" }},
        .result = "nil",
        .results = &.{"nil"},
        .result_items = &.{},
        .result_struct = null,
        .result_union = null,
        .tokens = tokens,
        .start_idx = 1,
        .arrow = false,
        .body_start = 9,
        .body_end = 17,
    }};

    const async_functions = try collect_async_functions(std.testing.allocator, &functions);
    defer {
        for (async_functions) |function| {
            var owned_function = function;
            owned_function.deinit(std.testing.allocator);
        }
        std.testing.allocator.free(async_functions);
    }

    try std.testing.expectEqual(@as(usize, 1), async_functions.len);
    try std.testing.expectEqualStrings("wait", async_functions[0].name);
    try std.testing.expectEqual(@as(usize, 1), async_functions[0].frame.resume_states.len);
    try std.testing.expectEqualStrings("input", async_functions[0].frame.resume_states[0].live_slots[0].name);
    try std.testing.expectEqualStrings("pending", async_functions[0].frame.resume_states[0].live_slots[1].name);
}

test "parsed async function collects frame states and scalar slot offsets" {
    const tokens = try lexer.tokenize(std.testing.allocator,
        \\async run() -> nil {
        \\    count i32 = 1
        \\    await(wait_for())
        \\    delay i64 = 2
        \\    await(wait_for())
        \\}
    );
    defer std.testing.allocator.free(tokens);

    var functions = std.ArrayList(codegen_model.FuncDecl).empty;
    defer {
        codegen_model.free_func_decls(std.testing.allocator, functions.items);
        functions.deinit(std.testing.allocator);
    }
    try codegen_collect_functions.collect_func_decls(
        std.testing.allocator,
        tokens,
        &.{},
        &.{},
        null,
        &functions,
    );

    const async_functions = try collect_async_functions(std.testing.allocator, functions.items);
    defer {
        for (async_functions) |function| {
            var owned_function = function;
            owned_function.deinit(std.testing.allocator);
        }
        std.testing.allocator.free(async_functions);
    }

    try std.testing.expectEqual(@as(usize, 1), async_functions.len);
    try std.testing.expectEqual(@as(u32, 1), async_functions[0].frame.resume_states[0].id);
    try std.testing.expectEqual(@as(u32, 2), async_functions[0].frame.resume_states[1].id);
    try std.testing.expectEqual(@as(u32, 3), async_functions[0].frame.cleanup_state);

    var layout = try FrameLayout.collect(std.testing.allocator, async_functions[0].frame);
    defer layout.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 16), layout.slots[0].offset);
    try std.testing.expectEqual(@as(u32, 24), layout.slots[1].offset);

    var wat = std.ArrayList(u8).empty;
    defer wat.deinit(std.testing.allocator);
    try codegen_emit_async.emit_frame_metadata(
        std.testing.allocator,
        &wat,
        async_functions[0],
    );
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "[async-state] 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "[async-state] 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "[async-cleanup] 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "count offset=16") != null);
    try std.testing.expect(std.mem.indexOf(u8, wat.items, "delay offset=24") != null);
}

test "async function collector rejects unsupported captured slots" {
    const tokens = try lexer.tokenize(std.testing.allocator,
        \\async run() -> nil {
        \\    label text = "pending"
        \\    await(wait_for())
        \\}
    );
    defer std.testing.allocator.free(tokens);

    var functions = std.ArrayList(codegen_model.FuncDecl).empty;
    defer {
        codegen_model.free_func_decls(std.testing.allocator, functions.items);
        functions.deinit(std.testing.allocator);
    }
    try codegen_collect_functions.collect_func_decls(
        std.testing.allocator,
        tokens,
        &.{},
        &.{},
        null,
        &functions,
    );

    try std.testing.expectError(
        error.UnsupportedAsyncFrameSlot,
        collect_async_functions(std.testing.allocator, functions.items),
    );
}

test "future bindings use the waitable-set header instead of user frame slots" {
    const tokens = try lexer.tokenize(std.testing.allocator,
        \\async run(duration u64) -> nil {
        \\    pending Future<nil> = wait_for(duration)
        \\    await(pending)
        \\}
    );
    defer std.testing.allocator.free(tokens);

    var functions = std.ArrayList(codegen_model.FuncDecl).empty;
    defer {
        codegen_model.free_func_decls(std.testing.allocator, functions.items);
        functions.deinit(std.testing.allocator);
    }
    try codegen_collect_functions.collect_func_decls(
        std.testing.allocator,
        tokens,
        &.{},
        &.{},
        null,
        &functions,
    );

    const plans = try collect_async_functions(std.testing.allocator, functions.items);
    defer free_async_function_plans(std.testing.allocator, plans);

    try std.testing.expectEqual(@as(usize, 1), plans.len);
    try std.testing.expectEqual(@as(u32, 4), plans[0].layout.waitable_set_offset);
    try std.testing.expectEqual(@as(usize, 1), plans[0].layout.slots.len);
    try std.testing.expectEqualStrings("duration", plans[0].layout.slots[0].name);
}

test "future read lifecycle distinguishes ready, pending cancellation, and drop" {
    var ready = FutureReadLifecycle{};
    try ready.begin_read();
    try ready.observe_read(.ready);
    try ready.drop();
    try std.testing.expectEqual(FutureReadState.dropped, ready.state);

    var pending = FutureReadLifecycle{};
    try pending.begin_read();
    try pending.observe_read(.pending);
    try std.testing.expectError(error.FutureReadStillPending, pending.drop());
    try pending.request_cancel(.pending);
    try std.testing.expectEqual(FutureReadState.cancel_pending, pending.state);
    try pending.observe_cancel();
    try pending.drop();
    try std.testing.expectEqual(FutureReadState.dropped, pending.state);
}

test "future read lifecycle rejects cancel without an active read" {
    var lifecycle = FutureReadLifecycle{};
    try std.testing.expectError(error.FutureReadNotPending, lifecycle.request_cancel(.ready));
}

test "stream reader lifecycle distinguishes item EOF cancel and terminal drop" {
    var reader = StreamReaderLifecycle{};
    try reader.begin_read();
    try reader.observe_read(.pending);
    try reader.observe_read(.item);
    try reader.consume_item();
    try reader.begin_read();
    try reader.observe_read(.eof);
    try reader.drop();
    try std.testing.expectEqual(StreamReaderState.dropped, reader.state);

    var cancelled = StreamReaderLifecycle{};
    try cancelled.begin_read();
    try cancelled.request_cancel();
    try cancelled.observe_cancel();
    try cancelled.drop();
    try std.testing.expectEqual(StreamReaderState.dropped, cancelled.state);
}

test "Result future cancellation keeps one operation and one drop without rollback" {
    var pending = ResultFutureLifecycle{};
    try pending.begin();
    try pending.commit_external_effect();
    try pending.observe(.pending);
    try pending.request_cancel(.pending);
    try pending.observe_cancel();
    try pending.drop();

    try std.testing.expectEqual(ResultFutureState.dropped, pending.state);
    try std.testing.expectEqual(@as(u32, 1), pending.operation_count);
    try std.testing.expectEqual(@as(u32, 1), pending.external_effect_count);
    try std.testing.expectEqual(@as(u32, 1), pending.drop_count);
    try std.testing.expectError(error.ResultFutureAlreadyDropped, pending.begin());
    try std.testing.expectError(error.ResultFutureAlreadyDropped, pending.drop());
}

test "ready Result future is consumed and cannot be cancelled or replayed" {
    var ready = ResultFutureLifecycle{};
    try ready.begin();
    try ready.observe(.ready);
    try ready.consume();
    try ready.drop();

    try std.testing.expectEqual(ResultFutureState.dropped, ready.state);
    try std.testing.expectEqual(@as(u32, 1), ready.operation_count);
    try std.testing.expectEqual(@as(u32, 1), ready.drop_count);
    try std.testing.expectError(error.ResultFutureNotPending, ready.request_cancel(.ready));
    try std.testing.expectError(error.ResultFutureAlreadyDropped, ready.begin());
}

test "reader EOF and cancellation each permit one terminal drop only" {
    var eof = StreamReaderLifecycle{};
    try eof.begin_read();
    try eof.observe_read(.eof);
    try eof.drop();
    try std.testing.expectError(error.StreamReaderAlreadyDropped, eof.drop());
    try std.testing.expectError(error.StreamReaderUnavailable, eof.begin_read());

    var cancelled = StreamReaderLifecycle{};
    try cancelled.begin_read();
    try cancelled.request_cancel();
    try cancelled.observe_cancel();
    try cancelled.drop();
    try std.testing.expectError(error.StreamReaderAlreadyDropped, cancelled.drop());
    try std.testing.expectError(error.StreamReaderUnavailable, cancelled.begin_read());
}
