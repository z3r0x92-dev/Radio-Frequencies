# Radio Frequencies

Server-authoritative music, announcements, emergency alerts, lore, events, and community updates delivered through configured Project Zomboid radio frequencies.

Current mod version: **0.9.1** (protocol v6, catalog `3-ghosted`).

## Status

Current features:

- powered portable radios, nearby placed/world radios, and the occupied vehicle radio are checked for a configured tuned frequency through guarded Build 42 device calls;
- approved DJs can enqueue tracks from a packaged, server-approved catalog;
- the server owns station state and broadcasts authoritative track timestamps;
- admins can grant/revoke DJs, lock stations, skip/stop queues, and issue emergency overrides;
- admins can send announcement, emergency, lore, event, and community bulletins from the radio console;
- text bulletins are delivered only when the active detected receiver is powered and tuned to the matching frequency;
- recent bulletins and the currently active message persist in server-owned station state;
- optional reviewed schedules can repeat server-authored messages at safe minimum intervals;
- one-time broadcasts use explicit Unix timestamps and persist completion so they cannot repeat after a restart;
- listeners can press F7 or use a powered portable-radio context menu to review history and request approved tracks; authorized DJs open the operations console with F7;
- DJs can approve or reject requests, subject to grants, station allowlists, and optional UTC shift windows;
- DJ/shift permissions refresh live and show an exact access reason for the active station;
- administrators can load editable evacuation, restart, event, weather, and meeting templates;
- emergency bulletins can play a packaged warning cue before showing their text;
- emergency overrides sequence the warning cue before the selected emergency audio rather than playing both at once;
- location-specific station names and DJ allowlists support settlements, factions, and administrative channels;
- clients never submit file paths, URLs, sound names, or durations;
- clients retry the compatibility handshake until the server acknowledges it, and version mismatches are shown in the radio UI;
- catalog tracks are checked against finite 1-3600 second duration limits at runtime and by the package validator;
- approved DJs can right-click a tuned radio to open a compact, vanilla-styled console;
- DJ permissions, queues, station locks, and current playback timing persist in server mod data;
- persisted tracks are revalidated against the packaged catalog at startup, with stale durations replaced and missing tracks removed;
- late listeners wait for the next track because Build 42's exposed Lua audio path does not provide a reliable cross-client seek primitive.

Vehicle, portable, and nearby placed-radio reception uses guarded feature detection because Build 42 device implementations differ between patches and radio objects. The default priority is occupied vehicle, carried portable, then nearby placed radio. The UI identifies the chosen receiver accurately. Nearby scans are cached and radius-limited to avoid a per-frame area scan.

## Install for development

Copy `Contents/mods/MeeksRadio` into the server and client Project Zomboid mods directory. Enable mod ID `MeeksRadio` on the server. Every player must receive the same audio content pack.

## Add cleared music

SoundCloud URLs are not streamed by the mod. Export or download only tracks you own or have permission to distribute, convert them to `.ogg`, and place them in:

`Contents/mods/MeeksRadio/42/media/sound/MeeksRadio/`

Then add a matching sound definition under the Build 42 `media/scripts` directory and a catalog entry under `media/lua/shared/MeeksRadio`. Never accept a client-provided URL or file path.

Example catalog entry:

```lua
{
    id = "my_song",
    title = "My Song",
    artist = "Meeks",
    sound = "MeeksRadio_MySong",
    duration = 184,
}
```

Track duration must match the encoded file closely because the server uses it to advance queues.

Run `python tools/validate_catalog.py` before publishing. It checks duplicate and malformed IDs, duration bounds, sound definitions, and packaged `.ogg` files.

## DJ console

Approved DJs and admins tune a receiver to a configured station and press F7, or right-click a powered portable radio and choose **Open Radio Operations Console**. The clamped panel provides approved-track search, now-playing details, the upcoming queue, active receiver details, and a station-specific permission reason. Admins also receive a validated bulletin editor, editable templates, and direct grant/revoke controls for DJ assignments. Listeners use the normal in-game radio controls.

## Broadcasts and schedules

Manual bulletins are limited to 240 characters, stripped of control characters, rate-limited, and accepted only from server-recognized administrators. They appear as radio text above a listener only when that player has a powered portable radio tuned to the matching frequency. The system does not impersonate player chat.

Recurring messages are configured in `Config.lua` under `scheduledBroadcasts`. Each entry has a unique ID, frequency, category, message, initial delay, and repeat interval. Examples remain disabled by default so a new server cannot accidentally spam players. Scheduled messages use the same validation, persistence, tuned-frequency delivery, and history system as manual broadcasts.

One-time messages use `oneTimeBroadcasts` and a Unix `at` timestamp in UTC. Completed IDs are stored in global mod data. Never reuse an old ID for a different event.

## Requests, stations, and DJ shifts

Listeners use the F7 terminal or radio context menu to submit catalog track requests. Requests are server-validated, deduplicated per player and track, capped per station, and cannot enter playback until an active DJ or administrator approves them.

Each station can define a display location and an `allowedDjs` list. An empty allowlist permits any globally granted DJ. Optional `djShifts` require a granted DJ, matching station, and active UTC start/end timestamps; administrators bypass shift restrictions.

DJ assignments can be granted or revoked from the admin console and update connected clients automatically. Schedule definitions and shift windows remain server-authored in `Config.lua`; runtime editing was intentionally not exposed because those changes need durable validation and review before affecting every listener.

## Mod integration API

Server-side mods can safely publish events after Radio Frequencies has loaded:

```lua
if MeeksRadio and MeeksRadio.ServerAPI then
    MeeksRadio.ServerAPI.broadcast(102800, "event", "Survivor League season results are available.", "SurvivorLeagueCommunity")
end
```

Radio Frequencies automatically supports its own server-start notice and an optional generic player-death notice. Survivor League milestones and season results must call this API from Survivor League because they are custom mod events, not vanilla Project Zomboid events.

## Command safety

DJ actions use the mod's client/server command interface and are validated again on the server. Editing a client cannot confer DJ or admin authority. The experimental `/mr` chat bridge was removed in 0.2.2 because the Build 42 `OnAddMessage` callback contract could not be verified consistently across supported patches. Use the DJ console instead.

## Publish

After creating an empty GitHub repository named `meeks-radio`:

```bash
git remote add origin git@github.com:YOUR_ACCOUNT/meeks-radio.git
git push -u origin main
```

Or, on a machine with GitHub CLI:

```bash
gh repo create meeks-radio --source=. --private --push
```

## License

Code is provided under the MIT License. This repository currently bundles the Radio Frequencies test signal and `Ghosted` audio used by the catalog. Any additional audio requires explicit distribution rights; the MIT code license does not automatically grant rights to third-party audio.

## Changelog

### 0.9.1

- standardizes Meeks FM and the server-start announcement on 102.8 MHz;
- adds responsive layouts for the listener and administrator interfaces;
- adds selectable Project Zomboid, Meeks Protocol, and Military themes with Meeks Protocol as the default;
- improves Build 42 audio stop, transition-window synchronization, queue rotation, skip, and stop behavior;
- sends active station state when a player is created and removes temporary debug logging;
- retains multiplayer synchronization protocol v6.

### 0.5.0

- refreshes DJ and shift authorization live with station-specific access reasons;
- batches persisted ModData transmission instead of retransmitting it on every station update;
- sequences the emergency cue before selected emergency audio;
- prioritizes occupied vehicle, portable, then nearby placed receivers and identifies the active source in the UI;
- opens the operations console with F7 for authorized DJs and the listener terminal for everyone else;
- adds powered-radio and active-frequency validation to listener requests;
- clamps console and listener windows to the screen and adds receiver, permission, and selected-bulletin details;
- adds admin grant/revoke DJ assignment controls while keeping schedules and shift windows safely server-authored;
- bumps the multiplayer protocol to v5.

### 0.4.0

- adds guarded portable, nearby world-radio, and occupied vehicle-radio reception;
- adds an F7 listener terminal with per-frequency broadcast history and catalog requests;
- adds DJ request approval/rejection with server validation and bounded persistence;
- adds one-time UTC schedules alongside recurring schedules;
- adds editable broadcast templates and configurable emergency cue audio;
- adds location metadata, per-station DJ allowlists, and timestamp-bounded DJ shifts;
- adds server-start/player-death automation and a public server integration API;
- bumps the multiplayer protocol to v4.

### 0.3.0

- adds server-authoritative tuned-radio text bulletins for announcements, emergencies, lore, events, and community updates;
- adds an admin broadcast composer with selectable categories to the Radio Operations Console;
- persists bounded broadcast history and active-message state per station;
- adds optional recurring server schedules with unique IDs and minimum repeat intervals;
- validates message length, category, frequency, permissions, control characters, and cooldowns;
- bumps the multiplayer command protocol to v3 so outdated clients cannot submit incompatible commands.

### 0.2.2

- sanitizes persisted queues and current tracks against the active server catalog;
- replaces saved durations with authoritative catalog durations and removes missing tracks;
- repairs invalid playback timestamps and removes stale station records with server logs;
- removes the unverified `/mr` `OnAddMessage` chat bridge;
- documents the no-seek late-listener policy and makes the transition grace window configurable in code.

### 0.2.1

- retries protocol-v2 compatibility handshakes until acknowledged;
- exposes connecting, protocol-mismatch, and catalog-mismatch states in the DJ interface;
- validates finite track durations between 1 and 3600 seconds;
- applies configured per-station playback volume when the active Build 42 emitter supports it;
- clears cached compatibility state on guarded disconnect events and expands server audit logging;
- corrects the online-status text and bundled-audio documentation.
