require "MeeksRadio/Config"
require "MeeksRadio/Catalog"
require "MeeksRadio/Console"
require "MeeksRadio/Listener"

local Config = MeeksRadio.Config
local stationStates = {}
local playback = { frequency = nil, trackId = nil, handle = nil, emitter = nil }
local permissions = {
    isDj = false, isAdmin = false, catalogMatch = true, protocolMatch = true,
    helloAcknowledged = false, serverCatalogVersion = nil, serverProtocolVersion = nil,
    stationPermissions = {},
}
local hello = { lastSentAt = 0, retrySeconds = 5 }
local lastBroadcastId = 0
MeeksRadio.ClientStationStates = stationStates
MeeksRadio.ClientPermissions = permissions

local detection = { checkedAt = 0, frequency = nil, receiver = nil }

local function frequencyFromDevice(device)
    if not device then return nil end
    local onOk, turnedOn = pcall(function() return device:getIsTurnedOn() end)
    local chOk, channel = pcall(function() return device:getChannel() end)
    if onOk and chOk and turnedOn and Config.station(channel) then return Config.normalizeFrequency(channel) end
    return nil
end

local function portableFrequency(player)
    if not Config.allowPortableRadios or not player then return nil end
    local items = player:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item and item.getDeviceData then
            local ok, device = pcall(function() return item:getDeviceData() end)
            if ok and device then
                local frequency = frequencyFromDevice(device)
                if frequency then return frequency end
            end
        end
    end
    return nil
end

local function vehicleFrequency(player)
    if not Config.allowVehicleRadios or not player or not player.getVehicle then return nil end
    local ok, vehicle = pcall(function() return player:getVehicle() end)
    if not ok or not vehicle then return nil end
    local partOk, part = pcall(function() return vehicle:getPartById("Radio") end)
    if partOk and part then
        local deviceOk, device = pcall(function() return part:getDeviceData() end)
        if deviceOk then return frequencyFromDevice(device) end
    end
    local radioOk, radio = pcall(function() return vehicle:getRadio() end)
    if radioOk then return frequencyFromDevice(radio) end
    return nil
end

local function worldFrequency(player)
    if not Config.allowWorldRadios or not player or not getCell then return nil end
    local squareOk, square = pcall(function() return player:getSquare() end)
    if not squareOk or not square then return nil end
    local radius = math.max(0, math.min(5, math.floor(tonumber(Config.worldRadioScanRadius) or 2)))
    for dx=-radius,radius do
        for dy=-radius,radius do
            local nearbyOk, nearby = pcall(function() return getCell():getGridSquare(square:getX()+dx, square:getY()+dy, square:getZ()) end)
            if nearbyOk and nearby then
                local objectsOk, objects = pcall(function() return nearby:getObjects() end)
                if objectsOk and objects then
                    for index=0,objects:size()-1 do
                        local object = objects:get(index)
                        if object and object.getDeviceData then
                            local deviceOk, device = pcall(function() return object:getDeviceData() end)
                            local frequency = deviceOk and frequencyFromDevice(device) or nil
                            if frequency then return frequency end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function activeRadioFrequency(player, force)
    local now = getTimestampMs and (getTimestampMs()/1000) or (getTimestamp and getTimestamp() or os.time())
    if not force and now-detection.checkedAt < 1 then return detection.frequency end
    detection.checkedAt = now
    detection.frequency = nil
    detection.receiver = nil
    local receivers = {
        vehicle = { find=vehicleFrequency, label="OCCUPIED VEHICLE RADIO" },
        portable = { find=portableFrequency, label="CARRIED PORTABLE RADIO" },
        nearby = { find=worldFrequency, label="NEARBY PLACED RADIO" },
    }
    for _, receiverId in ipairs(Config.receiverPriority or {"vehicle","portable","nearby"}) do
        local receiver = receivers[receiverId]
        local frequency = receiver and receiver.find(player) or nil
        if frequency then
            detection.frequency = frequency
            detection.receiver = { id=receiverId, label=receiver.label, frequency=frequency }
            break
        end
    end
    return detection.frequency
end
MeeksRadio.activeRadioFrequency = activeRadioFrequency
function MeeksRadio.activeRadioReceiver(player, force)
    activeRadioFrequency(player, force)
    return detection.receiver
end

local function stopPlayback()
    if playback.handle and playback.emitter then
        pcall(function() playback.emitter:stopSound(playback.handle) end)
    end
    playback = { frequency = nil, trackId = nil, handle = nil, emitter = nil }
end

local function updatePlayback()
    local player = getPlayer()
    local frequency = activeRadioFrequency(player, false)
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
    if elapsed > (tonumber(Config.playbackStartGraceSeconds) or 2) then return end

    local emitter = player:getEmitter()
    local ok, handle = pcall(function() return emitter:playSound(track.sound) end)
    if ok then
        playback = { frequency = frequency, trackId = wanted, handle = handle, emitter = emitter }
        local station = Config.station(frequency)
        local volume = station and tonumber(station.volume) or nil
        if handle and volume then
            volume = math.max(0, math.min(1, volume))
            -- Audio method availability differs between Build 42 patches.
            pcall(function()
                if emitter.setVolume then emitter:setVolume(handle, volume) end
            end)
        end
    end
end

local function showRadioBroadcast(args)
    local player = getPlayer()
    local frequency = Config.normalizeFrequency(args.frequency)
    if not player or not frequency or activeRadioFrequency(player, true) ~= frequency then return end
    local id = math.floor(tonumber(args.id) or 0)
    if id <= lastBroadcastId then return end
    local now = getTimestamp and getTimestamp() or os.time()
    if tonumber(args.expiresAt) and now > tonumber(args.expiresAt) then return end
    lastBroadcastId = id
    local kind = string.upper(tostring(args.kind or "announcement"))
    local message = "[RADIO " .. kind .. "] " .. tostring(args.text or "")
    print("[Radio Frequencies] " .. message)
    if HaloTextHelper then
        pcall(function()
            if string.lower(tostring(args.kind or "")) == "emergency" and HaloTextHelper.addBadText then
                HaloTextHelper.addBadText(player, message)
            elseif HaloTextHelper.addText then
                HaloTextHelper.addText(player, message)
            elseif HaloTextHelper.addBadText then
                HaloTextHelper.addBadText(player, message)
            end
        end)
    end
end

local function onServerCommand(module, command, args)
    if module ~= Config.module or type(args) ~= "table" then return end
    if command == "stationState" then
        local frequency = Config.normalizeFrequency(args.frequency)
        if frequency then stationStates[frequency] = args end
        updatePlayback()
    elseif command == "radioBroadcast" then
        showRadioBroadcast(args)
    elseif command == "error" and args.message then
        print("[Radio Frequencies] " .. tostring(args.message))
        if HaloTextHelper and getPlayer() then
            HaloTextHelper.addBadText(getPlayer(), "Radio Frequencies: " .. tostring(args.message))
        end
    elseif command == "permissions" then
        permissions.helloAcknowledged = true
        permissions.isDj = args.isDj == true
        permissions.isAdmin = args.isAdmin == true
        permissions.stationPermissions = {}
        for frequency, value in pairs(args.stationPermissions or {}) do
            local normalized = Config.normalizeFrequency(frequency)
            if normalized and type(value) == "table" then permissions.stationPermissions[normalized] = value end
        end
        permissions.serverCatalogVersion = args.catalogVersion
        permissions.serverProtocolVersion = args.protocolVersion
        permissions.catalogMatch = args.catalogMatch == true and tostring(args.catalogVersion) == tostring(Config.catalogVersion)
        permissions.protocolMatch = args.protocolMatch == true and tostring(args.protocolVersion) == tostring(Config.protocolVersion)
        if not permissions.catalogMatch then
            print("[Meeks Radio] Catalog mismatch; client=" .. tostring(Config.catalogVersion) .. " server=" .. tostring(args.catalogVersion))
        end
        if not permissions.protocolMatch then
            print("[Meeks Radio] Protocol mismatch; client=" .. tostring(Config.protocolVersion) .. " server=" .. tostring(args.protocolVersion))
        end
    end
end

local function requestHello()
    hello.lastSentAt = getTimestamp and getTimestamp() or os.time()
    sendClientCommand(Config.module, "hello", { catalogVersion = Config.catalogVersion, protocolVersion = Config.protocolVersion })
end

local function updateConnection()
    if permissions.helloAcknowledged then return end
    local now = getTimestamp and getTimestamp() or os.time()
    if now - hello.lastSentAt >= hello.retrySeconds then requestHello() end
end

Events.OnServerCommand.Add(onServerCommand)
Events.OnPlayerUpdate.Add(updatePlayback)
Events.OnPlayerUpdate.Add(updateConnection)
Events.OnCreatePlayer.Add(requestHello)
