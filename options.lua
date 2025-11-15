local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConsole = LibStub("AceConsole-3.0")
local AceDB = LibStub("AceDB-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")

local Addon = LibStub("AceAddon-3.0"):GetAddon("CoolLine")

---Splits a string by a separator
---@param str string
---@param pat string separator pattern
---@return string[]
local function SplitString(str, pat)
	local t = {}
	-- Escape every special pattern character
	pat = string.gsub(pat, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
	local fpat = "(.-)" .. pat
	local last_end = 1
	local s, e, cap = string.find(str, fpat, 1)
	while s do
		if s ~= 1 or cap ~= "" then
			table.insert(t, cap)
		end
		last_end = e + 1
		s, e, cap = string.find(str, fpat, last_end)
	end
	if last_end <= string.len(str) then
		cap = string.sub(str, last_end)
		table.insert(t, cap)
	end
	return t
end

---@param table_ table
---@param path string a dot-separated path string to a key
---@return any # The value at the end of the path, or nil if the path doesn't exist
local function GetTableValueByPath(table_, path)
	local cur_table = table_
	local path_list = SplitString(path, ".")

	for _, key in ipairs(path_list) do
		if cur_table == nil or type(cur_table) ~= "table" then
			return nil
		end

		cur_table = cur_table[key]
	end

	return cur_table
end

---@param table_ table
---@param path string a dot-separated path string to a key
---@param value any
---@return boolean
local function SetTableValueByPath(table_, path, value)
	local cur_table = table_
	local path_list = SplitString(path, ".")

	-- Iterate until the second last key
	for i = 1, table.getn(path_list) - 1 do
		local key = path_list[i]
		if cur_table[key] == nil or type(cur_table[key]) ~= "table" then
			-- Can't iterate through a non-table value
			-- Does not create intermediate tables
			return false
		end
		cur_table = cur_table[key]
	end

	local last_key = path_list[table.getn(path_list)]
	cur_table[last_key] = value

	return true
end

---Generates getter and setter function for an entry in config db
---@generic T
---@param store_path string a dot-separated path to the db entry
---@param func_on_set? fun(new_value: T, old_value: T, ui: TimelineUI, config: table): nil
---@return fun(): T getter_func
---@return fun(new_value: T): nil setter_func
function Addon:GenConfigGetterSetter(store_path, func_on_set)
	local function getter_func()
		if self.config_store then
			return GetTableValueByPath(self.config_store, store_path)
		end
	end

	local function setter_func(new_value)
		if self.main_ui and self.config_store then
			local old_value = GetTableValueByPath(self.config_store, store_path)
			if func_on_set then
				func_on_set(new_value, old_value, self.main_ui, self.config_store)
			end
			SetTableValueByPath(self.config_store, store_path, new_value)
		end
	end

	return getter_func, setter_func
end

Addon.GetConfigVertical, Addon.SetConfigVertical = Addon:GenConfigGetterSetter(
	"profile.general.vertical",
	function(new_value, old_value, ui, config)
		if new_value ~= old_value then
			ui:UpdateVertical(new_value)
		end
	end
)

Addon.GetConfigReversed, Addon.SetConfigReversed = Addon:GenConfigGetterSetter(
	"profile.general.reversed",
	function(new_value, old_value, ui, config)
		if new_value ~= old_value then
			ui:UpdateReversed(new_value)
		end
	end
)

Addon.GetConfigTimelineXOffset, Addon.SetConfigTimelineXOffset = Addon:GenConfigGetterSetter(
	"profile.general.timeline_x_offset",
	function(new_value, old_value, ui, config)
		if new_value ~= old_value then
			ui:UpdateXOffset(new_value)
		end
	end
)

Addon.GetConfigTimelineYOffset, Addon.SetConfigTimelineYOffset = Addon:GenConfigGetterSetter(
	"profile.general.timeline_y_offset",
	function(new_value, old_value, ui, config)
		if new_value ~= old_value then
			ui:UpdateYOffset(new_value)
		end
	end
)

Addon.GetConfigAlphaActive, Addon.SetConfigAlphaActive = Addon:GenConfigGetterSetter(
	"profile.general.alpha_active",
	function(new_value, old_value, ui, config)
		if new_value ~= old_value then
			ui:UpdateAlphaActive(new_value)
		end
	end
)

Addon.GetConfigAlphaInactive, Addon.SetConfigAlphaInactive = Addon:GenConfigGetterSetter(
	"profile.general.alpha_inactive",
	function(new_value, old_value, ui, config)
		if new_value ~= old_value then
			ui:UpdateAlphaInactive(new_value)
		end
	end
)
local options = {
	name = "CoolLine",
	type = "group",
	args = {
		general = {
			name = "General",
			type = "group",
			order = 1,
			args = {
				vertical = {
					name = "Vertical?",
					desc = "Makes the timeline vertical or not",
					type = "toggle",
					order = 1,
					get = function(info) return Addon.GetConfigVertical() end,
					set = function(info, value) Addon.SetConfigVertical(value) end,
				},
				reversed = {
					name = "Reversed?",
					desc = "Makes the timeline reversed or not",
					type = "toggle",
					order = 2,
					get = function(info) return Addon.GetConfigReversed() end,
					set = function(info, value) Addon.SetConfigReversed(value) end,
				},
				timeline_x_offset = {
					name = "Timeline X Offset",
					desc = "Offset of the timeline on the X axis",
					type = "range",
					min = -2000,
					max = 2000,
					softMin = -1000,
					softMax = 1000,
					step = 1,
					order = 3,
					get = function(info) return Addon.GetConfigTimelineXOffset() end,
					set = function(info, value) Addon.SetConfigTimelineXOffset(value) end,
				},
				timeline_y_offset = {
					name = "Timeline Y Offset",
					desc = "Offset of the timeline on the Y axis",
					type = "range",
					min = -2000,
					max = 2000,
					softMin = -1000,
					softMax = 1000,
					step = 1,
					order = 4,
					get = function(info) return Addon.GetConfigTimelineYOffset() end,
					set = function(info, value) Addon.SetConfigTimelineYOffset(value) end,
				},
				alpha_active = {
					name = "Alpha when active",
					desc = "Alpha of the timeline when there is any active cooldown.",
					type = "range",
					min = 0.0,
					max = 1.0,
					step = 0.05,
                    order = 5,
                    get = function(info) return Addon.GetConfigAlphaActive() end,
					set = function(info, value) Addon.SetConfigAlphaActive(value) end,
				},
				alpha_inactive = {
					name = "Alpha when inactive",
					desc = "Alpha of the timeline when there are no active cooldowns.\nSet to 0 to hide.",
					type = "range",
					min = 0.0,
					max = 1.0,
					step = 0.05,
					order = 6,
					get = function(info) return Addon.GetConfigAlphaInactive() end,
					set = function(info, value) Addon.SetConfigAlphaInactive(value) end,
				},
				debugging = {
					name = "Debugging?",
					desc = "Enables debugging mode",
					type = "toggle",
					order = 10,
					get = function(info) return Addon.debugging end,
					set = function(info, value) Addon.debugging = value end,
				}
			}
		}
	}
}

local defaults = {
	profile = {
		general = {
			vertical = false,
			reversed = false,
			timeline_x_offset = 0,
			timeline_y_offset = -240,
			alpha_active = 1.0,
			alpha_inactive = 0.5,
			debugging = false
		}
	}
}

function Addon:SetupOptions()
	local config_store = AceDB:New("CoolLineDB", defaults)
    self.config_store = config_store
	options.args.profile = AceDBOptions:GetOptionsTable(config_store)
	options.args.profile.order = 2

	AceConfig.RegisterOptionsTable(self, "CoolLine", options)

	-- Register the slash command to open the config GUI
	AceConsole:RegisterChatCommand("coolline", function()
		AceConfigDialog:Open("CoolLine")
	end)
end
