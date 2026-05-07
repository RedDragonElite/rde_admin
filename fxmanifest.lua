--[[
    ██████╗ ██████╗ ███████╗     █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗
    ██╔══██╗██╔══██╗██╔════╝    ██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║
    ██████╔╝██║  ██║█████╗      ███████║██║  ██║██╔████╔██║██║██╔██╗ ██║
    ██╔══██╗██║  ██║██╔══╝      ██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║
    ██║  ██║██████╔╝███████╗    ██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║
    ╚═╝  ╚═╝╚═════╝ ╚══════╝   ╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝

    rde_admin — Ingame Admin Desktop
    Architect: .:: RDE ⧌ Shin [△ ᛋᛅᚱᛒᛅᚾᛏᛋ ᛒᛁᛏᛅ ▽] ::.
    https://rd-elite.com | https://github.com/RedDragonElite

    ════════════════════════════════════════════════════════════════
    --- v1.1.1 (Console page hydration)
    ════════════════════════════════════════════════════════════════
    • The dedicated Console page (sidebar → Tools → Console) now
      pulls the existing server-side buffer on open, so admins see
      the boot tick + every prior [ADMIN]/[CMD] line immediately
      instead of staring at an empty pane until the next live event.
      The dashboard's mini console feed already worked — Console
      page now gets the same treatment via a new loadConsoleBuffer()
      that hydrates console-output without touching stats-console.

    ════════════════════════════════════════════════════════════════
    --- v1.1.0 (NUI bridge — fully working on FiveM b3000+)
    ════════════════════════════════════════════════════════════════
    🎯 ROOT-CAUSE FIX (the saga, in one paragraph):
    On modern FiveM (cerulean fx_version+, build b3000+) the NUI iframe
    is loaded from `nui://cfx-nui-<resname>/...`, which means
    `window.location.hostname` returns `cfx-nui-rde_admin` — WITH the
    prefix. RegisterNUICallback on the Lua side registers handlers at
    `https://<resname>/<callback>` — WITHOUT the prefix. So every fetch
    to `https://${window.location.hostname}/getStats` was 404'ing with
    an empty body, which `nuiPost` defensively coerced into `{}`, and
    the dashboard surfaced as "Access denied". The fix is one line in
    ui/app.js: prefer `GetParentResourceName()` (FiveM-injected helper
    that returns the bare resource name), fall back to stripping the
    `cfx-nui-` prefix from hostname for browser dev mode. txAdmin's
    NUI hardcodes `https://monitor/${callback}` to sidestep this same
    pitfall — same bug, same fix shape.

    Other v1.1.0 hardening (kept after the diagnostic dust settled):
    • Native RPC layer replaces all lib.callback usage in the bridge.
      TriggerServerEvent('rde_admin:rpc:request', id, action, payload)
      with a monotonic request-id map and TriggerClientEvent response.
      Zero ox_lib in the critical path; lib.notify and friends still
      used where they belong.
    • TriggerServerEvent is deferred via SetTimeout(0, ...) so it
      always runs on the main thread, never inside a NUI callback
      coroutine. Defensive — not strictly required once the hostname
      fix landed, but cheap insurance for edge-case FiveM builds.
    • RPC timeout 8s → 3s so we always beat FiveM's internal NUI fetch
      timeout (~5s) and the JS side gets a structured __error rather
      than an empty-body fallback.
    • Wire-protocol false-as-nil sentinel: nil payloads are sent as
      `false` and normalised back to nil server-side, so the network
      event always carries a concrete arg slot — avoids the same
      vararg-with-nil dispatch issue that bit lib.callback in some
      community ox_lib versions.
    • RegisterRdeRpc(action, handler) global on the server replaces
      lib.callback.register; database.lua module migrated. Dropped
      the duplicate isAdmin() helper from database.lua — it now uses
      the global IsRdeAdmin from server/main.lua, single source of
      truth for auth logic.

    ════════════════════════════════════════════════════════════════
    --- v1.0.7 fixes (movement lock + pause menu flash) ---
    ════════════════════════════════════════════════════════════════
    • Removed DisableControlAction(200/199/27) from ESC thread — this was
      blocking GTA input after panel close, causing movement lock, AND
      letting the pause menu flash through anyway on some frames
    • SetNuiFocusKeepInput(true) on open + (false) on close is now the sole
      mechanism for input isolation — cleaner and correct per FiveM docs
    • ESC thread now uses IsControlJustPressed as primary + IsDisabledControl
      as fallback — no side effects on GTA's own input handling

    --- v1.0.6 fixes (correct coxdocs API + definitive cursor fix) ---
    • Layer 2 now uses player.getGroup(string[]) per community ox_core docs —
      player.hasGroup does NOT exist in community ox_core, causing silent Layer 2
      failures on every getStats/getPlayers call despite ACE passing checkAdmin
    • Removed player.getGroups() fallback (also not the right API for group checks)
    • charId guard retained — correct per coxdocs (getGroup needs active char)
    • openPanel() now calls SetNuiFocusKeepInput(true) — prevents GTA from
      intercepting ESC before the NUI keydown handler can e.preventDefault() it,
      which was the root cause of the cursor-stays-after-ESC bug

    --- v1.0.5 fixes (Debug labels + aggressive cursor fix) ---
    • adminGuard() now logs callback name + source + cache state per call —
      makes it trivial to see exactly which callback is failing and why
    • adminGuard() coerces source to tonumber() — community ox can pass
      source as string in some callback contexts
    • closePanel() now fires SetNuiFocus(false,false) + SetNuiFocusKeepInput(false)
      at 0 / 50 / 150 / 350 / 600 ms — defeats all known cursor-stuck races
    • ESC thread now also disables F3 (control 27) and uses Wait(100) idle
    • closePanelFromUI() fires nuiPost('close') 3x (0 / 100 / 350 ms) so
      even if the first NUI message is dropped the cursor still releases

    --- v1.0.4 fixes (Admin cache + community ox_core compat) ---
    • isAdmin() now caches result per source for the entire session —
      ACE/group lookups only happen once, all subsequent callbacks hit cache
    • pcall() wrapper around IsPlayerAceAllowed (can throw in some builds)
    • Layer 2 now tries getGroups() as third fallback (full group table scan)
    • Removed player.charId guard — was blocking Layer 2 for unloaded chars
    • adminCache cleared on playerDropped to prevent stale entries
    • checkAdmin logs cache hit status for easier debugging

    --- v1.0.3 fixes (Cursor stuck + Triple Admin Verification) ---
    • Triple Admin Verification (rde_doors-style): ACE permission +
      ox_core groups + hardcoded identifiers — any one passes = admin
    • New /rde_admin_check command — diagnose admin status in F8
    • Default admin includes 'steam:110000101605859' (SerpentsByte)
    • closePanel() now fires SetNuiFocus(false,false) three times across
      0/50/250 ms — defeats race with other resources touching NUI focus
      (the "ESC closes UI but cursor stays" bug)
    • SetNuiFocusKeepInput(false) added for completeness
    • isAdmin() now returns (bool, reason) for full diagnostic logging
    • hasGroup() preferred over getGroup(filter) per coxdocs preferred API

    --- v1.0.2 fixes (Backend timeout / ESC won't close) ---
    • nuiPost now reads response as text() first and parses defensively —
      no more "Unexpected end of JSON input" crashes on empty bodies
    • All NUI callbacks now return TABLES (not raw strings) — FiveM b3000+
      otherwise sends an empty body for non-table cb() args
    • nuiBridge enforces a 5 s timeout — if the server callback never
      replies, the UI gets a graceful error instead of hanging
    • closePanelFromUI hides the desktop locally FIRST, then fire-and-forget
      to Lua — ESC always closes the panel even if the bridge is dead
    • teleportToPlayer uses the same timeout-safe pattern
    • Server returns plain `{}` instead of lib.array:new() — UI's asArray()
      coerces it correctly and avoids ox_lib version coupling

    --- v1.0.1 fixes ---
    • Fix Ox.GetPlayer() check (now uses player.charId per ox_core breaking changes)
    • Wrap all Ox.* calls in pcall — single bad player object no longer kills the callback
    • lib.array used for all list returns (forces JSON [] instead of {})
    • ESC always closes the panel (UI handler + GTA control failsafe)
    • Bans page uses dedicated rde_admin:getBans callback against ox_bans table
    • Status pill in titlebar shows backend connectivity at a glance
    • Console relay restricted to admins only
    • All NUI callbacks always invoke cb() so the UI never hangs
]]

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'rde_admin'
description '🐉 RDE Admin — Ingame Desktop Admin Panel with Player Manager, Console & DB CRUD'
version     '1.1.1'
author      'Red Dragon Elite (RDE) — SerpentsByte | rd-elite.com'
repository  'https://github.com/RedDragonElite/rde_admin'

-- ox_core MUST be imported via shared_script so Ox.* functions are available
shared_scripts {
    '@ox_lib/init.lua',
    '@ox_core/lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/modules/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/modules/*.lua',
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
}

dependencies {
    'oxmysql',
    'ox_core',
    'ox_lib',
}
