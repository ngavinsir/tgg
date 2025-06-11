const std = @import("std");
const Tui = @import("./tui/Tui.zig");
const Tgg = @This();

var rect: Tui.Rect = .{};
var result_text_buff: [32]u8 = undefined;
var result_span: [1]Tui.Text.Span = .{.{ .text = &.{}, .style = upcoming_style }};
var paragraph = [_][]const u8{ "new", "group", "but", "number", "still", "first", "at", "he", "much", "little" };
var spans: [128]Tui.Text.Span = undefined;
var word_states: [128]WordState = undefined;
var cursor: u7 = 0;
var timer: ?std.time.Timer = null;
var wpm: ?u9 = null;
var acc: ?u9 = null;

var result_text: Tui.Text = .{ .spans = &.{} };
var paragraph_text: Tui.Text = .{ .spans = &.{} };
var text_input: Tui.TextInput(32) = .{};
var separator: Tui.Text = .{ .spans = &.{} };
var root: Tui.Flex = .{
    .direction = .Row,
    .items = &.{
        result_text.view(),
        paragraph_text.view(),
        separator.view(),
        text_input.view(),
    },
    .focused_item_index = 3,
    .rect = .{
        .height = 4,
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
    wpm = null;
    acc = null;
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
    paragraph_text.spans = spans[0..paragraph.len];
    try update_result_text();
}

fn update_result_text() !void {
    var wpm_text: []const u8 = "xx";
    if (wpm) |w| {
        var buf: [8]u8 = undefined;
        wpm_text = try std.fmt.bufPrint(&buf, "{}", .{w});
    }
    result_span[0].text = try std.fmt.bufPrint(&result_text_buff, "wpm: {s}", .{wpm_text});
    result_text.spans = &result_span;
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

fn check_pending_word(inputted_text: []const u8) WordState {
    const expected_text = paragraph[cursor];
    const is_correct = std.mem.eql(u8, expected_text, inputted_text);
    return if (is_correct) WordState.correct else WordState.wrong;
}

fn update_pending_word(new_state: WordState) void {
    update_word_state(cursor, new_state);
    cursor += 1;
    if (cursor < paragraph.len - 1) {
        update_word_state(cursor, WordState.pending);
    }
}

fn get_total_correct_chars() f64 {
    var res: u16 = 0;
    for (word_states, 0..) |word_state, i| {
        switch (word_state) {
            .upcoming => break,
            .correct => {
                const is_last = i == paragraph.len - 1;
                res += @intCast(paragraph[i].len);
                if (!is_last) {
                    res += 1; // space character
                }
            },
            else => continue,
        }
    }

    return @floatFromInt(res);
}

fn calculate_result() !void {
    std.debug.assert(timer != null);
    const elapsed_ns: f64 = @floatFromInt(timer.?.lap());
    const ns_per_min: f64 = @floatFromInt(std.time.ns_per_min);
    const min = elapsed_ns / ns_per_min;
    wpm = @intFromFloat(get_total_correct_chars() / 5 / min);
    try update_result_text();
}

fn draw(ctx: *anyopaque, t: *Tui) !void {
    _ = ctx;

    try root.view().draw(t);
}

fn handle_key(ctx: *anyopaque, k: Tui.Key) !void {
    _ = ctx;
    switch (k) {
        .esc => try init(),
        .char => |c| {
            var inputted_text = text_input.text[0..text_input.text_len];

            // space
            if (c == 0x20) {
                // can't input space as the first character
                if (inputted_text.len == 0) return;

                // if there is still pending word
                if (cursor < paragraph.len) {
                    update_pending_word(check_pending_word(inputted_text));

                    if (cursor == paragraph.len) try calculate_result();
                }

                // clear text input
                @memset(&text_input.text, 0);
                text_input.cursor = 0;
                text_input.text_len = 0;
                return;
            }

            // record the starting timestamp
            if (cursor == 0 and inputted_text.len == 0) timer = try std.time.Timer.start();

            try root.view().handle_key(k);
            inputted_text = text_input.text[0..text_input.text_len];

            // last word don't need another space
            if (cursor == paragraph.len - 1 and check_pending_word(inputted_text) == WordState.correct) {
                update_pending_word(check_pending_word(inputted_text));
                try calculate_result();
            }
        },
        else => try root.view().handle_key(k),
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
    return root.view().focus();
}

fn blur(_: *anyopaque) void {}

pub fn view() Tui.View {
    return .{
        .ctx = &root,
        .get_rect_fn = get_rect,
        .set_rect_fn = set_rect,
        .draw_fn = draw,
        .focus_fn = focus,
        .has_focus_fn = has_focus,
        .handle_key_fn = handle_key,
        .blur_fn = blur,
    };
}
