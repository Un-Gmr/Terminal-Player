@echo off
SETLOCAL ENABLEDELAYEDEXPANSION

where choco >nul 2>&1
IF ERRORLEVEL 1 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "Set-ExecutionPolicy Bypass -Scope Process -Force; ^
         [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; ^
         iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
    exit /b 1
)

where git >nul 2>&1
IF ERRORLEVEL 1 (
    choco install git -y
)

choco install mpv yt-dlp jq curl imagemagick figlet python3 -y

SET PYTHON=%LOCALAPPDATA%\Programs\Python\Python39
IF EXIST "%PYTHON%\Scripts" SET PATH=%PYTHON%\Scripts;%PATH%

python -m pip install --upgrade pip
pip install syncedlyrics

SET DEST=%USERPROFILE%\bin
IF NOT EXIST "%DEST%" mkdir "%DEST%"

COPY play.sh "%DEST%\play.sh"
COPY playlist.sh "%DEST%\playlist.sh"

FOR /F "usebackq tokens=*" %%i IN (`where bash`) DO SET BASH_PATH=%%i
IF NOT DEFINED BASH_PATH exit /b 1

(
echo @echo off
echo "%BASH_PATH%" "%%~dp0play.sh" %%*
) > "%DEST%\play.bat"

(
echo @echo off
echo "%BASH_PATH%" "%%~dp0playlist.sh" %%*
) > "%DEST%\playlist.bat"

ENDLOCAL