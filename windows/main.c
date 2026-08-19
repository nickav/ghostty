#define GHOSTTY_STATIC
#include "ghostty.h"

#include <windows.h>
#include <stdio.h>

#define WM_WAKEUP (WM_APP + 1)

// @Sync: must stay in sync with dist/windows/ghostty.rc's ID_ICON_GHOSTTY
#define ID_ICON_GHOSTTY 1

static ghostty_app_t g_app = NULL;
static ghostty_surface_t g_surface = NULL;


#pragma comment(lib, "opengl32.lib")
extern void WINAPI glViewport(int x, int y, int width, int height);

typedef HRESULT Win32_DwmSetWindowAttribute(HWND hwnd, DWORD dwAttribute, LPCVOID pvAttribute, DWORD cbAttribute);
static Win32_DwmSetWindowAttribute *DwmSetWindowAttribute = NULL;
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

#ifndef PROCESS_SYSTEM_DPI_AWARE
#define PROCESS_SYSTEM_DPI_AWARE 1
#endif

#ifndef DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
#define DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 ((HANDLE) -4)
#endif


static void win32__fatal_error(const char *message)
{
    MessageBoxA(NULL, message, "Error", MB_ICONEXCLAMATION);
    ExitProcess(0);
}

static void win32__toggle_fullscreen(HWND hwnd)
{
    static WINDOWPLACEMENT placement = {0};

    bool is_fullscreen = false;
    {
        MONITORINFO monitor_info = {0};
        monitor_info.cbSize = sizeof(MONITORINFO);
        GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY), &monitor_info);

        RECT rect;
        GetWindowRect(hwnd, &rect);

        is_fullscreen = (
            rect.left == monitor_info.rcMonitor.left
            && rect.right == monitor_info.rcMonitor.right
            && rect.top == monitor_info.rcMonitor.top
            && rect.bottom == monitor_info.rcMonitor.bottom
        );
    }

    DWORD style = GetWindowLong(hwnd, GWL_STYLE);

    if (!is_fullscreen)
    {
        MONITORINFO monitor_info = {sizeof(monitor_info)};

        if (
            GetWindowPlacement(hwnd, &placement) &&
            GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY), &monitor_info)
        ) {
            SetWindowLong(hwnd, GWL_STYLE, style & ~WS_OVERLAPPEDWINDOW);

            SetWindowPos(
                hwnd,
                HWND_TOP,
                monitor_info.rcMonitor.left,
                monitor_info.rcMonitor.top,
                monitor_info.rcMonitor.right  - monitor_info.rcMonitor.left,
                monitor_info.rcMonitor.bottom - monitor_info.rcMonitor.top,
                SWP_NOOWNERZORDER | SWP_FRAMECHANGED
            );
        }
    } else {
        SetWindowLong(hwnd, GWL_STYLE, style | WS_OVERLAPPEDWINDOW);
        SetWindowPlacement(hwnd, &placement);
        DWORD flags = SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED;
        SetWindowPos(hwnd, 0, 0, 0, 0, 0, flags);
    }
}


static void win32__update_theme(HWND hwnd)
{
    BOOL is_light = FALSE;
    DWORD use_light_theme = 0;
    DWORD data_size = sizeof(use_light_theme);
    LSTATUS status = RegGetValueA(
        HKEY_CURRENT_USER,
        "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        "AppsUseLightTheme", RRF_RT_ANY, NULL, &use_light_theme, &data_size);

    if (status == ERROR_SUCCESS) {
        is_light = use_light_theme != 0;
    }

    if (DwmSetWindowAttribute)
    {
        BOOL dark = !is_light;
        DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark, sizeof(dark));
    }

    HBRUSH brush = (HBRUSH)GetStockObject(is_light ? WHITE_BRUSH : BLACK_BRUSH);
    SetClassLongPtrW(hwnd, GCLP_HBRBACKGROUND, (LONG_PTR)brush);
    InvalidateRect(hwnd, NULL, TRUE);
}

static double win32__get_scale_factor(HWND hwnd)
{
    double result = 1.0;

    typedef UINT Win32_GetDpiForWindowType(HWND hwnd);
    static Win32_GetDpiForWindowType *win32_GetDpiForWindow = 0;
    static bool did_load = false;
    if (!did_load)
    {
        HMODULE user32 = LoadLibraryA("user32.dll");
        win32_GetDpiForWindow = (Win32_GetDpiForWindowType *)GetProcAddress(user32, "GetDpiForWindow");
        did_load = true;
    }


    if (win32_GetDpiForWindow == 0)
    {
        // NOTE(nick): I'm pretty sure on windows LOGPIXELSX and LOGPIXELSY are always the same,
        // but @Robustness we should verify this assumption
        HDC hdc = GetDC(hwnd);
        result = (double)GetDeviceCaps(hdc, LOGPIXELSX) / (double)USER_DEFAULT_SCREEN_DPI;
        ReleaseDC(hwnd, hdc);
    }
    else
    {
        result = win32_GetDpiForWindow(hwnd) / (double)USER_DEFAULT_SCREEN_DPI;
    }
    return result;
}

static void wakeup_cb(void *userdata) {
    HWND hwnd = (HWND)userdata;
    PostMessageW(hwnd, WM_WAKEUP, 0, 0);
}

static bool action_cb(
    ghostty_app_t app,
    ghostty_target_s target,
    ghostty_action_s action
) {
    (void)app;

    switch (action.tag)
    {
        case GHOSTTY_ACTION_RENDER:
        {
            if (target.tag == GHOSTTY_TARGET_SURFACE)
            {
                ghostty_surface_draw(target.target.surface);
            }
            return true;
        } break;

        default:
        {
            return false;
        } break;
    }
}

static bool read_clipboard_cb(void *userdata, ghostty_clipboard_e clipboard, void *state)
{
    (void)userdata;
    (void)clipboard;
    (void)state;
    return false;
}

static void confirm_read_clipboard_cb(void *userdata, const char *str, void *state, ghostty_clipboard_request_e request)
{
    (void)userdata;
    (void)str;
    (void)state;
    (void)request;
}

static void write_clipboard_cb(void *userdata, ghostty_clipboard_e clipboard, const ghostty_clipboard_content_s *content, size_t len, bool confirm)
{
    (void)userdata;
    (void)clipboard;
    (void)content;
    (void)len;
    (void)confirm;
}

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam)
{
    switch (msg) {
        case WM_CREATE:
        {
            win32__update_theme(hwnd);
        } break;

        case WM_DESTROY:
        {
            if (g_surface) {
                ghostty_surface_free(g_surface);
                g_surface = NULL;
            }
            if (g_app) {
                ghostty_app_free(g_app);
                g_app = NULL;
            }
            PostQuitMessage(0);
            return 0;
        } break;

        case WM_SETTINGCHANGE:
        {
            if (lparam && lstrcmpiW((LPCWSTR)lparam, L"ImmersiveColorSet") == 0)
            {
                win32__update_theme(hwnd);
            }
        } break;

        case WM_DWMCOLORIZATIONCOLORCHANGED:
        {
            win32__update_theme(hwnd);
        } break;

        case WM_WAKEUP:
        {
            if (g_app) {
                ghostty_app_tick(g_app);
            }
            return 0;
        } break;

        case WM_SIZE:
        {
            uint32_t width = (uint32_t)LOWORD(lparam);
            uint32_t height = (uint32_t)HIWORD(lparam);

            if (g_surface)
            {
                ghostty_surface_set_size(g_surface, width, height);
                // @Robustness: make this a proper callback somehow into ghostty?
                glViewport(0, 0, (int)width, (int)height);
                ghostty_surface_draw(g_surface);
            }
            return 0;
        } break;

        case WM_DPICHANGED:
        {
            // Resize windowed mode windows that either permit rescaling or that
            // need it to compensate for non-client area scaling
            RECT *suggested = (RECT *)lparam;
            SetWindowPos(hwnd, HWND_TOP,
                            suggested->left,
                            suggested->top,
                            suggested->right - suggested->left,
                            suggested->bottom - suggested->top,
                            SWP_NOACTIVATE | SWP_NOZORDER);

            double scale = (double)LOWORD(wparam) / (double)USER_DEFAULT_SCREEN_DPI;
            if (g_surface)
            {
                ghostty_surface_set_content_scale(g_surface, scale, scale);
            }
        } break;

        case WM_GETMINMAXINFO:
        {
            // NOTE(nick): set window minimum size
            /*
            DWORD style = WS_OVERLAPPEDWINDOW;
            RECT wr = {0, 0, (LONG)game_width, (LONG)game_height};
            AdjustWindowRect(&wr, style, FALSE);
            int width = (int)(wr.right - wr.left);
            int height = (int)(wr.bottom - wr.top);

            MINMAXINFO *info = (MINMAXINFO *)lparam;
            info->ptMinTrackSize.x = width;
            info->ptMinTrackSize.y = height;
            return 0;
            */
        } break;

        case WM_SYSCOMMAND:
        {
            switch (wparam)
            {
                // User trying to access application menu using ALT
                case SC_KEYMENU: {
                    // NOTE(nick): prevent beep sound when pressing alt key combo (e.g. alt + enter)
                    return 0;
                } break;
            }
        } break;

        case WM_SYSKEYDOWN:
        case WM_SYSKEYUP:
        case WM_KEYDOWN:
        case WM_KEYUP:
        {
            bool was_down = !!(lparam & (1u << 30));
            bool is_down  =  !(lparam & (1u << 31));
            bool key_released    = (msg == WM_KEYUP || msg == WM_SYSKEYUP);

            // NOTE(nick): this is expected of windows apps in general -- but is this something that ghostty wants us to not do for whatever reason?
            if (!was_down && is_down)
            {
                if (wparam == VK_F11)
                {
                    win32__toggle_fullscreen(hwnd);
                }

                if ((GetKeyState(VK_MENU) & 0x8000) && wparam == VK_RETURN)
                {
                    win32__toggle_fullscreen(hwnd);
                }
            }

            // Send keyboard events to ghostty
            ghostty_input_mods_e mods = GHOSTTY_MODS_NONE;
            if (GetKeyState(VK_CONTROL) < 0) mods |= GHOSTTY_MODS_CTRL;
            if (GetKeyState(VK_SHIFT) < 0) mods |= GHOSTTY_MODS_SHIFT;
            if (GetKeyState(VK_MENU) < 0) mods |= GHOSTTY_MODS_ALT;
            if (GetKeyState(VK_LWIN) < 0 || GetKeyState(VK_RWIN) < 0) mods |= GHOSTTY_MODS_SUPER;

            uint32_t scan_code = (lparam >> 16) & 0xFF;
            bool extended = (lparam >> 24) & 1;
            uint32_t native_keycode = scan_code | (extended ? 0xE000u : 0u);

            uint32_t unshifted = 0;
            {
                UINT result = MapVirtualKeyW((UINT)wparam, MAPVK_VK_TO_CHAR);
                uint32_t cp = result & 0xFFFF; // high bit = dead key, ignore for now
                if (cp > 0) unshifted = cp;
            }

            ghostty_input_key_s event;
            ZeroMemory(&event, sizeof(event));

            event.action = key_released ? GHOSTTY_ACTION_RELEASE : was_down ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS;
            event.mods = mods;
            event.consumed_mods = GHOSTTY_MODS_NONE;
            event.keycode = native_keycode;
            event.text = NULL;
            event.unshifted_codepoint = unshifted;
            event.composing = false;

            if (g_surface) {
                ghostty_surface_key(g_surface, event);
            }
        } break;

        case WM_SYSCHAR:
        case WM_CHAR:
        {
            // Send text events to ghostty
            static WCHAR g_high_surrogate = 0;
            WCHAR ch = (WCHAR)wparam;
            if (ch >= 0xD800 && ch <= 0xDBFF) {
                g_high_surrogate = ch;
                return 0;
            }

            uint32_t codepoint;
            if (ch >= 0xDC00 && ch <= 0xDFFF && g_high_surrogate != 0) {
                codepoint = 0x10000 + (((uint32_t)g_high_surrogate - 0xD800) << 10) + ((uint32_t)ch - 0xDC00);
            } else {
                codepoint = ch;
            }
            g_high_surrogate = 0;

            if (codepoint == '\r') codepoint = '\n';
            if ((codepoint >= 32 && codepoint != 127) || codepoint == '\t' || codepoint == '\n') {
                char utf8[4];
                int len = WideCharToMultiByte(CP_UTF8, 0, &ch, 1, utf8, sizeof(utf8), NULL, NULL);
                if (g_surface && len > 0) {
                    ghostty_surface_text(g_surface, utf8, (uintptr_t)len);
                }
            }
            return 0;
        } break;

        case WM_UNICHAR:
        {
            /*
            if (w_param == UNICODE_NOCHAR)
            {
                // WM_UNICHAR is not sent by Windows, but is sent by some
                // third-party input method engine
                // Returning TRUE here announces support for this message
                result = true;
            }
            else
            {
                u32 codepoint = (u32)w_param;
                if (codepoint == '\r')
                {
                    codepoint = '\n';
                }

                // NOTE(nick): filter out non display characters (e.g. backspace)
                if ((codepoint >= 32 && codepoint != 127) || (codepoint == '\t' || codepoint == '\n'))
                {
                }
            }
            */
        } break;

        case WM_LBUTTONDOWN:
        case WM_LBUTTONUP:
        case WM_RBUTTONDOWN:
        case WM_RBUTTONUP:
        case WM_MBUTTONDOWN:
        case WM_MBUTTONUP:
        case WM_XBUTTONDOWN:
        case WM_XBUTTONUP:
        {
            // @Incomplete:
        } break;

        case WM_MOUSEMOVE:
        {
            /*
            int x = GET_X_LPARAM(lparam);
            int y = GET_Y_LPARAM(lparam);
            WPARAM keys = wparam;
            */
        } break;

        case WM_IME_REQUEST:
        {
            /*
            switch (w_param)
            {
                case IMR_QUERYCHARPOSITION:
                {
                    IMECHARPOSITION *char_pos = (IMECHARPOSITION *)l_param;
                    char_pos->dwSize = sizeof(IMECHARPOSITION);
                    char_pos->pt.x = 0;
                    char_pos->pt.y = 0;
                    // char_pos->cLineHeight = ;
                    // char_pos->rcDocument.left = ;
                    // char_pos->rcDocument.top = ;
                    // char_pos->rcDocument.right = ;
                    // char_pos->rcDocument.bottom = ;

                    result = true;
                } break;
            }
            */
        } break;

        case WM_DROPFILES:
        {
        } break;
    }

    return DefWindowProcW(hwnd, msg, wparam, lparam);
}

int main(int argc, char **argv) {
    if (ghostty_init((uintptr_t)argc, argv) != 0) {
        fprintf(stderr, "ghostty_init failed\n");
        return 1;
    }

    // NOTE(nick): Set DPI Awareness
    {
        HMODULE user32 = LoadLibraryA("user32.dll");

        typedef BOOL Win32_SetProcessDpiAwarenessContext(HANDLE);
        typedef BOOL Win32_SetProcessDpiAwareness(int);

        Win32_SetProcessDpiAwarenessContext *SetProcessDpiAwarenessContext = (Win32_SetProcessDpiAwarenessContext *) GetProcAddress(user32, "SetProcessDpiAwarenessContext");
        Win32_SetProcessDpiAwareness *SetProcessDpiAwareness = (Win32_SetProcessDpiAwareness *) GetProcAddress(user32, "SetProcessDpiAwareness");

        if (SetProcessDpiAwarenessContext) {
            SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        } else if (SetProcessDpiAwareness) {
            SetProcessDpiAwareness(PROCESS_SYSTEM_DPI_AWARE);
        } else {
            SetProcessDPIAware();
        }
    }

    // NOTE(nick): Set Dark Mode Awareness
    {
        typedef DWORD WINAPI Win32_SetPreferredAppMode(DWORD);
        HMODULE uxtheme = LoadLibraryExA("uxtheme.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
        if (uxtheme)
        {
            // @Robustness: is this the expected way to call this?
            Win32_SetPreferredAppMode *SetPreferredAppMode = (Win32_SetPreferredAppMode *)GetProcAddress(uxtheme, MAKEINTRESOURCEA(135));
            if (SetPreferredAppMode)
            {
                SetPreferredAppMode(1);
            }
        }
    }

    // NOTE(nick): load function for dark theme
    HMODULE dwmapi = LoadLibraryA("dwmapi.dll");
    if (dwmapi)
    {
        DwmSetWindowAttribute = (Win32_DwmSetWindowAttribute *)GetProcAddress(dwmapi, "DwmSetWindowAttribute");
    }

    HINSTANCE hinstance = GetModuleHandleW(NULL);

    HICON icon = LoadIconW(hinstance, MAKEINTRESOURCEW(ID_ICON_GHOSTTY));
    if (!icon) {
        fprintf(stderr, "LoadIconW failed err=%lu\n", GetLastError());
    }

    WNDCLASSEXW wc;
    ZeroMemory(&wc, sizeof(wc));
    wc.cbSize = sizeof(wc);
    // CS_OWNDC: we need a stable per-window DC for the WGL context.
    wc.style = CS_OWNDC;
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hinstance;
    wc.hIcon = icon;
    wc.hCursor = LoadCursorW(NULL, IDC_ARROW);
    wc.lpszClassName = L"GhosttyWindowClass";
    wc.hIconSm = icon;
    if (!RegisterClassExW(&wc)) {
        fprintf(stderr, "RegisterClassExW failed\n");
        win32__fatal_error("RegisterClassExW failed");
        return 1;
    }

    HWND hwnd = CreateWindowExW(
        0,
        L"GhosttyWindowClass",
        L"Ghostty",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT,
        1024, 768,
        NULL, NULL, hinstance, NULL
    );
    if (!hwnd) {
        fprintf(stderr, "CreateWindowExW failed\n");
        win32__fatal_error("CreateWindowExW failed");
        return 1;
    }

    // DragAcceptFiles(hwnd, TRUE);

    ghostty_config_t config = ghostty_config_new();
    ghostty_config_load_default_files(config);
    ghostty_config_finalize(config);

    ghostty_runtime_config_s runtime_config;
    ZeroMemory(&runtime_config, sizeof(runtime_config));
    runtime_config.userdata = hwnd;
    runtime_config.wakeup_cb = wakeup_cb;
    runtime_config.action_cb = action_cb;
    runtime_config.read_clipboard_cb = read_clipboard_cb;
    runtime_config.confirm_read_clipboard_cb = confirm_read_clipboard_cb;
    runtime_config.write_clipboard_cb = write_clipboard_cb;

    g_app = ghostty_app_new(&runtime_config, config);
    if (!g_app) {
        fprintf(stderr, "ghostty_app_new failed\n");
        return 1;
    }

    ghostty_surface_config_s surface_config = ghostty_surface_config_new();
    surface_config.platform_tag = GHOSTTY_PLATFORM_WINDOWS;
    surface_config.platform.windows.hwnd = hwnd;
    surface_config.userdata = hwnd;
    surface_config.scale_factor = win32__get_scale_factor(hwnd);

    g_surface = ghostty_surface_new(g_app, &surface_config);
    if (!g_surface) {
        fprintf(stderr, "ghostty_surface_new failed\n");
        return 1;
    }

    // The window's initial WM_SIZE fired during CreateWindowExW, before
    // g_surface existed, so give the surface its real client size now.
    RECT client_rect;
    GetClientRect(hwnd, &client_rect);
    ghostty_surface_set_size(
        g_surface,
        (uint32_t)(client_rect.right - client_rect.left),
        (uint32_t)(client_rect.bottom - client_rect.top)
    );

    ShowWindow(hwnd, SW_SHOWDEFAULT);
    UpdateWindow(hwnd);

    MSG msg;
    while (GetMessageW(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    ghostty_config_free(config);
    return 0;
}
