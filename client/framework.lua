-- Theme sync: read dei_hud_prefs KVP on startup
Citizen.CreateThread(function()
    Wait(500)
    local raw = GetResourceKvpString('dei_hud_prefs')
    local theme = 'dark'
    local lightMode = false
    if raw and raw ~= '' then
        local prefs = json.decode(raw)
        if prefs then
            theme = prefs.theme or 'dark'
            lightMode = prefs.lightMode or false
        end
    end
    SendNUIMessage({ action = 'setTheme', theme = theme, lightMode = lightMode })
end)

-- Listen for theme changes from dei_hud
RegisterNetEvent('dei:themeChanged', function(theme, lightMode)
    SendNUIMessage({ action = 'setTheme', theme = theme, lightMode = lightMode })
end)
