--[[ ============================================================
     RDE ADMIN — client/modules/effects.lua
     Server-triggered client effects:
     freeze / god / revive / health / armour / coords / spectate
     Red Dragon Elite | rd-elite.com
     ============================================================ ]]

local isFrozen    = false
local isGodMode   = false
local isSpectating = false

-- ─── FREEZE ───────────────────────────────────────────────────
RegisterNetEvent('rde_admin:setFrozen', function(state)
    isFrozen = state
    FreezeEntityPosition(PlayerPedId(), state)
    lib.notify({
        title       = 'RDE Admin',
        description = state and '🧊 You have been frozen.' or '✅ You have been unfrozen.',
        type        = state and 'warning' or 'success',
    })
end)

-- ─── GOD MODE ─────────────────────────────────────────────────
RegisterNetEvent('rde_admin:setGod', function(state)
    isGodMode = state
    NetworkSetEntityInvincible(PlayerPedId(), state)
    lib.notify({
        title       = 'RDE Admin',
        description = state and '🛡️ God Mode enabled.' or '⚔️ God Mode disabled.',
        type        = 'info',
    })
end)

-- Keep health/armour topped while god is active
CreateThread(function()
    while true do
        if isGodMode then
            local ped = PlayerPedId()
            SetEntityHealth(ped, 200)
            SetPedArmour(ped, 100)
            Wait(0)
        else
            Wait(1000)
        end
    end
end)

-- ─── REVIVE ───────────────────────────────────────────────────
RegisterNetEvent('rde_admin:revive', function()
    local ped = PlayerPedId()
    if IsEntityDead(ped) then
        NetworkResurrectLocalPlayer(0.0, 0.0, 0.0, 0.0, true, true)
    end
    SetEntityHealth(ped, 200)
    SetPedArmour(ped, 100)
    ClearPedBloodDamage(ped)
    lib.notify({ title = 'RDE Admin', description = '💊 You have been revived.', type = 'success' })
end)

-- ─── HEALTH / ARMOUR ──────────────────────────────────────────
RegisterNetEvent('rde_admin:setHealth', function(val)
    SetEntityHealth(PlayerPedId(), math.max(0, math.min(200, val)))
end)

RegisterNetEvent('rde_admin:setArmour', function(val)
    SetPedArmour(PlayerPedId(), math.max(0, math.min(100, val)))
end)

-- ─── TELEPORT ─────────────────────────────────────────────────
RegisterNetEvent('rde_admin:setCoords', function(coords)
    SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z, false, false, false, false)
    lib.notify({ title = 'RDE Admin', description = '📍 Teleported.', type = 'info' })
end)

-- ─── SPECTATE ─────────────────────────────────────────────────
RegisterNetEvent('rde_admin:spectate', function(targetSrc)
    if isSpectating then
        NetworkSetInSpectatorMode(false, PlayerPedId())
        isSpectating = false
        lib.notify({ title = 'RDE Admin', description = '👁️ Spectate disabled.', type = 'info' })
    else
        local targetPed = GetPlayerPed(GetPlayerFromServerId(targetSrc))
        if DoesEntityExist(targetPed) then
            NetworkSetInSpectatorMode(true, targetPed)
            isSpectating = true
            lib.notify({ title = 'RDE Admin', description = '👁️ Spectating...', type = 'info' })
        else
            lib.notify({ title = 'RDE Admin', description = '❌ Target not found.', type = 'error' })
        end
    end
end)
