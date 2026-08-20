require "MeeksRadio/Config"

MeeksRadio = MeeksRadio or {}

local themes = {
    ProjectZomboid = {
        id="ProjectZomboid", name="PROJECT ZOMBOID",
        bg={0.72,0.72,0.72,1}, panel={0.015,0.025,0.020,1},
        accent={0.00,0.00,0.50,1}, bright={0.92,0.92,0.92,1},
        live={0.15,1.00,0.25,1}, text={0.56,1.00,0.60,1},
        muted={0.66,0.74,0.67,1}, line={0.08,0.22,0.10,1},
        button={0.72,0.72,0.72,1}, buttonPrimary={0.82,0.82,0.82,1},
        buttonHover={0.90,0.90,0.90,1}, buttonText={0,0,0,1},
        label={0.08,0.08,0.08,1}, titleText={1,1,1,1},
    },
    MeeksProtocol = {
        id="MeeksProtocol", name="MEEKS PROTOCOL",
        bg={0.031,0.035,0.055,0.98}, panel={0.047,0.051,0.075,0.97},
        accent={0.878,0.220,0.659,1}, bright={0.973,0.157,0.753,1},
        live={0.400,0.898,0.545,1}, text={0.94,0.94,0.97,1},
        muted={0.64,0.61,0.69,1}, line={0.290,0.090,0.231,0.92},
        button={0.12,0.10,0.15,1}, buttonPrimary={0.32,0.08,0.24,1},
        buttonHover={0.44,0.10,0.34,1}, buttonText={0.96,0.90,0.96,1},
        label={0.72,0.68,0.76,1}, titleText={1,1,1,1},
    },
    Military = {
        id="Military", name="MILITARY",
        bg={0.16,0.18,0.12,1}, panel={0.025,0.035,0.020,1},
        accent={0.24,0.34,0.16,1}, bright={0.76,0.86,0.38,1},
        live={0.48,0.86,0.32,1}, text={0.70,0.86,0.48,1},
        muted={0.55,0.62,0.42,1}, line={0.18,0.28,0.12,1},
        button={0.24,0.27,0.18,1}, buttonPrimary={0.34,0.39,0.22,1},
        buttonHover={0.44,0.50,0.28,1}, buttonText={0.88,0.90,0.72,1},
        label={0.82,0.84,0.66,1}, titleText={0.92,0.94,0.78,1},
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
