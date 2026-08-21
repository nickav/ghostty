const Surface = @This();

const std = @import("std");
const apprt = @import("../../apprt.zig");
const App = @import("App.zig");
const CoreSurface = @import("../../Surface.zig");
const configpkg = @import("../../config.zig");
const global = @import("../../global.zig");
const win32 = @import("./win32.zig");

app: *App,
core_surface: CoreSurface,

pub fn init(self: *Surface, app: *App, config: *const configpkg.Config) !void {
    self.* = .{
        .app = app,
        .core_surface = undefined,
    };

    try self.core_surface.init(
        app.core_app.alloc,
        config,
        app.core_app,
        app,
        self,
    );
}

pub fn deinit(self: *Surface) void {
    self.core_surface.deinit();
}

pub fn core(self: *Surface) *CoreSurface {
    return &self.core_surface;
}

pub fn rtApp(self: *const Surface) *App {
    return self.app;
}

pub fn close(self: *const Surface, process_alive: bool) void {
    _ = process_alive;
    _ = win32.DestroyWindow(self.app.hwnd);
}

pub fn getContentScale(self: *const Surface) !apprt.ContentScale {
    _ = self;
    // @Incomplete:
    return .{ .x = 1, .y = 1 };
}

pub fn getSize(self: *const Surface) !apprt.SurfaceSize {
    var rect: win32.RECT = undefined;
    _ = win32.GetClientRect(self.app.hwnd, &rect);
    return .{
        .width = @intCast(rect.right - rect.left),
        .height = @intCast(rect.bottom - rect.top),
    };
}

pub fn getTitle(self: *Surface) ?[:0]const u8 {
    _ = self;
    return null;
}

pub fn supportsClipboard(
    self: *const Surface,
    clipboard_type: apprt.Clipboard,
) bool {
    _ = self;
    return clipboard_type == .standard;
}

pub fn clipboardRequest(
    self: *Surface,
    clipboard_type: apprt.Clipboard,
    state: apprt.ClipboardRequest,
) !bool {
    _ = self;
    _ = clipboard_type;
    _ = state;
    // @Incomplete:
    return false;
}

pub fn setClipboard(
    self: *const Surface,
    clipboard_type: apprt.Clipboard,
    contents: []const apprt.ClipboardContent,
    confirm: bool,
) !void {
    _ = self;
    _ = clipboard_type;
    _ = contents;
    _ = confirm;
    // @Incomplete:
}

pub fn getCursorPos(self: *const Surface) !apprt.CursorPos {
    _ = self;
    return .{ .x = 0, .y = 0 };
}

pub fn defaultTermioEnv(self: *const Surface) !std.process.Environ.Map {
    _ = self;
    return try global.environMap();
}
