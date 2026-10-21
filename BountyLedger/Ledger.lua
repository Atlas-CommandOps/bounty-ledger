-- The ledger: an append-only record every client keeps a copy of.
--
-- Each player's entries form their own hash chain: entry n carries the hash of entry n-1.
-- WoW stamps the real sender on every addon message, so an entry heard live from its author
-- is "verified". Entries relayed by other peers during sync are accepted but unverified
-- until the author's own HEAD message confirms the chain they belong to. Two different
-- entries with the same author and number are a fork, and the author is flagged.
local _, ns = ...

local Ledger = {}
ns.Ledger = Ledger

local NUMERIC = { n = true, t = true, r = true, m = true, kt = true, tl = true }
local REQUIRED = { "a", "n", "t", "k", "p", "h" }
local MAX_SYNC_SEND = 400

local function normalize(e)
	for k in pairs(NUMERIC) do
		if e[k] ~= nil then e[k] = tonumber(e[k]) end
	end
	return e
end

function Ledger.Id(e)
	return e.a .. "#" .. e.n
end

function Ledger.Hash(e)
	local copy = {}
	for k, v in pairs(e) do
		if k ~= "h" then copy[k] = v end
	end
	return ns.Sha256(ns.Encode(copy)):sub(1, 32)
end

local changeQueued = false
local function changed()
	if changeQueued then return end
	changeQueued = true
	C_Timer.After(0.3, function()
		changeQueued = false
		ns.Fire("LEDGER_CHANGED")
	end)
end

-- Write an entry authored by me and broadcast it.
function Ledger.Append(kind, data)
	local w, me = ns.world, ns.me.name
	local head = w.heads[me]
	local e = {}
	for k, v in pairs(data) do e[k] = v end
	e.k = kind
	e.a = me
	e.n = (head and head.n or 0) + 1
	e.t = ns.Now()
	e.p = head and head.h or "-"
	e.h = Ledger.Hash(e)
	local id = Ledger.Id(e)
	w.entries[id] = e
	w.verified[id] = true
	w.heads[me] = { n = e.n, h = e.h }
	ns.Comm.Broadcast("E", ns.Encode(e))
	changed()
	return e
end

-- Accept an entry from the network. direct = heard live, so the sender must be the author.
function Ledger.Receive(e, sender, direct)
	normalize(e)
	for _, k in ipairs(REQUIRED) do
		if e[k] == nil then return false, "missing " .. k end
	end
	if Ledger.Hash(e) ~= e.h then return false, "bad hash" end
	if direct and sender ~= e.a then return false, "spoofed author" end

	local w = ns.world
	local id = Ledger.Id(e)
	local existing = w.entries[id]
	if existing then
		if existing.h ~= e.h then
			w.forks[e.a] = true
			changed()
			return false, "fork"
		end
		if direct and not w.verified[id] then
			w.verified[id] = true
			changed()
		end
		return false, "duplicate"
	end

	w.entries[id] = e
	if direct then w.verified[id] = true end
	local head = w.heads[e.a]
	if not head or e.n > head.n then w.heads[e.a] = { n = e.n, h = e.h } end
	local prev = w.entries[e.a .. "#" .. (e.n - 1)]
	if prev and prev.h ~= e.p then w.forks[e.a] = true end
	local nextE = w.entries[e.a .. "#" .. (e.n + 1)]
	if nextE and nextE.p ~= e.h then w.forks[e.a] = true end
	changed()
	return true
end

-- The author's own HEAD confirms their whole chain back through intact prev links.
function Ledger.ConfirmHead(author, n, h)
	local w = ns.world
	local e = w.entries[author .. "#" .. n]
	if not e then return end
	if e.h ~= h then
		w.forks[author] = true
		changed()
		return
	end
	local any = false
	while e do
		local id = Ledger.Id(e)
		if not w.verified[id] then
			w.verified[id] = true
			any = true
		end
		if e.n <= 1 then break end
		local prev = w.entries[author .. "#" .. (e.n - 1)]
		if not prev or prev.h ~= e.p then break end
		e = prev
	end
	if any then changed() end
end

function Ledger.Prune()
	local w, cutoff = ns.world, ns.Now() - ns.PRUNE_AGE
	for id, e in pairs(w.entries) do
		if e.t < cutoff and e.a ~= ns.me.name then
			w.entries[id] = nil
			w.verified[id] = nil
		end
	end
end

-- sync -----------------------------------------------------------------------
-- On login a client asks the channel for entries newer than what it has. Each peer that can
-- help waits a random moment; the first to answer announces it, the rest stand down, and the
-- answer goes by whisper (whispers are exempt from the channel throttle).

local pendingOffers = {}

function Ledger.RequestSync()
	local newest = 0
	for _, e in pairs(ns.world.entries) do
		if e.t > newest then newest = e.t end
	end
	local since = math.max(0, newest - 3600)
	ns.Comm.Broadcast("Q", ns.Encode({ s = since }))
end

function Ledger.AnnounceHead()
	local head = ns.world.heads[ns.me.name]
	if head then ns.Comm.Broadcast("H", ns.Encode({ n = head.n, h = head.h })) end
end

local function onSyncRequest(since, requester)
	local list = {}
	for _, e in pairs(ns.world.entries) do
		if e.t > since then list[#list + 1] = e end
	end
	if #list == 0 then return end
	table.sort(list, function(x, y) return x.t > y.t end)
	pendingOffers[requester] = C_Timer.NewTimer(2 + math.random() * 8, function()
		pendingOffers[requester] = nil
		ns.Comm.Broadcast("O", ns.Encode({ r = requester }))
		for i = math.min(#list, MAX_SYNC_SEND), 1, -1 do
			ns.Comm.Whisper(requester, "S", ns.Encode(list[i]))
		end
		ns.Debug("synced", math.min(#list, MAX_SYNC_SEND), "entries to", requester)
	end)
end

ns.On("COMM", function(kind, payload, sender)
	if not ns.world then return end
	local me = ns.me.name
	if kind == "E" then
		if sender ~= me then Ledger.Receive(ns.Decode(payload), sender, true) end
	elseif kind == "S" then
		Ledger.Receive(ns.Decode(payload), sender, false)
	elseif kind == "H" then
		local d = ns.Decode(payload)
		Ledger.ConfirmHead(sender, tonumber(d.n), d.h)
	elseif kind == "Q" then
		if sender ~= me then onSyncRequest(tonumber(ns.Decode(payload).s) or 0, sender) end
	elseif kind == "O" then
		local target = ns.Decode(payload).r
		local timer = target and pendingOffers[target]
		if timer and sender ~= me then
			timer:Cancel()
			pendingOffers[target] = nil
		end
	end
end)

ns.On("READY", function()
	Ledger.Prune()
	changed()
	C_Timer.After(12, Ledger.RequestSync)
	C_Timer.After(40, Ledger.AnnounceHead)
	C_Timer.NewTicker(900, Ledger.AnnounceHead)
end)
