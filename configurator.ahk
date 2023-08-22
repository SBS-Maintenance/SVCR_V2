/*
	sVCR configurator by sendust
	
	2020/10/27  New remote2020 ready

*/

#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.

Gui, new,, sVCR configurator
Gui, Margin, 20, 20
Gui, Add, Button, w70 h20 gbutton1, VCR1
Gui, Add, Button, xp+80 yp w70 h20 gbutton2, VCR2
Gui, Add, Button, xp+80 yp w70 h20 gbutton3, VCR3
Gui, Add, Button, xp+80 yp w70 h20 gbutton4, VCR4
Gui, Add, Button, xp+80 yp w70 h20 gbutton5, VCR5
Gui, Add, Button, xp+100 yp w70 h20 gbutton6, REMOTE
;Gui, Add, Button, xp+80 yp w70 h20 gbutton7, REMOTE2

Gui, Add, Button, xp+110 yp w70 h20 gsave, SAVE
Gui, Add, Edit, xm yp+50 r25 w700 hwndhedit vedit
Gui, Add, StatusBar, hwndhstatusbar
Gui, Show,, sVCR Configurator
Gui -MinimizeBox -DPIScale -Resize

vcrnumber := 0
gosub, button1

return

button1:
inifile = svcr1.ini
loadconfiguration(inifile)
GuiControl,,%hstatusbar%, %inifile% loaded
return

button2:
inifile = svcr2.ini
loadconfiguration(inifile)
GuiControl,,%hstatusbar%, %inifile% loaded
return

button3:
inifile = svcr3.ini
loadconfiguration(inifile)
GuiControl,,%hstatusbar%, %inifile% loaded
return

button4:
inifile = svcr4.ini
loadconfiguration(inifile)
GuiControl,,%hstatusbar%, %inifile% loaded
return

button5:
inifile = svcr5.ini
loadconfiguration(inifile)
GuiControl,,%hstatusbar%, %inifile% loaded
return

button6:
inifile = remote2020.ini
loadconfiguration(inifile)
GuiControl,,%hstatusbar%, %inifile% loaded
return

button7:
inifile = remote2.ini
loadconfiguration(inifile)
GuiControl,,%hstatusbar%, %inifile% loaded
return


save:
if !FileExist(inifile)
	return
Gui, Submit, NoHide
FileDelete, %inifile%
FileAppend, %edit%, %inifile%
GuiControl,,%hstatusbar%, %inifile% saved
return



loadconfiguration(inifile)
{
	global hedit
	FileRead, outputvar, %inifile%
	GuiControl,, %hedit%, %outputvar%
}


GuiClose:
ExitApp