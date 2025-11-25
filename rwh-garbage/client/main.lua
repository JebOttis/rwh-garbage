local carryingBag = false
local carryingBagType = nil

local assignedTruckPlate = nil
local assignedTruckNetId = nil

local nuiOpen = false

-----------------------------------------------------
-- UTILITY: NOTIFICATIONS
-----------------------------------------------------
local function Notify(msg, nType)
    nType = nType or 'info'

    if lib and lib.notify then
        lib.notify({
            title = 'Garbage Job',
            description = msg,
            type = nType,
        })
        return
    end

    -- Fallback: simple native feed notification if ox_lib is not available
    BeginTextCommandThefeedPost("STRING")
    AddTextComponentSubstringPlayerName(('[Garbage Job] %s'):format(msg))
    EndTextCommandThefeedPostTicker(false, false)
end

RegisterNetEvent('rwh-garbage:client:notify', function(msg, nType)
    Notify(msg, nType)
end)

RegisterNetEvent('rwh-garbage:client:notifyPayout', function(reward, bagCount)
    local cash = reward.cash or 0
    local items = reward.items or {}
    local weapons = reward.weapons or {}

    local itemCount = #items
    local weaponCount = #weapons

    local parts = {}
    if cash > 0 then table.insert(parts, ('$%d cash'):format(cash)) end
    if itemCount > 0 then table.insert(parts, (('%d items'):format(itemCount))) end
    if weaponCount > 0 then table.insert(parts, (('%d weapon(s)'):format(weaponCount))) end

    local desc = ('Processed %d bags.'):format(bagCount or 0)
    if #parts > 0 then
        desc = desc .. ' You received: ' .. table.concat(parts, ', ') .. '.'
    end

    -- Push detailed summary into NUI if the terminal is open
    if nuiOpen then
        local lines = {}
        table.insert(lines, ('Processed %d bags.'):format(bagCount or 0))
        if cash > 0 then
            table.insert(lines, ('Cash: $%d'):format(cash))
        end
        if itemCount > 0 then
            table.insert(lines, 'Items:')
            for _, item in ipairs(items) do
                table.insert(lines, (' - %sx %s'):format(item.count or 1, item.name or 'unknown'))
            end
        end
        if weaponCount > 0 then
            table.insert(lines, 'Weapons:')
            for _, w in ipairs(weapons) do
                table.insert(lines, (' - %s'):format(w))
            end
        end

        SendNUIMessage({
            action = 'summary',
            lines = lines,
        })
    end

    -- Still show a quick toast so players notice immediately
    Notify(desc, 'success')
end)

-----------------------------------------------------
-- UTILITY: PLAYER STATE (CARRIED BAG)
-----------------------------------------------------
RegisterNetEvent('rwh-garbage:client:setCarryingBag', function(hasBag, bagType)
    carryingBag = hasBag and true or false
    carryingBagType = hasBag and bagType or nil
end)

-----------------------------------------------------
-- UTILITY: TRUCK ASSIGNMENT
-----------------------------------------------------
RegisterNetEvent('rwh-garbage:client:setAssignedTruck', function(plate, netId)
    assignedTruckPlate = plate
    assignedTruckNetId = netId
end)

local function getVehiclePlate(veh)
    if not veh or veh == 0 then return nil end
    return string.upper(GetVehicleNumberPlateText(veh) or '')
end

local function getNearestGarbageTruck(radius)
    radius = radius or (Config.TruckSearchRadius or 10.0)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)

    local handle, veh = FindFirstVehicle()
    local success
    local closestVeh
    local closestDist = radius + 0.1

    repeat
        local vehPos = GetEntityCoords(veh)
        local dist = #(vehPos - pos)
        if dist <= closestDist then
            -- Optional: restrict to our truck model only
            if not Config.LimitToGarbageModel or GetEntityModel(veh) == GetHashKey(Config.TruckModel or 'trash2') then
                closestVeh = veh
                closestDist = dist
            end
        end
        success, veh = FindNextVehicle(handle)
    until not success

    EndFindVehicle(handle)

    return closestVeh
end

-----------------------------------------------------
-- DUMPSTER INTERACTIONS
-----------------------------------------------------
local function playSimpleScenario(duration, scenario)
    local ped = PlayerPedId()
    TaskStartScenarioInPlace(ped, scenario, 0, true)
    Wait(duration)
    ClearPedTasks(ped)
end

local function checkDumpsterBagsEntity(entity)
    local coords = GetEntityCoords(entity)

    -- Searching animation while checking dumpster contents
    if lib then
        lib.progressCircle({
            duration = 2500,
            label = 'Checking dumpster...',
            position = 'bottom',
            useWhileDead = false,
            canCancel = false,
            disable = { move = true, car = true, combat = true },
            anim = {
                dict = 'amb@prop_human_bum_bin@base',
                clip = 'base',
            },
        })
    else
        playSimpleScenario(2500, 'PROP_HUMAN_BUM_BIN')
    end

    local result = lib.callback.await('rwh-garbage:server:getDumpsterInfo', false, {
        x = coords.x,
        y = coords.y,
        z = coords.z,
    })

    if not result or not result.ok then
        if result and result.reason == 'no_job' then
            Notify('You are not employed as a sanitation worker.', 'error')
        else
            Notify('Unable to read this dumpster.', 'error')
        end
        return
    end

    local remaining = result.remaining or 0
    local bagType = result.bagType or 'standard'
    local msg
    if remaining <= 0 then
        msg = ('This dumpster is empty (%s bags).'):format(bagType)
    else
        msg = ('This dumpster has %d %s bag(s) remaining.'):format(remaining, bagType)
    end

    Notify(msg, 'info')
end

local function checkDumpsterBagsCoords(coords)
    -- Searching animation while checking dumpster contents
    if lib then
        lib.progressCircle({
            duration = 2500,
            label = 'Checking dumpster...',
            position = 'bottom',
            useWhileDead = false,
            canCancel = false,
            disable = { move = true, car = true, combat = true },
            anim = {
                dict = 'amb@prop_human_bum_bin@base',
                clip = 'base',
            },
        })
    else
        playSimpleScenario(2500, 'PROP_HUMAN_BUM_BIN')
    end

    local result = lib.callback.await('rwh-garbage:server:getDumpsterInfo', false, {
        x = coords.x,
        y = coords.y,
        z = coords.z,
    })

    if not result or not result.ok then
        if result and result.reason == 'no_job' then
            Notify('You are not employed as a sanitation worker.', 'error')
        else
            Notify('Unable to read this dumpster.', 'error')
        end
        return
    end

    local remaining = result.remaining or 0
    local bagType = result.bagType or 'standard'
    local msg
    if remaining <= 0 then
        msg = ('This dumpster is empty (%s bags).'):format(bagType)
    else
        msg = ('This dumpster has %d %s bag(s) remaining.'):format(remaining, bagType)
    end

    Notify(msg, 'info')
end

local function takeBagFromDumpsterEntity(entity)
    if carryingBag then
        Notify('You are already carrying a garbage bag.', 'error')
        return
    end

    local coords = GetEntityCoords(entity)

    -- Animation for picking up a garbage bag
    if lib then
        lib.progressCircle({
            duration = 3000,
            label = 'Picking up garbage bag...',
            position = 'bottom',
            useWhileDead = false,
            canCancel = false,
            disable = { move = true, car = true, combat = true },
            anim = {
                dict = 'anim@heists@narcotics@trash',
                clip = 'pickup',
            },
        })
    else
        playSimpleScenario(3000, 'PROP_HUMAN_BUM_BIN')
    end

    TriggerServerEvent('rwh-garbage:server:takeBag', {
        x = coords.x,
        y = coords.y,
        z = coords.z,
    })
end

local function registerDumpsterTargets()
    -- Model-based dumpsters
    if Config.Dumpsters.Models and #Config.Dumpsters.Models > 0 then
        exports.ox_target:addModel(Config.Dumpsters.Models, {
            {
                name = 'rwh_garbage_checkbags',
                icon = 'fa-solid fa-dumpster',
                label = 'Check Bags',
                distance = Config.DumpsterInteractionRange or 2.0,
                onSelect = function(data)
                    checkDumpsterBagsEntity(data.entity)
                end,
            },
            {
                name = 'rwh_garbage_takebag',
                icon = 'fa-solid fa-trash',
                label = 'Take Bag',
                distance = Config.DumpsterInteractionRange or 2.0,
                canInteract = function(entity, distance, coords, name)
                    return not carryingBag
                end,
                onSelect = function(data)
                    takeBagFromDumpsterEntity(data.entity)
                end,
            },
        })
    end

    -- Explicit dumpster spots
    if Config.Dumpsters.Spots and #Config.Dumpsters.Spots > 0 then
        for index, spot in ipairs(Config.Dumpsters.Spots) do
            local zoneName = ('rwh_garbage_dumpster_spot_%d'):format(index)
            exports.ox_target:addBoxZone({
                coords = spot.coords,
                size = vec3(1.2, 1.2, 1.5),
                rotation = 0.0,
                debug = Config.Debug or false,
                options = {
                    {
                        name = zoneName .. '_check',
                        icon = 'fa-solid fa-dumpster',
                        label = 'Check Bags',
                        distance = Config.DumpsterInteractionRange or 2.0,
                        onSelect = function()
                            checkDumpsterBagsCoords(spot.coords)
                        end,
                    },
                    {
                        name = zoneName .. '_take',
                        icon = 'fa-solid fa-trash',
                        label = 'Take Bag',
                        distance = Config.DumpsterInteractionRange or 2.0,
                        canInteract = function()
                            return not carryingBag
                        end,
                        onSelect = function()
                            TriggerServerEvent('rwh-garbage:server:takeBag', {
                                x = spot.coords.x,
                                y = spot.coords.y,
                                z = spot.coords.z,
                            })
                        end,
                    },
                },
            })
        end
    end
end

-----------------------------------------------------
-- TRUCK INTERACTIONS
-----------------------------------------------------
local function loadBagIntoTruck(entity)
    if not carryingBag then
        Notify('You are not carrying a garbage bag.', 'error')
        return
    end

    local plate = getVehiclePlate(entity)
    if not plate or plate == '' then
        Notify('This vehicle has no plate; cannot load bags.', 'error')
        return
    end

    -- Animation for placing bag into truck
    if lib then
        lib.progressCircle({
            duration = 2500,
            label = 'Loading garbage bag...',
            position = 'bottom',
            useWhileDead = false,
            canCancel = false,
            disable = { move = true, car = true, combat = true },
            anim = {
                dict = 'anim@heists@narcotics@trash',
                clip = 'throw_b',
            },
        })
    else
        playSimpleScenario(2500, 'WORLD_HUMAN_GARDENER_LEAF_BLOWER')
    end

    TriggerServerEvent('rwh-garbage:server:loadBagIntoTruck', plate)
end

local function checkTruckBagCount(entity)
    local plate = getVehiclePlate(entity)
    if not plate or plate == '' then
        Notify('This vehicle has no plate.', 'error')
        return
    end

    local res = lib.callback.await('rwh-garbage:server:getTruckBagCount', false, plate)
    if not res or not res.ok then
        Notify('This truck is not registered for the garbage job.', 'error')
        return
    end

    Notify(('Truck contains %d/%d bags.'):format(res.count or 0, res.limit or 0), 'info')
end

local function unloadTruckBags()
    local veh = getNearestGarbageTruck(Config.TruckSearchRadius or 10.0)
    if not veh or veh == 0 then
        Notify('No garbage truck nearby to unload.', 'error')
        return
    end

    local plate = getVehiclePlate(veh)
    if not plate or plate == '' then
        Notify('This vehicle has no plate; cannot unload.', 'error')
        return
    end

    -- Animation for unloading truck at recycling center
    if lib then
        lib.progressCircle({
            duration = 3000,
            label = 'Unloading garbage bags...',
            position = 'bottom',
            useWhileDead = false,
            canCancel = false,
            disable = { move = true, car = true, combat = true },
            anim = {
                dict = 'anim@heists@narcotics@trash',
                clip = 'pickup',
            },
        })
    else
        playSimpleScenario(3000, 'WORLD_HUMAN_CLIPBOARD')
    end

    TriggerServerEvent('rwh-garbage:server:unloadTruckBags', plate)
end

local function processBags()
    local veh = getNearestGarbageTruck(Config.TruckSearchRadius or 10.0)
    local plate = nil
    if veh and veh ~= 0 then
        plate = getVehiclePlate(veh)
    end

    if not plate or plate == '' then
        -- If we don't find a nearby truck, fallback to assigned truck (if any)
        plate = assignedTruckPlate
    end

    if not plate or plate == '' then
        Notify('No garbage truck found to process bags for.', 'error')
        return
    end

    -- Animation while recycling / processing bags
    if lib then
        lib.progressCircle({
            duration = 3500,
            label = 'Processing garbage bags...',
            position = 'bottom',
            useWhileDead = false,
            canCancel = false,
            disable = { move = true, car = true, combat = true },
            anim = {
                dict = 'amb@prop_human_parking_meter@male@idle_a',
                clip = 'idle_a',
            },
        })
    else
        playSimpleScenario(3500, 'WORLD_HUMAN_CLIPBOARD')
    end

    TriggerServerEvent('rwh-garbage:server:processBags', plate)
end

-- NUI: Recycling terminal
RegisterNetEvent('rwh-garbage:client:openTerminal', function()
    if nuiOpen then return end
    nuiOpen = true

    SetNuiFocus(true, true)

    local name = GetPlayerName(PlayerId()) or 'UNKNOWN'
    local plate = assignedTruckPlate or 'N/A'
    local bagCount = 0

    if plate and plate ~= '' and plate ~= 'N/A' then
        local res = lib and lib.callback and lib.callback.await('rwh-garbage:server:getTruckBagCount', false, plate)
        if res and res.ok then
            bagCount = res.count or 0
        end
    end

    SendNUIMessage({
        action = 'open',
        operator = name,
        truckPlate = plate,
        bagCount = bagCount,
        logLine = 'Terminal session opened.',
    })
end)

RegisterNUICallback('close', function(_, cb)
    nuiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    cb('ok')
end)

RegisterNUICallback('startShift', function(_, cb)
    TriggerServerEvent('rwh-garbage:server:clockIn')
    cb('ok')
end)

RegisterNUICallback('endShift', function(_, cb)
    TriggerServerEvent('rwh-garbage:server:clockOut')
    cb('ok')
end)

RegisterNUICallback('endShiftReturn', function(_, cb)
    local plate = assignedTruckPlate
    if plate and plate ~= '' then
        TriggerServerEvent('rwh-garbage:server:endJob', plate, true)
        assignedTruckPlate = nil
        assignedTruckNetId = nil
    else
        Notify('No assigned garbage truck to return.', 'error')
    end
    cb('ok')
end)

RegisterNUICallback('processBags', function(_, cb)
    processBags()
    cb('ok')
end)

RegisterNUICallback('rentTruck', function(data, cb)
    local hours = tonumber(data and data.hours) or 1
    TriggerServerEvent('rwh-garbage:server:rentTruck', hours)
    cb('ok')
end)

local function registerTruckTargets()
    exports.ox_target:addGlobalVehicle({
        {
            name = 'rwh_garbage_loadbag',
            icon = 'fa-solid fa-dumpster',
            label = 'Load Bag',
            distance = 2.5,
            canInteract = function(entity, distance, coords, name)
                if distance > 3.0 then return false end
                if not carryingBag then return false end
                if Config.LimitToGarbageModel then
                    return GetEntityModel(entity) == GetHashKey(Config.TruckModel or 'trash2')
                end
                return true
            end,
            onSelect = function(data)
                loadBagIntoTruck(data.entity)
            end,
        },
        {
            name = 'rwh_garbage_checktruck',
            icon = 'fa-solid fa-eye',
            label = 'Check Bag Count',
            distance = 2.5,
            canInteract = function(entity, distance, coords, name)
                if distance > 3.0 then return false end
                if Config.LimitToGarbageModel then
                    return GetEntityModel(entity) == GetHashKey(Config.TruckModel or 'trash2')
                end
                return true
            end,
            onSelect = function(data)
                checkTruckBagCount(data.entity)
            end,
        },
    })
end

-----------------------------------------------------
-- RECYCLING CENTER INTERACTIONS
-----------------------------------------------------
RegisterNetEvent('rwh-garbage:client:spawnTruck', function(data)
    local modelName = data.model or 'trash2'
    local coords = data.coords or GetEntityCoords(PlayerPedId())
    local heading = data.heading or 0.0

    local model = joaat(modelName)
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(0)
    end

    local veh = CreateVehicle(model, coords.x, coords.y, coords.z, heading, true, false)
    SetVehicleOnGroundProperly(veh)
    SetVehicleNumberPlateText(veh, (Config.TruckPlatePrefix or 'RWHG') .. tostring(math.random(100, 999)))
    SetEntityAsMissionEntity(veh, true, true)

    local plate = getVehiclePlate(veh)
    local netId = NetworkGetNetworkIdFromEntity(veh)

    SetNetworkIdCanMigrate(netId, true)

    -- Inform server about the new truck.
    TriggerServerEvent('rwh-garbage:server:registerTruck', plate, netId, data.rentHours or 1, data.rentCost or (Config.RentBaseHourly or 35))

    assignedTruckPlate = plate
    assignedTruckNetId = netId

    Notify('Your garbage truck has been delivered. Collect trash around the city and return here to unload.', 'success')
end)

local function registerRecyclingCenterTargets()
    local rc = Config.RecyclingCenter
    if not rc then
        print('[RWH-Garbage] WARNING: Config.RecyclingCenter is missing.')
        return
    end

    -- Clock-in / management zone
    if rc.ClockIn and rc.ClockIn.coords then
        exports.ox_target:addBoxZone({
            coords = rc.ClockIn.coords,
            size = rc.ClockIn.size or vec3(1.5, 1.5, 2.0),
            rotation = rc.ClockIn.rotation or 0.0,
            debug = rc.ClockIn.debug or false,
            options = {
                {
                    name = 'rwh_garbage_clockin',
                    icon = 'fa-solid fa-user-clock',
                    label = 'Clock In',
                    onSelect = function()
                        TriggerServerEvent('rwh-garbage:server:clockIn')
                    end,
                },
                {
                    name = 'rwh_garbage_clockout',
                    icon = 'fa-solid fa-user-slash',
                    label = 'Clock Out',
                    onSelect = function()
                        TriggerServerEvent('rwh-garbage:server:clockOut')
                    end,
                },
                {
                    name = 'rwh_garbage_renttruck',
                    icon = 'fa-solid fa-truck',
                    label = ('Rent Garbage Truck%s'):format(
                        Config.TruckRentIsFree and '' or (' ($' .. Config.RentPrice .. ')')
                    ),
                    onSelect = function()
                        TriggerServerEvent('rwh-garbage:server:rentTruck')
                    end,
                },
            },
        })
    end

    -- Unload zone
    if rc.UnloadZone and rc.UnloadZone.coords then
        exports.ox_target:addBoxZone({
            coords = rc.UnloadZone.coords,
            size = rc.UnloadZone.size or vec3(4.0, 6.0, 3.0),
            rotation = rc.UnloadZone.rotation or 0.0,
            debug = rc.UnloadZone.debug or false,
            options = {
                {
                    name = 'rwh_garbage_unload',
                    icon = 'fa-solid fa-dumpster',
                    label = 'Unload Bags',
                    onSelect = function()
                        unloadTruckBags()
                    end,
                },
            },
        })
    end

    -- Processing zone + NUI terminal
    if rc.ProcessingZone and rc.ProcessingZone.coords then
        exports.ox_target:addBoxZone({
            coords = rc.ProcessingZone.coords,
            size = rc.ProcessingZone.size or vec3(3.0, 3.0, 2.5),
            rotation = rc.ProcessingZone.rotation or 0.0,
            debug = rc.ProcessingZone.debug or false,
            options = {
                {
                    name = 'rwh_garbage_process',
                    icon = 'fa-solid fa-recycle',
                    label = 'Process Bags (Quick)',
                    onSelect = function()
                        processBags()
                    end,
                },
                {
                    name = 'rwh_garbage_terminal',
                    icon = 'fa-solid fa-desktop',
                    label = 'Use Recycling Terminal',
                    onSelect = function()
                        TriggerEvent('rwh-garbage:client:openTerminal')
                    end,
                },
            },
        })
    end
end

-----------------------------------------------------
-- THREAD: REGISTER TARGETS ON RESOURCE START
-----------------------------------------------------
CreateThread(function()
    -- Wait a moment for ox_target / ox_lib to initialize.
    Wait(500)

    registerDumpsterTargets()
    registerTruckTargets()
    registerRecyclingCenterTargets()

    -- Map blip for garbage job location
    local rc = Config.RecyclingCenter
    if rc and rc.ClockIn and rc.ClockIn.coords then
        local blip = AddBlipForCoord(rc.ClockIn.coords.x, rc.ClockIn.coords.y, rc.ClockIn.coords.z)
        SetBlipSprite(blip, 318) -- garbage truck icon
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, 0.9)
        SetBlipColour(blip, 25)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Garbage Job")
        EndTextCommandSetBlipName(blip)
    end

    print('[RWH-Garbage] Client initialized.')
end)
