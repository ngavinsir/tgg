const std = @import("std");
const Tui = @import("./tui/Tui.zig");
const Tgg = @This();

var rect: Tui.Rect = .{};
var paragraph = [_][]const u8{ "new", "group", "but", "number", "still", "first", "at", "he", "much", "little" };
var spans: [128]Tui.Text.Span = undefined;
var word_states: [128]WordState = undefined;
var cursor: u7 = 0;

var text: Tui.Text = .{ .spans = &.{} };
var text_input: Tui.TextInput(32) = .{};
var separator: Tui.Text = .{ .spans = &.{} };
var flex: Tui.Flex = .{
    .direction = .Row,
    .items = &.{
        text.view(),
        separator.view(),
        text_input.view(),
    },
    .focused_item_index = 2,
    .rect = .{
        .height = 3,
        .width = 50,
    },
};

const WordState = enum {
    upcoming,
    pending,
    correct,
    wrong,
};

const upcoming_style = Tui.Style{
    .bg_color = Tui.color_from_hex("#292e42"),
    .fg_color = Tui.color_from_hex("#a9b1d6"),
};
const pending_style = Tui.Style{
    .bg_color = Tui.color_from_hex("#292e42"),
    .fg_color = Tui.color_from_hex("#bb9af7"),
};
const correct_style = Tui.Style{
    .bg_color = Tui.color_from_hex("#292e42"),
    .fg_color = Tui.color_from_hex("#9ece6a"),
};
const wrong_style = Tui.Style{
    .bg_color = Tui.color_from_hex("#292e42"),
    .fg_color = Tui.color_from_hex("#f7768e"),
};

pub fn init() !void {
    cursor = 0;
    text_input.clear();
    for (paragraph, 0..) |word, i| {
        if (i == 0) {
            word_states[i] = WordState.pending;
            spans[i] = Tui.Text.Span{
                .text = word,
                .style = pending_style,
            };
            continue;
        }
        word_states[i] = WordState.upcoming;
        spans[i] = Tui.Text.Span{
            .text = word,
            .style = upcoming_style,
        };
    }
    text.spans = spans[0..paragraph.len];
}

fn update_word_state(i: usize, state: WordState) void {
    word_states[i] = state;
    spans[i].style = switch (state) {
        .correct => correct_style,
        .wrong => wrong_style,
        .pending => pending_style,
        .upcoming => upcoming_style,
    };
}

fn draw(ctx: *anyopaque, t: *Tui) !void {
    _ = ctx;

    try flex.view().draw(t);
}

fn handle_key(ctx: *anyopaque, k: Tui.Key) !void {
    _ = ctx;
    switch (k) {
        .esc => try init(),
        .char => |c| {
            if (c == 0x20) { // space
                const inputted_text = text_input.text[0..text_input.text_len];

                // if there is still upcoming words
                if (cursor < paragraph.len) {
                    const expected_text = paragraph[cursor];
                    const is_correct = std.mem.eql(u8, expected_text, inputted_text);
                    const new_state = if (is_correct) WordState.correct else WordState.wrong;
                    update_word_state(cursor, new_state);
                    cursor += 1;
                    if (cursor < paragraph.len - 1) {
                        update_word_state(cursor, WordState.pending);
                    }
                }

                // clear text input
                @memset(&text_input.text, 0);
                text_input.cursor = 0;
                text_input.text_len = 0;
                return;
            }

            try flex.view().handle_key(k);
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
