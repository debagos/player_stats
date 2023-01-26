player_stats = {}
local debugging = true
local mod_name = minetest.get_current_modname()
local formspec_name = mod_name..":player_stats"
local fs_esc = minetest.formspec_escape
local data_dir = minetest.get_worldpath()..DIR_DELIM..mod_name..DIR_DELIM
local save_interval = 30
local online_player_stats = {}
local remove_unknown_entries = true
local stats_template = {
	player_name = "",
	created = 0,
	nodes_dug = 0,
	nodes_placed = 0,
	items_crafted = 0,
	died = 0,
	chat_messages = 0,
	joined = 0
}

local function get_timestamp()
	return os.time(os.date("!*t"))
end

local function log_debug(log_message)
	if debugging then
		local text = log_message
		if type(text) ~= "string" and type(text) ~= "number" then
			text = dump(text)
		end
		minetest.log("action", "["..mod_name.."] "..text)
	end
end

local function log_action(log_message)
	local text = log_message
	if type(text) ~= "string" and type(text) ~= "number" then
		text = dump(text)
	end
	minetest.log("action", "["..mod_name.."] "..text)
end

local function log_warning(log_message)
	local text = log_message
	if type(text) ~= "string" and type(text) ~= "number" then
		text = dump(text)
	end
	minetest.log("warning", "["..mod_name.."] "..text)
end

local function get_player_name(player_or_name)
	local player_name = ""
	if type(player_or_name) == "userdata" then
		player_name = player_or_name:get_player_name()
	elseif type(player_or_name) == "string" then
		player_name = player_or_name:trim()
	end
	return player_name
end

local function get_stats_path(player_name)
	return data_dir..player_name..".lua"
end

local function file_exist(path)
	local result = false
	if type(path) == "string" and path ~= "" then
		local file = io.open(path, "r")
		if file ~= nil then
			file:close()
			result = true
		end
	end
	return result
end

local function save_stats(player_name, stats)
	local stats_path = get_stats_path(player_name)
	local file = io.open(stats_path, "w")
	if file == nil then
		error("Failed to write stats for player '"..player_name.."' to '"..stats_path.."'")
	else
		local data_string = minetest.serialize(stats)
		if data_string == nil then
			error("Failed to serialize stats for player '"..player_name.."': "..dump(stats))
		else
			file:write(data_string)
			file:close()
			log_debug("Saved live stats for "..player_name)
		end
	end
end

local function return_player_stats(player_or_name, create_if_not_existent)
	local result = {}
	local player_name = get_player_name(player_or_name)
	if online_player_stats[player_name] ~= nil then
		result = table.copy(online_player_stats[player_name])
		result.error = "no_error"
	else
		local stats_path = get_stats_path(player_name)
		if file_exist(stats_path) then
			local file = io.open(stats_path, "r")
			if file == nil then
				error("Failed to open file: '"..stats_path.."'")
			else
				local data = minetest.deserialize(file:read("*all"), true)
				if data == nil then
					error("Deserialization error, invalid data, in file: '"..stats_path.."'")
				else
					if remove_unknown_entries then
						for key, _ in pairs(data) do
							if stats_template[key] == nil then
								data[key] = nil
								log_warning("Removed unknown entry '"..key.."' from player stats (player: "..player_name..")")
							end
						end
					end
					result = table.copy(data)
					result.error = "no_error"
				end
			end
		else
			if create_if_not_existent then
				local new_stats = table.copy(stats_template)
				new_stats.player_name = player_name
				new_stats.created = get_timestamp()
				save_stats(player_name, new_stats)
				result = table.copy(new_stats)
				result.error = "no_error"
			else
				result.error = "no stats available"
			end
		end
	end
	return result
end

function player_stats.get_player_stats(player_or_name)
	return table.copy(return_player_stats(player_or_name, false))
end

local function save_all_live_stats()
	local ts_start = minetest.get_us_time()
	for _, stats in pairs(online_player_stats) do
		save_stats(stats.player_name, stats)
	end
	local ts_end = minetest.get_us_time()
	log_debug("Saving all live stats took "..((ts_end - ts_start) / 1000).." ms")
end

local function mod_stat(player_or_name, key, modification)
	local player_name = get_player_name(player_or_name)
	if online_player_stats[player_name] == nil then
		error("mod_stat() got called, but the referenced player data is not loaded. Player name: '"..player_name.."'")
	else
		if type(key) ~= "string" then
			error("mod_stat() got called with an invalid key data type: "..type(key))
		end
		if key:trim() == "" then
			error("mod_stat() got called with an empty key")
		end
		if stats_template[key] == nil then
			error("mod_stat() got called with an unknown key: '"..key.."'")
		end
		if type(modification) ~= "number" then
			error("mod_stat() got called with an invalid modification data type: "..type(modification))
		end
		local old_value = 0
		if online_player_stats[player_name][key] ~= nil then
			old_value = online_player_stats[player_name][key]
		end
		online_player_stats[player_name][key] = old_value + modification
	end
end

minetest.register_on_joinplayer(function(player, last_login)
	local player_name = get_player_name(player)
	online_player_stats[player_name] = table.copy(return_player_stats(player_name, true))
	online_player_stats[player_name].error = nil
	mod_stat(player_name, "joined", 1)
end)

minetest.register_on_dignode(function(_, _, digger)
	mod_stat(digger, "nodes_dug", 1)
end)

minetest.register_on_placenode(function(_, _, placer, _, _, _)
	mod_stat(placer, "nodes_placed", 1)
end)

minetest.register_on_craft(function(_, player, _, _)
	mod_stat(player, "items_crafted", 1)
	return nil
end)

minetest.register_on_chat_message(function(player_name, _)
	mod_stat(player_name, "chat_messages", 1)
	return false
end)

minetest.register_on_dieplayer(function(player, _)
	mod_stat(player, "died", 1)
end)

minetest.register_on_leaveplayer(function(player, _)
	local player_name = get_player_name(player)
	save_stats(player_name, online_player_stats[player_name])
	online_player_stats[player_name] = nil
end)

local function show_player_stats(player_name, params)
	local target_player_name = params:trim()
	if target_player_name == "" then
		target_player_name = player_name
	end
	local stats = table.copy(return_player_stats(target_player_name, false))
	if stats.error ~= "no_error" then
		return false, "Failed to fetch stats for "..target_player_name..": "..stats.error
	else
		local formspec = {
			"formspec_version[1]",
			"size[6,9]",
			"label[1,1;"..fs_esc(target_player_name.." stats:").."]",
			"label[1,2;"..fs_esc("Registered: "..stats.created).."]",
			"label[1,3;"..fs_esc("Joined: "..stats.joined).."]",
			"label[1,4;"..fs_esc("Nodes dug: "..stats.nodes_dug).."]",
			"label[1,5;"..fs_esc("Nodes placed: "..stats.nodes_placed).."]",
			"label[1,6;"..fs_esc("Items crafted: "..stats.items_crafted).."]",
			"label[1,7;"..fs_esc("Died: "..stats.died).."]",
			"label[1,8;"..fs_esc("Chat messages: "..stats.chat_messages).."]",
		}
		minetest.show_formspec(player_name, formspec_name, table.concat(formspec))
		log_action(player_name.." is viewing player stats for "..target_player_name)
		return true
	end
end

minetest.register_chatcommand("stats", {
	description = "Shows player stats.",
	privs = { interact = true },
	params = "[player_name]",
	func = show_player_stats
})

minetest.register_on_mods_loaded(function()
	if not minetest.mkdir(data_dir) then
		error("Failed to create data_dir directory '"..data_dir.."' !")
	end
end)

local function save_all_live_stats_looper()
	save_all_live_stats()
	minetest.after(save_interval, save_all_live_stats_looper)
end

minetest.after(save_interval, save_all_live_stats_looper)

minetest.register_on_shutdown(function()
	save_all_live_stats()
end)