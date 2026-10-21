-- Bounty Ledger: shared namespace, constants, saved variables and a tiny event bus.
local ADDON, ns = ...

ns.VERSION = "0.1.1"
ns.PREFIX = "BntyLdgr"
ns.CHANNEL = "BountyLedgerFV"

ns.BOUNTY_TTL = 7 * 86400        -- a bounty stays open this long
ns.PRUNE_AGE = 30 * 86400        -- ledger entries older than this are dropped on login
ns.OVERDUE_AFTER = 48 * 3600     -- an unpaid claim is flagged overdue after this
ns.COSIGN_WINDOW = 15            -- seconds between a claim and a groupmate's matching kill
ns.MAX_OPEN_PER_POSTER = 5
ns.MIN_REWARD = 10000            -- 1 gold, in copper

-- event bus ------------------------------------------------------------------

local listeners = {}

function ns.On(event, fn)
	listeners[event] = listeners[event] or {}
	table.insert(listeners[event], fn)
end

function ns.Fire(event, ...)
	for _, fn in ipairs(listeners[event] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then ns.Debug("handler error", event, err) end
	end
end

-- helpers --------------------------------------------------------------------

function ns.IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end

function ns.Print(...)
	print("|cffd4af37Bounty Ledger|r", ...)
end

function ns.Debug(...)
	if not (ns.db and ns.db.settings.debug) then return end
	local parts = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		parts[#parts + 1] = ns.IsSecret(v) and "<secret>" or tostring(v)
	end
	print("|cff888888BL|r", table.concat(parts, " "))
end

function ns.Now()
	return GetServerTime()
end

-- Forever names are "First Last". UnitName returns them as two values, chat senders arrive
-- as "First Last", whisper targets need "First-Last". Canonical form is "First Last".
function ns.JoinName(first, last)
	if type(first) ~= "string" or ns.IsSecret(first) or ns.IsSecret(last) then return nil end
	if type(last) == "string" and last ~= "" then return first .. " " .. last end
	return first
end

function ns.UnitFullName(unit)
	return ns.JoinName(UnitName(unit))
end

function ns.Canon(name)
	if type(name) ~= "string" or ns.IsSecret(name) or name == "" then return nil end
	return (name:gsub("%-", " ", 1))
end

function ns.NameKey(name)
	return name and name:lower() or nil
end

function ns.WhisperTarget(name)
	return (name:gsub(" ", "-", 1))
end

function ns.Money(copper)
	copper = math.floor(copper or 0)
	if GetCoinTextureString then return GetCoinTextureString(copper) end
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then return g .. "g" end
	if s > 0 then return s .. "s" end
	return c .. "c"
end

function ns.Ago(t)
	local d = math.max(0, ns.Now() - t)
	if d < 3600 then return math.floor(d / 60) .. "m" end
	if d < 86400 then return math.floor(d / 3600) .. "h" end
	return math.floor(d / 86400) .. "d"
end

function ns.InOpenWorld()
	local inInstance = IsInInstance()
	return not inInstance
end

-- saved variables ------------------------------------------------------------
-- One ledger per world (ruleset) and faction: addon traffic never crosses factions.

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		BountyLedgerDB = BountyLedgerDB or {}
		local db = BountyLedgerDB
		db.worlds = db.worlds or {}
		db.settings = db.settings or {}
		if db.settings.toasts == nil then db.settings.toasts = true end
		if db.settings.sound == nil then db.settings.sound = true end
		ns.db = db
	elseif event == "PLAYER_LOGIN" then
		ns.me = {
			guid = UnitGUID("player"),
			name = ns.UnitFullName("player"),
			faction = UnitFactionGroup("player"),
		}
		local key = tostring(GetRealmName()) .. ":" .. tostring(ns.me.faction)
		local w = ns.db.worlds[key] or {}
		ns.db.worlds[key] = w
		w.entries = w.entries or {}
		w.heads = w.heads or {}
		w.verified = w.verified or {}
		w.forks = w.forks or {}
		w.deaths = w.deaths or {}
		w.notified = w.notified or {}
		ns.world = w
		ns.Fire("READY")
	end
end)
