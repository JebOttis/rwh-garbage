Config = {}

-- Framework selection:
-- 'qbx'  - for qbx_core (default)
-- 'qb'   - for qb-core
Config.Framework = 'qbx'

-- Name of the job required to use the system (if enabled below)
Config.JobName = 'garbage'

-- If true, only players with Config.JobName can see/use interactions.
Config.RequireJob = true

-- If true, players must "clock in" at the recycling center before renting truck / working.
Config.RequireClockIn = true

-- Max number of bags that a single garbage truck can hold.
Config.TruckBagLimit = 50

-- Model of the garbage truck to spawn for this job.
Config.TruckModel = 'trash'

-- Rent settings.
-- Legacy flat price (used for quick-rent label; 1 hour base by default).
Config.RentPrice = 35            -- Default to one hour at base rate.
Config.TruckRentIsFree = false   -- If true, rental is free.

-- Time-based rental settings for NUI / advanced rent flow.
Config.RentBaseHourly = 35       -- Base price per hour.
-- Allowed rental hour options and percent discounts.
-- Example: 1h (no discount), 2h (5% off), 4h (10% off), 8h (15% off).
Config.RentHourOptions = { 1, 2, 4, 8 }
Config.RentHourDiscounts = {
    [1] = 1.0,
    [2] = 0.95,
    [4] = 0.90,
    [8] = 0.85,
}

-- Damage fee multiplier when returning the truck.
-- DamageCost = rentCost * DamageChargeMultiplier * damageFraction (0.0-1.0)
Config.DamageChargeMultiplier = 2.0

-- How to split rewards between assigned players:
-- 'even'          - split evenly among all assigned players nearby the recycling center.
-- 'byContribution' - split based on number of bags each player loaded.
Config.PaySplitMode = 'even'

-- How close (in meters) players must be to the processing zone to receive payouts.
Config.PayoutRadius = 25.0

-- Minutes to wait before automatically cleaning up a truck that has no online players.
Config.TruckCleanupMinutes = 15

-- If true, unloading always moves ALL bags from the truck to the processing pool.
-- If false, only a limited number may be unloaded (see Config.UnloadMaxBags).
Config.UnloadAllBags = true
Config.UnloadMaxBags = 50 -- Only used if UnloadAllBags = false.

-- Debug printing to server console.
Config.Debug = false

-----------------------------------------------------
-- DUMPSTER CONFIGURATION
-----------------------------------------------------
-- You can interact with dumpsters via:
-- 1) Dumpster models found around the map (Config.Dumpsters.Models)
-- 2) Explicit dumpster spots with fixed coordinates (Config.Dumpsters.Spots)
--
-- The script lazily initializes each dumpster the first time it is used,
-- assigning a random number of bags and a bag type based on the tables below.
-----------------------------------------------------
Config.Dumpsters = {
    -- Dumpster prop models recognized by ox_target across the map.
    -- Add or remove as desired. These are common GTA V dumpster props.
    Models = {
        `prop_dumpster_01a`,
        `prop_dumpster_02a`,
        `prop_dumpster_02b`,
        `prop_dumpster_4a`,
        `prop_dumpster_4b`,
    },

    -- Default bag count range for any dumpster (model-based or coord-based)
    DefaultBagCount = {
        min = 3,
        max = 8,
    },

    -- Default bag type weights (for random selection on first interaction).
    -- Keys must match keys defined in Config.Rewards below.
    DefaultBagTypes = {
        standard    = 65,  -- 65% chance
        recyclable  = 30,  -- 30% chance
        hazardous   = 5,   -- 5% chance (optional higher-value bags)
    },

    -- Optional explicit spots with their own ranges and type weights.
    -- Each spot:
    --   coords   = vec3(x, y, z)
    --   bags     = { min = x, max = y } override for bag count
    --   bagTypes = { [bagTypeName] = weight, ... } override for type weights
    Spots = {
        -- Example dumpsters around a fictional recycling route
        {
            coords = vec3(-321.4, -1545.2, 31.0),
            bags = { min = 4, max = 10 },
            bagTypes = { standard = 80, recyclable = 20 },
        },
        {
            coords = vec3(-467.1, -1715.4, 18.7),
            bags = { min = 3, max = 6 },
            bagTypes = { standard = 60, recyclable = 40 },
        },
        {
            coords = vec3(403.1, -1623.9, 29.3),
            bags = { min = 5, max = 8 },
            bagTypes = { standard = 50, recyclable = 50 },
        },
    },
}

-----------------------------------------------------
-- RECYCLING CENTER CONFIGURATION
-----------------------------------------------------
Config.RecyclingCenter = {
    -- Where players "clock in" and manage their job.
    ClockIn = {
        coords = vec3(-350.0, -1569.0, 25.2),
        size = vec3(1.5, 1.5, 2.0),
        rotation = 0.0,
        debug = false, -- set true to visualize ox_target zone
    },

    -- Truck spawn location.
    TruckSpawn = {
        coords = vec3(-342.5, -1568.5, 24.8),
        heading = 60.0,
    },

    -- Zone to unload bags from the truck.
    -- Typically placed where trucks back up to unload.
    UnloadZone = {
        coords = vec3(-339.5, -1564.5, 25.0),
        size = vec3(4.0, 6.0, 3.0),
        rotation = 60.0,
        debug = false,
    },

    -- Zone center used for payout radius around the processing prop.
    ProcessingZone = {
        coords = vec3(-349.82, -1545.96, 26.72),
        size = vec3(3.0, 3.0, 2.5),
        rotation = 178.5,
        debug = false,
    },
}

-----------------------------------------------------
-- REWARDS CONFIGURATION
-----------------------------------------------------
-- Rewards are defined PER BAG TYPE.
-- The keys of Config.Rewards (e.g. "standard", "recyclable") are used as
-- bagType values inside Trucks[plate].bags entries on the server.
--
-- Structure:
--  Config.Rewards = {
--      [bagTypeName] = {
--          cash = { min = number, max = number },
--          items = {
--              { name = "itemname", chance = <0-100>, min = count, max = count },
--          },
--          weaponDrop = {
--              chance = 0.002, -- 0.2% (0.002 = 0.2%)
--              items = { "weapon_knife", "weapon_bat" },
--          }
--      }
--  }
--
-- "chance" fields for items are in percentage (0-100).
-- "weaponDrop.chance" is a per-bag float chance (0.0 - 1.0).
-----------------------------------------------------
Config.Rewards = {
    -- Standard trash bag: $2 - $4 per bag
    standard = {
        cash = { min = 2, max = 4 },
        items = {
            -- name, min, max, chance%% (if omitted = common)
            { name = "cola",              chance = 100, min = 1, max = 1 },
            { name = "water",             chance = 100, min = 1, max = 1 },
            { name = "garbage",           chance = 50,  min = 1, max = 2 },
            { name = "panties",           chance = 5,   min = 1, max = 1 },
            { name = "cash",              chance = 100, min = 1, max = 15 },
            { name = "cash",              chance = 5,   min = 20, max = 65 },
            { name = "bandage",           chance = 100, min = 1, max = 1 },
            { name = "lockpick",          chance = 3,   min = 1, max = 1 },
            { name = "advancedlockpick",  chance = 1,   min = 1, max = 1 },
            { name = "xtcbaggy",          chance = 2,   min = 1, max = 2 },
            { name = "meth",              chance = 1,   min = 1, max = 2 },
            { name = "oxy",               chance = 2,   min = 1, max = 3 },
            { name = "weed_seed",         chance = 1,   min = 1, max = 8 },
            { name = "ammo-9",            chance = 3,   min = 5, max = 15 },
            { name = "weapon_pistol",     chance = 1,   min = 1, max = 1 },
            { name = "luxury_watch",      chance = 2,   min = 1, max = 2 },
            { name = "antique_compass",   chance = 1,   min = 1, max = 2 },
            { name = "spy_gadget",        chance = 1,   min = 1, max = 2 },
            { name = "drugbag",           chance = 15,  min = 1, max = 2 },
            { name = "wallet",            chance = 10,  min = 1, max = 1 },
        },
        weaponDrop = {
            -- VERY rare so it does not inflate economy
            chance = 0.0005, -- 0.05% per bag (separate from item table above)
            items = { "weapon_knife", "weapon_bat" },
        },
    },

    -- Recyclable bag: $4 - $7 per bag
    recyclable = {
        cash = { min = 4, max = 7 },
        items = {
            -- Material rewards when processing recyclable bags
            { name = "scrap_metal",     chance = 80, min = 1, max = 5 },
            { name = "steel",           chance = 40, min = 1, max = 3 },
            { name = "aluminium",       chance = 45, min = 1, max = 4 },
            { name = "plastic",         chance = 60, min = 1, max = 5 },
            { name = "rubber",          chance = 40, min = 1, max = 3 },
            { name = "electric_scrap",  chance = 35, min = 1, max = 3 },
            { name = "glass",           chance = 50, min = 1, max = 4 },
            { name = "copper",          chance = 20, min = 1, max = 3 },
            { name = "carbon_fiber",    chance = 5,  min = 1, max = 2 },
            { name = "brass",           chance = 20, min = 1, max = 3 },
            { name = "synthetic_oil",   chance = 10, min = 1, max = 2 },
            { name = "acid",            chance = 8,  min = 1, max = 2 },
            -- drug-related finds (low chance)
            { name = "xtcbaggy",        chance = 2,  min = 1, max = 2 },
            { name = "meth",            chance = 1,  min = 1, max = 2 },
            { name = "oxy",             chance = 2,  min = 1, max = 3 },
            { name = "drugbag",         chance = 15, min = 1, max = 2 },
            { name = "wallet",          chance = 10, min = 1, max = 1 },
            { name = "weed_seed",       chance = 5,  min = 1, max = 8 },
        },
        weaponDrop = {
            -- STILL very rare, slightly higher than standard
            chance = 0.0007, -- 0.07% per bag
            items = { "weapon_switchblade", "weapon_sns" },
        },
    },

    -- Hazardous bag (optional, higher value): $6 - $10 per bag
    hazardous = {
        cash = { min = 6, max = 10 },
        items = {
            -- Material rewards when processing hazardous bags (same table, rarer bag type + higher cash)
            { name = "scrap_metal",     chance = 80, min = 1, max = 5 },
            { name = "steel",           chance = 40, min = 1, max = 3 },
            { name = "aluminium",       chance = 45, min = 1, max = 4 },
            { name = "plastic",         chance = 60, min = 1, max = 5 },
            { name = "rubber",          chance = 40, min = 1, max = 3 },
            { name = "electric_scrap",  chance = 35, min = 1, max = 3 },
            { name = "glass",           chance = 50, min = 1, max = 4 },
            { name = "copper",          chance = 20, min = 1, max = 3 },
            { name = "carbon_fiber",    chance = 5,  min = 1, max = 2 },
            { name = "brass",           chance = 20, min = 1, max = 3 },
            { name = "synthetic_oil",   chance = 10, min = 1, max = 2 },
            { name = "acid",            chance = 8,  min = 1, max = 2 },
            -- drug-related finds (slightly better odds than recyclable)
            { name = "xtcbaggy",        chance = 3,  min = 1, max = 2 },
            { name = "meth",            chance = 2,  min = 1, max = 2 },
            { name = "oxy",             chance = 3,  min = 1, max = 3 },
            { name = "drugbag",         chance = 15, min = 1, max = 2 },
            { name = "wallet",          chance = 10, min = 1, max = 1 },
            { name = "weed_seed",       chance = 5,  min = 1, max = 8 },
        },
        weaponDrop = {
            -- Still VERY rare, but best odds among bag types
            chance = 0.001, -- 0.1% per bag
            items = { "weapon_switchblade", "weapon_sns", "weapon_knife" },
        },
    },
}

-----------------------------------------------------
-- INTERNAL MISC SETTINGS (you can tweak but not required)
-----------------------------------------------------
-- How close (in meters) a player must be to a dumpster to interact.
Config.DumpsterInteractionRange = 2.0

-- How far from the player we look for a valid garbage truck when unloading/processing.
Config.TruckSearchRadius = 10.0

-- Small prefix for truck plates so you can identify job vehicles.
Config.TruckPlatePrefix = 'RWHG'

-- Model for dropped garbage bag props on the ground.
Config.BagPropModel = 'prop_ld_rub_binbag_01'

-- OPTIONAL: Change this to lock interactions to a specific vehicle model only.
-- By default, any vehicle with a registered truck plate is allowed.
Config.LimitToGarbageModel = true
