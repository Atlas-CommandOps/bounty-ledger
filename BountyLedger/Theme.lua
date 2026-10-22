-- Bounty Ledger's own look, taken from its logo: black ink-and-leather panels with brass
-- hairline borders, a blood-red wax seal, ruled ledger lines with a red margin, bone-white
-- text and the gritty Skurri face for titles.
local _, ns = ...

local Theme = {}
ns.Theme = Theme

Theme.TITLE_FONT = "Fonts\\SKURRI.TTF"
Theme.BODY_FONT = "Fonts\\FRIZQT__.TTF"
Theme.SEAL = "Interface\\AddOns\\BountyLedger\\Media\\seal"
Theme.SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
Theme.WHITE = "Interface\\Buttons\\WHITE8X8"

Theme.BONE = { 0.93, 0.88, 0.76 }
Theme.BRASS = { 0.66, 0.52, 0.30 }
Theme.RED = { 0.76, 0.15, 0.11 }
Theme.INK = { 0.07, 0.05, 0.04 }
Theme.DIM = { 0.55, 0.50, 0.42 }

local function hex(c)
	return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end
Theme.BONE_HEX, Theme.BRASS_HEX, Theme.RED_HEX, Theme.DIM_HEX = hex(Theme.BONE), hex(Theme.BRASS), hex(Theme.RED), hex(Theme.DIM)

local function flat(frame, bg, border, edge)
	frame:SetBackdrop({ bgFile = Theme.WHITE, edgeFile = Theme.WHITE, edgeSize = edge or 1 })
	frame:SetBackdropColor(unpack(bg))
	frame:SetBackdropBorderColor(unpack(border))
end

-- Window: ink-black leather, brass hairline, a red band along the top edge.
function Theme.Panel(frame)
	flat(frame, { Theme.INK[1], Theme.INK[2], Theme.INK[3], 0.96 }, { Theme.BRASS[1], Theme.BRASS[2], Theme.BRASS[3], 0.9 })
	local band = frame:CreateTexture(nil, "ARTWORK")
	band:SetColorTexture(unpack(Theme.RED))
	band:SetHeight(3)
	band:SetPoint("TOPLEFT", 1, -1)
	band:SetPoint("TOPRIGHT", -1, -1)
	local grain = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	grain:SetPoint("TOPLEFT", 1, -1)
	grain:SetPoint("BOTTOMRIGHT", -1, 1)
	grain:SetColorTexture(1, 1, 1, 1)
	if not pcall(grain.SetGradient, grain, "VERTICAL", CreateColor(0.10, 0.07, 0.05, 0.0), CreateColor(0.22, 0.13, 0.08, 0.35)) then
		grain:SetColorTexture(0.2, 0.12, 0.07, 0.15)
	end
end

-- Title block: the wax seal hanging over the top-left corner, the name in Skurri, a red rule.
function Theme.Header(frame, text, subtitle)
	local seal = frame:CreateTexture(nil, "OVERLAY")
	seal:SetTexture(Theme.SEAL)
	seal:SetSize(56, 56)
	seal:SetPoint("TOPLEFT", -16, 16)
	local title = Theme.Title(frame, 22, text)
	title:SetPoint("TOPLEFT", 46, -12)
	if subtitle then
		local sub = frame:CreateFontString(nil, "OVERLAY")
		sub:SetFont(Theme.BODY_FONT, 10, "")
		sub:SetTextColor(unpack(Theme.DIM))
		sub:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 3)
		sub:SetText(subtitle)
	end
	local rule = frame:CreateTexture(nil, "ARTWORK")
	rule:SetColorTexture(Theme.RED[1], Theme.RED[2], Theme.RED[3], 0.8)
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", 14, -42)
	rule:SetPoint("TOPRIGHT", -14, -42)
	return title
end

function Theme.Title(parent, size, text, color)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(Theme.TITLE_FONT, size, "")
	fs:SetTextColor(unpack(color or Theme.BONE))
	fs:SetShadowColor(0, 0, 0, 1)
	fs:SetShadowOffset(1, -1)
	if text then fs:SetText(text) end
	return fs
end

function Theme.Text(parent, size, color)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(Theme.BODY_FONT, size or 11, "")
	fs:SetTextColor(unpack(color or Theme.BONE))
	return fs
end

-- The ledger page: darker ruled area with a red margin line, like the logo.
function Theme.Ledger(frame)
	flat(frame, { 0.035, 0.025, 0.02, 0.92 }, { Theme.BRASS[1], Theme.BRASS[2], Theme.BRASS[3], 0.35 })
	local margin = frame:CreateTexture(nil, "ARTWORK")
	margin:SetColorTexture(Theme.RED[1], Theme.RED[2], Theme.RED[3], 0.55)
	margin:SetWidth(1)
	margin:SetPoint("TOPLEFT", 30, -1)
	margin:SetPoint("BOTTOMLEFT", 30, 1)
end

function Theme.Rule(parent, alpha)
	local line = parent:CreateTexture(nil, "BORDER")
	line:SetColorTexture(Theme.BRASS[1], Theme.BRASS[2], Theme.BRASS[3], alpha or 0.18)
	line:SetHeight(1)
	return line
end

-- Flat button: dark oxblood fill, red edge, bone text. Brightens on hover, greys when disabled.
function Theme.Button(parent, width, height, text)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(width, height or 22)
	flat(b, { 0.20, 0.05, 0.04, 0.95 }, { Theme.RED[1], Theme.RED[2], Theme.RED[3], 0.9 })
	b.label = Theme.Text(b, 11)
	b.label:SetPoint("CENTER")
	b.SetText = function(self, t) self.label:SetText(t) end
	b:SetText(text or "")
	b:SetScript("OnEnter", function(self) if self:IsEnabled() then self:SetBackdropColor(0.36, 0.08, 0.06, 1) end end)
	b:SetScript("OnLeave", function(self) if self:IsEnabled() then self:SetBackdropColor(0.20, 0.05, 0.04, 0.95) end end)
	b:SetScript("OnEnable", function(self)
		self:SetBackdropColor(0.20, 0.05, 0.04, 0.95)
		self:SetBackdropBorderColor(Theme.RED[1], Theme.RED[2], Theme.RED[3], 0.9)
		self.label:SetTextColor(unpack(Theme.BONE))
	end)
	b:SetScript("OnDisable", function(self)
		self:SetBackdropColor(0.10, 0.08, 0.07, 0.9)
		self:SetBackdropBorderColor(0.3, 0.27, 0.22, 0.8)
		self.label:SetTextColor(unpack(Theme.DIM))
	end)
	return b
end

-- Tab: brass label; the selected tab turns bone with a red underline.
function Theme.Tab(parent, text, onClick)
	local t = CreateFrame("Button", nil, parent)
	t.label = Theme.Title(t, 15, text, Theme.BRASS)
	t.label:SetPoint("CENTER", 0, 1)
	t:SetSize(t.label:GetStringWidth() + 22, 24)
	t.line = t:CreateTexture(nil, "ARTWORK")
	t.line:SetColorTexture(unpack(Theme.RED))
	t.line:SetHeight(2)
	t.line:SetPoint("BOTTOMLEFT", 6, 0)
	t.line:SetPoint("BOTTOMRIGHT", -6, 0)
	t.SetSelected = function(self, on)
		self.selected = on
		self.line:SetShown(on)
		self.label:SetTextColor(unpack(on and Theme.BONE or Theme.BRASS))
	end
	t:SetScript("OnEnter", function(self) if not self.selected then self.label:SetTextColor(unpack(Theme.BONE)) end end)
	t:SetScript("OnLeave", function(self) if not self.selected then self.label:SetTextColor(unpack(Theme.BRASS)) end end)
	t:SetScript("OnClick", onClick)
	t:SetSelected(false)
	return t
end

-- Single-line input: ink field, brass hairline that turns red while typing.
function Theme.Input(parent, width, numeric)
	local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	box:SetSize(width, 24)
	flat(box, { 0.03, 0.02, 0.02, 0.95 }, { Theme.BRASS[1], Theme.BRASS[2], Theme.BRASS[3], 0.6 })
	box:SetFont(Theme.BODY_FONT, 12, "")
	box:SetTextColor(unpack(Theme.BONE))
	box:SetTextInsets(8, 8, 0, 0)
	box:SetAutoFocus(false)
	if numeric then box:SetNumeric(true) end
	box:SetScript("OnEscapePressed", box.ClearFocus)
	box:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(Theme.RED[1], Theme.RED[2], Theme.RED[3], 1) end)
	box:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(Theme.BRASS[1], Theme.BRASS[2], Theme.BRASS[3], 0.6) end)
	return box
end

function Theme.Label(parent, text)
	local l = Theme.Title(parent, 13, text, Theme.BRASS)
	return l
end

function Theme.Close(frame)
	local close = CreateFrame("Button", nil, frame)
	close:SetSize(22, 22)
	close:SetPoint("TOPRIGHT", -8, -10)
	close.label = Theme.Text(close, 14, Theme.BRASS)
	close.label:SetText("X")
	close.label:SetPoint("CENTER")
	close:SetScript("OnEnter", function(self) self.label:SetTextColor(unpack(Theme.RED)) end)
	close:SetScript("OnLeave", function(self) self.label:SetTextColor(unpack(Theme.BRASS)) end)
	close:SetScript("OnClick", function() frame:Hide() end)
	return close
end

-- Class icon from the shared class-circles sheet; falls back to a skull.
function Theme.SetClassIcon(tex, classFile)
	local coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
	if coords then
		tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
		tex:SetTexCoord(unpack(coords))
	else
		tex:SetTexture(Theme.SKULL)
		tex:SetTexCoord(0, 1, 0, 1)
	end
end

function Theme.Window(name, width, height, key)
	local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	f:SetSize(width, height)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	Theme.Panel(f)
	Theme.Close(f)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetClampedToScreen(true)
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		ns.db.settings.positions = ns.db.settings.positions or {}
		ns.db.settings.positions[key] = { point, relPoint, x, y }
	end)
	local saved = ns.db.settings.positions and ns.db.settings.positions[key]
	if saved then
		f:ClearAllPoints()
		f:SetPoint(saved[1], UIParent, saved[2], saved[3], saved[4])
	end
	f:Hide()
	if name then tinsert(UISpecialFrames, name) end
	return f
end
