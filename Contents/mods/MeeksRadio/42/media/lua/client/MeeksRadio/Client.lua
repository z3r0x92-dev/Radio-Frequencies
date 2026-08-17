require "MeeksRadio/Config"
require "MeeksRadio/Catalog"
require "MeeksRadio/Console"

local Config = MeeksRadio.Config
local stationStates = {}
local playback = { frequency = nil, trackId = nil, handle = nil, emitter = nil }
local permissions = { isDj = false, isAdmin = false, catalogMatch = true }
MeeksRadio.ClientStationStates = stationStates
MeeksRadio.ClientPermissions = permissions

local function activePortableFrequency(player)
    if not Config.allowPortableRadios or not player then return nil end
    local items = player:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and item.getDeviceData then
            local ok, device = pcall(function() return item:getDeviceData() end)
            if ok and device then
                local onOk, turnedOn = pcall(function() return device:getIsTurnedOn() end)
                local chOk, channel = pcall(function() return device:getChannel() end)
                if onOk and chOk and turnedOn and Config.station(channel) then
                    return Config.normalizeFrequency(channel)
                end
            end
        end
    end
    return nil
end

local function stopPlayback()
    if playback.handle and playback.emitter then
        pcall(function() playback.emitter:stopSound(playback.handle) end)
    end
    playback = { frequency = nil, trackId = nil, handle = nil, emitter = nil }
end

local function updatePlayback()
    local player = getPlayer()
    local frequency = activePortableFrequency(player)
    local s = frequency and stationStates[frequency] or nil
    local wanted = s and s.currentTrackId or nil

    if playback.frequency == frequency and playback.trackId == wanted then return end
    stopPlayback()
    if not player or not frequency or not wanted then return end

    local track = MeeksRadio.getTrack(wanted)
    if not track then return end

    -- Build 42 Lua audio does not expose a dependable synchronized seek here.
    -- A listener already tuned when the state arrives starts the track; a late
    -- listener waits for the next authoritative transition.
    local clientNow = getTimestamp and getTimestamp() or (s.serverTime or 0)
    local elapsed = math.max(0, clientNow - (s.startedAt or 0))
    if elapsed > 2 then return end

    local emitter = player:getEmitter()
    local ok, handle = pcall(function() return emitter:playSound(track.sound) end)
    if ok then
        playback = { frequency = frequency, trackId = wanted, handle = handle, emitter = emitter }
    end
end

local function onServerCommand(module, command, args)
    if module ~= Config.module or type(args) ~= "table" then return end
    if command == "stationState" then
        local frequency = Config.normalizeFrequency(args.frequency)
        if frequency then stationStates[frequency] = args end
        updatePlayback()
    elseif command == "error" and args.message then
        print("[Meeks Radio] " .. tostring(args.message))
        if HaloTextHelper and getPlayer() then
            HaloTextHelper.addBadText(getPlayer(), "Meeks Radio: " .. tostring(args.message))
        end
    elseif command == "permissions" then
        permissions.isDj = args.isDj == true
        permissions.isAdmin = args.isAdmin == true
        permissions.catalogMatch = tostring(args.catalogVersion) == tostring(Config.catalogVersion)
        if not permissions.catalogMatch then print("[Meeks Radio] Catalog mismatch; DJ console disabled") end
    end
end

local function requestHello()
    sendClientCommand(Config.module, "hello", { catalogVersion = Config.catalogVersion })
end

local function words(value)
    local result = {}
    for word in string.gmatch(value or "", "%S+") do table.insert(result, word) end
    return result
end

local function onChatMessage(message)
    if type(message) ~= "string" or string.sub(message, 1, 3) ~= "/mr" then return end
    local p = words(message)
    local command = p[2]
    local frequency = p[3]
    if command == "status" then
        sendClientCommand(Config.module, "status", { frequency = frequency or 101200 })
    elseif command == "queue" then
        sendClientCommand(Config.module, "queue", { frequency = frequency, trackId = p[4] })
    elseif command == "skip" or command == "stop" then
        sendClientCommand(Config.module, command, { frequency = frequency })
    elseif command == "lock" then
        sendClientCommand(Config.module, "lock", { frequency = frequency, locked = p[4] == "on" })
    elseif command == "grant" or command == "revoke" then
        sendClientCommand(Config.module, command, { username = p[3] })
    elseif command == "emergency" then
        sendClientCommand(Config.module, "emergency", { frequency = frequency, trackId = p[4] })
    end
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnPlayerUpdate.Add(updatePlayback)
Events.OnCreatePlayer.Add(requestHello)

-- OnAddMessage signature varies across B42 patches; keep this bridge guarded.
if Events.OnAddMessage then Events.OnAddMessage.Add(onChatMessage) end
