# rde_admin
🐉 ULTIMATE IN-GAME ADMIN DESKTOP V1.1.1 — Built on ox_core & Native RPC! 🛠

<img width="1024" height="1024" alt="image" src="https://github.com/user-attachments/assets/PLACEHOLDER_BANNER" />

PREVIEW:
https://www.youtube.com/watch?v=YOUR_VIDEO_ID

# 🐉 rde_admin

[![Version](https://img.shields.io/badge/version-1.1.1-red?style=for-the-badge)](https://github.com/RedDragonElite/rde_admin)
[![License](https://img.shields.io/badge/license-RDE%20Black%20Flag-black?style=for-the-badge)](LICENSE)
[![FiveM](https://img.shields.io/badge/FiveM-Compatible-blue?style=for-the-badge)](https://fivem.net)
[![ox_core](https://img.shields.io/badge/Framework-ox__core-blue?style=for-the-badge)](https://github.com/communityox/ox_core)
[![Native RPC](https://img.shields.io/badge/Bridge-Native%20RPC-purple?style=for-the-badge)](https://github.com/RedDragonElite/rde_admin)
[![Quality](https://img.shields.io/badge/Quality-Production-gold?style=for-the-badge)](https://github.com/RedDragonElite)

**🛠 RDE ADMIN | In-Game Desktop Admin Panel for FiveM ox_core | Player Manager · Live Console · DB CRUD · Ban Manager | Production-Ready**

*Built by [Red Dragon Elite](https://rd-elite.com) | Free Forever | No Paywalls | No Legacy*

[📖 Installation](#-installation) • [⚙️ Configuration](#️-configuration) • [🌍 Locales](#-locales) • [🛡 Triple Verification](#-triple-admin-verification) • [🐛 Troubleshooting](#-troubleshooting) • [🌐 Website](https://rd-elite.com) • [🔭 Terminal](https://rd-elite.com/Files/NOSTR/)

---

## 🔥 Why This Destroys Every Other Admin Panel

Every other admin panel is either paid, ESX/QB-only, a glorified one-line command menu, or a Tebex rug-pull waiting to happen.

We said no.

| ❌ Other Admin Scripts | ✅ rde_admin |
|---|---|
| Paid Tebex resources for basic kick/ban | 100% free forever — RDE Black Flag |
| Basic chat-command menus (one-line text) | Real desktop window UI with traffic-light controls |
| ESX / QBCore bloat | ox_core native — the future, not the past |
| Single hardcoded admin list | Triple verification: ACE + ox groups + identifier fallback |
| No ingame DB access — leave the server, open phpMyAdmin | Full ingame DB CRUD with paginated browse & raw query |
| Bans are a separate broken script | Native `Ox.BanUser` / `Ox.UnbanUser` integration |
| Discord webhooks for ban logs (deletable) | Live admin-only console feed in-game |
| `lib.callback` everywhere (404s on b3000+) | Native RPC layer — zero ox_lib in the critical path |
| Locks you out if one permission is wrong | Triple-layer fallback — one mis-config can't kill access |
| 0.5ms+ idle | < 0.01ms idle when the panel is closed |
| No locale support | Full EN / DE out of the box |
| No diagnostic tools | `/rde_admin_check` shows exactly *why* permission failed |

### 🎯 Key Features

- 🖥 **Real Desktop UI** — draggable window, macOS-style traffic lights, multi-page sidebar
- 🛡 **Triple Admin Verification** — ACE permission + ox_core groups + identifier fallback (any one passes)
- 👥 **Full Player Management** — kick, ban, warn, freeze, god, revive, set health/armour, spectate, bring, teleport
- 📺 **Live Server Console** — real-time stream restricted to admins, with command input ingame
- 🗄 **Ingame Database Manager** — browse, sort, filter, edit, insert, delete + raw SQL query (DROP/TRUNCATE/ALTER blocked at the gate)
- 🚫 **Native ox_core Bans** — direct `Ox.BanUser` / `Ox.UnbanUser` against the `ox_bans` table
- ⚡ **Native RPC Layer** — `TriggerServerEvent` with monotonic request-IDs, zero `lib.callback` in the critical path
- 🔑 **Permission Cache** — first lookup cached per session, subsequent calls hit memory
- 🔧 **Diagnostic Tooling** — `/rde_admin_check` command shows exactly why a permission check passed or failed
- 🛠 **Auto-Migration** — `rde_admin_warns` table auto-creates on first boot, no SQL import needed
- 🌍 **Multilanguage** — EN / DE out of the box, add any language in minutes
- 🛡 **Server-Side Authority** — every callback gated by `adminGuard()`, source coerced to number, all Ox calls pcall-wrapped

---

## 📸 Screenshots

> Coming soon — drop a PR with your screenshots!

The dashboard, players list, database browser, and live console — all in one draggable desktop window.

---

## 📦 Dependencies

```
oxmysql        → https://github.com/communityox/oxmysql
ox_lib         → https://github.com/communityox/ox_lib
ox_core        → https://github.com/communityox/ox_core
```

> **⚠ Important:** Use the **CommunityOx** forks (linked above), not the abandoned `overextended/*` repos. ox_core was discontinued in 2025 and forked by the community — the old repos are stale.

---

## 🚀 Installation

### Step 1: Clone or download

```bash
cd resources
git clone https://github.com/RedDragonElite/rde_admin.git
```

### Step 2: Add to server.cfg

```cfg
# Dependencies first — order matters!
ensure oxmysql
ensure ox_lib
ensure ox_core

# The admin panel
ensure rde_admin

# Grant ACE permission to your admin group
add_ace group.admin rde.admin allow
add_principal identifier.steam:XXXXXXXXXXXXXXXXX group.admin
```

### Step 3: Configure (optional)

`config.lua` is fully self-documented. Defaults work out of the box. See [Configuration](#️-configuration).

### Step 4: Start your server

That's it. The `rde_admin_warns` table auto-creates on first boot. No SQL import needed. The `ox_bans` and `users` tables are read directly from your existing ox_core schema.

In-game: press **F9**, or type `/rde_admin_toggle` in F8.

---

## ⚙️ Configuration

`config.lua` is fully self-documented. Key sections:

```lua
-- Master debug toggle — verbose RPC dispatch logs on both sides
Config.Debug = true

-- Default keybind (rebindable via GTA Settings → Keybinds)
Config.OpenKey = 'F9'

-- ─── TRIPLE ADMIN VERIFICATION (rde_doors-style) ──────────────
Config.AdminSystem = {
    -- Layer 1: ACE permission (cheapest, framework-free)
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

    -- Layer 3: hardcoded identifiers (emergency back door)
    identifiers = {
        'steam:110000101605859',  -- Architect default
    },
}

-- Database Manager
Config.DB_HiddenTables = { 'mysql_async_debug', 'ox_metadata' }
Config.DB_MaxRows      = 500   -- Hard cap per browse page

-- Console buffer
Config.ConsoleBufferSize = 300

-- Language: 'en' or 'de'
Config.DefaultLanguage = 'en'
```

> **The Triple Verification model is borrowed from `rde_doors`** — three independent layers means a single mis-configured ACE or ox group can never lock you out of your own server. Set up Layer 3 with your Steam identifier first and you have a guaranteed back door.

---

## 🛡 Triple Admin Verification

Three independent layers. **Any one passes = admin.** First layer to pass is cached for the session.

| Layer | Source | Speed | Use Case |
|---|---|---|---|
| **1 — ACE** | `IsPlayerAceAllowed(src, 'rde.admin')` | Instant | Standard admins, server.cfg-driven |
| **2 — ox_core Groups** | `player.getGroup({...})` per coxdocs API | Cached | Full ox_core integration, group hierarchy |
| **3 — Identifiers** | Hardcoded steam/license/discord IDs | Instant | Emergency back door for the architect |

### Diagnostic Command

In F8 / chat, type:

```
/rde_admin_check
```

Output (in chat **and** server console):

```
[RDE_ADMIN] Admin check for SerpentsByte: GRANTED
Reason: ace:rde.admin
Your identifiers:
  • steam:110000101605859
  • license:abc123def456...
  • discord:456789012345678
  • fivem:123456
```

**If you see DENIED**, the reason field tells you exactly which layer to fix.

---

## 🌍 Locales

All user-facing text lives in `config.lua` under `Config.Locale`. Default is English. Switch language:

```lua
Config.DefaultLanguage = 'de'
```

**Add a new language:**

```lua
Config.Locale['es'] = {
    no_permission  = 'Acceso Denegado — Se requiere permiso de administrador.',
    panel_opened   = 'Panel de Administración RDE abierto.',
    panel_closed   = 'Panel de Administración RDE cerrado.',
    action_success = 'Acción ejecutada con éxito.',
    action_failed  = 'Acción fallida — verifique la consola del servidor.',
}
Config.DefaultLanguage = 'es'
```

Currently supported:

| Code | Language |
|------|----------|
| `en` | 🇬🇧 English |
| `de` | 🇩🇪 Deutsch |

---

## 🗂 Folder Structure

```
rde_admin/
├── fxmanifest.lua
├── config.lua
├── README.md
├── LICENSE
├── server/
│   ├── main.lua                    ← Authentication, RPC dispatcher, core handlers
│   └── modules/
│       └── database.lua            ← DB Manager: list, browse, CRUD, raw query
├── client/
│   ├── main.lua                    ← NUI bridge, RPC layer, key handler, cursor mgmt
│   └── modules/
│       └── effects.lua             ← Server-triggered effects (freeze/god/revive/etc)
└── ui/
    ├── index.html                  ← Desktop window markup
    ├── style.css                   ← Dragon-dark theme
    └── app.js                      ← Window manager, page logic, NUI bridge
```

---

## 🔧 Debug Commands

Enable with `Config.Debug = true` in `config.lua`, then in-game / F8:

| Command | Description |
|---------|-------------|
| `/rde_admin_toggle` | Open or close the admin panel |
| `/rde_admin_check` | Diagnose your admin status — shows GRANTED/DENIED + reason + all identifiers |
| **F9** | Default keybind — same as `/rde_admin_toggle` |

When `Config.Debug = true`, every RPC dispatch is logged with action name, source, request ID, and admin-cache state — both client (F8) and server console.

---

## 🛡 Security

- All sensitive actions validated **server-side** via `adminGuard()`
- Source coerced to `tonumber()` — community ox occasionally passes string sources
- All `Ox.*` calls wrapped in `pcall` — one bad player object can't kill the player list
- DB Manager **blocks DROP / TRUNCATE / ALTER** at the server, regardless of admin level
- Hard `LIMIT 1` on every UPDATE / DELETE — accidental fat-finger never wipes a table
- Native RPC layer with monotonic request-IDs — no per-call closure leaks, single-shot resolve guards against double-fire
- Console relay restricted to admins only — non-admins receive zero events
- Permission cache cleared on `playerDropped` — no stale entries
- All NUI callbacks always invoke `cb()` with a table — JS side never crashes on garbage responses
- Wire-protocol false-as-nil sentinel — concrete network arg slots avoid vararg-with-nil dispatch edge cases

---

## 🐛 Troubleshooting

### `Access Denied` when opening the panel

```
1. Run /rde_admin_check in F8 — it tells you EXACTLY why
2. Verify in server.cfg:
     add_ace group.admin rde.admin allow
     add_principal identifier.steam:XXX group.admin
3. Add your steam ID to Config.AdminSystem.identifiers as a fallback
4. Confirm ox_core is loaded BEFORE rde_admin (server.cfg order matters)
```

### Panel opens but every page shows `Access Denied`

This was the v1.0.x NUI hostname bug — fixed in v1.1.0. If you're seeing it on v1.1.0+:

```
✅ Verify version in fxmanifest.lua matches your panel's title bar
✅ Open F8 dev tools — fetch URLs should be https://rde_admin/...
   NOT https://cfx-nui-rde_admin/...
✅ Set Config.Debug = true and check both consoles for RPC dispatch logs
✅ Check that GetParentResourceName() exists in your FiveM build (b2802+)
```

### Database Manager returns empty tables

```
✅ Verify oxmysql is loaded and connected (check oxmysql startup logs)
✅ Confirm the table isn't in Config.DB_HiddenTables
✅ MySQL user needs SELECT on information_schema
```

### Bans page empty after banning someone

```
✅ Confirm you're using the CommunityOx fork of ox_core (not abandoned overextended/)
✅ Check the ox_bans table exists: SELECT * FROM ox_bans LIMIT 5
✅ Verify Ox.BanUser succeeded — look in the live console feed for the ban acknowledgement
```

### Console page is empty

If you're on **< v1.1.1**: this was a missing initial-buffer load. Update to v1.1.1.

If you're on **v1.1.1+** and still seeing it:

```
✅ Confirm Config.Debug = true and check F8 for "rpc PENDING" / "rpc RESPONSE" lines on Console page open
✅ Switch to Dashboard — if the mini console feed there is also empty, the buffer didn't initialize
✅ /restart rde_admin and check server console for [BOOT] tick messages
```

### Resource refuses to start / `attempt to call a nil value`

```
✅ Ensure ox_core, ox_lib, oxmysql start BEFORE rde_admin in server.cfg
✅ Run on a recent FiveM build (b3000+ recommended, tested on b3788)
✅ Use the CommunityOx forks, not the abandoned overextended/ ones
```

---

## 📚 Tech Stack

```
ox_core        → Player & group management, native bans
ox_lib         → UI helpers (lib.notify), locale loader
oxmysql        → Async database access (information_schema introspection)
Native FiveM   → TriggerServerEvent / TriggerClientEvent RPC layer
NUI            → Desktop window UI in HTML/CSS/JS
```

**Why no `lib.callback`?** Because community ox_lib has a vararg-with-nil dispatch edge case when fired from inside a `RegisterNUICallback` coroutine on FiveM b3000+. We replaced it with a tiny native RPC layer (40 lines client + 30 lines server) and never looked back. See [v1.1.0 changelog in `fxmanifest.lua`](fxmanifest.lua) for the full forensics.

---

## 🤝 Contributing

PRs are always welcome.

1. **Fork** the repository
2. **Create** a branch: `git checkout -b feature/your-feature`
3. **Test** on a live server before submitting
4. **Commit**: `git commit -m 'feat: your feature description'`
5. **Push**: `git push origin feature/your-feature`
6. **Open** a Pull Request with a clear description

**Guidelines:**

- ✅ Keep the RDE header in all files
- ✅ Follow existing code style — ox_core, ox_lib, native RPC
- ✅ Run `luac -p` on every modified `.lua` file before pushing
- ✅ Run `node --check ui/app.js` if you touched JS
- ✅ Test with `Config.Debug = true` before PR
- ❌ No telemetry, no paywalls, no ESX/QBCore
- ❌ Don't downgrade security — server-side `adminGuard()` stays on every callback
- ❌ Don't reintroduce `lib.callback` in the critical path
- ❌ Don't hardcode user-facing strings — extend `Config.Locale`

---

## 📜 License

**RDE Black Flag Source License v6.66**

```
###################################################################################
#                                                                                 #
#      .:: RED DRAGON ELITE (RDE)  -  BLACK FLAG SOURCE LICENSE v6.66 ::.         #
#                                                                                 #
#   PROJECT:    RDE_ADMIN (IN-GAME DESKTOP ADMIN PANEL FOR FIVEM OX_CORE)         #
#   ARCHITECT:  .:: RDE ⧌ Shin [△ ᛋᛅᚱᛒᛅᚾᛏᛋ ᛒᛁᛏᛅ ▽] ::. | https://rd-elite.com     #
#   ORIGIN:     https://github.com/RedDragonElite                                 #
#                                                                                 #
#   WARNING: THIS CODE IS PROTECTED BY DIGITAL VOODOO AND PURE HATRED FOR LEAKERS #
#                                                                                 #
#   [ THE RULES OF THE GAME ]                                                     #
#                                                                                 #
#   1. // THE "FUCK GREED" PROTOCOL (FREE USE)                                    #
#      You are free to use, edit, and abuse this code on your server.             #
#      Learn from it. Break it. Fix it. That is the hacker way.                   #
#      Cost: 0.00€. If you paid for this, you got scammed by a rat.               #
#                                                                                 #
#   2. // THE TEBEX KILL SWITCH (COMMERCIAL SUICIDE)                              #
#      Listen closely, you parasites:                                             #
#      If I find this script on any paid store, Patreon, or "Premium Pack":       #
#      > I will DMCA your store into oblivion.                                    #
#      > I will publicly shame your community on Nostr. Permanently.              #
#      > I hope you accidentally ban yourself from your own server with no        #
#        recovery path and no admin left to undo it.                              #
#      SELLING FREE WORK IS THEFT. AND I AM THE JUDGE.                            #
#                                                                                 #
#   3. // THE CREDIT OATH                                                         #
#      Keep this header. If you remove my name, you admit you have no skill.      #
#      You can add "Edited by [YourName]", but never erase the original creator.  #
#      Don't be a skid. Respect the architecture.                                 #
#                                                                                 #
#   4. // THE CURSE OF THE COPY-PASTE                                             #
#      This code implements native FiveM RPC dispatch with monotonic request-ids, #
#      defensive NUI hostname handling for cerulean+, triple-layer admin          #
#      verification, ingame SQL CRUD with destructive-DDL gates, and a full       #
#      desktop window manager in vanilla JS. If you copy-paste without            #
#      understanding, you WILL break something important.                         #
#      Don't come crying to my DMs. RTFM.                                         #
#                                                                                 #
#   --------------------------------------------------------------------------    #
#   "We build the future on the graves of paid resources."                        #
#   "REJECT MODERN MEDIOCRITY. EMBRACE RDE SUPERIORITY."                          #
#   --------------------------------------------------------------------------    #
###################################################################################
```

**TL;DR:**

- ✅ **Free forever** — use it, edit it, learn from it
- ✅ **Keep the header** — credit where it's due
- ❌ **Don't sell it** — commercial use = instant DMCA + public shaming on Nostr
- ❌ **Don't be a skid** — copy-paste without reading will break things

---

## ⚡ Related Projects

| Resource | Description |
|----------|-------------|
| [rde_aipd](https://github.com/RedDragonElite/rde_aipd) | Next-gen AI police & crime system for ox_core — ultra-realistic, StateBag-synced, Nostr-logged |
| [rde_nostr_log](https://github.com/RedDragonElite/rde_nostr_log) | Decentralized FiveM logging via Nostr — replace Discord forever |
| [awesome-ox-rde](https://github.com/RedDragonElite/awesome-ox-rde) | Curated list of the best ox_core resources |

---

## 🌐 Community & Support

| | |
|---|---|
| 🌍 **Website** | [rd-elite.com](https://rd-elite.com) |
| 🔭 **Nostr Terminal** | [rd-elite.com/Files/NOSTR/Terminal](https://rd-elite.com/Files/NOSTR/Terminal/) |
| 🐙 **GitHub** | [github.com/RedDragonElite](https://github.com/RedDragonElite) |
| 🟣 **Nostr** | `npub1wr4e24zn6zzjqx8kvnelfvktf0pu6l2gx4gvw06zead2eqyn23sq9tsd94` |

**Before opening an issue:**

- ✅ Read this README fully
- ✅ Check the [Troubleshooting](#-troubleshooting) section
- ✅ Run `/rde_admin_check` in F8 and include the output
- ✅ Set `Config.Debug = true` and include both server console and F8 logs
- ❌ Don't open issues without logs — we can't help without them

---

**Made with 🐉 and pure rage at paid Tebex admin panels by [Red Dragon Elite](https://rd-elite.com)**

*The future is ours. We are already inside.*

**REJECT MODERN MEDIOCRITY. EMBRACE RDE SUPERIORITY.**

**RDE FOREVER. SYSTEM FAILURE. ⚡777⚡**

[![Website](https://img.shields.io/badge/Website-Visit-red?style=for-the-badge&logo=google-chrome)](https://rd-elite.com)
[![Nostr](https://img.shields.io/badge/Nostr-Follow-purple?style=for-the-badge&logo=rss)](https://primal.net/p/npub1wr4e24zn6zzjqx8kvnelfvktf0pu6l2gx4gvw06zead2eqyn23sq9tsd94)
[![Terminal](https://img.shields.io/badge/Terminal-Live-green?style=for-the-badge&logo=gnome-terminal)](https://rd-elite.com/Files/NOSTR/)