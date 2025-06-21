const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const builtin = @import("builtin");
const Queue = @import("../Queue.zig").Queue;

const Tui = @This();
pub const Flex = @import("Flex.zig");
pub const Text = @import("Text.zig");
pub const TextInput = @import("TextInput.zig").TextInput;

term_size: Size = undefined,
cooked_termios: posix.termios = undefined,
uncooked_termios: posix.termios = undefined,
tty: posix.fd_t = undefined,
thread: ?std.Thread = null,
queue: Queue(Key, 16) = .{},
is_reading: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),

var initialized = false;
var tui: Tui = undefined;

pub fn init() !Tui {
    if (initialized) {
        return tui;
    }

    initialized = true;
    tui = .{
        .tty = try posix.open("/dev/tty", .{ .ACCMODE = .RDWR }, 0),
    };

    try tui.uncook();
    tui.term_size = try tui.getSize();

    posix.sigaction(posix.SIG.WINCH, &posix.Sigaction{
        .handler = .{ .handler = handleSigWinch },
        .mask = posix.sigemptyset(),
        .flags = 0,
    }, null);

    return tui;
}

pub fn deinit(self: *Tui) void {
    // trigger a read to stop the reading thread
    self.anyWriter().writeAll("\x1B[5n") catch {};

    if (self.thread) |t| {
        self.is_reading.store(false, .seq_cst);
        t.join();
    }

    self.cook() catch {};
    if (builtin.os.tag != .macos) { // closing /dev/tty may block indefinitely on macos
        posix.close(self.tty);
    }
}

pub fn start_reading(self: *Tui) !void {
    if (self.thread) |_| {
        return;
    }

    self.thread = try std.Thread.spawn(.{}, read_loop, .{self});
}

fn poll_tty(self: *Tui, buf: []u8) !bool {
    const n = try self.read(buf);
    return n > 0;
}

pub fn poll_key(self: *Tui) ?Key {
    return self.queue.pop();
}

fn read_loop(self: *Tui) void {
    while (self.is_reading.load(.seq_cst)) {
        var keyBuf: [3]u8 = .{0} ** 3;
        if (!(self.poll_tty(keyBuf[0..]) catch continue)) continue;

        switch (keyBuf[0]) {
            '\x03' => self.queue.try_push(Key.ctrl_c),
            '\x09' => self.queue.try_push(Key.tab),

            // alphanumerics and special chars
            '\x20'...'\x7e' => self.queue.try_push(.{ .char = keyBuf[0] }),

            // backspace or delete
            '\x08', '\x7f' => self.queue.try_push(Key.backspace),

            else => {
                if (std.mem.eql(u8, &keyBuf, "\x1B[D")) {
                    self.queue.try_push(Key.arrow_left);
                } else if (std.mem.eql(u8, &keyBuf, "\x1B[C")) {
                    self.queue.try_push(Key.arrow_right);
                } else if (std.mem.eql(u8, &keyBuf, &.{ 0x1B, 0, 0 })) {
                    self.queue.try_push(Key.esc);
                }
            },
        }
    }
}

pub fn opaque_write(ptr: *const anyopaque, bytes: []const u8) !usize {
    const self: *const Tui = @ptrCast(@alignCast(ptr));
    return posix.write(self.tty, bytes);
}

pub fn anyWriter(self: *const Tui) std.io.AnyWriter {
    return .{
        .context = self,
        .writeFn = Tui.opaque_write,
    };
}

pub fn bufferedWriter(self: Tui) std.io.BufferedWriter(4096, std.io.AnyWriter) {
    return std.io.bufferedWriter(self.anyWriter());
}

pub fn read(self: Tui, buf: []u8) !usize {
    return posix.read(self.tty, buf);
}

pub fn move_cursor(self: Tui, x: usize, y: usize) !void {
    _ = try self.anyWriter().print("\x1B[{};{}H", .{ y + 1, x + 1 });
}

fn enter_alt(self: Tui) !void {
    try self.anyWriter().writeAll("\x1B[s"); // Save cursor position.
    try self.anyWriter().writeAll("\x1B[?47h"); // Save screen.
    try self.anyWriter().writeAll("\x1B[?1049h"); // Enable alternative buffer.
}

fn leave_alt(self: Tui) !void {
    try self.anyWriter().writeAll("\x1B[?1049l"); // Disable alternative buffer.
    try self.anyWriter().writeAll("\x1B[?47l"); // Restore screen.
    try self.anyWriter().writeAll("\x1B[u"); // Restore cursor position.
}

fn hide_cursor(self: Tui) !void {
    try self.anyWriter().writeAll("\x1B[?25l");
}

fn show_cursor(self: Tui) !void {
    try self.anyWriter().writeAll("\x1B[?25h");
}

pub fn reset_style(self: Tui) !void {
    try self.anyWriter().writeAll("\x1B[0m");
}

pub fn set_style(self: Tui, style: Style) !void {
    var buf: [32]u8 = undefined;

    const mode_query = try std.fmt.bufPrint(&buf, "\x1B[{}m", .{style.mode});
    try self.anyWriter().writeAll(mode_query);

    const bg_query = try std.fmt.bufPrint(
        &buf,
        "\x1B[48;2;{};{};{}m",
        .{
            style.bg_color.r,
            style.bg_color.g,
            style.bg_color.b,
        },
    );
    try self.anyWriter().writeAll(bg_query);

    const fg_query = try std.fmt.bufPrint(
        &buf,
        "\x1B[38;2;{};{};{}m",
        .{
            style.fg_color.r,
            style.fg_color.g,
            style.fg_color.b,
        },
    );
    try self.anyWriter().writeAll(fg_query);
}

fn clear(self: Tui) !void {
    try self.anyWriter().writeAll("\x1B[2J");
}

fn handleSigWinch(_: c_int) callconv(.C) void {
    tui.term_size = tui.getSize() catch return;
    // trigger a read to redraw
    tui.anyWriter().writeAll("\x1B[5n") catch {};
}

fn uncook(self: *Tui) !void {
    self.cooked_termios = try posix.tcgetattr(self.tty);
    errdefer self.cook() catch {};

    self.uncooked_termios = self.cooked_termios;

    self.uncooked_termios.iflag.IGNBRK = false;
    self.uncooked_termios.iflag.BRKINT = false;
    self.uncooked_termios.iflag.PARMRK = false;
    self.uncooked_termios.iflag.ISTRIP = false;
    self.uncooked_termios.iflag.INLCR = false;
    self.uncooked_termios.iflag.IGNCR = false;
    self.uncooked_termios.iflag.ICRNL = false;
    self.uncooked_termios.iflag.IXON = false;

    self.uncooked_termios.oflag.OPOST = false;

    self.uncooked_termios.lflag.ECHO = false;
    self.uncooked_termios.lflag.ECHONL = false;
    self.uncooked_termios.lflag.ICANON = false;
    self.uncooked_termios.lflag.ISIG = false;
    self.uncooked_termios.lflag.IEXTEN = false;

    self.uncooked_termios.cflag.CSIZE = .CS8;
    self.uncooked_termios.cflag.PARENB = false;

    self.uncooked_termios.cc[@intFromEnum(posix.V.TIME)] = 0;
    self.uncooked_termios.cc[@intFromEnum(posix.V.MIN)] = 1;
    try posix.tcsetattr(self.tty, .FLUSH, self.uncooked_termios);

    // try self.hideCursor();
    try self.enter_alt();
    try self.clear();
}

fn cook(self: Tui) !void {
    try self.clear();
    try self.leave_alt();
    try self.show_cursor();
    try self.reset_style();
    try posix.tcsetattr(self.tty, .FLUSH, self.cooked_termios);
}

const Size = struct { width: u16, height: u16 };

fn getSize(self: Tui) !Size {
    var win_size = mem.zeroes(posix.winsize);
    const err = posix.system.ioctl(self.tty, posix.T.IOCGWINSZ, @intFromPtr(&win_size));
    if (posix.errno(err) != .SUCCESS) {
        return error.IoctlError;
    }
    return Size{
        .height = @intCast(win_size.row),
        .width = @intCast(win_size.col),
    };
}

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn eql(self: Color, other: Color) bool {
        return self.r == other.r and self.g == other.g and self.b == other.b;
    }
};

pub const Style = struct {
    bg_color: Color,
    fg_color: Color,
    mode: u4 = 0,

    pub fn eql(self: Style, other: ?Style) bool {
        if (other) |o| {
            return self.bg_color.eql(o.bg_color) and self.fg_color.eql(o.fg_color) and self.mode == o.mode;
        }
        return false;
    }
};

pub const Key = union(enum) {
    backspace,
    tab,
    ctrl_c,
    arrow_left,
    arrow_right,
    esc,
    char: u8,
};

pub const Rect = struct {
    width: u16 = 0,
    height: u16 = 0,
    x: u16 = 0,
    y: u16 = 0,
};

pub const View = struct {
    ctx: *anyopaque,
    get_rect_fn: *const fn (ctx: *anyopaque) Rect,
    set_rect_fn: *const fn (ctx: *anyopaque, r: Rect) void,
    draw_fn: *const fn (ctx: *anyopaque, screen: *Screen) anyerror!void,
    handle_key_fn: ?*const fn (ctx: *anyopaque, k: Key) anyerror!void = null,
    focus_fn: *const fn (ctx: *anyopaque) View,
    blur_fn: *const fn (ctx: *anyopaque) void,
    has_focus_fn: *const fn (ctx: *anyopaque) bool,

    pub fn get_rect(self: *View) Rect {
        return self.get_rect_fn(self.ctx);
    }

    pub fn set_rect(self: View, r: Rect) void {
        self.set_rect_fn(self.ctx, r);
    }

    pub fn draw(self: View, screen: *Screen) !void {
        try self.draw_fn(self.ctx, screen);
    }

    pub fn handle_key(self: View, k: Key) !void {
        if (self.handle_key_fn) |f| {
            try f(self.ctx, k);
        }
    }

    pub fn focus(self: View) View {
        return self.focus_fn(self.ctx);
    }

    pub fn blur(self: View) void {
        self.blur_fn(self.ctx);
    }

    pub fn has_focus(self: View) bool {
        return self.has_focus_fn(self.ctx);
    }
};

pub const Cell = struct {
    style: ?Style,
    char: u8,

    pub fn eql(self: Cell, other: Cell) bool {
        const same_char = self.char == other.char;
        const same_style = if (self.style) |s| s.eql(other.style) else other.style == null;
        return same_char and same_style;
    }
};

pub const Screen = struct {
    buffer: [128 * 4][128 * 4]?Cell = undefined,
    size: Size,

    // pub fn init(size: Size) Screen {
    //     const Row = [128 * 16]?Cell;
    //     var outer: [128 * 16]Row = undefined;
    //
    //     for (&outer) |*row| {
    //         row.* = [_]?Cell{null} ** 128 * 16;
    //     }
    //
    //     return .{
    //         .buffer = outer,
    //         .size = size,
    //     };
    // }

    pub fn move_cursor(_: *const Screen, x: usize, y: usize) !void {
        try tui.move_cursor(x, y);
    }

    pub fn draw(self: *Screen, x: usize, y: usize, text: []const u8, style: ?Style) void {
        for (text, 0..) |char, i| {
            const prev = self.buffer[y][x + i];
            const s = if (style) |cur_style| cur_style else blk: {
                if (prev) |p| {
                    break :blk p.style;
                }
                break :blk null;
            };
            self.buffer[y][x + i] = .{ .style = s, .char = char };
        }
    }

    pub fn drawNTimes(self: *Screen, x: usize, y: usize, text: []const u8, style: ?Style, n: usize) void {
        var count: usize = 0;
        while (count < n) : (count += 1) {
            self.draw(x + (text.len * count), y, text, style);
        }
    }

    fn draw_into_tui(self: *const Screen, prev: ?*const Screen) !void {
        var need_to_move_cursor = true;
        var last_style: ?Style = null;
        for (self.buffer[0..tui.term_size.height], 0..) |row, y| {
            for (row[0..tui.term_size.width], 0..) |cell, x| {
                const c = cell orelse {
                    need_to_move_cursor = true;
                    continue;
                };

                const style = if (c.style) |s| s else blk: {
                    if (prev) |p| {
                        if (p.buffer[y][x]) |pp| {
                            break :blk pp.style;
                        }
                    }
                    break :blk null;
                };
                const style_has_changed = if (last_style) |s| !s.eql(style) else true;

                const has_changed = if (prev) |p|
                    if (p.buffer[y][x]) |pp| !pp.eql(c) else true
                else
                    true;

                if (has_changed) {
                    if (need_to_move_cursor) try tui.move_cursor(x, y);
                    if (style_has_changed) {
                        if (style) |s| {
                            try tui.reset_style();
                            try tui.set_style(s);
                        } else {
                            try tui.reset_style();
                        }
                        last_style = c.style;
                    }
                    try tui.anyWriter().writeByte(c.char);
                    need_to_move_cursor = false;
                } else {
                    need_to_move_cursor = true;
                }
            }
        }
    }
};

pub const App = struct {
    root: View,
    cur_focused: ?View = null,
    last_screen: ?*Screen = null,
    cur_screen: Screen = undefined,

    pub fn init(root: View) !App {
        _ = try Tui.init();

        try tui.start_reading();
        try tui.move_cursor(0, 0);
        try tui.anyWriter().writeAll("\x1B[6 q"); // blinking bar cursor

        return .{ .root = root };
    }

    pub fn deinit(_: *App) void {
        tui.deinit();
    }

    pub fn focus(self: *App, view: View) void {
        const new_focused = view.focus();
        if (self.cur_focused) |f| {
            f.blur();
        }
        self.cur_focused = new_focused;
    }

    fn draw(self: *App) !void {
        try tui.hide_cursor();

        self.cur_screen = .{ .size = tui.term_size };
        try self.root.draw(&self.cur_screen);
        try self.cur_screen.draw_into_tui(self.last_screen);
        self.last_screen = &self.cur_screen;

        try tui.show_cursor();
    }

    pub fn run(self: *App) !void {
        self.focus(self.root);
        try self.draw();

        while (true) {
            if (tui.poll_key()) |k| {
                switch (k) {
                    .ctrl_c => return,
                    else => try self.root.handle_key(k),
                }

                try self.draw();
            }
        }
    }
};

pub fn color_from_hex(hex: []const u8) Color {
    if (hex.len != 7 or hex[0] != '#') {
        @panic("invalid rgb hex");
    }

    const r = std.fmt.parseInt(u8, hex[1..3], 16) catch unreachable;
    const g = std.fmt.parseInt(u8, hex[3..5], 16) catch unreachable;
    const b = std.fmt.parseInt(u8, hex[5..7], 16) catch unreachable;

    return .{
        .r = r,
        .g = g,
        .b = b,
    };
}
