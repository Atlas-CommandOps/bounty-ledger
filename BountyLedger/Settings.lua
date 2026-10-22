-- Settings window, the minimap button, and an entry in the game's own Options > AddOns list.
local _, ns = ...

local Settings_ = {}
ns.Settings = Settings_
local T = ns.Theme

local DEFAULTS = {
	toasts = true,
	sound = true,
	banner = true,
	nameplates = true,
	minimapHidden = false,
	minimapAngle = 215,
}

local OPTIONS = {
	{ key = "minimap", label = "Show the minimap button" },
	{ key = "toasts", label = "WANTED popups when a bounty is posted" },
	{ key = "banner", label = "BOUNTY CLAIMED banner on your kills" },
	{ key = "sound", label = "Sounds" },
	{ key = "nameplates", label = "Wax seals over wanted players' nameplates" },
}

local window, minimapButton
local checks = {}

local function get(key)
	if key == "minimap" then return not ns.db.settings.minimapHidden end
	return ns.db.settings[key]
end

-- minimap button -------------------------------------------------------------

local function placeMinimapButton()
	local angle = math.rad(ns.db.settings.minimapAngle or DEFAULTS.minimapAngle)
	local radius = (Minimap:GetWidth() / 2) + 6
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function createMinimapButton()
	local b = CreateFrame("Button", "BountyLedgerMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(22, 22)
	bg:SetPoint("TOPLEFT", 5, -4)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(T.SEAL)
	icon:SetSize(22, 22)
	icon:SetPoint("TOPLEFT", 5, -4)
	local ring = b:CreateTexture(nil, "OVERLAY")
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	ring:SetSize(53, 53)
	ring:SetPoint("TOPLEFT")

	b:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then Settings_.Toggle() else ns.UI.Toggle() end
	end)
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			ns.db.settings.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
			placeMinimapButton()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Bounty Ledger", T.BONE[1], T.BONE[2], T.BONE[3])
		local open = 0
		for _, bounty in pairs(ns.state.bounties) do
			if bounty.status == "open" then open = open + 1 end
		end
		GameTooltip:AddLine(open .. " open bounties", T.BRASS[1], T.BRASS[2], T.BRASS[3])
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Left-click: open the board", 1, 1, 1)
		GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
		GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	minimapButton = b
	placeMinimapButton()
end

-- settings window ------------------------------------------------------------

local function checkbox(parent, option, y)
	local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
	c:SetSize(18, 18)
	c:SetPoint("TOPLEFT", 24, y)
	c:SetBackdrop({ bgFile = T.WHITE, edgeFile = T.WHITE, edgeSize = 1 })
	c:SetBackdropColor(0.03, 0.02, 0.02, 0.95)
	c:SetBackdropBorderColor(T.BRASS[1], T.BRASS[2], T.BRASS[3], 0.8)
	c.mark = c:CreateTexture(nil, "ARTWORK")
	c.mark:SetColorTexture(unpack(T.RED))
	c.mark:SetPoint("TOPLEFT", 4, -4)
	c.mark:SetPoint("BOTTOMRIGHT", -4, 4)
	c.label = T.Text(parent, 12)
	c.label:SetPoint("LEFT", c, "RIGHT", 10, 0)
	c.label:SetText(option.label)
	c.Update = function(self) self.mark:SetShown(get(option.key) and true or false) end
	c:SetScript("OnClick", function(self)
		local key = option.key == "minimap" and "minimapHidden" or option.key
		Settings_.Set(key, not ns.db.settings[key])
	end)
	c:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(T.RED)) end)
	c:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(T.BRASS[1], T.BRASS[2], T.BRASS[3], 0.8) end)
	return c
end

local function createWindow()
	window = T.Window("BountyLedgerSettingsFrame", 400, 330, "settings")
	window:SetFrameStrata("DIALOG")
	T.Header(window, "SETTINGS")

	local y = -62
	for _, option in ipairs(OPTIONS) do
		checks[#checks + 1] = checkbox(window, option, y)
		y = y - 32
	end

	local rule = T.Rule(window, 0.4)
	rule:SetPoint("TOPLEFT", 18, y - 2)
	rule:SetPoint("TOPRIGHT", -18, y - 2)

	local reset = T.Button(window, 170, 24, "Reset window positions")
	reset:SetPoint("TOPLEFT", 24, y - 16)
	reset:SetScript("OnClick", function()
		ns.db.settings.positions = nil
		for _, name in ipairs({ "BountyLedgerFrame", "BountyLedgerPostFrame", "BountyLedgerSettingsFrame" }) do
			local f = _G[name]
			if f then
				f:ClearAllPoints()
				f:SetPoint("CENTER")
			end
		end
		ns.Print("Window positions reset.")
	end)
	local board = T.Button(window, 150, 24, "Open the board")
	board:SetPoint("LEFT", reset, "RIGHT", 10, 0)
	board:SetScript("OnClick", function()
		window:Hide()
		ns.UI.Toggle()
	end)

	local foot = T.Text(window, 10, T.DIM)
	foot:SetPoint("BOTTOMLEFT", 24, 16)
	foot:SetText("Bounty Ledger v" .. ns.VERSION .. "   /bounty settings")

	window:SetScript("OnShow", function()
		for _, c in ipairs(checks) do c:Update() end
	end)
end

function Settings_.Open()
	if not ns.db then return end
	if not window then createWindow() end
	window:Show()
end

function Settings_.Toggle()
	if window and window:IsShown() then window:Hide() else Settings_.Open() end
end

local LABELS = { toasts = "WANTED popups", sound = "Sounds", banner = "Claim banner", nameplates = "Nameplate seals" }

function Settings_.Set(key, value)
	ns.db.settings[key] = value
	if key == "minimapHidden" then
		if minimapButton then minimapButton:SetShown(not value) end
		ns.Print(value and "Minimap button hidden. Bring it back with /bounty minimap." or "Minimap button shown.")
	elseif key == "nameplates" then
		ns.UI.UpdatePlates()
	end
	if LABELS[key] then ns.Print(LABELS[key] .. " " .. (value and "on" or "off") .. ".") end
	for _, c in ipairs(checks) do c:Update() end
end

-- Esc > Options > AddOns: a small page that points to the real settings window.
local function registerBlizzardPanel()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
	local panel = CreateFrame("Frame")
	local title = T.Title(panel, 22, "BOUNTY LEDGER")
	title:SetPoint("TOPLEFT", 16, -16)
	local text = T.Text(panel, 12)
	text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	text:SetText("Player-run gold bounties on enemy players.")
	local open = T.Button(panel, 180, 26, "Open Bounty Ledger settings")
	open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -16)
	open:SetScript("OnClick", function()
		if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
		Settings_.Open()
	end)
	pcall(function()
		local category = Settings.RegisterCanvasLayoutCategory(panel, "Bounty Ledger")
		Settings.RegisterAddOnCategory(category)
	end)
end

ns.On("READY", function()
	for k, v in pairs(DEFAULTS) do
		if ns.db.settings[k] == nil then ns.db.settings[k] = v end
	end
	createMinimapButton()
	minimapButton:SetShown(not ns.db.settings.minimapHidden)
	registerBlizzardPanel()
end)
