#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
#SingleInstance Off
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.
menu, tray, icon, .\icon\arrowl.ico

title = Copy Manager by sendust (0610)
size_src := -1
size_dst := -2
size_src_old := -3
size_dst_old := -4
buffersize := 20000000					; 20MB
buffersize_header := 100000				; 100 kByte
;buffersize_footer := 100000000		;(100Mbyte, deprecated, require large footer buffer size)
offset_footer := 100000000			;(100Mbyte)  rewind specified position from file end and update footer again)
hfile_src := object()
hfile_dst := object()
x_prev = 50
y_prev = 100
logfile = %A_WorkingDir%\log\Transferlog.log

if %4%
	logfile = %A_WorkingDir%\log\Transferlog_%4%.log


WinGet, id, list, %title%
Loop, %id%
{
	this_id := id%A_Index%
	WinGetPos, x, y,,, ahk_id %this_id%
	if (x > x_prev)
		x_prev := x
	if (y > y_prev)
		y_prev := y
}	

x_prev += 40
y_prev += 40

if ((x_prev > A_ScreenWidth - 100) or (y_prev > A_ScreenHeight - 100))
{
	x_prev := 50
	y_prev := 100
}

if %3%				; 3rd parameter (caller's window title)
{
	WinGetPos, x, y,,, %3%
	x_prev := x - 150
	y_prev := y - 10
}


Gui, margin, 1, 1
Gui, Add, progress, w380 h15 hwndhprogress cBlue, 1
Gui, Add, text, xm yp+17 w380 hwndhtext, Source File Name
Gui, Add, StatusBar, hwndhstatus, Status bar
;Gui, show, w400 h70, %title%
Gui, show,  x%x_prev% y%y_prev%, %title%
Gui +Hwndhthiswindow

updatelog("Application Start ---------------------------------- xy position is " . x_prev . " / " . y_prev)

file_src = %1%
file_dst = %2%

if (!file_src or !file_dst)
	MsgBox ,,Attention,Usage`r`n`r`ncopymanager  "source_file" "target_file" "window title" index `r`n`r`n Entering GUI Drop operation, 2


if ((strlen(file_src) >1) and  (strlen(file_dst) >1 ))
{
	SplitPath, file_src, filename_src
	SplitPath, file_dst, ,dir_dst
	GuiControl,, %htext%, %filename_src%
	WinSetTitle, ahk_id %hthiswindow%,, %title% - %dir_dst%
	hfile_src := FileOpen(file_src, "r")
	hfile_dst := FileOpen(file_dst, "w")
	if (!hfile_dst)
	{
		MsgBox ,, Attention, Error Writing Target File, 1
		updatelog("Error Writing Destination File " . file_dst)
		ExitApp
	}
	updatelog("Transfer command received  src / dst is " . file_src . " / " . file_dst)
	SetTimer, check_src, -2000
}
return



GuiDropFiles:
SplitPath, A_GuiEvent, filename_src, outdir, outextension, outnamenoext
GuiControl,, %htext%, %filename_src%
hfile_src := FileOpen(A_GuiEvent, "r")
hfile_dst := FileOpen(outdir . "\" . outnamenoext . "_copy." . outextension, "w")
updatelog("Job started with GUI Drag Drop / " . A_GuiEvent)
SetTimer, check_src, -2000

return

check_src:

if %2%
{
	DriveSpaceFree, size_free, %dir_dst%		; result is MB
	if (size_free < 10000)
	{
		updatelog("Target Free space is not enough.. Terminating Copy Process. / " . file_dst)
		MsgBox ,, Attention !, Target free space is not enough %size_free% MB Left Exiting......., 2
		updatelog("Exit Application -------------------------")
		ExitApp
	}
}

size_src := hfile_src.length
pos_src := hfile_src.pos
size_dst := hfile_dst.length


if (size_src != size_src_old)			; Source file is growing
{
	buffersize_new := round(size_src - Abs(size_src_old))			; Buffer size is source file delta
	if (buffersize_new > buffersize)												; Buffer size cannot be larger than default buffersize
		buffersize_new := buffersize
}
else													; Source is not growing
	buffersize_new := buffersize

if (buffersize_new >= (size_src - pos_src))	;		buffersize cannot be larger than remaining tail size
	buffersize_new := size_src - pos_src

VarSetCapacity(buffer, buffersize_new)
hfile_src.RawRead(buffer, buffersize_new)
hfile_dst.RawWrite(buffer, buffersize_new)


if ((size_dst < size_src) or (size_src != size_src_old))		; (src fils is growing) or (dst file size < src file size)
{
	;ToolTip, % "Copying progress " . hfile_dst.length . "  /  " . hfile_src.length
	GuiControl,, %hstatus%, % "Copying progress " . size_dst . "  /  " . size_src . " (" . buffersize_new . ")"
	GuiControl,, %hprogress%, % (size_dst / size_src) * 100
	;updatelog("size_dst size_src size_src_old is " . size_dst . "/" . size_src . "/" . size_src_old)
	SetTimer, check_src, -300					; large value for small bitrate media (file size incresing can not be detect during short period)
}
else
{
	SetTimer, double_check, -3000		; wait long period for probing source file growing
}

/*
if (size_src = size_src_old)
{
	ToolTip, % "File Finish " . size_src
	SetTimer, removetooltip, -2000
}
else
{
	ToolTip, % "File Growing " . size_src
	SetTimer, check_src, -200
}
*/

size_src_old := size_src

return


double_check:
size_dst := hfile_dst.length
size_src := hfile_src.length
if ((size_dst < size_src) or (size_src != size_src_old))		; (src fils is growing) or (dst file size < src file size), double check
	SetTimer, check_src, -500	
else
	SetTimer,  header_write, -2000
return



header_write:
ToolTip
GuiControl,, %hprogress%, 100

GuiControl,, %hstatus%, % "Target Copy operation Finished " . size_dst . "  /  " . size_src . " (" . buffersize_new . ")"
updatelog("Transfer Finished, Source / Destination file size is " . size_src . " / " . size_dst . " Destination File name is " . file_dst)


hfile_src.Seek(0,0)			; return to header
hfile_dst.Seek(0.0)			; return to header
VarSetCapacity(buffer, buffersize_header)
hfile_src.RawRead(buffer,buffersize_header)
result := hfile_dst.RawWrite(buffer, buffersize_header)		; update header
if result
	updatelog("Update header " . buffersize_header . " Bytes /" . file_dst)
else
	updatelog("Failed to update header " . buffersize_header . " Bytes /" . file_dst)

/*
;--------- update footer ------------------------------  old ver (large footer buffer size req.)
if (hfile_src.length >= buffersize_footer)				; source file size is larger than footer buffer size
	buffersize_footer_new := buffersize_footer
else
	buffersize_footer_new := hfile_src.length

	result := hfile_src.Seek(-buffersize_footer_new, 2)			; return to footer
if result
{
	hfile_dst.Seek(-buffersize_footer_new, 2)						; return to dst file footer
	VarSetCapacity(buffer, buffersize_footer_new)
	hfile_src.RawRead(buffer,buffersize_footer_new)			; Read source footer
	hfile_dst.RawWrite(buffer, buffersize_footer_new)		; update footer
	updatelog("Update tail " . buffersize_footer_new . " Bytes /" . file_dst)
}
else
	updatelog("Failed to update tail, cannot open source file " . buffersize_footer_new . " Bytes /" . file_dst)
*/

;--------- update footer ------------------------------ new ver (with loop)

if (offset_footer <= hfile_src.length)				; source file size is larger than Default footer offset (file pointer can go offset_footer MAX size)
	offset_footer_new := offset_footer
else
	offset_footer_new := hfile_src.length			; source file size is smaller than footer offset size

	hfile_src.Seek(-offset_footer_new, 2)			; return to footer offset
	hfile_dst.Seek(-offset_footer_new, 2)			; return to footer offset

count := 0
while !hfile_src.AtEOF
{
	pos_src := hfile_src.pos
	if (buffersize <= (size_src - pos_src))			; buffer size is smaller than source positioned size (remain size)
		buffersize_new := buffersize
	else
		buffersize_new := size_src - pos_src		; buffer size is enough

	VarSetCapacity(buffer, buffersize_new)
	hfile_src.RawRead(buffer, buffersize_new)
	result := hfile_dst.RawWrite(buffer, buffersize_new)
	count++
}

if result
	updatelog("Update tail with " . count . " times loop / " . file_dst . " / dst position is " . hfile_dst.Position)
else
	updatelog("Failed to update tail, cannot write dst file, result is " . result)


hfile_src.Close()			; close source file
hfile_dst.Close()			; close target file
size_src := -1
size_dst := -2
size_src_old := -3
size_dst_old := -4
SetTimer, GuiClose, -1000
return



GuiClose:
updatelog("Exit Application -------------------------")
ExitApp


updatelog(text)
{
	global logfile
	FileAppend, [%A_Year%/%A_Mon%/%A_DD%] %A_Hour%:%A_Min%.%A_sec%_%A_MSec%  - %text%`r`n, %logfile%
}
