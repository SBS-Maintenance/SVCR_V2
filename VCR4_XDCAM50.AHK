/*
SBS ISO Ingest Server
Created by sendust
Maintained by sendust

HIstory
2020/5/8 - add stream record
2020/5/27 - UHD preview size change, 
	             - restart rec for large dup value
2020/6/9  - UHD  queue size changed 8G -> 4G 2020/6/9 (for nvenc)
2020/7/3  - Introduce onexit function
2020/7/6  - Check finish day
			    - Prepare for compiled version
2020/7/8	 - add ss 1 option to remove first few black frame
2020/7/14  - improve rc buffer underflow related log monitor
2020/7/17 - apply trellis for mpeg2video  (  -trellis 0 )
2020/7/20 - change mpeg2video bufsize (20000k -> 35000k, improve rc buffer underrun)
2020/7/20 - change trellis 1 -> trellis 0 	; trellis introduce 3~5% more cpu power
2020/11/4 - Improve old recfile deletion (skip locked file and delete only deletable file)
2020/11/8 - Introduce UDP Remote control (there is missing command  from gang control)
2021/4/15 - CONFI Video play with Caspar CG  (support mxf only)
2021/5/8   - Improve 4k UHD Prores parameter
2021/5/25 - Add Multiviewer class and method
2021/12/24  - change audio format for XDCAM MOV  (mono 8 stream-> single stream 8 ch)
*/



#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
#SingleInstance Ignore
AutoTrim, on
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.
menu, tray, icon, .\icon\bct-tape.ico
;#NoTrayIcon
#Include socket_mod.ahk
#include mediainfo.ahk

ahk_exe = ahk
if A_IsCompiled
	ahk_exe = exe


pid_ffmpeg = -1
pid_ffmpeg_proxy = -1
pid_ffmpeg_preview := -1
pid_mpv_preview := -1
pid_transfer := -1

count_size_mon := 0
flag_rec_restart := 0
flag_sbsdvr := 0							; sbs dvr mode (enhanced 1 hour segment record)
flag_recee_limit := 0					; auto close EE window when record started
flag_dshowinput := 1				; set 0 if you use native decklink input, set 1 if you use direct show input device
flag_tcwrite := 1						; Write TC 				added 2020/4/8
flag_ccg_ee := 0							; CONFI Video play with Caspar CG added 2021/4/15		(value update in ini read section)

binary_ffmpeg = %A_WorkingDir%\bin\ffmpeg2018.exe
binary_mpv = %A_WorkingDir%\bin\mpv-x86_64-20181002\mpv.com			; under testing.. 2019/6/4
binary_mpv = %A_WorkingDir%\bin\mpv-i686-20170423\mpv.com
binary_ffmpeg_uhd = %A_WorkingDir%\bin\ffmpeg_decklink3.exe			; Modified 2019/12/2
binary_ffmpeg_uhd = %A_WorkingDir%\bin\ffmpeg2020_11.5.1.exe			; Modified 2020/6/9
binary_copymanager = copymanager.%ahk_exe%

size_ffreport_old = 5000
size_rec_old = -1

channel_index := SubStr(A_ScriptName, 4, 1)			; extract 4th character from script file name

IniRead, path_rec, svcr%channel_index%.ini, path, capture, s:\temp\     		; read rec path from svcr.ini, default : d:\capture\
IniRead, path_dst, svcr%channel_index%.ini, path, target, g:\backup\  	;read backup target path
IniRead, CHNAME, svcr%channel_index%.ini, name, name, VTR%channel_index%  ; read channel name
IniRead, url_preview, svcr%channel_index%.ini, url, preview, udp://232.100.1.101:60000
IniRead, url_progress, svcr%channel_index%.ini, url, progress, udp://127.0.0.1:5556
IniRead, audiomonl, svcr%channel_index%.ini, monitor, monitorleft, CH1
IniRead, audiomonr, svcr%channel_index%.ini, monitor, monitorright, CH2
IniRead, param_mpv_add, svcr%channel_index%.ini, general, preview_moreparameter, --no-audio
IniRead, codec_default,  svcr%channel_index%.ini, general, codec_default, 1
IniRead, time_cleanup, svcr%channel_index%.ini, cleanup, auto_cleanup, 02:01				; LOG, REC file Auto cleanup time
IniRead, size_reserve, svcr%channel_index%.ini, cleanup, disk_usage, 100`%								; Capture Drive Reserve Capacity
IniRead, autodelete_age, svcr%channel_index%.ini, cleanup, auto_delete_age, 0				; unit - days  (0 means do not autodelete)
IniRead, flag_tcwrite, svcr%channel_index%.ini, general, timecode, 0				; write timecode flag
IniRead, flag_ccg_ee,  svcr%channel_index%.ini, general, casparee, 0				; EE mode with casparCG


mv := new multiviewer
mv.read_config("svcr" . channel_index . ".ini")

finishday :=  20290221235959
logfile = %A_WorkingDir%\log\sVCRLOG-%CHNAME%.log

; --------------- collect all log files name (with full path) --------------------------------------------
files_log := Object()
files_log.push(A_WorkingDir . "\log\transferlog.log")
files_log.push(A_WorkingDir . "\log\schedulerlog.log")
Loop, 5
{
	IniRead, temp, svcr%A_Index%.ini, name, name, VTR%A_Index%  ; read channel name
	temp = %A_WorkingDir%\log\sVCRLOG-%temp%.log
	files_log.push(temp)																				; collect all log file names
	temp = %A_WorkingDir%\log\transferlog_%A_index%.log
	files_log.push(temp)
}
; --------------- collect all log files name (with full path) --------------------------------------------

folders_capture := Object()
Loop, 5
{
	IniRead, temp, svcr%A_Index%.ini, path, capture,   ; read capture folder
	folders_capture.push(temp)
}


title := "SBS sVCR v2-" . CHNAME . " by sendust (20211224)"
title_ee := "EE Video " . CHNAME
title_encoder_main := "Encoder Main " . CHNAME
title_encoder_proxy := "Encoder Proxy " . CHNAME

duration_max := " -t 12:00:00 "
duration_max_proxy := " -t 11:59:55 "

decklink_array := Object()
decklink_array[1] := """video=Decklink Video Capture:audio=Decklink Audio Capture"""
decklink_array[2] := """video=Decklink Video Capture (2):audio=Decklink Audio Capture (2)"""
decklink_array[3] := """video=Decklink Video Capture (3):audio=Decklink Audio Capture (3)"""
decklink_array[4] := """video=Decklink Video Capture (4):audio=Decklink Audio Capture (4)"""
decklink_array[5] := """video=Decklink Video Capture (5):audio=Decklink Audio Capture (5)"""

/*
; test purpose (rearrange decklink order)			2020/4/9
decklink_array[1] := """video=Blackmagic WDM Capture (2):audio=Blackmagic WDM Capture (2)"""
decklink_array[2] := """video=Blackmagic WDM Capture (3):audio=Blackmagic WDM Capture (3)"""
decklink_array[3] := """video=Blackmagic WDM Capture (4):audio=Blackmagic WDM Capture (4)"""
decklink_array[4] := """video=Blackmagic WDM Capture (5):audio=Blackmagic WDM Capture (5)"""
decklink_array[5] := """video=Blackmagic WDM Capture (6):audio=Blackmagic WDM Capture (6)"""
*/

;--------------------------------------------------------------------------------------------------------------------------------


decklink_array_new := object()
decklink_array_new[1] := """DeckLink 4K Extreme 12G"""
decklink_array_new[2] := """DeckLink 8K Pro (2)"""
decklink_array_new[3] := """DeckLink 8K Pro (3)"""
decklink_array_new[4] := """DeckLink 8K Pro (4)"""
decklink_array_new[5] := """DeckLink Mini Recorder"""

decklink_array_new[channel_index] := get_decklinkname(decklink_array_new[channel_index], channel_index)			; read decklink name from ini file if exist

mpv_geometry := object()
mpv_geometry[1] := " --geometry=20:30"
mpv_geometry[2] := " --geometry=510:30"
mpv_geometry[3] := " --geometry=20:310"
mpv_geometry[4] := " --geometry=510:310"
mpv_geometry[5] := " --geometry=510:590"


gui, margin, 10, 10
gui, add, text, xm ym  w255 hwndhtext1 gtext1 r1, Target : %path_dst%
gui, add, text, xp+260 yp w600 hwndhtext2 gtext2 r1 , Capture folder : %path_rec% 
gui, add, groupbox, xm ym+20 w680 h95 cBlue hwndhgroupbox, %CHNAME%-XDCAM50_MXF
Gui, add, button, xm+20 ym+40 w50 h30 gpreview hwndhpreview, E.E.
gui, add, button, xp+70 yp  w80 h30 gstart_rec  hwndhstart_rec, start rec             ; start recording button 
gui, add, button, xp+100 yp w80 h30 gstop_rec  hwndhstop_rec, stop rec  ; stop recording button
Gui, add, DDL, xp+100 yp+5 w130 vcodec_choice hwndhcodec_choice choose%codec_default% gcodec_change, XDCAM50_MXF|XDCAM50_MOV|XDCAM_EX_MXF|PRORES_LT_MOV|PRORES_MOV|PRORES_HQ_MOV|MPEG2_TS|AUD_LOGGING|UHD_4K_MXF|UHD_4K_TS|UHD_4K_PRORES|STREAM|test
gui, add, button, xp+150 yp-5 w80 h30 gsel_target hwndhsel_target, Sel Target
gui, add, button, xp+100 yp w1 h1 gset_target hwndset_target, Set Target
gui, add, edit, xm+20 yp+40  w350 h25 vfile_userinput, %CHNAME%
gui, add, text, xp+360 yp+5  w200 h15 hwndhrectimedisplay,  Time              ; display record time

gui, add, checkbox,xm+580 ym+40 vchk_transfer hwndhtransfer, TRASFER                               ; auto transfer, checkbox
gui, add, Checkbox, xp yp+20  vchk_proxy hwndhproxy, PROXY                          ; Enable or disable Proxy clip generation
gui, add, Checkbox, xp yp+20  vchk_split hwndhsplit, SPLIT 

gui, add, picture, x0 y0 hwndhred_bar, .\icon\redbar_400.png
gui, add, picture, x400 y0 hwndhgreen_bar, .\icon\greenbar_300.png
gui, add, StatusBar, hwndhstatus, Application Started ([%A_DD%] %A_Hour%:%A_Min%.%A_Sec%) 

gui, show, w700 h150,%title%
Gui +Hwndhthiswindow

Gui, Font, s11 bold
GuiControl, font, %hrectimedisplay%

GuiControl, hide, %hred_bar%
GuiControl, hide, %hgreen_bar%


gui_stop:= [hstart_rec, hcodec_choice, hsel_target, htransfer, hproxy, hsplit]			; enabled gui handle at each situation
gui_rec := [hstop_rec]																										; enabled gui handle at each situation


if flag_sbsdvr
{
	duration_max := " -t 24:00:05 "
	duration_max_proxy := " -t 24:00:00 "
	gui_stop:= [hstart_rec, hcodec_choice, hsel_target, hproxy, hsplit]
	GuiControl,, %hstatus%, Application Started, SBS DVR Mode ([%A_DD%] %A_Hour%:%A_Min%.%A_Sec%) 
	GuiControl, choose, %hcodec_choice%, 7
	GuiControl,, %hsplit%, 1
	GuiControl, Disable, %htransfer%
	updatelog("SBB DVR Mode Started")
}


encoder_param := Object()
extension := Object()
progress_var := object()				; variable for ffmpeg progress position, time (from UDP stream)
progress_udp := Object()
split_param := Object()
remote_control := Object()						; Remote command list object


remote_control.cmd["start_rec"] := "__START_REC__"		; 13 character
remote_control.cmd["stop_rec"] := "__STOP_REC___"
remote_control.cmd["preview"] := "___PREVIEW___"
remote_control.handle["start_rec"] := hstart_rec
remote_control.handle["stop_rec"] := hstop_rec
remote_control.handle["preview"] := hpreview

printobjectlist(cmdlist.handle)

progress_udp := new  SocketUDP()
progress_udp.bind(url_to_address_array(url_progress))
progress_udp.onRecv := Func("OnUDPRecv")

media := object()
minfo := Object()
minfo := new Mediainfo

if !flag_dshowinput
	binary_ffmpeg := binary_ffmpeg_uhd

encoder_array := Object()
encoder_array["XDCAM50_MXF"] := binary_ffmpeg
encoder_array["XDCAM50_MOV"] := binary_ffmpeg
encoder_array["XDCAM_EX_MXF"] := binary_ffmpeg
encoder_array["PRORES_LT_MOV"] := binary_ffmpeg
encoder_array["PRORES_MOV"] := binary_ffmpeg
encoder_array["PRORES_HQ_MOV"] := binary_ffmpeg
encoder_array["MPEG2_TS"] := binary_ffmpeg
encoder_array["AUD_LOGGING"] := binary_ffmpeg
encoder_array["UHD_4K_MXF"] := binary_ffmpeg_uhd
encoder_array["UHD_4K_TS"] := binary_ffmpeg_uhd
encoder_array["UHD_4K_PRORES"] := binary_ffmpeg_uhd
encoder_array["STREAM"] := binary_ffmpeg
encoder_array["test"] := binary_ffmpeg


extension["XDCAM50_MXF"] := "mxf"
extension["XDCAM50_MOV"] := "mov"
extension["XDCAM_EX_MXF"] := "mxf"
extension["PRORES_LT_MOV"] := "mov"
extension["PRORES_MOV"] := "mov"
extension["PRORES_HQ_MOV"] := "mov"
extension["MPEG2_TS"] := "ts"
extension["AUD_LOGGING"] := "ts"
extension["UHD_4K_MXF"] := "mxf"
extension["UHD_4K_TS"] := "ts"
extension["UHD_4K_PRORES"] := "mov"
extension["STREAM"] := "ts"
extension["test"] := "mov"



;-pix_fmt yuv422p10le -r ntsc -c:v prores -profile:v 1 -b:v 102000k -maxrate 102000k
; Prores Profile : 0 Proxy,   1 LT,   2 Standard,   3 HQ,   4 4444,   5 4444 XQ  (with  c:v prores_ks)

;parameter - v1
;  ffmpeg_string =  ffmpeg -f dshow -r %framerate% -video_size 1920x1080 -rtbufsize 2100M -framerate %framerate% -top 1 -pixel_format uyvy422 -sample_rate 48000 -sample_size 16 -channels %audio_rec_channel% -i "%inputdevicestring%" -pix_fmt %mycspace% -c:v mpeg2video -profile:v 0 -level:v 2 -b:v %mybitrate% -maxrate %mybitrate% -minrate %mybitrate% -bufsize 20000k -flags +ildct+ilme -field_order tt -top 1 -g %gopsize% -bf 2 -color_primaries 1 -color_trc 1 -colorspace 1 -filter_complex "[0:0]setfield=tff;[0:1]aresample=async=1000[are];[are]channelsplit=channel_layout=%alayout%" -acodec pcm_s24le -y

param_decklinkinput_yuv422p := "  -y -f dshow -r 29.97 -video_size 1920x1080 -rtbufsize 2100M -framerate 29.97 -top 1 -pixel_format uyvy422 -sample_rate 48000 -sample_size 16 -channels 8 -i "
param_decklinkinput_v210 := "  -y -f dshow  -r 29.97 -vcodec v210 -video_size 1920x1080 -rtbufsize 2100M -framerate 29.97 -top 1 -sample_rate 48000 -sample_size 16 -channels 8 -i "	
param_streaminput := " -y -re -i " .  get_stream_address("svcr" . channel_index . ".ini")

;param_decklinkinput_yuv422p := " -y  -f dshow  -framerate 29.97 -video_size 1920x1080 -rtbufsize 2100M -top 1 -pixel_format uyvy422 -sample_rate 48000 -sample_size 16 -channels 8 -i "		; new 2020/4/9
;param_decklinkinput_v210 := " -y -f dshow  -framerate 29.97  -vcodec v210  -video_size 1920x1080 -rtbufsize 2100M -top 1 -sample_rate 48000 -sample_size 16 -channels 8 -i "				; new 2020/4/9	without -r 29.97 , encoding fail sometimes.

param_decklinkinput_yuv422p_new := " -y  -f decklink -channels 8 -audio_depth 32 -queue_size 3000000000 -timestamp_align 0.1 -draw_bars 0 -format_code Hi59 -raw_format uyvy422 -i  "
param_decklinkinput_v210_new := " -y  -f decklink -channels 8 -audio_depth 32 -queue_size 3000000000 -timestamp_align 0.1 -draw_bars 0 -format_code Hi59 -raw_format yuv422p10 -i  "

param_decklinkinput_yuv422p_uhd:= " -y  -f decklink -channels 8 -audio_depth 32 -queue_size 4000000000 -timestamp_align 0.2  -draw_bars 0 -format_code 4k59 -raw_format uyvy422 -i  "					; queue size changed 8G -> 4G 2020/6/9
param_decklinkinput_v210_uhd:= " -y  -f decklink -channels 8 -audio_depth 32 -queue_size 4000000000 -timestamp_align 0.2  -draw_bars 0  -format_code 4k59 -raw_format uyvy422 -i  "
param_decklinkinput_yuv422p10_uhd:= " -y  -f decklink -channels 8 -audio_depth 32 -queue_size 8000000000 -timestamp_align 0.2  -draw_bars 0  -format_code 4k59 -raw_format yuv422p10 -i  "		; new, added 2020/3/31


param_record_filtercomplex := " -filter_complex ""[0:v]split[vin1][vin2];[vin1]setfield=tff[vo1];[vin2]field=0[vfield];[vfield]scale=iw/4:ih/2:flags=fast_bilinear[vo2];[0:a]aresample=async=1000[are];[are]asplit=outputs=3[ain1][ain2][ain3];[ain1]channelsplit=channel_layout=7.1[ao1][ao2][ao3][ao4][ao5][ao6][ao7][ao8];[ain2]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[apw1];[ain3]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[apw2]"" -map [vo2] -map [apw1] -map [apw2] -pix_fmt yuv420p -c:v mpeg2video -b:v 2000k -minrate 2000k  -g 10 -bf 0 -c:a ac3 -ac 4 -f mpegts "		
param_record_filtercomplex_asum := " -filter_complex ""[0:v]split[vin1][vin2];[vin1]setfield=tff[vo1];[vin2]field=0[vfield];[vfield]scale=iw/4:ih/2:flags=fast_bilinear[vo2];[0:a]aresample=async=1000[are];[are]asplit=outputs=3[ain1][ain2][ain3];[ain1]anull[asumout];[ain2]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[apw1];[ain3]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[apw2]"" -map [vo2] -map [apw1] -map [apw2] -pix_fmt yuv420p -c:v mpeg2video -b:v 2000k -minrate 2000k  -g 10 -bf 0 -c:a ac3 -ac 4 -f mpegts "	
param_record_filtercomplex_ts := " -filter_complex ""[0:v]split[vin1][vin2];[vin1]setfield=tff[vo1];[vin2]field=0[vfield];[vfield]scale=iw/4:ih/2:flags=fast_bilinear[vo2];[0:a]aresample=async=1000[are];[are]asplit=outputs=4[ain1][ain2][ain3][ain4];[ain1]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[aout1];[ain2]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[aout2];[ain3]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[apw1];[ain4]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[apw2]"" -map [vo2] -map [apw1] -map [apw2]  -pix_fmt yuv420p -c:v mpeg2video -b:v 2000k  -minrate 2000k -g 10 -bf 0 -c:a ac3 -ac 4  -f mpegts "	


if !flag_dshowinput				; set input parameter as new input parameter
{
	param_decklinkinput_yuv422p := param_decklinkinput_yuv422p_new
	param_decklinkinput_v210 := param_decklinkinput_v210_new
	Loop, 5
		decklink_array[A_Index] := decklink_array_new[A_Index]
}


;encoder_param["XDCAM50_MXF"] := " -y -f dshow -r 29.97 -video_size 1920x1080 -rtbufsize 2100M -framerate 29.97 -top 1 -pixel_format uyvy422 -sample_rate 48000 -sample_size 16 -channels 8 -i " . decklink_array[channel_index] . " -filter_complex ""[0:v]split[vin1][vin2];[vin1]setfield=tff[vo1];[vin2]field=0[vfield];[vfield]scale=iw/4:ih/2[vo2];[0:a]aresample=async=1000[are];[are]asplit=outputs=3[ain1][ain2][ain3];[ain1]channelsplit=channel_layout=7.1[ao1][ao2][ao3][ao4][ao5][ao6][ao7][ao8];[ain2]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[apw1];[ain3]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[apw2]"" -map [vo2] -map [apw1] -map [apw2] -pix_fmt yuv420p -c:v mpeg2video -b:v 4000k -g 10 -bf 0 -c:a ac3 -ac 4 -f mpegts " . duration_max  . url_preview . " -map [vo1] -map [ao1] -map [ao2] -map [ao3] -map [ao4] -map [ao5] -map [ao6] -map [ao7] -map [ao8] -pix_fmt yuv422p  -profile:v 0 -level:v 2 -b:v 50000k -maxrate 50000k -minrate 50000k -bufsize 20000k -flags +ildct+ilme+cgop -top 1 -g 15 -bf 2 -sc_threshold 1000000000 -color_primaries 1 -color_trc 1 -colorspace 1 -c:v mpeg2video -acodec pcm_s24le " . duration_max		; 2019/6/3 Last ver

encoder_param["XDCAM50_MXF"] := param_decklinkinput_yuv422p . decklink_array[channel_index] . param_record_filtercomplex . duration_max  . url_preview . " -ss 1 -map [vo1] -map [ao1] -map [ao2] -map [ao3] -map [ao4] -map [ao5] -map [ao6] -map [ao7] -map [ao8] -pix_fmt yuv422p  -profile:v 0 -level:v 2 -b:v 50000k -maxrate 50000k -minrate 50000k -bufsize 35000k  -trellis 0  -mpv_flags strict_gop  -flags +ildct+ilme -top 1 -g 15 -bf 2 -color_primaries 1 -color_trc 1 -colorspace 1 -c:v mpeg2video -acodec pcm_s24le " . duration_max		; 2019/6/12 Last ver
;encoder_param["XDCAM50_MOV"] := param_decklinkinput_yuv422p . decklink_array[channel_index] . param_record_filtercomplex . duration_max  . url_preview .  " -ss 1  -map [vo1] -map [ao1] -map [ao2] -map [ao3] -map [ao4] -map [ao5] -map [ao6] -map [ao7] -map [ao8] -pix_fmt yuv422p  -profile:v 0 -level:v 2 -b:v 50000k -maxrate 50000k -minrate 50000k -bufsize 35000k  -trellis 0  -mpv_flags strict_gop  -flags +ildct+ilme  -top 1 -g 15 -bf 2  -color_primaries 1 -color_trc 1 -colorspace 1 -c:v mpeg2video -acodec pcm_s24le -vtag xd5b" . duration_max 				; 2019/6/12 Last ver
encoder_param["XDCAM50_MOV"] := param_decklinkinput_yuv422p . decklink_array[channel_index] . param_record_filtercomplex_asum . duration_max  . url_preview .  " -ss 1  -map [vo1] -map [asumout] -pix_fmt yuv422p  -profile:v 0 -level:v 2 -b:v 50000k -maxrate 50000k -minrate 50000k -bufsize 35000k  -trellis 0  -mpv_flags strict_gop  -flags +ildct+ilme  -top 1 -g 15 -bf 2  -color_primaries 1 -color_trc 1 -colorspace 1 -c:v mpeg2video -acodec pcm_s24le -vtag xd5b" . duration_max 				; 2021/1/26   Modified for Premier
encoder_param["XDCAM_EX_MXF"] := param_decklinkinput_yuv422p . decklink_array[channel_index] . param_record_filtercomplex . duration_max  . url_preview .  " -ss 1  -map [vo1] -map [ao1] -map [ao2] -map [ao3] -map [ao4] -map [ao5] -map [ao6] -map [ao7] -map [ao8] -pix_fmt yuv420p -b:v 35000k -maxrate 35000k -minrate 35000k -bufsize 35000k  -trellis 0  -mpv_flags strict_gop  -flags +ildct+ilme -top 1 -g 15 -bf 2  -color_primaries 1 -color_trc 1 -colorspace 1 -c:v mpeg2video -acodec pcm_s16le -vtag xdvb" . duration_max 			; 2019/6/12 Last ver
encoder_param["PRORES_LT_MOV"] := param_decklinkinput_v210 . decklink_array[channel_index] . param_record_filtercomplex_asum . duration_max  . url_preview .  " -ss 1  -map [vo1] -map [asumout] -pix_fmt yuv422p10le -c:v prores -profile:v 1 -flags +ildct+ilme -field_order tt -top 1 -color_primaries 1 -color_trc 1 -colorspace 1 -acodec pcm_s16le " . duration_max 				; 2019/6/12 Last ver
encoder_param["PRORES_MOV"] := param_decklinkinput_v210 . decklink_array[channel_index] . param_record_filtercomplex_asum . duration_max  . url_preview .  " -ss 1  -map [vo1] -map [asumout] -pix_fmt yuv422p10le -c:v prores -profile:v 2 -flags +ildct+ilme -field_order tt -top 1 -color_primaries 1 -color_trc 1 -colorspace 1 -acodec pcm_s16le " . duration_max 				; added 2019/6/7
encoder_param["PRORES_HQ_MOV"] := param_decklinkinput_v210 . decklink_array[channel_index] . param_record_filtercomplex_asum . duration_max  . url_preview .  "  -ss 1 -map [vo1] -map [asumout] -pix_fmt yuv422p10le -c:v prores -profile:v 3 -flags +ildct+ilme -field_order tt -top 1 -color_primaries 1 -color_trc 1 -colorspace 1 -acodec pcm_s16le " . duration_max 				; added 2019/6/7
;encoder_param["MPEG2_TS"] := " -y -f dshow -r 29.97 -video_size 1920x1080 -rtbufsize 2100M -framerate 29.97 -top 1 -pixel_format uyvy422 -sample_rate 48000 -sample_size 16 -channels 8 -i " . decklink_array[channel_index] . " -filter_complex ""[0:v]split[vin1][vin2];[vin1]setfield=tff[vo1];[vin2]field=0[vfield];[vfield]scale=iw/2:ih[vo2];[0:a]aresample=async=1000[are];[are]asplit=outputs=3[ain1][ain2][ain3];[ain1]channelsplit=channel_layout=7.1[ao1][ao2][ao3][ao4][ao5][ao6][ao7][ao8];[ain2]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[apw1];[ain3]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[apw2]"" -map [vo2] -map [apw1] -map [apw2]  -pix_fmt yuv420p -c:v mpeg2video -b:v 8000k -g 10 -c:a ac3 -ac 4  -f mpegts " . duration_max  . url_preview .  " -map [vo1] -map [ao1] -map [ao2] -map [ao3] -map [ao4] -map [ao5] -map [ao6] -map [ao7] -map [ao8]  -pix_fmt yuv420p -flags +ildct+ilme+cgop -sc_threshold 1000000000 -b:v 25000k -g 15 -bf 2 -qmax 4 -c:v mpeg2video -c:a mp2 -ac 1 " . duration_max 				; added 2019/6/7 (Edius cannot handle  8 track mp2 stream)
encoder_param["MPEG2_TS"] := param_decklinkinput_yuv422p . decklink_array[channel_index] . param_record_filtercomplex_ts . duration_max  . url_preview . " -map [vo1] -map [aout1] -map [aout2]   -pix_fmt yuv420p -flags +ildct+ilme+cgop -sc_threshold 1000000000 -b:v 19000k -g 15 -bf 2  -trellis 0  -c:v mpeg2video -c:a ac3 -ac 4 " . duration_max 				; added 2019/6/12, Edius friendly autio parameter



proxy_param := " -i " . url_preview . " -c copy -y "

; prores Example
; ffmpeg -f dshow -vcodec v210 -r 29.97 -video_size 1920x1080 -rtbufsize 1400M -framerate 29.97 -top 1 -sample_rate 48000 -sample_size 16 -channels %audio_rec_channel% -i "%inputdevicestring%" -pix_fmt yuv422p -c:v prores %prores_profile% -flags +ildct+ilme -field_order tt -top 1 -color_primaries 1 -color_trc 1 -colorspace 1 -filter_complex "[0:0]setfield=tff;channelsplit=channel_layout=%alayout%" -drop_frame_timecode 1 -acodec pcm_s16le -y

encoder_param["AUD_LOGGING"] := param_decklinkinput_yuv422p . decklink_array[channel_index] . " -filter_complex ""[0:v]format=pix_fmts=yuv420p[vpix];[vpix]field=0[vfield];[vfield]scale=iw/4:ih/2:flags=fast_bilinear[vs];[vs]setdar=1.7778[vdar];[0:a]aresample=async=1000[are];[are]asplit=6[a1][a2][a3][a4][a5][a6];[a1]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[apan1];[a2]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[apan2];[a3]showspectrum=mode=separate:saturation=5:gain=3:size=1280x720:fps=29.97:slide=scroll:legend=1:win_func=2[sptum];[a4]showvolume=r=29.97[vvol];[vdar][vvol]overlay[vovy1];[sptum][vovy1]overlay=x=900:y=50[vout];[vout]split[vrec][vrec2];[vrec2]scale=480x270[vpvw];[a5]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[arec1];[a6]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[arec2]"" -map [vpvw] -pix_fmt yuv420p   -c:v mpeg2video -b:v 4000k  -minrate 4000k -maxrate 4000k -bufsize 2000k  -g 10 -bf 0 -map [apan1] -map [apan2] -c:a ac3 -ac 4  -f mpegts " .  url_preview  .  duration_max . " -map [vrec] -map [arec1] -map [arec2] -c:a ac3 -ac 4 -c:v mpeg2video -b:v 17000k " . duration_max 
;encoder_param["test"] := "-y -i rtmp://210.216.76.120/live/sbsonair  -c copy -f mpegts  -bsf:v h264_mp4toannexb " . duration_max  . url_preview . " -c copy" . duration_max 
encoder_param["test"] := "-f lavfi -re -i testsrc2=size=1920x1080:rate=29.97 -f lavfi -re -i sine=frequency=1000:sample_rate=48000  -filter_complex ""[0]format=pix_fmts=yuv422p[vtest];[1][1][1][1][1][1][1][1]amerge=inputs=8[atest];[vtest]split[vin1][vin2];[vin1]setfield=tff[vo1];[vin2]scale=iw/4:ih/4:flags=fast_bilinear[vo2];[atest]aresample=async=1000[are];[are]asplit=outputs=3[ain1][ain2][ain3];[ain1]channelsplit=channel_layout=7.1[ao1][ao2][ao3][ao4][ao5][ao6][ao7][ao8];[ain2]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[apw1];[ain3]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[apw2]"" -map [vo2] -map [apw1] -map [apw2] -pix_fmt yuv420p -c:v mpeg2video -b:v 4000k -minrate 4000k  -g 10 -bf 0 -c:a ac3 -ac 4 -f mpegts " . duration_max  . url_preview .  " -map [vo1] -map [ao1] -map [ao2] -map [ao3] -map [ao4] -map [ao5] -map [ao6] -map [ao7] -map [ao8] -pix_fmt yuv422p  -profile:v 0 -level:v 2  -b:v 50000k -maxrate 50000k -minrate 50000k -bufsize 20000k -flags +ildct+ilme -top 1  -mpv_flags strict_gop  -g 15 -bf 2 -color_primaries 1 -color_trc 1 -colorspace 1 -c:v mpeg2video -acodec pcm_s24le -vtag xd5b" . duration_max 
encoder_param["UHD_4K_MXF"] :=param_decklinkinput_yuv422p_uhd . decklink_array_new[channel_index] . "  -filter_complex ""[0:v]format=pix_fmts=yuv420p[vpix];[vpix]split[vo1][vin2];[vin2]fps=29.97[vfps];[vfps]scale=iw/8:ih/8:flags=fast_bilinear[vo2];[0:a]aresample=48000[are];[are]asplit=outputs=3[ain1][ain2][ain3];[ain1]channelsplit=channel_layout=7.1[ao1][ao2][ao3][ao4][ao5][ao6][ao7][ao8];[ain2]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[apw1];[ain3]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[apw2]"" -map [vo2] -map [apw1] -map [apw2] -c:v mpeg2video -g 5 -b:v 4000k -c:a ac3 -ac 4 -f mpegts "  . duration_max  . url_preview . " -map [vo1] -map [ao1] -map [ao2] -map [ao3] -map [ao4] -map [ao5] -map [ao6] -map [ao7] -map [ao8] -c:v h264_nvenc -preset:v fast -rc vbr -b:v 100000000 -bf 0 -c:a pcm_s24le -signal_standard 6 " . duration_max 
encoder_param["UHD_4K_TS"] := param_decklinkinput_yuv422p_uhd . decklink_array_new[channel_index] .  "  -filter_complex ""[0:v]format=pix_fmts=yuv420p[vpix];[vpix]split[vo1][vin2];[vin2]fps=29.97[vfps];[vfps]scale=iw/8:ih/8:flags=fast_bilinear[vo2];[0:a]aresample=async=1000[are];[are]asplit=outputs=4[ain1][ain2][ain3][ain4];[ain1]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[aout1];[ain2]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[aout2];[ain3]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[apw1];[ain4]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[apw2]"" -map [vo2] -map [apw1] -map [apw2] -c:v mpeg2video -bf 0 -g 5 -b:v 4000k -c:a ac3 -ac 4 -f mpegts "  . duration_max  . url_preview . " -map [vo1] -map [aout1] -map [aout2] -c:v h264_nvenc -preset:v fast  -rc vbr -b:v 70000000 -bf 0 -minrate 1000k -c:a aac -ac 4  " . duration_max 
;encoder_param["UHD_4K_PRORES"] := param_decklinkinput_yuv422p10_uhd . decklink_array_new[channel_index] .  " -filter_complex ""[0:v]split[v1][v2];[v2]format=pix_fmts=yuv420p[vpix];[vpix]fps=29.97[vfps];[vfps]scale=iw/8:ih/8:flags=fast_bilinear[vo2];[0:a]aresample=48000[are];[are]asplit=outputs=3[ain1][ain2][ain3];[ain1]anull[asumout];[ain2]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[apw1];[ain3]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[apw2]"" -map [vo2] -map [apw1] -map [apw2] -c:v h264_nvenc -preset:v ll -b:v 4000k -g 5  -c:a ac3 -ac 4 -f mpegts "  . duration_max  . url_preview . " -map [v1] -map [asumout] -c:v prores -profile:v 1 -c:a pcm_s24le   "  . duration_max 			; new, added 2020/3/31
encoder_param["UHD_4K_PRORES"] := param_decklinkinput_yuv422p10_uhd . decklink_array_new[channel_index] .  " -filter_complex ""[0:v]split[v1][v2];[v2]fps=29.97[vfps];[vfps]scale=iw/8:ih/8:flags=fast_bilinear[vsize];[vsize]format=pix_fmts=yuv420p[vo2];[0:a]aresample=48000[are];[are]asplit=outputs=3[ain1][ain2][ain3];[ain1]anull[asumout];[ain2]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[apw1];[ain3]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[apw2]"" -map [vo2] -map [apw1] -map [apw2] -c:v h264_nvenc -preset:v ll -b:v 4000k -g 5  -c:a ac3 -ac 4 -f mpegts "  . duration_max  . url_preview . " -map [v1] -map [asumout] -c:v prores -profile:v 1 -c:a pcm_s24le   "  . duration_max 			; change filter order  2021/5/8

encoder_param["STREAM"] :=  param_streaminput  . " -filter_complex ""[0:v]split[v1][v2];[v2]format=pix_fmts=yuv420p[vpix];[vpix]fps=29.97[vfps];[vfps]scale=480:270:flags=fast_bilinear[vo2];[0:a]aresample=48000[are];[are]asplit=outputs=3[ain1][ain2][ain3];[ain1]anull[asumout];[ain2]pan=stereo|c0=c0|c1=c1[apw1];[ain3]pan=stereo|c0=c0|c1=c1[apw2]"" -map [vo2] -map [apw1] -map [apw2] -c:v mpeg2video  -b:v 4000k -maxrate 4000k -bufsize 2000k -g 10 -bf 0 -c:a ac3 -ac 2  -f mpegts "  . duration_max  . url_preview . " -map [v1] -map [asumout] -c:v mpeg2video -q:v 2 -g 15  -c:a libmp3lame -ab 128k   "  . duration_max 			; new, added 2020/5/8


; -reset_timestamps 1 introduce random 'missing frame', very rare...rare.... 2019/5/26

split_param["XDCAM50_MXF"] := "  -flags +ildct+ilme+cgop  -sc_threshold 1000000000 -f segment -fflags +genpts -increment_tc 1 -reset_timestamps 1 -segment_times 3,3603,7203,10803,14403,18003,21603,25203,28803,32403,36003,39603,43203,46803,50403,54003,57603,61203,64803,68403,72003,75603,79203,82803,86403"	; 1 hour split
;split_param["XDCAM50_MXF"] := " -f segment -fflags +genpts -increment_tc true -reset_timestamps 1 -segment_times 3,63,123,183,243,303,363,423,483,543,603,663,723,783,843,903,963,1023,1083,1143,1203,1263,1323,1383,1443,1503,1563"  ; 1 min split	(test purpose)
;split_param["XDCAM50_MXF"] := " -f segment -fflags +genpts -increment_tc true -reset_timestamps 1 -segment_time 300"  ; periodic  split - simple mode (test purpose)
split_param["XDCAM50_MOV"] := split_param["XDCAM50_MXF"]
split_param["XDCAM_EX_MXF"] := split_param["XDCAM50_MXF"]
split_param["PRORES_LT_MOV"] := split_param["XDCAM50_MXF"]
split_param["PRORES_MOV"] := split_param["XDCAM50_MXF"]
split_param["PRORES_HQ_MOV"] := split_param["XDCAM50_MXF"]
split_param["MPEG2_TS"] := "  -flags +ildct+ilme+cgop  -sc_threshold 1000000000   -f segment -fflags +genpts -reset_timestamps 1 -segment_time 3600"
split_param["AUD_LOGGING"] := split_param["MPEG2_TS"]
split_param["UHD_4K_MXF"] := " -f segment  -increment_tc 1 -reset_timestamps 1  -flags -global_header  -segment_times 3,3603,7203,10803,14403,18003,21603,25203,28803,32403,36003,39603,43203,46803,50403,54003,57603,61203,64803,68403,72003,75603,79203,82803,86403 "
split_param["UHD_4K_TS"] := split_param["UHD_4K_MXF"]
split_param["UHD_4K_PRORES"] := split_param["UHD_4K_MXF"]			; new added 2020/3/31
split_param["test"] := " -f segment -fflags +genpts -segment_times 3,13,23,33,43,53,63,73,83,93,103,113,123,133,143,153,163,173,183,193,203,213,223,233,243,253,263,273,283,293,303,313,323,333,343"
split_param["STREAM"] := "  -flags +cgop  -sc_threshold 1000000000    -f segment -fflags +genpts -reset_timestamps 1 -segment_time 3600"				; new add 2020/5/8


; about split, first segment ---------------
;  mxf : EDIUS, FCP NG
;  mov : EDIUS OK, FCP NG
;  ts : EDIUS OK
; 
;  FCP ; normal ts, segment ts both NG
;
;

;--------------------------------------------------- ffmpeg parameter for EE Preview -------------------------------------------------------------------------
;preview_param := "-f dshow -r 29.97 -video_size 1920x1080 -rtbufsize 2100M -framerate 29.97 -top 1 -pixel_format uyvy422 -sample_rate 48000 -sample_size 16 -channels 8 -i " . decklink_array[channel_index] . " -filter_complex ""[0:v]scale=960:540"" -pix_fmt yuv420p  -c:v mpeg2video -b:v 8000k -g 15 -c:a aac -ac 8  -f mpegts " . url_preview				; single stream, multi channel
;preview_param := "-f dshow -r 29.97 -video_size 1920x1080 -rtbufsize 2100M -framerate 29.97 -top 1 -pixel_format uyvy422 -sample_rate 48000 -sample_size 16 -channels 8 -i " . decklink_array[channel_index] . " -filter_complex ""[0:v]field=0[vfield];[vfield]scale=iw/2:ih;[0:a]channelsplit=channel_layout=7.1"" -pix_fmt yuv420p  -c:v mpeg2video -b:v 8000k -g 15 -c:a mp2 -ac 1  -f mpegts " . url_preview				; muti stream, single channel			(Final version 2019/5/30)
;preview_param := "-f dshow -r 29.97 -video_size 1920x1080 -rtbufsize 2100M -framerate 29.97 -top 1 -pixel_format uyvy422 -sample_rate 48000 -sample_size 16 -channels 8 -i " . decklink_array[channel_index] . " -filter_complex ""[0:v]field=0[vfield];[vfield]scale=iw/2:ih;[0:a]asplit[a1][a2];[a1]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3;[a2]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7"" -pix_fmt yuv420p  -c:v mpeg2video -b:v 8000k -g 15 -c:a aac -ac 4  -f mpegts " . url_preview				; muti stream, multi channel			(Final version 2019/6/3. 960x540 resolution)


preview_param_list := Object()
preview_param_list["XDCAM50_MXF"] :=  param_decklinkinput_yuv422p . decklink_array[channel_index] . " -filter_complex ""[0:v]field=0[vfield];[vfield]scale=iw/4:ih/2:flags=fast_bilinear;[0:a]asplit[a1][a2];[a1]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3;[a2]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7"" -pix_fmt yuv420p  -c:v mpeg2video -b:v 4000k -minrate 4000k  -maxrate 4000k -bufsize 2000k -g 10 -bf 0 -c:a aac -ac 4  -f mpegts " . url_preview				; muti stream, multi channel			(Final version 2019/6/12.480x270 resolution)
preview_param_list["XDCAM50_MOV"] := preview_param_list["XDCAM50_MXF"] 
preview_param_list["XDCAM_EX_MXF"] := preview_param_list["XDCAM50_MXF"] 
preview_param_list["PRORES_LT_MOV"] := preview_param_list["XDCAM50_MXF"] 
preview_param_list["PRORES_MOV"] := preview_param_list["XDCAM50_MXF"] 
preview_param_list["PRORES_HQ_MOV"] := preview_param_list["XDCAM50_MXF"] 
preview_param_list["MPEG2_TS"] := preview_param_list["XDCAM50_MXF"] 
preview_param_list["AUD_LOGGING"] :=  param_decklinkinput_yuv422p . decklink_array[channel_index] . " -filter_complex ""[0:v]format=pix_fmts=yuv420p[vpix];[vpix]field=0[vfield];[vfield]scale=iw/4:ih/2:flags=fast_bilinear[vs];[vs]setdar=1.7778[vdar];[0:a]aresample=async=1000[are];[are]asplit=4[a1][a2][a3][a4];[a1]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[apan1];[a2]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[apan2];[a3]showspectrum=mode=separate:saturation=5:gain=3:size=1280x720:fps=29.97:slide=scroll:legend=1:win_func=2[sptum];[a4]showvolume=r=29.97[vvol];[vdar][vvol]overlay[vovy1];[sptum][vovy1]overlay=x=900:y=50[vout];[vout]scale=1280x720[vpvw]"" -map [vpvw] -pix_fmt yuv420p   -c:v mpeg2video -b:v 8000k  -minrate 8000k -maxrate 8000k -bufsize 14000k  -g 10 -bf 0 -map [apan1] -map [apan2] -c:a ac3 -ac 4  -f mpegts " .  url_preview

preview_param_list["test"] := "-f lavfi -re -i testsrc2=size=480x270:rate=29.97 -f lavfi -re -i sine=frequency=1000:sample_rate=48000  -filter_complex ""[0]format=pix_fmts=yuv420p[vtest];[1][1][1][1]amerge=inputs=4[atest1];[1][1][1][1]amerge=inputs=4[atest2]"" -map [vtest] -map [atest1] -map [atest2] -c:v mpeg2video -b:v 4000k -minrate 4000k  -maxrate 4000k -bufsize 2000k -g 10 -bf 0 -c:a aac -ac 4  -f mpegts " . url_preview							; test signal generator for EE preview, 2019/9/6

preview_param_list["UHD_4K_MXF"]:= param_decklinkinput_yuv422p_uhd . decklink_array_new[channel_index] .  "  -filter_complex ""[0:v]fps=29.97[vfps];[vfps]scale=iw/8:ih/8:flags=fast_bilinear[size];[size]format=pix_fmts=yuv420p[vo1];[0:a]asplit=outputs=2[ain1][ain2];[ain1]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[apw1];[ain2]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[apw2]""  -map [vo1] -map [apw1] -map [apw2] -r 29.97 -c:v h264_nvenc -preset:v ll -b:v 4000k -g 5 -c:a ac3 -ac 4 -f mpegts " . url_preview

preview_param_list["UHD_4K_TS"]:= param_decklinkinput_yuv422p_uhd . decklink_array_new[channel_index] .  "  -filter_complex ""[0:v]fps=29.97[vfps];[vfps]scale=iw/8:ih/8:flags=fast_bilinear[size];[size]format=pix_fmts=yuv420p[vo1];[0:a]asplit=outputs=2[ain1][ain2];[ain1]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[apw1];[ain2]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[apw2]""  -map [vo1] -map [apw1] -map [apw2] -r 29.97 -c:v h264_nvenc -preset:v ll -b:v 4000k -g 5 -c:a ac3 -ac 4  -f mpegts " . url_preview

;preview_param_list["UHD_4K_PRORES"]:= param_decklinkinput_yuv422p10_uhd . decklink_array_new[channel_index] .  "  -filter_complex ""[0:v]format=pix_fmts=yuv420p[vpix];[vpix]fps=29.97[vfps];[vfps]scale=iw/8:ih/8:flags=fast_bilinear[vo1];[0:a]asplit=outputs=2[ain1][ain2];[ain1]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[apw1];[ain2]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[apw2]""  -map [vo1] -map [apw1] -map [apw2] -r 29.97 -c:v h264_nvenc -preset:v ll -b:v 4000k -g 5 -c:a ac3 -ac 4  -f mpegts " . url_preview			; new added 2020/3/31
preview_param_list["UHD_4K_PRORES"]:= param_decklinkinput_yuv422p10_uhd . decklink_array_new[channel_index] .  "  -filter_complex ""[0:v]fps=29.97[vfps];[vfps]scale=iw/8:ih/8:flags=fast_bilinear[size];[size]format=pix_fmts=yuv420p[vo1];[0:a]asplit=outputs=2[ain1][ain2];[ain1]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3[apw1];[ain2]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7[apw2]""  -map [vo1] -map [apw1] -map [apw2] -r 29.97 -c:v h264_nvenc -preset:v ll -b:v 4000k -g 5 -c:a ac3 -ac 4  -f mpegts " . url_preview			; new added 2020/3/31

preview_param_list["STREAM"]:= param_streaminput  .  "  -filter_complex ""[0:v]format=pix_fmts=yuv420p[vpix];[vpix]fps=29.97[vfps];[vfps]scale=480:270:flags=fast_bilinear[vo1];[0:a]asplit=outputs=2[ain1][ain2];[ain1]pan=stereo|c0=c0|c1=c1[apw1];[ain2]pan=stereo|c0=c0|c1=c1[apw2]""  -map [vo1] -map [apw1] -map [apw2]  -c:v mpeg2video  -b:v 4000k -maxrate 4000k -bufsize 2000k -g 10 -bf 0 -c:a ac3 -ac 2  -f mpegts " . url_preview			; new added 2020/5/8

/*
preview_param_decklink := "-f dshow -r 29.97 -video_size 1920x1080 -rtbufsize 2100M -framerate 29.97 -top 1 -pixel_format uyvy422 -sample_rate 48000 -sample_size 16 -channels 8 -i " . decklink_array[channel_index] . " -filter_complex ""[0:v]field=0[vfield];[vfield]scale=iw/4:ih/2;[0:a]asplit[a1][a2];[a1]pan=4.0|c0=c0|c1=c1|c2=c2|c3=c3;[a2]pan=4.0|c0=c4|c1=c5|c2=c6|c3=c7"" -pix_fmt yuv420p  -c:v mpeg2video -b:v 4000k -minrate 4000k  -maxrate 4000k -bufsize 2000k -g 10 -bf 0 -c:a aac -ac 4  -f mpegts " . url_preview				; muti stream, multi channel			(Final version 2019/6/12.480x270 resolution)
preview_param_test :=  "-f lavfi -re -i testsrc2=size=480x270:rate=29.97 -f lavfi -re -i sine=frequency=1000:sample_rate=48000  -filter_complex ""[0]format=pix_fmts=yuv420p[vtest];[1][1][1][1]amerge=inputs=4[atest1];[1][1][1][1]amerge=inputs=4[atest2]"" -map [vtest] -map [atest1] -map [atest2] -c:v mpeg2video -b:v 4000k -minrate 4000k  -maxrate 4000k -bufsize 2000k -g 10 -bf 0 -c:a aac -ac 4  -f mpegts " . url_preview							; test signal generator for EE preview, 2019/9/6
*/


;----------------------------------------------------  Test parameter ----------------------------------------------------
;preview_param := "-i rtmp://210.216.76.120/live/sbsonair  -c copy -f mpegts -bsf:v h264_mp4toannexb " . url_preview			; for test

; for Developing ~~~~~~~~~~
/*
ffmpeg2018 -f dshow -r 29.97 -video_size 1920x1080 -rtbufsize 2100M -framerate 29.97 -top 1 -pixel_format uyvy422 -sample_rate 48000 -sample_size 16 -channels 8 -i "video=Decklink Video Capture:audio=Decklink Audio Capture" -filter_complex ""[0:v]field=0[vfield];[vfield]scale=iw/4:ih/2;[0:a]asplit[a1][a2];[a1]pan=4.0^|c0=c0^|c1=c1^|c2=c2^|c3=c3;[a2]pan=4.0^|c0=c4^|c1=c5^|c2=c6^|c3=c7"" -pix_fmt yuv420p  -c:v mpeg2video  -b:v 4000k -minrate 4000k  -maxrate 4000k -bufsize 2000k -g 10  -c:a aac -ac 4  -f mpegts udp://127.0.0.1:8888

mpv --lavfi-complex=[aid1]showvolume=r=29.97[vvolume1];[aid2]showvolume=r=29.97[vvolume2];[vid1][vvolume1]overlay=x=20:y=50[vtemp];[vtemp][vvolume2]overlay=x=20:y=140[vo]  --osd-font-size=45 --no-border --cache-secs=0 --video-sync=audio  --untimed --no-cache-pause --cache-backbuffer=0 --frame-drop=no --no-demuxer-thread  --vd-lavc-threads=1 --no-audio --vo=opengl --hwdec=no udp://127.0.0.1:8888

*/

;----------------------------------------------------  Test parameter ----------------------------------------------------

;preview_param_mpv := "--lavfi-complex=[aid1]asplit[as1][as2];[as1]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vfmt];[vfmt][vvolume]overlay=x=20:y=20[vo];[as2]pan=stereo|c0=c0|c1=c1[ao] --title ""Preview Window " . CHNAME . """ --window-scale=0.5 --osc=no --input-default-bindings=no --untimed --no-demuxer-thread  --vd-lavc-threads=1 " . mpv_geometry[channel_index]					;  with audio. many latency
;preview_param_mpv := "--lavfi-complex=[aid1]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vfmt];[vfmt][vvolume]overlay=x=20:y=20[vo] --title ""Preview Window " . CHNAME . """ --window-scale=0.5 --osc=no --input-default-bindings=no --cache=no --cache-secs=0 --video-sync=audio --untimed --no-demuxer-thread  --vd-lavc-threads=1 --no-audio " . mpv_geometry[channel_index]		; single stream, multi channel, without audio PB. very low latency
 ; --untimed --no-demuxer-thread  --vd-lavc-threads=1 --no-audio	--video-sync=audio			; additional option for low latency
;--------------------------------------------------- ffmpeg parameter for EE Preview -------------------------------------------------------------------------

;-------------------------------------------------- mpv parameter for EE Preview ----------------------------------------------------------------------------
;preview_param_mpv := "--lavfi-complex=[aid1][aid2][aid3][aid4][aid5][aid6][aid7][aid8]amerge=inputs=8[a1];[a1]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vfmt];[vfmt][vvolume]overlay=x=20:y=20[vo] --title """ . title_ee . """ --window-scale=0.5 --osc=no --input-default-bindings=no  --cache-secs=0 --video-sync=audio  --untimed --no-demuxer-thread  --vd-lavc-threads=1 --no-audio " . mpv_geometry[channel_index]		; multi stream, single channel		; without audio PB  		(version 2019/5/30)   ----amerge intgroduce audio level meter group delay----

;preview_param_mpv := "--lavfi-complex=[aid1]showvolume=r=29.97[vvolume1];[aid2]showvolume=r=29.97[vvolume2];[vid1][vvolume1]overlay=x=20:y=50[vtemp];[vtemp][vvolume2]overlay=x=20:y=140[vo]  --osd-font-size=45 --no-border --osc=no --window-scale=0.5  --input-default-bindings=no  --cache-secs=0 --video-sync=audio  --untimed --no-demuxer-thread   --vd-lavc-threads=1 --no-audio " . param_mpv_add . mpv_geometry[channel_index] . " --title=""" . title_ee . """  --osd-msg1=""" . CHNAME . """ "	; multi stream, single channel		; without audio PB  		(Last good parameter 2019/6/3, latency is very good, 960x540 resolution)

;preview_param_mpv := "--lavfi-complex=[aid1]showvolume=r=29.97:t=0:v=0:h=10[vvolume1];[aid2]showvolume=r=29.97:t=0:v=0:h=10[vvolume2];[vid1][vvolume1]overlay=x=20:y=30[vtemp];[vtemp][vvolume2]overlay=x=20:y=80[vo]  --osd-font-size=45 --no-border --osc=no   --input-default-bindings=no  --cache-secs=0 --video-sync=audio  --untimed --no-demuxer-thread   --vd-lavc-threads=1 --no-audio " . param_mpv_add . mpv_geometry[channel_index] . " --title=""" . title_ee . """  --osd-msg1=""" . CHNAME . """ "	; multi stream, single channel		; without audio PB  		(Last good parameter 2019/6/11, 480x270 reseolution)

;preview_param_mpv := "--lavfi-complex=[aid1]showvolume=r=29.97:t=0:v=0:h=10[vvolume1];[aid2]showvolume=r=29.97:t=0:v=0:h=10[vvolume2];[vid1][vvolume1]overlay=x=20:y=30[vtemp];[vtemp][vvolume2]overlay=x=20:y=80[vo]  --osd-font-size=45 --no-border --osc=no   --input-default-bindings=no  --cache-secs=0 --video-sync=audio  --untimed --no-cache-pause --cache-backbuffer=0  --no-demuxer-thread  --framedrop=no --vd-lavc-threads=1 --no-audio " . param_mpv_add . mpv_geometry[channel_index] . " --title=""" . title_ee . """  --osd-msg1=""" . CHNAME . """ "	; multi stream, single channel		; without audio PB  		(Last good parameter 2019/6/19, 480x270 reseolution)

preview_param_mpv := "--lavfi-complex=[aid1]showvolume=r=29.97:t=0:v=0:h=10[vvolume1];[aid2]showvolume=r=29.97:t=0:v=0:h=10[vvolume2];[vid1][vvolume1]overlay=x=20:y=30[vtemp];[vtemp][vvolume2]overlay=x=20:y=80[vo]  --osd-font-size=45 --no-border --osc=no   --input-default-bindings=no  --cache-secs=0  --no-cache-pause --cache-backbuffer=0  --no-audio --script=""" .  A_ScriptDir . "\cache_eater.lua"" " .  param_mpv_add . mpv_geometry[channel_index] . " --title=""" . title_ee . """  --osd-msg1=""" . CHNAME . """ "	; multi stream, single channel		; without audio PB  		(Last good parameter 2019/6/27, 480x270 reseolution, with cache-eater script)

;preview_param_mpv := "--lavfi-complex=[aid1]showvolume=r=29.97:t=0:v=0:h=10[vvolume1];[aid2]showvolume=r=29.97:t=0:v=0:h=10[vvolume2];[vid1][vvolume1]overlay=x=20:y=30[vtemp];[vtemp][vvolume2]overlay=x=20:y=80[vo]  --osd-font-size=45 --no-border --osc=no   --input-default-bindings=no  --cache-secs=0  --no-cache-pause --cache-backbuffer=0  --no-audio --script=""" .  A_ScriptDir . "\low_latency.lua"" " .  param_mpv_add . mpv_geometry[channel_index] . " --title=""" . title_ee . """  --osd-msg1=""" . CHNAME . """ "	; new mpa lua script applied 2020/4/28

;preview_param_mpv := "--lavfi-complex=[aid1][aid2]amerge=inputs=2[a1];[a1]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vfmt];[vfmt][vvolume]overlay=x=20:y=50[vo]  --osd-font-size=40 --no-border --window-scale=0.5  --input-default-bindings=no  --cache-secs=0 --video-sync=audio  --osc=no --ao-null-untimed --no-demuxer-thread   --vd-lavc-threads=1 --no-audio " . param_mpv_add . mpv_geometry[channel_index] . " --title=""" . title_ee . """  --osd-msg1=""" . CHNAME . """ "	; multi stream, single channel		; without audio PB  		(test parameter with new mpv 2019/6/4) 

; hwdec ; auto is best, auto-copy is second
; mpv recent version : --untimed --->  --ao-null-untimed (recommanded)
; -- in case of problem --
;  --cache-initial=10  --ao-null-untimed 
;  --cache-backbuffer      default is 750000KB (unis is KB)

;-------------------------------------------------- mpv parameter for EE Preview ----------------------------------------------------------------------------

timecode_enabled = XDCAM50_MXF|XDCAM50_MOV|XDCAM_EX_MXF|PRORES_LT_MOV|PRORES_MOV|PRORES_HQ_MOV

; mpv and audio monitor  filter for file playback ---------------------------------------------------------------------------------------------------------------
mpv_filter := Object()
audio_monitor := Object()

mpv_filter["noaudio"] := ""
mpv_filter["mono-1"] := "--lavfi-complex=[aid1]asplit[as1][as2];[as2]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vf];[vf][vvolume]overlay=x=20:y=20[vo]"
mpv_filter["mono-2"] := "--lavfi-complex=[aid1][aid2]amerge=inputs=2[a1];[a1]asplit[as1][as2];[as2]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vf];[vf][vvolume]overlay=x=20:y=20[vo]"
mpv_filter["mono-4"] := "--lavfi-complex=[aid1][aid2][aid3][aid4]amerge=inputs=4[a1];[a1]asplit[as1][as2];[as2]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vf];[vf][vvolume]overlay=x=20:y=20[vo]"
mpv_filter["mono-8"] := "--lavfi-complex=[aid1][aid2][aid3][aid4][aid5][aid6][aid7][aid8]amerge=inputs=8[a1];[a1]asplit[as1][as2];[as2]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vf];[vf][vvolume]overlay=x=20:y=20[vo]"
mpv_filter["stereo-1"] := "--lavfi-complex=[aid1]asplit[as1][as2];[as2]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vf];[vf][vvolume]overlay=x=20:y=20[vo]"
mpv_filter["stereo-2"] := "--lavfi-complex=[aid1][aid2]amerge=inputs=2[a1];[a1]asplit[as1][as2];[as2]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vf];[vf][vvolume]overlay=x=20:y=20[vo]"
mpv_filter["stereo-3"] := "--lavfi-complex=[aid1][aid2][aid3]amerge=inputs=3[a1];[a1]asplit[as1][as2];[as2]showvolume=r=29.97[vvolume];[vid1]format=pix_fmts=yuv420p[vf];[vf][vvolume]overlay=x=20:y=20[vo]"
mpv_filter["stereo-4"] := mpv_filter["mono-4"]

mpv_filter["2 channels-1"] := mpv_filter["stereo-1"]
mpv_filter["2 channels-2"] := mpv_filter["stereo-2"]
mpv_filter["2 channels-3"] := mpv_filter["stereo-3"]
mpv_filter["2 channels-4"] := mpv_filter["stereo-4"]

mpv_filter["4 channels-1"] := mpv_filter["stereo-1"]
mpv_filter["4 channels-2"] := mpv_filter["stereo-2"]
mpv_filter["5 channels-1"] := mpv_filter["stereo-1"]
mpv_filter["6 channels-1"] := mpv_filter["stereo-1"]
mpv_filter["7 channels-1"] := mpv_filter["stereo-1"]
mpv_filter["8 channels-1"] := mpv_filter["stereo-1"]
mpv_filter["16 channels-1"] := mpv_filter["stereo-1"]
mpv_filter["32 channels-1"] := mpv_filter["stereo-1"]

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

audio_monitor_filter := ";[as1]pan=stereo|c0=" . audio_monitor[audiomonl] . "|c1=" . audio_monitor[audiomonr] . "[ao]"
;-----------------------------------------------------------------------------------------------------------------------------------------------------------------------

for key, val in gui_stop
	GuiControl, Enable, %val%
for key, val in gui_rec
	GuiControl, Disable, %val%


gui -MinimizeBox -DPIScale -Resize
updatelog("Start Application -----------------------------------------------")

if (channel_index = 1)
{
	DriveGet, outputvar, Capacity, %path_rec%
	updatelog("Capture Disk Capacity is " . outputvar . " MB")
	size_reserve := outputvar * (100 - RegExReplace(size_reserve, "[%]")) /100			; Calculate Total Disk reserve capacity
	updatelog("Reserve Capacity is " . size_reserve . " MB")
}

checkfinishday(finishday)
if !FileExist(binary_ffmpeg)
{
		MsgBox,, 알림, FFMPEG 인코더 파일이 없습니다. 종료 합니다, 4
		updatelog("There is no encoder file " . binary_ffmpeg)
		ExitApp	
}

if !FileExist(binary_mpv)
{
		MsgBox,, 알림, MPV 실행 파일이 없습니다. 종료 합니다, 4
		updatelog("There is no MPV file " . binary_mpv)
		ExitApp	
}

if !FileExist(binary_ffmpeg_uhd)
{
		MsgBox,, 알림, UHD용 인코더 실행 파일이 없습니다. 종료 합니다, 4
		updatelog("There is no UHD FFMPEG file " . binary_ffmpeg_uhd)
		ExitApp	
}

if !FileExist(binary_copymanager)
{
		MsgBox,, 알림, 카피메니저 실행 파일이 없습니다. 종료 합니다, 4
		updatelog("There is no copymanager file " . binary_copymanager)
		ExitApp	
}

OnExit("ExitFunc")


gosub displaynow
gosub codec_change
if (channel_index = 1)
	SetTimer, cleanup_log, -500

return


get_stream_address(ini_file)
{
	IniRead, outputvar, %ini_file%, url, stream, rtmp://210.216.76.120/live/sbsonair
	outputvar_quote = "%outputvar%"
	return outputvar_quote
}

get_decklinkname(default_name, channel_index)
{
	IniRead, decklink_name, svcr%channel_index%.ini, name, decklink, %default_name%
	decklink_name := RegExReplace(decklink_name, "[""]")			; remove double quotation if exist
	decklink_name = "%decklink_name%"										; apply double quotation
	;FileAppend, %decklink_name%`r`n, *
	return  decklink_name
	
}

url_to_address_array(url)		; convert human visible url  -> separate address, port
{
	address_array := object()
	RegExMatch(url, "\d+.\d+.\d.\d+", ipaddr)
	pos := RegExMatch(url, ":\d+")
	port := SubStr(url, pos+1)
	address_array.push(ipaddr)
	address_array.push(port)
	
	return address_array
}


GuiDropFiles:

GuiControl,, %hstatus%, Analysing Media...Please wait
media.fullpath := A_GuiEvent
analyse_media(media, minfo)

GuiControl,, %hstatus%, % "Finish Analysing Media /  (audio format " . media.audio_format . " / Scan type " . media.scantype . " / Duration " . media.duration . ")"
updatelog("Drag drop media file . " .  A_GuiEvent . "   Media audio format is " . media.audio_format . " Scan type is " . media.scantype . " Duration is " . media.duration)

file_srt := makesrt(A_GuiEvent, media.duration)		; 	; make srt before file play

runstring := binary_mpv . " " . mpv_filter[media.audio_format] . audio_monitor_filter
FileAppend, % media.width, *
if (media.width > 1600)				; audio spectrum video have 1564 width
	runstring = %runstring% --window-scale=0.5

if (media.scantype = "interlaced")
	runstring .= " --deinterlace=yes "
SplitPath, A_GuiEvent, outfilename
runstring = %runstring%  --title "%outfilename%" --sub-pos=10  --keep-open "%A_GuiEvent%"
Run, %runstring%,, Minimize

;SetTimer, delete_srt, -3000				; making srt takes long time
return


delete_srt:
FileDelete, %file_srt%
updatelog("SRT file deleted ... " . file_srt)
return


get_media_date(file)
{
	foundpos := RegExMatch(file, "20\d\d_\d\d\d\d[.]", string_date)
	if foundpos
	{
		return SubStr(string_date,1,4) . substr(string_date, -3)
	}
	else
	{
		FileGetTime, outputvar, %file%, C
		return outputvar
	}
}


makesrt(file_movie, duration=3600)			; make srt before file play
{
	SplitPath, file_movie, outfilename, outdir, outextension, outnamenoext, outdrive
	time_file := get_media_date(file_movie)
	srtfile = %outdir%\%outnamenoext%.srt
	if FileExist(srtfile)
	{
		FileDelete, %srtfile%												; Changed 2019/8/22 (delete previous srt file)
		updatelog("Srt file exist, Deleting srt file......")
	}
	time_initial := 19990101000000
	hsrtfile := FileOpen(srtfile, "w")
	Loop, % round(duration)
	{
		FormatTime, display_tc, %time_file%, yyyy/MM/dd HH:mm:ss
		FormatTime, srt_tc, %time_initial%, HH:mm:ss
		text_srt = %A_Index%`r`n%srt_tc%.000 --> %srt_tc%.999`r`n%display_tc%`r`n
		hsrtfile.Write(text_srt)
		time_initial += 1, second
		time_file += 1, second
	}
	hsrtfile.Close()
	updatelog("Make srt file . " . srtfile)
	return srtfile
}





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



return


displaynow:
WinSetTitle, ahk_id %hthiswindow%,, % title . "      [" . audiomonl . " - "  . audiomonr . "]   " .    formatednow()

if (channel_index = 1)			; new 2019/6/15,  VTR1 Specific job (delete old file, cleanup log...)
{
	DriveSpaceFree, size_free, % folders_capture[1]		; result is in MB,      update 2019/7/30
	if (size_free < size_reserve )											; free space is smaller than reserved capacity
	{
		updatelog(folders_capture[1] .  "  Free space : " . size_free . " MB Left")
		Loop, 5																		; update 2019/7/30 (each vtr has different path_rec)
			updatelog(deleteoldestfile(folders_capture[A_Index]))	;	 Delete oldest file from each rec path
	}
	if InStr(time_cleanup, SubStr(formatednow(),1,5))			; compare hh:mm with 'time_cleanup' and periodically delete old files
		SetTimer, cleanup_log, -500
}

/*  old manner
if ((channel_index = 1) and (size_free < size_reserve ))						; free space is smaller than reserved capacity
	updatelog("Free space : " . size_free . " MB Left / " . deleteoldestfile(path_rec))		;	 Delete oldest file from rec path

if ((channel_index = 1) and InStr(time_cleanup, SubStr(outputvar,1,5)))			; compare hh:mm with 'time_cleanup' and periodically delete old files
	SetTimer, cleanup_log, -500
*/

SetTimer, displaynow, % -(61 - A_Sec) * 1000
return


formatednow()
{
	FormatTime, outputvar,, HH:mm (yyyy/MM/dd)
	return outputvar
}



cleanup_log:			; delete old log file

if autodelete_age			; positive value, unit is hour
	updatelog(deleteoldfiles(path_rec, autodelete_age))				; auto delete Record file (unit is hour)

updatelog(deleteoldfiles(A_WorkingDir . "\log" , 8760))			; Delete log files
for key, val in files_log					; rename large log file
{
	FileGetSize, outputvar, %val%
	if (outputvar > 1000000)					; log size is larger than limit
	{
		FileMove, %val%, %val%_old_%A_Year%%A_Mon%%A_DD%_%A_Hour%%A_Min%.log, 1		
		updatelog("Log file renamed " . val . "Size is " . outputvar)
	}
}

return




codec_change:
GuiControlGet, codec_choice
GuiControl,, %hgroupbox%, %CHNAME%-%codec_choice%
preview_param := preview_param_list[codec_choice]
binary_encoder := encoder_array[codec_choice]
FileAppend, %binary_encoder%`r`n, *

return


text1:
Run, explorer %path_dst%

return


text2:
if FileExist(file_rec_full)
	run, explorer.exe /select`, "%file_rec_full%"
else
	run, explorer.exe "%path_rec%"
return

get_wallclock_segmentlist(min, sec)				; get ffmpeg segmet time list by wallclock (each o'clock) for mpeg-ts only
{
	soption := "  -f segment -fflags +genpts -reset_timestamps 1 -segment_times "
	rem_clock := (59-min) * 60 + (60-sec)
	rem_clock := rem_clock < 60 ? rem_clock + 3600 : rem_clock
	soption .= rem_clock
	Loop, 22
		soption .= "," . (A_Index * 3600 + rem_clock)
	return soption
}

start_rec:
Gui, Submit, NoHide
SetTimer, mpv_check, Off
updatelog("[REC] Button pressed. Codec selection is " . codec_choice)
for key, val in gui_stop
	GuiControl, Disable, %val%


pid_ffmpeg_preview := close_ffmpeg(pid_ffmpeg_preview)
pid_mpv_preview := close_mpv(pid_mpv_preview)
flag_rec_restart := 0
updatelog("Restart Rec flag set to FALSE")
progress_var.dup_frame_old := 0
progress_var.drop_frame_old := 0


; ----------------------------------- TC and file name parameter ----------------------------------------
tc_start := secondtotc_drop((A_Hour*3600 + A_Min*60 + A_Sec) . "." . A_MSec)
file_userinput := validatefilename(file_userinput)

last_name = %A_Year%%A_Mon%%A_DD%_%A_Hour%%A_Min%%A_Sec%
file_rec_full = %path_rec%%file_userinput%_%CHNAME%_%last_name%
file_rec_proxy_full = %file_rec_full%_proxy.mp4
if chk_split
	file_rec_full .= "_%05d"
file_rec_full_old = %path_rec%%file_userinput%_%CHNAME%_%last_name%_00000
file_rec_full .= "." . extension[codec_choice]
file_rec_full_old .= "." . extension[codec_choice]

updatelog("Rec file name is " . file_rec_full)
; ----------------------------------- TC and file name parameter ----------------------------------------


; ----------------------------------- Encoder parameter ----------------------------------------
runstring := binary_encoder . " " . encoder_param[codec_choice] . " -progress " . url_progress
if (InStr(timecode_enabled, codec_choice)	and flag_tcwrite	)							; add timecode option for supported wrapper,                                   update 2020/4/8 check flag_tcwrite
	runstring = %runstring%  -timecode %tc_start% -drop_frame_timecode 1
if chk_split
	if flag_sbsdvr 
		runstring := runstring . " " . get_wallclock_segmentlist(A_Min, A_Sec)			; make next o'clock segment list (SBS DVR only)
	else
		runstring := runstring . " " .  split_param[codec_choice]									; normal segment list
runstring = %runstring% "%file_rec_full%"
;FileAppend, %runstring%, *
; ----------------------------------- Encoder parameter ----------------------------------------

file_ffreport = ffmpeg_encoder_main_%file_userinput%[%A_DD%]_%A_Hour%_%A_Min%_%A_Sec%_%A_MSec%--[%CHNAME%].log
EnvSet, FFREPORT, file=%file_ffreport%:level=24				; error, 16 / warning, 24 / info, 32 
Run, %runstring%, %A_WorkingDir%\log, Minimize, pid_ffmpeg
WinWait, ahk_pid %pid_ffmpeg%
WinSetTitle, ahk_pid %pid_ffmpeg%,, %title_encoder_main%
updatelog("Encoder Started with pid " . pid_ffmpeg)


; ------------------------------------ Run EE Preview ------------------------------------------
runstring = %binary_mpv% %preview_param_mpv% %url_preview%
Run, %runstring%,,Minimize, pid_mpv_preview
;WinWait, ahk_pid %pid_mpv_preview%,,3
;WinMove, ahk_pid %pid_mpv_preview%,, 20000, 20000				; Move away invisible area
;WinSetTitle, ahk_pid %pid_mpv_preview%,, %title_ee%
SetTimer, SetMPVtitle, -1000
updatelog("MPV Preview started with pid " . pid_mpv_preview)
; ------------------------------------ Run EE Preview ------------------------------------------


if chk_split				; change rec file name for encoder_check routine
{
	file_rec_full := file_rec_full_old
	updatelog("Split mode, first segment name is " . file_rec_full)
}


; ----------------------------------- Proxy Encoder --------------------------------------------------------
if chk_proxy
{
	file_ffreport_proxy = ffmpeg_encoder_proxy_%file_userinput%[%A_DD%]_%A_Hour%_%A_Min%_%A_Sec%_%A_MSec%.log
	EnvSet, FFREPORT, file=%file_ffreport_proxy%:level=24	
	runstring = %binary_ffmpeg% %proxy_param% %duration_max_proxy% "%file_rec_proxy_full%"
	Run, %runstring%, %A_WorkingDir%\log, Minimize, pid_ffmpeg_proxy
	WinWait, ahk_pid %pid_ffmpeg_proxy%
	WinSetTitle, ahk_pid %pid_ffmpeg_proxy%,, %title_encoder_proxy%
	updatelog("Proxy Encoder Started with pid " . pid_ffmpeg_proxy)
}
; ----------------------------------- Proxy Encoder --------------------------------------------------------


GuiControl,, %htext2%, % SubStr(file_rec_full, -65)						; show rec filename
GuiControl, show, %hred_bar%
SetTimer, encoder_check_once, -1500

for key, val in gui_rec
	GuiControl, Enable, %val%

return


rec_ee_limit:
pid_mpv_preview := close_mpv(pid_mpv_preview)
return


stop_rec:
timer_tick("start")
updatelog("[STOP] Button pressed")

for key, val in gui_rec
	GuiControl, Disable, %val%
GuiControl, Disable, %hpreview%

updatelog("GUI Change takes " . timer_tick("stop") . " msec")
GuiControl,, %hstatus%, % "GUI Change takes " . timer_tick("stop") . " msec"

SetTimer, encoder_check, off
SetTimer, encoder_check_once, Off

if chk_proxy
	pid_ffmpeg_proxy := close_ffmpeg(pid_ffmpeg_proxy)

pid_ffmpeg :=close_ffmpeg(pid_ffmpeg)
pid_mpv_preview := close_mpv(pid_mpv_preview)
FileGetSize, size_rec, %file_rec_full%

if flag_sbsdvr
	FileMove, %file_rec_full% , % renametofiledate(file_rec_full)
		
updatelog("Finish Recording  " . file_rec_full . " / File size is " . size_rec . " Bytes")

for key, val in gui_stop
	GuiControl, Enable, %val%
GuiControl, Enable, %hpreview%
GuiControl, Hide, %hred_bar%
if flag_rec_restart
{
	updatelog("Restart REC flag is TRUE.. REC will start soon")
	SetTimer, start_rec, -100
}
;else
;	SetTimer, check_finish, -1000								; Double Check encoder finish		added 2019/10/11
updatelog("Closing Encoder takes " . timer_tick("stop") . " msec")	; calculate time for stop recording
GuiControl,, %hstatus%, % "Closing Encoder takes " . timer_tick("stop") . " msec"
return



check_finish:
Process, Exist, %pid_ffmpeg%
if ErrorLevel
	{
		RunWait, taskkill /pid %pid_ffmpeg%,, Hide
		SetTimer, check_finish, -1000
		updatelog("Encoder still exist, sending int signal")
	}
	else
	{
		SetTimer, check_finish, Off
		updatelog("Encoder Not exist set pid_ffmpeg to -1")
		pid_ffmpeg := -1
	}
return





timer_tick(param)
{
	static timer
	if (param = "start")
	{
		timer := A_TickCount
		return timer
	}
	if (param = "stop")
		return A_TickCount - timer
}

encoder_check_once:
Process, Exist, %pid_ffmpeg%
	if !ErrorLevel
	{
		updatelog("Encoder Stopped, There is cirtical problem. ffmpeg PID " . pid_ffmpeg)			; ffmpeg exit immediately (There is something wrong)
		pid_ffmpeg := -1
		SetTimer, stop_rec, -100
		GuiControl,, %hstatus%, Encoder Stopped`, There is cirtical problem
	}
	else
	{
		if chk_transfer			; Transfer is enabled, trigger transfer
		{
			updatelog("Triggering Transfer first segment (or single file), 5000 msec")
			Random, rand, 1, 2000
			SetTimer, transfer_trigger, % -5000-rand		; This trigger will ignored for short length first segment (_00000)
		}
		SetTimer, encoder_check, -1500
		if flag_recee_limit			; REC EE time limit (save system resource)
			SetTimer, rec_ee_limit, -20000
		if ((flag_ccg_ee) and (SubStr(file_rec_full, -2) = "mxf"))				; SBS EE mode (operate with Caspar CG), added 2021/4/15
		{
			timer_ee := Func("sendamcp").bind(file_rec_full)					; Takes long time if there is no caspar Engine
			SetTimer, % timer_ee, -3000
			updatelog("CasparCG EE mode enabled -- try to send amcp command")
		}
	}
return


sendamcp(filename)					; send play command to CCG (confi operate)
{
	SplitPath, filename, outfilename
	try
	{
		amcp := new SocketTCP()
		amcp.connect(["127.0.0.1", 5250])			; Local CCG amcp default port = 5250
		amcp.sendtext("play 1-1 """ . outfilename . """ length 1078921 `r`n")			; 5 Hour length (1078921 field)
		amcp.disconnect()
		amcp := ""
		updatelog("Successfully sending amcp command")
	}
	catch, err
		updatelog("Error while sending amcp command")
}


renametofiledate(f)
{
	SplitPath, f, outfilename, outdir, outextension, outnamenoext, outdrive
	FileGetTime, time_f, %f%, C
	FormatTime, time_str, %time_f%, yyyyMMdd_HHmmss
	newfilename := RegExReplace(outfilename, "20\d\d\d\d\d\d_\d\d\d\d\d\d_00\d\d\d", time_str)
	FileAppend, %outdir%\%newfilename%`r`n, *
	return outdir . "\" . newfilename
}

encoder_check:
Critical					; added 2019/8/22			
if chk_split
{
	;updatelog("Current segment is " . file_rec_full)
	;updatelog("<Next> segment is " . getnextsegment(file_rec_full, 5))
	if FileExist(getnextsegment(file_rec_full))
	{
		FileGetSize, size_rec, %file_rec_full%
		updatelog("Finish recording segment file " . file_rec_full . " / Size is " . size_rec . " Bytes")
		if flag_sbsdvr
			FileMove, %file_rec_full% , % renametofiledate(file_rec_full)
		file_rec_full := getnextsegment(file_rec_full)
		updatelog("There is rec file name change, new file name is " . file_rec_full)
		GuiControl,, %htext2%, % SubStr(file_rec_full, -65)						; show rec filename, last few character
	}
}

FileGetSize, size_rec, %file_rec_full%
FileGetSize, size_ffreport, %A_WorkingDir%\log\%file_ffreport%			; read size of ffreport file
FileRead, text_ffreport, %A_WorkingDir%\log\%file_ffreport%				; read contents of ffreport file

;GuiControl,, %hfilesizedisplay%, % "Size " . Round(size_rec / 1000000) . " MB"
GuiControl,, %hstatus%, % "Progress Time " . progress_var.time . " - Size " . progress_var.size . " - Frame " . progress_var.frame . " - DUP " . progress_var.dup_frame . " - DROP " . progress_var.drop_frame . " - FFREPORT " . size_ffreport . " - Speed " . progress_var.speed
GuiControl,, %hrectimedisplay%, % progress_var.time . " / " . Round(size_rec / 1048576) . " MB"

;size_rec := progress_var.size				; change size_rec to streaming size 2019/6/5 (in split rec mode , large size file closing takes very long time introduce wrong decision)
; SPLIT MODE, progress_var.size does not incresing during finalizing segment file (Find 2019/6/7)

if (progress_var.dup_frame_old != progress_var.dup_frame)
	updatelog("DUP  changed at time " . progress_var.time . " / DUP is " . progress_var.dup_frame)

if (progress_var.dup_frame > 100)					; added 2020/5/27			(for UHD)
{
	updatelog("FFMPEG dup value exceed limit. Terminating Encoder /_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/  PID " . pid_ffmpeg)
	updatelog("FFMPEG DUP value is " . progress_var.dup_frame )
	if chk_proxy
		close_ffmpeg(pid_ffmpeg_proxy)
	close_ffmpeg(pid_ffmpeg)
}

/* 			rc buffer underflow example ----------------------------------------------
[mpeg2video @ 0000000002272540] rc buffer underflow
[mpeg2video @ 0000000002272540] max bitrate possibly too small or try trellis with large lmax or increase qmax
[mpeg2video @ 0000000002272540] rc buffer underflow
[mpeg2video @ 0000000002272540] max bitrate possibly too small or try trellis with large lmax or increase qmax
*/

if ((size_ffreport - size_ffreport_old) > 15000)			; There is great ffreport log increment (before 500, 2019/11/15 changed to 2000)	, changed 2000 -> 6000 (2020/4/10) -> 15000 (2020/7/15)
{
		updatelog("FFMPEG log report abnormal size incresing. Terminating Encoder /_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/  PID " . pid_ffmpeg)
		updatelog("FFMPEG Log file size is " . size_ffreport . " Byte /  Delta is " . size_ffreport - size_ffreport_old . " Byte")
		if chk_proxy
				close_ffmpeg(pid_ffmpeg_proxy)
		close_ffmpeg(pid_ffmpeg)
}

if InStr(text_ffreport, "! frame dropped!")				; Terminate ffmpeg if there is frame dropping. added 2020/4/10
{
	updatelog("FFMPEG log report Frame dropping. Terminating Encoder /_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/  PID " . pid_ffmpeg)
	if chk_proxy
		close_ffmpeg(pid_ffmpeg_proxy)
	close_ffmpeg(pid_ffmpeg)
}

if (chk_transfer and !(file_rec_full_old  = file_rec_full))		; Transfer is enabled, rec file name change is detected is SPLIT REC Mode
{
	updatelog("OLD FILE="  . file_rec_full_old . "   /   NEW FILE="  . file_rec_full )	
	updatelog("Triggering Transfer, 5000 msec")
	Random, rand, 1, 2000
	SetTimer, transfer_trigger, % -5000-rand
}

if (size_rec = size_rec_old)				; check if there is rec file size incresing
{
	count_size_mon++
	if (count_size_mon > 5)
	{
		updatelog("Recording File size is not increasing [" . count_size_mon . "] seconds")
		updatelog("file_rec is " . file_rec_full . " / Rec file size is " . size_rec )
	}
	
	if (count_size_mon > 12)								; File size is not incresing during long period, (slow pc takes long time in finilizing large file)
	{
		updatelog("Terminating Encoder (Rec file size is not increasing) /_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/ PID " . pid_ffmpeg)
		if chk_proxy
			close_ffmpeg(pid_ffmpeg_proxy)
		close_ffmpeg(pid_ffmpeg)
		count_size_mon := 0
	}
}
else
	count_size_mon := 0

if ((flag_sbsdvr) and InStr(A_Hour . A_Min , "0429") and A_Sec >= 58)			; Added 2019/7/20  (SBS Dvr mode, Recording reset every 4:29.58 AM)
{
	close_ffmpeg(pid_ffmpeg)
	updatelog("Finish Recording file,  SBS DVR Mode _/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_ PID " . pid_ffmpeg)
}

file_rec_full_old := file_rec_full
size_rec_old := size_rec
size_ffreport_old := size_ffreport
progress_var.dup_frame_old := progress_var.dup_frame
progress_var.drop_frame_old := progress_var.drop_frame

Process, Exist, %pid_ffmpeg%
	if ErrorLevel
		SetTimer, encoder_check, -1000				; Normal state, encoder is exist
	else
	{
		updatelog("There is no Encoder PID (Encoder stopped), Try to Restart  (Triggering stop and start rec button) >>>>>>>>>>>>>>>>>>>")			; Encoder is not exist, Try to press rec_start button
		SetTimer, encoder_check, off
		pid_ffmpeg := -1
		GuiControl,, %hstatus%, Encoder Stopped, Try to Restart >>>>>>>>>>>>>>>>>
		flag_rec_restart := 1				; Set restart flag to 1
		updatelog("Restart Rec flag set to TRUE")
		SetTimer, stop_rec, -200
	}


DriveSpaceFree, size_free, %path_rec%\		; result is in MB
;GuiControlGet, outputvar, enabled, %hstop_rec%				; removed 2019/9/3

if (size_free < 10000)		; free space is low
{
	updatelog("Drive space low.. Triggering stop Button 500ms. " . path_rec . "  /   " .  size_free . " MB left >>>>>>>>>>>>>>>>>")
	GuiControl,, %hstatus%, % "Drive space low.. stop recording. " . path_rec . "  /   " .  size_free . " MB left"
	SetTimer, stop_rec, -500					; Stop Recording at low HDD Capacity
	SetTimer, encoder_check, Off
}

return


transfer_trigger:
GuiControl,Show, %hgreen_bar%
;file_dst_full = %path_dst%%file_userinput%_%CHNAME%_%last_name%
;file_dst_full .= "." . extension[codec_choice]
SplitPath, file_rec_full, temp
file_dst_full = %path_dst%\%temp%

Run, %A_WorkingDir%\%binary_copymanager% "%file_rec_full%" "%file_dst_full%" "%title%" %channel_index%,,, pid_transfer

updatelog("Transfer Started with pid " . pid_transfer . " [-->>] " . file_rec_full . "   --->   " . file_dst_full)
SetTimer, transfer_check, -1000
return


transfer_check:
Process, Exist, %pid_transfer%
if ErrorLevel
	SetTimer, transfer_check, -500
else
{
	GuiControl,Hide, %hgreen_bar%
	pid_transfer := -1
	SetTimer, transfer_check, Off
}

return

close_ffmpeg(pid)
{
	Critical
	updatelog("Try to close FFMPEG PID " . pid)
	count := 0
	Process, Exist, %pid%
	exist_process := ErrorLevel
	while(exist_process)
	{
		count += 1
		RunWait, taskkill /pid %pid%,, Hide UseErrorLevel
		updatelog("Sending signal to FFMPEG, signal kill  [" . count . "]  times")
		Process, Exist, %pid%
		exist_process := ErrorLevel
		if exist_process
			Sleep, 1000				; If There is encoder  process, wait 1 second
	}
	updatelog("Closing FFMPEG Result is " . exist_process)
	return -1
}



close_ffmpeg_old2(pid)
{
	Process, Exist, %pid%
	if ErrorLevel				; ffmpeg is running
	{
		RunWait, taskkill /pid %pid%,, Hide UseErrorLevel
		result_close := A_LastError
		updatelog("Closing FFMPEG result is " . result_close)
		if  (!result_close)
		{
			updatelog("Successfully Close ffmpeg PID " . pid)		; Gracefully close ffmpeg
			return pid
		}
		else
		{
			updatelog("Fail to closing ffmpeg PID " . pid . "`r`nTry to Close again --------------------")
			RunWait, taskkill /pid %pid%,, Hide UseErrorLevel
			result_close := A_LastError
			updatelog("Closing FFMPEG (Second Try) result is " . result_close)
			return pid
		}
	}
	else
	{
		updatelog("Try to Close FFMPEG but PID is not found  / PID " . pid)
		return pid
	}
}



close_ffmpeg_old_until201909(pid)
{
	Process, Exist, %pid%
	if ErrorLevel				; ffmpeg is running
		{
		Loop, 3
		{
			ControlSend,, "q", ahk_pid %pid%		; send 'q' key stroke many times
			Sleep, 33
		}
		WinWaitClose, ahk_pid %pid%,, 15			; Wait until closing encoder window (Huge rec file takes long time for finishing)
		if !ErrorLevel
		{
			updatelog("Successfully closing ffmpeg PID " . pid)		; There is no window with ffmpeg pid
			return -1
		}
		else
		{
			Run, taskkill /f /t /pid %pid%,, Hide						; There is window with ffmpeg pid
			updatelog("Error normal closing ffmpeg PID " . pid . "  /  Sending Kill Signal")
			return -1
		}
	}
	else
	{
		updatelog("ffmpeg PID is not found during calling close_ffmpeg() / PID " . pid)
		return pid
	}
}

close_mpv(pid)
{
	Process, Exist, %pid%
	if ErrorLevel			; mpv preview is running
	{
		Run,taskkill /f /t /pid %pid%,, Hide
		WinWaitClose, ahk_pid %pid%,, 2			; Wait until closing mpv console window
		if !ErrorLevel
		{
			updatelog("Successfully terminating mpv PID " . pid)
			return -1
		}
		else
		{
			updatelog("Error terminating mpv PID " . pid)
			return pid
		}
	}
	else
	{
		updatelog("mpv PID is not found during calling close_mpv() / PID " . pid)
		return -1
	}
}

set_target:
IniRead, path_dst, target.ini, Target, path
guicontrol,,%htext1%,  Target : %path_dst%
guicontrol,,%hstatus%, Target Folder is %path_dst% (%A_DD% %A_Hour%:%A_Min%.%A_Sec%)
IniWrite, %path_dst%, svcr%channel_index%.ini, path, target                  ; write ini immediately after selecting target
updatelog("Selected target is " . path_dst)
return





sel_target:
updatelog("Select Target Button pressed")
path_dst := selectfolder(path_dst)

guicontrol,,%htext1%,  Target : %path_dst%
guicontrol,,%hstatus%, Target Folder is %path_dst% (%A_DD% %A_Hour%:%A_Min%.%A_Sec%)
IniWrite, %path_dst%, svcr%channel_index%.ini, path, target                  ; write ini immediately after selecting target
updatelog("Selected target is " . path_dst)
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


preview:
updatelog("[EE] Button pressed")
SetTimer, mpv_check, Off
SetTimer, rec_ee_limit, Off			; Disable Auto close EE preview window if it activated	(start REC and Press EE within 20 second)
Critical
runstring = %binary_encoder% %preview_param%
EnvSet, FFREPORT, file=ffmpeg_preview_%A_DD%_%A_Hour%_%A_Min%_%A_Sec%_%A_MSec%--[%CHNAME%].log:level=24	



pid_ffmpeg_preview := close_ffmpeg(pid_ffmpeg_preview)
pid_mpv_preview := close_mpv(pid_mpv_preview)
WinKill, %title_ee%,, 0						; added 2019/11/21 (double chkeck if there is ffmpeg encoder window)
Process, Exist, %pid_ffmpeg%
if !ErrorLevel								; ffmpeg main encoder is not running
{
	Run, %runstring%, %A_WorkingDir%\log, Minimize, pid_ffmpeg_preview
	WinWait, ahk_pid %pid_ffmpeg_preview%
	WinSetTitle, ahk_pid %pid_ffmpeg_preview%,, %title_ee%
	updatelog("Encoder for preview started with pid " . pid_ffmpeg_preview)
}

; ------------------------------------ Run EE Preview ------------------------------------------
runstring = %binary_mpv% %preview_param_mpv% %url_preview%
Run, %runstring%,,Minimize, pid_mpv_preview
SetTimer, SetMPVtitle, -1000
updatelog("MPV Preview started with pid " . pid_mpv_preview)
; ------------------------------------ Run EE Preview ------------------------------------------

SetTimer, mpv_check, -2000
updatelog("mpv_check timer started")
return



SetMPVtitle:
Process, Exist, %pid_mpv_preview%
if ErrorLevel				; MPV Preview window is  exist
{
	WinSetTitle, ahk_pid %pid_mpv_preview%,, %title_ee%
	updatelog("Successfully Setup MPV Window title -- " . title_ee)
}
else
	updatelog("MPV process is not found, pid is " . pid_mpv_preview)
/*
else
{
	SetTimer, SetMPVtitle, -200
	updatelog("Trigering SetMPVtitle routine again")
}
*/
return




mpv_check:
Process, Exist, %pid_mpv_preview%
if ErrorLevel				; MPV Preview window is still exist
	SetTimer, mpv_check, -400
else								; MPV Preview window is closed
{
	updatelog("MPV preview window closed during mpv_check process, pid " . pid_mpv_preview)
	pid_mpv_preview := -1
	SetTimer, SetMPVtitle, Off
	updatelog("Set MPV Title timer off")
	pid_ffmpeg_preview := close_ffmpeg(pid_ffmpeg_preview)
	/*
	Process, Exist, %pid_ffmpeg_preview%
	if ErrorLevel					; There is encoder for preview
	{
		Run, taskkill /f /pid %pid_ffmpeg_preview%,, Hide		; Close encoder for preview
		updatelog("FFMPEG for preview encoder terminated during mpv_check process" . pid_ffmpeg_preview)
		pid_ffmpeg_preview := -1
	}
	*/
}


return




ExitFunc(ExitReason, ExitCode)
{
	global pid_mpv_preview, pid_ffmpeg_preview, pid_ffmpeg, pid_ffmpeg_proxy
	updatelog("Exit reason is " . ExitReason)
	if ExitReason not in Logoff,Shutdown
	 {
        MsgBox, 4, Quit, Are you sure want to quit ?
        IfMsgBox, No
		{
			updatelog("User denied closing application")
            return 1  ; OnExit functions must return non-zero to prevent exit.
		}
    }
	updatelog("Preparing closing Application")
	close_mpv(pid_mpv_preview)
	close_ffmpeg(pid_ffmpeg_preview)
	close_ffmpeg(pid_ffmpeg)
	close_ffmpeg(pid_ffmpeg_proxy)
	updatelog("Finish closing Application------------------------------------")
	return 0
}


GuiClose:
updatelog("Closing GUI.....")
ExitApp



;----------- Delete old files, unit is hour hour hour hour  !!!!! ------------------------------
deleteoldfiles(path, hour=87600)			; 10 year = 87600 hour,
{
	count := 0
	list_file := ""
	path := RegExReplace(path, "\\$")	;Removes the trailing backslash, if present.
	Loop, %path%\*.*
	{
		time_now := A_Now
		FileGetTime, outputvar, %A_LoopFileFullPath%, M   			; get file Modify time
		time_now -= outputvar, Hours													; get time difference between now and file time
		if (time_now > hour)																	; some action for aged files
		{
			list_file .= "`r`n" . A_LoopFileFullPath . "  -  " . outputvar  . "  -  (" . time_now . ")"
			count++
			try
			{
				FileDelete, %A_LoopFileFullPath%
			}
			catch e
			{
				updatelog("There is problem Deleting files >>>>>>>>> " . e.message)
			}
		}
	}
	;ToolTip %list_file%%count%
	return count . " Files Deleted / path is  " .  path . list_file
}

deleteoldestfile(path)				; Search files in path and delete most old file (NEW !! 2020/11/4 sorting algorithm applied)
{
	if (!FileExist(path))
	{
		updatelog("path is not exist, abandon deleting oldest file >>>> " . path)
		return
	}
	time_old := A_Now
	path := RegExReplace(path, "\\$")			; remove last \ character
	
	list_file := ""
	Loop, files, %path%\*.*, FR					; file only, include subfolder
		list_file .= A_LoopFileTimeModified . "|" . A_LoopFileFullPath . "`n"		; sort file list with modifed time order
	Sort, list_file

	Loop, Parse, list_file, "`n"
	{
		Array := StrSplit(A_LoopField, "|")				
		FileAppend, % Array[2] . "`n" , *
		updatelog("Try to delete file " . Array[2])
		FileDelete, % Array[2]											; find  oldest and deletable file
		result_delete := ErrorLevel
		if !result_delete
			break
	}
	return "File Deleted <" . Array[2] . ">  with ErrorLevel [" . result_delete . "]"
}


deleteoldestfile_backup(path)				; Search files in path and delete most old file
{
	if (!FileExist(path))
	{
		updatelog("path is not exist, abandon deleting oldest file >>>> " . path)
		return
	}
	time_old := A_Now
	path := RegExReplace(path, "\\$")			; remove last \ character
	Loop, files, %path%\*.*, F
	{
		if (A_LoopFileTimeModified < time_old)
		{
			file_old := A_LoopFileFullPath
			time_old := A_LoopFileTimeModified
		}
	}
	try
		FileDelete, %file_old%
	catch e
		updatelog("There is problem Deleting files >>>>>>>>> " . e.message)
	
	if ErrorLevel
		return "Error Deleting Oldest file  <" . file_old . ">"
	else
		return "Oldest file Deleted <" . file_old . ">"
}


getnextsegment(name, digit=5)				; find segment number and increse it  ,  example   getnextsegment("c:\test\test-00022.mpg")
{
	SplitPath, name, outfilename, outdir, outextension, outnamenoext, outdrive
	
	nameonly := substr(outnamenoext, 1, strlen(outnamenoext)-digit)
	segment_number := SubStr(outnamenoext, -(digit-1))
	segment_number += 1
	segment_number := SubStr("000000" . segment_number, -(digit-1))
	return outdir . "\" . nameonly . segment_number . "." . outextension
	
}


validatefilename(channel_name)
{
	channel_name = %channel_name%													; left, right trim (remove space)
	channel_name := RegExReplace(channel_name,"[+\?<>!@#$%^&()\[\]/\\\*""|:;'``]", "_")	; remove invalid character as file name
	channel_name := trim(channel_name)                           		 			; remove space left, right
	if channel_name = 
		channel_name = noname     
	return channel_name
}


getdatestring(param)
{
	if (param = "date")
		return A_Year . A_Mon . A_DD 
	if (param = "datentime")
		return A_Year . A_Mon . A_DD . "_" . A_Hour . A_Min . A_Sec
}

onUDPRecv(this)			; FFMPEG Progress status UDP stream 
{
	global progress_var, remote_control, mv
	static out_time_ms_old := 9999999999999
	static timer := Func("send_mv_stop")
	static timer_srt := Func("send_mv_start")
	string := this.RecvText()
	;ToolTip %string%
	;FileAppend, `n%string%, *
	
	for k, v in remote_control.cmd					; new 2020/11/8
		if (string = v)					; check if there is valid command
		{
			updatelog("Remote command [" . string . "] arrived")
			FileAppend, `n%k% -- %v%,  *
			GuiControlGet, outputvar, Enabled, % remote_control.handle[k]			; Check if button is enabled
			if outputvar
				SetTimer, %k%, -1
			else
				updatelog("Cannot execute remote command !! Button is disabled")
		}
	
	foundpos := RegExMatch(string, "frame=\d+", value)
	if foundpos
	{
		RegExMatch(value, "\d+", value)
		progress_var.frame := value
	}
	
	foundpos := RegExMatch(string, "out_time_ms=\d+", value)
	if foundpos
	{
		RegExMatch(value, "\d+", value)
		progress_var.second := secondtotc(value / 1000000)			; microsecond to second --> Human visible TC
		out_time_ms := value
		if (out_time_ms < out_time_ms_old)							; Send start signal to Multiviewer with new Recording, added 2021/5/25
		{
			Random, delay, 100, 500
			delay := -1 * delay
			SetTimer, % timer_srt, %delay%
		}
		out_time_ms_old := out_time_ms
		SetTimer, % timer, -900												; Send Stop signal to Multiviewer with stop Recording, added 2021/5/25
	}
	
	foundpos := RegExMatch(string, "speed=[\s\d.]+", value)
	if foundpos
	{
		RegExMatch(value, "[\d+.]+", value)
		progress_var.speed := value . "x"
	}

foundpos := RegExMatch(string, "fps=\d+.\d+", fps)				; ffmpeg2014ver does not report speed
	if foundpos
	{
		RegExMatch(fps, "\d+.\d+", value)
		progress_var.fps := value
	}
	
	foundpos := RegExMatch(string, "out_time=\d\d:\d\d:\d\d.\d\d", value)
	if foundpos
	{
		RegExMatch(value, "\d\d:\d\d:\d\d.\d\d", value)
		progress_var.time := value
	}

	foundpos := RegExMatch(string, "total_size=\d+", value)
	if foundpos
	{
		RegExMatch(value, "\d+", value)
		progress_var.size := value
	}

	foundpos := RegExMatch(string, "dup_frames=\d+", value)
	if foundpos
	{
		RegExMatch(value, "\d+", value)
		progress_var.dup_frame := value
	}

	foundpos := RegExMatch(string, "drop_frames=\d+", value)
	if foundpos
	{
		RegExMatch(value, "\d+", value)
		progress_var.drop_frame := value
	}

}

send_mv_start()
{
	global mv
	mv.sendsignal("START")
	print("Send Multiviewer start signal")
}

send_mv_stop()				; Send multiviewer stop signal
{
	global mv
	mv.sendsignal("STOP")	
	print("Send Multiviewer stop signal")
}


updatelog(text)
{
	global logfile
	FileAppend, [%A_Year%/%A_Mon%/%A_DD%] %A_Hour%:%A_Min%.%A_sec%_%A_MSec%  - %text%`r`n, %logfile%
}

/*				; old, simple algorithm
secondtotc_drop(sec)
{
	sec_out := Floor(sec)
	frame_out := sec - sec_out
	hour_out := sec_out // 3600
	minute_out := "00" . Mod(sec_out // 60, 60)
	second_out := "00" . Mod(sec_out, 60)
	frame_out := "00" . Floor(frame_out * 29.97)			; NTSC 29.97 frame

	minute_out := SubStr(minute_out, -1)
	second_out := SubStr(second_out, -1)
	frame_out := SubStr(frame_out, -1)
	
	return % hour_out . ":" . minute_out . ":" . second_out . ";" . frame_out
}
*/


secondtotc_drop(sec)			; changed 2020/3/23
{
	frames := Round(sec * 29.97)
	return frametotc(frames)
}


frametotc(frames)					; changed 2020/3/23  (NTSC Drop frame Applied)
{
	framerate := 29.97
	fps_int := Round(framerate)
	sizeBigCycle := 17982			; every 10 minute, there is no tc drop
	sizeWeeCycle := 1798			; every  1 minute, there is tc drop
	numBigCycles := frames // sizeBigCycle
	tailFrames := frames - (numBigCycles * sizeBigCycle)
	
	if (tailFrames < (sizeWeeCycle + 2))
		numWeeCycles := 1
	else
		numWeeCycles := (tailFrames - 2) // sizeWeeCycle + 1
	
	numSkips1 := numWeeCycles - 1
	numSkips2 := numBigCycles * 9
	numSkips3 := numSkips1 + numSkips2
	framesSkipped := numSkips3 * 2
	adjustedFrames := frames + framesSkipped
	
	frame := Mod(adjustedFrames, fps_int)
	seconds := Mod(adjustedFrames // fps_int, 60)
	minutes := Mod(adjustedFrames // (fps_int * 60), 60)
	hours := adjustedFrames // (fps_int * 3600)
	
	return  format("{1:.01d}:{2:.02d}:{3:.02d};{4:.02d}", hours, minutes, seconds, frame)
}


secondtotc(sec)
{
	sec := Round(sec)
	hour := sec // 3600
	minute := "00" . Mod(sec // 60, 60)
	second := "00" . Mod(sec, 60)

	minute := SubStr(minute, -1)
	second := SubStr(second, -1)
	
	return % hour . ":" . minute . ":" . second
}


checkfinishday(day)
{
	app_life := A_Now
	EnvSub, app_life, %day%, DD
	if app_life > 0
	{
		MsgBox,, 알림, 사용기간 만료`r`n새로운 버전을 받으세요`r`n문의 : SBS 미디어 IT 팀, 4
		ExitApp	
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


class multiviewer
{
	read_config(inifile)
	{
		IniRead, outputvar, %inifile%, multiviewer, address, 127.0.0.1
		this.address := outputvar
		IniRead, outputvar, %inifile%, multiviewer, port, 62011
		this.port := outputvar
		IniRead, outputvar, %inifile%, multiviewer, id, NAME1
		this.id := outputvar
		printobjectlist(this)
	}
	
	sendsignal(msg)				; send start or stop signal
	{

		addr := Object()
		addr.push(this.address)
		addr.push(this.port)
		message := "MV|" . msg . "|" . this.id 
		try
		{
			s := new SocketUDP
			s.connect(addr)
			s.sendtext(message)
			s.disconnect()
			s := ""
		}
		catch, err
			printobjectlist(err)
	}
}


print(text)
{
	global hstatus
	FormatTime, outputvar,, yyyy-MM-dd HH:mm:ss
	FileAppend, `r`n%outputvar%  %text%, *
	GuiControl,, %hstatus%, %outputvar%  %text%
	return text
}


/*  Decklink Format Code
        format_code     description
        ntsc            720x486 at 30000/1001 fps (interlaced, lower field first)
        pal             720x576 at 25000/1000 fps (interlaced, upper field first)
        23ps            1920x1080 at 24000/1001 fps
        24ps            1920x1080 at 24000/1000 fps
        Hp25            1920x1080 at 25000/1000 fps
        Hp29            1920x1080 at 30000/1001 fps
        Hp30            1920x1080 at 30000/1000 fps
        Hp47            1920x1080 at 48000/1001 fps
        Hp48            1920x1080 at 48000/1000 fps
        Hp50            1920x1080 at 50000/1000 fps
        Hp59            1920x1080 at 60000/1001 fps
        Hp60            1920x1080 at 60000/1000 fps
        Hp95            1920x1080 at 96000/1001 fps
        Hp96            1920x1080 at 96000/1000 fps
        Hp10            1920x1080 at 100000/1000 fps
        Hp11            1920x1080 at 120000/1001 fps
        Hp12            1920x1080 at 120000/1000 fps
        Hi50            1920x1080 at 25000/1000 fps (interlaced, upper field first)
        Hi59            1920x1080 at 30000/1001 fps (interlaced, upper field first)
        Hi60            1920x1080 at 30000/1000 fps (interlaced, upper field first)
        hp50            1280x720 at 50000/1000 fps
        hp59            1280x720 at 60000/1001 fps
        hp60            1280x720 at 60000/1000 fps
        2d23            2048x1080 at 24000/1001 fps
        2d24            2048x1080 at 24000/1000 fps
        2d25            2048x1080 at 25000/1000 fps
        2d29            2048x1080 at 30000/1001 fps
        2d30            2048x1080 at 30000/1000 fps
        2d47            2048x1080 at 48000/1001 fps
        2d48            2048x1080 at 48000/1000 fps
        2d50            2048x1080 at 50000/1000 fps
        2d59            2048x1080 at 60000/1001 fps
        2d60            2048x1080 at 60000/1000 fps
        2d95            2048x1080 at 96000/1001 fps
        2d96            2048x1080 at 96000/1000 fps
        2d10            2048x1080 at 100000/1000 fps
        2d11            2048x1080 at 120000/1001 fps
        2d12            2048x1080 at 120000/1000 fps
        4k23            3840x2160 at 24000/1001 fps
        4k24            3840x2160 at 24000/1000 fps
        4k25            3840x2160 at 25000/1000 fps
        4k29            3840x2160 at 30000/1001 fps
        4k30            3840x2160 at 30000/1000 fps
        4k47            3840x2160 at 48000/1001 fps
        4k48            3840x2160 at 48000/1000 fps
        4k50            3840x2160 at 50000/1000 fps
        4k59            3840x2160 at 60000/1001 fps
        4k60            3840x2160 at 60000/1000 fps
        4k95            3840x2160 at 96000/1001 fps
        4k96            3840x2160 at 96000/1000 fps
        4k10            3840x2160 at 100000/1000 fps
        4k11            3840x2160 at 120000/1001 fps
        4k12            3840x2160 at 120000/1000 fps
        4d23            4096x2160 at 24000/1001 fps
        4d24            4096x2160 at 24000/1000 fps
        4d25            4096x2160 at 25000/1000 fps
        4d29            4096x2160 at 30000/1001 fps
        4d30            4096x2160 at 30000/1000 fps
        4d47            4096x2160 at 48000/1001 fps
        4d48            4096x2160 at 48000/1000 fps
        4d50            4096x2160 at 50000/1000 fps
        4d59            4096x2160 at 60000/1001 fps
        4d60            4096x2160 at 60000/1000 fps
        4d95            4096x2160 at 96000/1001 fps
        4d96            4096x2160 at 96000/1000 fps
        4d10            4096x2160 at 100000/1000 fps
        4d11            4096x2160 at 120000/1001 fps
        4d12            4096x2160 at 120000/1000 fps
        8k23            7680x4320 at 24000/1001 fps
        8k24            7680x4320 at 24000/1000 fps
        8k25            7680x4320 at 25000/1000 fps
        8k29            7680x4320 at 30000/1001 fps
        8k30            7680x4320 at 30000/1000 fps
        8k47            7680x4320 at 48000/1001 fps
        8k48            7680x4320 at 48000/1000 fps
        8k50            7680x4320 at 50000/1000 fps
        8k59            7680x4320 at 60000/1001 fps
        8k60            7680x4320 at 60000/1000 fps
        8d23            8192x4320 at 24000/1001 fps
        8d24            8192x4320 at 24000/1000 fps
        8d25            8192x4320 at 25000/1000 fps
        8d29            8192x4320 at 30000/1001 fps
        8d30            8192x4320 at 30000/1000 fps
        8d47            8192x4320 at 48000/1001 fps
        8d48            8192x4320 at 48000/1000 fps
        8d50            8192x4320 at 50000/1000 fps
        8d59            8192x4320 at 60000/1001 fps
        8d60            8192x4320 at 60000/1000 fps

list_devices
If set to true, print a list of devices and exit. Defaults to false. Alternatively you can use the -sources option of ffmpeg to list the available input devices. 
list_formats
If set to true, print a list of supported formats and exit. Defaults to false. 
format_code <FourCC>
This sets the input video format to the format given by the FourCC. To see the supported values of your device(s) use list_formats. Note that there is a FourCC 'pal ' that can also be used as pal (3 letters). Default behavior is autodetection of the input video format, if the hardware supports it. 
bm_v210
This is a deprecated option, you can use raw_format instead. If set to ‘1’, video is captured in 10 bit v210 instead of uyvy422. Not all Blackmagic devices support this option. 
raw_format
Set the pixel format of the captured video. Available values are: 
‘uyvy422’‘yuv422p10’‘argb’‘bgra’‘rgb10’teletext_lines
If set to nonzero, an additional teletext stream will be captured from the vertical ancillary data. Both SD PAL (576i) and HD (1080i or 1080p) sources are supported. In case of HD sources, OP47 packets are decoded. 

This option is a bitmask of the SD PAL VBI lines captured, specifically lines 6 to 22, and lines 318 to 335. Line 6 is the LSB in the mask. Selected lines which do not contain teletext information will be ignored. You can use the special all constant to select all possible lines, or standard to skip lines 6, 318 and 319, which are not compatible with all receivers. 

For SD sources, ffmpeg needs to be compiled with --enable-libzvbi. For HD sources, on older (pre-4K) DeckLink card models you have to capture in 10 bit mode. 
channels
Defines number of audio channels to capture. Must be ‘2’, ‘8’ or ‘16’. Defaults to ‘2’. 
duplex_mode
Sets the decklink device duplex mode. Must be ‘unset’, ‘half’ or ‘full’. Defaults to ‘unset’. 
timecode_format
Timecode type to include in the frame and video stream metadata. Must be ‘none’, ‘rp188vitc’, ‘rp188vitc2’, ‘rp188ltc’, ‘rp188any’, ‘vitc’, ‘vitc2’, or ‘serial’. Defaults to ‘none’ (not included). 
video_input
Sets the video input source. Must be ‘unset’, ‘sdi’, ‘hdmi’, ‘optical_sdi’, ‘component’, ‘composite’ or ‘s_video’. Defaults to ‘unset’. 
audio_input
Sets the audio input source. Must be ‘unset’, ‘embedded’, ‘aes_ebu’, ‘analog’, ‘analog_xlr’, ‘analog_rca’ or ‘microphone’. Defaults to ‘unset’. 
video_pts
Sets the video packet timestamp source. Must be ‘video’, ‘audio’, ‘reference’, ‘wallclock’ or ‘abs_wallclock’. Defaults to ‘video’. 
audio_pts
Sets the audio packet timestamp source. Must be ‘video’, ‘audio’, ‘reference’, ‘wallclock’ or ‘abs_wallclock’. Defaults to ‘audio’. 
draw_bars
If set to ‘true’, color bars are drawn in the event of a signal loss. Defaults to ‘true’. 
queue_size
Sets maximum input buffer size in bytes. If the buffering reaches this value, incoming frames will be dropped. Defaults to ‘1073741824’. 
audio_depth
Sets the audio sample bit depth. Must be ‘16’ or ‘32’. Defaults to ‘16’. 
decklink_copyts
If set to true, timestamps are forwarded as they are without removing the initial offset. Defaults to false. 
timestamp_align
Capture start time alignment in seconds. If set to nonzero, input frames are dropped till the system timestamp aligns with configured value. Alignment difference of up to one frame duration is tolerated. This is useful for maintaining input synchronization across N different hardware devices deployed for ’N-way’ redundancy. The system time of different hardware devices should be synchronized with protocols such as NTP or PTP, before using this option. Note that this method is not foolproof. In some border cases input synchronization may not happen due to thread scheduling jitters in the OS. Either sync could go wrong by 1 frame or in a rarer case timestamp_align seconds. Defaults to ‘0’. 


*/

