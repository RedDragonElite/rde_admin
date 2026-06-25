/* ═══════════════════════════════════════════════════════════════
   RDE ADMIN — app.js
   Desktop window manager · all panel logic · NUI bridge
   Red Dragon Elite | rd-elite.com
   ═══════════════════════════════════════════════════════════════ */

'use strict';

// ─── NUI BRIDGE ───────────────────────────────────────────────
// On modern FiveM (cerulean fx_version+, b3000+), the NUI iframe is loaded
// from `nui://cfx-nui-<resname>/...`, so window.location.hostname returns
// "cfx-nui-rde_admin" — WITH the prefix. RegisterNUICallback registers at
// `https://<resname>/<callback>` — WITHOUT the prefix. Using the raw
// hostname therefore 404s every fetch and the JS side surfaces "Access
// denied" because nuiPost falls back to {}.
// Two acceptable fixes:
//   (a) call GetParentResourceName() — the FiveM-injected helper that
//       returns the bare resource name. Not present in browser dev mode.
//   (b) strip the cfx-nui- prefix from hostname ourselves.
// We do BOTH, with (a) preferred and (b) as a fallback.
const resourceName = (typeof GetParentResourceName === 'function')
  ? GetParentResourceName()
  : window.location.hostname.replace(/^cfx-nui-/, '');

async function nuiPost(action, data = {}) {
  try {
    const r = await fetch(`https://${resourceName}/${action}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    // Defensive parse: FiveM may return an empty body if the Lua callback
    // invokes cb() with a string, with nil, or throws — `r.json()` would
    // then explode with "Unexpected end of JSON input". Read as text first
    // and parse manually so we never crash on empty/garbage responses.
    const raw = await r.text();
    if (!raw || raw.trim() === '') return {};
    let json;
    try { json = JSON.parse(raw); }
    catch (parseErr) {
      console.warn('[RDE_ADMIN] nuiPost non-JSON body:', action, raw.slice(0, 100));
      return {};
    }
    // The Lua bridge wraps `nil` results as { __null: true } so the fetch
    // always resolves. Treat that as null on the JS side.
    if (json && json.__null) return null;
    if (json && json.__error) {
      console.error('[RDE_ADMIN] bridge error:', action, json.__error);
      return null;
    }
    return json;
  } catch (e) {
    console.error('[RDE_ADMIN] nuiPost failed:', action, e);
    return null;
  }
}

// Coerce backend results into a true Array. Lua sends an empty table as a
// JSON object `{}`, which has no .forEach — so we defensively wrap anything
// that should be array-shaped through this helper.
function asArray(maybe) {
  if (Array.isArray(maybe)) return maybe;
  if (maybe == null) return [];
  if (typeof maybe === 'object') {
    // Numeric-keyed object? Convert to array.
    const keys = Object.keys(maybe);
    if (keys.length === 0) return [];
    if (keys.every(k => /^\d+$/.test(k))) return Object.values(maybe);
  }
  return [];
}

// ─── STATE ────────────────────────────────────────────────────
let players = [];
let selectedPlayer = null;
let currentPage = 'stats';

// DB state
let dbCurrentTable = null;
let dbColumns = [];
let dbOffset = 0;
let dbLimit = 50;
let dbTotal = 0;
let dbFilter = { column: '', value: '' };
let dbEditData = null;

// Console history
let cmdHistory = [];
let cmdHistoryIdx = -1;

// ─── DESKTOP INIT ─────────────────────────────────────────────
window.addEventListener('message', (e) => {
  const { action, line } = e.data || {};
  if (action === 'open') {
    document.getElementById('desktop').classList.add('visible');
    setStatus('connecting', 'Connecting...');
    loadStats();
    loadPlayers();
  } else if (action === 'close') {
    document.getElementById('desktop').classList.remove('visible');
  } else if (action === 'consoleLine' && line) {
    appendConsoleLine(line);
  }
});

// ─── ESC HANDLER (always closes the panel as a failsafe) ──────
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    e.preventDefault();
    // If a modal is open, close it; otherwise close the whole panel
    const openModals = document.querySelectorAll('.modal-overlay.visible');
    if (openModals.length > 0) {
      openModals.forEach(m => m.classList.remove('visible'));
    } else {
      closePanelFromUI();
    }
  }
});

// Prevent right-click context menu
document.addEventListener('contextmenu', e => e.preventDefault());

// ─── STATUS PILL ──────────────────────────────────────────────
function setStatus(state, text) {
  const pill = document.getElementById('status-pill');
  if (!pill) return;
  pill.dataset.state = state;        // 'ok' | 'connecting' | 'error'
  pill.textContent = text;
}

// ─── CLOCK ────────────────────────────────────────────────────
function updateClock() {
  const now = new Date();
  document.getElementById('taskbar-clock').textContent =
    now.toLocaleTimeString('en-GB');
}
setInterval(updateClock, 1000);
updateClock();

// ─── PAGE SWITCH ──────────────────────────────────────────────
function switchPage(name) {
  document.querySelectorAll('.panel-page').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
  document.getElementById('page-' + name)?.classList.add('active');
  document.getElementById('nav-' + name)?.classList.add('active');
  currentPage = name;

  if (name === 'players') loadPlayers();
  else if (name === 'database') loadTables();
  else if (name === 'stats') loadStats();
  else if (name === 'bans') loadBans();
  else if (name === 'console') loadConsoleBuffer();
}

// ─── WINDOW MANAGER ───────────────────────────────────────────
let zCounter = 100;

function focusWindow(win) {
  document.querySelectorAll('.window').forEach(w => w.classList.remove('focused'));
  win.classList.add('focused');
  win.style.zIndex = ++zCounter;
  const id = win.id;
  document.querySelectorAll('.taskbar-btn').forEach(b => b.classList.remove('active'));
  document.querySelector(`[onclick="toggleWin('${id}')"]`)?.classList.add('active');
}

function toggleWin(id) {
  const win = document.getElementById(id);
  if (!win) return;
  if (win.classList.contains('minimized')) {
    win.classList.remove('minimized');
    focusWindow(win);
  } else if (win.classList.contains('focused')) {
    win.classList.add('minimized');
    document.querySelector(`[onclick="toggleWin('${id}')"]`)?.classList.remove('active');
  } else {
    focusWindow(win);
  }
}

function minimizeWin(id) {
  document.getElementById(id)?.classList.add('minimized');
  document.querySelector(`[onclick="toggleWin('${id}')"]`)?.classList.remove('active');
}

function maximizeWin(id) {
  const win = document.getElementById(id);
  if (!win) return;
  if (win._maximized) {
    Object.assign(win.style, win._prevStyle);
    win._maximized = false;
  } else {
    win._prevStyle = { left: win.style.left, top: win.style.top, width: win.style.width, height: win.style.height };
    Object.assign(win.style, { left: '0', top: '0', width: '100%', height: 'calc(100% - 48px)', borderRadius: '0' });
    win._maximized = true;
  }
}

// Drag
document.querySelectorAll('.window-titlebar').forEach(bar => {
  let dragging = false, ox = 0, oy = 0;
  const win = bar.closest('.window');

  bar.addEventListener('mousedown', e => {
    if (e.target.classList.contains('win-btn')) return;
    if (win._maximized) return;
    dragging = true;
    ox = e.clientX - win.offsetLeft;
    oy = e.clientY - win.offsetTop;
    focusWindow(win);
    e.preventDefault();
  });

  document.addEventListener('mousemove', e => {
    if (!dragging) return;
    let nx = e.clientX - ox;
    let ny = e.clientY - oy;
    nx = Math.max(0, Math.min(nx, window.innerWidth - win.offsetWidth));
    ny = Math.max(0, Math.min(ny, window.innerHeight - 48 - win.offsetHeight));
    win.style.left = nx + 'px';
    win.style.top  = ny + 'px';
  });

  document.addEventListener('mouseup', () => { dragging = false; });
});

// Resize
document.querySelectorAll('.window-resize').forEach(handle => {
  let resizing = false, sx = 0, sy = 0, sw = 0, sh = 0;
  const win = handle.closest('.window');

  handle.addEventListener('mousedown', e => {
    resizing = true;
    sx = e.clientX; sy = e.clientY;
    sw = win.offsetWidth; sh = win.offsetHeight;
    focusWindow(win);
    e.preventDefault();
  });
  document.addEventListener('mousemove', e => {
    if (!resizing) return;
    win.style.width  = Math.max(400, sw + e.clientX - sx) + 'px';
    win.style.height = Math.max(300, sh + e.clientY - sy) + 'px';
  });
  document.addEventListener('mouseup', () => { resizing = false; });
});

document.querySelectorAll('.window').forEach(win => {
  win.addEventListener('mousedown', () => focusWindow(win));
});
focusWindow(document.getElementById('win-main'));

// ─── CLOSE ────────────────────────────────────────────────────
// Hide the UI immediately on the JS side, THEN tell Lua to release NUI focus.
// We must not wait for the Lua response — if the bridge fails, the panel
// would otherwise stay open forever. Fire-and-forget is the safe pattern.
function closePanelFromUI() {
  document.getElementById('desktop')?.classList.remove('visible');
  document.querySelectorAll('.modal-overlay.visible')
    .forEach(m => m.classList.remove('visible'));
  // Fire close multiple times — first call releases focus, subsequent calls
  // are insurance against the cursor staying visible due to NUI focus races.
  nuiPost('close').catch(() => {});
  setTimeout(() => nuiPost('close').catch(() => {}), 100);
  setTimeout(() => nuiPost('close').catch(() => {}), 350);
}

// ─── MODAL ────────────────────────────────────────────────────
function openModal(id) { document.getElementById(id)?.classList.add('visible'); }
function closeModal(id) { document.getElementById(id)?.classList.remove('visible'); }

document.querySelectorAll('.modal-overlay').forEach(m => {
  m.addEventListener('mousedown', e => {
    if (e.target === m) closeModal(m.id);
  });
});

// ─── STATS ────────────────────────────────────────────────────
async function loadStats() {
  const stats = await nuiPost('getStats');

  if (!stats || !stats.ok) {
    setStatus('error', stats === null ? 'Backend timeout' : 'Access denied');
    document.getElementById('stat-players').textContent = '—';
    document.getElementById('stat-resources').textContent = '—';
    document.getElementById('stat-uptime').textContent = '—';
    document.getElementById('server-name-label').textContent =
      stats === null ? 'Backend not responding' : 'No admin permission';
    return;
  }

  setStatus('ok', 'Connected');
  document.getElementById('stat-players').textContent = stats.players ?? '—';
  document.getElementById('stat-maxplayers').textContent = `/ ${stats.maxPlayers ?? '—'} max`;
  document.getElementById('stat-resources').textContent = stats.resources ?? '—';
  document.getElementById('server-name-label').textContent = stats.serverName ?? '';

  const upMs = stats.uptime ?? 0;
  const upSec = Math.floor(upMs / 1000);
  const h = Math.floor(upSec / 3600);
  const m = Math.floor((upSec % 3600) / 60);
  const s = upSec % 60;
  document.getElementById('stat-uptime').textContent = `${h}h ${m}m ${s}s`;

  if (stats.console) {
    const el = document.getElementById('stats-console');
    el.innerHTML = '';
    asArray(stats.console).slice(-60).forEach(appendStatsConsoleLine);
    el.scrollTop = el.scrollHeight;
  }
}

function appendStatsConsoleLine(line) {
  const el = document.getElementById('stats-console');
  if (!el || !line) return;
  const div = document.createElement('div');
  div.className = 'console-line';
  div.innerHTML = `<span class="console-time">${escHtml(line.time || '')}</span><span class="console-text">${escHtml(line.text || '')}</span>`;
  el.appendChild(div);
}

function openTxAdmin() {
  // Sends an in-game command — txAdmin's webpanel is exposed via /tx,
  // but in-game we just trigger the chat command users already use.
  nuiPost('sendConsoleCommand', { command: 'tx' });
  notify('🛠 Sent /tx — open menu in your browser', 'info');
}

// ─── PLAYERS ──────────────────────────────────────────────────
async function loadPlayers() {
  const data = await nuiPost('getPlayers');
  players = asArray(data);
  renderPlayers(players);
}

function renderPlayers(list) {
  const tbody = document.getElementById('player-tbody');
  tbody.innerHTML = '';
  document.getElementById('player-count-label').textContent = list.length + ' players';

  if (list.length === 0) {
    tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;padding:30px;color:var(--text-muted);font-size:11px">No players online — or you are not yet recognised as admin. Check ACE perms / ox_core groups.</td></tr>';
    return;
  }

  list.forEach(p => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td><span class="badge badge-muted">${p.source}</span></td>
      <td style="font-family:var(--font-ui);font-size:12px;max-width:180px">${escHtml(p.name)}</td>
      <td>${groupBadge(p.group)}</td>
      <td>
        <span class="ping-dot ${pingClass(p.ping)}"></span>
        <span style="font-size:11px;margin-left:4px">${p.ping}ms</span>
      </td>
      <td>${healthBar(p.health)}</td>
      <td>
        <button class="btn btn-ghost btn-sm" onclick="selectPlayer(${p.source})">▶ Select</button>
      </td>`;
    tbody.appendChild(tr);
  });
}

function filterPlayers() {
  const q = document.getElementById('player-search').value.toLowerCase();
  renderPlayers(q ? players.filter(p =>
    p.name.toLowerCase().includes(q) ||
    String(p.source).includes(q) ||
    (p.license || '').includes(q)
  ) : players);
}

function selectPlayer(src) {
  selectedPlayer = players.find(p => p.source === src);
  if (!selectedPlayer) return;

  document.querySelectorAll('#player-tbody tr').forEach(tr => tr.classList.remove('selected'));

  const detail = document.getElementById('player-detail');
  detail.style.display = 'block';
  document.getElementById('detail-name').textContent = selectedPlayer.name;
  document.getElementById('detail-license').textContent = (selectedPlayer.license || '').slice(0, 28) + '…';
  const gb = document.getElementById('detail-group');
  gb.className = 'badge';
  gb.textContent = selectedPlayer.group || 'user';
  const isAdminPlayer = ['admin', 'superadmin', 'owner', 'headadmin'].includes(selectedPlayer.group);
  gb.classList.add(isAdminPlayer ? 'badge-red' : 'badge-muted');
}

async function playerAction(action, state) {
  if (!selectedPlayer) return;

  if (action === 'teleportToPlayer') {
    await nuiPost('teleportToPlayer', { target: selectedPlayer.source });
    return;
  }

  const result = await nuiPost('playerAction', {
    action, target: selectedPlayer.source, state,
  });
  if (result?.ok) notify('✅ Done', 'success');
  else notify('❌ ' + (result?.msg || 'Action failed'), 'error');
}

// ─── KICK / BAN / WARN MODALS ─────────────────────────────────
function openKickModal() {
  if (!selectedPlayer) return;
  document.getElementById('kick-name').textContent = selectedPlayer.name;
  document.getElementById('kick-reason').value = '';
  openModal('modal-kick');
}
async function confirmKick() {
  const reason = document.getElementById('kick-reason').value || 'No reason given';
  const r = await nuiPost('playerAction', { action: 'kick', target: selectedPlayer.source, reason });
  closeModal('modal-kick');
  if (r?.ok) { notify('🦶 Player kicked', 'success'); loadPlayers(); }
  else notify('❌ ' + (r?.msg || 'Kick failed'), 'error');
}

function openBanModal() {
  if (!selectedPlayer) return;
  document.getElementById('ban-name').textContent = selectedPlayer.name;
  document.getElementById('ban-reason').value = '';
  openModal('modal-ban');
}
async function confirmBan() {
  const reason = document.getElementById('ban-reason').value || 'No reason given';
  const minutes = parseInt(document.getElementById('ban-duration').value);
  const r = await nuiPost('playerAction', { action: 'ban', target: selectedPlayer.source, reason, minutes });
  closeModal('modal-ban');
  if (r?.ok) { notify('🚫 Player banned', 'success'); loadPlayers(); }
  else notify('❌ ' + (r?.msg || 'Ban failed'), 'error');
}

function openWarnModal() {
  if (!selectedPlayer) return;
  document.getElementById('warn-name').textContent = selectedPlayer.name;
  document.getElementById('warn-reason').value = '';
  openModal('modal-warn');
}
async function confirmWarn() {
  const reason = document.getElementById('warn-reason').value || 'No reason given';
  const r = await nuiPost('playerAction', { action: 'warn', target: selectedPlayer.source, reason });
  closeModal('modal-warn');
  if (r?.ok) notify('⚠️ Player warned', 'success');
  else notify('❌ ' + (r?.msg || 'Warn failed'), 'error');
}

// ─── CONSOLE ──────────────────────────────────────────────────
function appendConsoleLine(line) {
  ['console-output', 'stats-console'].forEach(id => {
    const el = document.getElementById(id);
    if (!el || !line) return;
    const div = document.createElement('div');
    div.className = 'console-line';
    const text = line.text || '';
    const cls = text.startsWith('[CMD]') ? 'cmd' :
                text.startsWith('[ADMIN]') ? 'admin' :
                text.startsWith('[ERR]') || text.includes('error') || text.includes('ERROR') ? 'error' :
                text.startsWith('[BOOT]') ? 'admin' : '';
    div.innerHTML = `<span class="console-time">${escHtml(line.time || '')}</span><span class="console-text ${cls}">${escHtml(text)}</span>`;
    el.appendChild(div);
    while (el.children.length > 300) el.removeChild(el.firstChild);
    el.scrollTop = el.scrollHeight;
  });
}

function clearConsole() {
  document.getElementById('console-output').innerHTML = '';
}

// v1.1.1: When the user opens the dedicated Console page, hydrate it with
// the existing server-side buffer so they don't stare at an empty pane until
// the next live event. We piggy-back on getStats which already returns the
// buffer; the dashboard's stats-console is unaffected because we only render
// into console-output here.
async function loadConsoleBuffer() {
  const stats = await nuiPost('getStats');
  const el = document.getElementById('console-output');
  if (!el || !stats || !stats.ok) return;
  el.innerHTML = '';
  asArray(stats.console).slice(-300).forEach(line => {
    const div = document.createElement('div');
    div.className = 'console-line';
    const text = line.text || '';
    const cls = text.startsWith('[CMD]')   ? 'cmd'   :
                text.startsWith('[ADMIN]') ? 'admin' :
                text.startsWith('[ERR]') || text.includes('error') || text.includes('ERROR') ? 'error' :
                text.startsWith('[BOOT]')  ? 'admin' : '';
    div.innerHTML = `<span class="console-time">${escHtml(line.time || '')}</span><span class="console-text ${cls}">${escHtml(text)}</span>`;
    el.appendChild(div);
  });
  el.scrollTop = el.scrollHeight;
}

function handleConsoleKey(e) {
  if (e.key === 'Enter') { sendConsoleCmd(); return; }
  if (e.key === 'ArrowUp') {
    cmdHistoryIdx = Math.min(cmdHistoryIdx + 1, cmdHistory.length - 1);
    e.target.value = cmdHistory[cmdHistory.length - 1 - cmdHistoryIdx] || '';
  }
  if (e.key === 'ArrowDown') {
    cmdHistoryIdx = Math.max(cmdHistoryIdx - 1, -1);
    e.target.value = cmdHistoryIdx < 0 ? '' : cmdHistory[cmdHistory.length - 1 - cmdHistoryIdx] || '';
  }
}

async function sendConsoleCmd() {
  const input = document.getElementById('console-cmd');
  const cmd = input.value.trim();
  if (!cmd) return;
  cmdHistory.push(cmd);
  cmdHistoryIdx = -1;
  input.value = '';
  appendConsoleLine({ time: new Date().toLocaleTimeString('en-GB'), text: '[CMD] > ' + cmd });
  const r = await nuiPost('sendConsoleCommand', { command: cmd });
  if (!r?.ok) notify('❌ ' + (r?.msg || 'Command failed'), 'error');
}

// ─── DATABASE ─────────────────────────────────────────────────
async function loadTables() {
  const list = document.getElementById('db-table-list');
  list.innerHTML = '<div class="empty-state" style="padding:20px 0"><div class="spinner"></div></div>';

  const tables = asArray(await nuiPost('dbListTables'));
  list.innerHTML = '';

  if (tables.length === 0) {
    list.innerHTML = '<div class="empty-state" style="padding:20px 0"><div class="e-text" style="font-size:11px">No tables (or no DB access)</div></div>';
    return;
  }

  tables.forEach(t => {
    const item = document.createElement('div');
    item.className = 'db-table-item';
    item.dataset.table = t.name;
    item.innerHTML = `<span>${escHtml(t.name)}</span><span class="db-table-rows">${t.rows}</span>`;
    item.addEventListener('click', () => {
      document.querySelectorAll('.db-table-item').forEach(i => i.classList.remove('active'));
      item.classList.add('active');
      selectDbTable(t.name, t.columns);
    });
    list.appendChild(item);
  });
}

async function selectDbTable(tname) {
  dbCurrentTable = tname;
  dbOffset = 0;
  dbFilter = { column: '', value: '' };
  document.getElementById('db-filter-val').value = '';
  document.getElementById('db-filter-col').innerHTML = '<option value="">All columns</option>';
  document.getElementById('db-query-input').value = `SELECT * FROM \`${tname}\` LIMIT 50`;
  document.getElementById('db-insert-btn').style.display = '';
  await browseTable();
}

async function browseTable() {
  if (!dbCurrentTable) return;

  document.getElementById('db-tbody').innerHTML =
    '<tr><td colspan="99" style="text-align:center;padding:20px"><div class="spinner" style="margin:auto"></div></td></tr>';

  const result = await nuiPost('dbBrowseTable', {
    table: dbCurrentTable,
    offset: dbOffset,
    limit: dbLimit,
    filter: dbFilter.column ? dbFilter : null,
  });

  if (!result || result.error) {
    document.getElementById('db-tbody').innerHTML =
      `<tr><td colspan="99" style="text-align:center;color:var(--text-red);padding:20px">${escHtml(result?.error || 'Error')}</td></tr>`;
    return;
  }

  dbColumns = asArray(result.columns);
  dbTotal   = result.total  || 0;
  const rows = asArray(result.rows);

  // build column filter select
  const colSel = document.getElementById('db-filter-col');
  colSel.innerHTML = '<option value="">All columns</option>';
  dbColumns.forEach(c => {
    const opt = document.createElement('option');
    opt.value = c.name; opt.textContent = c.name;
    colSel.appendChild(opt);
  });

  // header
  const thead = document.getElementById('db-thead-row');
  thead.innerHTML = '';
  const pkCol = (dbColumns.find(c => c.key === 'PRI') || dbColumns[0])?.name;

  dbColumns.forEach(c => {
    const th = document.createElement('th');
    th.textContent = c.name + (c.key === 'PRI' ? ' 🔑' : '');
    thead.appendChild(th);
  });
  const thAct = document.createElement('th');
  thAct.textContent = '⚙';
  thead.appendChild(thAct);

  // rows
  const tbody = document.getElementById('db-tbody');
  tbody.innerHTML = '';
  if (rows.length === 0) {
    tbody.innerHTML = '<tr><td colspan="99" style="text-align:center;padding:20px;color:var(--text-muted)">No rows</td></tr>';
  } else {
    rows.forEach(row => {
      const tr = document.createElement('tr');
      dbColumns.forEach(c => {
        const td = document.createElement('td');
        const val = row[c.name];
        td.textContent = val === null ? 'NULL' : String(val);
        td.title = td.textContent;
        td.addEventListener('dblclick', () => openEditModal(c.name, val, pkCol, row[pkCol]));
        tr.appendChild(td);
      });
      const tdAct = document.createElement('td');
      tdAct.innerHTML = `<button class="btn btn-danger btn-sm btn-icon" onclick='deleteDbRow(${JSON.stringify(pkCol)}, ${JSON.stringify(row[pkCol])})'>✕</button>`;
      tr.appendChild(tdAct);
      tbody.appendChild(tr);
    });
  }

  document.getElementById('db-page-info').textContent =
    `${dbOffset + 1}–${Math.min(dbOffset + dbLimit, dbTotal)} of ${dbTotal} rows`;
  document.getElementById('db-prev').disabled = dbOffset === 0;
  document.getElementById('db-next').disabled = dbOffset + dbLimit >= dbTotal;
  document.getElementById('db-row-count').textContent = `${dbTotal} total`;
}

function dbPrevPage() { dbOffset = Math.max(0, dbOffset - dbLimit); browseTable(); }
function dbNextPage() { dbOffset += dbLimit; browseTable(); }

function applyDbFilter() {
  const val = document.getElementById('db-filter-val').value;
  const col = document.getElementById('db-filter-col').value;
  dbFilter = { column: col, value: val };
  dbOffset = 0;
  browseTable();
}

async function runQuery() {
  const query = document.getElementById('db-query-input').value.trim();
  if (!query) return;

  document.getElementById('db-tbody').innerHTML =
    '<tr><td colspan="99" style="text-align:center;padding:20px"><div class="spinner" style="margin:auto"></div></td></tr>';

  const result = await nuiPost('dbRunQuery', { query });

  if (!result?.ok) {
    document.getElementById('db-tbody').innerHTML =
      `<tr><td colspan="99" style="text-align:center;color:var(--text-red);padding:20px">${escHtml(result?.error || 'Error')}</td></tr>`;
    return;
  }

  const rows = asArray(result.rows);
  if (rows.length === 0) {
    document.getElementById('db-tbody').innerHTML =
      `<tr><td colspan="99" style="text-align:center;padding:20px;color:var(--text-muted)">Query OK — ${result.affected || 0} rows affected</td></tr>`;
    return;
  }

  const cols = Object.keys(rows[0]);
  const thead = document.getElementById('db-thead-row');
  thead.innerHTML = '';
  cols.forEach(c => { const th = document.createElement('th'); th.textContent = c; thead.appendChild(th); });

  const tbody = document.getElementById('db-tbody');
  tbody.innerHTML = '';
  rows.forEach(row => {
    const tr = document.createElement('tr');
    cols.forEach(c => {
      const td = document.createElement('td');
      td.textContent = row[c] === null ? 'NULL' : String(row[c]);
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
  });
  document.getElementById('db-page-info').textContent = `${rows.length} rows returned`;
}

function deleteDbRow(pkCol, pkVal) {
  if (!dbCurrentTable) return;
  document.getElementById('confirm-delete-msg').textContent = `Delete row where ${pkCol} = ${pkVal}?`;
  const btn = document.getElementById('confirm-delete-btn');
  // Clone to remove old listeners
  const newBtn = btn.cloneNode(true);
  btn.parentNode.replaceChild(newBtn, btn);
  newBtn.addEventListener('click', async () => {
    closeModal('modal-confirm-delete');
    const r = await nuiPost('dbDeleteRow', { table: dbCurrentTable, pk: pkCol, value: pkVal });
    if (r?.ok) { notify('✅ Row deleted', 'success'); browseTable(); }
    else notify('❌ Delete failed', 'error');
  });
  openModal('modal-confirm-delete');
}

function openEditModal(column, currentValue, pk, pkVal) {
  dbEditData = { column, pk, pkVal, table: dbCurrentTable };
  document.getElementById('edit-col-label').textContent = column;
  document.getElementById('edit-value').value = currentValue === null ? '' : String(currentValue);
  openModal('modal-edit');
}
async function confirmEdit() {
  if (!dbEditData) return;
  const newValue = document.getElementById('edit-value').value;
  const r = await nuiPost('dbUpdateCell', {
    table: dbEditData.table,
    column: dbEditData.column,
    pk: dbEditData.pk,
    pkValue: dbEditData.pkVal,
    newValue,
  });
  closeModal('modal-edit');
  if (r?.ok) { notify('✅ Cell updated', 'success'); browseTable(); }
  else notify('❌ Update failed', 'error');
}

function showInsertModal() {
  if (!dbCurrentTable || !dbColumns.length) return;
  document.getElementById('insert-table-name').textContent = dbCurrentTable;
  const fields = document.getElementById('insert-fields');
  fields.innerHTML = '';
  dbColumns.forEach(c => {
    if (c.key === 'PRI') return;
    const div = document.createElement('div');
    div.className = 'form-group';
    div.innerHTML = `<label class="form-label">${escHtml(c.name)} <span style="color:var(--text-muted)">(${c.type})</span></label>
      <input class="form-input" data-col="${escHtml(c.name)}" placeholder="${escHtml(c.name)}">`;
    fields.appendChild(div);
  });
  openModal('modal-insert');
}
async function confirmInsert() {
  const row = {};
  document.querySelectorAll('#insert-fields input[data-col]').forEach(inp => {
    row[inp.dataset.col] = inp.value;
  });
  const r = await nuiPost('dbInsertRow', { table: dbCurrentTable, row });
  closeModal('modal-insert');
  if (r?.ok) { notify('✅ Row inserted', 'success'); browseTable(); }
  else notify('❌ Insert failed', 'error');
}

// ─── BANS ─────────────────────────────────────────────────────
async function loadBans() {
  const tbody = document.getElementById('ban-tbody');
  tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;padding:20px"><div class="spinner" style="margin:auto"></div></td></tr>';

  // Use the dedicated ox_core ban endpoint, not a raw query
  const bans = asArray(await nuiPost('getBans'));
  tbody.innerHTML = '';

  if (bans.length === 0) {
    tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;padding:20px;color:var(--text-muted)">No active bans</td></tr>';
    return;
  }

  bans.forEach(b => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${escHtml(b.name || ('userId:' + b.userId))}</td>
      <td style="max-width:200px">${escHtml(b.reason || '')}</td>
      <td>${escHtml(b.banned_by || b.bannedBy || '')}</td>
      <td>${b.expires_at ? escHtml(b.expires_at) : '<span class="badge badge-red">Permanent</span>'}</td>
      <td><button class="btn btn-ghost btn-sm" onclick="unbanByUserId(${b.userId})">✕ Unban</button></td>`;
    tbody.appendChild(tr);
  });
}

async function unbanByUserId(userId) {
  const r = await nuiPost('unbanUser', { userId });
  if (r?.ok) { notify('✅ Ban removed', 'success'); loadBans(); }
  else notify('❌ ' + (r?.msg || 'Unban failed'), 'error');
}

// ─── UTILITIES ────────────────────────────────────────────────
function escHtml(str) {
  return String(str ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#039;');
}

function pingClass(ping) {
  if (ping < 80)  return 'ping-good';
  if (ping < 150) return 'ping-medium';
  return 'ping-bad';
}

function groupBadge(group) {
  const adminGroups = ['admin', 'superadmin', 'owner', 'headadmin'];
  const modGroups   = ['moderator'];
  if (adminGroups.includes(group)) return `<span class="badge badge-red">${escHtml(group)}</span>`;
  if (modGroups.includes(group))   return `<span class="badge badge-gold">${escHtml(group)}</span>`;
  return `<span class="badge badge-muted">${escHtml(group || 'user')}</span>`;
}

function healthBar(hp) {
  // GTA peds: 100 = dead, 200 = full. Clamp + map to 0-100%.
  const pct = Math.max(0, Math.min(100, Math.round(((hp - 100) / 100) * 100)));
  const col = pct > 60 ? 'var(--green)' : pct > 30 ? 'var(--gold)' : 'var(--text-red)';
  return `<div style="display:flex;align-items:center;gap:5px">
    <div style="width:48px;height:5px;background:rgba(255,255,255,0.1);border-radius:3px;overflow:hidden">
      <div style="width:${pct}%;height:100%;background:${col};transition:.3s"></div>
    </div>
    <span style="font-size:10px;color:var(--text-muted)">${pct}%</span>
  </div>`;
}

function notify(msg, type = 'info') {
  const el = document.createElement('div');
  const colors = { success: 'var(--green)', error: 'var(--text-red)', info: 'var(--blue)', warning: 'var(--gold)' };
  el.style.cssText = `
    position:fixed;bottom:60px;right:16px;z-index:99999;
    background:var(--bg-panel);border:1px solid ${colors[type] || 'var(--border)'};
    border-radius:var(--radius);padding:10px 16px;
    font-size:12px;color:var(--text-primary);
    box-shadow:0 8px 24px rgba(0,0,0,0.5);
    animation:fadeIn .2s ease;
    max-width:280px;
  `;
  el.textContent = msg;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 3000);
}

const style = document.createElement('style');
style.textContent = `@keyframes fadeIn { from { opacity:0; transform:translateY(8px); } to { opacity:1; transform:none; } }`;
document.head.appendChild(style);
