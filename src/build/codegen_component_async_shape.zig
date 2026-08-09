pub const ShapeError = error{
    InvalidFrameAlignment,
    InvalidFrameSlot,
    InvalidFrameSize,
    InvalidCleanupOrder,
};

pub const BoundedAsyncMode = enum {
    child,
    inline_call,
    host_scalar,
};

pub const BoundedFrameLayout = struct {
    size: u32,
    alignment: u32,
    waitable_set_offset: u32,
    active_subtask_offset: u32,
    phase_offset: u32,
    u32_argument_offset: ?u32,
};

pub const BoundedCleanupAction = enum {
    cancel_active_subtask,
    drop_active_subtask_if_owned,
    drop_waitable_set,
    clear_root_context,
    free_root_frame,
    create_next_waitable_set,
    start_next_child,
    root_task_return,
    root_task_cancel,
};

pub const BoundedCleanupContract = struct {
    normal: []const BoundedCleanupAction,
    phase_transition: []const BoundedCleanupAction,
    cancelled: []const BoundedCleanupAction,
};

pub const BoundedAsyncShape = struct {
    mode: BoundedAsyncMode,
    frame: BoundedFrameLayout,
    cleanup: BoundedCleanupContract,

    pub fn validate(self: BoundedAsyncShape) ShapeError!void {
        if (self.frame.alignment != 4) return error.InvalidFrameAlignment;
        if (self.frame.waitable_set_offset != 0 or
            self.frame.active_subtask_offset != 4 or
            self.frame.phase_offset != 8)
        {
            return error.InvalidFrameSlot;
        }

        const has_argument = self.frame.u32_argument_offset != null;
        if ((has_argument and self.frame.size != 20) or
            (!has_argument and self.frame.size != 16))
        {
            return error.InvalidFrameSize;
        }

        if (!slot_is_valid(self.frame.waitable_set_offset, self.frame.size) or
            !slot_is_valid(self.frame.active_subtask_offset, self.frame.size) or
            !slot_is_valid(self.frame.phase_offset, self.frame.size))
        {
            return error.InvalidFrameSlot;
        }
        if (self.frame.u32_argument_offset) |offset| {
            if (offset != 12 or !slot_is_valid(offset, self.frame.size)) {
                return error.InvalidFrameSlot;
            }
        }

        try validate_terminal_sequence(self.cleanup.normal, false, false);
        try validate_phase_transition(self.mode, self.cleanup.phase_transition);
        try validate_terminal_sequence(self.cleanup.cancelled, true, self.mode == .child);
    }
};

const no_actions = [_]BoundedCleanupAction{};

const normal_actions = [_]BoundedCleanupAction{
    .drop_active_subtask_if_owned,
    .drop_waitable_set,
    .clear_root_context,
    .free_root_frame,
    .root_task_return,
};

const inline_phase_transition_actions = [_]BoundedCleanupAction{
    .drop_active_subtask_if_owned,
    .drop_waitable_set,
    .create_next_waitable_set,
    .start_next_child,
};

const cancelled_actions = [_]BoundedCleanupAction{
    .cancel_active_subtask,
    .drop_active_subtask_if_owned,
    .drop_waitable_set,
    .clear_root_context,
    .free_root_frame,
    .root_task_cancel,
};

pub fn child_shape(with_u32_argument: bool) ShapeError!BoundedAsyncShape {
    return make_shape(.child, with_u32_argument, normal_actions[0..], no_actions[0..], no_actions[0..]);
}

pub fn inline_shape(with_u32_argument: bool) ShapeError!BoundedAsyncShape {
    return make_shape(
        .inline_call,
        with_u32_argument,
        normal_actions[0..],
        inline_phase_transition_actions[0..],
        cancelled_actions[0..],
    );
}

pub fn host_scalar_shape() ShapeError!BoundedAsyncShape {
    return make_shape(.host_scalar, true, normal_actions[0..], no_actions[0..], cancelled_actions[0..]);
}

fn make_shape(
    mode: BoundedAsyncMode,
    with_u32_argument: bool,
    normal: []const BoundedCleanupAction,
    phase_transition: []const BoundedCleanupAction,
    cancelled: []const BoundedCleanupAction,
) ShapeError!BoundedAsyncShape {
    const shape = BoundedAsyncShape{
        .mode = mode,
        .frame = .{
            .size = if (with_u32_argument) 20 else 16,
            .alignment = 4,
            .waitable_set_offset = 0,
            .active_subtask_offset = 4,
            .phase_offset = 8,
            .u32_argument_offset = if (with_u32_argument) 12 else null,
        },
        .cleanup = .{
            .normal = normal,
            .phase_transition = phase_transition,
            .cancelled = cancelled,
        },
    };
    try shape.validate();
    return shape;
}

fn slot_is_valid(offset: u32, size: u32) bool {
    return offset % 4 == 0 and offset + 4 <= size;
}

fn validate_phase_transition(mode: BoundedAsyncMode, actions: []const BoundedCleanupAction) ShapeError!void {
    if (mode != .inline_call) {
        if (actions.len != 0) return error.InvalidCleanupOrder;
        return;
    }
    if (actions.len != inline_phase_transition_actions.len) return error.InvalidCleanupOrder;
    for (inline_phase_transition_actions, 0..) |expected, index| {
        if (actions[index] != expected) return error.InvalidCleanupOrder;
    }
}

fn validate_terminal_sequence(
    actions: []const BoundedCleanupAction,
    cancelled: bool,
    allow_empty: bool,
) ShapeError!void {
    if (actions.len == 0) {
        if (allow_empty) return;
        return error.InvalidCleanupOrder;
    }

    const expected_terminal: BoundedCleanupAction = if (cancelled) .root_task_cancel else .root_task_return;
    const forbidden_terminal: BoundedCleanupAction = if (cancelled) .root_task_return else .root_task_cancel;
    if (count_action(actions, expected_terminal) != 1 or count_action(actions, forbidden_terminal) != 0) {
        return error.InvalidCleanupOrder;
    }
    if (actions[actions.len - 1] != expected_terminal) return error.InvalidCleanupOrder;
    if (count_action(actions, .create_next_waitable_set) != 0 or
        count_action(actions, .start_next_child) != 0)
    {
        return error.InvalidCleanupOrder;
    }

    const drop_index = index_of(actions, .drop_active_subtask_if_owned) orelse return error.InvalidCleanupOrder;
    const waitable_index = index_of(actions, .drop_waitable_set) orelse return error.InvalidCleanupOrder;
    const clear_index = index_of(actions, .clear_root_context) orelse return error.InvalidCleanupOrder;
    const free_index = index_of(actions, .free_root_frame) orelse return error.InvalidCleanupOrder;
    if (drop_index >= waitable_index or waitable_index >= clear_index or clear_index >= free_index or
        free_index >= actions.len - 1)
    {
        return error.InvalidCleanupOrder;
    }

    if (cancelled) {
        if (actions[0] != .cancel_active_subtask or drop_index != 1) return error.InvalidCleanupOrder;
    } else if (count_action(actions, .cancel_active_subtask) != 0) {
        return error.InvalidCleanupOrder;
    }
}

fn count_action(actions: []const BoundedCleanupAction, expected: BoundedCleanupAction) usize {
    var count: usize = 0;
    for (actions) |action| {
        if (action == expected) count += 1;
    }
    return count;
}

fn index_of(actions: []const BoundedCleanupAction, expected: BoundedCleanupAction) ?usize {
    for (actions, 0..) |action, index| {
        if (action == expected) return index;
    }
    return null;
}
