const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});
    const zig_aio = b.dependency("aio", .{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
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

    exe_mod.addImport("http_lib", lib_mod);

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "http",
        .root_module = exe_mod,
    });

    exe.root_module.addImport("aio", zig_aio.module("aio"));
    exe.root_module.addImport("coro", zig_aio.module("coro"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
