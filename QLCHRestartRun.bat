@echo off
setlocal enabledelayedexpansion

:: Đường dẫn file config
set "cfgFile=C:\Tool\QLCHRestart\QLCHRestart.config"

:: Kiểm tra file config tồn tại không
if not exist "%cfgFile%" (
    echo ERROR: Not found file config "%cfgFile%"
    pause
    exit /b 1
)

:: Đọc từng dòng file config
for /f "usebackq tokens=1* delims==" %%A in ("%cfgFile%") do (
    set "line=%%A"
    rem Bỏ qua dòng bắt đầu bằng # hoặc dòng rỗng
    if not "!line:~0,1!"=="#" if not "%%A"=="" (
        rem Gán biến môi trường
        set "%%A=%%B"
    )
)

:: Debug: hiển thị các biến đã đọc được
echo ROOT_DIR=%ROOT_DIR%
echo SCRIPT_PATH=%SCRIPT_PATH%

:: Gán biến để dùng trong script
set "rootFolder=%ROOT_DIR%"
set "scriptPath=%SCRIPT_PATH%"

:: Kiểm tra file script PowerShell tồn tại không
if not exist "%scriptPath%" (
    echo ERROR: Not found file script "%scriptPath%"
    pause
    exit /b 2
)

:: Tạo file VBS tạm để chạy PowerShell với quyền admin và ẩn cửa sổ
set "vbsFile=%temp%\runPSAsAdmin.vbs"

> "%vbsFile%" echo Set UAC = CreateObject^("Shell.Application"^)
>> "%vbsFile%" echo UAC.ShellExecute "powershell.exe", "-ExecutionPolicy Bypass -WindowStyle Hidden -File ""%scriptPath%""", "", "runas", 0

:: Chạy file VBS
cscript //nologo "%vbsFile%"

:: Xoá file VBS sau khi chạy
del "%vbsFile%"

echo Script started: %scriptPath%

pause
exit /b 0
