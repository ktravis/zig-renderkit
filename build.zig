const std = @import("std");
const Pkg = std.build.Pkg;
const Builder = @import("std").build.Builder;
const Renderer = @import("renderkit/renderer/renderer.zig").Renderer;

var renderer: ?Renderer = null;
var enable_imgui: ?bool = null;

pub fn build(b: *Builder) !void {
    const prefix_path = "";

    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const examples = [_][2][]const u8{
        [_][]const u8{ "mode7", "examples/mode7.zig" },
        [_][]const u8{ "offscreen", "examples/offscreen.zig" },
        [_][]const u8{ "tri_batcher", "examples/tri_batcher.zig" },
        [_][]const u8{ "batcher", "examples/batcher.zig" },
        [_][]const u8{ "meshes", "examples/meshes.zig" },
        [_][]const u8{ "clear_imgui", "examples/clear_imgui.zig" },
        [_][]const u8{ "clear", "examples/clear.zig" },
    };

    const examples_step = b.step("examples", "build all examples");
    b.default_step.dependOn(examples_step);

    for (examples) |example, i| {
        const name = example[0];
        const source = example[1];

        var exe = createExe(b, target, name, source, prefix_path);
        examples_step.dependOn(&exe.step);

        // first element in the list is added as "run" so "zig build run" works
        if (i == 0) {
            _ = createExe(b, target, "run", source, prefix_path);
        }
    }
}

fn createExe(b: *Builder, target: std.build.Target, name: []const u8, source: []const u8, comptime prefix_path: []const u8) *std.build.LibExeObjStep {
    var exe = b.addExecutable(name, source);
    exe.setBuildMode(b.standardReleaseOptions());
    exe.setOutputDir("zig-cache/bin");

    if (b.standardReleaseOptions() == std.builtin.Mode.ReleaseSmall) exe.strip = true;

    addRenderKitToArtifact(b, exe, target, prefix_path);

    const run_cmd = exe.run();
    const exe_step = b.step(name, b.fmt("run {}.zig", .{name}));
    exe_step.dependOn(&run_cmd.step);

    return exe;
}

pub fn getRenderKitPackage(comptime prefix_path: []const u8) Pkg {
    const stb_builder = @import(prefix_path ++ "renderkit/deps/stb/build.zig");
    const stb_pkg = stb_builder.getPackage(prefix_path);

    return .{
        .name = "renderkit",
        .path = prefix_path ++ "renderkit/renderkit.zig",
        .dependencies = &[_]Pkg{stb_pkg},
    };
}

/// prefix_path is the path to the gfx build.zig file relative to your build.zig.
/// prefix_path is used to add package paths. It should be the the same path used to include this build file and end with a slash.
pub fn addRenderKitToArtifact(b: *Builder, exe: *std.build.LibExeObjStep, target: std.build.Target, comptime prefix_path: []const u8) void {
    // build options. For now they can be overridden in root directly as well
    if (renderer == null)
        renderer = b.option(Renderer, "renderer", "dummy, opengl, webgl, metal, directx or vulkan") orelse Renderer.opengl;
    exe.addBuildOption(Renderer, "renderer", renderer.?);

    // renderer specific linkage
    if (target.isDarwin()) addMetalToArtifact(b, exe, target);
    addOpenGlToArtifact(exe, target);

    // stb
    const stb_builder = @import(prefix_path ++ "renderkit/deps/stb/build.zig");
    stb_builder.linkArtifact(b, exe, target, prefix_path);

    exe.addPackage(getRenderKitPackage(prefix_path));

    // optional gamekit package. TODO: dont automatically add this
    addGameKitToArtifact(b, exe, target, prefix_path);
}

/// optionally adds gamekit, sdl and imgui packages to the LibExeObjStep. Note that gamekit relies on the main gfx package.
pub fn addGameKitToArtifact(b: *Builder, exe: *std.build.LibExeObjStep, target: std.build.Target, comptime prefix_path: []const u8) void {
    if (enable_imgui == null)
        enable_imgui = b.option(bool, "imgui", "enable imgui") orelse false;
    exe.addBuildOption(bool, "enable_imgui", enable_imgui.?);

    // sdl
    const sdl_builder = @import(prefix_path ++ "gamekit/deps/sdl/build.zig");
    sdl_builder.linkArtifact(exe, target, prefix_path);
    const sdl_pkg = sdl_builder.getPackage(prefix_path);
    exe.addPackage(sdl_pkg);

    // imgui
    // TODO: skip adding imgui altogether when enable_imgui is false
    const imgui_builder = @import(prefix_path ++ "gamekit/deps/imgui/build.zig");
    imgui_builder.linkArtifact(b, exe, target, prefix_path);
    const imgui_pkg = imgui_builder.getImGuiPackage(prefix_path);
    const imgui_gl_pkg = imgui_builder.getImGuiGlPackage(prefix_path);

    // gamekit
    const gamekit_package = Pkg{
        .name = "gamekit",
        .path = prefix_path ++ "gamekit/gamekit.zig",
        .dependencies = &[_]Pkg{ getRenderKitPackage(prefix_path), sdl_pkg, imgui_pkg, imgui_gl_pkg },
    };
    exe.addPackage(gamekit_package);
}

fn addOpenGlToArtifact(artifact: *std.build.LibExeObjStep, target: std.build.Target) void {
    if (target.isDarwin()) {
        artifact.linkFramework("OpenGL");
    } else if (target.isWindows()) {
        artifact.linkSystemLibrary("kernel32");
        artifact.linkSystemLibrary("user32");
        artifact.linkSystemLibrary("shell32");
        artifact.linkSystemLibrary("gdi32");
    } else if (target.isLinux()) {
        artifact.linkSystemLibrary("GL");
    }
}

fn addMetalToArtifact(b: *Builder, exe: *std.build.LibExeObjStep, target: std.build.Target) void {
    const frameworks_dir = @import("gamekit/deps/imgui/build.zig").macosFrameworksDir(b) catch unreachable;
    exe.addFrameworkDir(frameworks_dir);
    exe.linkFramework("Foundation");
    exe.linkFramework("Cocoa");
    exe.linkFramework("Quartz");
    exe.linkFramework("QuartzCore");
    exe.linkFramework("Metal");
    exe.linkFramework("MetalKit");

    const cflags = [_][]const u8{ "-std=c99", "-ObjC", "-fobjc-arc" };
    exe.addIncludeDir("renderkit/renderer/metal/native");
    exe.addCSourceFile("renderkit/renderer/metal/native/metal.c", &cflags);
}
