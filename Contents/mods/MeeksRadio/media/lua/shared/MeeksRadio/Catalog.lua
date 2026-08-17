MeeksRadio = MeeksRadio or {}

-- Only server-approved IDs from this table may enter a station queue.
-- Add packaged, cleared audio definitions here before enabling a track.
MeeksRadio.Catalog = {
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
    if type(track.sound) ~= "string" or tonumber(track.duration) == nil then return nil end
    return track
end

MeeksRadio.Catalog["meeks_test_signal"] = {
    id = "meeks_test_signal",
    title = "Meeks Radio Test Signal",
    artist = "Meeks Protocol",
    sound = "MeeksRadio_TestSignal",
    duration = 8,
}
