#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
#SingleInstance, Ignore
#WinActivateForce
#Include mediainfo.ahk
SetBatchLines, -1
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.
AutoTrim, on
;SetKeyDelay, 200, 50
;   last update 2019/5/31



binary_ffmpeg = %A_WorkingDir%\bin\ffmpeg2018.exe
binary_mpv = %A_WorkingDir%\bin\mpv-x86_64-20181002\mpv.com
binary_mpv = %A_WorkingDir%\bin\mpv-i686-20170423\mpv.com


mxfcheck = 1
play_pid := -1
playingtitle = Editor Play                        ; set initial mpv console title (prepare empty START TIME, END TIME clicking)
menu, tray, icon, .\icon\movie-editor.ico
if A_IsCompiled
	menu, tray, NoIcon

wtitle = Easy Movie Editor v2 (20190601)

RegRead, position_x, HKEY_LOCAL_MACHINE\SOFTWARE\sendust\%wtitle%, start_x
RegRead, position_y, HKEY_LOCAL_MACHINE\SOFTWARE\sendust\%wtitle%, start_y
RegRead, outfolder, HKEY_LOCAL_MACHINE\SOFTWARE\sendust\%wtitle%, outfolder

IfNotExist, %outfolder%
	outfolder = c:\

if position_x not between 0 and %A_ScreenWidth%
	position_x = 100
if position_y not between 0 and %A_ScreenHeight%
	position_y = 100
if !outfolder
	outfolder = c:\

media := object()						; add 2910/3/13
mpv_filter := object()					; add 2910/3/13
mpvrun := Object()				; mpv console object
minfo := Object()
encoder_filter := object()			; Encoder filter

minfo := new MediaInfo()

/*
mpv_filter["mono-4"] := "--lavfi-complex=[aid1][aid2][aid3][aid4]amerge=inputs=4[a1];[a1]asplit[as1][as2];[as1]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vf];[vf]yadif=0[deint];[deint]scale=700:400[vsize];[vsize][vvolume]overlay=x=20:y=20[vo];[as2]pan=stereo|c0=c0+c2|c1=c1+c3[ao]"
mpv_filter["mono-8"] := "--lavfi-complex=[aid1][aid2][aid3][aid4][aid5][aid6][aid7][aid8]amerge=inputs=8[a1];[a1]asplit[as1][as2];[as1]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vf];[vf]yadif=0[deint];[deint]scale=700:400[vsize];[vsize][vvolume]overlay=x=20:y=20[vo];[as2]pan=stereo|c0=c0+c2|c1=c1+c3[ao]"
mpv_filter["stereo-1"] := "--lavfi-complex=[aid1]asplit[as1][as2];[as1]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vf];[vf]yadif=0[deint];[deint]scale=700:400[vsize];[vsize][vvolume]overlay=x=20:y=20[vo];[as2]pan=stereo|c0=c0|c1=c1[ao]"
mpv_filter["5.1-1"] := "--lavfi-complex=[aid1]asplit[as1][as2];[as1]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vf];[vf]yadif=0[deint];[deint]scale=700:400[vsize];[vsize][vvolume]overlay=x=20:y=20[vo];[as2]pan=stereo|c0=c0|c1=c1[ao]"
mpv_filter["7.1-1"] := "--lavfi-complex=[aid1]asplit[as1][as2];[as1]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vf];[vf]yadif=0[deint];[deint]scale=700:400[vsize];[vsize][vvolume]overlay=x=20:y=20[vo];[as2]pan=stereo|c0=c0|c1=c1[ao]"

*/

mpv_filter["noaudio"] := ""
mpv_filter["mono-1"] := "--lavfi-complex=[aid1]asplit[as1][as2];[as1]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vfmt];[vfmt][vvolume]overlay=x=20:y=20[vo]"
mpv_filter["mono-2"] := "--lavfi-complex=[aid1][aid2]amerge=inputs=2[a1];[a1]asplit[as1][as2];[as1]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vfmt];[vfmt][vvolume]overlay=x=20:y=20[vo]"
mpv_filter["mono-4"] := "--lavfi-complex=[aid1][aid2][aid3][aid4]amerge=inputs=4[a1];[a1]asplit[as1][as2];[as1]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vfmt];[vfmt][vvolume]overlay=x=20:y=20[vo]"
mpv_filter["mono-8"] := "--lavfi-complex=[aid1][aid2][aid3][aid4][aid5][aid6][aid7][aid8]amerge=inputs=8[a1];[a1]asplit[as1][as2];[as1]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vfmt];[vfmt][vvolume]overlay=x=20:y=20[vo]"
mpv_filter["stereo-1"] := "--lavfi-complex=[aid1]asplit[as1][as2];[as1]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vfmt];[vfmt][vvolume]overlay=x=20:y=20[vo]"
mpv_filter["stereo-2"] := mpv_filte["mono-2"]
mpv_filter["stereo-3"] := "--lavfi-complex=[aid1][aid2][aid3]amerge=inputs=3[a1];[a1]asplit[as1][as2];[as1]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vfmt];[vfmt][vvolume]overlay=x=20:y=20[vo]"
mpv_filter["stereo-4"] := mpv_filter["mono-4"]
mpv_filter["2 channels-1"] := mpv_filter["stereo-1"]
mpv_filter["2 channels-2"] := mpv_filter["stereo-2"]
mpv_filter["2 channels-3"] := mpv_filter["stereo-3"]
mpv_filter["2 channels-4"] := mpv_filter["stereo-4"]
mpv_filter["4 channels-1"] := mpv_filter["stereo-1"]
mpv_filter["5 channels-1"] := mpv_filter["stereo-1"]
mpv_filter["6 channels-1"] := mpv_filter["stereo-1"]
mpv_filter["7 channels-1"] := mpv_filter["stereo-1"]
mpv_filter["8 channels-1"] := mpv_filter["stereo-1"]
mpv_filter["16 channels-1"] := mpv_filter["stereo-1"]
mpv_filter["32 channels-1"] := mpv_filter["stereo-1"]



audio_monitor := Object()
audio_monitor["CH1"] := "c0"
audio_monitor["CH2"] := "c1"
audio_monitor["CH3"] := "c2"
audio_monitor["CH4"] := "c3"
audio_monitor["CH5"] := "c4"
audio_monitor["CH6"] := "c5"
audio_monitor["CH7"] := "c6"
audio_monitor["CH8"] := "c7"
audio_monitor["CH1+CH3"] := "c0+c2"
audio_monitor["CH2+CH4"] := "c1+c3"

encoder_filter["interlaced"] := "  -filter_complex ""yadif=0:-1:0"
encoder_filter["mbaff"] :="  -filter_complex ""yadif=0:-1:0"
encoder_filter["paff"] :="  -filter_complex ""yadif=0:-1:0"
encoder_filter["progressive"] := "  -filter_complex ""null"

encoder_filter["noaudio"] := """"
encoder_filter["mono-1"] :=  """"
encoder_filter["mono-2"] := ";amerge=inputs=2[as2]"
encoder_filter["mono-4"] := ";amerge=inputs=4[as2]"
encoder_filter["mono-6"] := ";amerge=inputs=6[as2]"
encoder_filter["mono-8"] := ";amerge=inputs=8[as2]"
encoder_filter["2 channels-1"] := """"
encoder_filter["2 channels-2"] := ";amerge=inputs=2[as2]"
encoder_filter["2 channels-3"] := """"												; 5.1 channel (need auto downmix)
encoder_filter["2 channels-4"] := ";amerge=inputs=4[as2]"
encoder_filter["3 channels-1"] := ";anull[as2]"
encoder_filter["4 channels-1"] := encoder_filter["3 channels-1"]
encoder_filter["5 channels-1"] := encoder_filter["3 channels-1"]
encoder_filter["6 channels-1"] := """"												; 5.1 channel (need auto downmix)
encoder_filter["7 channels-1"] := encoder_filter["3 channels-1"]
encoder_filter["8 channels-1"] := encoder_filter["3 channels-1"]
encoder_filter["16 channels-1"] := encoder_filter["3 channels-1"]
encoder_filter["32 channels-1"] := encoder_filter["3 channels-1"]



gui, new,,%wtitle%
gui -MinimizeBox -Resize
gui, margin, 20, 20
gui, add, DateTime, xm ym w70 h20 vstart_time Choose19990101 1 hwndhstart_time, HH:mm:ss
gui, add, DateTime, xm yp+30 w70 h20 vend_time Choose19990101 1 hwndhend_time, HH:mm:ss
gui, add, edit, xp+70 ym vmillisecond1 hwndhmillisecond1, 000
gui, add, edit, xp yp+30 vmillisecond2 hwndhmillisecond2, 000
gui, add, text, xp+40 ym+3 gpickstart, [START]
gui, add, text, xp yp+30 gpickend, [END]
gui, add, button, xp+80 yp-3 greset, Time code Reset
gui, add, edit, xm yp+50 w300 h35 vfilename hwndhfilename ReadOnly -Multi, Drag and Drop Source File here ~~
gui, add, checkbox, xm yp+45 voutfilenamechange gchangename, Change Output Filename    ; Different file name
gui, add, edit, xm yp+20 w300 h20 voutfilename hwndhoutfilename, OUTPUT FILE NAME
gui, add, button, xm yp+40 gedit w90 h50 hwndhedit, GO!!
gui, add, button, xp+105 yp w90 h50 gplay hwndhplay , PLAY
gui, add, button, xp+105 yp w90 h50 gtarget , Select`r`nTargetFolder
Gui, add, Text, xm yp+80, Monitor Audio Select
Gui, add, DDL, xm+145 yp-5 w60 hwndhaudiomonl vaudiomonl choose1 gaudiomonsel, CH1|CH2|CH3|CH4|CH5|CH6|CH7|CH8|CH1+CH3
Gui, add, DDL, xp+90 w60 hwndhaudiomonr vaudiomonr choose2 gaudiomonsel, CH1|CH2|CH3|CH4|CH5|CH6|CH7|CH8|CH2+CH4
gui, add, text, xm yp+40, SELECT OUTPUT TYPE
gui, add, DropDownList, xm+160 yp-4 Choose1 vout_type hwndhout_type AltSubmit, STREAM COPY|PROXY MP4

gui, add, statusbar, hwndhstatus gstatusbar, Gui loading complete
gui, show, x%position_x% y%position_y%

gui, font, s12 bold
GuiControl, font, %hedit%

GuiControl, disable, %houtfilename%

if %0%
{
	file_full = %1%
	SplitPath, file_full, file_name, file_path, file_extension, file_name_only
	GuiControl,, %hfilename%, %file_name%	
}

btnenablecontrol := [hedit, hplay]

gosub, audiomonsel
GuiControl,, %hstatus%, Target path is %outfolder%
return


1::
Gui, Submit, NoHide
if (StrLen(encoder_filter[media.audio_format]) > 3)
	audio_monitor_filter := ";[as2]pan=stereo|c0=" . audio_monitor[audiomonl] . "|c1=" . audio_monitor[audiomonr] . "[ao]" . """"
else
	audio_monitor_filter := ""

msgbox % encoder_filter[media.scantype] encoder_filter[media.audio_format] audio_monitor_filter


return





statusbar:
run, explorer.exe %outfolder%

return

audiomonsel:
GuiControlGet, audiomonl
GuiControlGet, audiomonr

audio_monitor_filter := ";[as2]pan=stereo|c0=" . audio_monitor[audiomonl] . "|c1=" . audio_monitor[audiomonr] . "[ao]"
if (media.audio_format = "noaudio")
	audio_monitor_filter := ""
;[as1]pan=stereo|c0=c0+c2|c1=c1+c3[ao]

return


#IfWinActive, Easy Movie Editor v
WheelUp::
ControlGetFocus, mycontrol, %wtitle%
	IfEqual, mycontrol, SysDateTimePick321
		Send, {up}
	IfEqual, mycontrol, SysDateTimePick322
		Send, {up}
return

WheelDown::
ControlGetFocus, mycontrol, %wtitle%
	IfEqual, mycontrol, SysDateTimePick321
		Send, {down}
	IfEqual, mycontrol, SysDateTimePick322
		Send, {down}
return

#IfWinActive, Editor Play
i::gosub pickstart
o::gosub pickend
enter::gosub edit
WinActivate, Editor Play
return

mpvchk:
Process, Exist, %play_pid%
If !ErrorLevel			; There is no mpv console process
{
	GuiControl,, %hstatus%, Preview Window Closed
	play_pid := -1
	SetTimer, mpvchk, Off
	mpvrun := ""
	return
}
temp := mpvrun.read()
;Loop, parse, temp, `r
;	FileAppend, % A_Index . "   " . A_LoopField . "  -  " . StrLen(A_LoopField) . "`r`n", mpvoutput2.txt
pbposition := get_pvw_position2(temp)
;GuiControl,, %hstatus%, Preview Position is %pbposition%
StringReplace, pbposition, pbposition, :,,All
;ToolTip % pbposition
SetTimer, mpvchk, -300
return


get_pvw_position2(mpvout)			; old manner (clip board capture)
{
	global hstatus
	static pbposition
	Process, Exist, % play_pid
	if ErrorLevel			; There is mpv console process
	{
		Loop, Parse, mpvout, `r, `n
		{
			foundpos := RegExMatch(A_LoopField, "V:\s+[0-9]+:[0-9]+:[0-9]+.[0-9]+", position)		; Find time code information from last 70 character
			if foundpos
				pbposition := SubStr(position, 4)
		}
		return pbposition
	}
	else			; there is no mpv console process
	{
		return "00:00:00.000"
		play_pid := -1
		GuiControl,, %hstatus%, There is no preview window
	}
}

/*
	Loop, Parse, Clipboard, `n, `r
		lastline := A_LoopField

*/



reset:
start_time = 19990101000000
end_time = 19990101000000
guicontrol,,%hstart_time%, %start_time%
guicontrol,,%hend_time%, %end_time%
guicontrol,,%hmillisecond1%, 000
guicontrol,,%hmillisecond2%, 000

return

changename:
gui, submit, nohide
if outfilenamechange
	guicontrol, enable, %houtfilename%
else
	guicontrol, Disable, %houtfilename%
return

play:
gui, submit, nohide
if !media.fullpath
	return

FormatTime, starttime, %start_time%, HH:mm:ss
starttime = %starttime%.%millisecond1%				; prefare starttime for playing from in point   2019/3/18
filter := mpv_filter[media.audio_format] . audio_monitor_filter
IfWinExist, Editor Play
	WinClose, Editor Play


runstring = %binary_mpv% %filter%  --keep-open --pause --hr-seek=yes --osd-level=3 --osd-fractions --start %starttime% --title "Editor Play - %file_name%"
if (media.width > 1300)
	runstring = %runstring% --window-scale=0.5
if (media.scantype = "interlaced")
	runstring .= " --deinterlace=yes "
runstring = %runstring% "%file_full%"
;Clipboard := runstring			; Debug purpose

mpvrun := new consolerun(runstring,, "CP850")
play_pid := mpvrun.pid

;	run, %mpv% %filter% --osd-level=3 --osd-fractions --start %starttime% --title "Editor Play - %file_name%" "%file_full%",,,play_pid  ; escape character ` is used. for comma (,)

/*  8 channel mxf example
c:\util\mpv-i686-20170423\mpv.com --lavfi-complex=[aid1][aid2][aid3][aid4][aid5][aid6][aid7][aid8]amerge=inputs=8[a1];[a1]asplit[as1][as2];[as1]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vf];[vf]yadif=0[deint];[deint]scale=700:400[vsize];[vsize][vvolume]overlay=x=20:y=20[vo];[as2]pan=stereo|c0=0.5*c0+0.5*c2|c1=0.5*c1+0.5*c2[ao] --no-taskbar-progress 
*/
SetTimer, mpvchk, -500
return


seloutextention:
Gui, Submit, NoHide

file_extension = % media.extension
if (out_type >= 2)
	file_extension = mov
GuiControl,, %hstatus%, Out file Extension is %file_extension%
return


edit:

if !media.fullpath
	return
gui, submit, nohide

duration := SubStr(end_time, 1, 14)
EnvSub, duration, SubStr(start_time, 1, 14), seconds     ; Calculate duration by second unit ( 19990101hhmmss   14 character)


if  millisecond2 < %millisecond1%
{
	duration := duration - 1
	millisecond2 := millisecond2 + 1000
}

duration_millisecond := "000" . (millisecond2 - millisecond1)
StringRight, duration_millisecond, duration_millisecond, 3

duration = %duration%.%duration_millisecond%            ; Extend millisecond unit

if duration <= 0
{
	MsgBox, Check Duration !!
	return
}
FormatTime, ff_start_time, %start_time%, HH:mm:ss
StringReplace, cut_prefix, ff_start_time, :, _, all           ; change : to _ , for file name (use as default prefix)

file_extension := media.extension
targetfile = %outfolder%%file_name_only%_cut_%cut_prefix%.%file_extension%   ;  SplitPath, file_full, file_name, file_path, file_extension, file_name_only

if outfilenamechange
{
	outfilename = %outfilename%                                ; trim left or right space, tab
	targetfile = %outfolder%%outfilename%.%file_extension%
}

starttime = %ff_start_time%.%millisecond1%
OutputDebug, starttime = %ff_start_time%.%millisecond1%
OutputDebug, duration = %duration%

IfExist, %targetfile%
	MsgBox, 0x1004, Oops !, Target Exist !! Overwrite ? (YES or NO)	; always on top (0x1000)
IfMsgBox, No
	return

if (out_type =1)			; STREAM COPY MODE
{
	ffmpeg_PID := transcoding_normal(starttime, duration, file_full, targetfile)
	WinWait, ahk_pid %ffmpeg_PID%,,3
	WinSetTitle, ahk_pid %ffmpeg_PID%,, Editing ---- %file_name%
}

if (out_type = 2)		; PROXY mode
{
	MsgBox ,,Attention, Under Construction
	;ffmpeg_PID := transcoding_proxy(starttime, duration, file_full, targetfile)
	;WinWait, ahk_pid %ffmpeg_PID%,,3
	;WinSetTitle, ahk_pid %ffmpeg_PID%,, Editing ---- %file_name%
}

;WinActivate, %wtitle%
GuiControl,, %hstatus%, PID %ffmpeg_PID%`, %file_name_only%_cut_%cut_prefix%.%file_extension% 
ToolTip, Editing started with pid %ffmpeg_PID%`, %file_name_only%_cut_%cut_prefix%.%file_extension%
SetTimer, removetooltip, -1000

return

removetooltip:
ToolTip
return

/*     mov proxy generate example (verified with FCP 7, 20180131)
ffmpeg -i input.mxf -filter_complex "[0:a:0][0:a:1]amerge=inputs=2[a1];[0:a:2][0:a:3]amerge=inputs=2[a2]" -c:a pcm_s24le -ac 2 -c:v copy -vtag xd5c -map 0:0 -map [a1] -map [a2]  output.mov

-ignore_unknown
	Ignore input streams with unknown type instead of failing if copying such streams is attempted.

To map the video and audio streams from the first input, and using the trailing ?, ignore the audio mapping if no audio streams exist in the first input:
ffmpeg -i INPUT -map 0:v -map 0:a? OUTPUT

To map all the streams except the second audio, use negative mappings
ffmpeg -i INPUT -map 0 -map -0:a:1 OUTPUT

*/



transcoding_normal(starttime, duration, file_i, file_o)
{
	global binary_ffmpeg
	runstring = %binary_ffmpeg% -ss %starttime% -i "%file_i%" -t %duration% -map 0:v -map 0:a -c:v copy -c:a copy -ignore_unknown -y "%file_o%"
	OutputDebug, %runstring%
	;Clipboard := runstring
	run, %runstring%,,Minimize,ffmpeg_PID
	return ffmpeg_PID
}

transcoding_proxy(starttime, duration, file_i, file_o)
{
	global binary_ffmpeg, media
	runstring = %binary_ffmpeg% -ss %starttime% -i "%file_i%" -t %duration% -map 0:v -map 0:a -c:v copy -c:a copy -ignore_unknown -y "%file_o%"
	OutputDebug, %runstring%
	;Clipboard := runstring
	run, %runstring%,,Minimize,ffmpeg_PID
	return ffmpeg_PID
}



transcoding_mov4ch(starttime, duration, file_i, file_o)		;	 Depcrated 2019/5/31
{
	runstring = ffmpeg2016 -ss %starttime% -i "%file_i%" -t %duration% -c:v copy -filter_complex "[0:a:0][0:a:1]amerge=inputs=2[a1];[0:a:2][0:a:3]amerge=inputs=2[a2]"  -map 0:0 -map [a1] -map [a2] -c:a pcm_s24le -ac 2 -vtag xd5c -y "%file_o%"
	OutputDebug, %runstring%
	run, %runstring%,,,ffmpeg_PID
	return ffmpeg_PID
	
}

transcoding_mov8ch(starttime, duration, file_i, file_o)		;	 Depcrated 2019/5/31
{
	runstring = ffmpeg2016 -ss %starttime% -i "%file_i%" -t %duration% -c:v copy -filter_complex "[0:a:0][0:a:1]amerge=inputs=2[a1];[0:a:2][0:a:3]amerge=inputs=2[a2];[0:a:4][0:a:5]amerge=inputs=2[a3];[0:a:6][0:a:7]amerge=inputs=2[a4]"  -map 0:0 -map [a1] -map [a2] -map [a3] -map [a4] -c:a pcm_s24le -ac 2 -vtag xd5c -y "%file_o%"
	OutputDebug, %runstring%
	run, %runstring%,,,ffmpeg_PID
	return ffmpeg_PID	
}


GuiDropFiles:
gosub, reset
for key, val in btnenablecontrol
	GuiControl, disable, %val%
file_full = %A_GuiEvent%
media.fullpath := A_GuiEvent		; add 2019/3/13
ToolTip					; added 2019/3/30
analyse_media(media, minfo)
SplitPath, file_full, file_name, file_path, file_extension, file_name_only
if (media.extension = "mxf")
	GuiControl, Enable, %hout_type%
else
{
	GuiControl, Disable, %hout_type%
	GuiControl, Choose, %hout_type%, 1
}

GuiControl,, %hfilename%, %file_name%
GuiControl,, %hstatus%, % "Resolution : " . media.resolution . "  Audio Format : " . media.audio_format
for key, val in btnenablecontrol
	GuiControl, Enable, %val%
return


target:
currentoutfolder = %outfolder%
FileSelectFolder, outfolder,,3
	if outfolder =
	{
		outfolder := currentoutfolder
		GuiControl,,%hstatus%, Target is %outfolder%
		return				; you select no folder
	}
StringRight, temp, outfolder, 1
IfNotEqual, temp, \
	outfolder = %outfolder%\
GuiControl,,%hstatus%, Target is %outfolder%
RegWrite, REG_EXPAND_SZ, HKEY_LOCAL_MACHINE\SOFTWARE\sendust\%wtitle%, outfolder, %outfolder%
return

pickstart:                             ; detect start time -------------------------------

Process, Exist, % play_pid
if ErrorLevel
{
	temp := mpvrun.read()
	pbposition := get_pvw_position2(temp)
	StringReplace, pbposition, pbposition, :,,All
	StringRight, millisecond1, pbposition, 3
	start_time = 19990101%pbposition%
	guicontrol,, %hstart_time%, %start_time%
	GuiControl,, %hmillisecond1%, %millisecond1%
	ToolTip, Set In %pbposition%
}

return

pickend:                             ; detect end time -------------------------------

Process, Exist, % play_pid
if ErrorLevel
{
	temp := mpvrun.read()
	pbposition := get_pvw_position2(temp)
	StringReplace, pbposition, pbposition, :,,All
	StringRight, millisecond2, pbposition, 3
	end_time = 19990101%pbposition%
	guicontrol,, %hend_time%, %end_time%
	GuiControl,, %hmillisecond2%, %millisecond2%
	ToolTip, Set Out %pbposition%
}

return



mpvgetposition(mpvoutput)
{
	loop, Parse, mpvoutput, `n, `r
		lastline = %A_LoopField%
	StartingPos := InStr(lastline,"AV:") + 4
	pbposition := SubStr(lastline,StartingPos, 12)   ; select 8 (second), select 12 (milisecond)
	StringReplace, pbposition, pbposition, :,,All
return %pbposition%
}


consolecapture(title)				; Deprecated 2019/5/31
{
	IfWinNotExist, %title%
		return
	clipboard =
	WinActivate, %title%
	WinWaitActive, %title%,,2
	SendInput, !{Space}
	SendInput, es{Enter}
	ClipWait, 2
	WinMinimize, %title%
	return %Clipboard%
}


analyse_media2(ByRef media)  			; Deprecated 2019/5/31
{
	global hstatus
	;ffmpeg := "%A_ScriptDir%\bin\ffmpeg2018.exe"
	ffmpeg := "ffmpeg.exe"
	GuiControl,, %hstatus%, Analysing Media...Please wait
	
	inputfile := media.fullpath
	SplitPath, inputfile, outfilename, outdir, outextension, outnamenoext, outdrive

	EnvSet, FFREPORT, file=output.txt:level=32
	RunWait  %ffmpeg% -i "%inputfile%" -report -hide_banner, %A_Temp%, Hide		; run ffmpeg in hide mode
	
	stroutput := ""
	timecode := ""
	time_duration := ""
	time_start := ""
	creation_time := ""
	FileRead, stroutput, %A_Temp%\output.txt				; read ffmpeg result
	
	OutputDebug, %stroutput%
	RegExMatch(stroutput, "Duration:\s+[0-9]+:[0-9]+:[0-9]+.[0-9]+", time_duration)	; Find Clip duration
	RegExMatch(stroutput, "start:\s+[0-9]+.[0-9]+", time_start)						; Find Clip start time
	RegExMatch(stroutput, "creation_time\s+: [1234567890-\sT:]+", creation_time)	; Find Clip creation time       creation_time   : 2018-10-13T20:52:16.000000Z
	RegExMatch(stroutput, ", [0-9]+x[0-9]+", resolution)							; Find clip resolution
	RegExMatch(stroutput, "timecode\s+:\s[0-9]+:[0-9]+:[0-9]+[:;][0-9]+", timecode)	; Find time code information  
	RegExMatch(stroutput, ",\s[0-9.]+\sfps,", framerate)

	RegExReplace(stroutput, "Hz, stereo,", "", count_stereo)				; Find stereo stream and count
	RegExReplace(stroutput, "Hz, 5.1", "", count_fivedotone)				; Find 5.1 stream and count
	RegExReplace(stroutput, "Hz, 7.1", "", count_sevendotone)				; Find 7.1 stream and count
	RegExReplace(stroutput, "Hz, mono", "", count_mono)						; Find mono stream and count
	RegExReplace(stroutput, "Hz, 1 channels", "", count_onechannel)			; Find mono stream and count
	RegExReplace(stroutput, "Hz, 2 channels", "", count_twochannel)			; Find mono stream and count
	RegExReplace(stroutput, "Hz, 8 channels", "", count_eightchannel)			; Find mono stream and count
	RegExReplace(stroutput, "Hz, 16 channels", "", count_sixteenchannel)			; Find mono stream and count
	RegExReplace(Stroutput, "encoder\s+: GoPro\s", "", GoPro)				; Check if encoder is gopro (add 2018/12/10)

	audio_format = noaudio
	if count_mono
		audio_format = mono-%count_mono%
	if count_onechannel
		audio_format = mono-%count_onechannel%
	if count_stereo
		audio_format = stereo-%count_stereo%
	if count_twochannel
		audio_format = stereo-%count_twochannel%	
	if count_fivedotone
		audio_format = 5.1-%count_fivedotone%
	if count_sevendotone
		audio_format = 7.1-%count_sevendotone%
	if count_eightchannel
		audio_format = 8-%count_eightchannel%
	if count_sixteenchannel
		audio_format = 16-%count_sixteenchannel%
	
	time_duration := RegExReplace(time_duration, "Duration:\s", "")	; extract duration number only
	RegExMatch(time_start, "[0-9]+.[0-9]+", time_start)				; extract start time number only
	RegExMatch(timecode, "[0-9]+:[0-9]+:[0-9]+[:;][0-9]+", timecode) 	; extract timecode only
	RegExMatch(resolution, "[0-9]+x[0-9]+", resolution)				; extract resolution only
	RegExMatch(framerate, "[0-9.]+", framerate)						; extract framerate only
	RegExMatch(creation_time, "\d\d:\d\d:\d\d", creation_time)				; extract creatioin time only
	
	if !time_duration
		time_duration = 00:00:01			; added 2019/2/8  ffmpeg cannot read duration (N/A case)
	time_duration := TCtoSecond(time_duration, framerate)

	if (creation_time)
		time_start := TctoSecond(creation_time, framerate)
			
	if (timecode)
		time_start := TctoSecond(timecode, framerate)

	if (!time_start)						; added 2019/2/8   time_start is NULL case
		time_start = 0

	
	media.duration := time_duration
	media.start := time_start
	media.resolution := resolution
	media.framerate := framerate
	media.audio_format := audio_format
	media.extension := outextension
	
	GuiControl,, %hstatus%, Finish Analysing Media
}


GuiClose:
WinGetPos, position_x, position_y,,,%wtitle%
RegWrite, REG_SZ, HKEY_LOCAL_MACHINE\SOFTWARE\sendust\%wtitle%, start_x, %position_x%
RegWrite, REG_SZ, HKEY_LOCAL_MACHINE\SOFTWARE\sendust\%wtitle%, start_y, %position_y%
ExitApp


analyse_media(ByRef media, o_mi)			; new, 2019/4/3 from mediainfo.dll
{
	o_mi.open(media.fullpath)
	
	media.extension := o_mi.getgeneral("FileExtension")
	media.duration := o_mi.getvideo("Duration") / 1000	
	media.start := o_mi.gettimecode()	
	media.resolution := o_mi.getvideo("Width") . "x" . o_mi.getvideo("Height")
	media.width := o_mi.getvideo("Width")
	media.height := o_mi.getvideo("Height")
	media.resolution := StrLen(media.resolution) < 3 ? o_mi.getimage("Width") . "x" . o_mi.getimage("Height") : media.resolution
	media.framerate := o_mi.getvideo("FrameRate")
	media.audio_format := o_mi.getaudiocount()
	media.codecv := o_mi.getvideo("Format")
	media.codeca := o_mi.getaudio("Format")
	media.durationframe :=  o_mi.getvideo("FrameCount")	
	media.scantype := o_mi.getvideo("ScanType")	
	if (!media.scantype)
		media.scantype := "Progressive"
	media.titlev := o_mi.getvideo("Title")
	media.titlea := o_mi.getaudio("Title")

}






tctosecond(intime, fps)						; changed 2018/12/10
{
		if fps < 1
			fps := 30
		hh := SubStr(intime, 1, 2)			; ffmpeg output example   [ Duration: 00:06:56.42, start: 1.033367, bitrate: 9524 kb/s ]
		mm := SubStr(intime, 4, 2)			;						  [ timecode        : 11:10:59;25 ]
		ss := SubStr(intime, 7, 2)
		separator := SubStr(intime, 9, 1)
		IfEqual, separator, .				;  separator is . (00:06:56.42 format)
			ss := SubStr(intime, 7, 5)
		IfEqual, separator, `;
			ss := SubStr(intime, 7, 2) + SubStr(intime, 10,2) / fps
		IfEqual, separator, :				; separator is : (00:06:00:33 format, Gopro case)		added 2018/12/10
			ss := SubStr(intime, 7, 2) + SubStr(intime, 10,2) / fps

		return hh * 3600 + mm * 60 + ss	
}


; command line interface class, based on stdouttovar sean code and others ; v1.0, by segalion
; Code Modified by sendust 2019/4/8


class consolerun 
{
   pid := -1
   
    __New(sCmd, sDir="",codepage="") {
      DllCall("CreatePipe","Ptr*",hStdInRd,"Ptr*",hStdInWr,"Uint",0,"Uint",0)
      DllCall("CreatePipe","Ptr*",hStdOutRd,"Ptr*",hStdOutWr,"Uint",0,"Uint",0)
      DllCall("SetHandleInformation","Ptr",hStdInRd,"Uint",1,"Uint",1)
      DllCall("SetHandleInformation","Ptr",hStdOutWr,"Uint",1,"Uint",1)
      
      if (A_PtrSize=4) {
         VarSetCapacity(pi, 16, 0)
         VarSetCapacity(si,68,0)
         NumPut(68, si,  0)
         NumPut(0x100, si, 44)
         NumPut(hStdInRd , si, 56)
         NumPut(hStdOutWr, si, 60)
         NumPut(hStdOutWr, si, 64)
         }
      else if (A_PtrSize=8) {
         VarSetCapacity(pi, 24, 0)    ; PROCESS_INFORMATION  ;  http://goo.gl/b9BaI
         VarSetCapacity(si,104,0)           ; startupinfo      ;  http://goo.gl/fZf24
         NumPut(68, si,  0)         ; cbSize
         NumPut(0x100, si, 60)        ; dwFlags    =>  STARTF_USESTDHANDLES = 0x100
         NumPut(hStdInRd , si, 80)
         NumPut(hStdOutWr, si, 88)     ; hStdOutput
         NumPut(hStdOutWr, si, 96)    ; hStdError
         }
      result :=DllCall("CreateProcess", "Uint", 0, "Ptr", &sCmd, "Uint", 0, "Uint", 0, "Int", True, "Uint", 0x08000000, "Uint", 0, "Ptr", sDir ? &sDir : 0, "Ptr", &si, "Ptr", &pi)
      this.pid := NumGet( pi, A_PtrSize*2, "UInt" )         ; read 4 byte
      DllCall("CloseHandle","Ptr",NumGet(pi, 0, "Uint64"))
      DllCall("CloseHandle","Ptr",NumGet(pi, A_PtrSize, "Uint64"))
      DllCall("CloseHandle","Ptr",hStdOutWr)
      DllCall("CloseHandle","Ptr",hStdInRd)
         ; Create an object.
		this.hStdInWr:= hStdInWr, this.hStdOutRd:= hStdOutRd
		this.codepage:=(codepage="")?A_FileEncoding:codepage
	}
    __Delete() {
        this.close()
    }
    close() {
       hStdInWr:=this.hStdInWr
       hStdOutRd:=this.hStdOutRd
       DllCall("CloseHandle","Ptr",hStdInWr)
       DllCall("CloseHandle","Ptr",hStdOutRd)
      }
   write(sInput="")  {
		If   sInput <>
			FileOpen(this.hStdInWr, "h", this.codepage).Write(sInput)
      }
      
	readline() {
       fout:=FileOpen(this.hStdOutRd, "h", this.codepage)
	   this.AtEOF:=fout.AtEOF
       if (IsObject(fout) and fout.AtEOF=0)
         return fout.ReadLine()
      return ""
      }
      
      
   	read(chars="") {
       fout:=FileOpen(this.hStdOutRd, "h", this.codepage)
       this.AtEOF:=fout.AtEOF
	   if (IsObject(fout) and fout.AtEOF=0)
         return chars=""?fout.Read():fout.Read(chars)
      return ""
      }


   /*
	read(chars="")          ; Modified by sendust 209/4/8
    {
       fout:=FileOpen(this.hStdOutRd, "h", this.codepage)
      VarSetCapacity( Buffer, 4096, 0 ), nSz := 0 
      ;While 
      DllCall( "ReadFile", UInt,this.hStdOutRd, UInt,&Buffer, UInt,4094, UIntP,nSz, Int,0 ) 
      NumPut( 0, Buffer, nSz, "Char" )
      VarSetCapacity( Buffer,-1 )
      tOutput := StrGet( &Buffer, nSz, "CP850" )
      ToolTip % tOutput
      FileAppend, % tOutput, mpvoutput.txt
   }
   */


}



/* example  ------------  from https://autohotkey.com/board/topic/82732-class-command-line-interface/
netsh:= new cli("netsh.exe","","CP850")
msgbox % "hStdInWr=" netsh.hStdInWr "`thStdOutRd=" netsh.hStdOutRd
sleep 300
netsh.write("firewall`r`n")
sleep 100
netsh.write("show config`r`n")
sleep 1000
out:=netsh.read()
msgbox,, FIREWALL CONFIGURATION:, %out%
netsh.write("bye`r`n")
netsh.close()
*/



 ;Tip for struct calculation
  ; Any member should be aligned to multiples of its size
  ; Full size of structure should be multiples of the largest member size
  ;============================================================================
  ;
  ; x64
  ; STARTUPINFO
  ;                             offset    size                    comment
  ;DWORD  cb;                   0         4
  ;LPTSTR lpReserved;           8         8(A_PtrSize)            aligned to 8-byte boundary (4 + 4)
  ;LPTSTR lpDesktop;            16        8(A_PtrSize)
  ;LPTSTR lpTitle;              24        8(A_PtrSize)
  ;DWORD  dwX;                  32        4
  ;DWORD  dwY;                  36        4
  ;DWORD  dwXSize;              40        4
  ;DWORD  dwYSize;              44        4
  ;DWORD  dwXCountChars;        48        4
  ;DWORD  dwYCountChars;        52        4
  ;DWORD  dwFillAttribute;      56        4
  ;DWORD  dwFlags;              60        4
  ;WORD   wShowWindow;          64        2
  ;WORD   cbReserved2;          66        2
  ;LPBYTE lpReserved2;          72        8(A_PtrSize)           aligned to 8-byte boundary (2 + 4)
  ;HANDLE hStdInput;            80        8(A_PtrSize) 
  ;HANDLE hStdOutput;           88        8(A_PtrSize) 
  ;HANDLE hStdError;            96        8(A_PtrSize) 
  ;
  ;ALL : 96+8=104=8*13
  ;
  ; PROCESS_INFORMATION
  ;
  ;HANDLE hProcess              0         8(A_PtrSize)
  ;HANDLE hThread               8         8(A_PtrSize)
  ;DWORD  dwProcessId           16        4
  ;DWORD  dwThreadId            20        4
  ;
  ;ALL : 20+4=24=8*3
  ;============================================================================
  ; x86
  ; STARTUPINFO
  ;                             offset     size
  ;DWORD  cb;                   0          4
  ;LPTSTR lpReserved;           4          4(A_PtrSize)            
  ;LPTSTR lpDesktop;            8          4(A_PtrSize)
  ;LPTSTR lpTitle;              12         4(A_PtrSize)
  ;DWORD  dwX;                  16         4
  ;DWORD  dwY;                  20         4
  ;DWORD  dwXSize;              24         4
  ;DWORD  dwYSize;              28         4
  ;DWORD  dwXCountChars;        32         4
  ;DWORD  dwYCountChars;        36         4
  ;DWORD  dwFillAttribute;      40         4
  ;DWORD  dwFlags;              44         4
  ;WORD   wShowWindow;          48         2
  ;WORD   cbReserved2;          50         2
  ;LPBYTE lpReserved2;          52         4(A_PtrSize)           
  ;HANDLE hStdInput;            56         4(A_PtrSize) 
  ;HANDLE hStdOutput;           60         4(A_PtrSize) 
  ;HANDLE hStdError;            64         4(A_PtrSize) 
  ;
  ;ALL : 64+4=68=4*17
  ;
  ; PROCESS_INFORMATION
  ;
  ;HANDLE hProcess              0         4(A_PtrSize)
  ;HANDLE hThread               4         4(A_PtrSize)
  ;DWORD  dwProcessId           8         4
  ;DWORD  dwThreadId            12        4
  ;
  ;ALL : 12+4=16=4*4
  
  
  