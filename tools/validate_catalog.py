#!/usr/bin/env python3
"""Small static validator for Meeks Radio catalog/audio packaging."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "Contents/mods/MeeksRadio"
CATALOG = MOD / "media/lua/shared/MeeksRadio/Catalog.lua"
SOUNDS = MOD / "media/scripts/MeeksRadio_Sounds.txt"

errors = []
for path in (CATALOG, SOUNDS, MOD / "mod.info"):
    if not path.is_file():
        errors.append(f"missing: {path.relative_to(ROOT)}")

if CATALOG.is_file():
    text = CATALOG.read_text(encoding="utf-8")
    ids = re.findall(r'\bid\s*=\s*"([^"]+)"', text)
    if len(ids) != len(set(ids)):
        errors.append("catalog contains duplicate track IDs")
    for track_id in ids:
        if not re.fullmatch(r"[a-z0-9_]+", track_id):
            errors.append(f"invalid track ID: {track_id}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)

print("Meeks Radio package structure is valid")
