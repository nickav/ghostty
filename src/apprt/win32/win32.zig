const std = @import("std");
const windows = std.os.windows;

// Basic Types
pub const ATOM = windows.ATOM;
pub const DWORD = windows.DWORD;
pub const UINT = windows.UINT;
pub const LPCWSTR = windows.LPCWSTR;
pub const LSTATUS = c_long;
pub const BOOL = c_int;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;

pub const HANDLE = *anyopaque;
pub const HRESULT = c_long;
pub const S_OK: HRESULT = 0x00000000;
pub const E_FAIL: HRESULT = @bitCast(@as(u32, 0x80004005));
pub const ERROR_SUCCESS: LSTATUS = 0;

// Handles
pub const HWND = windows.HWND;
pub const HINSTANCE = windows.HINSTANCE;
pub const HMODULE = windows.HMODULE;
pub const HICON = windows.HICON;
pub const HCURSOR = windows.HCURSOR;
pub const HBRUSH = windows.HBRUSH;
pub const HMENU = windows.HMENU;

// Library-specific
pub const CW_USEDEFAULT: c_int = @bitCast(@as(u32, 0x80000000));
pub const WS_OVERLAPPEDWINDOW: DWORD = 0x00CF0000;
pub const WS_POPUP: DWORD = 0x80000000;
pub const SW_SHOWDEFAULT: c_int = 10;

pub const WM_CREATE: UINT = 0x0001;
pub const WM_DESTROY: UINT = 0x0002;
pub const WM_CLOSE: UINT = 0x0010;
pub const WM_SIZE: UINT = 0x0005;
pub const WM_PAINT: UINT = 0x000F;
pub const WM_SETTINGCHANGE: UINT = 0x001A;
pub const WM_DWMCOLORIZATIONCOLORCHANGED: UINT = 0x0320;
pub const WM_APP: UINT = 0x8000;

pub const IDC_ARROW: ResourceNameW = @ptrFromInt(32512);

pub const DPI_AWARENESS_CONTEXT = HANDLE;
pub const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: DPI_AWARENESS_CONTEXT = @ptrFromInt(@as(usize, @bitCast(@as(isize, -4))));
pub const PROCESS_SYSTEM_DPI_AWARE: c_int = 1;
pub const LOAD_LIBRARY_SEARCH_SYSTEM32: DWORD = 0x00000800;

pub const HKEY = *anyopaque;
pub const HKEY_CURRENT_USER: HKEY = @ptrFromInt(0x80000001);

pub const DWMWA_USE_IMMERSIVE_DARK_MODE: DWORD = 20;
pub const RRF_RT_ANY: DWORD = 0x0000ffff;

pub const HGDIOBJ = *anyopaque;
pub const GWLP_USERDATA: c_int = -21;
pub const WHITE_BRUSH: c_int = 0;
pub const BLACK_BRUSH: c_int = 4;
pub const WM_ERASEBKGND: UINT = 0x0014;

// align(1) because MAKEINTRESOURCE-style values aren't necessarily 2-byte aligned
pub const ResourceNameA = [*:0]align(1) const u8;
pub const ResourceNameW = [*:0]align(1) const u16;

// Compound-types
pub const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};

pub const POINT = extern struct { x: i32, y: i32 };

pub const PAINTSTRUCT = extern struct {
    hdc: HANDLE,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]u8,
};

pub const MSG = extern struct {
    hwnd: ?HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
};

pub const CREATESTRUCTW = extern struct {
    lpCreateParams: ?*anyopaque,
    hInstance: HINSTANCE,
    hMenu: ?HMENU,
    hwndParent: ?HWND,
    cy: c_int,
    cx: c_int,
    y: c_int,
    x: c_int,
    style: c_long,
    lpszName: ?LPCWSTR,
    lpszClass: ?LPCWSTR,
    dwExStyle: DWORD,
};

// Basic Helpers
pub fn makeIntResource(id: usize) ResourceNameW {
    return @ptrFromInt(id);
}

pub fn makeIntResourceA(id: usize) ResourceNameA {
    return @ptrFromInt(id);
}

pub const GetLastError = windows.GetLastError;

pub inline fn SUCCEEDED(hr: HRESULT) bool {
    return hr >= 0;
}

//
// DLL bindings
//

pub const WNDPROC = *const fn (
    hwnd: HWND,
    msg: UINT,
    wparam: WPARAM,
    lparam: LPARAM,
) callconv(.winapi) LRESULT;

pub const WNDCLASSEXW = extern struct {
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

pub extern "user32" fn RegisterClassExW(
    class: *const WNDCLASSEXW,
) callconv(.winapi) ATOM;

pub extern "user32" fn CreateWindowExW(
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

pub extern "user32" fn DestroyWindow(hwnd: HWND) callconv(.winapi) BOOL;

pub extern "user32" fn ShowWindow(hwnd: HWND, nCmdShow: c_int) callconv(.winapi) BOOL;

pub extern "user32" fn UpdateWindow(hwnd: HWND) callconv(.winapi) BOOL;

pub extern "user32" fn DefWindowProcW(
    hwnd: HWND,
    msg: UINT,
    wparam: WPARAM,
    lparam: LPARAM,
) callconv(.winapi) LRESULT;

pub extern "user32" fn GetMessageW(
    msg: *MSG,
    hwnd: ?HWND,
    msgFilterMin: UINT,
    msgFilterMax: UINT,
) callconv(.winapi) BOOL;

pub extern "user32" fn TranslateMessage(msg: *const MSG) callconv(.winapi) BOOL;

pub extern "user32" fn DispatchMessageW(msg: *const MSG) callconv(.winapi) LRESULT;

pub extern "user32" fn PostQuitMessage(exitCode: c_int) callconv(.winapi) void;

pub extern "user32" fn PostMessageW(
    hwnd: ?HWND,
    msg: UINT,
    wparam: WPARAM,
    lparam: LPARAM,
) callconv(.winapi) BOOL;

pub extern "user32" fn LoadCursorW(
    hInstance: ?HINSTANCE,
    lpCursorName: ResourceNameW,
) callconv(.winapi) ?HCURSOR;

pub extern "user32" fn LoadIconW(
    hInstance: ?HINSTANCE,
    lpIconName: ResourceNameW,
) callconv(.winapi) ?HICON;

pub extern "kernel32" fn GetModuleHandleW(
    lpModuleName: ?LPCWSTR,
) callconv(.winapi) ?HINSTANCE;

pub const DwmSetWindowAttributeFn = *const fn (
    hwnd: HWND,
    dwAttribute: DWORD,
    pvAttribute: *const anyopaque,
    cbAttribute: DWORD,
) callconv(.winapi) HRESULT;

pub extern "kernel32" fn LoadLibraryA(
    lpLibFileName: [*:0]const u8,
) callconv(.winapi) ?HMODULE;

pub extern "kernel32" fn LoadLibraryExA(
    lpLibFileName: [*:0]const u8,
    hFile: ?HANDLE,
    dwFlags: DWORD,
) callconv(.winapi) ?HMODULE;

pub extern "kernel32" fn GetProcAddress(
    hModule: HMODULE,
    lpProcName: [*:0]const u8,
) callconv(.winapi) ?*anyopaque;

pub extern "advapi32" fn RegGetValueA(
    hkey: HKEY,
    lpSubKey: ?[*:0]const u8,
    lpValue: ?[*:0]const u8,
    dwFlags: DWORD,
    pdwType: ?*DWORD,
    pvData: ?*anyopaque,
    pcbData: ?*DWORD,
) callconv(.winapi) LSTATUS;

var g_DwmSetWindowAttribute: ?DwmSetWindowAttributeFn = null;
pub fn DwmSetWindowAttribute(
    hwnd: HWND,
    dwAttribute: DWORD,
    pvAttribute: *const anyopaque,
    cbAttribute: DWORD,
) HRESULT {
    if (g_DwmSetWindowAttribute == null) {
        if (LoadLibraryA("dwmapi.dll")) |dwmapi| {
            g_DwmSetWindowAttribute = @ptrCast(GetProcAddress(dwmapi, "DwmSetWindowAttribute"));
        }
    }
    if (g_DwmSetWindowAttribute) |f| {
        return f(hwnd, dwAttribute, pvAttribute, cbAttribute);
    }
    return 0;
}

pub const SetProcessDpiAwarenessContextFn = *const fn (
    value: DPI_AWARENESS_CONTEXT,
) callconv(.winapi) BOOL;

pub const SetProcessDpiAwarenessFn = *const fn (
    value: c_int,
) callconv(.winapi) BOOL;

pub const SetPreferredAppModeFn = *const fn (
    mode: DWORD,
) callconv(.winapi) DWORD;

pub extern "user32" fn SetProcessDPIAware() callconv(.winapi) BOOL;

var g_user32: ?HMODULE = null;
fn getUser32() ?HMODULE {
    if (g_user32 == null) {
        g_user32 = LoadLibraryA("user32.dll");
    }
    return g_user32;
}

var g_SetProcessDpiAwarenessContext: ?SetProcessDpiAwarenessContextFn = null;
pub fn SetProcessDpiAwarenessContext(value: DPI_AWARENESS_CONTEXT) ?BOOL {
    if (g_SetProcessDpiAwarenessContext == null) {
        if (getUser32()) |user32| {
            g_SetProcessDpiAwarenessContext = @ptrCast(GetProcAddress(user32, "SetProcessDpiAwarenessContext"));
        }
    }
    if (g_SetProcessDpiAwarenessContext) |f| {
        return f(value);
    }
    return null;
}

var g_SetProcessDpiAwareness: ?SetProcessDpiAwarenessFn = null;
pub fn SetProcessDpiAwareness(value: c_int) ?BOOL {
    if (g_SetProcessDpiAwareness == null) {
        if (getUser32()) |user32| {
            g_SetProcessDpiAwareness = @ptrCast(GetProcAddress(user32, "SetProcessDpiAwareness"));
        }
    }
    if (g_SetProcessDpiAwareness) |f| {
        return f(value);
    }
    return null;
}

var g_SetPreferredAppMode: ?SetPreferredAppModeFn = null;
pub fn SetPreferredAppMode(mode: DWORD) ?DWORD {
    if (g_SetPreferredAppMode == null) {
        if (LoadLibraryExA("uxtheme.dll", null, LOAD_LIBRARY_SEARCH_SYSTEM32)) |uxtheme| {
            g_SetPreferredAppMode = @ptrCast(GetProcAddress(uxtheme, makeIntResourceA(135)));
        }
    }
    if (g_SetPreferredAppMode) |f| {
        return f(mode);
    }
    return null;
}

pub extern "user32" fn InvalidateRect(
    hwnd: HWND,
    lpRect: ?*const RECT,
    bErase: BOOL,
) callconv(.winapi) BOOL;

pub extern "gdi32" fn CreateSolidBrush(color: DWORD) callconv(.winapi) HBRUSH;

pub extern "gdi32" fn GetStockObject(i: c_int) callconv(.winapi) HGDIOBJ;

pub extern "gdi32" fn FillRect(
    hdc: HANDLE,
    lprc: *const RECT,
    hbr: HBRUSH,
) callconv(.winapi) c_int;

pub extern "user32" fn GetClientRect(
    hwnd: HWND,
    lpRect: *RECT,
) callconv(.winapi) BOOL;

pub extern "user32" fn BeginPaint(
    hwnd: HWND,
    lpPaint: *PAINTSTRUCT,
) callconv(.winapi) ?HANDLE;

pub extern "user32" fn EndPaint(
    hwnd: HWND,
    lpPaint: *const PAINTSTRUCT,
) callconv(.winapi) BOOL;

pub extern "user32" fn SetWindowLongPtrW(
    hwnd: HWND,
    nIndex: c_int,
    dwNewLong: isize,
) callconv(.winapi) isize;

pub extern "user32" fn GetWindowLongPtrW(
    hwnd: HWND,
    nIndex: c_int,
) callconv(.winapi) isize;