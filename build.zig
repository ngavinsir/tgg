const std = @import("std");

const targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "tgg",
        .root_module = exe_mod,
    });

    const run_cmd = b.addRunArtifact(exe);

    // Forward arguments after `--` to the application.
    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const queue_test_mod = b.createModule(.{
        .root_source_file = b.path("src/Queue.zig"),
        .target = target,
        .optimize = optimize,
    });
    const queue_unit_tests = b.addTest(.{ .root_module = queue_test_mod });
    const run_queue_unit_tests = b.addRunArtifact(queue_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_queue_unit_tests.step);

    const all_step = b.step("all", "Build for all targets");
    for (targets) |t| {
        const target_mod = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(t),
            .optimize = .ReleaseSafe,
        });
        const t_exe = b.addExecutable(.{
            .name = "tgg",
            .root_module = target_mod,
        });

        const target_output = b.addInstallArtifact(t_exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = try t.zigTriple(b.allocator),
                },
            },
        });

        all_step.dependOn(&target_output.step);
    }
}
