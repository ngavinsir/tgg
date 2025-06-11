const std = @import("std");
const Tui = @import("Tui.zig");

pub fn TextInput(comptime max_text_len: u8) type {
    return struct {
        has_focus: bool = false,
        text: [max_text_len]u8 = undefined,
        text_len: u8 = 0,
        rect: Tui.Rect = .{},
        cursor: u8 = 0,

        const Self = @This();

        pub fn clear(self: *Self) void {
            @memset(&self.text, 0);
            self.cursor = 0;
            self.text_len = 0;
        }

        fn get_rect(ctx: *anyopaque) Tui.Rect {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.rect;
        }

        fn set_rect(ctx: *anyopaque, rect: Tui.Rect) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.rect = rect;
        }

        fn has_focus_fn(ctx: *anyopaque) bool {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.has_focus;
        }

        fn focus(ctx: *anyopaque) Tui.View {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.has_focus = true;
            return self.view();
        }

        fn blur(ctx: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.has_focus = false;
        }

        fn draw(ctx: *anyopaque, tui: *Tui) !void {
            const self: *Self = @ptrCast(@alignCast(ctx));

            try tui.move_cursor(self.rect.x, self.rect.y);
            try tui.anyWriter().writeAll(&self.text);
            try tui.anyWriter().writeByteNTimes(' ', tui.term_size.width - self.text.len);
            try tui.move_cursor(self.cursor, self.rect.y);
        }

        fn handle_key(ctx: *anyopaque, k: Tui.Key) !void {
            const self: *Self = @ptrCast(@alignCast(ctx));

            switch (k) {
                .arrow_left => {
                    if (self.cursor > 0) {
                        self.cursor -= 1;
                    }
                },
                .arrow_right => {
                    if (self.cursor < max_text_len) {
                        self.cursor += 1;
                    }
                },
                .char => |c| {
                    if (self.text_len == max_text_len) {
                        return;
                    }

                    const old_text_suffix = self.text[self.cursor .. max_text_len - 1];
                    const new_text_suffix = self.text[self.cursor + 1 .. max_text_len];
                    std.mem.copyBackwards(u8, new_text_suffix, old_text_suffix);
                    const current_cursor_pos = self.text[self.cursor .. self.cursor + 1];
                    @memcpy(current_cursor_pos, ([1]u8{c})[0..]);
                    self.cursor += 1;
                    self.text_len += 1;
                },
                .backspace => {
                    if (self.cursor == 0) {
                        return;
                    }

                    self.cursor -= 1;
                    if (self.cursor < max_text_len) {
                        const old_text_suffix = self.text[self.cursor + 1 ..];
                        const new_text_suffix = self.text[self.cursor .. max_text_len - 1];
                        std.mem.copyForwards(u8, new_text_suffix, old_text_suffix);
                    }
                    self.text[max_text_len - 1] = 0;
                    self.text_len -= 1;
                },
                else => return,
            }
        }

        pub fn view(self: *Self) Tui.View {
            return .{
                .ctx = self,
                .get_rect_fn = get_rect,
                .set_rect_fn = set_rect,
                .draw_fn = draw,
                .focus_fn = focus,
                .blur_fn = blur,
                .has_focus_fn = has_focus_fn,
                .handle_key_fn = handle_key,
            };
        }
    };
}
