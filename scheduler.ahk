; SBS sVCR scheduler by sendust
; Last edit 2020/5/22
; 

#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
#SingleInstance, off
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode, Event
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.
DetectHiddenWindows, on
SetTitleMatchMode, slow
SetControlDelay, -1
SetKeyDelay, 30, 20				; before -1, 10, changed 2020/5/14
menu, tray, icon, .\icon\scheduler.ico
#NoTrayIcon



logfile = %A_WorkingDir%\log\schedulerlog.log
myWday := object()
sunday = 0
monday = 0
tuesday = 0
wednesday = 0
thursday = 0
friday = 0
saturday = 0
activate = 0
start_time = 13:00:00
end_time = 14:00:00
select_vcr = 1

recbutton = button3
stopbutton = button4

IniRead, title1, svcr1.ini, name, name, VTR1       ; read channel name
IniRead, title2, svcr2.ini, name, name, VTR2
IniRead, title3, svcr3.ini, name, name, VTR3
IniRead, title4, svcr4.ini, name, name, VTR4
IniRead, title5, svcr5.ini, name, name, VTR5

;  	title%A_Index% := "SBS sVCR v2-" . CHNAME%A_Index% . " by sendust"
panel_array := Object()
panel_array[1] := "SBS sVCR v2-" . title1 . " by sendust"
panel_array[2] := "SBS sVCR v2-" . title2 . " by sendust"
panel_array[3] := "SBS sVCR v2-" . title3 . " by sendust"
panel_array[4] := "SBS sVCR v2-" . title4 . " by sendust"
panel_array[5] := "SBS sVCR v2-" . title5 . " by sendust"
mytitle = VCR SCHEDULER

title_array := Object()
title_array[1] := title1
title_array[2] := title2
title_array[3] := title3
title_array[4] := title4
title_array[5] := title5

gui, new, ,%mytitle%
gui, add, text, x5 y5 ,START_TIME
gui, add, text, x120 y5, END_TIME
gui, add, datetime, x5 y20 w100 h20 vstart_time hwndhstart_time, MM/dd HH:mm
gui, add, datetime, x120 y20 w100 h20 vend_time hwndhend_time, MM/dd HH:mm
gui, add, edit, x230 y20 w310 h20 vrec_filename hwndhrec_filename, Schedule name_%A_msec%

gui, add, checkbox, x220 y5 vsunday hwndhsunday, S
gui, add, checkbox, x260 y5 vmonday hwndhmonday, M
gui, add, checkbox, x300 y5 vtuesday hwndhtuesday, T
gui, add, checkbox, x340 y5 vwednesday hwndhwednesday, W
gui, add, checkbox, x380 y5 vthursday hwndhthursday, T
gui, add, checkbox, x420 y5 vfriday hwndhfriday, F
gui, add, checkbox, x460 y5 vsaturday hwndhsaturday, S

gui, add, checkbox, x630 y23 vactivate gactivate hwndhactivate, Standby
gui, add, text, x550 y5 w200 hwndhstatus, Scheduler v1.1
gui, add, DropDownList, x550 y20 w65 vselect_vcr choose1 hwndhselect_vcr AltSubmit, %title1%|%title2%|%title3%|%title4%|%title5%
gui, add, button, x500 y1 w45 h18 gsave, save
gui, show, w700 h50
Gui +Hwndhthiswindow


;guicontrol,disable,%hsunday%          ; not implemented 
;guicontrol,disable,%hmonday%
;guicontrol,disable,%htuesday%
;guicontrol,disable,%hwednesday%
;guicontrol,disable,%hthursday%
;guicontrol,disable,%hfriday%
;guicontrol,disable,%hsaturday%

return

1::
ListVars
return



save:
gui, submit, nohide
FormatTime, savetime, %start_time%,HHmm
filename = %A_MyDocuments%\scheduler\%rec_filename%_
filename := filename . "_" . title_array[select_vcr]
filename = %filename%_%savetime%.txt
FileDelete, %filename%
ifnotexist,  %A_MyDocuments%\scheduler
	FileCreateDir, %A_MyDocuments%\scheduler
FileAppend, ## sVCR-scheduler save file ##`n`n, %filename%
FileAppend, title=%rec_filename%`n, %filename% 
FileAppend, start_time=%start_time%`n, %filename% 
FileAppend, end_time=%end_time%`n, %filename% 
FileAppend, sunday=%sunday%`n, %filename% 
FileAppend, monday=%monday%`n, %filename% 
FileAppend, tuesday=%tuesday%`n, %filename% 
FileAppend, wednesday=%wednesday%`n, %filename% 
FileAppend, thursday=%thursday%`n, %filename% 
FileAppend, friday=%friday%`n, %filename% 
FileAppend, saturday=%saturday%`n, %filename% 
FileAppend, vcr_selection=%select_vcr%`n, %filename%
tooltip, %filename% `n saved !!
SetTimer, removetooltip, -2000
return


removetooltip:
ToolTip
return


activate:
gui, submit, nohide

myWday[1] := saturday
myWday[2] := sunday
myWday[3] := monday
myWday[4] := tuesday
myWday[5] := wednesday
myWday[6] := thursday
myWday[7] := friday
myWday[8] := saturday

isweekly = 0
loop, 8
{
	isweekly := isweekly + myWday[A_Index]
}

if (end_time <= start_time) & activate             ; Check if end time is before start time
{
	msgbox Check END TIME
	activate = 0
	GuiControl,,%hactivate%, 0
	return
}

if end_time < % A_Now
	pastcheck = 1
else
	pastcheck = 0

outputdebug, %pastcheck%

temp := end_time
EnvSub, temp, %start_time%, hours

if (temp >= 23) & activate                        ; Check if duration is longer than 23 hours
{
	msgbox Duration is longer than 23 hours
	activate = 0
	GuiControl,,%hactivate%, 0
	return
}

rec_filename := Trim(rec_filename)
FormatTime, start_time, %start_time%, yyyyMMddHHmm00     ; take year, month, day, hour, monute and 00 Seconds
FormatTime, end_time, %end_time%, yyyyMMddHHmm00         ; example 19740406121212 -> 19740406121200


panel_title := panel_array[select_vcr]

if activate
{
	guicontrol,disable,%hstart_time%
	guicontrol,disable,%hend_time%
	guicontrol,disable,%hselect_vcr%
	guicontrol,Disable,%hrec_filename%
		
	guicontrol,disable,%hsunday%
	guicontrol,disable,%hmonday%
	guicontrol,disable,%htuesday%
	guicontrol,disable,%hwednesday%
	guicontrol,disable,%hthursday%
	guicontrol,disable,%hfriday%
	guicontrol,disable,%hsaturday%

	pre_time := (A_Sec - 61) * 1000          ; find next nearist 00 second
	settimer, checktime, %pre_time%          ; trigger pre timer one time
	guicontrol,, %hstatus%, Timer is triggered(single)
	WinSetTitle, ahk_id %hthiswindow%,, % mytitle " - " title_array[select_vcr]
	if !isweekly and pastcheck
		WinSetTitle, ahk_id %hthiswindow%,, % mytitle " - " title_array[select_vcr] " == Finished =="

	if isweekly
	{
		guicontrol,, %hstatus%, Timer is triggered(weekly)
		FormatTime, w_time_start, %start_time%, HHmm00     ; take hour, monute and 00 Seconds  
		FormatTime, w_time_end, %end_time%, HHmm00         ; example 19740406121212 -> 121200
		temp := w_time_start - w_time_end
		if temp > 0
			overnight = 1
		else 
			overnight = 0
	}
	updatelog("Engage recording schedule  " . mytitle " - " title_array[select_vcr] . " [ " . start_time . " / " . end_time . " weekly flag " . isweekly . " ]")
}
else
{
	guicontrol,Enable,%hstart_time%
	guicontrol,Enable,%hend_time%
	guicontrol,Enable,%hselect_vcr%
	guicontrol,Enable,%hrec_filename%
	
	guicontrol,Enable,%hsunday%
	guicontrol,Enable,%hmonday%
	guicontrol,Enable,%htuesday%
	guicontrol,Enable,%hwednesday%
	guicontrol,Enable,%hthursday%
	guicontrol,Enable,%hfriday%
	guicontrol,Enable,%hsaturday%
	
	settimer, checktime, Off
	guicontrol,, %hstatus%, timer is off
	WinSetTitle, ahk_id %hthiswindow% ,, %mytitle%
	updatelog("Release recording schedule " . mytitle " - " title_array[select_vcr] . " [ " . start_time . " / " . end_time . " weekly flag " . isweekly . " ]")
}
return


checktime:

pre_time := (A_Sec - 61) * 1000          ; find next nearist 00 second
settimer, checktime, %pre_time%          ; trigger pre timer one time

FormatTime, temp, %A_Now%, MM/dd HH:mm  
guicontrol,, %hstatus%, %temp%       ; display current time every 1 minute

if isweekly
{
	gosub, weeklycheck
	return
}

FormatTime, f_time_current_s,,yyyyMMddHHmm00     ; take year, month, day, hour, minute and 00 Seconds
FormatTime, f_time_current_e,,yyyyMMddHHmm00     ; example 19740406121212 -> 19740406121200

EnvSub, f_time_current_s, %start_time%, Minutes    ; compare current time and start time
EnvSub, f_time_current_e, %end_time%, Minutes      ; compare current time and end time

IfWinExist, %panel_title%
{
	if !f_time_current_s       ; execute now is start time
	{
		ControlSetText, Edit1, %rec_filename%, %panel_title%
		Sleep, 500
		gosub, clickstartrec
	}


	if !f_time_current_e        ; execute now is end time
	{
		gosub, clickstop
	}
}

return

weeklycheck:
;variables = w_time_start, w_time_end, overnight, myWday[1~8]
FormatTime, f_time_current,,HHmm00     ; take current hour, minute and 00 Seconds
Windex := A_WDay + 1
yesterday_check := A_WDay

if !overnight
{
	if (f_time_current = w_time_start) and myWday[Windex]
	{
		ControlSetText, Edit1, %rec_filename%, %panel_title%
		Sleep, 500	
		gosub, clickstartrec
	}
	if (f_time_current = w_time_end) and myWday[Windex]
		gosub, clickstop
}


if overnight
{
	if (f_time_current = w_time_start) and myWday[Windex]
	{
		ControlSetText, Edit1, %rec_filename%, %panel_title%
		Sleep, 500		
		gosub, clickstartrec
	}
	if (f_time_current = w_time_end) and myWday[yesterday_check]
		gosub, clickstop
}

return

clickstartrec:
ControlGet, buttoncheck, enabled,, %recbutton%, %panel_title%
if buttoncheck
{
	ControlFocus, %recbutton%, %panel_title%
	ControlClick, %recbutton%, %panel_title% ,,,1, NA   ; 1 click
	updatelog("REC Button pressed " . panel_title)
}
return



clickstop:
if !isweekly
	WinSetTitle, ahk_id %hthiswindow% ,, % mytitle . " - " . title_array[select_vcr] . " == Finished =="
ControlGet, buttoncheck, enabled,, %stopbutton%, %panel_title%
if buttoncheck
{
	ControlFocus, %stopbutton%, %panel_title%
	ControlClick, %stopbutton%, %panel_title% ,,,1, NA   ; 1 click
	updatelog("STOP Button pressed " . panel_title)
}

return

GuiDropFiles:
gui, submit, nohide
if activate
	return

ArrayCount = 0
Loop, Read, %A_GuiEvent%
{
	ArrayCount += 1
    Array%ArrayCount% := A_LoopReadLine  
}

StringSplit, splitarray, Array3, =
rec_filename := splitarray2
StringSplit, splitarray, Array4, =
start_time := splitarray2
StringSplit, splitarray, Array5, =
end_time := splitarray2
StringSplit, splitarray, Array6, =
sunday := splitarray2
StringSplit, splitarray, Array7, =
monday := splitarray2
StringSplit, splitarray, Array8, =
tuesday := splitarray2
StringSplit, splitarray, Array9, =
wednesday := splitarray2
StringSplit, splitarray, Array10, =
thursday := splitarray2
StringSplit, splitarray, Array11, =
friday := splitarray2
StringSplit, splitarray, Array12, =
saturday := splitarray2
StringSplit, splitarray, Array13, =
select_vcr := splitarray2

GuiControl,,%hrec_filename%, %rec_filename%
GuiControl,,%hstart_time%, %start_time%
GuiControl,,%hend_time%, %end_time%
GuiControl,,%hmonday%, %monday%
GuiControl,,%htuesday%, %tuesday%
GuiControl,,%hwednesday%, %wednesday%
GuiControl,,%hthursday%, %thursday%
GuiControl,,%hfriday%, %friday%
GuiControl,,%hsaturday%, %saturday%
GuiControl,,%hsunday%, %sunday%
GuiControl,Choose,%hselect_vcr%, %select_vcr%


return

#IfWinActive, VCR SCHEDULER
WheelUp::
ControlGetFocus, mycontrol, %mytitle%
	IfEqual, mycontrol, SysDateTimePick321
		Send, {up}
	IfEqual, mycontrol, SysDateTimePick322
		Send, {up}
return

WheelDown::
ControlGetFocus, mycontrol, %mytitle%
	IfEqual, mycontrol, SysDateTimePick321
		Send, {down}
	IfEqual, mycontrol, SysDateTimePick322
		Send, {down}
return

GuiClose:
ExitApp




updatelog(text)
{
	global logfile
	FileAppend, [%A_Year%/%A_Mon%/%A_DD%] %A_Hour%:%A_Min%.%A_sec%_%A_MSec%  - %text%`r`n, %logfile%
}

