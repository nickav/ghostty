const std = @import("std");
const builtin = @import("builtin");
const win32 = @import("win32.zig");

pub const HDC = win32.HANDLE;
pub const HGLRC = win32.HANDLE;
pub const WORD = u16;
pub const BYTE = u8;
pub const BOOL = c_int;

pub const CS_OWNDC: win32.UINT = 0x0020;

pub const PFD_DRAW_TO_WINDOW: win32.DWORD = 0x00000004;
pub const PFD_SUPPORT_OPENGL: win32.DWORD = 0x00000020;
pub const PFD_DOUBLEBUFFER: win32.DWORD = 0x00000001;
pub const PFD_TYPE_RGBA: BYTE = 0;
pub const PFD_MAIN_PLANE: BYTE = 0;

const WGL_DRAW_TO_WINDOW_ARB = 0x2001;
const WGL_SUPPORT_OPENGL_ARB = 0x2010;
const WGL_DOUBLE_BUFFER_ARB = 0x2011;
const WGL_PIXEL_TYPE_ARB = 0x2013;
const WGL_TYPE_RGBA_ARB = 0x202B;
const WGL_ACCELERATION_ARB = 0x2003;
const WGL_FULL_ACCELERATION_ARB = 0x2027;
const WGL_COLOR_BITS_ARB = 0x2014;
const WGL_DEPTH_BITS_ARB = 0x2022;
const WGL_STENCIL_BITS_ARB = 0x2023;
const WGL_SAMPLE_BUFFERS_ARB = 0x2041;
const WGL_SAMPLES_ARB = 0x2042;
const GL_TRUE = 1;

pub const PIXELFORMATDESCRIPTOR = extern struct {
    nSize: WORD = @sizeOf(PIXELFORMATDESCRIPTOR),
    nVersion: WORD = 1,
    dwFlags: win32.DWORD = 0,
    iPixelType: BYTE = 0,
    cColorBits: BYTE = 0,
    cRedBits: BYTE = 0,
    cRedShift: BYTE = 0,
    cGreenBits: BYTE = 0,
    cGreenShift: BYTE = 0,
    cBlueBits: BYTE = 0,
    cBlueShift: BYTE = 0,
    cAlphaBits: BYTE = 0,
    cAlphaShift: BYTE = 0,
    cAccumBits: BYTE = 0,
    cAccumRedBits: BYTE = 0,
    cAccumGreenBits: BYTE = 0,
    cAccumBlueBits: BYTE = 0,
    cAccumAlphaBits: BYTE = 0,
    cDepthBits: BYTE = 0,
    cStencilBits: BYTE = 0,
    cAuxBuffers: BYTE = 0,
    iLayerType: BYTE = 0,
    bReserved: BYTE = 0,
    dwLayerMask: win32.DWORD = 0,
    dwVisibleMask: win32.DWORD = 0,
    dwDamageMask: win32.DWORD = 0,
};

pub extern "user32" fn GetDC(hwnd: win32.HWND) callconv(.winapi) ?HDC;

pub extern "user32" fn ReleaseDC(hwnd: win32.HWND, hdc: HDC) callconv(.winapi) c_int;

pub extern "gdi32" fn ChoosePixelFormat(
    hdc: HDC,
    ppfd: *const PIXELFORMATDESCRIPTOR,
) callconv(.winapi) c_int;

pub extern "gdi32" fn SetPixelFormat(
    hdc: HDC,
    format: c_int,
    ppfd: *const PIXELFORMATDESCRIPTOR,
) callconv(.winapi) win32.BOOL;

pub extern "gdi32" fn DescribePixelFormat(
    hdc: HDC,
    format: c_int,
    bytes: win32.UINT,
    ppfd: ?*PIXELFORMATDESCRIPTOR,
) callconv(.winapi) c_int;

pub extern "gdi32" fn SwapBuffers(hdc: HDC) callconv(.winapi) win32.BOOL;

pub extern "opengl32" fn wglCreateContext(hdc: HDC) callconv(.winapi) ?HGLRC;

pub extern "opengl32" fn wglMakeCurrent(hdc: ?HDC, hglrc: ?HGLRC) callconv(.winapi) win32.BOOL;

pub extern "opengl32" fn wglDeleteContext(hglrc: HGLRC) callconv(.winapi) win32.BOOL;

pub extern "opengl32" fn wglGetProcAddress(name: [*:0]const u8) callconv(.winapi) ?*anyopaque;

pub const ChoosePixelFormatARBFn = *const fn (
    hdc: HDC,
    attrib_i_list: ?[*:0]const c_int,
    attrib_f_list: ?[*:0]const f32,
    max_formats: c_uint,
    formats: [*]c_int,
    num_formats: *c_uint,
) callconv(.winapi) BOOL;

pub const CreateContextAttribsARBFn = *const fn (
    hdc: HDC,
    share: ?HGLRC,
    attribs: [*:0]const c_int,
) callconv(.winapi) ?HGLRC;

pub const SwapIntervalEXTFn = *const fn (interval: c_int) callconv(.winapi) BOOL;

pub const GLContext = struct {
    hdc: HDC,
    hglrc: HGLRC,
};

fn dummyWndProc(
    hwnd: win32.HWND,
    msg: win32.UINT,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) callconv(.winapi) win32.LRESULT {
    return win32.DefWindowProcW(hwnd, msg, wparam, lparam);
}

/// Sets up a real, extension-loaded OpenGL context for the given window
/// and makes it current on the calling thread.
pub fn init(hwnd: win32.HWND, major_version: c_int, minor_version: c_int) !GLContext {
    const class_name = std.unicode.utf8ToUtf16LeStringLiteral("Ghostty_Dummy_OpenGL_Extension_Loader");
    const hinstance = win32.GetModuleHandleW(null) orelse return error.Win32GetModuleHandleFailed;

    const window_class: win32.WNDCLASSEXW = .{
        .style = CS_OWNDC,
        .lpfnWndProc = &dummyWndProc,
        .hInstance = hinstance,
        .lpszClassName = class_name,
    };
    if (win32.RegisterClassExW(&window_class) == 0) {
        return error.Win32RegisterClassFailed;
    }

    // Before we can load extensions, we need a dummy OpenGL context, created using a dummy window.
    // We use a dummy window because you can only set the pixel format for a window once. For the
    // real window, we want to use wglChoosePixelFormatARB (so we can potentially specify options
    // that aren't available in PIXELFORMATDESCRIPTOR), but we can't load and use that before we
    // have a context.
    const dummy_hwnd = win32.CreateWindowExW(
        0,
        class_name,
        std.unicode.utf8ToUtf16LeStringLiteral("Dummy OpenGL Window"),
        0,
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT,
        null,
        null,
        hinstance,
        null,
    ) orelse return error.Win32CreateWindowFailed;
    defer _ = win32.DestroyWindow(dummy_hwnd);

    const dummy_hdc = GetDC(dummy_hwnd) orelse return error.Win32GetDCFailed;
    defer _ = ReleaseDC(dummy_hwnd, dummy_hdc);

    var dummy_pfd: PIXELFORMATDESCRIPTOR = .{
        .dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER,
        .iPixelType = PFD_TYPE_RGBA,
        .cColorBits = 32,
        .cAlphaBits = 8,
        .cDepthBits = 24,
        .cStencilBits = 0,
        .iLayerType = PFD_MAIN_PLANE,
    };

    const dummy_format = ChoosePixelFormat(dummy_hdc, &dummy_pfd);
    if (dummy_format == 0) return error.Win32ChoosePixelFormatFailed;
    if (SetPixelFormat(dummy_hdc, dummy_format, &dummy_pfd) == 0) {
        return error.Win32SetPixelFormatFailed;
    }

    const dummy_context = wglCreateContext(dummy_hdc) orelse return error.Win32WglCreateContextFailed;
    if (wglMakeCurrent(dummy_hdc, dummy_context) == 0) {
        _ = wglDeleteContext(dummy_context);
        return error.Win32WglMakeCurrentFailed;
    }

    const choose_pf_p = wglGetProcAddress("wglChoosePixelFormatARB");
    const create_ctx_p = wglGetProcAddress("wglCreateContextAttribsARB");
    const swap_interval_p = wglGetProcAddress("wglSwapIntervalEXT");

    _ = wglMakeCurrent(null, null);
    _ = wglDeleteContext(dummy_context);

    const choosePixelFormatARB: ChoosePixelFormatARBFn = @ptrCast(
        choose_pf_p orelse return error.Win32WglChoosePixelFormatARBUnavailable,
    );
    const createContextAttribsARB: CreateContextAttribsARBFn = @ptrCast(
        create_ctx_p orelse return error.Win32WglCreateContextAttribsARBUnavailable,
    );

    const hdc = GetDC(hwnd) orelse return error.Win32GetDCFailed;
    errdefer _ = ReleaseDC(hwnd, hdc);

    const pixel_format_attribs = [_:0]c_int{
        WGL_DRAW_TO_WINDOW_ARB, GL_TRUE,
        WGL_SUPPORT_OPENGL_ARB, GL_TRUE,
        WGL_DOUBLE_BUFFER_ARB,  GL_TRUE,
        WGL_PIXEL_TYPE_ARB,     WGL_TYPE_RGBA_ARB,
        WGL_ACCELERATION_ARB,   WGL_FULL_ACCELERATION_ARB,
        WGL_COLOR_BITS_ARB,     32,
        WGL_DEPTH_BITS_ARB,     24,
        WGL_STENCIL_BITS_ARB,   8,
        WGL_SAMPLE_BUFFERS_ARB, 1,
        WGL_SAMPLES_ARB,        4,
    };

    var format: c_int = 0;
    var num_formats: c_uint = 0;
    if (choosePixelFormatARB(hdc, &pixel_format_attribs, null, 1, @ptrCast(&format), &num_formats) == 0 or num_formats == 0) {
        return error.Win32ChoosePixelFormatARBFailed;
    }

    var pfd: PIXELFORMATDESCRIPTOR = undefined;
    _ = DescribePixelFormat(hdc, format, @sizeOf(PIXELFORMATDESCRIPTOR), &pfd);
    if (SetPixelFormat(hdc, format, &pfd) == 0) {
        return error.Win32SetPixelFormatFailed;
    }

    const WGL_CONTEXT_MAJOR_VERSION_ARB = 0x2091;
    const WGL_CONTEXT_MINOR_VERSION_ARB = 0x2092;
    const WGL_CONTEXT_PROFILE_MASK_ARB = 0x9126;
    const WGL_CONTEXT_CORE_PROFILE_BIT_ARB = 0x00000001;
    const WGL_CONTEXT_FLAGS_ARB = 0x2094;
    const WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB = 0x00000002;
    const WGL_CONTEXT_DEBUG_BIT_ARB = 0x00000001;

    const gl_attribs = [_:0]c_int{
        WGL_CONTEXT_MAJOR_VERSION_ARB, major_version,
        WGL_CONTEXT_MINOR_VERSION_ARB, minor_version,
        WGL_CONTEXT_PROFILE_MASK_ARB,  WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
        WGL_CONTEXT_FLAGS_ARB,         WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB | (if (builtin.mode == .Debug) WGL_CONTEXT_DEBUG_BIT_ARB else 0),
    };

    const hglrc = createContextAttribsARB(hdc, null, &gl_attribs) orelse return error.Win32WglCreateContextAttribsARBFailed;
    errdefer _ = wglDeleteContext(hglrc);
    if (wglMakeCurrent(hdc, hglrc) == 0) {
        return error.Win32WglMakeCurrentFailed;
    }

    if (swap_interval_p) |sp| {
        const swapInterval: SwapIntervalEXTFn = @ptrCast(sp);
        _ = swapInterval(1);
    }

    return .{ .hdc = hdc, .hglrc = hglrc };
}

var win32_opengl32_module: ?*anyopaque = null;

/// GL function loader suitable for passing to glad. Prefers
/// wglGetProcAddress (for GL >= 1.2 / extension functions) and falls
/// back to GetProcAddress on opengl32.dll for older core functions.
pub fn getProcAddress(name: [*:0]const u8) callconv(.c) ?*const fn () callconv(.c) void {
    if (wglGetProcAddress(name)) |p| {
        const addr = @intFromPtr(p);
        if (addr != 0 and addr != 1 and addr != 2 and addr != 3 and addr != std.math.maxInt(usize)) {
            return @ptrCast(p);
        }
    }
    if (win32_opengl32_module == null) {
        win32_opengl32_module = @ptrCast(win32.LoadLibraryA("opengl32.dll"));
    }
    if (win32_opengl32_module) |mod| {
        if (win32.GetProcAddress(@ptrCast(mod), name)) |p| return @ptrCast(p);
    }
    return null;
}
