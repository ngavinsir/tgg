const std = @import("std");
const Tui = @import("./tui/Tui.zig");
const Tgg = @This();

var rect: Tui.Rect = .{};
var paragraph = [_][]const u8{ "new", "group", "but", "number", "still", "first", "at", "he", "much", "little" };
var text_input: Tui.TextInput(32) = .{};
var separator: Tui.Text = .{ .spans = &.{} };
var text_spans: [128]Tui.Text.Span = undefined;
var text: Tui.Text = .{ .spans = &.{} };
var flex: Tui.Flex = .{
    .direction = .Row,
    .items = &.{
        text.view(),
        separator.view(),
        text_input.view(),
    },
    .rect = .{
        .height = 3,
        .width = 50,
    },
};

pub fn init() !void {
    const style = Tui.Style{
        .bg_color = try Tui.color_from_hex("#292e42"),
        .fg_color = try Tui.color_from_hex("#a9b1d6"),
    };
    for (paragraph, 0..) |word, i| {
        text_spans[i] = Tui.Text.Span{
            .text = word,
            .style = style,
        };
    }
    text.spans = text_spans[0..paragraph.len];
}

fn draw(ctx: *anyopaque, t: *Tui) !void {
    _ = ctx;

    try flex.view().draw(t);
}

fn handle_key(ctx: *anyopaque, k: Tui.Key) !void {
    _ = ctx;
    switch (k) {
        .char => |c| {
            try flex.view().handle_key(k);
            if (c == 0x20) {
                @panic(&text_input.text);
            }
        },
        else => try flex.view().handle_key(k),
    }
}

fn get_rect(ctx: *anyopaque) Tui.Rect {
    _ = ctx;
    return .{};
}

fn set_rect(ctx: *anyopaque, r: Tui.Rect) void {
    _ = ctx;
    _ = r;
}

fn has_focus(ctx: *anyopaque) bool {
    _ = ctx;
    return true;
}

fn focus(ctx: *anyopaque) Tui.View {
    _ = ctx;
    return flex.view().focus();
}

fn blur(_: *anyopaque) void {}

pub fn view() Tui.View {
    return .{
        .ctx = &flex,
        .get_rect_fn = get_rect,
        .set_rect_fn = set_rect,
        .draw_fn = draw,
        .focus_fn = focus,
        .has_focus_fn = has_focus,
        .handle_key_fn = handle_key,
        .blur_fn = blur,
    };
}
