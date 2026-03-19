local lastCashEvent = {}
local MAX_DRIFT_PAYOUT = 5000
local activeDriftSessions = {}

-- Session tracking: client triggers when entering/exiting a vehicle
RegisterNetEvent('dei_drift:sessionStart')
AddEventHandler('dei_drift:sessionStart', function()
    local src = source
    -- Validate player is in a vehicle server-side
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then return end
    activeDriftSessions[src] = {
        startTime = os.time(),
        vehicle = vehicle
    }
end)

RegisterNetEvent('dei_drift:sessionEnd')
AddEventHandler('dei_drift:sessionEnd', function()
    activeDriftSessions[source] = nil
end)

RegisterNetEvent('dei_drift:GiveCash')
AddEventHandler('dei_drift:GiveCash', function(_, cash)
    local src = source
    -- Rate limit: 2 seconds between payouts
    local now = GetGameTimer()
    if lastCashEvent[src] and (now - lastCashEvent[src]) < 2000 then return end
    lastCashEvent[src] = now
    -- Require active drift session
    if not activeDriftSessions[src] then return end
    -- Validate player is STILL in a vehicle
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then
        activeDriftSessions[src] = nil
        return
    end
    -- Validate
    if type(cash) ~= 'number' then return end
    if cash <= 0 or cash ~= cash or cash == math.huge then return end
    cash = math.min(math.floor(cash), MAX_DRIFT_PAYOUT)
    cash = math.floor(cash / 100 * Config.Percentage)
    if cash <= 0 then return end
    addMoney(src, cash)
end)

-- ===== Leaderboard System (KVP) =====

local function GetDriftLeaderboard()
    local leaderboard = {}
    local size = Config.LeaderboardSize or 10
    for i = 1, size do
        local raw = GetResourceKvpString('dei_drift_lb_' .. i)
        if raw and raw ~= '' then
            local entry = json.decode(raw)
            if entry then
                entry.rank = i
                table.insert(leaderboard, entry)
            end
        end
    end
    return leaderboard
end

-- Export for other resources
exports('GetDriftLeaderboard', GetDriftLeaderboard)

local function SaveLeaderboard(leaderboard)
    local size = Config.LeaderboardSize or 10
    for i = 1, size do
        if leaderboard[i] then
            SetResourceKvp('dei_drift_lb_' .. i, json.encode(leaderboard[i]))
        else
            SetResourceKvp('dei_drift_lb_' .. i, '')
        end
    end
end

local function InsertScore(name, score, vehicle)
    local leaderboard = GetDriftLeaderboard()
    local size = Config.LeaderboardSize or 10
    local newEntry = {
        name = name,
        score = score,
        date = os.date('%Y-%m-%d'),
        vehicle = vehicle or 'Unknown'
    }

    -- Find insertion position
    local insertPos = nil
    for i = 1, #leaderboard do
        if score > leaderboard[i].score then
            insertPos = i
            break
        end
    end

    if insertPos then
        table.insert(leaderboard, insertPos, newEntry)
    elseif #leaderboard < size then
        table.insert(leaderboard, newEntry)
        insertPos = #leaderboard
    end

    -- Trim to max size
    while #leaderboard > size do
        table.remove(leaderboard)
    end

    if insertPos then
        -- Remove rank field before saving
        for _, entry in ipairs(leaderboard) do
            entry.rank = nil
        end
        SaveLeaderboard(leaderboard)
    end

    return insertPos
end

-- Client requests to check score against leaderboard
RegisterNetEvent('dei_drift:checkScore')
AddEventHandler('dei_drift:checkScore', function(score, vehicle)
    local src = source
    -- Validate score
    if type(score) ~= 'number' or score <= 0 or score ~= score then return end
    if score > 50000 then return end -- reasonable cap
    if type(vehicle) ~= 'string' then vehicle = 'Unknown' end
    vehicle = string.sub(vehicle, 1, 32)
    -- Rate limit
    if lastCashEvent[src] and (GetGameTimer() - lastCashEvent[src]) < 5000 then return end
    lastCashEvent[src] = GetGameTimer()
    -- Require active drift session
    if not activeDriftSessions[src] then return end

    local playerName = GetPlayerName(src)
    local leaderboard = GetDriftLeaderboard()
    local size = Config.LeaderboardSize or 10

    -- Check if score qualifies
    local qualifies = false
    if #leaderboard < size then
        qualifies = true
    else
        for _, entry in ipairs(leaderboard) do
            if score > entry.score then
                qualifies = true
                break
            end
        end
    end

    if qualifies then
        local rank = InsertScore(playerName, score, vehicle)
        if rank then
            -- Announce to all players
            local msg = playerName .. ' just hit #' .. rank .. ' on the drift leaderboard with ' .. score .. ' points!'
            -- Try dei_notifys first
            local hasNotifys = GetResourceState('dei_notifys') == 'started'
            if hasNotifys then
                TriggerClientEvent('dei_notifys:send', -1, {
                    title = 'Drift Leaderboard',
                    message = msg,
                    type = 'success',
                    duration = 5000
                })
            else
                TriggerClientEvent('chat:addMessage', -1, {
                    color = {255, 191, 36},
                    args = {'Drift', msg}
                })
            end
        end
    end
end)

-- Leaderboard data request callback
local lastLeaderboardRequest = {}
RegisterNetEvent('dei_drift:getLeaderboard:request')
AddEventHandler('dei_drift:getLeaderboard:request', function(playerId)
    local src = source
    -- Rate limit: 5 seconds between requests
    local now = GetGameTimer()
    if lastLeaderboardRequest[src] and (now - lastLeaderboardRequest[src]) < 5000 then return end
    lastLeaderboardRequest[src] = now
    local data = GetDriftLeaderboard()
    TriggerClientEvent('dei_drift:getLeaderboard:response', src, data)
end)

-- Cleanup on player drop
AddEventHandler('playerDropped', function()
    local src = source
    lastCashEvent[src] = nil
    activeDriftSessions[src] = nil
    if lastLeaderboardRequest then lastLeaderboardRequest[src] = nil end
end)

-- ============================================================
-- Dei Ecosystem - Startup
-- ============================================================
CreateThread(function()
    Wait(500)
    local v = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or '1.0'
    print('^4[Dei]^0 dei_drift v' .. v .. ' - ^2Iniciado^0')
end)
