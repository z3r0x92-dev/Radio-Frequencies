# Meeks Radio

Server-authoritative community radio and DJ queues for Project Zomboid Build 42 multiplayer.

## Status

This repository contains the first playable multiplayer scaffold:

- ordinary portable radios are checked for a configured tuned frequency;
- approved DJs can enqueue tracks from a packaged, server-approved catalog;
- the server owns station state and broadcasts authoritative track timestamps;
- admins can grant/revoke DJs, lock stations, skip/stop queues, and issue emergency overrides;
- clients never submit file paths, URLs, sound names, or durations;
- approved DJs can right-click a tuned radio to open a compact, vanilla-styled console;
- DJ permissions, queues, station locks, and current playback timing persist in server mod data;
- late listeners wait for the next track because Build 42's exposed Lua audio path does not provide a reliable cross-client seek primitive.

World radios and vehicle radios are represented in configuration but disabled until their Build 42 stable device hooks are verified in multiplayer.

## Install for development

Copy `Contents/mods/MeeksRadio` into the server and client Project Zomboid mods directory. Enable mod ID `MeeksRadio` on the server. Every player must receive the same audio content pack.

## Add cleared music

SoundCloud URLs are not streamed by the mod. Export or download only tracks you own or have permission to distribute, convert them to `.ogg`, and place them in:

`Contents/mods/MeeksRadio/media/sound/MeeksRadio/`

Then add a matching sound definition in `media/scripts/MeeksRadio_Sounds.txt` and a catalog entry in `media/lua/shared/MeeksRadio/Catalog.lua`. Never accept a client-provided URL or file path.

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

## DJ console

Approved DJs and admins tune a portable radio to a configured station, right-click the radio in inventory, and choose **Open Meeks DJ Console**. The compact Project Zomboid-style panel provides approved-track search, now-playing details, the upcoming queue, add/remove controls, and admin skip. Listeners use only the normal in-game radio controls.

## Fallback commands

Commands are sent through the mod's client command interface. The included chat-command bridge accepts:

- `/mr status [frequency]`
- `/mr queue <frequency> <trackId>`
- `/mr skip <frequency>`
- `/mr stop <frequency>`
- `/mr lock <frequency> <on|off>`
- `/mr grant <username>`
- `/mr revoke <username>`
- `/mr emergency <frequency> <trackId>`

Admin-only commands are validated again on the server. Editing a client cannot confer DJ or admin authority.

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

Code is provided under the MIT License. Audio files are intentionally excluded and require their own explicit distribution rights.
