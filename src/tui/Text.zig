const std = @import("std");
const Tui = @import("Tui.zig");

const Text = @This();
pub const Span = struct {
    text: []const u8,
    style: Tui.Style,
};

has_focus: bool = false,
spans: []const Span,
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

fn focus(ctx: *anyopaque) Tui.View {
    const self: *Text = @ptrCast(@alignCast(ctx));
    self.has_focus = true;
    return self.view();
}

fn blur(ctx: *anyopaque) void {
    const self: *Text = @ptrCast(@alignCast(ctx));
    self.has_focus = false;
}

fn draw(ctx: *anyopaque, screen: *Tui.Screen) !void {
    const self: *Text = @ptrCast(@alignCast(ctx));

    if (self.spans.len == 0) return;

    var x: usize = self.rect.x;
    var y: usize = self.rect.y;
    for (self.spans) |span| {
        screen.draw(x, y, span.text, span.style);
        screen.draw(span.text.len, y, " ", span.style);
        x += span.text.len + 1;
        y += 0;
    }
    if (x < screen.size.width) {
        screen.drawNTimes(x, y, " ", null, screen.size.width - x + 1);
    }
}

pub fn view(self: *Text) Tui.View {
    return .{
        .ctx = self,
        .get_rect_fn = get_rect,
        .set_rect_fn = set_rect,
        .draw_fn = draw,
        .focus_fn = focus,
        .blur_fn = blur,
        .has_focus_fn = has_focus_fn,
    };
}
