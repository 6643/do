const std = @import("std");
const p3_http_wit_manifest = @import("p3_http_wit_manifest.zig");
const p3_filesystem_wit_manifest = @import("p3_filesystem_wit_manifest.zig");

const max_nested_container_depth: u8 = 6;

pub const Descriptor = struct {
    locator: []const u8,
    member: []const u8,
    effect: []const u8,
    params: []const []const u8,
    result: []const u8,
    resource: ?[]const u8,
    wit_sha256: ?[]const u8,
    canonical: Canonical,
    wit: Wit,
};

pub const LoweringShape = union(enum) {
    scalar_unit: ScalarUnitShape,
    unit_result_tag: void,
    scalar_result: ScalarResultShape,
    future_owned_resource: FutureOwnedCanonical,
    resource_result_2word: ResourceResult2WordShape,
    http_resource_result: HttpResourceResultShape,
    http_request_constructor: HttpRequestConstructorShape,
    http_stream_reader: HttpStreamReaderShape,
    stream_reader_acquire: StreamReaderShape,
    record_stream_reader: RecordStreamReaderShape,
    record_resource_list_stream_reader: RecordResourceListStreamShape,
    record_resource_list_stream_producer: RecordResourceListStreamProducerShape,
    record_resource_list_stream_dynamic_producer: RecordResourceListStreamProducerShape,
    variant_resource_stream_reader: VariantResourceStreamShape,
    stream_writer: StreamWriterShape,
};

/// ABI facts observed for a record-valued stream that is intentionally not
/// admitted to lowering yet. Keep this separate from LoweringShape so the
/// manifest can preserve evidence without widening the compiler surface.
pub const UnsupportedShape = union(enum) {
    record_stream_reader: RecordStreamReaderShape,
};

pub const RecordStreamReaderShape = struct {
    element: []const u8,
    stream_index: usize,
    future_index: usize,
    method: StreamOperation,
    stream: StreamCanonical,
    future: FutureCanonical,
    record_layout: ?RecordLayout = null,
};

/// ABI facts for the one registered `stream<list<resource-entry>>` slice.
/// This is deliberately distinct from record streams: the list allocation and
/// per-element ownership transfer have their own bounded cleanup contract.
pub const RecordResourceListStreamShape = struct {
    element: []const u8,
    stream_index: usize,
    future_index: usize,
    method: StreamOperation,
    stream: StreamCanonical,
    future: FutureCanonical,
    record_layout: RecordLayout,
    list_layout: ListResourceLayout,
};

pub const RecordResourceListStreamProducerShape = struct {
    element: []const u8,
    stream_index: usize,
    method: StreamOperation,
    stream: StreamCanonical,
    record_layout: RecordLayout,
    list_layout: ListResourceLayout,
    producer: ProducerCanonical,
};

/// ABI facts for the private `stream<event>` probe. Unlike the general stream
/// records, this probe only imports the read/drop operations that were
/// measured by the hand-written canonical WAT.
pub const VariantResourceStreamShape = struct {
    element: []const u8,
    stream_index: usize,
    future_index: usize,
    stream_read: StreamOperation,
    stream_drop_readable: StreamOperation,
    future_read: StreamOperation,
    future_drop_readable: StreamOperation,
    ticket_drop_import: []const u8,
    event: VariantEventLayout,
};

pub const VariantEventLayout = struct {
    tag_offset: u32,
    payload_offset: u32,
    byte_size: u32,
    alignment: u32,
    variants: []const VariantEventBranch,
};

pub const VariantEventBranch = struct {
    name: []const u8,
    tag: u32,
    payload: ?[]const u8,
};

const VariantStreamCanonical = struct {
    element: []const u8,
    read: StreamOperation,
    drop_readable: StreamOperation,
};

const VariantFutureCanonical = struct {
    read: StreamOperation,
    drop_readable: StreamOperation,
};

pub const ListResourceLayout = struct {
    result_pointer_offset: u32,
    result_length_offset: u32,
    element_stride: u32,
    ticket_offset: u32,
    max_items: u32,
};

pub const ProducerCanonical = struct {
    source_module: []const u8,
    source_import_name: []const u8,
    source_core_params: []const []const u8,
    source_core_results: []const []const u8,
    resource_drop_import: []const u8,
    stream_capacity: u32,
    terminal: []const u8,
    runtime_count_param: ?[]const u8 = null,
    runtime_max: ?u32 = null,
};

pub const RecordField = struct {
    name: []const u8,
    core_type: []const u8,
    offset: u32,
};

pub const RecordOwnership = enum {
    none,
    own,
    borrow,
};

pub const RecordNestedField = struct {
    name: []const u8,
    source_type: []const u8,
    storage: []const []const u8,
    ownership: RecordOwnership = .none,
    resource: ?[]const u8 = null,
    drop_import: ?[]const u8 = null,
    nested_fields: []const RecordNestedField = &.{},
};

pub const RecordSourceField = struct {
    name: []const u8,
    source_type: []const u8,
    storage: []const []const u8,
    ownership: RecordOwnership = .none,
    resource: ?[]const u8 = null,
    drop_import: ?[]const u8 = null,
    nested_fields: []const RecordNestedField = &.{},
};

pub const RecordLayout = struct {
    name: []const u8,
    byte_size: u32,
    fields: []const RecordField,
    source_fields: []const RecordSourceField,

    pub fn field_offset(self: RecordLayout, name: []const u8) ?u32 {
        for (self.fields) |field| {
            if (std.mem.eql(u8, field.name, name)) return field.offset;
        }
        return null;
    }
};

pub const ScalarUnitShape = struct {
    source_param: []const u8,
    core_param: []const u8,
};

pub const ScalarResultShape = struct {
    source_result: []const u8,
    tag: []const u8,
    ok: []const []const u8,
    err: []const []const u8,
};

pub const ScalarResultSource = struct {
    ok: []const u8,
    err: []const u8,
};

pub const FutureOwnedCanonical = struct {
    resource: []const u8,
    payload_offset: u32,
    resource_offset: u32,
    presence_offset: u32,
    drop_import: []const u8,
};

pub const ResourceResult2WordShape = struct {
    source_param: []const u8,
    resource: []const u8,
};

/// The pinned wasi:http client Result uses a resource handle on the Ok arm and
/// a seven-word error payload in the task-return callback. The shape is kept
/// internal to the HTTP component emitter; it is not a public Do Result ABI.
pub const HttpResourceResultShape = struct {
    source_param: []const u8,
    request_resource: []const u8,
    response_resource: []const u8,
    completion_words: usize,
};

pub const HttpRequestConstructorShape = struct {
    trailers_future: FutureCanonical,
    transmission_future: FutureCanonical,
};

pub const HttpStreamReaderShape = struct {
    source_param: []const u8,
    resource: []const u8,
    element: []const u8,
    future_new: StreamOperation,
    future_write: StreamOperation,
    future_read: StreamOperation,
    read: StreamOperation,
    drop_readable: StreamOperation,
    future_drop_readable: StreamOperation,
    future_drop_writable: StreamOperation,
};

pub const StreamWriterShape = struct {
    element: []const u8,
    new: StreamOperation,
    cancel_read: StreamOperation,
    cancel_write: StreamOperation,
    drop_readable: StreamOperation,
    drop_writable: StreamOperation,
    read: StreamOperation,
    write: StreamOperation,
};

pub const StreamReaderShape = struct {
    element: []const u8,
    read: StreamOperation,
    drop_readable: StreamOperation,
    future_drop_readable: StreamOperation,
};

pub const StreamOperation = struct {
    import_name: []const u8,
    core_params: []const []const u8,
    core_results: []const []const u8,
};

pub fn lowering_shape(descriptor: Descriptor) ?LoweringShape {
    if (std.mem.eql(u8, descriptor.effect, "http-stream-reader")) {
        if (valid_http_stream_reader_descriptor(descriptor)) |shape| return .{ .http_stream_reader = shape };
        return null;
    }

    if (std.mem.eql(u8, descriptor.effect, "stream-reader")) {
        if (valid_stream_reader_descriptor(descriptor)) |shape| return .{ .stream_reader_acquire = shape };
        return null;
    }

    if (std.mem.eql(u8, descriptor.effect, "record-stream-reader")) {
        if (valid_record_stream_reader_descriptor(descriptor)) |shape| return .{ .record_stream_reader = shape };
        return null;
    }

    if (std.mem.eql(u8, descriptor.effect, "record-resource-list-stream-reader")) {
        if (valid_record_resource_list_stream_reader_descriptor(descriptor)) |shape| return .{ .record_resource_list_stream_reader = shape };
        return null;
    }

    if (std.mem.eql(u8, descriptor.effect, "record-resource-list-stream-producer")) {
        if (valid_record_resource_list_stream_producer_descriptor(descriptor)) |shape| return .{ .record_resource_list_stream_producer = shape };
        return null;
    }

    if (std.mem.eql(u8, descriptor.effect, "record-resource-list-stream-dynamic-producer")) {
        if (valid_record_resource_list_stream_dynamic_producer_descriptor(descriptor)) |shape| return .{ .record_resource_list_stream_dynamic_producer = shape };
        return null;
    }

    if (std.mem.eql(u8, descriptor.effect, "variant-resource-stream-reader")) {
        if (valid_variant_resource_stream_reader_descriptor(descriptor)) |shape| return .{ .variant_resource_stream_reader = shape };
        return null;
    }

    if (std.mem.eql(u8, descriptor.effect, "stream-writer")) {
        const stream = descriptor.canonical.stream orelse return null;
        if (!valid_stream_writer_descriptor(descriptor, stream)) return null;
        return .{ .stream_writer = .{
            .element = stream.element,
            .new = stream.new,
            .cancel_read = stream.cancel_read,
            .cancel_write = stream.cancel_write,
            .drop_readable = stream.drop_readable,
            .drop_writable = stream.drop_writable,
            .read = stream.read,
            .write = stream.write,
        } };
    }

    if (valid_http_request_constructor_descriptor(descriptor)) {
        return .{ .http_request_constructor = .{
            .trailers_future = descriptor.canonical.future_input.?,
            .transmission_future = descriptor.canonical.future.?,
        } };
    }

    if (std.mem.eql(u8, descriptor.effect, "future-owned-resource")) {
        const owned = descriptor.canonical.future_owned orelse return null;
        if (!std.mem.eql(u8, descriptor.locator, "do:future-owned-canonical/source@0.1.0") or
            !std.mem.eql(u8, descriptor.member, "read") or
            descriptor.params.len != 0 or
            !std.mem.eql(u8, descriptor.result, "Ticket") or
            descriptor.resource != null or
            !std.mem.eql(u8, descriptor.wit.package, "do:future-owned-canonical@0.1.0") or
            !std.mem.eql(u8, descriptor.wit.interface, "source") or
            !std.mem.eql(u8, descriptor.wit.operation, "read") or
            !std.mem.eql(u8, descriptor.wit.world, "future-owned-canonical") or
            descriptor.wit.parameter.len != 0 or
            descriptor.canonical.core_params.len != 0 or
            descriptor.canonical.core_results.len != 0 or
            descriptor.canonical.completion_params.len != 0 or
            !std.mem.eql(u8, descriptor.canonical.completion, "task-return") or
            !std.mem.eql(u8, descriptor.canonical.async_import_module, "do:future-owned-canonical/source@0.1.0") or
            !std.mem.eql(u8, descriptor.canonical.async_import_name, "[async-lower]read") or
            !std.mem.eql(u8, owned.resource, "ticket") or
            owned.payload_offset != 12 or
            owned.resource_offset != 16 or
            owned.presence_offset != 20 or
            !std.mem.eql(u8, owned.drop_import, "[resource-drop]ticket")) return null;
        return .{ .future_owned_resource = owned };
    }

    if (!std.mem.eql(u8, descriptor.effect, "async") or !std.mem.eql(u8, descriptor.canonical.completion, "task-return")) return null;

    if (descriptor.params.len == 1 and
        descriptor.resource == null and
        std.mem.eql(u8, descriptor.result, "nil") and
        descriptor.canonical.core_params.len == 1 and
        is_core_scalar(descriptor.canonical.core_params[0]) and
        descriptor.canonical.core_results.len == 0 and
        descriptor.canonical.completion_params.len == 0)
    {
        return .{ .scalar_unit = .{
            .source_param = descriptor.params[0],
            .core_param = descriptor.canonical.core_params[0],
        } };
    }

    if (descriptor.params.len == 0 and
        descriptor.resource == null and
        std.mem.eql(u8, descriptor.result, "Result<nil,nil>") and
        all_i32(descriptor.canonical.core_params, 1) and
        all_i32(descriptor.canonical.core_results, 1) and
        all_i32(descriptor.canonical.completion_params, 1))
    {
        return .{ .unit_result_tag = {} };
    }

    if (descriptor.params.len == 1 and
        descriptor.resource == null and
        descriptor.canonical.result_payload != null and
        scalar_result_layout_matches(descriptor))
    {
        const payload = descriptor.canonical.result_payload.?;
        return .{ .scalar_result = .{
            .source_result = descriptor.result,
            .tag = payload.tag,
            .ok = payload.ok,
            .err = payload.err,
        } };
    }

    if (descriptor.params.len == 1 and
        descriptor.resource != null and
        is_result_type(descriptor.result) and
        all_i32(descriptor.canonical.core_params, 2) and
        all_i32(descriptor.canonical.core_results, 2) and
        all_i32(descriptor.canonical.completion_params, 2))
    {
        return .{ .resource_result_2word = .{
            .source_param = descriptor.params[0],
            .resource = descriptor.resource.?,
        } };
    }

    if (valid_http_resource_result_descriptor(descriptor)) {
        return .{ .http_resource_result = .{
            .source_param = descriptor.params[0],
            .request_resource = descriptor.resource.?,
            .response_resource = "response",
            .completion_words = descriptor.canonical.completion_params.len,
        } };
    }

    return null;
}

pub fn unsupported_shape(descriptor: Descriptor) ?UnsupportedShape {
    if (!std.mem.eql(u8, descriptor.locator, "wasi:filesystem/types@0.3.0-rc-2025-09-16") or
        !std.mem.eql(u8, descriptor.member, "descriptor.read-directory") or
        !std.mem.eql(u8, descriptor.effect, "stream-reader") or
        !std.mem.eql(u8, descriptor.result, "tuple<stream<directory-entry>,future<result<_,error-code>>>") or
        !std.mem.eql(u8, descriptor.canonical.completion, "result-area") or
        !equal_core_types(descriptor.canonical.core_params, &.{ "i32", "i32" }) or
        !equal_core_types(descriptor.canonical.core_results, &.{"i32"}) or
        descriptor.canonical.completion_params.len != 0 or
        !std.mem.eql(u8, descriptor.canonical.async_import_module, "wasi:filesystem/types@0.3.0-rc-2025-09-16") or
        !std.mem.eql(u8, descriptor.canonical.async_import_name, "[async-lower][method]descriptor.read-directory") or
        !std.mem.eql(u8, descriptor.wit.package, "wasi:filesystem@0.3.0-rc-2025-09-16") or
        !std.mem.eql(u8, descriptor.wit.interface, "types") or
        !std.mem.eql(u8, descriptor.wit.operation, "descriptor.read-directory") or
        !std.mem.eql(u8, descriptor.wit.world, "imports") or
        descriptor.wit.parameter.len != 0) return null;

    const stream = descriptor.canonical.stream orelse return null;
    const future = descriptor.canonical.future orelse return null;
    if (!std.mem.eql(u8, stream.element, "directory-entry") or
        !valid_stream_operation(stream.new, &.{}, &.{"i64"}) or
        !valid_stream_operation(stream.cancel_read, &.{"i32"}, &.{"i32"}) or
        !valid_stream_operation(stream.cancel_write, &.{"i32"}, &.{"i32"}) or
        !valid_stream_operation(stream.drop_readable, &.{"i32"}, &.{}) or
        !valid_stream_operation(stream.drop_writable, &.{"i32"}, &.{}) or
        !valid_stream_operation(stream.read, &.{ "i32", "i32", "i32" }, &.{"i32"}) or
        !valid_stream_operation(stream.write, &.{ "i32", "i32", "i32" }, &.{"i32"}) or
        future.new == null or
        !valid_stream_operation(future.new.?, &.{}, &.{"i64"}) or
        future.cancel_read == null or
        !valid_stream_operation(future.cancel_read.?, &.{"i32"}, &.{"i32"}) or
        future.cancel_write == null or
        !valid_stream_operation(future.cancel_write.?, &.{"i32"}, &.{"i32"}) or
        !valid_stream_operation(future.drop_readable, &.{"i32"}, &.{}) or
        future.drop_writable == null or
        !valid_stream_operation(future.drop_writable.?, &.{"i32"}, &.{}) or
        future.read == null or
        !valid_stream_operation(future.read.?, &.{ "i32", "i32" }, &.{"i32"}) or
        future.write == null or
        !valid_stream_operation(future.write.?, &.{ "i32", "i32" }, &.{"i32"})) return null;

    return .{ .record_stream_reader = .{
        .element = stream.element,
        .stream_index = 0,
        .future_index = 1,
        .method = .{
            .import_name = descriptor.canonical.async_import_name,
            .core_params = descriptor.canonical.core_params,
            .core_results = descriptor.canonical.core_results,
        },
        .stream = stream,
        .future = future,
    } };
}

pub const Canonical = struct {
    core_params: []const []const u8,
    core_results: []const []const u8,
    completion_params: []const []const u8,
    completion: []const u8,
    result_payload: ?ResultPayload,
    future_owned: ?FutureOwnedCanonical = null,
    error_variants: []const ErrorVariantPayload = &.{},
    record_layout: ?RecordLayout = null,
    list_resource_layout: ?ListResourceLayout = null,
    producer: ?ProducerCanonical = null,
    async_import_module: []const u8,
    async_import_name: []const u8,
    stream: ?StreamCanonical = null,
    future_input: ?FutureCanonical = null,
    future: ?FutureCanonical = null,
    variant_stream: ?VariantStreamCanonical = null,
    variant_future: ?VariantFutureCanonical = null,
    event_layout: ?VariantEventLayout = null,
    ticket_drop_import: ?[]const u8 = null,
};

pub const FutureCanonical = struct {
    new: ?StreamOperation = null,
    write: ?StreamOperation = null,
    read: ?StreamOperation = null,
    cancel_read: ?StreamOperation = null,
    cancel_write: ?StreamOperation = null,
    drop_readable: StreamOperation,
    drop_writable: ?StreamOperation = null,
};

pub const StreamCanonical = struct {
    element: []const u8,
    new: StreamOperation,
    cancel_read: StreamOperation,
    cancel_write: StreamOperation,
    drop_readable: StreamOperation,
    drop_writable: StreamOperation,
    read: StreamOperation,
    write: StreamOperation,
};

pub const ResultPayload = struct {
    tag: []const u8,
    ok: []const []const u8,
    err: []const []const u8,
};

pub const ErrorVariantFieldKind = enum {
    optional_string,
    optional_u16,
};

pub const ErrorVariantField = struct {
    name: []const u8,
    kind: ErrorVariantFieldKind,
    core_words: []const []const u8,
    offset: u32,
};

pub const ErrorVariantPayload = struct {
    variant: []const u8,
    discriminant: u32,
    byte_size: u32,
    fields: []const ErrorVariantField,
};

pub const Wit = struct {
    package: []const u8,
    interface: []const u8,
    operation: []const u8,
    world: []const u8,
    parameter: []const u8,
};

pub const Registry = struct {
    descriptors: []Descriptor,

    pub fn load(allocator: std.mem.Allocator, json: []const u8) !Registry {
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, json, .{}) catch return error.InvalidP3AsyncManifest;
        defer parsed.deinit();

        const root = object_value(parsed.value) orelse return error.InvalidP3AsyncManifest;
        if (unsigned_value(root.get("schema")) != 1) return error.InvalidP3AsyncManifest;
        _ = string_value(root.get("wit_sha256")) orelse return error.InvalidP3AsyncManifest;
        const descriptor_values = array_value(root.get("descriptors")) orelse return error.InvalidP3AsyncManifest;

        var descriptors = try std.ArrayList(Descriptor).initCapacity(allocator, descriptor_values.items.len);
        errdefer {
            for (descriptors.items) |descriptor| free_descriptor(allocator, descriptor);
            descriptors.deinit(allocator);
        }

        for (descriptor_values.items) |descriptor_value| {
            const descriptor = try parse_descriptor(allocator, descriptor_value);
            errdefer free_descriptor(allocator, descriptor);
            if (contains_descriptor(descriptors.items, descriptor.locator, descriptor.member)) return error.InvalidP3AsyncManifest;
            try descriptors.append(allocator, descriptor);
        }

        return .{ .descriptors = try descriptors.toOwnedSlice(allocator) };
    }

    pub fn deinit(self: *Registry, allocator: std.mem.Allocator) void {
        free_descriptors(allocator, self.descriptors);
        self.* = undefined;
    }

    pub fn find(self: Registry, locator: []const u8, member: []const u8) ?Descriptor {
        for (self.descriptors) |descriptor| {
            if (std.mem.eql(u8, descriptor.locator, locator) and std.mem.eql(u8, descriptor.member, member)) return descriptor;
        }
        return null;
    }
};

fn parse_descriptor(allocator: std.mem.Allocator, value: std.json.Value) !Descriptor {
    const object = object_value(value) orelse return error.InvalidP3AsyncManifest;
    if (object.get("cancel") != null) return error.InvalidP3AsyncManifest;
    const canonical = try parse_canonical(allocator, object.get("canonical"));
    errdefer free_canonical(allocator, canonical);
    const wit = try parse_wit(allocator, object.get("wit"));
    errdefer free_wit(allocator, wit);
    const effect = string_value(object.get("effect")) orelse return error.InvalidP3AsyncManifest;
    if (!std.mem.eql(u8, effect, "async") and
        !std.mem.eql(u8, effect, "future-owned-resource") and
        !std.mem.eql(u8, effect, "http-request-constructor") and
        !std.mem.eql(u8, effect, "http-stream-reader") and
        !std.mem.eql(u8, effect, "stream-reader") and
        !std.mem.eql(u8, effect, "record-stream-reader") and
        !std.mem.eql(u8, effect, "record-resource-list-stream-reader") and
        !std.mem.eql(u8, effect, "record-resource-list-stream-producer") and
        !std.mem.eql(u8, effect, "record-resource-list-stream-dynamic-producer") and
        !std.mem.eql(u8, effect, "variant-resource-stream-reader") and
        !std.mem.eql(u8, effect, "stream-writer")) return error.InvalidP3AsyncManifest;
    const owned_params = try duplicate_params(allocator, array_value(object.get("params")) orelse return error.InvalidP3AsyncManifest);
    errdefer {
        for (owned_params) |param| allocator.free(param);
        allocator.free(owned_params);
    }
    const resource = try parse_resource(object.get("resource"));
    const locator = try duplicate_required(allocator, object.get("locator"));
    errdefer allocator.free(locator);
    const member = try duplicate_required(allocator, object.get("member"));
    errdefer allocator.free(member);
    const owned_effect = try allocator.dupe(u8, effect);
    errdefer allocator.free(owned_effect);
    const result = try duplicate_required(allocator, object.get("result"));
    errdefer allocator.free(result);
    const owned_resource = if (resource) |name| try allocator.dupe(u8, name) else null;
    errdefer if (owned_resource) |name| allocator.free(name);
    const wit_sha256 = try duplicate_optional_sha256(allocator, object.get("wit_sha256"));
    errdefer if (wit_sha256) |hash| allocator.free(hash);

    return .{
        .locator = locator,
        .member = member,
        .effect = owned_effect,
        .params = owned_params,
        .result = result,
        .resource = owned_resource,
        .wit_sha256 = wit_sha256,
        .canonical = canonical,
        .wit = wit,
    };
}

fn parse_canonical(allocator: std.mem.Allocator, value: ?std.json.Value) !Canonical {
    const canonical = object_value(value orelse return error.InvalidP3AsyncManifest) orelse return error.InvalidP3AsyncManifest;
    const core_params = try duplicate_params(allocator, array_value(canonical.get("core_params")) orelse return error.InvalidP3AsyncManifest);
    errdefer free_string_list(allocator, core_params);
    const core_results = try duplicate_params(allocator, array_value(canonical.get("core_results")) orelse return error.InvalidP3AsyncManifest);
    errdefer free_string_list(allocator, core_results);
    const completion_params = if (canonical.get("completion_params")) |completion_value|
        try duplicate_params(allocator, array_value(completion_value) orelse return error.InvalidP3AsyncManifest)
    else
        try allocator.alloc([]const u8, 0);
    errdefer free_string_list(allocator, completion_params);
    const result_payload = if (canonical.get("result_payload") != null)
        try parse_result_payload(allocator, canonical.get("result_payload"))
    else
        null;
    errdefer if (result_payload) |payload| free_result_payload(allocator, payload);
    const future_owned = if (canonical.get("future_owned")) |owned_value|
        try parse_future_owned_canonical(allocator, owned_value)
    else
        null;
    errdefer if (future_owned) |owned| free_future_owned_canonical(allocator, owned);
    const record_layout = if (canonical.get("record_layout")) |layout_value|
        try parse_record_layout(allocator, layout_value)
    else
        null;
    errdefer if (record_layout) |layout| free_record_layout(allocator, layout);
    const list_resource_layout = if (canonical.get("list_resource_layout")) |layout_value|
        try parse_list_resource_layout(layout_value)
    else
        null;
    const producer = if (canonical.get("producer")) |producer_value|
        try parse_producer_canonical(allocator, producer_value)
    else
        null;
    errdefer if (producer) |value_to_free| free_producer_canonical(allocator, value_to_free);
    const completion = string_value(canonical.get("completion")) orelse return error.InvalidP3AsyncManifest;
    if (!std.mem.eql(u8, completion, "task-return") and
        !std.mem.eql(u8, completion, "result-area") and
        !std.mem.eql(u8, completion, "none")) return error.InvalidP3AsyncManifest;
    if (std.mem.eql(u8, completion, "task-return")) {
        for (completion_params) |param| {
            if (!is_core_scalar(param)) return error.InvalidP3AsyncManifest;
        }
    } else if (completion_params.len != 0) return error.InvalidP3AsyncManifest;
    const error_variants = if (canonical.get("error_variants")) |error_variants_value|
        try parse_error_variants(allocator, error_variants_value, completion, completion_params)
    else
        try allocator.alloc(ErrorVariantPayload, 0);
    errdefer free_error_variants(allocator, error_variants);
    if (canonical.get("operation_token") != null) return error.InvalidP3AsyncManifest;
    const owned_completion = try allocator.dupe(u8, completion);
    errdefer allocator.free(owned_completion);
    const async_import_module = try duplicate_required(allocator, canonical.get("async_import_module"));
    errdefer allocator.free(async_import_module);
    if (async_import_module.len == 0) return error.InvalidP3AsyncManifest;
    const async_import_name = try duplicate_required(allocator, canonical.get("async_import_name"));
    errdefer allocator.free(async_import_name);
    if (async_import_name.len == 0) return error.InvalidP3AsyncManifest;
    const event_layout = if (canonical.get("event_layout")) |event_value|
        try parse_variant_event_layout(allocator, event_value)
    else
        null;
    errdefer if (event_layout) |layout| free_variant_event_layout(allocator, layout);
    const ticket_drop_import = if (event_layout != null)
        try duplicate_required(allocator, canonical.get("ticket_drop_import"))
    else
        null;
    errdefer if (ticket_drop_import) |import_name| allocator.free(import_name);
    const variant_stream = if (event_layout != null)
        try parse_variant_stream_canonical(allocator, canonical.get("stream"))
    else
        null;
    errdefer if (variant_stream) |value_to_free| free_variant_stream_canonical(allocator, value_to_free);
    const variant_future = if (event_layout != null)
        try parse_variant_future_canonical(allocator, canonical.get("future"))
    else
        null;
    errdefer if (variant_future) |value_to_free| free_variant_future_canonical(allocator, value_to_free);
    const stream = if (event_layout == null) if (canonical.get("stream")) |stream_value|
        try parse_stream_canonical(allocator, stream_value)
    else
        null else null;
    errdefer if (stream) |value_to_free| free_stream_canonical(allocator, value_to_free);
    const future_input = if (canonical.get("future_input")) |future_value|
        try parse_future_canonical(allocator, future_value)
    else
        null;
    errdefer if (future_input) |value_to_free| free_future_canonical(allocator, value_to_free);
    const future = if (canonical.get("future")) |future_value|
        try parse_future_canonical(allocator, future_value)
    else
        null;
    errdefer if (future) |value_to_free| free_future_canonical(allocator, value_to_free);
    return .{
        .core_params = core_params,
        .core_results = core_results,
        .completion_params = completion_params,
        .completion = owned_completion,
        .result_payload = result_payload,
        .future_owned = future_owned,
        .error_variants = error_variants,
        .record_layout = record_layout,
        .list_resource_layout = list_resource_layout,
        .producer = producer,
        .async_import_module = async_import_module,
        .async_import_name = async_import_name,
        .stream = stream,
        .future_input = future_input,
        .future = future,
        .variant_stream = variant_stream,
        .variant_future = variant_future,
        .event_layout = event_layout,
        .ticket_drop_import = ticket_drop_import,
    };
}

fn parse_list_resource_layout(value: std.json.Value) !ListResourceLayout {
    const object = object_value(value) orelse return error.InvalidP3AsyncManifest;
    const pointer_offset = unsigned_value(object.get("result_pointer_offset")) orelse return error.InvalidP3AsyncManifest;
    const length_offset = unsigned_value(object.get("result_length_offset")) orelse return error.InvalidP3AsyncManifest;
    const element_stride = unsigned_value(object.get("element_stride")) orelse return error.InvalidP3AsyncManifest;
    const ticket_offset = unsigned_value(object.get("ticket_offset")) orelse return error.InvalidP3AsyncManifest;
    const max_items = unsigned_value(object.get("max_items")) orelse return error.InvalidP3AsyncManifest;
    if (pointer_offset > std.math.maxInt(u32) or
        length_offset > std.math.maxInt(u32) or
        element_stride > std.math.maxInt(u32) or
        ticket_offset > std.math.maxInt(u32) or
        max_items > std.math.maxInt(u32)) return error.InvalidP3AsyncManifest;
    return .{
        .result_pointer_offset = @intCast(pointer_offset),
        .result_length_offset = @intCast(length_offset),
        .element_stride = @intCast(element_stride),
        .ticket_offset = @intCast(ticket_offset),
        .max_items = @intCast(max_items),
    };
}

fn parse_producer_canonical(allocator: std.mem.Allocator, value: std.json.Value) !ProducerCanonical {
    const object = object_value(value) orelse return error.InvalidP3AsyncManifest;
    const source_module = try duplicate_required(allocator, object.get("source_module"));
    errdefer allocator.free(source_module);
    const source_import_name = try duplicate_required(allocator, object.get("source_import_name"));
    errdefer allocator.free(source_import_name);
    const source_core_params = try duplicate_params(allocator, array_value(object.get("source_core_params")) orelse return error.InvalidP3AsyncManifest);
    errdefer free_string_list(allocator, source_core_params);
    const source_core_results = try duplicate_params(allocator, array_value(object.get("source_core_results")) orelse return error.InvalidP3AsyncManifest);
    errdefer free_string_list(allocator, source_core_results);
    const resource_drop_import = try duplicate_required(allocator, object.get("resource_drop_import"));
    errdefer allocator.free(resource_drop_import);
    const stream_capacity = unsigned_value(object.get("stream_capacity")) orelse return error.InvalidP3AsyncManifest;
    if (stream_capacity > std.math.maxInt(u32)) return error.InvalidP3AsyncManifest;
    const terminal = try duplicate_required(allocator, object.get("terminal"));
    errdefer allocator.free(terminal);
    const runtime_count_param = if (object.get("runtime_count_param")) |raw| blk: {
        const value_text = string_value(raw) orelse return error.InvalidP3AsyncManifest;
        if (value_text.len == 0) return error.InvalidP3AsyncManifest;
        break :blk try allocator.dupe(u8, value_text);
    } else null;
    errdefer if (runtime_count_param) |value_text| allocator.free(value_text);
    const runtime_max = if (object.get("runtime_max")) |raw| blk: {
        const value_number = unsigned_value(raw) orelse return error.InvalidP3AsyncManifest;
        if (value_number > std.math.maxInt(u32)) return error.InvalidP3AsyncManifest;
        break :blk @as(?u32, @intCast(value_number));
    } else null;
    if (source_module.len == 0 or source_import_name.len == 0 or resource_drop_import.len == 0 or terminal.len == 0) {
        return error.InvalidP3AsyncManifest;
    }
    for (source_core_params) |param| if (!is_core_scalar(param)) return error.InvalidP3AsyncManifest;
    for (source_core_results) |result| if (!is_core_scalar(result)) return error.InvalidP3AsyncManifest;
    return .{
        .source_module = source_module,
        .source_import_name = source_import_name,
        .source_core_params = source_core_params,
        .source_core_results = source_core_results,
        .resource_drop_import = resource_drop_import,
        .stream_capacity = @intCast(stream_capacity),
        .terminal = terminal,
        .runtime_count_param = runtime_count_param,
        .runtime_max = runtime_max,
    };
}

fn parse_future_owned_canonical(allocator: std.mem.Allocator, value: std.json.Value) !FutureOwnedCanonical {
    const object = object_value(value) orelse return error.InvalidP3AsyncManifest;
    const resource = try duplicate_required(allocator, object.get("resource"));
    errdefer allocator.free(resource);
    const payload_offset = unsigned_value(object.get("payload_offset")) orelse return error.InvalidP3AsyncManifest;
    const resource_offset = unsigned_value(object.get("resource_offset")) orelse return error.InvalidP3AsyncManifest;
    const presence_offset = unsigned_value(object.get("presence_offset")) orelse return error.InvalidP3AsyncManifest;
    if (payload_offset > std.math.maxInt(u32) or
        resource_offset > std.math.maxInt(u32) or
        presence_offset > std.math.maxInt(u32)) return error.InvalidP3AsyncManifest;
    const drop_import = try duplicate_required(allocator, object.get("drop_import"));
    errdefer allocator.free(drop_import);
    if (resource.len == 0 or drop_import.len == 0) return error.InvalidP3AsyncManifest;
    return .{
        .resource = resource,
        .payload_offset = @intCast(payload_offset),
        .resource_offset = @intCast(resource_offset),
        .presence_offset = @intCast(presence_offset),
        .drop_import = drop_import,
    };
}

fn parse_future_canonical(allocator: std.mem.Allocator, value: std.json.Value) !FutureCanonical {
    const object = object_value(value) orelse return error.InvalidP3AsyncManifest;
    const new = try parse_optional_stream_operation(allocator, object.get("new"));
    errdefer if (new) |operation| free_stream_operation(allocator, operation);
    const write = try parse_optional_stream_operation(allocator, object.get("write"));
    errdefer if (write) |operation| free_stream_operation(allocator, operation);
    const read = try parse_optional_stream_operation(allocator, object.get("read"));
    errdefer if (read) |operation| free_stream_operation(allocator, operation);
    const cancel_read = try parse_optional_stream_operation(allocator, object.get("cancel_read"));
    errdefer if (cancel_read) |operation| free_stream_operation(allocator, operation);
    const cancel_write = try parse_optional_stream_operation(allocator, object.get("cancel_write"));
    errdefer if (cancel_write) |operation| free_stream_operation(allocator, operation);
    const drop_readable = try parse_stream_operation(allocator, object.get("drop_readable"));
    errdefer free_stream_operation(allocator, drop_readable);
    const drop_writable = try parse_optional_stream_operation(allocator, object.get("drop_writable"));
    errdefer if (drop_writable) |operation| free_stream_operation(allocator, operation);
    return .{
        .new = new,
        .write = write,
        .read = read,
        .cancel_read = cancel_read,
        .cancel_write = cancel_write,
        .drop_readable = drop_readable,
        .drop_writable = drop_writable,
    };
}

fn parse_optional_stream_operation(allocator: std.mem.Allocator, value: ?std.json.Value) !?StreamOperation {
    if (value) |operation_value| return try parse_stream_operation(allocator, operation_value);
    return null;
}

fn parse_stream_canonical(allocator: std.mem.Allocator, value: std.json.Value) !StreamCanonical {
    const object = object_value(value) orelse return error.InvalidP3AsyncManifest;
    const element = try duplicate_required(allocator, object.get("element"));
    errdefer allocator.free(element);
    const new = try parse_stream_operation(allocator, object.get("new"));
    errdefer free_stream_operation(allocator, new);
    const cancel_read = try parse_stream_operation(allocator, object.get("cancel_read"));
    errdefer free_stream_operation(allocator, cancel_read);
    const cancel_write = try parse_stream_operation(allocator, object.get("cancel_write"));
    errdefer free_stream_operation(allocator, cancel_write);
    const drop_readable = try parse_stream_operation(allocator, object.get("drop_readable"));
    errdefer free_stream_operation(allocator, drop_readable);
    const drop_writable = try parse_stream_operation(allocator, object.get("drop_writable"));
    errdefer free_stream_operation(allocator, drop_writable);
    const read = try parse_stream_operation(allocator, object.get("read"));
    errdefer free_stream_operation(allocator, read);
    const write = try parse_stream_operation(allocator, object.get("write"));
    errdefer free_stream_operation(allocator, write);
    return .{
        .element = element,
        .new = new,
        .cancel_read = cancel_read,
        .cancel_write = cancel_write,
        .drop_readable = drop_readable,
        .drop_writable = drop_writable,
        .read = read,
        .write = write,
    };
}

fn parse_stream_operation(allocator: std.mem.Allocator, value: ?std.json.Value) !StreamOperation {
    const object = object_value(value orelse return error.InvalidP3AsyncManifest) orelse return error.InvalidP3AsyncManifest;
    const import_name = try duplicate_required(allocator, object.get("import_name"));
    errdefer allocator.free(import_name);
    if (import_name.len == 0) return error.InvalidP3AsyncManifest;
    const core_params = try duplicate_params(allocator, array_value(object.get("core_params")) orelse return error.InvalidP3AsyncManifest);
    errdefer free_string_list(allocator, core_params);
    const core_results = try duplicate_params(allocator, array_value(object.get("core_results")) orelse return error.InvalidP3AsyncManifest);
    errdefer free_string_list(allocator, core_results);
    return .{ .import_name = import_name, .core_params = core_params, .core_results = core_results };
}

fn parse_variant_stream_canonical(allocator: std.mem.Allocator, value: ?std.json.Value) !VariantStreamCanonical {
    const object = object_value(value orelse return error.InvalidP3AsyncManifest) orelse return error.InvalidP3AsyncManifest;
    const element = try duplicate_required(allocator, object.get("element"));
    errdefer allocator.free(element);
    const read = try parse_stream_operation(allocator, object.get("read"));
    errdefer free_stream_operation(allocator, read);
    const drop_readable = try parse_stream_operation(allocator, object.get("drop_readable"));
    errdefer free_stream_operation(allocator, drop_readable);
    return .{ .element = element, .read = read, .drop_readable = drop_readable };
}

fn parse_variant_future_canonical(allocator: std.mem.Allocator, value: ?std.json.Value) !VariantFutureCanonical {
    const object = object_value(value orelse return error.InvalidP3AsyncManifest) orelse return error.InvalidP3AsyncManifest;
    const read = try parse_stream_operation(allocator, object.get("read"));
    errdefer free_stream_operation(allocator, read);
    const drop_readable = try parse_stream_operation(allocator, object.get("drop_readable"));
    errdefer free_stream_operation(allocator, drop_readable);
    return .{ .read = read, .drop_readable = drop_readable };
}

fn parse_variant_event_layout(allocator: std.mem.Allocator, value: std.json.Value) !VariantEventLayout {
    const object = object_value(value) orelse return error.InvalidP3AsyncManifest;
    const raw_tag_offset = unsigned_value(object.get("tag_offset")) orelse return error.InvalidP3AsyncManifest;
    const raw_payload_offset = unsigned_value(object.get("payload_offset")) orelse return error.InvalidP3AsyncManifest;
    const raw_byte_size = unsigned_value(object.get("byte_size")) orelse return error.InvalidP3AsyncManifest;
    const raw_alignment = unsigned_value(object.get("alignment")) orelse return error.InvalidP3AsyncManifest;
    if (raw_tag_offset > std.math.maxInt(u32) or raw_payload_offset > std.math.maxInt(u32) or
        raw_byte_size > std.math.maxInt(u32) or raw_alignment > std.math.maxInt(u32)) return error.InvalidP3AsyncManifest;

    const values = array_value(object.get("variants")) orelse return error.InvalidP3AsyncManifest;
    if (values.items.len == 0) return error.InvalidP3AsyncManifest;
    var variants = try std.ArrayList(VariantEventBranch).initCapacity(allocator, values.items.len);
    errdefer {
        for (variants.items) |variant| free_variant_event_branch(allocator, variant);
        variants.deinit(allocator);
    }
    for (values.items) |value_item| {
        const branch = object_value(value_item) orelse return error.InvalidP3AsyncManifest;
        const name = try duplicate_required(allocator, branch.get("name"));
        errdefer allocator.free(name);
        const raw_tag = unsigned_value(branch.get("tag")) orelse return error.InvalidP3AsyncManifest;
        if (raw_tag > std.math.maxInt(u32) or name.len == 0) return error.InvalidP3AsyncManifest;
        const payload_value = branch.get("payload") orelse return error.InvalidP3AsyncManifest;
        const payload = switch (payload_value) {
            .null => null,
            .string => |text| try allocator.dupe(u8, text),
            else => return error.InvalidP3AsyncManifest,
        };
        errdefer if (payload) |payload_text| allocator.free(payload_text);
        for (variants.items) |previous| {
            if (previous.tag == @as(u32, @intCast(raw_tag)) or std.mem.eql(u8, previous.name, name)) {
                return error.InvalidP3AsyncManifest;
            }
        }
        try variants.append(allocator, .{
            .name = name,
            .tag = @intCast(raw_tag),
            .payload = payload,
        });
        errdefer _ = variants.pop();
    }
    return .{
        .tag_offset = @intCast(raw_tag_offset),
        .payload_offset = @intCast(raw_payload_offset),
        .byte_size = @intCast(raw_byte_size),
        .alignment = @intCast(raw_alignment),
        .variants = try variants.toOwnedSlice(allocator),
    };
}

fn valid_stream_writer_descriptor(descriptor: Descriptor, stream: StreamCanonical) bool {
    if (descriptor.params.len != 1 or descriptor.resource != null) return false;
    if (!std.mem.eql(u8, descriptor.params[0], "stream<u8>") or
        !std.mem.eql(u8, descriptor.result, "Result<nil,error-code>") or
        !std.mem.eql(u8, stream.element, "u8")) return false;
    if (!std.mem.eql(u8, descriptor.canonical.completion, "task-return") or
        !equal_core_types(descriptor.canonical.core_params, &.{ "i32", "i32" }) or
        !equal_core_types(descriptor.canonical.core_results, &.{"i32"}) or
        !equal_core_types(descriptor.canonical.completion_params, &.{ "i32", "i32" })) return false;
    return valid_stream_operation(stream.new, &.{}, &.{"i64"}) and
        valid_stream_operation(stream.cancel_read, &.{"i32"}, &.{"i32"}) and
        valid_stream_operation(stream.cancel_write, &.{"i32"}, &.{"i32"}) and
        valid_stream_operation(stream.drop_readable, &.{"i32"}, &.{}) and
        valid_stream_operation(stream.drop_writable, &.{"i32"}, &.{}) and
        valid_stream_operation(stream.read, &.{ "i32", "i32", "i32" }, &.{"i32"}) and
        valid_stream_operation(stream.write, &.{ "i32", "i32", "i32" }, &.{"i32"});
}

fn valid_http_resource_result_descriptor(descriptor: Descriptor) bool {
    if (descriptor.params.len != 1 or descriptor.resource == null or
        !std.mem.eql(u8, descriptor.params[0], "HttpRequest") or
        !std.mem.eql(u8, descriptor.resource.?, "request") or
        !std.mem.eql(u8, descriptor.result, "Result<HttpResponse,HttpError>") or
        !std.mem.eql(u8, descriptor.canonical.completion, "task-return") or
        !equal_core_types(descriptor.canonical.core_params, &.{ "i32", "i32" }) or
        !equal_core_types(descriptor.canonical.core_results, &.{"i32"}) or
        !http_completion_shape(descriptor.canonical.completion_params) or
        descriptor.canonical.result_payload != null) return false;
    return std.mem.eql(u8, descriptor.wit.interface, "client") and
        std.mem.eql(u8, descriptor.wit.operation, "send") and
        std.mem.eql(u8, descriptor.wit.parameter, "request");
}

fn valid_http_request_constructor_descriptor(descriptor: Descriptor) bool {
    const input = descriptor.canonical.future_input orelse return false;
    const output = descriptor.canonical.future orelse return false;
    return std.mem.eql(u8, descriptor.locator, "wasi:http/types@0.3.0-rc-2025-09-16") and
        std.mem.eql(u8, descriptor.member, "request.new") and
        std.mem.eql(u8, descriptor.effect, "http-request-constructor") and
        descriptor.params.len == 0 and
        descriptor.resource == null and
        std.mem.eql(u8, descriptor.result, "tuple<request,future<result<_,error-code>>>") and
        std.mem.eql(u8, descriptor.canonical.completion, "none") and
        equal_core_types(descriptor.canonical.core_params, &.{ "i32", "i32", "i32", "i32", "i32", "i32", "i32" }) and
        descriptor.canonical.core_results.len == 0 and
        valid_stream_operation(input.new orelse return false, &.{}, &.{"i64"}) and
        valid_stream_operation(input.write orelse return false, &.{ "i32", "i32" }, &.{"i32"}) and
        valid_stream_operation(input.drop_readable, &.{"i32"}, &.{}) and
        valid_stream_operation(input.drop_writable orelse return false, &.{"i32"}, &.{}) and
        input.read == null and
        valid_stream_operation(output.drop_readable, &.{"i32"}, &.{}) and
        output.new == null and
        output.write == null and
        output.read == null;
}

fn http_completion_shape(values: []const []const u8) bool {
    const expected = [_][]const u8{ "i32", "i32", "i32", "i64", "i32", "i32", "i32", "i32" };
    return equal_core_types(values, &expected);
}

fn valid_stream_reader_descriptor(descriptor: Descriptor) ?StreamReaderShape {
    const stream = descriptor.canonical.stream orelse return null;
    const future = descriptor.canonical.future orelse return null;
    if (descriptor.params.len != 0 or descriptor.resource != null or
        !std.mem.eql(u8, descriptor.canonical.completion, "result-area") or
        !std.mem.eql(u8, descriptor.result, "tuple<stream<u8>,future<result<_,error-code>>>") or
        !std.mem.eql(u8, stream.element, "u8") or
        !all_i32(descriptor.canonical.core_params, 1) or
        descriptor.canonical.core_results.len != 0 or descriptor.canonical.completion_params.len != 0)
    {
        return null;
    }
    if (!valid_stream_operation(stream.read, &.{ "i32", "i32", "i32" }, &.{"i32"}) or
        !valid_stream_operation(stream.drop_readable, &.{"i32"}, &.{}) or
        !valid_stream_operation(future.drop_readable, &.{"i32"}, &.{})) return null;
    return .{
        .element = stream.element,
        .read = stream.read,
        .drop_readable = stream.drop_readable,
        .future_drop_readable = future.drop_readable,
    };
}

fn valid_record_stream_reader_descriptor(descriptor: Descriptor) ?RecordStreamReaderShape {
    const stream = descriptor.canonical.stream orelse return null;
    const future = descriptor.canonical.future orelse return null;
    const record_layout = descriptor.canonical.record_layout orelse return null;
    const future_new = future.new orelse return null;
    const future_cancel_read = future.cancel_read orelse return null;
    const future_cancel_write = future.cancel_write orelse return null;
    const future_drop_writable = future.drop_writable orelse return null;
    const future_read = future.read orelse return null;
    const future_write = future.write orelse return null;

    if (!std.mem.eql(u8, descriptor.effect, "record-stream-reader") or
        descriptor.resource != null or
        !valid_record_stream_result(descriptor.result, stream.element) or
        !std.mem.eql(u8, descriptor.canonical.completion, "result-area") or
        descriptor.canonical.completion_params.len != 0 or
        !valid_record_stream_layout(record_layout, stream.element)) return null;

    const filesystem_descriptor =
        std.mem.eql(u8, descriptor.locator, "wasi:filesystem/types@0.3.0-rc-2025-09-16") and
        std.mem.eql(u8, descriptor.member, "descriptor.read-directory");
    if (filesystem_descriptor) {
        if (descriptor.wit_sha256 == null or
            !std.mem.eql(u8, descriptor.wit_sha256.?, p3_filesystem_wit_manifest.directory_types_sha256) or
            descriptor.params.len != 1 or
            !std.mem.eql(u8, descriptor.params[0], "descriptor") or
            !equal_core_types(descriptor.canonical.core_params, &.{ "i32", "i32" }) or
            !equal_core_types(descriptor.canonical.core_results, &.{"i32"}) or
            !std.mem.eql(u8, stream.element, "directory-entry") or
            !valid_pinned_directory_entry_layout(record_layout)) return null;
    } else if (descriptor.params.len != 0 or
        !equal_core_types(descriptor.canonical.core_params, &.{"i32"}) or
        descriptor.canonical.core_results.len != 0)
    {
        return null;
    }

    if (!valid_stream_operation(stream.new, &.{}, &.{"i64"}) or
        !valid_stream_operation(stream.cancel_read, &.{"i32"}, &.{"i32"}) or
        !valid_stream_operation(stream.cancel_write, &.{"i32"}, &.{"i32"}) or
        !valid_stream_operation(stream.drop_readable, &.{"i32"}, &.{}) or
        !valid_stream_operation(stream.drop_writable, &.{"i32"}, &.{}) or
        !valid_stream_operation(stream.read, &.{ "i32", "i32", "i32" }, &.{"i32"}) or
        !valid_stream_operation(stream.write, &.{ "i32", "i32", "i32" }, &.{"i32"}) or
        !valid_stream_operation(future_new, &.{}, &.{"i64"}) or
        !valid_stream_operation(future_cancel_read, &.{"i32"}, &.{"i32"}) or
        !valid_stream_operation(future_cancel_write, &.{"i32"}, &.{"i32"}) or
        !valid_stream_operation(future.drop_readable, &.{"i32"}, &.{}) or
        !valid_stream_operation(future_drop_writable, &.{"i32"}, &.{}) or
        !valid_stream_operation(future_read, &.{ "i32", "i32" }, &.{"i32"}) or
        !valid_stream_operation(future_write, &.{ "i32", "i32" }, &.{"i32"})) return null;

    if (filesystem_descriptor and
        (!valid_named_stream_operation(stream.new, "[stream-new-0][method]descriptor.read-directory", &.{}, &.{"i64"}) or
            !valid_named_stream_operation(stream.cancel_read, "[stream-cancel-read-0][method]descriptor.read-directory", &.{"i32"}, &.{"i32"}) or
            !valid_named_stream_operation(stream.cancel_write, "[stream-cancel-write-0][method]descriptor.read-directory", &.{"i32"}, &.{"i32"}) or
            !valid_named_stream_operation(stream.drop_readable, "[stream-drop-readable-0][method]descriptor.read-directory", &.{"i32"}, &.{}) or
            !valid_named_stream_operation(stream.drop_writable, "[stream-drop-writable-0][method]descriptor.read-directory", &.{"i32"}, &.{}) or
            !valid_named_stream_operation(stream.read, "[async-lower][stream-read-0][method]descriptor.read-directory", &.{ "i32", "i32", "i32" }, &.{"i32"}) or
            !valid_named_stream_operation(stream.write, "[async-lower][stream-write-0][method]descriptor.read-directory", &.{ "i32", "i32", "i32" }, &.{"i32"}) or
            !valid_named_stream_operation(future_new, "[future-new-1][method]descriptor.read-directory", &.{}, &.{"i64"}) or
            !valid_named_stream_operation(future_cancel_read, "[future-cancel-read-1][method]descriptor.read-directory", &.{"i32"}, &.{"i32"}) or
            !valid_named_stream_operation(future_cancel_write, "[future-cancel-write-1][method]descriptor.read-directory", &.{"i32"}, &.{"i32"}) or
            !valid_named_stream_operation(future.drop_readable, "[future-drop-readable-1][method]descriptor.read-directory", &.{"i32"}, &.{}) or
            !valid_named_stream_operation(future_drop_writable, "[future-drop-writable-1][method]descriptor.read-directory", &.{"i32"}, &.{}) or
            !valid_named_stream_operation(future_read, "[async-lower][future-read-1][method]descriptor.read-directory", &.{ "i32", "i32" }, &.{"i32"}) or
            !valid_named_stream_operation(future_write, "[async-lower][future-write-1][method]descriptor.read-directory", &.{ "i32", "i32" }, &.{"i32"}))) return null;

    return .{
        .element = stream.element,
        .stream_index = 0,
        .future_index = 1,
        .method = .{
            .import_name = descriptor.canonical.async_import_name,
            .core_params = descriptor.canonical.core_params,
            .core_results = descriptor.canonical.core_results,
        },
        .stream = stream,
        .future = future,
        .record_layout = record_layout,
    };
}

fn valid_record_resource_list_stream_reader_descriptor(descriptor: Descriptor) ?RecordResourceListStreamShape {
    const stream = descriptor.canonical.stream orelse return null;
    const future = descriptor.canonical.future orelse return null;
    const record_layout = descriptor.canonical.record_layout orelse return null;
    const list_layout = descriptor.canonical.list_resource_layout orelse return null;
    const future_new = future.new orelse return null;
    const future_cancel_read = future.cancel_read orelse return null;
    const future_cancel_write = future.cancel_write orelse return null;
    const future_drop_writable = future.drop_writable orelse return null;
    const future_read = future.read orelse return null;
    const future_write = future.write orelse return null;

    if (!std.mem.eql(u8, descriptor.effect, "record-resource-list-stream-reader") or
        !std.mem.eql(u8, descriptor.locator, "do:record-resource-list-stream-probe@0.1.0") or
        !std.mem.eql(u8, descriptor.member, "read-via-stream") or
        descriptor.resource != null or
        descriptor.params.len != 0 or
        !std.mem.eql(u8, descriptor.result, "tuple<stream<list<resource-entry>>,future<result<_,error-code>>>") or
        !std.mem.eql(u8, descriptor.wit.package, "do:record-resource-list-stream-probe@0.1.0") or
        !std.mem.eql(u8, descriptor.wit.interface, "source") or
        !std.mem.eql(u8, descriptor.wit.operation, "read-via-stream") or
        !std.mem.eql(u8, descriptor.wit.world, "record-resource-list-stream-probe") or
        descriptor.wit.parameter.len != 0 or
        !equal_core_types(descriptor.canonical.core_params, &.{"i32"}) or
        descriptor.canonical.core_results.len != 0 or
        !std.mem.eql(u8, descriptor.canonical.completion, "result-area") or
        descriptor.canonical.completion_params.len != 0 or
        !std.mem.eql(u8, descriptor.canonical.async_import_module, "do:record-resource-list-stream-probe/source@0.1.0") or
        !std.mem.eql(u8, descriptor.canonical.async_import_name, "read-via-stream") or
        !valid_list_resource_layout(list_layout) or
        !valid_single_ticket_record_layout(record_layout) or
        !std.mem.eql(u8, stream.element, "list<resource-entry>")) return null;

    if (!valid_stream_operation(stream.new, &.{}, &.{"i64"}) or
        !valid_stream_operation(stream.cancel_read, &.{"i32"}, &.{"i32"}) or
        !valid_stream_operation(stream.cancel_write, &.{"i32"}, &.{"i32"}) or
        !valid_stream_operation(stream.drop_readable, &.{"i32"}, &.{}) or
        !valid_stream_operation(stream.drop_writable, &.{"i32"}, &.{}) or
        !valid_stream_operation(stream.read, &.{ "i32", "i32", "i32" }, &.{"i32"}) or
        !valid_stream_operation(stream.write, &.{ "i32", "i32", "i32" }, &.{"i32"}) or
        !valid_stream_operation(future_new, &.{}, &.{"i64"}) or
        !valid_stream_operation(future_cancel_read, &.{"i32"}, &.{"i32"}) or
        !valid_stream_operation(future_cancel_write, &.{"i32"}, &.{"i32"}) or
        !valid_stream_operation(future.drop_readable, &.{"i32"}, &.{}) or
        !valid_stream_operation(future_drop_writable, &.{"i32"}, &.{}) or
        !valid_stream_operation(future_read, &.{ "i32", "i32" }, &.{"i32"}) or
        !valid_stream_operation(future_write, &.{ "i32", "i32" }, &.{"i32"})) return null;

    return .{
        .element = record_layout.name,
        .stream_index = 0,
        .future_index = 1,
        .method = .{
            .import_name = descriptor.canonical.async_import_name,
            .core_params = descriptor.canonical.core_params,
            .core_results = descriptor.canonical.core_results,
        },
        .stream = stream,
        .future = future,
        .record_layout = record_layout,
        .list_layout = list_layout,
    };
}

fn valid_record_resource_list_stream_producer_descriptor(descriptor: Descriptor) ?RecordResourceListStreamProducerShape {
    const stream = descriptor.canonical.stream orelse return null;
    const record_layout = descriptor.canonical.record_layout orelse return null;
    const list_layout = descriptor.canonical.list_resource_layout orelse return null;
    const producer = descriptor.canonical.producer orelse return null;

    if (!std.mem.eql(u8, descriptor.effect, "record-resource-list-stream-producer") or
        !std.mem.eql(u8, descriptor.locator, "do:g6-2-c-min-producer@0.1.0") or
        !std.mem.eql(u8, descriptor.member, "consume-via-stream") or
        descriptor.params.len != 1 or
        !std.mem.eql(u8, descriptor.params[0], "stream<list<resource-entry>>") or
        descriptor.resource != null or
        !std.mem.eql(u8, descriptor.result, "Result<nil,error-code>") or
        descriptor.wit_sha256 == null or
        !std.mem.eql(u8, descriptor.wit_sha256.?, "8decd27aeca4a1f1863544860caec230a1fc50259336a893de79413c6f9ec3f7") or
        !std.mem.eql(u8, descriptor.wit.package, "do:g6-2-c-min-producer@0.1.0") or
        !std.mem.eql(u8, descriptor.wit.interface, "sink") or
        !std.mem.eql(u8, descriptor.wit.operation, "consume-via-stream") or
        !std.mem.eql(u8, descriptor.wit.world, "c-min-producer") or
        !std.mem.eql(u8, descriptor.wit.parameter, "data") or
        !equal_core_types(descriptor.canonical.core_params, &.{ "i32", "i32" }) or
        !equal_core_types(descriptor.canonical.core_results, &.{"i32"}) or
        !equal_core_types(descriptor.canonical.completion_params, &.{ "i32", "i32" }) or
        !std.mem.eql(u8, descriptor.canonical.completion, "task-return") or
        !std.mem.eql(u8, descriptor.canonical.async_import_module, "do:g6-2-c-min-producer/sink@0.1.0") or
        !std.mem.eql(u8, descriptor.canonical.async_import_name, "[async-lower]consume-via-stream") or
        descriptor.canonical.future != null or
        descriptor.canonical.future_input != null or
        descriptor.canonical.result_payload != null or
        descriptor.canonical.future_owned != null or
        descriptor.canonical.error_variants.len != 0 or
        !valid_list_resource_layout(list_layout) or
        !valid_single_ticket_record_layout(record_layout) or
        !std.mem.eql(u8, stream.element, "list<resource-entry>") or
        !valid_producer_canonical(producer) or
        !std.mem.eql(u8, producer.resource_drop_import, "[resource-drop]ticket")) return null;

    if (!valid_named_stream_operation(stream.new, "[stream-new-0]consume-via-stream", &.{}, &.{"i64"}) or
        !valid_named_stream_operation(stream.cancel_read, "[stream-cancel-read-0]consume-via-stream", &.{"i32"}, &.{"i32"}) or
        !valid_named_stream_operation(stream.cancel_write, "[stream-cancel-write-0]consume-via-stream", &.{"i32"}, &.{"i32"}) or
        !valid_named_stream_operation(stream.drop_readable, "[stream-drop-readable-0]consume-via-stream", &.{"i32"}, &.{}) or
        !valid_named_stream_operation(stream.drop_writable, "[stream-drop-writable-0]consume-via-stream", &.{"i32"}, &.{}) or
        !valid_named_stream_operation(stream.read, "[async-lower][stream-read-0]consume-via-stream", &.{ "i32", "i32", "i32" }, &.{"i32"}) or
        !valid_named_stream_operation(stream.write, "[async-lower][stream-write-0]consume-via-stream", &.{ "i32", "i32", "i32" }, &.{"i32"})) return null;

    return .{
        .element = record_layout.name,
        .stream_index = 0,
        .method = .{
            .import_name = descriptor.canonical.async_import_name,
            .core_params = descriptor.canonical.core_params,
            .core_results = descriptor.canonical.core_results,
        },
        .stream = stream,
        .record_layout = record_layout,
        .list_layout = list_layout,
        .producer = producer,
    };
}

fn valid_record_resource_list_stream_dynamic_producer_descriptor(descriptor: Descriptor) ?RecordResourceListStreamProducerShape {
    const stream = descriptor.canonical.stream orelse return null;
    const record_layout = descriptor.canonical.record_layout orelse return null;
    const list_layout = descriptor.canonical.list_resource_layout orelse return null;
    const producer = descriptor.canonical.producer orelse return null;

    if (!std.mem.eql(u8, descriptor.effect, "record-resource-list-stream-dynamic-producer") or
        !std.mem.eql(u8, descriptor.locator, "do:g6-2-c-min-dynamic-producer@0.1.0") or
        !std.mem.eql(u8, descriptor.member, "consume-via-stream") or
        descriptor.params.len != 1 or
        !std.mem.eql(u8, descriptor.params[0], "stream<list<resource-entry>>") or
        descriptor.resource != null or
        !std.mem.eql(u8, descriptor.result, "Result<nil,error-code>") or
        descriptor.wit_sha256 == null or
        !std.mem.eql(u8, descriptor.wit_sha256.?, "95f6d2d616e80248a8710e10199fa3674aa80b76247f25c2e71d3d87ea4afe76") or
        !std.mem.eql(u8, descriptor.wit.package, "do:g6-2-c-min-dynamic-producer@0.1.0") or
        !std.mem.eql(u8, descriptor.wit.interface, "sink") or
        !std.mem.eql(u8, descriptor.wit.operation, "consume-via-stream") or
        !std.mem.eql(u8, descriptor.wit.world, "dynamic-list-producer") or
        !std.mem.eql(u8, descriptor.wit.parameter, "data") or
        !equal_core_types(descriptor.canonical.core_params, &.{ "i32", "i32" }) or
        !equal_core_types(descriptor.canonical.core_results, &.{ "i32" }) or
        !equal_core_types(descriptor.canonical.completion_params, &.{ "i32", "i32" }) or
        !std.mem.eql(u8, descriptor.canonical.completion, "task-return") or
        !std.mem.eql(u8, descriptor.canonical.async_import_module, "do:g6-2-c-min-dynamic-producer/sink@0.1.0") or
        !std.mem.eql(u8, descriptor.canonical.async_import_name, "[async-lower]consume-via-stream") or
        descriptor.canonical.future != null or
        descriptor.canonical.future_input != null or
        descriptor.canonical.result_payload != null or
        descriptor.canonical.future_owned != null or
        descriptor.canonical.error_variants.len != 0 or
        !valid_list_resource_layout(list_layout) or
        !valid_single_ticket_record_layout(record_layout) or
        !std.mem.eql(u8, stream.element, "list<resource-entry>") or
        !std.mem.eql(u8, producer.source_module, "do:g6-2-c-min-dynamic-producer/source@0.1.0") or
        !std.mem.eql(u8, producer.source_import_name, "make-ticket") or
        !equal_core_types(producer.source_core_params, &.{ "i32" }) or
        !equal_core_types(producer.source_core_results, &.{ "i32" }) or
        !std.mem.eql(u8, producer.resource_drop_import, "[resource-drop]ticket") or
        producer.stream_capacity != 1 or
        !std.mem.eql(u8, producer.terminal, "result-area") or
        producer.runtime_count_param == null or
        !std.mem.eql(u8, producer.runtime_count_param.?, "u32") or
        producer.runtime_max == null or
        producer.runtime_max.? != 3) return null;

    if (!valid_named_stream_operation(stream.new, "[stream-new-0]consume-via-stream", &.{}, &.{ "i64" }) or
        !valid_named_stream_operation(stream.cancel_read, "[stream-cancel-read-0]consume-via-stream", &.{ "i32" }, &.{ "i32" }) or
        !valid_named_stream_operation(stream.cancel_write, "[stream-cancel-write-0]consume-via-stream", &.{ "i32" }, &.{ "i32" }) or
        !valid_named_stream_operation(stream.drop_readable, "[stream-drop-readable-0]consume-via-stream", &.{ "i32" }, &.{}) or
        !valid_named_stream_operation(stream.drop_writable, "[stream-drop-writable-0]consume-via-stream", &.{ "i32" }, &.{}) or
        !valid_named_stream_operation(stream.read, "[async-lower][stream-read-0]consume-via-stream", &.{ "i32", "i32", "i32" }, &.{ "i32" }) or
        !valid_named_stream_operation(stream.write, "[async-lower][stream-write-0]consume-via-stream", &.{ "i32", "i32", "i32" }, &.{ "i32" })) return null;

    return .{
        .element = record_layout.name,
        .stream_index = 0,
        .method = .{
            .import_name = descriptor.canonical.async_import_name,
            .core_params = descriptor.canonical.core_params,
            .core_results = descriptor.canonical.core_results,
        },
        .stream = stream,
        .record_layout = record_layout,
        .list_layout = list_layout,
        .producer = producer,
    };
}

fn valid_producer_canonical(producer: ProducerCanonical) bool {
    return std.mem.eql(u8, producer.source_module, "do:g6-2-c-min-producer/source@0.1.0") and
        std.mem.eql(u8, producer.source_import_name, "make-ticket") and
        equal_core_types(producer.source_core_params, &.{"i32"}) and
        equal_core_types(producer.source_core_results, &.{"i32"}) and
        std.mem.eql(u8, producer.resource_drop_import, "[resource-drop]ticket") and
        producer.stream_capacity == 1 and
        std.mem.eql(u8, producer.terminal, "result-area");
}

fn valid_variant_resource_stream_reader_descriptor(descriptor: Descriptor) ?VariantResourceStreamShape {
    const stream = descriptor.canonical.variant_stream orelse return null;
    const future = descriptor.canonical.variant_future orelse return null;
    const event = descriptor.canonical.event_layout orelse return null;
    const ticket_drop_import = descriptor.canonical.ticket_drop_import orelse return null;

    if (!std.mem.eql(u8, descriptor.effect, "variant-resource-stream-reader") or
        !std.mem.eql(u8, descriptor.locator, "do:variant-resource-stream-canonical@0.1.0") or
        !std.mem.eql(u8, descriptor.member, "read-via-stream") or
        descriptor.params.len != 0 or
        descriptor.resource != null or
        !std.mem.eql(u8, descriptor.result, "tuple<stream<event>,future<result<_,error-code>>>") or
        !std.mem.eql(u8, descriptor.wit.package, "do:variant-resource-stream-canonical@0.1.0") or
        !std.mem.eql(u8, descriptor.wit.interface, "source") or
        !std.mem.eql(u8, descriptor.wit.operation, "read-via-stream") or
        !std.mem.eql(u8, descriptor.wit.world, "variant-resource-stream-canonical") or
        descriptor.wit.parameter.len != 0 or
        !equal_core_types(descriptor.canonical.core_params, &.{"i32"}) or
        !equal_core_types(descriptor.canonical.core_results, &.{}) or
        !equal_core_types(descriptor.canonical.completion_params, &.{}) or
        !std.mem.eql(u8, descriptor.canonical.completion, "result-area") or
        !std.mem.eql(u8, descriptor.canonical.async_import_module, "do:variant-resource-stream-canonical/source@0.1.0") or
        !std.mem.eql(u8, descriptor.canonical.async_import_name, "read-via-stream") or
        !std.mem.eql(u8, stream.element, "event") or
        !valid_named_stream_operation(stream.read, "[async-lower][stream-read-0]read-via-stream", &.{ "i32", "i32", "i32" }, &.{"i32"}) or
        !valid_named_stream_operation(stream.drop_readable, "[stream-drop-readable-0]read-via-stream", &.{"i32"}, &.{}) or
        !valid_named_stream_operation(future.read, "[async-lower][future-read-1]read-via-stream", &.{"i32", "i32"}, &.{"i32"}) or
        !valid_named_stream_operation(future.drop_readable, "[future-drop-readable-1]read-via-stream", &.{"i32"}, &.{}) or
        !std.mem.eql(u8, ticket_drop_import, "[resource-drop]ticket") or
        !valid_variant_event_layout(event)) return null;

    return .{
        .element = stream.element,
        .stream_index = 0,
        .future_index = 1,
        .stream_read = stream.read,
        .stream_drop_readable = stream.drop_readable,
        .future_read = future.read,
        .future_drop_readable = future.drop_readable,
        .ticket_drop_import = ticket_drop_import,
        .event = event,
    };
}

fn valid_variant_event_layout(layout: VariantEventLayout) bool {
    if (layout.tag_offset != 0 or layout.payload_offset != 4 or layout.byte_size != 8 or layout.alignment != 4 or
        layout.variants.len != 3) return false;

    const expected = [_]struct { name: []const u8, tag: u32, payload: ?[]const u8 }{
        .{ .name = "ticket", .tag = 0, .payload = "own<ticket>" },
        .{ .name = "idle", .tag = 1, .payload = null },
        .{ .name = "failed", .tag = 2, .payload = "error-code" },
    };
    for (expected, 0..) |want, index| {
        const actual = layout.variants[index];
        if (!std.mem.eql(u8, actual.name, want.name) or actual.tag != want.tag) return false;
        if (want.payload) |payload| {
            if (actual.payload == null or !std.mem.eql(u8, actual.payload.?, payload)) return false;
        } else if (actual.payload != null) return false;
    }
    for (layout.variants, 0..) |actual, index| {
        for (layout.variants[index + 1 ..]) |other| {
            if (actual.tag == other.tag or std.mem.eql(u8, actual.name, other.name)) return false;
        }
    }
    return true;
}

fn valid_list_resource_layout(layout: ListResourceLayout) bool {
    return layout.result_pointer_offset == 64 and
        layout.result_length_offset == 68 and
        layout.element_stride == 4 and
        layout.ticket_offset == 0 and
        layout.max_items == 3;
}

fn valid_single_ticket_record_layout(layout: RecordLayout) bool {
    if (!std.mem.eql(u8, layout.name, "resource-entry") or
        layout.byte_size != 4 or
        layout.fields.len != 1 or
        layout.source_fields.len != 1) return false;
    const field = layout.fields[0];
    const source = layout.source_fields[0];
    return std.mem.eql(u8, field.name, "ticket") and
        std.mem.eql(u8, field.core_type, "i32") and
        field.offset == 0 and
        std.mem.eql(u8, source.name, "ticket") and
        std.mem.eql(u8, source.source_type, "ticket") and
        source.storage.len == 1 and
        std.mem.eql(u8, source.storage[0], "ticket") and
        source.ownership == .own and
        source.resource != null and
        std.mem.eql(u8, source.resource.?, "ticket") and
        source.drop_import != null and
        std.mem.eql(u8, source.drop_import.?, "[resource-drop]ticket") and
        source.nested_fields.len == 0;
}

fn valid_record_stream_result(result: []const u8, element: []const u8) bool {
    const prefix = "tuple<stream<";
    const suffix = ">,future<result<_,error-code>>>";
    if (!std.mem.startsWith(u8, result, prefix) or !std.mem.endsWith(u8, result, suffix)) return false;
    const element_end = result.len - suffix.len;
    return element_end > prefix.len and std.mem.eql(u8, result[prefix.len..element_end], element);
}

fn valid_record_stream_layout(layout: RecordLayout, element: []const u8) bool {
    if (layout.fields.len == 0 or layout.source_fields.len == 0 or !std.mem.eql(u8, layout.name, element)) return false;
    var nested_count: usize = 0;
    for (layout.source_fields) |field| {
        if (field.nested_fields.len != 0) nested_count += 1;
    }
    if (nested_count != 0 and nested_count != layout.source_fields.len) return false;
    for (layout.source_fields) |field| {
        if (field.nested_fields.len != 0) {
            if (field.ownership != .none or field.resource != null or field.drop_import != null or field.storage.len != 0 or
                field.nested_fields.len != 1 or !valid_nested_resource_field(layout, field.nested_fields[0])) return false;
            continue;
        }
        if (field.ownership == .none) {
            if (field.resource != null or field.drop_import != null) return false;
            continue;
        }
        if (field.ownership != .own or field.resource == null or field.drop_import == null) return false;
        if (field.storage.len != 1 or !std.mem.eql(u8, field.source_type, field.resource.?)) return false;
        if (!record_drop_import_matches(field.drop_import.?, field.resource.?)) return false;
        const storage = field.storage[0];
        const core = for (layout.fields) |layout_field| {
            if (std.mem.eql(u8, layout_field.name, storage)) break layout_field;
        } else return false;
        if (!std.mem.eql(u8, core.core_type, "i32") or core.offset % 4 != 0) return false;
    }
    return true;
}

fn valid_nested_resource_field(layout: RecordLayout, field: RecordNestedField) bool {
    if (field.nested_fields.len != 0) {
        return field.ownership == .none and field.resource == null and field.drop_import == null and
            field.storage.len == 0 and field.nested_fields.len == 1 and valid_nested_resource_field(layout, field.nested_fields[0]);
    }
    if (field.ownership != .own or field.resource == null or field.drop_import == null or
        field.storage.len != 1 or !std.mem.eql(u8, field.source_type, field.resource.?) or
        !record_drop_import_matches(field.drop_import.?, field.resource.?)) return false;
    const storage = layout.field_offset(field.storage[0]) orelse return false;
    const core_type = for (layout.fields) |layout_field| {
        if (std.mem.eql(u8, layout_field.name, field.storage[0])) break layout_field.core_type;
    } else return false;
    return std.mem.eql(u8, core_type, "i32") and storage % 4 == 0;
}

fn valid_pinned_directory_entry_layout(layout: RecordLayout) bool {
    if (!std.mem.eql(u8, layout.name, "directory-entry") or
        layout.byte_size != 12 or
        layout.fields.len != 3 or
        layout.source_fields.len != 2) return false;
    const expected = [_]struct { name: []const u8, core_type: []const u8, offset: u32 }{
        .{ .name = "type", .core_type = "i32", .offset = 0 },
        .{ .name = "name-ptr", .core_type = "i32", .offset = 4 },
        .{ .name = "name-len", .core_type = "i32", .offset = 8 },
    };
    for (expected, 0..) |field, index| {
        const actual = layout.fields[index];
        if (!std.mem.eql(u8, actual.name, field.name) or
            !std.mem.eql(u8, actual.core_type, field.core_type) or
            actual.offset != field.offset) return false;
    }
    const source_type = layout.source_fields[0];
    const source_name = layout.source_fields[1];
    return std.mem.eql(u8, source_type.name, "type") and
        std.mem.eql(u8, source_type.source_type, "descriptor-type") and
        source_type.storage.len == 1 and
        std.mem.eql(u8, source_type.storage[0], "type") and
        std.mem.eql(u8, source_name.name, "name") and
        std.mem.eql(u8, source_name.source_type, "string") and
        source_name.storage.len == 2 and
        std.mem.eql(u8, source_name.storage[0], "name-ptr") and
        std.mem.eql(u8, source_name.storage[1], "name-len");
}

fn valid_http_stream_reader_descriptor(descriptor: Descriptor) ?HttpStreamReaderShape {
    const stream = descriptor.canonical.stream orelse return null;
    const future_input = descriptor.canonical.future_input orelse return null;
    const future = descriptor.canonical.future orelse return null;
    const future_new = future_input.new orelse return null;
    const future_input_write = future_input.write orelse return null;
    const future_input_cancel_read = future_input.cancel_read orelse return null;
    const future_input_cancel_write = future_input.cancel_write orelse return null;
    const future_input_drop_writable = future_input.drop_writable orelse return null;
    const future_cancel_read = future.cancel_read orelse return null;
    const future_cancel_write = future.cancel_write orelse return null;
    const future_drop_writable = future.drop_writable orelse return null;
    const future_read = future.read orelse return null;
    if (future.new != null) return null;
    if (descriptor.params.len != 1 or descriptor.resource == null or
        !std.mem.eql(u8, descriptor.params[0], "HttpResponse") or
        !std.mem.eql(u8, descriptor.resource.?, "response") or
        !std.mem.eql(u8, descriptor.result, "tuple<stream<u8>,future<result<option<trailers>,error-code>>>") or
        !std.mem.eql(u8, descriptor.canonical.completion, "result-area") or
        !equal_core_types(descriptor.canonical.core_params, &.{ "i32", "i32", "i32" }) or
        descriptor.canonical.core_results.len != 0 or descriptor.canonical.completion_params.len != 0 or
        !std.mem.eql(u8, stream.element, "u8")) return null;
    if (!valid_stream_operation(future_new, &.{}, &.{"i64"}) or
        !valid_stream_operation(future_input_write, &.{ "i32", "i32" }, &.{"i32"}) or
        !valid_stream_operation(future_input_cancel_read, &.{"i32"}, &.{"i32"}) or
        !valid_stream_operation(future_input_cancel_write, &.{"i32"}, &.{"i32"}) or
        !valid_stream_operation(future_input.drop_readable, &.{"i32"}, &.{}) or
        !valid_stream_operation(future_input_drop_writable, &.{"i32"}, &.{}) or
        !valid_stream_operation(future_cancel_read, &.{"i32"}, &.{"i32"}) or
        !valid_stream_operation(future_cancel_write, &.{"i32"}, &.{"i32"}) or
        !valid_stream_operation(future_read, &.{ "i32", "i32" }, &.{"i32"}) or
        !valid_stream_operation(future_drop_writable, &.{"i32"}, &.{}) or
        !valid_stream_operation(stream.new, &.{}, &.{"i64"}) or
        !valid_stream_operation(stream.cancel_read, &.{"i32"}, &.{"i32"}) or
        !valid_stream_operation(stream.cancel_write, &.{"i32"}, &.{"i32"}) or
        !valid_stream_operation(stream.drop_writable, &.{"i32"}, &.{}) or
        !valid_stream_operation(stream.read, &.{ "i32", "i32", "i32" }, &.{"i32"}) or
        !valid_stream_operation(stream.drop_readable, &.{"i32"}, &.{}) or
        !valid_stream_operation(future.drop_readable, &.{"i32"}, &.{})) return null;
    return .{
        .source_param = descriptor.params[0],
        .resource = descriptor.resource.?,
        .element = stream.element,
        .future_new = future_new,
        .future_write = future_input_write,
        .future_read = future_read,
        .read = stream.read,
        .drop_readable = stream.drop_readable,
        .future_drop_readable = future.drop_readable,
        .future_drop_writable = future_input_drop_writable,
    };
}

fn valid_stream_operation(operation: StreamOperation, params: []const []const u8, results: []const []const u8) bool {
    return operation.import_name.len != 0 and
        equal_core_types(operation.core_params, params) and
        equal_core_types(operation.core_results, results);
}

fn valid_named_stream_operation(
    operation: StreamOperation,
    import_name: []const u8,
    params: []const []const u8,
    results: []const []const u8,
) bool {
    return std.mem.eql(u8, operation.import_name, import_name) and
        valid_stream_operation(operation, params, results);
}

fn equal_core_types(actual: []const []const u8, expected: []const []const u8) bool {
    if (actual.len != expected.len) return false;
    for (actual, 0..) |value, index| {
        if (!std.mem.eql(u8, value, expected[index])) return false;
    }
    return true;
}

fn parse_result_payload(allocator: std.mem.Allocator, value: ?std.json.Value) !ResultPayload {
    const object = object_value(value orelse return error.InvalidP3AsyncManifest) orelse return error.InvalidP3AsyncManifest;
    const tag = try duplicate_required(allocator, object.get("tag"));
    errdefer allocator.free(tag);
    const ok = try duplicate_params(allocator, array_value(object.get("ok")) orelse return error.InvalidP3AsyncManifest);
    errdefer free_string_list(allocator, ok);
    const err = try duplicate_params(allocator, array_value(object.get("err")) orelse return error.InvalidP3AsyncManifest);
    errdefer free_string_list(allocator, err);
    if (!std.mem.eql(u8, tag, "i32") or !valid_scalar_arm(ok) or !valid_scalar_arm(err)) return error.InvalidP3AsyncManifest;
    return .{ .tag = tag, .ok = ok, .err = err };
}

fn parse_error_variants(
    allocator: std.mem.Allocator,
    value: std.json.Value,
    completion: []const u8,
    completion_params: []const []const u8,
) ![]const ErrorVariantPayload {
    if (!std.mem.eql(u8, completion, "task-return") or completion_params.len < 3 or
        !std.mem.eql(u8, completion_params[0], "i32") or
        !std.mem.eql(u8, completion_params[1], "i32")) return error.InvalidP3AsyncManifest;
    const values = array_value(value) orelse return error.InvalidP3AsyncManifest;
    if (values.items.len == 0) return error.InvalidP3AsyncManifest;

    var variants = try std.ArrayList(ErrorVariantPayload).initCapacity(allocator, values.items.len);
    errdefer {
        for (variants.items) |variant| free_error_variant(allocator, variant);
        variants.deinit(allocator);
    }

    var max_flat_words: usize = 0;
    for (values.items) |variant_value| {
        const object = object_value(variant_value) orelse return error.InvalidP3AsyncManifest;
        const variant = try duplicate_required(allocator, object.get("variant"));
        errdefer allocator.free(variant);
        const raw_discriminant = unsigned_value(object.get("discriminant")) orelse return error.InvalidP3AsyncManifest;
        const raw_byte_size = unsigned_value(object.get("byte_size")) orelse return error.InvalidP3AsyncManifest;
        if (variant.len == 0 or raw_discriminant > std.math.maxInt(u32) or
            raw_byte_size == 0 or raw_byte_size > std.math.maxInt(u32) or raw_byte_size % 4 != 0) return error.InvalidP3AsyncManifest;
        const discriminant: u32 = @intCast(raw_discriminant);
        const byte_size: u32 = @intCast(raw_byte_size);
        for (variants.items) |previous| {
            if (std.mem.eql(u8, previous.variant, variant) or previous.discriminant == discriminant) return error.InvalidP3AsyncManifest;
        }

        const field_values = array_value(object.get("fields")) orelse return error.InvalidP3AsyncManifest;
        if (field_values.items.len == 0) return error.InvalidP3AsyncManifest;
        var fields = std.ArrayList(ErrorVariantField).empty;
        errdefer {
            for (fields.items) |field| free_error_variant_field(allocator, field);
            fields.deinit(allocator);
        }
        var flat_words: usize = 0;
        for (field_values.items) |field_value| {
            const field_object = object_value(field_value) orelse return error.InvalidP3AsyncManifest;
            const name = try duplicate_required(allocator, field_object.get("name"));
            errdefer allocator.free(name);
            const kind = try parse_error_variant_field_kind(field_object.get("kind"));
            const core_words = try duplicate_params(allocator, array_value(field_object.get("core_words")) orelse return error.InvalidP3AsyncManifest);
            errdefer free_string_list(allocator, core_words);
            const raw_offset = unsigned_value(field_object.get("offset")) orelse return error.InvalidP3AsyncManifest;
            if (name.len == 0 or raw_offset > std.math.maxInt(u32) or raw_offset % 4 != 0 or
                !error_variant_core_words_match(kind, core_words)) return error.InvalidP3AsyncManifest;
            const offset: u32 = @intCast(raw_offset);
            const field_size = error_variant_field_byte_size(kind);
            const field_end = @as(u64, offset) + field_size;
            if (field_end > byte_size) return error.InvalidP3AsyncManifest;
            for (fields.items) |previous| {
                const previous_end = @as(u64, previous.offset) + error_variant_field_byte_size(previous.kind);
                if (std.mem.eql(u8, previous.name, name) or
                    (@as(u64, offset) < previous_end and @as(u64, previous.offset) < field_end)) return error.InvalidP3AsyncManifest;
            }
            flat_words += core_words.len;
            try fields.append(allocator, .{ .name = name, .kind = kind, .core_words = core_words, .offset = offset });
            errdefer _ = fields.pop();
        }
        if (flat_words > max_flat_words) max_flat_words = flat_words;
        try variants.append(allocator, .{
            .variant = variant,
            .discriminant = discriminant,
            .byte_size = byte_size,
            .fields = try fields.toOwnedSlice(allocator),
        });
        errdefer _ = variants.pop();
    }

    if (completion_params.len != 2 + max_flat_words + 1) return error.InvalidP3AsyncManifest;
    for (completion_params[2 .. completion_params.len - 1]) |word| {
        if (!std.mem.eql(u8, word, "i32") and !std.mem.eql(u8, word, "i64")) return error.InvalidP3AsyncManifest;
    }
    if (!std.mem.eql(u8, completion_params[completion_params.len - 1], "i32")) return error.InvalidP3AsyncManifest;
    return try variants.toOwnedSlice(allocator);
}

fn parse_error_variant_field_kind(value: ?std.json.Value) !ErrorVariantFieldKind {
    const text = string_value(value) orelse return error.InvalidP3AsyncManifest;
    if (std.mem.eql(u8, text, "optional_string")) return .optional_string;
    if (std.mem.eql(u8, text, "optional_u16")) return .optional_u16;
    return error.InvalidP3AsyncManifest;
}

fn error_variant_core_words_match(kind: ErrorVariantFieldKind, words: []const []const u8) bool {
    return switch (kind) {
        .optional_string => equal_core_types(words, &.{ "i32", "i64", "i32" }),
        .optional_u16 => equal_core_types(words, &.{ "i32", "i32" }),
    };
}

fn error_variant_field_byte_size(kind: ErrorVariantFieldKind) u64 {
    return switch (kind) {
        .optional_string => 12,
        .optional_u16 => 4,
    };
}

fn parse_record_layout(allocator: std.mem.Allocator, value: std.json.Value) !RecordLayout {
    const object = object_value(value) orelse return error.InvalidP3AsyncManifest;
    const name = try duplicate_required(allocator, object.get("name"));
    errdefer allocator.free(name);
    if (name.len == 0) return error.InvalidP3AsyncManifest;
    const raw_byte_size = unsigned_value(object.get("byte_size")) orelse return error.InvalidP3AsyncManifest;
    if (raw_byte_size == 0 or raw_byte_size > std.math.maxInt(u32) or raw_byte_size % 4 != 0) return error.InvalidP3AsyncManifest;
    const byte_size: u32 = @intCast(raw_byte_size);
    const values = array_value(object.get("fields")) orelse return error.InvalidP3AsyncManifest;
    if (values.items.len == 0) return error.InvalidP3AsyncManifest;

    var fields = try std.ArrayList(RecordField).initCapacity(allocator, values.items.len);
    errdefer {
        for (fields.items) |field| {
            allocator.free(field.name);
            allocator.free(field.core_type);
        }
        fields.deinit(allocator);
    }

    for (values.items) |field_value| {
        const field_object = object_value(field_value) orelse return error.InvalidP3AsyncManifest;
        const field_name = try duplicate_required(allocator, field_object.get("name"));
        errdefer allocator.free(field_name);
        const core_type = try duplicate_required(allocator, field_object.get("core_type"));
        errdefer allocator.free(core_type);
        const raw_offset = unsigned_value(field_object.get("offset")) orelse return error.InvalidP3AsyncManifest;
        if (field_name.len == 0 or !is_core_scalar(core_type) or raw_offset > std.math.maxInt(u32) or raw_offset % 4 != 0) {
            return error.InvalidP3AsyncManifest;
        }
        const offset: u32 = @intCast(raw_offset);
        const offset_end = @as(u64, offset) + 4;
        if (offset_end > byte_size) return error.InvalidP3AsyncManifest;
        for (fields.items) |previous| {
            const previous_end = @as(u64, previous.offset) + 4;
            if (std.mem.eql(u8, previous.name, field_name) or
                (@as(u64, offset) < previous_end and @as(u64, previous.offset) < offset_end)) return error.InvalidP3AsyncManifest;
        }
        try fields.append(allocator, .{ .name = field_name, .core_type = core_type, .offset = offset });
        errdefer _ = fields.pop();
    }

    const source_values = array_value(object.get("source_fields")) orelse return error.InvalidP3AsyncManifest;
    if (source_values.items.len == 0) return error.InvalidP3AsyncManifest;
    var source_fields = try std.ArrayList(RecordSourceField).initCapacity(allocator, source_values.items.len);
    errdefer {
        for (source_fields.items) |field| {
            allocator.free(field.name);
            allocator.free(field.source_type);
            free_string_list(allocator, field.storage);
            if (field.resource) |resource| allocator.free(resource);
            if (field.drop_import) |drop_import| allocator.free(drop_import);
            free_nested_fields(allocator, field.nested_fields);
        }
        source_fields.deinit(allocator);
    }

    for (source_values.items) |source_value| {
        const source_object = object_value(source_value) orelse return error.InvalidP3AsyncManifest;
        const source_name = try duplicate_required(allocator, source_object.get("name"));
        errdefer allocator.free(source_name);
        const source_type = try duplicate_required(allocator, source_object.get("source_type"));
        errdefer allocator.free(source_type);
        const storage = try duplicate_params(allocator, array_value(source_object.get("storage")) orelse return error.InvalidP3AsyncManifest);
        errdefer free_string_list(allocator, storage);
        const ownership = try parse_record_ownership(source_object.get("ownership"));
        const resource = try duplicate_optional_text(allocator, source_object.get("resource"));
        errdefer if (resource) |resource_value| allocator.free(resource_value);
        const drop_import = try duplicate_optional_text(allocator, source_object.get("drop_import"));
        errdefer if (drop_import) |drop_value| allocator.free(drop_value);
        const nested_fields = try parse_nested_fields(allocator, source_object.get("nested_fields"), 0);
        errdefer free_nested_fields(allocator, nested_fields);
        const is_nested = nested_fields.len != 0;
        const is_resource = ownership != .none or resource != null or drop_import != null;
        if (source_name.len == 0 or
            (is_nested and (is_resource or storage.len != 0 or nested_fields.len != 1)) or
            (is_resource and (ownership != .own or resource == null or drop_import == null or storage.len != 1 or
                !std.mem.eql(u8, source_type, resource.?) or !record_drop_import_matches(drop_import.?, resource.?))) or
            (!is_nested and !is_resource and (!is_record_source_type(source_type) or
                ((std.mem.eql(u8, source_type, "string") and storage.len != 2) or
                    (!std.mem.eql(u8, source_type, "string") and storage.len != 1))))) return error.InvalidP3AsyncManifest;
        if (is_nested and !valid_nested_resource_fields_for_parse(fields.items, nested_fields)) return error.InvalidP3AsyncManifest;
        for (source_fields.items) |previous| {
            if (std.mem.eql(u8, previous.name, source_name)) return error.InvalidP3AsyncManifest;
        }
        for (storage) |storage_name| {
            const storage_field = for (fields.items) |field| {
                if (std.mem.eql(u8, field.name, storage_name)) break field;
            } else return error.InvalidP3AsyncManifest;
            if (is_resource and !std.mem.eql(u8, storage_field.core_type, "i32")) return error.InvalidP3AsyncManifest;
            for (source_fields.items) |previous| {
                if (source_field_uses_storage(previous, storage_name)) return error.InvalidP3AsyncManifest;
            }
        }
        if (is_nested) {
            if (nested_fields_conflict_with_sources(source_fields.items, nested_fields)) return error.InvalidP3AsyncManifest;
        }
        try source_fields.append(allocator, .{
            .name = source_name,
            .source_type = source_type,
            .storage = storage,
            .ownership = ownership,
            .resource = resource,
            .drop_import = drop_import,
            .nested_fields = nested_fields,
        });
        errdefer _ = source_fields.pop();
    }

    var nested_count: usize = 0;
    for (source_fields.items) |field| {
        if (field.nested_fields.len != 0) nested_count += 1;
    }
    if (nested_count != 0 and nested_count != source_fields.items.len) return error.InvalidP3AsyncManifest;

    return .{
        .name = name,
        .byte_size = byte_size,
        .fields = try fields.toOwnedSlice(allocator),
        .source_fields = try source_fields.toOwnedSlice(allocator),
    };
}

fn parse_wit(allocator: std.mem.Allocator, value: ?std.json.Value) !Wit {
    const wit = object_value(value orelse return error.InvalidP3AsyncManifest) orelse return error.InvalidP3AsyncManifest;
    const package = try duplicate_required(allocator, wit.get("package"));
    errdefer allocator.free(package);
    const interface = try duplicate_required(allocator, wit.get("interface"));
    errdefer allocator.free(interface);
    const operation = try duplicate_required(allocator, wit.get("operation"));
    errdefer allocator.free(operation);
    const world = try duplicate_required(allocator, wit.get("world"));
    errdefer allocator.free(world);
    const parameter = try duplicate_required(allocator, wit.get("parameter"));
    errdefer allocator.free(parameter);
    if (package.len == 0 or interface.len == 0 or operation.len == 0 or world.len == 0) return error.InvalidP3AsyncManifest;
    return .{
        .package = package,
        .interface = interface,
        .operation = operation,
        .world = world,
        .parameter = parameter,
    };
}

fn duplicate_params(allocator: std.mem.Allocator, values: std.json.Array) ![]const []const u8 {
    var params = try std.ArrayList([]const u8).initCapacity(allocator, values.items.len);
    errdefer {
        for (params.items) |param| allocator.free(param);
        params.deinit(allocator);
    }
    for (values.items) |value| {
        const param = string_value(value) orelse return error.InvalidP3AsyncManifest;
        try params.append(allocator, try allocator.dupe(u8, param));
    }
    return params.toOwnedSlice(allocator);
}

fn duplicate_required(allocator: std.mem.Allocator, value: ?std.json.Value) ![]const u8 {
    const text = string_value(value) orelse return error.InvalidP3AsyncManifest;
    return allocator.dupe(u8, text);
}

fn duplicate_optional_sha256(allocator: std.mem.Allocator, value: ?std.json.Value) !?[]const u8 {
    const raw = value orelse return null;
    const hash = string_value(raw) orelse return error.InvalidP3AsyncManifest;
    if (hash.len != 64) return error.InvalidP3AsyncManifest;
    for (hash) |ch| {
        if (!std.ascii.isHex(ch)) return error.InvalidP3AsyncManifest;
    }
    const owned: []const u8 = try allocator.dupe(u8, hash);
    return owned;
}

fn free_descriptors(allocator: std.mem.Allocator, descriptors: []Descriptor) void {
    for (descriptors) |descriptor| free_descriptor(allocator, descriptor);
    allocator.free(descriptors);
}

fn free_descriptor(allocator: std.mem.Allocator, descriptor: Descriptor) void {
    allocator.free(descriptor.locator);
    allocator.free(descriptor.member);
    allocator.free(descriptor.effect);
    for (descriptor.params) |param| allocator.free(param);
    allocator.free(descriptor.params);
    allocator.free(descriptor.result);
    if (descriptor.resource) |resource| allocator.free(resource);
    if (descriptor.wit_sha256) |hash| allocator.free(hash);
    free_canonical(allocator, descriptor.canonical);
    free_wit(allocator, descriptor.wit);
}

fn free_wit(allocator: std.mem.Allocator, wit: Wit) void {
    allocator.free(wit.package);
    allocator.free(wit.interface);
    allocator.free(wit.operation);
    allocator.free(wit.world);
    allocator.free(wit.parameter);
}

fn free_canonical(allocator: std.mem.Allocator, canonical: Canonical) void {
    free_string_list(allocator, canonical.core_params);
    free_string_list(allocator, canonical.core_results);
    free_string_list(allocator, canonical.completion_params);
    allocator.free(canonical.completion);
    if (canonical.result_payload) |payload| free_result_payload(allocator, payload);
    if (canonical.future_owned) |owned| free_future_owned_canonical(allocator, owned);
    free_error_variants(allocator, canonical.error_variants);
    if (canonical.record_layout) |layout| free_record_layout(allocator, layout);
    if (canonical.producer) |producer| free_producer_canonical(allocator, producer);
    allocator.free(canonical.async_import_module);
    allocator.free(canonical.async_import_name);
    if (canonical.stream) |stream| free_stream_canonical(allocator, stream);
    if (canonical.future_input) |future| free_future_canonical(allocator, future);
    if (canonical.future) |future| free_future_canonical(allocator, future);
    if (canonical.variant_stream) |stream| free_variant_stream_canonical(allocator, stream);
    if (canonical.variant_future) |future| free_variant_future_canonical(allocator, future);
    if (canonical.event_layout) |layout| free_variant_event_layout(allocator, layout);
    if (canonical.ticket_drop_import) |import_name| allocator.free(import_name);
}

fn free_future_owned_canonical(allocator: std.mem.Allocator, owned: FutureOwnedCanonical) void {
    allocator.free(owned.resource);
    allocator.free(owned.drop_import);
}

fn free_producer_canonical(allocator: std.mem.Allocator, producer: ProducerCanonical) void {
    allocator.free(producer.source_module);
    allocator.free(producer.source_import_name);
    free_string_list(allocator, producer.source_core_params);
    free_string_list(allocator, producer.source_core_results);
    allocator.free(producer.resource_drop_import);
    allocator.free(producer.terminal);
    if (producer.runtime_count_param) |value| allocator.free(value);
}

fn free_future_canonical(allocator: std.mem.Allocator, future: FutureCanonical) void {
    if (future.new) |operation| free_stream_operation(allocator, operation);
    if (future.write) |operation| free_stream_operation(allocator, operation);
    if (future.read) |operation| free_stream_operation(allocator, operation);
    if (future.cancel_read) |operation| free_stream_operation(allocator, operation);
    if (future.cancel_write) |operation| free_stream_operation(allocator, operation);
    free_stream_operation(allocator, future.drop_readable);
    if (future.drop_writable) |operation| free_stream_operation(allocator, operation);
}

fn free_stream_canonical(allocator: std.mem.Allocator, stream: StreamCanonical) void {
    allocator.free(stream.element);
    free_stream_operation(allocator, stream.new);
    free_stream_operation(allocator, stream.cancel_read);
    free_stream_operation(allocator, stream.cancel_write);
    free_stream_operation(allocator, stream.drop_readable);
    free_stream_operation(allocator, stream.drop_writable);
    free_stream_operation(allocator, stream.read);
    free_stream_operation(allocator, stream.write);
}

fn free_stream_operation(allocator: std.mem.Allocator, operation: StreamOperation) void {
    allocator.free(operation.import_name);
    free_string_list(allocator, operation.core_params);
    free_string_list(allocator, operation.core_results);
}

fn free_variant_stream_canonical(allocator: std.mem.Allocator, stream: VariantStreamCanonical) void {
    allocator.free(stream.element);
    free_stream_operation(allocator, stream.read);
    free_stream_operation(allocator, stream.drop_readable);
}

fn free_variant_future_canonical(allocator: std.mem.Allocator, future: VariantFutureCanonical) void {
    free_stream_operation(allocator, future.read);
    free_stream_operation(allocator, future.drop_readable);
}

fn free_variant_event_layout(allocator: std.mem.Allocator, layout: VariantEventLayout) void {
    for (layout.variants) |variant| free_variant_event_branch(allocator, variant);
    allocator.free(layout.variants);
}

fn free_variant_event_branch(allocator: std.mem.Allocator, branch: VariantEventBranch) void {
    allocator.free(branch.name);
    if (branch.payload) |payload| allocator.free(payload);
}

fn free_result_payload(allocator: std.mem.Allocator, payload: ResultPayload) void {
    allocator.free(payload.tag);
    free_string_list(allocator, payload.ok);
    free_string_list(allocator, payload.err);
}

fn free_error_variants(allocator: std.mem.Allocator, variants: []const ErrorVariantPayload) void {
    for (variants) |variant| free_error_variant(allocator, variant);
    if (variants.len != 0) allocator.free(variants);
}

fn free_error_variant(allocator: std.mem.Allocator, variant: ErrorVariantPayload) void {
    allocator.free(variant.variant);
    for (variant.fields) |field| free_error_variant_field(allocator, field);
    if (variant.fields.len != 0) allocator.free(variant.fields);
}

fn free_error_variant_field(allocator: std.mem.Allocator, field: ErrorVariantField) void {
    allocator.free(field.name);
    free_string_list(allocator, field.core_words);
}

fn free_record_layout(allocator: std.mem.Allocator, layout: RecordLayout) void {
    allocator.free(layout.name);
    for (layout.fields) |field| {
        allocator.free(field.name);
        allocator.free(field.core_type);
    }
    allocator.free(layout.fields);
    for (layout.source_fields) |field| {
        allocator.free(field.name);
        allocator.free(field.source_type);
        free_string_list(allocator, field.storage);
        if (field.resource) |resource| allocator.free(resource);
        if (field.drop_import) |drop_import| allocator.free(drop_import);
        free_nested_fields(allocator, field.nested_fields);
    }
    allocator.free(layout.source_fields);
}

fn parse_nested_fields(allocator: std.mem.Allocator, value: ?std.json.Value, depth: u8) ![]const RecordNestedField {
    const array = if (value) |actual| array_value(actual) orelse return error.InvalidP3AsyncManifest else return &.{};
    if (array.items.len == 0) return error.InvalidP3AsyncManifest;
    if (depth >= max_nested_container_depth) return error.InvalidP3AsyncManifest;
    var fields = try std.ArrayList(RecordNestedField).initCapacity(allocator, array.items.len);
    errdefer {
        for (fields.items) |field| {
            allocator.free(field.name);
            allocator.free(field.source_type);
            free_string_list(allocator, field.storage);
            if (field.resource) |resource| allocator.free(resource);
            if (field.drop_import) |drop_import| allocator.free(drop_import);
            free_nested_fields(allocator, field.nested_fields);
        }
        fields.deinit(allocator);
    }
    for (array.items) |field_value| {
        const object = object_value(field_value) orelse return error.InvalidP3AsyncManifest;
        const name = try duplicate_required(allocator, object.get("name"));
        errdefer allocator.free(name);
        const source_type = try duplicate_required(allocator, object.get("source_type"));
        errdefer allocator.free(source_type);
        const storage = try duplicate_params(allocator, array_value(object.get("storage")) orelse return error.InvalidP3AsyncManifest);
        errdefer free_string_list(allocator, storage);
        const ownership = try parse_record_ownership(object.get("ownership"));
        const resource = try duplicate_optional_text(allocator, object.get("resource"));
        errdefer if (resource) |value_to_free| allocator.free(value_to_free);
        const drop_import = try duplicate_optional_text(allocator, object.get("drop_import"));
        errdefer if (drop_import) |value_to_free| allocator.free(value_to_free);
        const nested_fields = try parse_nested_fields(allocator, object.get("nested_fields"), depth + 1);
        errdefer free_nested_fields(allocator, nested_fields);
        const is_container = nested_fields.len != 0;
        if (name.len == 0 or
            (is_container and (ownership != .none or resource != null or drop_import != null or storage.len != 0 or nested_fields.len != 1)) or
            (!is_container and (ownership != .own or resource == null or drop_import == null or storage.len != 1 or
                !std.mem.eql(u8, source_type, resource.?) or !record_drop_import_matches(drop_import.?, resource.?)))) return error.InvalidP3AsyncManifest;
        for (fields.items) |previous| {
            if (std.mem.eql(u8, previous.name, name)) return error.InvalidP3AsyncManifest;
            for (previous.storage) |previous_storage| {
                for (storage) |storage_name| {
                    if (std.mem.eql(u8, previous_storage, storage_name)) return error.InvalidP3AsyncManifest;
                }
            }
        }
        try fields.append(allocator, .{ .name = name, .source_type = source_type, .storage = storage, .ownership = ownership, .resource = resource, .drop_import = drop_import, .nested_fields = nested_fields });
        errdefer _ = fields.pop();
    }
    return fields.toOwnedSlice(allocator);
}

fn valid_nested_resource_fields_for_parse(fields: []const RecordField, nested_fields: []const RecordNestedField) bool {
    if (nested_fields.len != 1) return false;
    const nested = nested_fields[0];
    if (nested.nested_fields.len != 0) {
        return nested.ownership == .none and nested.resource == null and nested.drop_import == null and
            nested.storage.len == 0 and valid_nested_resource_fields_for_parse(fields, nested.nested_fields);
    }
    if (nested.storage.len != 1) return false;
    const storage = for (fields) |field| {
        if (std.mem.eql(u8, field.name, nested.storage[0])) break field;
    } else return false;
    return nested.ownership == .own and nested.resource != null and nested.drop_import != null and
        std.mem.eql(u8, nested.source_type, nested.resource.?) and record_drop_import_matches(nested.drop_import.?, nested.resource.?) and
        std.mem.eql(u8, storage.core_type, "i32") and storage.offset % 4 == 0;
}

fn source_field_uses_storage(field: RecordSourceField, storage_name: []const u8) bool {
    for (field.storage) |storage| {
        if (std.mem.eql(u8, storage, storage_name)) return true;
    }
    return nested_fields_use_storage(field.nested_fields, storage_name);
}

fn nested_fields_use_storage(fields: []const RecordNestedField, storage_name: []const u8) bool {
    for (fields) |field| {
        for (field.storage) |storage| {
            if (std.mem.eql(u8, storage, storage_name)) return true;
        }
        if (nested_fields_use_storage(field.nested_fields, storage_name)) return true;
    }
    return false;
}

fn nested_fields_conflict_with_sources(
    source_fields: []const RecordSourceField,
    nested_fields: []const RecordNestedField,
) bool {
    for (nested_fields) |field| {
        for (field.storage) |storage_name| {
            for (source_fields) |previous| {
                if (source_field_uses_storage(previous, storage_name)) return true;
            }
        }
        if (nested_fields_conflict_with_sources(source_fields, field.nested_fields)) return true;
    }
    return false;
}

fn free_nested_fields(allocator: std.mem.Allocator, fields: []const RecordNestedField) void {
    for (fields) |field| {
        allocator.free(field.name);
        allocator.free(field.source_type);
        free_string_list(allocator, field.storage);
        if (field.resource) |resource| allocator.free(resource);
        if (field.drop_import) |drop_import| allocator.free(drop_import);
        free_nested_fields(allocator, field.nested_fields);
    }
    if (fields.len != 0) allocator.free(fields);
}

fn free_string_list(allocator: std.mem.Allocator, items: []const []const u8) void {
    for (items) |item| allocator.free(item);
    allocator.free(items);
}

fn is_core_scalar(value: []const u8) bool {
    return std.mem.eql(u8, value, "i32") or
        std.mem.eql(u8, value, "i64") or
        std.mem.eql(u8, value, "f32") or
        std.mem.eql(u8, value, "f64");
}

fn is_record_source_type(value: []const u8) bool {
    return std.mem.eql(u8, value, "string") or
        std.mem.eql(u8, value, "descriptor-type") or
        std.mem.eql(u8, value, "bool") or
        std.mem.eql(u8, value, "u8") or
        std.mem.eql(u8, value, "u16") or
        std.mem.eql(u8, value, "u32") or
        std.mem.eql(u8, value, "u64") or
        std.mem.eql(u8, value, "i8") or
        std.mem.eql(u8, value, "i16") or
        std.mem.eql(u8, value, "i32") or
        std.mem.eql(u8, value, "i64") or
        std.mem.eql(u8, value, "f32") or
        std.mem.eql(u8, value, "f64");
}

fn parse_record_ownership(value: ?std.json.Value) !RecordOwnership {
    const actual = value orelse return .none;
    const text = string_value(actual) orelse return error.InvalidP3AsyncManifest;
    if (std.mem.eql(u8, text, "none")) return .none;
    if (std.mem.eql(u8, text, "own")) return .own;
    if (std.mem.eql(u8, text, "borrow")) return .borrow;
    return error.InvalidP3AsyncManifest;
}

fn duplicate_optional_text(allocator: std.mem.Allocator, value: ?std.json.Value) !?[]const u8 {
    const actual = value orelse return null;
    const text = string_value(actual) orelse return error.InvalidP3AsyncManifest;
    return try allocator.dupe(u8, text);
}

fn record_drop_import_matches(drop_import: []const u8, resource: []const u8) bool {
    const prefix = "[resource-drop]";
    return drop_import.len == prefix.len + resource.len and
        std.mem.startsWith(u8, drop_import, prefix) and
        std.mem.eql(u8, drop_import[prefix.len..], resource);
}

fn is_result_type(value: []const u8) bool {
    return std.mem.startsWith(u8, value, "Result<") and std.mem.endsWith(u8, value, ">");
}

fn is_scalar_result_type(value: []const u8) bool {
    return scalar_result_source_types(value) != null;
}

pub fn scalar_result_source_types(value: []const u8) ?ScalarResultSource {
    if (!is_result_type(value)) return null;
    const inner = value["Result<".len .. value.len - 1];
    const comma = std.mem.indexOfScalar(u8, inner, ',') orelse return null;
    if (std.mem.indexOfScalar(u8, inner[comma + 1 ..], ',') != null) return null;
    const ok = trim_ascii(inner[0..comma]);
    const err = trim_ascii(inner[comma + 1 ..]);
    if (!is_source_scalar_or_nil(ok) or !is_source_scalar_or_nil(err)) return null;
    return .{ .ok = ok, .err = err };
}

fn is_source_scalar_or_nil(value: []const u8) bool {
    return std.mem.eql(u8, value, "nil") or
        std.mem.eql(u8, value, "bool") or
        std.mem.eql(u8, value, "u8") or
        std.mem.eql(u8, value, "u16") or
        std.mem.eql(u8, value, "u32") or
        std.mem.eql(u8, value, "u64") or
        std.mem.eql(u8, value, "i8") or
        std.mem.eql(u8, value, "i16") or
        std.mem.eql(u8, value, "i32") or
        std.mem.eql(u8, value, "i64") or
        std.mem.eql(u8, value, "f32") or
        std.mem.eql(u8, value, "f64");
}

fn trim_ascii(value: []const u8) []const u8 {
    var start: usize = 0;
    var end = value.len;
    while (start < end and std.ascii.isWhitespace(value[start])) : (start += 1) {}
    while (end > start and std.ascii.isWhitespace(value[end - 1])) : (end -= 1) {}
    return value[start..end];
}

fn valid_scalar_arm(values: []const []const u8) bool {
    if (values.len > 1) return false;
    for (values) |value| {
        if (!is_core_scalar(value)) return false;
    }
    return true;
}

fn scalar_result_layout_matches(descriptor: Descriptor) bool {
    const source = scalar_result_source_types(descriptor.result) orelse return false;
    const payload = descriptor.canonical.result_payload orelse return false;
    if (descriptor.params.len != 1 or descriptor.resource != null or
        source_scalar_core_type(descriptor.params[0]) == null or
        descriptor.canonical.core_params.len != 2 or
        !std.mem.eql(u8, descriptor.canonical.core_params[0], source_scalar_core_type(descriptor.params[0]).?) or
        !std.mem.eql(u8, descriptor.canonical.core_params[1], "i32") or
        descriptor.canonical.core_results.len != 1 or
        !std.mem.eql(u8, descriptor.canonical.core_results[0], "i32") or
        !valid_scalar_arm(payload.ok) or
        !valid_scalar_arm(payload.err) or
        !result_arm_matches(source.ok, payload.ok) or
        !result_arm_matches(source.err, payload.err) or
        !scalar_result_completion_shape(descriptor)) return false;

    if (payload.ok.len == 1 and payload.err.len == 1 and
        !std.mem.eql(u8, payload.ok[0], payload.err[0])) return false;
    return true;
}

fn result_arm_matches(source: []const u8, canonical: []const []const u8) bool {
    const core = source_scalar_core_type(source) orelse return canonical.len == 0;
    return canonical.len == 1 and std.mem.eql(u8, canonical[0], core);
}

fn all_core_scalars(values: []const []const u8) bool {
    for (values) |value| {
        if (!is_core_scalar(value)) return false;
    }
    return true;
}

fn scalar_result_completion_shape(descriptor: Descriptor) bool {
    const payload = descriptor.canonical.result_payload orelse return false;
    if (payload.tag.len == 0 or !std.mem.eql(u8, payload.tag, "i32")) return false;
    const payload_words = if (payload.ok.len > payload.err.len) payload.ok.len else payload.err.len;
    if (descriptor.canonical.completion_params.len != 1 + payload_words or
        descriptor.canonical.completion_params.len == 0 or
        !std.mem.eql(u8, descriptor.canonical.completion_params[0], "i32")) return false;
    if (payload_words == 1) {
        const word = if (payload.ok.len == 1) payload.ok[0] else payload.err[0];
        return std.mem.eql(u8, descriptor.canonical.completion_params[1], word);
    }
    return true;
}

pub fn source_scalar_core_type(value: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, value, "bool") or
        std.mem.eql(u8, value, "u8") or
        std.mem.eql(u8, value, "u16") or
        std.mem.eql(u8, value, "u32") or
        std.mem.eql(u8, value, "i8") or
        std.mem.eql(u8, value, "i16") or
        std.mem.eql(u8, value, "i32")) return "i32";
    if (std.mem.eql(u8, value, "u64") or std.mem.eql(u8, value, "i64")) return "i64";
    if (std.mem.eql(u8, value, "f32")) return "f32";
    if (std.mem.eql(u8, value, "f64")) return "f64";
    return null;
}

fn all_i32(values: []const []const u8, expected_len: usize) bool {
    if (values.len != expected_len) return false;
    for (values) |value| {
        if (!std.mem.eql(u8, value, "i32")) return false;
    }
    return true;
}

fn contains_descriptor(descriptors: []const Descriptor, locator: []const u8, member: []const u8) bool {
    for (descriptors) |descriptor| {
        if (std.mem.eql(u8, descriptor.locator, locator) and std.mem.eql(u8, descriptor.member, member)) return true;
    }
    return false;
}

fn object_value(value: std.json.Value) ?std.json.ObjectMap {
    return switch (value) {
        .object => |object| object,
        else => null,
    };
}

fn array_value(value: ?std.json.Value) ?std.json.Array {
    const actual = value orelse return null;
    return switch (actual) {
        .array => |array| array,
        else => null,
    };
}

fn string_value(value: ?std.json.Value) ?[]const u8 {
    const actual = value orelse return null;
    return switch (actual) {
        .string => |text| text,
        else => null,
    };
}

fn unsigned_value(value: ?std.json.Value) ?u64 {
    const actual = value orelse return null;
    return switch (actual) {
        .integer => |number| if (number >= 0) @intCast(number) else null,
        else => null,
    };
}

fn parse_resource(value: ?std.json.Value) !?[]const u8 {
    const actual = value orelse return error.InvalidP3AsyncManifest;
    return switch (actual) {
        .null => null,
        .string => |text| text,
        else => error.InvalidP3AsyncManifest,
    };
}

test "registry resolves a pinned async descriptor" {
    const json =
        \\{"schema":1,"wit_sha256":"abc","descriptors":[
        \\  {"locator":"wasi:clocks@0.3.0","member":"monotonic-clock.wait-for","effect":"async","params":["u64"],"result":"nil","resource":null,"canonical":{"core_params":["i64"],"core_results":[],"completion":"task-return","async_import_module":"wasi:clocks/monotonic-clock@0.3.0","async_import_name":"[async-lower]wait-for"},"wit":{"package":"wasi:clocks@0.3.0","interface":"monotonic-clock","operation":"wait-for","world":"probe","parameter":"how-long"}}
        \\]}
    ;

    var registry = try Registry.load(std.testing.allocator, json);
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("wasi:clocks@0.3.0", "monotonic-clock.wait-for").?;
    try std.testing.expectEqualStrings("i64", descriptor.canonical.core_params[0]);
    try std.testing.expectEqual(@as(usize, 0), descriptor.canonical.core_results.len);
    try std.testing.expectEqualStrings("task-return", descriptor.canonical.completion);
}

test "checked-in registry resolves wait-until with its explicit ABI names" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("wasi:clocks@0.3.0", "monotonic-clock.wait-until").?;
    try std.testing.expectEqualStrings("[async-lower]wait-until", descriptor.canonical.async_import_name);
    try std.testing.expectEqualStrings("wait-until", descriptor.wit.operation);
    try std.testing.expectEqualStrings("when", descriptor.wit.parameter);
}

test "registry resolves the private future-owned resource shape" {
    const json =
        \\{"schema":1,"wit_sha256":"abc","descriptors":[
        \\  {"locator":"do:future-owned-canonical/source@0.1.0","member":"read","effect":"future-owned-resource","params":[],"result":"Ticket","resource":null,"canonical":{"core_params":[],"core_results":[],"completion_params":[],"completion":"task-return","async_import_module":"do:future-owned-canonical/source@0.1.0","async_import_name":"[async-lower]read","future_owned":{"resource":"ticket","payload_offset":12,"resource_offset":16,"presence_offset":20,"drop_import":"[resource-drop]ticket"}},"wit":{"package":"do:future-owned-canonical@0.1.0","interface":"source","operation":"read","world":"future-owned-canonical","parameter":""}}
        \\]}
    ;

    var registry = try Registry.load(std.testing.allocator, json);
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("do:future-owned-canonical/source@0.1.0", "read") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("future-owned-resource", descriptor.effect);
    try std.testing.expectEqualStrings("Ticket", descriptor.result);
    const shape = switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .future_owned_resource => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualStrings("ticket", shape.resource);
    try std.testing.expectEqual(@as(u32, 12), shape.payload_offset);
    try std.testing.expectEqual(@as(u32, 16), shape.resource_offset);
    try std.testing.expectEqual(@as(u32, 20), shape.presence_offset);
    try std.testing.expectEqualStrings("[resource-drop]ticket", shape.drop_import);

    var drifted = descriptor;
    var drifted_owned = descriptor.canonical.future_owned.?;
    drifted_owned.payload_offset = 16;
    var drifted_canonical = descriptor.canonical;
    drifted_canonical.future_owned = drifted_owned;
    drifted.canonical = drifted_canonical;
    try std.testing.expect(lowering_shape(drifted) == null);
}

test "checked-in registry admits the private future-owned resource shape" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("do:future-owned-canonical/source@0.1.0", "read") orelse return error.TestUnexpectedResult;
    const shape = switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .future_owned_resource => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualStrings("ticket", shape.resource);
    try std.testing.expectEqual(@as(u32, 12), shape.payload_offset);
    try std.testing.expectEqual(@as(u32, 16), shape.resource_offset);
    try std.testing.expectEqual(@as(u32, 20), shape.presence_offset);
}

test "registry rejects an invalid task-return core parameter" {
    const json =
        \\{"schema":1,"wit_sha256":"abc","descriptors":[
        \\  {"locator":"wasi:clocks@0.3.0","member":"monotonic-clock.wait-for","effect":"async","params":["u64"],"result":"nil","resource":null,"canonical":{"core_params":["i64"],"core_results":[],"completion":"task-return","completion_params":["v128"],"async_import_module":"wasi:clocks/monotonic-clock@0.3.0","async_import_name":"[async-lower]wait-for"},"wit":{"package":"wasi:clocks@0.3.0","interface":"monotonic-clock","operation":"wait-for","world":"probe","parameter":"how-long"}}
        \\]}
    ;

    try std.testing.expectError(error.InvalidP3AsyncManifest, Registry.load(std.testing.allocator, json));
}

test "registry rejects obsolete descriptor cancellation metadata" {
    const json =
        \\{"schema":1,"wit_sha256":"abc","descriptors":[
        \\  {"locator":"wasi:clocks@0.3.0","member":"monotonic-clock.wait-for","effect":"async","params":["u64"],"result":"nil","resource":null,"cancel":"not-supported","canonical":{"core_params":["i64"],"core_results":[],"completion":"task-return","async_import_module":"wasi:clocks/monotonic-clock@0.3.0","async_import_name":"[async-lower]wait-for"},"wit":{"package":"wasi:clocks@0.3.0","interface":"monotonic-clock","operation":"wait-for","world":"probe","parameter":"how-long"}}
        \\]}
    ;

    try std.testing.expectError(error.InvalidP3AsyncManifest, Registry.load(std.testing.allocator, json));
}

test "registry rejects obsolete operation token metadata" {
    const json =
        \\{"schema":1,"wit_sha256":"abc","descriptors":[
        \\  {"locator":"wasi:clocks@0.3.0","member":"monotonic-clock.wait-for","effect":"async","params":["u64"],"result":"nil","resource":null,"canonical":{"core_params":["i64"],"core_results":[],"completion":"task-return","operation_token":null,"async_import_module":"wasi:clocks/monotonic-clock@0.3.0","async_import_name":"[async-lower]wait-for"},"wit":{"package":"wasi:clocks@0.3.0","interface":"monotonic-clock","operation":"wait-for","world":"probe","parameter":"how-long"}}
        \\]}
    ;

    try std.testing.expectError(error.InvalidP3AsyncManifest, Registry.load(std.testing.allocator, json));
}

test "registry preserves explicit async Core import names" {
    const json =
        \\{"schema":1,"wit_sha256":"abc","descriptors":[
        \\  {"locator":"wasi:clocks@0.3.0","member":"monotonic-clock.wait-for","effect":"async","params":["u64"],"result":"nil","resource":null,"canonical":{"core_params":["i64"],"core_results":[],"completion":"task-return","async_import_module":"wasi:clocks/monotonic-clock@0.3.0","async_import_name":"[async-lower]wait-for"},"wit":{"package":"wasi:clocks@0.3.0","interface":"monotonic-clock","operation":"wait-for","world":"probe","parameter":"how-long"}}
        \\]}
    ;
    var registry = try Registry.load(std.testing.allocator, json);
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("wasi:clocks@0.3.0", "monotonic-clock.wait-for").?;
    try std.testing.expectEqualStrings("wasi:clocks/monotonic-clock@0.3.0", descriptor.canonical.async_import_module);
    try std.testing.expectEqualStrings("[async-lower]wait-for", descriptor.canonical.async_import_name);
}

test "registry preserves explicit WIT component names" {
    const json =
        \\{"schema":1,"wit_sha256":"abc","descriptors":[
        \\  {"locator":"wasi:clocks@0.3.0","member":"monotonic-clock.wait-for","effect":"async","params":["u64"],"result":"nil","resource":null,"canonical":{"core_params":["i64"],"core_results":[],"completion":"task-return","async_import_module":"wasi:clocks/monotonic-clock@0.3.0","async_import_name":"[async-lower]wait-for"},"wit":{"package":"wasi:clocks@0.3.0","interface":"monotonic-clock","operation":"wait-for","world":"probe","parameter":"how-long"}}
        \\]}
    ;
    var registry = try Registry.load(std.testing.allocator, json);
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("wasi:clocks@0.3.0", "monotonic-clock.wait-for").?;
    try std.testing.expectEqualStrings("wasi:clocks@0.3.0", descriptor.wit.package);
    try std.testing.expectEqualStrings("monotonic-clock", descriptor.wit.interface);
    try std.testing.expectEqualStrings("wait-for", descriptor.wit.operation);
    try std.testing.expectEqualStrings("probe", descriptor.wit.world);
    try std.testing.expectEqualStrings("how-long", descriptor.wit.parameter);
}

test "registry requires explicit WIT component names" {
    const json =
        \\{"schema":1,"wit_sha256":"abc","descriptors":[
        \\  {"locator":"wasi:clocks@0.3.0","member":"monotonic-clock.wait-for","effect":"async","params":["u64"],"result":"nil","resource":null,"canonical":{"core_params":["i64"],"core_results":[],"completion":"task-return","async_import_module":"wasi:clocks/monotonic-clock@0.3.0","async_import_name":"[async-lower]wait-for"}}
        \\]}
    ;
    try std.testing.expectError(error.InvalidP3AsyncManifest, Registry.load(std.testing.allocator, json));
}

test "registry rejects an unknown async effect" {
    const json =
        \\{"schema":1,"wit_sha256":"abc","descriptors":[
        \\  {"locator":"wasi:clocks@0.3.0","member":"monotonic-clock.wait-for","effect":"later","params":["u64"],"result":"nil","resource":null,"canonical":{"core_params":["i64"],"core_results":[],"completion":"task-return"}}
        \\]}
    ;

    try std.testing.expectError(error.InvalidP3AsyncManifest, Registry.load(std.testing.allocator, json));
}

test "registry requires the pinned canonical completion shape" {
    const json =
        \\{"schema":1,"wit_sha256":"abc","descriptors":[
        \\  {"locator":"wasi:clocks@0.3.0","member":"monotonic-clock.wait-for","effect":"async","params":["u64"],"result":"nil","resource":null}
        \\]}
    ;

    try std.testing.expectError(error.InvalidP3AsyncManifest, Registry.load(std.testing.allocator, json));
}

test "registry preserves a zero-parameter descriptor WIT hash" {
    const json =
        \\{"schema":1,"wit_sha256":"abc","descriptors":[
        \\  {"locator":"wasi:cli@0.3.0","member":"run.run","effect":"async","params":[],"result":"Result<nil, nil>","resource":null,"wit_sha256":"04b2de3bf344052c78080f3c5320442132b4e7c20b42633a92b8400b6d29ab0d","canonical":{"core_params":["i32"],"core_results":["i32"],"completion":"task-return","async_import_module":"wasi:cli/run@0.3.0","async_import_name":"[async-lower]run"},"wit":{"package":"wasi:cli@0.3.0","interface":"run","operation":"run","world":"probe","parameter":""}}
        \\]}
    ;
    var registry = try Registry.load(std.testing.allocator, json);
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("wasi:cli@0.3.0", "run.run").?;
    try std.testing.expectEqualStrings("04b2de3bf344052c78080f3c5320442132b4e7c20b42633a92b8400b6d29ab0d", descriptor.wit_sha256.?);
    try std.testing.expectEqual(@as(usize, 0), descriptor.params.len);
    try std.testing.expectEqualStrings("", descriptor.wit.parameter);
}

test "pinned HTTP WIT retains its exact async resource boundary" {
    try p3_http_wit_manifest.validate();
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/worlds.wit"), "send: async func(") != null);
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/worlds.wit"), ") -> result<response, error-code>;") != null);
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("p3_wit/wasi-http-0.3.0-rc-2025-09-16/types.wit"), "consume-body: static func(this: response") != null);
}

test "checked-in registry pins HTTP client send async resource metadata" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("wasi:http/client@0.3.0-rc-2025-09-16", "send") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("HttpRequest", descriptor.params[0]);
    try std.testing.expectEqualStrings("Result<HttpResponse,HttpError>", descriptor.result);
    try std.testing.expectEqualStrings("request", descriptor.resource.?);
    try std.testing.expectEqual(@as(usize, 2), descriptor.canonical.core_params.len);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.core_params[0]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.core_params[1]);
    try std.testing.expectEqual(@as(usize, 1), descriptor.canonical.core_results.len);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.core_results[0]);
    try std.testing.expectEqual(@as(usize, 8), descriptor.canonical.completion_params.len);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.completion_params[0]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.completion_params[1]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.completion_params[2]);
    try std.testing.expectEqualStrings("i64", descriptor.canonical.completion_params[3]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.completion_params[4]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.completion_params[5]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.completion_params[6]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.completion_params[7]);
    try std.testing.expectEqualStrings("wasi:http/client@0.3.0-rc-2025-09-16", descriptor.canonical.async_import_module);
    try std.testing.expectEqualStrings("[async-lower]send", descriptor.canonical.async_import_name);
    try std.testing.expectEqualStrings("wasi:http@0.3.0-rc-2025-09-16", descriptor.wit.package);
    try std.testing.expectEqualStrings("client", descriptor.wit.interface);
    try std.testing.expectEqualStrings("send", descriptor.wit.operation);
    try std.testing.expectEqualStrings("service", descriptor.wit.world);
    try std.testing.expectEqualStrings("request", descriptor.wit.parameter);
}

test "checked-in HTTP task-return preserves the pinned i64 payload word" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("wasi:http/client@0.3.0-rc-2025-09-16", "send") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 8), descriptor.canonical.completion_params.len);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.completion_params[0]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.completion_params[1]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.completion_params[2]);
    try std.testing.expectEqualStrings("i64", descriptor.canonical.completion_params[3]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.completion_params[4]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.completion_params[5]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.completion_params[6]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.completion_params[7]);
}

test "checked-in HTTP send exposes the proven payload variant metadata" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("wasi:http/client@0.3.0-rc-2025-09-16", "send") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 2), descriptor.canonical.error_variants.len);
    try std.testing.expectEqualStrings("internal-error", descriptor.canonical.error_variants[0].variant);
    try std.testing.expectEqual(@as(u32, 38), descriptor.canonical.error_variants[0].discriminant);
    try std.testing.expectEqualStrings("DNS-error", descriptor.canonical.error_variants[1].variant);
    try std.testing.expectEqual(@as(u32, 1), descriptor.canonical.error_variants[1].discriminant);
}

test "checked-in registry exposes the pinned HTTP response body stream ABI" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("wasi:http/types@0.3.0-rc-2025-09-16", "response.consume-body") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("http-stream-reader", descriptor.effect);
    try std.testing.expectEqualStrings("HttpResponse", descriptor.params[0]);
    try std.testing.expectEqualStrings("response", descriptor.resource.?);
    try std.testing.expectEqualStrings("tuple<stream<u8>,future<result<option<trailers>,error-code>>>", descriptor.result);
    try std.testing.expectEqualStrings("result-area", descriptor.canonical.completion);
    try std.testing.expectEqualStrings("[static]response.consume-body", descriptor.canonical.async_import_name);
    try std.testing.expectEqual(@as(usize, 3), descriptor.canonical.core_params.len);
    try std.testing.expectEqual(@as(usize, 0), descriptor.canonical.completion_params.len);
    const stream = descriptor.canonical.stream orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("[stream-new-1]response.consume-body", stream.new.import_name);
    try std.testing.expectEqualStrings("[stream-drop-readable-1]response.consume-body", stream.drop_readable.import_name);
    try std.testing.expectEqualStrings("[async-lower][stream-read-1]response.consume-body", stream.read.import_name);
    const input_future = descriptor.canonical.future_input orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("[future-new-0]response.consume-body", input_future.new.?.import_name);
    try std.testing.expectEqualStrings("[future-write-0]response.consume-body", input_future.write.?.import_name);
    try std.testing.expectEqualStrings("[future-cancel-read-0]response.consume-body", input_future.cancel_read.?.import_name);
    try std.testing.expectEqualStrings("[future-cancel-write-0]response.consume-body", input_future.cancel_write.?.import_name);
    try std.testing.expectEqualStrings("[future-drop-readable-0]response.consume-body", input_future.drop_readable.import_name);
    try std.testing.expectEqualStrings("[future-drop-writable-0]response.consume-body", input_future.drop_writable.?.import_name);
    const future = descriptor.canonical.future orelse return error.TestUnexpectedResult;
    try std.testing.expect(future.new == null);
    try std.testing.expectEqualStrings("[future-cancel-read-2]response.consume-body", future.cancel_read.?.import_name);
    try std.testing.expectEqualStrings("[future-cancel-write-2]response.consume-body", future.cancel_write.?.import_name);
    try std.testing.expectEqualStrings("[future-drop-readable-2]response.consume-body", future.drop_readable.import_name);
    try std.testing.expectEqualStrings("[future-drop-writable-2]response.consume-body", future.drop_writable.?.import_name);
    try std.testing.expectEqualStrings("[async-lower][future-read-2]response.consume-body", future.read.?.import_name);
    const shape = switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .http_stream_reader => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualStrings("[future-new-0]response.consume-body", shape.future_new.import_name);
    try std.testing.expectEqualStrings("[future-write-0]response.consume-body", shape.future_write.import_name);
    try std.testing.expectEqualStrings("[async-lower][future-read-2]response.consume-body", shape.future_read.import_name);
}

test "checked-in registry exposes the pinned HTTP request constructor ABI" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("wasi:http/types@0.3.0-rc-2025-09-16", "request.new") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("http-request-constructor", descriptor.effect);
    try std.testing.expectEqualStrings("tuple<request,future<result<_,error-code>>>", descriptor.result);
    try std.testing.expectEqualStrings("[static]request.new", descriptor.canonical.async_import_name);
    try std.testing.expectEqual(@as(usize, 7), descriptor.canonical.core_params.len);
    const input = descriptor.canonical.future_input orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("[future-new-1]request-new-payload", input.new.?.import_name);
    try std.testing.expectEqualStrings("[future-write-1]request-new-payload", input.write.?.import_name);
    try std.testing.expectEqualStrings("[future-drop-writable-1]request-new-payload", input.drop_writable.?.import_name);
    const output = descriptor.canonical.future orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("[future-drop-readable-2]request-new-payload", output.drop_readable.import_name);
    switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .http_request_constructor => |shape| {
            try std.testing.expectEqualStrings("[future-new-1]request-new-payload", shape.trailers_future.new.?.import_name);
            try std.testing.expectEqualStrings("[future-drop-readable-2]request-new-payload", shape.transmission_future.drop_readable.import_name);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "checked-in registry exposes the pinned HTTP trailers future read ABI" {
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("p3_async_registry.json"), "[async-lower][future-read-2]response.consume-body") != null);
}

test "checked-in registry exposes the pinned CLI source completion future read ABI" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("wasi:cli/stdin@0.3.0-rc-2025-09-16", "read-via-stream") orelse return error.TestUnexpectedResult;
    const future = descriptor.canonical.future orelse return error.TestUnexpectedResult;
    const read = future.read orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("[async-lower][future-read-1]read-via-stream", read.import_name);
    try std.testing.expectEqual(@as(usize, 2), read.core_params.len);
    try std.testing.expectEqualStrings("i32", read.core_params[0]);
    try std.testing.expectEqualStrings("i32", read.core_params[1]);
    try std.testing.expectEqual(@as(usize, 1), read.core_results.len);
    try std.testing.expectEqualStrings("i32", read.core_results[0]);
}

test "read-directory metadata is observable without becoming a lowering shape" {
    const method = StreamOperation{
        .import_name = "[async-lower][method]descriptor.read-directory",
        .core_params = &.{ "i32", "i32" },
        .core_results = &.{"i32"},
    };
    const stream = StreamCanonical{
        .element = "directory-entry",
        .new = .{ .import_name = "[stream-new-0]descriptor.read-directory", .core_params = &.{}, .core_results = &.{"i64"} },
        .cancel_read = .{ .import_name = "[stream-cancel-read-0]descriptor.read-directory", .core_params = &.{"i32"}, .core_results = &.{"i32"} },
        .cancel_write = .{ .import_name = "[stream-cancel-write-0]descriptor.read-directory", .core_params = &.{"i32"}, .core_results = &.{"i32"} },
        .drop_readable = .{ .import_name = "[stream-drop-readable-0]descriptor.read-directory", .core_params = &.{"i32"}, .core_results = &.{} },
        .drop_writable = .{ .import_name = "[stream-drop-writable-0]descriptor.read-directory", .core_params = &.{"i32"}, .core_results = &.{} },
        .read = .{ .import_name = "[async-lower][stream-read-0]descriptor.read-directory", .core_params = &.{ "i32", "i32", "i32" }, .core_results = &.{"i32"} },
        .write = .{ .import_name = "[async-lower][stream-write-0]descriptor.read-directory", .core_params = &.{ "i32", "i32", "i32" }, .core_results = &.{"i32"} },
    };
    const future = FutureCanonical{
        .new = .{ .import_name = "[future-new-1]descriptor.read-directory", .core_params = &.{}, .core_results = &.{"i64"} },
        .cancel_read = .{ .import_name = "[future-cancel-read-1]descriptor.read-directory", .core_params = &.{"i32"}, .core_results = &.{"i32"} },
        .cancel_write = .{ .import_name = "[future-cancel-write-1]descriptor.read-directory", .core_params = &.{"i32"}, .core_results = &.{"i32"} },
        .drop_readable = .{ .import_name = "[future-drop-readable-1]descriptor.read-directory", .core_params = &.{"i32"}, .core_results = &.{} },
        .drop_writable = .{ .import_name = "[future-drop-writable-1]descriptor.read-directory", .core_params = &.{"i32"}, .core_results = &.{} },
        .read = .{ .import_name = "[async-lower][future-read-1]descriptor.read-directory", .core_params = &.{ "i32", "i32" }, .core_results = &.{"i32"} },
        .write = .{ .import_name = "[async-lower][future-write-1]descriptor.read-directory", .core_params = &.{ "i32", "i32" }, .core_results = &.{"i32"} },
    };
    const descriptor = Descriptor{
        .locator = "wasi:filesystem/types@0.3.0-rc-2025-09-16",
        .member = "descriptor.read-directory",
        .effect = "stream-reader",
        .params = &.{},
        .result = "tuple<stream<directory-entry>,future<result<_,error-code>>>",
        .resource = null,
        .wit_sha256 = null,
        .canonical = .{
            .core_params = method.core_params,
            .core_results = method.core_results,
            .completion_params = &.{},
            .completion = "result-area",
            .result_payload = null,
            .async_import_module = "wasi:filesystem/types@0.3.0-rc-2025-09-16",
            .async_import_name = method.import_name,
            .stream = stream,
            .future = future,
        },
        .wit = .{
            .package = "wasi:filesystem@0.3.0-rc-2025-09-16",
            .interface = "types",
            .operation = "descriptor.read-directory",
            .world = "imports",
            .parameter = "",
        },
    };

    try std.testing.expect(lowering_shape(descriptor) == null);
    const shape = switch (unsupported_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .record_stream_reader => |value| value,
    };
    try std.testing.expectEqualStrings("directory-entry", shape.element);
    try std.testing.expectEqual(@as(usize, 0), shape.stream_index);
    try std.testing.expectEqual(@as(usize, 1), shape.future_index);
    try std.testing.expectEqualStrings("[async-lower][future-read-1]descriptor.read-directory", shape.future.read.?.import_name);
}

test "checked-in registry admits the pinned read-directory descriptor" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find(
        "wasi:filesystem/types@0.3.0-rc-2025-09-16",
        "descriptor.read-directory",
    ) orelse return error.TestUnexpectedResult;
    const shape = switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .record_stream_reader => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualStrings(p3_filesystem_wit_manifest.directory_types_sha256, descriptor.wit_sha256.?);
    try std.testing.expectEqualStrings("directory-entry", shape.element);
    try std.testing.expectEqual(@as(usize, 0), shape.stream_index);
    try std.testing.expectEqual(@as(usize, 1), shape.future_index);
    try std.testing.expectEqualStrings(
        "[async-lower][future-read-1][method]descriptor.read-directory",
        shape.future.read.?.import_name,
    );
}

test "checked-in registry admits the bounded list-owned resource stream" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find(
        "do:record-resource-list-stream-probe@0.1.0",
        "read-via-stream",
    ) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("record-resource-list-stream-reader", descriptor.effect);
    try std.testing.expect(lowering_shape(descriptor) != null);
}

test "C-min producer descriptor exposes the measured source and sink contract" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("do:g6-2-c-min-producer@0.1.0", "consume-via-stream") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("record-resource-list-stream-producer", descriptor.effect);
    try std.testing.expectEqualStrings("stream<list<resource-entry>>", descriptor.params[0]);
    try std.testing.expectEqualStrings("Result<nil,error-code>", descriptor.result);
    const producer = descriptor.canonical.producer orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("do:g6-2-c-min-producer/source@0.1.0", producer.source_module);
    try std.testing.expectEqualStrings("make-ticket", producer.source_import_name);
    try std.testing.expectEqualStrings("[resource-drop]ticket", producer.resource_drop_import);
    try std.testing.expectEqual(@as(u32, 1), producer.stream_capacity);
    try std.testing.expectEqualStrings("result-area", producer.terminal);
    try std.testing.expectEqualStrings(
        "8decd27aeca4a1f1863544860caec230a1fc50259336a893de79413c6f9ec3f7",
        descriptor.wit_sha256.?,
    );
    switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .record_resource_list_stream_producer => |shape| {
            try std.testing.expectEqual(@as(usize, 0), shape.stream_index);
            try std.testing.expectEqual(@as(u32, 64), shape.list_layout.result_pointer_offset);
            try std.testing.expectEqual(@as(u32, 68), shape.list_layout.result_length_offset);
            try std.testing.expectEqual(@as(u32, 4), shape.list_layout.element_stride);
            try std.testing.expectEqual(@as(u32, 0), shape.list_layout.ticket_offset);
            try std.testing.expectEqual(@as(u32, 3), shape.list_layout.max_items);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "C-min producer descriptor rejects hash, element, layout, ownership, locator, and queue drift" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const original = registry.find("do:g6-2-c-min-producer@0.1.0", "consume-via-stream") orelse return error.TestUnexpectedResult;

    var wrong_hash = original;
    wrong_hash.wit_sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
    try std.testing.expect(lowering_shape(wrong_hash) == null);

    var wrong_element = original;
    wrong_element.canonical.stream.?.element = "stream<resource-entry>";
    try std.testing.expect(lowering_shape(wrong_element) == null);

    var wrong_layout = original;
    wrong_layout.canonical.list_resource_layout.?.result_pointer_offset = 60;
    try std.testing.expect(lowering_shape(wrong_layout) == null);

    var borrowed_field = original.canonical.record_layout.?.source_fields[0];
    borrowed_field.ownership = .borrow;
    var borrowed_layout = original.canonical.record_layout.?;
    borrowed_layout.source_fields = &.{borrowed_field};
    var borrowed = original;
    borrowed.canonical.record_layout = borrowed_layout;
    try std.testing.expect(lowering_shape(borrowed) == null);

    var unknown_locator = original;
    unknown_locator.locator = "do:unknown-producer@0.1.0";
    try std.testing.expect(lowering_shape(unknown_locator) == null);

    var extra_queue = original;
    extra_queue.canonical.producer.?.stream_capacity = 2;
    try std.testing.expect(lowering_shape(extra_queue) == null);
}

test "dynamic C-min producer descriptor admits only its bounded runtime shape" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const original = registry.find("do:g6-2-c-min-dynamic-producer@0.1.0", "consume-via-stream") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("record-resource-list-stream-dynamic-producer", original.effect);
    try std.testing.expectEqualStrings("95f6d2d616e80248a8710e10199fa3674aa80b76247f25c2e71d3d87ea4afe76", original.wit_sha256.?);
    const producer = original.canonical.producer orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("u32", producer.runtime_count_param.?);
    try std.testing.expectEqual(@as(u32, 3), producer.runtime_max.?);
    switch (lowering_shape(original) orelse return error.TestUnexpectedResult) {
        .record_resource_list_stream_dynamic_producer => |shape| {
            try std.testing.expectEqual(@as(u32, 3), shape.list_layout.max_items);
            try std.testing.expectEqualStrings("dynamic-list-producer", original.wit.world);
        },
        else => return error.TestUnexpectedResult,
    }

    var wrong_hash = original;
    wrong_hash.wit_sha256 = "0000000000000000000000000000000000000000000000000000000000000000";
    try std.testing.expect(lowering_shape(wrong_hash) == null);

    var wrong_world = original;
    wrong_world.wit.world = "c-min-producer";
    try std.testing.expect(lowering_shape(wrong_world) == null);

    var wrong_capacity = original;
    wrong_capacity.canonical.list_resource_layout.?.max_items = 4;
    try std.testing.expect(lowering_shape(wrong_capacity) == null);

    var wrong_pointer = original;
    wrong_pointer.canonical.list_resource_layout.?.result_pointer_offset = 60;
    try std.testing.expect(lowering_shape(wrong_pointer) == null);

    var wrong_count_type = original;
    wrong_count_type.canonical.producer.?.runtime_count_param = "u64";
    try std.testing.expect(lowering_shape(wrong_count_type) == null);

    var missing_drop = original;
    missing_drop.canonical.producer.?.resource_drop_import = "";
    try std.testing.expect(lowering_shape(missing_drop) == null);

    var unbounded = original;
    unbounded.canonical.producer.?.runtime_max = null;
    try std.testing.expect(lowering_shape(unbounded) == null);
}

test "record layout metadata exposes pinned directory-entry offsets" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find(
        "wasi:filesystem/types@0.3.0-rc-2025-09-16",
        "descriptor.read-directory",
    ) orelse return error.TestUnexpectedResult;
    const shape = switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .record_stream_reader => |value| value,
        else => return error.TestUnexpectedResult,
    };
    const layout = shape.record_layout orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("directory-entry", layout.name);
    try std.testing.expectEqual(@as(?u32, 0), layout.field_offset("type"));
    try std.testing.expectEqual(@as(?u32, 4), layout.field_offset("name-ptr"));
    try std.testing.expectEqual(@as(?u32, 8), layout.field_offset("name-len"));
}

test "record stream lowering rejects a missing record layout" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor_index = for (registry.descriptors, 0..) |descriptor, index| {
        if (std.mem.eql(u8, descriptor.member, "descriptor.read-directory")) break index;
    } else return error.TestUnexpectedResult;
    if (registry.descriptors[descriptor_index].canonical.record_layout) |layout| {
        free_record_layout(std.testing.allocator, layout);
    }
    registry.descriptors[descriptor_index].canonical.record_layout = null;
    try std.testing.expect(lowering_shape(registry.descriptors[descriptor_index]) == null);
}

test "record layout parser rejects unsafe field metadata" {
    const invalid_layouts = [_][]const u8{
        "{\"name\":\"entry\",\"fields\":[{\"name\":\"a\",\"core_type\":\"i32\",\"offset\":2}]}",
        "{\"name\":\"entry\",\"fields\":[{\"name\":\"a\",\"core_type\":\"i32\",\"offset\":0},{\"name\":\"b\",\"core_type\":\"i32\",\"offset\":0}]}",
        "{\"name\":\"entry\",\"fields\":[{\"name\":\"a\",\"core_type\":\"text\",\"offset\":0}]}",
    };
    for (invalid_layouts) |json| {
        var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
        defer parsed.deinit();
        try std.testing.expectError(error.InvalidP3AsyncManifest, parse_record_layout(std.testing.allocator, parsed.value));
    }
}

test "checked-in registry pins private async resource Result ABI" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("do:resource-probe/http@0.1.0", "send") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("HttpRequest", descriptor.params[0]);
    try std.testing.expectEqualStrings("Result<HttpResponse,HttpError>", descriptor.result);
    try std.testing.expectEqualStrings("request", descriptor.resource.?);
    try std.testing.expectEqual(@as(usize, 2), descriptor.canonical.core_params.len);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.core_params[0]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.core_params[1]);
    try std.testing.expectEqual(@as(usize, 2), descriptor.canonical.core_results.len);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.core_results[0]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.core_results[1]);
    try std.testing.expectEqualStrings("do:resource-probe/http@0.1.0", descriptor.canonical.async_import_module);
    try std.testing.expectEqualStrings("[async-lower]send", descriptor.canonical.async_import_name);
    try std.testing.expectEqualStrings("async-resource-probe", descriptor.wit.world);
}

test "checked-in registry pins the generic async runtime host descriptor" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("do:generic-async-runtime-probe/host@0.1.0", "work") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("async", descriptor.effect);
    try std.testing.expectEqual(@as(usize, 0), descriptor.params.len);
    try std.testing.expectEqualStrings("nil", descriptor.result);
    try std.testing.expect(descriptor.resource == null);
    try std.testing.expectEqualStrings("32d239e3d6e9323577422ee1e54287a27cb7607dd8843537af7d69975b1e9803", descriptor.wit_sha256.?);
    try std.testing.expectEqual(@as(usize, 0), descriptor.canonical.core_params.len);
    try std.testing.expectEqual(@as(usize, 0), descriptor.canonical.core_results.len);
    try std.testing.expectEqual(@as(usize, 0), descriptor.canonical.completion_params.len);
    try std.testing.expectEqualStrings("task-return", descriptor.canonical.completion);
    try std.testing.expectEqualStrings("do:generic-async-runtime-probe/host@0.1.0", descriptor.canonical.async_import_module);
    try std.testing.expectEqualStrings("[async-lower]work", descriptor.canonical.async_import_name);
    try std.testing.expectEqualStrings("do:generic-async-runtime-probe@0.1.0", descriptor.wit.package);
    try std.testing.expectEqualStrings("host", descriptor.wit.interface);
    try std.testing.expectEqualStrings("work", descriptor.wit.operation);
    try std.testing.expectEqualStrings("probe", descriptor.wit.world);
    try std.testing.expectEqualStrings("", descriptor.wit.parameter);
    try std.testing.expect(lowering_shape(descriptor) == null);
}

test "descriptor lowering shapes separate scalar unit, private Result, and HTTP" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const clocks = registry.find("wasi:clocks@0.3.0", "monotonic-clock.wait-for") orelse return error.TestUnexpectedResult;
    switch (lowering_shape(clocks) orelse return error.TestUnexpectedResult) {
        .scalar_unit => |shape| {
            try std.testing.expectEqualStrings("u64", shape.source_param);
            try std.testing.expectEqualStrings("i64", shape.core_param);
        },
        else => return error.TestUnexpectedResult,
    }

    const resource = registry.find("do:resource-probe/http@0.1.0", "send") orelse return error.TestUnexpectedResult;
    switch (lowering_shape(resource) orelse return error.TestUnexpectedResult) {
        .resource_result_2word => |shape| {
            try std.testing.expectEqualStrings("HttpRequest", shape.source_param);
            try std.testing.expectEqualStrings("request", shape.resource);
        },
        else => return error.TestUnexpectedResult,
    }

    const cli = registry.find("wasi:cli@0.3.0", "run.run") orelse return error.TestUnexpectedResult;
    switch (lowering_shape(cli) orelse return error.TestUnexpectedResult) {
        .unit_result_tag => {},
        else => return error.TestUnexpectedResult,
    }

    const http = registry.find("wasi:http/client@0.3.0-rc-2025-09-16", "send") orelse return error.TestUnexpectedResult;
    switch (lowering_shape(http) orelse return error.TestUnexpectedResult) {
        .http_resource_result => |shape| {
            try std.testing.expectEqualStrings("HttpRequest", shape.source_param);
            try std.testing.expectEqualStrings("request", shape.request_resource);
            try std.testing.expectEqualStrings("response", shape.response_resource);
            try std.testing.expectEqual(@as(usize, 8), shape.completion_words);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "HTTP descriptor exposes its canonical resource Result completion shape" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("wasi:http/client@0.3.0-rc-2025-09-16", "send") orelse return error.TestUnexpectedResult;
    const shape = lowering_shape(descriptor) orelse return error.TestUnexpectedResult;
    const http = switch (shape) {
        .http_resource_result => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualStrings("wasi:http/client@0.3.0-rc-2025-09-16", descriptor.canonical.async_import_module);
    try std.testing.expectEqualStrings("[async-lower]send", descriptor.canonical.async_import_name);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.core_params[0]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.core_params[1]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.core_results[0]);
    try std.testing.expectEqualStrings("task-return", descriptor.canonical.completion);
    try std.testing.expectEqual(@as(usize, 8), http.completion_words);
}

test "checked-in registry exposes a scalar Result payload layout" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("do:result-probe@0.1.0", "run") orelse return error.TestUnexpectedResult;
    const shape = lowering_shape(descriptor) orelse return error.TestUnexpectedResult;
    switch (shape) {
        .scalar_result => |result| {
            try std.testing.expectEqualStrings("Result<i32,i32>", result.source_result);
            try std.testing.expectEqualStrings("i32", result.tag);
            try std.testing.expectEqual(@as(usize, 1), result.ok.len);
            try std.testing.expectEqualStrings("i32", result.ok[0]);
            try std.testing.expectEqual(@as(usize, 1), result.err.len);
            try std.testing.expectEqualStrings("i32", result.err[0]);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "descriptor-driven scalar Result layout maps u8 source values onto i32" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    var descriptor = registry.find("do:result-probe@0.1.0", "run") orelse return error.TestUnexpectedResult;
    descriptor.params = &.{"u8"};
    descriptor.result = "Result<u8,u8>";
    switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .scalar_result => |result| {
            try std.testing.expectEqualStrings("Result<u8,u8>", result.source_result);
            try std.testing.expectEqual(@as(usize, 1), result.ok.len);
            try std.testing.expectEqual(@as(usize, 1), result.err.len);
            try std.testing.expectEqualStrings("i32", result.ok[0]);
            try std.testing.expectEqualStrings("i32", result.err[0]);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "registry exposes the pinned stdout stream writer ABI" {
    const json =
        \\{"schema":1,"wit_sha256":"abc","descriptors":[
        \\  {"locator":"wasi:cli/stdout@0.3.0-rc-2025-09-16","member":"write-via-stream","effect":"stream-writer","params":["stream<u8>"],"result":"Result<nil,error-code>","resource":null,"canonical":{"core_params":["i32","i32"],"core_results":["i32"],"completion_params":["i32","i32"],"completion":"task-return","async_import_module":"wasi:cli/stdout@0.3.0-rc-2025-09-16","async_import_name":"[async-lower]write-via-stream","stream":{"element":"u8","new":{"import_name":"[stream-new-0]write-via-stream","core_params":[],"core_results":["i64"]},"cancel_read":{"import_name":"[stream-cancel-read-0]write-via-stream","core_params":["i32"],"core_results":["i32"]},"cancel_write":{"import_name":"[stream-cancel-write-0]write-via-stream","core_params":["i32"],"core_results":["i32"]},"drop_readable":{"import_name":"[stream-drop-readable-0]write-via-stream","core_params":["i32"],"core_results":[]},"drop_writable":{"import_name":"[stream-drop-writable-0]write-via-stream","core_params":["i32"],"core_results":[]},"read":{"import_name":"[async-lower][stream-read-0]write-via-stream","core_params":["i32","i32","i32"],"core_results":["i32"]},"write":{"import_name":"[async-lower][stream-write-0]write-via-stream","core_params":["i32","i32","i32"],"core_results":["i32"]}}},"wit":{"package":"wasi:cli@0.3.0-rc-2025-09-16","interface":"stdout","operation":"write-via-stream","world":"service","parameter":"data"}}
        \\]}
    ;
    var registry = try Registry.load(std.testing.allocator, json);
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream") orelse return error.TestUnexpectedResult;
    const shape = lowering_shape(descriptor) orelse return error.TestUnexpectedResult;
    switch (shape) {
        .stream_writer => |writer| {
            try std.testing.expectEqualStrings("u8", writer.element);
            try std.testing.expectEqualStrings("[stream-new-0]write-via-stream", writer.new.import_name);
            try std.testing.expectEqualStrings("[async-lower][stream-write-0]write-via-stream", writer.write.import_name);
            try std.testing.expectEqual(@as(usize, 3), writer.write.core_params.len);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "checked-in registry exposes the pinned stdout stream writer descriptor" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const descriptor = registry.find("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 2), descriptor.canonical.completion_params.len);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.completion_params[0]);
    try std.testing.expectEqualStrings("i32", descriptor.canonical.completion_params[1]);
    try std.testing.expect(lowering_shape(descriptor) != null);
}

test "scalar Result lowering rejects multiword and non-scalar source arms" {
    const multiword = Descriptor{
        .locator = "test:result@0.1.0",
        .member = "run",
        .effect = "async",
        .params = &.{"i32"},
        .result = "Result<i32,i32>",
        .resource = null,
        .wit_sha256 = null,
        .canonical = .{
            .core_params = &.{"i32"},
            .core_results = &.{"i32"},
            .completion_params = &.{ "i32", "i32", "i32", "i32" },
            .completion = "task-return",
            .result_payload = .{ .tag = "i32", .ok = &.{ "i32", "i32" }, .err = &.{"i32"} },
            .async_import_module = "test:result/run@0.1.0",
            .async_import_name = "[async-lower]run",
        },
        .wit = .{ .package = "test:result@0.1.0", .interface = "result", .operation = "run", .world = "probe", .parameter = "value" },
    };
    try std.testing.expect(lowering_shape(multiword) == null);

    var non_scalar = multiword;
    non_scalar.result = "Result<text,i32>";
    non_scalar.canonical.result_payload = .{ .tag = "i32", .ok = &.{"i32"}, .err = &.{"i32"} };
    non_scalar.canonical.completion_params = &.{ "i32", "i32", "i32" };
    try std.testing.expect(lowering_shape(non_scalar) == null);
}

test "scalar Result lowering rejects a source-to-core scalar mismatch" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    var descriptor = registry.find("do:result-probe@0.1.0", "run") orelse return error.TestUnexpectedResult;
    descriptor.params = &.{"u8"};
    descriptor.result = "Result<u8,u8>";
    descriptor.canonical.core_params = &.{ "i64", "i32" };
    try std.testing.expect(lowering_shape(descriptor) == null);
    try std.testing.expectEqualStrings("i32", source_scalar_core_type("u8").?);
    try std.testing.expectEqualStrings("i32", source_scalar_core_type("bool").?);
    try std.testing.expectEqualStrings("i64", source_scalar_core_type("u64").?);
}

test "generic record metadata parses scalar and text source fields" {
    const json =
        \\{"name":"probe-entry","byte_size":16,"fields":[
        \\  {"name":"id","core_type":"i32","offset":0},
        \\  {"name":"label-ptr","core_type":"i32","offset":4},
        \\  {"name":"label-len","core_type":"i32","offset":8}
        \\],"source_fields":[
        \\  {"name":"id","source_type":"u32","storage":["id"]},
        \\  {"name":"label","source_type":"string","storage":["label-ptr","label-len"]}
        \\]}
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    const layout = try parse_record_layout(std.testing.allocator, parsed.value);
    defer free_record_layout(std.testing.allocator, layout);

    try std.testing.expectEqual(@as(u32, 16), layout.byte_size);
    try std.testing.expectEqual(@as(usize, 2), layout.source_fields.len);
    try std.testing.expectEqualStrings("u32", layout.source_fields[0].source_type);
    try std.testing.expectEqualStrings("id", layout.source_fields[0].storage[0]);
    try std.testing.expectEqualStrings("string", layout.source_fields[1].source_type);
    try std.testing.expectEqual(@as(usize, 2), layout.source_fields[1].storage.len);
    try std.testing.expectEqualStrings("label-ptr", layout.source_fields[1].storage[0]);
    try std.testing.expectEqualStrings("label-len", layout.source_fields[1].storage[1]);
}

test "generic record metadata rejects invalid source encodings" {
    const invalid_layouts = [_][]const u8{
        "{\"name\":\"entry\",\"byte_size\":8,\"fields\":[{\"name\":\"ptr\",\"core_type\":\"i32\",\"offset\":0}],\"source_fields\":[{\"name\":\"label\",\"source_type\":\"string\",\"storage\":[\"ptr\"]}]}",
        "{\"name\":\"entry\",\"byte_size\":8,\"fields\":[{\"name\":\"id\",\"core_type\":\"i32\",\"offset\":0}],\"source_fields\":[{\"name\":\"value\",\"source_type\":\"u32\",\"storage\":[\"id\"]},{\"name\":\"value\",\"source_type\":\"u32\",\"storage\":[\"id\"]}]}",
        "{\"name\":\"entry\",\"byte_size\":8,\"fields\":[{\"name\":\"items\",\"core_type\":\"i32\",\"offset\":0}],\"source_fields\":[{\"name\":\"items\",\"source_type\":\"list<u8>\",\"storage\":[\"items\"]}]}",
    };
    for (invalid_layouts) |json| {
        var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
        defer parsed.deinit();
        try std.testing.expectError(error.InvalidP3AsyncManifest, parse_record_layout(std.testing.allocator, parsed.value));
    }
}

test "generic record resource metadata parses an owned resource field" {
    const json = "{\"name\":\"resource-entry\",\"byte_size\":8,\"fields\":[{\"name\":\"id\",\"core_type\":\"i32\",\"offset\":0},{\"name\":\"ticket\",\"core_type\":\"i32\",\"offset\":4}],\"source_fields\":[{\"name\":\"id\",\"source_type\":\"u32\",\"storage\":[\"id\"]},{\"name\":\"ticket\",\"source_type\":\"ticket\",\"storage\":[\"ticket\"],\"ownership\":\"own\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"}]}";
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    const layout = try parse_record_layout(std.testing.allocator, parsed.value);
    defer free_record_layout(std.testing.allocator, layout);

    try std.testing.expectEqual(@as(usize, 2), layout.source_fields.len);
    const ticket = layout.source_fields[1];
    try std.testing.expectEqual(RecordOwnership.own, ticket.ownership);
    try std.testing.expectEqualStrings("ticket", ticket.resource.?);
    try std.testing.expectEqualStrings("[resource-drop]ticket", ticket.drop_import.?);
}

test "generic record resource metadata parses multiple owned resource fields" {
    const json = "{\"name\":\"resource-entry\",\"byte_size\":12,\"fields\":[{\"name\":\"id\",\"core_type\":\"i32\",\"offset\":0},{\"name\":\"left\",\"core_type\":\"i32\",\"offset\":4},{\"name\":\"right\",\"core_type\":\"i32\",\"offset\":8}],\"source_fields\":[{\"name\":\"id\",\"source_type\":\"u32\",\"storage\":[\"id\"]},{\"name\":\"left\",\"source_type\":\"ticket\",\"storage\":[\"left\"],\"ownership\":\"own\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"},{\"name\":\"right\",\"source_type\":\"ticket\",\"storage\":[\"right\"],\"ownership\":\"own\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"}]}";
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    const layout = try parse_record_layout(std.testing.allocator, parsed.value);
    defer free_record_layout(std.testing.allocator, layout);

    try std.testing.expectEqual(@as(usize, 3), layout.source_fields.len);
    try std.testing.expectEqual(RecordOwnership.own, layout.source_fields[1].ownership);
    try std.testing.expectEqual(RecordOwnership.own, layout.source_fields[2].ownership);
    try std.testing.expectEqualStrings("ticket", layout.source_fields[1].resource.?);
    try std.testing.expectEqualStrings("ticket", layout.source_fields[2].resource.?);
}

test "generic record resource metadata rejects unsafe ownership shapes" {
    const invalid_layouts = [_][]const u8{
        "{\"name\":\"entry\",\"byte_size\":8,\"fields\":[{\"name\":\"ticket\",\"core_type\":\"i32\",\"offset\":4}],\"source_fields\":[{\"name\":\"ticket\",\"source_type\":\"ticket\",\"storage\":[\"ticket\"],\"ownership\":\"borrow\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"}]} ",
        "{\"name\":\"entry\",\"byte_size\":8,\"fields\":[{\"name\":\"ticket\",\"core_type\":\"i32\",\"offset\":4}],\"source_fields\":[{\"name\":\"ticket\",\"source_type\":\"ticket\",\"storage\":[\"ticket\"],\"ownership\":\"own\",\"resource\":\"ticket\"}]} ",
        "{\"name\":\"entry\",\"byte_size\":8,\"fields\":[{\"name\":\"ticket\",\"core_type\":\"i64\",\"offset\":4}],\"source_fields\":[{\"name\":\"ticket\",\"source_type\":\"ticket\",\"storage\":[\"ticket\"],\"ownership\":\"own\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"}]} ",
        "{\"name\":\"entry\",\"byte_size\":12,\"fields\":[{\"name\":\"ticket\",\"core_type\":\"i32\",\"offset\":4}],\"source_fields\":[{\"name\":\"ticket\",\"source_type\":\"ticket\",\"storage\":[\"ticket\"],\"ownership\":\"own\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]wrong\"}]} ",
    };
    for (invalid_layouts) |json| {
        var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
        defer parsed.deinit();
        try std.testing.expectError(error.InvalidP3AsyncManifest, parse_record_layout(std.testing.allocator, parsed.value));
    }
}

test "generic record resource metadata parses one nested owned resource field" {
    const json = "{\"name\":\"resource-entry\",\"byte_size\":4,\"fields\":[{\"name\":\"ticket\",\"core_type\":\"i32\",\"offset\":0}],\"source_fields\":[{\"name\":\"inner\",\"source_type\":\"inner-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"ticket\",\"source_type\":\"ticket\",\"storage\":[\"ticket\"],\"ownership\":\"own\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"}]}]}";
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    const layout = try parse_record_layout(std.testing.allocator, parsed.value);
    defer free_record_layout(std.testing.allocator, layout);
    try std.testing.expectEqual(@as(usize, 1), layout.source_fields.len);
    try std.testing.expectEqualStrings("inner-entry", layout.source_fields[0].source_type);
    try std.testing.expectEqual(@as(usize, 1), layout.source_fields[0].nested_fields.len);
    try std.testing.expectEqual(RecordOwnership.own, layout.source_fields[0].nested_fields[0].ownership);
    try std.testing.expectEqualStrings("ticket", layout.source_fields[0].nested_fields[0].resource.?);
}

test "generic record resource metadata parses two nested owned resource levels" {
    const json = "{\"name\":\"resource-entry\",\"byte_size\":4,\"fields\":[{\"name\":\"ticket\",\"core_type\":\"i32\",\"offset\":0}],\"source_fields\":[{\"name\":\"inner\",\"source_type\":\"inner-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"deep\",\"source_type\":\"deep-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"ticket\",\"source_type\":\"ticket\",\"storage\":[\"ticket\"],\"ownership\":\"own\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"}]}]}]}";
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    const layout = try parse_record_layout(std.testing.allocator, parsed.value);
    defer free_record_layout(std.testing.allocator, layout);
    try std.testing.expectEqual(@as(usize, 1), layout.source_fields.len);
    try std.testing.expectEqual(@as(usize, 1), layout.source_fields[0].nested_fields.len);
    try std.testing.expectEqual(@as(usize, 1), layout.source_fields[0].nested_fields[0].nested_fields.len);
    try std.testing.expectEqualStrings("ticket", layout.source_fields[0].nested_fields[0].nested_fields[0].resource.?);
}

test "generic record resource metadata parses three nested owned resource levels" {
    const json = "{\"name\":\"resource-entry\",\"byte_size\":4,\"fields\":[{\"name\":\"ticket\",\"core_type\":\"i32\",\"offset\":0}],\"source_fields\":[{\"name\":\"inner\",\"source_type\":\"inner-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"deep\",\"source_type\":\"deep-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"deeper\",\"source_type\":\"deeper-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"ticket\",\"source_type\":\"ticket\",\"storage\":[\"ticket\"],\"ownership\":\"own\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"}]}]}]}]}";
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    const layout = try parse_record_layout(std.testing.allocator, parsed.value);
    defer free_record_layout(std.testing.allocator, layout);
    try std.testing.expectEqual(@as(usize, 1), layout.source_fields.len);
    const inner = layout.source_fields[0];
    try std.testing.expectEqual(@as(usize, 1), inner.nested_fields.len);
    const deep = inner.nested_fields[0];
    try std.testing.expectEqual(@as(usize, 1), deep.nested_fields.len);
    const deeper = deep.nested_fields[0];
    try std.testing.expectEqual(@as(usize, 1), deeper.nested_fields.len);
    try std.testing.expectEqualStrings("ticket", deeper.nested_fields[0].resource.?);
}

test "generic record resource metadata parses four nested owned resource levels" {
    const json = "{\"name\":\"resource-entry\",\"byte_size\":4,\"fields\":[{\"name\":\"ticket\",\"core_type\":\"i32\",\"offset\":0}],\"source_fields\":[{\"name\":\"inner\",\"source_type\":\"inner-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"deep\",\"source_type\":\"deep-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"deeper\",\"source_type\":\"deeper-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"deepest\",\"source_type\":\"deepest-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"ticket\",\"source_type\":\"ticket\",\"storage\":[\"ticket\"],\"ownership\":\"own\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"}]}]}]}]}]}";
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    const layout = try parse_record_layout(std.testing.allocator, parsed.value);
    defer free_record_layout(std.testing.allocator, layout);
    try std.testing.expectEqual(@as(usize, 1), layout.source_fields.len);
    const inner = layout.source_fields[0];
    const deep = inner.nested_fields[0];
    const deeper = deep.nested_fields[0];
    const deepest = deeper.nested_fields[0];
    try std.testing.expectEqual(@as(usize, 1), deepest.nested_fields.len);
    try std.testing.expectEqualStrings("ticket", deepest.nested_fields[0].resource.?);
}

test "generic record resource metadata parses five nested owned resource levels" {
    const json = "{\"name\":\"resource-entry\",\"byte_size\":4,\"fields\":[{\"name\":\"ticket\",\"core_type\":\"i32\",\"offset\":0}],\"source_fields\":[{\"name\":\"inner\",\"source_type\":\"inner-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"deep\",\"source_type\":\"deep-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"deeper\",\"source_type\":\"deeper-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"deepest\",\"source_type\":\"deepest-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"ultra\",\"source_type\":\"ultra-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"ticket\",\"source_type\":\"ticket\",\"storage\":[\"ticket\"],\"ownership\":\"own\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"}]}]}]}]}]}]}";
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    const layout = try parse_record_layout(std.testing.allocator, parsed.value);
    defer free_record_layout(std.testing.allocator, layout);
    const inner = layout.source_fields[0];
    const deep = inner.nested_fields[0];
    const deeper = deep.nested_fields[0];
    const deepest = deeper.nested_fields[0];
    const ultra = deepest.nested_fields[0];
    try std.testing.expectEqualStrings("ultra-entry", ultra.source_type);
    try std.testing.expectEqual(RecordOwnership.own, ultra.nested_fields[0].ownership);
    try std.testing.expectEqualStrings("ticket", ultra.nested_fields[0].resource.?);
}

test "generic record resource metadata parses multiple nested owned resource paths" {
    const json = "{\"name\":\"resource-entry\",\"byte_size\":8,\"fields\":[{\"name\":\"left-ticket\",\"core_type\":\"i32\",\"offset\":0},{\"name\":\"right-ticket\",\"core_type\":\"i32\",\"offset\":4}],\"source_fields\":[{\"name\":\"left\",\"source_type\":\"left-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"ticket\",\"source_type\":\"ticket\",\"storage\":[\"left-ticket\"],\"ownership\":\"own\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"}]},{\"name\":\"right\",\"source_type\":\"right-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"ticket\",\"source_type\":\"ticket\",\"storage\":[\"right-ticket\"],\"ownership\":\"own\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"}]}]}";
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    const layout = try parse_record_layout(std.testing.allocator, parsed.value);
    defer free_record_layout(std.testing.allocator, layout);
    try std.testing.expectEqual(@as(usize, 2), layout.source_fields.len);
    try std.testing.expectEqualStrings("left-entry", layout.source_fields[0].source_type);
    try std.testing.expectEqualStrings("right-entry", layout.source_fields[1].source_type);
    try std.testing.expectEqualStrings("left-ticket", layout.source_fields[0].nested_fields[0].storage[0]);
    try std.testing.expectEqualStrings("right-ticket", layout.source_fields[1].nested_fields[0].storage[0]);
}

test "generic record resource metadata rejects unsafe nested ownership shapes" {
    const invalid_layouts = [_][]const u8{
        "{\"name\":\"entry\",\"byte_size\":4,\"fields\":[{\"name\":\"ticket\",\"core_type\":\"i32\",\"offset\":0}],\"source_fields\":[{\"name\":\"inner\",\"source_type\":\"inner-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"ticket\",\"source_type\":\"ticket\",\"storage\":[\"ticket\"],\"ownership\":\"borrow\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"}]}]}",
        "{\"name\":\"entry\",\"byte_size\":8,\"fields\":[{\"name\":\"left\",\"core_type\":\"i32\",\"offset\":0},{\"name\":\"right\",\"core_type\":\"i32\",\"offset\":4}],\"source_fields\":[{\"name\":\"inner\",\"source_type\":\"inner-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"left\",\"source_type\":\"ticket\",\"storage\":[\"left\"],\"ownership\":\"own\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"},{\"name\":\"right\",\"source_type\":\"ticket\",\"storage\":[\"right\"],\"ownership\":\"own\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"}]}]}",
        "{\"name\":\"entry\",\"byte_size\":8,\"fields\":[{\"name\":\"ticket\",\"core_type\":\"i32\",\"offset\":0},{\"name\":\"id\",\"core_type\":\"i32\",\"offset\":4}],\"source_fields\":[{\"name\":\"inner\",\"source_type\":\"inner-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"ticket\",\"source_type\":\"ticket\",\"storage\":[\"ticket\"],\"ownership\":\"own\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"}]},{\"name\":\"id\",\"source_type\":\"u32\",\"storage\":[\"id\"]}]}",
        "{\"name\":\"entry\",\"byte_size\":8,\"fields\":[{\"name\":\"left-ticket\",\"core_type\":\"i32\",\"offset\":0},{\"name\":\"right-ticket\",\"core_type\":\"i32\",\"offset\":4}],\"source_fields\":[{\"name\":\"left\",\"source_type\":\"left-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"ticket\",\"source_type\":\"ticket\",\"storage\":[\"left-ticket\"],\"ownership\":\"own\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"}]},{\"name\":\"right\",\"source_type\":\"right-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"left\",\"source_type\":\"left-entry\",\"storage\":[],\"nested_fields\":[]}]}]}",
    };
    for (invalid_layouts) |json| {
        var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
        defer parsed.deinit();
        try std.testing.expectError(error.InvalidP3AsyncManifest, parse_record_layout(std.testing.allocator, parsed.value));
    }
}

test "generic record resource metadata parses six nested owned resource levels" {
    const json = "{\"name\":\"resource-entry\",\"byte_size\":4,\"fields\":[{\"name\":\"ticket\",\"core_type\":\"i32\",\"offset\":0}],\"source_fields\":[{\"name\":\"inner\",\"source_type\":\"inner-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"deep\",\"source_type\":\"deep-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"deeper\",\"source_type\":\"deeper-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"deepest\",\"source_type\":\"deepest-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"ultra\",\"source_type\":\"ultra-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"hyper\",\"source_type\":\"hyper-entry\",\"storage\":[],\"nested_fields\":[{\"name\":\"ticket\",\"source_type\":\"ticket\",\"storage\":[\"ticket\"],\"ownership\":\"own\",\"resource\":\"ticket\",\"drop_import\":\"[resource-drop]ticket\"}]}]}]}]}]}]}]}";
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    const layout = try parse_record_layout(std.testing.allocator, parsed.value);
    defer free_record_layout(std.testing.allocator, layout);
    const ultra = layout.source_fields[0].nested_fields[0].nested_fields[0].nested_fields[0].nested_fields[0];
    try std.testing.expectEqualStrings("ultra-entry", ultra.source_type);
    try std.testing.expectEqualStrings("hyper-entry", ultra.nested_fields[0].source_type);
    try std.testing.expectEqual(RecordOwnership.own, ultra.nested_fields[0].nested_fields[0].ownership);
}

test "generic record resource metadata rejects a seventh nested owned resource level" {
    const json =
        \\{
        \\  "name": "entry",
        \\  "byte_size": 4,
        \\  "fields": [{"name":"ticket","core_type":"i32","offset":0}],
        \\  "source_fields": [{
        \\    "name": "inner",
        \\    "source_type": "inner-entry",
        \\    "storage": [],
        \\    "nested_fields": [{
        \\      "name": "deep",
        \\      "source_type": "deep-entry",
        \\      "storage": [],
        \\      "nested_fields": [{
        \\        "name": "deeper",
        \\        "source_type": "deeper-entry",
        \\        "storage": [],
        \\        "nested_fields": [{
        \\          "name": "deepest",
        \\          "source_type": "deepest-entry",
        \\          "storage": [],
        \\          "nested_fields": [{
        \\            "name": "ultra",
        \\            "source_type": "ultra-entry",
        \\            "storage": [],
        \\            "nested_fields": [{
        \\              "name": "hyper",
        \\              "source_type": "hyper-entry",
        \\              "storage": [],
        \\              "nested_fields": [{
        \\                "name": "super",
        \\                "source_type": "super-entry",
        \\                "storage": [],
        \\                "nested_fields": [{
        \\                  "name": "ticket",
        \\                  "source_type": "ticket",
        \\                  "storage": ["ticket"],
        \\                  "ownership": "own",
        \\                  "resource": "ticket",
        \\                  "drop_import": "[resource-drop]ticket"
        \\                }]
        \\              }]
        \\            }]
        \\          }]
        \\        }]
        \\      }]
        \\    }]
        \\  }]
        \\}
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expectError(error.InvalidP3AsyncManifest, parse_record_layout(std.testing.allocator, parsed.value));
}

test "checked-in registry admits a generic record stream probe" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:record-stream-probe@0.1.0", "read-via-stream") orelse return error.TestUnexpectedResult;
    const shape = switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .record_stream_reader => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualStrings("probe-entry", shape.element);
    try std.testing.expectEqualStrings("probe-entry", shape.record_layout.?.name);
    try std.testing.expectEqual(@as(?u32, 0), shape.record_layout.?.field_offset("id"));
    try std.testing.expectEqual(@as(?u32, 4), shape.record_layout.?.field_offset("label-ptr"));
}

test "checked-in registry admits the owned resource record stream probe" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:record-resource-stream-probe@0.1.0", "read-via-stream") orelse return error.TestUnexpectedResult;
    const shape = switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .record_stream_reader => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualStrings("resource-entry", shape.element);
    const ticket = shape.record_layout.?.source_fields[1];
    try std.testing.expectEqual(RecordOwnership.own, ticket.ownership);
    try std.testing.expectEqualStrings("ticket", ticket.resource.?);
    try std.testing.expectEqualStrings("[resource-drop]ticket", ticket.drop_import.?);
}

test "checked-in registry admits the multiple owned resource record stream probe" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:record-resource-stream-multi@0.1.0", "read-via-stream") orelse return error.TestUnexpectedResult;
    const shape = switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .record_stream_reader => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualStrings("resource-entry", shape.element);
    try std.testing.expectEqual(@as(usize, 3), shape.record_layout.?.source_fields.len);
    try std.testing.expectEqual(RecordOwnership.own, shape.record_layout.?.source_fields[1].ownership);
    try std.testing.expectEqual(RecordOwnership.own, shape.record_layout.?.source_fields[2].ownership);
    try std.testing.expectEqualStrings("ticket", shape.record_layout.?.source_fields[1].resource.?);
    try std.testing.expectEqualStrings("ticket", shape.record_layout.?.source_fields[2].resource.?);
}

test "checked-in registry admits the nested owned resource record stream probe" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:record-resource-stream-nested@0.1.0", "read-via-stream") orelse return error.TestUnexpectedResult;
    const shape = switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .record_stream_reader => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualStrings("resource-entry", shape.element);
    const nested = shape.record_layout.?.source_fields[0];
    try std.testing.expectEqualStrings("inner-entry", nested.source_type);
    try std.testing.expectEqual(@as(usize, 1), nested.nested_fields.len);
    try std.testing.expectEqual(RecordOwnership.own, nested.nested_fields[0].ownership);
    try std.testing.expectEqualStrings("ticket", nested.nested_fields[0].resource.?);
}

test "checked-in registry admits the two-level nested owned resource record stream probe" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:record-resource-stream-nested-two-level@0.1.0", "read-via-stream") orelse return error.TestUnexpectedResult;
    const shape = switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .record_stream_reader => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualStrings("resource-entry", shape.element);
    const inner = shape.record_layout.?.source_fields[0];
    try std.testing.expectEqualStrings("inner-entry", inner.source_type);
    try std.testing.expectEqual(@as(usize, 1), inner.nested_fields.len);
    const deep = inner.nested_fields[0];
    try std.testing.expectEqualStrings("deep-entry", deep.source_type);
    try std.testing.expectEqual(@as(usize, 1), deep.nested_fields.len);
    try std.testing.expectEqual(RecordOwnership.own, deep.nested_fields[0].ownership);
    try std.testing.expectEqualStrings("ticket", deep.nested_fields[0].resource.?);
}

test "checked-in registry admits the three-level nested owned resource record stream probe" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:record-resource-stream-nested-three-level@0.1.0", "read-via-stream") orelse return error.TestUnexpectedResult;
    const shape = switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .record_stream_reader => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualStrings("resource-entry", shape.element);
    const inner = shape.record_layout.?.source_fields[0];
    try std.testing.expectEqualStrings("inner-entry", inner.source_type);
    const deep = inner.nested_fields[0];
    try std.testing.expectEqualStrings("deep-entry", deep.source_type);
    const deeper = deep.nested_fields[0];
    try std.testing.expectEqualStrings("deeper-entry", deeper.source_type);
    try std.testing.expectEqual(RecordOwnership.own, deeper.nested_fields[0].ownership);
    try std.testing.expectEqualStrings("ticket", deeper.nested_fields[0].resource.?);
}

test "checked-in registry admits the four-level nested owned resource record stream probe" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:record-resource-stream-nested-four-level@0.1.0", "read-via-stream") orelse return error.TestUnexpectedResult;
    const shape = switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .record_stream_reader => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualStrings("resource-entry", shape.element);
    const inner = shape.record_layout.?.source_fields[0];
    const deep = inner.nested_fields[0];
    const deeper = deep.nested_fields[0];
    const deepest = deeper.nested_fields[0];
    try std.testing.expectEqualStrings("deepest-entry", deepest.source_type);
    try std.testing.expectEqual(RecordOwnership.own, deepest.nested_fields[0].ownership);
    try std.testing.expectEqualStrings("ticket", deepest.nested_fields[0].resource.?);
}

test "checked-in registry admits the five-level nested owned resource record stream probe" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:record-resource-stream-nested-five-level@0.1.0", "read-via-stream") orelse return error.TestUnexpectedResult;
    const shape = switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .record_stream_reader => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualStrings("resource-entry", shape.element);
    const inner = shape.record_layout.?.source_fields[0];
    const deep = inner.nested_fields[0];
    const deeper = deep.nested_fields[0];
    const deepest = deeper.nested_fields[0];
    const ultra = deepest.nested_fields[0];
    try std.testing.expectEqualStrings("ultra-entry", ultra.source_type);
    try std.testing.expectEqual(RecordOwnership.own, ultra.nested_fields[0].ownership);
    try std.testing.expectEqualStrings("ticket", ultra.nested_fields[0].resource.?);
}

test "checked-in registry admits the six-level nested owned resource record stream probe" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:record-resource-stream-nested-six-level@0.1.0", "read-via-stream") orelse return error.TestUnexpectedResult;
    const shape = switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .record_stream_reader => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualStrings("resource-entry", shape.element);
    const inner = shape.record_layout.?.source_fields[0];
    const deep = inner.nested_fields[0];
    const deeper = deep.nested_fields[0];
    const deepest = deeper.nested_fields[0];
    const ultra = deepest.nested_fields[0];
    const hyper = ultra.nested_fields[0];
    try std.testing.expectEqualStrings("hyper-entry", hyper.source_type);
    try std.testing.expectEqual(RecordOwnership.own, hyper.nested_fields[0].ownership);
    try std.testing.expectEqualStrings("ticket", hyper.nested_fields[0].resource.?);
}

test "checked-in registry admits multiple nested owned resource paths" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:record-resource-stream-multiple-nested@0.1.0", "read-via-stream") orelse return error.TestUnexpectedResult;
    const shape = switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .record_stream_reader => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualStrings("resource-entry", shape.element);
    try std.testing.expectEqual(@as(usize, 2), shape.record_layout.?.source_fields.len);
    const left = shape.record_layout.?.source_fields[0];
    const right = shape.record_layout.?.source_fields[1];
    try std.testing.expectEqualStrings("left-entry", left.source_type);
    try std.testing.expectEqualStrings("right-entry", right.source_type);
    try std.testing.expectEqual(RecordOwnership.own, left.nested_fields[0].ownership);
    try std.testing.expectEqual(RecordOwnership.own, right.nested_fields[0].ownership);
    try std.testing.expectEqualStrings("left-ticket", left.nested_fields[0].storage[0]);
    try std.testing.expectEqualStrings("right-ticket", right.nested_fields[0].storage[0]);
}

test "registry parses exact HTTP payload variant descriptors" {
    const json =
        \\{"schema":1,"wit_sha256":"abc","descriptors":[
        \\  {"locator":"wasi:http/client@0.3.0-rc-2025-09-16","member":"send","effect":"async","params":["HttpRequest"],"result":"Result<HttpResponse,HttpError>","resource":"request","canonical":{"core_params":["i32","i32"],"core_results":["i32"],"completion_params":["i32","i32","i32","i64","i32","i32","i32","i32"],"completion":"task-return","error_variants":[
        \\    {"variant":"internal-error","discriminant":38,"byte_size":32,"fields":[{"name":"payload","kind":"optional_string","core_words":["i32","i64","i32"],"offset":16}]},
        \\    {"variant":"DNS-error","discriminant":1,"byte_size":32,"fields":[{"name":"rcode","kind":"optional_string","core_words":["i32","i64","i32"],"offset":16},{"name":"info-code","kind":"optional_u16","core_words":["i32","i32"],"offset":28}]}
        \\  ],"async_import_module":"wasi:http/client@0.3.0-rc-2025-09-16","async_import_name":"[async-lower]send"},"wit":{"package":"wasi:http@0.3.0-rc-2025-09-16","interface":"client","operation":"send","world":"service","parameter":"request"}}
        \\]}
    ;

    var registry = try Registry.load(std.testing.allocator, json);
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("wasi:http/client@0.3.0-rc-2025-09-16", "send").?;
    try std.testing.expectEqual(@as(usize, 2), descriptor.canonical.error_variants.len);
    const internal = descriptor.canonical.error_variants[0];
    try std.testing.expectEqualStrings("internal-error", internal.variant);
    try std.testing.expectEqual(@as(u32, 38), internal.discriminant);
    try std.testing.expectEqual(@as(u32, 32), internal.byte_size);
    try std.testing.expectEqual(@as(usize, 1), internal.fields.len);
    try std.testing.expectEqual(ErrorVariantFieldKind.optional_string, internal.fields[0].kind);
    try std.testing.expectEqual(@as(u32, 16), internal.fields[0].offset);
    try std.testing.expectEqual(@as(usize, 3), internal.fields[0].core_words.len);

    const dns = descriptor.canonical.error_variants[1];
    try std.testing.expectEqualStrings("DNS-error", dns.variant);
    try std.testing.expectEqual(@as(u32, 1), dns.discriminant);
    try std.testing.expectEqual(@as(usize, 2), dns.fields.len);
    try std.testing.expectEqualStrings("rcode", dns.fields[0].name);
    try std.testing.expectEqualStrings("info-code", dns.fields[1].name);
    try std.testing.expectEqual(ErrorVariantFieldKind.optional_u16, dns.fields[1].kind);
    try std.testing.expectEqual(@as(u32, 28), dns.fields[1].offset);
}

test "registry rejects malformed HTTP payload variant layout" {
    const json =
        \\{"schema":1,"wit_sha256":"abc","descriptors":[
        \\  {"locator":"wasi:http/client@0.3.0-rc-2025-09-16","member":"send","effect":"async","params":["HttpRequest"],"result":"Result<HttpResponse,HttpError>","resource":"request","canonical":{"core_params":["i32","i32"],"core_results":["i32"],"completion_params":["i32","i32","i32","i64","i32","i32","i32","i32"],"completion":"task-return","error_variants":[{"variant":"internal-error","discriminant":38,"byte_size":32,"fields":[{"name":"payload","kind":"optional_string","core_words":["i32","i64","i32"],"offset":15}]}],"async_import_module":"wasi:http/client@0.3.0-rc-2025-09-16","async_import_name":"[async-lower]send"},"wit":{"package":"wasi:http@0.3.0-rc-2025-09-16","interface":"client","operation":"send","world":"service","parameter":"request"}}
        \\]}
    ;

    try std.testing.expectError(error.InvalidP3AsyncManifest, Registry.load(std.testing.allocator, json));
}

test "checked-in registry admits the measured variant resource stream descriptor" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:variant-resource-stream-canonical@0.1.0", "read-via-stream") orelse return error.TestUnexpectedResult;
    const shape = switch (lowering_shape(descriptor) orelse return error.TestUnexpectedResult) {
        .variant_resource_stream_reader => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualStrings("event", shape.element);
    try std.testing.expectEqual(@as(u32, 0), shape.event.tag_offset);
    try std.testing.expectEqual(@as(u32, 4), shape.event.payload_offset);
    try std.testing.expectEqual(@as(u32, 8), shape.event.byte_size);
    try std.testing.expectEqual(@as(u32, 4), shape.event.alignment);
    try std.testing.expectEqual(@as(usize, 3), shape.event.variants.len);
    try std.testing.expectEqualStrings("ticket", shape.event.variants[0].name);
    try std.testing.expectEqual(@as(u32, 0), shape.event.variants[0].tag);
    try std.testing.expectEqualStrings("own<ticket>", shape.event.variants[0].payload.?);
    try std.testing.expectEqualStrings("idle", shape.event.variants[1].name);
    try std.testing.expectEqual(@as(u32, 1), shape.event.variants[1].tag);
    try std.testing.expect(shape.event.variants[1].payload == null);
    try std.testing.expectEqualStrings("failed", shape.event.variants[2].name);
    try std.testing.expectEqual(@as(u32, 2), shape.event.variants[2].tag);
    try std.testing.expectEqualStrings("error-code", shape.event.variants[2].payload.?);
    try std.testing.expectEqualStrings("[async-lower][stream-read-0]read-via-stream", shape.stream_read.import_name);
    try std.testing.expectEqualStrings("[stream-drop-readable-0]read-via-stream", shape.stream_drop_readable.import_name);
    try std.testing.expectEqualStrings("[async-lower][future-read-1]read-via-stream", shape.future_read.import_name);
    try std.testing.expectEqualStrings("[future-drop-readable-1]read-via-stream", shape.future_drop_readable.import_name);
    try std.testing.expectEqualStrings("[resource-drop]ticket", shape.ticket_drop_import);
}

test "variant resource stream lowering rejects a drifted event tag" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:variant-resource-stream-canonical@0.1.0", "read-via-stream") orelse return error.TestUnexpectedResult;
    var event = descriptor.canonical.event_layout.?;
    var variants: [3]VariantEventBranch = .{ event.variants[0], event.variants[1], event.variants[2] };
    variants[0].tag = 7;
    event.variants = &variants;
    var canonical = descriptor.canonical;
    canonical.event_layout = event;
    var drifted = descriptor;
    drifted.canonical = canonical;
    try std.testing.expect(lowering_shape(drifted) == null);
}

test "variant resource stream lowering rejects a drifted payload offset" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:variant-resource-stream-canonical@0.1.0", "read-via-stream") orelse return error.TestUnexpectedResult;
    var event = descriptor.canonical.event_layout.?;
    event.payload_offset = 8;
    var canonical = descriptor.canonical;
    canonical.event_layout = event;
    var drifted = descriptor;
    drifted.canonical = canonical;
    try std.testing.expect(lowering_shape(drifted) == null);
}

test "variant resource stream lowering rejects a missing event branch" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:variant-resource-stream-canonical@0.1.0", "read-via-stream") orelse return error.TestUnexpectedResult;
    var event = descriptor.canonical.event_layout.?;
    var variants: [2]VariantEventBranch = .{ event.variants[0], event.variants[1] };
    event.variants = &variants;
    var canonical = descriptor.canonical;
    canonical.event_layout = event;
    var drifted = descriptor;
    drifted.canonical = canonical;
    try std.testing.expect(lowering_shape(drifted) == null);
}

test "variant resource stream lowering rejects duplicate event tags" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:variant-resource-stream-canonical@0.1.0", "read-via-stream") orelse return error.TestUnexpectedResult;
    var event = descriptor.canonical.event_layout.?;
    var variants: [3]VariantEventBranch = .{ event.variants[0], event.variants[1], event.variants[2] };
    variants[1].tag = variants[0].tag;
    event.variants = &variants;
    var canonical = descriptor.canonical;
    canonical.event_layout = event;
    var drifted = descriptor;
    drifted.canonical = canonical;
    try std.testing.expect(lowering_shape(drifted) == null);
}

test "variant resource stream lowering rejects a drifted stream drop import" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:variant-resource-stream-canonical@0.1.0", "read-via-stream") orelse return error.TestUnexpectedResult;
    var stream = descriptor.canonical.variant_stream.?;
    var drop_readable = stream.drop_readable;
    drop_readable.import_name = "[wrong]stream-drop";
    stream.drop_readable = drop_readable;
    var canonical = descriptor.canonical;
    canonical.variant_stream = stream;
    var drifted = descriptor;
    drifted.canonical = canonical;
    try std.testing.expect(lowering_shape(drifted) == null);
}

test "variant resource stream lowering rejects a drifted WIT result shape" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("p3_async_registry.json"));
    defer registry.deinit(std.testing.allocator);
    const descriptor = registry.find("do:variant-resource-stream-canonical@0.1.0", "read-via-stream") orelse return error.TestUnexpectedResult;
    var drifted = descriptor;
    drifted.result = "tuple<stream<u8>,future<result<_,error-code>>>";
    try std.testing.expect(lowering_shape(drifted) == null);
}
