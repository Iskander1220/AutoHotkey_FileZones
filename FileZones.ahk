; ============================================================
;  FileZones — 6 зон (3x2): папки, DnD, виды, INI-состояние
;  AutoHotkey v1.1.30+   (запускается извне, окно сразу видно)
; ============================================================
#NoEnv
#SingleInstance, Force
#KeyHistory 0
ListLines, Off
SetWorkingDir, %A_ScriptDir%
SetBatchLines, -1
CoordMode, Mouse, Screen
CoordMode, ToolTip, Screen
DetectHiddenWindows, On
OnExit, AppExit

; ============================ ГЛОБАЛЬНЫЕ ДАННЫЕ ============================
global INI      := A_ScriptDir "\FileZones.ini"
global ZCOUNT   := 6
global Z        := []
global LVH      := [], TITLEH := [], REFRESHH := [], FOLDH := [], VIEWH := []
global BANDCTL  := {}, BANDBRUSH := {}, BANDBGR := {}, BANDTXT := {}
global CTLZ     := {}
global ZRECT    := []
global GuiHwnd  := 0, GuiReady := 0, BOOTING := 1
global SettingsHwnd := 0, HelpHwnd := 0, HelpEditHwnd := 0, HelpOkHwnd := 0
global hIcon16 := 0, hIcon32 := 0
global hNameEdit := 0, EditZone := 0, EditOld := ""
global hMARK := 0, MarkVisible := 0, MarkZone := 0, MarkIndex := 0
global DragZone := 0, DragBusy := 0
global CtxZone  := 0
global IL16 := 0, IL48 := 0, IL96 := 0, ICONIX := {}
global ICONSRC := {}, ILDONE := {}, ILTRIES := {} ; отложенная догрузка крупных картинок
global PREVIEWIX := {}                         ; быстрые предварительные значки по типу файла
global STARTQ := [], STARTPOS := [], STARTDONE := {} ; очереди стартовой загрузки зон
global START_CHUNK := 40                        ; по 40 готовых элементов из каждой зоны за проход
global ICONQ := [], ICONQPOS := 1               ; строки, которым во втором проходе нужны значки
global SHELL_COM_INIT := 0
global THUMBEXTS_RAW := "jpg,jpeg,jpe,png,gif,bmp,webp,tif,tiff,heic,heif,avif,psd,svg,raw,cr2,nef,dng"
global THUMBEXTS := "," THUMBEXTS_RAW ","       ; форматы второго прохода (настраиваются в INI)
global DIRTY    := {}
global LEGACY   := {}                          ; зоны, прочитанные из INI старого формата
global DEFCOL   := ["E8F1FF","E8F7EE","FFF1D6","FBE7EF","EFE8FF","DFF6F4"]
global PALETTE  := ["E8F1FF","E8F7EE","FFF1D6","FBE7EF","EFE8FF","DFF6F4","FFE5D8","E5EDF8","F2E6D8","EEF4D2"]
global VIEWNAME := {"Report":"Таблица","Icon":"Эскизы","Medium":"Обычные значки"}
global DPI_SCALE := A_ScreenDPI / 96.0             ; 96 DPI = 100%; внутренние размеры храним в логических единицах
global WX := "", WY := "", WW := Dpi(1280), WH := Dpi(800), WMAX := 0
global WSAVED   := ""                          ; что уже лежит в INI: положение окна пишется только при изменении
global FS_BASE  := 11, FS_TITLE := 15          ; размеры шрифтов (чуть крупнее прежних)
global GRID_COLOR := "FFFFFF", GRID_THICKNESS := 10
; Полоса шапки зоны: "auto" — цвет зоны в усиленном виде, иначе явный HEX.
global BAND_COLOR := "auto", BAND_THICKNESS := 30, BAND_INTENSITY := 40
global SHOW_TRAY_ICON := 1                       ; по умолчанию значок в трее видим
global SWATCH   := {}                          ; кэш картинок-образцов цвета для меню

EnsureIni()
LoadState()
Loop, %ZCOUNT%
    WriteZone(A_Index)     ; гарантируем, что секция каждой зоны создана с первого запуска
ReorderIniSections()       ; и приводим секции файла к порядку [App] [Zone1]..[ZoneN]
InitAppIcons()
InitShellCOM()
InitImageLists()

STitle := "FileZones (Файловые зоны — быстрый доступ)"

; Перевод логических координат GUI (96 DPI) в физические пиксели.
; Главный GUI и изменяемая справка работают с -DPIScale, чтобы размеры,
; полученные из GetClientRect/A_GuiWidth, не масштабировались повторно.
Dpi(value) {
    global DPI_SCALE
    return Round(value * DPI_SCALE)
}

; ================================== GUI ==================================
; +E0x80 = WS_EX_TOOLWINDOW — окна нет на панели задач и в Alt+Tab
Gui, Main:New, % "+Resize -DPIScale +MinSize" Dpi(900) "x" Dpi(560) " +E0x10 +HwndGuiHwnd", STitle
Gui, Main:Default
Gui, Font, % "s" FS_BASE, Segoe UI
Gui, Color, %GRID_COLOR%
SetWindowIcons(GuiHwnd)

Loop, %ZCOUNT%
{
    i := A_Index
    c := Z[i].color
    bc := ZoneBandColor(i)                ; полоса шапки — отдельный цвет, не цвет сетки

    ; Полоса шапки — это сами название и кнопки: вместе они занимают всю
    ; ширину и всю толщину полосы. Фон и цвет текста рисуем сами
    ; в OnBandCtlColor — так цвет не зависит от темы Windows и от опции Background.
    ; Стиль 0x200 (SS_CENTERIMAGE) центрирует текст и значки по высоте полосы.
    Gui, Font, % "s" FS_TITLE " w600", Segoe UI
    Gui, Add, Text, % "x" Dpi(8) " y" Dpi(8) " w" Dpi(120) " h" Dpi(BAND_THICKNESS) " hwndhTT +0x200 Background" bc " gZNameClick Center", % Z[i].name

    ; Обновление зоны.
    Gui, Font, s18 Norm, Segoe UI Symbol
    Gui, Add, Text, % "x" Dpi(8) " y" Dpi(8) " w" Dpi(36) " h" Dpi(BAND_THICKNESS) " hwndhRB +0x200 Background" bc " gZRefreshBtn Center", ↻

    Gui, Font, s14 Norm, Segoe UI Emoji
    Gui, Add, Text, % "x" Dpi(8) " y" Dpi(8) " w" Dpi(36) " h" Dpi(BAND_THICKNESS) " hwndhFB +0x200 Background" bc " gZFolderBtn Center", 📁

    Gui, Font, s16 Norm, Segoe UI
    Gui, Add, Text, % "x" Dpi(8) " y" Dpi(8) " w" Dpi(36) " h" Dpi(BAND_THICKNESS) " hwndhVB +0x200 Background" bc " gZViewBtn Center", % ViewGlyph(Z[i].view)

    Gui, Font, % "s" FS_BASE " Norm c202020", Segoe UI
    Gui, Add, ListView, % "x" Dpi(8) " y" Dpi(42) " w" Dpi(200) " h" Dpi(120) " hwndhLV gZLVEvent Background" c " -E0x200 Report +0x100"
                      , Имя|Тип|Размер|Изменён|Путь|Создан

    LVH[i] := hLV, TITLEH[i] := hTT
    REFRESHH[i] := hRB, FOLDH[i] := hFB, VIEWH[i] := hVB

    CTLZ[hLV] := i, CTLZ[hTT] := i, CTLZ[hRB] := i
    CTLZ[hFB] := i, CTLZ[hVB] := i

    BANDCTL[hTT] := i, BANDCTL[hRB] := i, BANDCTL[hFB] := i, BANDCTL[hVB] := i
    UpdateBandPaint(i)                ; цвет полосы и цвет текста на ней

    DllCall("SendMessageW", "Ptr", hLV, "UInt", 0x1003, "Ptr", 0, "Ptr", IL96)   ; LVSIL_NORMAL
    DllCall("SendMessageW", "Ptr", hLV, "UInt", 0x1003, "Ptr", 1, "Ptr", IL16)   ; LVSIL_SMALL
    DllCall("SendMessageW", "Ptr", hLV, "UInt", 0x1036, "Ptr", 0x10020, "Ptr", 0x10020) ; DOUBLEBUFFER|FULLROWSELECT

    AllowDrops(hLV)
    ApplyView(i)                      ; вид применяется сразу, содержимое — уже после показа окна
}

; общий редактор имени и маркер вставки — создаются последними (верх z-порядка)
Gui, Font, % "s" FS_TITLE " Bold", Segoe UI
Gui, Add, Edit, % "x" Dpi(8) " y" Dpi(8) " w" Dpi(120) " h" BandTitleHeight() " hwndhNameEdit Hidden -WantReturn Center"
Gui, Font, % "s" FS_BASE " Norm", Segoe UI
Gui, Add, Progress, % "x0 y0 w" Dpi(3) " h" Dpi(3) " hwndhMARK Hidden Disabled E0x20 Background0078D7 c0078D7", 0

AllowDrops(GuiHwnd)
BuildMenus()
OnMessage(0x4E,  "OnLVNotify")
OnMessage(0x233, "OnDropFiles")
OnMessage(0x138, "OnBandCtlColor")    ; WM_CTLCOLORSTATIC — фон и текст полос зон
OnMessage(0x24,  "OnGetMinMaxInfo")   ; разворот — только на рабочую область, не под панель задач

GuiReady := 1
Gui, Main:Show, % "Hide w" WW " h" WH, %STitle%



global WM_ZONES_TOGGLE := 0x8042
OnMessage(WM_ZONES_TOGGLE, "ToggleFileZonesWindow")




ClientSize(GuiHwnd, cw0, ch0)
LayoutZones(cw0, ch0)                 ; (1) раскладка до первой отрисовки
ShowMainWindow()                      ; сначала показываем готовое пустое окно
SetTimer, WatchWinPos, 2000           ; окно передвинули мышью — тоже запоминаем
SetTimer, StartFillZonesTimer, -10    ; дать Windows отрисовать окно до начала чтения папок
return

StartFillZonesTimer:
StartFillZones()                      ; затем наполняем все зоны вперемешку
return

; AHK v1 однопоточный, поэтому используем кооперативную загрузку: за один тик
; добавляется небольшая порция в КАЖДУЮ зону. Визуально зоны наполняются
; одновременно, а окно остаётся отзывчивым.
FillZonesChunk:
FillZonesTick()
return

FillStartupIcons:
FillStartupIconsTick()
return

; --------- показ окна с восстановлением сохранённого положения -------------
ShowMainWindow() {
    wantMax := WMAX                    ; показ окна сам вызывает GuiSize и сбрасывает WMAX — берём копию
    opt := "w" WW " h" WH
    if (WX != "" && WY != "" && PosVisible(WX, WY, WW, WH))
        opt .= " x" WX " y" WY
    else
        opt := "Center " opt

    ; «обычная» геометрия задаётся, пока окно ещё скрыто, — она нужна для восстановления
    ; из развёрнутого состояния, но пользователь её уже не увидит
    Gui, Main:Show, % "Hide " opt

    if (wantMax) {
        Gui, Main:Show, Maximize       ; единственный видимый показ — сразу развёрнутым
        WMAX := 1
        ClientSize(GuiHwnd, cw, ch)    ; разложить зоны под итоговый размер немедленно,
        LayoutZones(cw, ch)            ; не дожидаясь события GuiSize
    } else {
        Gui, Main:Show
    }
    BOOTING := 0                       ; теперь изменения геометрии можно запоминать
    WinActivate, ahk_id %GuiHwnd%
}

; Окна AHK — popup-окна, поэтому по умолчанию разворачиваются на весь экран
; (низ уходит под панель задач). Ограничиваем разворот рабочей областью монитора.
OnGetMinMaxInfo(wParam, lParam, msg, hwnd) {
    if (!GuiHwnd || hwnd != GuiHwnd)
        return
    hMon := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")   ; MONITOR_DEFAULTTONEAREST
    if !hMon
        return
    VarSetCapacity(mi, 40, 0)
    NumPut(40, mi, 0, "UInt")
    if !DllCall("GetMonitorInfo", "Ptr", hMon, "Ptr", &mi)
        return
    mL := NumGet(mi,  4, "Int"), mT := NumGet(mi,  8, "Int")             ; rcMonitor
    wL := NumGet(mi, 20, "Int"), wT := NumGet(mi, 24, "Int")             ; rcWork
    wR := NumGet(mi, 28, "Int"), wB := NumGet(mi, 32, "Int")
    ww := wR - wL, wh := wB - wT
    if (ww < 100 || wh < 100)
        return
    NumPut(ww,      lParam +  8, 0, "Int")   ; ptMaxSize.x
    NumPut(wh,      lParam +  8, 4, "Int")   ; ptMaxSize.y
    NumPut(wL - mL, lParam + 16, 0, "Int")   ; ptMaxPosition.x
    NumPut(wT - mT, lParam + 16, 4, "Int")   ; ptMaxPosition.y
    NumPut(ww,      lParam + 32, 0, "Int")   ; ptMaxTrackSize.x
    NumPut(wh,      lParam + 32, 4, "Int")   ; ptMaxTrackSize.y
    return 0
}

; положение считается годным, если окно попадает на видимую область рабочего стола
PosVisible(x, y, w, h) {
    SysGet, vx, 76
    SysGet, vy, 77
    SysGet, vw, 78
    SysGet, vh, 79
    return (x + w > vx + Dpi(60)) && (x < vx + vw - Dpi(60))
        && (y >= vy - Dpi(8)) && (y < vy + vh - Dpi(40))
}

WatchWinPos:
CheckWinPos()
return

CheckWinPos() {
    static lx := "", ly := "", lmm := ""
    if (!GuiHwnd || !GuiReady)
        return
    WinGet, mm, MinMax, ahk_id %GuiHwnd%
    if (mm = -1)
        return
    WinGetPos, x, y, , , ahk_id %GuiHwnd%
    if (x = lx && y = ly && mm = lmm)
        return
    lx := x, ly := y, lmm := mm
    SetTimer, SaveWinNow, -800
}

; ============================ РЕДАКТИРОВАНИЕ ИМЕНИ =========================
ZNameClick(hCtl, GuiEvent := "", EventInfo := "") {
    ; Одиночный щелчок только выделяет заголовок; переименование — по двойному.
    if (GuiEvent != "DoubleClick")
        return
    i := CTLZ.HasKey(hCtl) ? CTLZ[hCtl] : 0
    if (i)
        StartRename(i)
}

StartRename(i) {
    if (EditZone)
        CommitRename()
    GuiControlGet, p, Main:Pos, % TITLEH[i]
    EditZone := i
    EditOld  := Z[i].name
    GuiControl, Main:, %hNameEdit%, % Z[i].name
    eh := BandTitleHeight()                       ; поле ввода — у верхней кромки полосы
    if (eh > pH)
        eh := pH
    ey := pY + Max(0, Floor((pH - eh) / 2))   ; поле центрируется в полосе, как и сам заголовок
    GuiControl, Main:MoveDraw, %hNameEdit%, x%pX% y%ey% w%pW% h%eh%
    DllCall("SetWindowPos", "Ptr", hNameEdit, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
    GuiControl, Main:Show, %hNameEdit%
    GuiControl, Main:Focus, %hNameEdit%
    DllCall("SendMessageW", "Ptr", hNameEdit, "UInt", 0xB1, "Ptr", 0, "Ptr", -1)   ; EM_SETSEL
    SetTimer, RenameWatch, 120
}

RenameWatch:
if (!EditZone) {
    SetTimer, RenameWatch, Off
    return
}
if (DllCall("GetFocus", "Ptr") != hNameEdit)
    CommitRename()
return

CommitRename() {
    if !EditZone
        return
    i := EditZone
    EditZone := 0
    SetTimer, RenameWatch, Off
    GuiControlGet, val, Main:, %hNameEdit%
    val := Trim(val)
    if (val != "")
        Z[i].name := val
    GuiControl, Main:, % TITLEH[i], % Z[i].name
    GuiControl, Main:Hide, %hNameEdit%
    SaveZone(i)
}

CancelRename() {
    if !EditZone
        return
    EditZone := 0
    SetTimer, RenameWatch, Off
    GuiControl, Main:Hide, %hNameEdit%
}

#If (EditZone && WinActive("ahk_id " GuiHwnd))
Enter::CommitRename()
NumpadEnter::CommitRename()
Escape::CancelRename()
#If

; ================================ СОБЫТИЯ ================================
MainGuiSize:
if (A_EventInfo = 1 || !GuiReady)
    return
LayoutZones(A_GuiWidth, A_GuiHeight)
if (BOOTING)                           ; события при старте не должны затирать состояние из INI
    return
WMAX := (A_EventInfo = 2) ? 1 : 0      ; 2 = развёрнуто на весь экран
if (!WMAX)
    WW := A_GuiWidth, WH := A_GuiHeight
SetTimer, SaveWinNow, -600
return

SaveWinNow:
SaveWindowPos()
return

MainGuiEscape:
MainGuiClose:
HideZonesWindow() ;ExitApp/HideZonesWindow()
return

MainGuiContextMenu:
MouseGetPos, , , , hCtx, 2
CtxZone := CTLZ.HasKey(hCtx) ? CTLZ[hCtx] : ZoneFromScreen()
if !CtxZone
    return
if (Z[CtxZone].foldersFirst)
    Menu, ZoneMenu, Check, Папки всегда сверху
else
    Menu, ZoneMenu, Uncheck, Папки всегда сверху
Menu, ZoneMenu, Show
return

ZRefreshBtn(hCtl) {
    global CTLZ, STARTDONE, STARTQ

    i := CTLZ.HasKey(hCtl) ? CTLZ[hCtl] : 0
    if (!i)
        return

    ; Если первоначальное порционное заполнение этой зоны ещё идёт,
    ; прекращаем его, чтобы старый таймер не добавлял строки повторно.
    if (STARTDONE.HasKey(i) && !STARTDONE[i]) {
        STARTDONE[i] := 1
        STARTQ[i] := []
    }

    RefreshZone(i)
}

ZFolderBtn(hCtl) {
    i := CTLZ.HasKey(hCtl) ? CTLZ[hCtl] : 0
    if (i)
        PickFolderFor(i)
}

ZViewBtn(hCtl) {
    i := CTLZ.HasKey(hCtl) ? CTLZ[hCtl] : 0
    if (i)
        SetView(i, (Z[i].view = "Report") ? "Icon" : (Z[i].view = "Icon") ? "Medium" : "Report")
}

ZLVEvent(hCtl, GuiEvent, EventInfo) {
    i := CTLZ.HasKey(hCtl) ? CTLZ[hCtl] : 0
    if (!i)
        return
    if (GuiEvent = "ColClick") {              ; сортировка по столбцу (запоминается)
        if (Z[i].view != "Report" || !EventInfo)
            return
        if (EventInfo = Z[i].sortCol)
            Z[i].sortDir := -Z[i].sortDir
        else
            Z[i].sortCol := EventInfo, Z[i].sortDir := 1
        SaveZone(i), RefreshZone(i)
        return
    }
    if (GuiEvent != "DoubleClick")
        return
    row := RowUnderMouse(LVH[i])
    if (row)
        LaunchItem(i, row)
    else
        PickFolderFor(i)                      ; двойной клик по пустому месту = кнопка «Папка…»
}

; =============================== МЕНЮ ====================================
BuildMenus() {
    ; При повторном вызове (после применения настроек) меню создаются заново.
    ; DeleteAll допустим только для уже созданного пользовательского меню.
    ; Сначала удаляем родительское меню, затем его цветное подменю.
    if MenuGetHandle("ZoneMenu")
        Menu, ZoneMenu, DeleteAll
    if MenuGetHandle("ColorMenu")
        Menu, ColorMenu, DeleteAll
    Menu, Tray, DeleteAll
    FreeSwatches()

    ; Сначала создаём все пункты меню.
    for k, c in PALETTE {
        item := "#" c
        Menu, ColorMenu, Add, %item%, MenuColor
    }

    ; В AHK v1 Handle — не подкоманда Menu. Получаем HMENU функцией.
    hColorMenu := MenuGetHandle("ColorMenu")

    ; Назначаем цветные HBITMAP напрямую, без Menu, Icon.
    AttachSwatches(hColorMenu, PALETTE)
    Menu, ZoneMenu, Add, Открыть, MenuOpen
    Menu, ZoneMenu, Add, Показать в проводнике, MenuReveal
    Menu, ZoneMenu, Add
    ; Частые действия
    Menu, ZoneMenu, Add, Обновить, MenuRefresh
    Menu, ZoneMenu, Add, Убрать выделенное из зоны, MenuRemove
    Menu, ZoneMenu, Add
    ; Управление папкой и скрытыми объектами
    Menu, ZoneMenu, Add, Выбрать папку…, MenuPickFolder
    Menu, ZoneMenu, Add, Отвязать папку, MenuUnbind
    Menu, ZoneMenu, Add, Показать скрытые объекты, MenuUnhide
    Menu, ZoneMenu, Add
    ; Оформление зоны
    Menu, ZoneMenu, Add, Переименовать зону, MenuRename
    Menu, ZoneMenu, Add, Цвет зоны, :ColorMenu
    Menu, ZoneMenu, Add
    ; Полная очистка
    Menu, ZoneMenu, Add, Очистить зону, MenuClear
    Menu, ZoneMenu, Add
    Menu, ZoneMenu, Add, Вид: Таблица, MenuView
    Menu, ZoneMenu, Add, Вид: Эскизы, MenuView
    Menu, ZoneMenu, Add, Вид: Обычные значки, MenuView
    Menu, ZoneMenu, Add, Папки всегда сверху, MenuFoldersFirst
    Menu, ZoneMenu, Add
    Menu, ZoneMenu, Add, Настройки, MenuSettings
    Menu, ZoneMenu, Add, Справка, MenuHelp

    Menu, Tray, NoStandard
    Menu, Tray, Add, Показать окно, MenuShow
    Menu, Tray, Add
    Menu, Tray, Add, Настройки, MenuSettings
    Menu, Tray, Add, Справка, MenuHelp
    Menu, Tray, Add
    Menu, Tray, Add, Редактировать, EditScript
    Menu, Tray, Add, Выход, MenuExit
    Menu, Tray, Default, Показать окно
    Menu, Tray, Click, 1
    ApplyTrayIconVisibility()
}

MenuShow:
ShowZonesWindow()
return

MenuOpen:
rows := SelectedRows(CtxZone)
if rows.Length()
    LaunchItem(CtxZone, rows[1])
return

MenuReveal:
rows := SelectedRows(CtxZone)
if rows.Length() {
    p := Z[CtxZone].display[rows[1]]
    Run, % "explorer.exe /select,""" p """", , UseErrorLevel
}
return

MenuRename:
StartRename(CtxZone)
return

MenuRemove:
rows := SelectedRows(CtxZone), dead := []
for k, r in rows
    dead.Push(Z[CtxZone].display[r])
for k, p in dead
    RemoveFromZone(CtxZone, p)
SaveZone(CtxZone), RefreshZone(CtxZone)
return

MenuClear:
ClearZone(CtxZone)
return

MenuPickFolder:
PickFolderFor(CtxZone)
return

MenuUnbind:
for k, p in Z[CtxZone].display                          ; файлы папки остаются в зоне как обычные объекты —
    if (InFolders(CtxZone, p) != "" && !HasVal(Z[CtxZone].items, p))  ; иначе они пропали бы из вида немедленно
        Z[CtxZone].items.Push(p)
Z[CtxZone].folders := [], Z[CtxZone].hidden := []
SaveZone(CtxZone), RefreshZone(CtxZone)
return

; вернуть в зону всё, что было убрано или очищено из привязанной папки
MenuUnhide:
Z[CtxZone].hidden := []
SaveZone(CtxZone), RefreshZone(CtxZone)
return

MenuView:
SetView(CtxZone, InStr(A_ThisMenuItem, "Таблица") ? "Report" : InStr(A_ThisMenuItem, "Эскизы") ? "Icon" : "Medium")
return

MenuFoldersFirst:
Z[CtxZone].foldersFirst := !Z[CtxZone].foldersFirst
SaveZone(CtxZone), RefreshZone(CtxZone)
return

MenuColor:
c := PALETTE[A_ThisMenuItemPos]
Z[CtxZone].color := c
ApplyZoneColors(CtxZone)               ; полоса шапки пересчитывается вместе с зоной
SaveZone(CtxZone), RefreshZone(CtxZone)
return

MenuRefresh:
RefreshZone(CtxZone)
return

MenuSettings:
OpenSettingsWindow()
return

MenuHelp:
ShowHelpWindow()
return


; ========================== НАСТРОЙКИ И СПРАВКА ==========================
OpenSettingsWindow() {
    global SettingsHwnd
    HideHelpWindow()
    if WindowExistsByHwnd(SettingsHwnd) {
        LoadSettingsControls()
        Gui, Settings:Show
        WinActivate, ahk_id %SettingsHwnd%
        return
    }

    Gui, Settings:New, +OwnerMain +HwndSettingsHwnd, Настройки
    Gui, Settings:Margin, 14, 12
    Gui, Settings:Font, s10, Segoe UI
    Gui, Settings:Add, GroupBox, x14 y10 w612 h110, Загрузка и внешний вид
    Gui, Settings:Add, Text, x28 y36 w125 h22 +0x200, Расширения эскизов
    Gui, Settings:Add, Edit, x158 y36 w452 h22 vSetThumbnailExts
    Gui, Settings:Add, Text, x28 y70 w125 h22 +0x200, Объектов за проход
    Gui, Settings:Add, Edit, x158 y70 w62 h22 Number vSetStartChunk
    Gui, Settings:Add, Text, x236 y70 w96 h22 +0x200, Шрифт списка
    Gui, Settings:Add, Edit, x340 y70 w56 h22 Number vSetFsBase
    Gui, Settings:Add, Text, x412 y70 w118 h22 +0x200, Шрифт заголовка
    Gui, Settings:Add, Edit, x538 y70 w56 h22 Number vSetFsTitle

    Gui, Settings:Add, GroupBox, x14 y132 w612 h184, Сетка и полосы зон
    Gui, Settings:Add, Text, x28 y158 w125 h22 +0x200, Цвет сетки (HEX)
    Gui, Settings:Add, Edit, x158 y158 w92 h22 vSetGridColor
    Gui, Settings:Add, Text, x278 y158 w104 h22 +0x200, Толщина сетки
    Gui, Settings:Add, Edit, x390 y158 w58 h22 Number vSetGridThickness
    Gui, Settings:Add, Text, x28 y190 w125 h22 +0x200, Цвет полос
    Gui, Settings:Add, Edit, x158 y190 w92 h22 vSetBandColor
    Gui, Settings:Add, Text, x278 y190 w104 h22 +0x200, Толщина полос
    Gui, Settings:Add, Edit, x390 y190 w58 h22 Number vSetBandThickness
    Gui, Settings:Add, Text, x464 y190 w96 h22 +0x200, Насыщенность
    Gui, Settings:Add, Edit, x568 y190 w42 h22 Number vSetBandIntensity
    Gui, Settings:Font, s9 cGray, Segoe UI
    Gui, Settings:Add, Text, x28 y216 w582 h20, auto — цвет полосы берётся от цвета зоны; насыщенность 0–100 задаёт силу усиления цвета
    Gui, Settings:Font, s10 cDefault, Segoe UI
    Gui, Settings:Add, Text, x28 y242 w125 h22 +0x200, Начальные цвета
    Gui, Settings:Add, Edit, x158 y242 w452 h22 vSetDefaultColors
    Gui, Settings:Add, Text, x28 y274 w125 h22 +0x200, Палитра меню
    Gui, Settings:Add, Edit, x158 y274 w452 h22 vSetPalette

    Gui, Settings:Add, GroupBox, x14 y328 w612 h58, Область уведомлений
    Gui, Settings:Add, CheckBox, x28 y352 w410 h22 vSetShowTrayIcon, Показывать значок FileZones в трее

    Gui, Settings:Add, Button, x350 y404 w86 h28 gSettingsOK Default, OK
    Gui, Settings:Add, Button, x444 y404 w86 h28 gSettingsApply, Применить
    Gui, Settings:Add, Button, x538 y404 w86 h28 gSettingsCancel, Отмена
    LoadSettingsControls()
    Gui, Settings:Show, w640 h446, Настройки
}

LoadSettingsControls() {
    global THUMBEXTS_RAW, START_CHUNK, FS_BASE, FS_TITLE, GRID_COLOR
         , GRID_THICKNESS, BAND_COLOR, BAND_THICKNESS, BAND_INTENSITY
         , DEFCOL, PALETTE, SHOW_TRAY_ICON
    GuiControl, Settings:, SetThumbnailExts, %THUMBEXTS_RAW%
    GuiControl, Settings:, SetStartChunk, %START_CHUNK%
    GuiControl, Settings:, SetFsBase, %FS_BASE%
    GuiControl, Settings:, SetFsTitle, %FS_TITLE%
    GuiControl, Settings:, SetGridColor, %GRID_COLOR%
    GuiControl, Settings:, SetGridThickness, %GRID_THICKNESS%
    GuiControl, Settings:, SetBandColor, %BAND_COLOR%
    GuiControl, Settings:, SetBandThickness, %BAND_THICKNESS%
    GuiControl, Settings:, SetBandIntensity, %BAND_INTENSITY%
    GuiControl, Settings:, SetDefaultColors, % JoinColors(DEFCOL)
    GuiControl, Settings:, SetPalette, % JoinColors(PALETTE)
    GuiControl, Settings:, SetShowTrayIcon, %SHOW_TRAY_ICON%
}

SettingsApply:
ApplySettingsFromGui()
return

SettingsOK:
if ApplySettingsFromGui() {
    Gui, Settings:Destroy            ; окно уничтожаем, а не прячем — не оставляем лишнее
    SettingsHwnd := 0                ; окно того же класса, которое могло бы мешать внешним сообщениям
}
return

SettingsCancel:
SettingsGuiEscape:
SettingsGuiClose:
Gui, Settings:Destroy
SettingsHwnd := 0
return

ApplySettingsFromGui() {
    global SetThumbnailExts, SetStartChunk, SetFsBase, SetFsTitle, SetGridColor
         , SetGridThickness, SetBandColor, SetBandThickness, SetBandIntensity
         , SetDefaultColors, SetPalette, SetShowTrayIcon
    global THUMBEXTS_RAW, THUMBEXTS, START_CHUNK, FS_BASE, FS_TITLE, GRID_COLOR
         , GRID_THICKNESS, BAND_COLOR, BAND_THICKNESS, BAND_INTENSITY
         , DEFCOL, PALETTE, SHOW_TRAY_ICON, INI, GuiHwnd, ZCOUNT
         , TITLEH, REFRESHH, FOLDH, VIEWH, LVH, hNameEdit

    Gui, Settings:Submit, NoHide
    if (SetStartChunk < 1 || SetStartChunk > 500
     || SetFsBase < 8 || SetFsBase > 24
     || SetFsTitle < 9 || SetFsTitle > 32
     || SetGridThickness < 2 || SetGridThickness > 40
     || SetBandThickness < 20 || SetBandThickness > 90
     || SetBandIntensity < 0 || SetBandIntensity > 100) {
        MsgBox, 48, Настройка, Проверьте числовые значения:`nSTART_CHUNK 1–500; шрифты 8–24 и 9–32; сетка 2–40;`nтолщина полос 20–90; насыщенность 0–100.
        return false
    }
    if !RegExMatch(Trim(SetGridColor), "i)^#?[0-9a-f]{6}$") {
        MsgBox, 48, Настройка, Цвет сетки должен содержать шесть HEX-символов.
        return false
    }
    if !RegExMatch(Trim(SetBandColor), "i)^(auto|#?[0-9a-f]{6})$") {
        MsgBox, 48, Настройка, Цвет полос — шесть HEX-символов либо слово auto.
        return false
    }
    newDefaults := ParseColorList(SetDefaultColors, 6, 6)
    newPalette := ParseColorList(SetPalette, 6, 16)
    if !IsObject(newDefaults) || !IsObject(newPalette) {
        MsgBox, 48, Настройка, Начальные цвета: ровно 6 HEX-цветов.`nПалитра: от 6 до 16 HEX-цветов, через запятую.
        return false
    }

    THUMBEXTS_RAW := Trim(SetThumbnailExts)
    THUMBEXTS := NormalizeThumbExts(THUMBEXTS_RAW)
    START_CHUNK := SetStartChunk + 0
    FS_BASE := SetFsBase + 0
    FS_TITLE := SetFsTitle + 0
    GRID_COLOR := NormalizeHexColor(SetGridColor, "FFFFFF")
    GRID_THICKNESS := SetGridThickness + 0
    BAND_COLOR := NormalizeBandColor(SetBandColor)
    BAND_THICKNESS := SetBandThickness + 0
    BAND_INTENSITY := SetBandIntensity + 0
    DEFCOL := newDefaults
    PALETTE := newPalette
    SHOW_TRAY_ICON := SetShowTrayIcon ? 1 : 0

    IniWrite, %THUMBEXTS_RAW%, %INI%, App, ThumbnailExts
    IniWrite, %START_CHUNK%, %INI%, App, StartChunk
    IniWrite, %FS_BASE%, %INI%, App, FontBase
    IniWrite, %FS_TITLE%, %INI%, App, FontTitle
    IniWrite, %GRID_COLOR%, %INI%, App, GridColor
    IniWrite, %GRID_THICKNESS%, %INI%, App, GridThickness
    IniWrite, %BAND_COLOR%, %INI%, App, BandColor
    IniWrite, %BAND_THICKNESS%, %INI%, App, BandThickness
    IniWrite, %BAND_INTENSITY%, %INI%, App, BandIntensity
    IniWrite, % JoinColors(DEFCOL), %INI%, App, DefaultColors
    IniWrite, % JoinColors(PALETTE), %INI%, App, Palette
    IniWrite, %SHOW_TRAY_ICON%, %INI%, App, ShowTrayIcon

    Gui, Main:Color, %GRID_COLOR%
    Loop, %ZCOUNT%
        ApplyZoneColors(A_Index)
    Gui, Main:Font, % "s" FS_TITLE " Bold", Segoe UI
    GuiControl, Main:Font, %hNameEdit%
    ClientSize(GuiHwnd, cw, ch)
    LayoutZones(cw, ch)
    BuildMenus()
    return true
}

ShowHelpWindow() {
    global HelpHwnd, HelpEditHwnd, HelpOkHwnd, HelpDoc
    if WindowExistsByHwnd(HelpHwnd) {
        Gui, Help:Show
        WinSet, AlwaysOnTop, On, ahk_id %HelpHwnd%
        WinActivate, ahk_id %HelpHwnd%
        return
    }
    Gui, Settings:Hide
    ; Окно справки самостоятельное и всегда остаётся поверх остальных окон.
    Gui, Help:New, % "+AlwaysOnTop +Resize -DPIScale +MinSize" Dpi(640) "x" Dpi(480) " +HwndHelpHwnd", Справка FileZones
    Gui, Help:Margin, % Dpi(14), % Dpi(12)
    Gui, Help:Color, FFFFFF
    Gui, Help:Font, s10, Segoe UI
    ; Текст справки — обычная HTML-страница в браузерном контроле.
    Gui, Help:Add, ActiveX, % "x" Dpi(14) " y" Dpi(12) " w" Dpi(692) " h" Dpi(510) " hwndHelpEditHwnd vHelpDoc", Shell.Explorer
    Gui, Help:Add, Button, % "x" Dpi(616) " y" Dpi(534) " w" Dpi(90) " h" Dpi(28) " hwndHelpOkHwnd gCloseHelpWindow Default", OK
    HelpDoc.Silent := true
    HelpDoc.Navigate("about:blank")
    while (HelpDoc.ReadyState != 4)
        Sleep, 20
    HelpDoc.document.write(BuildHelpHtml())
    HelpDoc.document.close()
    Gui, Help:Show, % "w" Dpi(720) " h" Dpi(574), Справка FileZones
    WinSet, AlwaysOnTop, On, ahk_id %HelpHwnd%
}

HelpGuiSize:
if (A_EventInfo = 1)
    return
GuiControl, Help:Move, %HelpEditHwnd%, % "w" (A_GuiWidth - Dpi(28)) " h" (A_GuiHeight - Dpi(64))
GuiControl, Help:Move, %HelpOkHwnd%, % "x" (A_GuiWidth - Dpi(104)) " y" (A_GuiHeight - Dpi(40))
return

CloseHelpWindow:
HelpGuiEscape:
HelpGuiClose:
HideHelpWindow()
return

HideHelpWindow() {
    global HelpHwnd, HelpEditHwnd, HelpOkHwnd, HelpDoc
    if WindowExistsByHwnd(HelpHwnd) {
        Gui, Help:Destroy                 ; окно уничтожаем, а не прячем — не оставляем лишнее
        HelpDoc := ""                     ; окно того же класса и отпускаем ActiveX-объект браузера
        HelpHwnd := 0, HelpEditHwnd := 0, HelpOkHwnd := 0
    }
}

WindowExistsByHwnd(Hwnd) {
    if !Hwnd
        return false
    DetectHiddenWindowsWasOn := A_DetectHiddenWindows
    DetectHiddenWindows, On
    Exists := WinExist("ahk_id " Hwnd)
    DetectHiddenWindows, %DetectHiddenWindowsWasOn%
    return Exists
}

BuildHelpHtml() {
    Html := "<!DOCTYPE html>`r`n"
         . "<html><head><meta charset='utf-8'><meta http-equiv='X-UA-Compatible' content='IE=edge'>`r`n"
         . "<style>`r`n"
         . "body{font-family:'Segoe UI',Tahoma,sans-serif;line-height:1.55;color:#202020;background:#FFFFFF;margin:18px 22px}`r`n"
         . "h1{font-weight:600;color:#14304A;margin:0 0 14px;padding-bottom:8px;border-bottom:2px solid #DCE3EA}`r`n"
         . "h2{font-weight:600;color:#14304A;margin:26px 0 8px}`r`n"
         . "h3{font-weight:600;color:#1F5C8B;margin:20px 0 6px}`r`n"
         . "h4{font-weight:600;color:#1F5C8B;margin:16px 0 6px}`r`n"
         . "p{margin:8px 0}`r`n"
         . "ul,ol{margin:8px 0 8px 26px;padding:0}`r`n"
         . "li{margin:4px 0}`r`n"
         . "code{font-family:Consolas,'Courier New',monospace;color:#1F5C8B;background:#F2F5F8;padding:1px 4px;border-radius:3px}`r`n"
         . "pre{font-family:Consolas,'Courier New',monospace;color:#26404F;background:#F5F7F9;border:1px solid #E1E7ED;border-radius:4px;padding:10px 12px;margin:10px 0;white-space:pre-wrap}`r`n"
         . "pre code{background:none;padding:0}`r`n"
         . "blockquote{margin:12px 0;padding:10px 14px;background:#F3F7FB;border-left:4px solid #7FA8C9;color:#3C4A56}`r`n"
         . "table{border-collapse:collapse;margin:12px 0}`r`n"
         . "th,td{border:1px solid #DCE3EA;padding:6px 10px;text-align:left;vertical-align:top}`r`n"
         . "th{background:#F2F5F8;color:#14304A;font-weight:600}`r`n"
         . "hr{border:none;border-top:1px solid #DCE3EA;margin:18px 0}`r`n"
         . "</style></head><body>`r`n"
         . "<h1>FileZones — справка</h1>`r`n"
         . "<p>FileZones — окно быстрого доступа к файлам и папкам, разделенное на шесть независимых зон (3 × 2): каждой можно назначить имя и цвет, добавить отдельные объекты, привязать папку и выбрать режим отображения.</p>`r`n"
         . "<blockquote>FileZones не копирует и не перемещает файлы при обычном добавлении. Программа хранит исходные пути и управляет только тем, какие объекты показаны в зонах.</blockquote>`r`n"
         . "<h2>Быстрый старт</h2>`r`n"
         . "<ol>`r`n"
         . "<li>Перетащите файлы или папки из Проводника в нужную зону.</li>`r`n"
         . "<li>Чтобы показать содержимое папки, нажмите <b>📁</b> в заголовке зоны и выберите её.</li>`r`n"
         . "<li>Дважды щёлкните объект, чтобы открыть его.</li>`r`n"
         . "<li>Щёлкните зону правой кнопкой мыши для переименования, настройки цвета и вида, очистки и других действий.</li>`r`n"
         . "</ol>`r`n"
         . "<h2>Устройство окна</h2>`r`n"
         . "<p>В каждой зоне есть:</p>`r`n"
         . "<ul>`r`n"
         . "<li><b>название</b> — дважды щёлкните по нему, чтобы переименовать зону;</li>`r`n"
         . "<li><b>↻</b> — перечитать содержимое и обновить список;</li>`r`n"
         . "<li><b>📁</b> — выбрать привязанную папку;</li>`r`n"
         . "<li><b>кнопка вида</b> — переключать режимы <b>Таблица → Эскизы → Обычные значки</b>;</li>`r`n"
         . "<li><b>список объектов</b> — файлы и папки, доступные в зоне.</li>`r`n"
         . "</ul>`r`n"
         . "<p>При переименовании нажмите <b>Enter</b> или <b>Numpad Enter</b>, чтобы сохранить название, и <b>Esc</b>, чтобы отменить изменение. При переходе к другому элементу интерфейса введённое название сохраняется автоматически.</p>`r`n"
         . "<p>Цвет настраивается через пункт <b>Цвет зоны</b> в контекстном меню. Для каждой зоны можно выбрать один из десяти пастельных цветов.</p>`r`n"
         . "<p>Полоса с названием и кнопками окрашивается отдельно от сетки. По умолчанию она повторяет цвет зоны в более насыщенном виде. В окне <b>Настройки</b> задаются толщина полос (20–90 пикселей), сила усиления цвета (0–100 %) или собственный HEX-цвет вместо значения <code>auto</code>.</p>`r`n"
         . "<p>Размер окна можно менять. Зоны автоматически перестраиваются, сохраняя сетку 3 × 2. Минимальный размер — 900 × 560 пикселей.</p>`r`n"
         . "<h2>Файлы и папки</h2>`r`n"
         . "<p>Перетащите в зону один или несколько файлов и папок. Поддерживаются ярлыки и исполняемые файлы. Объекты остаются на прежних местах, повторное добавление того же пути не создаёт дубликат, а недоступные пути не отображаются.</p>`r`n"
         . "<p>Чтобы привязать папку, нажмите <b>📁</b> либо дважды щёлкните по пустому месту списка.</p>`r`n"
         . "<ul>`r`n"
         . "<li>В зону добавляется содержимое верхнего уровня папки. Вложенные папки показываются как объекты, но не раскрываются автоматически.</li>`r`n"
         . "<li>Если зона носит стандартное имя вида «Зона 1», оно заменится именем выбранной папки.</li>`r`n"
         . "<li>Через интерфейс к зоне назначается одна папка; выбор другой заменяет прежнюю привязку.</li>`r`n"
         . "<li>Новые файлы и папки появляются после нажатия <b>↻</b>.</li>`r`n"
         . "<li>При повторном выборе той же папки FileZones предложит вернуть ранее скрытые объекты, если они есть.</li>`r`n"
         . "</ul>`r`n"
         . "<p>Отдельно добавленные объекты и содержимое привязанной папки могут находиться в одной зоне одновременно.</p>`r`n"
         . "<p>Для открытия дважды щёлкните объект. Файл откроется в назначенном приложении, папка — в Проводнике. Команда <b>Открыть</b> в контекстном меню действует на первый выделенный объект, а <b>Показать в проводнике</b> открывает его расположение и выделяет объект. Перед запуском FileZones сохраняет состояние, затем скрывает окно.</p>`r`n"
         . "<h2>Виды, сортировка и порядок</h2>`r`n"
         . "<p>Режим задаётся отдельно для каждой зоны:</p>`r`n"
         . "<ul>`r`n"
         . "<li><b>Таблица</b> — имя, тип, размер, дата изменения и дата создания. Путь хранится в скрытом служебном столбце.</li>`r`n"
         . "<li><b>Эскизы</b> — крупные значки размером 96 пикселей; для разрешённых форматов загружаются эскизы содержимого.</li>`r`n"
         . "<li><b>Обычные значки</b> — компактные значки размером 48 пикселей; эскизы также доступны для разрешённых форматов.</li>`r`n"
         . "</ul>`r`n"
         . "<p>В режиме <b>Таблица</b> щёлкните заголовок столбца, чтобы отсортировать список. Повторный щелчок меняет направление. Активный столбец и направление сортировки отмечаются стандартной стрелкой в заголовке.</p>`r`n"
         . "<p>По умолчанию папки и файлы участвуют в одной общей сортировке. Переключатель <b>Папки всегда сверху</b> в контекстном меню создаёт отдельную группу папок перед файлами; внутри обеих групп действует выбранный столбец и направление. Настройка сохраняется отдельно для каждой зоны.</p>`r`n"
         . "<p>При активной сортировке весь список соответствует выбранному столбцу. Например, при сортировке по дате создания от новых к старым новые объекты попадают наверх, а при обратном направлении — вниз.</p>`r`n"
         . "<p>Объекты можно перетаскивать:</p>`r`n"
         . "<ul>`r`n"
         . "<li>внутри зоны — чтобы изменить порядок;</li>`r`n"
         . "<li>между зонами — чтобы перенести их;</li>`r`n"
         . "<li>группой — если выделено несколько объектов.</li>`r`n"
         . "</ul>`r`n"
         . "<p>Синяя полоса показывает место вставки. У краёв длинного списка включается автоматическая прокрутка. <b>Esc</b> отменяет начатое перетаскивание.</p>`r`n"
         . "<p>Ручная перестановка отключает сортировку по столбцу. После этого существующий пользовательский порядок сохраняется, а новые объекты из привязанной папки добавляются отдельной группой наверх. Внутри новой группы они располагаются по дате создания — от новых к старым. После добавления порядок фиксируется, поэтому при следующем обновлении наверх попадут только действительно новые объекты.</p>`r`n"
         . "<p>Перетаскивание внутри FileZones меняет только состав и порядок зон: файлы и папки на диске не перемещаются.</p>`r`n"
         . "<h2>Скрытие и очистка</h2>`r`n"
         . "<p>Следующие команды не удаляют данные с компьютера:</p>`r`n"
         . "<ul>`r`n"
         . "<li><b>Убрать выделенное из зоны</b> — удаляет вручную добавленный объект из списка; объект привязанной папки заносится в список скрытых и не возвращается после обновления.</li>`r`n"
         . "<li><b>Показать скрытые объекты</b> — очищает список скрытых и возвращает содержимое привязанной папки.</li>`r`n"
         . "<li><b>Очистить зону</b> — убирает вручную добавленные объекты и скрывает текущее содержимое привязанной папки. Привязка сохраняется, поэтому появившиеся позднее объекты будут показаны после обновления. Если название зоны отличается от стандартного («Зона N»), оно сбрасывается на стандартное.</li>`r`n"
         . "<li><b>Отвязать папку</b> — удаляет связь с папкой и очищает список скрытых объектов этой зоны. Файлы, которые были видны из папки, остаются в зоне как обычные вручную добавленные объекты, название зоны при этом не меняется.</li>`r`n"
         . "</ul>`r`n"
         . "<h2>Контекстное меню</h2>`r`n"
         . "<p>Правый щелчок внутри зоны открывает команды:</p>`r`n"
         . "<ul>`r`n"
         . "<li><b>Открыть</b>;</li>`r`n"
         . "<li><b>Показать в проводнике</b>;</li>`r`n"
         . "<li><b>Переименовать зону</b>;</li>`r`n"
         . "<li><b>Убрать выделенное из зоны</b>;</li>`r`n"
         . "<li><b>Выбрать папку…</b>;</li>`r`n"
         . "<li><b>Показать скрытые объекты</b>;</li>`r`n"
         . "<li><b>Очистить зону</b>;</li>`r`n"
         . "<li><b>Отвязать папку</b>;</li>`r`n"
         . "<li><b>Вид: Таблица / Эскизы / Обычные значки</b>;</li>`r`n"
         . "<li><b>Папки всегда сверху</b>;</li>`r`n"
         . "<li><b>Цвет зоны</b>;</li>`r`n"
         . "<li><b>Обновить</b>;</li>`r`n"
         . "<li><b>Настройки</b>;</li>`r`n"
         . "<li><b>Справка</b>.</li>`r`n"
         . "</ul>`r`n"
         . "<p>Команды <b>Открыть</b> и <b>Показать в проводнике</b> действуют на первый из выделенных объектов.</p>`r`n"
         . "<h2>Сохранение и закрытие</h2>`r`n"
         . "<p>FileZones автоматически сохраняет:</p>`r`n"
         . "<ul>`r`n"
         . "<li>названия, цвета и режимы зон;</li>`r`n"
         . "<li>добавленные и скрытые объекты;</li>`r`n"
         . "<li>привязанные папки;</li>`r`n"
         . "<li>ручной порядок или выбранную сортировку;</li>`r`n"
         . "<li>настройку <b>Папки всегда сверху</b>;</li>`r`n"
         . "<li>размер, положение и развёрнутое состояние окна;</li>`r`n"
         . "<li>список расширений для эскизов;</li>`r`n"
         . "<li>параметры шрифтов, сетки, полос, палитры и значка в трее.</li>`r`n"
         . "</ul>`r`n"
         . "<p>Настройки находятся в <code>FileZones.ini</code> рядом со скриптом. При первом запуске файл создаётся автоматически в кодировке UTF-16. Изменения зон записываются сразу же, без задержки.</p>`r`n"
         . "<p>Поведение <b>Esc</b> зависит от текущего действия:</p>`r`n"
         . "<ul>`r`n"
         . "<li>при переименовании — отменяет переименование;</li>`r`n"
         . "<li>при перетаскивании — отменяет перенос;</li>`r`n"
         . "<li>в остальных случаях, когда окно активно, — завершает программу.</li>`r`n"
         . "</ul>`r`n"
         . "<p>Кнопка закрытия скрывает FileZones, предварительно сохранив состояние. По умолчанию значок виден в области уведомлений: щелчок показывает окно, а его меню содержит команды показа, выхода, настройки и справки. Значок можно отключить в настройках. Открытие файла или папки также скрывает окно.</p>`r`n"
         . "<h2>Загрузка и эскизы</h2>`r`n"
         . "<p>При запуске FileZones сначала показывает готовое окно, затем порциями наполняет все зоны. За один проход в каждую незаполненную зону добавляется до 40 объектов, поэтому интерфейс остаётся доступным.</p>`r`n"
         . "<p>Загрузка проходит в два этапа:</p>`r`n"
         . "<ol>`r`n"
         . "<li>Для каждого объекта сразу запрашивается быстрый системный значок — включая собственные значки программ, папок и обозначения ярлыков.</li>`r`n"
         . "<li>После появления всех строк для разрешённых форматов загружаются эскизы содержимого.</li>`r`n"
         . "</ol>`r`n"
         . "<p>Нажатие <b>↻</b> во время первоначального заполнения останавливает старую очередь выбранной зоны и формирует список заново, не создавая дубликатов.</p>`r`n"
         . "<p>Расширения для эскизов задаются в секции <code>[App]</code> файла <code>FileZones.ini</code>:</p>`r`n"
         . "<pre>`r`n"
         . "[App]`r`n"
         . "ThumbnailExts=jpg,jpeg,jpe,png,gif,bmp,webp,tif,tiff,<br>heic,heif,avif,psd,svg,raw,cr2,nef,dng`r`n"
         . "</pre>`r`n"
         . "<p>Примеры:</p>`r`n"
         . "<pre>`r`n"
         . "; отключить эскизы`r`n"
         . "ThumbnailExts=none`r`n"
         . "`r`n"
         . "; строить эскизы для всех расширений — может замедлить загрузку`r`n"
         . "ThumbnailExts=*`r`n"
         . "`r`n"
         . "; ограничиться распространёнными изображениями`r`n"
         . "ThumbnailExts=jpg,jpeg,png,webp`r`n"
         . "</pre>`r`n"
         . "<p>Параметр рекомендуется изменять при остановленном скрипте. Значения <code>none</code>, <code>off</code> и <code>0</code> отключают эскизы; разделителями могут быть запятые, точки с запятой и пробелы.</p>`r`n"
         . "<h2>Файл настроек</h2>`r`n"
         . "<p>Для каждой зоны используется секция <code>[ZoneN]</code>, где <code>N</code> — число от 1 до 6:</p>`r`n"
         . "<pre>`r`n"
         . "[Zone1]`r`n"
         . "Name=Работа`r`n"
         . "Color=EAF4FF`r`n"
         . "View=Report`r`n"
         . "SortCol=6`r`n"
         . "SortDir=-1`r`n"
         . "FoldersFirst=0`r`n"
         . "fld1=*D:\Работа`r`n"
         . "fld2=C:\Windows\notepad.exe`r`n"
         . "fld3=-D:\Работа\Черновик.txt`r`n"
         . "</pre>`r`n"
         . "<table>`r`n"
         . "<tr><th>Ключ</th><th>Значение</th></tr>`r`n"
         . "<tr><td><code>Name</code></td><td>название зоны</td></tr>`r`n"
         . "<tr><td><code>Color</code></td><td>цвет: шесть шестнадцатеричных символов без <code>#</code></td></tr>`r`n"
         . "<tr><td><code>View</code></td><td><code>Report</code>, <code>Icon</code> или <code>Medium</code></td></tr>`r`n"
         . "<tr><td><code>SortCol</code></td><td><code>0</code> — ручной порядок; <code>1</code>–<code>6</code> — столбец сортировки</td></tr>`r`n"
         . "<tr><td><code>SortDir</code></td><td><code>1</code> — по возрастанию; <code>-1</code> — по убыванию</td></tr>`r`n"
         . "<tr><td><code>FoldersFirst</code></td><td><code>1</code> — папки всегда сверху; <code>0</code> — общая сортировка</td></tr>`r`n"
         . "<tr><td><code>fldN</code></td><td>привязанная папка, скрытый или добавленный объект</td></tr>`r`n"
         . "</table>`r`n"
         . "<p>Префиксы записей <code>fldN</code>:</p>`r`n"
         . "<ul>`r`n"
         . "<li><code>*</code> — привязанная папка;</li>`r`n"
         . "<li><code>-</code> — скрытый объект привязанной папки;</li>`r`n"
         . "<li>без префикса — объект зоны.</li>`r`n"
         . "</ul>`r`n"
         . "<p>При чтении INI поддерживается несколько записей с префиксом <code>*</code>, однако выбор папки через интерфейс заменяет их одной папкой.</p>`r`n"
         . "<p>Секции в файле всегда идут по порядку <code>[App]</code>, <code>[Zone1]</code>…<code>[Zone6]</code>: при каждом запуске программа создаёт все секции зон, если их ещё нет, и переставляет их в этом порядке, даже если раньше они оказались вперемешку.</p>`r`n"
         . "<h2>Требования и внешний запуск</h2>`r`n"
         . "<ul>`r`n"
         . "<li>Windows;</li>`r`n"
         . "<li>AutoHotkey v1.1.30 или новее (Unicode);</li>`r`n"
         . "<li><code>FileZones.ahk</code> и <code>FileZones.ini</code> в одной папке;</li>`r`n"
         . "<li>те же права запуска, что у Проводника Windows, — иначе перетаскивание может не работать.</li>`r`n"
         . "</ul>`r`n"
         . "<p>Чтобы показать скрытое окно или скрыть видимое, внешний AutoHotkey-скрипт может отправить сообщение <code>0x8042</code> (<code>WM_ZONES_TOGGLE</code>):</p>`r`n"
         . "<pre>`r`n"
         . "PostMessage, 0x8042, 0, 0, , ahk_id %hZonesGui%`r`n"
         . "</pre>`r`n"
         . "<p>Здесь <code>hZonesGui</code> — заранее полученный внешним скриптом HWND главного окна FileZones. Если внешний скрипт получает <code>hZonesGui</code> через <code>WinGet</code>/<code>WinExist</code>, для надёжности указывайте полный заголовок главного окна, а не только класс.</p>`r`n"
         . "<p>При скрытии состояние сохраняется; при повторном показе восстанавливается в том числе развёрнутое состояние.</p>`r`n"
         . "<p>На скорость заполнения влияют сетевые и отключённые диски, облачные папки, недоступные пути, большое количество изображений, антивирусная проверка и обработчики значков Windows. Если загрузка замедляется, сократите <code>ThumbnailExts</code> или отключите эскизы.</p>`r`n"
         . "</body></html>`r`n"
    return Html
}

#If WinActive(STitle " ahk_class AutoHotkeyGUI")
Esc::
ExitApp
return
#IfWinActive

MenuExit:
ExitApp
return

; ====================== ПЕРЕТАСКИВАНИЕ + МАРКЕР ВСТАВКИ ===================
OnLVNotify(wParam, lParam, msg, hwnd) {
    hFrom := NumGet(lParam + 0, 0, "UPtr")
    code  := NumGet(lParam + 0, 2 * A_PtrSize, "Int")
    if (code != -109)                       ; LVN_BEGINDRAG
        return
    zi := CTLZ.HasKey(hFrom) ? CTLZ[hFrom] : 0
    if (!zi || DragBusy || LVH[zi] != hFrom)
        return
    DragZone := zi
    SetTimer, DragStart, -10
}

DragStart:
DragBusy := 1
DoDrag(DragZone)
DragBusy := 0
return

DoDrag(src) {
    if !src
        return
    rows := SelectedRows(src)
    if !rows.Length()
        return
    paths := []
    for k, r in rows
        paths.Push(Z[src].display[r])

    ; порог срабатывания: случайный микросдвиг не должен менять порядок
    MouseGetPos, sx0, sy0
    moved := 0
    while GetKeyState("LButton", "P") {
        MouseGetPos, mx, my
        if (Abs(mx - sx0) > Dpi(4) || Abs(my - sy0) > Dpi(4)) {
            moved := 1
            break
        }
        Sleep, 10
    }
    if (!moved)
        return

    HideMarker()
    cancel := 0
    while GetKeyState("LButton", "P") {
        if GetKeyState("Escape", "P") {        ; Esc отменяет перетаскивание
            cancel := 1
            break
        }
        MouseGetPos, mx, my
        t := ZoneUnderCursor(mx, my)          ; только геометрия, никаких HWND под курсором
        if (t) {
            AutoScroll(t, my)
            UpdateMarker(t, mx, my)
        } else
            HideMarker()
        ToolTip, % "Перенос: " paths.Length() " объект(ов)", mx + Dpi(18), my + Dpi(18)
        Sleep, 10
    }
    ToolTip

    ; зона и позиция вставки определяются ЗАНОВО в точке отпускания кнопки,
    ; а не по последнему кадру цикла опроса (при быстром переносе он устаревает)
    MouseGetPos, ex, ey
    tgt := ZoneUnderCursor(ex, ey)
    idx := 0
    if (tgt) {
        UpdateMarker(tgt, ex, ey)
        idx := MarkIndex
    }
    HideMarker()
    if (cancel || !tgt)                        ; отмена или отпустили вне окна
        return

    n := Z[tgt].display.Length()
    if (!idx || idx > n + 1)
        idx := n + 1

    ; КЛЮЧЕВОЕ: запоминаем не номер, а ОБЪЕКТ-якорь, ПЕРЕД которым вставляем.
    ; Номера «плывут» после изъятия перетаскиваемых элементов — именно из-за этого
    ; последний объект раньше не вставал перед предпоследним.
    anchor := ""
    k := idx
    while (k <= n) {
        p := Z[tgt].display[k]
        if !HasVal(paths, p) {
            anchor := p
            break
        }
        k++
    }

    if (tgt != src)
        for k, p in paths {
            RemoveFromZone(src, p)
            AddItem(tgt, p)
        }

    newOrder := [], placed := 0
    for k, p in Z[tgt].display {
        if HasVal(paths, p)
            continue
        if (!placed && anchor != "" && p = anchor) {
            for j, dp in paths
                newOrder.Push(dp)
            placed := 1
        }
        newOrder.Push(p)
    }
    if (!placed)                               ; вставка в самый конец
        for j, dp in paths
            newOrder.Push(dp)

    Z[tgt].order  := newOrder
    Z[tgt].sortCol := 0                        ; ручной порядок отменяет сортировку по столбцу

    if (tgt != src)
        SaveZone(src), RefreshZone(src)
    SaveZone(tgt), RefreshZone(tgt)
    SelectPaths(tgt, paths)
}

; --- какая зона под курсором (строго по прямоугольникам) ------------------
ZoneUnderCursor(mx, my) {
    Loop, %ZCOUNT%
        if PtInCtl(LVH[A_Index], mx, my)
            return A_Index
    zi := ZoneFromPoint(mx, my)                ; заголовок/кнопки зоны
    if (zi)
        return zi
    return NearZone(mx, my, Dpi(16))           ; курсор в зазоре между зонами
}

; ближайшая зона, если точка не дальше tol пикселей от её списка
NearZone(mx, my, tol) {
    best := 0, bestD := -1
    Loop, %ZCOUNT% {
        i := A_Index
        d := RectDist(LVH[i], mx, my)
        if (d < 0)
            continue
        if (bestD < 0 || d < bestD)
            bestD := d, best := i
    }
    return (bestD >= 0 && bestD <= tol) ? best : 0
}

RectDist(hCtl, mx, my) {
    if !hCtl
        return -1
    VarSetCapacity(rc, 16, 0)
    DllCall("GetWindowRect", "Ptr", hCtl, "Ptr", &rc)
    L := NumGet(rc, 0, "Int"), T := NumGet(rc, 4, "Int")
    R := NumGet(rc, 8, "Int"), B := NumGet(rc, 12, "Int")
    dx := (mx < L) ? L - mx : (mx > R) ? mx - R : 0
    dy := (my < T) ? T - my : (my > B) ? my - B : 0
    return (dx > dy) ? dx : dy
}

PtInCtl(hCtl, mx, my) {
    if !hCtl
        return false
    VarSetCapacity(rc, 16, 0)
    DllCall("GetWindowRect", "Ptr", hCtl, "Ptr", &rc)
    return (mx >= NumGet(rc, 0, "Int") && mx < NumGet(rc, 8, "Int")
         && my >= NumGet(rc, 4, "Int") && my < NumGet(rc, 12, "Int"))
}

AutoScroll(t, my) {
    hLV := LVH[t]
    VarSetCapacity(rc, 16, 0)
    DllCall("GetWindowRect", "Ptr", hLV, "Ptr", &rc)
    top := NumGet(rc, 4, "Int"), bot := NumGet(rc, 12, "Int")
    dy := 0
    edge := Dpi(26)
    if (my - top < edge && my >= top)
        dy := -edge
    else if (bot - my < edge && my <= bot)
        dy := edge
    if (dy)
        DllCall("SendMessageW", "Ptr", hLV, "UInt", 0x1014, "Ptr", 0, "Ptr", dy)   ; LVM_SCROLL
}

; --- позиция вставки + отрисовка маркера ----------------------------------
UpdateMarker(t, mx, my) {
    hLV := LVH[t]
    n := Z[t].display.Length()
    VarSetCapacity(pt, 8, 0)
    NumPut(mx, pt, 0, "Int"), NumPut(my, pt, 4, "Int")
    DllCall("ScreenToClient", "Ptr", hLV, "Ptr", &pt)
    cx := NumGet(pt, 0, "Int"), cy := NumGet(pt, 4, "Int")
    ClientSize(hLV, lw, lh)
    L := 0, T := 0, R := 0, B := 0

    if (Z[t].view = "Report") {                ; ---- таблица: только по вертикали
        idx := InsertIndexReport(hLV, cy, n)
        pw := lw, ph := Dpi(3), px := 0, py := Dpi(2)
        if (n) {
            k := (idx > n) ? n : idx
            if GetItemRect(hLV, k - 1, L, T, R, B)
                py := ((idx > n) ? B : T) - Dpi(1)
        }
    } else {                                   ; ---- эскизы/значки: по горизонтали
        px := Dpi(3), py := Dpi(3), pw := Dpi(3), ph := Dpi(40)
        idx := InsertIndexIcon(hLV, cx, cy, n, px, py, ph)
    }

    if (px < 0)
        px := 0
    if (py < 0)
        py := 0
    if (px > lw - pw)
        px := lw - pw
    if (py > lh - ph)
        py := lh - ph

    VarSetCapacity(p2, 8, 0)
    NumPut(px, p2, 0, "Int"), NumPut(py, p2, 4, "Int")
    DllCall("ClientToScreen", "Ptr", hLV, "Ptr", &p2)
    DllCall("ScreenToClient", "Ptr", GuiHwnd, "Ptr", &p2)
    MarkZone := t, MarkIndex := idx
    ShowMarker(NumGet(p2, 0, "Int"), NumGet(p2, 4, "Int"), pw, ph)
}

InsertIndexReport(hLV, cy, n) {
    if (!n)
        return 1
    top := DllCall("SendMessageW", "Ptr", hLV, "UInt", 0x1027, "Ptr", 0, "Ptr", 0, "Int")  ; TOPINDEX
    per := DllCall("SendMessageW", "Ptr", hLV, "UInt", 0x1028, "Ptr", 0, "Ptr", 0, "Int")  ; COUNTPERPAGE
    last := top + per + 1
    if (last > n - 1)
        last := n - 1
    if (top > last)
        top := last
    L := 0, T := 0, R := 0, B := 0
    i := top
    while (i <= last) {
        if GetItemRect(hLV, i, L, T, R, B)
            if (cy < (T + B) // 2)
                return i + 1
        i++
    }
    return (last + 2 > n + 1) ? n + 1 : last + 2
}

InsertIndexIcon(hLV, cx, cy, n, ByRef px, ByRef py, ByRef ph) {
    px := Dpi(3), py := Dpi(3), ph := Dpi(40)
    if (!n)
        return 1
    top := DllCall("SendMessageW", "Ptr", hLV, "UInt", 0x1027, "Ptr", 0, "Ptr", 0, "Int")
    per := DllCall("SendMessageW", "Ptr", hLV, "UInt", 0x1028, "Ptr", 0, "Ptr", 0, "Int")
    last := top + per + 2
    if (last > n - 1)
        last := n - 1
    if (top > last)
        top := last
    sel := -1, bestD := -1
    L := 0, T := 0, R := 0, B := 0
    i := top
    while (i <= last) {
        if GetItemRect(hLV, i, L, T, R, B) {
            if (cx >= L && cx < R && cy >= T && cy < B) {
                sel := i
                break
            }
            ddx := cx - (L + R) // 2, ddy := cy - (T + B) // 2
            d := ddx * ddx + ddy * ddy
            if (bestD < 0 || d < bestD)
                bestD := d, sel := i
        }
        i++
    }
    if (sel < 0)
        return n + 1
    GetItemRect(hLV, sel, L, T, R, B)
    aft := (cx > (L + R) // 2)
    px := (aft ? R : L) - Dpi(1)
    py := T
    ph := B - T
    return sel + 1 + (aft ? 1 : 0)
}

ShowMarker(x, y, w, h) {
    GuiControl, Main:MoveDraw, %hMARK%, x%x% y%y% w%w% h%h%
    if !MarkVisible {
        DllCall("SetWindowPos", "Ptr", hMARK, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
        GuiControl, Main:Show, %hMARK%
        MarkVisible := 1
    }
}

HideMarker() {
    if MarkVisible {
        GuiControl, Main:Hide, %hMARK%
        MarkVisible := 0
    }
    MarkZone := 0, MarkIndex := 0
}

SelectPaths(i, paths) {
    UseLV(i)
    LV_Modify(0, "-Select")
    first := 1
    for k, p in Z[i].display
        if HasVal(paths, p) {
            LV_Modify(k, first ? "Select Focus Vis" : "Select")
            first := 0
        }
}

GetItemRect(hLV, idx0, ByRef L, ByRef T, ByRef R, ByRef B) {
    VarSetCapacity(rc, 16, 0)
    NumPut(0, rc, 0, "Int")                   ; LVIR_BOUNDS
    ; 0x100E = LVM_GETITEMRECT (0x1010 = LVM_GETITEMPOSITION — возвращал только угол,
    ; из-за чего все расчёты точки вставки были неверными)
    if !DllCall("SendMessageW", "Ptr", hLV, "UInt", 0x100E, "Ptr", idx0, "Ptr", &rc)
        return false
    L := NumGet(rc, 0, "Int"), T := NumGet(rc, 4, "Int")
    R := NumGet(rc, 8, "Int"), B := NumGet(rc, 12, "Int")
    return true
}

RowUnderMouse(hLV) {                          ; используется контекстным меню
    if !hLV
        return 0
    MouseGetPos, mx, my
    VarSetCapacity(pt, 8, 0)
    NumPut(mx, pt, 0, "Int"), NumPut(my, pt, 4, "Int")
    DllCall("ScreenToClient", "Ptr", hLV, "Ptr", &pt)
    VarSetCapacity(hti, 64, 0)
    NumPut(NumGet(pt, 0, "Int"), hti, 0, "Int")
    NumPut(NumGet(pt, 4, "Int"), hti, 4, "Int")
    r := DllCall("SendMessageW", "Ptr", hLV, "UInt", 0x1039, "Ptr", 0, "Ptr", &hti, "Int") ; LVM_SUBITEMHITTEST
    return (r < 0) ? 0 : r + 1
}

; ==================== ПРИЁМ ФАЙЛОВ ИЗ ПРОВОДНИКА =========================
AllowDrops(hwnd) {
    DllCall("shell32\DragAcceptFiles", "Ptr", hwnd, "Int", 1)
    try DllCall("ChangeWindowMessageFilterEx", "Ptr", hwnd, "UInt", 0x0233, "UInt", 1, "Ptr", 0)
    try DllCall("ChangeWindowMessageFilterEx", "Ptr", hwnd, "UInt", 0x0049, "UInt", 1, "Ptr", 0)
    try DllCall("ChangeWindowMessageFilterEx", "Ptr", hwnd, "UInt", 0x004A, "UInt", 1, "Ptr", 0)
}

OnDropFiles(wParam, lParam, msg, hwnd) {
    hDrop := wParam
    zi := CTLZ.HasKey(hwnd) ? CTLZ[hwnd] : 0
    if !zi {
        VarSetCapacity(pt, 8, 0)
        DllCall("shell32\DragQueryPoint", "Ptr", hDrop, "Ptr", &pt)
        DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", &pt)
        zi := ZoneFromPoint(NumGet(pt, 0, "Int"), NumGet(pt, 4, "Int"))
    }
    if (zi) {
        n := DllCall("shell32\DragQueryFileW", "Ptr", hDrop, "UInt", 0xFFFFFFFF, "Ptr", 0, "UInt", 0, "UInt")
        Loop, %n% {
            len := DllCall("shell32\DragQueryFileW", "Ptr", hDrop, "UInt", A_Index - 1, "Ptr", 0, "UInt", 0, "UInt")
            VarSetCapacity(buf, (len + 1) * 2, 0)
            DllCall("shell32\DragQueryFileW", "Ptr", hDrop, "UInt", A_Index - 1, "Str", buf, "UInt", len + 1)
            AddItem(zi, buf)
        }
        SaveZone(zi), RefreshZone(zi)
    }
    DllCall("shell32\DragFinish", "Ptr", hDrop)
    return 0
}

ZoneFromScreen() {
    MouseGetPos, mx, my
    return ZoneFromPoint(mx, my)
}

ZoneFromPoint(sx, sy) {
    VarSetCapacity(pt, 8, 0)
    NumPut(sx, pt, 0, "Int"), NumPut(sy, pt, 4, "Int")
    DllCall("ScreenToClient", "Ptr", GuiHwnd, "Ptr", &pt)
    x := NumGet(pt, 0, "Int"), y := NumGet(pt, 4, "Int")
    for i, r in ZRECT
        if (x >= r.x && x <= r.x + r.w && y >= r.y && y <= r.y + r.h)
            return i
    return 0
}

; ============================ ЛОГИКА ЗОН ================================
UseLV(i) {
    Gui, Main:Default
    Gui, ListView, % LVH[i]
}

SelectedRows(i) {
    if !i
        return []
    UseLV(i)
    rows := [], r := 0
    Loop {
        r := LV_GetNext(r)
        if !r
            break
        rows.Push(r)
    }
    return rows
}

StartFillZones() {
    global
    STARTQ := [], STARTPOS := [], STARTDONE := {}
    ICONQ := [], ICONQPOS := 1
    Loop, %ZCOUNT% {
        i := A_Index
        STARTQ[i] := BuildZoneList(i)
        STARTPOS[i] := 1
        STARTDONE[i] := 0
        UseLV(i)
        LV_Delete()
    }
    SetTimer, FillZonesChunk, 1
}

FillZonesTick() {
    global
    anyPending := 0
    Loop, %ZCOUNT% {
        i := A_Index
        if (STARTDONE[i])
            continue
        q := STARTQ[i], pos := STARTPOS[i], added := 0
        while (pos <= q.Length() && added < START_CHUNK) {
            ; Списки путей уже готовы. Добавляем до 20 элементов из каждой
            ; зоны сразу с точной быстрой системной иконкой (включая overlay
            ; ярлыка). Эскизы разрешённых форматов уточняются позднее.
            row := AddZoneRow(i, q[pos], 0)
            if ShouldLoadThumbnail(q[pos])
                ICONQ.Push({zone: i, row: row, path: q[pos]})
            pos++, added++
        }
        STARTPOS[i] := pos
        if (pos > q.Length()) {
            STARTDONE[i] := 1
            FinalizeZone(i, 0)               ; крупные эскизы догружаются отдельным таймером
        } else
            anyPending := 1
    }
    if !anyPending {
        SetTimer, FillZonesChunk, Off
        SetTimer, FillStartupIcons, 1
    }
}

RefreshZone(i) {
    ordered := BuildZoneList(i)
    UseLV(i)
    GuiControl, Main:-Redraw, % LVH[i]
    LV_Delete()
    for k, p in ordered
        AddZoneRow(i, p)
    FinalizeZone(i, 1)
}

BuildZoneList(i) {
    zz := Z[i]
    seen := {}, list := []
    for k, p in zz.items
        if (!seen[p] && FileExist(p)) {
            seen[p] := 1
            list.Push(p)
        }
    for fk, fp in zz.folders {
        if (fp = "" || !InStr(FileExist(fp), "D"))
            continue
        Loop, Files, % fp "\*.*", FD
        {
            p := A_LoopFileLongPath
            if (!seen[p] && !HasVal(zz.hidden, p)) {
                seen[p] := 1
                list.Push(p)
            }
        }
    }
    ; При активной сортировке по столбцу сохраняем прежнее поведение:
    ; весь список строится и сортируется заново по выбранному столбцу.
    if (zz.sortCol) {
        ordered := [], used := {}
        for k, p in zz.order
            if (seen[p] && !used[p]) {
                used[p] := 1
                ordered.Push(p)
            }
        for k, p in list
            if (!used[p]) {
                used[p] := 1
                ordered.Push(p)
            }
        ordered := SortList(ordered, zz.sortCol, zz.sortDir, zz.foldersFirst)
    } else {
        ; В ручном режиме существующий пользовательский порядок не меняем.
        ; Объекты, которых ещё нет в сохранённом порядке (например, новые файлы
        ; привязанной папки), выводим отдельной группой перед старым списком.
        old := [], fresh := [], used := {}
        for k, p in zz.order
            if (seen[p] && !used[p]) {
                used[p] := 1
                old.Push(p)
            }
        for k, p in list
            if (!used[p]) {
                used[p] := 1
                fresh.Push(p)
            }

        ; Между собой новые объекты располагаются от более новых к старым.
        if (fresh.Length() > 1)
            fresh := SortList(fresh, 6, -1, zz.foldersFirst)

        ordered := []
        for k, p in fresh
            ordered.Push(p)
        for k, p in old
            ordered.Push(p)

        ; Сразу принимаем получившийся порядок как текущий. Поэтому при следующем
        ; обновлении уже показанные файлы не будут снова считаться новыми и
        ; переставляться; наверх попадёт только следующая порция новых объектов.
        if (fresh.Length()) {
            zz.order := []
            for k, p in ordered
                zz.order.Push(p)
            SaveZone(i)
        }
    }
    zz.display := ordered
    return ordered
}

AddZoneRow(i, p, loadIcon := 1) {
    UseLV(i)
    SplitPath, p, nm, , ext
    isDir := InStr(FileExist(p), "D")
    sz := ""
    if !isDir {
        FileGetSize, kb, %p%, K
        sz := kb " КБ"
    }
    FileGetTime, tm, %p%, M
    FormatTime, tms, %tm%, dd.MM.yyyy HH:mm
    FileGetTime, tc, %p%, C
    FormatTime, tcs, %tc%, dd.MM.yyyy HH:mm

    ; Строка попадает в ListView только после подготовки значка текущего вида.
    ; Поэтому пользователь больше не видит временные чёрные квадраты.
    ; Быстрый точный значок непосредственно по пути. SHGetFileInfo не строит
    ; эскиз и потому обычно отвечает сразу; настоящий thumbnail появится позже.
    idx := FastIconIndex(p)
    if loadIcon {
        idx := IconIndex(p)
        if (ShouldLoadThumbnail(p) && Z[i].view = "Medium")
            PrepareIconSize(idx, p, 48)
        else if (ShouldLoadThumbnail(p) && Z[i].view = "Icon")
            PrepareIconSize(idx, p, 96)
    }
    return LV_Add("Icon" (idx + 1), nm, isDir ? "Папка" : (ext = "" ? "Файл" : ext), sz, tms, p, tcs)
}

FinalizeZone(i, loadLarge := 1) {
    UseLV(i)
    if (Z[i].view = "Report") {
        LV_ModifyCol(1, 250), LV_ModifyCol(2, 82), LV_ModifyCol(3, 92)
        LV_ModifyCol(4, 132), LV_ModifyCol(5, 0), LV_ModifyCol(6, 132)
    }
    ApplyView(i, loadLarge)
    GuiControl, Main:+Redraw, % LVH[i]
}

ApplyView(i, loadLarge := 1) {
    hLV := LVH[i]
    vw  := Z[i].view
    v   := (vw = "Report") ? 1 : 0            ; «Эскизы» и «Обычные значки» — один режим LVS_ICON

    ; 96 px для эскизов, 48 px для обычных значков (как в проводнике)
    DllCall("SendMessageW", "Ptr", hLV, "UInt", 0x1003, "Ptr", 0, "Ptr", (vw = "Medium") ? IL48 : IL96)
    DllCall("SendMessageW", "Ptr", hLV, "UInt", 0x1003, "Ptr", 1, "Ptr", IL16)

    if (vw != "Report") {
        if (loadLarge)
            FillIconSize((vw = "Medium") ? 48 : 96) ; при старте — отдельным таймером
        LVStyleClear(hLV, 0x0080)             ; снять LVS_NOLABELWRAP — подпись переносится по строкам
        sz := (vw = "Medium") ? 48 : 96
        cx := sz + Dpi(24)                    ; отступы ячейки учитывают масштаб экрана
        cy := sz + Dpi((vw = "Medium") ? 46 : 62) ; запас по высоте под многострочную подпись
        DllCall("SendMessageW", "Ptr", hLV, "UInt", 0x1035, "Ptr", 0   ; LVM_SETICONSPACING
              , "Ptr", cx | (cy << 16))
    }

    DllCall("SendMessageW", "Ptr", hLV, "UInt", 0x108E, "Ptr", v, "Ptr", 0)      ; LVM_SETVIEW
    if (vw != "Report")
        DllCall("SendMessageW", "Ptr", hLV, "UInt", 0x1016, "Ptr", 0, "Ptr", 0)  ; LVM_ARRANGE
    GuiControl, Main:, % VIEWH[i], % ViewGlyph(vw)
    UpdateSortIndicator(i)
}

; Стандартная стрелка в заголовке активного столбца таблицы.
UpdateSortIndicator(i) {
    hHeader := DllCall("SendMessageW", "Ptr", LVH[i], "UInt", 0x101F, "Ptr", 0, "Ptr", 0, "Ptr") ; LVM_GETHEADER
    if !hHeader
        return

    hdiSize := (A_PtrSize = 8) ? 72 : 48
    fmtOff  := (A_PtrSize = 8) ? 28 : 20
    Loop, 6 {
        VarSetCapacity(hdi, hdiSize, 0)
        NumPut(0x4, hdi, 0, "UInt")            ; HDI_FORMAT
        DllCall("SendMessageW", "Ptr", hHeader, "UInt", 0x120B
              , "Ptr", A_Index - 1, "Ptr", &hdi) ; HDM_GETITEMW
        fmt := NumGet(hdi, fmtOff, "Int") & ~0x600 ; убрать HDF_SORTUP/DOWN
        if (Z[i].view = "Report" && Z[i].sortCol = A_Index)
            fmt |= (Z[i].sortDir < 0) ? 0x200 : 0x400
        NumPut(fmt, hdi, fmtOff, "Int")
        DllCall("SendMessageW", "Ptr", hHeader, "UInt", 0x120C
              , "Ptr", A_Index - 1, "Ptr", &hdi) ; HDM_SETITEMW
    }
}

; Лаконичные пиктограммы режимов без текстовых кнопок.
ViewGlyph(vw) {
    return (vw = "Report") ? "☷" : (vw = "Icon") ? "▦" : "▤"
}

; снять биты оконного стиля у списка
LVStyleClear(hLV, bits) {
    fg := (A_PtrSize = 8) ? "GetWindowLongPtrW" : "GetWindowLongW"
    fs := (A_PtrSize = 8) ? "SetWindowLongPtrW" : "SetWindowLongW"
    st := DllCall("User32\" fg, "Ptr", hLV, "Int", -16, "Ptr")
    n2 := st & ~bits
    if (n2 != st)
        DllCall("User32\" fs, "Ptr", hLV, "Int", -16, "Ptr", n2)
}

SetView(i, v) {
    if !i
        return
    Z[i].view := v
    ApplyView(i), SaveZone(i), RefreshZone(i)
}

; «Очистить зону»: убираются и добавленные объекты, и содержимое привязанной папки.
; Привязка папки сохраняется — новые файлы в ней появятся в зоне как обычно.
; Чтобы вернуть скрытое, используйте «Отвязать папку», а затем выберите её снова.
ClearZone(i) {
    if !i
        return
    if (Z[i].folders.Length())
        for k, p in Z[i].display
            if !HasVal(Z[i].hidden, p)
                Z[i].hidden.Push(p)
    Z[i].items := [], Z[i].order := []
    if !RegExMatch(Z[i].name, "^Зона \d$") {         ; сбрасываем название на дефолтное,
        Z[i].name := "Зона " i                        ; если оно ещё не совпадает с ним
        GuiControl, Main:, % TITLEH[i], % Z[i].name
    }
    SaveZone(i), RefreshZone(i)
}

PickFolderFor(i) {
    if !i
        return
    Gui, Main:+OwnDialogs
    cur := ZoneFolder(i)
    start := (cur != "") ? "*" cur : ""
    FileSelectFolder, sel, %start%, 3, % "Папка для зоны «" Z[i].name "»"
    if (sel = "")
        return
    sel := RTrim(sel, "\")
    if (sel != cur)                            ; другая папка — начинаем с чистого листа
        Z[i].hidden := []
    else if (Z[i].hidden.Length()) {           ; та же папка: спрашиваем, возвращать ли скрытое
        MsgBox, 36, Зона, % "В этой зоне скрыто объектов папки: " Z[i].hidden.Length() "`n`nПоказать их снова?"
        IfMsgBox, Yes
            Z[i].hidden := []
    }
    Z[i].folders := [sel]
    if RegExMatch(Z[i].name, "^Зона \d$") {
        SplitPath, sel, nm
        if (nm != "") {
            Z[i].name := nm
            GuiControl, Main:, % TITLEH[i], %nm%
        }
    }
    SaveZone(i), RefreshZone(i)
}

AddItem(i, path) {
    path := RTrim(path, "\")
    if (path = "" || !FileExist(path))
        return
    if !HasVal(Z[i].items, path)
        Z[i].items.Push(path)
    Loop, % Z[i].hidden.Length()
        if (Z[i].hidden[A_Index] = path) {
            Z[i].hidden.RemoveAt(A_Index)
            break
        }
    if !HasVal(Z[i].order, path)
        Z[i].order.Push(path)
}

RemoveFromZone(i, path) {
    Loop, % Z[i].items.Length()
        if (Z[i].items[A_Index] = path) {
            Z[i].items.RemoveAt(A_Index)
            break
        }
    Loop, % Z[i].order.Length()
        if (Z[i].order[A_Index] = path) {
            Z[i].order.RemoveAt(A_Index)
            break
        }
    if (InFolders(i, path) != "" && !HasVal(Z[i].hidden, path))
        Z[i].hidden.Push(path)
}

LaunchItem(i, row) {                 ; (3) запустили — сохранились — вышли
    p := Z[i].display[row]
    if (p = "")
        return
    SplitPath, p, , dir
    SaveWindowPos()
    FlushSaveNow()
    if InStr(FileExist(p), "D")
        Run, % "explorer.exe """ p """", , UseErrorLevel
    else {
        Run, % """" p """", % dir, UseErrorLevel
        if ErrorLevel
            Run, % "explorer.exe """ p """", , UseErrorLevel
    }
    HideZonesWindow()
    return
}

LayoutZones(w, h) {
    ; Внутренняя сетка имеет настраиваемую толщину, внешний отступ — вдвое меньше.
    gap := Dpi(GRID_THICKNESS)
    outer := Max(Dpi(1), Floor(gap / 2))
    cw := Floor((w - outer * 2 - gap * 2) / 3)
    ch := Floor((h - outer * 2 - gap) / 2)
    if (cw < Dpi(120) || ch < Dpi(100))
        return
    Loop, %ZCOUNT% {
        i := A_Index
        col := Mod(i - 1, 3), row := (i - 1) // 3
        x := outer + col * (cw + gap)
        y := outer + row * (ch + gap)
        ZRECT[i] := {x: x, y: y, w: cw, h: ch}

        ; Справа располагаются три кнопки по 36 px: обновление,
        ; папка и выбор вида. Они идут встык, и заголовок доходит вплотную до первого значка,
        ; иначе в зазорах просвечивает цвет сетки.
        bw := Dpi(36)
        tw := cw - bw * 3
        if (tw < Dpi(60))
            tw := Dpi(60)

        ; Полоса целиком занимает заданную толщину, а текст и значки
        ; центрируются в ней по высоте стилем 0x200.
        bh := Dpi(BAND_THICKNESS)
        GuiControl, Main:Move, % TITLEH[i],   % "x" x " y" y " w" tw " h" bh
        GuiControl, Main:Move, % REFRESHH[i], % "x" (x + cw - bw * 3) " y" y " w" bw " h" bh
        GuiControl, Main:Move, % FOLDH[i],    % "x" (x + cw - bw * 2) " y" y " w" bw " h" bh
        GuiControl, Main:Move, % VIEWH[i],    % "x" (x + cw - bw)     " y" y " w" bw " h" bh
        GuiControl, Main:Move, % LVH[i],     % "x" x " y" (y + bh) " w" cw " h" (ch - bh)
        if (Z[i].view != "Report")            ; значки/плитки перестраиваются под новую ширину
            DllCall("SendMessageW", "Ptr", LVH[i], "UInt", 0x1016, "Ptr", 0, "Ptr", 0)
    }
    if EditZone
        CancelRename()
    ; (1) полная перерисовка окна вместе с дочерними контролами
    DllCall("RedrawWindow", "Ptr", GuiHwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x185)
}

ClientSize(hwnd, ByRef w, ByRef h) {
    VarSetCapacity(rc, 16, 0)
    DllCall("GetClientRect", "Ptr", hwnd, "Ptr", &rc)
    w := NumGet(rc, 8, "Int"), h := NumGet(rc, 12, "Int")
}

; Внедрение иконки повторяет способ ScreenCatcher: ресурс хранится в Base64
; и разворачивается CreateIconFromResourceEx без временных файлов.
InitAppIcons() {
    global hIcon16, hIcon32
    hIcon16 := CreateIconFromBase64(GetFileZonesBase64String(16), 16)
    hIcon32 := CreateIconFromBase64(GetFileZonesBase64String(32), 32)
    if hIcon32
        DllCall("SendMessage", "Ptr", A_ScriptHwnd, "UInt", 0x80, "Ptr", 1, "Ptr", hIcon32)
}

SetWindowIcons(hwnd) {
    global hIcon16, hIcon32
    if hIcon16
        DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x80, "Ptr", 0, "Ptr", hIcon16)
    if hIcon32
        DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x80, "Ptr", 1, "Ptr", hIcon32)
}

ApplyTrayIconVisibility() {
    global SHOW_TRAY_ICON, hIcon16
    if SHOW_TRAY_ICON {
        ; После NoIcon сначала явно возвращаем значок в область уведомлений.
        Menu, Tray, Icon
        if hIcon16
            Menu, Tray, Icon, HICON:*%hIcon16%
    } else
        Menu, Tray, NoIcon
}

; Оригинальная функция ScreenCatcher сохранена без изменения.
CreateIconFromBase64(StringBASE64, Size) {
    DllCall("Crypt32.dll\CryptStringToBinary", "Ptr", &StringBase64
       , "UInt", StrLen(StringBase64), "UInt", CRYPT_STRING_BASE64 := 1, "UInt", 0, "UInt*", Bytes, "UInt*", 0, "UInt*", 0)
 
    VarSetCapacity(IconData, Bytes) 
    DllCall("Crypt32.dll\CryptStringToBinary", "Ptr", &StringBase64 
       , "UInt", StrLen(StringBase64), "UInt", CRYPT_STRING_BASE64, "Str", IconData, "UInt*", Bytes, "UInt*", 0, "UInt*", 0)
       
    return DllCall("CreateIconFromResourceEx", "Ptr", &IconData + 4
       , "UInt", NumGet(&IconData, "UInt"), "UInt", true, "UInt", 0x30000, "Int", Size, "Int", Size, "UInt", 0, "Ptr")
}

GetFileZonesBase64String(Size) {
    Icon16 := "xgIAAIlQTkcNChoKAAAADUlIRFIAAAAQAAAAEAgGAAAAH/P/YQAAAo1JREFUeJx1k82KnFUQhp+qc76f7kxPd8LYo0HNJIpIGBEEEcVNcKHoBQjZBC/AjSAuRFy58ga8Ahe5Ad24MJsIEQTJIogtmZEs7DQz/d9ff985p1x0Z5gssngXVfVQULz1yuG3f1k1OqaZPka9ownGfJ3othwiACDAtIp4FdqFI4VAtvsc5d7LaDU6ohoO8EVJHZWDfpsvPrpMkXtMHOo866Tcen+fG9cvsmrAFyXVcEA1OsI3sxH5bp/dV94mTuYcvnGRb272+Wn4kPEyUnglLhs+v/kadwcrfj09orvXYfz3PZrZCC/qMUukusKaNetqxckiEusKayLJFGsCJ5MVs/kCwppUZ5glRD0Ktj1UQAQRwTs9q5/IOUX1XB8AQwFUwKvgVXC6GbpztVdBnsF5EVjUiXoWGM8axssAwGgemCwDhXecLBpCMpZ14r9pg2SB5aKhUwh+uU7cuN7j4w/6TBY9DvZKVISvP3mBOiRUhXVI7Hcz3nt1h+8/fYlLOzl/3r/Cj3eO8SEZl3sZ71xtMV1mdC9kiMBbB21SMkSEmIx2rjy/XdJtOerTHZKBXP3sttVRKV58k/F0zoeHPX64dYV3v3twdsLpsuGXL1/n7mDOV7eP2b/UYXH8By0P3gyKTOi2FGsc7UIB2C0VzJF7JZlDBQovdFtuwxaOFOPGBTNIW9nW1WRP61mcbj59OzXDzIhPiHNKyUjne9uUeEsBdSWal0gWyYuSXlvRvERDRL0iWaBzoaTdikhWbFhRUqrxWWePavgP08HvVFXNv3mPn3+7xuThfRZVIHNKVQXu3Kt58GjO+tER00lBPR1S9q8hZ3GePUbUERPUEUrPU3FeBXACuYcUI1lnE+f/AWLrSDSwsK66AAAAAElFTkSuQmCC"
    Icon32 := "DwQAAIlQTkcNChoKAAAADUlIRFIAAAAgAAAAIAgGAAAAc3p69AAAA9ZJREFUeJztl79vHEUUxz9vZnbvt8+2LNtBMkSOIRIohogCRYKOIh0U0OdPoElHT5GGf4GGIqkokFLQJUhIlkAEgWQJIoKRHFsm9tk5393+mEexe3e7vrPjJtD4SXc7O/OdN995783befLW57+q2ICos0N0sM1/IeHsJcL2EprGOLEB/d3H9Hb/IGxfAnTqJCMCgNfp40MRESTXolOxQnfrEX5wheriKi7q7NDbfUz76gfYShPUA1LEk3plEGfKaoFgjUznKTCIPakHZ6ASmBM4BTGkgzU6mw8xlQYuOtgmbC9jK038oAtiCruBXuRZX6lx++YyAHfu7/Bo65haaChuUAT6sef2zWXefrXKz3/1uXP/KdWgjEM9ttIkbC8THWzjRsw0Y4dISWmiwlwj4MZaE4C5xjMS7SMipc2JgFdhfaXBe6s1VC1eZQIHJlsr73VTDHnSqiReiZLsPfFadNCEHEeZC44j/yLV5yMwJGHNuH2WGMmw5kXAIf58sJcnFwQuCJROgYz+8nfJfycwU/ullEJOnX8mgcRrlo/ydyMQp0ritYSJUyVJlUL3CDvMeqpMxaFKUFh11FSgVbU4a0aZywg462lV7WhCq2qZbziaFTNBILQeZ7PM56wwX3fUT+BUPb1CjpLLt+6qtQ6zfI0vP13kxlqDbjQ2naoSWBmROOqnxKlOpuIc26paAivEqXLUT8c4BWvhsJtw66tt/t78EUc6toAHXpkLmGtY5hpMSDfKnoszdnKwIHEKUQK1UJipTSba+brFFELfkTOvWOHrH57x/e8hUTK2QJQory2EfHx9FoC7Gwc82YsI3aQF4lT56PoslxdC/tyL+OanAwI7toAx0I88/VgxksWJy8cIjHBvY5/Yj6PZCBz2PB++2eKTdzMC9zb2+e63I2ZqkzHwvO95Z6XO60shT/Yivvj2Kc1qAacgKO1Wo0xgSGKmZku+HQbWTM2O+mZqloWmKyvOsVXnCVzGPnDCQrMchMM40cK5LDkp9Vo6tCrZsUsLK6VeR32l6JbxMc7cylQcqphCGP3vmfCCwAWBc90JAV5Qj4xxOfac8HNeSgWcHbfPVGgkw5/zVpoTyD/c6pn0ihInnv1udi+PE8+ojpjYpnLUSzjsJRz1kuk4HabajKC88dkD7W79Qvvq+1NLMyUrs+qVjNjxwJP46ZcMBeqhwVlI0qw2kJMIMaSD53Q2H9JYuYYL20v4QZfO5oNTi1NV+CfvtlNuPkU59JmGYi1RFiHqbFNbvELYXsJpGlNdXMVUGmeW58NgUT07IIsfaz2lOGqsrI/K838Bs7K6HtbMtUoAAAAASUVORK5CYII="
    return (Size = 16) ? Icon16 : Icon32
}

; ============================ ИКОНКИ (SHELL) =============================
InitImageLists() {
    IL16 := MakeIL(16)                        ; таблица
    IL48 := MakeIL(48)                        ; обычные значки
    IL96 := MakeIL(96)                        ; эскизы (крупные значки)
    InitPreviewIcons()
    ICONIX := {}, ICONSRC := {}
    ILDONE := {48: {}, 96: {}}, ILTRIES := {48: {}, 96: {}}
}

; Предварительные значки типов создаются один раз. SHGFI_USEFILEATTRIBUTES не
; открывает реальные файлы и не вызывает thumbnail-provider: Shell лишь отдаёт
; кэшированный значок для фиктивного расширения. Это быстро и не даёт чёрных DIB.
InitPreviewIcons() {
    global PREVIEWIX, IL16, IL48, IL96
    PREVIEWIX := {}
    defs := [["folder", "C:\\PreviewFolder", 0x10], ["image", "preview.jpg", 0x80]
           , ["video", "preview.mp4", 0x80], ["document", "preview.docx", 0x80]
           , ["archive", "preview.zip", 0x80], ["app", "preview.exe", 0x80]
           , ["link", "preview.lnk", 0x80], ["file", "preview.bin", 0x80]]
    for k, d in defs {
        i16 := AddPreviewShellIcon(IL16, d[2], d[3], 16)
        AddPreviewShellIcon(IL48, d[2], d[3], 48)
        AddPreviewShellIcon(IL96, d[2], d[3], 96)
        PREVIEWIX[d[1]] := i16
    }
}

AddPreviewShellIcon(hIL, sample, attrs, sz) {
    ; SHFILEINFO достаточно с запасом для x86/x64; нужен только первый Ptr hIcon.
    VarSetCapacity(sfi, 704, 0)
    flags := 0x100 | 0x10                    ; SHGFI_ICON | SHGFI_USEFILEATTRIBUTES
    if (sz = 16)
        flags |= 0x1                         ; SHGFI_SMALLICON, иначе LARGEICON
    ok := DllCall("shell32\SHGetFileInfoW", "WStr", sample, "UInt", attrs
                , "Ptr", &sfi, "UInt", 704, "UInt", flags, "Ptr")
    hIcon := ok ? NumGet(sfi, 0, "Ptr") : 0
    if !hIcon
        hIcon := DllCall("user32\LoadIconW", "Ptr", 0, "Ptr", 32512, "Ptr") ; IDI_APPLICATION
    idx := DllCall("comctl32\ImageList_ReplaceIcon", "Ptr", hIL, "Int", -1
                 , "Ptr", hIcon, "Int")
    if (ok && hIcon)
        DllCall("user32\DestroyIcon", "Ptr", hIcon)
    return idx
}

PreviewIconIndex(path) {
    global PREVIEWIX
    if InStr(FileExist(path), "D")
        return PREVIEWIX["folder"]
    SplitPath, path, , , ext
    StringLower, e, ext
    if e in jpg,jpeg,jpe,png,gif,bmp,webp,tif,tiff,heic,heif,avif,psd,svg,raw,cr2,nef,dng
        return PREVIEWIX["image"]
    if e in mp4,avi,mkv,mov,wmv,m4v,mpg,mpeg,webm
        return PREVIEWIX["video"]
    if e in doc,docx,pdf,txt,rtf,xls,xlsx,ppt,pptx,csv
        return PREVIEWIX["document"]
    if e in zip,7z,rar,gz,tar,bz2
        return PREVIEWIX["archive"]
    if e in exe,com,bat,cmd,msi,scr
        return PREVIEWIX["app"]
    if e in lnk,url
        return PREVIEWIX["link"]
    return PREVIEWIX["file"]
}

InitShellCOM() {
    global SHELL_COM_INIT
    hr := DllCall("ole32\CoInitializeEx", "Ptr", 0, "UInt", 0x2, "UInt")
    SHELL_COM_INIT := (hr = 0 || hr = 1) ? 1 : 0
}

MakeIL(sz) {
    return DllCall("comctl32\ImageList_Create", "Int", sz, "Int", sz, "UInt", 0x20, "Int", 64, "Int", 64, "Ptr")
}

; один и тот же индекс во всех трёх списках, поэтому ячейки добавляются синхронно.
; Дорогие крупные картинки при старте НЕ строятся — вместо них пустые ячейки.
IconIndex(path) {
    return FastIconIndex(path)
}

; Быстрый первый уровень: обычная системная иконка файла/папки по реальному пути.
; В отличие от IShellItemImageFactory здесь не запрашивается содержимое/thumbnail.
FastIconIndex(path) {
    global ICONIX, ICONSRC, IL16, IL48, IL96
    key := IconKey(path)
    if ICONIX.HasKey(key)
        return ICONIX[key]
    idx := AddFastIconSet(path)
    ICONIX[key] := idx
    ICONSRC[idx] := path
    return idx
}

; Добавляет один и тот же системный значок во все три ImageList. Маленький
; запрашивается отдельно, крупный копируется в 48/96 — без генерации эскиза.
AddFastIconSet(path) {
    global IL16, IL48, IL96
    hSmall := FastPathIcon(path, 1)
    hLarge := FastPathIcon(path, 0)
    sharedSmall := 0, sharedLarge := 0
    if !hSmall {
        hSmall := DllCall("user32\LoadIconW", "Ptr", 0, "Ptr", 32512, "Ptr")
        sharedSmall := 1
    }
    if !hLarge {
        hLarge := DllCall("user32\LoadIconW", "Ptr", 0, "Ptr", 32512, "Ptr")
        sharedLarge := 1
    }
    i16 := DllCall("comctl32\ImageList_ReplaceIcon", "Ptr", IL16, "Int", -1, "Ptr", hSmall, "Int")
    i48 := DllCall("comctl32\ImageList_ReplaceIcon", "Ptr", IL48, "Int", -1, "Ptr", hLarge, "Int")
    i96 := DllCall("comctl32\ImageList_ReplaceIcon", "Ptr", IL96, "Int", -1, "Ptr", hLarge, "Int")
    if (hSmall && !sharedSmall)
        DllCall("user32\DestroyIcon", "Ptr", hSmall)
    if (hLarge && !sharedLarge)
        DllCall("user32\DestroyIcon", "Ptr", hLarge)
    return i16
}

FastPathIcon(path, small := 0) {
    VarSetCapacity(sfi, 704, 0)
    flags := 0x100                             ; SHGFI_ICON
    if small
        flags |= 0x1                          ; SHGFI_SMALLICON
    ok := DllCall("shell32\SHGetFileInfoW", "WStr", path, "UInt", 0
                , "Ptr", &sfi, "UInt", 704, "UInt", flags, "Ptr")
    return ok ? NumGet(sfi, 0, "Ptr") : 0
}

AddPlaceholder(hIL, sz) {
    hsq := SquareBitmap(0, sz)
    idx := DllCall("comctl32\ImageList_Add", "Ptr", hIL, "Ptr", hsq, "Ptr", 0, "Int")
    DllCall("DeleteObject", "Ptr", hsq)
    return idx
}

; Подготавливает крупный значок ДО добавления строки в ListView.
; Если такой тип/файл уже обработан, повторного обращения к Shell нет.
PrepareIconSize(idx, path, sz) {
    done := ILDONE[sz]
    if done[idx]
        return 1
    tries := ILTRIES[sz]
    hIL := (sz = 96) ? IL96 : IL48
    hbm := ShellImage(path, sz)
    if hbm {
        hsq := SquareBitmap(hbm, sz)
        DllCall("DeleteObject", "Ptr", hbm)
        if hsq {
            ok := DllCall("comctl32\ImageList_Replace", "Ptr", hIL, "Int", idx, "Ptr", hsq, "Ptr", 0, "Int")
            DllCall("DeleteObject", "Ptr", hsq)
            if ok {
                done[idx] := 1
                tries.Delete(idx)
                return 1
            }
        }
    }
    tries[idx] := tries.HasKey(idx) ? tries[idx] + 1 : 1
    if (tries[idx] >= 3)
        done[idx] := 1
    return 0
}

; настоящие крупные картинки строятся только при первом показе соответствующего вида
FillIconSize(sz) {
    hIL := (sz = 96) ? IL96 : IL48
    done := ILDONE[sz]
    for idx, p in ICONSRC {
        if !ShouldLoadThumbnail(p)
            continue
        if done[idx]
            continue
        done[idx] := 1
        hbm := ShellImage(p, sz)
        if !hbm
            continue
        hsq := SquareBitmap(hbm, sz)
        DllCall("DeleteObject", "Ptr", hbm)
        if (hsq) {
            DllCall("comctl32\ImageList_Replace", "Ptr", hIL, "Int", idx, "Ptr", hsq, "Ptr", 0)
            DllCall("DeleteObject", "Ptr", hsq)
        }
    }
}

; Второй проход начинается только после появления всех строк. ICONQ сформирована
; вперемешку по зонам, поэтому настоящие значки также появляются равномерно.
FillStartupIconsTick() {
    global
    if (ICONQPOS > ICONQ.Length()) {
        SetTimer, FillStartupIcons, Off
        return
    }

    it := ICONQ[ICONQPOS]
    ICONQPOS++
    i := it.zone, p := it.path
    idx := IconIndex(p)
    vw := Z[i].view
    if (vw = "Medium")
        PrepareIconSize(idx, p, 48)
    else if (vw = "Icon")
        PrepareIconSize(idx, p, 96)

    ; Номер строки мог измениться, если пользователь успел перетащить элементы.
    row := FindZoneRow(i, p, it.row)
    if row {
        UseLV(i)
        LV_Modify(row, "Icon" (idx + 1))
        DllCall("InvalidateRect", "Ptr", LVH[i], "Ptr", 0, "Int", 0)
    }
}

FindZoneRow(i, path, hint := 0) {
    UseLV(i)
    if (hint > 0 && hint <= LV_GetCount()) {
        LV_GetText(p, hint, 5)
        if (p = path)
            return hint
    }
    Loop, % LV_GetCount() {
        LV_GetText(p, A_Index, 5)
        if (p = path)
            return A_Index
    }
    return 0
}

FillIconSizeStep(sz) {
    hIL := (sz = 96) ? IL96 : IL48
    done := ILDONE[sz]
    for idx, p in ICONSRC {
        if !ShouldLoadThumbnail(p)
            continue
        if done[idx]
            continue
        done[idx] := 1
        hbm := ShellImage(p, sz)
        if hbm {
            hsq := SquareBitmap(hbm, sz)
            DllCall("DeleteObject", "Ptr", hbm)
            if (hsq) {
                DllCall("comctl32\ImageList_Replace", "Ptr", hIL, "Int", idx, "Ptr", hsq, "Ptr", 0)
                DllCall("DeleteObject", "Ptr", hsq)
                RedrawIconViews(sz)           ; ListView кэширует значок: явно сбрасываем отрисовку
            }
        }
        return 1
    }
    return 0
}

; После фоновой замены элемента ImageList ListView сам не всегда узнаёт,
; что вместо временного квадрата уже готов настоящий значок. Инвалидация
; заставляет соответствующие зоны перерисоваться без смены вида.
RedrawIconViews(sz) {
    Loop, %ZCOUNT% {
        i := A_Index
        vw := Z[i].view
        if ((sz = 48 && vw = "Medium") || (sz = 96 && vw = "Icon"))
            DllCall("InvalidateRect", "Ptr", LVH[i], "Ptr", 0, "Int", 1)
    }
}

; свой эскиз только у картинок/видео/ярлыков, у остальных — общий значок типа файла
IconKey(path) {
    ; У папок могут быть собственные значки из desktop.ini. Нельзя объединять
    ; все каталоги под одним ключом: иначе значок первой папки применяется
    ; к папкам в следующих строках и соседних зонах.
    if InStr(FileExist(path), "D")
        return "|DIR|" path
    SplitPath, path, , , ext
    StringLower, e, ext
    if (e = "")
        return "|FILE|"
    if (IsThumbExt(e) || e = "exe" || e = "lnk" || e = "url" || e = "ico" || e = "cur" || e = "scr")
        return path
    return "*." e
}

IsThumbExt(e) {
    static L := ",jpg,jpeg,jpe,png,gif,bmp,webp,tif,tiff,ico,heic,heif,avif,psd,svg,raw,cr2,nef,dng,"
              . "mp4,avi,mkv,mov,wmv,m4v,mpg,mpeg,webm,pdf,docx,pptx,xlsx,ai,"
    return (e != "" && InStr(L, "," e ",") > 0)
}

; Второй проход разрешён только для расширений из [App] ThumbnailExts.
; Значение "none" отключает эскизы, "*" включает для всех файлов.
ShouldLoadThumbnail(path) {
    global THUMBEXTS
    if InStr(FileExist(path), "D")
        return false
    SplitPath, path, , , ext
    StringLower, e, ext
    if (e = "")
        return false
    return (InStr(THUMBEXTS, ",*,") || InStr(THUMBEXTS, "," e ","))
}

NormalizeThumbExts(s) {
    s := Trim(s)
    StringLower, s, s
    if (s = "none" || s = "off" || s = "0")
        return ","
    s := RegExReplace(s, "[\s;]+", ",")
    s := StrReplace(s, ".", "")
    s := RegExReplace(s, ",+", ",")
    s := Trim(s, ",")
    return (s = "") ? "," : "," s ","
}

AddShellImage(hIL, path, sz) {
    idx := -1
    hbm := ShellImage(path, sz)
    if (hbm) {
        hsq := SquareBitmap(hbm, sz)
        DllCall("DeleteObject", "Ptr", hbm)
        if (hsq) {
            idx := DllCall("comctl32\ImageList_Add", "Ptr", hIL, "Ptr", hsq, "Ptr", 0, "Int")
            DllCall("DeleteObject", "Ptr", hsq)
        }
    }
    if (idx < 0) {                            ; пустая ячейка: индексы списков не должны разъехаться
        hsq := SquareBitmap(0, sz)
        idx := DllCall("comctl32\ImageList_Add", "Ptr", hIL, "Ptr", hsq, "Ptr", 0, "Int")
        DllCall("DeleteObject", "Ptr", hsq)
    }
    return idx
}

; настоящий эскиз через IShellItemImageFactory (как в проводнике)
ShellImage(path, sz) {
    static IID_SIIF := "{BCC18B79-BA16-442F-80C4-8A59C30C463B}"
    VarSetCapacity(g, 16, 0)
    if (DllCall("ole32\CLSIDFromString", "WStr", IID_SIIF, "Ptr", &g) != 0)
        return 0
    pf := 0
    if (DllCall("shell32\SHCreateItemFromParsingName", "WStr", path, "Ptr", 0, "Ptr", &g, "PtrP", pf, "UInt") != 0 || !pf)
        return 0
    SplitPath, path, , , ext
    StringLower, e, ext
    ; для 16 px превью не строим — в таблице берём быстрый значок типа файла
    thumb := (ShouldLoadThumbnail(path) && sz > 16)
    hbm := ShellImageCall(pf, sz, thumb ? 0x0 : 0x4)     ; RESIZETOFIT : ICONONLY
    if (!hbm && thumb)
        hbm := ShellImageCall(pf, sz, 0x4)
    DllCall(NumGet(NumGet(pf + 0) + 2 * A_PtrSize), "Ptr", pf)   ; Release
    return hbm
}

ShellImageCall(pf, sz, flags) {
    hbm := 0
    if (A_PtrSize = 8)
        hr := DllCall(NumGet(NumGet(pf + 0) + 3 * A_PtrSize), "Ptr", pf
                    , "Int64", sz | (sz << 32), "UInt", flags, "PtrP", hbm, "UInt")
    else
        hr := DllCall(NumGet(NumGet(pf + 0) + 3 * A_PtrSize), "Ptr", pf
                    , "Int", sz, "Int", sz, "UInt", flags, "PtrP", hbm, "UInt")
    return (hr = 0) ? hbm : 0
}

; вписать картинку в квадрат sz*sz с прозрачным фоном (32 bpp, альфа сохраняется)
SquareBitmap(hbmSrc, sz) {
    VarSetCapacity(bi, 40, 0)
    NumPut(40, bi, 0, "UInt"), NumPut(sz, bi, 4, "Int"), NumPut(sz, bi, 8, "Int")
    NumPut(1,  bi, 12, "UShort"), NumPut(32, bi, 14, "UShort")
    hdcS := DllCall("GetDC", "Ptr", 0, "Ptr")
    hdcD := DllCall("CreateCompatibleDC", "Ptr", hdcS, "Ptr")
    pBits := 0
    hbm := DllCall("CreateDIBSection", "Ptr", hdcD, "Ptr", &bi, "UInt", 0, "PtrP", pBits, "Ptr", 0, "UInt", 0, "Ptr")
    if (hbm) {
        oldD := DllCall("SelectObject", "Ptr", hdcD, "Ptr", hbm, "Ptr")
        if (hbmSrc) {
            VarSetCapacity(bm, 40, 0)
            DllCall("GetObject", "Ptr", hbmSrc, "Int", (A_PtrSize = 8) ? 32 : 24, "Ptr", &bm)
            sw := NumGet(bm, 4, "Int"), sh := NumGet(bm, 8, "Int")
            if (sw > sz)
                sw := sz
            if (sh > sz)
                sh := sz
            if (sw > 0 && sh > 0) {
                hdcM := DllCall("CreateCompatibleDC", "Ptr", hdcS, "Ptr")
                oldM := DllCall("SelectObject", "Ptr", hdcM, "Ptr", hbmSrc, "Ptr")
                DllCall("BitBlt", "Ptr", hdcD, "Int", (sz - sw) // 2, "Int", (sz - sh) // 2
                       , "Int", sw, "Int", sh, "Ptr", hdcM, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
                DllCall("SelectObject", "Ptr", hdcM, "Ptr", oldM)
                DllCall("DeleteDC", "Ptr", hdcM)
            }
        }
        DllCall("SelectObject", "Ptr", hdcD, "Ptr", oldD)
    }
    DllCall("DeleteDC", "Ptr", hdcD)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcS)
    return hbm
}

; --------- привязанные папки зоны -----------------------------------------
ZoneFolder(i) {                               ; первая привязанная папка (для диалогов)
    return Z[i].folders.Length() ? Z[i].folders[1] : ""
}

InFolders(i, path) {                          ; путь лежит внутри привязанной папки?
    for k, f in Z[i].folders
        if (f != "" && InStr(path, f "\") = 1)
            return f
    return ""
}

; ================================ INI ====================================

LoadAppSetting(key, ByRef value, defaultValue) {
    global INI
    IniRead, t, %INI%, App, %key%, __MISSING__
    if (t = "__MISSING__" || t = "ERROR") {
        value := defaultValue
        IniWrite, %value%, %INI%, App, %key%
    } else
        value := Trim(t)
}

Clamp(value, low, high) {
    return (value < low) ? low : ((value > high) ? high : value)
}

NormalizeHexColor(value, fallback := "FFFFFF") {
    value := Trim(value)
    if (SubStr(value, 1, 1) = "#")
        value := SubStr(value, 2)
    StringUpper, value, value
    return RegExMatch(value, "^[0-9A-F]{6}$") ? value : fallback
}

; Цвет полосы: либо явный HEX, либо "auto" — цвет зоны в усиленном виде.
NormalizeBandColor(value) {
    value := Trim(value)
    StringLower, low, value
    if (low = "" || low = "auto")
        return "auto"
    hex := NormalizeHexColor(value, "")
    return (hex = "") ? "auto" : hex
}

ZoneBandColor(i) {
    global Z, BAND_COLOR, BAND_INTENSITY
    if (BAND_COLOR = "auto")
        bc := IntensifyHexColor(Z[i].color, BAND_INTENSITY)
    else
        bc := NormalizeHexColor(BAND_COLOR, "")
    if !RegExMatch(bc, "i)^[0-9a-f]{6}$")            ; никогда не возвращаем пустоту
        bc := IntensifyHexColor(Z[i].color, 45)
    if !RegExMatch(bc, "i)^[0-9a-f]{6}$")
        bc := "7F8C99"
    return bc
}

; Тот же оттенок, что у зоны, но насыщеннее и темнее: полоса видна на фоне зоны.
IntensifyHexColor(hex, percent) {
    hex := NormalizeHexColor(hex, "FFFFFF")
    p := Clamp(percent + 0, 0, 100) / 100
    r := HexVal(SubStr(hex, 1, 2)) / 255
    g := HexVal(SubStr(hex, 3, 2)) / 255
    b := HexVal(SubStr(hex, 5, 2)) / 255

    mx := (r > g) ? ((r > b) ? r : b) : ((g > b) ? g : b)
    mn := (r < g) ? ((r < b) ? r : b) : ((g < b) ? g : b)
    ll := (mx + mn) / 2
    dd := mx - mn
    if (dd <= 0) {
        hh := 0
        ss := 0
    } else {
        ss := (ll > 0.5) ? dd / (2 - mx - mn) : dd / (mx + mn)
        if (mx = r)
            hh := Mod((g - b) / dd + ((g < b) ? 6 : 0), 6) / 6
        else if (mx = g)
            hh := ((b - r) / dd + 2) / 6
        else
            hh := ((r - g) / dd + 4) / 6
    }

    ss := ss + (1 - ss) * p * 0.95
    ll := ll - (ll - 0.34) * p * 0.85
    if (ll < 0.14)
        ll := 0.14
    if (ll > 0.94)
        ll := 0.94

    if (ss <= 0) {
        v := Round(ll * 255)
        return HexByte(v) HexByte(v) HexByte(v)
    }
    q  := (ll < 0.5) ? ll * (1 + ss) : ll + ss - ll * ss
    pp := 2 * ll - q
    r2 := Round(HueToRgb(pp, q, hh + 1 / 3) * 255)
    g2 := Round(HueToRgb(pp, q, hh) * 255)
    b2 := Round(HueToRgb(pp, q, hh - 1 / 3) * 255)
    return HexByte(r2) HexByte(g2) HexByte(b2)
}

; Разбор пары HEX-символов в число 0–255 без преобразования строки "0x.." в число.
HexVal(pair) {
    static d := "0123456789ABCDEF"
    pair := Trim(pair)
    StringUpper, pair, pair
    hi := InStr(d, SubStr(pair, 1, 1)) - 1
    lo := InStr(d, SubStr(pair, 2, 1)) - 1
    if (hi < 0 || lo < 0 || SubStr(pair, 1, 1) = "" || SubStr(pair, 2, 1) = "")
        return 0
    return hi * 16 + lo
}

; Один байт в два HEX-символа — без зависимости от Format() и типа числа.
HexByte(v) {
    v := Round(v)
    if (v < 0)
        v := 0
    if (v > 255)
        v := 255
    d := "0123456789ABCDEF"
    return SubStr(d, (v // 16) + 1, 1) SubStr(d, Mod(v, 16) + 1, 1)
}

UpdateBandPaint(i) {
    global BANDBRUSH, BANDBGR, BANDTXT
    bc := ZoneBandColor(i)
    bgr := HexToBgr(bc)
    if (bgr = "" || bgr < 0)
        bgr := HexToBgr("7F8C99")   ; страховка: никогда не чёрный
    BANDBGR[i] := bgr
    BANDTXT[i] := HexToBgr(BandTextColor(bc))
    old := BANDBRUSH.HasKey(i) ? BANDBRUSH[i] : 0
    BANDBRUSH[i] := DllCall("gdi32\CreateSolidBrush", "UInt", BANDBGR[i], "Ptr")
    if (old)
        DllCall("gdi32\DeleteObject", "Ptr", old)
}

; Возвращаем свою кисть только для надписей полос; остальные рисует сам AHK.
OnBandCtlColor(wParam, lParam, msg, hwnd) {
    global BANDCTL, BANDBRUSH, BANDBGR, BANDTXT, ZCOUNT, TITLEH, REFRESHH, FOLDH, VIEWH
    i := BANDCTL.HasKey(lParam) ? BANDCTL[lParam] : 0
    if (!i) {
        ; lParam может приходить в другом числовом виде, чем сохранённый hwnd,
        ; поэтому один раз сравниваем его со всеми надписями шапок и запоминаем.
        Loop, %ZCOUNT% {
            k := A_Index
            if (lParam = TITLEH[k] || lParam = REFRESHH[k] || lParam = FOLDH[k] || lParam = VIEWH[k]) {
                i := k
                BANDCTL[lParam] := k
                break
            }
        }
    }
    if (!i)
        return                         ; остальные надписи рисует сам AHK
    if (!BANDBRUSH.HasKey(i) || !BANDBRUSH[i])
        UpdateBandPaint(i)
    if (!BANDBRUSH[i])
        return                         ; кисть создать не удалось — пусть рисует AHK, а не чёрный фон
    DllCall("gdi32\SetTextColor", "Ptr", wParam, "UInt", BANDTXT[i])
    DllCall("gdi32\SetBkColor",   "Ptr", wParam, "UInt", BANDBGR[i])
    return BANDBRUSH[i]
}

HexToBgr(hex) {
    hex := NormalizeHexColor(hex, "FFFFFF")
    r := HexVal(SubStr(hex, 1, 2))
    g := HexVal(SubStr(hex, 3, 2))
    b := HexVal(SubStr(hex, 5, 2))
    return b * 65536 + g * 256 + r
}

BandTextColor(hex) {
    hex := NormalizeHexColor(hex, "FFFFFF")
    r := HexVal(SubStr(hex, 1, 2))
    g := HexVal(SubStr(hex, 3, 2))
    b := HexVal(SubStr(hex, 5, 2))
    lum := (r * 299 + g * 587 + b * 114) / 1000
    return (lum < 150) ? "FFFFFF" : "202020"
}

RgbToHsl(r, g, b, ByRef h, ByRef s, ByRef l) {
    r := r / 255, g := g / 255, b := b / 255
    mx := (r > g) ? ((r > b) ? r : b) : ((g > b) ? g : b)
    mn := (r < g) ? ((r < b) ? r : b) : ((g < b) ? g : b)
    l := (mx + mn) / 2
    if (mx = mn) {
        h := 0, s := 0
        return
    }
    d := mx - mn
    s := (l > 0.5) ? d / (2 - mx - mn) : d / (mx + mn)
    if (mx = r)
        h := Mod((g - b) / d + ((g < b) ? 6 : 0), 6) / 6
    else if (mx = g)
        h := ((b - r) / d + 2) / 6
    else
        h := ((r - g) / d + 4) / 6
}

HslToRgb(h, s, l, ByRef r, ByRef g, ByRef b) {
    if (s <= 0) {
        v := Round(l * 255)
        r := v, g := v, b := v
        return
    }
    q := (l < 0.5) ? l * (1 + s) : l + s - l * s
    p := 2 * l - q
    r := Round(HueToRgb(p, q, h + 1 / 3) * 255)
    g := Round(HueToRgb(p, q, h) * 255)
    b := Round(HueToRgb(p, q, h - 1 / 3) * 255)
}

HueToRgb(p, q, t) {
    if (t < 0)
        t += 1
    if (t > 1)
        t -= 1
    if (t < 1 / 6)
        return p + (q - p) * 6 * t
    if (t < 1 / 2)
        return q
    if (t < 2 / 3)
        return p + (q - p) * (2 / 3 - t) * 6
    return p
}

; Цвета зоны: список получает цвет зоны, шапка — цвет полосы.
; Цвета одной зоны: список — цвет зоны, полоса шапки — свой цвет.
; Фон и цвет текста задаются разными командами: в одном GuiControl их смешивать нельзя.
ApplyZoneColors(i) {
    global Z, TITLEH, REFRESHH, FOLDH, VIEWH, LVH, FS_TITLE, FS_BASE, GuiHwnd
    c := Z[i].color

    UpdateBandPaint(i)                 ; цвет полосы и цвет текста на ней
    bc := ZoneBandColor(i)
    GuiControl, Main:+Background%bc%, % TITLEH[i]
    GuiControl, Main:+Background%bc%, % REFRESHH[i]
    GuiControl, Main:+Background%bc%, % FOLDH[i]
    GuiControl, Main:+Background%bc%, % VIEWH[i]
    GuiControl, Main:+Background%c%, % LVH[i]

    Gui, Main:Font, % "s" FS_TITLE " w600", Segoe UI
    GuiControl, Main:Font, % TITLEH[i]
    Gui, Main:Font, s18 Norm, Segoe UI Symbol
    GuiControl, Main:Font, % REFRESHH[i]
    Gui, Main:Font, s14 Norm, Segoe UI Emoji
    GuiControl, Main:Font, % FOLDH[i]
    Gui, Main:Font, s16 Norm, Segoe UI
    GuiControl, Main:Font, % VIEWH[i]
    Gui, Main:Font, % "s" FS_BASE " Norm c202020", Segoe UI
    GuiControl, Main:Font, % LVH[i]

    DllCall("RedrawWindow", "Ptr", TITLEH[i], "Ptr", 0, "Ptr", 0, "UInt", 0x185)
    DllCall("RedrawWindow", "Ptr", REFRESHH[i], "Ptr", 0, "Ptr", 0, "UInt", 0x185)
    DllCall("RedrawWindow", "Ptr", FOLDH[i], "Ptr", 0, "Ptr", 0, "UInt", 0x185)
    DllCall("RedrawWindow", "Ptr", VIEWH[i], "Ptr", 0, "Ptr", 0, "UInt", 0x185)
}

; Высота названия и кнопок внутри полосы: не больше самой полосы.
BandTitleHeight() {
    global FS_TITLE, BAND_THICKNESS
    h := Dpi(Round(FS_TITLE * 1.7) + 6)
    maxH := Dpi(BAND_THICKNESS)
    return (h > maxH) ? maxH : h
}

BandIconHeight() {
    global BAND_THICKNESS
    return Dpi((BAND_THICKNESS < 32) ? BAND_THICKNESS : 32)
}

ParseColorList(raw, minCount, maxCount) {
    arr := []
    raw := StrReplace(StrReplace(raw, ";", ","), " ", ",")
    Loop, Parse, raw, `,
    {
        color := Trim(A_LoopField)
        if (color = "")
            continue
        if !RegExMatch(color, "i)^#?[0-9a-f]{6}$")
            return ""
        arr.Push(NormalizeHexColor(color))
    }
    return (arr.Length() >= minCount && arr.Length() <= maxCount) ? arr : ""
}

JoinColors(colors) {
    out := ""
    for k, color in colors
        out .= (out = "" ? "" : ",") color
    return out
}

EnsureIni() {
    if !FileExist(INI) {
        f := FileOpen(INI, "w", "UTF-16")     ; BOM — иначе кириллица бьётся
        if IsObject(f) {
            f.Write("[App]`n")
            f.Close()
        }
    }
}

; Секции INI создаются по мере первого сохранения каждой зоны, поэтому без этой
; пересборки они могут оказаться в произвольном порядке. Вызывается раз при
; запуске, когда секции всех зон уже гарантированно существуют в файле.
ReorderIniSections() {
    global INI, ZCOUNT
    names := [], secs := {}
    IniRead, appSec, %INI%, App
    if (appSec != "ERROR") {
        names.Push("App"), secs["App"] := appSec
    }
    Loop, %ZCOUNT% {
        nm := "Zone" A_Index
        IniRead, zSec, %INI%, %nm%
        if (zSec != "ERROR") {
            names.Push(nm), secs[nm] := zSec
        }
    }
    if !names.Length()
        return
    out := ""
    for k, nm in names
        out .= "[" nm "]`r`n" secs[nm] "`r`n`r`n"
    f := FileOpen(INI, "w", "UTF-16")     ; BOM — иначе кириллица бьётся
    if IsObject(f) {
        f.Write(out)
        f.Close()
    }
}

LoadState() {
    ; Общие параметры интерфейса и загрузки. Отсутствующие ключи дописываются.
    LoadAppSetting("StartChunk", START_CHUNK, 40)
    START_CHUNK := Clamp(START_CHUNK + 0, 1, 500)
    LoadAppSetting("FontBase", FS_BASE, 11)
    FS_BASE := Clamp(FS_BASE + 0, 8, 24)
    LoadAppSetting("FontTitle", FS_TITLE, 15)
    FS_TITLE := Clamp(FS_TITLE + 0, 9, 32)
    LoadAppSetting("GridColor", GRID_COLOR, "FFFFFF")
    GRID_COLOR := NormalizeHexColor(GRID_COLOR, "FFFFFF")
    LoadAppSetting("GridThickness", GRID_THICKNESS, 10)
    GRID_THICKNESS := Clamp(GRID_THICKNESS + 0, 2, 40)
    LoadAppSetting("BandColor", BAND_COLOR, "auto")
    BAND_COLOR := NormalizeBandColor(BAND_COLOR)
    LoadAppSetting("BandThickness", BAND_THICKNESS, 32)
    BAND_THICKNESS := Clamp(BAND_THICKNESS + 0, 20, 90)
    LoadAppSetting("BandIntensity", BAND_INTENSITY, 45)
    BAND_INTENSITY := Clamp(BAND_INTENSITY + 0, 0, 100)
    LoadAppSetting("ShowTrayIcon", SHOW_TRAY_ICON, 1)
    SHOW_TRAY_ICON := (SHOW_TRAY_ICON = 0) ? 0 : 1

    IniRead, rawColors, %INI%, App, DefaultColors, __MISSING__
    if (rawColors = "__MISSING__" || rawColors = "ERROR")
        IniWrite, % JoinColors(DEFCOL), %INI%, App, DefaultColors
    else if IsObject(parsed := ParseColorList(rawColors, 6, 6))
        DEFCOL := parsed

    IniRead, rawColors, %INI%, App, Palette, __MISSING__
    if (rawColors = "__MISSING__" || rawColors = "ERROR")
        IniWrite, % JoinColors(PALETTE), %INI%, App, Palette
    else if IsObject(parsed := ParseColorList(rawColors, 6, 16))
        PALETTE := parsed

    ; Форматы, для которых обычная системная иконка во втором проходе заменяется
    ; эскизом. Ключ автоматически добавляется в существующий INI.
    IniRead, thumbCfg, %INI%, App, ThumbnailExts, __MISSING__
    if (thumbCfg = "__MISSING__" || thumbCfg = "ERROR") {
        thumbCfg := THUMBEXTS_RAW
        IniWrite, %thumbCfg%, %INI%, App, ThumbnailExts
    }
    THUMBEXTS_RAW := Trim(thumbCfg)
    THUMBEXTS := NormalizeThumbExts(THUMBEXTS_RAW)

    IniRead, t, %INI%, App, W, __MISSING__
    WW := (t != "__MISSING__" && t + 0 > Dpi(400)) ? t + 0 : Dpi(1280)
    IniRead, t, %INI%, App, H, __MISSING__
    WH := (t != "__MISSING__" && t + 0 > Dpi(300)) ? t + 0 : Dpi(800)
    IniRead, t, %INI%, App, X, %A_Space%      ; позиция окна теперь запоминается
    WX := (t = "ERROR" || Trim(t) = "") ? "" : Trim(t)
    IniRead, t, %INI%, App, Y, %A_Space%
    WY := (t = "ERROR" || Trim(t) = "") ? "" : Trim(t)
    IniRead, t, %INI%, App, Max, 1
    WMAX := (t = 1) ? 1 : 0                   ; развёрнуто на весь экран
    WSAVED := WW "|" WH "|" WX "|" WY "|" WMAX ; снимок для сравнения при сохранении

    Loop, %ZCOUNT% {
        i := A_Index
        o := {}
        ; вся зона читается одной секцией: скаляры + список fld1..fldN
        IniRead, sec, %INI%, Zone%i%
        kv := {}, lst := []
        if (sec != "ERROR" && sec != "")
            Loop, Parse, sec, `n, `r
            {
                if (A_LoopField = "")
                    continue
                q := InStr(A_LoopField, "=")     ; делим по первому «=» — путь может его содержать
                if (!q)
                    continue
                key := Trim(SubStr(A_LoopField, 1, q - 1))
                val := SubStr(A_LoopField, q + 1)
                if RegExMatch(key, "i)^fld\d+$") {
                    if (Trim(val) != "")
                        lst.Push(Trim(val))
                } else
                    kv[key] := val
            }

        o.name := kv.HasKey("Name") ? kv["Name"] : "Зона " i
        t := kv.HasKey("Color") ? Trim(kv["Color"]) : ""
        o.color := (StrLen(t) != 6) ? DEFCOL[i] : t
        t := kv.HasKey("View") ? Trim(kv["View"]) : "Report"
        if (t = "Tile")                       ; старая «Плитка» → «Обычные значки»
            t := "Medium"
        o.view := (t = "Icon" || t = "Medium") ? t : "Report"
        t := kv.HasKey("SortCol") ? Trim(kv["SortCol"]) : 0
        o.sortCol := (t + 0 >= 1 && t + 0 <= 6) ? t + 0 : 0
        t := kv.HasKey("SortDir") ? Trim(kv["SortDir"]) : 1
        o.sortDir := (t = -1) ? -1 : 1
        t := kv.HasKey("FoldersFirst") ? Trim(kv["FoldersFirst"]) : 0
        o.foldersFirst := (t = 1) ? 1 : 0

        o.folders := [], o.items := [], o.order := [], o.hidden := []
        o.display := []
        Z[i] := o
        for k, v in lst                        ; сначала папки: они могут стоять где угодно
            if (SubStr(v, 1, 1) = "*") {
                f := RTrim(Trim(SubStr(v, 2)), "\")
                if (f != "" && !HasVal(o.folders, f))
                    o.folders.Push(f)
            }
        for k, v in lst {
            c := SubStr(v, 1, 1)
            if (c = "*")
                continue
            if (c = "-") {                     ; скрытый объект привязанной папки
                p := RTrim(Trim(SubStr(v, 2)), "\")
                if (p != "" && !HasVal(o.hidden, p))
                    o.hidden.Push(p)
                continue
            }
            p := RTrim(v, "\")
            if (p = "")
                continue
            if !HasVal(o.order, p)             ; порядок строк = порядок в зоне
                o.order.Push(p)
            if (InFolders(i, p) = "" && !HasVal(o.items, p))
                o.items.Push(p)                ; объект вне привязанных папок — добавлен вручную
        }
        if (!lst.Length())
            LoadLegacyZone(i)                  ; INI старого формата
    }
    for i, v in DIRTY {                        ; найден старый формат — перенесём его в новый
        SetTimer, FlushSave, -1500
        break
    }
}

; чтение старого формата: Folder= в [ZoneN] плюс секции _Items/_Order/_Hidden
LoadLegacyZone(i) {
    IniRead, t, %INI%, Zone%i%, Folder, %A_Space%
    f := (t = "ERROR") ? "" : RTrim(Trim(t), "\")
    if (f != "")
        Z[i].folders := [f]
    Z[i].items  := ReadList("Zone" i "_Items")
    Z[i].order  := ReadList("Zone" i "_Order")
    Z[i].hidden := ReadList("Zone" i "_Hidden")
    if (f != "" || Z[i].items.Length() || Z[i].order.Length() || Z[i].hidden.Length())
        LEGACY[i] := 1, DIRTY[i] := 1
}

ReadList(sec) {
    arr := []
    IniRead, raw, %INI%, %sec%
    if (raw = "ERROR" || raw = "")
        return arr
    Loop, Parse, raw, `n, `r
    {
        p := InStr(A_LoopField, "=")
        if (p) {
            v := SubStr(A_LoopField, p + 1)
            if (v != "")
                arr.Push(v)
        }
    }
    return arr
}

WriteList(sec, arr) {
    pairs := ""
    for k, v in arr
        pairs .= "i" k "=" v "`n"
    IniDelete, %INI%, %sec%
    if (pairs != "")
        IniWrite, %pairs%, %INI%, %sec%
}

; запись выполняется сразу — раздел [ZoneN] мал, лишний диск-IO не оправдывает риск
; потери изменений при закрытии/аварийном завершении в течение отложенного окна
SaveZone(i) {
    WriteZone(i)
}

FlushSave:
FlushSaveNow()
return

FlushSaveNow() {
    for i, v in DIRTY
        WriteZone(i)
    DIRTY := {}
}

; вся зона пишется одной операцией: секция [ZoneN] заменяется целиком
WriteZone(i) {
    zz := Z[i]
    pairs := "Name=" zz.name "`n"
           . "Color=" zz.color "`n"
           . "View=" zz.view "`n"
           . "SortCol=" zz.sortCol "`n"
           . "SortDir=" zz.sortDir "`n"
           . "FoldersFirst=" zz.foldersFirst "`n"
    n := 0, used := {}
    for k, f in zz.folders                     ; привязанные папки
        if (f != "" && !used["*" f]) {
            used["*" f] := 1
            n++, pairs .= "fld" n "=*" f "`n"
        }
    for k, p in zz.hidden                      ; скрытые объекты папок
        if (p != "" && !used[p]) {
            used[p] := 1
            n++, pairs .= "fld" n "=-" p "`n"
        }
    ; при сортировке по столбцу порядок вычисляется на лету — содержимое папок
    ; в файл не пишется вовсе, хранятся только объекты, добавленные вручную
    lists := zz.sortCol ? [zz.items] : [zz.order, zz.items]
    for li, arr in lists
        for k, p in arr
            if (p != "" && !used[p] && (!zz.sortCol || InFolders(i, p) = "")) {
                used[p] := 1
                n++, pairs .= "fld" n "=" p "`n"
            }
    IniWrite, %pairs%, %INI%, Zone%i%
    if LEGACY.HasKey(i) {                      ; разовая уборка секций старого формата
        IniDelete, %INI%, Zone%i%_Items
        IniDelete, %INI%, Zone%i%_Order
        IniDelete, %INI%, Zone%i%_Hidden
        LEGACY.Delete(i)
    }
}

; сохраняются размер, позиция и признак «развёрнуто на весь экран»
SaveWindowPos() {
    if !GuiHwnd
        return
    WinGet, mm, MinMax, ahk_id %GuiHwnd%
    if (mm = -1)                       ; свёрнуто — состояние не трогаем
        return
    WMAX := (mm = 1) ? 1 : 0
    if (!WMAX) {                       ; геометрию берём только у обычного окна
        ClientSize(GuiHwnd, w, h)
        if (w > Dpi(300) && h > Dpi(200))
            WW := w, WH := h
        WinGetPos, wx, wy, , , ahk_id %GuiHwnd%
        if (wx != "")
            WX := wx, WY := wy
    }
    now := WW "|" WH "|" WX "|" WY "|" WMAX
    if (now = WSAVED)                  ; окно не двигали и не меняли размер — файл не трогаем
        return
    WSAVED := now
    IniWrite, %WW%, %INI%, App, W
    IniWrite, %WH%, %INI%, App, H
    if (WX != "") {
        IniWrite, %WX%, %INI%, App, X
        IniWrite, %WY%, %INI%, App, Y
    }
    IniWrite, %WMAX%, %INI%, App, Max
}

; ============================ СОРТИРОВКА СПИСКА ==========================
; столбцы: 1 Имя, 2 Тип, 3 Размер, 4 Изменён, 5 Путь, 6 Создан; dir: 1 / -1
; foldersFirst = 1: папки всегда отдельной группой перед файлами.
SortList(list, col, dir, foldersFirst := 0) {
    if (!foldersFirst)
        return SortListCore(list, col, dir)

    dirs := [], files := []
    for k, p in list
        if InStr(FileExist(p), "D")
            dirs.Push(p)
        else
            files.Push(p)

    dirs := SortListCore(dirs, col, dir)
    files := SortListCore(files, col, dir)
    out := []
    for k, p in dirs
        out.Push(p)
    for k, p in files
        out.Push(p)
    return out
}

SortListCore(list, col, dir) {
    if (list.Length() < 2)
        return list
    s := ""
    for k, p in list
        s .= SortKey(p, col) "`t" p "`n"
    s := RTrim(s, "`n")
    Sort, s, % (dir < 0) ? "R" : ""
    out := []
    Loop, Parse, s, `n, `r
    {
        t := InStr(A_LoopField, "`t")
        if (t)
            out.Push(SubStr(A_LoopField, t + 1))
    }
    return (out.Length() = list.Length()) ? out : list
}

SortKey(p, col) {
    SplitPath, p, nm, , ext
    isDir := InStr(FileExist(p), "D") ? 1 : 0
    if (col = 3) {                            ; размер — числом (с выравниванием нулями)
        sz := 0
        if (!isDir)
            FileGetSize, sz, %p%
        return ZeroPad(sz, 18)
    }
    if (col = 4) {                            ; дата изменения — YYYYMMDDHHMISS
        FileGetTime, tm, %p%, M
        return tm
    }
    if (col = 6) {                            ; дата создания — YYYYMMDDHHMISS
        FileGetTime, tc, %p%, C
        return tc
    }
    key := (col = 2) ? (isDir ? "" : ext) : ((col = 5) ? p : nm)
    StringLower, key, key
    return key
}

ZeroPad(n, len) {
    s := "" n
    while (StrLen(s) < len)
        s := "0" s
    return s
}

; Создаёт цветные HBITMAP в памяти и сразу назначает их пунктам меню.
; Файлы BMP/ICO не используются.
AttachSwatches(hMenu, colors) {
    global SWATCH
    static MIIM_BITMAP := 0x0080

    if !hMenu
        return

    miiSize := (A_PtrSize = 8) ? 80 : 48
    ofsBmp  := (A_PtrSize = 8) ? 72 : 44

    VarSetCapacity(mii, miiSize, 0)
    NumPut(miiSize,     mii, 0, "UInt")
    NumPut(MIIM_BITMAP, mii, 4, "UInt")

    for i, hex in colors {
        hbm := SwatchBitmap(hex)
        if (!hbm)
            continue
        NumPut(hbm, mii, ofsBmp, "Ptr")
        DllCall("User32\SetMenuItemInfoW", "Ptr", hMenu, "UInt", i - 1, "Int", true, "Ptr", &mii)
    }
}

; 32-битный top-down DIB с заполненным альфа-каналом (0xFF),
; иначе меню рисует чёрные квадраты.
SwatchBitmap(hex, border := 0xB0B0B0) {
    global SWATCH

    hex := Trim(hex)
    if (SubStr(hex, 1, 1) = "#")
        hex := SubStr(hex, 2)
    if (StrLen(hex) != 6)
        return 0

    if SWATCH.HasKey(hex)
        return SWATCH[hex]

    size := DllCall("GetSystemMetrics", "Int", 49)   ; SM_CXSMICON
    if (size < 8)
        size := 16

    rgb := "0x" hex
    rgb += 0

    VarSetCapacity(bi, 40, 0)              ; BITMAPINFOHEADER
    NumPut(40,     bi,  0, "UInt")         ; biSize
    NumPut(size,   bi,  4, "Int")          ; biWidth
    NumPut(-size,  bi,  8, "Int")          ; biHeight < 0 -> top-down
    NumPut(1,      bi, 12, "UShort")       ; biPlanes
    NumPut(32,     bi, 14, "UShort")       ; biBitCount
    NumPut(0,      bi, 16, "UInt")         ; biCompression = BI_RGB

    bits := 0
    hbm := DllCall("CreateDIBSection", "Ptr", 0, "Ptr", &bi, "UInt", 0   ; DIB_RGB_COLORS
                 , "Ptr*", bits, "Ptr", 0, "UInt", 0, "Ptr")
    if (!hbm || !bits) {
        if (hbm)
            DllCall("DeleteObject", "Ptr", hbm)
        return 0
    }

    fill := 0xFF000000 | rgb
    edge := 0xFF000000 | border
    last := size - 1

    Loop, %size% {
        y := A_Index - 1
        Loop, %size% {
            x := A_Index - 1
            onEdge := (x = 0 || y = 0 || x = last || y = last)
            NumPut(onEdge ? edge : fill, bits + 0, (y * size + x) * 4, "UInt")
        }
    }

    ; Bitmap должен существовать всё время, пока работает меню.
    SWATCH[hex] := hbm
    return hbm
}

FreeSwatches() {
    global SWATCH
    for hex, hbm in SWATCH
        DllCall("DeleteObject", "Ptr", hbm)
    SWATCH := {}
}

; =============================== УТИЛИТЫ =================================
HasVal(arr, val) {
    if (val = "")
        return false
    for k, v in arr
        if (v = val)
            return true
    return false
}

ToggleFileZonesWindow(wParam, lParam, msg, hwnd) {
    global GuiHwnd

    if (hwnd != GuiHwnd)
        return

    if DllCall("IsWindowVisible", "Ptr", GuiHwnd)
        HideZonesWindow()
    else
        ShowZonesWindow()
}

HideZonesWindow() {
    global EditZone

    if (EditZone)
        CommitRename()

    SaveWindowPos()
    FlushSaveNow()
    Gui, Main:Hide
}

ShowZonesWindow() {
    global GuiHwnd, WMAX

    ; WinRestore здесь использовать нельзя: он принудительно переводит
    ; развёрнутое окно в обычное состояние. Сохраняем состояние до Show,
    ; поскольку событие GuiSize во время показа может временно изменить WMAX.
    wantMax := WMAX
    if (wantMax) {
        Gui, Main:Show, Maximize
        WMAX := 1
    } else {
    Gui, Main:Show
    }
    WinActivate, ahk_id %GuiHwnd%
}

AppExit:
if EditZone
    CommitRename()
SaveWindowPos()
FreeSwatches()
if hIcon16
    DllCall("DestroyIcon", "Ptr", hIcon16)
if hIcon32
    DllCall("DestroyIcon", "Ptr", hIcon32)
FlushSaveNow()    ; на выходе пишутся только зоны, помеченные SaveZone()
if SHELL_COM_INIT
    DllCall("ole32\CoUninitialize")
ExitApp

EditScript() {
    Edit
}
