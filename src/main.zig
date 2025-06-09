const Tui = @import("tui/Tui.zig");
const std = @import("std");

var app: Tui.App = undefined;

pub const panic = std.debug.FullPanic(panic_handler);

pub fn panic_handler(msg: []const u8, first_trace_addr: ?usize) noreturn {
    app.deinit();
    std.debug.defaultPanic(msg, first_trace_addr);
}

pub fn main() !void {
    var text_input1 = Tui.TextInput(32){};
    var text_input2 = Tui.TextInput(32){};
    var flex = Tui.Flex{
        .direction = .Row,
        .items = &.{
            text_input1.view(),
            text_input2.view(),
        },
        .rect = .{
            .height = 2,
            .width = 50,
        },
    };
    app = try Tui.App.init(flex.view());
    defer app.deinit();

    try app.run();

    // tui = try Tui.init();
    // defer tui.deinit();
    //
    // try tui.start_reading();
    //
    // var inputTextBuffer: [20]u8 = undefined;
    // var textLen: u8 = 0;
    // var cursor: u8 = 0;
    //
    // try tui.move_cursor(0, 0);
    // try tui.anyWriter().writeAll("\x1B[6 q"); // blinking bar cursor
    //
    // var text1 = Tui.Text{ .text = "Hello" };
    // var text2 = Tui.Text{ .text = "World!" };
    // var f: Tui.Flex = .{
    //     .direction = .Row,
    //     .items = &.{
    //         text1.view(),
    //         text2.view(),
    //     },
    //     .rect = .{
    //         .height = 2,
    //         .width = 50,
    //         .x = 0,
    //         .y = 6,
    //     },
    // };
    // try f.view().draw(&tui);
    //
    // while (true) {
    //     if (tui.poll_key()) |k| {
    //         switch (k) {
    //             .ctrl_c => return,
    //             .arrow_left => {
    //                 if (cursor > 0) {
    //                     cursor -= 1;
    //                 }
    //             },
    //             .arrow_right => {
    //                 if (cursor < textLen) {
    //                     cursor += 1;
    //                 }
    //             },
    //
    //             .char => |c| {
    //                 if (textLen == inputTextBuffer.len) {
    //                     continue;
    //                 }
    //
    //                 std.mem.copyBackwards(u8, inputTextBuffer[cursor + 1 .. inputTextBuffer.len], inputTextBuffer[cursor .. inputTextBuffer.len - 1]);
    //                 @memcpy(inputTextBuffer[cursor .. cursor + 1], ([1]u8{c})[0..]);
    //                 cursor += 1;
    //                 if (textLen < inputTextBuffer.len) {
    //                     textLen += 1;
    //                 }
    //             },
    //
    //             .backspace => {
    //                 if (cursor == 0) {
    //                     continue;
    //                 }
    //
    //                 cursor -= 1;
    //                 if (cursor < inputTextBuffer.len) {
    //                     std.mem.copyForwards(u8, inputTextBuffer[cursor .. inputTextBuffer.len - 1], inputTextBuffer[cursor + 1 ..]);
    //                 }
    //                 inputTextBuffer[inputTextBuffer.len - 1] = 0;
    //                 textLen -= 1;
    //             },
    //         }
    //
    //         // rerender
    //         tui.move_cursor(0, 0) catch continue;
    //         tui.anyWriter().writeAll(inputTextBuffer[0..]) catch continue;
    //         tui.anyWriter().writeByteNTimes(' ', tui.term_size.width - cursor) catch continue;
    //         tui.move_cursor(cursor, 0) catch continue;
    //     }
    // }
}
