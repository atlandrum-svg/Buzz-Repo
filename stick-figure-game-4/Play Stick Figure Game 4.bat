@echo off
setlocal EnableDelayedExpansion
cd /d "%~dp0"

if defined GODOT_PATH if exist "%GODOT_PATH%" (
  start "" "%GODOT_PATH%" --path "%cd%"
  exit /b 0
)

where godot >nul 2>&1
if %ERRORLEVEL%==0 (
  for /f "delims=" %%i in ('where godot') do (
    start "" "%%i" --path "%cd%"
    exit /b 0
  )
)

for %%P in (
  "%USERPROFILE%\Desktop\Stick Figure\Godot_v4.7.1-stable_win64.exe"
  "%USERPROFILE%\Desktop\Godot_v4.7.1-stable_win64.exe"
  "%USERPROFILE%\Downloads\Godot_v4.7.1-stable_win64.exe"
  "%LOCALAPPDATA%\Godot\Godot_v4.7.1-stable_win64.exe"
  "C:\Program Files\Godot\Godot_v4.7.1-stable_win64.exe"
  "C:\Godot\Godot_v4.7.1-stable_win64.exe"
) do (
  if exist %%P (
    start "" %%P --path "%cd%"
    exit /b 0
  )
)

REM Any Godot 4 win64 on Desktop / Downloads
for %%D in ("%USERPROFILE%\Desktop" "%USERPROFILE%\Downloads" "%USERPROFILE%\Desktop\Stick Figure") do (
  if exist %%D (
    for %%F in (%%D\Godot_v4*-stable_win64.exe) do (
      if exist "%%F" (
        start "" "%%F" --path "%cd%"
        exit /b 0
      )
    )
  )
)

echo.
echo Godot 4 not found.
echo 1^) Install Godot 4 from https://godotengine.org/download/windows/
echo 2^) Tell your AI helper to set GODOT_PATH to the full path of Godot_v4*_win64.exe
echo 3^) Or open project.godot in Godot and press F5
echo.
pause
exit /b 1
