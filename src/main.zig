const std = @import("std");
const Tui = @import("tui/Tui.zig");
const tgg = @import("tgg.zig");

var app: Tui.App = undefined;

pub const panic = std.debug.FullPanic(panic_handler);

pub fn panic_handler(msg: []const u8, first_trace_addr: ?usize) noreturn {
    app.deinit();
    std.debug.defaultPanic(msg, first_trace_addr);
}

pub fn main(init: std.process.Init) !void {
    try tgg.init(init.io);
    app = try Tui.App.init(init.io, tgg.view());
    defer app.deinit();

    try app.run();
}
