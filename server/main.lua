--[[ ============================================================
     RDE ADMIN — server/main.lua  (v1.1.1)
     Authentication · core RPC handlers · console relay
     Red Dragon Elite | rd-elite.com
     ─────────────────────────────────────────────────────────────
     API refs (coxdocs.dev):
       Ox.GetPlayer(source) / Ox.GetPlayers()
       player.getGroup(filter[]) → groupName, grade
       Ox.BanUser / Ox.UnbanUser / Ox.IsUserBanned

     Architecture:
       Client → TriggerServerEvent('rde_admin:rpc:request', id, action, payload)
       Server → handler dispatched, result sent back via
                TriggerClientEvent('rde_admin:rpc:response', src, id, result)

     RegisterRdeRpc(action, handler) is exposed as a global on the
     server-side Lua state (server_scripts share globals within a
     resource), so server/modules/database.lua uses it directly.
     ============================================================ ]]

local consoleBuffer = {}

local function debugLog(...)
    if Config.Debug then print('^3[RDE_ADMIN SERVER]^7', ...) end
end

local function errLog(...)
    print('^1[RDE_ADMIN ERROR]^7', ...)
end

local function safeCall(fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        errLog('Ox call failed:', tostring(result))
        return false, tostring(result)
    end
    return true, result
end

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  NATIVE RPC DISPATCHER                                       ║
-- ╚══════════════════════════════════════════════════════════════╝
local rpcHandlers = {}

function RegisterRdeRpc(action, handler)
    if rpcHandlers[action] then
        errLog('Duplicate RPC registration for action:', action)
    end
    rpcHandlers[action] = handler
    debugLog('RPC registered:', action)
end

RegisterNetEvent('rde_admin:rpc:request', function(requestId, action, payload)
    local src = source -- capture immediately, async boundaries can change it
    if payload == false then payload = nil end -- wire-protocol false-as-nil

    local function reply(result)
        TriggerClientEvent('rde_admin:rpc:response', src, requestId, result)
    end

    if type(action) ~= 'string' or type(requestId) ~= 'number' then
        errLog(('rpc: malformed request from src=%s'):format(tostring(src)))
        return reply({ __error = 'malformed request' })
    end

    local handler = rpcHandlers[action]
    if not handler then
        errLog(('rpc: unknown action "%s" from src=%s'):format(action, tostring(src)))
        return reply({ __error = 'unknown action: ' .. action })
    end

    debugLog(('rpc dispatch action=%s src=%s id=%d'):format(action, tostring(src), requestId))

    local ok, result = pcall(handler, src, payload)
    if not ok then
        errLog(('rpc handler "%s" threw: %s'):format(action, tostring(result)))
        return reply({ __error = 'handler failed: ' .. tostring(result) })
    end

    -- Wire-friendly: never send raw bool, always wrap so the response
    -- event has a concrete arg slot. Clients accept both shapes.
    if result == true then result = { ok = true } end
    if result == false then result = { ok = false } end

    reply(result)
end)

-- ─── ADMIN CACHE ──────────────────────────────────────────────
local adminCache = {}

AddEventHandler('playerDropped', function()
    adminCache[source] = nil
end)

local function isAdmin(source)
    source = tonumber(source)
    if not source or source <= 0 then return false, 'invalid source' end

    if adminCache[source] then
        return true, adminCache[source]
    end

    local cfg = Config.AdminSystem or {}

    -- Layer 1: ACE
    local aceOk, aceResult = pcall(IsPlayerAceAllowed, source, cfg.acePermission or 'rde.admin')
    if aceOk and aceResult then
        adminCache[source] = 'ace:' .. (cfg.acePermission or 'rde.admin')
        return true, adminCache[source]
    end

    -- Layer 2: ox_core groups via player.getGroup(string[]) per coxdocs
    -- (player.hasGroup does NOT exist in community ox_core).
    local ok, groupReason = pcall(function()
        local player = Ox.GetPlayer(source)
        if not player or not player.charId then return nil end
        local groupFilter = {}
        for groupName, _ in pairs(cfg.oxGroups or {}) do
            groupFilter[#groupFilter + 1] = groupName
        end
        if #groupFilter == 0 then return nil end
        local gName, gGrade = player.getGroup(groupFilter)
        if gName then
            return ('ox_group:%s(%s)'):format(gName, tostring(gGrade or 1))
        end
        return nil
    end)
    if ok and groupReason then
        adminCache[source] = groupReason
        return true, groupReason
    end
    if not ok then
        errLog('isAdmin Layer-2 pcall failed for src=' .. tostring(source) .. ': ' .. tostring(groupReason))
    end

    -- Layer 3: hardcoded identifiers (emergency back door)
    if cfg.identifiers and #cfg.identifiers > 0 then
        local identifiers = GetPlayerIdentifiers(source) or {}
        for _, id in ipairs(identifiers) do
            for _, allowed in ipairs(cfg.identifiers) do
                if id == allowed then
                    adminCache[source] = 'identifier:' .. id
                    return true, adminCache[source]
                end
            end
        end
    end

    return false, 'not authorised (no ACE / no ox group / no identifier match)'
end

IsRdeAdmin = isAdmin -- exposed for server/modules/database.lua

local function adminGuard(source, label)
    source = tonumber(source) -- community ox occasionally passes string sources
    local ok, reason = isAdmin(source)
    debugLog(('adminGuard[%s] src=%s cached=%s → %s (%s)'):format(
        tostring(label or '?'), tostring(source),
        tostring(adminCache[source] ~= nil), tostring(ok), tostring(reason)))
    return ok
end

local function pushConsole(text)
    local line = { time = os.date('%H:%M:%S'), text = tostring(text) }
    consoleBuffer[#consoleBuffer + 1] = line
    if #consoleBuffer > Config.ConsoleBufferSize then
        table.remove(consoleBuffer, 1)
    end
    for _, ply in ipairs(GetPlayers()) do
        local src = tonumber(ply)
        if src and (isAdmin(src)) then
            TriggerClientEvent('rde_admin:consoleLine', src, line)
        end
    end
end

local function getDisplayGroup(player)
    if not player or not player.charId then return 'user', 0 end
    local ok, groups = pcall(function() return player.getGroups() end)
    if not ok or type(groups) ~= 'table' then return 'user', 0 end

    local topGroup, topGrade = nil, 0
    for gName, gGrade in pairs(groups) do
        if Config.AdminGroups[gName] and gGrade > topGrade then
            topGroup, topGrade = gName, gGrade
        end
    end
    if topGroup then return topGroup, topGrade end

    for gName, gGrade in pairs(groups) do
        if gGrade > topGrade then topGroup, topGrade = gName, gGrade end
    end
    return topGroup or 'user', topGrade
end

-- ─── ADMIN CHECK ──────────────────────────────────────────────
RegisterRdeRpc('rde_admin:checkAdmin', function(source)
    local ok, reason = isAdmin(source)
    debugLog(('checkAdmin src=%s → %s (%s) [cached=%s]'):format(
        tostring(source), tostring(ok), tostring(reason), tostring(adminCache[source] ~= nil)))
    return { ok = ok, reason = reason }
end)

-- ─── DIAGNOSTIC COMMAND ───────────────────────────────────────
-- /rde_admin_check in F8 prints exactly why a player is (not) recognised
-- as admin. Indispensable for setup debugging.
RegisterCommand('rde_admin_check', function(source)
    if not source or source == 0 then
        print('^3[RDE_ADMIN]^7 /rde_admin_check is for player use (F8 console)')
        return
    end
    local ok, reason = isAdmin(source)
    local identifiers = GetPlayerIdentifiers(source) or {}
    local idList = table.concat(identifiers, '\n  • ')
    local msg = ('^5[RDE_ADMIN]^7 Admin check for ^3%s^7: ^%s%s^7\nReason: ^3%s^7\nYour identifiers:\n  • %s'):format(
        GetPlayerName(source) or '?',
        ok and '2' or '1',
        ok and 'GRANTED' or 'DENIED',
        tostring(reason), idList)
    TriggerClientEvent('chat:addMessage', source, { args = { '[RDE Admin]', msg } })
    print(msg)
end, false)

-- ─── PLAYER LIST ──────────────────────────────────────────────
RegisterRdeRpc('rde_admin:getPlayers', function(source)
    if not adminGuard(source, 'getPlayers') then return {} end

    local result = {}
    local ok, oxPlayers = safeCall(Ox.GetPlayers)
    if not ok or type(oxPlayers) ~= 'table' then
        errLog('Ox.GetPlayers returned no data — returning empty list')
        return result
    end

    for _, player in ipairs(oxPlayers) do
        -- Wrap each player so one bad object doesn't kill the whole list
        local pOk, entry = pcall(function()
            local src = player.source
            if not src then return nil end
            local ped    = GetPlayerPed(src)
            local coords = ped ~= 0 and GetEntityCoords(ped) or vector3(0, 0, 0)
            local groupName, grade = getDisplayGroup(player)
            return {
                source   = src,
                name     = GetPlayerName(src) or 'unknown',
                ping     = GetPlayerPing(src) or 0,
                license  = GetPlayerIdentifierByType(src, 'license') or 'unknown',
                steam    = GetPlayerIdentifierByType(src, 'steam')   or 'unknown',
                discord  = GetPlayerIdentifierByType(src, 'discord') or 'unknown',
                coords   = { x = coords.x, y = coords.y, z = coords.z },
                group    = groupName,
                grade    = grade,
                health   = ped ~= 0 and GetEntityHealth(ped) or 0,
                armour   = ped ~= 0 and GetPedArmour(ped) or 0,
                userId   = player.userId,
                charId   = player.charId,
            }
        end)
        if pOk and entry then table.insert(result, entry) end
    end
    return result
end)

-- ─── PLAYER COORDS (for teleport) ────────────────────────────
RegisterRdeRpc('rde_admin:getPlayerCoords', function(source, target)
    if not adminGuard(source, 'getPlayerCoords') then return { __error = 'denied' } end
    local tgt = tonumber(target)
    if not tgt then return { __error = 'invalid target' } end
    local ped = GetPlayerPed(tgt)
    if ped == 0 then return { __error = 'no ped' } end
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, z = c.z + 1.0 }
end)

-- ─── PLAYER ACTIONS ───────────────────────────────────────────
RegisterRdeRpc('rde_admin:playerAction', function(source, data)
    if not adminGuard(source, 'playerAction') then return { ok = false, msg = 'Access Denied' } end
    if type(data) ~= 'table' then return { ok = false, msg = 'Bad payload' } end

    local target     = tonumber(data.target)
    local action     = data.action
    local reason     = data.reason or 'No reason given'
    local adminName  = GetPlayerName(source) or ('src:' .. source)
    local targetName = (target and GetPlayerName(target)) or tostring(target)

    if not target or not action then return { ok = false, msg = 'Missing target/action' } end
    debugLog(('Action [%s] by %s (src:%s) on target %s'):format(action, adminName, source, target))

    if action == 'kick' then
        DropPlayer(target, ('Kicked by Admin: %s'):format(reason))
        pushConsole(('[ADMIN] %s kicked %s | Reason: %s'):format(adminName, targetName, reason))
        return { ok = true }
    elseif action == 'ban' then
        local ok, targetPlayer = safeCall(Ox.GetPlayer, target)
        if not ok or not targetPlayer or not targetPlayer.charId then
            return { ok = false, msg = 'Player not found / no active char' }
        end
        local hours = nil
        local mins = tonumber(data.minutes)
        if mins and mins > 0 then hours = math.ceil(mins / 60) end
        local banOk, banResult = safeCall(Ox.BanUser, targetPlayer.userId, reason, hours)
        if banOk and banResult then
            pushConsole(('[ADMIN] %s banned %s (userId:%s) | Reason: %s | Hours: %s'):format(
                adminName, targetName, targetPlayer.userId, reason, hours or 'permanent'))
            return { ok = true }
        end
        return { ok = false, msg = 'Ox.BanUser failed: ' .. tostring(banResult) }
    elseif action == 'warn' then
        MySQL.insert('INSERT INTO rde_admin_warns (license, name, reason, warned_by) VALUES (?, ?, ?, ?)', {
            GetPlayerIdentifierByType(target, 'license') or '',
            targetName, reason, adminName,
        })
        TriggerClientEvent('ox_lib:notify', target, {
            title = '⚠️ Warning', description = ('You have been warned: %s'):format(reason),
            type = 'error', duration = 10000,
        })
        pushConsole(('[ADMIN] %s warned %s | Reason: %s'):format(adminName, targetName, reason))
        return { ok = true }
    elseif action == 'freeze' then
        TriggerClientEvent('rde_admin:setFrozen', target, data.state); return { ok = true }
    elseif action == 'god' then
        TriggerClientEvent('rde_admin:setGod', target, data.state); return { ok = true }
    elseif action == 'revive' then
        TriggerClientEvent('rde_admin:revive', target); return { ok = true }
    elseif action == 'setHealth' then
        TriggerClientEvent('rde_admin:setHealth', target, tonumber(data.value) or 200); return { ok = true }
    elseif action == 'setArmour' then
        TriggerClientEvent('rde_admin:setArmour', target, tonumber(data.value) or 100); return { ok = true }
    elseif action == 'spectate' then
        TriggerClientEvent('rde_admin:spectate', source, target); return { ok = true }
    elseif action == 'bring' then
        local adminPed = GetPlayerPed(source)
        if adminPed == 0 then return { ok = false, msg = 'Admin ped invalid' } end
        local c = GetEntityCoords(adminPed)
        TriggerClientEvent('rde_admin:setCoords', target, { x = c.x + 2.0, y = c.y, z = c.z })
        return { ok = true }
    end
    return { ok = false, msg = 'Unknown action: ' .. tostring(action) }
end)

-- ─── WARN LIST ────────────────────────────────────────────────
RegisterRdeRpc('rde_admin:getWarns', function(source, target)
    if not adminGuard(source, 'getWarns') then return {} end
    local license = GetPlayerIdentifierByType(tonumber(target) or 0, 'license') or ''
    local warns = MySQL.query.await(
        'SELECT * FROM rde_admin_warns WHERE license = ? ORDER BY created_at DESC LIMIT 50',
        { license })
    return warns or {}
end)

-- ─── CONSOLE COMMAND ──────────────────────────────────────────
RegisterRdeRpc('rde_admin:sendConsoleCommand', function(source, command)
    if not adminGuard(source, 'sendConsoleCommand') then return { ok = false, msg = 'Access Denied' } end
    if type(command) ~= 'string' or #command < 1 then return { ok = false, msg = 'Empty command' } end
    pushConsole(('[CMD] %s > %s'):format(GetPlayerName(source) or source, command))
    local ok, err = pcall(ExecuteCommand, command)
    if not ok then
        pushConsole(('[ERR] %s'):format(tostring(err)))
        return { ok = false, msg = tostring(err) }
    end
    return { ok = true }
end)

-- ─── SERVER STATS ─────────────────────────────────────────────
RegisterRdeRpc('rde_admin:getStats', function(source)
    if not adminGuard(source, 'getStats') then return { ok = false, msg = 'Access Denied' } end

    local ok, oxPlayers = safeCall(Ox.GetPlayers)
    local playerCount = (ok and type(oxPlayers) == 'table') and #oxPlayers or #GetPlayers()

    return {
        ok         = true,
        players    = playerCount,
        maxPlayers = GetConvarInt('sv_maxclients', 32),
        serverName = GetConvar('sv_projectName', 'FiveM Server'),
        uptime     = GetGameTimer(),
        resources  = GetNumResources(),
        console    = consoleBuffer,
    }
end)

-- ─── BAN LIST ─────────────────────────────────────────────────
RegisterRdeRpc('rde_admin:getBans', function(source)
    if not adminGuard(source, 'getBans') then return {} end
    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT b.id, b.userId, b.reason, b.bannedBy AS banned_by,
                   b.bannedAt AS created_at, b.expiresAt AS expires_at,
                   COALESCE(u.username, CONCAT('userId:', b.userId)) AS name
            FROM   ox_bans b
            LEFT   JOIN users u ON u.userId = b.userId
            ORDER  BY b.bannedAt DESC
            LIMIT  100
        ]])
    end)
    if not ok then
        local fbOk, fbRows = pcall(MySQL.query.await, 'SELECT * FROM ox_bans ORDER BY bannedAt DESC LIMIT 100')
        if fbOk and fbRows then return fbRows end
        return {}
    end
    return rows or {}
end)

RegisterRdeRpc('rde_admin:unbanUser', function(source, data)
    if not adminGuard(source, 'unbanUser') then return { ok = false } end
    local userId = tonumber(data and data.userId)
    if not userId then return { ok = false, msg = 'Invalid userId' } end
    local ok, success = safeCall(Ox.UnbanUser, userId)
    if not ok then return { ok = false, msg = tostring(success) } end
    pushConsole(('[ADMIN] %s unbanned userId:%s'):format(GetPlayerName(source) or source, userId))
    return { ok = success == true }
end)

-- ─── AUTO TABLE CREATION ──────────────────────────────────────
CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query([[
            CREATE TABLE IF NOT EXISTS rde_admin_warns (
                id          INT AUTO_INCREMENT PRIMARY KEY,
                license     VARCHAR(64)  NOT NULL,
                name        VARCHAR(128) NOT NULL,
                reason      TEXT         NOT NULL,
                warned_by   VARCHAR(128) NOT NULL,
                created_at  TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_license (license)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]])
    end)
    if ok then
        print('^2[RDE_ADMIN]^7 Tables ensured. Admin panel ready. 🐉')
        print('^2[RDE_ADMIN]^7 Bans → ox_core native (Ox.BanUser / Ox.UnbanUser, table: ox_bans)')
    else
        errLog('Table creation failed:', err)
    end
end)

CreateThread(function()
    Wait(500)
    pushConsole('[BOOT] rde_admin server module loaded (v1.1.1)')
    pushConsole('[BOOT] Ox API ready — awaiting admin connections')
end)

debugLog('Server main loaded — Ox API ready, native RPC layer online (v1.1.1)')
