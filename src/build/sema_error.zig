const lexer = @import("lexer.zig");

pub const ErrorSite = struct {
    line: usize,
    col: usize,
};

var last_error_site: ?ErrorSite = null;

pub fn take_last_error_site() ?ErrorSite {
    const out = last_error_site;
    last_error_site = null;
    return out;
}

pub fn clear_last_error_site() void {
    last_error_site = null;
}

pub fn mark_error_at(tokens: []const lexer.Token, idx: usize, err: anyerror) anyerror {
    if (tokens.len != 0) {
        const safe_idx = if (idx < tokens.len) idx else tokens.len - 1;
        last_error_site = .{
            .line = tokens[safe_idx].line,
            .col = tokens[safe_idx].col,
        };
    }
    return err;
}
