const Tui = @import("Tui.zig");

pub const Flex = @This();

pub const Direction = enum {
    Row,
    Column,
};

direction: Direction,
items: []const Tui.View,
rect: Tui.Rect = .{},

fn get_rect(ctx: *anyopaque) Tui.Rect {
    const self: *Flex = @ptrCast(@alignCast(ctx));
    return self.rect;
}

fn set_rect(ctx: *anyopaque, rect: Tui.Rect) void {
    const self: *Flex = @ptrCast(@alignCast(ctx));
    self.rect = rect;
}

fn has_focus(ctx: *anyopaque) bool {
    const self: *Flex = @ptrCast(@alignCast(ctx));

    for (self.items) |i| {
        if (i.has_focus()) {
            return true;
        }
    }
    return false;
}

fn focus(ctx: *anyopaque) Tui.View {
    const self: *Flex = @ptrCast(@alignCast(ctx));

    const item_count = self.items.len;
    if (item_count == 0) return self.view();

    const new_focused_item = switch (has_focus(self)) {
        false => 0,
        true => blk: {
            for (self.items, 0..) |item, i| {
                if (item.has_focus()) break :blk (i + 1) % item_count;
            }
            break :blk 0;
        },
    };
    return self.items[new_focused_item].focus();
}

fn blur(_: *anyopaque) void {}

fn draw(ctx: *anyopaque, t: *Tui) !void {
    const self: *Flex = @ptrCast(@alignCast(ctx));

    const item_count: u16 = @intCast(self.items.len);
    if (item_count == 0) {
        return;
    }

    const item_width = switch (self.direction) {
        .Column => self.rect.width / item_count,
        .Row => self.rect.width,
    };
    const item_height = switch (self.direction) {
        .Column => self.rect.height,
        .Row => self.rect.height / item_count,
    };
    if (item_width <= 0 or item_height <= 0) {
        return;
    }

    var x = self.rect.x;
    var y = self.rect.y;
    for (self.items) |item| {
        item.set_rect(.{ .x = x, .y = y, .width = item_width, .height = item_height });

        // draw focused item last
        if (!item.has_focus()) {
            try item.draw(t);
        }

        switch (self.direction) {
            .Column => x += item_width,
            .Row => y += item_height,
        }
    }
    for (self.items) |item| {
        if (item.has_focus()) {
            try item.draw(t);
            return;
        }
    }
}

fn handle_key(ctx: *anyopaque, k: Tui.Key) !void {
    const self: *Flex = @ptrCast(@alignCast(ctx));

    for (self.items) |item| {
        if (!item.has_focus()) continue;

        try item.handle_key(k);
    }
}

pub fn view(self: *Flex) Tui.View {
    return .{
        .ctx = self,
        .get_rect_fn = get_rect,
        .set_rect_fn = set_rect,
        .draw_fn = draw,
        .focus_fn = focus,
        .has_focus_fn = has_focus,
        .handle_key_fn = handle_key,
        .blur_fn = blur,
    };
}
