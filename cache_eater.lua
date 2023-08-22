-- Script For low latency live stream playback
--
-- Monitor Cache size and adjust playback speed
-- Try to consume cache immediately
-- Created by sendust 2019/6/27
-- example;  mpv --script "c:\path_to_script\cache_eater.lua" --no-cache-pause --cache-secs=0 rtmp://210.216.76.120/live/sbsonair
-- last modified 2020/5/6
------------------------------------------------------


function oncache()


local c = mp.get_property_number("demuxer-cache-duration")
if c then

	if c>=0.4 then				-- cache size is more than 0.xxx second
		mp.set_property_number("speed", "1.1")
		spd = "speed = x1.1"
	elseif c<=0.3 then
		mp.set_property_number("speed", "0.9")
		spd = "speed = x0.9"
	else
		mp.set_property_number("speed", "1.0")
		spd = "speed = x1.0"
	end
--str_c = tostring(c)
--mp.osd_message(spd .. " / " .. str_c)
end




end


function chk_first()
	position = mp.get_property_number("time-pos")

	if position == nil then			-- mpv for preview is open but there is no stream data
		mp.command("quit")
	end

end

mp.observe_property("demuxer-cache-duration", native, oncache)
mp.add_timeout(4, chk_first)							-- check once 

