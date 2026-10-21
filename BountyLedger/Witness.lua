-- The witnesses. Everything here is something this client saw happen with its own events:
--   * PARTY_KILL: a killing blow by me or a groupmate, with both GUIDs (open world only).
--   * The death recap: who killed me, read from the [Death Recap] link the client prints.
--   * Trades: who I traded with and how much gold moved each way.
local _, ns = ...

local Witness = {}
ns.Witness = Witness

local recentClaims = {}

-- kills ----------------------------------------------------------------------

local function onPartyKill(attackerGUID, targetGUID)
	if not ns.world or not ns.InOpenWorld() then return end
	if ns.IsSecret(attackerGUID) or ns.IsSecret(targetGUID) or not targetGUID then return end
	if not targetGUID:find("^Player%-") then return end

	local _, classFile, race, _, _, targetName = GetPlayerInfoByGUID(targetGUID)
	if ns.IsSecret(targetName) then return end
	local open = ns.Bounties.OpenOn(targetGUID, targetName)
	if #open == 0 then return end

	local now, zone = ns.Now(), GetZoneText()
	if attackerGUID == ns.me.guid then
		local total = 0
		for _, b in ipairs(open) do
			local key = b.id .. "@" .. targetGUID
			if not recentClaims[key] or now - recentClaims[key] > 60 then
				recentClaims[key] = now
				if ns.Ledger.Append("CLAIM", { b = b.id, tid = targetGUID, tn = targetName, kt = now, z = zone }) then
					total = total + b.reward
				end
			end
		end
		if total > 0 then ns.Fire("CLAIMED", targetName, classFile, total, open) end
	else
		local _, _, _, _, _, hunterName = GetPlayerInfoByGUID(attackerGUID)
		if hunterName and not ns.IsSecret(hunterName) then
			ns.Ledger.Append("COSIGN", { tid = targetGUID, tn = targetName, hn = hunterName, kt = now })
		end
	end
end

-- death recap ----------------------------------------------------------------
-- The killing blow is the recap event with overkill > 0. Recap ids persist across deaths,
-- so only the id from the chat link is trusted, never a guess.

local function onSystemMessage(text)
	if type(text) ~= "string" or ns.IsSecret(text) or not ns.world then return end
	local id = text:match("|Hdeath:(%d+)|h")
	if not id or not C_DeathRecap or not ns.InOpenWorld() then return end
	local ok, events = pcall(C_DeathRecap.GetRecapEvents, tonumber(id))
	if not ok or type(events) ~= "table" or #events == 0 then return end
	local blow = events[1]
	for _, e in ipairs(events) do
		if e.overkill and not ns.IsSecret(e.overkill) and e.overkill > 0 then
			blow = e
			break
		end
	end
	if ns.IsSecret(blow.sourceName) or not blow.sourceName then return end
	local death = {
		t = ns.Now(), killer = blow.sourceName, spell = blow.spellName, amount = blow.amount,
		overkill = blow.overkill, zone = GetZoneText(),
	}
	table.insert(ns.world.deaths, 1, death)
	while #ns.world.deaths > 100 do table.remove(ns.world.deaths) end
	ns.Fire("DIED", death)
end

-- trades ---------------------------------------------------------------------
-- When a trade completes, gold I gave to a hunter I owe is recorded as PAY; gold I got from
-- a poster who owes me is recorded as RECV. The other side's client records the mirror entry.

local trade

local function snapshotTrade()
	if not trade then return end
	trade.give = GetPlayerTradeMoney() or trade.give
	trade.get = GetTargetTradeMoney() or trade.get
end

local function settle(partner, give, get)
	local owed, owing = {}, {}
	for _, c in pairs(ns.state.claims) do
		local b = c.bounty
		if b.winner == c then
			local unpaid = (c.paid or 0) < b.reward and (c.recv or 0) < b.reward
			if unpaid and b.poster == ns.me.name and c.hunter == partner then owed[#owed + 1] = c end
			if (c.recv or 0) < b.reward and c.hunter == ns.me.name and b.poster == partner then owing[#owing + 1] = c end
		end
	end
	table.sort(owed, function(x, y) return x.kt < y.kt end)
	table.sort(owing, function(x, y) return x.kt < y.kt end)

	local function allocate(list, amount, kind)
		local recorded = 0
		for i, c in ipairs(list) do
			if amount <= 0 then break end
			local due = c.bounty.reward
			local m = (i == #list) and amount or math.min(amount, due)
			if not ns.Ledger.Append(kind, { c = c.id, m = m }) then break end
			amount = amount - m
			recorded = recorded + 1
		end
		return recorded
	end

	local paid = give > 0 and allocate(owed, give, "PAY") or 0
	local got = get > 0 and allocate(owing, get, "RECV") or 0
	if paid > 0 then ns.Print("Payment recorded: " .. ns.Money(give) .. " to " .. partner .. ".") end
	if got > 0 then ns.Print("Bounty payment received: " .. ns.Money(get) .. " from " .. partner .. ".") end
end

local function onTradeComplete()
	if not trade or not trade.partner then return end
	local t = trade
	trade = nil
	settle(t.partner, t.give or 0, t.get or 0)
end

-- events ---------------------------------------------------------------------

local f = CreateFrame("Frame")
for _, ev in ipairs({
	"PARTY_KILL", "CHAT_MSG_SYSTEM", "TRADE_SHOW", "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE",
	"TRADE_CLOSED", "UI_INFO_MESSAGE",
}) do
	pcall(f.RegisterEvent, f, ev)
end

f:SetScript("OnEvent", function(_, event, ...)
	if event == "PARTY_KILL" then
		onPartyKill(...)
	elseif event == "CHAT_MSG_SYSTEM" then
		onSystemMessage(...)
	elseif event == "TRADE_SHOW" then
		trade = { partner = ns.UnitFullName("NPC"), give = 0, get = 0 }
	elseif event == "TRADE_MONEY_CHANGED" or event == "TRADE_ACCEPT_UPDATE" then
		snapshotTrade()
	elseif event == "UI_INFO_MESSAGE" then
		for i = 1, select("#", ...) do
			if select(i, ...) == ERR_TRADE_COMPLETE then onTradeComplete() break end
		end
	elseif event == "TRADE_CLOSED" then
		-- TRADE_CLOSED also fires on completion, right before or after the info message.
		local closing = trade
		C_Timer.After(1, function()
			if trade == closing then trade = nil end
		end)
	end
end)
