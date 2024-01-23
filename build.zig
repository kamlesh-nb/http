const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "http",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    _ = b.addModule("http", .{
        .root_source_file = .{ .path = "src/main.zig" },
        .imports =  &.{
            .{
                .name = "buffer",
                .module = b.dependency("buffer", .{}).module("buffer"),
            },
        },
    });

    lib.root_module.addImport("buffer", b.dependency("buffer", .{
        .target = target,
        .optimize = optimize,
    }).module("buffer"));

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "http",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("buffer", b.dependency("buffer", .{
        .target = target,
        .optimize = optimize,
    }).module("buffer"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
 
    
}
