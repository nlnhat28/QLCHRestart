## Mô tả chung
- Do có lần bị lỗi fileshare, các service triển khai trên IIS không đọc được config, dẫn đến Application Pools bị Stop, phần mềm không hoạt động
- Nên cần tạo file powershell, chạy ngầm để mỗi 1 khoảng thời gian sẽ check Event Viewer xem có log lỗi config không, nếu có sẽ restart máy và Start lại Application Pools

## Chi tiết các file
<pre>
├── QLCHRestartRun.bat
├── QLCHRestartKill.bat
├── Core
│   └── QLCHRestart.ps1
├── Config
│   └── QLCHRestart.config
├── Log
│   └── QLCHRestart.log
├── Util
│   └── QLCHCreateFakeEvent.bat
└── README.md </pre>

* `QLCHRestartRun.bat`: Dùng để chạy file powershell trên
* `QLCHRestartKill.bat`: Kill process powershell sau khi chạy
* `QLCHRestart.ps1`: File powershell chính, xử lý các nghiệp vụ
* `QLCHRestart.config`: Chứa config
* `QLCHRestart.log`: Chứa log
* `QLCHCreateFakeEvent.bat`: Giả lập tạo log vào Event Viewer

## Các bước thực hiện

1. Để ổn định thì chỉ để 1 process của script này chạy. Vào Task Manager -> Details, tìm powershell.exe, xem có process nào của cái này đang chạy không, có thì kill rồi chạy hoặc để chạy tiếp không chạy thêm nữa.
2. Chạy file `QLCHRestartRun.bat`. Chọn Run as Administrator cho Windows Powershell
3. Để kill thì chạy file `QLCHRestartKill.bat` (Run as Administrator)

