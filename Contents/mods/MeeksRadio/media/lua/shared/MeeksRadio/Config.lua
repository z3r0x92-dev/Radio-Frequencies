MeeksRadio = MeeksRadio or {}

MeeksRadio.Config = {
    module = "MeeksRadio",
    protocolVersion = 1,
    frequencyTolerance = 0.01,
    requestCooldownSeconds = 2,
    maxQueueLength = 20,
    catalogVersion = "1",
    allowPortableRadios = true,
    allowWorldRadios = false,
    allowVehicleRadios = false,
    stations = {
        [101200] = { name = "Meeks FM", volume = 0.8 },
        [104600] = { name = "Protocol Radio", volume = 0.8 },
        [107900] = { name = "Emergency Override", volume = 1.0 },
    },
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
