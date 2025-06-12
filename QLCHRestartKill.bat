@echo off
setlocal enabledelayedexpansion

:: Đường dẫn file config
set "cfgFile=C:\Tool\QLCH\QLCHRestart\Config\QLCHRestart.cfg"

:: Kiểm tra file config tồn tại không
if not exist "%cfgFile%" (
    echo ERROR: Not found file config "%cfgFile%"
    pause
    exit /b 1
)

:: Đọc từng dòng file cfg
for /f "usebackq tokens=1* delims==" %%A in ("%cfgFile%") do (
    set "line=%%A"
    :: Bỏ qua dòng bắt đầu bằng # hoặc dòng rỗng
    if not "!line:~0,1!"=="#" if not "%%A"=="" (
        :: Gán biến môi trường
        set "%%A=%%B"
    )
)

:: Debug: hiển thị các biến đã đọc được
echo REG_PATH=%REG_PATH%
echo REG_KEY_PID=%REG_KEY_PID%

:: Gán biến
set "regFullPath=%REG_TYPE%\%REG_PATH%"
set "regKey=%REG_KEY_PID%"

:: Truy vấn registry
for /f "tokens=1,2,3" %%A in ('reg query "%regFullPath%" /v %regKey% 2^>nul') do (
    if /i "%%A"=="%regKey%" (
        set "PID_HEX=%%C"
    )
)

:: Chuyển HEX sang DEC và kill
if defined PID_HEX (
    set /a PID_DEC=%PID_HEX%
    echo Found %regKey%: !PID_DEC!
    taskkill /PID !PID_DEC! /F
) else (
    echo PID not found in registry.
)

endlocal
pause
