/*
    sVCR Network Remote Enhanced Version
    Maintained by sendust
    
    2020/10/27
      Increase address 1 to 9
    2020/11/12      Improve address parsing
        

*/

#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
#SingleInstance force
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.
SetTitleMatchMode, slow
#Include %A_ScriptDir%\AHKsock.ahk
AHKsock_ErrorHandler("AHKsockErrors")

menu, tray, icon, .\icon\remote.ico

global iSendSocket = 0, ipaddress, port
list_address := Object()

Loop, 9
{
    IniRead, ipaddress, remote2020.ini, network, address%A_Index%, NONE
    if (RegExMatch(ipaddress, "\d+.\d+.\d+.\d+") = 1)
        list_address.push(ipaddress)
}
IniRead, port, remote2020.ini, network, port, 3441

IniRead, CHNAME, svcr1.ini, name, name, VTR1	            	; read CHNAME
title_vtrpanel := "SBS sVCR v2-" . CHNAME . " by sendust"

printobjectlist(list_address)


cmdrec = _REC__          ; protocol string, REC, STOP, EE(by Kim Syehoon)
cmdstop = _STOP_
cmdsettitle = _SETT_
cmdEE=_EE_

remote_panel_x := 250
remote_panel_y := A_ScreenHeight - 600
 
gui, new,, Gang REMOTE%remotenumber%
gui, margin, 10
gui, add, button, xm ym w110 h40 gbutton1 hwndhbutton1, REC
gui, add, progress, xm yp+42 w110 h10 cred hwndhredbar, 100

gui, add, button, xm yp+30 w110 h40 gbutton2 hwndhbutton2, STOP
gui, add, progress, xm yp+42 w110 h10 cblue hwndhbluebar, 100

gui, add, button, xm yp+30 w110 h40 gbutton3 hwndhbutton3, EE

; gui, add, text, xm yp+60 w160 h40 hwndhtext,  REMOTE.2020
gui, add, text, xm yp+90 w160 h40 hwndhtext,  REMOTE.2024 by Kim Syehoon
Gui, add, StatusBar, hwndhstatus, Application Start
gui, show, x%remote_panel_x% y%remote_panel_y%  w160
gui, -MinimizeBox

GuiControl, Hide, %hredbar%
GuiControl, Hide, %hbluebar%

Gui, Font, s15
GuiControl, font, %htext%

SetTimer, show_address_list, -500

return

show_address_list:
GuiControl,, %hstatus%, % "Number of address " . list_address.MaxIndex()
return



button1:
    GuiControl, Hide, %hredbar%
    GuiControl, Hide, %hbluebar%
    count_success := 0
    
    Loop, % list_address.MaxIndex()
    {
        ipaddress := list_address[A_Index]
        if (sendresult := sendcommand(ipaddress, cmdrec)) = 12     ; send 12 byte (6 character)
            count_success += 1
    }
    if (count_success = list_address.MaxIndex())
        GuiControl, Show, %hredbar%

    GuiControl,, %hstatus%, %count_success% client(s) accepted 
return


button2:
    GuiControl, Hide, %hredbar%
    GuiControl, Hide, %hbluebar%
    count_success := 0
    
    Loop, % list_address.MaxIndex()
    {
        ipaddress := list_address[A_Index]
        if (sendresult := sendcommand(ipaddress, cmdstop)) = 12     ; send 12 byte (6 character)
            count_success += 1
    }
    if (count_success = list_address.MaxIndex())
        GuiControl, Show, %hbluebar%

    GuiControl,, %hstatus%,  %count_success% client(s) accepted 
return

button3:
    count_success := 0

    Loop, % list_address.MaxIndex()
        {
            ipaddress := list_address[A_index]
            if(sendresult:=sendcommand(ipaddress,cmdee))=12
                count_success+=1
        }

GuiControl,, %hstatus%,  %count_success% client(s) accepted 
return


~!Down::    ; get panel 1 text and send to network remote gang
count_success := 0
ControlGet, paneltext, line, 1, edit1, %title_vtrpanel%
GuiControl, Hide, %htext%

    Loop, % list_address.MaxIndex()
    {
        ipaddress := list_address[A_Index]
        if ((sendresult := sendcommand(ipaddress,  "_SETT_" . paneltext)) > 0)
            count_success += 1
    }
    
    if (count_success = list_address.MaxIndex())
        SetTimer, showtext, -100

    GuiControl,, %hstatus%,  %count_success% client(s) accepted 

return


showtext:
GuiControl, Show, %htext%
return



sendcommand(ipaddress, command)
{
    len_command := StrLen(command)      ; length of command text
    if i := AHKsock_Connect(ipaddress, port, "ConnEvent")
    {
        MsgBox ,,CAUTION !! [%ipaddress%], Error Opening Socket with code %i%, 1
    }
    OutputDebug, %ipaddress%, %port%
    sleep 100              ; wait server tcp response time

    if iSendSocket > 0     ; socket allocation success
    {
    	;sendresult := AHKsock_Send(iSendSocket, &command, 6)   ; protocol length is 12 byte (6 character)
        sendresult := AHKsock_Send(iSendSocket, &command, len_command * 2)      ; unicode (2 byte / character)
        
    }                                                           ; sendresult get transferred number of character (on success)
 if (sendresult <= 0) or (iSendSocket <= 0)               ; fail to open socket or fail to send command
    MsgBox,,CAUTION !! [%ipaddress%], Device Not Ready, 1
      
    AHKsock_Close()
    OutputDebug, sendresult = %sendresult%
    return sendresult
}


ConnEvent(sEvent, iSocket, sName = 0, sAddr = 0, sPort = 0, ByRef bData = 0, iLength = 0) 
{
    iSendSocket := iSocket
}


printobjectlist(myobject)
{
	temp := "`r`n--------------------   Print object list  ------------------------`r`n"
	for key, val in myobject
		temp .= key . " ---->  " . val . "`r`n"
	FileAppend, %temp%, *
	return temp
}




~!0::
;ControlFocus, button1, Gang REMOTE1
;ControlClick, button1, Gang REMOTE1,,,1,NA    ; Start REC , REMOTE 1
SetTimer, button1, -1
return


~^!0::
;ControlFocus, button2, Gang REMOTE1
;ControlClick, button2, Gang REMOTE1,,,1,NA    ; Start REC , REMOTE 1
SetTimer, button2, -1
return




GuiClose:
AHKsock_Close()
ExitApp

AHKsockErrors(iError, iSocket) 
{
    OutputDebug, % "Server - Error " iError " with error code = " ErrorLevel ((iSocket <> -1) ? " on socket " iSocket : "")
}