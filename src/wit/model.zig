const std = @import("std");

pub const Span = struct {
    start: usize,
    end: usize,
    line: usize,
    column: usize,
};

pub const Version = struct {
    major: u32,
    minor: u32,
    patch: u32,
    prerelease: []const u8 = "",
};

pub const PackageDecl = struct {
    namespace: []const u8,
    name: []const u8,
    version: Version,
    span: Span,
};

pub const OwnershipMode = enum {
    none,
    owned,
    borrowed,
};

pub const TypeKind = enum {
    bool,
    s8,
    u8,
    s16,
    u16,
    s32,
    u32,
    s64,
    u64,
    f32,
    f64,
    char,
    string,
    named,
    list,
    option,
    result,
    future,
    stream,
    tuple,
    own,
    borrow,
    unit,
};

pub const TypeRef = struct {
    kind: TypeKind,
    name: []const u8,
    args: []const *TypeRef,
    ownership: OwnershipMode,
    span: Span,
};

pub const Field = struct {
    name: []const u8,
    type_ref: *TypeRef,
    span: Span,
};

pub const Case = struct {
    name: []const u8,
    payload: ?*TypeRef,
    span: Span,
};

pub const TypeAlias = struct {
    name: []const u8,
    type_ref: *TypeRef,
    span: Span,
};

pub const RecordDecl = struct {
    name: []const u8,
    fields: []const Field,
    span: Span,
};

pub const VariantDecl = struct {
    name: []const u8,
    cases: []const Case,
    span: Span,
};

pub const EnumDecl = struct {
    name: []const u8,
    cases: []const Case,
    span: Span,
};

pub const FlagsDecl = struct {
    name: []const u8,
    flags: []const []const u8,
    span: Span,
};

pub const ResourceDecl = struct {
    name: []const u8,
    has_drop: bool,
    span: Span,
};

pub const FunctionEffects = struct {
    is_async: bool,
    has_future: bool,
    has_stream: bool,
    has_resource: bool,
};

pub const Param = struct {
    name: []const u8,
    type_ref: *TypeRef,
    span: Span,
};

pub const FunctionDecl = struct {
    name: []const u8,
    is_async: bool,
    params: []const Param,
    result: ?*TypeRef,
    effects: FunctionEffects,
    span: Span,
};

pub const UseDecl = struct {
    target: []const u8,
    span: Span,
};

pub const IncludeDecl = struct {
    target: []const u8,
    span: Span,
};

pub const InterfaceDecl = struct {
    name: []const u8,
    package: ?PackageDecl = null,
    uses: []const UseDecl,
    includes: []const IncludeDecl,
    aliases: []const TypeAlias,
    records: []const RecordDecl,
    variants: []const VariantDecl,
    enums: []const EnumDecl,
    flags: []const FlagsDecl,
    resources: []const ResourceDecl,
    functions: []const FunctionDecl,
    span: Span,
};

pub const WorldImport = struct {
    name: []const u8,
    target: []const u8 = "",
    span: Span,
};

pub const WorldDecl = struct {
    name: []const u8,
    package: ?PackageDecl = null,
    imports: []const WorldImport,
    exports: []const WorldImport,
    span: Span,
};

pub const Parsed = struct {
    source: []const u8,
    package: PackageDecl,
    interfaces: []const InterfaceDecl,
    worlds: []const WorldDecl,
};

pub const Ast = struct {
    arena: std.heap.ArenaAllocator,
    source: []const u8,
    package: PackageDecl,
    interfaces: []const InterfaceDecl,
    worlds: []const WorldDecl,

    pub fn deinit(self: *Ast) void {
        self.arena.deinit();
    }
};

pub const BindingModel = struct {
    arena: std.heap.ArenaAllocator,
    source: []const u8,
    owns_source: bool,
    owned_sources: []const []const u8,
    package: PackageDecl,
    packages: []const PackageDecl = &.{},
    world: WorldDecl,
    interfaces: []const InterfaceDecl,
    content_hash: [32]u8,

    pub fn deinit(self: *BindingModel) void {
        if (self.owns_source) {
            for (self.owned_sources) |source| self.arena.child_allocator.free(source);
        }
        self.arena.deinit();
    }
};

pub fn primitive_kind(name: []const u8) ?TypeKind {
    if (std.mem.eql(u8, name, "bool")) return .bool;
    if (std.mem.eql(u8, name, "s8")) return .s8;
    if (std.mem.eql(u8, name, "u8")) return .u8;
    if (std.mem.eql(u8, name, "s16")) return .s16;
    if (std.mem.eql(u8, name, "u16")) return .u16;
    if (std.mem.eql(u8, name, "s32")) return .s32;
    if (std.mem.eql(u8, name, "u32")) return .u32;
    if (std.mem.eql(u8, name, "s64")) return .s64;
    if (std.mem.eql(u8, name, "u64")) return .u64;
    if (std.mem.eql(u8, name, "f32")) return .f32;
    if (std.mem.eql(u8, name, "f64")) return .f64;
    if (std.mem.eql(u8, name, "char")) return .char;
    if (std.mem.eql(u8, name, "string")) return .string;
    if (std.mem.eql(u8, name, "unit")) return .unit;
    return null;
}

pub fn type_has_kind(type_ref: *const TypeRef, kind: TypeKind) bool {
    if (type_ref.kind == kind) return true;
    for (type_ref.args) |arg| {
        if (type_has_kind(arg, kind)) return true;
    }
    return false;
}

pub fn type_is_resource(type_ref: *const TypeRef, resources: []const ResourceDecl) bool {
    if (type_ref.kind != .named) return false;
    for (resources) |resource| {
        if (std.mem.eql(u8, resource.name, type_ref.name)) return true;
    }
    return false;
}
