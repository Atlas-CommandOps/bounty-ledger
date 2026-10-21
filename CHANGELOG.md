# Changelog

## 0.1.2
- Spam protection: each player can write at most 30 ledger records an hour, and every client enforces it on what it receives. Oversized, malformed, future-dated or unknown records are rejected. Players who flood the network are ignored for the rest of the minute.
- Messages now carry a protocol version. When someone on a newer version is online, you get a one-time notice to update.
- The ledger is capped at 5,000 records. The oldest closed history is dropped first. Open bounties, unpaid or disputed claims, and your own records are always kept.
- Each player's sync request is answered at most once every 5 minutes.

## 0.1.1
- Hides the addon's data channel more reliably across chat setups.

## 0.1.0
- First release: post gold bounties on enemy players, automatic kill claims with groupmate witnesses, trade-verified payments, a shared hash-chained ledger, public reputation, My Deaths with one-click revenge bounties, nameplate skulls, BOUNTY CLAIMED banner and WANTED popups.
