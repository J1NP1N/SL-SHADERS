@echo off
setlocal
if "%~1"=="" (
  echo Usage: build-msvc.bat C:\Users\Duck\source\repos\reshade
  exit /b 1
)
set "RESHADE_DIR=%~1"
pushd "%~dp0"
if exist build rmdir /s /q build
cmake -S . -B build -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=Release -DRESHADE_DIR="%RESHADE_DIR%"
if errorlevel 1 (popd & exit /b 1)
cmake --build build
if errorlevel 1 (popd & exit /b 1)
echo.
echo Built: %CD%\build\SLAlphaGTAOHook.addon
popd
endlocal
