/// This is the main entrypoint to the apprt for Ghostty on windows.
/// Ghostty will initialize this in main to start the application..
const App = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const apprt = @import("../../apprt.zig");
const CoreApp = @import("../../App.zig");
const configpkg = @import("../../config.zig");
const Config = configpkg.Config;

const win32 = @import("./win32.zig");

const log = std.log.scoped(.win32);

const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyWindowClass");

// @Sync: must stay in sync with dist/windows/ghostty.rc's ID_ICON_GHOSTTY
const ID_ICON_GHOSTTY: usize = 1;

core_app: *CoreApp,
hwnd: win32.HWND,
bg_brush: win32.HBRUSH,
use_light_theme: win32.DWORD = 0,

pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = opts;

    self.core_app = core_app;

    var config = Config.load(core_app.alloc) catch |err| err: {
        log.warn("error loading configuration, using defaults err={}", .{err});
        break :err try Config.default(core_app.alloc);
    };
    defer config.deinit();

    const title_w = try std.unicode.utf8ToUtf16LeAllocZ(
        core_app.alloc,
        config.title orelse "Ghostty",
    );
    defer core_app.alloc.free(title_w);

    // NOTE: we want to use a DPI-aware window
    if (false) {}
    else if (win32.SetProcessDpiAwarenessContext(win32.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)) |_| {}
    else if (win32.SetProcessDpiAwareness(win32.PROCESS_SYSTEM_DPI_AWARE)) |_| {}
    else {
        _ = win32.SetProcessDPIAware();
    }

    // NOTE: we want to tell windows to match the app to the user's preferred color scheme (light or dark)
    _ = win32.SetPreferredAppMode(1);

    const hinstance = win32.GetModuleHandleW(null) orelse {
        log.err("GetModuleHandleW failed", .{});
        return error.Win32GetModuleHandleFailed;
    };

    const icon = win32.LoadIconW(hinstance, win32.makeIntResource(ID_ICON_GHOSTTY));
    if (icon == null) {
        log.warn("LoadIconW failed err={}", .{win32.GetLastError()});
    }

    const wc: win32.WNDCLASSEXW = .{
        .lpfnWndProc = &wndProc,
        .hInstance = hinstance,
        .hIcon = icon,
        .hCursor = win32.LoadCursorW(null, win32.IDC_ARROW),
        .lpszClassName = class_name,
        .hIconSm = icon,
    };
    if (win32.RegisterClassExW(&wc) == 0) {
        log.err("RegisterClassExW failed err={}", .{win32.GetLastError()});
        return error.Win32RegisterClassFailed;
    }

    self.bg_brush = @ptrCast(win32.GetStockObject(win32.BLACK_BRUSH));
    const hwnd = win32.CreateWindowExW(
        0,
        class_name,
        title_w,
        win32.WS_OVERLAPPEDWINDOW,
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT,
        800,
        600,
        null,
        null,
        hinstance,
        self,
    ) orelse {
        log.err("CreateWindowExW failed err={}", .{win32.GetLastError()});
        return error.Win32CreateWindowFailed;
    };
    self.hwnd = hwnd;
}

pub fn run(self: *App) !void {
    _ = win32.ShowWindow(self.hwnd, win32.SW_SHOWDEFAULT);
    _ = win32.UpdateWindow(self.hwnd);

    var msg: win32.MSG = undefined;
    while (win32.GetMessageW(&msg, null, 0, 0) > 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageW(&msg);
    }
}

pub fn terminate(self: *App) void {
    _ = self;
}

pub fn wakeup(self: *App) void {
    _ = self;
}

pub fn performIpc(
    _: Allocator,
    _: apprt.ipc.Target,
    comptime action: apprt.ipc.Action.Key,
    _: apprt.ipc.Action.Value(action),
) !bool {
    return false;
}

fn wndProc(
    hwnd: win32.HWND,
    msg: win32.UINT,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) callconv(.winapi) win32.LRESULT {
    switch (msg) {
        win32.WM_CLOSE => {
            _ = win32.DestroyWindow(hwnd);
            return 0;
        },
        win32.WM_CREATE => {
            const cs: *win32.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lparam)));
            const self: *App = @ptrCast(@alignCast(cs.lpCreateParams));
            _ = win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, @bitCast(@intFromPtr(self)));
            self.hwnd = hwnd;
            self.updateTheme();
            return win32.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        win32.WM_DESTROY => {
            win32.PostQuitMessage(0);
            return 0;
        },
        win32.WM_PAINT => {
            _ = win32.InvalidateRect(hwnd, null, 1);
        },
        win32.WM_ERASEBKGND => {
            const self: *App = @ptrFromInt(@as(usize, @bitCast(win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA))));
            var rect: win32.RECT = undefined;
            _ = win32.GetClientRect(hwnd, &rect);
            _ = win32.FillRect(@ptrFromInt(wparam), &rect, self.bg_brush);
            return 1;
        },
        win32.WM_SETTINGCHANGE => {
            if (lparam != 0) {
                const str: [*:0]const u16 = @ptrFromInt(@as(usize, @bitCast(lparam)));
                const slice = std.mem.span(str);
                if (std.mem.eql(u16, slice, std.unicode.utf8ToUtf16LeStringLiteral("ImmersiveColorSet"))) {
                    const self: *App = @ptrFromInt(@as(usize, @bitCast(win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA))));
                    self.updateTheme();
                    _ = win32.InvalidateRect(hwnd, null, 1);
                }
            }
        },
        win32.WM_DWMCOLORIZATIONCOLORCHANGED => {
            const self: *App = @ptrFromInt(@as(usize, @bitCast(win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA))));
            self.updateTheme();
            _ = win32.InvalidateRect(hwnd, null, 1);
        },
        else => {},
    }

    return win32.DefWindowProcW(hwnd, msg, wparam, lparam);
}

fn updateTheme(self: *App) void {
    self.use_light_theme = 0;
    var dataSize: win32.DWORD = @sizeOf(win32.DWORD);
    const status = win32.RegGetValueA(
        win32.HKEY_CURRENT_USER,
        "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        "AppsUseLightTheme",
        win32.RRF_RT_ANY,
        null,
        &self.use_light_theme,
        &dataSize,
    );

    if (status == win32.ERROR_SUCCESS) {
        var value: win32.BOOL = if (self.use_light_theme == 0) 1 else 0;
        _ = win32.DwmSetWindowAttribute(self.hwnd, win32.DWMWA_USE_IMMERSIVE_DARK_MODE, &value, @sizeOf(win32.BOOL));
    }

    self.bg_brush = @ptrCast(win32.GetStockObject(if (self.use_light_theme == 0) win32.BLACK_BRUSH else win32.WHITE_BRUSH));
}