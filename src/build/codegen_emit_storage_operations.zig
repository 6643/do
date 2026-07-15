//! Storage set / put / copy / alias operation emit facade.
//!
//! The operation implementations still live beside storage value emission while
//! Task 6 preserves WAT and ownership behavior byte-for-byte. This module is
//! the import boundary for callers that need mutating storage operations.

const values = @import("codegen_emit_storage_values.zig");

pub const emitStorageBoundsCheck = values.emitStorageBoundsCheck;
pub const emitStorageWriteExpr = values.emitStorageWriteExpr;
pub const emitStorageSetExpr = values.emitStorageSetExpr;
pub const emitStoragePutCall = values.emitStoragePutCall;
pub const emitStoragePutExpr = values.emitStoragePutExpr;
pub const emitStoragePutSpreadCall = values.emitStoragePutSpreadCall;
pub const emitStorageSetScalarCall = values.emitStorageSetScalarCall;
pub const emitStoragePutSpreadScalarElement = values.emitStoragePutSpreadScalarElement;
pub const emitStoragePutScalarCall = values.emitStoragePutScalarCall;
pub const emitStorageCloneCurrentLen = values.emitStorageCloneCurrentLen;
pub const emitStorageCloneCurrentLenForElem = values.emitStorageCloneCurrentLenForElem;
pub const emitStorageCloneManagedCurrentLen = values.emitStorageCloneManagedCurrentLen;
pub const emitStorageCloneManagedWithLenLocal = values.emitStorageCloneManagedWithLenLocal;
pub const emitStorageIncCopiedManagedElements = values.emitStorageIncCopiedManagedElements;
pub const emitStorageCloneWithLenLocal = values.emitStorageCloneWithLenLocal;
pub const emitStorageCloneWithLenLocalForElem = values.emitStorageCloneWithLenLocalForElem;
pub const emitStorageCloneWithLenLocalTyped = values.emitStorageCloneWithLenLocalTyped;
pub const emitStorageElementPtrFromLocal = values.emitStorageElementPtrFromLocal;
pub const emitStorageElementPtrFromLocalWithIndent = values.emitStorageElementPtrFromLocalWithIndent;
pub const emitStorageAliasProtect = values.emitStorageAliasProtect;
pub const emitStorageAliasRelease = values.emitStorageAliasRelease;
pub const emitReplaceStoragePutSourceTmp = values.emitReplaceStoragePutSourceTmp;
pub const emitOverwriteReleaseManagedLocal = values.emitOverwriteReleaseManagedLocal;
pub const emitStorageSetCall = values.emitStorageSetCall;
pub const emitStoragePutOneCall = values.emitStoragePutOneCall;
pub const emitStorageSetManagedCall = values.emitStorageSetManagedCall;
pub const emitStoragePutManagedCall = values.emitStoragePutManagedCall;
