const Tui = @import("Tui.zig");

const Text = @This();

has_focus: bool = false,
text: []const u8,
rect: Tui.Rect = .{},

fn get_rect(ctx: *anyopaque) Tui.Rect {
    const self: *Text = @ptrCast(@alignCast(ctx));
    return self.rect;
}

fn set_rect(ctx: *anyopaque, rect: Tui.Rect) void {
    const self: *Text = @ptrCast(@alignCast(ctx));
    self.rect = rect;
}

fn has_focus_fn(ctx: *anyopaque) bool {
    const self: *Text = @ptrCast(@alignCast(ctx));
    return self.has_focus;
}

fn focus(ctx: *anyopaque, _: *const fn (a: Tui.App, v: Tui.View) void) void {
    const self: *Text = @ptrCast(@alignCast(ctx));
    self.has_focus = true;
}

fn draw(ctx: *anyopaque, t: *Tui) !void {
    const self: *Text = @ptrCast(@alignCast(ctx));

    try t.move_cursor(self.rect.x, self.rect.y);
    try t.anyWriter().writeAll(self.text);
    try t.anyWriter().writeByteNTimes(' ', t.term_size.width - self.text.len);
}

pub fn view(self: *Text) Tui.View {
    return .{
        .ctx = self,
        .get_rect_fn = get_rect,
        .set_rect_fn = set_rect,
        .draw_fn = draw,
        .focus_fn = focus,
        .has_focus_fn = has_focus_fn,
    };
}
