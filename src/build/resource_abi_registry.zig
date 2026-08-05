const std = @import("std");

pub const Ownership = enum {
    none,
    own,
    borrow,
};

pub const Param = struct {
    type_name: []const u8,
    ownership: Ownership,
};

pub const Result = struct {
    type_name: []const u8,
    ownership: Ownership,
};

pub const Descriptor = struct {
    locator: []const u8,
    member: []const u8,
    resource: []const u8,
    resource_path: []const u8,
    result_resource: ?[]const u8 = null,
    result_resource_path: ?[]const u8 = null,
    result_error_resource: ?[]const u8 = null,
    result_error_resource_path: ?[]const u8 = null,
    params: []const Param,
    result: Result,
    resource_drop: bool,
};

pub const Registry = struct {
    descriptors: []const Descriptor,

    pub fn load(allocator: std.mem.Allocator, json: []const u8) !Registry {
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, json, .{}) catch return error.InvalidResourceAbiRegistry;
        defer parsed.deinit();

        const root = object_value(parsed.value) orelse return error.InvalidResourceAbiRegistry;
        if (unsigned_value(root.get("schema")) != 1) return error.InvalidResourceAbiRegistry;
        const values = array_value(root.get("descriptors")) orelse return error.InvalidResourceAbiRegistry;

        var descriptors = try std.ArrayList(Descriptor).initCapacity(allocator, values.items.len);
        errdefer {
            for (descriptors.items) |descriptor| free_descriptor(allocator, descriptor);
            descriptors.deinit(allocator);
        }
        for (values.items) |value| {
            const descriptor = try parse_descriptor(allocator, value);
            errdefer free_descriptor(allocator, descriptor);
            if (contains_descriptor(descriptors.items, descriptor.locator, descriptor.member)) return error.InvalidResourceAbiRegistry;
            try descriptors.append(allocator, descriptor);
        }
        return .{ .descriptors = try descriptors.toOwnedSlice(allocator) };
    }

    pub fn deinit(self: *Registry, allocator: std.mem.Allocator) void {
        for (self.descriptors) |descriptor| free_descriptor(allocator, descriptor);
        allocator.free(self.descriptors);
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
    const object = object_value(value) orelse return error.InvalidResourceAbiRegistry;
    const locator = try duplicate_required(allocator, object.get("locator"));
    errdefer allocator.free(locator);
    const member = try duplicate_required(allocator, object.get("member"));
    errdefer allocator.free(member);
    const resource = try duplicate_required(allocator, object.get("resource"));
    errdefer allocator.free(resource);
    const resource_path = try duplicate_required(allocator, object.get("resource_path"));
    errdefer allocator.free(resource_path);
    if (locator.len == 0 or member.len == 0 or resource.len == 0 or resource_path.len == 0) return error.InvalidResourceAbiRegistry;
    const result_resource = try duplicate_optional(allocator, object.get("result_resource"));
    errdefer if (result_resource) |name| allocator.free(name);
    const result_resource_path = try duplicate_optional(allocator, object.get("result_resource_path"));
    errdefer if (result_resource_path) |path| allocator.free(path);
    if ((result_resource == null) != (result_resource_path == null)) return error.InvalidResourceAbiRegistry;
    if (result_resource) |name| {
        if (name.len == 0 or result_resource_path.?.len == 0) return error.InvalidResourceAbiRegistry;
    }
    const result_error_resource = try duplicate_optional(allocator, object.get("result_error_resource"));
    errdefer if (result_error_resource) |name| allocator.free(name);
    const result_error_resource_path = try duplicate_optional(allocator, object.get("result_error_resource_path"));
    errdefer if (result_error_resource_path) |path| allocator.free(path);
    if ((result_error_resource == null) != (result_error_resource_path == null)) return error.InvalidResourceAbiRegistry;
    if (result_error_resource) |name| {
        if (name.len == 0 or result_error_resource_path.?.len == 0) return error.InvalidResourceAbiRegistry;
    }
    const params = try parse_params(allocator, array_value(object.get("params")) orelse return error.InvalidResourceAbiRegistry, resource);
    errdefer free_params(allocator, params);
    const result = try parse_result(allocator, object.get("result"), result_resource orelse resource, result_error_resource);
    errdefer allocator.free(result.type_name);
    if ((result_resource != null or result_error_resource != null) and result.ownership != .own) return error.InvalidResourceAbiRegistry;
    const resource_drop = bool_value(object.get("resource_drop")) orelse return error.InvalidResourceAbiRegistry;
    if (resource_drop and (params.len != 1 or params[0].ownership != .own or !std.mem.eql(u8, params[0].type_name, resource) or result.ownership != .none or !std.mem.eql(u8, result.type_name, "nil"))) {
        return error.InvalidResourceAbiRegistry;
    }
    return .{
        .locator = locator,
        .member = member,
        .resource = resource,
        .resource_path = resource_path,
        .result_resource = result_resource,
        .result_resource_path = result_resource_path,
        .result_error_resource = result_error_resource,
        .result_error_resource_path = result_error_resource_path,
        .params = params,
        .result = result,
        .resource_drop = resource_drop,
    };
}

fn parse_params(allocator: std.mem.Allocator, values: std.json.Array, resource: []const u8) ![]const Param {
    var params = try std.ArrayList(Param).initCapacity(allocator, values.items.len);
    errdefer {
        for (params.items) |param| allocator.free(param.type_name);
        params.deinit(allocator);
    }
    for (values.items) |value| {
        const object = object_value(value) orelse return error.InvalidResourceAbiRegistry;
        const type_name = try duplicate_required(allocator, object.get("type"));
        errdefer allocator.free(type_name);
        const ownership = try parse_ownership(object.get("ownership"));
        if ((ownership == .own or ownership == .borrow) and !std.mem.eql(u8, type_name, resource)) return error.InvalidResourceAbiRegistry;
        try params.append(allocator, .{ .type_name = type_name, .ownership = ownership });
    }
    return params.toOwnedSlice(allocator);
}

fn parse_result(allocator: std.mem.Allocator, value: ?std.json.Value, resource: []const u8, error_resource: ?[]const u8) !Result {
    const object = object_value(value orelse return error.InvalidResourceAbiRegistry) orelse return error.InvalidResourceAbiRegistry;
    const type_name = try duplicate_required(allocator, object.get("type"));
    errdefer allocator.free(type_name);
    const ownership = try parse_ownership(object.get("ownership"));
    if (ownership == .borrow) return error.InvalidResourceAbiRegistry;
    if (ownership == .own and !owned_result_type_matches_resources(type_name, resource, error_resource orelse "error-code")) return error.InvalidResourceAbiRegistry;
    return .{ .type_name = type_name, .ownership = ownership };
}

fn owned_result_type_matches_resource(type_name: []const u8, resource: []const u8) bool {
    if (std.mem.eql(u8, type_name, resource)) return true;
    if (owned_result_type_matches_resources(type_name, resource, "error-code")) return true;
    const prefix = "list<tuple<";
    const suffix = ",string>>";
    return type_name.len == prefix.len + resource.len + suffix.len and
        std.mem.eql(u8, type_name[0..prefix.len], prefix) and
        std.mem.eql(u8, type_name[prefix.len .. prefix.len + resource.len], resource) and
        std.mem.eql(u8, type_name[prefix.len + resource.len ..], suffix);
}

fn owned_result_type_matches_resources(type_name: []const u8, result_resource: []const u8, error_resource: []const u8) bool {
    if (std.mem.eql(u8, type_name, result_resource)) return true;
    const prefix = "result<";
    const separator = ",";
    const suffix = ">";
    const expected_len = prefix.len + result_resource.len + separator.len + error_resource.len + suffix.len;
    const result_matches = type_name.len == expected_len and
        std.mem.eql(u8, type_name[0..prefix.len], prefix) and
        std.mem.eql(u8, type_name[prefix.len .. prefix.len + result_resource.len], result_resource) and
        std.mem.eql(u8, type_name[prefix.len + result_resource.len .. prefix.len + result_resource.len + separator.len], separator) and
        std.mem.eql(u8, type_name[prefix.len + result_resource.len + separator.len .. prefix.len + result_resource.len + separator.len + error_resource.len], error_resource) and
        std.mem.eql(u8, type_name[expected_len - suffix.len ..], suffix);
    if (result_matches) return true;
    if (!std.mem.eql(u8, error_resource, "error-code")) return false;
    const list_prefix = "list<tuple<";
    const list_suffix = ",string>>";
    return type_name.len == list_prefix.len + result_resource.len + list_suffix.len and
        std.mem.eql(u8, type_name[0..list_prefix.len], list_prefix) and
        std.mem.eql(u8, type_name[list_prefix.len .. list_prefix.len + result_resource.len], result_resource) and
        std.mem.eql(u8, type_name[list_prefix.len + result_resource.len ..], list_suffix);
}

fn parse_ownership(value: ?std.json.Value) !Ownership {
    const text = string_value(value) orelse return error.InvalidResourceAbiRegistry;
    if (std.mem.eql(u8, text, "none")) return .none;
    if (std.mem.eql(u8, text, "own")) return .own;
    if (std.mem.eql(u8, text, "borrow")) return .borrow;
    return error.InvalidResourceAbiRegistry;
}

fn duplicate_required(allocator: std.mem.Allocator, value: ?std.json.Value) ![]const u8 {
    return allocator.dupe(u8, string_value(value) orelse return error.InvalidResourceAbiRegistry);
}

fn duplicate_optional(allocator: std.mem.Allocator, value: ?std.json.Value) !?[]const u8 {
    const actual = value orelse return null;
    const copied: []const u8 = try allocator.dupe(u8, string_value(actual) orelse return error.InvalidResourceAbiRegistry);
    return copied;
}

fn free_params(allocator: std.mem.Allocator, params: []const Param) void {
    for (params) |param| allocator.free(param.type_name);
    allocator.free(params);
}

fn free_descriptor(allocator: std.mem.Allocator, descriptor: Descriptor) void {
    allocator.free(descriptor.locator);
    allocator.free(descriptor.member);
    allocator.free(descriptor.resource);
    allocator.free(descriptor.resource_path);
    if (descriptor.result_resource) |name| allocator.free(name);
    if (descriptor.result_resource_path) |path| allocator.free(path);
    if (descriptor.result_error_resource) |name| allocator.free(name);
    if (descriptor.result_error_resource_path) |path| allocator.free(path);
    free_params(allocator, descriptor.params);
    allocator.free(descriptor.result.type_name);
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

fn bool_value(value: ?std.json.Value) ?bool {
    const actual = value orelse return null;
    return switch (actual) {
        .bool => |flag| flag,
        else => null,
    };
}

const fixture_json =
    \\{"schema":1,"descriptors":[
    \\  {"locator":"do:resource-probe/ledger@0.1.0","member":"create","resource":"ticket","resource_path":"do:resource-probe/ledger/ticket","params":[{"type":"u32","ownership":"none"}],"result":{"type":"ticket","ownership":"own"},"resource_drop":false},
    \\  {"locator":"do:resource-probe/ledger@0.1.0","member":"borrow-value","resource":"ticket","resource_path":"do:resource-probe/ledger/ticket","params":[{"type":"ticket","ownership":"borrow"}],"result":{"type":"u32","ownership":"none"},"resource_drop":false},
    \\  {"locator":"do:resource-probe/ledger@0.1.0","member":"consume","resource":"ticket","resource_path":"do:resource-probe/ledger/ticket","params":[{"type":"ticket","ownership":"own"}],"result":{"type":"u32","ownership":"none"},"resource_drop":false},
    \\  {"locator":"do:resource-probe/ledger@0.1.0","member":"drop","resource":"ticket","resource_path":"do:resource-probe/ledger/ticket","params":[{"type":"ticket","ownership":"own"}],"result":{"type":"nil","ownership":"none"},"resource_drop":true}
    \\]}
;

test "resource descriptor preserves ownership qualifiers" {
    var registry = try Registry.load(std.testing.allocator, fixture_json);
    defer registry.deinit(std.testing.allocator);

    const borrow = registry.find("do:resource-probe/ledger@0.1.0", "borrow-value").?;
    try std.testing.expectEqual(Ownership.borrow, borrow.params[0].ownership);
    const consume = registry.find("do:resource-probe/ledger@0.1.0", "consume").?;
    try std.testing.expectEqual(Ownership.own, consume.params[0].ownership);
}

test "filesystem preopen descriptors preserve ownership qualifiers" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("resource_abi_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const preopens = registry.find("wasi:filesystem/preopens@0.3.0", "get-directories") orelse return error.TestUnexpectedResult;
    const open_at = registry.find("wasi:filesystem/types@0.3.0", "descriptor.open-at") orelse return error.TestUnexpectedResult;
    const sync = registry.find("wasi:filesystem/types@0.3.0", "descriptor.sync") orelse return error.TestUnexpectedResult;
    const drop = registry.find("wasi:filesystem/types@0.3.0", "descriptor.drop") orelse return error.TestUnexpectedResult;

    try std.testing.expectEqual(Ownership.own, preopens.result.ownership);
    try std.testing.expectEqualStrings("list<tuple<descriptor,string>>", preopens.result.type_name);
    try std.testing.expectEqual(Ownership.borrow, open_at.params[0].ownership);
    try std.testing.expectEqual(Ownership.own, open_at.result.ownership);
    try std.testing.expectEqual(Ownership.borrow, sync.params[0].ownership);
    try std.testing.expect(drop.resource_drop);
}

test "resource descriptor permits an owned Result resource distinct from its input resource" {
    const json =
        \\{"schema":1,"descriptors":[
        \\  {"locator":"wasi:http/client@0.3.0-rc-2025-09-16","member":"send","resource":"request","resource_path":"wasi:http/types/request","result_resource":"response","result_resource_path":"wasi:http/types/response","params":[{"type":"request","ownership":"own"}],"result":{"type":"result<response,error-code>","ownership":"own"},"resource_drop":false}
        \\]}
    ;
    var registry = try Registry.load(std.testing.allocator, json);
    defer registry.deinit(std.testing.allocator);

    const send = registry.find("wasi:http/client@0.3.0-rc-2025-09-16", "send") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("request", send.resource);
    try std.testing.expectEqualStrings("response", send.result_resource.?);
    try std.testing.expectEqualStrings("wasi:http/types/response", send.result_resource_path.?);
}

test "pinned HTTP client send preserves request and response resource identities" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("resource_abi_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const send = registry.find("wasi:http/client@0.3.0-rc-2025-09-16", "send") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("request", send.resource);
    try std.testing.expectEqualStrings("http/types/request", send.resource_path);
    try std.testing.expectEqualStrings("response", send.result_resource.?);
    try std.testing.expectEqualStrings("http/types/response", send.result_resource_path.?);
    try std.testing.expectEqual(Ownership.own, send.params[0].ownership);
    try std.testing.expectEqualStrings("result<response,error-code>", send.result.type_name);
}

test "private owned-error HTTP send preserves both Result resource identities" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("resource_abi_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const send = registry.find("do:resource-probe-owned-error/http@0.1.0", "send") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("request", send.resource);
    try std.testing.expectEqualStrings("do:resource-probe-owned-error/http/request", send.resource_path);
    try std.testing.expectEqualStrings("response", send.result_resource.?);
    try std.testing.expectEqualStrings("do:resource-probe-owned-error/http/response", send.result_resource_path.?);
    try std.testing.expectEqualStrings("error-resource", send.result_error_resource.?);
    try std.testing.expectEqualStrings("do:resource-probe-owned-error/http/error-resource", send.result_error_resource_path.?);
    try std.testing.expectEqualStrings("result<response,error-resource>", send.result.type_name);
    try std.testing.expectEqual(Ownership.own, send.params[0].ownership);
    try std.testing.expectEqual(Ownership.own, send.result.ownership);
}

test "pinned HTTP response status method borrows without consuming response" {
    var registry = try Registry.load(std.testing.allocator, @embedFile("resource_abi_registry.json"));
    defer registry.deinit(std.testing.allocator);

    const status = registry.find("wasi:http/types@0.3.0-rc-2025-09-16", "response.get-status-code") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("response", status.resource);
    try std.testing.expectEqualStrings("http/types/response", status.resource_path);
    try std.testing.expectEqual(@as(usize, 1), status.params.len);
    try std.testing.expectEqualStrings("response", status.params[0].type_name);
    try std.testing.expectEqual(Ownership.borrow, status.params[0].ownership);
    try std.testing.expectEqualStrings("u16", status.result.type_name);
    try std.testing.expectEqual(Ownership.none, status.result.ownership);
    try std.testing.expect(!status.resource_drop);
}
