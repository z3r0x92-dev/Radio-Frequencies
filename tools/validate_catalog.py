#!/usr/bin/env python3
"""Small static validator for Meeks Radio catalog/audio packaging."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "Contents/mods/MeeksRadio"
BUILD = MOD / "42"
CATALOG = BUILD / "media/lua/shared/MeeksRadio/Catalog.lua"
SOUNDS = BUILD / "media/scripts/MeeksRadio_Sounds.txt"
AUDIO = BUILD / "media/sound/MeeksRadio"
CONFIG = BUILD / "media/lua/shared/MeeksRadio/Config.lua"
CLIENT = BUILD / "media/lua/client/MeeksRadio/Client.lua"
SERVER = BUILD / "media/lua/server/MeeksRadio/Server.lua"
CONSOLE = BUILD / "media/lua/client/MeeksRadio/Console.lua"
LISTENER = BUILD / "media/lua/client/MeeksRadio/Listener.lua"
MIN_DURATION = 1
MAX_DURATION = 3600

errors = []
for path in (CATALOG, CONFIG, CLIENT, SERVER, CONSOLE, LISTENER, SOUNDS, BUILD / "mod.info", MOD / "mod.info"):
    if not path.is_file():
        errors.append(f"missing: {path.relative_to(ROOT)}")

if CATALOG.is_file():
    text = CATALOG.read_text(encoding="utf-8")
    text = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.DOTALL)
    text = re.sub(r"--[^\n]*", "", text)
    ids = re.findall(r'\bid\s*=\s*"([^"]+)"', text)
    if len(ids) != len(set(ids)):
        errors.append("catalog contains duplicate track IDs")
    for track_id in ids:
        if not re.fullmatch(r"[a-z0-9_]+", track_id):
            errors.append(f"invalid track ID: {track_id}")
    entries = re.findall(r'\["([^\"]+)"\]\s*=\s*\{(.*?)\n\s*\}', text, re.DOTALL)
    sounds_text = SOUNDS.read_text(encoding="utf-8") if SOUNDS.is_file() else ""
    sounds_text = re.sub(r"/\*.*?\*/", "", sounds_text, flags=re.DOTALL)
    sound_names = set(re.findall(r'\bsound\s+([^\s{]+)', sounds_text))
    for table_id, body in entries:
        sound_match = re.search(r'\bsound\s*=\s*"([^\"]+)"', body)
        duration_match = re.search(r'\bduration\s*=\s*([0-9]+(?:\.[0-9]+)?)', body)
        if not sound_match:
            errors.append(f"track {table_id} has no sound name")
        elif sound_match.group(1) not in sound_names:
            errors.append(f"track {table_id} references undefined sound: {sound_match.group(1)}")
        if not duration_match:
            errors.append(f"track {table_id} has no numeric duration")
        else:
            duration = float(duration_match.group(1))
            if not MIN_DURATION <= duration <= MAX_DURATION:
                errors.append(
                    f"track {table_id} duration {duration:g} is outside "
                    f"{MIN_DURATION}-{MAX_DURATION} seconds"
                )

if SOUNDS.is_file():
    sounds_text = SOUNDS.read_text(encoding="utf-8")
    sounds_text = re.sub(r"/\*.*?\*/", "", sounds_text, flags=re.DOTALL)
    files = re.findall(r'\bfile\s*=\s*media/sound/MeeksRadio/([^,\s}]+)', sounds_text)
    for filename in files:
        if not (AUDIO / filename).is_file():
            errors.append(f"sound definition references missing audio: {filename}")

if CONFIG.is_file():
    config_text = CONFIG.read_text(encoding="utf-8")
    for key in (
        "minTrackDurationSeconds", "maxTrackDurationSeconds", "playbackStartGraceSeconds",
        "maxBroadcastLength", "broadcastCooldownSeconds", "broadcastDisplaySeconds",
        "broadcastHistoryLimit",
        "maxRequestsPerStation", "worldRadioScanRadius",
    ):
        if not re.search(rf"\b{key}\s*=\s*[0-9]+", config_text):
            errors.append(f"missing numeric config value: {key}")

if CLIENT.is_file() and "OnAddMessage" in CLIENT.read_text(encoding="utf-8"):
    errors.append("unsupported OnAddMessage chat-command bridge is enabled")

for path, token in ((CLIENT, '"radioBroadcast"'), (SERVER, '"radioBroadcast"'), (CONSOLE, '"broadcast"'), (LISTENER, '"requestTrack"')):
    if path.is_file() and token not in path.read_text(encoding="utf-8"):
        errors.append(f"broadcast protocol token missing from {path.relative_to(ROOT)}")

if CONFIG.is_file() and not re.search(r"\bprotocolVersion\s*=\s*6\b", CONFIG.read_text(encoding="utf-8")):
    errors.append("protocolVersion is not 6")

build_info = BUILD / "mod.info"
if build_info.is_file() and "version=0.9.1" not in build_info.read_text(encoding="utf-8"):
    errors.append("Build 42 mod.info version is not 0.9.1")
root_info = MOD / "mod.info"
if root_info.is_file() and "version=0.9.1" not in root_info.read_text(encoding="utf-8"):
    errors.append("root mod.info version is not 0.9.1")

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)

print("Meeks Radio package structure is valid")
