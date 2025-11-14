local AceAddon = LibStub("AceAddon-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConsole = LibStub("AceConsole-3.0")

CoolLineAddon = AceAddon:NewAddon("CoolLine")
---@type TimelineUI?
local main_ui = nil
local is_debugging = false

local function GetKeysSortedByValue(tbl, sortFunction)
	local keys = {}
	for key in pairs(tbl) do
		table.insert(keys, key)
	end

	table.sort(keys, function(a, b)
		return sortFunction(tbl[a], tbl[b])
	end)

	return keys
end

---@return string
local function HyperlinkName(hyperlink)
	local _, _, name = strfind(hyperlink, '|Hitem:%d+:%d+:%d+:%d+|h[[]([^]]+)[]]|h')
	return name
end

---@return string
local function StringToID(str)
	local replaced = gsub(str, " ", "_")
	return replaced
end

local function GetServerTimeStr()
	local hour, minute = GetGameTime()
	local seconds = date("%S")
	return string.format("%02d:%02d:%s", hour, minute, seconds)
end

---@param msg string
local function PrintDebug(msg)
	if is_debugging then
		DEFAULT_CHAT_FRAME:AddMessage(format("[%s][CoolLine] %s", GetServerTimeStr(), msg))
	end
end

---@class FramePool
---@field name string
---@field _next_frame_id integer
---@field _pool Frame[]
local FramePool = {}

---@param pool_name string?
---@return FramePool
function FramePool:New(pool_name)
	return setmetatable({
		name = pool_name or (StringToID(CoolLineAddon.name) .. "FramePool"),
		_next_frame_id = 1,
		_pool = {},
	}, { __index = self })
end

---@return Frame
---@param parent Frame|nil
function FramePool:Acquire(parent)
	local frame = tremove(self._pool)
	if not frame then
		frame = CreateFrame("Frame", self.name .. "#" .. self._next_frame_id)
		PrintDebug("FramePool: creating new frame #" .. self._next_frame_id)
		self._next_frame_id = self._next_frame_id + 1
	else
		PrintDebug("FramePool: reusing a frame")
	end
	if parent then
		frame:SetParent(parent)
	end
	return frame
end

---@param frame Frame
function FramePool:Recycle(frame)
	if frame then
		-- Clear all textures from the frame to prevent old icons from showing
		for _, region in ipairs({frame:GetRegions()}) do
			if region:GetObjectType() == "Texture" then
				region:SetTexture(nil)
				break
			end
		end
		tinsert(self._pool, frame)
		PrintDebug("FramePool: recycled a frame. Current pool size: " .. getn(self._pool))
	end
end

---@class CooldownAura
---@field frame Frame
---@field name string
---@field end_time number
---@field time_last_update number
---@field _icon Texture
local CooldownAura = {}

---@param frame Frame
---@param name string
---@param size integer
---@param texture string
---@param end_time number
---@param is_spell boolean
---@return CooldownAura
function CooldownAura:New(frame, name, size, texture, end_time, is_spell)
	local inst = setmetatable({
		frame = frame,
		name = name,
		end_time = end_time,
		time_last_update = 0,
		_icon = frame:CreateTexture(nil, 'ARTWORK')
	}, { __index = self })

	frame:SetBackdrop({ bgFile = [[Interface\AddOns\CoolLine\backdrop.tga]] })

	inst._icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	inst._icon:SetPoint('TopLeft', 1, -1)
	inst._icon:SetPoint('BottomRight', -1, 1)

	self.Update(inst, name, size, texture, end_time, is_spell)

	return inst
end

---@param name string
---@param size integer
---@param texture string
---@param end_time number
---@param is_spell boolean
function CooldownAura:Update(name, size, texture, end_time, is_spell)
	self.name = name
	self.end_time = end_time
	self._icon:SetTexture(texture)
	self:SetSize(size)
	self:SetAlpha((end_time - GetTime() > 360) and 0.6 or 1)
	if is_spell then
		self.frame:SetBackdropColor(unpack(COOLINE_THEME.spell_color))
	else
		self.frame:SetBackdropColor(unpack(COOLINE_THEME.no_spell_color))
	end
end

---@param alpha number
function CooldownAura:SetAlpha(alpha)
	self.frame:SetAlpha(alpha)
end

---@param size integer
function CooldownAura:SetSize(size)
	self.frame:SetWidth(size)
	self.frame:SetHeight(size)
end

---@param level integer
function CooldownAura:SetFrameLevel(level)
	self.frame:SetFrameLevel(level)
end

function CooldownAura:Show()
	self.frame:Show()
end

---@return number
function CooldownAura:TimeLeft()
	return self.end_time - GetTime()
end

---@class TimeLabel
---@field label string
---@field pos_on_bar integer
---@field anchor_point FramePoint
---@field _font_string FontString
local TimeLabel = {}

---@param parent Frame
---@param label string
---@param pos_on_bar integer
---@return table|TimeLabel
function TimeLabel:New(parent, label, pos_on_bar)
	local fs = parent:CreateFontString(nil, 'OVERLAY')
	fs:SetFont(COOLINE_THEME.font, COOLINE_THEME.font_size)
	fs:SetTextColor(unpack(COOLINE_THEME.font_color))
	fs:SetText(label)
	fs:SetWidth(COOLINE_THEME.font_size * 3)
	fs:SetHeight(COOLINE_THEME.font_size + 2)
	fs:SetShadowColor(unpack(COOLINE_THEME.bg_color))
	fs:SetShadowOffset(1, -1)
	fs:SetJustifyH('Center')

	return setmetatable({
		label = label,
		pos_on_bar = pos_on_bar,
		anchor_point = "Center",
		_font_string = fs
	}, { __index = self })
end

---@return Region
function TimeLabel:GetRegion()
	return self._font_string
end

---@param is_vertical boolean
---@param is_reversed boolean
function TimeLabel:SetFirstLabelAlignment(is_vertical, is_reversed)
	if is_vertical then
		self._font_string:SetJustifyH("Center")
		if is_reversed then
			self.anchor_point = "Top"
		else
			self.anchor_point = "Bottom"
		end
	else
		if is_reversed then
			self.anchor_point = "Right"
			self._font_string:SetJustifyH("Right")
		else
			self.anchor_point = "Left"
			self._font_string:SetJustifyH("Left")
		end
	end
end

---@param is_vertical boolean
---@param is_reversed boolean
function TimeLabel:SetLastLabelAlignment(is_vertical, is_reversed)
	if is_vertical then
		self._font_string:SetJustifyH("Center")
		if is_reversed then
			self.anchor_point = "Bottom"
		else
			self.anchor_point = "Top"
		end
	else
		if is_reversed then
			self.anchor_point = "Left"
			self._font_string:SetJustifyH("Left")
		else
			self.anchor_point = "Right"
			self._font_string:SetJustifyH("Right")
		end
	end
end

---@alias State {
---  is_vertical: boolean,
---  is_reversed: boolean,
---  is_dragging: boolean,
---  x: integer,
---  y: integer,
---  to_shuffle_level: boolean,
---  time_last_shuffle_level: number,
---  is_active: boolean }

-- 5 segments: 0-1s, 1-3s, 3-10s, 10-30s, 30-120s, 120-360s
---@class TimelineUI
---@field len_segment integer
---@field icon_size integer
---@field state State
---@field _auras table<string, CooldownAura>
---@field _background Texture
---@field _border Frame
---@field _overlay Frame
---@field _time_labels TimeLabel[]
---@field _frame Frame
---@field _frame_pool FramePool
---@field _first_label TimeLabel
---@field _last_label TimeLabel
local TimelineUI = {}

function TimelineUI:New()
	local inst = setmetatable({
		len_segment = COOLINE_THEME.width / 6,
		icon_size = COOLINE_THEME.height + COOLINE_THEME.icon_outset * 2,
		state = {
			is_vertical = false,
			is_reversed = false,
			is_dragging = false,
			x = 0,
			y = -240,
			to_shuffle_level = false,
			time_last_shuffle_level = 0,
			is_active = false,
		},
		_auras = {},
		_frame_pool = FramePool:New()
	}, { __index = TimelineUI })

	return inst
end

function TimelineUI:Enable()
	local frame = CreateFrame('Button', nil, UIParent)
	self._frame = frame
	local state = self.state

	self.state.is_vertical = COOLINE_THEME.vertical
	self.state.is_reversed = COOLINE_THEME.reverse

	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetPoint('Center', state.x, state.y)

	-- Background texture
	local background = frame:CreateTexture(nil, 'ARTWORK')
	background:SetTexture(COOLINE_THEME.statusbar)
	background:SetVertexColor(unpack(COOLINE_THEME.bg_color))
	background:SetAllPoints(frame)
	self._background = background

	-- Border frame
	local border = CreateFrame('Frame', nil, frame)
	border:SetPoint('TopLeft', -COOLINE_THEME.border_inset, COOLINE_THEME.border_inset)
	border:SetPoint('BottomRight', COOLINE_THEME.border_inset, -COOLINE_THEME.border_inset)
	border:SetBackdrop({
		edgeFile = COOLINE_THEME.border,
		edgeSize = COOLINE_THEME.border_size,
	})
	border:SetBackdropBorderColor(unpack(COOLINE_THEME.border_color))
	self._border = border

	-- Overlay frame
	local overlay = CreateFrame('Frame', nil, border)
	overlay:SetFrameLevel(24) -- TODO this gets changed automatically later, to 9, find out why
	self._overlay = overlay

	-- Dragging
	local function OnDragStop()
		frame:StopMovingOrSizing()
		local x, y = frame:GetCenter()
		local ux, uy = UIParent:GetCenter()
		state.x, state.y = floor(x - ux + 0.5), floor(y - uy + 0.5)
		state.is_dragging = false
	end
	frame:RegisterForDrag('LeftButton')
	frame:SetScript('OnDragStart', function()
		state.is_dragging = true
		frame:StartMoving()
	end)
	frame:SetScript('OnDragStop', function()
		OnDragStop()
	end)
	frame:SetScript('OnUpdate', function()
		frame:EnableMouse(IsAltKeyDown())
		if not IsAltKeyDown() and state.is_dragging then
			OnDragStop()
		end
		self:Update(false)
	end)

	-- 7 Text labels for time markers
	local first_label = TimeLabel:New(overlay, '0', 0)
	local last_label = TimeLabel:New(overlay, '6m', self.len_segment * 6)
	first_label:SetFirstLabelAlignment(self.state.is_vertical, self.state.is_reversed)
	last_label:SetLastLabelAlignment(self.state.is_vertical, self.state.is_reversed)
	self._first_label = first_label
	self._last_label = last_label
	self._time_labels = {
		first_label,
		TimeLabel:New(overlay, '1', self.len_segment),
		TimeLabel:New(overlay, '3', self.len_segment * 2),
		TimeLabel:New(overlay, '10', self.len_segment * 3),
		TimeLabel:New(overlay, '30', self.len_segment * 4),
		TimeLabel:New(overlay, '2m', self.len_segment * 5),
		last_label
	}
	self:UpdateTimeLabelPositions()

	-- Events
	frame:RegisterEvent('VARIABLES_LOADED')
	frame:RegisterEvent('SPELL_UPDATE_COOLDOWN')
	frame:RegisterEvent('BAG_UPDATE_COOLDOWN')
	frame:SetScript('OnEvent', function()
		if event == 'VARIABLES_LOADED' or event == 'BAG_UPDATE_COOLDOWN' or event == 'SPELL_UPDATE_COOLDOWN' then
			self:FindAllCooldown()
			self:Update(true)
		end
	end)

	self:SetAlignment(self.state.is_vertical, self.state.is_reversed, true)
	self:FindAllCooldown()
	frame:Show()
end

function TimelineUI:UpdateTimeLabelPositions()
	for _, label in ipairs(self._time_labels) do
		local region = label:GetRegion()
		region:ClearAllPoints()
		self:PlaceOnBar(region, label.pos_on_bar, label.anchor_point)
	end
end

---@param is_vertical boolean
---@param is_reversed boolean
---@param forced boolean|nil
function TimelineUI:SetAlignment(is_vertical, is_reversed, forced)
	local changed = self.state.is_vertical ~= is_vertical or self.state.is_reversed ~= is_reversed
	if changed or forced then
		self.state.is_vertical = is_vertical
		self.state.is_reversed = is_reversed

		self._first_label:SetFirstLabelAlignment(is_vertical, is_reversed)
		self._last_label:SetLastLabelAlignment(is_vertical, is_reversed)
		self:UpdateTimeLabelPositions()

		if is_vertical then
			self._frame:SetWidth(COOLINE_THEME.height)
			self._frame:SetHeight(COOLINE_THEME.width)
			self._background:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
		else
			self._frame:SetWidth(COOLINE_THEME.width)
			self._frame:SetHeight(COOLINE_THEME.height)
			self._background:SetTexCoord(0, 1, 0, 1)
		end

		self:Update(true)
	end
end

---@param forced boolean
function TimelineUI:Update(forced)
	local state = self.state
	local now = GetTime()

	local to_shuffle_level = false
	-- Shuffles auras' frame levels every 0.4 seconds
	-- only for far-away cooldowns
	if now - state.time_last_shuffle_level > 0.4 then
		to_shuffle_level = true
		state.time_last_shuffle_level = now
	end
	state.to_shuffle_level = to_shuffle_level

	-- Aura moves faster as it approaches expiration
	-- because each segment has the same length,
	-- so the segment closer to expiration has a shorter time span.
	--
	-- Reduces calls to SetPoint by reducing update frequency for far-away cooldowns.
	state.is_active = false
	for name, aura in pairs(self._auras) do
		local time_left = aura:TimeLeft()
		state.is_active = state.is_active or time_left < 360

		if time_left < -1 then
			-- Keeps the expired and fading aura for 1 second
			state.is_active = true
			self:ClearAura(name)
		elseif time_left < 0 then
			self:UpdateAura(aura, 0, to_shuffle_level)
			-- Adds fading effect after expired
			aura:SetAlpha(max(1 + time_left, 0))
		elseif time_left < 0.3 then
			-- icon_size + icon_size * (0.3 - time_left) / 0.2
			local size = floor(self.icon_size * (0.5 - time_left) * 5)
			aura:SetSize(size)
			self:UpdateAura(aura, self.len_segment * time_left, to_shuffle_level)
		elseif time_left < 1 then
			self:UpdateAura(aura, self.len_segment * time_left, to_shuffle_level)
		elseif time_left < 3 then
			if now - aura.time_last_update > 0.02 or forced then
				self:UpdateAura(aura, self.len_segment * (time_left + 1) * 0.5, to_shuffle_level)
				aura.time_last_update = now
			end
		elseif time_left < 10 then
			local threshold = time_left > 4 and 0.05 or 0.02
			if now - aura.time_last_update > threshold or forced then
				-- 2 + (time_left - 3) / 7
				self:UpdateAura(aura, self.len_segment * (time_left + 11) * 0.14286, to_shuffle_level)
				aura.time_last_update = now
			end
		elseif time_left < 30 then
			if now - aura.time_last_update > 0.06 or forced then
				-- 3 + (time_left - 10) / 20
				self:UpdateAura(aura, self.len_segment * (time_left + 50) * 0.05, to_shuffle_level)
				aura.time_last_update = now
			end
		elseif time_left < 120 then
			if now - aura.time_last_update > 0.18 or forced then
				-- 4 + (time_left - 30) / 90
				self:UpdateAura(aura, self.len_segment * (time_left + 330) * 0.011111, to_shuffle_level)
				aura.time_last_update = now
			end
		elseif time_left < 360 then
			if now - aura.time_last_update > 1.2 or forced then
				-- 5 + (time_left - 120) / 240
				self:UpdateAura(aura, self.len_segment * (time_left + 1080) * 0.0041667, to_shuffle_level)
				aura:SetAlpha(COOLINE_THEME.active_alpha)
				aura.time_last_update = now
			end
		else
			self:UpdateAura(aura, 6 * self.len_segment, to_shuffle_level)
		end
	end
	self._frame:SetAlpha(state.is_active and COOLINE_THEME.active_alpha or COOLINE_THEME.inactive_alpha)
end

---@param name string
---@param texture string
---@param start_time number
---@param duration number
---@param is_spell boolean
---@return CooldownAura|nil
function TimelineUI:NewAura(name, texture, start_time, duration, is_spell)
	-- Filters with the blacklist
	for _, ignored_name in COOLINE_IGNORE_LIST do
		if strupper(name) == strupper(ignored_name) then
			return
		end
	end

	local end_time = start_time + duration

	-- Filters out duplicates with the same end_time
	-- assuming human can not press two buttons at exactly the same time?
	local auras = self._auras
	for _, aura in pairs(auras) do
		if aura.end_time == end_time then
			return
		end
	end

	local aura = auras[name]
	if aura then
		PrintDebug("TimelineUI: updating an aura with the same name " .. name)
		aura:Update(name, self.icon_size, texture, end_time, is_spell)
	else
		PrintDebug("TimelineUI: creating a new aura " .. name)
		aura = CooldownAura:New(
			self._frame_pool:Acquire(self._border),
			name,
			self.icon_size,
			texture,
			end_time,
			is_spell
		)
		auras[name] = aura
	end
	return aura
end

---@param aura CooldownAura
---@param position number
---@param to_shuffle_level boolean
function TimelineUI:UpdateAura(aura, position, to_shuffle_level)
	if aura.end_time - GetTime() < COOLINE_THEME.threshold then
		-- Expiring-soon cooldowns: sort by end_time in descending order
		-- so the most urgent ones appear on top
		local sorted = GetKeysSortedByValue(self._auras, function(a, b) return a.end_time > b.end_time end)
		for i, k in ipairs(sorted) do
			if aura.name == k then
				aura:SetFrameLevel(i + 2)
			end
		end
	else
		-- Far-away cooldowns: they may stack with each other,
		-- so randomize frame level to create visual variety
		if to_shuffle_level then
			aura:SetFrameLevel(random(1, 5) + 2)
		end
	end

	self:PlaceOnBar(aura.frame, position)
end

function TimelineUI:ClearAura(name)
	-- Does not delete the frame, just hides and puts it into the pool
	local auras = self._auras
	if auras[name] then
		auras[name].frame:Hide()
		self._frame_pool:Recycle(auras[name].frame)
		auras[name] = nil
	end
end

function TimelineUI:FindAllCooldown()
	-- Finds cooldowns on items in bags
	for bag_id = 0, 4 do
		local bag = GetBagName(bag_id)
		if bag then
			for slot = 1, GetContainerNumSlots(bag_id) do
				local start_time, duration, enabled = GetContainerItemCooldown(bag_id, slot)
				if enabled == 1 then
					local name = HyperlinkName(GetContainerItemLink(bag_id, slot))
					if duration > 3 and duration < 3601 then
						local aura = self:NewAura(
							name,
							GetContainerItemInfo(bag_id, slot),
							start_time,
							duration,
							false
						)
						if aura then aura:Show() end
					elseif duration == 0 then
						self:ClearAura(name)
					end
				end
			end
		end
	end

	-- Finds cooldowns on equipped items
	for slot = 0, 19 do
		local start_time, duration, enabled = GetInventoryItemCooldown('player', slot)
		local item_texture = GetInventoryItemTexture('player', slot)
		if item_texture and enabled == 1 then
			local name = HyperlinkName(GetInventoryItemLink('player', slot))
			if duration > 3 and duration < 3601 then
				local aura = self:NewAura(
					name,
					item_texture,
					start_time,
					duration,
					false
				)
				if aura then aura:Show() end
			elseif duration == 0 then
				self:ClearAura(name)
			end
		end
	end

	-- Finds cooldowns on spells
	local _, _, offset, spell_count = GetSpellTabInfo(GetNumSpellTabs())
	local total_spells = offset + spell_count
	for id = 1, total_spells do
		local start_time, duration, enabled = GetSpellCooldown(id, BOOKTYPE_SPELL)
		local spell_texture = GetSpellTexture(id, BOOKTYPE_SPELL)
		local name = GetSpellName(id, BOOKTYPE_SPELL)
		if name and spell_texture and enabled == 1 and duration > 2.5 then
			local aura = self:NewAura(
				name,
				spell_texture,
				start_time,
				duration,
				true
			)
			if aura then aura:Show() end
		elseif duration == 0 then
			self:ClearAura(name)
		end
	end
end

---Places a label or aura frame on the timeline bar
---@param region Region
---@param offset number
---@param anchor_point FramePoint|nil
function TimelineUI:PlaceOnBar(region, offset, anchor_point)
	if not anchor_point then
		anchor_point = 'Center'
	end

	if self.state.is_vertical then
		if self.state.is_reversed then
			region:SetPoint(anchor_point, self._frame, 'Top', 0, -offset)
		else
			region:SetPoint(anchor_point, self._frame, 'Bottom', 0, offset)
		end
	else
		if self.state.is_reversed then
			region:SetPoint(anchor_point, self._frame, 'Right', -offset, 0)
		else
			region:SetPoint(anchor_point, self._frame, 'Left', offset, 0)
		end
	end
end

-- Configuration
local function SetVertical(info, value)
	if main_ui then
		main_ui:SetAlignment(value, main_ui.state.is_reversed)
	end
end

---@return boolean
local function GetVertical(info)
	if main_ui then
		return main_ui.state.is_vertical
	end
	return false
end

local function SetReversed(info, value)
	if main_ui then
		main_ui:SetAlignment(main_ui.state.is_vertical, value)
	end
end

---@return boolean
local function GetReversed(info)
	if main_ui then
		return main_ui.state.is_reversed
	end
	return false
end

local options = {
	name = "CoolLine",
	type = "group",
	args = {
		vertical = {
			name = "Vertical?",
			desc = "Makes the timeline vertical or not",
			type = "toggle",
			get = GetVertical,
			set = SetVertical,
		},
		reversed = {
			name = "Reversed?",
			desc = "Makes the timeline reversed or not",
			type = "toggle",
			get = GetReversed,
			set = SetReversed,
		},
		debugging = {
			name = "Debugging?",
			desc = "Enables debugging mode",
			type = "toggle",
			get = function() return is_debugging end,
			set = function(info, value) is_debugging = value end,
		}
	}
}

function CoolLineAddon:OnInitialize()
	main_ui = TimelineUI:New()
	AceConfig.RegisterOptionsTable(self, "CoolLine", options)

	-- Register the slash command to open the config GUI
	AceConsole:RegisterChatCommand("coolline", function()
		AceConfigDialog:Open("CoolLine")
	end)
end

function CoolLineAddon:OnEnable()
	if main_ui then
		main_ui:Enable()
	end
	DEFAULT_CHAT_FRAME:AddMessage(COOLINE_LOADED_MESSAGE);
end
