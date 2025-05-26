const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});
    const zig_aio = b.dependency("aio", .{});

    const lib_mod = b.addModule("http", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "http",
        .root_module = lib_mod,
    });

    lib.root_module.addImport("aio", zig_aio.module("aio"));
    lib.root_module.addImport("coro", zig_aio.module("coro"));


    b.installArtifact(lib);

    const run_cmd = b.addRunArtifact(lib);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
