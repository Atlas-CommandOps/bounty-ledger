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
local KINDS = { POST = true, CANCEL = true, CLAIM = true, COSIGN = true, PAY = true, RECV = true, DISPUTE = true }
local MAX_SYNC_SEND = 400

-- Runtime index of entry timestamps per author, for the hourly rate limit. Rebuilt on login.
local authorTimes = {}

local function indexAdd(e)
	local list = authorTimes[e.a]
	if not list then
		list = {}
		authorTimes[e.a] = list
	end
	list[#list + 1] = e.t
end

function Ledger.ReindexAuthors()
	authorTimes = {}
	for _, e in pairs(ns.world.entries) do indexAdd(e) end
end

-- How many entries this author has within an hour either side of t.
function Ledger.AuthorRate(author, t)
	local n = 0
	for _, et in ipairs(authorTimes[author] or {}) do
		if math.abs(et - t) < 3600 then n = n + 1 end
	end
	return n
end

local function validate(e)
	for _, k in ipairs(REQUIRED) do
		if e[k] == nil then return "missing " .. k end
	end
	if not KINDS[e.k] then return "unknown kind" end
	if e.n < 1 or e.n ~= math.floor(e.n) then return "bad number" end
	for k, v in pairs(e) do
		if NUMERIC[k] and type(v) ~= "number" then return "bad " .. k end
		if type(v) == "string" and #v > ns.MAX_FIELD then return "field too long" end
	end
	if #ns.Encode(e) > ns.MAX_ENTRY_BYTES then return "entry too large" end
	local now = ns.Now()
	if e.t > now + ns.MAX_FUTURE_SKEW then return "from the future" end
	if e.t < now - ns.PRUNE_AGE then return "too old" end
end

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

-- Write an entry authored by me and broadcast it. Returns nil if I'm over the hourly limit,
-- since every other client would reject the entry anyway.
function Ledger.Append(kind, data)
	local w, me = ns.world, ns.me.name
	if Ledger.AuthorRate(me, ns.Now()) >= ns.MAX_PER_AUTHOR_HOUR then
		ns.Print("You've hit the limit of " .. ns.MAX_PER_AUTHOR_HOUR .. " ledger records an hour. Try again later.")
		return nil
	end
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
	indexAdd(e)
	ns.Comm.Broadcast("E", ns.Encode(e))
	changed()
	return e
end

-- Accept an entry from the network. direct = heard live, so the sender must be the author.
function Ledger.Receive(e, sender, direct)
	normalize(e)
	local invalid = validate(e)
	if invalid then return false, invalid end
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

	if Ledger.AuthorRate(e.a, e.t) >= ns.MAX_PER_AUTHOR_HOUR then return false, "rate limit" end

	w.entries[id] = e
	indexAdd(e)
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

local function drop(id)
	ns.world.entries[id] = nil
	ns.world.verified[id] = nil
end

function Ledger.Prune()
	local w, cutoff = ns.world, ns.Now() - ns.PRUNE_AGE
	for id, e in pairs(w.entries) do
		if e.t < cutoff and e.a ~= ns.me.name then drop(id) end
	end
	Ledger.ReindexAuthors()
end

-- Size cap. When the ledger grows past MAX_ENTRIES, drop the oldest history that no longer
-- matters, down to 90% of the cap. Kept: my own entries, everything about open bounties, and
-- claims that are still unpaid, overdue or disputed (they are the evidence behind reputations).
function Ledger.Compact()
	local w = ns.world
	local count = 0
	for _ in pairs(w.entries) do count = count + 1 end
	if count <= ns.MAX_ENTRIES then return 0 end

	local keep = {}
	for id, b in pairs(ns.state.bounties) do
		if b.status == "open" then keep[id] = true end
	end
	local liveClaims = {}
	for id, c in pairs(ns.state.claims) do
		local s = c.status
		if keep[c.bounty.id] or s == "unpaid" or s == "overdue" or s == "disputed" then
			keep[id] = true
			keep[c.bounty.id] = true
			liveClaims[id] = true
		end
	end

	local candidates = {}
	for id, e in pairs(w.entries) do
		local protected = keep[id] or e.a == ns.me.name
			or (e.k == "CLAIM" and keep[e.b])
			or ((e.k == "PAY" or e.k == "RECV" or e.k == "DISPUTE") and liveClaims[e.c])
		if not protected then candidates[#candidates + 1] = e end
	end
	table.sort(candidates, function(x, y) return x.t < y.t end)

	local target, removed = math.floor(ns.MAX_ENTRIES * 0.9), 0
	for _, e in ipairs(candidates) do
		if count <= target then break end
		drop(Ledger.Id(e))
		count = count - 1
		removed = removed + 1
	end
	if removed > 0 then
		Ledger.ReindexAuthors()
		ns.Debug("compacted ledger, dropped", removed)
		changed()
	end
	return removed
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
	if head then
		ns.Comm.Broadcast("H", ns.Encode({ n = head.n, h = head.h, v = ns.VERSION }))
	else
		ns.Comm.Broadcast("H", ns.Encode({ v = ns.VERSION }))
	end
end

local lastServed = {}

local function onSyncRequest(since, requester)
	local now = ns.Now()
	if lastServed[requester] and now - lastServed[requester] < ns.SYNC_SERVE_COOLDOWN then return end
	local list = {}
	for _, e in pairs(ns.world.entries) do
		if e.t > since then list[#list + 1] = e end
	end
	if #list == 0 then return end
	table.sort(list, function(x, y) return x.t > y.t end)
	if pendingOffers[requester] then return end
	pendingOffers[requester] = C_Timer.NewTimer(2 + math.random() * 8, function()
		pendingOffers[requester] = nil
		lastServed[requester] = ns.Now()
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
		if d.n and d.h then Ledger.ConfirmHead(sender, tonumber(d.n), d.h) end
		if d.v and ns.VersionNewer(d.v, ns.VERSION) then ns.Fire("NEWER_VERSION", d.v) end
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

ns.On("STATE_CHANGED", function() Ledger.Compact() end)

ns.On("READY", function()
	Ledger.Prune()
	changed()
	C_Timer.After(12, Ledger.RequestSync)
	C_Timer.After(40, Ledger.AnnounceHead)
	C_Timer.NewTicker(900, Ledger.AnnounceHead)
end)
