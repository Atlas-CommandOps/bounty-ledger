-- Bounty state, rebuilt from the ledger every time it changes. Nothing here is stored: the
-- ledger is the only source of truth, so every client that holds the same entries computes
-- the same board, the same claim winners and the same reputations.
--
-- Entry kinds:
--   POST    tn tid tr tc tl r note   a bounty on an enemy player (r = reward in copper)
--   CANCEL  b                        poster withdraws an open bounty
--   CLAIM   b tid tn kt z            hunter's client saw their killing blow on the target
--   COSIGN  tid tn hn kt             a groupmate's client saw the same kill
--   PAY     c m                      poster's client saw the trade that paid the hunter
--   RECV    c m                      hunter's client saw the same trade from their side
--   DISPUTE c why                    poster contests a claim
local _, ns = ...

local Bounties = {}
ns.Bounties = Bounties

ns.state = { bounties = {}, claims = {}, rep = {}, openByGuid = {}, openByName = {} }

local KIND_ORDER = { POST = 1, CANCEL = 2, CLAIM = 3, COSIGN = 4, PAY = 5, RECV = 5, DISPUTE = 6 }

local function rep(name)
	local r = ns.state.rep[name]
	if not r then
		r = { name = name, posted = 0, paid = 0, overdue = 0, disputes = 0, claims = 0, collected = 0 }
		ns.state.rep[name] = r
	end
	return r
end

local function targetMatches(bounty, tid, tn)
	if bounty.tid and tid then return bounty.tid == tid end
	return ns.NameKey(bounty.tn) == ns.NameKey(tn)
end

function Bounties.Rebuild()
	local now = ns.Now()
	local w = ns.world
	local list = {}
	for id, e in pairs(w.entries) do list[#list + 1] = e end
	-- Time order, with entries from the same second ordered by kind so a bounty always exists
	-- before claims on it, and claims before payments that reference them.
	table.sort(list, function(x, y)
		if x.t ~= y.t then return x.t < y.t end
		local rx, ry = KIND_ORDER[x.k] or 9, KIND_ORDER[y.k] or 9
		if rx ~= ry then return rx < ry end
		if x.a ~= y.a then return x.a < y.a end
		return x.n < y.n
	end)

	local bounties, claims, cosigns = {}, {}, {}
	ns.state.rep = {}
	local openCount = {}

	for _, e in ipairs(list) do
		local id = e.a .. "#" .. e.n
		local verified = w.verified[id] == true
		if e.k == "POST" and e.tn and e.r and e.r >= ns.MIN_REWARD and e.a ~= e.tn then
			openCount[e.a] = (openCount[e.a] or 0) + 1
			if openCount[e.a] <= ns.MAX_OPEN_PER_POSTER then
				bounties[id] = {
					id = id, poster = e.a, tn = e.tn, tid = e.tid, race = e.tr, class = e.tc, level = e.tl,
					reward = e.r, note = e.note, t = e.t, expires = e.t + ns.BOUNTY_TTL,
					status = "open", claims = {}, verified = verified,
				}
				rep(e.a).posted = rep(e.a).posted + 1
			end
		elseif e.k == "CANCEL" then
			local b = bounties[e.b]
			if b and b.poster == e.a and b.status == "open" then
				b.status = "cancelled"
				b.closedAt = e.t
				openCount[e.a] = openCount[e.a] - 1
			end
		elseif e.k == "CLAIM" then
			local b = bounties[e.b]
			if b and e.a ~= b.poster and e.kt and e.kt >= b.t and e.kt <= b.expires
				and not (b.closedAt and b.closedAt < e.kt) and targetMatches(b, e.tid, e.tn) then
				local c = {
					id = id, bounty = b, hunter = e.a, kt = e.kt, zone = e.z, tid = e.tid, tn = e.tn,
					cosigners = {}, verified = verified, status = "unpaid",
				}
				claims[id] = c
				table.insert(b.claims, c)
				if not b.winner then
					if b.status == "open" then openCount[b.poster] = openCount[b.poster] - 1 end
					b.winner = c
					b.status = "claimed"
				end
			end
		elseif e.k == "COSIGN" then
			table.insert(cosigns, e)
		elseif e.k == "PAY" then
			local c = claims[e.c]
			if c and c.bounty.poster == e.a then c.paid = (c.paid or 0) + (e.m or 0) end
		elseif e.k == "RECV" then
			local c = claims[e.c]
			if c and c.hunter == e.a then c.recv = (c.recv or 0) + (e.m or 0) end
		elseif e.k == "DISPUTE" then
			local c = claims[e.c]
			if c and c.bounty.poster == e.a then c.disputed = e.why or "disputed" end
		end
	end

	for _, s in ipairs(cosigns) do
		for _, c in pairs(claims) do
			if c.hunter == s.hn and s.a ~= c.hunter and math.abs((s.kt or 0) - c.kt) <= ns.COSIGN_WINDOW
				and (c.tid and s.tid and c.tid == s.tid or ns.NameKey(c.tn) == ns.NameKey(s.tn)) then
				c.cosigners[s.a] = true
			end
		end
	end

	-- Only the winning claim of each bounty is owed. A hunter's own RECV is the strongest
	-- proof of payment (they have no reason to lie about being paid); PAY + RECV is verified.
	for _, c in pairs(claims) do
		local b = c.bounty
		if b.winner == c then
			if c.disputed then
				c.status = "disputed"
			elseif (c.paid or 0) >= b.reward and (c.recv or 0) >= b.reward then
				c.status = "verified"
			elseif (c.recv or 0) >= b.reward then
				c.status = "received"
			elseif (c.paid or 0) >= b.reward then
				c.status = "paid"
			elseif now - c.kt > ns.OVERDUE_AFTER then
				c.status = "overdue"
			else
				c.status = "unpaid"
			end
			local pr, hr = rep(b.poster), rep(c.hunter)
			hr.claims = hr.claims + 1
			if c.status == "verified" or c.status == "received" or c.status == "paid" then
				pr.paid = pr.paid + 1
				hr.collected = hr.collected + 1
			elseif c.status == "overdue" then
				pr.overdue = pr.overdue + 1
			elseif c.status == "disputed" then
				pr.disputes = pr.disputes + 1
			end
		else
			c.status = "late"
		end
	end

	local openByGuid, openByName = {}, {}
	for _, b in pairs(bounties) do
		if b.status == "open" and now > b.expires then b.status = "expired" end
		if b.status == "open" then
			if b.tid then
				openByGuid[b.tid] = openByGuid[b.tid] or {}
				table.insert(openByGuid[b.tid], b)
			end
			local key = ns.NameKey(b.tn)
			openByName[key] = openByName[key] or {}
			table.insert(openByName[key], b)
		end
	end

	ns.state.bounties = bounties
	ns.state.claims = claims
	ns.state.openByGuid = openByGuid
	ns.state.openByName = openByName
	ns.Fire("STATE_CHANGED")
end

-- Open bounties on a player, by GUID when known, otherwise by full name.
function Bounties.OpenOn(guid, name)
	local found, seen = {}, {}
	for _, b in ipairs((guid and ns.state.openByGuid[guid]) or {}) do
		found[#found + 1] = b
		seen[b.id] = true
	end
	for _, b in ipairs((name and ns.state.openByName[ns.NameKey(name)]) or {}) do
		if not seen[b.id] and (not b.tid or not guid or b.tid == guid) then found[#found + 1] = b end
	end
	return found
end

function Bounties.MyOpenCount()
	local n = 0
	for _, b in pairs(ns.state.bounties) do
		if b.poster == ns.me.name and b.status == "open" then n = n + 1 end
	end
	return n
end

-- actions --------------------------------------------------------------------

function Bounties.Post(spec)
	local name = spec.name and strtrim(spec.name) or ""
	if name == "" then return false, "Enter the target's full name (First Last) or target them." end
	if ns.NameKey(name) == ns.NameKey(ns.me.name) then return false, "You can't post a bounty on yourself." end
	local reward = math.floor(spec.reward or 0)
	if reward < ns.MIN_REWARD then return false, "The minimum reward is " .. ns.Money(ns.MIN_REWARD) .. "." end
	if GetMoney() < reward then return false, "You don't have " .. ns.Money(reward) .. " to pay this bounty." end
	if Bounties.MyOpenCount() >= ns.MAX_OPEN_PER_POSTER then
		return false, "You already have " .. ns.MAX_OPEN_PER_POSTER .. " open bounties."
	end
	local note = spec.note and strtrim(spec.note) or ""
	if #name > ns.MAX_FIELD then return false, "That name is too long." end
	local posted = ns.Ledger.Append("POST", {
		tn = name, tid = spec.guid, tr = spec.race, tc = spec.class, tl = spec.level,
		r = reward, note = note ~= "" and note:sub(1, 80) or nil,
	})
	if not posted then return false, "Not posted: hourly record limit reached." end
	return true
end

function Bounties.Cancel(bountyId)
	ns.Ledger.Append("CANCEL", { b = bountyId })
end

function Bounties.Dispute(claimId, why)
	ns.Ledger.Append("DISPUTE", { c = claimId, why = why or "disputed" })
end

-- Fill a post spec from the current target, if it is an enemy player we can read.
function Bounties.SpecFromTarget()
	if not UnitExists("target") or not UnitIsPlayer("target") then return nil, "Target an enemy player first." end
	if UnitFactionGroup("target") == ns.me.faction then return nil, "Bounties are for enemy-faction players." end
	local guid, name = UnitGUID("target"), ns.UnitFullName("target")
	if ns.IsSecret(guid) or not name then return nil, "That player's identity is hidden here. Try in the open world." end
	local _, classFile = UnitClass("target")
	return { name = name, guid = guid, race = UnitRace("target"), class = classFile, level = UnitLevel("target") }
end

ns.On("LEDGER_CHANGED", Bounties.Rebuild)
