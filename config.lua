--[[ ============================================================
     RDE ADMIN — config.lua
     Red Dragon Elite | rd-elite.com
     ============================================================ ]]

Config = {}

-- Set this to true to print verbose logs in BOTH client and server consoles.
-- Recommended `true` while diagnosing issues — flip to false for production.
Config.Debug = true

-- Keybind to open/close the admin panel (rebindable in GTA V settings)
Config.OpenKey = 'F9'

-- ─── TRIPLE ADMIN VERIFICATION (rde_doors-style) ──────────────
-- Three independent layers — any one passing grants admin access.
-- This mirrors the security model used in rde_doors so a single
-- mis-configured layer can't lock you out of your own server.
Config.AdminSystem = {
    -- Layer 1: ACE permission (cheapest, no ox_core dependency)
    -- In your server.cfg:
    --   add_ace group.admin rde.admin allow
    --   add_principal identifier.steam:XXXXX group.admin
    acePermission = 'rde.admin',

    -- Layer 2: ox_core group membership (any of these = admin)
    oxGroups = {
        admin      = true,
        superadmin = true,
        management = true,
        owner      = true,
        moderator  = true,
        headadmin  = true,
    },

    -- Layer 3: manual Steam-ID fallback — emergency back door if both
    -- ACE and ox_core are mis-configured. The architect always has access.
    -- Add more identifiers (steam:..., license:..., discord:...) as needed.
    identifiers = {
        'steam:110000101605859',  -- SerpentsByte (RDE Architect — default)
    },
}

-- Backward-compat alias — older code paths read Config.AdminGroups
Config.AdminGroups = Config.AdminSystem.oxGroups

-- Tables to hide from the ingame DB Manager
Config.DB_HiddenTables = {
    'mysql_async_debug',
    'ox_metadata',
}

-- Max rows per DB browse page (hard cap for safety)
Config.DB_MaxRows = 500

-- Console buffer size (lines kept in memory)
Config.ConsoleBufferSize = 300

-- Server stats refresh interval (ms) — handled clientside
Config.StatsRefreshInterval = 5000

Config.DefaultLanguage = 'en'  -- 'en' or 'de'

Config.Locale = {
    en = {
        no_permission  = 'Access Denied — Admin clearance required.',
        panel_opened   = 'RDE Admin Panel opened.',
        panel_closed   = 'RDE Admin Panel closed.',
        action_success = 'Action executed successfully.',
        action_failed  = 'Action failed — check server console.',
    },
    de = {
        no_permission  = 'Zugriff verweigert — Admin-Berechtigung erforderlich.',
        panel_opened   = 'RDE Admin Panel geöffnet.',
        panel_closed   = 'RDE Admin Panel geschlossen.',
        action_success = 'Aktion erfolgreich ausgeführt.',
        action_failed  = 'Aktion fehlgeschlagen — Server-Konsole prüfen.',
    },
}
