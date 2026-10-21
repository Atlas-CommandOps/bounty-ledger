-- BountyProbe: answers the questions the bounty addon design depends on.
-- Every result prints to chat and is appended to BountyProbeLog (written on /reload or logout).
-- Commands: /bprobe env | comms | target | where | plates | banner | dump | clear

local ADDON = ...
local PREFIX = "BntyProbe"
local CHANNEL_NAME = "bntyprobe"

local function isSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end

local function safe(v)
	if isSecret(v) then return "<SECRET>" end
	if v == nil then return "nil" end
	local ok, s = pcall(tostring, v)
	return ok and s or "<tostring failed>"
end

local function join(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = safe((select(i, ...))) end
	return table.concat(parts, " | ")
end

local function log(tag, ...)
	local line = "[" .. tag .. "] " .. join(...)
	print("|cffff5555BountyProbe|r " .. line)
	BountyProbeLog = BountyProbeLog or { entries = {} }
	table.insert(BountyProbeLog.entries, date("%Y-%m-%d %H:%M:%S") .. " " .. line)
end

local f = CreateFrame("Frame")

local function tryRegister(event)
	local ok, err = pcall(f.RegisterEvent, f, event)
	log("register", event, ok and "OK" or ("FAIL: " .. safe(err)))
end

local function guidInfo(guid)
	if guid == nil or isSecret(guid) or not GetPlayerInfoByGUID then return "n/a" end
	local ok, class, _, race, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
	if not ok then return "GetPlayerInfoByGUID failed" end
	return join(name, realm, race, class)
end

local function fullNames(unit)
	-- Forever names are "First Last"; find which API returns the part that makes them unique.
	local n1, n2 = UnitName(unit)
	local f1, f2 = UnitFullName(unit)
	local g = GetUnitName and GetUnitName(unit, true)
	return join("UnitName", n1, n2, "UnitFullName", f1, f2, "GetUnitName", g)
end

-- env -----------------------------------------------------------------------

local function probeEnv()
	local version, build, _, iface = GetBuildInfo()
	log("env", "build", version, build, "interface", iface, "WOW_PROJECT_ID", WOW_PROJECT_ID)
	local globals = {
		"issecretvalue", "CombatLogGetCurrentEventInfo", "C_DeathRecap", "JoinTemporaryChannel",
		"GetPlayerInfoByGUID", "GetPVPSessionStats", "GetPVPLifetimeStats", "UnitIsPVP",
	}
	for _, name in ipairs(globals) do log("env", name, _G[name] ~= nil and "present" or "MISSING") end
	log("env", "C_ChatInfo.SendAddonMessage", C_ChatInfo and C_ChatInfo.SendAddonMessage and "present" or "MISSING")
	log("env", "C_Map.GetPlayerMapPosition", C_Map and C_Map.GetPlayerMapPosition and "present" or "MISSING")
end

-- comms ---------------------------------------------------------------------

local function send(chatType, target)
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, "ping " .. chatType .. " " .. time(), chatType, target)
	log("send", chatType, safe(target), ok and ("returned " .. safe(result)) or ("ERROR " .. safe(result)))
end

local function probeComms()
	log("comms", "RegisterAddonMessagePrefix", C_ChatInfo.RegisterAddonMessagePrefix(PREFIX))

	local name, realm = UnitFullName("player")
	send("WHISPER", realm and realm ~= "" and (name .. "-" .. realm) or name)
	send("SAY")
	send("YELL")
	if IsInGuild() then send("GUILD") else log("comms", "GUILD skipped (no guild)") end
	if IsInGroup() then send("PARTY") else log("comms", "PARTY skipped (not grouped)") end

	-- The core question: can a hidden custom channel carry addon traffic on Forever?
	local okJoin, err = pcall(JoinTemporaryChannel, CHANNEL_NAME)
	log("comms", "JoinTemporaryChannel", okJoin and "called" or ("ERROR " .. safe(err)))
	C_Timer.After(2, function()
		local id = GetChannelName(CHANNEL_NAME)
		log("comms", "channel id", id)
		if id and id > 0 then send("CHANNEL", id) end
		log("comms", "done; CHAT_MSG_ADDON lines above/below show what actually arrived")
	end)
end

-- target / where / plates ---------------------------------------------------

local function probeTarget()
	if not UnitExists("target") then log("target", "no target") return end
	local guid = UnitGUID("target")
	log("target", "name", UnitName("target"), "guid", guid, "player", UnitIsPlayer("target"),
		"faction", UnitFactionGroup("target"), "level", UnitLevel("target"),
		"health", UnitHealth("target"), "dead", UnitIsDead("target"))
	log("target", "byGUID", guidInfo(guid))
	log("target", "names", fullNames("target"))
end

local function probeWhere()
	local mapID = C_Map.GetBestMapForUnit("player")
	local pos = "n/a"
	if mapID then
		local ok, p = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
		if ok and p then pos = join(p.x, p.y) elseif not ok then pos = "ERROR " .. safe(p) end
	end
	log("where", "zone", GetZoneText(), "subzone", GetSubZoneText(), "mapID", mapID, "pos", pos,
		"pvpFlagged", UnitIsPVP("player"))
end

local function probePlates()
	local myFaction = UnitFactionGroup("player")
	local total, enemies = 0, 0
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if UnitExists(unit) then
			total = total + 1
			if UnitIsPlayer(unit) and UnitFactionGroup(unit) ~= myFaction then
				enemies = enemies + 1
				log("plates", unit, fullNames(unit), UnitGUID(unit))
			end
		end
	end
	log("plates", "visible", total, "enemy players", enemies)
end

-- banner: can we draw the clip moment, including a possibly-secret name? ------

local banner
local function showBanner()
	if not banner then
		banner = CreateFrame("Frame", nil, UIParent)
		banner:SetSize(900, 140)
		banner:SetPoint("TOP", 0, -160)
		banner.bg = banner:CreateTexture(nil, "BACKGROUND")
		banner.bg:SetAllPoints()
		banner.bg:SetColorTexture(0, 0, 0, 0.7)
		banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
		banner.title:SetPoint("TOP", 0, -20)
		banner.title:SetText("BOUNTY CLAIMED")
		banner.title:SetTextColor(1, 0.2, 0.2)
		banner.sub = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
		banner.sub:SetPoint("TOP", banner.title, "BOTTOM", 0, -16)
	end
	-- SetText is allowed to take a secret string; this shows whether it renders.
	banner.sub:SetText(UnitExists("target") and UnitName("target") or "Test Hunter")
	banner:Show()
	PlaySound(SOUNDKIT.RAID_WARNING)
	C_Timer.After(5, function() banner:Hide() end)
	log("banner", "shown")
end

-- events --------------------------------------------------------------------

local handlers = {}

function handlers.ADDON_LOADED(name)
	if name ~= ADDON then return end
	BountyProbeLog = BountyProbeLog or { entries = {} }
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	for _, ev in ipairs({
		"CHAT_MSG_ADDON", "PARTY_KILL", "PLAYER_DEAD", "PLAYER_TARGET_DIED", "UNIT_DIED",
		"CHAT_MSG_COMBAT_HONOR_GAIN", "PLAYER_PVP_KILLS_CHANGED", "ZONE_CHANGED_NEW_AREA",
		"COMBAT_LOG_EVENT_UNFILTERED", "CHAT_MSG_SYSTEM", "CHAT_MSG_COMBAT_MISC_INFO",
	}) do tryRegister(ev) end
end

function handlers.CHAT_MSG_ADDON(prefix, text, channel, sender)
	if prefix ~= PREFIX then return end
	log("recv", channel, sender, text)
end

function handlers.PARTY_KILL(attackerGUID, targetGUID)
	log("PARTY_KILL", "attacker", attackerGUID, guidInfo(attackerGUID), "target", targetGUID, guidInfo(targetGUID))
end

-- Victim side, path 1: the death recap. Run 1 tried ids 1-5 and found nothing, so scan wide
-- and also catch the recap id from any "|Hdeath:N|h" chat link the client prints on death.
local function readRecap(id, how)
	local ok, events = pcall(C_DeathRecap.GetRecapEvents, id)
	if not ok then log("deathrecap", how, "id", id, "ERROR", events) return false end
	if type(events) ~= "table" or #events == 0 then return false end
	log("deathrecap", how, "id", id, "events", #events)
	for i, e in ipairs(events) do
		log("deathrecap", "event", i, "source", e.sourceName, "spell", e.spellName, "amount", e.amount,
			"overkill", e.overkill, "school", e.school)
	end
	return true
end

local function scanRecaps()
	if not C_DeathRecap then log("deathrecap", "C_DeathRecap missing") return end
	for id = 1, 500 do
		local okHas, has = pcall(C_DeathRecap.HasRecapEvents, id)
		if okHas and has and readRecap(id, "scan") then return end
	end
	log("deathrecap", "scan 1-500 found nothing")
end

-- Victim side, path 2: suspects. Who was targeting me, and who was I targeting, when I died?
local function logSuspects()
	local myFaction = UnitFactionGroup("player")
	local found = 0
	local function check(unit, why)
		if UnitExists(unit) and UnitIsPlayer(unit) and UnitFactionGroup(unit) ~= myFaction then
			found = found + 1
			log("suspect", why, GetUnitName(unit, true), UnitGUID(unit))
		end
	end
	check("target", "my target")
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if UnitExists(unit) and UnitIsUnit(unit .. "target", "player") then check(unit, "was targeting me") end
	end
	log("suspect", "total", found)
end

function handlers.PLAYER_DEAD()
	log("PLAYER_DEAD", "zone", GetZoneText())
	local ok, err = pcall(logSuspects)
	if not ok then log("suspect", "ERROR", err) end
	C_Timer.After(1, scanRecaps)
end

local function scanChatForRecap(event, text)
	if type(text) ~= "string" or isSecret(text) then return end
	local id = text:match("|Hdeath:(%d+)|h")
	if id then
		log("deathrecap", "chat link in", event, "id", id)
		readRecap(tonumber(id), "chatlink")
	end
end
for _, ev in ipairs({ "CHAT_MSG_SYSTEM", "CHAT_MSG_COMBAT_MISC_INFO" }) do
	handlers[ev] = function(text) scanChatForRecap(ev, text) end
end

function handlers.PLAYER_TARGET_DIED() log("PLAYER_TARGET_DIED", fullNames("target"), UnitGUID("target")) end
function handlers.UNIT_DIED(...) log("UNIT_DIED", ...) end
function handlers.CHAT_MSG_COMBAT_HONOR_GAIN(text) log("HONOR_GAIN", text) end

function handlers.PLAYER_PVP_KILLS_CHANGED()
	if GetPVPSessionStats then log("PVP_KILLS_CHANGED", "session", GetPVPSessionStats()) else log("PVP_KILLS_CHANGED") end
end

function handlers.ZONE_CHANGED_NEW_AREA() probeWhere() end
function handlers.COMBAT_LOG_EVENT_UNFILTERED()
	local ok, _, sub = pcall(CombatLogGetCurrentEventInfo)
	if ok and sub == "PARTY_KILL" then log("CLEU", "PARTY_KILL fired via combat log") end
end

f:SetScript("OnEvent", function(_, event, ...)
	local h = handlers[event]
	if h then h(...) else log("event", event, ...) end
end)
f:RegisterEvent("ADDON_LOADED")

-- slash ---------------------------------------------------------------------

SLASH_BOUNTYPROBE1 = "/bprobe"
SlashCmdList.BOUNTYPROBE = function(msg)
	local cmd = strtrim(msg or ""):lower()
	if cmd == "env" then probeEnv()
	elseif cmd == "comms" then probeComms()
	elseif cmd == "target" then probeTarget()
	elseif cmd == "where" then probeWhere()
	elseif cmd == "plates" then probePlates()
	elseif cmd == "banner" then showBanner()
	elseif cmd:match("^whisper ") then
		-- Cross-faction check: whisper an enemy-faction character; the other side runs the probe and watches for a recv line.
		C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
		send("WHISPER", strtrim(msg):match("^%S+%s+(.+)$"))
	elseif cmd == "dump" then for _, line in ipairs(BountyProbeLog.entries) do print(line) end
	elseif cmd == "clear" then BountyProbeLog.entries = {} print("BountyProbe log cleared")
	else print("BountyProbe: /bprobe env | comms | target | where | plates | banner | whisper <Name> | dump | clear") end
end
