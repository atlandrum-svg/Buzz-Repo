@echo off
setlocal
cd /d "%~dp0"

if defined GODOT_PATH (
  if exist "%GODOT_PATH%" (
    start "" "%GODOT_PATH%" --path "%cd%"
    exit /b 0
  )
)

where godot >nul 2>&1
if %ERRORLEVEL%==0 (
  start "" godot --path "%cd%"
  exit /b 0
)

if exist "%USERPROFILE%\Desktop\Stick Figure\Godot_v4.7.1-stable_win64.exe" (
  start "" "%USERPROFILE%\Desktop\Stick Figure\Godot_v4.7.1-stable_win64.exe" --path "%cd%"
  exit /b 0
)

if exist "%USERPROFILE%\Desktop\Godot_v4.7.1-stable_win64.exe" (
  start "" "%USERPROFILE%\Desktop\Godot_v4.7.1-stable_win64.exe" --path "%cd%"
  exit /b 0
)

echo.
echo Godot 4 not found.
echo Install Godot 4.x, then either:
echo   - Add the Godot executable to PATH as "godot", or
echo   - Set env var GODOT_PATH to the full path of Godot_v4.x_win64.exe
echo.
echo Or open project.godot in the Godot Project Manager.
pause
exit /b 1
