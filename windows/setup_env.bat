@echo off

echo Locating latest VS version...
for /f "usebackq tokens=*" %%i in (`"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set VSPATH=%%i

set VSCMD_ARG_TGT_ARCH=
set VSCMD_VER=
set VSCMD_ARG_HOST_ARCH=
set VSINSTALLDIR=
set VCToolsInstallDir=
set VCToolsVersion=
echo Loading cl.exe from vcvars64.bat...
call "%VSPATH%\VC\Auxiliary\Build\vcvars64.bat" >nul
