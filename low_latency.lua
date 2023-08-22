--[[
MPV script for RTMP, HLS Monitoring
OUTPUT only interested mpv message 
Maintained by sendust
Last edit : 2020/4/27


"demuxer-cache-sate" table list (mpv 2018)

[monitor] reader-pts30.835999999996
[monitor] seekable-rangestable: 0x001a1fa0
[monitor] debug-ts-last41246.789
[monitor] debug-low-level-seeks0
[monitor] fw-bytes58880
[monitor] cache-end31.184000000001
[monitor] eoffalse
[monitor] idlefalse
[monitor] underrunfalse
[monitor] total-bytes7932288

C:\util\mpv-x86_64-20181002>mpv --show-profile=low-latency
Profile low-latency:
 audio-buffer=0
 vd-lavc-threads=1
 cache-pause=no
 demuxer-lavf-o-add=fflags=+nobuffer
 demuxer-lavf-probe-info=nostreams
 demuxer-lavf-analyzeduration=0.1
 video-sync=audio
 interpolation=no
 video-latency-hacks=yes

--cache-secs=0   	 req.  for 'cache-used' properties
 
 
 
C:\util\mpv-x86_64-20181002>mpv --script=Z:\ahk\StreamMonitor_Radio\monitor2.lua --audio-buffer=0 --vd-lavc-threads=1 --cache-pause=no --demuxer-lavf-o-add=fflags=+nobuffer --demuxer-lavf-probe-info=nostreams --cache-secs=0 --video-sync=audio --interpolation=no --video-latency-hacks=yes -af silencedetect=d=0.1 --script-opts=key1="s",key2="\lua\test.log"   http://wowlive.sbs.co.kr/sbsch6/_definst_/sbsch60.stream/playlist.m3u8?token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOiIxODkzMTE0NTM1IiwicGF0aCI6Ii9zYnNjaDYvX2RlZmluc3RfL3Nic2NoNjAuc3RyZWFtIn0.6jN-AAE9Fj72M3hfBSYZEt4sCkXcJLlH501HvB0jUVk


--]]

--mp.set_property("audio-buffer", 0)
--mp.set_property("vd-lavc-threads", 1)
--mp.set_property("cache-pause", "no")
--mp.set_property("demuxer-lavf-o-add", "fflags=+nobufer")
--mp.set_property("demuxer-lavf-probe-info", "nostreams")			-- mpv higher version (2018~)
--mp.set_property("demuxer-lavf-probe-info", "no")				-- compatible with mpv old ver ~2017
--mp.set_property("cache-secs", 0)
--mp.set_property("video-sync", "audio")
--mp.set_property("interpolation", "no")
--mp.set_property("video-latency-hacks", "yes")


str_msg_filtered = "low_latency"				-- not interested message list 

speed_set = 1
speed_old = 1


function printmessage(MPV_EVENT_LOG_MESSAGE)

	local msg_prefix = MPV_EVENT_LOG_MESSAGE.prefix
	local msg_level = MPV_EVENT_LOG_MESSAGE.level
	local msg_text = MPV_EVENT_LOG_MESSAGE.text
	
	if string.find(msg_level, "error") then			-- logging stream error
		print("[ERROR DETECT] " .. msg_text)
	end
	
	if not string.find(str_msg_filtered, msg_prefix) then				-- output only interested message
		print("prefix = " .. msg_prefix)
		print("level = " .. msg_level)
		print("text = " .. msg_text)
	end

	
end


function speed_check()

	local cache_used = mp.get_property_number("cache-used")  -- RTMP pause cache, Require --cache-secs=0 option
	print("--------------------")
	print("cache-used = " .. tostring(cache_used))
	print("--------------------")

	if cache_used then
		cache_used = tonumber(cache_used)
	else
		return
	end
	
	if (cache_used > 0) then		-- check RTMP cache (HLS doesn't work)
		speed_set = 1.5
		else
		speed_set = 1
	end
	
	print("playback speed = x" .. tostring(speed_set))
	
	if speed_set ~= speed_old then
		mp.set_property_number("speed", speed_set)	-- set new Playback speed if new speed come
	end

	speed_old = speed_set
end


mp.enable_messages("v")								-- set MPV log level
mp.register_event("log-message", printmessage)		-- Register mpv message event
mp.add_periodic_timer(1, speed_check)



