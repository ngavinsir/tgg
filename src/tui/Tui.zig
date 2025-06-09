const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const builtin = @import("builtin");
const Queue = @import("../Queue.zig").Queue;

const Tui = @This();
pub const Flex = @import("Flex.zig");
// pub const Text = @import("Text.zig");
pub const TextInput = @import("TextInput.zig").TextInput;

term_size: Size = undefined,
cooked_termios: posix.termios = undefined,
uncooked_termios: posix.termios = undefined,
tty: posix.fd_t = undefined,
thread: ?std.Thread = null,
queue: Queue(Key, 512) = .{},
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
        var keyBuf: [3]u8 = undefined;
        if (self.poll_tty(keyBuf[0..]) catch continue) {
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
                    }
                },
            }
        }
    }
}

// pub fn loop(self: *Tui) !void {
//     while (true) {
//         try self.render();
//
//         var buffer: [1]u8 = undefined;
//         _ = try self.read(&buffer);
//
//         var buf: [64]u8 = undefined;
//         const bufferHex = try std.fmt.bufPrint(&buf, "0x{x}", .{buffer});
//         try self.writeLine(bufferHex, 17, self.term_size.width, true);
//         if (buffer[0] == 'q') {
//             return;
//         } else if (buffer[0] == '\x1B') {
//             self.uncooked_termios.cc[@intFromEnum(posix.V.TIME)] = 1;
//             self.uncooked_termios.cc[@intFromEnum(posix.V.MIN)] = 0;
//             try posix.tcsetattr(self.tty, .NOW, self.uncooked_termios);
//
//             var esc_buffer: [8]u8 = undefined;
//             const esc_read = try self.read(&esc_buffer);
//             const escBufferHex = try std.fmt.bufPrint(&buf, "0x{x}", .{esc_buffer});
//             try self.writeLine(escBufferHex, 18, self.term_size.width, false);
//
//             self.uncooked_termios.cc[@intFromEnum(posix.V.TIME)] = 0;
//             self.uncooked_termios.cc[@intFromEnum(posix.V.MIN)] = 1;
//             try posix.tcsetattr(self.tty, .NOW, self.uncooked_termios);
//
//             if (mem.eql(u8, esc_buffer[0..esc_read], "[A")) {
//                 self.i -|= 1;
//             } else if (mem.eql(u8, esc_buffer[0..esc_read], "[B")) {
//                 self.i = @min(self.i + 1, 15);
//             }
//         }
//     }
// }

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

fn attribute_reset(self: Tui) !void {
    try self.anyWriter().writeAll("\x1B[0m");
}

fn blueBackground(self: Tui) !void {
    try self.anyWriter().writeAll("\x1B[44m");
}

fn clear(self: Tui) !void {
    try self.anyWriter().writeAll("\x1B[2J");
}

fn handleSigWinch(_: c_int) callconv(.C) void {
    tui.term_size = tui.getSize() catch return;
}

// fn render(self: Tui) !void {
//     try self.writeLine("foo", 0, self.term_size.width, self.i == 0);
//     try self.writeLine("bar", 1, self.term_size.width, self.i == 1);
//     try self.writeLine("baz", 2, self.term_size.width, self.i == 2);
//     try self.writeLine("xyzzy", 3, self.term_size.width, self.i == 3);
//     try self.writeLine("foo", 4, self.term_size.width, self.i == 4);
//     try self.writeLine("bar", 5, self.term_size.width, self.i == 5);
//     try self.writeLine("baz", 6, self.term_size.width, self.i == 6);
//     try self.writeLine("xyzzy", 7, self.term_size.width, self.i == 7);
//     try self.writeLine("foo", 8, self.term_size.width, self.i == 8);
//     try self.writeLine("bar", 9, self.term_size.width, self.i == 9);
//     try self.writeLine("baz", 10, self.term_size.width, self.i == 10);
//     try self.writeLine("xyzzy", 11, self.term_size.width, self.i == 11);
//     try self.writeLine("foo", 12, self.term_size.width, self.i == 12);
//     try self.writeLine("bar", 13, self.term_size.width, self.i == 13);
//     try self.writeLine("baz", 14, self.term_size.width, self.i == 14);
//     try self.writeLine("xyzzy", 15, self.term_size.width, self.i == 15);
// }

fn writeLine(self: Tui, txt: []const u8, y: usize, width: usize, selected: bool) !void {
    if (selected) {
        try self.blueBackground();
    } else {
        try self.attribute_reset();
    }
    try self.show_cursor();
    try self.move_cursor(0, y);
    // try hideCursor(writer);
    try self.anyWriter().writeAll(txt);
    try self.anyWriter().writeByteNTimes(' ', width - txt.len);
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

    self.uncooked_termios.cc[@intFromEnum(posix.V.TIME)] = 1;
    self.uncooked_termios.cc[@intFromEnum(posix.V.MIN)] = 0;
    try posix.tcsetattr(self.tty, .FLUSH, self.uncooked_termios);

    // try self.hideCursor();
    try self.enter_alt();
    try self.clear();
}

fn cook(self: Tui) !void {
    try self.clear();
    try self.leave_alt();
    try self.show_cursor();
    try self.attribute_reset();
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

pub const Key = union(enum) {
    backspace,
    tab,
    ctrl_c,
    arrow_left,
    arrow_right,
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

    pub fn run(self: *App) !void {
        self.focus(self.root);
        while (true) {
            if (tui.poll_key()) |k| {
                switch (k) {
                    .ctrl_c => return,
                    .tab => _ = self.focus(self.root),
                    else => try self.root.handle_key(k),
                }

                try self.root.draw(&tui);
            }
        }
    }
};
