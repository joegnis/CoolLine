local function get_keys_sorted_by_value(tbl, sortFunction)
	local keys = {}
	for key in pairs(tbl) do
		table.insert(keys, key)
	end

	table.sort(keys, function(a, b)
		return sortFunction(tbl[a], tbl[b])
	end)

	return keys
end

local function hyperlink_name(hyperlink)
	local _, _, name = strfind(hyperlink, '|Hitem:%d+:%d+:%d+:%d+|h[[]([^]]+)[]]|h')
	return name
end

---@class CooldownAura
---@field frame Frame
---@field icon Texture
---@field end_time number
local CooldownAura = {}

---@param parent Frame
function CooldownAura:new(parent)
	local inst = setmetatable({}, { __index = CooldownAura })

	local frame = CreateFrame('Frame', nil, parent)
	frame:SetBackdrop({ bgFile = [[Interface\AddOns\cooline\backdrop.tga]] })
	local icon = frame:CreateTexture(nil, 'ARTWORK')
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetPoint('TopLeft', 1, -1)
	icon:SetPoint('BottomRight', -1, 1)

	inst.frame = frame
	inst.icon = icon
	inst.end_time = 0

	return inst
end

---@alias State {
---  is_dragging: boolean,
---  x: integer,
---  y: integer,
---  update_threshold: number,
---  last_update: number,
---  to_re_level: boolean,
---  last_re_level: number,
---  is_active: boolean }

---@class TimelineUI
---@field frame Frame
---@field background Texture
---@field border Frame
---@field overlay Frame
---@field section integer
---@field icon_size integer
---@field auras table<string, CooldownAura>
---@field state State
---@field aura_frame_pool Frame[]
local TimelineUI = {}

---@return TimelineUI
function TimelineUI:new()
	local inst = {}
	setmetatable(inst, { __index = TimelineUI })

	inst.section = COOLINE_THEME.width / 6
	inst.icon_size = COOLINE_THEME.height + COOLINE_THEME.icon_outset * 2
	inst.auras = {}
	inst.aura_frame_pool = {}
	inst.state = {
		is_dragging = false,
		x = 0,
		y = -240,
		-- to dynamically adjust update frequency based on remaining cooldown
		-- TODO: separate threshold for each aura
		update_threshold = 0.0,
		last_update = GetTime(),
		to_re_level = false,
		last_re_level = GetTime(),
		is_active = false,
	}

	return inst
end

function TimelineUI:enable()
	local frame = CreateFrame('Button', nil, UIParent)
	self.frame = frame
	local state = self.state

	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	if COOLINE_THEME.vertical then
		frame:SetWidth(COOLINE_THEME.height)
		frame:SetHeight(COOLINE_THEME.width)
	else
		frame:SetWidth(COOLINE_THEME.width)
		frame:SetHeight(COOLINE_THEME.height)
	end
	frame:SetPoint('Center', state.x, state.y)

	-- Background texture
	local background = frame:CreateTexture(nil, 'ARTWORK')
	background:SetTexture(COOLINE_THEME.statusbar)
	background:SetVertexColor(unpack(COOLINE_THEME.bg_color))
	background:SetAllPoints(frame)
	if COOLINE_THEME.vertical then
		background:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
	else
		background:SetTexCoord(0, 1, 0, 1)
	end
	self.background = background

	-- Border frame
	local border = CreateFrame('Frame', nil, frame)
	border:SetPoint('TopLeft', -COOLINE_THEME.border_inset, COOLINE_THEME.border_inset)
	border:SetPoint('BottomRight', COOLINE_THEME.border_inset, -COOLINE_THEME.border_inset)
	border:SetBackdrop({
		edgeFile = COOLINE_THEME.border,
		edgeSize = COOLINE_THEME.border_size,
	})
	border:SetBackdropBorderColor(unpack(COOLINE_THEME.border_color))
	self.border = border

	-- Overlay frame
	local overlay = CreateFrame('Frame', nil, border)
	overlay:SetFrameLevel(24) -- TODO this gets changed automatically later, to 9, find out why
	self.overlay = overlay

	-- Dragging
	local function on_drag_stop()
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
		on_drag_stop()
	end)
	frame:SetScript('OnUpdate', function()
		frame:EnableMouse(IsAltKeyDown())
		if not IsAltKeyDown() and state.is_dragging then
			on_drag_stop()
		end
		self:on_update(false)
	end)

	-- Text labels for time markers
	self:label('0', 0, 'Left')
	self:label('1', self.section)
	self:label('3', self.section * 2)
	self:label('10', self.section * 3)
	self:label('30', self.section * 4)
	self:label('2m', self.section * 5)
	self:label('6m', self.section * 6, 'Right')

	-- Events
	frame:RegisterEvent('VARIABLES_LOADED')
	frame:RegisterEvent('SPELL_UPDATE_COOLDOWN')
	frame:RegisterEvent('BAG_UPDATE_COOLDOWN')
	frame:SetScript('OnEvent', function()
		if event == 'VARIABLES_LOADED' or event == 'BAG_UPDATE_COOLDOWN' or event == 'SPELL_UPDATE_COOLDOWN' then
			self:detect_cooldowns()
			self:on_update(true)
		end
	end)

	self:detect_cooldowns()
	frame:Show()
end

---@param is_force boolean
function TimelineUI:on_update(is_force)
	local state = self.state

	if GetTime() - state.last_update < state.update_threshold and not is_force then return end
	state.last_update = GetTime()

	state.to_re_level = false
	if GetTime() - state.last_re_level > 0.4 then
		state.to_re_level, state.last_re_level = true, GetTime()
	end
	local to_re_level = state.to_re_level

	state.is_active, state.update_threshold = false, 1.5
	for name, aura in pairs(self.auras) do
		local aura_frame = aura.frame
		local time_left = aura.end_time - GetTime()
		state.is_active = state.is_active or time_left < 360

		if time_left < -1 then
			state.update_threshold = min(state.update_threshold, 0.2)
			state.is_active = true
			self:clear_cooldown(name)
		elseif time_left < 0 then
			self:update_cooldown(name, aura, 0, to_re_level)
			aura_frame:SetAlpha(1 + time_left) -- fades
		elseif time_left < 0.3 then
			state.update_threshold = min(state.update_threshold, 0)
			local size = self.icon_size * (0.5 - time_left) *
				5 -- icon_size + icon_size * (0.3 - time_left) / 0.2
			aura_frame:SetWidth(size)
			aura_frame:SetHeight(size)
			self:update_cooldown(name, aura, self.section * time_left, to_re_level)
		elseif time_left < 1 then
			state.update_threshold = min(state.update_threshold, 0)
			self:update_cooldown(name, aura, self.section * time_left, to_re_level)
		elseif time_left < 3 then
			state.update_threshold = min(state.update_threshold, 0.02)
			self:update_cooldown(name, aura, self.section * (time_left + 1) * 0.5, to_re_level)
		elseif time_left < 10 then
			state.update_threshold = min(state.update_threshold, time_left > 4 and 0.05 or 0.02)
			self:update_cooldown(name, aura, self.section * (time_left + 11) * 0.14286,
				to_re_level) -- 2 + (time_left - 3) / 7
		elseif time_left < 30 then
			state.update_threshold = min(state.update_threshold, 0.06)
			self:update_cooldown(name, aura, self.section * (time_left + 50) * 0.05, to_re_level) -- 3 + (time_left - 10) / 20
		elseif time_left < 120 then
			state.update_threshold = min(state.update_threshold, 0.18)
			self:update_cooldown(name, aura, self.section * (time_left + 330) * 0.011111, to_re_level) -- 4 + (time_left - 30) / 90
		elseif time_left < 360 then
			state.update_threshold = min(state.update_threshold, 1.2)
			self:update_cooldown(name, aura, self.section * (time_left + 1080) * 0.0041667, to_re_level) -- 5 + (time_left - 120) / 240
			aura_frame:SetAlpha(COOLINE_THEME.active_alpha)
		else
			self:update_cooldown(name, aura, 6 * self.section, to_re_level)
		end
	end
	self.frame:SetAlpha(state.is_active and COOLINE_THEME.active_alpha or COOLINE_THEME.inactive_alpha)
end

function TimelineUI:start_cooldown(name, texture, start_time, duration, is_spell)
	for _, ignored_name in COOLINE_IGNORE_LIST do
		if strupper(name) == strupper(ignored_name) then
			return
		end
	end

	local end_time = start_time + duration

	local auras = self.auras
	for _, aura in pairs(auras) do
		if aura.end_time == end_time then
			return
		end
	end

	auras[name] = auras[name] or tremove(self.aura_frame_pool) or CooldownAura:new(self.border)
	local aura = auras[name]
	aura.frame:SetWidth(self.icon_size)
	aura.frame:SetHeight(self.icon_size)
	aura.icon:SetTexture(texture)
	if is_spell then
		aura.frame:SetBackdropColor(unpack(COOLINE_THEME.spell_color))
	else
		aura.frame:SetBackdropColor(unpack(COOLINE_THEME.no_spell_color))
	end
	aura.frame:SetAlpha((end_time - GetTime() > 360) and 0.6 or 1)
	aura.end_time = end_time
	aura.frame:Show()
end

---@param name string
---@param aura CooldownAura
---@param position number
---@param to_re_level boolean
function TimelineUI:update_cooldown(name, aura, position, to_re_level)
	if aura.end_time - GetTime() < COOLINE_THEME.threshold then
		local sorted = get_keys_sorted_by_value(self.auras, function(a, b) return a.end_time > b.end_time end)
		for i, k in ipairs(sorted) do
			if name == k then
				aura.frame:SetFrameLevel(i + 2)
			end
		end
	else
		if to_re_level then
			aura.frame:SetFrameLevel(random(1, 5) + 2)
		end
	end

	self:place(aura.frame, position)
end

function TimelineUI:clear_cooldown(name)
	local auras = self.auras
	if auras[name] then
		auras[name].frame:Hide()
		tinsert(self.aura_frame_pool, auras[name])
		auras[name] = nil
	end
end

function TimelineUI:detect_cooldowns()
	-- Finds cooldowns on items in bags
	for bag_id = 0, 4 do
		local bag = GetBagName(bag_id)
		if bag then
			for slot = 1, GetContainerNumSlots(bag_id) do
				local start_time, duration, enabled = GetContainerItemCooldown(bag_id, slot)
				if enabled == 1 then
					local name = hyperlink_name(GetContainerItemLink(bag_id, slot))
					if duration > 3 and duration < 3601 then
						self:start_cooldown(
							name,
							GetContainerItemInfo(bag_id, slot),
							start_time,
							duration,
							false
						)
					elseif duration == 0 then
						self:clear_cooldown(name)
					end
				end
			end
		end
	end

	-- Finds cooldowns on equipped items
	for slot = 0, 19 do
		local start_time, duration, enabled = GetInventoryItemCooldown('player', slot)
		if enabled == 1 then
			local name = hyperlink_name(GetInventoryItemLink('player', slot))
			if duration > 3 and duration < 3601 then
				self:start_cooldown(
					name,
					GetInventoryItemTexture('player', slot),
					start_time,
					duration,
					false
				)
			elseif duration == 0 then
				self:clear_cooldown(name)
			end
		end
	end

	-- Finds cooldowns on spells
	local _, _, offset, spell_count = GetSpellTabInfo(GetNumSpellTabs())
	local total_spells = offset + spell_count
	for id = 1, total_spells do
		local start_time, duration, enabled = GetSpellCooldown(id, BOOKTYPE_SPELL)
		local name = GetSpellName(id, BOOKTYPE_SPELL)
		if enabled == 1 and duration > 2.5 then
			self:start_cooldown(
				name,
				GetSpellTexture(id, BOOKTYPE_SPELL),
				start_time,
				duration,
				true
			)
		elseif duration == 0 then
			self:clear_cooldown(name)
		end
	end
end

---@param text string
---@param offset integer
---@param point FramePoint|nil
---@return FontString
function TimelineUI:label(text, offset, point)
	-- Create a font string as a child of overlay
	local fs = self.overlay:CreateFontString(nil, 'OVERLAY')
	fs:SetFont(COOLINE_THEME.font, COOLINE_THEME.font_size)
	fs:SetTextColor(unpack(COOLINE_THEME.font_color))
	fs:SetText(text)
	fs:SetWidth(COOLINE_THEME.font_size * 3)
	fs:SetHeight(COOLINE_THEME.font_size + 2)
	fs:SetShadowColor(unpack(COOLINE_THEME.bg_color))
	fs:SetShadowOffset(1, -1)
	if point then
		fs:ClearAllPoints()
		if COOLINE_THEME.vertical then
			fs:SetJustifyH('Center')
			if COOLINE_THEME.reverse then
				point = (point == 'Left' and 'Top') or 'Bottom'
			else
				point = (point == 'Left' and 'Bottom') or 'Top'
			end
		else
			if COOLINE_THEME.reverse then
				point = (point == 'Left' and 'Right') or 'Left'
				offset = offset + ((point == 'Left' and 1) or -1)
			else
				offset = offset + ((point == 'Left' and 1) or -1)
			end
			fs:SetJustifyH(point)
		end
	else
		fs:SetJustifyH('Center')
	end
	self:place(fs, offset, point)
	return fs
end

---@param frame Frame|FontString
---@param offset number
---@param point FramePoint|nil
function TimelineUI:place(frame, offset, point)
	if COOLINE_THEME.vertical then
		if COOLINE_THEME.reverse then
			frame:SetPoint(point or 'Center', self.frame, 'Top', 0, -offset)
		else
			frame:SetPoint(point or 'Center', self.frame, 'Bottom', 0, offset)
		end
	else
		if COOLINE_THEME.reverse then
			frame:SetPoint(point or 'Center', self.frame, 'Right', -offset, 0)
		else
			frame:SetPoint(point or 'Center', self.frame, 'Left', offset, 0)
		end
	end
end

CoolLineAddon = LibStub("AceAddon-3.0"):NewAddon("CoolLine")

---@type TimelineUI?
local main_ui = nil

function CoolLineAddon:OnInitialize()
	main_ui = TimelineUI:new()
	DEFAULT_CHAT_FRAME:AddMessage('|c00ffff00' .. COOLINE_LOADED_MESSAGE .. '|r');
end

function CoolLineAddon:OnEnable()
	if main_ui then
		main_ui:enable()
	end
end
