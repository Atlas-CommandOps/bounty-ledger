"""Build the Bounty Ledger zips.

  dist/BountyLedger-<version>.zip          release zip for CurseForge/Wago: only the addon folder,
                                           so the CurseForge app installs it cleanly into AddOns
  dist/BountyLedger-<version>-friends.zip  same, plus INSTALL.txt for people installing by hand

Usage: python build.py
"""
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).parent
ADDON = ROOT / "BountyLedger"
DIST = ROOT / "dist"


def version():
    toc = (ADDON / "BountyLedger.toc").read_text(encoding="utf-8")
    return re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)


def build(out, extras=()):
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for path in sorted(ADDON.rglob("*")):
            if path.is_file():
                z.write(path, Path("BountyLedger") / path.relative_to(ADDON))
        for extra in extras:
            z.write(ROOT / extra, extra)
    print(out)


def main():
    DIST.mkdir(exist_ok=True)
    v = version()
    build(DIST / f"BountyLedger-{v}.zip")
    build(DIST / f"BountyLedger-{v}-friends.zip", extras=["INSTALL.txt"])


if __name__ == "__main__":
    main()
