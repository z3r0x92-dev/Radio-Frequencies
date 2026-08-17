require "MeeksRadio/Config"
require "MeeksRadio/Catalog"

local Config = MeeksRadio.Config
local state = { stations = {}, djs = {}, cooldowns = {} }

local function nowSeconds()
    return getTimestamp and getTimestamp() or os.time()
end

local function username(player)
    return player and player:getUsername() or ""
end

local function isAdmin(player)
    if not player then return false end
    local level = tostring(player:getAccessLevel() or "")
    return level ~= "" and level ~= "None" and level ~= "none" and level ~= "player"
end

local function isDj(player)
    return isAdmin(player) or state.djs[string.lower(username(player))] == true
end

local function stationState(frequency)
    local frequencyKey = Config.normalizeFrequency(frequency)
    if not frequencyKey or not Config.stations[frequencyKey] then return nil end
    if not state.stations[frequencyKey] then
        state.stations[frequencyKey] = {
            frequency = frequencyKey,
            queue = {},
            locked = false,
            current = nil,
            startedAt = nil,
            endsAt = nil,
            revision = 0,
        }
    end
    return state.stations[frequencyKey]
end

local function publicStation(s)
    return {
        frequency = s.frequency,
        locked = s.locked,
        currentTrackId = s.current and s.current.id or nil,
        startedAt = s.startedAt,
        endsAt = s.endsAt,
        queueLength = #s.queue,
        revision = s.revision,
        serverTime = nowSeconds(),
    }
end

local function broadcast(s)
    s.revision = s.revision + 1
    sendServerCommand(Config.module, "stationState", publicStation(s))
end

local function startNext(s)
    local entry = table.remove(s.queue, 1)
    s.current = entry
    if entry then
        s.startedAt = nowSeconds()
        s.endsAt = s.startedAt + entry.duration
    else
        s.startedAt = nil
        s.endsAt = nil
    end
    broadcast(s)
end

local function reject(player, message)
    sendServerCommand(player, Config.module, "error", { message = message })
end

local function rateLimited(player)
    local key = string.lower(username(player))
    local now = nowSeconds()
    if (state.cooldowns[key] or 0) > now then return true end
    state.cooldowns[key] = now + Config.requestCooldownSeconds
    return false
end

local function handleQueue(player, args)
    if not isDj(player) then return reject(player, "DJ permission required") end
    local s = stationState(args.frequency)
    local track = MeeksRadio.getTrack(args.trackId)
    if not s or not track then return reject(player, "Unknown station or track") end
    if s.locked and not isAdmin(player) then return reject(player, "Station is locked") end
    if #s.queue >= Config.maxQueueLength then return reject(player, "Queue is full") end
    table.insert(s.queue, { id = track.id, duration = tonumber(track.duration), queuedBy = username(player) })
    if not s.current then startNext(s) else broadcast(s) end
end

local function handleAdmin(player, command, args)
    if not isAdmin(player) then return reject(player, "Admin permission required") end
    if command == "grant" or command == "revoke" then
        local target = string.lower(tostring(args.username or ""))
        if target == "" then return reject(player, "Username required") end
        state.djs[target] = command == "grant" or nil
        sendServerCommand(Config.module, "djChanged", { username = target, approved = command == "grant" })
        return
    end

    local s = stationState(args.frequency)
    if not s then return reject(player, "Unknown station") end
    if command == "lock" then
        s.locked = args.locked == true
        broadcast(s)
    elseif command == "skip" then
        startNext(s)
    elseif command == "stop" then
        s.queue = {}
        s.current = nil
        s.startedAt = nil
        s.endsAt = nil
        broadcast(s)
    elseif command == "emergency" then
        local track = MeeksRadio.getTrack(args.trackId)
        if not track then return reject(player, "Unknown emergency track") end
        s.queue = {}
        s.current = { id = track.id, duration = tonumber(track.duration), queuedBy = username(player) }
        s.startedAt = nowSeconds()
        s.endsAt = s.startedAt + s.current.duration
        broadcast(s)
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= Config.module or type(args) ~= "table" then return end
    if rateLimited(player) then return reject(player, "Please slow down") end
    if command == "queue" then
        handleQueue(player, args)
    elseif command == "status" then
        local s = stationState(args.frequency)
        if s then sendServerCommand(player, Config.module, "stationState", publicStation(s)) end
    elseif command == "grant" or command == "revoke" or command == "lock" or
           command == "skip" or command == "stop" or command == "emergency" then
        handleAdmin(player, command, args)
    end
end

local function tickStations()
    local now = nowSeconds()
    for _, s in pairs(state.stations) do
        if s.current and s.endsAt and now >= s.endsAt then startNext(s) end
    end
end

for frequency, _ in pairs(Config.stations) do stationState(frequency) end
Events.OnClientCommand.Add(onClientCommand)
Events.EveryOneMinute.Add(tickStations)
