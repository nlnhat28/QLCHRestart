# Chạy với quyền Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run as Administrator to execute!" -ForegroundColor Red
    exit
}

# Đọc cấu hình từ file
$configFile = "C:\Tool\QLCH\QLCHRestart\Config\QLCHRestart.config"
$config = @{}
try {
    Get-Content $configFile | Where-Object { $_ -match "=" } | ForEach-Object {
        $parts = $_ -split "=", 2
        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        $config[$key] = $value
    }
} catch {
    Write-Host "Error reading file config: $_" -ForegroundColor Red
    exit
}
# Thư mục chứa script và log
$rootDir = $config["ROOT_DIR"]
# Đường dẫn đến file script
$scriptPath = $config["SCRIPT_PATH"]
# Đường dẫn đến file log
$logPath = $config["LOG_PATH"]
# Loại registry
$regType = $config["REG_TYPE"]
# Đường dẫn đến registry
$regPath = $config["REG_PATH"]
$regFullPath = "$regType`:\$regPath"
# Đường dẫn đến registry
$regKeyPID = $config["REG_KEY_PID"]

# PID của script hiện tại
$thisPID = $PID
# Thời gian lặp lại kiểm tra log event viewer (giây)
$loopSeconds = 60
# Thời gian lấy log so với thời điểm hiện tại (giây)
$offsetSeconds = $loopSeconds + 1
# Thời gian chờ trước khi bắt đầu script (giây)
$startupDelaySeconds = 10

# Cấu hình event cần theo dõi
# Level của event. 1: Warning, 2: Error, 4: Information
$eventLevel = 2
# ID của event
$eventID = 230
# Nội dung cần tìm trong message của event
$eventMessage = "Configuration file is not well-formed XML"

Write-Host "Script started"

# Deley trước khi bắt đầu script
Start-Sleep -Seconds $startupDelaySeconds

# Tạo thư mục chứa log nếu chưa có
try {
    if (-not (Test-Path $rootDir)) {
        New-Item -ItemType Directory -Path $rootDir -Force | Out-Null
        Write-Host "Created log folder: $rootDir"
    }
} catch {
    Write-Host "Cannot create log folder $rootDir. $_" -ForegroundColor Red
}

# Hàm ghi log
function Write-Log {
    param (
        [string]$message,
        [string]$level = "Info"
    )
    try {
        $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
        $fullMessage = "[$timestamp] [$level] [$thisPID] $message"
        Write-Host $fullMessage
        $fullMessage | Out-File -FilePath $logPath -Append -Encoding UTF8
    }
    catch {
        Write-Host "Write-Log: $_" -ForegroundColor Red
    }
}

# Lưu PID vào registry
function Save-PID {
    try {
        # Kiểm tra và tạo registry key nếu chưa có
        if (-not (Test-Path $regFullPath)) {
            New-Item -Path $regFullPath -Force | Out-Null
            New-ItemProperty -Path $regFullPath -Name "$regKeyPID" -Value $thisPID -PropertyType String -Force

            Write-Log "Created registry key: $regFullPath"
        }
        # Lưu PID vào registry
        New-ItemProperty -Path $regFullPath -Name "$regKeyPID" -Value $thisPID -PropertyType String -Force | Out-Null

        Write-Log "Saved PID $thisPID to registry at $regFullPath"
    } catch {
        Write-Log "Save-PID: $_" "Error"
    }
}

# Hàm kiểm tra và khởi động lại IIS sau khi restart
function Start-IISServer {
    try {
        $iisStatus = Get-Service W3SVC -ErrorAction Stop
        if ($iisStatus.Status -ne 'Running') {
            Write-Log "W3SVC not running. Attempting to start..."
            Start-Service W3SVC -ErrorAction Stop
            Start-Sleep -Seconds 3
        } else {
            Write-Log "W3SVC is already running"
        }

        if (Get-Module -ListAvailable -Name WebAdministration) {
            Import-Module WebAdministration -ErrorAction Stop

            # Start App Pools
            Get-ChildItem IIS:\AppPools | Where-Object { $_.State -ne "Started" } | ForEach-Object {
                Write-Log "Starting Application Pool: $($_.Name)"
                Start-WebAppPool -Name $_.Name
            }

            # Start Sites
            Get-Website | Where-Object { $_.State -ne "Started" } | ForEach-Object {
                Write-Log "Starting Site: $($_.Name)"
                Start-Website -Name $_.Name
            }
        } else {
            Write-Log "Start-IISServer: WebAdministration module not available" "Error"
        }
    } catch {
        Write-Log "Start-IISServer: $_" "Error"
    }
}

# Hàm tạo task tự động chạy script này sau khi khởi động
function Create-ScheduledTask {
    try {
        $taskName = "QLCHRestartTask"
        # $taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        $taskExists = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {$_.TaskName -eq $taskName -and ($_.State -eq 'Ready' -or $_.State -eq 'Running')}
        if (-not $taskExists) {
            # Chạy không ẩn
            # $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$scriptPath`""
            # Chạy ẩn
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
            $trigger = New-ScheduledTaskTrigger -AtLogOn
            $settings = New-ScheduledTaskSettingsSet `
                -AllowStartIfOnBatteries `
                -DontStopIfGoingOnBatteries `
                -StartWhenAvailable `
                -ExecutionTimeLimit ([TimeSpan]::Zero) `
                -MultipleInstances IgnoreNew

            Register-ScheduledTask -Action $action `
                                   -Trigger $trigger `
                                   -Settings $settings `
                                   -TaskName $taskName `
                                   -Description "Check Event Viewer and restart IIS if needed" `
                                   -RunLevel Highest `
                                   -Force

            Write-Log "Scheduled task '$taskName' created to auto-run at log on"
        } else {
            Write-Log "Scheduled task '$taskName' already exists. Will run at log on"
        }
    } catch {
        Write-Log "Create-ScheduledTask: $_" "Error"
    }
}

# Hàm kiểm tra log event viewer để restart máy
function DoWork-CheckLog {
    try {
        Write-Log "Checking events every $loopSeconds seconds for events with ID $eventID and message containing '$eventMessage'..."
        while ($true) {
            try {
                Write-Log "In loop"

                Start-Sleep -Seconds $loopSeconds

                $now = Get-Date
                $fromTime = $now.AddSeconds(-$offsetSeconds)

                # Lấy event có:
                # - Level là $eventLevel (2: Error)
                # - ID là $eventID (2307 lỗi file config)
                # - Message chứa $eventMessage ("Configuration file is not well-formed XML")
                # - Thời gian của event cách hiện tại $offsetSeconds (61s)
                $events = Get-WinEvent -FilterHashtable @{
                    LogName = 'Application';
                    Level = $eventLevel;
                    Id = $eventID;
                    StartTime = $fromTime
                } -ErrorAction SilentlyContinue | Where-Object {
                    $_.Message -like "*$eventMessage*"
                }

                if ($events) {
                    # Log lại các event và restart máy
                    foreach ($event in $events) {
                        Write-Log "Event found: ID=$($event.Id), Time=$($event.TimeCreated), Message=$($event.Message)" "Error"
                    }
                    Write-Log "Restarting computer." "Warn"
                    Restart-Computer -Force
                    exit
                } 
            } catch {
                Write-Log "DoWork-CheckLog in loop: $_" "Error"
            }
        }
    } catch {
        Write-Log "DoWork-CheckLog: $_" "Error"
    }
}

# Bắt đầu thực hiện
Write-Log "PID: $thisPID. Start process"

# Lưu PID vào registry, phục vụ kill script này
Save-PID

# Khởi động lại IIS sau khi restart
Start-IISServer

# Tạo task tự động chạy script này sau khi khởi động
Create-ScheduledTask

# Chạy vòng lặp kiểm tra log event viewer
DoWork-CheckLog



