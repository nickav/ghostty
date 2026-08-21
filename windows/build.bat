@echo off

set project_root=%~dp0%..
pushd %project_root%

    rem Make sure libghostty is built
    if not exist .\zig-out\lib\ghostty-internal-static.lib (
        zig build -Dapp-runtime=none -Doptimize=ReleaseFast
    )

    rem Make sure the current session has the latest cl.exe
    for /f "usebackq tokens=*" %%i in (`"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set VSPATH=%%i
    where cl.exe 2>nul | findstr /I /C:"%VSPATH%" >nul
    if %errorlevel% NEQ 0 (
        echo cl.exe was not found or doesn't match Zig's version
        echo    vcvarsall.bat can be quite slow unfortunately
        echo    to speed this up you may run .\windows\setup_env.bat from a Command Prompt _once_

        call .\windows\setup_env.bat
    )

    rem Build windows app
    if not exist zig-out\bin mkdir zig-out\bin
    if not exist zig-out\obj mkdir zig-out\obj

    rc.exe /nologo /fo zig-out\obj\ghostty.res dist\windows\ghostty.rc

    IF %errorlevel% NEQ 0 (popd && goto end)

    rem @Incomplete: should we put this in zig-out or somewhere else?
    rem At the moment, this is clobbering the actual target built on windows with zig:
    rem zig build
    cl.exe /nologo /std:c11 /Iinclude ^
        windows\src\main.c ^
        /link ^
        zig-out\lib\ghostty-internal-static.lib zig-out\obj\ghostty.res ^
        user32.lib gdi32.lib kernel32.lib advapi32.lib shell32.lib ole32.lib opengl32.lib ws2_32.lib mswsock.lib bcrypt.lib ntdll.lib ^
        -subsystem:windows -incremental:no -opt:ref -OUT:zig-out\bin\ghostty.exe

    IF %errorlevel% NEQ 0 (popd && goto end)

    rem Run
    .\zig-out\bin\ghostty.exe

    :end
popd
exit /B %errorlevel%
