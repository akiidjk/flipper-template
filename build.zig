const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m4 },
        .os_tag = .freestanding,
        .abi = .eabihf,
    });

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    const obj = b.addObject(.{
        .name = "app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    obj.root_module.unwind_tables = .none;

    // Get SDK path from $HOME/.ufbt
    const home = std.posix.getenv("HOME") orelse ".";
    const sdk_base = b.fmt("{s}/.ufbt/current/sdk_headers/f7_sdk", .{home});

    // Add ARM toolchain libc headers for @cImport
    const arm_libc_include = b.fmt("{s}/.ufbt/toolchain/arm64-darwin/arm-none-eabi/include", .{home});
    obj.addSystemIncludePath(.{ .cwd_relative = arm_libc_include });

    // Add Flipper SDK includes and defines
    addFlipperIncludes(obj, sdk_base);
    addFlipperDefines(obj);

    // Install the .o file
    const obj_install = b.addInstallBinFile(obj.getEmittedBin(), "app.o");
    b.getInstallStep().dependOn(&obj_install.step);

    const fap_step = b.step("fap", "Package the app into a .fap file");

    const run_ufbt = b.addSystemCommand(&[_][]const u8{ "python3", "-m", "ufbt" });
    run_ufbt.step.dependOn(&obj_install.step);
    fap_step.dependOn(&run_ufbt.step);

    // Create an "init" step that runs the setup script
    const init_step = b.step("init", "Initialize project with custom settings");
    const run_setup = b.addSystemCommand(&[_][]const u8{ "bash", "setup.sh" });
    init_step.dependOn(&run_setup.step);

    const launch_step = b.step("launch", "Launch the app on Flipper via UFBT");
    const run_launch = b.addSystemCommand(&[_][]const u8{ "python3", "-m", "ufbt", "launch" });
    run_launch.step.dependOn(&obj_install.step);
    launch_step.dependOn(&run_launch.step);
}

fn addFlipperIncludes(obj: *std.Build.Step.Compile, sdk_base: []const u8) void {
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

fn addFlipperDefines(obj: *std.Build.Step.Compile) void {
    obj.root_module.addCMacro("_GNU_SOURCE", "");
    obj.root_module.addCMacro("FW_CFG_default", "");
    obj.root_module.addCMacro("M_MEMORY_FULL(x)", "abort()");
    obj.root_module.addCMacro("STM32WB", "");
    obj.root_module.addCMacro("STM32WB55xx", "");
    obj.root_module.addCMacro("USE_FULL_ASSERT", "");
    obj.root_module.addCMacro("USE_FULL_LL_DRIVER", "");
    obj.root_module.addCMacro("MBEDTLS_CONFIG_FILE", "\\\"mbedtls_cfg.h\\\"");
    obj.root_module.addCMacro("PB_ENABLE_MALLOC", "");
    obj.root_module.addCMacro("FW_ORIGIN_Official", "");
    obj.root_module.addCMacro("FURI_NDEBUG", "");
    obj.root_module.addCMacro("NDEBUG", "");
    obj.root_module.addCMacro("FAP_VERSION", "\\\"1.0\\\"");
}
// reference
//
//     const target = b.standardTargetOptions(.{});

//     const optimize = b.standardOptimizeOption(.{});

//     const mod = b.addModule("flipper_template", .{
//         .root_source_file = b.path("src/root.zig"),

//         .target = target,
//     });

//     const exe = b.addExecutable(.{
//         .name = "flipper_template",
//         .root_module = b.createModule(.{
//             .root_source_file = b.path("src/main.zig"),

//             .target = target,
//             .optimize = optimize,

//             .imports = &.{
//                 .{ .name = "flipper_template", .module = mod },
//             },
//         }),
//     });

//     b.installArtifact(exe);

//     const run_step = b.step("run", "Run the app");

//     const run_cmd = b.addRunArtifact(exe);
//     run_step.dependOn(&run_cmd.step);

//     run_cmd.step.dependOn(b.getInstallStep());

//     if (b.args) |args| {
//         run_cmd.addArgs(args);
//     }
// }
