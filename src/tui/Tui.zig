const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const builtin = @import("builtin");
const Queue = @import("../Queue.zig").Queue;
const io = std.Options.debug_io;

const Tui = @This();
pub const Flex = @import("Flex.zig");
pub const Text = @import("Text.zig");
pub const TextInput = @import("TextInput.zig").TextInput;

term_size: Size = undefined,
cooked_termios: posix.termios = undefined,
uncooked_termios: posix.termios = undefined,
tty: std.Io.File = undefined,
writer: std.Io.File.Writer = undefined,
writer_buffer: [0]u8 = .{},
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
        .tty = .{
            .handle = try posix.openat(posix.AT.FDCWD, "/dev/tty", .{ .ACCMODE = .RDWR }, 0),
            .flags = .{ .nonblocking = false },
        },
    };
    tui.writer = std.Io.File.writerStreaming(tui.tty, io, &tui.writer_buffer);

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
        self.tty.close(io);
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
        var keyBuf: [3]u8 = undefined;
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
                } else if (keyBuf[0] == 0x1B) {
                    self.queue.try_push(Key.esc);
                }
            },
        }
    }
}

pub fn anyWriter(self: *Tui) *std.Io.Writer {
    return &self.writer.interface;
}

pub fn writeRepeated(self: *Tui, byte: u8, count: usize) !void {
    var buffer: [128]u8 = undefined;
    @memset(&buffer, byte);
    var remaining = count;
    while (remaining > 0) {
        const chunk_len = @min(remaining, buffer.len);
        try self.anyWriter().writeAll(buffer[0..chunk_len]);
        remaining -= chunk_len;
    }
}

pub fn read(self: Tui, buf: []u8) !usize {
    return posix.read(self.tty.handle, buf);
}

pub fn move_cursor(self: *Tui, x: usize, y: usize) !void {
    try self.anyWriter().print("\x1B[{};{}H", .{ y + 1, x + 1 });
}

fn enter_alt(self: *Tui) !void {
    try self.anyWriter().writeAll("\x1B[s"); // Save cursor position.
    try self.anyWriter().writeAll("\x1B[?47h"); // Save screen.
    try self.anyWriter().writeAll("\x1B[?1049h"); // Enable alternative buffer.
}

fn leave_alt(self: *Tui) !void {
    try self.anyWriter().writeAll("\x1B[?1049l"); // Disable alternative buffer.
    try self.anyWriter().writeAll("\x1B[?47l"); // Restore screen.
    try self.anyWriter().writeAll("\x1B[u"); // Restore cursor position.
}

fn hide_cursor(self: *Tui) !void {
    try self.anyWriter().writeAll("\x1B[?25l");
}

fn show_cursor(self: *Tui) !void {
    try self.anyWriter().writeAll("\x1B[?25h");
}

pub fn reset_style(self: *Tui) !void {
    try self.anyWriter().writeAll("\x1B[0m");
}

pub fn set_style(self: *Tui, style: Style) !void {
    var buf: [32]u8 = undefined;
    const mode_query = try std.fmt.bufPrint(&buf, "\x1B[{}m", .{style.mode});
    const bg_query = try std.fmt.bufPrint(
        &buf,
        "\x1B[48;2;{};{};{}m",
        .{
            style.bg_color.r,
            style.bg_color.g,
            style.bg_color.b,
        },
    );
    const fg_query = try std.fmt.bufPrint(
        &buf,
        "\x1B[38;2;{};{};{}m",
        .{
            style.fg_color.r,
            style.fg_color.g,
            style.fg_color.b,
        },
    );
    try self.anyWriter().writeAll(mode_query);
    try self.anyWriter().writeAll(bg_query);
    try self.anyWriter().writeAll(fg_query);
}

fn clear(self: *Tui) !void {
    try self.anyWriter().writeAll("\x1B[2J");
}

fn handleSigWinch(_: posix.SIG) callconv(.c) void {
    tui.term_size = tui.getSize() catch return;
}

fn uncook(self: *Tui) !void {
    self.cooked_termios = try posix.tcgetattr(self.tty.handle);
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

    self.uncooked_termios.cc[@backingInt(posix.V.TIME)] = 0;
    self.uncooked_termios.cc[@backingInt(posix.V.MIN)] = 1;
    try posix.tcsetattr(self.tty.handle, .FLUSH, self.uncooked_termios);

    // try self.hideCursor();
    try self.enter_alt();
    try self.clear();
}

fn cook(self: *Tui) !void {
    try self.clear();
    try self.leave_alt();
    try self.show_cursor();
    try self.reset_style();
    try posix.tcsetattr(self.tty.handle, .FLUSH, self.cooked_termios);
}

const Size = struct { width: u16, height: u16 };

fn getSize(self: Tui) !Size {
    var win_size = mem.zeroes(posix.winsize);
    const err = posix.system.ioctl(self.tty.handle, posix.T.IOCGWINSZ, @intFromPtr(&win_size));
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
};

pub const Style = struct {
    bg_color: Color,
    fg_color: Color,
    mode: u4 = 0,
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
    draw_fn: *const fn (ctx: *anyopaque, t: *Tui) anyerror!void,
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

    pub fn draw(self: View, t: *Tui) !void {
        try self.draw_fn(self.ctx, t);
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

pub const App = struct {
    root: View,
    cur_focused: ?View = null,

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
        // DEC synchronized output keeps each rendered frame atomic.
        try tui.anyWriter().writeAll("\x1B[?2026h");
        errdefer tui.anyWriter().writeAll("\x1B[?2026l") catch {};

        try tui.hide_cursor();
        try self.root.draw(&tui);
        try tui.show_cursor();
        try tui.anyWriter().writeAll("\x1B[?2026l");
    }

    pub fn run(self: *App) !void {
        self.focus(self.root);
        try self.draw();

        while (true) {
            if (tui.poll_key()) |k| {
                switch (k) {
                    .ctrl_c => return,
                    .tab => _ = self.focus(self.root),
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
