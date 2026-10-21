-- Board window, post dialog, the BOUNTY CLAIMED banner, toasts, nameplate skulls, slash commands.
local _, ns = ...

local UI = {}
ns.UI = UI

local ROWS = 12
local ROW_HEIGHT = 24
local COLS = { 200, 100, 190, 110 }

local main, postDialog, banner, toast
local rows, tabButtons = {}, {}
local currentTab, page = "wanted", 1

local STATUS_TEXT = {
	open = "|cffffffffOpen|r",
	claimed = "|cffffd100Claimed|r",
	cancelled = "|cff888888Cancelled|r",
	expired = "|cff888888Expired|r",
	unpaid = "|cffffd100Unpaid|r",
	overdue = "|cffff3333Overdue|r",
	paid = "|cff99ff99Paid (hunter hasn't confirmed)|r",
	received = "|cff33ff33Paid|r",
	verified = "|cff33ff33Verified|r",
	disputed = "|cffff9933Disputed|r",
	late = "|cff888888Late (someone was first)|r",
}

local function classColored(classFile, text)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c and c.colorStr then return "|c" .. c.colorStr .. text .. "|r" end
	return text
end

local function repBadge(name)
	local r = ns.state.rep[name]
	if not r then return "|cff888888new|r" end
	local owed = r.paid + r.overdue + r.disputes
	if r.overdue > 0 then return "|cffff3333" .. r.overdue .. " unpaid|r" end
	if owed == 0 then return "|cff888888no claims yet|r" end
	return "|cff33ff33paid " .. r.paid .. "/" .. owed .. "|r"
end

local function sortedBounties(filter, sorter)
	local list = {}
	for _, b in pairs(ns.state.bounties) do
		if filter(b) then list[#list + 1] = b end
	end
	table.sort(list, sorter or function(x, y) return x.t > y.t end)
	return list
end

-- tab data -------------------------------------------------------------------

local TABS = {
	{ key = "wanted", label = "Wanted", header = { "Target", "Reward", "Posted by", "Expires" } },
	{ key = "mine", label = "My Bounties", header = { "Target", "Reward", "Status", "Posted" } },
	{ key = "claims", label = "My Claims", header = { "Target", "Reward", "Poster", "Payment" } },
	{ key = "deaths", label = "My Deaths", header = { "Killed by", "Ability", "Zone", "When" } },
	{ key = "rep", label = "Reputation", header = { "Player", "Bounties paid", "Unpaid / disputed", "Collected" } },
}

local function targetLabel(b)
	local label = classColored(b.class, b.tn)
	if b.level then label = label .. " |cff888888(" .. b.level .. ")|r" end
	return label
end

local function buildRows()
	local out = {}
	local me = ns.me.name
	if currentTab == "wanted" then
		local list = sortedBounties(function(b) return b.status == "open" end, function(x, y) return x.reward > y.reward end)
		for _, b in ipairs(list) do
			local poster = b.poster .. "  " .. repBadge(b.poster)
			local left = math.max(0, b.expires - ns.Now())
			out[#out + 1] = { cols = { targetLabel(b), ns.Money(b.reward), poster, math.floor(left / 3600) .. "h left" }, tip = b.note }
		end
	elseif currentTab == "mine" then
		for _, b in ipairs(sortedBounties(function(b) return b.poster == me end)) do
			local status = STATUS_TEXT[b.status] or b.status
			local action
			if b.status == "open" then
				action = { label = "Cancel", fn = function() ns.Bounties.Cancel(b.id) end }
			elseif b.winner then
				local c = b.winner
				local cos = 0
				for _ in pairs(c.cosigners) do cos = cos + 1 end
				status = "by " .. c.hunter .. ": " .. (STATUS_TEXT[c.status] or c.status)
				if cos > 0 then status = status .. " |cff888888+" .. cos .. " witness|r" end
				if c.status == "unpaid" or c.status == "overdue" then
					action = { label = "Dispute", fn = function() ns.Bounties.Dispute(c.id, "poster disputes") end }
				end
			end
			out[#out + 1] = { cols = { targetLabel(b), ns.Money(b.reward), status, ns.Ago(b.t) .. " ago" }, action = action }
		end
	elseif currentTab == "claims" then
		local list = {}
		for _, c in pairs(ns.state.claims) do
			if c.hunter == me then list[#list + 1] = c end
		end
		table.sort(list, function(x, y) return x.kt > y.kt end)
		for _, c in ipairs(list) do
			local b = c.bounty
			out[#out + 1] = { cols = { targetLabel(b), ns.Money(b.reward), b.poster .. "  " .. repBadge(b.poster), STATUS_TEXT[c.status] or c.status } }
		end
	elseif currentTab == "deaths" then
		for _, d in ipairs(ns.world.deaths) do
			out[#out + 1] = {
				cols = { d.killer, d.spell or "melee", d.zone or "", ns.Ago(d.t) .. " ago" },
				action = { label = "Bounty", fn = function() UI.OpenPost({ name = d.killer }) end },
			}
		end
	elseif currentTab == "rep" then
		local list = {}
		for _, r in pairs(ns.state.rep) do list[#list + 1] = r end
		table.sort(list, function(x, y) return (x.posted + x.claims) > (y.posted + y.claims) end)
		for _, r in ipairs(list) do
			local bad = r.overdue + r.disputes
			out[#out + 1] = {
				cols = { r.name, r.paid .. " of " .. r.posted .. " posted", bad > 0 and ("|cffff3333" .. bad .. "|r") or "0", r.collected .. " of " .. r.claims .. " claims" },
			}
		end
	end
	return out
end

-- main window ----------------------------------------------------------------

local function refresh()
	if not main or not main:IsShown() then return end
	local tab
	for _, t in ipairs(TABS) do
		if t.key == currentTab then tab = t end
		tabButtons[t.key]:SetEnabled(t.key ~= currentTab)
	end
	for i, h in ipairs(main.headers) do h:SetText(tab.header[i]) end

	local data = buildRows()
	local pages = math.max(1, math.ceil(#data / ROWS))
	page = math.min(page, pages)
	for i = 1, ROWS do
		local row, item = rows[i], data[(page - 1) * ROWS + i]
		if item then
			for c = 1, 4 do row.cols[c]:SetText(item.cols[c] or "") end
			row.tip = item.tip
			if item.action then
				row.action:SetText(item.action.label)
				row.action:SetScript("OnClick", item.action.fn)
				row.action:Show()
			else
				row.action:Hide()
			end
			row:Show()
		else
			row:Hide()
		end
	end
	main.empty:SetShown(#data == 0)
	main.pageText:SetText(page .. " / " .. pages)
	main.prev:SetEnabled(page > 1)
	main.next:SetEnabled(page < pages)

	local entries, peers = 0, 0
	for _ in pairs(ns.world.entries) do entries = entries + 1 end
	for _ in pairs(ns.world.heads) do peers = peers + 1 end
	main.status:SetText(string.format("%d records from %d players", entries, peers))
end

local function createMain()
	main = CreateFrame("Frame", "BountyLedgerFrame", UIParent, "BasicFrameTemplateWithInset")
	main:SetSize(740, 430)
	main:SetPoint("CENTER")
	main:SetMovable(true)
	main:EnableMouse(true)
	main:RegisterForDrag("LeftButton")
	main:SetScript("OnDragStart", main.StartMoving)
	main:SetScript("OnDragStop", main.StopMovingOrSizing)
	main:SetClampedToScreen(true)
	main:Hide()
	tinsert(UISpecialFrames, "BountyLedgerFrame")

	local title = main.TitleText or main:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	if not main.TitleText then title:SetPoint("TOP", 0, -5) end
	title:SetText("Bounty Ledger")

	local x = 12
	for _, t in ipairs(TABS) do
		local b = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
		b:SetSize(110, 22)
		b:SetPoint("TOPLEFT", x, -30)
		b:SetText(t.label)
		b:SetScript("OnClick", function()
			currentTab, page = t.key, 1
			refresh()
		end)
		tabButtons[t.key] = b
		x = x + 114
	end

	main.headers = {}
	local hx = 18
	for i, w in ipairs(COLS) do
		local h = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		h:SetPoint("TOPLEFT", hx, -62)
		h:SetWidth(w)
		h:SetJustifyH("LEFT")
		main.headers[i] = h
		hx = hx + w + 8
	end

	for i = 1, ROWS do
		local row = CreateFrame("Frame", nil, main)
		row:SetSize(710, ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 14, -78 - (i - 1) * ROW_HEIGHT)
		if i % 2 == 0 then
			local bg = row:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints()
			bg:SetColorTexture(1, 1, 1, 0.04)
		end
		row.cols = {}
		local cx = 4
		for c, w in ipairs(COLS) do
			local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetPoint("LEFT", cx, 0)
			fs:SetWidth(w)
			fs:SetJustifyH("LEFT")
			fs:SetWordWrap(false)
			row.cols[c] = fs
			cx = cx + w + 8
		end
		row.action = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
		row.action:SetSize(70, 20)
		row.action:SetPoint("RIGHT", -2, 0)
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self)
			if not self.tip then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rows[i] = row
	end

	main.empty = main:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	main.empty:SetPoint("CENTER", 0, 10)
	main.empty:SetText("Nothing here yet.")

	local post = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
	post:SetSize(130, 24)
	post:SetPoint("BOTTOMLEFT", 14, 12)
	post:SetText("Post Bounty")
	post:SetScript("OnClick", function() UI.OpenPost(ns.Bounties.SpecFromTarget()) end)

	main.status = main:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	main.status:SetPoint("LEFT", post, "RIGHT", 12, 0)

	main.next = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
	main.next:SetSize(28, 22)
	main.next:SetPoint("BOTTOMRIGHT", -14, 12)
	main.next:SetText(">")
	main.next:SetScript("OnClick", function() page = page + 1 refresh() end)
	main.pageText = main:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	main.pageText:SetPoint("RIGHT", main.next, "LEFT", -8, 0)
	main.prev = CreateFrame("Button", nil, main, "UIPanelButtonTemplate")
	main.prev:SetSize(28, 22)
	main.prev:SetPoint("RIGHT", main.pageText, "LEFT", -8, 0)
	main.prev:SetText("<")
	main.prev:SetScript("OnClick", function() page = page - 1 refresh() end)

	main:SetScript("OnShow", refresh)
end

function UI.Toggle()
	if not ns.world then return end
	if not main then createMain() end
	main:SetShown(not main:IsShown())
end

-- post dialog ----------------------------------------------------------------

local function editBox(parent, width, label, y)
	local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	l:SetPoint("TOPLEFT", 20, y)
	l:SetText(label)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	e:SetSize(width, 22)
	e:SetPoint("TOPLEFT", 26, y - 14)
	e:SetAutoFocus(false)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	return e
end

local function createPost()
	postDialog = CreateFrame("Frame", "BountyLedgerPostFrame", UIParent, "BasicFrameTemplateWithInset")
	postDialog:SetSize(340, 250)
	postDialog:SetPoint("CENTER", 0, 60)
	postDialog:SetFrameStrata("DIALOG")
	postDialog:EnableMouse(true)
	postDialog:Hide()
	tinsert(UISpecialFrames, "BountyLedgerPostFrame")
	local title = postDialog.TitleText or postDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	if not postDialog.TitleText then title:SetPoint("TOP", 0, -5) end
	title:SetText("Post a Bounty")

	postDialog.name = editBox(postDialog, 220, "Target (First Last)", -34)
	local use = CreateFrame("Button", nil, postDialog, "UIPanelButtonTemplate")
	use:SetSize(60, 22)
	use:SetPoint("LEFT", postDialog.name, "RIGHT", 6, 0)
	use:SetText("Target")
	use:SetScript("OnClick", function()
		local spec, err = ns.Bounties.SpecFromTarget()
		if spec then UI.OpenPost(spec) else ns.Print(err) end
	end)
	postDialog.gold = editBox(postDialog, 100, "Reward (gold)", -84)
	postDialog.gold:SetNumeric(true)
	postDialog.note = editBox(postDialog, 280, "Note (optional)", -134)
	postDialog.note:SetMaxLetters(80)

	postDialog.info = postDialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	postDialog.info:SetPoint("TOPLEFT", 20, -186)
	postDialog.info:SetWidth(300)
	postDialog.info:SetJustifyH("LEFT")

	local ok = CreateFrame("Button", nil, postDialog, "UIPanelButtonTemplate")
	ok:SetSize(120, 24)
	ok:SetPoint("BOTTOM", 0, 14)
	ok:SetText("Post")
	ok:SetScript("OnClick", function()
		local spec = postDialog.spec or {}
		local typed = strtrim(postDialog.name:GetText() or "")
		if ns.NameKey(typed) ~= ns.NameKey(spec.name) then spec = { name = typed } end
		spec.reward = (tonumber(postDialog.gold:GetText()) or 0) * 10000
		spec.note = postDialog.note:GetText()
		local posted, err = ns.Bounties.Post(spec)
		if posted then
			ns.Print("Bounty posted on " .. spec.name .. " for " .. ns.Money(spec.reward) .. ".")
			postDialog:Hide()
		else
			ns.Print(err)
		end
	end)
end

function UI.OpenPost(spec)
	if not ns.world then return end
	if not postDialog then createPost() end
	spec = spec or {}
	postDialog.spec = spec
	postDialog.name:SetText(spec.name or "")
	postDialog.gold:SetText("")
	postDialog.note:SetText("")
	if spec.guid then
		postDialog.info:SetText("Locked to this exact player (" .. (spec.race or "") .. " " .. (spec.class or ""):lower() .. ").")
	else
		postDialog.info:SetText("Posting by name. Targeting the player first locks the bounty to them exactly.")
	end
	postDialog:Show()
	postDialog.gold:SetFocus()
end

-- banner and toast -----------------------------------------------------------

local function createBanner()
	banner = CreateFrame("Frame", nil, UIParent)
	banner:SetSize(820, 130)
	banner:SetPoint("TOP", 0, -150)
	banner:SetFrameStrata("HIGH")
	local bg = banner:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.05, 0, 0, 0.75)
	local skull = banner:CreateTexture(nil, "ARTWORK")
	skull:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
	skull:SetSize(64, 64)
	skull:SetPoint("LEFT", 30, 0)
	banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	banner.title:SetPoint("TOP", 0, -22)
	banner.title:SetTextColor(1, 0.2, 0.2)
	banner.sub = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	banner.sub:SetPoint("TOP", banner.title, "BOTTOM", 0, -14)
	banner.anim = banner:CreateAnimationGroup()
	local fade = banner.anim:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0)
	fade:SetDuration(0.8)
	fade:SetStartDelay(4.5)
	banner.anim:SetScript("OnFinished", function() banner:Hide() end)
	banner:Hide()
end

function UI.Banner(title, sub)
	if not banner then createBanner() end
	banner.title:SetText(title)
	banner.sub:SetText(sub)
	banner:SetAlpha(1)
	banner:Show()
	banner.anim:Stop()
	banner.anim:Play()
	if ns.db.settings.sound then PlaySound(SOUNDKIT.RAID_WARNING) end
end

local function createToast()
	toast = CreateFrame("Frame", nil, UIParent)
	toast:SetSize(460, 44)
	toast:SetPoint("TOP", 0, -90)
	toast:SetFrameStrata("HIGH")
	local bg = toast:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.65)
	toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	toast.text:SetPoint("CENTER")
	toast.text:SetWidth(440)
	toast.anim = toast:CreateAnimationGroup()
	local fade = toast.anim:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0)
	fade:SetDuration(0.6)
	fade:SetStartDelay(5)
	toast.anim:SetScript("OnFinished", function() toast:Hide() end)
	toast:Hide()
end

function UI.Toast(text)
	if not ns.db.settings.toasts then return end
	if not toast then createToast() end
	toast.text:SetText(text)
	toast:SetAlpha(1)
	toast:Show()
	toast.anim:Stop()
	toast.anim:Play()
end

-- nameplate skulls -----------------------------------------------------------

local function updatePlate(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then return end
	local guid, name = UnitGUID(unit), ns.UnitFullName(unit)
	local wanted = false
	if UnitIsPlayer(unit) and not ns.IsSecret(guid) and name then
		wanted = #ns.Bounties.OpenOn(guid, name) > 0
	end
	if wanted and not plate.bountySkull then
		local ok, tex = pcall(plate.CreateTexture, plate, nil, "OVERLAY")
		if not ok then return end
		tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
		tex:SetSize(22, 22)
		tex:SetPoint("BOTTOM", plate, "TOP", 0, 2)
		plate.bountySkull = tex
	end
	if plate.bountySkull then plate.bountySkull:SetShown(wanted) end
end

local function updateAllPlates()
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if UnitExists(unit) then updatePlate(unit) end
	end
end

-- wiring ---------------------------------------------------------------------

ns.On("STATE_CHANGED", function()
	refresh()
	updateAllPlates()
	-- Tell the poster once when one of their bounties is claimed, and everyone once when a
	-- new bounty goes up while they're online.
	local w, me = ns.world, ns.me.name
	for _, b in pairs(ns.state.bounties) do
		if b.winner and b.poster == me and not w.notified[b.winner.id] then
			w.notified[b.winner.id] = true
			UI.Toast(b.winner.hunter .. " claimed your bounty on " .. b.tn .. ". Pay " .. ns.Money(b.reward) .. " by trade.")
		elseif b.status == "open" and b.poster ~= me and not w.notified[b.id] then
			w.notified[b.id] = true
			if ns.Now() - b.t < 120 then
				UI.Toast("|cffff3333WANTED|r " .. b.tn .. "  " .. ns.Money(b.reward) .. "  |cff888888(" .. b.poster .. ")|r")
			end
		end
	end
end)

ns.On("CLAIMED", function(targetName, classFile, total)
	UI.Banner("BOUNTY CLAIMED", classColored(classFile, targetName) .. "  -  " .. ns.Money(total))
end)

local updateNoticeShown = false
ns.On("NEWER_VERSION", function(version)
	if updateNoticeShown then return end
	updateNoticeShown = true
	ns.Print("A newer version" .. (version and (" (" .. version .. ")") or "") ..
		" is out. Update on CurseForge to keep seeing everyone's bounties.")
end)

ns.On("DIED", function(death)
	ns.Print("Killed by " .. death.killer .. (death.spell and (" (" .. death.spell .. ")") or "") .. ". It's in My Deaths if you want to post a bounty.")
	refresh()
end)

local plates = CreateFrame("Frame")
plates:RegisterEvent("NAME_PLATE_UNIT_ADDED")
plates:SetScript("OnEvent", function(_, _, unit)
	-- Plates can arrive before the unit is filled in; check again a moment later.
	updatePlate(unit)
	C_Timer.After(0.2, function() if UnitExists(unit) then updatePlate(unit) end end)
end)

function BountyLedger_OnAddonCompartmentClick()
	UI.Toggle()
end

SLASH_BOUNTYLEDGER1 = "/bounty"
SLASH_BOUNTYLEDGER2 = "/bledger"
SlashCmdList.BOUNTYLEDGER = function(msg)
	local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	if cmd == "" then
		UI.Toggle()
	elseif cmd == "post" then
		local spec, err = ns.Bounties.SpecFromTarget()
		if not spec then ns.Print(err) return end
		local gold, note = rest:match("^(%d+)%s*(.-)$")
		if not gold then UI.OpenPost(spec) return end
		spec.reward, spec.note = tonumber(gold) * 10000, note
		local ok, e = ns.Bounties.Post(spec)
		ns.Print(ok and ("Bounty posted on " .. spec.name .. " for " .. ns.Money(spec.reward) .. ".") or e)
	elseif cmd == "toasts" or cmd == "sound" then
		ns.db.settings[cmd] = not ns.db.settings[cmd]
		ns.Print(cmd .. " " .. (ns.db.settings[cmd] and "on" or "off"))
	elseif cmd == "debug" then
		ns.db.settings.debug = not ns.db.settings.debug
		ns.Print("debug " .. (ns.db.settings.debug and "on" or "off"))
	elseif cmd == "chat" then
		ns.Comm.ChatApiReport()
		ns.Comm.HideChannel()
	elseif cmd == "test" then
		UI.Banner("BOUNTY CLAIMED", "Test Target  -  " .. ns.Money(500000))
	else
		ns.Print("/bounty  open the board")
		ns.Print("/bounty post <gold> [note]  post on your current target")
		ns.Print("/bounty toasts | sound | test | debug")
	end
end
