const std = @import("std");
const assert = std.debug.assert;
const io = std.Options.debug_io;

pub fn Queue(comptime T: type, comptime len: usize) type {
    if (len <= 0 or (len & (len - 1)) != 0) {
        @compileError("queue len must be power of 2");
    }

    return struct {
        q: [len]T = undefined,
        push_index: usize = 0,
        pop_index: usize = 0,
        mutex: std.Io.Mutex = .init,
        cond: std.Io.Condition = .init,

        const Self = @This();
        const mod_mask = len - 1;

        fn _is_full(self: *Self) bool {
            const current_size = self.push_index - self.pop_index;
            assert(current_size <= len);
            return current_size == len;
        }

        fn _is_empty(self: *Self) bool {
            return self.push_index == self.pop_index;
        }

        pub fn is_full(self: *Self) bool {
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);

            return self._is_full();
        }

        pub fn is_empty(self: *Self) bool {
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);

            return self._is_empty();
        }

        pub fn push(self: *Self, x: T) !void {
            assert(self.push_index >= self.pop_index);

            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);

            if (self._is_full()) {
                return error.FullQueueError;
            }

            self.q[self.push_index & mod_mask] = x;
            self.push_index += 1;

            self.cond.signal(io);
        }

        pub fn try_push(self: *Self, x: T) void {
            self.push(x) catch {};
        }

        pub fn pop(self: *Self) ?T {
            assert(self.push_index >= self.pop_index);

            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);

            while (self._is_empty()) {
                self.cond.waitUncancelable(io, &self.mutex);
            }

            const x = self.q[self.pop_index & mod_mask];
            self.pop_index += 1;
            return x;
        }
    };
}

const testing = std.testing;
test "Queue: simple push / pop" {
    var queue: Queue(u8, 16) = .{};
    try queue.push(1);
    try queue.push(2);
    const pop = queue.pop();
    try testing.expectEqual(1, pop);
    try testing.expectEqual(2, queue.pop());
}

const Thread = std.Thread;
const thread_cfg = Thread.SpawnConfig{ .allocator = testing.allocator };
test "Queue rejects pushes while full and accepts them after a pop" {
    var queue: Queue(u8, 2) = .{};
    try queue.push(1);
    try queue.push(2);
    try testing.expectError(error.FullQueueError, queue.push(3));
    try testing.expectEqual(1, queue.pop());
    try queue.push(3);
    try testing.expectEqual(2, queue.pop());
    try testing.expectEqual(3, queue.pop());
}

fn sleep(nanoseconds: u64) void {
    std.Io.sleep(io, .{ .nanoseconds = nanoseconds }, .awake) catch unreachable;
}

fn sleepy_pop(q: *Queue(u8, 2)) !void {
    // First we wait for the queue to be full.
    while (!q.is_full())
        try Thread.yield();

    // Then give the other thread a good chance of waking up. It's not
    // clear that yield guarantees the other thread will be scheduled,
    // so we'll throw a sleep in here just to be sure. The queue is
    // still full and the push in the other thread is still blocked
    // waiting for space.
    try Thread.yield();
    sleep(std.time.ns_per_s);
    // Finally, let that other thread go.
    try std.testing.expectEqual(1, q.pop());

    // This won't continue until the other thread has had a chance to
    // put at least one item in the queue.
    while (!q.is_full())
        try Thread.yield();
    // But we want to ensure that there's a second push waiting, so
    // here's another sleep.
    sleep(std.time.ns_per_s / 2);

    // And another chance for the other thread to see that it's
    // spurious and go back to sleep.
    try Thread.yield();
    sleep(std.time.ns_per_s / 2);

    // Pop that thing and we're done.
    try std.testing.expectEqual(2, q.pop());
}

test "Fill, block, fill, block" {
    // Fill the queue, block while trying to write another item, have
    // a background thread unblock us, then block while trying to
    // write yet another thing. Have the background thread unblock
    // that too (after some time) then drain the queue. This test
    // fails if the while loop in `push` is turned into an `if`.

    var queue: Queue(u8, 2) = .{};
    const thread = try Thread.spawn(thread_cfg, sleepy_pop, .{&queue});
    try queue.push(1);
    try queue.push(2);
    const now = std.Io.Clock.awake.now(io).nanoseconds;
    while (true) {
        if (queue.push(3)) |_| {
            break;
        } else |_| {
            sleep(50 * std.time.ns_per_ms);
        }
    }
    const then = std.Io.Clock.awake.now(io).nanoseconds;

    // Just to make sure the sleeps are yielding to this thread, make
    // sure it took at least 900ms to do the push.
    try std.testing.expect(then - now > 900 * std.time.ns_per_ms);

    while (true) {
        if (queue.push(4)) |_| {
            break;
        } else |_| {
            sleep(50 * std.time.ns_per_ms);
        }
    }

    // And once that push has gone through, the other thread's done.
    thread.join();
    try std.testing.expectEqual(3, queue.pop());
    try std.testing.expectEqual(4, queue.pop());
}
