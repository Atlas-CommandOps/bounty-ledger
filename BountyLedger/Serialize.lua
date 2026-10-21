-- Canonical key=value encoding. Keys are sorted so the same entry always encodes to the
-- same bytes, which is what makes its hash reproducible on every client.
local _, ns = ...

local US = "\31" -- field separator

local function escape(s)
	return (s:gsub("[%c%%|=]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function unescape(s)
	return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function ns.Encode(t)
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do
		local v = t[k]
		if type(v) == "number" then
			v = string.format("%d", v)
		else
			v = escape(tostring(v))
		end
		parts[#parts + 1] = k .. "=" .. v
	end
	return table.concat(parts, US)
end

function ns.Decode(s)
	local t = {}
	for field in (s .. US):gmatch("(.-)" .. US) do
		local k, v = field:match("^([%w_]+)=(.*)$")
		if k then t[k] = unescape(v) end
	end
	return t
end
