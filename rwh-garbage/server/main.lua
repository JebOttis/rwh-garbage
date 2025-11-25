local Trucks = {}      -- [plate] = { count, bags = {}, players = { [src] = { bagsLoaded = 0 } }, netId, processingPool = {}, lastActive = os.time(), rent = { ... } }
local Dumpsters = {}   -- [dumpsterId] = { bagsRemaining, bagType, coords = vector3 }
local PlayerClockIn = {} -- [src] = true/false

local Framework = Config.Framework or 'qbx'
local Core = nil

-----------------------------------------------------
-- FRAMEWORK INITIALIZATION
-----------------------------------------------------
if Framework == 'qbx' then
    Core = exports['qbx-core']:GetCoreObject()
elseif Framework == 'qb' then
    Core = exports['qb-core']:GetCoreObject()
else
    print('[RWH-Garbage] Unknown framework: ' .. tostring(Framework) .. ' - money/job checks will not work!')
end

local function debugPrint(msg)
    if Config.Debug then
        print(('[RWH-Garbage][DEBUG] %s'):format(msg))
    end
end

-----------------------------------------------------
-- UTILITY: JOB / MONEY HELPERS
-----------------------------------------------------
local function playerHasRequiredJob(src)
    if not Config.RequireJob then
        return true
    end

    local jobName = Config.JobName

    if Framework == 'qbx' and Core then
        local player = Core.Functions.GetPlayer(src)
        if not player or not player.PlayerData or not player.PlayerData.job then
            return false
        end
        return (player.PlayerData.job.name == jobName)
    elseif Framework == 'qb' and Core then
        local player = Core.Functions.GetPlayer(src)
        if not player or not player.PlayerData or not player.PlayerData.job then
            return false
        end
        return (player.PlayerData.job.name == jobName)
    end

    -- If no known framework, allow (owner can implement custom logic).
    return true
end

local function chargePlayerRent(src, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 or Config.TruckRentIsFree then
        return true
    end

    if not Core then
        print('[RWH-Garbage] No framework core available to charge rent; allowing r    if Framework == 'qbx' or Framework == 'qb' then
        local player = Core.Functions.GetPlayer(src)
        if not player then return false end
        local cash = player.Functions.GetMoney('cash') or 0
        if cash < amount then
            return false
        end
        player.Functions.RemoveMoney('cash', amount, 'garbage-truck-rent')
        return true
    end

    return true
end

local function addMoney(src, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end

    if Core and (Framework == 'qbx' or Framework == 'qb') then
        local player = Core.Functions.GetPlayer(src)
        if player then
            player.Functions.AddMoney('cash', amount, 'garbage-job-payout')
        end
    else
        -- Fallback: add as cash in ox_inventory (if configured that way on your server)
        exports.ox_inventory:AddItem(src, 'money', amount)
    end
end

-----------------------------------------------------
-- UTILITY: PLAYER STATE (CARRIED BAG)
-----------------------------------------------------
local function setPlayerCarriedBag(src, hasBag, bagType)
    local player = Player(src)
    if player and player.state then
        player.state:set('rwh_garbage_bag', {
            hasBag = hasBag,
            bagType = hasBag and bagType or nil,
        }, true)
    end
    TriggerClientEvent('rwh-garbage:client:setCarryingBag', src, hasBag, bagType)
end

local function getPlayerCarriedBag(src)
    local player = Player(src)
    if player and player.state then
        local state = player.state.rwh_garbage_bag
        if state and state.hasBag then
            return true, state.bagType
        end
    end
    return false, nil
end

-----------------------------------------------------
-- UTILITY: DUMPSTERS
-----------------------------------------------------
local function makeDumpsterIdFromCoords(coords)
    -- Use a consistent string with 2 decimal places to match client.
    return ('%.2f,%.2f,%.2f'):format(coords.x, coords.y, coords.z)
end

local function pickRandomBagType(weights)
    -- weights: { [bagTypeName] = weightNumber, ... }
    local total = 0
    for _, w in pairs(weights) do
        total = total + w
    end
    if total <= 0 then
        return 'standard'
    end

    local r = math.random() * total
    local acc = 0
    for bagType, w in pairs(weights) do
        acc = acc + w
        if r <= acc then
            return bagType
        end
    end
    return 'standard'
end

local function getSpotConfigForCoords(coords)
    if not Config.Dumpsters.Spots or #Config.Dumpsters.Spots == 0 then
        return nil
    end

    for _, spot in ipairs(Config.Dumpsters.Spots) do
        if #(coords - spot.coords) < 1.0 then
            return spot
        end
    end

    return nil
end

local function ensureDumpster(coords)
    local id = makeDumpsterIdFromCoords(coords)
    local existing = Dumpsters[id]
    if existing then
        return id, existing
    end

    local baseRange = Config.Dumpsters.DefaultBagCount or { min = 3, max = 8 }
    local baseTypes = Config.Dumpsters.DefaultBagTypes or { standard = 100 }

    local spotConf = getSpotConfigForCoords(coords)
    local range = spotConf and spotConf.bags or baseRange
    local types = spotConf and (spotConf.bagTypes or baseTypes) or baseTypes

    local minB = math.max(0, tonumber(range.min) or 0)
    local maxB = math.max(minB, tonumber(range.max) or minB)

    local bagsRemaining = math.random(minB, maxB)
    local bagType = pickRandomBagType(types)

    local data = {
        bagsRemaining = bagsRemaining,
        bagType = bagType,
        coords = coords,
    }

    Dumpsters[id] = data
    debugPrint(('Initialized dumpster %s with %d %s bags'):format(id, bagsRemaining, bagType))
    return id, data
end

-----------------------------------------------------
-- UTILITY: TRUCKS
-----------------------------------------------------
local function getTruckByPlate(plate)
    return Trucks[plate]
end

local function createTruck(plate, netId)
    local truck = Trucks[plate]
    if not truck then
        truck = {
            plate = plate,
            netId = netId,
            count = 0,
            bags = {},
            players = {},
            processingPool = {},
            lastActive = os.time(),
            rent = nil, -- { hours, cost, startedAt, engineStart, bodyStart, renter, damageCharged }
        }
        Trucks[plate] = truck
        debugPrint(('Created truck entry for %s (netId=%s)'):format(plate, tostring(netId)))
    else
        -- Update netId in case it changed.
        truck.netId = netId
        truck.lastActive = os.time()
    end
    return truck
end

local function addPlayerToTruck(truck, src)
    if not truck.players[src] then
        truck.players[src] = { bagsLoaded = 0 }
        debugPrint(('Added player %d to truck %s'):format(src, truck.plate or 'unknown'))
    end
end

local function addBagToTruck(plate, bagType, src)
    local truck = Trucks[plate]
    if not truck then
        return false, 'no_truck'
    end

    local limit = Config.TruckBagLimit or 50
    if truck.count >= limit then
        return false, 'truck_full'
    end

    truck.count = truck.count + 1
    local entry = {
        type = bagType,
        loadedBy = src,
    }
    truck.bags[#truck.bags + 1] = entry
    truck.lastActive = os.time()

    addPlayerToTruck(truck, src)
    truck.players[src].bagsLoaded = (truck.players[src].bagsLoaded or 0) + 1

    debugPrint(('Bag added to truck %s (type=%s, total=%d)'):format(plate, bagType, truck.count))
    return true
end

local function moveBagsToProcessing(plate, amount)
    local truck = Trucks[plate]
    if not truck then
        return 0
    end

    -- Always move bags one-by-one when unloading
    local toMove = math.min(#truck.bags, tonumber(amount) or 1)

    if toMove <= 0 then
        return 0
    end

    truck.processingPool = truck.processingPool or {}

    for i = 1, toMove do
        local bag = truck.bags[i]
        if bag then
            truck.processingPool[#truck.processingPool + 1] = bag
        end
    end

    -- Remove moved bags from truck.bags
    if toMove == #truck.bags then
        truck.bags = {}
    else
        for i = 1, toMove do
            table.remove(truck.bags, 1)
        end
    end

    truck.count = #truck.bags
    truck.lastActive = os.time()

    debugPrint(('Moved %d bags from truck %s to processing pool (%d remaining in truck)'):format(toMove, plate, truck.count))
    return toMove
end

local function removeAllBagsFromTruck(plate)
    local truck = Trucks[plate]
    if not truck then return end
    truck.bags = {}
    truck.processingPool = {}
    truck.count = 0
    truck.lastActive = os.time()
end

local function cleanupTruck(plate, deleteVehicle)
    local truck = Trucks[plate]
    if not truck then return end

    if deleteVehicle and truck.netId then
        local ent = NetworkGetEntityFromNetworkId(truck.netId)
        if ent and DoesEntityExist(ent) then
            DeleteEntity(ent)
        end
    end

    Trucks[plate] = nil
    debugPrint(('Cleaned up truck %s'):format(plate))
end

-----------------------------------------------------
-- REWARD ROLLING
-----------------------------------------------------
local function rollRewardsForBag(bagType)
    local conf = Config.Rewards[bagType]
    if not conf then
        conf = Config.Rewards['standard'] or nil
    end
    if not conf then
        return { cash = 0, items = {}, weapons = {} }
    end

    local result = { cash = 0, items = {}, weapons = {} }

    if conf.cash then
        local minC = math.floor(conf.cash.min or 0)
        local maxC = math.floor(conf.cash.max or minC)
        if maxC > 0 and maxC >= minC then
            result.cash = math.random(minC, maxC)
        end
    end

    if conf.items and #conf.items > 0 then
        for _, item in ipairs(conf.items) do
            local chance = tonumber(item.chance) or 0
            if chance > 0 and math.random(100) <= chance then
                local minI = math.floor(item.min or 1)
                local maxI = math.floor(item.max or minI)
                if maxI > 0 and maxI >= minI then
                    local count = math.random(minI, maxI)
                    if count > 0 then
                        result.items[#result.items + 1] = {
                            name = item.name,
                            count = count,
                        }
                    end
                end
            end
        end
    end

    if conf.weaponDrop and conf.weaponDrop.items and #conf.weaponDrop.items > 0 then
        local chance = tonumber(conf.weaponDrop.chance) or 0
        if chance > 0 then
            if math.random() < chance then
                local idx = math.random(1, #conf.weaponDrop.items)
                local weaponName = conf.weaponDrop.items[idx]
                if weaponName then
                    result.weapons[#result.weapons + 1] = weaponName
                end
            end
        end
    end

    return result
end

-- Main payout splitter; simple default logic (even/byContribution).
-- You can replace or extend this function to customize split logic.
local function distributeRewards(plate, totals, totalBagsProcessed)
    local truck = Trucks[plate]
    if not truck then
        return
    end

    local players = {}
    for src, pdata in pairs(truck.players) do
        if GetPlayerPing(src) > 0 then
            players[#players + 1] = { src = src, bagsLoaded = pdata.bagsLoaded or 0 }
        end
    end

    if #players == 0 then
        debugPrint(('No players assigned to truck %s for payout'):format(plate))
        return
    end

    -- Filter by proximity to processing center
    local center = Config.RecyclingCenter.ProcessingZone.coords
    local nearby = {}
    for _, entry in ipairs(players) do
        local src = entry.src
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local pos = GetEntityCoords(ped)
            if #(pos - center) <= (Config.PayoutRadius or 25.0) then
                nearby[#nearby + 1] = entry
            end
        end
    end

    if #nearby == 0 then
        debugPrint(('No nearby players found for payout for truck %s'):format(plate))
        return
    end

    local mode = Config.PaySplitMode or 'even'
    local perPlayerRewards = {}

    if mode == 'byContribution' then
        local contributedBags = 0
        for _, entry in ipairs(nearby) do
            contributedBags = contributedBags + (entry.bagsLoaded or 0)
        end
        if contributedBags <= 0 then
            mode = 'even'
        else
            for _, entry in ipairs(nearby) do
                local src = entry.src
                local share = (entry.bagsLoaded or 0) / contributedBags
                perPlayerRewards[src] = {
                    cash = math.floor((totals.cash or 0) * share),
                    items = {},
                    weapons = {},
                }
            end
        end
    end

    if mode == 'even' then
        local n = #nearby
        local cashPer = math.floor((totals.cash or 0) / n)
        for _, entry in ipairs(nearby) do
            perPlayerRewards[entry.src] = {
                cash = cashPer,
                items = {},
                weapons = {},
            }
        end
    end

    -- Distribute items and weapons roughly evenly (round-robin).
    local itemIndex = 1
    for _, item in ipairs(totals.items or {}) do
        local remaining = item.count
        while remaining > 0 do
            local entry = nearby[itemIndex]
            if not entry then
                itemIndex = 1
                entry = nearby[itemIndex]
            end
            local src = entry.src
            perPlayerRewards[src].items[#perPlayerRewards[src].items + 1] = {
                name = item.name,
                count = 1,
            }
            remaining = remaining - 1
            itemIndex = itemIndex + 1
        end
    end

    local weaponIndex = 1
    for _, weapon in ipairs(totals.weapons or {}) do
        local entry = nearby[weaponIndex]
        if not entry then
            weaponIndex = 1
            entry = nearby[weaponIndex]
        end
        local src = entry.src
        perPlayerRewards[src].weapons[#perPlayerRewards[src].weapons + 1] = weapon
        weaponIndex = weaponIndex + 1
    end

    -- Apply rewards
    for src, reward in pairs(perPlayerRewards) do
        if reward.cash and reward.cash > 0 then
            addMoney(src, reward.cash)
        end

        for _, item in ipairs(reward.items or {}) do
            exports.ox_inventory:AddItem(src, item.name, item.count)
        end

        for _, weapon in ipairs(reward.weapons or {}) do
            exports.ox_inventory:AddItem(src, weapon, 1)
        end

        TriggerClientEvent('rwh-garbage:client:notifyPayout', src, reward, totalBagsProcessed)
    end
end

-----------------------------------------------------
-- OX_LIB CALLBACKS
-----------------------------------------------------
lib.callback.register('rwh-garbage:server:getDumpsterInfo', function(src, coords)
    if not playerHasRequiredJob(src) then
        return { ok = false, reason = 'no_job', remaining = 0, bagType = nil }
    end

    local vec = vector3(coords.x, coords.y, coords.z)
    local id, dumpster = ensureDumpster(vec)
    return {
        ok = true,
        remaining = dumpster.bagsRemaining,
        bagType = dumpster.bagType,
    }
end)

lib.callback.register('rwh-garbage:server:getTruckBagCount', function(src, plate)
    local truck = Trucks[plate]
    if not truck then
        return { ok = false, count = 0, limit = Config.TruckBagLimit or 50, types = {} }
    end

    local typeCounts = {}
    for _, bag in ipairs(truck.bags or {}) do
        local btype = bag.type or 'standard'
        typeCounts[btype] = (typeCounts[btype] or 0) + 1
    end

    return {
        ok = true,
        count = truck.count,
        limit = Config.TruckBagLimit or 50,
        types = typeCounts,
    }
end)

-----------------------------------------------------
-- EVENTS: JOB START / END
-----------------------------------------------------
RegisterNetEvent('rwh-garbage:server:clockIn', function()
    local src = source
    if Config.RequireJob and not playerHasRequiredJob(src) then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'You are not employed as a sanitation worker.', 'error')
        return
    end

    PlayerClockIn[src] = true
    TriggerClientEvent('rwh-garbage:client:notify', src, 'You clocked in for the garbage job.', 'success')
end)

RegisterNetEvent('rwh-garbage:server:clockOut', function()
    local src = source
    PlayerClockIn[src] = nil
    TriggerClientEvent('rwh-garbage:client:notify', src, 'You clocked out of the garbage job.', 'info')
end)


    if Config.RequireJob and not playerHasRequiredJob(src) then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'You are not employed as a sanitation worker.', 'error')
        return
    end

    if Config.RequireClockIn and not PlayerClockIn[src] then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'You must clock in before renting a truck.', 'error')
        return
    end

    local rentHours, rentCost = computeTimedRent(hours)

    if not chargePlayerRent(src, rentCost) then
        TriggerClientEvent('rwh-garbage:client:notify', src,
            ('You need $%d in cash to rent a garbage truck for %d hour(s).'):format(rentCost, rentHours),
            'error'
        )
        return
    end

    local spawn = Config.RecyclingCenter.TruckSpawn
    if not spawn or not spawn.coords then
        print('[RWH-Garbage] ERROR: Config.RecyclingCenter.TruckSpawn is not configured.')
        TriggerClientEvent('rwh-garbage:client:notify', src, 'Truck spawn is not configured on this server.', 'error')
        return
    end

    -- Ask client to spawn the truck and report back plate/netId.
    TriggerClientEvent('rwh-garbage:client:spawnTruck', src, {
        model = Config.TruckModel or 'trash2',
        coords = spawn.coords,
        heading = spawn.heading or 0.0,
        rentHours = rentHours,
        rentCost = rentCost,
    })
end)

-- Client reports created truck plate + netId so we can track it.
RegisterNetEvent('rwh-garbage:server:registerTruck', function(plate, netId, rentHours, rentCost)
    local src = source
    plate = tostring(plate or ''):upper()
    if plate == '' then
        return
    end

    local truck = createTruck(plate, netId)
    addPlayerToTruck(truck, src)

    rentHours = tonumber(rentHours) or 1
    rentCost = tonumber(rentCost) or (Config.RentBaseHourly or 35)

    local ent = NetworkGetEntityFromNetworkId(netId)
    local engineStart = 1000.0
    local bodyStart = 1000.0
    if ent and ent ~= 0 and DoesEntityExist(ent) then
        engineStart = GetVehicleEngineHealth(ent) or 1000.0
        bodyStart = GetVehicleBodyHealth(ent) or 1000.0
    end

    truck.rent = {
        hours = rentHours,
        cost = rentCost,
        startedAt = os.time(),
        engineStart = engineStart,
        bodyStart = bodyStart,
        renter = src,
        damageCharged = false,
    }

    TriggerClientEvent('rwh-garbage:client:notify', src,
        ('You rented a garbage truck (%s) for %d hour(s) at $%d.'):format(plate, rentHours, rentCost),
        'success'
    )
    TriggerClientEvent('rwh-garbage:client:setAssignedTruck', src, plate, netId)
end)

-----------------------------------------------------
-- EVENTS: DUMPSTER / WORLD BAG HANDLING
-----------------------------------------------------
RegisterNetEvent('rwh-garbage:server:takeBag', function(coords)
    local src = source

    if Config.RequireJob and not playerHasRequiredJob(src) then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'You are not employed as a sanitation worker.', 'error')
        return
    end

    if Config.RequireClockIn and not PlayerClockIn[src] then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'You must clock in before collecting trash.', 'error')
        return
    end

    local has, _ = getPlayerCarriedBag(src)
    if has then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'You are already carrying a garbage bag.', 'error')
        return
    end

    local vec = vector3(coords.x, coords.y, coords.z)
    local id, dumpster = ensureDumpster(vec)

    if dumpster.bagsRemaining <= 0 then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'This dumpster is empty.', 'error')
        return
    end

    dumpster.bagsRemaining = dumpster.bagsRemaining - 1
    if dumpster.bagsRemaining < 0 then
        dumpster.bagsRemaining = 0
    end

    setPlayerCarriedBag(src, true, dumpster.bagType)
    TriggerClientEvent('rwh-garbage:client:notify', src,
        ('You picked up a %s garbage bag.'):format(dumpster.bagType or 'standard'),
        'success'
    )

    debugPrint(('Player %d took bag from dumpster %s, remaining = %d'):format(src, id, dumpster.bagsRemaining))
end)

-- Drop a carried bag onto the ground as a prop
RegisterNetEvent('rwh-garbage:server:dropCarriedBag', function()
    local src = source

    local has, bagType = getPlayerCarriedBag(src)
    if not has then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'You are not carrying a garbage bag.', 'error')
        return
    end

    setPlayerCarriedBag(src, false, nil)

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local coords = GetEntityCoords(ped)

    TriggerClientEvent('rwh-garbage:client:spawnDroppedBag', -1, {
        x = coords.x,
        y = coords.y,
        z = coords.z,
    }, bagType or 'standard')
end)

-- Pick up a dropped bag prop from the ground
RegisterNetEvent('rwh-garbage:server:pickupDroppedBag', function(bagType)
    local src = source

    local has = select(1, getPlayerCarriedBag(src))
    if has then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'You are already carrying a garbage bag.', 'error')
        return
    end

    bagType = bagType or 'standard'
    setPlayerCarriedBag(src, true, bagType)
end)

-----------------------------------------------------
-- EVENTS: TRUCK BAG HANDLING
-----------------------------------------------------
RegisterNetEvent('rwh-garbage:server:loadBagIntoTruck', function(plate)
    local src = source

    plate = tostring(plate or ''):upper()
    if plate == '' then return end

    if Config.RequireJob and not playerHasRequiredJob(src) then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'You are not employed as a sanitation worker.', 'error')
        return
    end

    local hasBag, bagType = getPlayerCarriedBag(src)
    if not hasBag then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'You are not carrying a garbage bag.', 'error')
        return
    end

    local truck = Trucks[plate]
    if not truck then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'This truck is not registered for the garbage job.', 'error')
        return
    end

    -- Optional: restrict to garbage job truck model only
    if Config.LimitToGarbageModel and truck.netId then
        local entity = NetworkGetEntityFromNetworkId(truck.netId)
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            local model = GetEntityModel(entity)
            if model ~= GetHashKey(Config.TruckModel or 'trash2') then
                TriggerClientEvent('rwh-garbage:client:notify', src, 'You can only load garbage bags into a job truck.', 'error')
                return
            end
        end
    end

    local ok, reason = addBagToTruck(plate, bagType, src)
    if not ok then
        if reason == 'truck_full' then
            TriggerClientEvent('rwh-garbage:client:notify', src, 'The truck is full. Return to the recycling center.', 'error')
        else
            TriggerClientEvent('rwh-garbage:client:notify', src, 'Unable to load the bag into this truck.', 'error')
        end
        return
    end

    setPlayerCarriedBag(src, false, nil)
    local limit = Config.TruckBagLimit or 50
    TriggerClientEvent('rwh-garbage:client:notify', src,
        ('Loaded bag into truck (%d/%d).'):format(truck.count, limit),
        'success'
    )
end)

-----------------------------------------------------
-- EVENTS: UNLOAD / PROCESS BAGS
-----------------------------------------------------
RegisterNetEvent('rwh-garbage:server:unloadTruckBags', function(plate)
    local src = source

    plate = tostring(plate or ''):upper()
    if plate == '' then return end

    if Config.RequireJob and not playerHasRequiredJob(src) then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'You are not employed as a sanitation worker.', 'error')
        return
    end

    local truck = Trucks[plate]
    if not truck then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'This truck is not registered for the garbage job.', 'error')
        return
    end

    local moved = moveBagsToProcessing(plate, 1)
    if moved <= 0 then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'There are no bags in the truck to unload.', 'error')
        return
    end

    TriggerClientEvent('rwh-garbage:client:notify', src,
        ('Unloaded %d bag from the truck into processing.'):format(moved),
        'success'
    )
end)

-- Unload a single bag of a specific type into processing (from truck rear / menu)
RegisterNetEvent('rwh-garbage:server:unloadTruckBagType', function(plate, bagType)
    local src = source

    plate = tostring(plate or ''):upper()
    bagType = tostring(bagType or 'standard')

    if plate == '' then return end

    if Config.RequireJob and not playerHasRequiredJob(src) then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'You are not employed as a sanitation worker.', 'error')
        return
    end

    local truck = Trucks[plate]
    if not truck then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'This truck is not registered for the garbage job.', 'error')
        return
    end

    local index = nil
    for i, bag in ipairs(truck.bags or {}) do
        if (bag.type or 'standard') == bagType then
            index = i
            break
        end
    end

    if not index then
        TriggerClientEvent('rwh-garbage:client:notify', src,
            ('There are no %s bags in this truck.'):format(bagType),
            'error'
        )
        return
    end

    truck.processingPool = truck.processingPool or {}
    local bag = table.remove(truck.bags, index)
    truck.processingPool[#truck.processingPool + 1] = bag
    truck.count = #truck.bags
    truck.lastActive = os.time()

    TriggerClientEvent('rwh-garbage:client:notify', src,
        ('Unloaded one %s bag into processing.'):format(bagType),
        'success'
    )
end)

RegisterNetEvent('rwh-garbage:server:processBags', function(plate)
    local src = source

    plate = tostring(plate or ''):upper()
    if plate == '' then return end

    if Config.RequireJob and not playerHasRequiredJob(src) then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'You are not employed as a sanitation worker.', 'error')
        return
    end

    local truck = Trucks[plate]
    if not truck then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'No active garbage truck found for processing.', 'error')
        return
    end

    truck.processingPool = truck.processingPool or {}
    local pool = truck.processingPool
    local bagCount = #pool

    if bagCount <= 0 then
        TriggerClientEvent('rwh-garbage:client:notify', src, 'There are no bags waiting to be processed.', 'error')
        return
    end

    local totals = {
        cash = 0,
        items = {},  -- aggregated: { { name, count }, ... }
        weapons = {}, -- aggregated: { weaponName, ... }
    }

    local itemIndex = {}

    for _, bag in ipairs(pool) do
        local rewards = rollRewardsForBag(bag.type or 'standard')

        totals.cash = totals.cash + (rewards.cash or 0)

        for _, item in ipairs(rewards.items or {}) do
            local key = item.name
            itemIndex[key] = itemIndex[key] or { name = key, count = 0 }
            itemIndex[key].count = itemIndex[key].count + item.count
        end

        for _, weapon in ipairs(rewards.weapons or {}) do
            totals.weapons[#totals.weapons + 1] = weapon
        end
    end

    for _, agg in pairs(itemIndex) do
        totals.items[#totals.items + 1] = agg
    end

    distributeRewards(plate, totals, bagCount)

    -- Clear processing pool for this truck
    truck.processingPool = {}
    truck.lastActive = os.time()

    TriggerClientEvent('rwh-garbage:client:notify', src,
        ('Processed %d bags.'):format(bagCount),
        'success'
    )
end)

-----------------------------------------------------
-- EVENTS: END JOB / RETURN TRUCK (OPTIONAL)
-----------------------------------------------------
local function chargeTruckDamage(src, plate)
    local truck = Trucks[plate]
    if not truck or not truck.rent or truck.rent.damageCharged then return end

    local ent = truck.netId and NetworkGetEntityFromNetworkId(truck.netId) or nil
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end

    local engineNow = GetVehicleEngineHealth(ent) or 1000.0
    local bodyNow = GetVehicleBodyHealth(ent) or 1000.0

    local engineStart = truck.rent.engineStart or 1000.0
    local bodyStart = truck.rent.bodyStart or 1000.0

    local startAvg = math.max(1.0, (engineStart + bodyStart) / 2.0)
    local nowAvg = math.max(0.0, (engineNow + bodyNow) / 2.0)

    local damageFrac = math.max(0.0, (startAvg - nowAvg) / startAvg)
    if damageFrac <= 0.05 then -- ignore minor wear under 5%
        return
    end

    local baseCost = tonumber(truck.rent.cost) or 0
    if baseCost <= 0 then return end

    local multiplier = Config.DamageChargeMultiplier or 2.0
    local damageCost = math.floor(baseCost * multiplier * damageFrac)
    if damageCost <= 0 then return end

    if Core and (Framework == 'qbx' or Framework == 'qb') then
        local player = Core.Functions.GetPlayer(src)
        if player then
            local cash = player.Functions.GetMoney('cash') or 0
            local charged = math.min(cash, damageCost)
            if charged > 0 then
                player.Functions.RemoveMoney('cash', charged, 'garbage-truck-damage')
                TriggerClientEvent('rwh-garbage:client:notify', src,
                    ('You were charged $%d for garbage truck damage.'):format(charged),
                    'error'
                )
            end
        end
    end

    truck.rent.damageCharged = true
end

RegisterNetEvent('rwh-garbage:server:endJob', function(plate, deleteVehicle)
    local src = source

    plate = tostring(plate or ''):upper()
    if plate ~= '' then
        chargeTruckDamage(src, plate)
        cleanupTruck(plate, deleteVehicle)
    end

    PlayerClockIn[src] = nil
    setPlayerCarriedBag(src, false, nil)

    TriggerClientEvent('rwh-garbage:client:notify', src, 'You ended your garbage shift.', 'info')
end)

-----------------------------------------------------
-- PLAYER DISCONNECT HANDLING
-----------------------------------------------------
AddEventHandler('playerDropped', function()
    local src = source
    PlayerClockIn[src] = nil
    -- The truck cleanup loop will handle stale trucks when all players leave.
end)

-----------------------------------------------------
-- PERIODIC CLEANUP THREAD
-----------------------------------------------------
CreateThread(function()
    while true do
        Wait(60 * 1000)

        local timeout = (Config.TruckCleanupMinutes or 15) * 60
        local now = os.time()

        for plate, truck in pairs(Trucks) do
            local hasOnline = false
            for src, _ in pairs(truck.players or {}) do
                if GetPlayerPing(src) > 0 then
                    hasOnline = true
                    break
                end
            end

            if not hasOnline and (now - (truck.lastActive or now)) > timeout then
                print(('[RWH-Garbage] Cleaning up inactive truck %s (no players online).'):format(plate))
                cleanupTruck(plate, true)
            end
        end
    end
end)
