--[[ ============================================================
     RDE ADMIN — server/modules/database.lua
     Ingame DB Manager: list tables, browse, CRUD, raw query
     Red Dragon Elite | rd-elite.com
     ─────────────────────────────────────────────────────────────
     v1.0.9 NOTE
     Migrated from lib.callback.register → RegisterRdeRpc (native
     event RPC). Also dropped the duplicated isAdmin() helper —
     we now use the global IsRdeAdmin from server/main.lua so
     auth logic stays in exactly one place.

     Ox.* is available because @ox_core/lib/init.lua is loaded as
     shared_script in fxmanifest. No manual require.
     ============================================================ ]]

local function errLog(...)
    print('^1[RDE_ADMIN DB ERROR]^7', ...)
end

---Wrapper around the global IsRdeAdmin so the call sites stay short.
---IsRdeAdmin returns (bool, reason); we only need the bool here.
local function isAdmin(source)
    if type(IsRdeAdmin) ~= 'function' then
        errLog('IsRdeAdmin global missing — server/main.lua must load before this module')
        return false
    end
    local ok = IsRdeAdmin(source)
    return ok == true
end

-- ─── LIST TABLES ──────────────────────────────────────────────
RegisterRdeRpc('rde_admin:dbListTables', function(source)
    if not isAdmin(source) then return {} end

    local ok, result = pcall(MySQL.query.await,
        'SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema = DATABASE() ORDER BY table_name',
        {})

    if not ok or not result then
        errLog('Failed to query information_schema:', tostring(result))
        return {}
    end

    local hidden = {}
    for _, t in ipairs(Config.DB_HiddenTables) do hidden[t] = true end

    local tables = {}
    for _, row in ipairs(result) do
        local tname = row.table_name or row.TABLE_NAME
        if tname and not hidden[tname] then
            table.insert(tables, {
                name = tname,
                rows = row.table_rows or row.TABLE_ROWS or 0,
            })
        end
    end
    return tables
end)

-- ─── BROWSE TABLE ─────────────────────────────────────────────
RegisterRdeRpc('rde_admin:dbBrowseTable', function(source, data)
    if not isAdmin(source) then
        return { columns = {}, rows = {}, error = 'Access Denied' }
    end
    if type(data) ~= 'table' then
        return { columns = {}, rows = {}, error = 'Bad payload' }
    end

    -- Sanitize: only allow alphanumeric + underscore table names
    local tname = tostring(data.table or ''):match('^[%w_]+$')
    if not tname then
        return { columns = {}, rows = {}, error = 'Invalid table name' }
    end

    local offset   = tonumber(data.offset) or 0
    local limit    = math.min(tonumber(data.limit) or 50, Config.DB_MaxRows)
    local orderBy  = data.orderBy and tostring(data.orderBy):match('^[%w_]+$') and data.orderBy or nil
    local orderDir = (data.orderDir == 'DESC') and 'DESC' or 'ASC'
    local filter   = data.filter

    local colOk, colResult = pcall(MySQL.query.await,
        'SELECT COLUMN_NAME, DATA_TYPE, COLUMN_KEY FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION',
        { tname })
    if not colOk or not colResult then
        return { columns = {}, rows = {}, error = 'Table not found' }
    end

    local columns = {}
    for _, c in ipairs(colResult) do
        table.insert(columns, {
            name = c.COLUMN_NAME or c.column_name,
            type = c.DATA_TYPE   or c.data_type,
            key  = c.COLUMN_KEY  or c.column_key or '',
        })
    end

    local where, params = '', {}
    if filter and filter.column and tostring(filter.column):match('^[%w_]+$')
       and filter.value and filter.value ~= '' then
        where = (' WHERE `%s` LIKE ?'):format(filter.column)
        params[#params + 1] = '%' .. tostring(filter.value) .. '%'
    end

    local cntOk, countRes = pcall(MySQL.query.await,
        ('SELECT COUNT(*) as cnt FROM `%s`%s'):format(tname, where), params)
    local total = (cntOk and countRes and countRes[1]) and (countRes[1].cnt or 0) or 0

    local orderClause = orderBy and (' ORDER BY `%s` %s'):format(orderBy, orderDir) or ''
    local queryParams = {}
    for _, v in ipairs(params) do queryParams[#queryParams + 1] = v end
    queryParams[#queryParams + 1] = limit
    queryParams[#queryParams + 1] = offset

    local rOk, rows = pcall(MySQL.query.await,
        ('SELECT * FROM `%s`%s%s LIMIT ? OFFSET ?'):format(tname, where, orderClause),
        queryParams)

    if not rOk then
        return { columns = columns, rows = {}, error = tostring(rows) }
    end

    return {
        columns = columns,
        rows    = rows or {},
        total   = total,
        offset  = offset,
        limit   = limit,
    }
end)

-- ─── RAW QUERY ────────────────────────────────────────────────
RegisterRdeRpc('rde_admin:dbRunQuery', function(source, query)
    if not isAdmin(source) then return { ok = false, error = 'Access Denied' } end
    if type(query) ~= 'string' or #query < 3 then return { ok = false, error = 'Empty query' } end

    -- Block destructive DDL
    local upper = query:upper():match('^%s*(%a+)')
    local blocked = { DROP = true, TRUNCATE = true, ALTER = true }
    if blocked[upper] then
        return { ok = false, error = 'Blocked statement: ' .. tostring(upper) }
    end

    local ok, result = pcall(function()
        return MySQL.query.await(query, {})
    end)

    if ok then
        return {
            ok       = true,
            rows     = type(result) == 'table' and result or {},
            affected = type(result) == 'number' and result or 0,
        }
    end
    return { ok = false, error = tostring(result) }
end)

-- ─── DELETE ROW ───────────────────────────────────────────────
RegisterRdeRpc('rde_admin:dbDeleteRow', function(source, data)
    if not isAdmin(source) then return { ok = false } end
    if type(data) ~= 'table' then return { ok = false, error = 'Bad payload' } end

    local tname = tostring(data.table or ''):match('^[%w_]+$')
    local pk    = tostring(data.pk    or ''):match('^[%w_]+$')
    local val   = data.value

    if not tname or not pk or val == nil then
        return { ok = false, error = 'Invalid parameters' }
    end

    local ok, affected = pcall(MySQL.query.await,
        ('DELETE FROM `%s` WHERE `%s` = ? LIMIT 1'):format(tname, pk),
        { val })
    if not ok then return { ok = false, error = tostring(affected) } end
    return { ok = true, affected = affected or 0 }
end)

-- ─── UPDATE CELL ──────────────────────────────────────────────
RegisterRdeRpc('rde_admin:dbUpdateCell', function(source, data)
    if not isAdmin(source) then return { ok = false } end
    if type(data) ~= 'table' then return { ok = false, error = 'Bad payload' } end

    local tname  = tostring(data.table  or ''):match('^[%w_]+$')
    local column = tostring(data.column or ''):match('^[%w_]+$')
    local pk     = tostring(data.pk     or ''):match('^[%w_]+$')

    if not tname or not column or not pk then
        return { ok = false, error = 'Invalid parameters' }
    end

    local ok, affected = pcall(MySQL.query.await,
        ('UPDATE `%s` SET `%s` = ? WHERE `%s` = ? LIMIT 1'):format(tname, column, pk),
        { data.newValue, data.pkValue })
    if not ok then return { ok = false, error = tostring(affected) } end
    return { ok = true, affected = affected or 0 }
end)

-- ─── INSERT ROW ───────────────────────────────────────────────
RegisterRdeRpc('rde_admin:dbInsertRow', function(source, data)
    if not isAdmin(source) then return { ok = false } end
    if type(data) ~= 'table' then return { ok = false, error = 'Bad payload' } end

    local tname = tostring(data.table or ''):match('^[%w_]+$')
    if not tname or not data.row or type(data.row) ~= 'table' then
        return { ok = false, error = 'Invalid parameters' }
    end

    local cols, vals, params = {}, {}, {}
    for col, val in pairs(data.row) do
        local safeCol = tostring(col):match('^[%w_]+$')
        if safeCol then
            cols[#cols + 1]     = ('`%s`'):format(safeCol)
            vals[#vals + 1]     = '?'
            params[#params + 1] = val
        end
    end

    if #cols == 0 then return { ok = false, error = 'No columns provided' } end

    local ok, insertId = pcall(MySQL.insert.await,
        ('INSERT INTO `%s` (%s) VALUES (%s)'):format(tname, table.concat(cols, ','), table.concat(vals, ',')),
        params)
    if not ok then return { ok = false, error = tostring(insertId) } end
    return { ok = true, insertId = insertId }
end)
