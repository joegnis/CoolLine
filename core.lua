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

local function HyperlinkName(hyperlink)
	local _, _, name = strfind(hyperlink, '|Hitem:%d+:%d+:%d+:%d+|h[[]([^]]+)[]]|h')
	return name
end

---@class CooldownAura
---@field name string
---@field frame Frame
---@field icon Texture
---@field end_time number
---@field time_last_update number
local CooldownAura = {}

---@param parent Frame
---@param name string
function CooldownAura:New(parent, name)
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
	inst.name = name
	inst.time_last_update = 0

	return inst
end

---@param size integer
---@param texture string
---@param end_time number
---@param is_spell boolean
function CooldownAura:Reset(size, texture, end_time, is_spell)
	self:SetSize(size)
	self.icon:SetTexture(texture)
	self.end_time = end_time
	if is_spell then
		self.frame:SetBackdropColor(unpack(COOLINE_THEME.spell_color))
	else
		self.frame:SetBackdropColor(unpack(COOLINE_THEME.no_spell_color))
	end
	self:SetAlpha((end_time - GetTime() > 360) and 0.6 or 1)
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

---@alias State {
---  is_dragging: boolean,
---  x: integer,
---  y: integer,
---  to_shuffle_level: boolean,
---  time_last_shuffle_level: number,
---  is_active: boolean }

-- 5 segments: 0-1s, 1-3s, 3-10s, 10-30s, 30-120s, 120-360s
---@class TimelineUI
---@field frame Frame
---@field background Texture
---@field border Frame
---@field overlay Frame
---@field len_segment integer
---@field icon_size integer
---@field auras table<string, CooldownAura>
---@field state State
---@field aura_frame_pool Frame[]
local TimelineUI = {}

function TimelineUI:New()
	local inst = {}
	setmetatable(inst, { __index = TimelineUI })

	inst.len_segment = COOLINE_THEME.width / 6
	inst.icon_size = COOLINE_THEME.height + COOLINE_THEME.icon_outset * 2
	inst.auras = {}
	inst.aura_frame_pool = {}
	inst.state = {
		is_dragging = false,
		x = 0,
		y = -240,
		to_shuffle_level = false,
		time_last_shuffle_level = 0,
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

	-- Text labels for time markers
	self:Label('0', 0, 'Left')
	self:Label('1', self.len_segment)
	self:Label('3', self.len_segment * 2)
	self:Label('10', self.len_segment * 3)
	self:Label('30', self.len_segment * 4)
	self:Label('2m', self.len_segment * 5)
	self:Label('6m', self.len_segment * 6, 'Right')

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

	self:FindAllCooldown()
	frame:Show()
end

---@param is_force boolean
function TimelineUI:Update(is_force)
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
	for name, aura in pairs(self.auras) do
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
			if now - aura.time_last_update > 0.02 or is_force then
				self:UpdateAura(aura, self.len_segment * (time_left + 1) * 0.5, to_shuffle_level)
				aura.time_last_update = now
			end
		elseif time_left < 10 then
			local threshold = time_left > 4 and 0.05 or 0.02
			if now - aura.time_last_update > threshold or is_force then
				-- 2 + (time_left - 3) / 7
				self:UpdateAura(aura, self.len_segment * (time_left + 11) * 0.14286, to_shuffle_level)
				aura.time_last_update = now
			end
		elseif time_left < 30 then
			if now - aura.time_last_update > 0.06 or is_force then
				-- 3 + (time_left - 10) / 20
				self:UpdateAura(aura, self.len_segment * (time_left + 50) * 0.05, to_shuffle_level)
				aura.time_last_update = now
			end
		elseif time_left < 120 then
			if now - aura.time_last_update > 0.18 or is_force then
				-- 4 + (time_left - 30) / 90
				self:UpdateAura(aura, self.len_segment * (time_left + 330) * 0.011111, to_shuffle_level)
				aura.time_last_update = now
			end
		elseif time_left < 360 then
			if now - aura.time_last_update > 1.2 or is_force then
				-- 5 + (time_left - 120) / 240
				self:UpdateAura(aura, self.len_segment * (time_left + 1080) * 0.0041667, to_shuffle_level)
				aura:SetAlpha(COOLINE_THEME.active_alpha)
				aura.time_last_update = now
			end
		else
			self:UpdateAura(aura, 6 * self.len_segment, to_shuffle_level)
		end

	end
	self.frame:SetAlpha(state.is_active and COOLINE_THEME.active_alpha or COOLINE_THEME.inactive_alpha)
end

---@param name string
---@param texture string
---@param start_time number
---@param duration number
---@param is_spell boolean
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
	local auras = self.auras
	for _, aura in pairs(auras) do
		if aura.end_time == end_time then
			return
		end
	end

	auras[name] = auras[name] or tremove(self.aura_frame_pool) or CooldownAura:New(self.border, name)
	local aura = auras[name]
	aura:Reset(self.icon_size, texture, end_time, is_spell)
	aura:Show()
end

---@param aura CooldownAura
---@param position number
---@param to_shuffle_level boolean
function TimelineUI:UpdateAura(aura, position, to_shuffle_level)
	if aura.end_time - GetTime() < COOLINE_THEME.threshold then
		-- Expiring-soon cooldowns: sort by end_time in descending order
		-- so the most urgent ones appear on top
		local sorted = GetKeysSortedByValue(self.auras, function(a, b) return a.end_time > b.end_time end)
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
	local auras = self.auras
	if auras[name] then
		auras[name].frame:Hide()
		tinsert(self.aura_frame_pool, auras[name])
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
						self:NewAura(
							name,
							GetContainerItemInfo(bag_id, slot),
							start_time,
							duration,
							false
						)
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
				self:NewAura(
					name,
					item_texture,
					start_time,
					duration,
					false
				)
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
			self:NewAura(
				name,
				spell_texture,
				start_time,
				duration,
				true
			)
		elseif duration == 0 then
			self:ClearAura(name)
		end
	end
end

---@param text string
---@param offset integer
---@param point FramePoint|nil
---@return FontString
function TimelineUI:Label(text, offset, point)
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
	self:PlaceOnBar(fs, offset, point)
	return fs
end

---Places a label or aura frame on the timeline bar
---@param frame Frame|FontString
---@param offset number
---@param point FramePoint|nil
function TimelineUI:PlaceOnBar(frame, offset, point)
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
	main_ui = TimelineUI:New()
	DEFAULT_CHAT_FRAME:AddMessage('|c00ffff00' .. COOLINE_LOADED_MESSAGE .. '|r');
end

function CoolLineAddon:OnEnable()
	if main_ui then
		main_ui:enable()
	end
end
