MeeksRadio = MeeksRadio or {}

-- Only server-approved IDs from this table may enter a station queue.
-- Add packaged, cleared audio definitions here before enabling a track.
MeeksRadio.Catalog = {
    ["meeks_test_signal"] = {
        id = "meeks_test_signal",
        title = "Meeks Radio Test Signal",
        artist = "Meeks Protocol",
        sound = "MeeksRadio_TestSignal",
        duration = 8,
    },
    ["ghosted_z3r0null"] = {
        id = "ghosted_z3r0null",
        title = "Ghosted",
        artist = "Z3R0NULL",
        sound = "MeeksRadio_GhostedZ3R0NULL",
        duration = 315,
    },
    -- ["my_song"] = {
    --     id = "my_song",
    --     title = "My Song",
    --     artist = "Meeks",
    --     sound = "MeeksRadio_MySong",
    --     duration = 184,
    -- },
}

function MeeksRadio.getTrack(trackId)
    local track = MeeksRadio.Catalog[tostring(trackId or "")]
    if not track then return nil end
    if type(track.sound) ~= "string" or (tonumber(track.duration) or 0) <= 0 then return nil end
    return track
end
