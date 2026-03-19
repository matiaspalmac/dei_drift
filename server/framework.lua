Framework = {}

CreateThread(function()
    if Config.Framework == 'esx' then
        local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok then Framework.Core = obj end
    elseif Config.Framework == 'qb' then
        local ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok then Framework.Core = obj end
    end
end)

function addMoney(playerId, amount)
    if not Framework.Core then return end
    if Config.Framework == 'esx' then
        local xPlayer = Framework.Core.GetPlayerFromId(playerId)
        if not xPlayer then return end
        xPlayer.addMoney(amount)
    elseif Config.Framework == 'qb' then
        local xPlayer = Framework.Core.Functions.GetPlayer(playerId)
        if not xPlayer then return end
        xPlayer.Functions.AddMoney('cash', amount)
    end
end
