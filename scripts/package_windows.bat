@echo off
setlocal enabledelayedexpansion

echo ==========================================================
echo  CastSprint for Windows — Automated Packaging & Release   
echo  Version: 0.2.0                                           
echo ==========================================================

set ROOT_DIR=%~dp0..
set BUILD_DIR=%ROOT_DIR%\build
set DIST_DIR=%ROOT_DIR%\dist\windows
set PKG_DIR=%DIST_DIR%\CastSprint-v0.2.0-Windows-x64

echo ==^> 1. Configuring CMake for Visual Studio 2022 (x64)...
cmake -S "%ROOT_DIR%" -B "%BUILD_DIR%" -G "Visual Studio 17 2022" -A x64
if errorlevel 1 goto error

echo ==^> 2. Building CastSprint Windows Receiver (Release)...
cmake --build "%BUILD_DIR%" --config Release --target castsprint_receiver --parallel
if errorlevel 1 goto error

echo ==^> 3. Running Smoke Test...
"%BUILD_DIR%\apps\windows\Release\castsprint_receiver.exe" --smoke-test
if errorlevel 1 goto error

echo ==^> 4. Assembling Standalone Package...
if exist "%PKG_DIR%" rd /s /q "%PKG_DIR%"
mkdir "%PKG_DIR%"
mkdir "%PKG_DIR%\docs"

copy "%BUILD_DIR%\apps\windows\Release\castsprint_receiver.exe" "%PKG_DIR%\"
copy "%ROOT_DIR%\README.md" "%PKG_DIR%\"
copy "%ROOT_DIR%\LICENSE" "%PKG_DIR%\"
copy "%ROOT_DIR%\docs\OBS_GUIDE.md" "%PKG_DIR%\docs\"
copy "%ROOT_DIR%\docs\USB_CONNECTION.md" "%PKG_DIR%\docs\"
copy "%ROOT_DIR%\docs\WIFI_CONNECTION.md" "%PKG_DIR%\docs\"
copy "%ROOT_DIR%\docs\TROUBLESHOOTING.md" "%PKG_DIR%\docs\"

echo ==^> 5. Creating ZIP Archive via PowerShell...
powershell -Command "Compress-Archive -Path '%PKG_DIR%\*' -DestinationPath '%DIST_DIR%\CastSprint-v0.2.0-Windows-x64.zip' -Force"
powershell -Command "Get-FileHash '%DIST_DIR%\CastSprint-v0.2.0-Windows-x64.zip' -Algorithm SHA256 | Out-File '%DIST_DIR%\CastSprint-v0.2.0-Windows-x64.zip.sha256'"

echo ==^> 6. Compiling Inno Setup Installer (if ISCC available)...
set ISCC="C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if exist %ISCC% (
    %ISCC% "%ROOT_DIR%\installer\castsprint_installer.iss"
    if exist "%BUILD_DIR%\installer\CastSprint_Setup_v0.2.0_Beta_x64.exe" (
        copy "%BUILD_DIR%\installer\CastSprint_Setup_v0.2.0_Beta_x64.exe" "%DIST_DIR%\"
        powershell -Command "Get-FileHash '%DIST_DIR%\CastSprint_Setup_v0.2.0_Beta_x64.exe' -Algorithm SHA256 | Out-File '%DIST_DIR%\CastSprint_Setup_v0.2.0_Beta_x64.exe.sha256'"
    )
) else (
    echo Note: Inno Setup 6 not found in default path. Skipping installer EXE generation.
)

echo ==========================================================
echo  CastSprint Windows distribution package ready!           
echo  Package: %DIST_DIR%\CastSprint-v0.2.0-Windows-x64.zip    
echo ==========================================================
exit /b 0

:error
echo [ERROR] Build or packaging failed.
exit /b 1
