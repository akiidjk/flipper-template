# Building Flipper Zero apps with Zig 0.17.1

## Prerequisites

Install [Zig 0.17.1](https://ziglang.org/download/), Python 3 and UFBT:

```bash
python3 -m pip install --upgrade ufbt
ufbt update
zig version # Expected: 0.17.1
```

UFBT installs the SDK under `~/.ufbt/current/sdk_headers/f7_sdk` and the ARM
compiler under `~/.ufbt/toolchain`. A Flipper Zero is required only for deployment
and runtime testing.

## Build and package

Run commands from the repository root:

```bash
zig build init # Interactive app metadata setup; writes application.fam
zig build      # Compile zig-out/bin/app.o
zig build fap  # Compile and package with python3 -m ufbt
```

`build.zig` targets `thumb-freestanding-eabihf` with a Cortex-M4 CPU. It installs
an object file, which `application.fam` passes to UFBT for linking and packaging.
No C entry-point wrapper or separate static library is required.

The default build uses Debug. To use the preferred ReleaseSmall mode:

```bash
zig build -Drelease=true
```

## SDK imports and callbacks

Add C headers to `src/flipper.h`. The build translates these headers into a Zig
module, available in `src/root.zig` as:

```zig
const flipper = @import("flipper");
```

The build uses `b.graph.io` and `std.Io.Dir` to read SDK headers. It generates
patched copies of `m-core.h` and `input/input.h` for C translation without editing
the installed SDK. The patches remove unsupported diagnostic pragmas and replace
the input event's bitfield union with its `uint32_t sequence` member.

Keep exported functions compatible with the SDK's ARM calling conventions:

```zig
export fn start(_: ?*anyopaque) callconv(.{ .arm_aapcs = .{} }) i32
export fn draw_callback(canvas: ?*flipper.Canvas, context: ?*anyopaque) callconv(.{ .arm_aapcs_vfp = .{} }) void
export fn input_callback(event: ?*flipper.InputEvent, context: ?*anyopaque) callconv(.{ .arm_aapcs_vfp = .{} }) void
```

See `src/root.zig` for the complete viewport setup and thread-flag wait. Use
Flipper APIs for allocation, storage and threading on the freestanding target.

## Deploy and troubleshoot

After packaging, connect an unlocked Flipper Zero over USB and run:

```bash
python3 -m ufbt launch
```

If `furi.h` is missing, run `ufbt update` and check the SDK path. If standard C
headers are missing, check that the ARM toolchain is installed for the host
architecture and operating system detected by `build.zig`.

A successful build verifies compilation and packaging. Check drawing, input and
exit behavior on the device before distributing a FAP.

## Memory management

Use Flipper's allocator for dynamic memory and release each allocation when its
owner finishes using it. Check allocation failures before dereferencing pointers:

```zig
const flipper = @import("flipper");

fn useBuffer(size: usize) !void {
    const ptr = flipper.malloc(size) orelse return error.OutOfMemory;
    defer flipper.free(ptr);
    const bytes: [*]u8 = @ptrCast(ptr);
    @memset(bytes[0..size], 0);
    // Use bytes[0..size] while ptr is alive.
}
```

Keep callback state alive until the viewport or view has been removed and its
callbacks can no longer access it. Avoid allocating in draw callbacks; allocate
state and buffers during initialization instead. Large local buffers consume the
app thread's stack, whose size is configured by `stack_size` in `application.fam`.

### Using the Zig standard library

Use `std.fmt` for formatting, `std.mem` for memory operations and `std.math` for
calculations. Collections such as `std.ArrayList` require an allocator. Use the
Flipper storage and thread APIs for file access and concurrency. OS-backed Zig
allocators such as `std.heap.page_allocator` are unsuitable for this freestanding
target.

### Allocator integration

For a bounded collection, `std.heap.FixedBufferAllocator` lets Zig collections
use an existing buffer without a custom allocator implementation:

```zig
const std = @import("std");

fn useCollection() !void {
    var buffer: [256]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fixed.allocator();
    var list: std.ArrayList(u32) = .empty;
    defer list.deinit(allocator);
    try list.append(allocator, 42);
}
```

The buffer must outlive the allocator and all allocations made through it. This
example uses stack memory and returns `error.OutOfMemory` when the buffer fills.
A longer-lived buffer can come from Flipper's heap; free it only after all users
have finished. A general adapter around Flipper's heap must implement the Zig
0.17.1 allocator interface, including alignment requirements and resize/remap
behavior. A plain cast of `malloc` is insufficient for over-aligned allocations.

## GUI view system

The template's single-screen UI uses a `ViewPort`. See `src/root.zig` for drawing,
input callbacks, registration with the GUI and cleanup. Canvas coordinates run
from 0 to 127 horizontally and 0 to 63 vertically. Clear the canvas before drawing
and select the font and color before rendering text or shapes.

For multiple screens, use `View` and `ViewDispatcher`. Add their headers to
`src/flipper.h`:

```c
#include "gui/view.h"
#include "gui/view_dispatcher.h"
```

Keep application state containing the GUI, dispatcher, views and callback context.
Allocate the dispatcher and views during initialization, set their contexts and
callbacks, then register each view under a distinct ID. The following fragment
assumes those resources and compatible draw/input callbacks already exist:

```zig
flipper.view_set_context(settings_view, context);
flipper.view_set_draw_callback(settings_view, settings_draw_callback);
flipper.view_set_input_callback(settings_view, settings_input_callback);

flipper.view_dispatcher_add_view(dispatcher, 0, main_view);
flipper.view_dispatcher_add_view(dispatcher, 1, settings_view);
flipper.view_dispatcher_attach_to_gui(
    dispatcher,
    gui,
    flipper.ViewDispatcherTypeFullscreen,
);
flipper.view_dispatcher_switch_to_view(dispatcher, 1);
flipper.view_dispatcher_run(dispatcher);
```

Unlike a viewport input callback, a view input callback returns `bool` to indicate
whether it handled the event. Match the callback types generated from the SDK.
Provide a Back/navigation handler that stops the dispatcher or switches views.
After the event loop returns, remove registered views, free each view, free the
dispatcher and close the GUI record. Keep callback contexts alive through cleanup.

## Debugging with GDB

Build from the repository root in Debug mode, then package the same object:

```bash
zig build -Drelease=false
python3 -m ufbt
python3 -m ufbt debug
```

Debugging requires a configured hardware debug connection and UFBT's debug tools.
A USB connection used to launch a FAP alone does not provide an SWD debugging
connection. Follow the UFBT instructions for your probe and firmware setup.

Once GDB is connected and the application's symbols are loaded:

```gdb
# Break at the template's exported entry point or draw callback.
break start
break draw_callback
continue

# Inspect the current stack and variables after stopping.
backtrace
info locals
print context
```

FAPs load dynamically, so application breakpoints require symbols relocated to the
loaded app's address. If GDB cannot find `start` or `draw_callback`, check the
loaded app and its debug symbols before setting breakpoints. Optimized builds may
inline functions or remove variables; use the Debug object for source inspection.

For crashes, inspect the backtrace, pointer validity, callback signatures and
`stack_size` in `application.fam`. For device logs without a debug probe, use:

```bash
python3 -m ufbt cli
```

## References

- [Zig 0.17.1 language reference](https://ziglang.org/documentation/0.17.1/)
- [UFBT](https://github.com/flipperdevices/flipperzero-ufbt)
- [Flipper developer documentation](https://developer.flipper.net/)
