//! A minimal native Windows application runtime. Opens a single Win32
//! window and pumps its message loop; no surfaces or rendering yet.
const App = @This();

const std = @import("std");
const windows = std.os.windows;
const Allocator = std.mem.Allocator;
const apprt = @import("../../apprt.zig");
const CoreApp = @import("../../App.zig");
const configpkg = @import("../../config.zig");
const Config = configpkg.Config;

const log = std.log.scoped(.win32);

const HWND = windows.HWND;
const HINSTANCE = windows.HINSTANCE;
const HICON = windows.HICON;
const HCURSOR = windows.HCURSOR;
const HBRUSH = windows.HBRUSH;
const HMENU = windows.HMENU;
const ATOM = windows.ATOM;
const DWORD = windows.DWORD;
const UINT = windows.UINT;
const LPCWSTR = windows.LPCWSTR;

const BOOL = c_int;
const WPARAM = usize;
const LPARAM = isize;
const LRESULT = isize;

const WNDPROC = *const fn (
    hwnd: HWND,
    msg: UINT,
    wparam: WPARAM,
    lparam: LPARAM,
) callconv(.winapi) LRESULT;

const WNDCLASSEXW = extern struct {
    cbSize: UINT = @sizeOf(WNDCLASSEXW),
    style: UINT = 0,
    lpfnWndProc: WNDPROC,
    cbClsExtra: c_int = 0,
    cbWndExtra: c_int = 0,
    hInstance: HINSTANCE,
    hIcon: ?HICON = null,
    hCursor: ?HCURSOR = null,
    hbrBackground: ?HBRUSH = null,
    lpszMenuName: ?LPCWSTR = null,
    lpszClassName: LPCWSTR,
    hIconSm: ?HICON = null,
};

const POINT = extern struct { x: i32, y: i32 };

const MSG = extern struct {
    hwnd: ?HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
};

const CW_USEDEFAULT: c_int = @bitCast(@as(u32, 0x80000000));
const WS_OVERLAPPEDWINDOW: DWORD = 0x00CF0000;
const SW_SHOWDEFAULT: c_int = 10;
const WM_DESTROY: UINT = 0x0002;
const WM_CLOSE: UINT = 0x0010;

// align(1) because MAKEINTRESOURCE-style values (small integer resource
// IDs cast to a pointer) aren't necessarily 2-byte aligned.
const ResourceNameW = [*:0]align(1) const u16;

const IDC_ARROW: ResourceNameW = @ptrFromInt(32512);

extern "user32" fn RegisterClassExW(
    class: *const WNDCLASSEXW,
) callconv(.winapi) ATOM;
extern "user32" fn CreateWindowExW(
    dwExStyle: DWORD,
    lpClassName: LPCWSTR,
    lpWindowName: LPCWSTR,
    dwStyle: DWORD,
    X: c_int,
    Y: c_int,
    nWidth: c_int,
    nHeight: c_int,
    hWndParent: ?HWND,
    hMenu: ?HMENU,
    hInstance: HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(.winapi) ?HWND;
extern "user32" fn DestroyWindow(hwnd: HWND) callconv(.winapi) BOOL;
extern "user32" fn ShowWindow(hwnd: HWND, nCmdShow: c_int) callconv(.winapi) BOOL;
extern "user32" fn UpdateWindow(hwnd: HWND) callconv(.winapi) BOOL;
extern "user32" fn DefWindowProcW(
    hwnd: HWND,
    msg: UINT,
    wparam: WPARAM,
    lparam: LPARAM,
) callconv(.winapi) LRESULT;
extern "user32" fn GetMessageW(
    msg: *MSG,
    hwnd: ?HWND,
    msgFilterMin: UINT,
    msgFilterMax: UINT,
) callconv(.winapi) BOOL;
extern "user32" fn TranslateMessage(msg: *const MSG) callconv(.winapi) BOOL;
extern "user32" fn DispatchMessageW(msg: *const MSG) callconv(.winapi) LRESULT;
extern "user32" fn PostQuitMessage(exitCode: c_int) callconv(.winapi) void;
extern "user32" fn LoadCursorW(
    hInstance: ?HINSTANCE,
    lpCursorName: ResourceNameW,
) callconv(.winapi) ?HCURSOR;
extern "user32" fn LoadIconW(
    hInstance: ?HINSTANCE,
    lpIconName: ResourceNameW,
) callconv(.winapi) ?HICON;
extern "kernel32" fn GetModuleHandleW(
    lpModuleName: ?LPCWSTR,
) callconv(.winapi) ?HINSTANCE;

const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyWindowClass");

// Must stay in sync with dist/windows/ghostty.rc's ID_ICON_GHOSTTY.
const ID_ICON_GHOSTTY: usize = 1;

fn makeIntResource(id: usize) ResourceNameW {
    return @ptrFromInt(id);
}

core_app: *CoreApp,
hwnd: HWND,

pub fn init(
    self: *App,
    core_app: *CoreApp,
    opts: struct {},
) !void {
    _ = opts;

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

    const hinstance = GetModuleHandleW(null) orelse {
        log.err("GetModuleHandleW failed", .{});
        return error.Win32GetModuleHandleFailed;
    };

    const icon = LoadIconW(hinstance, makeIntResource(ID_ICON_GHOSTTY));
    if (icon == null) {
        log.warn("LoadIconW failed err={}", .{windows.GetLastError()});
    }

    const wc: WNDCLASSEXW = .{
        .lpfnWndProc = &wndProc,
        .hInstance = hinstance,
        .hIcon = icon,
        .hCursor = LoadCursorW(null, IDC_ARROW),
        .lpszClassName = class_name,
        .hIconSm = icon,
    };
    if (RegisterClassExW(&wc) == 0) {
        log.err("RegisterClassExW failed err={}", .{windows.GetLastError()});
        return error.Win32RegisterClassFailed;
    }

    const hwnd = CreateWindowExW(
        0,
        class_name,
        title_w,
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        800,
        600,
        null,
        null,
        hinstance,
        null,
    ) orelse {
        log.err("CreateWindowExW failed err={}", .{windows.GetLastError()});
        return error.Win32CreateWindowFailed;
    };

    self.* = .{
        .core_app = core_app,
        .hwnd = hwnd,
    };
}

pub fn run(self: *App) !void {
    _ = ShowWindow(self.hwnd, SW_SHOWDEFAULT);
    _ = UpdateWindow(self.hwnd);

    var msg: MSG = undefined;
    while (GetMessageW(&msg, null, 0, 0) > 0) {
        _ = TranslateMessage(&msg);
        _ = DispatchMessageW(&msg);
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
    hwnd: HWND,
    msg: UINT,
    wparam: WPARAM,
    lparam: LPARAM,
) callconv(.winapi) LRESULT {
    switch (msg) {
        WM_CLOSE => {
            _ = DestroyWindow(hwnd);
            return 0;
        },
        WM_DESTROY => {
            PostQuitMessage(0);
            return 0;
        },
        else => {},
    }

    return DefWindowProcW(hwnd, msg, wparam, lparam);
}
