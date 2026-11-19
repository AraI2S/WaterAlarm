WaterAlarm · Windows PowerShell 5.1 绿色免安装版
版本：v1.0.0（2026-11-16）
授权：MIT（见 LICENSE.txt）

一、使用方法

1. 解压整个文件夹到可写目录，例如 D:\Tools\WaterAlarm（不要只拿出一个 .ps1）。
2. 如旧的 AutoHotkey WaterAlarm.ahk 仍在运行，请先从 AHK 托盘图标退出旧版，否则两个版本会同时提醒。
3. 双击 Main.vbs 启动，通常不出现任何命令行窗口。随后在任务栏右下角的隐藏图标区域找到托盘图标。
   Main.cmd 也能启动，而且无需 Windows Script Host，但由于 .cmd/启动器属于控制台程序，双击时可能短暂闪现黑框；建议使用 Main.vbs。
4. 右键托盘图标：
   “立即预览提醒”：手动显示一次提醒，不影响每日计划。
   “暂停提醒 / 恢复提醒”：切换当前进程的定时提醒状态；暂停时托盘图标显示警告图案。
   “编辑配置（重启生效）”：打开 Config.json，保存后需重新启动程序。
   “打开运行日志”：查看 WaterAlarm.log。
   “退出”：彻底退出后台常驻程序。
   双击托盘图标也能预览提醒。
5. 若需要开机自启，Win+R 输入 shell:startup，将 Main.vbs 的快捷方式放到打开的启动目录。
   不要同时给旧 AHK 和新版设置自启。

二、保留的原版行为（依据上传的 Legacy/WaterAlarm.ahk 原文件逐项核对）

每天 7 个提醒时间：10:20、11:10、14:30、15:40、16:30、17:20、18:10。
注意：更早的聊天记录里曾出现“14:50”，但本次实际上传的 AHK 文件写的是“14:30”。
本次迁移严格保留上传文件的 14:30；若想改回 14:50，只编辑 Config.json 中的对应项。

- 本地系统时钟每 5 秒检查一次；同一日期、同一计划时间只触发一次。
- 不设启动时测试弹窗，正式时间点到达时才自动显示。
- 完全无主动播放声音：不用 SoundBeep、MessageBox、Toast、TrayTip 等提醒机制。
- 绿色无边框卡片，主屏幕几何中心，始终置顶、不抢键盘焦点；主文字水平/垂直居中，下面另有“点击关闭”。
- 鼠标点击卡片任意位置（含文字和底部说明）关闭；20 秒后自动关闭。
- 程序常驻期间除了到点弹出的绿色卡片，仅显示托盘图标；没有持续控制台窗口。
- 单实例：再次启动会通过命名事件通知之前的同版本进程退出，并等待互斥锁交接。

三、移植后的可见变化

- 不需要安装 AutoHotkey，也没有封装 EXE；使用 Windows 自带 Windows PowerShell 5.1、WinForms 与内嵌 Add-Type C# 调用 Win32 API。
- 新增右键托盘菜单：预览、暂停/恢复、编辑配置、日志和退出。没有任何热键，也不会拦截键盘输入。
- 暂停状态仅在当前进程内有效；退出或重新启动会恢复正常提醒。手动预览在暂停期间仍能用。
- 旧版 #SingleInstance Force 由命名 Mutex + 停止事件替代。仅管理当前新版本自己的进程，不能自动结束仍在运行的旧 AHK。
- 旧版时间和外观已一次性迁入 Config.json，旧脚本原始字节保存在 Legacy/WaterAlarm.ahk（不再自动读取、更不会修改）。
- 新版还会把错误、启动、计划提醒及暂停/恢复动作写入 WaterAlarm.log；正常无错误时也有日志。
- DPI 使用 Windows 10 1703+ 的 Per-Monitor V2：启动时先调用 SetProcessDpiAwarenessContext(-4)，无论进程默认模式是否已由 manifest 固定，随后用 SetThreadDpiAwarenessContext(-4) 确保 UI 线程采用 PMv2，再加载 WinForms；弹窗建立句柄后用 GetDpiForWindow 获取主显示器 DPI，按比例调整尺寸并居中。不同缩放比例的细节以实机验收为准。

四、文件列表

Main.vbs         推荐双击入口（Windows Script Host 隐藏启动器）
Main.cmd         独立于 WSH 的可选启动入口（可能短暂闪一下 CMD/PowerShell）
Launcher.ps1     使用 ProcessStartInfo.UseShellExecute=false 和 CreateNoWindow=true 启动常驻进程
WaterAlarm.ps1   源码主体，WinForms 托盘、定时器、互斥锁、绿色提醒窗、DPI 调用
Config.json      提醒时间、显示文字、持续时间、视觉设置
Check.cmd        手动校验 Config.json，打开控制台显示 PASS/FAIL；不启动后台常驻进程
Legacy/WaterAlarm.ahk 原版留存，内容未修改
LICENSE.txt      MIT 开源许可
WaterAlarm.log   正常启动后自动生成的运行日志
WaterAlarm-launch-error.log 只有启动器遇到错误才自动生成

五、配置说明（编辑 Config.json 后需重启）

schemaVersion：配置格式版本，目前必须为 1。
times：使用 24 小时制 HH:mm，例如 "14:30"；1~48 个时间点，不允许重复。
message、hint：主提醒文字和底部提示语。
durationSeconds：弹窗自动消失秒数，默认 20（1~120）。
pollSeconds：检查时间间隔，默认 5（1~30）。
appearance.width/height：96 DPI 基准下的卡片宽高，默认 400 × 100。
appearance.background/foreground/hintColor：6 位 RGB 十六进制颜色（省略 #）。
appearance.font：字体名称，默认 Microsoft YaHei UI。
appearance.mainFontPt/hintFontPt：文字字号，默认 23pt 和 9pt。

编辑后先双击 Check.cmd，看到 Config.json: PASS 后再退出/重新双击 Main.vbs。
遇到配置错误时，后台程序会拒绝启动并写入 WaterAlarm.log，避免用错误的时间静默运行；
Check.cmd 提供可见的 PASS/FAIL 结果。它会显示控制台是有意的诊断行为，与日常静音常驻无关。

六、实机验收清单（必须在目标 Windows 机器上执行）

以下是交付给用户执行的实机验收步骤，不是已完成的实测结果。

[ ] 1. 确认 Windows 10 1703 或更高（建议 Windows 10/11）、Windows PowerShell 5.1、.NET Framework 4.x、Windows Script Host 可用。
[ ] 2. 先退出旧 AHK，解压到可写目录，双击 Check.cmd，看到 Config.json: PASS 和 7 个正确时间。
[ ] 3. 双击 Main.vbs，观察没有 Windows Terminal/CMD/PowerShell 常驻窗口，右下角出现且仅出现一个托盘图标；任务管理器看到后台 powershell.exe 属于预期现象。
[ ] 4. 右键托盘“立即预览提醒”：绿色卡片在主屏幕完整几何正中心；“起来喝水”在卡片中心，底部文字独立居中。
[ ] 5. 在 100%、150%、200% 缩放以及 4K 屏上重复步骤 4：检查字是否锐利、尺寸相近、无错位或裁切；如有混合 DPI 多屏，仍应出现在主屏幕居中。Windows 字体/WinForms 行为需实机确认。
[ ] 6. 在浏览器或文本编辑器持续输入时预览：键盘焦点继续留在原窗口；单击卡片主体、文字和底部提示均能立即关闭；单击也不能激活浮层。
[ ] 7. 预览后什么也不点，约 20 秒关闭；打开系统音量观察或耳机监听，没有 Windows 提示音、应用提示音。
[ ] 8. 托盘“暂停提醒”后暂停状态视觉可辨；手动预览仍可用。恢复后正常计划提醒；重复点击不会产生双重挂钩或多份定时器。
[ ] 9. 为避免等待数小时，先备份 Config.json，将 times 临时改为系统当前时间的下一分钟；运行 Check.cmd 校验并退出/重启程序，观察到点提醒一次，同一分钟无重复。测完务必恢复原 Config.json 并重新启动。
[ ] 10. 连续双击 Main.vbs 两次，检查日志有旧实例退出/新实例启动记录，只留一个图标；回到测试计划时间确认只提醒一次。
[ ] 11. 在自定义休眠/唤醒、手动修改系统时钟、深夜跨日期时留意：同日时间键不重复；电脑关机/休眠期间错过的时间不补弹（与原版一致）。
[ ] 12. 把 Config.json 暂时改成非法时间（如 25:90），Check.cmd 必须显示 FAIL；正常启动应拒绝运行并在日志说明原因。恢复配置。
[ ] 13. 右键“退出”后托盘消失，后台工作进程退出；放 Main.vbs 快捷方式进 shell:startup 并重新登录验证自启。

七、运行限制与故障排查

- 这是 Windows 桌面交互程序，不能在当前提供文件的 Linux 环境运行。现阶段已完成源码检查、JSON 结构检查和原版文件哈希比对；未执行 Windows 实机 GUI/DPI/声音/单实例测试。请按第六节验收后再长期自启。
- 若启动后没有图标，请查看同目录 WaterAlarm.log 与 WaterAlarm-launch-error.log；再使用 Check.cmd 检查配置。脚本故意不会弹出带 Windows 提示音的错误对话框。
- 文件夹需要写权限，以便写日志；配置采用 UTF-8，建议用 Windows 记事本编辑，保留合法 JSON 语法。
- 如果 Windows Script Host 被组织策略禁用，Main.vbs 无法启动；可以改用不依赖 WSH 的 Main.cmd，此时启动器可能短暂显示控制台，但后台进程仍使用 CreateNoWindow。
- Windows 电源睡眠、锁屏、用户注销后，GUI 可能不能可见或任务无法按时触发；错过的提醒不会补发。
- 与 AHK 相比，Windows PowerShell 5.1 的常驻进程内存占用通常更高。
- 修改 Config.json 后不会热加载；退出/重启（新实例自动替换旧实例）才会生效。暂停状态不会跨重启保留。
- 若目标电脑系统 DPI、兼容性选项或旧版 WinForms 机制覆盖了 DPI 设置，程序会记录相关结果；视觉锐度仍需在该电脑实测。
- 不提供全局键盘热键，不采集按键、无后台网络访问、无注册表写入、无需管理员权限。
- -ExecutionPolicy Bypass 仅用于这次 powershell.exe 进程，未改变机器或用户级执行策略。请只运行可信任的本地脚本。

八、版本历史

v1.0.0 · 2026-11-16
- 从用户上传的 AutoHotkey v2 版完整移植为 PowerShell 5.1 + WinForms + Win32 API 开源脚本包。
- 按原文件迁移 7 个时间（第三项 14:30）、静音绿色浮层、居中、点击关闭、20 秒自动关闭、5 秒调度。
- 新增隐藏后台启动器、PMv2 DPI 线程设置、独立 JSON 配置、托盘操作、单实例重启协调和日志、配置校验。
- 原 AHK 原样收录于 Legacy 目录，方便回滚。
