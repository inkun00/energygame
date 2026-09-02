@echo off
chcp 65001 > nul
echo ====================================================
echo  [에너지 사다리: 에코 히어로즈] 게임을 실행합니다...
echo ====================================================

set "GODOT_EXE="
for /f "delims=" %%G in ('where godot.exe 2^>nul') do if not defined GODOT_EXE set "GODOT_EXE=%%G"
for /f "delims=" %%G in ('dir /b /s "C:\Users\user\Downloads\*godot*.exe" 2^>nul') do if not defined GODOT_EXE set "GODOT_EXE=%%G"

if not exist "%GODOT_EXE%" (
    echo [오류] Godot 실행 파일을 찾을 수 없습니다: %GODOT_EXE%
    pause
    exit /b
)

start "" "%GODOT_EXE%" --path "%~dp0."
