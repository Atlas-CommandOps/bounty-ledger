-- Network: a hidden custom channel every Bounty Ledger user on a faction joins, plus whispers
-- for sync. Messages are chunked to fit 255 bytes and paced under Blizzard's per-prefix
-- throttle (10 burst, 1/sec). Sends are held while in an instance, where they are locked down.
local _, ns = ...

local Comm = {}
ns.Comm = Comm

local CHUNK = 230
local MAX_QUEUE = 600
local RESULT_OK, RESULT_THROTTLE, RESULT_CHANNEL_THROTTLE, RESULT_LOCKDOWN = 0, 3, 8, 11

local queue = {}
local tokens, whisperTokens = 10, 8
local lastRefill = GetTime()
local counter = 0
local partial = {}
local lastJoin = 0

local function channelId()
	local id = GetChannelName(ns.CHANNEL)
	if id and id > 0 then return id end
end

-- Keep the channel out of every chat window. The join completes asynchronously and the client
-- re-adds joined channels to windows, so this runs on every channel notice, not just once.
-- Which removal API exists differs between client versions, so try each one.
function Comm.HideChannel()
	local util = ChatFrameUtil
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i]
		if frame then
			if ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, frame, ns.CHANNEL) end
			if util and util.RemoveChannel then pcall(util.RemoveChannel, frame, ns.CHANNEL) end
			if frame.RemoveChannel then pcall(frame.RemoveChannel, frame, ns.CHANNEL) end
		end
	end
end

local function isOurChannel(...)
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if type(v) == "string" and not ns.IsSecret(v) and v:lower():find(ns.CHANNEL:lower(), 1, true) then return true end
	end
	return false
end

-- Swallow "Joined/Left Channel: BountyLedgerFV" and any other line that names the channel.
local function chatFilter(_, _, ...)
	return isOurChannel(...)
end

local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if addFilter then
	for _, ev in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
		pcall(addFilter, ev, chatFilter)
	end
end

function Comm.ChatApiReport()
	ns.Print("ChatFrame_RemoveChannel", ChatFrame_RemoveChannel and "yes" or "no",
		"| ChatFrameUtil.RemoveChannel", (ChatFrameUtil and ChatFrameUtil.RemoveChannel) and "yes" or "no",
		"| frame:RemoveChannel", (ChatFrame1 and ChatFrame1.RemoveChannel) and "yes" or "no",
		"| message filter", addFilter and "yes" or "no")
end

function Comm.JoinChannel()
	if channelId() or GetTime() - lastJoin < 30 then return end
	lastJoin = GetTime()
	pcall(JoinTemporaryChannel, ns.CHANNEL)
	C_Timer.After(2, Comm.HideChannel)
end

local function enqueue(dist, target, body)
	if #queue >= MAX_QUEUE then ns.Debug("queue full, dropping") return end
	counter = counter + 1
	local id = string.format("%x%02x", counter % 4096, math.random(0, 255))
	local n = math.max(1, math.ceil(#body / CHUNK))
	for i = 1, n do
		local part = body:sub((i - 1) * CHUNK + 1, i * CHUNK)
		queue[#queue + 1] = { dist = dist, target = target, text = id .. ":" .. i .. ":" .. n .. ":" .. part }
	end
end

function Comm.Broadcast(kind, payload)
	enqueue("CHANNEL", nil, kind .. "\30" .. payload)
end

function Comm.Whisper(name, kind, payload)
	enqueue("WHISPER", ns.WhisperTarget(name), kind .. "\30" .. payload)
end

local function pump()
	local now = GetTime()
	local dt = now - lastRefill
	lastRefill = now
	tokens = math.min(10, tokens + dt)
	whisperTokens = math.min(8, whisperTokens + dt * 4)

	for key, p in pairs(partial) do
		if now - p.t > 60 then partial[key] = nil end
	end

	if not ns.InOpenWorld() then return end

	while #queue > 0 do
		local m = queue[1]
		local whisper = m.dist == "WHISPER"
		if whisper and whisperTokens < 1 then return end
		if not whisper and tokens < 1 then return end

		local dist, target = m.dist, m.target
		if dist == "CHANNEL" then
			target = channelId()
			if not target then Comm.JoinChannel() return end
		end

		local ok, result = pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, m.text, dist, target)
		if ok and (result == RESULT_THROTTLE or result == RESULT_CHANNEL_THROTTLE) then
			tokens = 0
			return
		elseif ok and result == RESULT_LOCKDOWN then
			return
		end
		table.remove(queue, 1)
		if whisper then whisperTokens = whisperTokens - 1 else tokens = tokens - 1 end
		if not ok then
			ns.Debug("send error", result)
		elseif result ~= nil and result ~= true and result ~= RESULT_OK then
			ns.Debug("send result", result, dist)
		end
	end
end

local function onAddonMessage(prefix, text, dist, sender)
	if prefix ~= ns.PREFIX or ns.IsSecret(text) or ns.IsSecret(sender) then return end
	local who = ns.Canon(sender)
	if not who then return end
	local id, i, n, part = text:match("^([^:]+):(%d+):(%d+):(.*)$")
	if not id then return end
	i, n = tonumber(i), tonumber(n)
	if n < 1 or n > 40 or i < 1 or i > n then return end

	local body
	if n == 1 then
		body = part
	else
		local key = who .. "/" .. id
		local p = partial[key]
		if not p then
			p = { n = n, got = 0, parts = {}, t = GetTime() }
			partial[key] = p
		end
		if not p.parts[i] then
			p.parts[i] = part
			p.got = p.got + 1
		end
		if p.got < p.n then return end
		partial[key] = nil
		body = table.concat(p.parts)
	end

	local kind, payload = body:match("^(%a)\30(.*)$")
	if kind then ns.Fire("COMM", kind, payload, who, dist) end
end

C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
f:RegisterEvent("CHANNEL_UI_UPDATE")
f:SetScript("OnEvent", function(_, event, ...)
	if event == "CHAT_MSG_ADDON" then
		onAddonMessage(...)
	elseif event == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(5, Comm.JoinChannel)
		C_Timer.After(10, Comm.HideChannel)
	elseif event == "CHANNEL_UI_UPDATE" or isOurChannel(...) then
		Comm.HideChannel()
	end
end)
C_Timer.NewTicker(0.25, pump)
