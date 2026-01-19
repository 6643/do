const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Sema = @import("sema.zig").Sema;
const CodegenWasm = @import("codegen_wasm.zig").CodegenWasm;
const CodegenWat = @import("codegen_wat.zig").CodegenWat;
const token = @import("token.zig");

pub const Compiler = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Compiler {
        return .{ .allocator = allocator };
    }

    pub const BuildResult = struct {
        wasm: []u8,
        wat: []const u8,
    };

    pub fn build(self: *Compiler, source: [:0]const u8) !BuildResult {
        var lexer = Lexer.init(source);
        var tokens = std.ArrayListUnmanaged(token.Token){};
        defer tokens.deinit(self.allocator);
        while (true) {
            const tok = lexer.next();
            try tokens.append(self.allocator, tok);
            if (tok.tag == .eof) break;
        }

        var p = Parser.init(self.allocator, source, try self.allocator.dupe(token.Token, tokens.items));
        defer {
            self.allocator.free(p.tokens);
            p.deinit();
        }
        const root_idx = try p.parse();

        var s = try Sema.init(self.allocator, &p.tree);
        defer s.deinit();
        try s.analyze(root_idx);

        // 生成 WASM 二进制
        var cg_wasm = CodegenWasm.init(self.allocator, &p.tree, &s);
        defer cg_wasm.deinit();
        const wasm = try cg_wasm.generate(root_idx);

        // 生成 WAT 文本
        var cg_wat = CodegenWat.init(self.allocator, &p.tree, &s);
        defer cg_wat.deinit();
        const wat = try cg_wat.generateModule(root_idx);

        return BuildResult{
            .wasm = wasm,
            .wat = try self.allocator.dupe(u8, wat),
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("用法: do <file.do>\n", .{});
        return;
    }

    const file_path = args[1];
    const raw_source = try std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024);
    defer allocator.free(raw_source);
    const source = try allocator.dupeZ(u8, raw_source);
    defer allocator.free(source);

    var compiler = Compiler.init(allocator);
    const result = try compiler.build(source);
    defer allocator.free(result.wasm);
    defer allocator.free(result.wat);

    // 输出 WASM
    try std.fs.cwd().writeFile(.{ .sub_path = "out.wasm", .data = result.wasm });
    // 输出 WAT
    try std.fs.cwd().writeFile(.{ .sub_path = "out.wat", .data = result.wat });

    std.debug.print("\nBuild Successful:\n  -> out.wasm ({d} bytes)\n  -> out.wat ({d} bytes)\n", .{ result.wasm.len, result.wat.len });
}
