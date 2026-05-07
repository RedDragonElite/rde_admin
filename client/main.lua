--[[ ============================================================
     RDE ADMIN — client/main.lua  (v1.1.1)
     NUI bridge · cursor management · key handler · native RPC
     Red Dragon Elite | rd-elite.com
     ─────────────────────────────────────────────────────────────
     The NUI bridge talks to the server via a tiny native RPC
     layer (rde_admin:rpc:request / rde_admin:rpc:response) with
     a monotonic request-id map. Zero ox_lib in the critical path;
     lib.notify and other ox_lib UI helpers are still used where
     they belong but never to ferry data.
     ============================================================ ]]

local isOpen  = false
local isAdmin = false

-- ─── LANGUAGE ─────────────────────────────────────────────────
local function L(key)
    local loc = Config.Locale[Config.DefaultLanguage] or Config.Locale['en']
    return loc[key] or key
end

local function debugLog(...)
    if Config.Debug then print('^3[RDE_ADMIN CLIENT]^7', ...) end
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  NATIVE RPC LAYER                                            ║
-- ╚══════════════════════════════════════════════════════════════╝
-- One pending-request map keyed by a monotonic id. Each request has
-- a single-shot resolve closure protected against double-fire from
-- both the response path AND the timeout path.
local pendingRequests = {}
local nextRequestId   = 0

---Send an RPC request to the server and resolve via callback.
---@param action  string   The RPC action name (e.g. 'rde_admin:getStats')
---@param cb      function Callback invoked exactly once with the result
---@param payload any?     Optional payload — pass anything, including nil
local function rpc(action, cb, payload)
    nextRequestId = nextRequestId + 1
    local requestId = nextRequestId

    local resolved = false
    local function resolve(value)
        if resolved then return end
        resolved = true
        pendingRequests[requestId] = nil
        local ok, err = pcall(cb, value)
        if not ok then debugLog('rpc cb threw:', action, err) end
    end

    pendingRequests[requestId] = resolve

    -- Timeout 3s — must be SHORTER than FiveM's internal NUI fetch timeout
    -- (~5s on b3000+) so the JS side gets a structured __error rather than
    -- an empty-body fallback which would surface as "Access denied".
    SetTimeout(3000, function()
        if pendingRequests[requestId] then
            debugLog(('rpc TIMEOUT id=%d action=%s'):format(requestId, action))
            resolve({ __error = 'timeout: ' .. action })
        end
    end)

    -- Defer TriggerServerEvent to the next tick so it always runs on the
    -- main thread, never inside a RegisterNUICallback coroutine. Wire-
    -- protocol false-as-nil sentinel keeps the event arg slot concrete;
    -- the server normalises false → nil before dispatch.
    local wirePayload = payload == nil and false or payload
    SetTimeout(0, function()
        TriggerServerEvent('rde_admin:rpc:request', requestId, action, wirePayload)
    end)
end

RegisterNetEvent('rde_admin:rpc:response', function(requestId, result)
    local resolve = pendingRequests[requestId]
    if not resolve then return end -- stale or already-resolved
    resolve(result == nil and { __null = true } or result)
end)

-- ─── PANEL OPEN / CLOSE ───────────────────────────────────────
local function closePanel()
    isOpen = false
    SendNUIMessage({ action = 'close' })
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SetTimeout(50,  function() SetNuiFocus(false, false); SetNuiFocusKeepInput(false) end)
    SetTimeout(150, function() SetNuiFocus(false, false); SetNuiFocusKeepInput(false) end)
    SetTimeout(350, function() SetNuiFocus(false, false); SetNuiFocusKeepInput(false) end)
    SetTimeout(600, function() SetNuiFocus(false, false); SetNuiFocusKeepInput(false) end)
    debugLog('Panel closed')
end

-- Coerce an RPC result into a definitive admin bool. Server returns
-- `{ ok = true, reason = ... }` for admins; be liberal in what we accept.
local function isAdminResult(result)
    if result == true then return true end
    if type(result) == 'table' and result.ok == true then return true end
    return false
end

local function openPanel()
    if not isAdmin then
        rpc('rde_admin:checkAdmin', function(result)
            isAdmin = isAdminResult(result)
            if isAdmin then
                isOpen = true
                SetNuiFocus(true, true)
                SetNuiFocusKeepInput(true)
                SendNUIMessage({ action = 'open' })
                debugLog('Panel opened (after re-check)')
            else
                lib.notify({
                    title       = 'RDE Admin',
                    description = L('no_permission'),
                    type        = 'error',
                })
            end
        end)
        return
    end
    isOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    SendNUIMessage({ action = 'open' })
    debugLog('Panel opened')
end

-- ─── ADMIN CHECK ──────────────────────────────────────────────
AddEventHandler('ox:playerLoaded', function()
    rpc('rde_admin:checkAdmin', function(result)
        isAdmin = isAdminResult(result)
        debugLog('Admin check (playerLoaded):', isAdmin)
    end)
end)

-- Fallback for late resource restarts where the player was already loaded
-- before the resource came up.
CreateThread(function()
    Wait(3000)
    rpc('rde_admin:checkAdmin', function(result)
        isAdmin = isAdminResult(result)
        debugLog('Admin check (delayed startup):', isAdmin)
    end)
end)

-- ─── KEYBINDS ─────────────────────────────────────────────────
RegisterKeyMapping('rde_admin_toggle', 'RDE Admin Panel', 'keyboard', Config.OpenKey)

RegisterCommand('rde_admin_toggle', function()
    if isOpen then closePanel() else openPanel() end
end, false)

-- ESC handler: detect ESC while panel is open and close it.
-- We do NOT DisableControlAction here — that caused the pause-menu flash
-- and movement-lock bug. SetNuiFocusKeepInput(true) is the input isolation
-- mechanism per FiveM docs; this thread is a pure Lua fallback.
CreateThread(function()
    while true do
        if isOpen then
            if IsControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 200) then
                closePanel()
            end
            Wait(0)
        else
            Wait(100)
        end
    end
end)

-- ─── NUI CALLBACKS ────────────────────────────────────────────
-- IMPORTANT: cb() MUST always be invoked with a TABLE, never a raw string
-- and never nil. On some FiveM builds (b3000+) a non-table response yields
-- an empty body and the JS side crashes with "Unexpected end of JSON input".
RegisterNUICallback('close', function(_, cb)
    pcall(closePanel)
    cb({ ok = true })
end)

local function nuiBridge(action, cb, payload)
    rpc(action, function(result)
        if type(result) ~= 'table' then
            cb({ value = result })
            return
        end
        cb(result)
    end, payload)
end

RegisterNUICallback('getPlayers', function(_, cb)
    nuiBridge('rde_admin:getPlayers', cb)
end)

RegisterNUICallback('playerAction', function(data, cb)
    nuiBridge('rde_admin:playerAction', cb, data)
end)

RegisterNUICallback('teleportToPlayer', function(data, cb)
    rpc('rde_admin:getPlayerCoords', function(coords)
        if type(coords) == 'table' and not coords.__error and not coords.__null
           and coords.x and coords.y and coords.z then
            SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z, false, false, false, false)
            cb({ ok = true })
        else
            cb({ ok = false, __error = (type(coords) == 'table' and coords.__error) or 'no coords' })
        end
    end, data and data.target or nil)
end)

RegisterNUICallback('sendConsoleCommand', function(data, cb)
    nuiBridge('rde_admin:sendConsoleCommand', cb, data and data.command)
end)

RegisterNUICallback('dbListTables', function(_, cb)
    nuiBridge('rde_admin:dbListTables', cb)
end)

RegisterNUICallback('dbBrowseTable', function(data, cb)
    nuiBridge('rde_admin:dbBrowseTable', cb, data)
end)

RegisterNUICallback('dbRunQuery', function(data, cb)
    nuiBridge('rde_admin:dbRunQuery', cb, data and data.query)
end)

RegisterNUICallback('dbDeleteRow', function(data, cb)
    nuiBridge('rde_admin:dbDeleteRow', cb, data)
end)

RegisterNUICallback('dbUpdateCell', function(data, cb)
    nuiBridge('rde_admin:dbUpdateCell', cb, data)
end)

RegisterNUICallback('dbInsertRow', function(data, cb)
    nuiBridge('rde_admin:dbInsertRow', cb, data)
end)

RegisterNUICallback('getStats', function(_, cb)
    nuiBridge('rde_admin:getStats', cb)
end)

RegisterNUICallback('getWarns', function(data, cb)
    nuiBridge('rde_admin:getWarns', cb, data and data.target)
end)

RegisterNUICallback('getBans', function(_, cb)
    nuiBridge('rde_admin:getBans', cb)
end)

RegisterNUICallback('unbanUser', function(data, cb)
    nuiBridge('rde_admin:unbanUser', cb, data)
end)

-- ─── LIVE CONSOLE RELAY ───────────────────────────────────────
RegisterNetEvent('rde_admin:consoleLine', function(line)
    if isOpen then
        SendNUIMessage({ action = 'consoleLine', line = line })
    end
end)

-- ─── CLEANUP ──────────────────────────────────────────────────
AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then
        if isOpen then closePanel() end
        SetNuiFocus(false, false) -- failsafe even if isOpen is stale
    end
end)
