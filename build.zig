const std = @import("std");

pub fn build(b: *std.Build) !void {
    var arena = std.heap.ArenaAllocator.init(b.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Get SDK path from $HOME/.ufbt
    const home = b.graph.environ_map.get("HOME") orelse ".";
    const sdk_base = b.fmt("{s}/.ufbt/current/sdk_headers/f7_sdk", .{home});

    const host_target = b.standardTargetOptions(.{});
    const arch = host_target.result.cpu.arch;
    const os = host_target.result.os.tag;

    // UFBT and shell commands
    const ufbt_cmd = [_][]const u8{ "python3", "-m", "ufbt" };
    const shell_cmd = [_][]const u8{"bash"};

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m4 },
        .os_tag = .freestanding,
        .abi = .eabihf,
    });

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    const flipper = b.addTranslateC(.{ .root_source_file = b.path("src/flipper.h"), .target = target, .optimize = optimize, .link_libc = false });

    // Add ARM toolchain libc headers for @cImport
    const arm_libc_include = b.fmt("{s}/.ufbt/toolchain/{s}-{s}/arm-none-eabi/include", .{ home, @tagName(arch), @tagName(os) });
    flipper.addSystemIncludePath(.{ .cwd_relative = arm_libc_include });

    // GCC's own resource-dir headers (stddef.h, stdarg.h, ...) must come first: newlib's
    // headers rely on GCC's stddef.h __need_* multiple-inclusion pattern, which zig's
    // bundled stddef.h doesn't implement.
    if (findGccResourceInclude(allocator, b.graph.io, home, @tagName(arch), @tagName(os))) |gcc_include| {
        flipper.addIncludePath(.{ .cwd_relative = gcc_include });
    }

    // m-core.h (mlib, pulled in transitively by furi.h) wraps itself in file-scope
    // _Pragma(...) to silence compiler warnings; zig's translate-c can't parse that. It's
    // purely cosmetic, so serve a copy with those calls stripped, ahead of the real one.
    if (patchedMlibDir(b, b.graph.io, sdk_base)) |patched_mlib| {
        flipper.addIncludePath(patched_mlib);
    }

    // InputEvent (input.h, pulled in by gui/view_port.h) packs a sequence counter as C
    // bitfields inside an anonymous union; translate-c can't represent bitfields and
    // demotes the whole struct to opaque. Nothing needs those bitfields from Zig (only
    // `key`/`type`), so serve a copy with the union collapsed to its plain uint32_t
    // member: identical size/offsets, but now a real, readable struct.
    if (patchedInputDir(b, b.graph.io, sdk_base)) |patched_input| {
        flipper.addIncludePath(patched_input);
    }

    // Add Flipper SDK includes and defines
    addFlipperIncludes(flipper, sdk_base);
    addFlipperDefines(flipper);

    const obj = b.addObject(.{
        .name = "app",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "flipper", .module = flipper.createModule() }} }),
    });

    obj.root_module.unwind_tables = .none;

    // Install the .o file
    const obj_install = b.addInstallBinFile(obj.getEmittedBin(), b.fmt("{s}.o", .{obj.name}));
    b.getInstallStep().dependOn(&obj_install.step);

    const fap_step = b.step("fap", "Package the app into a .fap file");

    const run_ufbt = b.addSystemCommand(try cmdBuilder(allocator, &ufbt_cmd, &[_][]const u8{}));
    run_ufbt.step.dependOn(&obj_install.step);
    fap_step.dependOn(&run_ufbt.step);

    // Create an "init" step that runs the setup script
    const init_step = b.step("init", "Initialize project with custom settings");
    const run_setup = b.addSystemCommand(try cmdBuilder(allocator, &shell_cmd, &[_][]const u8{"setup.sh"}));
    init_step.dependOn(&run_setup.step);

    const launch_step = b.step("launch", "Launch the app on Flipper via UFBT");
    const run_launch = b.addSystemCommand(try cmdBuilder(allocator, &shell_cmd, &[_][]const u8{"launch"}));
    run_launch.step.dependOn(&obj_install.step);
    launch_step.dependOn(&run_launch.step);
}

fn findGccResourceInclude(alloc: std.mem.Allocator, io: std.Io, home: []const u8, arch: []const u8, os: []const u8) ?[]const u8 {
    const gcc_base = std.fmt.allocPrint(alloc, "{s}/.ufbt/toolchain/{s}-{s}/lib/gcc/arm-none-eabi", .{ home, arch, os }) catch return null;
    var dir = std.Io.Dir.openDirAbsolute(io, gcc_base, .{ .iterate = true }) catch return null;
    defer dir.close(io);
    var it = dir.iterate();
    while (it.next(io) catch return null) |entry| {
        if (entry.kind == .directory) {
            return std.fmt.allocPrint(alloc, "{s}/{s}/include", .{ gcc_base, entry.name }) catch return null;
        }
    }
    return null;
}

fn patchedMlibDir(b: *std.Build, io: std.Io, sdk_base: []const u8) ?std.Build.LazyPath {
    const real_path = b.fmt("{s}/lib/mlib/m-core.h", .{sdk_base});
    const content = std.Io.Dir.cwd().readFileAlloc(io, real_path, b.allocator, .unlimited) catch return null;

    var patched: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, trimmed, "_Pragma(")) {
            // Blank the call but keep a trailing '\' so backslash-continued macros stay intact.
            if (std.mem.endsWith(u8, line, "\\")) patched.append(b.allocator, '\\') catch return null;
        } else {
            patched.appendSlice(b.allocator, line) catch return null;
        }
        patched.append(b.allocator, '\n') catch return null;
    }

    const wf = b.addWriteFiles();
    _ = wf.add("m-core.h", patched.items);
    return wf.getDirectory();
}

fn patchedInputDir(b: *std.Build, io: std.Io, sdk_base: []const u8) ?std.Build.LazyPath {
    const real_path = b.fmt("{s}/applications/services/input/input.h", .{sdk_base});
    const content = std.Io.Dir.cwd().readFileAlloc(io, real_path, b.allocator, .unlimited) catch return null;

    const start = std.mem.indexOf(u8, content, "union {") orelse return null;
    var depth: i32 = 0;
    var seen_open = false;
    var end = start;
    while (end < content.len) : (end += 1) {
        switch (content[end]) {
            '{' => {
                depth += 1;
                seen_open = true;
            },
            '}' => depth -= 1,
            else => {},
        }
        if (seen_open and depth == 0) {
            end += 1;
            break;
        }
    }
    if (end < content.len and content[end] == ';') end += 1;

    var patched: std.ArrayList(u8) = .empty;
    patched.appendSlice(b.allocator, content[0..start]) catch return null;
    patched.appendSlice(b.allocator, "uint32_t sequence;") catch return null;
    patched.appendSlice(b.allocator, content[end..]) catch return null;

    const wf = b.addWriteFiles();
    _ = wf.add("input/input.h", patched.items);
    return wf.getDirectory();
}

fn cmdBuilder(alloc: std.mem.Allocator, cmd: []const []const u8, parts: []const []const u8) ![]const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;

    for (cmd) |part| {
        try result.append(alloc, part);
    }
    for (parts) |part| {
        try result.append(alloc, part);
    }

    return result.toOwnedSlice(alloc);
}

fn addFlipperIncludes(obj: *std.Build.Step.TranslateC, sdk_base: []const u8) void {
    const b = obj.step.owner;

    // Core SDK paths
    obj.addIncludePath(.{ .cwd_relative = sdk_base });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/furi", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/applications/services", .{sdk_base}) });

    // HAL paths
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/targets/furi_hal_include", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/targets/f7/ble_glue", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/targets/f7/furi_hal", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/targets/f7/inc", .{sdk_base}) });

    // Core library paths
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/mlib", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/cmsis_core", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/stm32wb_cmsis/Include", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/stm32wb_hal/Inc", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/stm32wb_copro/wpan", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/drivers", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/mbedtls/include", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/toolbox", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/libusb_stm32/inc", .{sdk_base}) });

    // Flipper-specific libraries
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/flipper_format", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/one_wire", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/ibutton", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/infrared/encoder_decoder", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/infrared/worker", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/subghz", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/nfc", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/digital_signal", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/pulse_reader", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/signal_reader", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/lfrfid", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/flipper_application", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/music_worker", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/mjs", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/nanopb", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/ble_profile", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/bit_lib", .{sdk_base}) });
    obj.addIncludePath(.{ .cwd_relative = b.fmt("{s}/lib/datetime", .{sdk_base}) });
}

fn addFlipperDefines(obj: *std.Build.Step.TranslateC) void {
    obj.defineCMacro("_GNU_SOURCE", "");
    obj.defineCMacro("FW_CFG_default", "");
    obj.defineCMacro("M_MEMORY_FULL(x)", "abort()");
    obj.defineCMacro("STM32WB", "");
    obj.defineCMacro("STM32WB55xx", "");
    obj.defineCMacro("USE_FULL_ASSERT", "");
    obj.defineCMacro("USE_FULL_LL_DRIVER", "");
    obj.defineCMacro("MBEDTLS_CONFIG_FILE", "\\\"mbedtls_cfg.h\\\"");
    obj.defineCMacro("PB_ENABLE_MALLOC", "");
    obj.defineCMacro("FW_ORIGIN_Official", "");
    obj.defineCMacro("FURI_NDEBUG", "");
    obj.defineCMacro("NDEBUG", "");
    obj.defineCMacro("FAP_VERSION", "\\\"1.0\\\"");
}
