local myServerId = GetPlayerServerId(PlayerId())
local score, screenScore, idleTime, mult, total, cash = 0, 0, 0, 0.2, 0, 0
local isDrifting = false
local comboCount = 0
local lastDriftTime = 0
local COMBO_WINDOW = 2500 -- ms to maintain combo between drifts

-- Personal best
local personalBest = 0

-- Session stats
local sessionActive = false
local sessionTotalScore = 0
local sessionBestDrift = 0
local sessionTotalCombos = 0
local sessionMoneyEarned = 0
local sessionDriftStart = 0
local sessionTotalDriftTime = 0
local sessionLastActivity = 0
local sessionSummaryShown = false

-- Load personal best from KVP
if Config.ShowPersonalBest then
    local raw = GetResourceKvpString('dei_drift_pb')
    if raw and raw ~= '' then
        personalBest = tonumber(raw) or 0
    end
end

-- Send personal best to NUI on startup
Citizen.CreateThread(function()
    Wait(1000)
    if Config.ShowPersonalBest and personalBest > 0 then
        SendNUIMessage({ type = 'personalBest', score = personalBest })
    end
    -- Send config to NUI
    SendNUIMessage({
        type = 'configUpdate',
        enableSounds = Config.EnableSounds,
        soundVolume = Config.SoundVolume,
        showPersonalBest = Config.ShowPersonalBest,
        comboWindow = COMBO_WINDOW
    })
end)

-- Leaderboard command
if Config.EnableLeaderboard then
    RegisterCommand('driftboard', function()
        SendNUIMessage({ type = 'showLeaderboard' })
        SetNuiFocus(true, true)
    end, false)

    RegisterNUICallback('closeLeaderboard', function(_, cb)
        SendNUIMessage({ type = 'hideLeaderboard' })
        SetNuiFocus(false, false)
        cb('ok')
    end)

    -- Pending callback for leaderboard response (avoid event handler stacking)
    local pendingLeaderboardCb = nil

    RegisterNetEvent('dei_drift:getLeaderboard:response')
    AddEventHandler('dei_drift:getLeaderboard:response', function(data)
        if pendingLeaderboardCb then
            pendingLeaderboardCb(data)
            pendingLeaderboardCb = nil
        end
    end)

    RegisterNUICallback('requestLeaderboard', function(_, cb)
        local done = false
        local result = nil
        pendingLeaderboardCb = function(data)
            result = data
            done = true
        end
        TriggerServerEvent('dei_drift:getLeaderboard:request', myServerId)
        local timeout = 0
        while not done and timeout < 5000 do
            Wait(50)
            timeout = timeout + 50
        end
        cb(result or {})
    end)
end

-- Session summary timeout check
Citizen.CreateThread(function()
    while true do
        Wait(1000)
        if Config.ShowSessionSummary and sessionActive then
            local now = GetGameTimer()
            local playerPed = PlayerPedId()
            local vehicle = GetVehiclePedIsUsing(playerPed)
            local exitedVehicle = not vehicle or GetPedInVehicleSeat(vehicle, -1) ~= playerPed

            if exitedVehicle or (now - sessionLastActivity > 30000) then
                -- Show session summary
                if not sessionSummaryShown and sessionTotalScore > 0 then
                    sessionSummaryShown = true
                    SendNUIMessage({
                        type = 'sessionSummary',
                        totalScore = sessionTotalScore,
                        bestDrift = sessionBestDrift,
                        totalCombos = sessionTotalCombos,
                        moneyEarned = sessionMoneyEarned,
                        driftTime = math.floor(sessionTotalDriftTime / 1000)
                    })
                    -- Reset session
                    sessionActive = false
                    sessionTotalScore = 0
                    sessionBestDrift = 0
                    sessionTotalCombos = 0
                    sessionMoneyEarned = 0
                    sessionTotalDriftTime = 0
                end
            end
        end
    end
end)

-- Main drift detection loop
local lastNuiUpdate = 0
local wasInVehicle = false
Citizen.CreateThread(function()
    while true do
        local playerPed = PlayerPedId()
        local vehicle = GetVehiclePedIsUsing(playerPed)
        local inVehicle = vehicle and vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == playerPed
        if inVehicle and not wasInVehicle then
            TriggerServerEvent('dei_drift:sessionStart')
            wasInVehicle = true
        elseif not inVehicle and wasInVehicle then
            TriggerServerEvent('dei_drift:sessionEnd')
            wasInVehicle = false
        end
        if not inVehicle then
            Citizen.Wait(500)
        else
            Citizen.Wait(0)
        local currentTick = GetGameTimer()

        if not IsPedDeadOrDying(playerPed, false) then
            if IsVehicleOnAllWheels(vehicle) and not IsPedInFlyingVehicle(playerPed) then
                local angle, velocity = Angle(vehicle)
                local isIdle = currentTick - (idleTime or 0) < 1850

                -- Drift ended
                if not isIdle and score ~= 0 then
                    local previousScore = CalculateBonus(score)
                    total = total + previousScore
                    cash = math.floor(total)

                    -- Session stats: track drift time
                    if sessionDriftStart > 0 then
                        sessionTotalDriftTime = sessionTotalDriftTime + (currentTick - sessionDriftStart)
                        sessionDriftStart = 0
                    end

                    -- Session stats: accumulate
                    sessionTotalScore = sessionTotalScore + screenScore
                    if screenScore > sessionBestDrift then
                        sessionBestDrift = screenScore
                    end
                    sessionLastActivity = currentTick
                    sessionSummaryShown = false

                    -- Send money to server
                    TriggerServerEvent("dei_drift:GiveCash", myServerId, cash)

                    -- Session stats: money
                    sessionMoneyEarned = sessionMoneyEarned + math.floor(cash / 100 * Config.Percentage)

                    -- Check personal best
                    if Config.ShowPersonalBest and screenScore > personalBest then
                        personalBest = screenScore
                        SetResourceKvp('dei_drift_pb', tostring(personalBest))
                        SendNUIMessage({ type = 'newPersonalBest', score = personalBest })
                    end

                    -- Check leaderboard
                    if Config.EnableLeaderboard then
                        local vehicleName = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
                        TriggerServerEvent('dei_drift:checkScore', screenScore, vehicleName)
                    end

                    -- Notify NUI of drift end with money earned
                    SendNUIMessage({
                        type = 'driftEnd',
                        score = screenScore,
                        money = cash
                    })

                    score, total, screenScore = 0, 0, 0
                    isDrifting = false
                end

                -- Active drifting
                if angle ~= 0 then
                    local scoreIncrement = math.floor(angle * velocity * mult)
                    score = isIdle and score + scoreIncrement or scoreIncrement
                    screenScore = CalculateBonus(score)
                    idleTime = currentTick

                    -- Start session tracking
                    if not sessionActive then
                        sessionActive = true
                        sessionSummaryShown = false
                    end

                    -- Combo: check if this is a continuation
                    if not isDrifting then
                        if currentTick - lastDriftTime < COMBO_WINDOW then
                            comboCount = comboCount + 1
                            sessionTotalCombos = sessionTotalCombos + 1
                        else
                            comboCount = 1
                        end
                        isDrifting = true
                        sessionDriftStart = currentTick
                    end
                    lastDriftTime = currentTick

                    -- Combo timer: calculate remaining time ratio
                    local comboTimerRatio = 1.0
                    if not isDrifting or isIdle then
                        local elapsed = currentTick - lastDriftTime
                        comboTimerRatio = math.max(0, 1.0 - (elapsed / COMBO_WINDOW))
                    end

                    -- Send update to NUI (throttled to ~100ms)
                    if currentTick - lastNuiUpdate > 100 then
                        SendNUIMessage({
                            type = 'driftUpdate',
                            score = screenScore,
                            angle = math.floor(angle * 2),
                            combo = comboCount,
                            comboTimerRatio = comboTimerRatio
                        })
                        lastNuiUpdate = currentTick
                    end
                end
            end
        else
            -- Player dead, hide drift UI
            if isDrifting then
                SendNUIMessage({ type = 'driftHide' })
                isDrifting = false
                score, total, screenScore = 0, 0, 0
            end
        end
        end -- end else (in vehicle)
    end
end)

-- Combo timer depletion thread (sends updates when not actively drifting but combo window still active)
Citizen.CreateThread(function()
    while true do
        Wait(50)
        if not isDrifting and comboCount > 0 then
            local now = GetGameTimer()
            local elapsed = now - lastDriftTime
            if elapsed < COMBO_WINDOW then
                local ratio = math.max(0, 1.0 - (elapsed / COMBO_WINDOW))
                SendNUIMessage({
                    type = 'comboTimer',
                    comboTimerRatio = ratio
                })
            else
                comboCount = 0
                SendNUIMessage({
                    type = 'comboTimer',
                    comboTimerRatio = 0
                })
            end
        end
    end
end)
