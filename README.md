# Bounty Ledger

Player-run gold bounties for World of Warcraft: Forever. Post a bounty on an enemy-faction player. Whoever lands the killing blow in the open world claims it. The payment is a normal trade that both players' addons record, so anyone can see who pays.

Download: [CurseForge](https://www.curseforge.com/wow/addons/bounty-ledger)

## Repository layout

| Path | What it is |
|---|---|
| `BountyLedger/` | The addon (the folder that goes in `Interface/AddOns`) |
| `tests/test_logic.py` | Runs the ledger, claim and payment logic outside the game (`pip install lupa`, then `python tests/test_logic.py`) |
| `build.py` | Builds `dist/BountyLedger-<version>.zip` (release) and `-friends.zip` (with INSTALL.txt) |
| `BountyProbe/` | Development probe used to check which game APIs Forever allows |
| `branding/` | Logo source and CurseForge listing copy |

## How verification works

Every post, claim and payment is a ledger entry. Each entry is hashed (SHA-256) and carries the hash of its author's previous entry, so each player's history is a hash chain. WoW stamps the real sender on every addon message, so a live entry from someone other than its author is rejected. A payment is verified only when the payer's PAY entry and the hunter's RECV entry both exist for the same claim.

## License

All rights reserved. See [LICENSE](LICENSE).
