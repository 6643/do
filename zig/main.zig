const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const sema = @import("sema.zig");
const codegen_wasm = @import("codegen_wasm.zig");
const codegen_wat = @import("codegen_wat.zig");
const token = @import("token.zig");
const ast = @import("ast.zig");

const Compiler = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Compiler {
        return .{ .allocator = allocator };
    }

    pub fn build(self: *Compiler, source: [:0]const u8) !BuildResult {
        std.debug.print("STAGE: Lexing\n", .{});
        var l = lexer.Lexer.init(source);
        var tokens = std.ArrayListUnmanaged(token.Token){};
        defer tokens.deinit(self.allocator);

        while (true) {
            const tok = l.next();
            try tokens.append(self.allocator, tok);
            if (tok.tag == .eof) break;
        }

        std.debug.print("STAGE: Parsing\n", .{});
        var p = parser.Parser.init(self.allocator, source, try self.allocator.dupe(token.Token, tokens.items));
        defer {
            self.allocator.free(p.tokens);
            p.deinit();
        }
        const root_idx = try p.parse();

        std.debug.print("STAGE: Sema\n", .{});
        var s = try sema.Sema.init(self.allocator, &p.tree);
        defer s.deinit();
        try s.analyze(root_idx);

        std.debug.print("STAGE: Codegen WASM\n", .{});
        var cg_wasm = codegen_wasm.CodegenWasm.init(self.allocator, &p.tree, &s);
        defer cg_wasm.deinit();
        const wasm = try cg_wasm.generate(root_idx);

        std.debug.print("STAGE: Codegen WAT\n", .{});
        var cg_wat = codegen_wat.CodegenWat.init(self.allocator, &p.tree, &s);
        defer cg_wat.deinit();
        const wat = try cg_wat.generateModule(root_idx);

        return BuildResult{
            .wasm = wasm,
            .wat = try self.allocator.dupe(u8, wat),
        };
    }
};

const BuildResult = struct {
    wasm: []const u8,
    wat: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: docc <file.do>\n", .{});
        return;
    }

    const raw_source = try std.fs.cwd().readFileAlloc(allocator, args[1], 1024 * 1024);
    defer allocator.free(raw_source);
    const source = try allocator.dupeZ(u8, raw_source);
    defer allocator.free(source);

    var compiler = Compiler.init(allocator);
    const result = try compiler.build(source);
    defer allocator.free(result.wasm);
    defer allocator.free(result.wat);

    const f_wasm = try std.fs.cwd().createFile("out.wasm", .{});
    defer f_wasm.close();
    try f_wasm.writeAll(result.wasm);

    const f_wat = try std.fs.cwd().createFile("out.wat", .{});
    defer f_wat.close();
    try f_wat.writeAll(result.wat);
    
    std.debug.print("\nBuild Successful:\n  -> out.wasm ({d} bytes)\n  -> out.wat ({d} bytes)\n", .{ result.wasm.len, result.wat.len });
}