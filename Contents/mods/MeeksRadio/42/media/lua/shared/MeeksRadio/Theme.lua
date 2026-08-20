require "MeeksRadio/Config"

MeeksRadio = MeeksRadio or {}

local themes = {
    ProjectZomboid = {
        id="ProjectZomboid", name="PROJECT ZOMBOID",
        bg={0.035,0.035,0.045,0.97}, panel={0.065,0.065,0.080,0.96},
        accent={0.92,0.92,0.92,1}, bright={0.92,0.92,0.95,1},
        live={0.30,0.90,0.55,1}, text={0.92,0.92,0.95,1},
        muted={0.58,0.59,0.64,1}, line={0.20,0.20,0.24,0.85},
        button={0.055,0.055,0.068,1}, buttonPrimary={0.085,0.085,0.100,1},
        buttonHover={0.11,0.11,0.13,1}, buttonText={0.92,0.92,0.95,1},
        label={0.77,0.79,0.82,1}, titleText={0.92,0.92,0.95,1},
    },
    MeeksProtocol = {
        id="MeeksProtocol", name="MEEKS PROTOCOL",
        bg={0.020,0.020,0.026,0.98}, panel={0.038,0.038,0.048,0.98},
        accent={1.00,0.05,0.55,1}, bright={1.00,0.16,0.67,1},
        live={0.30,0.90,0.55,1}, text={0.92,0.92,0.95,1},
        muted={0.58,0.59,0.64,1}, line={0.18,0.18,0.22,0.95},
        button={0.055,0.055,0.068,1}, buttonPrimary={0.075,0.075,0.090,1},
        buttonHover={0.11,0.11,0.13,1}, buttonText={0.92,0.92,0.95,1},
        label={0.70,0.70,0.75,1}, titleText={0.92,0.92,0.95,1},
    },
    Military = {
        id="Military", name="MILITARY",
        bg={0.035,0.045,0.025,0.97}, panel={0.075,0.085,0.050,0.96},
        accent={0.48,0.62,0.25,1}, bright={0.83,0.82,0.67,1},
        live={0.56,0.72,0.30,1}, text={0.83,0.82,0.67,1},
        muted={0.53,0.55,0.43,1}, line={0.24,0.30,0.14,0.90},
        button={0.060,0.070,0.040,1}, buttonPrimary={0.105,0.115,0.070,1},
        buttonHover={0.14,0.15,0.09,1}, buttonText={0.83,0.82,0.67,1},
        label={0.72,0.74,0.64,1}, titleText={0.83,0.82,0.67,1},
    },
}

local themeOrder = { "ProjectZomboid", "MeeksProtocol", "Military" }

function MeeksRadio.getInterfaceTheme()
    local selected = MeeksRadio.Config.interfaceTheme or 2
    if SandboxVars and SandboxVars.MeeksRadio and SandboxVars.MeeksRadio.InterfaceTheme ~= nil then
        selected = SandboxVars.MeeksRadio.InterfaceTheme
    end
    if type(selected) == "number" then selected = themeOrder[math.floor(selected)] end
    selected = tostring(selected or "MeeksProtocol")
    return themes[selected] or themes.MeeksProtocol
end
