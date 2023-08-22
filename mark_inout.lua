-- Script for Mark in and out point (by sendust 2019/6/27) Modified 2019/6/30
-- i ; mark in
-- o ; mark out
-- ctrl+i ; jump to in
-- ctrl+o ; jump to out

pos_in = 0
pos_out = 0
sDuration = ""

function parseTime(pos)
  local hours = math.floor(pos/3600)
  local minutes = math.floor((pos % 3600)/60)
  local seconds = math.floor((pos % 60))
  local milliseconds = math.floor(pos % 1 * 1000)
  return string.format("%02d:%02d:%02d.%03d",hours,minutes,seconds,milliseconds)
end

function mark_in()
	pos_in = mp.get_property_number("time-pos")
	duration = pos_out - pos_in
	if (duration > 0) then
		sDuration = " / Duration " .. tostring(parseTime(duration))
	else
		sDuration = ""
	end
	mp.osd_message("Mark In " .. parseTime(pos_in) .. sDuration)

end

function goto_in()
	mp.set_property_bool("pause", true)
	mp.command("seek " .. pos_in .. " absolute+exact")
	mp.osd_message("Goto In " .. parseTime(pos_in) .. sDuration)
end


function mark_out()
	pos_out = mp.get_property_number("time-pos")
	duration = pos_out - pos_in
	if (duration > 0) then
		sDuration = " / Duration " .. tostring(parseTime(duration))
	else
		sDuration = ""
	end
	mp.osd_message("Mark out " .. parseTime(pos_out) .. sDuration)

end

function goto_out()
	mp.set_property_bool("pause", true)
	mp.command("seek " .. pos_out .. " absolute+exact")
	mp.osd_message("Goto Out " .. parseTime(pos_out) .. sDuration)

end



mp.add_key_binding("i", "mark_in", mark_in)
mp.add_key_binding("o", "mark_out", mark_out)

mp.add_key_binding("ctrl+i", "goto_in", goto_in)
mp.add_key_binding("ctrl+o", "goto_out", goto_out)

-- mp.observe_property('pause', 'bool', PauseIndicator)
