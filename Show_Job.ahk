#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.
#SingleInstance, Off
no_argument = %0%


if !no_argument
{
	MsgBox, Usage...`r`n   showjob [pid] [Title] [Text]
	ExitApp	
}

pid_watch = %1%

Gui, margin, 10, 10
Gui, add, Text, w300, %3%
Gui, add, Progress, xm yp+20 w300 h10 cRed, 100
Gui, show, x10 y10, %2% - pid %pid_watch%
Gui, -MinimizeBox
SetTimer, pid_check, -200
return


pid_check:
Process, exist, %pid_watch%
if ErrorLevel
	SetTimer, pid_check, -200
else
	SetTimer, GuiClose, -500
return



GuiClose:
ExitApp


