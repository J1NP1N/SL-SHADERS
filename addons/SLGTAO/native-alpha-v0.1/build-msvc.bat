@echo off
setlocal
if "%~1"=="" (
  echo Usage: build-msvc.bat ^<ReShadeRoot^>
  exit /b 2
)
set "RESHADEROOT=%~1"
if not exist "%RESHADEROOT%\include\reshade.hpp" (
  echo ERROR: reshade.hpp not found at "%RESHADEROOT%\include\reshade.hpp"
  exit /b 3
)
if not exist build mkdir build
cl /nologo /std:c++17 /EHsc /O2 /MD /LD /DWIN32_LEAN_AND_MEAN /DNOMINMAX /I"%RESHADEROOT%\include" SLNativeAlphaLink.cpp /link /OUT:build\SLNativeAlphaLink.addon
if errorlevel 1 exit /b %errorlevel%
echo Built build\SLNativeAlphaLink.addon
endlocal
