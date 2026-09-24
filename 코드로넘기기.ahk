#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off

; ==================================================
; 코드로 넘기기
;
; 화면 좌표나 색을 보지 않고, 웹페이지 안의 '코드'(class / id / 이름)로
; 버튼을 직접 눌러서 강의를 넘깁니다.
;   - 마우스를 움직이지 않습니다.
;   - 강의 창이 다른 창 뒤에 있어도 됩니다. (창을 앞으로 끌어내지 않음)
;   - 사이트마다 다른 부분은 '사이트' 폴더의 프로필 파일에만 적습니다.
;
; 단축키
;   F9  : 시작 / 정지                 (설정 창에서 바꿀 수 있음)
;   F10 : 코드 목록 뽑기                (설정 창에서 바꿀 수 있음)
;   F11 : 강의 창 밀어두기 / 되돌리기   (설정 창에서 바꿀 수 있음)
;   ESC : 이 창이 앞에 있을 때 정지
;
; 작업 중 오버레이
;   화면 우상단에 페이지 / 시간 / 상태를 작게 띄운다. 사람이 봐야 하면 빨갛게 바뀐다.
;   끌어서 옮기고(자리 기억), 누르면 이 창이 뜬다.
; ==================================================

SetWorkingDir A_ScriptDir
SetTitleMatchMode 2

global appVersion   := "1.5.0"      ; 바꾸면 CHANGELOG.md 에도 적는다
global profileDir   := A_ScriptDir "\사이트"
global settingFile  := A_ScriptDir "\코드로넘기기.ini"
global dumpFile     := A_ScriptDir "\코드목록.txt"

global profileList  := []          ; 프로필 이름 목록
global prof         := ""          ; 현재 프로필 (Map of Map)
global profName     := ""
global running      := false
global lectureHwnd  := 0
global pressCount   := 0
global holdUntil    := 0           ; 이 시각까지는 누르지 않음 (연타 방지)
global lastQuizBeep := 0
global lastTimeVal  := -1
global lastTimeTick := 0
global lastTimeMovedTick := 0      ; 재생 시간이 실제로 바뀐 것을 마지막으로 본 시각
global lastPageVal  := -1
global doneNotified := false

global tgToken      := ""          ; 텔레그램 봇 토큰
global tgChat       := ""          ; 텔레그램 채팅 ID
global lastReadTick := 0           ; 마지막으로 강의 화면을 읽은 시각
global blindNotified := false      ; '읽을 수 없음' 을 이미 알렸는지
global awakeOn      := false

global windowHwnds  := []          ; 창 고르기 목록에 들어 있는 창 번호
global pinnedHwnd   := 0           ; 사용자가 직접 고른 창 (0 이면 자동)
global covered      := false       ; 강의 창이 완전히 가려졌는지
global coveredNotified := false
global asideSaved   := ""          ; 밀어두기 전의 창 위치
global asideHwnd    := 0

global ovl          := 0           ; 작업 중 오버레이
global ovlPage, ovlTime, ovlPlay, ovlEmo, ovlWord
global ovlLook      := ""          ; 지금 오버레이 겉모양 (보통 / 정지 / 주의 / 완료)

global gui1, ddSite, ddWindow, txtWindow, txtState, txtCount, btnStart, btnAside
global chkNext, chkPlay, chkQuizBeep, chkEndClose, chkTelegram, chkAwake, chkNoFront, ddTarget
global gui3, editToken, editChat, editAsidePx, ddAsideSide, rdOvlBig, rdOvlSmall, rdOvlHidden
global asideSideSet    := "자동"      ; 밀어둘 쪽 (자동 / 오른쪽 / 왼쪽)
global settingsLoaded := false    ; 설정을 읽기 전에는 저장하지 않는다
global ovlMode      := "크게"      ; 오버레이 (크게 / 작게 / 숨김)
global ovlIcon      := 0
global hkStart      := "F9"        ; 단축키 (설정 창에서 바꿀 수 있음)
global hkAside      := "F11"
global hkDump       := "F10"
global hkCtlStart, hkCtlAside, hkCtlDump, txtHotkeys
global chkQuizAuto, editQuizWait
global quizStep     := 0           ; 퀴즈 자동: 0 보기 누를 차례 / 1 기다리는 중 / 2 넘김
global quizTick     := 0
global quizPage     := -1
global quizTries    := 0
global quizStuck    := false       ; 자동으로 못 넘겨서 사람이 봐야 함
global quizNote     := ""          ; 상태 칸에 보일 설명
global quizFail     := 0           ; 처음으로 못 찾거나 못 누른 시각 (0 이면 문제 없음)
global quizWhy      := ""          ; 자동으로 못 넘긴 까닭
global quizGoneTick := 0           ; 퀴즈가 안 보이기 시작한 시각
global quizLatchPage := -1         ; 영상 없는 퀴즈 페이지로 알아본 페이지 번호
global quizStarted  := false       ; 이 페이지에서 [문제풀이] 시작 버튼을 눌렀는지
global quizTried    := Map()       ; 이 퀴즈에서 이미 눌러 본 답 (오답이면 다른 답을 누르려고)
global quizLastKey  := ""          ; 마지막으로 누른 답
global quizLastName := ""
global staticPage   := -1          ; 영상도 퀴즈도 없는 페이지를 처음 본 페이지 번호
global sessionNum   := 0           ; 지금 보고 있는 차시 번호
global videoWrapped := false       ; 영상이 끝나고 시간이 0으로 되돌아갔는지
global lastTotalVal := -1          ; 지난번에 읽은 전체 시간 (바뀌면 다른 영상)
global editTickSec                 ; 화면 읽는 주기(초)
global readGapMs   := 0            ; 지난번 읽기와 이번 읽기 사이 간격
global guessCur    := 0            ; 오버레이 시계를 혼자 흐르게 하기 위한 마지막 값
global guessTotal  := 0
global guessTick   := 0
global ddList                      ; 차시 목록이 있는 창 고르기
global listHwnds := []             ; 그 칸에 담긴 창들
global pinnedListHwnd := 0         ; 직접 고른 차시 목록 창 (0 이면 자동)
global sessionInfo := []           ; 차시 목록 {num, name, time, done}
global sessionTotal := 0           ; 전체 차시 수
global editLastSession             ; 몇 차시까지 들을지 (비우면 끝까지)
global txtSessionInfo              ; 설정 창의 차시 목록 상자
global sessionTried := Map()       ; 이미 눌러 본 차시 번호
global sessionPct := Map()         ; 차시 번호 → 진도율 (학습창 목록에서 읽음. 100 이면 다 들음)
global endedSince := 0             ; '끝남' 표시를 처음 본 시각 (안내창이 뜰 틈을 준다)
global noticeSeen := Map()         ; 이미 알린 모르는 안내창 글
global awaitFresh := 0             ; 차시를 넘긴 시각. 새 영상이 도는 것을 볼 때까지 '끝남' 을 믿지 않는다 (0 이면 아님)
global chkOnTop                    ; 진행 중에는 강의 창을 항상 위에
global topHwnd := 0                ; 진행 중 항상 위로 두고 있는 강의 창
global topOwned := false           ; 그 항상 위를 이 프로그램이 켰는지 (원래 항상 위였으면 끝날 때 풀지 않는다)
global chkAutoSession              ; 본체 창의 '다음 차시 자동' (설정 창의 chkNextSession 과 같이 움직임)
global chkNextSession
global staticSince  := 0           ;   그 시각
global chkQuizForce
global forceTried   := Map()       ; 차례로 누르기: 이 화면에서 이미 누른 것
global forceCount   := 0
global forceTick    := 0
global forceLastKey := ""
global forceSig     := ""
global forceGaveUp  := false
global forceActive  := false
global lastPressError := ""        ; 마지막으로 못 누른 까닭

BuildGui()
BuildSettingsGui()
LoadSettings()
ApplyHotkeys()
LoadProfileNames()
RefreshWindowList()
BuildOverlay()
OnMessage(0x201, OverlayMouseDown)          ; 오버레이를 누르거나 끌 때
ApplyTickInterval()
SetTimer(OverlayGuess, 1000)                ; 오버레이 시계만 혼자 흐르게 (화면은 안 읽음)
Tick()
SetTimer(() => CheckUpdate(true), -4000)   ; 켜고 조금 뒤 GitHub 에 새 버전이 있는지 조용히 확인
OnExit((*) => CleanUpOnExit())
OnError(LogError)                           ; 오류가 나면 코드로넘기기_기록.txt 에 남긴다

; --------------------------------------------------
; 화면
; --------------------------------------------------
; 화면에서 쓰는 색
UiColor(name)
{
    static c := Map(
        "바탕", "FFFFFF",
        "카드", "F3F4F6",
        "선",   "E5E7EB",
        "글자", "111827",
        "흐림", "6B7280",
        "강조", "2563EB"
    )

    return c[name]
}

UiBody(g)
{
    g.SetFont("s10 norm c" UiColor("글자"), "맑은 고딕")
}

; 체크박스·라디오용 글꼴. 글자색을 주면 윈도우 테마가 꺼져 옛날 모양이 되므로 색은 기본값
UiChoice(g)
{
    g.SetFont("s10 norm cDefault", "맑은 고딕")
}

; 입력칸 옆의 흐린 이름표
UiLabel(g, opts, text)
{
    g.SetFont("s10 norm c" UiColor("흐림"), "맑은 고딕")
    ctrl := g.Add("Text", opts, text)
    UiBody(g)

    return ctrl
}

; 작은 설명 글
UiNote(g, opts, text)
{
    g.SetFont("s9 norm c" UiColor("흐림"), "맑은 고딕")
    ctrl := g.Add("Text", opts, text)
    UiBody(g)

    return ctrl
}

; 구역 제목 + 가는 선
UiSection(g, title, width, x := "xm", y := "y+22")
{
    g.SetFont("s10 bold c" UiColor("강조"), "맑은 고딕")
    g.Add("Text", x " " y " w" width, title)
    g.Add("Text", x " y+5 w" width " h1 Background" UiColor("선"))
    UiBody(g)
}

; 기호 하나짜리 작은 버튼 (↻ 등)
UiIconButton(g, opts, glyph, callback)
{
    g.SetFont("s11 norm c" UiColor("글자"), "Segoe UI Symbol")
    b := g.Add("Button", opts, glyph)
    b.OnEvent("Click", callback)
    UiBody(g)

    return b
}

; --------------------------------------------------
; 본체 창 : 사이트 / 강의 창 / 상태 / 시작 만 둔다
; 세부 설정은 모두 [설정] 창에
; --------------------------------------------------
BuildGui()
{
    global gui1, ddSite, ddWindow, ddList, txtWindow, txtState, txtCount, btnStart, btnAside, txtHotkeys, chkAutoSession

    cw := 520

    gui1 := Gui("", "코드로 넘기기")
    gui1.BackColor := UiColor("바탕")
    gui1.MarginX := 24
    gui1.MarginY := 20

    ; 머리글
    gui1.SetFont("s15 bold c" UiColor("글자"), "맑은 고딕")
    gui1.Add("Text", "xm w" cw, "코드로 넘기기")
    UiNote(gui1, "xm y+2 w" cw, "강의 화면의 버튼을 코드로 눌러, 다른 일을 하는 동안 알아서 넘깁니다.   v" appVersion)

    ; 사이트 / 강의 창
    UiLabel(gui1, "xm y+22 w78 h30 +0x200", "사이트")
    ddSite := gui1.Add("DropDownList", "x+8 yp+1 w384", [])
    ddSite.OnEvent("Change", (*) => UseProfile(ddSite.Text))
    UiIconButton(gui1, "x+6 yp-1 w44 h30", "↻", (*) => LoadProfileNames())

    UiLabel(gui1, "xm y+12 w78 h30 +0x200", "강의 창")
    ddWindow := gui1.Add("DropDownList", "x+8 yp+1 w384", [])
    ddWindow.OnEvent("Change", (*) => PickWindow())
    UiIconButton(gui1, "x+6 yp-1 w44 h30", "↻", (*) => RefreshWindowList())

    ; 차시 목록(또는 학습현황)이 있는 창. 자동으로 못 찾는 사이트는 여기서 직접 고른다
    UiLabel(gui1, "xm y+12 w78 h30 +0x200", "차시 목록")
    ddList := gui1.Add("DropDownList", "x+8 yp+1 w384", [])
    ddList.OnEvent("Change", (*) => PickListWindow())
    UiIconButton(gui1, "x+6 yp-1 w44 h30", "↻", (*) => RefreshWindowList())

    txtWindow := UiNote(gui1, "xm+86 y+6 w" (cw - 86), "찾는 중...")

    ; 차시 자동 넘기기 (설정 창의 같은 칸과 함께 움직인다)
    UiChoice(gui1)
    chkAutoSession := gui1.Add("CheckBox", "xm+86 y+10 w" (cw - 86), "차시가 끝나면 다음 차시로  (다 들은 차시는 건너뜀)")
    chkAutoSession.OnEvent("Click", (*) => SyncAutoSession(chkAutoSession))
    UiBody(gui1)

    ; 상태 카드
    UiSection(gui1, "상태", cw)
    txtState := gui1.Add("Edit", "xm y+10 w" cw " r9 ReadOnly -E0x200 -VScroll Background" UiColor("카드"), "")
    SendMessage(0xD3, 3, (16 << 16) | 16, txtState)          ; 안쪽 여백 (왼쪽·오른쪽)

    ; 동작 버튼
    gui1.SetFont("s10 bold c" UiColor("글자"), "맑은 고딕")
    btnStart := gui1.Add("Button", "xm y+20 w190 h44 Default", "▶  시작    F9")
    btnStart.OnEvent("Click", (*) => Toggle())
    UiBody(gui1)
    btnAside := gui1.Add("Button", "x+10 yp w200 h44", "창 밀어두기    F11")
    btnAside.OnEvent("Click", (*) => ToggleAside())
    gui1.Add("Button", "x+10 yp w110 h44", "설정").OnEvent("Click", (*) => ShowSettings())

    ; 바닥글
    txtCount := UiNote(gui1, "xm y+16 w200", "넘김 0회")
    txtHotkeys := UiNote(gui1, "x+0 yp w" (cw - 200) " Right", "")

    gui1.OnEvent("Close", (*) => ExitApp())
    gui1.Show("AutoSize")
}

; --------------------------------------------------
; 설정 창 (처음부터 만들어 두고 숨겨 둔다)
; 바꾼 내용은 바로 적용되고, 닫을 때 저장된다
; --------------------------------------------------
BuildSettingsGui()
{
    global gui1, gui3
    global chkNext, chkPlay, chkQuizBeep, chkEndClose, chkTelegram, chkAwake, chkNoFront, chkOnTop
    global editToken, editChat, rdOvlBig, rdOvlSmall, rdOvlHidden, editAsidePx, ddTarget
    global hkCtlStart, hkCtlAside, hkCtlDump, chkQuizAuto, editQuizWait, chkQuizForce, ddAsideSide, chkNextSession
    global editTickSec, editLastSession, txtSessionInfo

    colW := 430           ; 한 칸 너비
    gap := 44             ; 두 칸 사이
    L := 26               ; 왼쪽 칸 x (= 바깥 여백)
    R := L + colW + gap   ; 오른쪽 칸 x

    gui3 := Gui("+Owner" gui1.Hwnd " -MinimizeBox", "설정")
    gui3.BackColor := UiColor("바탕")
    gui3.MarginX := L
    gui3.MarginY := 20
    gui3.OnEvent("Close", (*) => CloseSettings())
    gui3.OnEvent("Escape", (*) => CloseSettings())

    gui3.SetFont("s15 bold c" UiColor("글자"), "맑은 고딕")
    gui3.Add("Text", "xm w" (colW * 2 + gap), "설정")
    sub := UiNote(gui3, "xm y+2 w" (colW * 2 + gap), "바꾼 내용은 바로 적용되고, 닫을 때 저장됩니다.")
    sub.GetPos(, &sy, , &sh)
    top := sy + sh + 20

    ; ================= 왼쪽 칸 =================
    UiSection(gui3, "자동 동작", colW, "x" L, "y" top)
    UiChoice(gui3)
    chkNext     := gui3.Add("CheckBox", "x" L " y+12 w" colW " Checked", "영상이 끝나면 다음을 누른다")
    chkPlay     := gui3.Add("CheckBox", "x" L " y+9 w" colW " Checked", "멈춰 있으면 다시 재생을 누른다")
    chkEndClose := gui3.Add("CheckBox", "x" L " y+9 w" colW, "강의가 끝나면 닫기를 누른다")
    chkQuizAuto := gui3.Add("CheckBox", "x" L " y+9 w" colW, "퀴즈는 아무 답이나 누르고 넘어간다  (O/X 등)")
    UiLabel(gui3, "x" (L + 26) " y+8 w180 h28 +0x200", "답을 누르고 넘기기까지")
    editQuizWait := gui3.Add("Edit", "x+6 yp+1 w50 Number Center", "3")
    UiLabel(gui3, "x+8 yp-1 w40 h28 +0x200", "초")
    UiChoice(gui3)
    chkQuizForce := gui3.Add("CheckBox", "x" (L + 26) " y+6 w" (colW - 26), "안 되면 누를 수 있는 것을 차례로 눌러서라도 넘긴다")

    UiSection(gui3, "알림", colW, "x" L)
    UiChoice(gui3)
    chkQuizBeep := gui3.Add("CheckBox", "x" L " y+12 w" colW " Checked", "문제풀이가 뜨면 소리로 알린다")
    chkTelegram := gui3.Add("CheckBox", "x" L " y+9 w" colW " Checked", "문제풀이·완료·멈춤을 텔레그램으로 알린다")

    UiLabel(gui3, "x" (L + 26) " y+12 w70 h28 +0x200", "봇 토큰")
    editToken := gui3.Add("Edit", "x+6 yp+1 w" (colW - 102) " Password", "")
    UiLabel(gui3, "x" (L + 26) " y+9 w70 h28 +0x200", "채팅 ID")
    editChat := gui3.Add("Edit", "x+6 yp+1 w150", "")
    gui3.Add("Button", "x+8 yp-2 w" (colW - 26 - 70 - 6 - 150 - 8) " h30", "시험 보내기").OnEvent("Click", (*) => TelegramTest())
    UiNote(gui3, "x" (L + 26) " y+6 w" (colW - 26), "봇 토큰과 채팅 ID 는 이 PC 의 설정 파일에만 저장됩니다.")

    UiSection(gui3, "시스템", colW, "x" L)
    UiChoice(gui3)
    chkAwake := gui3.Add("CheckBox", "x" L " y+12 w" colW " Checked", "진행 중 잠들지 않게 한다  (화면은 꺼져도 됨)")
    UiLabel(gui3, "x" (L + 26) " y+10 w150 h28 +0x200", "화면 읽는 주기")
    editTickSec := gui3.Add("Edit", "x+6 yp+1 w60 Number Center", "5")
    editTickSec.OnEvent("Change", (*) => ApplyTickInterval())
    UiLabel(gui3, "x+8 yp-1 w40 h28 +0x200", "초")
    UiNote(gui3, "x" (L + 26) " y+4 w" (colW - 26), "느리게 둘수록 가볍습니다. 영상이 도는 중에는 끝날 때까지 알아서 더 쉽니다.")
    chkNoFront := gui3.Add("CheckBox", "x" L " y+9 w" colW " Checked", "브라우저 창을 절대 앞으로 가져오지 않는다")
    UiNote(gui3, "x" (L + 26) " y+3 w" (colW - 26), "다른 작업 중에 강의 창이 앞으로 튀어나오지 않습니다.")
    UiChoice(gui3)
    chkOnTop := gui3.Add("CheckBox", "x" L " y+9 w" colW " Checked", "진행 중에는 강의 창을 항상 위에 둔다")
    chkOnTop.OnEvent("Click", (*) => (SaveSettings(), chkOnTop.Value ? Tick() : ReleaseOnTop()))
    leftLast := UiNote(gui3, "x" (L + 26) " y+3 w" (colW - 26), "다른 창을 전체 화면으로 써도 강의가 멈추지 않습니다."
        . "`n강의 창은 작게 두거나 F11 로 밀어 두세요. (정지·종료하면 풀립니다)")

    ; ================= 오른쪽 칸 =================
    UiSection(gui3, "작업 중 화면", colW, "x" R, "y" top)
    UiLabel(gui3, "x" R " y+12 w70 h30 +0x200", "오버레이")
    UiChoice(gui3)
    rdOvlBig    := gui3.Add("Radio", "x+4 yp w64 h30 Checked Group", "크게")
    rdOvlSmall  := gui3.Add("Radio", "x+2 yp w112 h30", "작게 (두 줄)")
    rdOvlHidden := gui3.Add("Radio", "x+2 yp w64 h30", "숨김")
    rdOvlBig.OnEvent("Click", (*) => SetOverlayMode("크게"))
    rdOvlSmall.OnEvent("Click", (*) => SetOverlayMode("작게"))
    rdOvlHidden.OnEvent("Click", (*) => SetOverlayMode("숨김"))
    UiBody(gui3)
    gui3.Add("Button", "x+4 yp w" (colW - 70 - 4 - 64 - 2 - 112 - 2 - 64 - 4) " h30", "자리 초기화").OnEvent("Click", (*) => ResetOverlayPos())
    UiNote(gui3, "x" (R + 74) " y+4 w" (colW - 74), "끌면 옮겨지고, 누르면 본체 창이 뜹니다.")

    UiLabel(gui3, "x" R " y+12 w150 h28 +0x200", "밀어둘 때 남길 폭")
    editAsidePx := gui3.Add("Edit", "x+6 yp+1 w60 Number Center", "6")
    UiLabel(gui3, "x+8 yp-1 w40 h28 +0x200", "픽셀")
    UiLabel(gui3, "x+10 yp w40 h28 +0x200", "쪽")
    ddAsideSide := gui3.Add("DropDownList", "x+6 yp+1 w100 Choose1", ["자동", "오른쪽", "왼쪽"])
    ddAsideSide.OnEvent("Change", (*) => SaveSettings())

    UiSection(gui3, "단축키", colW, "x" R)
    UiLabel(gui3, "x" R " y+12 w160 h30 +0x200", "시작 / 정지")
    hkCtlStart := gui3.Add("Hotkey", "x+6 yp+1 w150", "")
    gui3.Add("Button", "x+8 yp-1 w" (colW - 160 - 6 - 150 - 8) " h30", "기본값").OnEvent("Click", (*) => ResetHotkeyFields())
    UiLabel(gui3, "x" R " y+8 w160 h30 +0x200", "창 밀어두기 / 되돌리기")
    hkCtlAside := gui3.Add("Hotkey", "x+6 yp+1 w150", "")
    UiLabel(gui3, "x" R " y+8 w160 h30 +0x200", "코드 목록 뽑기")
    hkCtlDump := gui3.Add("Hotkey", "x+6 yp+1 w150", "")
    UiNote(gui3, "x" R " y+6 w" colW, "칸을 누르고 원하는 키를 누르세요 (예: Ctrl+F11). 비워 두면 단축키 없음."
        . "`n설정 창이 열려 있는 동안에는 단축키가 잠시 꺼집니다.")

    UiSection(gui3, "사이트 프로필", colW, "x" R)
    bw := (colW - 16) // 3
    gui3.Add("Button", "x" R " y+12 w" bw " h34", "프로필 편집").OnEvent("Click", (*) => EditProfile())
    gui3.Add("Button", "x+8 yp w" bw " h34", "폴더 열기").OnEvent("Click", (*) => OpenProfileDir())
    gui3.Add("Button", "x+8 yp w" bw " h34", "코드 목록 뽑기").OnEvent("Click", (*) => DumpCodes())

    UiLabel(gui3, "x" R " y+12 w70 h30 +0x200", "눌러보기")
    ddTarget := gui3.Add("DropDownList", "x+6 yp+1 w" (colW - 70 - 6 - 8 - 110), [])
    gui3.Add("Button", "x+8 yp-1 w110 h30", "누르기").OnEvent("Click", (*) => PressOnce(ddTarget.Text))

    UiSection(gui3, "차시", colW, "x" R)
    UiChoice(gui3)
    chkNextSession := gui3.Add("CheckBox", "x" R " y+12 w" colW, "차시가 끝나면 다음 차시로 넘어간다")
    chkNextSession.OnEvent("Click", (*) => SyncAutoSession(chkNextSession))
    UiLabel(gui3, "x" (R + 26) " y+8 w60 h28 +0x200", "어디까지")
    editLastSession := gui3.Add("Edit", "x+6 yp+1 w60 Number Center", "")
    UiLabel(gui3, "x+8 yp-1 w170 h28 +0x200", "차시까지 (비우면 끝까지)")
    UiBody(gui3)
    gui3.Add("Button", "x+8 yp-1 w92 h30", "목록 읽기").OnEvent("Click", (*) => ScanSessions(true))
    rightLast := gui3.Add("Edit", "x" R " y+10 w" colW " r6 ReadOnly -E0x200 Background" UiColor("카드"),
        "차시 목록을 아직 읽지 않았습니다.  [목록 읽기] 를 누르면 전체 차시와 들은 차시를 읽어 옵니다.")
    txtSessionInfo := rightLast
    SendMessage(0xD3, 3, (12 << 16) | 12, txtSessionInfo)

    ; ================= 닫기 (두 칸 중 긴 쪽 아래) =================
    leftLast.GetPos(, &ly, , &lh)
    rightLast.GetPos(, &ry, , &rh)
    bottom := Max(ly + lh, ry + rh)

    gui3.Add("Text", "x" L " y" (bottom + 24) " w" (colW * 2 + gap) " h1 Background" UiColor("선"))
    gui3.Add("Button", "x" (R + colW - 120) " y+14 w120 h38 Default", "닫기").OnEvent("Click", (*) => CloseSettings())
    gui3.Add("Button", "x" L " yp w150 h38", "업데이트 확인").OnEvent("Click", (*) => CheckUpdate(false))
    UiNote(gui3, "x+12 yp+10 w200", "지금 버전  v" appVersion)
}

ShowSettings()
{
    global gui3, hkStart, hkAside, hkDump, hkCtlStart, hkCtlAside, hkCtlDump

    hkCtlStart.Value := hkStart
    hkCtlAside.Value := hkAside
    hkCtlDump.Value := hkDump

    ; 단축키 칸에서 키를 눌러 정할 수 있도록, 설정 창이 열려 있는 동안 단축키를 끈다
    Suspend(true)
    gui3.Show("AutoSize")
}

CloseSettings()
{
    global gui3, hkStart, hkAside, hkDump, hkCtlStart, hkCtlAside, hkCtlDump

    s := Trim(hkCtlStart.Value)
    a := Trim(hkCtlAside.Value)
    d := Trim(hkCtlDump.Value)

    if ((s != "" && (s = a || s = d)) || (a != "" && a = d)) {
        MsgBox("같은 단축키를 두 가지 동작에 쓸 수 없습니다.", "단축키", "0x40030 Owner" gui3.Hwnd)
        return
    }

    old := [hkStart, hkAside, hkDump]
    hkStart := s, hkAside := a, hkDump := d

    Suspend(false)
    failed := ApplyHotkeys()

    if failed.Length {
        ; 쓸 수 없는 키면 예전 것으로 되돌리고 창을 닫지 않는다
        hkStart := old[1], hkAside := old[2], hkDump := old[3]
        ApplyHotkeys()
        hkCtlStart.Value := hkStart, hkCtlAside.Value := hkAside, hkCtlDump.Value := hkDump
        Suspend(true)
        MsgBox("이 단축키는 쓸 수 없습니다: " Join(failed, ", ") "`n다른 키를 골라 주세요.", "단축키", "0x40030 Owner" gui3.Hwnd)
        return
    }

    SaveSettings()
    gui3.Hide()
}

; --------------------------------------------------
; 단축키 (설정 창에서 바꿀 수 있음)
; --------------------------------------------------
ResetHotkeyFields()
{
    global hkCtlStart, hkCtlAside, hkCtlDump

    hkCtlStart.Value := "F9"
    hkCtlAside.Value := "F11"
    hkCtlDump.Value := "F10"
}

; 예전에 켠 단축키는 끄고, 지금 값으로 다시 켠다. 켜지 못한 키 목록을 돌려준다
ApplyHotkeys()
{
    global hkStart, hkAside, hkDump

    static active := []

    for key in active
        try Hotkey(key, "Off")

    active := []
    failed := []

    for pair in [[hkStart, (*) => Toggle()], [hkAside, (*) => ToggleAside()], [hkDump, (*) => DumpCodes()]] {
        if (pair[1] = "")
            continue

        try {
            Hotkey(pair[1], pair[2], "On")
            active.Push(pair[1])
        } catch {
            failed.Push(HotkeyText(pair[1]))
        }
    }

    RefreshHotkeyLabels()

    return failed
}

; "^+F11" → "Ctrl+Shift+F11"
HotkeyText(hk)
{
    if (hk = "")
        return ""

    mods := ""
    i := 1

    while (i < StrLen(hk) && InStr("^+!#", SubStr(hk, i, 1))) {
        c := SubStr(hk, i, 1)
        mods .= (c = "^") ? "Ctrl+" : (c = "+") ? "Shift+" : (c = "!") ? "Alt+" : "Win+"
        i += 1
    }

    key := SubStr(hk, i)

    return mods StrUpper(SubStr(key, 1, 1)) SubStr(key, 2)
}

KeyHint(hk)
{
    return (hk != "") ? "    " HotkeyText(hk) : ""
}

; 버튼과 바닥글에 지금 단축키를 보여 준다
RefreshHotkeyLabels()
{
    global btnStart, btnAside, txtHotkeys, running, asideSaved, hkStart, hkAside

    if IsObject(btnStart)
        btnStart.Text := (running ? "■  정지" : "▶  시작") KeyHint(hkStart)

    if IsObject(btnAside)
        btnAside.Text := (IsObject(asideSaved) ? "창 되돌리기" : "창 밀어두기") KeyHint(hkAside)

    if IsObject(txtHotkeys) {
        parts := []

        if (hkStart != "")
            parts.Push(HotkeyText(hkStart) " 시작·정지")

        if (hkAside != "")
            parts.Push(HotkeyText(hkAside) " 밀어두기")

        parts.Push("ESC 정지")
        txtHotkeys.Text := Join(parts, "    ")
    }
}



; 본체 창과 설정 창의 '다음 차시로' 칸을 같게 맞추고 저장한다
SyncAutoSession(from)
{
    global chkAutoSession, chkNextSession, running

    v := from.Value
    chkAutoSession.Value := v
    chkNextSession.Value := v
    SaveSettings()

    ; 진행 중에 켰으면 다 들은 차시를 알 수 있게 목록을 한 번 읽어 둔다
    if (v && running && P("차시", "차시링크") != "")
        ScanSessions()

    Tick()
}

SetState(s)
{
    global txtState

    if (txtState.Value != s)
        txtState.Value := s
}

; --------------------------------------------------
; 프로필
; --------------------------------------------------
LoadProfileNames()
{
    global profileDir, profileList, ddSite, profName

    profileList := []

    if !DirExist(profileDir)
        try DirCreate(profileDir)

    Loop Files profileDir "\*.ini"
        profileList.Push(RegExReplace(A_LoopFileName, "\.ini$", ""))

    ddSite.Delete()

    if !profileList.Length {
        ddSite.Add(["(프로필 파일이 없습니다)"])
        ddSite.Choose(1)
        SetState("'" profileDir "' 안에 프로필 파일(.ini)이 없습니다.")
        return
    }

    ddSite.Add(profileList)

    pick := (profName != "" && HasValue(profileList, profName)) ? profName : AutoPickProfile()
    ddSite.Choose(pick)
    UseProfile(pick)
}

HasValue(arr, v)
{
    for x in arr
        if (x = v)
            return true

    return false
}

; 지금 열려 있는 브라우저 창 제목과 맞는 프로필을 고른다
AutoPickProfile()
{
    global profileList, profileDir

    for name in profileList {
        data := ReadProfileFile(profileDir "\" name ".ini")
        key := GetVal(data, "사이트", "창제목")

        if (key != "" && FindLectureWindow(key))
            return name
    }

    return profileList[1]
}

UseProfile(name)
{
    global prof, profName, profileDir, ddTarget, lectureHwnd

    if (name = "" || !FileExist(profileDir "\" name ".ini"))
        return

    prof := ReadProfileFile(profileDir "\" name ".ini")
    profName := name
    lectureHwnd := 0

    ddTarget.Delete()
    names := []

    if prof.Has("누를것")
        for k, v in prof["누를것"]
            if (Trim(v) != "")
                names.Push(k)

    if names.Length {
        ddTarget.Add(names)
        ddTarget.Choose(1)
    }

    SaveSettings()
    Tick()
}

ReadProfileFile(path)
{
    data := Map()
    section := ""
    text := ""

    try text := FileRead(path, "UTF-8")

    for line in StrSplit(text, "`n", "`r") {
        line := Trim(line)

        if (line = "" || SubStr(line, 1, 1) = ";")
            continue

        if (SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]") {
            section := Trim(SubStr(line, 2, StrLen(line) - 2))

            if !data.Has(section)
                data[section] := Map()

            continue
        }

        p := InStr(line, "=")

        if (!p || section = "")
            continue

        data[section][Trim(SubStr(line, 1, p - 1))] := Trim(SubStr(line, p + 1))
    }

    return data
}

GetVal(data, section, key, def := "")
{
    if (IsObject(data) && data.Has(section) && data[section].Has(key))
        return data[section][key]

    return def
}

P(section, key, def := "")
{
    global prof

    return GetVal(prof, section, key, def)
}

OpenProfileDir()
{
    global profileDir

    if !DirExist(profileDir)
        try DirCreate(profileDir)

    Run 'explorer.exe "' profileDir '"'
}

; --------------------------------------------------
; 설정 기억
; --------------------------------------------------


LoadSettings()
{
    global settingFile, profName, settingsLoaded, tgToken, tgChat, ovlMode, hkStart, hkAside, hkDump
    global chkNext, chkPlay, chkQuizBeep, chkEndClose, chkTelegram, chkAwake, chkNoFront, chkOnTop
    global editToken, editChat, editAsidePx, ddAsideSide, rdOvlBig, rdOvlSmall, rdOvlHidden, chkQuizAuto, editQuizWait, chkQuizForce, chkNextSession
    global editTickSec, editLastSession, chkAutoSession
    global asideSideSet

    px := 6
    quizWait := 3
    tickSec := 5
    lastSession := ""

    if FileExist(settingFile) {
        try {
            profName := IniRead(settingFile, "기본", "사이트", "")
            chkNext.Value := IniRead(settingFile, "기본", "영상끝나면다음", 1)
            chkPlay.Value := IniRead(settingFile, "기본", "멈추면재생", 1)
            chkQuizBeep.Value := IniRead(settingFile, "기본", "문제풀이소리", 1)
            chkEndClose.Value := IniRead(settingFile, "기본", "끝나면닫기", 0)
            chkQuizAuto.Value := IniRead(settingFile, "기본", "퀴즈자동", 0)
            chkQuizForce.Value := IniRead(settingFile, "기본", "퀴즈강제", 0)
            chkNextSession.Value := IniRead(settingFile, "기본", "차시자동", 0)
            quizWait := IniRead(settingFile, "기본", "퀴즈대기초", 3)
            chkTelegram.Value := IniRead(settingFile, "기본", "텔레그램알림", 1)
            chkAwake.Value := IniRead(settingFile, "기본", "잠들지않기", 1)
            chkNoFront.Value := IniRead(settingFile, "기본", "창앞으로안가져오기", 1)
            chkOnTop.Value := IniRead(settingFile, "기본", "강의창항상위", 1)
            ovlMode := IniRead(settingFile, "기본", "오버레이", "크게")
            px := IniRead(settingFile, "기본", "밀어둘때보일픽셀", 6)
            asideSideSet := IniRead(settingFile, "기본", "밀어둘쪽", "자동")
            tickSec := IniRead(settingFile, "기본", "화면읽는주기초", 5)
            lastSession := IniRead(settingFile, "기본", "마지막차시", "")
            hkStart := IniRead(settingFile, "단축키", "시작정지", "F9")
            hkAside := IniRead(settingFile, "단축키", "밀어두기", "F11")
            hkDump := IniRead(settingFile, "단축키", "코드목록", "F10")
            tgToken := IniRead(settingFile, "알림", "텔레그램토큰", "")
            tgChat := IniRead(settingFile, "알림", "텔레그램채팅ID", "")
        }
    }

    ; 예전 설정값도 받아 준다 (1 → 크게, 0 → 숨김, 보통 → 크게)
    if (ovlMode = "1" || ovlMode = "보통")
        ovlMode := "크게"
    else if (ovlMode = "0")
        ovlMode := "숨김"
    else if (ovlMode != "작게" && ovlMode != "숨김")
        ovlMode := "크게"

    ; 읽은 값을 설정 창에 채운다
    editToken.Value := tgToken
    editChat.Value := tgChat
    editAsidePx.Value := IsInteger(px) ? px : 6
    editQuizWait.Value := IsInteger(quizWait) ? quizWait : 3
    editTickSec.Value := IsInteger(tickSec) ? tickSec : 5
    editLastSession.Value := IsInteger(lastSession) ? lastSession : ""
    ApplyTickInterval()

    if (asideSideSet != "오른쪽" && asideSideSet != "왼쪽")
        asideSideSet := "자동"

    ddAsideSide.Choose(asideSideSet)
    rdOvlBig.Value := (ovlMode = "크게")
    rdOvlSmall.Value := (ovlMode = "작게")
    rdOvlHidden.Value := (ovlMode = "숨김")

    chkAutoSession.Value := chkNextSession.Value

    ; 이제부터 저장해도 된다 (읽기 전에 저장하면 기본값으로 덮어써 버린다)
    settingsLoaded := true
    SaveSettings()
}

SaveSettings()
{
    global settingFile, profName, settingsLoaded, tgToken, tgChat, ovlMode, hkStart, hkAside, hkDump
    global chkNext, chkPlay, chkQuizBeep, chkEndClose, chkTelegram, chkAwake, chkNoFront, chkOnTop
    global editToken, editChat, chkQuizAuto, chkQuizForce, chkNextSession

    if !settingsLoaded
        return

    if IsObject(editToken) {
        tgToken := Trim(editToken.Value)
        tgChat := Trim(editChat.Value)
    }

    try {
        IniWrite(profName, settingFile, "기본", "사이트")
        IniWrite(chkNext.Value, settingFile, "기본", "영상끝나면다음")
        IniWrite(chkPlay.Value, settingFile, "기본", "멈추면재생")
        IniWrite(chkQuizBeep.Value, settingFile, "기본", "문제풀이소리")
        IniWrite(chkEndClose.Value, settingFile, "기본", "끝나면닫기")
        IniWrite(chkQuizAuto.Value, settingFile, "기본", "퀴즈자동")
        IniWrite(chkQuizForce.Value, settingFile, "기본", "퀴즈강제")
        IniWrite(chkNextSession.Value, settingFile, "기본", "차시자동")
        IniWrite(QuizWaitSec(), settingFile, "기본", "퀴즈대기초")
        IniWrite(chkTelegram.Value, settingFile, "기본", "텔레그램알림")
        IniWrite(chkAwake.Value, settingFile, "기본", "잠들지않기")
        IniWrite(chkNoFront.Value, settingFile, "기본", "창앞으로안가져오기")
        IniWrite(chkOnTop.Value, settingFile, "기본", "강의창항상위")
        IniWrite(ovlMode, settingFile, "기본", "오버레이")
        IniWrite(AsidePx(), settingFile, "기본", "밀어둘때보일픽셀")
        IniWrite(AsideSide(), settingFile, "기본", "밀어둘쪽")
        IniWrite(TickSec(), settingFile, "기본", "화면읽는주기초")
        IniWrite(LastSessionLimit() ? LastSessionLimit() : "", settingFile, "기본", "마지막차시")
        IniWrite(hkStart, settingFile, "단축키", "시작정지")
        IniWrite(hkAside, settingFile, "단축키", "밀어두기")
        IniWrite(hkDump, settingFile, "단축키", "코드목록")
        IniWrite(tgToken, settingFile, "알림", "텔레그램토큰")
        IniWrite(tgChat, settingFile, "알림", "텔레그램채팅ID")
    }
}

; --------------------------------------------------
; 알림 (소리 + 텔레그램)
; --------------------------------------------------
Notify(msg, withSound := true)
{
    global chkQuizBeep, chkTelegram, profName

    if (withSound && chkQuizBeep.Value)
        Beep3()

    if chkTelegram.Value
        SendTelegram("[" profName "] " msg)
}

SendTelegram(msg)
{
    global tgToken, tgChat

    token := Trim(tgToken)
    chatId := Trim(tgChat)

    if (token = "" || chatId = "")
        return "봇 토큰 또는 채팅 ID가 비어 있습니다."

    url := "https://api.telegram.org/bot" token "/sendMessage"
    body := "chat_id=" UriEncode(chatId) "&text=" UriEncode(msg)

    try {
        http := ComObject("WinHttp.WinHttpRequest.5.1")
        http.SetTimeouts(5000, 5000, 5000, 15000)
        http.Open("POST", url, true)
        http.SetRequestHeader("Content-Type", "application/x-www-form-urlencoded; charset=utf-8")
        http.Send(body)
        http.WaitForResponse(15)

        if (http.Status = 200)
            return ""

        return "HTTP " http.Status " / " SubStr(http.ResponseText, 1, 150)
    } catch as e {
        return e.Message
    }
}

UriEncode(str)
{
    static safe := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_.~"

    size := StrPut(str, "UTF-8")
    buf := Buffer(size, 0)
    StrPut(str, buf, "UTF-8")

    out := ""

    Loop size - 1 {
        b := NumGet(buf, A_Index - 1, "UChar")

        if (b < 128 && InStr(safe, Chr(b), true))
            out .= Chr(b)
        else
            out .= Format("%{:02X}", b)
    }

    return out
}



TelegramTest()
{
    global gui3

    SaveSettings()

    err := SendTelegram("[시험] 코드로 넘기기 알림이 정상으로 연결되었습니다.")

    if (err = "")
        MsgBox("텔레그램으로 시험 메시지를 보냈습니다.", "보냈습니다", "0x40040 Owner" gui3.Hwnd)
    else
        MsgBox("보내지 못했습니다.`n`n" err, "보내지 못함", "0x40030 Owner" gui3.Hwnd)
}

; --------------------------------------------------
; 오류 기록
;   오류 창은 닫으면 내용이 사라지므로, 오류가 나면 코드로넘기기_기록.txt 에 남긴다.
;   (시각, 버전, 오류, 줄, 호출 경로. GitHub 에는 올리지 않음)
;   다른 일을 하는 동안 오류 창이 떠서 멈춰 있지 않도록, 창은 띄우지 않고
;   같은 오류는 한 번만 소리·텔레그램으로 알린다. 화면 읽기는 다음 차례에 그대로 이어진다.
; --------------------------------------------------
LogError(e, mode)
{
    global appVersion

    static told := Map()

    line := e.HasProp("Line") ? e.Line : "?"
    extra := (e.HasProp("Extra") && e.Extra != "") ? "`n자세히: " e.Extra : ""

    try FileAppend("===== " FormatTime(, "yyyy-MM-dd HH:mm:ss") "   v" appVersion "`n"
        . Type(e) ": " e.Message extra "`n"
        . "줄 " line (e.HasProp("What") && e.What != "" ? "  (" e.What ")" : "") "`n"
        . (e.HasProp("Stack") ? e.Stack : "") "`n", A_ScriptDir "\코드로넘기기_기록.txt", "UTF-8")

    key := e.Message "@" line

    if !told.Has(key) {
        told[key] := true
        try Notify("프로그램 오류가 나서 기록했습니다 (코드로넘기기_기록.txt). " e.Message " / 줄 " line)
    }

    return 1          ; 오류 창은 띄우지 않는다
}

; --------------------------------------------------
; 업데이트 (GitHub)
;   이 폴더가 GitHub 에서 받은 git 저장소이면, 켤 때 새 버전이 있는지 조용히 확인하고 묻는다.
;   받을 때는 git pull --ff-only 로만 받는다.
;     이 PC 에서 고친 파일(프로필 등)과 겹치면 덮어쓰지 않고, 실패한 까닭을 그대로 보여 준다.
;   인터넷이 막혔거나 git 이 없으면 켤 때는 아무 말 없이 넘어간다.
;     (확인 실패를 '최신' 이라고 하지 않는다. [업데이트 확인] 을 누르면 까닭을 보여 준다)
;   exe 로 만든 판은 git 저장소가 아니므로 쓸 수 없다.
;   설정(코드로넘기기.ini)은 저장소에 올리지 않으므로 받아도 그대로 남는다.
; --------------------------------------------------
Git(args, &out)
{
    tmp := A_Temp "\코드로넘기기_git.txt"
    try FileDelete(tmp)

    ; 로그인 창을 띄우지 않고, 느린 연결에서 하염없이 기다리지 않게
    EnvSet("GIT_TERMINAL_PROMPT", "0")
    EnvSet("GIT_HTTP_LOW_SPEED_LIMIT", "1000")
    EnvSet("GIT_HTTP_LOW_SPEED_TIME", "8")

    code := -1
    try code := RunWait(A_ComSpec ' /c git ' args ' > "' tmp '" 2>&1', A_ScriptDir, "Hide")

    out := ""
    try out := Trim(FileRead(tmp, "UTF-8"), " `t`r`n")
    try FileDelete(tmp)

    return code
}

CheckUpdate(quiet := true)
{
    global gui1, gui3, running, appVersion

    owner := (IsObject(gui3) && DllCall("IsWindowVisible", "ptr", gui3.Hwnd)) ? gui3.Hwnd : gui1.Hwnd
    say := (msg, opt := "0x40") => quiet ? "" : MsgBox(msg, "업데이트", opt " Owner" owner)

    if (A_IsCompiled || !DirExist(A_ScriptDir "\.git")) {
        say("이 폴더는 GitHub 에서 받은 저장소가 아니라서 업데이트를 확인할 수 없습니다."
            . "`n(exe 로 만든 판이거나, 파일만 복사해 온 경우)", "0x30")
        return
    }

    if (Git("fetch --quiet origin", &out) != 0) {
        say("새 버전을 확인하지 못했습니다. (인터넷이 막혔거나 git 이 없을 수 있습니다)`n`n" SubStr(out, 1, 600), "0x30")
        return
    }

    n := ""

    if (Git("rev-list --count HEAD..@{u}", &n) != 0 || !IsInteger(n)) {
        say("새 버전을 확인하지 못했습니다.`n`n" SubStr(n, 1, 600), "0x30")
        return
    }

    if (Integer(n) = 0) {
        say("최신 버전입니다.  (v" appVersion ")")
        return
    }

    changes := ""
    Git('log --format="· %s" HEAD..@{u}', &changes)

    ask := MsgBox("새 버전이 있습니다.  (지금 v" appVersion ",  바뀐 것 " n "개)`n`n"
        . SubStr(changes, 1, 1500)
        . "`n`n지금 받아서 다시 시작할까요?"
        . (running ? "`n(진행 중인 넘기기는 다시 켠 뒤 F9 로 다시 시작하세요)" : ""),
        "업데이트", "0x44 Owner" owner)

    if (ask != "Yes")
        return

    if (Git("pull --ff-only", &out) != 0) {
        MsgBox("받지 못했습니다. 아무것도 바꾸지 않았습니다.`n"
            . "이 PC 에서 고친 파일(사이트 프로필 등)이 새 버전과 겹치면 이렇게 됩니다.`n`n"
            . SubStr(out, 1, 1200), "업데이트", "0x30 Owner" owner)
        return
    }

    MsgBox("업데이트했습니다. 다시 시작합니다.", "업데이트", "0x40 T3 Owner" owner)
    Reload()
}

; --------------------------------------------------
; 진행 중에는 컴퓨터가 잠들지 않게 (화면은 꺼져도 됨)
; --------------------------------------------------
KeepAwake(on)
{
    global awakeOn

    if (on = awakeOn)
        return

    ; 0x80000001 = 계속 유지 + 시스템 깨어 있음 (화면 유지는 요구하지 않음)
    try DllCall("SetThreadExecutionState", "uint", on ? 0x80000001 : 0x80000000)

    awakeOn := on
}

; --------------------------------------------------
; 강의 창 찾기 (좌표 없이 창 제목으로)
; --------------------------------------------------
;   allowMin : 최소화된 창도 찾을지
;     강의 창은 최소화되면 영상이 멈추므로 건너뛴다.
;     읽기만 하는 창(진도·차시 목록)은 최소화돼 있어도 글자는 읽히므로 찾는다.
FindLectureWindow(keyword, allowMin := false)
{
    if (keyword = "")
        return 0

    for hwnd in WinGetList() {
        try {
            cls := WinGetClass(hwnd)

            if (cls != "Chrome_WidgetWin_1" && cls != "MozillaWindowClass")
                continue

            if (!allowMin && WinGetMinMax(hwnd) = -1)
                continue

            title := WinGetTitle(hwnd)

            if (title != "" && InStr(title, keyword))
                return hwnd
        }
    }

    return 0
}

GetLectureWindow()
{
    global lectureHwnd, pinnedHwnd

    ; 직접 고른 창이 있으면 그 창만 쓴다
    if pinnedHwnd {
        if WinExist("ahk_id " pinnedHwnd)
            return pinnedHwnd

        pinnedHwnd := 0          ; 그 창이 닫혔으면 자동으로 되돌림
    }

    if (lectureHwnd && WinExist("ahk_id " lectureHwnd))
        return lectureHwnd

    lectureHwnd := FindLectureWindow(P("사이트", "창제목"))

    return lectureHwnd
}

; 지금 열려 있는 브라우저 창들을 목록에 채운다
RefreshWindowList()
{
    global ddWindow, ddList, windowHwnds, listHwnds, pinnedHwnd, pinnedListHwnd

    windowHwnds := [0]
    listHwnds := [0]
    items := ["(자동으로 찾기)"]
    listItems := ["(자동으로 찾기)"]

    for hwnd in WinGetList() {
        try {
            cls := WinGetClass(hwnd)

            if (cls != "Chrome_WidgetWin_1" && cls != "MozillaWindowClass")
                continue

            title := WinGetTitle(hwnd)

            if (title = "")
                continue

            small := (WinGetMinMax(hwnd) = -1)

            ; 차시 목록 창은 읽기만 하므로 최소화된 창도 고를 수 있게 한다
            listHwnds.Push(hwnd)
            listItems.Push(SubStr(title, 1, 60) (small ? "  (최소화)" : ""))

            if small
                continue

            windowHwnds.Push(hwnd)
            items.Push(SubStr(title, 1, 60))
        }
    }

    ddWindow.Delete()
    ddWindow.Add(items)
    ddList.Delete()
    ddList.Add(listItems)

    ; 고른 창이 있으면 그 자리를 다시 고른다
    pick := 1

    for i, h in windowHwnds
        if (h = pinnedHwnd && pinnedHwnd)
            pick := i

    ddWindow.Choose(pick)

    pick := 1

    for i, h in listHwnds
        if (h = pinnedListHwnd && pinnedListHwnd)
            pick := i

    ddList.Choose(pick)
}

; 차시 목록이 있는 창을 직접 고른다 (자동으로 못 찾는 사이트용)
PickListWindow()
{
    global ddList, listHwnds, pinnedListHwnd

    idx := ddList.Value

    if (!idx || idx > listHwnds.Length)
        return

    pinnedListHwnd := listHwnds[idx]

    if !pinnedListHwnd {
        SetState("차시 목록 창을 자동으로 찾습니다.")
        return
    }

    ScanSessions(true)
    SetState(SessionReport())
}

; 창을 직접 고르면, 그 창에 맞는 사이트 프로필을 자동으로 맞춰 준다
PickWindow()
{
    global ddWindow, windowHwnds, pinnedHwnd, lectureHwnd

    idx := ddWindow.Value

    if (!idx || idx > windowHwnds.Length)
        return

    pinnedHwnd := windowHwnds[idx]
    lectureHwnd := 0

    if pinnedHwnd
        MatchProfileToWindow(pinnedHwnd)

    Tick()
}

; 창 제목을 보고 맞는 프로필로 바꿔 준다 (사용자가 다시 바꿔도 됨)
MatchProfileToWindow(hwnd)
{
    global profileList, profileDir, ddSite, profName

    title := ""

    try title := WinGetTitle("ahk_id " hwnd)

    if (title = "")
        return

    for name in profileList {
        data := ReadProfileFile(profileDir "\" name ".ini")
        key := GetVal(data, "사이트", "창제목")

        if (key != "" && InStr(title, key)) {
            if (name != profName) {
                ddSite.Choose(name)
                UseProfile(name)
            }

            return
        }
    }
}

; 지금 고른 프로필 파일을 메모장으로 연다
EditProfile()
{
    global profileDir, profName

    path := profileDir "\" profName ".ini"

    if !FileExist(path) {
        SetState("고른 프로필 파일이 없습니다: " path)
        return
    }

    try Run 'notepad.exe "' path '"'
    SetState("프로필을 고친 뒤 [다시 읽기] 를 누르면 바로 반영됩니다.")
}

; --------------------------------------------------
; 본 흐름
; --------------------------------------------------
Toggle()
{
    global running

    if running
        Stop("정지했습니다.")
    else
        Start()
}

Start()
{
    global running, btnStart, prof, pressCount, holdUntil, doneNotified, lastTimeVal, lastPageVal
    global lastReadTick, blindNotified, chkAwake, chkNextSession

    if (!IsObject(prof) || !prof.Count) {
        SetState("먼저 사이트 프로필을 고르세요.")
        return
    }

    if !GetLectureWindow() {
        SetState("'" P("사이트", "창제목") "' 이(가) 들어간 브라우저 창을 찾지 못했습니다."
            . "`n강의 창을 열어 두고 다시 시작하세요.")
        return
    }

    running := true
    pressCount := 0
    holdUntil := 0
    doneNotified := false
    lastTimeVal := -1
    lastPageVal := -1
    lastReadTick := 0
    blindNotified := false
    RefreshHotkeyLabels()
    KeepAwake(chkAwake.Value ? true : false)

    ; 다음 차시로 넘어가기를 켰으면, 전체 차시가 몇 개인지 한 번 읽어 둔다
    if (chkNextSession.Value && P("차시", "차시링크") != "")
        ScanSessions()

    Tick()
}

Stop(msg := "")
{
    global running, btnStart

    running := false
    RefreshHotkeyLabels()
    KeepAwake(false)
    ReleaseOnTop()

    if (msg != "")
        SetState(msg)
}

; 화면을 한 번 읽고 판단한 뒤, 다음에 언제 다시 볼지 스스로 정해 예약한다.
Tick()
{
    st := ""

    try
        st := TickBody()
    finally
        SetTimer(Tick, -NextTickMs(st))
}

; 다음에 화면을 읽을 때까지 기다릴 밀리초
;   영상이 잘 흐르는 중에는 끝날 때쯤까지 쉰다 (그동안 읽을 이유가 없다).
;   퀴즈·무언가 누르고 기다리는 중·멈춘 것 같을 때는 설정한 주기대로 본다.
NextTickMs(st)
{
    global running, holdUntil, quizStep, forceActive

    ms := TickSec() * 1000

    if (running && IsObject(st) && !st.quiz && quizStep = 0 && !forceActive
        && st.timeTotal > 0 && st.timeCur >= 0 && TimeMoving()) {
        left := (st.timeTotal - st.timeCur - 2) * 1000

        if (left > ms)
            ms := Min(left, 60000)          ; 아무리 길어도 1분에 한 번은 확인
    }

    ; 본체 창을 띄워 두고 보는 중이면 정한 주기대로 (상태 칸이 멈춘 것처럼 보이지 않게)
    if MainWindowShown()
        ms := Min(ms, TickSec() * 1000)

    if (holdUntil > A_TickCount)
        ms := Min(ms, Max(holdUntil - A_TickCount + 200, 500))

    return Max(ms, 500)
}

; 본체 창이 화면에 떠 있는지 (최소화·숨김이면 아니다)
MainWindowShown()
{
    global gui1

    if !IsObject(gui1)
        return false

    try {
        if !DllCall("IsWindowVisible", "ptr", gui1.Hwnd)
            return false

        return WinGetMinMax("ahk_id " gui1.Hwnd) != -1
    }

    return false
}

TickBody()
{
    global running, txtWindow, txtCount, pressCount, holdUntil, prof
    global readGapMs
    global lastTimeVal, lastTimeTick, lastTimeMovedTick, lastPageVal, covered, quizLatchPage, sessionNum, videoWrapped
    global lastTotalVal, lectureHwnd

    static lastAt := 0

    readGapMs := lastAt ? (A_TickCount - lastAt) : 0
    lastAt := A_TickCount

    if (!IsObject(prof) || !prof.Count) {
        UpdateOverlay("", "프로필 없음")
        return
    }

    hwnd := GetLectureWindow()

    if !hwnd {
        txtWindow.Text := "못 찾음 (창 제목에 '" P("사이트", "창제목") "' 이 들어간 창)"

        if running
            SetState("강의 창을 찾지 못했습니다. 창이 닫혔거나 최소화되어 있는지 확인하세요.")

        UpdateOverlay("", "강의 창 없음")
        return
    }

    title := WinGetTitle("ahk_id " hwnd)
    txtWindow.Text := title
    KeepOnTop(hwnd)

    ; 같은 브라우저 창에서 다른 탭(예: GitHub)을 보고 있으면 강의 화면이 아니다.
    ;   이 프로그램은 창에서 '지금 보이는 탭' 만 읽으므로, 그대로 두면 엉뚱한 페이지의 숫자를
    ;   페이지 번호로 읽거나 버튼을 찾아 누를 수 있다. 강의 탭이 돌아올 때까지 아무것도 하지 않는다.
    ;   (창을 직접 고른 경우는 제목이 프로필과 다를 수 있으므로 따지지 않는다)
    static tabGoneSince := 0, tabGoneNotified := false
    global pinnedHwnd
    key := P("사이트", "창제목")

    if (!pinnedHwnd && key != "" && !InStr(title, key)) {
        if !tabGoneSince
            tabGoneSince := A_TickCount

        lectureHwnd := 0          ; 강의 탭을 다른 창으로 옮겼으면 다음 번에 그 창을 찾도록

        if running {
            SetState("강의 탭이 앞에 있지 않습니다. 그 창에서 다른 탭을 보고 있습니다."
                . "`n지금 보이는 탭: " title
                . "`n강의 탭을 다시 눌러 주세요. 그동안은 아무것도 누르지 않습니다."
                . "`n(다른 사이트는 새 창(Ctrl+N)에서 열면 강의에 영향이 없습니다)")

            if (!tabGoneNotified && A_TickCount - tabGoneSince > 30000) {
                tabGoneNotified := true
                Notify("강의 탭이 앞에 있지 않아 넘기지 못하고 있습니다. 강의 탭을 다시 눌러 주세요.")
            }
        }

        UpdateOverlay("", "탭 바뀜")
        return
    }

    tabGoneSince := 0, tabGoneNotified := false

    root := 0
    try ComCall(6, UIA(), "ptr", hwnd, "ptr*", &root)

    if !root {
        SetState("창은 찾았지만 내용을 읽지 못했습니다.")
        UpdateOverlay("", "화면 못 읽음")
        return
    }

    covered := WindowCovered(hwnd)

    st := ReadState(root)

    n := ReadSessionNum(root)

    if (n > 0)
        sessionNum := n

    ; 영상 없이 퀴즈만 있는 페이지는, 한 번 퀴즈로 알아보면 페이지가 바뀔 때까지 퀴즈로 본다
    ; ('퀴즈 시작' 을 누르고 나면 퀴즈 표시가 사라지는 사이트가 있음)
    if (st.pageCur > 0 && st.pageCur != quizLatchPage)
        quizLatchPage := -1

    if (st.quiz && st.pageCur > 0 && st.timeTotal <= 0) {
        quizLatchPage := st.pageCur
    } else if (!st.quiz && quizLatchPage > 0 && st.pageCur = quizLatchPage) {
        st.quiz := true
        st.quizDesc := "퀴즈 페이지 (이 페이지에서 퀴즈를 알아봤음)"
    }

    ; 전체 시간이 바뀌었으면 다른 영상이다 (다음 차시가 뜸).
    ; 지난 영상의 끝 시간과 견주면 '되돌아감' 으로 잘못 알아 새 영상을 조금 보다 또 넘기므로 비운다.
    if (st.timeTotal > 0) {
        if (lastTotalVal > 0 && Abs(st.timeTotal - lastTotalVal) > 2) {
            lastTimeVal := -1
            lastTimeTick := 0
            lastTimeMovedTick := 0
            videoWrapped := false
        }

        lastTotalVal := st.timeTotal
    }

    ; 영상이 끝나면 시간을 처음으로 되돌리는 플레이어가 있다 (존플레이어)
    ; 끝 가까이 갔다가 시간이 뒤로 크게 돌아오면 '끝난 것' 으로 본다
    ; (읽는 주기를 늦게 두면 04:20 → 00:05 처럼 건너뛰므로 '되돌아감' 으로 판단해야 한다)
    ; 이 영상에서 시간이 흐르는 것을 한 번이라도 본 뒤에만 (멈춰 있던 지난 화면 값으로 판단하지 않게)
    if (st.timeTotal > 10 && lastTimeVal >= 0 && st.timeCur >= 0 && lastTimeMovedTick
        && st.timeCur < lastTimeVal - 3
        && (lastTimeVal >= st.timeTotal - 3 || lastTimeVal * 4 >= st.timeTotal * 3)
        && st.timeCur * 5 < st.timeTotal)
        videoWrapped := true

    ; 재생 시간이 흐르는지 기록
    if (st.timeCur != lastTimeVal) {
        if (lastTimeVal >= 0 && st.timeCur >= 0)
            lastTimeMovedTick := A_TickCount          ; 실제로 값이 바뀐 것을 본 시각

        lastTimeVal := st.timeCur
        lastTimeTick := A_TickCount
    }

    if (st.pageCur > 0 && st.pageCur != lastPageVal) {
        lastPageVal := st.pageCur
        holdUntil := 0
        videoWrapped := false
    }

    ; 차시를 넘긴 뒤에는 새 영상이 실제로 도는 것을 볼 때까지 '끝남' 을 믿지 않는다
    ; (새 강의가 늦게 뜨면 지난 영상의 '끝남' 이 그대로 보여 한 차시를 더 건너뛰게 된다)
    global awaitFresh

    if (awaitFresh && !st.ended && (st.playKnown ? st.playing : TimeMoving())
        && !(st.timeTotal > 0 && st.timeCur >= st.timeTotal - 1))
        awaitFresh := 0

    SetState(StateText(st))
    WatchReadable(st)
    WatchCovered()

    if (running && A_TickCount >= holdUntil)
        Act(root, st)

    ObjRelease(root)
    txtCount.Text := "넘김 " pressCount "회"
    UpdateOverlay(st)

    return st
}

; ==================================================
; 작업 중 오버레이
;
; 다른 일을 하면서도 한눈에 보이도록 화면 구석에 작게 띄운다.
;   05/08
;   15:03/30:00
;   재생 중
; 사람이 봐야 하는 상태(퀴즈, 못 읽음, 가려져 멈춤)면 빨갛게 바뀐다.
; 끌면 옮겨지고(위치 기억), 그냥 누르면 본체 창이 뜬다.
; 눌러도 지금 하던 작업 창의 포커스를 빼앗지 않는다.
; ==================================================
OverlayFont()
{
    static font := ""

    if (font != "")
        return font

    ; 디지털 느낌의 고정폭 글꼴. 없으면 모든 윈도우에 있는 Consolas
    dirs := [A_WinDir "\Fonts", EnvGet("LOCALAPPDATA") "\Microsoft\Windows\Fonts"]

    for pair in [["Cascadia Mono", "CascadiaMono.ttf"], ["Cascadia Code", "CascadiaCode.ttf"]] {
        for d in dirs
            if FileExist(d "\" pair[2])
                return font := pair[1]
    }

    return font := "Consolas"
}

BuildOverlay()
{
    global ovl, ovlPage, ovlTime, ovlPlay, ovlEmo, ovlWord, ovlIcon, ovlLook, ovlMode, settingFile

    if IsObject(ovl) {
        try ovl.Destroy()
        ovl := 0
    }

    ovlLook := ""
    ovlIcon := 0, ovlTime := 0, ovlPlay := 0, ovlEmo := 0, ovlWord := 0

    if (ovlMode = "숨김")          ; 아예 띄우지 않는다
        return

    k := A_ScreenDPI / 96
    small := (ovlMode = "작게")

    ; -DPIScale: 크기를 직접 픽셀로 다룬다 / E0x08000000: 눌러도 포커스를 빼앗지 않음
    ovl := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000", "강의 듣는 중")
    ovl.BackColor := OverlayLook("보통").bg
    ovl.MarginX := 0
    ovl.MarginY := 0

    if small {
        ; ▶ 2/5차시 4/8p
        ;   02:31/17:43        ← 아랫줄은 작은 글씨로 시간
        ow := Round(190 * k)
        oh := Round(58 * k)
        radius := Round(16 * k)

        ovl.SetFont("s12 norm", "Segoe UI Symbol")
        ovlIcon := ovl.Add("Text", Format("x{1} y{2} w{3} h{4} Center +0x200", Round(8 * k), Round(3 * k), Round(28 * k), Round(30 * k)), "")

        ovl.SetFont("s13 bold", OverlayFont())
        ovlPage := ovl.Add("Text", Format("x{1} y{2} w{3} h{4} +0x200", Round(38 * k), Round(3 * k), ow - Round(42 * k), Round(30 * k)), "-/-")

        ovl.SetFont("s10 bold", OverlayFont())
        ovlTime := ovl.Add("Text", Format("x{1} y{2} w{3} h{4} +0x200", Round(38 * k), Round(31 * k), ow - Round(42 * k), Round(22 * k)), "")
    } else {
        ;       6/8
        ;   ▶ 12:02/14:44
        ;       📖
        ow := Round(230 * k)
        oh := Round(106 * k)
        radius := Round(20 * k)

        ovl.SetFont("s15 bold", OverlayFont())
        ovlPage := ovl.Add("Text", Format("x0 y{1} w{2} h{3} Center +0x200", Round(6 * k), ow, Round(30 * k)), "-/-")

        ovl.SetFont("s12 norm", "Segoe UI Symbol")
        ovlPlay := ovl.Add("Text", Format("x0 y{1} w1 h{2} +0x200", Round(38 * k), Round(30 * k)), "")
        ovl.SetFont("s16 bold", OverlayFont())
        ovlTime := ovl.Add("Text", Format("x0 y{1} w1 h{2} +0x200", Round(38 * k), Round(30 * k)), "")

        ovl.SetFont("s14 norm", "Segoe UI Symbol")
        ovlEmo := ovl.Add("Text", Format("x0 y{1} w1 h{2} +0x200", Round(70 * k), Round(30 * k)), "")
        ovl.SetFont("s10 bold", "맑은 고딕")
        ovlWord := ovl.Add("Text", Format("x0 y{1} w1 h{2} +0x200", Round(70 * k), Round(30 * k)), "")
    }

    ovl.Show(Format("NA Hide w{1} h{2}", ow, oh))

    ; 모서리를 둥글게, 살짝 투명하게
    ; 아직 숨겨 둔 창이라 잠시 '숨은 창도 찾기' 를 켠다 (끝나면 원래대로)
    prevHidden := A_DetectHiddenWindows
    DetectHiddenWindows true
    WinSetRegion(Format("0-0 w{1} h{2} R{3}-{3}", ow, oh, radius), "ahk_id " ovl.Hwnd)
    WinSetTransparent(200, "ahk_id " ovl.Hwnd)
    DetectHiddenWindows prevHidden

    ; 자리는 '오른쪽 끝' 기준으로 기억한다 (크기를 바꿔도 같은 구석에 붙어 있도록)
    right := "", y := ""

    try {
        right := IniRead(settingFile, "오버레이", "오른쪽", "")
        y := IniRead(settingFile, "오버레이", "Y", "")
    }

    if (IsInteger(right) && IsInteger(y) && PointOnScreen(Integer(right) - ow // 2, Integer(y) + oh // 2)) {
        x := Integer(right) - ow
        y := Integer(y)
    } else {
        x := A_ScreenWidth - ow - Round(24 * k)
        y := Round(24 * k)
    }

    ovl.Show(Format("NA x{1} y{2}", x, y))
}

; 겉모양 한 벌: 바탕색, 숫자색, 이모지색
OverlayLook(look)
{
    static looks := Map(
        "보통", {bg: "1C2129", text: "E8EDF2", emo: "7EE2A8"},     ; 자동 넘기기 진행 중
        "정지", {bg: "1C2129", text: "9AA4AE", emo: "D9B98A"},     ; 쉬는 중 (자동 넘기기 꺼짐)
        "주의", {bg: "B3261E", text: "FFFFFF", emo: "FFFFFF"},     ; 사람이 봐야 함
        "완료", {bg: "1B6B3A", text: "FFFFFF", emo: "FFFFFF"}      ; 강의 끝
    )

    return looks.Has(look) ? looks[look] : looks["보통"]
}

; 강의 상태를 보고 오버레이에 무엇을 보일지 정한다
;   영상 상태     → 시간 앞 ▶(재생) / ‖(멈춤)
;   자동 넘기기   → 📖 학습 중 / ☕ 휴식 / 📝 퀴즈 / 🎓 완료 / ⚠ 확인 필요
UpdateOverlay(st := "", note := "")
{
    global ovl, running, covered, blindNotified, chkQuizAuto, quizStuck, forceActive

    if !IsObject(ovl)          ; 숨김으로 해 두었거나 아직 안 만들었으면 할 일 없음
        return

    static shortWord := Map(
        "강의 창 없음", "창 없음",
        "탭 바뀜", "탭 바뀜",
        "화면 못 읽음", "못 읽음",
        "프로필 없음", "프로필 없음"
    )

    if !IsObject(st) {
        GuessTime("")
        SetOverlay("-/-", "--:--/--:--", "", "⚠", shortWord.Has(note) ? shortWord[note] : note, running ? "주의" : "정지")
        return
    }

    ; 차시와 페이지를 함께:  2/5차시 5/8p  (모르는 쪽은 뺀다)
    global sessionNum, sessionTotal

    ses := (sessionNum > 0) ? sessionNum (sessionTotal > 0 ? "/" sessionTotal : "") "차시" : ""
    pg := (st.pageTotal > 0) ? st.pageCur "/" st.pageTotal "p" : ""
    page := (ses != "" && pg != "") ? ses " " pg : (ses pg != "" ? ses pg : "-/-")
    ; 전체 시간이 안 나오는 플레이어는 지금 시간만
    time := (st.timeTotal > 0) ? SecText(st.timeCur) "/" SecText(st.timeTotal)
        : (st.timeCur >= 0 ? SecText(st.timeCur) : "--:--/--:--")

    readable := (st.playKnown || st.timeText != "" || st.pageTotal > 0 || st.quiz)
    ended := (st.timeTotal > 0 && st.timeCur >= st.timeTotal - 1) || videoWrapped || st.ended
    ; 페이지 표시가 없는 강의(차시 하나가 영상 한 편)는 영상이 끝나면 그대로 차시 끝
    last := (st.pageTotal > 0) ? (st.pageCur >= st.pageTotal) : true
    stalled := StalledSec()

    ; 영상이 실제로 흐르는지: 재생 상태이고 시간도 흐르고 있어야 ▶
    ; 재생 상태를 알 수 없는 사이트는 시간이 흐르는지만 본다
    playing := st.playKnown ? st.playing : TimeMoving()

    ; 재생 상태를 알려 주는 플레이어는 그 표시를 믿는다.
    ;   창이 가려지거나 뒤에 있으면 브라우저가 시간 글자를 1분에 한 번쯤만 바꾸므로,
    ;   시간이 잠깐 멈춰 보여도 영상은 돌고 있다. 시간으로만 판단하는 사이트만 멈춘 시간을 본다.
    if (!st.playKnown && st.timeTotal <= 0)
        video := ""
    else if (!ended && (st.playKnown ? st.playing : (playing && stalled < 10)))
        video := "▶"
    else
        video := "❚❚"

    if (st.quiz && running && chkQuizAuto.Value && (!quizStuck || forceActive))
        emo := "📝", word := "자동", look := "보통"          ; 알아서 푸는 중
    else if st.quiz
        emo := "📝", word := "퀴즈", look := "주의"
    else if (ended && last)
        emo := "🎓", word := "", look := "완료"
    else if !readable
        emo := "⚠", word := "못 읽음", look := running ? "주의" : "정지"
    else if !running
        emo := "☕", word := "", look := "정지"
    else if blindNotified
        emo := "⚠", word := "못 읽음", look := "주의"
    else if (covered && stalled >= 10)
        emo := "⚠", word := "가려짐", look := "주의"
    else
        emo := "📖", word := "", look := "보통"

    GuessTime((video = "▶" && st.timeTotal > 0 && st.timeCur >= 0) ? st : "")
    SetOverlay(page, time, video, emo, word, look)
}

; 화면을 5초·10초에 한 번만 읽으므로, 그사이 오버레이 시계가 멈춘 것처럼 보인다.
; 마지막에 읽은 값에서 흐른 만큼을 더해 보여 준다 (화면을 읽지 않으므로 가볍다).
GuessTime(st)
{
    global guessCur, guessTotal, guessTick

    if !IsObject(st) {
        guessTotal := 0
        return
    }

    guessCur := st.timeCur
    guessTotal := st.timeTotal
    guessTick := A_TickCount
}

OverlayGuess()
{
    global guessCur, guessTotal, guessTick, ovl, ovlTime

    if (!guessTotal || !IsObject(ovl) || !IsObject(ovlTime))
        return

    sec := guessCur + (A_TickCount - guessTick) // 1000

    if (sec > guessTotal)
        sec := guessTotal

    t := SecText(sec) "/" SecText(guessTotal)

    if (ovlTime.Text != t)
        ovlTime.Text := t
}

SetOverlay(page, time, video, emo, word, look)
{
    global ovl, ovlPage, ovlTime, ovlPlay, ovlEmo, ovlWord, ovlIcon, ovlLook

    static last := Map()

    c := OverlayLook(look)
    lookChanged := (look != ovlLook)

    if lookChanged {
        ovl.BackColor := c.bg

        for ctrl in [ovlPage, ovlTime, ovlPlay, ovlEmo, ovlWord, ovlIcon]
            if IsObject(ctrl)
                ctrl.Opt("+Background" c.bg)

        ovlPage.SetFont("c" c.text)

        if IsObject(ovlTime)
            ovlTime.SetFont("c" c.text)

        if IsObject(ovlWord)
            ovlWord.SetFont("c" c.text)

        if IsObject(ovlEmo)
            ovlEmo.SetFont("c" c.emo)

        ovlLook := look
        last := Map()          ; 색이 바뀌었으니 아래에서 모두 다시 칠한다
    }

    ; 재생 기호 색: 재생 초록 / 멈춤 주황 (빨강·초록 바탕 위에서는 흰색)
    playColor := (look = "주의" || look = "완료") ? "FFFFFF" : (video = "▶" ? "3DDC84" : "FFC857")

    if IsObject(ovlIcon) {
        ; ---- 작게: 기호 하나 + 페이지
        ;   진행 중이면 영상 상태(▶/‖), 쉬는 중이면 ☕, 그 밖에는 그 상태의 이모지
        if (look = "보통")
            icon := (video != "") ? video : emo, iconColor := (video != "") ? playColor : c.emo
        else
            icon := emo, iconColor := c.emo

        if (last.Get("icon", "") != icon || last.Get("iconColor", "") != iconColor) {
            ovlIcon.SetFont("c" iconColor)
            ovlIcon.Text := icon
            last["icon"] := icon, last["iconColor"] := iconColor
        }

        text := (word != "") ? word : page

        if (ovlPage.Text != text)
            ovlPage.Text := text

        if (ovlTime.Text != time)
            ovlTime.Text := time
    } else {
        ; ---- 크게: 페이지 / ▶ 시간 / 이모지
        if (ovlPage.Text != page)
            ovlPage.Text := page

        if (last.Get("play", "?") != video || last.Get("playColor", "") != playColor || ovlTime.Text != time) {
            ovlPlay.SetFont("c" playColor)
            ovlPlay.Text := video
            ovlTime.Text := time
            last["play"] := video, last["playColor"] := playColor
            LayoutPair(ovlPlay, ovlTime, 6)
        }

        if (last.Get("emo", "?") != emo || ovlWord.Text != word) {
            ovlEmo.Text := emo
            ovlWord.Text := word
            last["emo"] := emo
            LayoutPair(ovlEmo, ovlWord, 6)
        }
    }

    if !DllCall("IsWindowVisible", "ptr", ovl.Hwnd)
        ovl.Show("NA")
}

; 두 글자 칸을 나란히 붙여 오버레이 가운데에 놓는다 (글자 폭을 재서)
LayoutPair(a, b, gapLogical)
{
    global ovl

    k := A_ScreenDPI / 96
    ovl.GetClientPos(, , &ow)
    a.GetPos(, &y, , &h)

    wa := (a.Text != "") ? MeasureText(a, a.Text) + 2 : 0
    wb := (b.Text != "") ? MeasureText(b, b.Text) + 2 : 0
    gap := (wa && wb) ? Round(gapLogical * k) : 0

    x := (ow - (wa + gap + wb)) // 2

    a.Move(x, y, Max(wa, 1), h)
    b.Move(x + wa + gap, y, Max(wb, 1), h)
}

; 그 칸의 글꼴로 글자 폭(픽셀)을 잰다
MeasureText(ctrl, text)
{
    hFont := SendMessage(0x31, 0, 0, ctrl)                  ; WM_GETFONT
    hdc := DllCall("GetDC", "ptr", ctrl.Hwnd, "ptr")
    old := DllCall("SelectObject", "ptr", hdc, "ptr", hFont, "ptr")

    size := Buffer(8, 0)
    DllCall("GetTextExtentPoint32W", "ptr", hdc, "wstr", text, "int", StrLen(text), "ptr", size)

    DllCall("SelectObject", "ptr", hdc, "ptr", old)
    DllCall("ReleaseDC", "ptr", ctrl.Hwnd, "ptr", hdc)

    return NumGet(size, 0, "int")
}

SetOverlayMode(mode)
{
    global ovlMode

    if (mode = ovlMode)
        return

    ovlMode := mode
    BuildOverlay()
    SaveSettings()
    Tick()
}

ResetOverlayPos()
{
    global settingFile

    try IniDelete(settingFile, "오버레이")

    BuildOverlay()
    Tick()
}

PointOnScreen(x, y)
{
    vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)     ; 가상 화면 전체

    return (x >= vx && x < vx + vw && y >= vy && y < vy + vh)
}

; 강의 상태를 보고 오버레이에 쓸 글자와 색을 정한다


; 오버레이를 끌면 옮기고, 그냥 누르면 본체 창을 띄운다
OverlayMouseDown(wParam, lParam, msg, hwnd)
{
    global ovl, settingFile

    if !IsObject(ovl)
        return

    if (DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr") != ovl.Hwnd)
        return

    WinGetPos(&x1, &y1, &ow, , "ahk_id " ovl.Hwnd)

    ; 창 제목줄을 잡은 것처럼 끌기 시작. 버튼을 놓을 때까지 여기서 기다린다
    SendMessage(0xA1, 2, 0, , "ahk_id " ovl.Hwnd)      ; WM_NCLBUTTONDOWN, HTCAPTION

    WinGetPos(&x2, &y2, , , "ahk_id " ovl.Hwnd)

    if (Abs(x2 - x1) <= 3 && Abs(y2 - y1) <= 3) {
        ShowMainWindow()
    } else {
        try {
            IniWrite(x2 + ow, settingFile, "오버레이", "오른쪽")
            IniWrite(y2, settingFile, "오버레이", "Y")
        }
    }

    return 0
}


; 강의 상태를 보고 오버레이에 쓸 글자와 색을 정한다


; 오버레이를 끌면 옮기고, 그냥 누르면 본체 창을 띄운다

ShowMainWindow()
{
    global gui1

    try {
        if (WinGetMinMax("ahk_id " gui1.Hwnd) = -1)
            WinRestore("ahk_id " gui1.Hwnd)

        gui1.Show()
        WinActivate("ahk_id " gui1.Hwnd)
    }
}

; --------------------------------------------------
; 강의 창 밀어두기 / 되돌리기
;
; 브라우저는 창이 '완전히' 가려지면 그 화면을 멈춘다.
; 그래서 화면 오른쪽 끝에 몇 픽셀만 남기고 밀어 두고,
; 그 몇 픽셀이 다른 창에 덮이지 않도록 '항상 위' 로 만든다.
; 이러면 화면을 거의 차지하지 않으면서도 강의는 계속 진행된다.
; --------------------------------------------------
; 프로그램을 끌 때는 밀어둔 창을 반드시 되돌려 놓는다
CleanUpOnExit()
{
    global asideSaved

    KeepAwake(false)
    try ReleaseOnTop()

    if IsObject(asideSaved)
        try RestoreAside()
}

AsidePx()
{
    global editAsidePx

    v := IsObject(editAsidePx) ? Trim(editAsidePx.Value) : "6"

    if !IsInteger(v)
        return 6

    n := Integer(v)

    return (n < 2) ? 2 : (n > 400 ? 400 : n)
}

; 밀어둘 쪽 (설정: 자동 / 오른쪽 / 왼쪽)
AsideSide()
{
    global ddAsideSide, asideSideSet

    v := IsObject(ddAsideSide) ? ddAsideSide.Text : asideSideSet

    return (v = "오른쪽" || v = "왼쪽") ? v : "자동"
}

; 밀어둘 자리 (모든 모니터를 합친 화면 기준)
;   듀얼 모니터에서 '그 창이 놓인 모니터의 오른쪽 끝' 으로 밀면 옆 모니터로 옮겨질 뿐 숨겨지지 않는다.
;   그래서 전체 화면의 바깥 끝으로 민다. 자동이면 창이 가까운 쪽 바깥으로.
AsideTargetX(x, w, px)
{
    vx := SysGet(76)                    ; 전체 화면 왼쪽
    vw := SysGet(78)                    ; 전체 화면 너비
    side := AsideSide()

    if (side = "자동")
        side := ((x + w // 2) < vx + vw // 2) ? "왼쪽" : "오른쪽"

    return (side = "왼쪽") ? (vx - w + px) : (vx + vw - px)
}

ToggleAside()
{
    global asideSaved

    if IsObject(asideSaved)
        RestoreAside()
    else
        PushAside()
}

PushAside()
{
    global asideSaved, asideHwnd, btnAside

    hwnd := GetLectureWindow()

    if !hwnd {
        SetState("강의 창을 찾지 못했습니다.")
        return
    }

    if (WinGetMinMax("ahk_id " hwnd) = 1)
        WinRestore("ahk_id " hwnd)          ; 최대화 상태면 먼저 풀어야 옮길 수 있다

    Sleep 200
    WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)

    if (w <= 0 || h <= 0) {
        SetState("창 크기를 읽지 못했습니다.")
        return
    }

    asideSaved := {x: x, y: y, w: w, h: h}
    asideHwnd := hwnd

    px := AsidePx()
    newX := AsideTargetX(x, w, px)

    WinMove(newX, y, w, h, "ahk_id " hwnd)
    WinSetAlwaysOnTop(true, "ahk_id " hwnd)

    RefreshHotkeyLabels()
    SetState("강의 창을 화면 " (newX < x ? "왼쪽" : "오른쪽") " 끝에 " px "픽셀만 남기고 밀어 두었습니다."
        . "`n그 몇 픽셀이 가려지지 않도록 '항상 위' 로 해 두었습니다. 계속 진행됩니다."
        . "`n되돌리려면 F11 을 다시 누르세요.")
}

RestoreAside()
{
    global asideSaved, asideHwnd, btnAside

    if !IsObject(asideSaved)
        return

    hwnd := (asideHwnd && WinExist("ahk_id " asideHwnd)) ? asideHwnd : GetLectureWindow()

    if hwnd {
        try {
            WinSetAlwaysOnTop(false, "ahk_id " hwnd)
            WinMove(asideSaved.x, asideSaved.y, asideSaved.w, asideSaved.h, "ahk_id " hwnd)
        }
    }

    asideSaved := ""
    asideHwnd := 0
    RefreshHotkeyLabels()
    SetState("강의 창을 원래 자리로 되돌렸습니다.")
}

; --------------------------------------------------
; 진행 중에는 강의 창을 항상 위에 ([설정] → 시스템, 기본 켜짐)
;   다른 창을 전체 화면으로 써도 강의 창이 완전히 덮이지 않아, 브라우저가 영상을 멈추지 않는다.
;   강의 창이 바뀌면 새 창으로 옮기고, 정지·종료하면 푼다.
;   밀어둔 창(F11)은 밀어두기가 따로 항상 위를 관리하므로 여기서 풀지 않는다.
;   원래 항상 위였던 창(사용자가 PowerToys 등으로 켜 둔 것)은 끝날 때도 그대로 둔다.
; --------------------------------------------------
KeepOnTop(hwnd)
{
    global running, chkOnTop, topHwnd, topOwned

    want := running && IsObject(chkOnTop) && chkOnTop.Value && hwnd

    if (topHwnd && (!want || topHwnd != hwnd))
        ReleaseOnTop()

    if !want
        return

    try {
        isTop := WinGetExStyle("ahk_id " hwnd) & 0x8          ; 0x8 = 항상 위

        if (topHwnd != hwnd) {
            topHwnd := hwnd
            topOwned := !isTop          ; 처음 볼 때 이미 항상 위면 사용자가 켜 둔 것
        }

        if !isTop
            WinSetAlwaysOnTop(true, "ahk_id " hwnd)
    }
}

ReleaseOnTop()
{
    global topHwnd, topOwned, asideSaved, asideHwnd

    if (topHwnd && topOwned && !(IsObject(asideSaved) && asideHwnd = topHwnd) && WinExist("ahk_id " topHwnd))
        try WinSetAlwaysOnTop(false, "ahk_id " topHwnd)

    topHwnd := 0
    topOwned := false
}

; --------------------------------------------------
; 창 가림 감시
; 강의 창이 다른 창에 '완전히' 덮이면 브라우저가 그 화면을 멈춰 버린다.
; (포커스는 상관없다. 창이 조금이라도 보이면 잘 돌아간다)
; --------------------------------------------------
TopWindowAt(x, y)
{
    h := DllCall("WindowFromPoint", "int64", (x & 0xFFFFFFFF) | (y << 32), "ptr")

    return h ? DllCall("GetAncestor", "ptr", h, "uint", 2, "ptr") : 0
}

WindowCovered(hwnd)
{
    try WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)

    if (!IsSet(ww) || ww <= 0 || wh <= 0)
        return false

    ; 화면에 걸친 부분만 본다 (밀어둔 창은 대부분이 화면 밖이라 그대로 재면 늘 '가려짐' 이 된다)
    vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
    l := Max(wx, vx), t := Max(wy, vy)
    r := Min(wx + ww, vx + vw), b := Min(wy + wh, vy + vh)

    if (r - l < 2 || b - t < 2)
        return true                      ; 화면에 한 점도 안 걸침 (최소화 등)

    mx := Min(40, (r - l) // 3), my := Min(120, (b - t) // 3)
    wx := l, wy := t, ww := r - l, wh := b - t

    pts := [[wx + ww // 2, wy + wh // 2]
          , [wx + mx, wy + my]
          , [wx + ww - mx, wy + my]
          , [wx + mx, wy + wh - my]
          , [wx + ww - mx, wy + wh - my]]

    for p in pts
        if (TopWindowAt(p[1], p[2]) = hwnd)
            return false          ; 한 군데라도 보이면 가려진 것이 아니다

    return true
}

WatchCovered()
{
    global running, covered, coveredNotified

    if (!covered) {
        coveredNotified := false
        return
    }

    if (!running || coveredNotified)
        return

    ; 가려진 데다 재생 시간까지 멈춰 있으면 알린다
    if (StalledSec() >= 10) {
        coveredNotified := true
        Notify("강의 창이 다른 창에 완전히 가려져 진행이 멈췄습니다."
            . "`n창이 조금이라도 보이게 해 주세요. 포커스는 다른 창에 있어도 됩니다.")
    }
}

; 화면을 읽을 수 있는 상태인지 지켜본다.
; 탭이 바뀌거나 창이 최소화되면 읽히지 않고, 그러면 진행도 멈추므로 알려 준다.
WatchReadable(st)
{
    global running, lastReadTick, blindNotified

    readable := (st.playKnown || st.timeText != "" || st.pageTotal > 0 || st.quiz)

    if readable {
        lastReadTick := A_TickCount

        if blindNotified {
            blindNotified := false
            Notify("강의 화면을 다시 읽을 수 있습니다. 진행을 계속합니다.", false)
        }

        return
    }

    if (!running || blindNotified)
        return

    if (lastReadTick = 0) {
        lastReadTick := A_TickCount
        return
    }

    if (A_TickCount - lastReadTick > 30000) {
        blindNotified := true
        Notify("강의 화면을 읽을 수 없습니다. 진행이 멈춥니다."
            . "`n그 창에서 다른 탭을 보고 있거나, 창이 최소화되어 있지 않은지 확인하세요.")
    }
}

; --------------------------------------------------
; 퀴즈 아무거나 누르고 넘어가기 (설정에서 켰을 때)
;
; 사이트마다 퀴즈 모양이 다르므로 특정 O/X 코드에 기대지 않는다.
;   1) 아무 답이나 하나 누른다
;        프로필에 [문제풀이] 보기 가 있으면 그것, 없으면 일반 규칙으로 찾는다 (FindAnyAnswer)
;   2) 몇 초 기다렸다가, 다음/next 같은 버튼이 보이면 누른다
;        프로필의 [문제풀이] 푼뒤누를것 → 없으면 이름으로 찾는다 (FindNextLike)
;   3) 그래도 퀴즈가 그대로면 한 번 더. 두 번 해도 안 되면 사람에게 알린다
; 순간적으로 못 찾거나 못 누르는 일이 있으므로, 한 번 실패로 포기하지 않고 몇 번 더 해 본다.
; --------------------------------------------------
AutoQuiz(root, st)
{
    global quizStep, quizTick, quizPage, quizTries, quizStuck, quizNote, quizFail, quizWhy, holdUntil, pressCount, lastPressError
    global chkQuizForce, forceGaveUp, quizStarted, quizTried, quizLastKey, quizLastName

    ; 페이지가 바뀌면 처음부터
    if (st.pageCur != quizPage) {
        quizPage := st.pageCur
        quizStep := 0
        quizTries := 0
        quizFail := 0
        quizStuck := false
        quizWhy := ""
        quizStarted := false
        quizTried := Map()
        quizLastKey := "", quizLastName := ""
        ResetForce()
    }

    ; 퀴즈에 '시작' 버튼이 따로 있는 사이트는 그것부터 (페이지마다 한 번)
    if (!quizStarted && P("문제풀이", "시작") != "") {
        el := FindSel(root, P("문제풀이", "시작"))

        if el {
            how := PressElement(el)
            ObjRelease(el)

            if (how != "") {
                quizStarted := true
                quizTick := A_TickCount
                holdUntil := A_TickCount + 2500          ; 문제가 뜰 때까지 잠깐
                quizNote := "퀴즈 시작을 눌렀습니다."
                return
            }
        }
    }

    if quizStuck {
        if (chkQuizForce.Value && !forceGaveUp)
            return ForceQuiz(root, st)          ; 설정에서 켰으면 누를 수 있는 것을 차례로

        return QuizNeedsPerson(st, quizWhy != "" ? quizWhy : "자동으로 넘기지 못했습니다.")
    }

    if (quizStep = 0) {
        if (quizTries >= 2) {
            quizStuck := true
            quizWhy := "아무 답이나 두 번 눌러 봤지만 넘어가지 않았습니다."
            return QuizNeedsPerson(st, quizWhy)
        }

        el := FindQuizAnswer(root, quizTried)

        ; 모든 답을 눌러 봤으면 (모두 오답 표시) 더 누르지 않고 넘기러 간다
        if (!el && quizTried.Count) {
            quizStep := 1
            quizTick := A_TickCount - QuizWaitSec() * 1000
            quizNote := "모든 답을 눌러 봤습니다. 넘깁니다."
            return
        }

        if !el
            return QuizFailOnce(st, "누를 답을 찾지 못했습니다.")

        answer := Trim(U_Str(el, 23))
        key := AnswerKey(el)
        how := PressElement(el)
        ObjRelease(el)

        if (how = "")
            return QuizFailOnce(st, "답을 누르지 못했습니다" (lastPressError != "" ? " (" lastPressError ")" : "") ".")

        quizTried[key] := true
        quizLastKey := key
        quizLastName := (answer != "") ? SubStr(answer, 1, 20) : "답"
        quizFail := 0
        quizTries += 1
        quizStep := 1
        quizTick := A_TickCount
        quizNote := "'" quizLastName "' 을(를) 눌렀습니다. " QuizWaitSec() "초 뒤에 넘깁니다."
            . (quizTried.Count > 1 ? " (" quizTried.Count "번째 답)" : "")
        return
    }

    if (quizStep = 1) {
        left := QuizWaitSec() - (A_TickCount - quizTick) // 1000

        if (left > 0) {
            quizNote := "'" quizLastName "' 을(를) 눌렀습니다. " left "초 뒤에 넘깁니다."
            return
        }

        ; 누른 답에 오답 표시가 붙었고, 아직 안 눌러 본 답이 있으면 그것을 누른다
        ;   (틀린 채로 넘기면 그 페이지가 진도에 들어가지 않는 사이트가 있다. 산업안전포털)
        if (quizLastKey != "" && QuizAnswerWrong(root, quizLastKey)) {
            el := FindQuizAnswer(root, quizTried)

            if el {
                ObjRelease(el)
                quizTries -= 1          ; 오답이라 다시 누르는 것은 '넘기기 실패' 로 세지 않는다
                quizStep := 0
                quizNote := "'" quizLastName "' 은(는) 오답입니다. 다른 답을 누릅니다."
                return
            }
        }

        ; 1) 퀴즈 안에 확인 / 제출 / 다음 같은 버튼이 있으면 그것 (페이지 '다음' 보다 먼저)
        nxInside := false
        el := FindNextLike(root, &nxInside)

        if (el && nxInside) {
            label := Trim(U_Str(el, 23))
            how := PressElement(el)
            ObjRelease(el)
            el := 0

            if (how != "")
                return QuizAdvanced("'" SubStr(label, 1, 20) "'")
        }

        ; 2) 프로필에 적힌 것 (페이지의 '다음' 등)
        for name in StrSplit(P("문제풀이", "푼뒤누를것", "다음 || 풍선"), "||") {
            name := Trim(name)

            if (name != "" && PressByName(root, name)) {
                if el
                    ObjRelease(el)

                return QuizAdvanced("'" name "'")
            }
        }

        ; 3) 퀴즈 밖의 다음 / next 같은 이름의 버튼
        if el {
            label := Trim(U_Str(el, 23))
            how := PressElement(el)
            ObjRelease(el)

            if (how != "")
                return QuizAdvanced("'" SubStr(label, 1, 20) "'")
        }

        ; 아직 안 떴으면 기다린다 (30초 넘게 안 뜨면 처음부터 한 번 더)
        if (A_TickCount - quizTick > 30000)
            quizStep := 0

        quizNote := "넘길 버튼이 뜨기를 기다립니다."
        return
    }

    ; 넘겼는데 8초가 지나도 퀴즈가 그대로면 처음부터 한 번 더
    if (quizStep = 2 && A_TickCount - quizTick >= 8000)
        quizStep := 0
}

QuizAdvanced(what)
{
    global quizStep, quizTick, pressCount, holdUntil, quizNote

    quizStep := 2
    quizTick := A_TickCount
    pressCount += 1
    holdUntil := A_TickCount + 5000
    quizNote := what " 을(를) 눌러 넘겼습니다."
}

; 한 번 못 찾았다고 바로 포기하지 않는다 (화면이 바뀌는 중일 수 있음)
QuizFailOnce(st, why)
{
    global quizFail, quizStuck, quizNote, quizWhy

    ; 페이지가 막 뜬 직후에는 몇 초 동안 '아직 누를 수 없음' 이 나므로 10초는 기다려 준다
    if !quizFail
        quizFail := A_TickCount

    waited := (A_TickCount - quizFail) // 1000
    quizNote := why " 다시 해 봅니다. (" waited "초째)"

    if (waited >= 10) {
        quizStuck := true
        quizWhy := why
        QuizNeedsPerson(st, why)
    }
}

; 자동으로 못 넘긴 퀴즈 → 예전처럼 사람에게 알린다 (5분마다)
QuizNeedsPerson(st, why)
{
    global lastQuizBeep, quizNote

    quizNote := why " 직접 풀어 주세요."

    if (A_TickCount - lastQuizBeep > 300000) {
        lastQuizBeep := A_TickCount
        Notify("문제풀이를 자동으로 넘기지 못했습니다. " why
            . (st.pageTotal > 0 ? " (" st.pageCur " / " st.pageTotal " 페이지)" : "")
            . "`n" st.quizDesc)
    }
}

QuizWaitSec()
{
    global editQuizWait

    v := IsObject(editQuizWait) ? Trim(editQuizWait.Value) : "3"

    if !IsInteger(v)
        return 3

    n := Integer(v)

    return (n < 1) ? 1 : (n > 60 ? 60 : n)
}

; 퀴즈가 사라지면 다음 퀴즈를 위해 비워 둔다
ResetQuiz()
{
    global quizStep, quizTries, quizStuck, quizNote, quizPage, quizFail, quizWhy, quizStarted
    global quizTried, quizLastKey, quizLastName

    quizTried := Map()
    quizLastKey := "", quizLastName := ""
    quizWhy := ""
    quizStarted := false
    ResetForce()
    quizStep := 0
    quizTries := 0
    quizFail := 0
    quizStuck := false
    quizNote := ""
    quizPage := -1
}

; --------------------------------------------------
; 퀴즈에서 누를 답 하나 (사용 후 ObjRelease). 못 찾으면 0
; --------------------------------------------------
FindQuizAnswer(root, tried := "")
{
    sel := P("문제풀이", "보기")

    if (sel != "") {
        hit := 0

        ; 프로필의 보기 가운데 아직 안 눌러 본 첫 번째 (O 가 오답이면 X)
        for el in FindAllSel(root, sel) {
            if (!hit && U_HasSize(el) && !(IsObject(tried) && tried.Has(AnswerKey(el))))
                hit := el
            else
                ObjRelease(el)
        }

        if hit
            return hit
    }

    return FindAnyAnswer(root, tried)
}

; 답 하나를 알아보는 열쇠: 이름 + 자리. 누른 뒤 class 가 바뀌어도(check wrong) 같은 답으로 본다
AnswerKey(el)
{
    r := Buffer(16, 0)
    try ComCall(43, el, "ptr", r)

    return Trim(U_Str(el, 23)) "@" NumGet(r, 0, "int") "," NumGet(r, 4, "int")
}

; 마지막으로 누른 답에 오답 표시가 붙었는지 ([문제풀이] 오답표시, class·이름에서 찾는 정규식)
QuizAnswerWrong(root, key)
{
    static cond := 0

    if !cond {
        for ct in [50000, 50013, 50002, 50005, 50007] {
            c := U_CondInt(30003, ct)
            cond := cond ? U_Or(cond, c) : c
        }
    }

    pat := "i)" P("문제풀이", "오답표시", "\bwrong\b|incorrect|오답|틀렸")
    wrong := false

    for el in U_FindAll(root, cond) {
        if (!wrong && AnswerKey(el) = key && RegExMatch(U_Str(el, 30) " " U_Str(el, 23), pat))
            wrong := true

        ObjRelease(el)
    }

    return wrong
}

; 규칙에 맞는 요소 모두 (웹페이지 안에서만). 사용 후 하나씩 ObjRelease
FindAllSel(root, sel)
{
    out := []

    for alt in StrSplit(sel, "||") {
        terms := []

        for piece in StrSplit(Trim(alt), "&&") {
            t := ParseTerm(Trim(piece))

            if IsObject(t)
                terms.Push(t)
        }

        if !terms.Length
            continue

        cond := U_Cond(terms[1].prop, terms[1].val, terms[1].exact)

        if !cond
            continue

        for el in U_FindAll(root, cond) {
            ok := true

            Loop terms.Length - 1
                if !TermMatch(el, terms[A_Index + 1]) {
                    ok := false
                    break
                }

            if (ok && InWebPage(el))
                out.Push(el)
            else
                ObjRelease(el)
        }

        ObjRelease(cond)
    }

    return out
}

; 일반 규칙으로 '아무 답이나' 고른다.
;   누를 수 있는 것 가운데 점수가 가장 높은 것
;     퀴즈로 알아본 영역 안에 있음 +100 / 라디오·체크 +60
;     이름이 O·X·1~9·①~⑨·예·아니오 처럼 생김 +60 / class·id 에 quiz·answer·choice·ox 등 +50
;   재생·다음·이전·닫기 같은 조작 버튼과 프로필의 버튼은 누르지 않는다.
;   링크는 퀴즈 영역 안에 있을 때만 (다른 페이지로 가 버릴 수 있으므로)
;   점수가 50 이 안 되면 아무것도 누르지 않는다 (엉뚱한 것을 누르지 않게)
FindAnyAnswer(root, tried := "")
{
    static cond := 0

    if !cond {
        for ct in [50000, 50013, 50002, 50005, 50007] {        ; 버튼, 라디오, 체크, 링크, 목록항목
            c := U_CondInt(30003, ct)
            cond := cond ? U_Or(cond, c) : c
        }
    }

    quizRect := QuizArea(root)
    scopeRect := PlayerRect(root)
    scope := ReadScope(root)
    box := scope ? scope : root
    controls := ProfileControls(root)

    best := 0
    bestScore := -1

    for el in U_FindAll(box, cond) {
        score := (IsObject(tried) && tried.Has(AnswerKey(el))) ? -1 : AnswerScore(el, quizRect, scopeRect, controls)

        if (score > bestScore) {
            if best
                ObjRelease(best)

            best := el
            bestScore := score
        } else {
            ObjRelease(el)
        }
    }

    for c in controls
        ObjRelease(c)

    if scope
        ObjRelease(scope)

    if (best && bestScore < 50) {
        ObjRelease(best)
        best := 0
    }

    return best
}

AnswerScore(el, quizRect, scopeRect, controls)
{
    static answerLike := "i)^\s*(O|X|○|×|[1-9]|[①-⑨]|예|아니오|맞다|틀리다|참|거짓)\s*[.)]?\s*$"
    static quizLike := "i)quiz|answer|choice|\box\b|ox_|보기|정답|문항|select|option"

    if !U_HasSize(el)          ; 크기가 없는 것은 빼고, 스크롤 밖에 있는 것은 받는다 (코드로는 눌린다)
        return -1

    for c in controls
        if U_Same(el, c)
            return -1

    name := Trim(U_Str(el, 23))

    if IsControlWord(name)
        return -1

    ct := U_Int(el, 21)

    if IsBigElement(el, scopeRect)
        return -1

    inside := InQuizArea(el, quizRect, scopeRect)

    if (ct = 50005 && !inside)
        return -1

    score := 0

    if inside
        score += 100

    if (ct = 50013 || ct = 50002)
        score += 60

    if RegExMatch(name, answerLike)
        score += 60

    if RegExMatch(U_Str(el, 30) " " U_Str(el, 29), quizLike)
        score += 50

    if U_IsShown(el)
        score += 10

    return score
}

; 퀴즈가 끝난 뒤 누를 '다음 / next / 확인' 같은 것 (사용 후 ObjRelease). 없으면 0
FindNextLike(root, &inside := false)
{
    static cond := 0
    ; 버튼 이름이 이 낱말로 '시작' 해야 한다 (문제 글 "다음 중 옳은 것은?" 을 다음 버튼으로 착각하지 않게)
    static nextStart := "i)^\W*(다음|next|확인|제출|계속|진행|넘어가기|완료|continue|submit|ok)"
    static notWords := "i)이전|prev|닫기|close|처음|다시|replay|다음\s*중"

    if !cond {
        for ct in [50000, 50026, 50005] {                       ; 버튼, 묶음(풍선), 링크
            c := U_CondInt(30003, ct)
            cond := cond ? U_Or(cond, c) : c
        }
    }

    quizRect := QuizArea(root)
    scopeRect := PlayerRect(root)
    scope := ReadScope(root)
    box := scope ? scope : root
    hit := 0, hitRank := -1
    inside := false

    ; 조작 줄의 '다음페이지' 보다 퀴즈 상자 안의 '확인' 을 먼저
    ; 스크롤 밖에 있는 버튼도 코드로는 눌리므로 받는다
    for el in U_FindAll(box, cond) {
        name := Trim(U_Str(el, 23))

        ct := U_Int(el, 21)
        bubble := InStr(name, "클릭하세요") || InStr(name, "이동하세요")      ; '버튼을 클릭하세요' 풍선

        ; 짧은 이름이 넘기는 낱말로 시작하거나 풍선 문구. 묶음(글상자)은 풍선일 때만
        isNext := name != "" && StrLen(name) <= 20 && !RegExMatch(name, notWords)
            && (RegExMatch(name, nextStart) || bubble) && (ct != 50026 || bubble)

        if (isNext && U_HasSize(el)) {
            pat := 0
            try ComCall(16, el, "int", 10018, "ptr*", &pat)      ; 누를 수 있는 것만

            if pat {
                ObjRelease(pat)
                ; 버튼 > 퀴즈 상자 안 > 화면에 보임
                isIn := InQuizArea(el, quizRect, scopeRect)
                rank := (ct = 50000 ? 4 : 0) + (isIn ? 2 : 0) + (U_IsShown(el) ? 1 : 0)

                if (rank > hitRank) {
                    if hit
                        ObjRelease(hit)

                    hit := el, hitRank := rank, inside := isIn
                    continue
                }
            }
        }

        ObjRelease(el)
    }

    if scope
        ObjRelease(scope)

    return hit
}

; 퀴즈 영역 {l, t, r, b}. 없으면 ""
;   class·id 에 퀴즈 낱말이 붙은 요소를 모두 합친 범위
;   (제목 한 줄만 잡히면 보기들이 '밖' 으로 판정되므로, 너무 작으면 없는 것으로 보고
;    대신 플레이어에서 조작 줄을 뺀 곳을 쓴다)
QuizArea(root)
{
    area := ""

    for word in StrSplit(P("문제풀이", "class키워드"), "|") {
        word := Trim(word)

        if (word = "")
            continue

        for term in ["class:", "id:"] {
            cond := U_Cond(term = "class:" ? 30012 : 30011, word)

            if !cond
                continue

            for el in U_FindAll(root, cond) {
                if U_HasSize(el) {
                    r := Buffer(16, 0)
                    try ComCall(43, el, "ptr", r)
                    l := NumGet(r, 0, "int"), t := NumGet(r, 4, "int"), rr := NumGet(r, 8, "int"), bb := NumGet(r, 12, "int")

                    if !IsObject(area)
                        area := {l: l, t: t, r: rr, b: bb}
                    else
                        area := {l: Min(area.l, l), t: Min(area.t, t), r: Max(area.r, rr), b: Max(area.b, bb)}
                }

                ObjRelease(el)
            }

            ObjRelease(cond)
        }
    }

    if !IsObject(area)
        return ""

    ; 너무 작으면 (플레이어의 15% 미만) 믿지 않는다
    scope := ReadScope(root)

    if scope {
        sr := Buffer(16, 0)
        try ComCall(43, scope, "ptr", sr)
        ObjRelease(scope)

        full := (NumGet(sr, 8, "int") - NumGet(sr, 0, "int")) * (NumGet(sr, 12, "int") - NumGet(sr, 4, "int"))
        mine := (area.r - area.l) * (area.b - area.t)

        if (full > 0 && mine * 100 < full * 15)
            return ""
    }

    return area
}

; 플레이어 문서의 자리 {l, t, r, b}. 없으면 ""
PlayerRect(root)
{
    scope := ReadScope(root)

    if !scope
        return ""

    sr := Buffer(16, 0)
    try ComCall(43, scope, "ptr", sr)
    ObjRelease(scope)

    return {l: NumGet(sr, 0, "int"), t: NumGet(sr, 4, "int"), r: NumGet(sr, 8, "int"), b: NumGet(sr, 12, "int")}
}

; 퀴즈 영역 안인지. 영역을 모르면 플레이어에서 아래쪽 조작 줄(14%)을 뺀 곳을 퀴즈 영역으로 본다
InQuizArea(el, quizRect, scopeRect)
{
    if IsObject(quizRect)
        return CenterInside(el, quizRect)

    if !IsObject(scopeRect)
        return false

    r := Buffer(16, 0)
    try ComCall(43, el, "ptr", r)
    cx := (NumGet(r, 0, "int") + NumGet(r, 8, "int")) // 2
    cy := (NumGet(r, 4, "int") + NumGet(r, 12, "int")) // 2

    return (cx >= scopeRect.l && cx <= scopeRect.r && cy >= scopeRect.t
        && cy < scopeRect.b - (scopeRect.b - scopeRect.t) * 14 // 100)
}

; 플레이어의 40% 가 넘는 큰 요소 (영상 화면, 큰 틀). 잘못 누르면 재생·멈춤이 바뀌므로 누르지 않는다
IsBigElement(el, scopeRect)
{
    if !IsObject(scopeRect)
        return false

    r := Buffer(16, 0)
    try ComCall(43, el, "ptr", r)
    mine := (NumGet(r, 8, "int") - NumGet(r, 0, "int")) * (NumGet(r, 12, "int") - NumGet(r, 4, "int"))
    full := (scopeRect.r - scopeRect.l) * (scopeRect.b - scopeRect.t)

    return (full > 0 && mine * 100 > full * 40)
}

CenterInside(el, rc)
{
    r := Buffer(16, 0)
    try ComCall(43, el, "ptr", r)

    cx := (NumGet(r, 0, "int") + NumGet(r, 8, "int")) // 2
    cy := (NumGet(r, 4, "int") + NumGet(r, 12, "int")) // 2

    return (cx >= rc.l - 4 && cx <= rc.r + 4 && cy >= rc.t - 4 && cy <= rc.b + 4)
}

; 프로필 [누를것] 의 버튼들 (재생·다음 등은 답으로 누르면 안 된다). 사용 후 각각 ObjRelease
ProfileControls(root)
{
    global prof

    list := []

    if (IsObject(prof) && prof.Has("누를것")) {
        for k, v in prof["누를것"] {
            if (Trim(v) = "")
                continue

            el := FindSel(root, v)

            if el
                list.Push(el)
        }
    }

    return list
}

; 플레이어 조작 버튼에 흔히 붙는 이름
IsControlWord(name)
{
    static words := "i)재생|일시정지|정지|다시보기|자막|소리|볼륨|음소거|전체\s*화면|배속|속도|목차|인덱스|잠금"
        . "|이전|다음|닫기|확대|축소|설정|도움말|로그아웃|메뉴|play|pause|mute|volume|fullscreen|prev|next|close"

    return (name != "" && RegExMatch(name, words))
}

; --------------------------------------------------
; 퀴즈를 보통 방법으로 못 넘겼을 때, 누를 수 있는 것을 차례로 눌러서라도 넘기기 (설정에서 켰을 때)
;
; 시간차(답 누르고 넘기기까지 초)를 두고 하나씩 누른다.
;   먼저 퀴즈 상자 안의 것 (시작 버튼, 보기), 그다음 확인·다음 같은 넘기는 버튼,
;   다 눌러 봤으면 페이지의 '다음'.
; 재생 막대·소리·자막·전체화면·목차·이전·나가기·좋아요·별점 같은 것은 누르지 않는다.
; 화면(문제)이 바뀌면 처음부터 다시 시도한다. 30번 눌러도 안 넘어가면 사람에게 알린다.
; --------------------------------------------------
ForceQuiz(root, st)
{
    global forceTried, forceCount, forceTick, forceLastKey, forceGaveUp, forceActive
    global quizNote, quizWhy, pressCount

    forceActive := true
    wait := QuizWaitSec() * 1000

    if (forceTick && A_TickCount - forceTick < wait) {
        left := (wait - (A_TickCount - forceTick)) // 1000 + 1
        quizNote := "누를 수 있는 것을 차례로 누르는 중. " forceCount "번 눌렀고 " left "초 뒤에 다음 것."
        return
    }

    if (forceCount >= 30) {
        forceGaveUp := true
        forceActive := false
        quizWhy := "누를 수 있는 것을 30번 눌러 봤지만 넘어가지 않았습니다."
        return QuizNeedsPerson(st, quizWhy)
    }

    label := ""
    el := PickForceTarget(root, &label)

    if el {
        how := PressElement(el)
        ObjRelease(el)
        forceCount += 1
        forceTick := A_TickCount
        quizNote := "'" (label != "" ? SubStr(label, 1, 20) : "이름 없는 버튼") "' 을(를) 눌렀습니다"
            . (how = "" ? " (안 눌림)" : "") ". (" forceCount "번째)"
        return
    }

    ; 퀴즈 안에서 누를 것이 다 떨어졌으면 페이지의 '다음' 을 누르고 처음부터
    for name in StrSplit(P("문제풀이", "푼뒤누를것", "다음 || 풍선"), "||") {
        name := Trim(name)

        if (name != "" && PressByName(root, name)) {
            forceTried := Map()
            forceLastKey := ""
            forceCount += 1
            forceTick := A_TickCount
            pressCount += 1
            quizNote := "'" name "' 을(를) 눌렀습니다. (" forceCount "번째)"
            return
        }
    }

    forceTried := Map()
    forceTick := A_TickCount
    quizNote := "누를 것을 찾지 못했습니다. 잠시 뒤 다시 찾습니다."
}

; 다음에 누를 것 하나 (사용 후 ObjRelease). label 에 이름을 돌려준다. 없으면 0
PickForceTarget(root, &label)
{
    global forceTried, forceSig, forceLastKey

    static cond := 0

    if !cond {
        ; 버튼, 라디오, 체크, 링크, 목록항목, 묶음, 사용자정의, 글자, 그림
        for ct in [50000, 50013, 50002, 50005, 50007, 50026, 50025, 50020, 50006] {
            c := U_CondInt(30003, ct)
            cond := cond ? U_Or(cond, c) : c
        }
    }

    quizRect := QuizArea(root)
    scope := ReadScope(root)
    box := scope ? scope : root
    controls := ProfileControls(root)
    scopeRect := PlayerRect(root)

    cands := []
    sig := ""

    for el in U_FindAll(box, cond) {
        key := "", isNext := false
        rank := ForceRank(el, quizRect, scopeRect, controls, &key, &isNext)

        if (rank < 0) {
            ObjRelease(el)
            continue
        }

        cands.Push({el: el, rank: rank, key: key, isNext: isNext, name: Trim(U_Str(el, 23))})
        sig .= key "`n"
    }

    for c in controls
        ObjRelease(c)

    if scope
        ObjRelease(scope)

    ; 화면(문제)이 바뀌었으면 처음부터 다시 시도
    if (sig != forceSig) {
        forceSig := sig
        forceTried := Map()
    }

    best := ""

    for c in cands {
        ; 보기 같은 것은 한 번씩만, 넘기는 버튼은 바로 전에 누른 것만 아니면 또 눌러도 된다
        usable := c.isNext ? (c.key != forceLastKey) : !forceTried.Has(c.key)

        if (usable && (!IsObject(best) || c.rank > best.rank))
            best := c
    }

    for c in cands
        if (!IsObject(best) || c.el != best.el)
            ObjRelease(c.el)

    if !IsObject(best)
        return 0

    if !best.isNext
        forceTried[best.key] := true

    forceLastKey := best.key
    label := best.name

    return best.el
}

ForceRank(el, quizRect, scopeRect, controls, &key, &isNext)
{
    ; 앞뒤가 다른 영어 글자와 붙어 있지 않을 때만 (quiz_start_btn 의 'star' 같은 것에 걸리지 않게)
    static avoid := "i)(?<![a-z])(time-bar|timebar|progress|slider|seek|volume|sound|mute|script|subtitle|caption"
        . "|full|fullscreen|index|prev|btn_out|logout|heart|like|star|rate|speed|jog|toggle|menu|close"
        . "|video|videoplayer|player|print|down|download)(?![a-z])"
    static nextStart := "i)^\W*(다음|next|확인|제출|계속|진행|완료|submit|ok)"

    if !U_HasSize(el)
        return -1

    ; 코드로 '누를 수 있는' 것만 (브라우저가 클릭 동작을 붙여 둔 요소)
    pat := 0
    try ComCall(16, el, "int", 10000, "ptr*", &pat)          ; InvokePattern

    if !pat
        return -1

    ObjRelease(pat)

    for c in controls
        if U_Same(el, c)
            return -1

    name := Trim(U_Str(el, 23))
    cls := U_Str(el, 30)
    id := U_Str(el, 29)
    ct := U_Int(el, 21)

    if RegExMatch(cls " " id, avoid)
        return -1

    if IsBigElement(el, scopeRect)
        return -1

    ; 퀴즈 상자를 알면 그 안, 모르면 플레이어 아래쪽 조작 줄을 뺀 곳을 '안' 으로 본다
    r := Buffer(16, 0)
    try ComCall(43, el, "ptr", r)
    inside := InQuizArea(el, quizRect, scopeRect)

    ; 밖에서는 조작 버튼이 아닌, 이름 있는 버튼만
    if (!inside && !(ct = 50000 && name != "" && !IsControlWord(name)))
        return -1

    isNext := (name != "" && StrLen(name) <= 20 && RegExMatch(name, nextStart))

    rank := (inside ? 100 : 0)
        + ((ct = 50013 || ct = 50002) ? 30 : 0)
        + (ct = 50000 ? 20 : 0)
        + (U_IsShown(el) ? 5 : 0)
        - (isNext ? 10 : 0)                ; 같은 조건이면 보기를 먼저, 넘기는 버튼은 그다음

    key := name "|" cls "|" id "|" (NumGet(r, 4, "int") // 20)

    return rank
}

ResetForce()
{
    global forceTried, forceCount, forceTick, forceLastKey, forceSig, forceGaveUp, forceActive

    forceTried := Map()
    forceCount := 0
    forceTick := 0
    forceLastKey := ""
    forceSig := ""
    forceGaveUp := false
    forceActive := false
}

; --------------------------------------------------
; 차시 목록 읽기 (전체 몇 차시인지, 어디까지 들었는지)
;
;   목록이 학습창 안에 있으면 그대로, 따로 뜨는 학습목록 창이면 그 창에서 읽는다.
;   ([차시] 목록창 = 학습창   또는   목록 창 제목의 일부)
;   읽기만 한다. 창을 닫거나 페이지를 옮기지 않는다.
; --------------------------------------------------
SessionListHwnd()
{
    global pinnedListHwnd

    ; 본체 창에서 직접 고른 창이 있으면 그 창만 쓴다
    if pinnedListHwnd {
        if WinExist("ahk_id " pinnedListHwnd)
            return pinnedListHwnd

        pinnedListHwnd := 0          ; 그 창이 닫혔으면 자동으로 되돌림
    }

    where := P("차시", "목록창", "학습창")

    return (where = "" || where = "학습창") ? GetLectureWindow() : FindLectureWindow(where, true)
}

ScanSessions(report := false)
{
    global sessionInfo, sessionTotal

    rule := P("차시", "차시링크")

    if (rule = "") {
        if report
            ShowSessionInfo("이 사이트 프로필에는 차시 목록 규칙이 없습니다."
                . "`n프로필의 [차시] 칸에 차시링크 를 적어야 합니다. (설정 → 프로필 편집)")

        return []
    }

    ; 진도(학습현황) 창이 따로 있으면 거기서 읽는다.
    ; 차시마다 학습 시간이 나와 있어 어디까지 들었는지까지 알 수 있다.
    global pinnedListHwnd

    hwnd := 0
    where := P("차시", "진도창")

    ; 직접 고른 창이 가장 먼저
    if (pinnedListHwnd && WinExist("ahk_id " pinnedListHwnd))
        hwnd := pinnedListHwnd
    else if (where != "")
        hwnd := FindLectureWindow(where, true)          ; 최소화돼 있어도 읽는다

    if !hwnd
        hwnd := SessionListHwnd()

    if !hwnd {
        if report
            ShowSessionInfo("차시 목록이 있는 창을 찾지 못했습니다."
                . "`n'" (where != "" ? where : P("차시", "목록창", "학습창")) "' 이(가) 들어간 창을 열어 두고 다시 눌러 보세요.")

        return []
    }

    root := 0
    try ComCall(6, UIA(), "ptr", hwnd, "ptr*", &root)

    if !root
        return []

    rows := SessionRows(root, rule)

    ; 목록이 접혀 있으면 아예 안 읽힌다 → 목록 버튼을 눌러 펼치고 다시 찾는다
    if (!rows.Length && P("차시", "목록열기") != "") {
        opener := FindSel(root, P("차시", "목록열기"))

        if opener {
            PressElement(opener)
            ObjRelease(opener)
            Sleep 1500
            rows := SessionRows(root, rule)
        }
    }

    KeepSessions(rows)

    for row in rows
        ObjRelease(row.el)

    ObjRelease(root)

    if report
        ShowSessionInfo(SessionReport())

    return sessionInfo
}

; 읽은 줄들을 {번호, 이름, 학습시간, 들었는지} 로 남겨 둔다
KeepSessions(rows)
{
    global sessionInfo, sessionTotal

    if !rows.Length
        return

    list := []

    for row in rows
        list.Push({num: row.num, name: RegExReplace(Trim(row.name), "\s+", " "), time: row.time,
            done: (row.time != "" && !RegExMatch(row.time, "^[0:]+$"))})

    sessionInfo := list
    sessionTotal := list.Length
}

; 사람이 보도록 차시 목록을 적는다
SessionReport()
{
    global sessionInfo, sessionTotal, sessionNum

    if !sessionTotal
        return "차시를 하나도 못 읽었습니다."
            . "`n차시 목록이 보이는 창을 열어 두고 다시 눌러 보세요."
            . "`n(목록이 접혀 있으면 프로필의 [차시] 목록열기 에 펼치는 버튼을 적어 주세요)"

    doneN := 0
    knowTime := false

    for it in sessionInfo {
        if it.done
            doneN += 1

        if (it.time != "")
            knowTime := true
    }

    lines := ["전체 " sessionTotal "차시"
        . (knowTime ? "   ·   들은 것 " doneN "   ·   남은 것 " (sessionTotal - doneN) : "")
        . (sessionNum > 0 ? "   ·   지금 " sessionNum "차시" : "")
        . (LastSessionLimit() > 0 ? "   ·   " LastSessionLimit() "차시까지만" : "")]

    for it in sessionInfo
        lines.Push(Format("{:2}", it.num) "차시  "
            . (it.time != "" ? (it.done ? "들음   " : "안 들음 ") it.time "  " : "")
            . SubStr(it.name, 1, 26))

    return Join(lines, "`n")
}

ShowSessionInfo(text)
{
    global txtSessionInfo

    if IsObject(txtSessionInfo)
        txtSessionInfo.Value := text
}

; 몇 차시까지 들을지 (0 이면 끝까지)
LastSessionLimit()
{
    global editLastSession

    v := IsObject(editLastSession) ? Trim(editLastSession.Value) : ""

    return IsInteger(v) ? Integer(v) : 0
}

; --------------------------------------------------
; 차시(강의) 하나가 끝나면 다음 차시로 (설정에서 켰을 때)
;
;   차시 목록이 학습창 안에 있으면 그 줄을 누르고,
;   따로 있는 목록 창에 있으면 학습창을 닫고 그 창에서 누른다.
;   지금 차시 번호를 알면 그 다음 번호, 모르면 학습 시간이 00:00:00 인 첫 줄.
;   더 들을 차시가 없으면 알리고 멈춘다.
; --------------------------------------------------
GoNextSession(st)
{
    global lectureHwnd, pinnedHwnd, pinnedListHwnd, sessionNum, holdUntil, sessionTried, sessionInfo, sessionTotal
    global sessionPct

    rule := P("차시", "차시링크")

    if (rule = "")
        return false

    listWhere := P("차시", "목록창", "학습창")
    sameWindow := (listWhere = "" || listWhere = "학습창")

    ; 본체 창에서 차시 목록 창을 직접 골랐으면 그 창에서 누른다
    if (pinnedListHwnd && WinExist("ahk_id " pinnedListHwnd)) {
        listHwnd := pinnedListHwnd
        sameWindow := (listHwnd = GetLectureWindow())

        if !sameWindow
            CloseLectureWindow()
    } else if sameWindow {
        listHwnd := GetLectureWindow()
    } else {
        listHwnd := FindLectureWindow(listWhere)

        if !listHwnd {
            Notify("다음 차시로 가려 했지만 목록 창을 찾지 못했습니다. ('" listWhere "' 이 들어간 창)")
            return false
        }

        CloseLectureWindow()
    }

    if !listHwnd
        return false

    ; 앞서 뜬 '사이트에서 나가시겠습니까?' 가 남아 있으면 페이지가 멈춰 있으므로 먼저 정리
    ConfirmLeaveDialog(listHwnd)

    root := 0
    try ComCall(6, UIA(), "ptr", listHwnd, "ptr*", &root)

    if !root
        return false

    rows := SessionRows(root, rule)

    ; 차시 목록이 접혀 있으면 아예 안 읽힌다 → 목록 버튼을 눌러 펼치고 다시 찾는다
    if (!rows.Length && P("차시", "목록열기") != "") {
        opener := FindSel(root, P("차시", "목록열기"))

        if opener {
            PressElement(opener)
            ObjRelease(opener)
            Sleep 1500
            rows := SessionRows(root, rule)
        }
    }

    ; 읽은 김에 전체 차시 수도 갱신
    ; (진도창이 따로 있으면 그쪽이 학습 시간까지 알려 주므로 덮어쓰지 않는다)
    if (P("차시", "진도창") = "")
        KeepSessions(rows)

    target := ""
    skipped := []

    ; 1) 지금 차시 다음 번호부터, 다 들은 차시(진도율 100)는 건너뛴다
    if (sessionNum > 0)
        for row in rows
            if (row.num > sessionNum) {
                if SessionDone(row.num) {
                    skipped.Push(row.num)
                    continue
                }

                target := row
                break
            }

    ; 2) 아직 안 들은 (학습 시간 0) 첫 줄
    if !IsObject(target)
        for row in rows
            if (row.time != "" && RegExMatch(row.time, "^0+:0+:0+$") && !sessionTried.Has(row.num) && !SessionDone(row.num)) {
                target := row
                break
            }

    ; 3) 차시 번호를 모르면, 다 듣지 않은 첫 줄 (진도율을 읽을 수 있는 사이트)
    if (!IsObject(target) && sessionNum <= 0 && sessionPct.Count)
        for row in rows
            if (!SessionDone(row.num) && !sessionTried.Has(row.num)) {
                target := row
                break
            }

    if !IsObject(target) {
        for row in rows
            ObjRelease(row.el)

        ObjRelease(root)
        Notify("모든 차시를 마쳤습니다. 더 들을 차시가 없습니다.")
        Stop("모든 차시를 마쳤습니다.")

        return true
    }

    ; 설정에서 '몇 차시까지' 를 정해 두었으면 거기서 멈춘다
    if (LastSessionLimit() > 0 && target.num > LastSessionLimit()) {
        limit := LastSessionLimit()

        for row in rows
            ObjRelease(row.el)

        ObjRelease(root)
        Notify("정해 두신 " limit "차시까지 다 들었습니다.")
        Stop(limit "차시까지 다 들었습니다. (설정 → 차시 → 어디까지)")

        return true
    }

    num := target.num

    ; 같은 창에서 누르는 경우, 영상 창(팝업)을 먼저 닫아야 하는 사이트 ([차시] 넘기기전 = [누를것] 이름)
    before := P("차시", "넘기기전")

    if (sameWindow && before != "") {
        if PressByName(root, before) {
            Sleep 2000

            ; 영상 창을 닫으면 화면이 새로 그려지므로, 차시 표를 다시 읽어 같은 번호의 버튼을 누른다
            fresh := SessionRows(root, rule)
            replaced := false

            for row in fresh {
                if (row.num = num && !replaced) {
                    ObjRelease(target.el)
                    target.el := row.el
                    replaced := true
                } else {
                    ObjRelease(row.el)
                }
            }
        } else {
            Notify("다음 차시로 가기 전에 '" before "' 을(를) 누르지 못했습니다. 영상 창을 직접 닫아 주세요.")
        }
    }

    how := PressElement(target.el)

    for row in rows
        ObjRelease(row.el)

    ObjRelease(root)

    if (how = "") {
        Notify(num "차시를 누르지 못했습니다. 직접 눌러 주세요.")
        return false
    }

    ; 누르면 '사이트에서 나가시겠습니까?' 가 뜨는 사이트가 있다
    Sleep 1000

    if ConfirmLeaveDialog(listHwnd)
        Sleep 1000

    sessionTried[num] := true
    sessionNum := num
    lectureHwnd := 0
    pinnedHwnd := sameWindow ? pinnedHwnd : 0
    holdUntil := A_TickCount + 10000          ; 새 강의가 뜰 때까지 잠깐
    ResetForProgress()
    global awaitFresh
    awaitFresh := A_TickCount
    skipNote := skipped.Length ? " (다 들은 " Join(skipped, "·") "차시는 건너뜀)" : ""
    Notify(num "차시로 넘어갑니다." skipNote, false)
    SetState(num "차시를 눌렀습니다." skipNote " 새 강의가 뜨기를 기다립니다.")

    return true
}

; 브라우저의 '사이트에서 나가시겠습니까?' 같은 확인 창에서 '나가기' 를 누른다.
; 차시를 옮기거나 학습창을 닫을 때 이 창이 뜨면 여기서 막히므로 반드시 처리해야 한다.
ConfirmLeaveDialog(hwnd)
{
    static cond := 0
    static words := "i)^(나가기|나감|확인|계속|OK|Leave|Reload|다시 로드)$"

    if !cond
        cond := U_CondInt(30003, 50000)          ; 버튼

    root := 0
    try ComCall(6, UIA(), "ptr", hwnd, "ptr*", &root)

    if !root
        return false

    hit := 0

    for el in U_FindAll(root, cond) {
        name := Trim(U_Str(el, 23))

        ; 브라우저가 띄운 대화상자의 버튼만 (웹페이지 안의 '확인' 이 아니라)
        if (!hit && InStr(U_Str(el, 30), "MdTextButton") && RegExMatch(name, words))
            hit := el
        else
            ObjRelease(el)
    }

    ObjRelease(root)

    if !hit
        return false

    PressElement(hit)
    ObjRelease(hit)
    Sleep 1000

    return true
}

; 차시 목록의 줄들: {num, time, el}
;   차시링크 규칙
;     무늬:정규식     이름에서 찾고, 그 안의 숫자가 차시 번호   예) 무늬:^(\d+)차시
;     id무늬:정규식   id 에서 찾는다                            예) id무늬:^list-group-item-(\d+)$
SessionRows(root, rule)
{
    ; 학습 시간 글자 (같은 줄인지는 y 로 맞춘다). 없으면 시간 없이
    times := []
    tRule := P("차시", "학습시간")
    tPat := (SubStr(tRule, 1, 3) = "무늬:") ? Trim(SubStr(tRule, 4)) : ""

    if (tPat != "") {
        for el in TextElements(root) {
            s := Trim(U_Str(el, 23))

            if (s != "" && RegExMatch(s, tPat)) {
                r := Buffer(16, 0)
                try ComCall(43, el, "ptr", r)
                times.Push({y: (NumGet(r, 4, "int") + NumGet(r, 12, "int")) // 2, text: s})
            }

            ObjRelease(el)
        }
    }

    ; 규칙은 || 로 여러 개 적을 수 있다. 앞에서부터 해 보고, 줄이 찾히는 규칙을 쓴다.
    ; (같은 사이트라도 창마다 차시 줄의 생김새가 다르다.
    ;  학습창은 id=list-group-item-2, 학습현황 창은 이름이 '2차시')
    for alt in StrSplit(rule, "||") {
        alt := Trim(alt)
        byId := false

        if (SubStr(alt, 1, 3) = "버튼:") {
            rows := SessionRowsByButton(root, Trim(SubStr(alt, 4)))

            if rows.Length
                return rows

            continue
        }

        if (SubStr(alt, 1, 5) = "id무늬:")
            pat := Trim(SubStr(alt, 6)), byId := true
        else if (SubStr(alt, 1, 3) = "무늬:")
            pat := Trim(SubStr(alt, 4))
        else
            continue

        rows := SessionRowsBy(root, pat, byId, times)

        if rows.Length
            return rows
    }

    return []
}

; 차시 줄마다 같은 이름의 버튼이 있는 표 (예: 산업안전포털의 '학습하기')
;   차시링크 = 버튼:class:takeLesson
;   같은 줄(높이가 같은) 글자에서  맨 왼쪽 숫자 = 차시 번호,  '40%' = 진도율,  가장 긴 글 = 차시 이름
SessionRowsByButton(root, sel)
{
    global sessionPct

    rows := []
    first := StrSplit(sel, "&&")[1]
    t := ParseTerm(Trim(first))

    if !IsObject(t)
        return rows

    cond := U_Cond(t.prop, t.val, t.exact)

    if !cond
        return rows

    btns := []

    for el in U_FindAll(root, cond) {
        ok := U_HasSize(el)

        for piece in StrSplit(sel, "&&") {
            if (A_Index = 1)
                continue

            tt := ParseTerm(Trim(piece))

            if (IsObject(tt) && !TermMatch(el, tt))
                ok := false
        }

        if ok
            btns.Push(el)
        else
            ObjRelease(el)
    }

    ObjRelease(cond)

    if !btns.Length
        return rows

    ; 같은 줄의 글: 글자와 표 칸 (표 칸의 글은 글자 요소가 아니라 칸 이름으로만 읽히는 사이트가 있다)
    static rowCond := 0

    if !rowCond
        rowCond := U_Or(U_CondInt(30003, 50020), U_CondInt(30003, 50029))

    texts := []

    for el in U_FindAll(root, rowCond) {
        s := Trim(StrReplace(StrReplace(U_Str(el, 23), "`n", " "), "`r", ""))

        if (s != "") {
            r := Buffer(16, 0)
            try ComCall(43, el, "ptr", r)

            if (NumGet(r, 8, "int") > NumGet(r, 0, "int"))
                texts.Push({x: NumGet(r, 0, "int"), y: (NumGet(r, 4, "int") + NumGet(r, 12, "int")) // 2, text: s
                    , cell: U_Int(el, 21) = 50029})
        }

        ObjRelease(el)
    }

    seen := Map()

    for el in btns {
        r := Buffer(16, 0)
        try ComCall(43, el, "ptr", r)
        y := (NumGet(r, 4, "int") + NumGet(r, 12, "int")) // 2
        bname := Trim(U_Str(el, 23))

        num := -1, numX := 0, pct := -1, name := ""

        ; 표 칸이 있는 줄이면 표 칸만 본다 (같은 높이에 뜬 안내창 글 등이 섞이지 않게)
        hasCell := false

        for tx in texts
            if (tx.cell && Abs(tx.y - y) <= 45)
                hasCell := true

        for tx in texts {
            if (Abs(tx.y - y) > 45 || (hasCell && !tx.cell))
                continue

            if RegExMatch(tx.text, "^\d{1,3}$") {
                if (num < 0 || tx.x < numX)
                    num := Integer(tx.text), numX := tx.x
            } else if RegExMatch(tx.text, "^(\d{1,3})\s*%$", &mp) {
                pct := Integer(mp[1])
            } else if (tx.text != bname && !RegExMatch(tx.text, "^[\d\s.:/\-]+$") && StrLen(tx.text) > StrLen(name)) {
                ; 날짜·시간·숫자만 있는 칸('2026.09.24 17:38:01', '-')은 이름이 아니다
                name := tx.text
            }
        }

        if (num < 1 || seen.Has(num)) {
            ObjRelease(el)
            continue
        }

        seen[num] := true
        rows.Push({num: num, time: "", name: name, y: y, el: el, pct: pct})

        if (pct >= 0)
            sessionPct[num] := pct
    }

    ; 번호 순으로
    loop Max(rows.Length - 1, 0) {
        i := A_Index

        loop rows.Length - i {
            j := A_Index

            if (rows[j].num > rows[j + 1].num) {
                tmp := rows[j]
                rows[j] := rows[j + 1]
                rows[j + 1] := tmp
            }
        }
    }

    return rows
}

; 한 가지 규칙으로 차시 줄 찾기
SessionRowsBy(root, pat, byId, times)
{
    global sessionPct

    static cond := 0

    if !cond {
        for ct in [50005, 50000, 50007] {          ; 링크, 버튼, 목록항목
            c := U_CondInt(30003, ct)
            cond := cond ? U_Or(cond, c) : c
        }
    }

    rows := []
    seen := Map()
    others := []          ; 차시 줄이 아닌 글자들 (같은 줄의 강의 제목을 찾는 데 쓴다)

    for el in U_FindAll(root, cond) {
        text := byId ? U_Str(el, 29) : Trim(U_Str(el, 23))
        keep := false
        name := Trim(U_Str(el, 23))
        r := Buffer(16, 0)
        try ComCall(43, el, "ptr", r)
        y := (NumGet(r, 4, "int") + NumGet(r, 12, "int")) // 2

        if (text != "" && RegExMatch(text, pat, &m) && RegExMatch(text, "(\d+)", &mn)) {
            num := Integer(mn[1])

            if (!seen.Has(num) && U_HasSize(el)) {
                seen[num] := true
                t := ""

                for tm in times
                    if (Abs(tm.y - y) <= 30)
                        t := tm.text

                rows.Push({num: num, time: t, name: name, y: y, el: el, pct: ReadSessionPct(el)})
                keep := true
            }
        } else if (name != "" && StrLen(name) <= 80) {
            others.Push({y: y, text: name})
        }

        if !keep
            ObjRelease(el)
    }

    ; 차시 줄 이름이 '2차시' 처럼 번호뿐이면, 같은 줄에 있는 강의 제목을 붙인다
    ;   (학습현황 창은 '2차시' 와 '바이브 코딩 패러다임 ...' 이 따로 있다)
    for row in rows {
        if !RegExMatch(row.name, "^\d+\s*(차시|강)?$")
            continue

        best := ""

        for o in others
            if (Abs(o.y - row.y) <= 20 && !RegExMatch(o.text, "^[\d:]+$") && o.text != "진도상세"
                && StrLen(o.text) > StrLen(best))
                best := o.text

        if (best != "")
            row.name := best
    }

    ; 다 들은 차시를 기억해 둔다 (같은 번호가 두 줄로 나뉘어 있으면 읽힌 쪽을 쓴다)
    for row in rows
        if (row.pct >= 0)
            sessionPct[row.num] := row.pct

    ; 번호 순으로
    loop Max(rows.Length - 1, 0) {
        i := A_Index

        loop rows.Length - i {
            j := A_Index

            if (rows[j].num > rows[j + 1].num) {
                tmp := rows[j]
                rows[j] := rows[j + 1]
                rows[j + 1] := tmp
            }
        }
    }

    return rows
}

; 차시 줄의 진도율 (0~100). 모르면 -1
;   [차시] 진도율 = class무늬:정규식   같은 목록항목 안에서 class 가 맞는 것을 찾고, 그 안의 숫자가 진도율
;   예) 지방자치인재개발원 학습창:  class="step p100" (다 들음) / "step p0" (안 들음)
ReadSessionPct(el)
{
    rule := P("차시", "진도율")

    if (SubStr(rule, 1, 7) != "class무늬:")
        return -1

    pat := Trim(SubStr(rule, 8))

    ; 차시 줄을 감싸는 목록항목까지 올라간다
    item := 0
    cur := U_Parent(el)

    Loop 4 {
        if !cur
            break

        if (U_Int(cur, 21) = 50007) {
            item := cur
            break
        }

        up := U_Parent(cur)
        ObjRelease(cur)
        cur := up
    }

    if !item {
        if cur
            ObjRelease(cur)

        return -1
    }

    static cond := 0

    if !cond
        cond := U_CondInt(30003, 50026)          ; 묶음 (div)

    pct := -1

    for c in U_FindAll(item, cond) {
        if (pct < 0 && RegExMatch(U_Str(c, 30), pat, &m))
            pct := Integer(m[1])

        ObjRelease(c)
    }

    ObjRelease(item)

    return pct
}

; 다 들은 차시인지 (학습창 목록의 진도율 100)
SessionDone(num)
{
    global sessionPct

    return sessionPct.Has(num) && sessionPct[num] >= 100
}

; 학습창 닫기 ([차시] 학습창닫기 → 없으면 창 자체를 닫는다)
CloseLectureWindow()
{
    global lectureHwnd

    hwnd := GetLectureWindow()

    if !hwnd
        return

    sel := P("차시", "학습창닫기")

    if (sel != "") {
        root := 0
        try ComCall(6, UIA(), "ptr", hwnd, "ptr*", &root)

        if root {
            el := FindSel(root, sel)

            if el {
                PressElement(el)
                ObjRelease(el)
            }

            ObjRelease(root)
        }

        Sleep 1500
    }

    if WinExist("ahk_id " hwnd) {
        try WinClose("ahk_id " hwnd)
        Sleep 800
        ConfirmLeaveDialog(hwnd)
    }

    Sleep 1000
    lectureHwnd := 0
}

; 새 차시를 시작할 때 진행 상태를 비운다
ResetForProgress()
{
    global lastTimeVal, lastTimeTick, lastTimeMovedTick, lastPageVal, doneNotified
    global staticPage, staticSince, quizLatchPage, videoWrapped

    lastTimeVal := -1
    lastTimeTick := 0
    lastTimeMovedTick := 0
    lastPageVal := -1
    doneNotified := false
    staticPage := -1
    staticSince := 0
    quizLatchPage := -1
    videoWrapped := false
    ResetQuiz()
}

; 지금 보고 있는 차시 번호 (학습창의 '1차시 : ...' 같은 글자에서)
ReadSessionNum(root)
{
    rule := P("읽을것", "차시")

    if (rule = "")
        return 0

    ; 제목:선택자  →  그 글이 차시 목록의 어느 줄 이름으로 시작하는지로 번호를 찾는다
    ;   (영상 제목에 번호가 없는 사이트. 예: 산업안전포털 '[인트로] 안전보건의 중요성')
    if (SubStr(rule, 1, 3) = "제목:") {
        global sessionInfo

        t := ReadRule(root, Trim(SubStr(rule, 4)))

        if (t = "")
            return 0

        best := 0, bestLen := 0

        for it in sessionInfo
            if (it.name != "" && InStr(t, it.name) && StrLen(it.name) > bestLen)
                best := it.num, bestLen := StrLen(it.name)

        return best
    }

    t := ReadRule(root, rule)

    return (t != "" && RegExMatch(t, "(\d+)", &m)) ? Integer(m[1]) : 0
}

; 무엇을 누를지 결정
Act(root, st)
{
    global holdUntil, pressCount, lastQuizBeep, doneNotified, lastTimeTick
    global chkNext, chkPlay, chkQuizBeep, chkEndClose, chkQuizAuto, quizGoneTick, staticPage, staticSince
    global chkNextSession, videoWrapped

    ; 0) 사이트가 띄운 안내창 ('다음 동영상 페이지를 학습하시겠습니까?' 등)
    if HandleNotice(root, st) {
        pressCount += 1
        holdUntil := A_TickCount + 5000

        return
    }

    ; 1) 문제풀이
    ;    '아무 답이나 누르고 넘어가기' 를 켰으면 자동으로, 아니면 건드리지 않고 알린다 (5분마다)
    if st.quiz {
        quizGoneTick := 0

        if chkQuizAuto.Value {
            AutoQuiz(root, st)
            return
        }

        if (A_TickCount - lastQuizBeep > 300000) {
            lastQuizBeep := A_TickCount
            Notify("문제풀이가 나왔습니다. 진행이 멈춰 있습니다."
                . (st.pageTotal > 0 ? " (" st.pageCur " / " st.pageTotal " 페이지)" : "")
                . "`n" st.quizDesc)
        }

        return
    }

    lastQuizBeep := 0          ; 문제풀이가 사라졌으면 다음 번에 바로 알리도록

    ; 퀴즈가 잠깐 안 읽혔다고 바로 비우지 않는다 (답을 누르는 순간 화면이 바뀌며 1초쯤 안 읽히기도 함)
    if !quizGoneTick
        quizGoneTick := A_TickCount
    else if (A_TickCount - quizGoneTick > 2500)
        ResetQuiz()

    ; 시간이 끝났거나, 끝나고 처음으로 되돌아갔으면 (존플레이어)
    ended := (st.timeTotal > 0 && st.timeCur >= st.timeTotal - 1) || videoWrapped || st.ended

    ; 차시를 넘긴 직후 2분 동안은, 새 영상이 도는 것을 보기 전의 '끝남' 은 지난 영상의 것으로 본다
    global awaitFresh

    if (awaitFresh && A_TickCount - awaitFresh < 120000)
        ended := false

    ; '끝남' 표시만 보고 판단할 때는 몇 초 기다린다. 끝나고 조금 뒤에 안내창이 뜨는 사이트가 있다
    ; (그 사이에 차시를 넘겨 버리면 남은 페이지를 못 듣는다)
    global endedSince

    if st.ended {
        if !endedSince
            endedSince := A_TickCount

        if (A_TickCount - endedSince < 8000 && !(st.timeTotal > 0 && st.timeCur >= st.timeTotal - 1) && !videoWrapped)
            ended := false
    } else {
        endedSince := 0
    }

    pagesKnown := (st.pageTotal > 0)
    last := pagesKnown && (st.pageCur >= st.pageTotal)

    ; 영상도 퀴즈도 없는 페이지 (요약·인쇄 페이지 등): 10초 보고 끝난 것으로 친다
    if (st.timeCur < 0 && st.pageTotal > 0) {
        if (st.pageCur != staticPage) {
            staticPage := st.pageCur
            staticSince := A_TickCount
        }

        if (A_TickCount - staticSince >= 10000)
            ended := true
    } else {
        staticPage := -1
    }

    ; 2) 영상이 끝났는데 아직 남은 페이지가 있으면 다음
    ;    페이지 수를 못 읽는 사이트(차시 하나가 영상 한 편)는 눌러 보고,
    ;    누를 '다음' 이 없으면 그것으로 이 차시가 끝난 것으로 본다
    if (ended && !last && chkNext.Value && P("동작", "영상끝나면") != "") {
        if PressByName(root, P("동작", "영상끝나면")) {
            pressCount += 1
            holdUntil := A_TickCount + 6000

            return
        }

        if !pagesKnown
            last := true
    }

    ; 3) 마지막 페이지까지 다 봤으면
    if (ended && last) {
        ; 설정에서 켰으면 다음 차시로 넘어간다
        if (chkNextSession.Value && P("차시", "차시링크") != "" && GoNextSession(st))
            return

        if !doneNotified {
            doneNotified := true
            Notify("강의를 모두 마쳤습니다. (" st.pageCur " / " st.pageTotal " 페이지)")
        }

        if (chkEndClose.Value && P("동작", "강의끝나면") != "") {
            if PressByName(root, P("동작", "강의끝나면")) {
                holdUntil := A_TickCount + 8000
                Stop("강의를 마치고 '" P("동작", "강의끝나면") "' 을(를) 눌렀습니다.")
            }
        } else {
            Stop("강의를 모두 마쳤습니다. (" st.pageCur " / " st.pageTotal " 페이지)")
        }

        return
    }

    ; 4) 멈춰 있으면 다시 재생
    ; 반드시 '재생 시간이 실제로 멈춰 있을 때' 만 누른다.
    ; 그래야 상태를 잘못 읽어도 재생 중인 영상을 눌러서 세우는 일이 없다.
    ;   재생 상태를 알려 주는 사이트  : 그 상태가 '멈춤' 이고 시간도 멈춰 있을 때
    ;   알려 주지 않는 사이트 (전환식) : 시간이 흐르지 않을 때 누르고, 그래도 안 흐르면 한 번 더
    ;     (지방자치인재개발원: '다음' 뒤 자동 재생이 막혀 한두 번 눌러야 재생됨)
    ;   창이 완전히 가려져 화면이 멈춘 것일 수 있으면 누르지 않는다 (잘 돌던 영상을 세우지 않게)
    global covered

    isPaused := st.playKnown ? !st.playing : (st.timeCur >= 0 && !TimeMoving())

    if (isPaused && !covered && chkPlay.Value && P("동작", "멈춰있으면") != "") {
        if (StalledSec() < StallNeedSec())
            return

        if PressByName(root, P("동작", "멈춰있으면")) {
            holdUntil := A_TickCount + 6000
            lastTimeTick := A_TickCount          ; 누른 뒤 다시 처음부터 지켜본다
        }
    }
}

; --------------------------------------------------
; 사이트가 띄운 안내창 ([안내창] 칸)
;   창     : 안내창 자체 (예: class:normal && name:안내)
;   누를글 : 이 글이 있으면 [누를것] 버튼을 누른다 (진행하는 안내)
;   안누를글 : 이 글이 있으면 절대 누르지 않는다 (종료·취소 등)
;   누를것 : 누를 버튼 (안내창 안에서만 찾는다)
; 모르는 안내창은 누르지 않고 한 번 알린다.
; 누르면 true
; --------------------------------------------------
HandleNotice(root, st := "")
{
    global noticeSeen, quizNote

    winSel := P("안내창", "창")

    if (winSel = "")
        return false

    dlg := FindSel(root, winSel)

    if !dlg
        return false

    if !U_IsShown(dlg) {
        ObjRelease(dlg)
        return false
    }

    text := CollectText(dlg)
    yes := P("안내창", "누를글")
    no := P("안내창", "안누를글")
    pressed := false

    if (no != "" && RegExMatch(text, no)) {
        NoticeOnce(text, "누르지 않는 안내창입니다. 직접 확인해 주세요")
    } else if (yes != "" && RegExMatch(text, yes)) {
        ; 영상이 도는 중이면 누르지 않는다.
        ;   확인을 눌러 다음 영상이 떠도 지난 안내창이 화면에 남아 있는 사이트가 있다 (산업안전포털).
        ;   그걸 또 누르면 차시를 하나씩 더 건너뛴다. 안내창은 영상이 끝나 멈춰 있을 때만 누른다.
        ;   (시간이 끝까지 갔으면 재생 표시가 남아 있어도 끝난 것으로 본다)
        done := IsObject(st) && (st.ended || (st.timeTotal > 0 && st.timeCur >= st.timeTotal - 1))

        if (IsObject(st) && !done && (st.playKnown ? st.playing : TimeMoving())) {
            ObjRelease(dlg)
            return false
        }

        btn := FindSel(dlg, P("안내창", "누를것"))

        if btn {
            pressed := PressElement(btn) != ""
            ObjRelease(btn)
            SetState("안내창에서 확인을 눌렀습니다: " SubStr(text, 1, 80))
        }
    } else {
        NoticeOnce(text, "처음 보는 안내창이라 누르지 않았습니다. 직접 확인해 주세요")
    }

    ObjRelease(dlg)

    return pressed
}

NoticeOnce(text, why)
{
    global noticeSeen

    key := SubStr(text, 1, 120)

    if noticeSeen.Has(key)
        return

    noticeSeen[key] := true
    Notify(why ": " SubStr(text, 1, 150))
}

; 화면을 몇 초마다 읽을지 (설정. 기본 5초)
;   자주 읽을수록 반응이 빠르지만, 무거운 플레이어에서는 그만큼 CPU 를 씁니다.
TickSec()
{
    global editTickSec

    v := IsObject(editTickSec) ? Trim(editTickSec.Value) : "5"

    if !IsInteger(v)
        return 5

    n := Integer(v)

    return (n < 1) ? 1 : (n > 60 ? 60 : n)
}

ApplyTickInterval()
{
    SetTimer(Tick, TickSec() * 1000)
}

; 재생 시간이 방금(3초 안) 실제로 바뀌었는지. 재생 상태를 알려 주지 않는 사이트용
; 재생 시간이 '지난번 읽을 때와 견줘' 실제로 바뀌었는지.
;   읽는 주기를 10초로 해 두면 10초 전 값과 견주므로, 그만큼 여유를 둔다.
TimeMoving()
{
    global lastTimeMovedTick, readGapMs

    return lastTimeMovedTick && (A_TickCount - lastTimeMovedTick < Max(3000, readGapMs + 1500))
}

; 재생 시간이 몇 초째 그대로인지
StalledSec()
{
    global lastTimeTick

    if !lastTimeTick
        return 0

    return (A_TickCount - lastTimeTick) // 1000
}

; 몇 초 멈춰 있으면 '진짜 멈춤' 으로 볼지 (프로필의 [동작] 멈춤판단초, 기본 6초)
StallNeedSec()
{
    v := P("동작", "멈춤판단초", "6")

    if !IsInteger(v)
        return 6

    n := Integer(v)

    return (n < 3) ? 3 : (n > 120 ? 120 : n)
}

PressByName(root, itemName)
{
    sel := P("누를것", itemName)

    if (sel = "")
        return false

    el := FindSel(root, sel)

    if !el
        return false

    how := PressElement(el)
    ObjRelease(el)

    return (how != "")
}

PressOnce(itemName)
{
    global prof

    if (itemName = "" || !IsObject(prof))
        return

    hwnd := GetLectureWindow()

    if !hwnd {
        SetState("강의 창을 찾지 못했습니다.")
        return
    }

    root := 0
    try ComCall(6, UIA(), "ptr", hwnd, "ptr*", &root)

    if !root
        return

    sel := P("누를것", itemName)
    el := FindSel(root, sel)

    if !el {
        SetState("'" itemName "' 을(를) 찾지 못했습니다."
            . "`n프로필에 적힌 코드: " sel
            . "`n지금 화면에 그 버튼이 보이는지 확인하거나 설정 → [코드 목록 뽑기] 로 코드를 다시 확인하세요.")
        ObjRelease(root)
        return
    }

    how := PressElement(el)
    ObjRelease(el)
    ObjRelease(root)

    SetState("'" itemName "' 을(를) " (how != "" ? "눌렀습니다 (" how ")" : "누르지 못했습니다") ".")
}

; --------------------------------------------------
; 지금 상태 읽기
; --------------------------------------------------
ReadState(root)
{
    st := {playing: false, playKnown: false, timeCur: -1, timeTotal: -1, timeText: ""
        , pageCur: 0, pageTotal: 0, quiz: false, quizDesc: "", notice: "", ended: false}

    ; 영상이 끝났다는 표시 ([상태] 끝남). 전체 시간이 안 나오는 플레이어용 (예: video.js 의 vjs-ended)
    endSel := P("상태", "끝남")

    if (endSel != "") {
        el := FindSel(root, endSel)
        st.ended := el ? true : false

        if el
            ObjRelease(el)
    }

    ; 재생 / 멈춤
    ; [상태] 재생중 이 적혀 있으면 그것만 본다.
    ; (버튼 이름이 상태를 나타내지 않는 사이트가 있다. 산업안전포털 스킨2 가 그렇다)
    liveSel := P("상태", "재생중")

    if (liveSel != "") {
        el := FindSel(root, liveSel)
        st.playKnown := true
        st.playing := el ? true : false

        if el
            ObjRelease(el)
    } else {
        pauseSel := P("누를것", "일시정지")
        playSel := P("누를것", "재생")

        elPause := (pauseSel != "") ? FindSel(root, pauseSel) : 0
        elPlay := (playSel != "") ? FindSel(root, playSel) : 0

        if elPause {
            st.playing := true
            st.playKnown := true
            ObjRelease(elPause)
        } else if elPlay {
            st.playing := false
            st.playKnown := true
            ObjRelease(elPlay)
        }
    }

    ; 시간과 페이지는 '다음' 버튼이 들어 있는 문서 안에서만 찾는다
    ; (바깥 페이지의 표에 있는 숫자를 페이지 번호로 잘못 읽지 않도록)
    scope := ReadScope(root)
    box := scope ? scope : root

    ; 시간
    cur := ReadNumberFrom(box, P("읽을것", "현재시간"))
    tot := ReadNumberFrom(box, P("읽을것", "전체시간"))

    if (cur >= 0)
        st.timeCur := cur

    if (tot >= 0)
        st.timeTotal := tot

    ; 한 덩어리로 된 경우도 지원 ("01:27 / 01:42")
    if (st.timeTotal < 0) {
        t := ReadRule(box, P("읽을것", "현재시간"))

        if RegExMatch(t, "(\d{1,2}:\d{2}(?::\d{2})?)\s*/\s*(\d{1,2}:\d{2}(?::\d{2})?)", &m) {
            st.timeCur := ClockToSec(m[1])
            st.timeTotal := ClockToSec(m[2])
        }
    }

    ; 현재 시간만 따로 있는 경우 (전체 시간이 안 나오는 플레이어. 예: '00:01:47')
    if (st.timeCur < 0) {
        t := ReadRule(box, P("읽을것", "현재시간"))

        if RegExMatch(t, "^(\d{1,2}:\d{2}(?::\d{2})?)$", &m1)
            st.timeCur := ClockToSec(m1[1])
    }

    if (st.timeCur >= 0 && st.timeTotal >= 0)
        st.timeText := SecText(st.timeCur) " / " SecText(st.timeTotal)

    ; 페이지
    pt := ReadRule(box, P("읽을것", "페이지"))

    if RegExMatch(pt, "(\d{1,3})\s*페이지[^0-9]*?(\d{1,3})\s*페이지", &mp) {
        st.pageCur := Integer(mp[1])
        st.pageTotal := Integer(mp[2])
    } else if RegExMatch(pt, "(\d{1,3})\s*[/|]\s*(\d{1,3})", &mp2) {
        st.pageCur := Integer(mp2[1])
        st.pageTotal := Integer(mp2[2])
    }

    st.notice := ReadTextOf(root, P("읽을것", "안내문구"))

    if scope
        ObjRelease(scope)

    ; 문제풀이
    st.quizDesc := FindQuiz(root)
    st.quiz := (st.quizDesc != "")

    return st
}

; 읽기 범위: '다음' 버튼이 들어 있는 문서 (사용 후 ObjRelease), 없으면 0
ReadScope(root)
{
    el := FindSel(root, P("누를것", "다음"))

    if !el
        return 0

    doc := NearestDocument(el)
    ObjRelease(el)

    return doc
}

; 요소를 감싸는 가장 가까운 문서
NearestDocument(el)
{
    cur := U_Parent(el)

    Loop 40 {
        if !cur
            return 0

        if (U_Int(cur, 21) = 50030)
            return cur

        p := U_Parent(cur)
        ObjRelease(cur)
        cur := p
    }

    if cur
        ObjRelease(cur)

    return 0
}

; --------------------------------------------------
; [읽을것] 값 해석
;   class:값 / id:값 / name:값   → 그 요소의 이름을 읽음
;   무늬:정규식                  → 그 모양에 맞는 글자를 찾아 읽음 (class 가 없는 글자용)
;   숫자쌍                       → '01' '08' 처럼 나란히 있는 숫자 두 개를 '01 / 08' 로
; 여러 개를 || 로 이어 적으면 되는 것을 골라 씁니다. (사이트 스킨이 여러 가지일 때)
; --------------------------------------------------
ReadRule(scope, rule)
{
    rule := Trim(rule)

    if (rule = "")
        return ""

    for alt in StrSplit(rule, "||") {
        alt := Trim(alt)

        if (alt = "")
            continue

        if (SubStr(alt, 1, 3) = "무늬:") {
            t := FindTextByPattern(scope, Trim(SubStr(alt, 4)))

            if (t != "")
                return t

            continue
        }

        ; 02:36 과 04:44 처럼 시간이 둘로 나뉘어 있는 경우
        if (alt = "시간쌍") {
            t := FindTimePair(scope)

            if (t != "")
                return t

            continue
        }

        if (alt = "숫자쌍") {
            t := FindNumberPair(scope)

            if (t != "")
                return t

            continue
        }

        ; A ++ B : 두 요소의 글자를 이어서 읽는다 (예: '09' 와 '/10' → '09 /10')
        if InStr(alt, "++") {
            joined := ""
            ok := true

            for part in StrSplit(alt, "++") {
                t := ReadTextOf(scope, Trim(part))

                if (t = "") {
                    ok := false
                    break
                }

                joined .= (joined = "" ? "" : " ") t
            }

            if ok
                return joined

            continue
        }

        t := ReadTextOf(scope, alt)

        if (t != "")
            return t
    }

    return ""
}

; 범위 안의 글자 요소 전부
TextElements(scope)
{
    static cond := 0

    if !cond
        cond := U_CondInt(30003, 50020)          ; 종류 = 글자

    return cond ? U_FindAll(scope, cond) : []
}

FindTextByPattern(scope, pattern)
{
    out := ""

    for el in TextElements(scope) {
        if (out = "" && U_IsShown(el)) {
            s := Trim(StrReplace(StrReplace(U_Str(el, 23), "`n", " "), "`r", ""))

            if (s != "" && RegExMatch(s, pattern))
                out := s
        }

        ObjRelease(el)
    }

    return out
}

; 나란히 있는 시간 두 개 (앞이 현재, 뒤가 전체).  02:36  |  04:44  →  "02:36 / 04:44"
FindTimePair(scope)
{
    static timeLike := "^\d{1,2}:\d{2}(:\d{2})?$"

    prev := ""
    out := ""

    for el in TextElements(scope) {
        if (out = "" && U_HasSize(el)) {
            s := Trim(U_Str(el, 23))

            if RegExMatch(s, timeLike) {
                if (prev != "")
                    out := prev " / " s

                prev := s
            } else if (s != "" && s != "/" && s != "|" && s != "|") {
                prev := ""
            }
        }

        ObjRelease(el)
    }

    return out
}

; 나란히 있는 숫자 두 개 (앞이 현재, 뒤가 전체)
;   '04' '08'  /  '04' '/' '08'  /  '01' '/10'  모두 받는다
;   플레이어가 창보다 넓어 페이지 번호가 화면 밖에 있는 사이트도 있으므로 보이는지는 따지지 않는다
FindNumberPair(scope)
{
    prev := -1
    out := ""

    for el in TextElements(scope) {
        if (out = "" && U_HasSize(el)) {
            s := Trim(U_Str(el, 23))

            if RegExMatch(s, "^\d{1,3}$") {
                n := Integer(s)

                if (prev >= 1 && n >= prev)
                    out := prev " / " n

                prev := n
            } else if (prev >= 1 && RegExMatch(s, "^[/|]\s*(\d{1,3})$", &mt) && Integer(mt[1]) >= prev) {
                out := prev " / " Integer(mt[1])
            } else if (s != "" && s != "/" && s != "|") {
                prev := -1
            }
        }

        ObjRelease(el)
    }

    return out
}

StateText(st)
{
    global running, profName, pressCount, covered, quizNote, sessionNum, sessionTotal, sessionPct, chkNextSession

    stalled := StalledSec()

    lines := []
    lines.Push("사이트   : " profName (running ? "   [진행 중]" : "   [멈춤]"))

    if (sessionNum > 0 || sessionTotal > 0)
        lines.Push("차시     : " (sessionNum > 0 ? sessionNum "차시" : "?")
            . (sessionTotal > 0 ? "   (전체 " sessionTotal "차시" (LastSessionLimit() > 0 ? ", " LastSessionLimit() "차시까지만" : "") ")" : ""))

    ; 다음 차시 자동: 켬/끔, 그리고 다 들은 차시
    done := []

    for num, pct in sessionPct
        if (pct >= 100)
            done.Push(num)

    lines.Push("다음차시 : " (chkNextSession.Value ? "자동 (켬)" : "끔 — 이 차시가 끝나면 멈춤")
        . (done.Length ? "   · 다 들은 차시 " Join(done, "·") " 건너뜀" : ""))

    lines.Push("재생     : " (st.playKnown ? (st.playing ? "재생 중" : "멈춰 있음") : (st.timeTotal > 0 ? (TimeMoving() ? "재생 중 (시간으로 판단)" : "멈춤 (시간으로 판단)") : "모름"))
        . (stalled < 3 ? "  (시간 흐르는 중)"
            : (st.playKnown && st.playing) ? "  (시간 표시만 " stalled "초째 그대로 · 창이 가려지면 늦게 바뀜)"
            : "  (시간이 " stalled "초째 그대로)"))
    lines.Push("시간     : " (st.timeText != "" ? st.timeText : (st.timeCur >= 0 ? SecText(st.timeCur) " (전체 시간은 안 나옴)" : "못 읽음"))
        . (st.ended ? "   → 영상 끝남" : "") "   (" ReadIntervalText() ")")
    lines.Push("페이지   : " (st.pageTotal > 0 ? st.pageCur " / " st.pageTotal : "못 읽음"))
    lines.Push("문제풀이 : " (st.quiz ? "예 → " st.quizDesc : "아님"))

    if (st.quiz && quizNote != "")
        lines.Push("           " quizNote)
    global topHwnd
    lines.Push("창       : " (covered ? "다른 창에 완전히 가려짐 → 이러면 영상이 멈춥니다" : "보임 (정상)")
        . (topHwnd ? "   · 항상 위" : ""))

    if (st.notice != "")
        lines.Push("안내     : " st.notice)

    ; 아무것도 못 읽었으면 가장 흔한 원인을 알려준다
    if (!st.playKnown && st.timeText = "" && st.pageTotal = 0 && !st.quiz)
        lines.Push("`n읽히는 것이 없습니다. 강의 탭을 보고 있는지,"
            . "`n프로필 코드가 맞는지 (설정 → 코드 목록 뽑기) 확인하세요.")

    return Join(lines, "`n")
}

; 화면을 얼마마다 읽는지. 본체 창이 떠 있으면 설정한 주기, 숨겨 두면 영상이 도는 동안 더 쉰다
ReadIntervalText()
{
    global readGapMs

    s := TickSec() "초마다 읽음"

    if (readGapMs > (TickSec() + 2) * 1000)
        s .= ", 지난번은 " Round(readGapMs / 1000) "초 전"

    return s
}

Join(arr, sep)
{
    out := ""

    for v in arr
        out .= (out = "" ? "" : sep) v

    return out
}

; 요소 이름에서 "03분 51초" / "01:27" 같은 시간을 초로 바꿔 돌려줌. 못 읽으면 -1
ReadNumberFrom(root, sel)
{
    t := ReadTextOf(root, sel)

    if (t = "")
        return -1

    if RegExMatch(t, "(\d{1,3})\s*분\s*(\d{1,2})\s*초", &m)
        return Integer(m[1]) * 60 + Integer(m[2])

    if RegExMatch(t, "(\d{1,2}:\d{2}(?::\d{2})?)", &m2)
        return ClockToSec(m2[1])

    return -1
}

ReadTextOf(root, sel)
{
    if (sel = "")
        return ""

    el := FindSel(root, sel)

    if !el
        return ""

    t := Trim(StrReplace(StrReplace(U_Str(el, 23), "`n", " "), "`r", ""))

    ; 요소 자체에 읽을 이름이 없으면, 그 안의 글자들을 모아서 읽는다
    if (t = "")
        t := CollectText(el)

    ObjRelease(el)

    return t
}

; 요소 안쪽의 글자 요소들을 한 줄로 모음
CollectText(el)
{
    static cond := 0

    if !cond
        cond := U_CondInt(30003, 50020)         ; ControlType = 글자

    if !cond
        return ""

    out := ""

    for c in U_FindAll(el, cond) {
        s := Trim(StrReplace(StrReplace(U_Str(c, 23), "`n", " "), "`r", ""))

        if (s != "")
            out .= (out = "" ? "" : " ") s

        ObjRelease(c)
    }

    return out
}

ClockToSec(s)
{
    p := StrSplit(s, ":")

    if (p.Length = 3)
        return Integer(p[1]) * 3600 + Integer(p[2]) * 60 + Integer(p[3])

    if (p.Length = 2)
        return Integer(p[1]) * 60 + Integer(p[2])

    return 0
}

SecText(sec)
{
    if (sec < 0)
        return "--:--"

    return Format("{:02}:{:02}", sec // 60, Mod(sec, 60))
}

FindQuiz(root)
{
    ; class 에 키워드가 들어간 요소
    for word in StrSplit(P("문제풀이", "class키워드"), "|") {
        word := Trim(word)

        if (word = "")
            continue

        el := FindSel(root, "class:" word " || id:" word)          ; class 또는 id 에 들어 있으면

        if el {
            cls := U_Str(el, 30)
            desc := "'" U_Str(el, 23) "' (" (cls != "" ? "class: " cls : "id: " U_Str(el, 29)) ")"
            ObjRelease(el)
            return desc
        }
    }

    ; 이름에 키워드가 들어간 요소
    for word in StrSplit(P("문제풀이", "이름키워드"), "||") {
        word := Trim(word)

        if (word = "")
            continue

        el := FindSel(root, "name:" word)

        if el {
            desc := "'" U_Str(el, 23) "'"
            ObjRelease(el)
            return desc
        }
    }

    return ""
}

Beep3()
{
    Loop 3 {
        SoundBeep(1000, 200)
        Sleep 120
    }
}

; --------------------------------------------------
; 코드로 찾기 / 누르기
; --------------------------------------------------
; sel 예) "class:page && name:다음페이지"  또는  "class:a || class:b"
FindSel(root, sel)
{
    sel := Trim(sel)

    if (sel = "")
        return 0

    for alt in StrSplit(sel, "||") {
        el := FindOne(root, Trim(alt))

        if el
            return el
    }

    return 0
}

FindOne(root, expr)
{
    terms := []

    for piece in StrSplit(expr, "&&") {
        t := ParseTerm(Trim(piece))

        if IsObject(t)
            terms.Push(t)
    }

    if !terms.Length
        return 0

    cond := U_Cond(terms[1].prop, terms[1].val, terms[1].exact)

    if !cond
        return 0

    hit := 0
    backup := 0

    for el in U_FindAll(root, cond) {
        ok := true

        Loop terms.Length - 1 {
            if !TermMatch(el, terms[A_Index + 1]) {
                ok := false
                break
            }
        }

        ; 브라우저 자체의 버튼(탭 닫기·창 닫기·주소창 등)은 어떤 규칙으로도 잡지 않는다.
        ; 'class:close && name:닫기' 가 브라우저 탭의 닫기 버튼(TabCloseButton)에도 맞았다.
        if (ok && !InWebPage(el))
            ok := false

        if (ok && !hit && U_IsShown(el))
            hit := el
        else if (ok && !backup)
            backup := el                     ; 조건은 맞지만 지금은 안 보이는 것 (예비)
        else
            ObjRelease(el)
    }

    ObjRelease(cond)

    if hit {
        if backup
            ObjRelease(backup)

        return hit
    }

    return backup
}

; 요소가 조건 하나에 맞는지 (따옴표로 적었으면 정확히 같아야 함)
TermMatch(el, t)
{
    s := U_Str(el, t.idx)

    return t.exact ? (s = t.val) : InStr(s, t.val)
}

; 웹페이지(문서) 안에 있는 요소인지. 브라우저 틀(탭 줄·주소창·창 버튼)은 문서 밖에 있다
InWebPage(el)
{
    cur := U_Parent(el)

    Loop 60 {
        if !cur
            return false

        if (U_Int(cur, 21) = 50030) {          ; 문서
            ObjRelease(cur)
            return true
        }

        up := U_Parent(cur)
        ObjRelease(cur)
        cur := up
    }

    if cur
        ObjRelease(cur)

    return false
}

ParseTerm(piece)
{
    p := InStr(piece, ":")

    if !p
        return ""

    kind := Trim(SubStr(piece, 1, p - 1))
    val := Trim(SubStr(piece, p + 1))

    ; 따옴표로 감싸면 '정확히 같은 것' 만 (예: class:"close" 는 closeMenu·TabCloseButton 을 뺀다)
    exact := false

    if (StrLen(val) >= 2 && SubStr(val, 1, 1) = '"' && SubStr(val, -1) = '"')
        val := SubStr(val, 2, StrLen(val) - 2), exact := true

    if (val = "")
        return ""

    if (kind = "class")
        return {prop: 30012, idx: 30, val: val, exact: exact}

    if (kind = "id")
        return {prop: 30011, idx: 29, val: val, exact: exact}

    if (kind = "name")
        return {prop: 30005, idx: 23, val: val, exact: exact}

    return ""
}

; 창을 앞으로 끌어내지 않는 방법(기본동작)을 먼저 쓴다.
; '창을 앞으로 가져오지 않기' 를 껐을 때만, 안 될 경우 Invoke 로 넘어간다.
; (Invoke 는 브라우저 창을 맨 앞으로 끌어내므로 다른 작업을 방해한다)
PressElement(el)
{
    global chkNoFront, lastPressError

    lastPressError := ""
    pat := 0
    try ComCall(16, el, "int", 10018, "ptr*", &pat)        ; LegacyIAccessible

    if !pat
        lastPressError := "누르기 기능이 없는 요소"

    if pat {
        ok := false

        try {
            ComCall(4, pat)                                ; DoDefaultAction
            ok := true
        } catch as e {
            lastPressError := e.Message
        }

        ObjRelease(pat)

        if ok
            return "기본동작"
    }

    if (IsObject(chkNoFront) && chkNoFront.Value)
        return ""

    pat := 0
    try ComCall(16, el, "int", 10000, "ptr*", &pat)        ; InvokePattern

    if pat {
        ok := false

        try {
            ComCall(3, pat)                                ; Invoke
            ok := true
        }

        ObjRelease(pat)

        if ok
            return "Invoke"
    }

    return ""
}

; --------------------------------------------------
; 코드 목록 뽑기 (새 사이트 프로필 만들 때)
; --------------------------------------------------
DumpCodes()
{
    global dumpFile, prof

    hwnd := (IsObject(prof) && prof.Count) ? GetLectureWindow() : 0

    if !hwnd {
        ; 프로필이 없어도 브라우저 창이 하나라도 있으면 그걸 본다
        for h in WinGetList() {
            try {
                if (WinGetClass(h) = "Chrome_WidgetWin_1" && WinGetTitle(h) != "" && WinGetMinMax(h) != -1) {
                    hwnd := h
                    break
                }
            }
        }
    }

    if !hwnd {
        SetState("코드를 뽑을 브라우저 창을 찾지 못했습니다.")
        return
    }

    try FileDelete(dumpFile)

    FileAppend("창: " WinGetTitle("ahk_id " hwnd) "`n"
        . "적는 법: 프로필 파일에 class:값  id:값  name:값  으로 적습니다.`n"
        . "         두 조건을 모두 만족시키려면  class:page && name:다음페이지`n"
        . "'누를 수 있음' 이 예 인 것만 코드로 누를 수 있습니다.`n"
        . "-------------------------------------------------------------------`n", dumpFile, "UTF-8")

    root := 0
    try ComCall(6, UIA(), "ptr", hwnd, "ptr*", &root)

    if root {
        DumpWalk(root, 0)
        ObjRelease(root)
    }

    SetState("코드 목록을 '" dumpFile "' 에 저장했습니다.")
    try Run 'notepad.exe "' dumpFile '"'
}

DumpWalk(el, depth)
{
    global dumpFile

    static walker := 0

    if !walker
        ComCall(14, UIA(), "ptr*", &walker)

    if (depth > 26)
        return

    id := U_Str(el, 29)
    cls := U_Str(el, 30)
    name := U_Str(el, 23)
    ct := U_Int(el, 21)

    if (id != "" || cls != "" || name != "") {
        pressable := false
        pat := 0

        try ComCall(16, el, "int", 10018, "ptr*", &pat)

        if pat {
            pressable := true
            ObjRelease(pat)
        }

        FileAppend(Format("{1:-3} | {2} | class:{3} | id:{4} | 이름:{5} | 보임:{6} | 누를 수 있음:{7}`n"
            , depth, U_TypeName(ct), cls, id
            , SubStr(Trim(StrReplace(StrReplace(name, "`n", " "), "`r", "")), 1, 70)
            , U_IsShown(el) ? "예" : "아니오"
            , pressable ? "예" : "아니오"), dumpFile, "UTF-8")
    }

    child := 0
    try ComCall(4, walker, "ptr", el, "ptr*", &child)

    while child {
        DumpWalk(child, depth + 1)
        nxt := 0
        try ComCall(6, walker, "ptr", child, "ptr*", &nxt)
        ObjRelease(child)
        child := nxt
    }
}

; ==================================================
; UI Automation 도우미
; ==================================================
UIA()
{
    static uia := 0

    if !IsObject(uia)
        uia := ComObject("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")

    return uia
}

; 글자 속성 조건 (부분 일치 + 대소문자 무시)
U_Cond(propId, value, exact := false)
{
    var := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("ushort", 8, var, 0)
    bstr := DllCall("oleaut32\SysAllocString", "wstr", value, "ptr")
    NumPut("ptr", bstr, var, 8)

    cond := 0
    ; 1 = 대소문자 무시, 2 = 부분 일치. 정확히 같은 것만 찾을 때는 부분 일치를 뺀다
    try ComCall(24, UIA(), "int", propId, "ptr", var, "int", exact ? 1 : 3, "ptr*", &cond)

    if bstr
        DllCall("oleaut32\SysFreeString", "ptr", bstr)

    return cond
}

; 숫자 속성 조건 (예: 종류 = 글자)
U_CondInt(propId, value)
{
    var := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("ushort", 3, var, 0)
    NumPut("int", value, var, 8)

    cond := 0
    try ComCall(24, UIA(), "int", propId, "ptr", var, "int", 0, "ptr*", &cond)

    return cond
}

; 두 조건 중 하나라도 맞으면
U_Or(c1, c2)
{
    cond := 0
    try ComCall(28, UIA(), "ptr", c1, "ptr", c2, "ptr*", &cond)     ; CreateOrCondition

    return cond
}

; 두 요소가 같은 요소인지
U_Same(a, b)
{
    same := 0
    try ComCall(3, UIA(), "ptr", a, "ptr", b, "int*", &same)        ; CompareElements

    return same
}

U_FindAll(el, cond)
{
    list := []
    arr := 0

    try {
        ComCall(6, el, "int", 4, "ptr", cond, "ptr*", &arr)

        if arr {
            n := 0
            ComCall(3, arr, "int*", &n)

            Loop n {
                e := 0
                ComCall(4, arr, "int", A_Index - 1, "ptr*", &e)

                if e
                    list.Push(e)
            }
        }
    }

    if arr
        ObjRelease(arr)

    return list
}

; 23 = 이름, 29 = id, 30 = class
U_Str(el, index)
{
    p := 0
    try ComCall(index, el, "ptr*", &p)

    if !p
        return ""

    s := StrGet(p, "UTF-16")
    DllCall("oleaut32\SysFreeString", "ptr", p)

    return s
}

; 21 = 종류, 38 = 화면 밖인지
U_Int(el, index)
{
    v := 0
    try ComCall(index, el, "int*", &v)

    return v
}

U_Parent(el)
{
    static walker := 0

    if !walker
        ComCall(14, UIA(), "ptr*", &walker)          ; ControlViewWalker

    p := 0
    try ComCall(3, walker, "ptr", el, "ptr*", &p)    ; GetParentElement

    return p
}

; 화면 위 크기가 있는지 (스크롤 밖이어도 참)
U_HasSize(el)
{
    rect := Buffer(16, 0)
    try ComCall(43, el, "ptr", rect)

    return (NumGet(rect, 8, "int") > NumGet(rect, 0, "int"))
        && (NumGet(rect, 12, "int") > NumGet(rect, 4, "int"))
}

U_IsShown(el)
{
    if U_Int(el, 38)
        return false

    rect := Buffer(16, 0)
    try ComCall(43, el, "ptr", rect)

    return (NumGet(rect, 8, "int") > NumGet(rect, 0, "int"))
        && (NumGet(rect, 12, "int") > NumGet(rect, 4, "int"))
}

U_TypeName(ct)
{
    static names := Map(
        50000, "버튼", 50002, "체크상자", 50003, "목록상자", 50004, "입력칸",
        50005, "링크", 50006, "그림", 50007, "목록항목", 50008, "목록",
        50011, "메뉴항목", 50013, "라디오", 50020, "글자", 50025, "사용자",
        50026, "묶음", 50030, "문서", 50033, "판", 50036, "표"
    )

    return names.Has(ct) ? names[ct] : "종류" ct
}

; --------------------------------------------------
; 단축키
; --------------------------------------------------
; F9 / F10 / F11 은 설정 창에서 바꿀 수 있도록 ApplyHotkeys() 에서 등록한다

#HotIf WinActive("코드로 넘기기 ahk_class AutoHotkeyGUI")
Esc:: Stop("정지했습니다.")
#HotIf
