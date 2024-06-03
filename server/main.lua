local KGCore = exports['kg-core']:GetCoreObject()
local vehicleComponents = {}
local drivingDistance = {}
local tunedVehicles = {}
local nitrousVehicles = {}

-- Functions

function Trim(plate)
    return (string.gsub(plate, '^%s*(.-)%s*$', '%1'))
end

local function IsVehicleOwned(plate)
    local result = MySQL.scalar.await('SELECT 1 from player_vehicles WHERE plate = ?', { plate })
    if result then return true end
    return false
end

local function StartParticles(coords, netId, color)
    for _, playerId in ipairs(GetPlayers()) do
        local playerPed = GetPlayerPed(playerId)
        local playerCoords = GetEntityCoords(playerPed)
        local distance = #(coords - playerCoords)
        if distance < 10 then
            Player(playerId).state:set('paint_particles', true, false)
            TriggerClientEvent('kg-mechanicjob:client:startParticles', playerId, netId, color)
        end
    end
end

local function StopParticles()
    for _, playerId in ipairs(GetPlayers()) do
        if Player(playerId).state.paint_particles then
            Player(playerId).state:set('paint_particles', false, false)
            TriggerClientEvent('kg-mechanicjob:client:stopParticles', playerId)
        end
    end
end

local function LerpColor(colorFrom, colorTo, fraction)
    return {
        r = colorFrom.r + (colorTo.r - colorFrom.r) * fraction,
        g = colorFrom.g + (colorTo.g - colorFrom.g) * fraction,
        b = colorFrom.b + (colorTo.b - colorFrom.b) * fraction
    }
end

local function TransitionVehicleColor(vehicle, section, currentColor, targetColor, duration)
    local startTime = GetGameTimer()
    local endTime = startTime + duration
    while GetGameTimer() <= endTime do
        local currentTime = GetGameTimer()
        local fraction = (currentTime - startTime) / duration
        local newColor = LerpColor(currentColor, targetColor, fraction)
        if section == 'primary' then
            SetVehicleCustomPrimaryColour(vehicle, math.floor(newColor.r), math.floor(newColor.g), math.floor(newColor.b))
        elseif section == 'secondary' then
            SetVehicleCustomSecondaryColour(vehicle, math.floor(newColor.r), math.floor(newColor.g), math.floor(newColor.b))
        end
        Wait(0)
    end
end

local function GetPaintTypeIndex(type)
    if type == 'metallic' then return 0 end
    if type == 'matte' then return 12 end
    if type == 'chrome' then return 120 end
    return 0
end

-- Callbacks

KGCore.Functions.CreateCallback('kg-mechanicjob:server:getnitrousVehicles', function(_, cb)
    cb(nitrousVehicles)
end)

KGCore.Functions.CreateCallback('kg-mechanicjob:server:checkTune', function(_, cb, plate)
    if not tunedVehicles[plate] then cb(false) end
    cb(tunedVehicles[plate])
end)

KGCore.Functions.CreateCallback('kg-mechanicjob:server:getVehicleStatus', function(_, cb, plate)
    if not vehicleComponents[plate] then cb(false) end
    cb(vehicleComponents[plate])
end)

KGCore.Functions.CreateCallback('kg-mechanicjob:server:hasPermission', function(source, cb)
    if KGCore.Functions.HasPermission(source, { 'god', 'admin', 'command' }) then
        cb(true)
    else
        cb(false)
    end
end)

-- Events

RegisterNetEvent('kg-mechanicjob:server:stash', function(data)
    local src = source
    local shopName = data.job
    if not Config.Shops[shopName] then return end
    local Player = KGCore.Functions.GetPlayer(src)
    if not Player then return end
    if Config.Shops[shopName].managed and Player.PlayerData.job.name ~= shopName then return end
    local playerPed = GetPlayerPed(src)
    local playerCoords = GetEntityCoords(playerPed)
    local stashCoords = Config.Shops[shopName].stash
    if #(playerCoords - stashCoords) < 2.5 then
        local stashName = shopName .. '_stash'
        exports['kg-inventory']:OpenInventory(src, stashName, {
            maxweight = 4000000,
            slots = 100,
        })
    end
end)

RegisterNetEvent('kg-mechanicjob:server:sprayVehicleCustom', function(netId, section, type, color)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    local vehicleCoords = GetEntityCoords(vehicle)
    local paintTypeIndex = GetPaintTypeIndex(type)
    FreezeEntityPosition(vehicle, true)
    StartParticles(vehicleCoords, netId, color)
    local r, g, b
    if section == 'primary' then
        local _, colorSecondary = GetVehicleColours(vehicle)
        SetVehicleColours(vehicle, paintTypeIndex, colorSecondary)
        r, g, b = GetVehicleCustomPrimaryColour(vehicle)
    elseif section == 'secondary' then
        local colorPrimary, _ = GetVehicleColours(vehicle)
        SetVehicleColours(vehicle, colorPrimary, paintTypeIndex)
        r, g, b = GetVehicleCustomSecondaryColour(vehicle)
    end
    local currentColor = { r = r, g = g, b = b }
    TransitionVehicleColor(vehicle, section, currentColor, color, Config.PaintTime * 1000)
    StopParticles()
    FreezeEntityPosition(vehicle, false)
end)

RegisterNetEvent('kg-mechanicjob:server:sprayVehicle', function(netId, primary, secondary, pearlescent, wheel, colors)
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    local vehicleCoords = GetEntityCoords(vehicle)
    FreezeEntityPosition(vehicle, true)

    if colors.primary then
        StartParticles(vehicleCoords, netId, colors.primary)
        Wait(Config.PaintTime * 1000)
        -- local _, colorSecondary = GetVehicleColours(vehicle)
        -- ClearVehicleCustomPrimaryColour(vehicle) -- does not exist yet
        -- SetVehicleColours(vehicle, tonumber(primary), colorSecondary)
        TriggerClientEvent('kg-mechanicjob:client:vehicleSetColors', -1, netId, 'primary', primary)
        StopParticles()
    end

    if colors.secondary then
        StartParticles(vehicleCoords, netId, colors.secondary)
        Wait(Config.PaintTime * 1000)
        -- local colorPrimary, _ = GetVehicleColours(vehicle)
        -- ClearVehicleCustomSecondaryColour(vehicle) -- does not exist yet
        -- SetVehicleColours(vehicle, colorPrimary, tonumber(secondary))
        TriggerClientEvent('kg-mechanicjob:client:vehicleSetColors', -1, netId, 'secondary', secondary)
        StopParticles()
    end

    if colors.pearlescent then
        StartParticles(vehicleCoords, netId, colors.pearlescent)
        Wait(Config.PaintTime * 1000)
        -- local pearlescentColor, wheelColor = GetVehicleExtraColours(vehicle) -- does not exist yet
        -- SetVehicleExtraColours(vehicle, tonumber(pearlescent) or pearlescentColor, tonumber(wheel) or wheelColor) -- does not exist yet
        TriggerClientEvent('kg-mechanicjob:client:vehicleSetColors', -1, netId, 'pearlescent', pearlescent)
        StopParticles()
    end

    if colors.wheel then
        StartParticles(vehicleCoords, netId, colors.wheel)
        Wait(Config.PaintTime * 1000)
        -- local pearlescentColor, wheelColor = GetVehicleExtraColours(vehicle) -- does not exist yet
        -- SetVehicleExtraColours(vehicle, tonumber(pearlescent) or pearlescentColor, tonumber(wheel) or wheelColor) -- does not exist yet
        TriggerClientEvent('kg-mechanicjob:client:vehicleSetColors', -1, netId, 'wheel', wheel)
        StopParticles()
    end

    FreezeEntityPosition(vehicle, false)
end)

RegisterNetEvent('kg-mechanicjob:server:syncNitrous', function(plate, hasnitro, level)
    if not nitrousVehicles[plate] then
        nitrousVehicles[plate] = { hasnitro = hasnitro, level = level }
    else
        nitrousVehicles[plate].hasnitro = hasnitro
        nitrousVehicles[plate].level = level
    end
end)

RegisterNetEvent('kg-mechanicjob:server:syncNitrousFlames', function(netId, toggle)
    TriggerClientEvent('kg-mechanicjob:client:syncNitrousFlames', -1, netId, toggle)
end)

RegisterNetEvent('kg-mechanicjob:server:tuneStatus', function(plate)
    if not tunedVehicles[plate] then
        tunedVehicles[plate] = true
    end
end)

RegisterNetEvent('kg-mechanicjob:server:SaveVehicleProps', function(vehicleProps)
    if IsVehicleOwned(vehicleProps.plate) then
        MySQL.update('UPDATE player_vehicles SET mods = ? WHERE plate = ?', { json.encode(vehicleProps), vehicleProps.plate })
    end
end)

RegisterNetEvent('kg-mechanicjob:server:repairVehicleComponent', function(plate, component)
    if plate and component then
        if not vehicleComponents[plate] then return end
        if vehicleComponents[plate][component] then
            vehicleComponents[plate][component] = 100
        end
    end
end)

RegisterNetEvent('kg-mechanicjob:server:updateVehicleComponents', function(plate, componentData)
    if plate and componentData then
        if vehicleComponents[plate] then
            vehicleComponents[plate] = componentData
        else
            vehicleComponents[plate] = componentData
        end
    end
    local isOwned = IsVehicleOwned(plate)
    if isOwned then MySQL.update('UPDATE player_vehicles SET status = ? WHERE plate = ?', { json.encode(vehicleComponents[plate]), plate }) end
end)

RegisterNetEvent('kg-mechanicjob:server:updateDrivingDistance', function(plate, distance)
    if plate and distance then
        if drivingDistance[plate] then
            drivingDistance[plate] = drivingDistance[plate] + distance
        else
            drivingDistance[plate] = distance
        end
    end
    local isOwned = IsVehicleOwned(plate)
    if isOwned then MySQL.update('UPDATE player_vehicles SET drivingdistance = drivingdistance + ? WHERE plate = ?', { drivingDistance[plate], plate }) end
end)

RegisterNetEvent('kg-mechanicjob:server:removeItem', function(part, amount)
    local src = source
    local Player = KGCore.Functions.GetPlayer(src)
    if not Player then return end
    if not amount then amount = 1 end
    if not exports['kg-inventory']:RemoveItem(src, part, amount, false, 'kg-mechanicjob:server:removeItem') then DropPlayer(src, 'kg-mechanicjob:server:removeItem') end
    TriggerClientEvent('kg-inventory:client:ItemBox', src, KGCore.Shared.Items[part], 'remove')
end)

-- Items

local performanceParts = {
    'veh_armor',
    'veh_brakes',
    'veh_engine',
    'veh_suspension',
    'veh_transmission',
    'veh_turbo',
}

for i = 1, #performanceParts do
    KGCore.Functions.CreateUseableItem(performanceParts[i], function(source, item)
        local Player = KGCore.Functions.GetPlayer(source)
        if not Player then return end
        if Config.RequireJob and Player.PlayerData.job.type ~= 'mechanic' then return end
        TriggerClientEvent('kg-mechanicjob:client:installPart', source, item.name)
    end)
end

local cosmeticParts = {
    'veh_interior',
    'veh_exterior',
    'veh_wheels',
    'veh_neons',
    'veh_xenons',
    'veh_tint',
    'veh_plates',
}

for i = 1, #cosmeticParts do
    KGCore.Functions.CreateUseableItem(cosmeticParts[i], function(source, item)
        local Player = KGCore.Functions.GetPlayer(source)
        if not Player then return end
        if Config.RequireJob and Player.PlayerData.job.type ~= 'mechanic' then return end
        TriggerClientEvent('kg-mechanicjob:client:installCosmetic', source, item.name)
    end)
end

KGCore.Functions.CreateUseableItem('veh_toolbox', function(source)
    local Player = KGCore.Functions.GetPlayer(source)
    if not Player then return end
    if Config.RequireJob and Player.PlayerData.job.type ~= 'mechanic' then return end
    TriggerClientEvent('kg-mechanicjob:client:PartsMenu', source)
end)

KGCore.Functions.CreateUseableItem('tunerlaptop', function(source)
    local Player = KGCore.Functions.GetPlayer(source)
    if not Player then return end
    if Config.RequireJob and Player.PlayerData.job.type ~= 'mechanic' then return end
    TriggerClientEvent('kg-mechanicjob:client:openChip', source)
end)

KGCore.Functions.CreateUseableItem('nitrous', function(source)
    local Player = KGCore.Functions.GetPlayer(source)
    if not Player then return end
    if Config.RequireJob and Player.PlayerData.job.type ~= 'mechanic' then return end
    TriggerClientEvent('kg-mechanicjob:client:installNitrous', source)
end)

KGCore.Functions.CreateUseableItem('tirerepairkit', function(source)
    local Player = KGCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('kg-mechanicjob:client:repairTire', source)
end)

KGCore.Functions.CreateUseableItem('repairkit', function(source)
    local Player = KGCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('kg-mechanicjob:client:repairVehicle', source)
end)

KGCore.Functions.CreateUseableItem('advancedrepairkit', function(source)
    local Player = KGCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('kg-mechanicjob:client:repairVehicleFull', source)
end)

KGCore.Functions.CreateUseableItem('cleaningkit', function(source)
    local Player = KGCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('kg-mechanicjob:client:cleanVehicle', source)
end)

-- Commands

KGCore.Commands.Add('fix', 'Repair your vehicle (Admin Only)', {}, false, function(source)
    local ped = GetPlayerPed(source)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle then return end
    local plate = GetVehicleNumberPlateText(vehicle)
    if not plate then return end
    local trimmedPlate = Trim(plate)
    if vehicleComponents[trimmedPlate] then
        for k in pairs(vehicleComponents[trimmedPlate]) do
            vehicleComponents[trimmedPlate][k] = 100
        end
    end
    TriggerClientEvent('kg-mechanicjob:client:fixEverything', source)
end, 'admin')
