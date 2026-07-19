const flipper = @import("flipper");

// Draw callback
export fn draw_callback(canvas: ?*flipper.Canvas, context: ?*anyopaque) callconv(.{ .arm_aapcs_vfp = .{} }) void {
    _ = context;
    flipper.canvas_clear(canvas);
    flipper.canvas_set_font(canvas, flipper.FontPrimary);
    flipper.canvas_draw_str(canvas, 10, 30, "Hello World!");
    flipper.canvas_set_font(canvas, flipper.FontSecondary);
    flipper.canvas_draw_str(canvas, 10, 50, "Press Back to exit");
}

// Input callback - exit on any button press
export fn input_callback(event: ?*flipper.InputEvent, context: ?*anyopaque) callconv(.{ .arm_aapcs_vfp = .{} }) void {
    _ = event;
    // context contains the main thread ID (cast back from pointer)
    const main_thread_id: flipper.FuriThreadId = @ptrCast(@alignCast(context));
    _ = flipper.furi_thread_flags_set(main_thread_id, 1);
}

export fn start(_: ?*anyopaque) callconv(.{ .arm_aapcs = .{} }) i32 {
    const gui: ?*flipper.Gui = @ptrCast(@alignCast(flipper.furi_record_open("gui")));
    defer flipper.furi_record_close("gui");

    const view_port = flipper.view_port_alloc();
    defer flipper.view_port_free(view_port);

    // Get main thread ID to pass as context
    const main_thread_id = flipper.furi_thread_get_current_id();
    const context: ?*anyopaque = @ptrCast(main_thread_id);

    flipper.view_port_draw_callback_set(view_port, draw_callback, null);
    flipper.view_port_input_callback_set(view_port, input_callback, context);
    flipper.gui_add_view_port(gui, view_port, flipper.GuiLayerFullscreen);
    defer flipper.gui_remove_view_port(gui, view_port);

    // Wait for any button press (thread flag 1)
    _ = flipper.furi_thread_flags_wait(1, flipper.FuriFlagWaitAny, flipper.FuriWaitForever);

    return 0;
}
