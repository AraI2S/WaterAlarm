#Requires AutoHotkey v2.0
#SingleInstance Force

; =========================
; 每日喝水提醒时间
; =========================
DrinkTimes := [
    "10:20",
    "11:10",
    "14:50",
    "15:40",
    "16:30",
    "17:20",
    "18:10"
]

LastReminder := ""

; 每 5 秒检查一次时间
SetTimer(CheckDrinkTime, 5000)


CheckDrinkTime()
{
    global DrinkTimes, LastReminder

    CurrentTime := FormatTime(, "HH:mm")
    CurrentDate := FormatTime(, "yyyy-MM-dd")
    CurrentKey := CurrentDate " " CurrentTime

    ; 同一分钟最多提醒一次
    if (LastReminder = CurrentKey)
        return

    for DrinkTime in DrinkTimes
    {
        if (CurrentTime = DrinkTime)
        {
            LastReminder := CurrentKey
            ShowDrinkReminder()
            return
        }
    }
}


ShowDrinkReminder()
{
    WindowWidth  := 400
    WindowHeight := 100

    Reminder := Gui(
        "+AlwaysOnTop -Caption +ToolWindow +E0x08000000"
    )

    Reminder.MarginX := 0
    Reminder.MarginY := 0

    ; 柔和绿色
    Reminder.BackColor := "E7F3E8"

    ; =========================
    ; 主文字
    ; =========================
    Reminder.SetFont(
        "s23 w600 c2F5D3A",
        "Microsoft YaHei UI"
    )

    ; +0x200 = SS_CENTERIMAGE
    ; 让单行文字在控件内垂直居中
    MainText := Reminder.AddText(
        "x0 y0 w" WindowWidth
        " h" WindowHeight
        " Center BackgroundTrans +0x200",
        "起来喝水"
    )

    ; =========================
    ; 底部辅助文字
    ; =========================
    Reminder.SetFont(
        "s9 c6C7F70",
        "Microsoft YaHei UI"
    )

    HintText := Reminder.AddText(
        "x0 y76 w" WindowWidth
        " h18 Center BackgroundTrans",
        "点击关闭"
    )

    ; 点击关闭
    MainText.OnEvent(
        "Click",
        (*) => SafeDestroy(Reminder)
    )

    HintText.OnEvent(
        "Click",
        (*) => SafeDestroy(Reminder)
    )

    ; 屏幕正中央显示
    Reminder.Show(
        "NoActivate"
        " w" WindowWidth
        " h" WindowHeight
        " xCenter yCenter"
    )

    ; 20 秒无人操作则自动消失
    SetTimer(
        () => SafeDestroy(Reminder),
        -20000
    )
}


SafeDestroy(GuiObj)
{
    try GuiObj.Destroy()
}