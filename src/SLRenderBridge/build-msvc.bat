@echo off
setlocal enabledelayedexpansion

set "ROOT=%~dp0"
set "RESH=%~1"
if "%RESH%"=="" set "RESH=%RESHADE_SDK_DIR%"
if "%RESH%"=="" (
  echo Usage: build-msvc.bat ^<path-to-reshade-source^>
  echo Or set RESHADE_SDK_DIR.
  exit /b 2
)

where cmake >nul 2>nul || (
  echo ERROR: cmake.exe was not found on PATH.
  exit /b 3
)

set "BUILD=%ROOT%build-msvc"
cmake -S "%ROOT%" -B "%BUILD%" -A x64 -DSLRB_BUILD_ADDON=ON -DSLRB_BUILD_TESTS=ON -DRESHADE_SDK_DIR="%RESH%" || exit /b 4
cmake --build "%BUILD%" --config Release || exit /b 5
ctest --test-dir "%BUILD%" -C Release --output-on-failure || exit /b 6

echo.
echo Output: %BUILD%\Release\SLRenderBridge.addon64
exit /b 0
