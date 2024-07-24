 #NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
;SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
; SBS sVCR Gang Controller by sendust. last edit 2020/7/6
;  2020/5/27  introduce new scheduler
;  2020/7/6   prepare compiled version
;  2020/10/27  DetectHiddenWindows -> Off
;  2020/11/8   - Introduce UDP Remote command  (control click -> UDP command)
; 2020/11/11	- Bux fix (gui, submit, nohide positioned in main)
;

SendMode, Event

#SingleInstance Ignore
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.
DetectHiddenWindows, Off
SetTitleMatchMode, slow
; SetControlDelay, -1							;disabled 2020/4/13
SetKeyDelay, 30, 20							; before -1, 10, changed 2020/5/14
#Include %A_ScriptDir%\AHKsock.ahk
AHKsock_ErrorHandler("AHKsockErrors")

ahk_exe = ahk
if A_IsCompiled
	ahk_exe = exe



menu, tray, icon, .\icon\home.ico

IniRead, recpath, svcr1.ini, path, capture, d:\capture\    ; read capture folder
IniRead, codec_default,  svcr1.ini, general, codec_default, 1

IniRead, CHNAME1, svcr1.ini, name, name, VTR1		; read CHNAME
IniRead, CHNAME2, svcr2.ini, name, name, VTR2
IniRead, CHNAME3, svcr3.ini, name, name, VTR3
IniRead, CHNAME4, svcr4.ini, name, name, VTR4
IniRead, CHNAME5, svcr5.ini, name, name, VTR5


IniRead, remoteurl1, svcr1.ini, url, progress, udp://127.0.0.1:50001		; read udp url
IniRead, remoteurl2, svcr2.ini, url, progress, udp://127.0.0.1:50002		; read udp url
IniRead, remoteurl3, svcr3.ini, url, progress, udp://127.0.0.1:50003		; read udp url
IniRead, remoteurl4, svcr4.ini, url, progress, udp://127.0.0.1:50004		; read udp url
IniRead, remoteurl5, svcr5.ini, url, progress, udp://127.0.0.1:50005		; read udp url

loop, 5
	remoteport%A_Index% := port_from_url(remoteurl%A_Index%)

/*      	copy from VCR1_XDCAM50.AHK
title := "SBS sVCR v2-" . CHNAME . " by sendust"
title_ee := "EE Video " . CHNAME
title_encoder_main := "Encoder Main " . CHNAME
title_encoder_proxy := "Encoder Proxy " . CHNAME
*/
Loop, 5
{
	title%A_Index% := "SBS sVCR v2-" . CHNAME%A_Index% . " by sendust"
	title_ee%A_Index% := "EE Video " . CHNAME%A_Index%
	title_encoder_main%A_Index% := "Encoder Main " . CHNAME%A_Index%
	title_encoder_proxy%A_Index% := "Encoder Proxy " . CHNAME%A_Index%
}

OutputDebug, capture folder is %recpath%


name_array := Object()
win_position_x := Object()
win_position_y := Object()
listenport := 3441 	      ; listen port for remote control
cmdrec = _REC__          ; protocol string, REC, STOP, EE(by Kim Syehoon)
cmdstop = _STOP_
cmdsettitle = _SETT_
cmdee=_EE_
cmdsettarget=_TRGT_

loop, 5
{
	name_array[A_Index] := title%A_Index%
}

win_position_x := Object()			; EE video quad screen position (large)
win_position_y := Object()
win_position_x[1] := 0
win_position_y[1] := 0
win_position_x[2] := A_ScreenWidth / 2
win_position_y[2] := 0
win_position_x[3] := 0
win_position_y[3] := A_ScreenHeight / 2
win_position_x[4] := A_ScreenWidth / 2 
win_position_y[4] := A_ScreenHeight / 2
win_position_x[5] := A_ScreenWidth / 2 - 480 
win_position_y[5] := A_ScreenHeight / 2 - 270

/*			copy from VCR1_XDCAM50.AHK
mpv_geometry[1] := " --geometry=20:30"
mpv_geometry[2] := " --geometry=510:30"
mpv_geometry[3] := " --geometry=20:310"
mpv_geometry[4] := " --geometry=510:310"
mpv_geometry[5] := " --geometry=510:590"
*/


ee_position_array_x := object()
ee_position_array_y := object()
ee_position_array_x[1] := 20
ee_position_array_x[2] := 510
ee_position_array_x[3] := 20
ee_position_array_x[4] := 510
ee_position_array_x[5] := 510

ee_position_array_y[1] := 30
ee_position_array_y[2] := 30
ee_position_array_y[3] := 310
ee_position_array_y[4] := 310
ee_position_array_y[5] := 590

loop, 5
{
	ee_title%A_Index% := "Preview Window " . title%A_Index% 
	encoder_title%A_Index% := "Encoder Main " . title%A_Index% 
}

;  WinSetTitle, ahk_pid %pid_ffmpeg%,, Encoder Main %CHNAME%

schedulertitle = VCR SCHEDULER
schedulertitle2 = sVCR Scheduler v2 by sendust
delaytime = 100
scheduler_count = -1

eebutton = button2
recbutton = button3
stopbutton = button4

transfer_button = button6
proxy_button = button7
split_button = button8
codec_button = ComboBox1


panel_start_position_x1 := A_ScreenWidth - 900
panel_start_position_x2 := A_ScreenWidth - 900
panel_start_position_x3 := A_ScreenWidth - 900
panel_start_position_x4 := A_ScreenWidth - 900
panel_start_position_x5 := A_ScreenWidth - 900

panel_start_position_y1 = 50
panel_start_position_y2 = 240
panel_start_position_y3 = 430
panel_start_position_y4 = 620
panel_start_position_y5 = 810


gang_panel_x := 20
gang_panel_y := A_ScreenHeight - 500
autogransfer = 0

gui, new,, Gang Controller
gui, margin, 10
gui, add, button, xm ym w100 h40 gbutton1 hwndhbutton1, REC
gui, add, button, xm ym+60 w100 h40 gbutton2 hwndhbutton2, STOP
gui, add, picture, xm ym+42 hwndhredbar, .\icon\redbar_100x5.png
gui, add, picture, xm ym+102 hwndhbluebar, .\icon\bluebar_100x5.png
gui, add, checkbox, x10 y210 vch1 gsave Checked, VTR1
gui, add, checkbox, vch2 gsave Checked, VTR2
gui, add, checkbox, vch3 gsave Checked, VTR3
gui, add, checkbox, vch4 gsave Checked, VTR4
gui, add, checkbox, vch5 gsave Checked, VTR5
gui, add, checkbox, x10 y120 vautotransfer gautotransfer, TRANSFER (ALL)
gui, add, checkbox, x10 y140 vchk_proxy gproxy hwndproxy, PROXY (ALL)
gui, add, checkbox, x10 y160 vchk_split gsplit hwndhsplit, SPLIT (ALL)
Gui, add, DDL, x10 y180 vcodec_choice hwndhcodec_choice  choose%codec_default% gcodec_change, XDCAM50_MXF|XDCAM50_MOV|XDCAM_EX_MXF|PRORES_LT_MOV|PRORES_MOV|PRORES_HQ_MOV|MPEG2_TS|test
gui, add, button, x120 y210 w50 h20 glaunch1 hwndhlaunch1, VTR1
gui, add, button, w50 h20 glaunch2 hwndhlaunch2, VTR2
gui, add, button, w50 h20 glaunch3 hwndhlaunch3, VTR3
gui, add, button, w50 h20 glaunch4 hwndhlaunch4, VTR4
gui, add, button, w50 h20 glaunch5 hwndhlaunch5, VTR5
gui, add, button, x130 y70 w40 h30 gresetposition hwndhresetposition, EE
gui, add, button, x130 y120 w40 h30 gsettarget hwndsettarget , Target
gui, add, button, x10 y350 w90 h20 gschedule, SCHEDULER
gui, add, button, x110 yp w60 h20 geditor, EDITOR
gui, add, picture, x140 y1 gnamesetting, .\icon\setting30.png
gui, add, checkbox, xm ym+320 vchkremote gremote, REMOTE
gui, add, text, xm w105 y305 vfreespace hwndhfreespace Right, %freespace_rec% GB Free
gui, show, x%gang_panel_x% y%gang_panel_y%   ; w180 h300
gui, -MinimizeBox

GuiControl, Hide, %hredbar%
GuiControl, Hide, %hbluebar%
GuiControl,,%heightchannel%, %my8chrec%			; update audio channel from ini read

OutputDebug, control delay is %A_Controldelay%

Gui, font, bold
GuiControl, font, %hfreespace%

port_from_url(remoteurl2)
Gui, Submit, NoHide

SetTimer, displayfreespace, -100
return



codec_change:
gui, submit, nohide

loop, 5
if ch%A_Index%			; Check if VTR is selected
{
	IfWinExist, % title%A_Index%
	{
		ControlGet, ifchecked, Enabled,, %codec_button%, % title%A_Index%
		if ifchecked
		{
			Control, ChooseString, %codec_choice%, %codec_button%, % title%A_Index%
		}
	}
}
return





displayfreespace:

IfExist, %recpath%
{
	DriveSpaceFree, freespace_rec, %recpath%
	freespace_rec := ceil( freespace_rec / 1024)
}
else
	freespace_rec = 0

GuiControl, ,%hfreespace%, %freespace_rec% GB Free
SetTimer, displayfreespace, -60000

return


remote:
gui, submit, nohide
if chkremote
{
	AHKsock_Listen(listenport, "ListenEvent")
	OutputDebug, starting listen ....
}
else
	AHKsock_close()
return

ListenEvent(sEvent, iSocket = 0, sName = 0, sAddr = 0, sPort = 0, ByRef bRecvData = 0, bRecvDataLength = 0) 
{
	Global hbutton1, hbutton2, hresetposition, cmdrec, cmdstop, cmdee, cmdsettitle, cmdsettarget,title_received
	OutputDebug, %sEvent%, %bRecvData%, %bRecvDataLength%
	
	; add tooltip command doesn't help debugging. this function always finish with TCP disconnect command (bRecvData=0, bRecvDataLength=0)
	
	cmd_header := SubStr(bRecvData, 1, 6)
	
    if cmd_header = %cmdrec%
    {
        ControlClick,, ahk_id %hbutton1%,,,1
    }
	
    if cmd_header = %cmdstop%
    {
        ControlClick,, ahk_id %hbutton2%,,,1
    }
	
	if cmd_header = %cmdsettitle%
	{
		title_received := SubStr(bRecvData, 7)
		OutputDebug, Set title command received %title_received%
		SetTimer, paste_title_network, -20
	}

	if cmd_header=%cmdee%
	{
		loop,5
		{
			if ch%A_index%=1
			{
				SetTimer, launch%A_index%, -1
				WinActivate, % title%A_index%
				winmove, % title%A_index%,, % panel_start_position_x%A_index%, % panel_start_position_y%A_index%
			}
		}
		SetTimer,previewstart,-3000
	}

	if cmd_header = %cmdsettarget%
	{
		path_dst := SubStr(bRecvData, 7)
		OutputDebug, Set target command received %path_dst%
		IniWrite, %path_dst%, target.ini, Target, path
		loop,5
		{
			send_udp_text("127.0.0.1", remoteport%A_Index%, "_SETTARGET___")
		}
	}
    
}

namesetting:
IfWinNotExist, sVCR Configurator
	Run, configurator.%ahk_exe%

return

proxy:
gui, submit, nohide
if chk_proxy
	mycontrol = Check
else
	mycontrol = UnCheck

loop, 5
if ch%A_Index%			; Check if VTR is selected
{
	IfWinExist, % title%A_Index%
	{
		ControlGet, ifchecked, Enabled,, %proxy_button%, % title%A_Index%
		if ifchecked
			Control, %mycontrol%,, %proxy_button%, % title%A_Index%
	}
}


return

split:
gui, submit, nohide
if chk_split
	mycontrol = Check
else
	mycontrol = UnCheck

loop, 5
if ch%A_Index%			; Check if VTR is selected
{
	IfWinExist, % title%A_Index%
	{
		ControlGet, ifchecked, Enabled,, %split_button%, % title%A_Index%
		if ifchecked
			Control, %mycontrol%,, %split_button%, % title%A_Index%
	}
}

return

autotransfer:
gui, submit, nohide
if autotransfer
	mycontrol = Check
else
	mycontrol = UnCheck

loop, 5
if ch%A_Index%			; Check if VTR is selected
{
	IfWinExist, % title%A_Index%
	{
		ControlGet, ifchecked, Enabled,, %transfer_button%, % title%A_Index%
		if ifchecked
			Control, %mycontrol%,,%transfer_button%, % title%A_Index%
	}
}

return

/*
schedule:
scheduler_count += 1
run, scheduler.ahk
WinWait, %schedulertitle%,,3
WinMove, %schedulertitle%,, % A_Screenwidth / 6, % ((scheduler_count & 7) + 1) * 80 + 50
return
*/

schedule:
if WinExist(schedulertitle2)
{
	WinRestore, %schedulertitle2%
	WinWait, %schedulertitle2%,, 2
	WinActivate, %schedulertitle2%
}
else
	Run, scheduler2.%ahk_exe%
return


editor:
run, easy_movie_editor.%ahk_exe%
return

resetposition:

Gui, Submit, NoHide
/*
WinGet, windowlist, List, SBS-ingest                 ; restore minized window
loop, %windowlist%
{
	;WinRestore, % "ahk_id " . windowlist%A_Index%
	WinActivate, % "ahk_id " . windowlist%A_Index%
}
*/         ; removed after disable minimize button in VCR Control Panel

WinGet, windowlist, List, VCR SCHEDULER              ; restore minized window

loop, %windowlist%
{
	;WinRestore, % "ahk_id " . windowlist%A_Index%
	WinActivate,  % "ahk_id " . windowlist%A_Index%
}

loop, 5
	winmove, % title%A_index%,, % panel_start_position_x%A_index%, % panel_start_position_y%A_index%   ; reposition control panel

loop, 5
{
	;ControlFocus, button2, % title%A_Index%
	;ControlClick, button2, % title%A_Index%,,,1,NA  ; click EE button
	send_udp_text("127.0.0.1", remoteport%A_Index%, "___PREVIEW___")

}

return

previewstart:
loop, 5
{
	send_udp_text("127.0.0.1", remoteport%A_Index%, "___PREVIEW___")
}
return

settarget:
WinGet, windowlist, List, VCR SCHEDULER  
path_dst := selectfolder(path_dst)
loop, %windowlist%
	{
		WinActivate,  % "ahk_id " . windowlist%A_Index%
	}
IniWrite, %path_dst%, target.ini, Target, path

loop, 5
{
	ControlClick,Button6,  % title%A_index%
}
return
selectfolder(folder)
{
	folder_old := folder
	FileSelectFolder, OutputVar, *%folder%, 3, Select Target Folder          ; option 3 = create new folder, paste text path is possible  2018/1/15

	if OutputVar =                       ; Select cancel
		return folder_old
	else
	{
		path_dst :=RegExReplace(OutputVar, "\\$")  ; Removes the trailing backslash, if present.
		path_dst =%path_dst%\
		return path_dst
	}
}


GuiContextMenu:
Gui, Submit, NoHide
OutputDebug, Guicontrol name is %A_GuiControl%
if A_GuiControl = EE              ; reset position is selected
{
	loop, 5
	{
		if ch%A_Index%            ; close all EE window (selected channel only)
			WinClose, % title_ee%A_Index%
	}
}
return


launch1:
IfWinExist, %title1%
{
	winmove, %title1%,, %panel_start_position_x1%, %panel_start_position_y1%
	return
}
run, VCR1_XDCAM50.%ahk_exe%,,,vcr1_pid
winwait, %title1%,, 2
winmove, %title1%,, %panel_start_position_x1%, %panel_start_position_y1%
return

launch2:
IfWinExist, %title2%
{
	winmove, %title2%,, %panel_start_position_x2%, %panel_start_position_y2%
	return
}
run, VCR2_XDCAM50.%ahk_exe%
winwait, %title2%,, 2
winmove, %title2%,, %panel_start_position_x2%, %panel_start_position_y2%
return

launch3:
IfWinExist, %title3%
{
	winmove, %title3%,, %panel_start_position_x3%, %panel_start_position_y3%
	return
}
run, VCR3_XDCAM50.%ahk_exe%
winwait, %title3%,, 2
winmove, %title3%,, %panel_start_position_x3%, %panel_start_position_y3%
return

launch4:
IfWinExist, %title4%
{
	winmove, %title4%,, %panel_start_position_x4%, %panel_start_position_y4%
	return
}
run, VCR4_XDCAM50.%ahk_exe%
winwait, %title4%,, 2
winmove, %title4%,, %panel_start_position_x4%, %panel_start_position_y4%
return


launch5:
IfWinExist, %title5%
{
	winmove, %title5%,, %panel_start_position_x5%, %panel_start_position_y5%
	return
}
run, VCR5_XDCAM50.%ahk_exe%
winwait, %title5%,, 2
winmove, %title5%,, %panel_start_position_x5%, %panel_start_position_y5%
return

save:
gui, submit, nohide
return

button1:                         ; gang rec button
gui, submit, nohide              ; get gang channel select status (ch1 - ch5)

OutputDebug, button1 pressed
loop, 5
{
	OutputDebug, % "channel select status is " . ch%A_Index%	
}
GuiControl, Show, %hredbar%
GuiControl, Hide, %hbluebar%

OutputDebug, %A_TickCount% --------gand rec process started--------

loop, 5
{
	;ControlGet, result%A_index%, Enabled,, %recbutton%, % title%A_index%
	;OutputDebug, % A_Index . " panel rec button status is " . result%A_index%
	;if ch%A_index% and result%A_index%
	if ch%A_index%
		{
			OutputDebug, VTR pannel %A_Index% rec button should be pressed !!
			;ControlFocus, %recbutton%, % title%A_Index%           ; set forcus to rec button
			;ControlClick, %recbutton%, % title%A_Index%,,,1, NA   ; 1 click
			send_udp_text("127.0.0.1", remoteport%A_Index%, "__START_REC__")
			;ToolTip, start rec command [%a_index%] send !!
		}
	
}

/*      ; old manner, removed after "SetControlDelay, -1" is introduced. (removed 2017/12/9)
ifwinexist, %title1%
{
	if ch1 and result1
	{	
		while(result1)
		{
		controlclick, %recbutton%, %title1%
		controlget,result1,Enabled,,button1,%title1%
		}
	}
}

ifwinexist, %title2%
{
	if ch2
	{	
		while (result2)
		{
		controlclick, %recbutton%, %title2%
		controlget,result2,enabled,,button1,%title2%
		}
	}
}

ifwinexist, %title3%
{
	if ch3
	{
		while (result3)
		{
		controlclick, %recbutton%, %title3%
		controlget,result3,enabled,,button1,%title3%
		}
	}
}

ifwinexist, %title4%
{
	if ch4
	{
		while (result4)	
		{
		controlclick, %recbutton%, %title4%	
		controlget,result4,enabled,,button1,%title4%
		}
	}
}

ifwinexist, %title5%
{
	if ch5
	{
		while (result5)	
		{
		controlclick, %recbutton%, %title5%	
		controlget,result5,enabled,,button1,%title5%
		}
	}
}
*/
sleep, 100
return


button2:        		  ; gang stop button
gui, submit, nohide       ; get gang channel select status (ch1 - ch5)
OutputDebug, button2 pressed
OutputDebug, %A_TickCount% --------gand stop process started--------
GuiControl, Hide, %hredbar%
GuiControl, Show, %hbluebar%

loop, 5
{
OutputDebug, % "channel select status is " . ch%A_Index%	
}

Loop, 5
{
	;ControlGet, result%A_index%, Enabled,, %stopbutton%, % title%A_index%
	;if ch%A_index% and result%A_index%
	if ch%A_index%
	{
		OutputDebug, VTR pannel %A_Index% stop button should be pressed !!
		;ControlFocus, %stopbutton%, % title%A_Index%			; set foruc to stop button
		;ControlClick, %stopbutton%, % title%A_Index%,,,1, NA    ; do single click
		send_udp_text("127.0.0.1", remoteport%A_Index%, "__STOP_REC___")
	}
}



/*              ; old manner, removed 2017/12/9
ifwinexist, %title1%
{
	if ch1 and result1
	{	
		while(result1)
		{
		controlclick, %stopbutton%, %title1%
		controlget,result1,Enabled,,button2,%title1%
		}
	}
}

ifwinexist, %title2%
{
	if ch2
	{	
		while (result2)
		{
		controlclick, %stopbutton%, %title2%
		controlget,result2,enabled,,button2,%title2%
		}
	}
}

ifwinexist, %title3%
{
	if ch3
	{
		while (result3)
		{
		controlclick, %stopbutton%, %title3%
		controlget,result3,enabled,,button2,%title3%
		}
	}
}

ifwinexist, %title4%
{
	if ch4
	{
		while (result4)	
		{
		controlclick, %stopbutton%, %title4%	
		controlget,result4,enabled,,button2,%title4%
		}
	}
}


ifwinexist, %title5%
{
	if ch5
	{
		while (result5)	
		{
		controlclick, %stopbutton%, %title5%	
		controlget,result5,enabled,,button2,%title5%
		}
	}
}



*/
sleep, 100

return


;=====================================================================
!h::
WinActivate, Gang Controller          ; activate gang controller window (alt + h)
return

~!0::
SetTimer, button1, -1    ; Start REC all channel, alt + 0
return

~^!0::
SetTimer, button2, -1   ; Stop REC all channel, Control + alt + 0
return
;=====================================================================  example ;		ControlClick,, ahk_id %hpreview1%,,,1, NA


!1::
SetTimer, launch1, -1				; open VTR1 panel
;ControlClick,, ahk_id %hlaunch1%,,,1,NA  ; open VTR1 panel
WinActivate, %title1%
winmove, %title1%,, %panel_start_position_x1%, %panel_start_position_y1%
return

!2::
SetTimer, launch2, -1				; open VTR1 panel
;ControlClick,, ahk_id %hlaunch2%,,,1,NA ; open VTR2 panel
WinActivate, %title2%
winmove, %title2%,, %panel_start_position_x2%, %panel_start_position_y2%
return

!3::
SetTimer, launch3, -1				; open VTR1 panel
;ControlClick,, ahk_id %hlaunch3%,,,1,NA ; open VTR3 panel
WinActivate, %title3%
winmove, %title3%,, %panel_start_position_x3%, %panel_start_position_y3%
return

!4::
SetTimer, launch4, -1				; open VTR1 panel
;ControlClick,, ahk_id %hlaunch4%,,,1,NA ; open VTR4 panel
WinActivate, %title4%
winmove, %title4%,, %panel_start_position_x4%, %panel_start_position_y4%
return

!5::
SetTimer, launch5, -1				; open VTR1 panel
;ControlClick,, ahk_id %hlaunch5%,,,1,NA ; open VTR5 panel
WinActivate, %title5%
winmove, %title5%,, %panel_start_position_x5%, %panel_start_position_y5%
return

;=====================================================================

^!1::										; control - alt - 1 ; close VCR panel 1
SendMessage, 0x10,,,,%title1%
return

^!2::										; control - alt - 1 ; close VCR panel 2
SendMessage, 0x10,,,,%title2%
return

^!3::										; control - alt - 1 ; close VCR panel 3
SendMessage, 0x10,,,,%title3%
return

^!4::										; control - alt - 1 ; close VCR panel 4
SendMessage, 0x10,,,,%title4%
return

^!5::										; control - alt - 1 ; close VCR panel 5
SendMessage, 0x10,,,,%title5%
return

;=====================================================================


!q::
	ControlClick, %eebutton%, %title1%,,,1,NA  ; open VTR1 EE
return

!w::
	ControlClick, %eebutton%, %title2%,,,1,NA  ; open VTR2 EE
return

!e::
	ControlClick, %eebutton%, %title3%,,,1,NA  ; open VTR3 EE
return

!r::
	ControlClick, %eebutton%, %title4%,,,1,NA  ; open VTR4 EE
return

!t::
	ControlClick, %eebutton%, %title5%,,,1,NA  ; open VTR5 EE
return

;=====================================================================
!a::
ControlGet, outvar, enabled,,%recbutton%, %title1%
if outvar
	ControlClick, %recbutton%, %title1%,,,1,NA  ; start REC, VTR1,
return

!s::
ControlGet, outvar, enabled,,%recbutton%, %title2%
if outvar
	ControlClick, %recbutton%, %title2%,,,1,NA  ; start REC, VTR2
return

!d::
ControlGet, outvar, enabled,,%recbutton%, %title3%
if outvar
	ControlClick, %recbutton%, %title3%,,,1,NA  ; start REC, VTR3
return

!f::
ControlGet, outvar, enabled,,%recbutton%, %title4%
if outvar
	ControlClick, %recbutton%, %title4%,,,1,NA  ; start REC, VTR4
return

!g::
ControlGet, outvar, enabled,,%recbutton%, %title5%
if outvar
	ControlClick, %recbutton%, %title5%,,,1,NA  ; start REC, VTR5
return

;=====================================================================
^!a::
ControlGet, outvar, enabled,,%stopbutton%, %title1%
if outvar
	ControlClick, %stopbutton%, %title1%,,,1,NA  ; stop REC, VTR1
return

^!s::
ControlGet, outvar, enabled,,%stopbutton%, %title2%
if outvar
	ControlClick, %stopbutton%, %title2%,,,1,NA  ; stop REC, VTR2
return

^!d::
ControlGet, outvar, enabled,,%stopbutton%, %title3%
if outvar
	ControlClick, %stopbutton%, %title3%,,,1,NA  ; stop REC, VTR3
return

^!f::
ControlGet, outvar, enabled,,%stopbutton%, %title4%
if outvar
	ControlClick, %stopbutton%, %title4%,,,1,NA  ; stop REC, VTR4
return

^!g::
ControlGet, outvar, enabled,,%stopbutton%, %title5%
if outvar
	ControlClick, %stopbutton%, %title5%,,,1,NA  ; stop REC, VTR5
return

;=====================================================================
;   --title ""Preview Window " . CHNAME . "

!z::
WinClose, %title_ee1%      ; Close EE window, panel 1
return

!x::
WinClose, %title_ee2%   ; Close EE window, panel 2
return

!c::
WinClose, %title_ee3%      ; Close EE window, panel 3
return

!v::
WinClose, %title_ee4%      ; Close EE window, panel 4
return

!b::
WinClose, %title_ee5%      ; Close EE window, panel 5
return
;=====================================================================

;	Arrange EE, panel window
!l::   ; Activate EE  Window
loop, 5
{
	WinMove, % title_ee%A_Index% ,, % ee_position_array_x[A_Index], % ee_position_array_y[A_Index], 480, 270			; Move EE window, VTR Panel to default position and default size
	WinMove, % title%A_Index%,, % panel_start_position_x%A_Index%, % panel_start_position_y%A_Index%
}

return
;=====================================================================

^!l::   ; Arrange EE or Confi Window (quad layout)

loop, 5
{
	WinMove, %  title_ee%A_Index%,, win_position_x[A_Index],  win_position_y[A_Index], 960, 540				; Make EE windows to large quad layout and large size
}
loop, 5
{
	WinActivate, %  title_ee%A_Index%        ; Make visible last window
}
return

;=====================================================================


!up::  ; re-activate home, vtr panel window
OutputDebug, alt up pressed
WinActivate, Gang Controller
WinGet, id, list, Copy Manager
Loop, %id%
{
	this_id := id%A_Index%
	WinActivate, ahk_id  %this_id%
}
SetTimer,  resetposition, -1
;ControlFocus, Button16, Gang Controller      ; Button16 is R button is Gang Controller
;ControlClick, Button16, Gang Controller
return

;=====================================================================

~!Down::    ; get panel 1 text paste panel 2,3,4

ControlGet, paneltext, line, 1, edit1, %title1%
;'StringReplace, paneltext, paneltext, % "-" . name_array[1]
OutputDebug, %paneltext%

Loop, 5
{
	;ControlSetText, edit1, % paneltext . "-" . name_array[A_Index], % title%A_Index%
	ControlSetText, edit1, % paneltext, % title%A_Index%
}
return

paste_title_network:			; added 2019/6/12			Synchronize user input text from remote server command
paneltext := title_received
Loop, 5
	ControlSetText, edit1, % paneltext, % title%A_Index%
return



;=====================================================================


+!^up::                     			; activate encoder window (form verifying ffmpeg console output)
loop, 5
	WinActivate, % title_encoder_main%A_Index%
return

;=====================================================================

+!^down::								; minimize encoder window (finish verifying ffmpeg console)
loop, 5
	WinMinimize, % title_encoder_main%A_Index%
return

;=====================================================================

+!^left::								; open script directory
run, explorer.exe %A_ScriptDir%
return

;=====================================================================



GuiClose:
AHKsock_Close()
ExitApp

AHKsockErrors(iError, iSocket) {
    OutputDebug, % "Server - Error " iError " with error code = " ErrorLevel ((iSocket <> -1) ? " on socket " iSocket : "")
}


port_from_url(url)			; example   udp://127.0.0.1:50001  -> 50001
{
	RegExMatch(url, ":\d+$", lastnumber)
	RegExMatch(lastnumber, "\d+", lastnumber)
	return lastnumber
}


send_udp_text(addr, port, message)
{
	try
	{
		sender := new udp_send_socket
		sender.connect([addr, port])
		sender.sendtext(message)
		sender := ""
	}
	catch, err
		printobjectlist(err)
}


class udp_send_socket				; Very Simple udp send socket class from socket.ahk. Modified by sendust 2020/11/7
{
	static WM_SOCKET := 0x9987, MSG_PEEK := 2
	static FD_READ := 1, FD_ACCEPT := 8, FD_CLOSE := 32
	static Blocking := True, BlockSleep := 50
	static PORT_BIND := 0

	static ProtocolId := 17 ; IPPROTO_UDP
	static SocketType := 2  ; SOCK_DGRAM

	__New(Socket:=-1)
	{
		static Init
		if (!Init)
		{
			DllCall("LoadLibrary", "Str", "Ws2_32", "Ptr")
			VarSetCapacity(WSAData, 394+A_PtrSize)
			if (Error := DllCall("Ws2_32\WSAStartup", "UShort", 0x0202, "Ptr", &WSAData))
				throw Exception("Error starting Winsock",, Error)
			if (NumGet(WSAData, 2, "UShort") != 0x0202)
				throw Exception("Winsock version 2.2 not available")
			Init := True
		}
		this.Socket := Socket
	}
	
	__Delete()
	{
		if (this.Socket != -1)
			this.Disconnect()
	}
	
	Connect(Address)
	{
		if (this.Socket != -1)
			throw Exception("Socket already connected")
		Next := pAddrInfo := this.GetAddrInfo(Address)
		while Next
		{
			ai_addrlen := NumGet(Next+0, 16, "UPtr")
			ai_addr := NumGet(Next+0, 16+(2*A_PtrSize), "Ptr")
			if ((this.Socket := DllCall("Ws2_32\socket", "Int", NumGet(Next+0, 4, "Int")
				, "Int", this.SocketType, "Int", this.ProtocolId, "UInt")) != -1)
			{
				if (DllCall("Ws2_32\WSAConnect", "UInt", this.Socket, "Ptr", ai_addr
					, "UInt", ai_addrlen, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0, "Int") == 0)
				{
					DllCall("Ws2_32\freeaddrinfo", "Ptr", pAddrInfo) ; TODO: Error Handling
					return this.EventProcRegister(this.FD_READ | this.FD_CLOSE)
				}
				this.Disconnect()
			}
			Next := NumGet(Next+0, 16+(3*A_PtrSize), "Ptr")
		}
		throw Exception("Error connecting")
	}


	Disconnect()
	{
		; Return 0 if not connected
		if (this.Socket == -1)
			return 0
		
		; Unregister the socket event handler and close the socket
		this.EventProcUnregister()
		if (DllCall("Ws2_32\closesocket", "UInt", this.Socket, "Int") == -1)
			throw Exception("Error closing socket",, this.GetLastError())
		this.Socket := -1
		return 1
	}
	
	
	Send(pBuffer, BufSize, Flags:=0)
	{
		if ((r := DllCall("Ws2_32\send", "UInt", this.Socket, "Ptr", pBuffer, "Int", BufSize, "Int", Flags)) == -1)
			throw Exception("Error calling send",, this.GetLastError())
		return r
	}
	
	SendText(Text, Flags:=0, Encoding:="UTF-8")
	{
		VarSetCapacity(Buffer, StrPut(Text, Encoding) * ((Encoding="UTF-16"||Encoding="cp1200") ? 2 : 1))
		Length := StrPut(Text, &Buffer, Encoding)
		return this.Send(&Buffer, Length - 1)
	}

	GetAddrInfo(Address)
	{
		; TODO: Use GetAddrInfoW
		Host := Address[1], Port := Address[2]
		VarSetCapacity(Hints, 16+(4*A_PtrSize), 0)
		NumPut(this.SocketType, Hints, 8, "Int")
		NumPut(this.ProtocolId, Hints, 12, "Int")
		if (Error := DllCall("Ws2_32\getaddrinfo", "AStr", Host, "AStr", Port, "Ptr", &Hints, "Ptr*", Result))
			throw Exception("Error calling GetAddrInfo",, Error)
		return Result
	}

	AsyncSelect(lEvent)
	{
		if (DllCall("Ws2_32\WSAAsyncSelect"
			, "UInt", this.Socket    ; s
			, "Ptr", A_ScriptHwnd    ; hWnd
			, "UInt", this.WM_SOCKET ; wMsg
			, "UInt", lEvent) == -1) ; lEvent
			throw Exception("Error calling WSAAsyncSelect",, this.GetLastError())
	}
	
	GetLastError()
	{
		return DllCall("Ws2_32\WSAGetLastError")
	}
}



showobjectlist(myobject)			; show object in tooltip
{
	temp := ""
	for key, val in myobject
		temp .= key . " ---->  " . val . "`r`n"
	ToolTip % temp
}

printobjectlist(myobject)			; show object in stdout
{
	temp := "`r`n--------------------   Print object list  ------------------------`r`n"
	for key, val in myobject
		temp .= key . " ---->  " . val . "`r`n"
	FileAppend, %temp%, *
	return temp
}

