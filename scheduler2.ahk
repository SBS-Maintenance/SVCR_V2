/* scheduler for SBS sVCR Recorder
Maintained by sendust
Last edit  : 2020/5/28
2020/5/28 ; backup previous schedule data,
					do not save if there is no schedule data
2020/11/9	; change command send method (control click -> udp command)
*/

#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.
SetKeyDelay, 30, 20
#SingleInstance, ignore

Menu, Tray, icon, .\icon\scheduler.ico
Menu, Tray, NoStandard
Menu, Tray, Click, 1
Menu, Tray, Add, Restore, Restore
Menu, Tray, Default, Restore

OnMessage(0x112, "WM_SYSCOMMAND")


title_vcr := Object()
title_panel := Object()
data_lv := Object()
handle_gui := Object()
file_save := A_WorkingDir . "\scheduler_save.txt"
title_gui =  sVCR Scheduler v2 by sendust 2020/11/09
recbutton = button3
stopbutton = button4
	

mylog := new cLOG(A_ScriptFullPath)

Gui, margin, 5, 5
Gui, add, Edit, xm ym w400 h20 vtitle_text hwndhtitle_text, PROGRAM NAME HERE
Gui, add, text, xm  yp+30 , 시작 시간
Gui, add, datetime, xp+100 yp-3 w100 h20 vstart_time hwndhstart_time, MM/dd HH:mm
Gui, add, text, xm  yp+30 , 종료 시간
Gui, add, datetime, xp+100 yp-3 w100 h20  vend_time hwndhend_time, MM/dd HH:mm
Gui, add, Checkbox, xm+230 ym+30 vchkbox_vcr1 w100 hwndhchkbox_vcr1, VCR1
Gui, add, Checkbox, xm+230 yp+20 vchkbox_vcr2 w100 hwndhchkbox_vcr2, VCR2
Gui, add, Checkbox, xm+230 yp+20 vchkbox_vcr3 w100 hwndhchkbox_vcr3, VCR3
Gui, add, Checkbox, xm+230 yp+20 vchkbox_vcr4 w100 hwndhchkbox_vcr4, VCR4
Gui, add, Checkbox, xm+230 yp+20 vchkbox_vcr5 w100 hwndhchkbox_vcr5, VCR5
Gui, add, Checkbox, xp+120 ym+30 vchk_week1 hwndhchk_week1, 일
Gui, add, Checkbox, xp yp+20 vchk_week2 hwndhchk_week2, 월
Gui, add, Checkbox, xp yp+20 vchk_week3 hwndhchk_week3, 화
Gui, add, Checkbox, xp yp+20 vchk_week4 hwndhchk_week4, 수
Gui, add, Checkbox, xp yp+20 vchk_week5 hwndhchk_week5, 목
Gui, add, Checkbox, xp yp+20 vchk_week6 hwndhchk_week6, 금
Gui, add, Checkbox, xp yp+20 vchk_week7 hwndhchk_week7, 토
Gui, add, Button, xm ym+100 w80 h20 gbtn_load, 불러오기
Gui, add, Button, xp+100 yp w80 h20 gbtn_save, 저장하기
Gui, add, Text, xm  yp+30 w290 h30 hwndhclock center, [----/--/--] --:--
Gui, add, Button, xm yp+35 w80 h30 gbtn_add, 추가 ▼
Gui, add, Button, xp+100 yp w80 h30 gbtn_modify, 수정 ▲
Gui, add, Button, xp+150 yp w80 h30 gbtn_delete, 삭제 ※
Gui, Add, Progress, xm yp+35 w400 h5 hwndhprogress cBlue, 100
Gui, add, ListView, xm yp+10 w400 h200 Grid, no|시작|제목|종료|WEEK|VCR
Gui, show,, %title_gui%


Gui, Font, s20
GuiControl, Font, %hclock%

IniRead, remoteurl1, svcr1.ini, url, progress, udp://127.0.0.1:50001		; read udp url
IniRead, remoteurl2, svcr2.ini, url, progress, udp://127.0.0.1:50002		; read udp url
IniRead, remoteurl3, svcr3.ini, url, progress, udp://127.0.0.1:50003		; read udp url
IniRead, remoteurl4, svcr4.ini, url, progress, udp://127.0.0.1:50004		; read udp url
IniRead, remoteurl5, svcr5.ini, url, progress, udp://127.0.0.1:50005		; read udp url

remoteport := object()

loop, 5
	remoteport[A_Index] := port_from_url(remoteurl%A_Index%)


Loop, 5
{
	IniRead, temp, svcr%A_Index%.ini, name, name
	title_vcr[A_Index] := temp
	title_panel[A_Index] := "SBS sVCR v2-" . temp . " by sendust"
	handle_gui.vcr[A_Index] := hchkbox_vcr%A_Index%				; save handle of 5 vcr check box
	GuiControl, text, % handle_gui.vcr[A_Index], %temp%			; update VTR1~5 check box's  caption
}

Loop, 7			; save handle of 7 week day check box
	handle_gui.week[A_Index] := hchk_week%A_Index%

printobjectlist(title_vcr)
printobjectlist(title_panel)
printobjectlist(remoteport)

SetTimer, show_progress, -1000
SetTimer, show_time, -1100
return

GuiClose:
ExitApp


show_progress:
second_to_progress(hprogress)
SetTimer, show_progress, % -600				; 60000msec / 100 percent (update progress bar every 600ms)
return


submit_gui:
Gui, Submit, NoHide
if (end_time <= start_time)			; validate start and end time
{
	end_time := start_time
	EnvAdd, end_time, 1, minute
	GuiControl,, %hend_time%, %end_time%
}
data_lv.cnt := LV_GetCount() + 1
data_lv.week := chk_week1 . chk_week2 . chk_week3 . chk_week4 . chk_week5 . chk_week6 . chk_week7
data_lv.title := title_text
data_lv.time_start := lv_format_time(start_time)
data_lv.time_end := lv_format_time(end_time)
data_lv.vcr := chkbox_vcr1 . chkbox_vcr2 . chkbox_vcr3 . chkbox_vcr4 . chkbox_vcr5
return


btn_load:
LV_Delete()
Loop, Read, %file_save%
{
	data_lv := parsing_saved(A_LoopReadLine)
	data_lv.cnt := A_Index
	LV_PutAll(data_lv)
	printobjectlist(data_lv)
}
LV_ModifyColAuto()
return

btn_save:
if LV_GetCount()
{
	FileMove, %file_save%, %file_save%.bak, 1				; backup previous schedule data
}
else
	return		; return if there is no schedule data
Loop, % LV_GetCount()
{
	LV_GetAll(A_Index, data_lv)
	FileAppend, % data_lv_saveformat(data_lv), %file_save%
	ToolTip, %A_Index% Line Saved !!!
	Sleep, 20
}
SetTimer, removetooltip, -500
return

btn_add:
gosub, submit_gui
LV_PutAll(data_lv)
LV_ModifyColAuto()
return


btn_modify:
if !LV_GetNext(0)
	return
LV_GetAll(LV_GetNext(0), data_lv)
GuiControl,, %htitle_text%, % data_lv.title
GuiControl,, %hstart_time%, % gui_format_time(data_lv.time_start)
GuiControl,, %hend_time%, % gui_format_time(data_lv.time_end)
Loop, 5
	GuiControl,, % handle_gui.vcr[A_Index], % SubStr(data_lv.vcr, A_Index, 1)
Loop, 7
	GuiControl,, % handle_gui.week[A_Index], % SubStr(data_lv.week, A_Index, 1)
return

btn_delete:
Loop, % LV_GetCount("S")			; Delete until there is no selected row
	LV_Delete(LV_GetNext(0))
Loop, % LV_GetCount()		;	update lv count number
{
	LV_GetAll(A_Index, data_lv)
	data_lv.cnt := A_Index
	LV_ModifyAll(A_Index, data_lv)
}
return


removetooltip:
ToolTip
return


/*
Home::
ListVars
return

end::
*/
show_time:
SetTimer, show_progress, off
display_time(hclock)
second_to_progress(hprogress)
Loop, % LV_GetCount()
{
	LV_GetAll(A_Index, data_lv)
	analysis := read_job(data_lv)
	if check_finish(data_lv)					; mark 'x' at finished event
	{
		data_lv.cnt := "x"
		LV_ModifyAll(A_Index, data_lv)
	}
	FileAppend, `r`n%A_Index%___%analysis%, *
	if (analysis)
		do_job(analysis, data_lv)
}
SetTimer, show_time, % -(60020 - (A_Sec * 1000 + A_MSec)) 			; repeat every 1 minute (60000msec)
SetTimer, show_progress, % -200
return


Minimize:
	Critical
	Gui, Hide
	;Menu, Tray, Icon
Return
   
Restore:
	Critical
	;Menu, Tray, NoIcon
	Gui, Show
Return


WM_SYSCOMMAND(wParam)
{
	If (wParam = 61472) ; minimize
		SetTimer, Minimize, -1
	Else If (wParam = 61728) ; restore
		SetTimer, Restore, -1
}


check_finish(data)
{
	full_time_end := full_format_time(data.time_end)
	if ((data.cnt != "x") and (full_time_end <= A_Now) and (data.week = "0000000"))
		return 1
	else
		return 0
}

read_job(data)
{
	overnight := 0
	if (SubStr(data.time_start, 1, 5) != SubStr(data.time_end, 1, 5))		; compare month, day only
		overnight := 1
	
	time_full_formatted := lv_format_time(A_Now)					; month/day hour:minute   ex)  12/05 12:00
	time_short_formatted := lv_format_time_short(A_Now)		; hour:minute	for weekly program  ex)  12:00
	
	;FileAppend, `r`n%time_full_formatted%, *
	result := ""
	
	if (time_full_formatted = data.time_start)				; single event start
		result = start
	
	if (time_full_formatted = data.time_end)				; single event stop
		result = stop
	
	if SubStr(data.week, A_WDay, 1)						; weekly event decision, start
		if (SubStr(data.time_start, 7, 5) = time_short_formatted)			; compare hour, minute only
			result = week_start

	if SubStr(data.week, A_WDay, 1)						; weekly event decision, start
		if (SubStr(data.time_end, 7, 5) = time_short_formatted)			; compare hour, minute only
			result = week_stop
		
	if overnight
		if SubStr(overnight_stop(data.week), A_WDay, 1)			; weekly event decision, and overnight stop
			if (SubStr(data.time_end, 7, 5) = time_short_formatted)			; compare hour, minute only
				result = week_stop_overnight
	return result
}

do_job(action, data)
{
	count := 0
	Loop, 5
	{
		if SubStr(data.vcr, A_Index, 1)			; check if there is selected VCR
		{
			count += 1
			if InStr(action, "start")
				send_cmd_vtr_panel(A_Index, "start", data)
			if InStr(action, "stop")
				send_cmd_vtr_panel(A_Index, "stop", data)
		}
	}
	return count
}

click_vtr_panel(no_vtr, btn, data)				; click VTR panel button and set title
{
	global title_panel, recbutton, stopbutton
	title_panel_thisvcr := title_panel[no_vtr]
	FileAppend, `r`nVCR number is %no_vtr%, *				; selected vcr number
	if (btn = "start")
	{
		ControlSetText, Edit1, % data.title, %title_panel_thisvcr%								; set title
		ControlGet, buttoncheck, enabled,, %recbutton%, %title_panel_thisvcr%		; check if button is enabled
		FileAppend, `r`n-----Click rec button with click count ---- %buttoncheck%, *
		SetControlDelay -1
		ControlClick, %recbutton%, %title_panel_thisvcr% ,,, buttoncheck, NA   ; only 1 click if button is enabled
	}
	if (btn = "stop")
	{
		ControlGet, buttoncheck, enabled,, %stopbutton%, %title_panel_thisvcr%		; check if button is enabled
		FileAppend, `r`n-----Click stop button with click count ---- %buttoncheck%, *
		SetControlDelay -1
		ControlClick, %stopbutton%, %title_panel_thisvcr% ,,, buttoncheck, NA   ;  only 1 click if button is enabled
	}
}

send_cmd_vtr_panel(no_vtr, btn, data)				; click VTR panel button and set title, new !!! 2020/11/9   (controlclick -> udp command)
{
	global title_panel, recbutton, stopbutton, remoteport
	title_panel_thisvcr := title_panel[no_vtr]
	FileAppend, `r`nVCR number is %no_vtr%, *				; selected vcr number
	if (btn = "start")
	{
		ControlSetText, Edit1, % data.title, %title_panel_thisvcr%								; set title
		ControlGet, buttoncheck, enabled,, %recbutton%, %title_panel_thisvcr%		; check if button is enabled
		send_udp_text("127.0.0.1", remoteport[no_vtr], "__START_REC__")
		;FileAppend, `r`n-----Click rec button with click count ---- %buttoncheck%, *
		;SetControlDelay -1
		;ControlClick, %recbutton%, %title_panel_thisvcr% ,,, buttoncheck, NA   ; only 1 click if button is enabled
	}
	if (btn = "stop")
	{
		ControlGet, buttoncheck, enabled,, %stopbutton%, %title_panel_thisvcr%		; check if button is enabled
		send_udp_text("127.0.0.1", remoteport[no_vtr], "__STOP_REC___")
		;FileAppend, `r`n-----Click stop button with click count ---- %buttoncheck%, *
		;SetControlDelay -1
		;ControlClick, %stopbutton%, %title_panel_thisvcr% ,,, buttoncheck, NA   ;  only 1 click if button is enabled
	}
}


overnight_stop(week_string)			; return overnight recording stop condition
{
	temp := ""
	temp := SubStr(week_string, 7, 1)
	Loop, 6
		temp .= SubStr(week_string, A_Index, 1) 
	return temp								; example "0110011" return "1011001"			ring shift right
}




lv_format_time(time_input)				; time_input is YYYYMMDDHH24MISS
{
	FormatTime, outputvar, %time_input%, MM/dd HH:mm
	return outputvar
}


lv_format_time_short(time_input)		; output hour, minute only
{
	FormatTime, outputvar, %time_input%, HH:mm
	return outputvar
}


gui_format_time(time_input)			; time_input is MM/dd HH:mm
{
	new_year := A_Year
	month := SubStr(time_input, 1, 2)
	day := SubStr(time_input, 4, 2)
	hour := SubStr(time_input, 7, 2)
	minute := SubStr(time_input, 10, 2)
	if ((A_MM = 12) and (month = 01))		; now is december and scheduled date is january 
		new_year := A_Year + 1
	return new_year . month . day . hour . minute . "00"		; return YYYYMMDDHH24MISS 
}

full_format_time(time_input)			; time_input is MM/dd HH:mm
{
	return gui_format_time(time_input)
}


display_time(handle)
{
	FormatTime, outputvar,, yyyy/MM/dd  HH:mm
	FileAppend, `r`n%outputvar%`r`n, *
	GuiControl,, %handle%, %outputvar%
}


second_to_progress(handle_progress)
{
	percent := 100 - (A_Sec + A_MSec / 1000) / 60 * 100
	GuiControl,, %handle_progress%, %percent%
	return percent
}



printobjectlist(myobject)
{
	FileAppend, `r`n, *
	temp := ""
	for key, val in myobject
		temp .= key . " ---->  " . val . "`r`n"
	FileAppend, %temp%, *
	return temp
}


getlogfile(filename)
{
	SplitPath, filename, outfilename, outdir, outextension, outnamenoext, outdrive
	return  outdir . "\" . outnamenoext . ".log"
}


LV_GetAll(rownumber, ByRef singlerow)
{
	; LV column order ---      
	
	LV_GetText(temp, rownumber, 1)
	singlerow.cnt := temp
	LV_GetText(temp, rownumber, 2)
	singlerow.time_start := temp
	LV_GetText(temp, rownumber, 3)
	singlerow.title := temp
	LV_GetText(temp, rownumber, 4)
	singlerow.time_end := temp
	LV_GetText(temp, rownumber, 5)
	singlerow.week := temp
	LV_GetText(temp, rownumber, 6)
	singlerow.vcr := temp
	
}

; LV_Modify(RowNumber [, Options, NewCol1, NewCol2, ...])
; LV_Add([Options, Field1, Field2, ...])

LV_PutAll(row)
{
	LV_Add(, row.cnt, row.time_start, row.title, row.time_end, row.week, row.vcr)
}

LV_ModifyAll(cnt, row)
{
	LV_Modify(cnt,, row.cnt, row.time_start, row.title, row.time_end, row.week, row.vcr)
}



LV_ModifyColAuto()
{
	
	Loop, % LV_GetCount("Column")		; Total Number of column
	LV_ModifyCol(A_Index, "AutoHdr")
}


data_lv_saveformat(singlerow)
{
	field1 := singlerow.time_start
	field2 := singlerow.title
	field3 := singlerow.time_end
	field4 := singlerow.week
	field5 := singlerow.vcr
	return field1 . "|" . field2 . "|" . field3 . "|" . field4 . "|" . field5 . "`r`n"
}

parsing_saved(text)
{
	data := Object()
	singlerow := StrSplit(text, "|")
	data.time_start := singlerow[1]
	data.title := singlerow[2]
	data.time_end := singlerow[3]
	data.week := singlerow[4]
	data.vcr := singlerow[5]
	return data
}


class cLOG
{
	static logfile :=""
	
	__New(filename)
	{
		SplitPath, filename, outfilename, outdir, outextension, outnamenoext, outdrive
		this.logfile := outdir . "\" . outnamenoext . ".log"
	}

	update(text)
	{
		logfile := this.logfile
		FileGetSize, size_file, %logfile%
		FormatTime, time_log,, yyyy/MM/dd HH:mm.ss
		FileAppend, [%time_log%_%A_MSec%]  - %text%`r`n, %logfile%
		if (size_file > 3000000)
		{
			str_message := "Log File size is greater than limit... move to archive folder"
			FileAppend, [%time_log%_%A_MSec%]  - %str_message%`r`n, %logfile%
			this.move_logfile(logfile)
		}
	}

	updateall(text)
	{
		global hstatus
		this.update(text)
		GuiControl,, %hstatus%, % text . "  " . this.now_dhms()
	}

	move_logfile()								; check log file size and rename it
	{
		filename := this.logfile
		FileGetSize, filesize, %filename%
		SplitPath, filename, outfilename, outdir, outextension, outnamenoext, outdrive
		if !FileExist(outdir . "\log")
		{
			FileCreateDir, %outdir%\log
			if ErrorLevel
			{
				this.updateall("Creating Log backup folder fail")
				return
			}
		}
		filename_target := outdir . "\log\" .  outnamenoext . "_" . A_Now . "." . outextension
		FileMove, %filename%, %filename_target%
		return filename_target
	}

	get_logfilename()
	{
		return this.logfile
	}
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

