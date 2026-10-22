-- Board window, post dialog, the BOUNTY CLAIMED banner, toasts, nameplate seals, slash commands.
local _, ns = ...

local UI = {}
ns.UI = UI
local T = ns.Theme

local ROWS = 12
local ROW_HEIGHT = 24
local COLS = { 190, 100, 220, 140 }
local LIST_LEFT = 38

local main, postDialog, banner, toast
local rows, tabButtons = {}, {}
local currentTab, page = "wanted", 1

local STATUS_TEXT = {
	open = T.BONE_HEX .. "Open|r",
	claimed = "|cffffd100Claimed|r",
	cancelled = T.DIM_HEX .. "Cancelled|r",
	expired = T.DIM_HEX .. "Expired|r",
	unpaid = "|cffffd100Unpaid|r",
	overdue = T.RED_HEX .. "Overdue|r",
	paid = "|cff99ff99Paid, awaiting hunter|r",
	received = "|cff5fd35fPaid|r",
	verified = "|cff5fd35fVerified|r",
	disputed = "|cffff9933Disputed|r",
	late = T.DIM_HEX .. "Late (someone was first)|r",
}

local function classColored(classFile, text)
	local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
	if c and c.colorStr then return "|c" .. c.colorStr .. text .. "|r" end
	return text
end

local function repBadge(name)
	local r = ns.state.rep[name]
	if not r then return T.DIM_HEX .. "new|r" end
	local owed = r.paid + r.overdue + r.disputes
	if r.overdue > 0 then return T.RED_HEX .. r.overdue .. " unpaid|r" end
	if owed == 0 then return T.DIM_HEX .. "no claims yet|r" end
	return "|cff5fd35fpaid " .. r.paid .. "/" .. owed .. "|r"
end

local function sortedBounties(filter, sorter)
	local list = {}
	for _, b in pairs(ns.state.bounties) do
		if filter(b) then list[#list + 1] = b end
	end
	table.sort(list, sorter or function(x, y) return x.t > y.t end)
	return list
end

local function targetLabel(b)
	local label = classColored(b.class, b.tn)
	if b.level then label = label .. " " .. T.DIM_HEX .. b.level .. "|r" end
	return label
end

-- tab data -------------------------------------------------------------------

local TABS = {
	{ key = "wanted", label = "Wanted", header = { "Target", "Reward", "Posted by", "Time left" } },
	{ key = "mine", label = "My Bounties", header = { "Target", "Reward", "Status", "Posted" } },
	{ key = "claims", label = "My Claims", header = { "Target", "Reward", "Poster", "Payment" } },
	{ key = "deaths", label = "My Deaths", header = { "Killed by", "Ability", "Zone", "When" } },
	{ key = "rep", label = "Reputation", header = { "Player", "Bounties paid", "Unpaid / disputed", "Collected" } },
}

local function buildRows()
	local out = {}
	local me = ns.me.name
	if currentTab == "wanted" then
		local list = sortedBounties(function(b) return b.status == "open" end, function(x, y) return x.reward > y.reward end)
		for _, b in ipairs(list) do
			local left = math.max(0, b.expires - ns.Now())
			local hours = math.floor(left / 3600)
			out[#out + 1] = {
				class = b.class,
				cols = { targetLabel(b), ns.Money(b.reward), b.poster .. "  " .. repBadge(b.poster), hours >= 24 and (math.floor(hours / 24) .. "d " .. hours % 24 .. "h") or (hours .. "h") },
				tip = b.note,
			}
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
				status = c.hunter .. ": " .. (STATUS_TEXT[c.status] or c.status)
				if cos > 0 then status = status .. " " .. T.DIM_HEX .. "+" .. cos .. " witness|r" end
				if c.status == "unpaid" or c.status == "overdue" then
					action = { label = "Dispute", fn = function() ns.Bounties.Dispute(c.id, "poster disputes") end }
				end
			end
			out[#out + 1] = { class = b.class, cols = { targetLabel(b), ns.Money(b.reward), status, ns.Ago(b.t) .. " ago" }, action = action }
		end
	elseif currentTab == "claims" then
		local list = {}
		for _, c in pairs(ns.state.claims) do
			if c.hunter == me then list[#list + 1] = c end
		end
		table.sort(list, function(x, y) return x.kt > y.kt end)
		for _, c in ipairs(list) do
			local b = c.bounty
			out[#out + 1] = { class = b.class, cols = { targetLabel(b), ns.Money(b.reward), b.poster .. "  " .. repBadge(b.poster), STATUS_TEXT[c.status] or c.status } }
		end
	elseif currentTab == "deaths" then
		for _, d in ipairs(ns.world.deaths) do
			out[#out + 1] = {
				skull = true,
				cols = { d.killer, d.spell or "Melee", d.zone or "", ns.Ago(d.t) .. " ago" },
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
				seal = true,
				cols = { r.name, r.paid .. " of " .. r.posted .. " posted", bad > 0 and (T.RED_HEX .. bad .. "|r") or "0", r.collected .. " of " .. r.claims .. " claims" },
			}
		end
	end
	return out
end

-- main window ----------------------------------------------------------------

local function stats()
	local open, gold = 0, 0
	for _, b in pairs(ns.state.bounties) do
		if b.status == "open" then
			open = open + 1
			gold = gold + b.reward
		end
	end
	return open, gold
end

local function refresh()
	if not main or not main:IsShown() then return end
	local tab
	for _, t in ipairs(TABS) do
		if t.key == currentTab then tab = t end
		tabButtons[t.key]:SetSelected(t.key == currentTab)
	end
	for i, h in ipairs(main.headers) do h:SetText(tab.header[i]:upper()) end

	local open, gold = stats()
	main.statOpen:SetText(open)
	main.statGold:SetText(ns.Money(gold))
	main.statRep:SetText(repBadge(ns.me.name))

	local data = buildRows()
	local pages = math.max(1, math.ceil(#data / ROWS))
	page = math.min(page, pages)
	for i = 1, ROWS do
		local row, item = rows[i], data[(page - 1) * ROWS + i]
		if item then
			for c = 1, 4 do row.cols[c]:SetText(item.cols[c] or "") end
			if item.skull then
				row.icon:SetTexture(T.SKULL)
				row.icon:SetTexCoord(0, 1, 0, 1)
			elseif item.seal then
				row.icon:SetTexture(T.SEAL)
				row.icon:SetTexCoord(0, 1, 0, 1)
			else
				T.SetClassIcon(row.icon, item.class)
			end
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

	local entries, players = 0, 0
	for _ in pairs(ns.world.entries) do entries = entries + 1 end
	for _ in pairs(ns.world.heads) do players = players + 1 end
	main.status:SetText(entries .. (entries == 1 and " record" or " records") .. " from " .. players .. (players == 1 and " player" or " players"))
end
UI.Refresh = refresh

local function stat(parent, x, label)
	local value = T.Title(parent, 20, "0")
	value:SetPoint("TOPLEFT", x, -54)
	local l = T.Text(parent, 9, T.DIM)
	l:SetPoint("TOPLEFT", value, "BOTTOMLEFT", 0, -2)
	l:SetText(label)
	return value
end

local function createMain()
	main = T.Window("BountyLedgerFrame", 780, 520, "board")
	T.Header(main, "BOUNTY LEDGER", "v" .. ns.VERSION)

	main.statOpen = stat(main, 24, "OPEN BOUNTIES")
	main.statGold = stat(main, 190, "GOLD ON THE BOARD")
	main.statRep = stat(main, 420, "YOUR RECORD AS A POSTER")
	-- Skurri draws 1 like a Roman I, so numbers use the body face.
	main.statOpen:SetFont(T.BODY_FONT, 18, "")
	main.statGold:SetFont(T.BODY_FONT, 15, "")
	main.statRep:SetFont(T.BODY_FONT, 14, "")

	local x = 16
	for _, t in ipairs(TABS) do
		local tab = T.Tab(main, t.label, function()
			currentTab, page = t.key, 1
			refresh()
		end)
		tab:SetPoint("TOPLEFT", x, -98)
		tabButtons[t.key] = tab
		x = x + tab:GetWidth() + 4
	end

	local ledger = CreateFrame("Frame", nil, main, "BackdropTemplate")
	ledger:SetPoint("TOPLEFT", 14, -126)
	ledger:SetPoint("BOTTOMRIGHT", -14, 50)
	T.Ledger(ledger)
	main.ledger = ledger

	main.headers = {}
	local hx = LIST_LEFT
	for i, w in ipairs(COLS) do
		local h = T.Text(ledger, 9, T.BRASS)
		h:SetPoint("TOPLEFT", hx, -9)
		h:SetWidth(w)
		h:SetJustifyH("LEFT")
		main.headers[i] = h
		hx = hx + w + 8
	end
	local headRule = T.Rule(ledger, 0.5)
	headRule:SetPoint("TOPLEFT", 1, -24)
	headRule:SetPoint("TOPRIGHT", -1, -24)

	for i = 1, ROWS do
		local row = CreateFrame("Frame", nil, ledger)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 1, -25 - (i - 1) * ROW_HEIGHT)
		row:SetPoint("TOPRIGHT", -1, -25 - (i - 1) * ROW_HEIGHT)
		local rule = T.Rule(row)
		rule:SetPoint("BOTTOMLEFT")
		rule:SetPoint("BOTTOMRIGHT")
		local hover = row:CreateTexture(nil, "BACKGROUND")
		hover:SetAllPoints()
		hover:SetColorTexture(T.RED[1], T.RED[2], T.RED[3], 0.12)
		hover:Hide()
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(18, 18)
		row.icon:SetPoint("LEFT", 6, 0)
		row.cols = {}
		local cx = LIST_LEFT - 1
		for c, w in ipairs(COLS) do
			local fs = T.Text(row, 11)
			fs:SetPoint("LEFT", cx, 0)
			fs:SetWidth(w)
			fs:SetJustifyH("LEFT")
			fs:SetWordWrap(false)
			row.cols[c] = fs
			cx = cx + w + 8
		end
		row.action = T.Button(row, 66, 18)
		row.action:SetPoint("RIGHT", -6, 0)
		row:EnableMouse(true)
		row:SetScript("OnEnter", function(self)
			hover:Show()
			if not self.tip then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function()
			hover:Hide()
			GameTooltip:Hide()
		end)
		rows[i] = row
	end

	main.empty = T.Title(ledger, 16, "The ledger is empty. For now.", T.DIM)
	main.empty:SetPoint("CENTER", 0, 0)

	local post = T.Button(main, 140, 26, "Post a Bounty")
	post:SetPoint("BOTTOMLEFT", 14, 14)
	post:SetScript("OnClick", function() UI.OpenPost(ns.Bounties.SpecFromTarget()) end)

	local settings = T.Button(main, 80, 26, "Settings")
	settings:SetPoint("LEFT", post, "RIGHT", 8, 0)
	settings:SetScript("OnClick", function() ns.Settings.Open() end)

	main.status = T.Text(main, 10, T.DIM)
	main.status:SetPoint("LEFT", settings, "RIGHT", 12, 0)

	main.next = T.Button(main, 26, 22, ">")
	main.next:SetPoint("BOTTOMRIGHT", -14, 16)
	main.next:SetScript("OnClick", function() page = page + 1 refresh() end)
	main.pageText = T.Text(main, 11, T.BRASS)
	main.pageText:SetPoint("RIGHT", main.next, "LEFT", -8, 0)
	main.prev = T.Button(main, 26, 22, "<")
	main.prev:SetPoint("RIGHT", main.pageText, "LEFT", -8, 0)
	main.prev:SetScript("OnClick", function() page = page - 1 refresh() end)

	main:SetScript("OnShow", refresh)
end

function UI.Toggle()
	if not ns.world then return end
	if not main then createMain() end
	main:SetShown(not main:IsShown())
end

-- post dialog ----------------------------------------------------------------

local function createPost()
	postDialog = T.Window("BountyLedgerPostFrame", 380, 330, "post")
	postDialog:SetFrameStrata("DIALOG")
	T.Header(postDialog, "POST A BOUNTY")

	postDialog.icon = postDialog:CreateTexture(nil, "ARTWORK")
	postDialog.icon:SetSize(36, 36)
	postDialog.icon:SetPoint("TOPLEFT", 20, -56)
	postDialog.who = T.Title(postDialog, 18, "")
	postDialog.who:SetPoint("TOPLEFT", postDialog.icon, "TOPRIGHT", 10, -2)
	postDialog.info = T.Text(postDialog, 10, T.DIM)
	postDialog.info:SetPoint("TOPLEFT", postDialog.who, "BOTTOMLEFT", 0, -4)
	postDialog.info:SetWidth(290)
	postDialog.info:SetJustifyH("LEFT")

	local l1 = T.Label(postDialog, "Target (First Last)")
	l1:SetPoint("TOPLEFT", 20, -110)
	postDialog.name = T.Input(postDialog, 250)
	postDialog.name:SetPoint("TOPLEFT", l1, "BOTTOMLEFT", 0, -4)
	local use = T.Button(postDialog, 80, 24, "Use Target")
	use:SetPoint("LEFT", postDialog.name, "RIGHT", 8, 0)
	use:SetScript("OnClick", function()
		local spec, err = ns.Bounties.SpecFromTarget()
		if spec then UI.OpenPost(spec) else ns.Print(err) end
	end)
	postDialog.name:SetScript("OnTextChanged", function(self, user)
		if user then
			postDialog.spec = { name = self:GetText() }
			postDialog.who:SetText(self:GetText())
			T.SetClassIcon(postDialog.icon, nil)
			postDialog.info:SetText("Posting by name. Target the player and press Use Target to lock it to them exactly.")
		end
	end)

	local l2 = T.Label(postDialog, "Reward")
	l2:SetPoint("TOPLEFT", 20, -164)
	postDialog.gold = T.Input(postDialog, 110, true)
	postDialog.gold:SetPoint("TOPLEFT", l2, "BOTTOMLEFT", 0, -4)
	local coin = T.Text(postDialog, 11, T.BRASS)
	coin:SetPoint("LEFT", postDialog.gold, "RIGHT", 8, 0)
	coin:SetText("gold")

	local l3 = T.Label(postDialog, "Note")
	l3:SetPoint("TOPLEFT", 20, -218)
	postDialog.note = T.Input(postDialog, 340)
	postDialog.note:SetPoint("TOPLEFT", l3, "BOTTOMLEFT", 0, -4)
	postDialog.note:SetMaxLetters(80)

	local ok = T.Button(postDialog, 160, 28, "Post Bounty")
	ok:SetPoint("BOTTOM", 0, 16)
	ok:SetScript("OnClick", function()
		local spec = postDialog.spec or {}
		spec.name = strtrim(postDialog.name:GetText() or "")
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
	postDialog.gold:SetScript("OnEnterPressed", function() ok:Click() end)
end

function UI.OpenPost(spec)
	if not ns.world then return end
	if not postDialog then createPost() end
	spec = spec or {}
	postDialog.spec = spec
	postDialog.name:SetText(spec.name or "")
	postDialog.gold:SetText("")
	postDialog.note:SetText("")
	postDialog.who:SetText(spec.name and classColored(spec.class, spec.name) or T.DIM_HEX .. "No target|r")
	T.SetClassIcon(postDialog.icon, spec.class)
	if spec.guid then
		postDialog.info:SetText("Locked to this exact player: level " .. (spec.level or "?") .. " " .. (spec.race or "") .. ".")
	elseif spec.name then
		postDialog.info:SetText("Posting by name. Target the player and press Use Target to lock it to them exactly.")
	else
		postDialog.info:SetText("Target an enemy player and press Use Target, or type their full name.")
	end
	postDialog:Show()
	if spec.name then postDialog.gold:SetFocus() else postDialog.name:SetFocus() end
end

-- banner and toast -----------------------------------------------------------

local function createBanner()
	banner = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	banner:SetSize(760, 120)
	banner:SetPoint("TOP", 0, -140)
	banner:SetFrameStrata("HIGH")
	banner:SetBackdrop({ bgFile = T.WHITE })
	banner:SetBackdropColor(0.04, 0.02, 0.02, 0.88)
	for _, edge in ipairs({ "TOP", "BOTTOM" }) do
		local rule = banner:CreateTexture(nil, "ARTWORK")
		rule:SetColorTexture(unpack(T.RED))
		rule:SetHeight(2)
		rule:SetPoint(edge .. "LEFT")
		rule:SetPoint(edge .. "RIGHT")
	end
	local seal = banner:CreateTexture(nil, "OVERLAY")
	seal:SetTexture(T.SEAL)
	seal:SetSize(96, 96)
	seal:SetPoint("LEFT", 26, 0)
	banner.title = T.Title(banner, 40, "", T.RED)
	banner.title:SetPoint("TOPLEFT", seal, "TOPRIGHT", 22, -10)
	banner.sub = T.Text(banner, 16)
	banner.sub:SetPoint("TOPLEFT", banner.title, "BOTTOMLEFT", 2, -10)

	banner.anim = banner:CreateAnimationGroup()
	local fadeIn = banner.anim:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.25)
	fadeIn:SetOrder(1)
	local fadeOut = banner.anim:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetDuration(0.8)
	fadeOut:SetStartDelay(4.5)
	fadeOut:SetOrder(2)
	banner.anim:SetScript("OnFinished", function() banner:Hide() end)
	banner:Hide()
end

function UI.Banner(title, sub)
	if not banner then createBanner() end
	banner.title:SetText(title)
	banner.sub:SetText(sub)
	banner:Show()
	banner.anim:Stop()
	banner.anim:Play()
	if ns.db.settings.sound then PlaySound(SOUNDKIT.RAID_WARNING) end
end

local function createToast()
	toast = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	toast:SetSize(440, 48)
	toast:SetPoint("TOP", 0, -84)
	toast:SetFrameStrata("HIGH")
	toast:SetBackdrop({ bgFile = T.WHITE, edgeFile = T.WHITE, edgeSize = 1 })
	toast:SetBackdropColor(0.05, 0.035, 0.03, 0.94)
	toast:SetBackdropBorderColor(T.BRASS[1], T.BRASS[2], T.BRASS[3], 0.7)
	local bar = toast:CreateTexture(nil, "ARTWORK")
	bar:SetColorTexture(unpack(T.RED))
	bar:SetWidth(3)
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("BOTTOMLEFT", 1, 1)
	local seal = toast:CreateTexture(nil, "OVERLAY")
	seal:SetTexture(T.SEAL)
	seal:SetSize(34, 34)
	seal:SetPoint("LEFT", 10, 0)
	toast.text = T.Text(toast, 12)
	toast.text:SetPoint("LEFT", seal, "RIGHT", 10, 0)
	toast.text:SetPoint("RIGHT", -12, 0)
	toast.text:SetJustifyH("LEFT")
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

-- nameplate seals ------------------------------------------------------------

local function updatePlate(unit)
	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then return end
	local wanted = false
	if ns.db.settings.nameplates and UnitIsPlayer(unit) then
		local guid, name = UnitGUID(unit), ns.UnitFullName(unit)
		if not ns.IsSecret(guid) and name then wanted = #ns.Bounties.OpenOn(guid, name) > 0 end
	end
	if wanted and not plate.bountySeal then
		local ok, tex = pcall(plate.CreateTexture, plate, nil, "OVERLAY")
		if not ok then return end
		tex:SetTexture(T.SEAL)
		tex:SetSize(26, 26)
		tex:SetPoint("BOTTOM", plate, "TOP", 0, 2)
		plate.bountySeal = tex
	end
	if plate.bountySeal then plate.bountySeal:SetShown(wanted) end
end

function UI.UpdatePlates()
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if UnitExists(unit) then updatePlate(unit) end
	end
end

-- wiring ---------------------------------------------------------------------

ns.On("STATE_CHANGED", function()
	refresh()
	UI.UpdatePlates()
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
				UI.Toast(T.RED_HEX .. "WANTED|r  " .. classColored(b.class, b.tn) .. "  " .. ns.Money(b.reward) .. "  " .. T.DIM_HEX .. b.poster .. "|r")
			end
		end
	end
end)

ns.On("CLAIMED", function(targetName, classFile, total)
	if ns.db.settings.banner == false then
		ns.Print("Bounty claimed on " .. targetName .. ": " .. ns.Money(total) .. ".")
		return
	end
	UI.Banner("BOUNTY CLAIMED", classColored(classFile, targetName) .. "   " .. ns.Money(total))
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
	elseif cmd == "settings" or cmd == "config" or cmd == "options" then
		ns.Settings.Open()
	elseif cmd == "minimap" then
		ns.Settings.Set("minimapHidden", not ns.db.settings.minimapHidden)
	elseif cmd == "toasts" or cmd == "sound" then
		ns.Settings.Set(cmd, not ns.db.settings[cmd])
	elseif cmd == "debug" then
		ns.db.settings.debug = not ns.db.settings.debug
		ns.Print("debug " .. (ns.db.settings.debug and "on" or "off"))
	elseif cmd == "chat" then
		ns.Comm.ChatApiReport()
		ns.Comm.HideChannel()
	elseif cmd == "test" then
		UI.Banner("BOUNTY CLAIMED", "Test Target   " .. ns.Money(500000))
	else
		ns.Print("/bounty  open the board")
		ns.Print("/bounty post <gold> [note]  post on your current target")
		ns.Print("/bounty settings | minimap | test")
	end
end
