# Complete Guide: Building Flipper Zero Apps with Zig

This comprehensive guide will walk you through creating Flipper Zero applications using Zig programming language, from initial setup to deploying FAP files on your device.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Understanding the Architecture](#understanding-the-architecture)
3. [Project Setup](#project-setup)
4. [Writing Zig Code](#writing-zig-code)
5. [Creating the Build System](#creating-the-build-system)
6. [C Integration Layer](#c-integration-layer)
7. [Application Configuration](#application-configuration)
8. [Building the Project](#building-the-project)
9. [Deployment and Testing](#deployment-and-testing)
10. [Troubleshooting](#troubleshooting)
11. [Advanced Topics](#advanced-topics)

---

## Prerequisites

### Required Software

1. **ufbt (Micro Flipper Build Tool)**
   ```bash
   # Install ufbt
   python3 -m pip install --upgrade ufbt

   # Initialize ufbt and download SDK
   ufbt update
   ```

2. **Zig Compiler** (version 0.13.0 or later)
   ```bash
   # macOS (using Homebrew)
   brew install zig

   # Linux (download from ziglang.org)
   wget https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz
   tar xf zig-linux-x86_64-0.13.0.tar.xz
   sudo mv zig-linux-x86_64-0.13.0 /opt/zig
   export PATH=$PATH:/opt/zig

   # Verify installation
   zig version
   ```

3. **Flipper Zero Device** (optional, for testing)

### Verify ufbt Installation

```bash
# Check ufbt is working
ufbt --help

# Verify SDK location (should show ~/.ufbt/current/)
ls ~/.ufbt/current/sdk_headers/
```

---

## Understanding the Architecture

### Flipper Zero Hardware Specs

- **CPU**: ARM Cortex-M4 (STM32WB55xx)
- **Architecture**: Thumb-2 instruction set (`-mthumb`)
- **Float ABI**: Hardware floating point (`-mfloat-abi=hard -mfpu=fpv4-sp-d16`)
- **Optimization**: Size-optimized (`-Os`)
- **OS**: FreeRTOS-based firmware
- **App Format**: FAP (Flipper Application Package)

**Critical Compiler Flags** (from ufbt's compile_commands.json):
```
-mcpu=cortex-m4          # Target Cortex-M4 processor
-mfloat-abi=hard         # Use hardware floating point
-mfpu=fpv4-sp-d16        # FPU type
-mthumb                  # Use Thumb instruction set
-Os                      # Optimize for size
-nostdlib                # No standard library (bare metal)
-fdata-sections          # Place data in separate sections
-ffunction-sections      # Place functions in separate sections
```

### The Build Pipeline (Static Library Approach)

```
┌─────────────┐
│  Zig Code   │
│   (.zig)    │
└──────┬──────┘
       │
       │ zig build (cross-compile to ARM Cortex-M4)
       ▼
┌─────────────┐
│   Static    │
│  Library    │
│ libzigapp.a │
└──────┬──────┘
       │
       │ Referenced in application.fam
       ▼
┌─────────────┐     ┌──────────────┐
│  C Wrapper  │────▶│  ufbt build  │
│  (thin)     │     │   (SCons)    │
│ app_entry.c │     └──────┬───────┘
└─────────────┘            │
                           │ Compiles C → .o files
                           │ Links with libzigapp.a
                           │ Links with Flipper SDK libs
                           │ (libflipper7.a, libnfc.a, etc.)
                           ▼
                    ┌──────────────┐
                    │  FAP File    │
                    │  (.fap)      │
                    └──────────────┘
```

**How This Works**:
1. **Zig compiles to ARM**: Using target `thumb-freestanding-eabihf`, Zig produces a static library (`libzigapp.a`) containing ARM Cortex-M4 machine code
2. **C wrapper provides entry point**: A minimal C file (`app_entry.c`) serves as the FAP entry point and calls Zig functions
3. **application.fam links it all**: The `fap_libs` parameter tells ufbt to link your Zig library
4. **ufbt handles final linking**: SCons invokes `arm-none-eabi-gcc` to:
   - Compile the C wrapper to `.o` files
   - Link `.o` files with `libzigapp.a`
   - Link with 33 Flipper SDK libraries
   - Use linker script `application_ext.ld`
   - Create the final `.fap` file

**Why Static Library?**
- ✓ No ufbt modification needed
- ✓ Clean separation between Zig and C code
- ✓ Can incrementally migrate C projects to Zig
- ✓ Compatible with ufbt's existing build system

---

## Project Setup

### Directory Structure

Create your project with this structure:

```
my_zig_flipper_app/
├── application.fam          # App manifest for ufbt
├── app_entry.c              # C entry point (thin wrapper)
├── app_entry.h              # C header for exported functions
├── icon.png                 # App icon (10x10px)
├── Makefile                 # Build automation (optional)
├── README.md
└── zig/                     # Zig source directory
    ├── build.zig            # Zig build configuration
    ├── build.zig.zon        # Zig package manifest (optional)
    └── src/
        ├── main.zig         # Main Zig code
        ├── flipper.zig      # Flipper SDK C bindings
        └── app_logic.zig    # Your application logic
```

### Create the Project

```bash
# Create project directory
mkdir my_zig_flipper_app
cd my_zig_flipper_app

# Create subdirectories
mkdir -p zig/src

# Create empty files
touch application.fam
touch app_entry.c
touch app_entry.h
touch zig/build.zig
touch zig/src/main.zig
touch zig/src/flipper.zig

# Create placeholder icon (10x10 white square)
# You can create a proper icon later
```

---

## Writing Zig Code

### 1. Flipper SDK Bindings (`zig/src/flipper.zig`)

This file provides Zig-friendly wrappers around Flipper's C API:

```zig
// zig/src/flipper.zig
const std = @import("std");

// Import Flipper SDK C headers
pub const c = @cImport({
    @cInclude("furi.h");
    @cInclude("furi_hal.h");
    @cInclude("gui/gui.h");
    @cInclude("gui/view.h");
    @cInclude("gui/view_dispatcher.h");
    @cInclude("gui/modules/submenu.h");
    @cInclude("gui/modules/widget.h");
    @cInclude("gui/canvas.h");
    @cInclude("input/input.h");
    @cInclude("notification/notification_messages.h");
});

// Zig-friendly wrappers

/// Log levels matching Flipper's FuriLogLevel
pub const LogLevel = enum(c_int) {
    None = 0,
    Error = 1,
    Warn = 2,
    Info = 3,
    Debug = 4,
    Trace = 5,
};

/// Log a message to Flipper's console
pub fn log(level: LogLevel, comptime fmt: []const u8, args: anytype) void {
    // Convert format string to C string at comptime
    const c_fmt = fmt ++ "\x00";

    // Use Flipper's logging function
    const level_int: c_int = @intFromEnum(level);
    _ = c.furi_log_print_format(level_int, "ZigApp", c_fmt.ptr, args);
}

/// Delay execution for specified milliseconds
pub fn delay(ms: u32) void {
    c.furi_delay_ms(ms);
}

/// Get current tick count
pub fn getTick() u32 {
    return c.furi_get_tick();
}

/// Allocate memory using Flipper's allocator
pub fn alloc(size: usize) ?*anyopaque {
    return c.malloc(size);
}

/// Free memory allocated by alloc()
pub fn free(ptr: ?*anyopaque) void {
    if (ptr) |p| {
        c.free(p);
    }
}

/// Canvas drawing functions
pub const Canvas = struct {
    ptr: *c.Canvas,

    pub fn clear(self: Canvas) void {
        c.canvas_clear(self.ptr);
    }

    pub fn setColor(self: Canvas, color: Color) void {
        c.canvas_set_color(self.ptr, @intFromEnum(color));
    }

    pub fn drawStr(self: Canvas, x: u8, y: u8, text: [*:0]const u8) void {
        c.canvas_draw_str(self.ptr, x, y, text);
    }

    pub fn drawBox(self: Canvas, x: u8, y: u8, width: u8, height: u8) void {
        c.canvas_draw_box(self.ptr, x, y, width, height);
    }

    pub fn drawFrame(self: Canvas, x: u8, y: u8, width: u8, height: u8) void {
        c.canvas_draw_frame(self.ptr, x, y, width, height);
    }

    pub fn setFont(self: Canvas, font: Font) void {
        c.canvas_set_font(self.ptr, @intFromEnum(font));
    }
};

pub const Color = enum(c_int) {
    White = 0,
    Black = 1,
};

pub const Font = enum(c_int) {
    Primary = 0,
    Secondary = 1,
    Keyboard = 2,
    BigNumbers = 3,
};

/// Input key types
pub const InputKey = enum(c_int) {
    Up = 0,
    Down = 1,
    Right = 2,
    Left = 3,
    Ok = 4,
    Back = 5,
};

/// Input event types
pub const InputType = enum(c_int) {
    Press = 0,
    Release = 1,
    Short = 2,
    Long = 3,
    Repeat = 4,
};

pub const InputEvent = struct {
    key: InputKey,
    type: InputType,
};
```

### 2. Application Logic (`zig/src/app_logic.zig`)

Example: A simple counter app

```zig
// zig/src/app_logic.zig
const std = @import("std");
const flipper = @import("flipper.zig");

pub const AppState = struct {
    counter: i32 = 0,

    pub fn init() AppState {
        flipper.log(.Info, "App initialized", .{});
        return AppState{};
    }

    pub fn increment(self: *AppState) void {
        self.counter += 1;
        flipper.log(.Debug, "Counter: %d", .{self.counter});
    }

    pub fn decrement(self: *AppState) void {
        self.counter -= 1;
        flipper.log(.Debug, "Counter: %d", .{self.counter});
    }

    pub fn reset(self: *AppState) void {
        self.counter = 0;
        flipper.log(.Info, "Counter reset", .{});
    }

    pub fn getCounter(self: *const AppState) i32 {
        return self.counter;
    }
};

/// Draw callback for the canvas
pub fn drawCallback(canvas_ptr: ?*flipper.c.Canvas, context: ?*anyopaque) callconv(.C) void {
    if (canvas_ptr == null or context == null) return;

    const canvas = flipper.Canvas{ .ptr = canvas_ptr.? };
    const app_state: *AppState = @ptrCast(@alignCast(context.?));

    canvas.clear();
    canvas.setColor(.Black);
    canvas.setFont(.Primary);

    // Draw title
    canvas.drawStr(30, 10, "Zig Counter");

    // Draw counter value
    var buffer: [32]u8 = undefined;
    const counter_str = std.fmt.bufPrintZ(&buffer, "Count: {d}", .{app_state.counter}) catch "Error";
    canvas.drawStr(25, 35, counter_str.ptr);

    // Draw instructions
    canvas.setFont(.Secondary);
    canvas.drawStr(10, 55, "UP: +1  DOWN: -1  OK: Reset");
}

/// Input callback for handling button presses
pub fn inputCallback(event_ptr: ?*flipper.c.InputEvent, context: ?*anyopaque) callconv(.C) bool {
    if (event_ptr == null or context == null) return false;

    const event = event_ptr.?;
    const app_state: *AppState = @ptrCast(@alignCast(context.?));

    if (event.type == flipper.c.InputTypeShort) {
        switch (event.key) {
            flipper.c.InputKeyUp => app_state.increment(),
            flipper.c.InputKeyDown => app_state.decrement(),
            flipper.c.InputKeyOk => app_state.reset(),
            flipper.c.InputKeyBack => return false, // Exit app
            else => {},
        }
    }

    return true;
}
```

### 3. Main Entry Point (`zig/src/main.zig`)

Export functions that will be called from C:

```zig
// zig/src/main.zig
const std = @import("std");
const flipper = @import("flipper.zig");
const app_logic = @import("app_logic.zig");

// Export draw callback
comptime {
    @export(app_logic.drawCallback, .{ .name = "zig_draw_callback", .linkage = .strong });
    @export(app_logic.inputCallback, .{ .name = "zig_input_callback", .linkage = .strong });
}

/// Initialize the app state (called from C)
export fn zig_app_init() ?*anyopaque {
    flipper.log(.Info, "Initializing Zig app", .{});

    const state = flipper.alloc(@sizeOf(app_logic.AppState)) orelse {
        flipper.log(.Error, "Failed to allocate app state", .{});
        return null;
    };

    const app_state: *app_logic.AppState = @ptrCast(@alignCast(state));
    app_state.* = app_logic.AppState.init();

    return state;
}

/// Cleanup the app state (called from C)
export fn zig_app_deinit(context: ?*anyopaque) void {
    if (context) |ctx| {
        flipper.log(.Info, "Cleaning up Zig app", .{});
        flipper.free(ctx);
    }
}

/// Get the draw callback function pointer
export fn zig_get_draw_callback() ?*const fn (?*flipper.c.Canvas, ?*anyopaque) callconv(.C) void {
    return &app_logic.drawCallback;
}

/// Get the input callback function pointer
export fn zig_get_input_callback() ?*const fn (?*flipper.c.InputEvent, ?*anyopaque) callconv(.C) bool {
    return &app_logic.inputCallback;
}
```

---

## Creating the Build System

### Zig Build Configuration (`zig/build.zig`)

This is the heart of the Zig build system. The configuration below matches exactly what ufbt uses (extracted from compile_commands.json):

```zig
// zig/build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    // Target configuration for Flipper Zero (ARM Cortex-M4)
    // Matches ufbt flags: -mcpu=cortex-m4 -mfloat-abi=hard -mfpu=fpv4-sp-d16 -mthumb
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m4 },
        .os_tag = .freestanding,
        .abi = .eabihf, // Hardware floating point
    });

    // Optimize for size (matches ufbt's -Os flag)
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    // Create static library
    const lib = b.addStaticLibrary(.{
        .name = "zigapp",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add Flipper SDK include paths
    // NOTE: Adjust the path if your ufbt installation is elsewhere
    const sdk_base = b.pathFromRoot(std.fs.path.expandHome(
        b.allocator,
        "~/.ufbt/current/sdk_headers/f7_sdk"
    ) catch @panic("Failed to expand SDK path"));

    addFlipperIncludes(lib, sdk_base);

    // Add preprocessor defines (matching ufbt)
    addFlipperDefines(lib);

    // Install the library
    b.installArtifact(lib);
}

fn addFlipperIncludes(lib: *std.Build.Step.Compile, sdk_base: []const u8) void {
    const b = lib.step.owner;

    // Core SDK paths
    lib.addIncludePath(b.path(sdk_base));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "furi" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "applications/services" })));

    // HAL paths
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "targets/furi_hal_include" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "targets/f7/ble_glue" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "targets/f7/furi_hal" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "targets/f7/inc" })));

    // Core library paths
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/mlib" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/cmsis_core" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/stm32wb_cmsis/Include" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/stm32wb_hal/Inc" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/stm32wb_copro/wpan" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/drivers" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/mbedtls/include" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/toolbox" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/libusb_stm32/inc" })));

    // Flipper-specific libraries
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/flipper_format" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/one_wire" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/ibutton" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/infrared/encoder_decoder" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/infrared/worker" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/subghz" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/nfc" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/digital_signal" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/pulse_reader" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/signal_reader" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/lfrfid" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/flipper_application" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/music_worker" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/mjs" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/nanopb" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/ble_profile" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/bit_lib" })));
    lib.addIncludePath(b.path(b.pathJoin(&.{ sdk_base, "lib/datetime" })));
}

fn addFlipperDefines(lib: *std.Build.Step.Compile) void {
    // All defines from ufbt's compile_commands.json
    lib.defineCMacro("_GNU_SOURCE", null);
    lib.defineCMacro("FW_CFG_default", null);
    lib.defineCMacro("M_MEMORY_FULL(x)", "abort()");
    lib.defineCMacro("STM32WB", null);
    lib.defineCMacro("STM32WB55xx", null);
    lib.defineCMacro("USE_FULL_ASSERT", null);
    lib.defineCMacro("USE_FULL_LL_DRIVER", null);
    lib.defineCMacro("MBEDTLS_CONFIG_FILE", "\"mbedtls_cfg.h\"");
    lib.defineCMacro("PB_ENABLE_MALLOC", null);
    lib.defineCMacro("FW_ORIGIN_Official", null);
    lib.defineCMacro("FURI_NDEBUG", null);
    lib.defineCMacro("NDEBUG", null);
    lib.defineCMacro("FAP_VERSION", "\"1.0\"");
}
```

**Important Notes**:
- The include paths and defines above match ufbt SDK version 1.3.4
- To verify settings for your ufbt version:
  1. Run `ufbt` in any project directory
  2. Open `.vscode/compile_commands.json` that gets generated
  3. Check the `-I` flags for include paths
  4. Check the `-D` flags for preprocessor defines
- SDK path may differ on Windows: `C:\Users\<username>\.ufbt\current\sdk_headers\f7_sdk`

---

## C Integration Layer

### C Header (`app_entry.h`)

Define the interface between C and Zig:

```c
// app_entry.h
#pragma once

#include <furi.h>
#include <gui/gui.h>
#include <gui/view.h>
#include <input/input.h>

// Forward declarations for Zig-exported functions
void* zig_app_init(void);
void zig_app_deinit(void* context);
void zig_draw_callback(Canvas* canvas, void* context);
bool zig_input_callback(InputEvent* event, void* context);
```

### C Entry Point (`app_entry.c`)

This is the minimal C glue code that ufbt will compile:

```c
// app_entry.c
#include "app_entry.h"
#include <furi.h>
#include <gui/gui.h>
#include <gui/view.h>
#include <gui/view_dispatcher.h>

typedef struct {
    Gui* gui;
    ViewDispatcher* view_dispatcher;
    View* main_view;
    void* zig_context;
} App;

static App* app_alloc(void) {
    App* app = malloc(sizeof(App));

    // Initialize Zig app state
    app->zig_context = zig_app_init();
    if (!app->zig_context) {
        free(app);
        return NULL;
    }

    // Setup GUI
    app->gui = furi_record_open(RECORD_GUI);
    app->view_dispatcher = view_dispatcher_alloc();
    view_dispatcher_attach_to_gui(app->view_dispatcher, app->gui, ViewDispatcherTypeFullscreen);

    // Create main view with Zig callbacks
    app->main_view = view_alloc();
    view_set_context(app->main_view, app->zig_context);
    view_set_draw_callback(app->main_view, zig_draw_callback);
    view_set_input_callback(app->main_view, zig_input_callback);

    view_dispatcher_add_view(app->view_dispatcher, 0, app->main_view);
    view_dispatcher_switch_to_view(app->view_dispatcher, 0);

    return app;
}

static void app_free(App* app) {
    if (!app) return;

    view_dispatcher_remove_view(app->view_dispatcher, 0);
    view_free(app->main_view);
    view_dispatcher_free(app->view_dispatcher);
    furi_record_close(RECORD_GUI);

    zig_app_deinit(app->zig_context);
    free(app);
}

int32_t zig_flipper_app(void* p) {
    UNUSED(p);

    App* app = app_alloc();
    if (!app) {
        return -1;
    }

    view_dispatcher_run(app->view_dispatcher);

    app_free(app);
    return 0;
}
```

---

## Application Configuration

### Application Manifest (`application.fam`)

This tells ufbt how to build your app:

```python
# application.fam
App(
    appid="zig_flipper_app",                    # Unique app ID
    name="Zig Counter",                          # Display name in menu
    apptype=FlipperAppType.EXTERNAL,             # External app (FAP)
    entry_point="zig_flipper_app",               # C entry function name
    stack_size=2 * 1024,                         # 2KB stack

    # Source files (C wrapper only)
    sources=[
        "app_entry.c",
    ],

    # Static libraries (our Zig-compiled library)
    fap_libs=[
        "zig/zig-out/lib/libzigapp.a",
    ],

    # Icons
    fap_icon="icon.png",                         # 10x10 PNG icon
    fap_category="Tools",                        # Category in app menu

    # Version info
    fap_version="1.0",
    fap_description="Counter app written in Zig",
    fap_author="Your Name",
    fap_weburl="https://github.com/yourusername/zig-flipper-app",

    # Required SDK features (uncomment if needed)
    # requires=[
    #     "gui",
    #     "storage",
    #     "notification",
    # ],

    # API version compatibility
    # fap_api_version="1.0",
)
```

### Important application.fam Notes

1. **appid**: Must be unique across all Flipper apps
2. **entry_point**: Must match your C function name (e.g., `int32_t zig_flipper_app(void* p)`)
3. **fap_libs**: Path to Zig-compiled static library (relative to application.fam)
   - Path is relative to where application.fam is located
   - Must be built before running ufbt
   - Can include multiple `.a` files if needed: `fap_libs=["zig/libzig1.a", "zig/libzig2.a"]`
4. **stack_size**: Adjust based on your app's needs (2-4KB typical)
5. **fap_icon**: Must be 10x10 pixels, 1-bit PNG

**What ufbt does with fap_libs**:
- Passes each `.a` file to `arm-none-eabi-gcc` during linking
- Links them alongside Flipper's SDK libraries
- Resolves symbols exported from Zig (functions with `export` keyword)

---

## Building the Project

### Manual Build Process

#### Step 1: Build Zig Library

```bash
cd zig
zig build

# Verify the library was created
ls -lh zig-out/lib/libzigapp.a
```

#### Step 2: Build FAP with ufbt

```bash
cd ..  # Back to project root
ufbt

# This will:
# 1. Compile app_entry.c to .o file using arm-none-eabi-gcc
# 2. Link .o files with libzigapp.a and SDK libraries
# 3. Create the .fap file
```

**What ufbt does behind the scenes**:
```bash
# 1. Compiles your C files
arm-none-eabi-gcc -o ~/.ufbt/build/zig_flipper_app/app_entry.o -c \
  -mcpu=cortex-m4 -mfloat-abi=hard -mfpu=fpv4-sp-d16 -mthumb \
  -Os -g -nostdlib \
  -I~/.ufbt/current/sdk_headers/f7_sdk \
  [... all SDK includes ...] \
  -DSTM32WB55xx -DFURI_NDEBUG [... all defines ...] \
  app_entry.c

# 2. Links everything together
arm-none-eabi-gcc -o ~/.ufbt/build/zig_flipper_app/zig_flipper_app_d.elf \
  app_entry.o \
  zig/zig-out/lib/libzigapp.a \
  ~/.ufbt/current/lib/libflipper7.a \
  ~/.ufbt/current/lib/libnfc.a \
  [... 33 SDK libraries ...] \
  -T ~/.ufbt/current/sdk_headers/f7_sdk/targets/f7/application_ext.ld

# 3. Strips and creates FAP
arm-none-eabi-objcopy [...strip debug...] -o zig_flipper_app.fap
```

#### Step 3: Check Build Output

```bash
# FAP file location
ls -lh ~/.ufbt/build/zig_flipper_app/zig_flipper_app.fap

# View build artifacts
ls ~/.ufbt/build/zig_flipper_app/
```

### Automated Build with Makefile

Create a `Makefile` for convenience:

```makefile
# Makefile
.PHONY: all build clean zig launch install

all: build

# Build everything
build: zig
	@echo "Building FAP with ufbt..."
	ufbt

# Build only Zig library
zig:
	@echo "Building Zig library..."
	cd zig && zig build

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -rf zig/zig-out
	rm -rf zig/.zig-cache
	ufbt clean

# Build and launch on device
launch: build
	@echo "Launching app on device..."
	ufbt launch

# Build and install to device
install: build
	@echo "Installing app to device..."
	ufbt install

# Flash via USB
flash: build
	@echo "Flashing app via USB..."
	ufbt flash_usb

# View logs
logs:
	@echo "Opening serial console..."
	ufbt cli

# Help
help:
	@echo "Available targets:"
	@echo "  make build   - Build Zig library and FAP"
	@echo "  make zig     - Build only Zig library"
	@echo "  make clean   - Clean build artifacts"
	@echo "  make launch  - Build and launch on device"
	@echo "  make install - Build and install to device"
	@echo "  make flash   - Flash app via USB"
	@echo "  make logs    - Open serial console"
```

Usage:

```bash
# Build everything
make

# Build and run on device
make launch

# Clean and rebuild
make clean
make build
```

---

## Deployment and Testing

### Deploy to Flipper Zero

#### Method 1: USB Upload (Recommended)

```bash
# Connect Flipper via USB
ufbt launch

# Or manually copy
ufbt install
```

This installs the FAP to `/ext/apps/Tools/zig_flipper_app.fap` on your Flipper.

#### Method 2: SD Card

```bash
# Copy FAP to SD card
cp ~/.ufbt/build/zig_flipper_app/zig_flipper_app.fap /path/to/sdcard/apps/Tools/

# Eject SD card and insert into Flipper
# Navigate to: Applications -> Tools -> Zig Counter
```

#### Method 3: qFlipper

1. Open qFlipper application
2. Connect Flipper via USB
3. Go to "File Manager"
4. Navigate to `SD Card/apps/Tools/`
5. Upload `zig_flipper_app.fap`

### Testing and Debugging

#### View Logs

```bash
# Connect to serial console
ufbt cli

# You'll see logs from your Zig app
# (The flipper.log() calls will appear here)
```

#### Common Issues

**App crashes immediately**:
- Check stack size in `application.fam` (increase to 4KB)
- Verify all callbacks return proper values
- Look for null pointer dereferences

**Linking errors**:
- Ensure Zig library path in `application.fam` is correct
- Rebuild Zig library: `cd zig && zig build`
- Check exported function names match C declarations

**App not appearing in menu**:
- Verify icon is 10x10 pixels
- Check `fap_category` in `application.fam`
- Ensure file is in correct directory on SD card

---

## Troubleshooting

### Build Issues

#### Error: "ufbt: command not found"

```bash
# Reinstall ufbt
python3 -m pip install --upgrade ufbt
ufbt update
```

#### Error: "SDK not found"

```bash
# Download SDK
ufbt update

# Verify SDK location
ls ~/.ufbt/current/sdk_headers/
```

#### Error: Zig library not found

```bash
# Check library exists
ls zig/zig-out/lib/libzigapp.a

# Rebuild if missing
cd zig && zig build
```

#### Error: Undefined reference to `zig_xxx`

This means the C code can't find your Zig exports.

**Solution**:
1. Verify exports in `main.zig` use `export` keyword
2. Check function signatures match C declarations
3. Ensure callconv(.C) is specified

```zig
// Correct:
export fn zig_app_init() ?*anyopaque { ... }

// Incorrect (missing export):
fn zig_app_init() ?*anyopaque { ... }
```

### Runtime Issues

#### App crashes on startup

**Check logs**:
```bash
ufbt cli
# Look for FAULT or panic messages
```

**Common causes**:
- Stack overflow (increase `stack_size` in application.fam)
- Invalid memory access (check pointer casting)
- Missing null checks

#### Callbacks not working

**Verify callback signatures**:
```zig
// Draw callback
export fn zig_draw_callback(
    canvas: ?*c.Canvas,
    context: ?*anyopaque
) callconv(.C) void { ... }

// Input callback (must return bool)
export fn zig_input_callback(
    event: ?*c.InputEvent,
    context: ?*anyopaque
) callconv(.C) bool { ... }
```

#### Display issues

- Ensure Canvas functions are called correctly
- Check coordinates are within bounds (0-127 for X, 0-63 for Y)
- Verify color is set before drawing
- Clear canvas at start of draw callback

### Zig Compilation Issues

#### Error: Can't find furi.h

Your include paths are incorrect.

**Solution**:
```zig
// In build.zig, verify SDK path
const sdk_path = "~/.ufbt/current/sdk_headers/f7_sdk";

// Or use environment variable
const sdk_path = std.process.getEnvVarOwned(
    b.allocator,
    "UFBT_SDK_PATH"
) catch "~/.ufbt/current/sdk_headers/f7_sdk";
```

#### Error: @cImport failed

**Check**:
1. All include paths are added before @cImport
2. Headers exist at specified paths
3. No circular includes in headers

**Debug**:
```bash
# List available headers
ls ~/.ufbt/current/sdk_headers/f7_sdk/furi/

# Test include path
zig build --verbose
```

---

## Advanced Topics

### Memory Management

Flipper uses a custom allocator. Always use Flipper's malloc/free:

```zig
// Correct: Use Flipper's allocator
const ptr = flipper.c.malloc(size);
defer flipper.c.free(ptr);

// Incorrect: Don't use Zig's std.heap
// const allocator = std.heap.page_allocator; // DON'T DO THIS
```

### Using Zig Standard Library

The Zig standard library works in freestanding mode, but avoid:
- File I/O (use Flipper's storage API instead)
- Networking (Flipper doesn't have it)
- Threading (use Flipper's FuriThread)

**Safe to use**:
- `std.fmt` for formatting
- `std.mem` for memory operations
- `std.math` for mathematics
- `std.ArrayList` and other data structures (with Flipper's allocator)

### Custom Allocator Integration

Wrap Flipper's allocator for use with Zig collections:

```zig
// zig/src/flipper.zig
pub const FlipperAllocator = struct {
    pub fn allocator() std.mem.Allocator {
        return .{
            .ptr = undefined,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(
        _: *anyopaque,
        len: usize,
        ptr_align: u8,
        ret_addr: usize,
    ) ?[*]u8 {
        _ = ptr_align;
        _ = ret_addr;
        const ptr = c.malloc(len);
        return @ptrCast(ptr);
    }

    fn resize(
        _: *anyopaque,
        buf: []u8,
        buf_align: u8,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false; // Flipper doesn't support resize
    }

    fn free(
        _: *anyopaque,
        buf: []u8,
        buf_align: u8,
        ret_addr: usize,
    ) void {
        _ = buf_align;
        _ = ret_addr;
        c.free(buf.ptr);
    }
};

// Usage:
const allocator = FlipperAllocator.allocator();
var list = std.ArrayList(i32).init(allocator);
defer list.deinit();
```

### Using More Flipper Features

#### Storage (Reading/Writing Files)

```zig
pub const Storage = struct {
    ptr: *c.Storage,

    pub fn open() !Storage {
        const storage = c.furi_record_open("storage");
        if (storage == null) return error.StorageNotAvailable;
        return Storage{ .ptr = @ptrCast(storage) };
    }

    pub fn close(self: Storage) void {
        c.furi_record_close("storage");
    }
};
```

#### Notifications (LED, Vibration)

```zig
pub fn notifySuccess() void {
    const notify = c.furi_record_open("notification");
    defer c.furi_record_close("notification");

    c.notification_message(notify, &c.sequence_success);
}
```

#### SubGHz Radio

```zig
// Include in flipper.zig @cImport
@cInclude("lib/subghz/subghz_tx_rx_worker.h");
@cInclude("lib/subghz/devices/devices.h");

// Then use SubGHz API
```

### Multi-File Zig Projects

Organize larger projects:

```
zig/src/
├── main.zig              # Entry point, exports
├── flipper.zig           # SDK bindings
├── app.zig               # Main app logic
├── views/
│   ├── main_view.zig
│   └── settings_view.zig
├── models/
│   └── app_state.zig
└── utils/
    ├── storage.zig
    └── helpers.zig
```

Import in `main.zig`:
```zig
const app = @import("app.zig");
const main_view = @import("views/main_view.zig");
const storage = @import("utils/storage.zig");
```

### GUI View System

For multi-screen apps:

```c
// app_entry.c - Multiple views
typedef struct {
    Gui* gui;
    ViewDispatcher* view_dispatcher;
    View* main_view;
    View* settings_view;
    void* zig_context;
} App;

// In app_alloc():
app->settings_view = view_alloc();
view_set_context(app->settings_view, app->zig_context);
view_set_draw_callback(app->settings_view, zig_settings_draw_callback);
view_set_input_callback(app->settings_view, zig_settings_input_callback);

view_dispatcher_add_view(app->view_dispatcher, 0, app->main_view);
view_dispatcher_add_view(app->view_dispatcher, 1, app->settings_view);

// Switch views:
view_dispatcher_switch_to_view(app->view_dispatcher, 1); // Go to settings
```

### Debugging with GDB

```bash
# Build with debug symbols
cd zig && zig build -Doptimize=Debug

# Start GDB session
ufbt debug
```

In GDB:
```gdb
# Set breakpoint in C code
break app_entry.c:50

# Set breakpoint in Zig code (if symbols available)
break zig_app_init

# Continue execution
continue

# Inspect Zig variables (may need debug info)
print app_state
```

### Performance Optimization

1. **Use ReleaseSmall for size**: FAPs have size limits
   ```zig
   const optimize = .ReleaseSmall;
   ```

2. **Avoid allocations in draw callbacks**: Pre-allocate buffers

3. **Profile with tick counts**:
   ```zig
   const start = flipper.getTick();
   // ... your code ...
   const elapsed = flipper.getTick() - start;
   flipper.log(.Debug, "Took %d ticks", .{elapsed});
   ```

4. **Check generated assembly**:
   ```bash
   zig build-lib -target thumb-freestanding-eabihf \
     -mcpu=cortex_m4 --emit asm=output.s src/main.zig
   ```

---

## Example Projects

### Minimal Hello World

See the code examples above for a complete counter app.

### More Complex Example: Multi-Screen App

```zig
// zig/src/app.zig
pub const Screen = enum {
    Main,
    Settings,
    About,
};

pub const AppState = struct {
    current_screen: Screen = .Main,
    counter: i32 = 0,
    settings_value: u8 = 10,

    pub fn switchScreen(self: *AppState, screen: Screen) void {
        self.current_screen = screen;
    }
};
```

Export multiple draw callbacks for different screens.

---

## Resources

### Documentation

- **Flipper Zero Docs**: https://docs.flipper.net/
- **Zig Documentation**: https://ziglang.org/documentation/master/
- **ufbt GitHub**: https://github.com/flipperdevices/flipperzero-ufbt

### Community

- **Flipper Zero Discord**: https://flipperzero.one/discord
- **Zig Discord**: https://discord.gg/zig
- **r/flipperzero**: https://reddit.com/r/flipperzero

### Example Code

- **Official Flipper Apps**: https://github.com/flipperdevices/flipperzero-firmware/tree/dev/applications
- **Community Apps**: https://github.com/flipperdevices/flipperzero-good-faps

---

## Conclusion

You now have a complete guide to building Flipper Zero applications with Zig! The key points:

1. **Zig compiles to a static library** (`.a`)
2. **Thin C wrapper** provides entry point
3. **ufbt links everything** and creates FAP
4. **Use @cImport** for Flipper SDK access
5. **Export with `export` keyword** for C visibility

Start with the simple counter example, then expand to more complex applications. The combination of Zig's safety features and Flipper's hardware capabilities opens up many possibilities.

Happy hacking!

---

## Appendix: Quick Reference

### Essential Commands

```bash
# Build
cd zig && zig build
ufbt

# Deploy
ufbt launch

# Debug
ufbt cli

# Clean
make clean
```

### Key File Checklist

- [ ] `application.fam` - Configured with correct paths
- [ ] `zig/build.zig` - Target and includes configured
- [ ] `zig/src/main.zig` - Functions exported
- [ ] `app_entry.c` - Calls Zig functions
- [ ] `app_entry.h` - Declares Zig functions
- [ ] `icon.png` - 10x10 pixels
- [ ] Zig library built: `zig/zig-out/lib/libzigapp.a`

### Common Zig Export Signatures

```zig
// Init function
export fn zig_app_init() ?*anyopaque

// Deinit function
export fn zig_app_deinit(context: ?*anyopaque) void

// Draw callback
export fn zig_draw_callback(
    canvas: ?*c.Canvas,
    context: ?*anyopaque
) callconv(.C) void

// Input callback
export fn zig_input_callback(
    event: ?*c.InputEvent,
    context: ?*anyopaque
) callconv(.C) bool
```

### Flipper Canvas Coordinates

- **Width**: 128 pixels (0-127)
- **Height**: 64 pixels (0-63)
- **Origin**: Top-left (0, 0)
- **Color**: 1-bit (Black/White)

---

**Version**: 1.0
**Last Updated**: October 2024
**Zig Version**: 0.13.0
**Flipper Firmware**: 1.x (tested on 1.3.4)
