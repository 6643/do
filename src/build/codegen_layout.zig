//! Backend-neutral layout records shared by GC codegen and legacy test oracles.

pub const ManagedFieldOffset = struct {
    name: []const u8,
    offset: usize,
};

pub const StructLayout = struct {
    name: []const u8,
    type_id: usize,
    payload_bytes: usize,
    managed_fields: []const ManagedFieldOffset,
    owned_name: bool = false,
    /// True for one packed storage element (managed offsets are element-relative).
    is_storage_pack: bool = false,
};

pub const StringData = struct {
    lexeme: []const u8 = "",
    ptr: usize,
    bytes: []const u8,
};
