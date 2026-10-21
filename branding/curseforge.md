# CurseForge / Wago listing: Bounty Ledger

**Name:** Bounty Ledger

**Summary (one sentence, per CurseForge policy):**
Post gold bounties on enemy players, with kills and payments verified by both sides and a public record of who pays.

**Category suggestions:** PvP, Chat & Communication

**Logo:** `branding/logo-400.png` (CurseForge policy: avatars must be 400x400; no WebP)

---

## Description

**Someone camping your quest hub? Put a price on their head.**

Bounty Ledger is a player-run bounty system for World of Warcraft: Forever. Post a gold bounty on any enemy-faction player. Every player on your faction running Bounty Ledger sees it. Whoever lands the killing blow claims it, and the whole community can see whether the poster paid up.

### How it works
1. **Post.** Target an enemy player and type `/bounty post 10` (or use the Post Bounty button). The bounty is locked to that exact character.
2. **Hunt.** Wanted players get a skull above their nameplate, and a WANTED popup appears when a new bounty goes up.
3. **Claim.** Land the killing blow in the open world and the claim is recorded automatically, with a big **BOUNTY CLAIMED** banner. Groupmates who saw the kill are recorded as witnesses.
4. **Get paid.** The poster pays the hunter with a normal trade. Both players' addons record that trade, and the bounty shows as **Verified**.

### Why "Ledger"
Every post, claim and payment goes into a shared ledger that every user keeps a copy of. Each record is fingerprinted (SHA-256) and chained to the player's previous record, and WoW stamps the real sender on every addon message. In practice:
- Nobody can post a record in someone else's name.
- Editing an old record breaks its fingerprint, and every other copy notices.
- A payment only counts as **Verified** when the payer *and* the hunter both recorded the same trade.
- Posters who don't pay get flagged red on the board for everyone to see.

### Revenge, built in
Bounty Ledger reads your death recap, so **My Deaths** shows exactly who killed you and with what. One click posts a bounty on them.

### Features
- Wanted board, sorted by reward
- My Bounties, My Claims and My Deaths tabs
- Public reputation for every poster and hunter (bounties paid, unpaid, collected)
- Nameplate skulls on wanted players
- BOUNTY CLAIMED banner and WANTED popups (each can be turned off)
- No server, no website, no account. Everything runs between players' addons in-game.
- No libraries required

### Commands
| Command | What it does |
|---|---|
| `/bounty` | Open the board |
| `/bounty post <gold> [note]` | Post a bounty on your current target |
| `/bounty test` | Preview the BOUNTY CLAIMED banner |
| `/bounty toasts` / `/bounty sound` | Turn popups or sounds on or off |

### Good to know
- **Open world only.** Battleground and dungeon kills don't count. Blizzard hides player identities and blocks addon messages inside instances.
- **Your faction only.** Addons can't talk across factions, so you see bounties posted by your own faction on enemy players.
- **Gold moves by trade.** Addons can't move gold on their own. The poster trades the hunter, and the addon records it.
- **No location tracking.** Bounty Ledger never shares where anyone is.
- Bounties expire after 7 days. Minimum reward is 1 gold, and each player can have up to 5 open bounties.

### Fair play by design
Bounty Ledger is built for in-game world PvP, not for following people around:
- **No location tracking.** Nobody can use it to find where a player is.
- **Open world kills only**, under the game's normal PvP rules.
- **Bounties expire** after 7 days, and each player can have at most 5 open at a time.
- **The target's faction never sees the board.** It's a hunt, not a message to the player.
- Everything happens through normal game actions: killing blows and trades. The addon automates no combat, movement or trading, and never sends chat messages players can see. It only exchanges hidden addon data with other Bounty Ledger users.

### FAQ
**Can someone fake a kill?**
A claim is recorded by the killer's own addon from the game's kill event, which names both players. Groupmates who saw the same kill are added as witnesses, so the poster can see who backed it up before paying. Posters can also dispute a claim.

**Can someone fake a payment?**
A payment is Verified only when the payer's addon and the hunter's addon both recorded the same trade. One side can't fake the other side's record, because WoW stamps the real sender on every message.

**What if the poster never pays?**
After 48 hours an unpaid claim turns **Overdue**, and the poster's reputation shows it in red on every bounty they post. The community decides whether to hunt for them again.

**Does it work across factions?**
Bounties are always on enemy-faction players, but only your own faction sees your board. Blizzard doesn't let addons talk across factions.

**Do I need to keep it open?**
No. The board syncs from other players when you log in, and kills and trades are recorded in the background.

**Does it track where players are?**
No. Bounty Ledger never shares locations. You find your target the old-fashioned way.

### Status
Early release. Please report bugs (screenshots of red error popups help a lot) in the Issues/comments.
