-- Pure-Lua SHA-256 on WoW's bit library. Used to hash-chain ledger entries.
local _, ns = ...

local band, bor, bxor, bnot, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.bnot, bit.rshift, bit.lshift
local MOD = 4294967296
local floor, byte, char, format = math.floor, string.byte, string.char, string.format

local function u(x) return x % MOD end
local function rrot(x, n) return u(bor(rshift(x, n), lshift(x, 32 - n))) end

local K = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function be32(x)
	return char(floor(x / 16777216) % 256, floor(x / 65536) % 256, floor(x / 256) % 256, x % 256)
end

local function block(msg, i, H)
	local w = {}
	for j = 1, 16 do
		local a, b, c, d = byte(msg, i + (j - 1) * 4, i + (j - 1) * 4 + 3)
		w[j] = ((a * 256 + b) * 256 + c) * 256 + d
	end
	for j = 17, 64 do
		local v = w[j - 15]
		local s0 = u(bxor(rrot(v, 7), rrot(v, 18), rshift(v, 3)))
		v = w[j - 2]
		local s1 = u(bxor(rrot(v, 17), rrot(v, 19), rshift(v, 10)))
		w[j] = u(w[j - 16] + s0 + w[j - 7] + s1)
	end
	local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
	for j = 1, 64 do
		local S1 = u(bxor(rrot(e, 6), rrot(e, 11), rrot(e, 25)))
		local ch = u(bxor(band(e, f), band(bnot(e), g)))
		local t1 = u(h + S1 + ch + K[j] + w[j])
		local S0 = u(bxor(rrot(a, 2), rrot(a, 13), rrot(a, 22)))
		local maj = u(bxor(band(a, b), band(a, c), band(b, c)))
		local t2 = u(S0 + maj)
		h, g, f, e, d, c, b, a = g, f, e, u(d + t1), c, b, a, u(t1 + t2)
	end
	H[1], H[2], H[3], H[4] = u(H[1] + a), u(H[2] + b), u(H[3] + c), u(H[4] + d)
	H[5], H[6], H[7], H[8] = u(H[5] + e), u(H[6] + f), u(H[7] + g), u(H[8] + h)
end

function ns.Sha256(msg)
	local len = #msg
	local bits = len * 8
	msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64) .. be32(floor(bits / MOD)) .. be32(bits % MOD)
	local H = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
	for i = 1, #msg, 64 do block(msg, i, H) end
	local out = {}
	for i = 1, 8 do out[i] = format("%04x%04x", floor(H[i] / 65536), H[i] % 65536) end
	return table.concat(out)
end
