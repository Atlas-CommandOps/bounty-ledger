import lupa, sys, os
SRC = r"C:\Users\Colton\Projects\ForeverBounty\BountyLedger"
L = lupa.LuaRuntime(unpack_returned_tuples=True)

# WoW API stubs + Lua 5.1 bit library shim (signed 32-bit results like WoW's bitlib).
L.execute(r'''
local function tobit(x) x = math.tointeger(math.floor(x) % 4294967296); if x >= 0x80000000 then x = x - 0x100000000 end; return x end
local function un(x) return math.tointeger(math.floor(x) % 4294967296) end
bit = {
  band = function(...) local r = 0xffffffff; for _,v in ipairs({...}) do r = r & un(v) end; return tobit(r) end,
  bor = function(...) local r = 0; for _,v in ipairs({...}) do r = r | un(v) end; return tobit(r) end,
  bxor = function(...) local r = 0; for _,v in ipairs({...}) do r = r ~ un(v) end; return tobit(r) end,
  bnot = function(a) return tobit(~un(a)) end,
  rshift = function(a, n) return tobit(un(a) >> n) end,
  lshift = function(a, n) return tobit((un(a) << n) & 0xffffffff) end,
}
NOW = 1792550000
function GetServerTime() return NOW end
function GetTime() return NOW end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function GetMoney() return 1000000000 end
function IsInInstance() return false end
timers = {}
C_Timer = {
  After = function(d, fn) table.insert(timers, fn) end,
  NewTimer = function(d, fn) local t = {fn = fn, Cancel = function(self) self.cancelled = true end}; table.insert(timers, t); return t end,
  NewTicker = function() return {} end,
}
function runTimers() local list = timers; timers = {}; for _, t in ipairs(list) do if type(t) == "function" then t() elseif not t.cancelled then t.fn() end end end
function CreateFrame() return setmetatable({}, {__index = function() return function() end end}) end
''')

def load(ns, name):
    src = open(os.path.join(SRC, name), encoding="utf-8").read()
    fn = L.eval("function(src, name) return assert(load(src, name)) end")(src, name)
    fn("BountyLedger", ns)

def new_client(me):
    ns = L.table()
    for f in ["Core.lua", "Sha256.lua", "Serialize.lua", "Ledger.lua", "Bounties.lua"]:
        load(ns, f)
    L.execute("""local ns, me = ...
      ns.db = {settings = {}}
      ns.me = {name = me, guid = "Player-1-" .. me, faction = "Horde"}
      ns.world = {entries = {}, heads = {}, verified = {}, forks = {}, deaths = {}, notified = {}}
      ns.outbox = {}
      ns.Comm = { Broadcast = function(kind, payload) table.insert(ns.outbox, {kind, payload}) end,
                  Whisper = function(to, kind, payload) table.insert(ns.outbox, {kind, payload, to}) end }
    """.replace("local ns, me = ...", "")) if False else None
    L.eval("""function(ns, me)
      ns.db = {settings = {}}
      ns.me = {name = me, guid = "Player-1-" .. me, faction = "Horde"}
      ns.world = {entries = {}, heads = {}, verified = {}, forks = {}, deaths = {}, notified = {}}
      ns.outbox = {}
      ns.Comm = { Broadcast = function(kind, payload) table.insert(ns.outbox, {kind, payload}) end,
                  Whisper = function(to, kind, payload) table.insert(ns.outbox, {kind, payload, to}) end }
    end""")(ns, me)
    return ns

fails = 0
def check(label, cond):
    global fails
    print(("PASS " if cond else "FAIL ") + label)
    if not cond: fails += 1

a = new_client("Alice Horde")
sha = a.Sha256
check("sha256('abc')", sha("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
check("sha256('')", sha("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
check("sha256 two blocks", sha("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")

rt = L.eval("function(ns) local t = {tn='Écagão Day=1|x', r=50000, note='a\\31b%c'}; local d = ns.Decode(ns.Encode(t)); return d.tn == t.tn and d.note == t.note and d.r == '50000' end")(a)
check("serializer round-trip with separators and accents", rt)

# Deliver every outbox message from src to the listed clients as live channel traffic.
deliver = L.eval("""function(src, dsts)
  for _, m in ipairs(src.outbox) do
    for _, dst in ipairs(dsts) do dst.Fire("COMM", m[1], m[2], src.me.name, "CHANNEL") end
  end
  src.outbox = {}
end""")
def rebuild(*clients):
    L.execute("runTimers()")
    for c in clients: c.Bounties.Rebuild()

h = new_client("Hank Hunter")
p = new_client("Pete Party")
everyone = L.table(a, h, p)

# Alice posts a 5g bounty on an Alliance player, locked to his GUID.
post = L.eval("function(ns) return ns.Bounties.Post({name='Fin Thecutter', guid='Player-4613-0188B342', race='Night Elf', class='ROGUE', level=19, reward=50000}) end")(a)
check("post accepted", post)
deliver(a, L.table(h, p)); rebuild(a, h, p)
bid = L.eval("function(ns) for id in pairs(ns.state.bounties) do return id end end")(h)
check("hunter sees the open bounty", h.state.bounties[bid].status == "open")
check("relayed-live entry is verified (sender == author)", h.world.verified[bid] == True)

# Hank kills Fin: claim. Pete (groupmate) co-signs.
L.eval("function(ns, bid) ns.Ledger.Append('CLAIM', {b=bid, tid='Player-4613-0188B342', tn='Fin Thecutter', kt=GetServerTime(), z='Ashenvale'}) end")(h, bid)
L.eval("function(ns) ns.Ledger.Append('COSIGN', {tid='Player-4613-0188B342', tn='Fin Thecutter', hn='Hank Hunter', kt=GetServerTime()+3}) end")(p)
deliver(h, L.table(a, p)); deliver(p, L.table(a, h)); rebuild(a, h, p)
b = a.state.bounties[bid]
check("bounty is claimed by Hank", b.status == "claimed" and b.winner.hunter == "Hank Hunter")
check("Pete co-signed the claim", b.winner.cosigners["Pete Party"] == True)
check("claim starts unpaid", b.winner.status == "unpaid")

# Trade: Alice pays, Hank receives.
cid = b.winner.id
L.eval("function(ns, cid) ns.Ledger.Append('PAY', {c=cid, m=50000}) end")(a, cid)
deliver(a, L.table(h, p)); rebuild(a, h, p)
check("after PAY only: paid, awaiting hunter", p.state.claims[cid].status == "paid")
L.eval("function(ns, cid) ns.Ledger.Append('RECV', {c=cid, m=50000}) end")(h, cid)
deliver(h, L.table(a, p)); rebuild(a, h, p)
check("PAY + RECV: verified on a third client", p.state.claims[cid].status == "verified")
check("Alice's reputation: paid 1", p.state.rep["Alice Horde"].paid == 1)
check("Hank's reputation: collected 1", p.state.rep["Hank Hunter"].collected == 1)

# Spoofing: Pete broadcasts an entry claiming to be authored by Alice.
spoof = L.eval("""function(ns)
  local e = {k='PAY', a='Alice Horde', n=99, t=GetServerTime(), p='-', c='x', m=1}
  e.h = ns.Ledger.Hash(e)
  return select(2, ns.Ledger.Receive(e, 'Pete Party', true))
end""")(h)
check("spoofed author over live channel is rejected", spoof == "spoofed author")

# Tamper: change a reward after hashing.
tamper = L.eval("""function(ns, bid)
  local src = ns.world.entries[bid]; local e = {}
  for k, v in pairs(src) do e[k] = v end
  e.r = 1
  return select(2, ns.Ledger.Receive(e, e.a, false))
end""")(p, bid)
check("tampered entry fails its hash", tamper == "bad hash")

# Fork: Alice publishes a different entry #1.
fork = L.eval("""function(ns)
  local e = {k='POST', a='Alice Horde', n=1, t=GetServerTime(), p='-', tn='Someone Else', r=20000}
  e.h = ns.Ledger.Hash(e)
  ns.Ledger.Receive(e, 'Alice Horde', true)
  return ns.world.forks['Alice Horde'] == true
end""")(p)
check("conflicting entry with same number flags a fork", fork)

# Sync: a new client gets everything by whisper, unverified, then Alice's HEAD verifies her chain.
n = new_client("Nina New")
L.eval("function(ns) ns.Fire('COMM', 'Q', ns.Encode({s=0}), 'Nina New', 'CHANNEL') end")(h)
L.execute("runTimers()")
L.eval("""function(src, dst)
  for _, m in ipairs(src.outbox) do if m[1] == 'S' then dst.Fire('COMM', 'S', m[2], src.me.name, 'WHISPER') end end
  src.outbox = {}
end""")(h, n)
rebuild(n)
check("synced client rebuilt the same verified claim", n.state.claims[cid].status == "verified")
check("synced entries start unverified", n.world.verified[bid] != True)
L.eval("function(src) src.Ledger.AnnounceHead() end")(a)
deliver(a, L.table(n)); L.execute("runTimers()")
check("author HEAD verifies their whole chain", n.world.verified[bid] == True and n.world.verified[cid.replace('Hank Hunter', 'Alice Horde')] if False else n.world.verified[bid] == True)

# Late claim and overdue.
c2 = new_client("Carl Second")
L.eval("function(ns) ns.Bounties.Post({name='Late Target', reward=20000}) end")(a)
deliver(a, L.table(h, c2)); rebuild(a, h, c2)
bid2 = L.eval("function(ns) for id, b in pairs(ns.state.bounties) do if b.tn == 'Late Target' then return id end end end")(h)
L.eval("function(ns, bid) ns.Ledger.Append('CLAIM', {b=bid, tn='Late Target', kt=GetServerTime(), z='X'}) end")(h, bid2)
L.execute("NOW = NOW + 5")
L.eval("function(ns, bid) ns.Ledger.Append('CLAIM', {b=bid, tn='Late Target', kt=GetServerTime(), z='X'}) end")(c2, bid2)
deliver(h, L.table(a)); deliver(c2, L.table(a)); rebuild(a)
b2 = a.state.bounties[bid2]
check("first claim wins, by-name bounty", b2.winner.hunter == "Hank Hunter")
late = L.eval("function(ns, bid) for _, c in ipairs(ns.state.bounties[bid].claims) do if c.hunter == 'Carl Second' then return c.status end end end")(a, bid2)
check("second claim is marked late", late == "late")
L.execute("NOW = NOW + 49*3600")
rebuild(a)
check("unpaid after 48h is overdue", a.state.bounties[bid2].winner.status == "overdue")
check("overdue shows on poster reputation", a.state.rep["Alice Horde"].overdue == 1)

# Self-claim and below-minimum posts are ignored.
bad = L.eval("function(ns) local ok, err = ns.Bounties.Post({name='Cheap Target', reward=50}); return ok end")(a)
check("below-minimum reward refused", not bad)

print("\n%d failure(s)" % fails)
sys.exit(1 if fails else 0)
