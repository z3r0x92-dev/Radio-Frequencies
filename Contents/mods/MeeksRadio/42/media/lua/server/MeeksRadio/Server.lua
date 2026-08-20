require "MeeksRadio/Config"
require "MeeksRadio/Catalog"

local Config = MeeksRadio.Config
local state = { stations = {}, djs = {}, cooldowns = {}, schedules = {}, oneTimeFired = {}, nextBroadcastId = 1 }
local lastTick = 0
local lastBroadcastAt = 0
local stateDirty = false
local lastStateTransmit = 0
local permissionSnapshots = {}

local compatibleClients = {}

local function nowSeconds()
    return getTimestamp and getTimestamp() or os.time()
end

local function username(player)
    if type(player) == "string" then return player end
    if not player then return "" end
    local ok, value = pcall(function() return player:getUsername() end)
    return ok and tostring(value or "") or ""
end

local function isAdmin(player)
    if not player then return false end
    local level = tostring(player:getAccessLevel() or "")
    return level ~= "" and level ~= "None" and level ~= "none" and level ~= "player"
end

local function shiftAllows(user, frequency)
    local shifts = Config.djShifts or {}
    if #shifts == 0 then return true end
    local now = nowSeconds()
    for _, shift in ipairs(shifts) do
        if type(shift) == "table" and string.lower(tostring(shift.username or "")) == user and
           Config.normalizeFrequency(shift.frequency) == Config.normalizeFrequency(frequency) and
           now >= (tonumber(shift.startsAt) or math.huge) and now <= (tonumber(shift.endsAt) or -math.huge) then
            return true
        end
    end
    return false
end

local function isDj(player, frequency)
    if isAdmin(player) then return true end
    local user = string.lower(username(player))
    if state.djs[user] ~= true or not shiftAllows(user, frequency) then return false end
    local station = Config.station(frequency)
    local allowed = station and station.allowedDjs or {}
    if #allowed == 0 then return true end
    for _, name in ipairs(allowed) do
        if string.lower(tostring(name)) == user then return true end
    end
    return false
end

local function isDjAnywhere(player)
    if isAdmin(player) then return true end
    if state.djs[string.lower(username(player))] ~= true then return false end
    if #(Config.djShifts or {}) == 0 then return true end
    for frequency, _ in pairs(Config.stations) do
        if isDj(player, frequency) then return true end
    end
    return false
end

local function saveState()
    stateDirty = true
end

local function flushState(force)
    local now = nowSeconds()
    if stateDirty and (force or now - lastStateTransmit >= 5) and ModData and ModData.transmit then
        ModData.transmit("MeeksRadioState")
        stateDirty = false
        lastStateTransmit = now
    end
end

local function stationPermission(player, frequency)
    if isAdmin(player) then return true, "administrator" end
    local user = string.lower(username(player))
    if state.djs[user] ~= true then return false, "DJ assignment required" end
    if not shiftAllows(user, frequency) then return false, "no active shift for this station" end
    local station = Config.station(frequency)
    local allowed = station and station.allowedDjs or {}
    if #allowed > 0 then
        for _, name in ipairs(allowed) do
            if string.lower(tostring(name)) == user then return true, "active DJ shift" end
        end
        return false, "not on this station's DJ allowlist"
    end
    return true, "active DJ shift"
end

local function permissionPayload(player, catalogMatch, protocolMatch)
    local stations = {}
    local signatureParts = {}
    for frequency, _ in pairs(Config.stations) do
        local allowed, reason = stationPermission(player, frequency)
        stations[tostring(frequency)] = { allowed = allowed, reason = reason }
        signatureParts[#signatureParts + 1] = tostring(frequency) .. ":" .. tostring(allowed) .. ":" .. reason
    end
    table.sort(signatureParts)
    local payload = {
        isDj = isDjAnywhere(player), isAdmin = isAdmin(player), stationPermissions = stations,
        catalogVersion = Config.catalogVersion, protocolVersion = Config.protocolVersion,
        catalogMatch = catalogMatch ~= false, protocolMatch = protocolMatch ~= false,
    }
    return payload, table.concat(signatureParts, "|") .. ":" .. tostring(payload.isAdmin)
end

local function sendPermissions(player, catalogMatch, protocolMatch)
    local payload, signature = permissionPayload(player, catalogMatch, protocolMatch)
    sendServerCommand(player, Config.module, "permissions", payload)
    permissionSnapshots[string.lower(username(player))] = signature
end

local function stationState(frequency)
    local frequencyKey = Config.normalizeFrequency(frequency)
    if not frequencyKey or not Config.stations[frequencyKey] then return nil end
    if type(state.stations[frequencyKey]) ~= "table" then
        if state.stations[frequencyKey] ~= nil then
            print("[Meeks Radio] Reset malformed persisted state for station " .. tostring(frequencyKey))
        end
        state.stations[frequencyKey] = {
            frequency = frequencyKey,
            queue = {},
            locked = false,
            stopped = false,
            current = nil,
            startedAt = nil,
            endsAt = nil,
            revision = 0,
            bulletins = {},
            activeBulletin = nil,
            requests = {},
        }
    end
    return state.stations[frequencyKey]
end

local function publicStation(s)
    local queue = {}
    for index, entry in ipairs(s.queue) do
        queue[index] = { id = entry.id, queuedBy = entry.queuedBy }
    end
    local requests = {}
    for index, entry in ipairs(s.requests or {}) do
        requests[index] = { id=entry.id, trackId=entry.trackId, requestedBy=entry.requestedBy, requestedAt=entry.requestedAt }
    end
    return {
        frequency = s.frequency,
        locked = s.locked,
        stopped = s.stopped == true,
        currentTrackId = s.current and s.current.id or nil,
        startedAt = s.startedAt,
        endsAt = s.endsAt,
        queueLength = #s.queue,
        queue = queue,
        revision = s.revision,
        activeBulletin = s.activeBulletin,
        bulletins = s.bulletins,
        requests = requests,
        serverTime = nowSeconds(),
    }
end

local function cleanBroadcastText(value)
    local text = tostring(value or "")
    text = string.gsub(text, "[%c]", " ")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    text = string.gsub(text, "%s+", " ")
    local maximum = math.max(32, math.floor(tonumber(Config.maxBroadcastLength) or 240))
    if #text > maximum then text = string.sub(text, 1, maximum) end
    return text
end

local function validBroadcastKind(value)
    local kind = string.lower(tostring(value or "announcement"))
    if not (MeeksRadio.BroadcastKinds and MeeksRadio.BroadcastKinds[kind]) then return nil end
    return kind
end

local broadcast

local function issueBroadcast(s, kind, text, author, scheduledId)
    kind = validBroadcastKind(kind)
    text = cleanBroadcastText(text)
    if not s or not kind or text == "" then return false end
    local issuedAt = nowSeconds()
    local bulletin = {
        id = math.max(1, math.floor(tonumber(state.nextBroadcastId) or 1)),
        frequency = s.frequency,
        kind = kind,
        text = text,
        author = tostring(author or "SERVER"),
        scheduledId = scheduledId,
        issuedAt = issuedAt,
        expiresAt = issuedAt + math.max(3, math.floor(tonumber(Config.broadcastDisplaySeconds) or 12)),
    }
    state.nextBroadcastId = bulletin.id + 1
    s.activeBulletin = bulletin
    if type(s.bulletins) ~= "table" then s.bulletins = {} end
    table.insert(s.bulletins, 1, bulletin)
    local limit = math.max(1, math.floor(tonumber(Config.broadcastHistoryLimit) or 20))
    while #s.bulletins > limit do table.remove(s.bulletins) end
    sendServerCommand(Config.module, "radioBroadcast", bulletin)
    broadcast(s)
    return true
end

broadcast = function(s)
    s.revision = s.revision + 1
    sendServerCommand(Config.module, "stationState", publicStation(s))
    saveState()
end


local function sortedCatalogTracks()
    local tracks = {}
    for _, track in pairs(MeeksRadio.Catalog or {}) do
        if MeeksRadio.getTrack(track.id) then tracks[#tracks + 1] = track end
    end
    table.sort(tracks, function(a, b)
        return string.lower(tostring(a.title or a.id)) < string.lower(tostring(b.title or b.id))
    end)
    return tracks
end

local function nextCatalogEntry(previousId)
    local tracks = sortedCatalogTracks()
    if #tracks == 0 then return nil end
    local nextIndex = 1
    for index, track in ipairs(tracks) do
        if track.id == previousId then
            nextIndex = (index % #tracks) + 1
            break
        end
    end
    local track = tracks[nextIndex]
    return { id = track.id, duration = tonumber(track.duration), queuedBy = "station-autoplay" }
end

local function startNext(s, allowCatalogFallback)
    local previousId = s.current and s.current.id or nil
    local entry = table.remove(s.queue, 1)
    if not entry and allowCatalogFallback and s.stopped ~= true then
        entry = nextCatalogEntry(previousId)
    end
    s.current = entry
    if entry then
        s.stopped = false
        s.startedAt = nowSeconds()
        s.endsAt = s.startedAt + entry.duration
    else
        s.startedAt = nil
        s.endsAt = nil
    end
    broadcast(s)
end

local function reject(player, message)
    print("[Meeks Radio] Rejected " .. tostring(username(player)) .. ": " .. tostring(message))
    sendServerCommand(player, Config.module, "error", { message = message })
end

local function audit(player, action, detail)
    print("[Meeks Radio] " .. tostring(action) .. " by " .. tostring(username(player)) ..
        (detail and (": " .. tostring(detail)) or ""))
end

local function handleRemove(player, args)
    local s = stationState(args.frequency)
    if not isDj(player, s and s.frequency) then return reject(player, "DJ permission or active shift required") end
    local index = math.floor(tonumber(args.index) or 0)
    local entry = s and s.queue[index] or nil
    if not entry then return reject(player, "Unknown queue entry") end
    if not isAdmin(player) and string.lower(entry.queuedBy or "") ~= string.lower(username(player)) then
        return reject(player, "You may only remove your own queued tracks")
    end
    table.remove(s.queue, index)
    audit(player, "queue remove", tostring(s.frequency) .. " index=" .. tostring(index))
    broadcast(s)
end

local function rateLimited(player)
    local key = string.lower(username(player))
    local now = nowSeconds()
    if (state.cooldowns[key] or 0) > now then return true end
    state.cooldowns[key] = now + Config.requestCooldownSeconds
    return false
end

local function handleQueue(player, args)
    local s = stationState(args.frequency)
    if not isDj(player, s and s.frequency) then return reject(player, "DJ permission or active shift required") end
    local track = MeeksRadio.getTrack(args.trackId)
    if not s or not track then return reject(player, "Unknown station or track") end
    if s.locked and not isAdmin(player) then return reject(player, "Station is locked") end
    if #s.queue >= Config.maxQueueLength then return reject(player, "Queue is full") end
    table.insert(s.queue, { id = track.id, duration = tonumber(track.duration), queuedBy = username(player) })
    s.stopped = false
    audit(player, "queue add", tostring(s.frequency) .. " track=" .. tostring(track.id))
    if not s.current then startNext(s) else broadcast(s) end
end

local function handleRequest(player, command, args)
    local s = stationState(args.frequency)
    if not s then return reject(player, "Unknown station") end
    if type(s.requests) ~= "table" then s.requests = {} end
    if command == "requestTrack" then
        if Config.normalizeFrequency(args.receiverFrequency) ~= s.frequency then
            return reject(player, "Tune an active receiver to this station before requesting")
        end
        local track = MeeksRadio.getTrack(args.trackId)
        if not track then return reject(player, "Unknown requested track") end
        if #s.requests >= math.max(1, tonumber(Config.maxRequestsPerStation) or 30) then return reject(player, "Request list is full") end
        local user = username(player)
        for _, request in ipairs(s.requests) do
            if request.trackId == track.id and string.lower(request.requestedBy or "") == string.lower(user) then
                return reject(player, "You already requested that track")
            end
        end
        local request = { id=nowSeconds() .. "-" .. user, trackId=track.id, requestedBy=user, requestedAt=nowSeconds() }
        table.insert(s.requests, request)
        audit(player, "track request", tostring(s.frequency) .. " track=" .. track.id)
        broadcast(s)
        return
    end
    if not isDj(player, s.frequency) then return reject(player, "DJ permission or active shift required") end
    local index = math.floor(tonumber(args.index) or 0)
    local request = s.requests[index]
    if not request then return reject(player, "Unknown request") end
    if command == "approveRequest" then
        local track = MeeksRadio.getTrack(request.trackId)
        if not track or #s.queue >= Config.maxQueueLength then return reject(player, "Track unavailable or queue full") end
        table.insert(s.queue, { id=track.id, duration=tonumber(track.duration), queuedBy="request:" .. tostring(request.requestedBy) })
        audit(player, "request approved", tostring(s.frequency) .. " track=" .. track.id)
        table.remove(s.requests, index)
        if not s.current then startNext(s) else broadcast(s) end
    elseif command == "rejectRequest" then
        audit(player, "request rejected", tostring(s.frequency) .. " track=" .. tostring(request.trackId))
        table.remove(s.requests, index)
        broadcast(s)
    end
end

local function handleAdmin(player, command, args)
    if not isAdmin(player) then return reject(player, "Admin permission required") end
    if command == "grant" or command == "revoke" then
        local target = string.lower(tostring(args.username or ""))
        if target == "" then return reject(player, "Username required") end
        state.djs[target] = command == "grant" or nil
        audit(player, command .. " DJ", target)
        saveState()
        return
    end

    local s = stationState(args.frequency)
    if not s then return reject(player, "Unknown station") end
    if command == "lock" then
        s.locked = args.locked == true
        audit(player, s.locked and "station lock" or "station unlock", tostring(s.frequency))
        broadcast(s)
    elseif command == "skip" then
        audit(player, "station skip", tostring(s.frequency))
        s.stopped = false
        startNext(s, true)
    elseif command == "stop" then
        audit(player, "station stop", tostring(s.frequency))
        s.queue = {}
        s.current = nil
        s.startedAt = nil
        s.endsAt = nil
        s.stopped = true
        broadcast(s)
    elseif command == "emergency" then
        local track = MeeksRadio.getTrack(args.trackId)
        if not track then return reject(player, "Unknown emergency track") end
        audit(player, "emergency override", tostring(s.frequency) .. " track=" .. tostring(track.id))
        s.queue = {}
        local cue = MeeksRadio.getTrack(Config.emergencyCueTrackId)
        if cue and cue.id ~= track.id then
            s.current = { id = cue.id, duration = tonumber(cue.duration), queuedBy = "emergency-cue" }
            table.insert(s.queue, { id = track.id, duration = tonumber(track.duration), queuedBy = username(player) })
        else
            s.current = { id = track.id, duration = tonumber(track.duration), queuedBy = username(player) }
        end
        s.startedAt = nowSeconds()
        s.endsAt = s.startedAt + s.current.duration
        issueBroadcast(s, "emergency", args.message or ("Emergency override: " .. tostring(track.title or track.id)), username(player))
    elseif command == "broadcast" then
        local kind = validBroadcastKind(args.kind)
        local text = cleanBroadcastText(args.text)
        local now = nowSeconds()
        if not kind then return reject(player, "Unknown broadcast category") end
        if text == "" then return reject(player, "Broadcast text required") end
        if now - lastBroadcastAt < math.max(1, tonumber(Config.broadcastCooldownSeconds) or 10) then
            return reject(player, "Broadcast cooldown is active")
        end
        lastBroadcastAt = now
        audit(player, "radio broadcast", tostring(s.frequency) .. " kind=" .. kind .. " text=" .. text)
        issueBroadcast(s, kind, text, username(player))
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= Config.module or type(args) ~= "table" then return end
    local clientKey = string.lower(username(player))
    if command == "hello" then
        local catalogMatch = tostring(args.catalogVersion) == tostring(Config.catalogVersion)
        local protocolMatch = tostring(args.protocolVersion) == tostring(Config.protocolVersion)
        compatibleClients[clientKey] = catalogMatch and protocolMatch
        if not compatibleClients[clientKey] then
            print("[Meeks Radio] Version mismatch for " .. tostring(username(player)) ..
                ": client protocol=" .. tostring(args.protocolVersion) .. " catalog=" .. tostring(args.catalogVersion) ..
                "; server protocol=" .. tostring(Config.protocolVersion) .. " catalog=" .. tostring(Config.catalogVersion))
        end
    elseif command ~= "status" and compatibleClients[clientKey] ~= true then
        return reject(player, "Meeks Radio client/server version mismatch; reconnect or update the mod")
    end
    if rateLimited(player) then return reject(player, "Please slow down") end
    if command == "queue" then
        handleQueue(player, args)
    elseif command == "remove" then
        handleRemove(player, args)
    elseif command == "hello" then
        sendPermissions(player,
            tostring(args.catalogVersion) == tostring(Config.catalogVersion),
            tostring(args.protocolVersion) == tostring(Config.protocolVersion))
        for _, s in pairs(state.stations) do
            sendServerCommand(player, Config.module, "stationState", publicStation(s))
        end
    elseif command == "status" then
        local s = stationState(args.frequency)
        if s then sendServerCommand(player, Config.module, "stationState", publicStation(s)) end
    elseif command == "requestTrack" or command == "approveRequest" or command == "rejectRequest" then
        handleRequest(player, command, args)
    elseif command == "grant" or command == "revoke" or command == "lock" or
           command == "skip" or command == "stop" or command == "emergency" or command == "broadcast" then
        handleAdmin(player, command, args)
    end
end

local function clearClientCompatibility(player)
    local key = string.lower(username(player))
    if key ~= "" then compatibleClients[key] = nil; permissionSnapshots[key] = nil end
end

local function refreshOnlinePermissions()
    if not getOnlinePlayers then return end
    local ok, players = pcall(getOnlinePlayers)
    if not ok or not players then return end
    local scanOk, scanError = pcall(function()
        for index = 0, players:size() - 1 do
            local player = players:get(index)
            local key = string.lower(username(player))
            if compatibleClients[key] == true then
                local _, signature = permissionPayload(player, true, true)
                if permissionSnapshots[key] ~= signature then sendPermissions(player, true, true) end
            end
        end
    end)
    if not scanOk then print("[Meeks Radio] Permission refresh skipped: " .. tostring(scanError)) end
end

local function tickStations()
    local now = nowSeconds()
    if now <= lastTick then return end
    lastTick = now
    for _, s in pairs(state.stations) do
        if s.current and s.endsAt and now >= s.endsAt then startNext(s, true) end
        if s.activeBulletin and tonumber(s.activeBulletin.expiresAt) and now >= tonumber(s.activeBulletin.expiresAt) then
            s.activeBulletin = nil
            broadcast(s)
        end
    end
    for _, entry in ipairs(Config.scheduledBroadcasts or {}) do
        if type(entry) == "table" and entry.enabled == true and entry.id then
            local scheduleId = tostring(entry.id)
            local nextAt = tonumber(state.schedules[scheduleId]) or (now + math.max(1, tonumber(entry.initialDelaySeconds) or 60))
            if now >= nextAt then
                local s = stationState(entry.frequency)
                local interval = math.max(60, tonumber(entry.intervalSeconds) or 3600)
                if s and validBroadcastKind(entry.kind) and cleanBroadcastText(entry.text) ~= "" then
                    issueBroadcast(s, entry.kind, entry.text, "SERVER", scheduleId)
                    print("[Meeks Radio] Scheduled broadcast " .. scheduleId .. " on " .. tostring(s.frequency))
                else
                    print("[Meeks Radio] Skipped invalid scheduled broadcast " .. scheduleId)
                end
                state.schedules[scheduleId] = now + interval
                saveState()
            elseif state.schedules[scheduleId] == nil then
                state.schedules[scheduleId] = nextAt
                saveState()
            end
        end
    end
    for _, entry in ipairs(Config.oneTimeBroadcasts or {}) do
        if type(entry) == "table" and entry.enabled == true and entry.id then
            local scheduleId = tostring(entry.id)
            local fireAt = tonumber(entry.at)
            if fireAt and now >= fireAt and state.oneTimeFired[scheduleId] ~= true then
                local s = stationState(entry.frequency)
                if s and validBroadcastKind(entry.kind) and cleanBroadcastText(entry.text) ~= "" then
                    issueBroadcast(s, entry.kind, entry.text, "SERVER", scheduleId)
                    print("[Meeks Radio] One-time broadcast " .. scheduleId .. " fired")
                else
                    print("[Meeks Radio] Invalid one-time broadcast " .. scheduleId .. " marked complete")
                end
                state.oneTimeFired[scheduleId] = true
                saveState()
            end
        end
    end
    if now % 5 == 0 then refreshOnlinePermissions() end
    flushState(false)
end

local function finiteNumber(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
    return number
end

local function sanitizeStation(s, frequency)
    local changed = false
    s.frequency = frequency
    s.locked = s.locked == true
    s.stopped = s.stopped == true
    s.revision = math.max(0, math.floor(finiteNumber(s.revision) or 0))
    if type(s.bulletins) ~= "table" then
        s.bulletins = {}
        changed = true
    end
    local cleanBulletins = {}
    local historyLimit = math.max(1, math.floor(tonumber(Config.broadcastHistoryLimit) or 20))
    for _, bulletin in ipairs(s.bulletins) do
        if #cleanBulletins >= historyLimit then break end
        if type(bulletin) == "table" then
            local kind = validBroadcastKind(bulletin.kind)
            local text = cleanBroadcastText(bulletin.text)
            if kind and text ~= "" then
                cleanBulletins[#cleanBulletins + 1] = {
                    id = math.max(1, math.floor(finiteNumber(bulletin.id) or 1)),
                    frequency = frequency,
                    kind = kind,
                    text = text,
                    author = tostring(bulletin.author or "SERVER"),
                    scheduledId = bulletin.scheduledId and tostring(bulletin.scheduledId) or nil,
                    issuedAt = finiteNumber(bulletin.issuedAt) or nowSeconds(),
                    expiresAt = finiteNumber(bulletin.expiresAt) or 0,
                }
            else
                changed = true
            end
        else
            changed = true
        end
    end
    s.bulletins = cleanBulletins
    if type(s.requests) ~= "table" then
        s.requests = {}
        changed = true
    end
    local cleanRequests = {}
    for _, request in ipairs(s.requests) do
        local track = type(request) == "table" and MeeksRadio.getTrack(request.trackId) or nil
        if track and #cleanRequests < math.max(1, tonumber(Config.maxRequestsPerStation) or 30) then
            cleanRequests[#cleanRequests+1] = {
                id=tostring(request.id or (#cleanRequests+1)), trackId=track.id,
                requestedBy=tostring(request.requestedBy or "unknown"),
                requestedAt=finiteNumber(request.requestedAt) or nowSeconds(),
            }
        else
            changed = true
        end
    end
    s.requests = cleanRequests
    local active = type(s.activeBulletin) == "table" and s.activeBulletin or nil
    if active and finiteNumber(active.expiresAt) and finiteNumber(active.expiresAt) > nowSeconds() then
        s.activeBulletin = active
    else
        if s.activeBulletin ~= nil then changed = true end
        s.activeBulletin = nil
    end

    local cleanQueue = {}
    local originalQueueLength = type(s.queue) == "table" and #s.queue or 0
    if type(s.queue) == "table" then
        for _, entry in ipairs(s.queue) do
            local track = type(entry) == "table" and MeeksRadio.getTrack(entry.id) or nil
            if track then
                cleanQueue[#cleanQueue + 1] = {
                    id = track.id,
                    duration = tonumber(track.duration),
                    queuedBy = tostring(entry.queuedBy or "unknown"),
                }
                if tonumber(entry.duration) ~= tonumber(track.duration) then
                    changed = true
                    print("[Meeks Radio] Replaced stale queued duration on " .. tostring(frequency) ..
                        " for " .. tostring(track.id))
                end
            else
                changed = true
                print("[Meeks Radio] Removed missing/invalid queued track from " .. tostring(frequency) ..
                    ": " .. tostring(type(entry) == "table" and entry.id or entry))
            end
        end
    else
        changed = true
    end
    if #cleanQueue ~= originalQueueLength then changed = true end
    s.queue = cleanQueue

    local currentTrack = type(s.current) == "table" and MeeksRadio.getTrack(s.current.id) or nil
    if not currentTrack then
        if s.current ~= nil then
            print("[Meeks Radio] Removed missing/invalid current track from " .. tostring(frequency) ..
                ": " .. tostring(type(s.current) == "table" and s.current.id or s.current))
            changed = true
        end
        s.current = nil
        s.startedAt = nil
        s.endsAt = nil
        return changed
    end

    local catalogDuration = tonumber(currentTrack.duration)
    local storedDuration = tonumber(s.current.duration)
    s.current = {
        id = currentTrack.id,
        duration = catalogDuration,
        queuedBy = tostring(s.current.queuedBy or "unknown"),
    }
    local now = nowSeconds()
    local startedAt = finiteNumber(s.startedAt)
    local maximumFuture = now + (tonumber(Config.maxTimestampSkewSeconds) or 300)
    if not startedAt or startedAt <= 0 or startedAt > maximumFuture then
        print("[Meeks Radio] Reset invalid playback timestamp on " .. tostring(frequency))
        startedAt = now
        changed = true
    end
    local expectedEnd = startedAt + catalogDuration
    if storedDuration ~= catalogDuration then
        changed = true
        print("[Meeks Radio] Replaced stale current-track duration on " .. tostring(frequency) ..
            " for " .. tostring(currentTrack.id))
    end
    if finiteNumber(s.endsAt) ~= expectedEnd then
        changed = true
        print("[Meeks Radio] Repaired playback end timestamp on " .. tostring(frequency))
    end
    s.startedAt = startedAt
    s.endsAt = expectedEnd
    return changed
end

local function sanitizePersistedState()
    local changed = false
    for frequency, _ in pairs(Config.stations) do
        local s = stationState(frequency)
        if sanitizeStation(s, frequency) then changed = true end
        if not s.current and #s.queue > 0 then
            print("[Meeks Radio] Starting next valid queued track on " .. tostring(frequency))
            s.stopped = false
            startNext(s, false)
            changed = true
        end
    end
    local staleFrequencies = {}
    for frequency, _ in pairs(state.stations) do
        local normalized = Config.normalizeFrequency(frequency)
        if frequency ~= normalized or not Config.stations[normalized] then
            staleFrequencies[#staleFrequencies + 1] = frequency
        end
    end
    for _, frequency in ipairs(staleFrequencies) do
        state.stations[frequency] = nil
        changed = true
        print("[Meeks Radio] Removed persisted state for unknown/invalid station " .. tostring(frequency))
    end
    if changed then saveState() end
end

local function initializeState()
    state = ModData.getOrCreate("MeeksRadioState")
    if type(state.stations) ~= "table" then
        print("[Meeks Radio] Reset malformed persisted station collection")
        state.stations = {}
    end
    if type(state.djs) ~= "table" then
        print("[Meeks Radio] Reset malformed persisted DJ collection")
        state.djs = {}
    end
    if type(state.schedules) ~= "table" then state.schedules = {} end
    if type(state.oneTimeFired) ~= "table" then state.oneTimeFired = {} end
    state.nextBroadcastId = math.max(1, math.floor(finiteNumber(state.nextBroadcastId) or 1))
    state.cooldowns = {}
    for frequency, _ in pairs(Config.stations) do stationState(frequency) end
    sanitizePersistedState()
    tickStations()
    flushState(true)
end

MeeksRadio.ServerAPI = MeeksRadio.ServerAPI or {}
function MeeksRadio.ServerAPI.broadcast(frequency, kind, text, source)
    local s = stationState(frequency)
    if not s then return false end
    local ok = issueBroadcast(s, kind, text, source or "INTEGRATION")
    if ok then print("[Meeks Radio] Integration broadcast from " .. tostring(source or "INTEGRATION")) end
    return ok
end

local function onServerStarted()
    if Config.autoBroadcastServerStart then
        MeeksRadio.ServerAPI.broadcast(102800, "announcement", "Radio Frequencies is online. Monitor this station for server information.", "SERVER_START")
    end
end

local function onPlayerDeath(player)
    if not Config.autoBroadcastPlayerDeaths or not player then return end
    MeeksRadio.ServerAPI.broadcast(107900, "community", tostring(username(player)) .. " has died.", "PLAYER_DEATH")
end

Events.OnInitGlobalModData.Add(initializeState)
Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(tickStations)
if Events.OnServerStarted then Events.OnServerStarted.Add(onServerStarted) end
if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(onPlayerDeath) end
if Events.OnDisconnect then Events.OnDisconnect.Add(clearClientCompatibility) end
