MeeksRadio = MeeksRadio or {}

MeeksRadio.Config = {
    module = "MeeksRadio",
    protocolVersion = 8,
    -- Fallback when the Sandbox option is unavailable: 1 Project Zomboid,
    -- 2 Meeks Protocol, 3 Military.
    interfaceTheme = 2,
    frequencyTolerance = 0.01,
    requestCooldownSeconds = 2,
    maxQueueLength = 20,
    minTrackDurationSeconds = 1,
    maxTrackDurationSeconds = 3600,
    -- Without a stable seek API, playback may only begin near the server's
    -- authoritative track transition. Later listeners wait for the next one.
    playbackStartGraceSeconds = 4,
    maxTimestampSkewSeconds = 300,
    maxBroadcastLength = 240,
    broadcastCooldownSeconds = 10,
    broadcastDisplaySeconds = 12,
    broadcastHistoryLimit = 20,
    maxRequestsPerStation = 30,
    worldRadioScanRadius = 2,
    -- The first powered receiver found wins when several are available.
    receiverPriority = { "vehicle", "portable", "nearby" },
    emergencyCueTrackId = "meeks_test_signal",
    autoBroadcastServerStart = true,
    autoBroadcastPlayerDeaths = false,
    catalogVersion = "3-ghosted",
    allowPortableRadios = true,
    allowWorldRadios = true,
    allowVehicleRadios = true,
    stations = {
        [102800] = { name = "Meeks FM", location = "Community Network", volume = 0.8, allowedDjs = {} },
        [104600] = { name = "Protocol Radio", location = "Administration", volume = 0.8, allowedDjs = {} },
        [107900] = { name = "Emergency Override", location = "Countywide", volume = 1.0, allowedDjs = {} },
    },
    broadcastTemplates = {
        { id="evacuation", kind="emergency", text="Emergency evacuation notice. Follow staff instructions and monitor this frequency." },
        { id="restart", kind="announcement", text="The server will restart soon. Please move to a safe location and log out safely." },
        { id="event_open", kind="event", text="A community event is now open. Check the event channel for location and rules." },
        { id="weather", kind="emergency", text="Severe weather warning. Seek shelter and monitor this frequency for updates." },
        { id="meeting", kind="community", text="A community meeting will begin soon at the Protocol Center." },
    },
    -- Optional recurring broadcasts. Keep entries disabled until their text,
    -- station, and interval have been reviewed for the live server.
    scheduledBroadcasts = {
        -- {
        --     id = "community_reminder",
        --     enabled = true,
        --     frequency = 102800,
        --     kind = "community",
        --     text = "Community meeting begins at the Protocol Center soon.",
        --     initialDelaySeconds = 300,
        --     intervalSeconds = 3600,
        -- },
    },
    -- One-time entries use a Unix timestamp (UTC) and fire once per save.
    oneTimeBroadcasts = {
        -- { id="launch_event", enabled=true, frequency=102800, kind="event",
        --   text="The launch event is beginning now.", at=1787072400 },
    },
    -- DJs must still be granted. When this list is non-empty, non-admin DJs
    -- may operate only during a matching UTC window on the matching station.
    djShifts = {
        -- { username="ExampleDJ", frequency=102800, startsAt=1787072400, endsAt=1787079600 },
    },
}

MeeksRadio.BroadcastKinds = {
    announcement = true,
    emergency = true,
    lore = true,
    event = true,
    community = true,
}

function MeeksRadio.Config.normalizeFrequency(value)
    local number = tonumber(value)
    if not number then return nil end
    if number < 1000 then
        return math.floor((number * 1000) + 0.5)
    end
    return math.floor(number + 0.5)
end

function MeeksRadio.Config.station(frequency)
    return MeeksRadio.Config.stations[MeeksRadio.Config.normalizeFrequency(frequency)]
end
