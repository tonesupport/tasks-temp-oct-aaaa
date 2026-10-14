/* Board skin — single shell; agenda = toggleable day-plane preset (caty).
   Plane sources (in order):
     0) window.__SIGHT_PLANE__ (decrypted gated payload from unlock.js)
     1) ?plane=<url> query override
     2) same-origin /board/board-model.toml
     3) relative ./board-model.toml
     4) inline fallback sample cards
   Gated Netlify path: /sight/ — wait for "sight-unlocked" when data-sight-locked.
   Notes peek: in-memory __SIGHT_PLANE__.notes[id] first, else /board/notes/<id>.toml
   ?agenda=1 boots with agenda preset on. ?test=1 forces sight-test UI fixtures.
   Live field: decrypted __SIGHT_PLANE__.field (packed field.toml string) is the
   default parcel source when non-empty. Fixtures only if that string is absent/empty,
   or when ?parcels=fixtures. Tasks and field are peers in ONE column
   (one plane at a time, same width). Default plane is Tasks. A hamburger
   to the right of search opens monolith pills (tasks / field). It stays
   visible at ≤520. Field cards scroll in the same column.
   ?view=field opens Field.
   ?parcel= / ?field= opens Field on that parcel's plot and focuses it
   (no slide). In-session ← → stack; not browser history.
   Parcel id scheme (live): bare suffix of the table name.
     [parcel.t0a1] -> id t0a1.  ?parcel=t0a1   #parcel-t0a1  (also #field-t0a1).
   Focus aliases: parcel.t0a1, field/parcel.t0a1, field/t0a1.
   Projection (field-sight 0.3): parcel title <- claim, body <- content. plot/area/ord are meta.
   Plot cards: heading <- plot title (blank if absent), slug stays a pill, description under the title.
   Field first screen lists plots. A card opens that plot's parcels.
   Hash: #parcel-<id> / #field-<id> (same); #card-<id> / #<id> for tasks.
   Search: no prefix filters the visible plane. T: tasks, F: parcels. Leading / still
   overrides task filters.
   Specimens: work/board/local-config.example.toml
*/

(function () {
  'use strict';

  var AXES = ['GLOBAL', 'STATUS', 'SCHED', 'DOMAIN', 'PROJECT', 'TIMERS']; /* FIELD parked — fpln sibling */
  var FILTER_AXES = { STATUS: 'status', SCHED: 'sched', DOMAIN: 'domain', PROJECT: 'project' };
  var SPECIAL_AXES = { TIMERS: 1 };
  var GLOBAL_VALUES = ['tosu', 'done', 'blocks', 'remove', 'test'];
  /* One pill row. agenda is binary (not an axis). GLOBAL opens cycle chips. */
  var AXIS_ROWS = [
    [
      { id: 'AGENDA', label: 'agenda', short: 'AGNDA', word: 1, binary: 1 },
      { id: 'GLOBAL', label: 'GLOBAL', short: 'GLOB' },
      { id: 'STATUS', label: 'STATUS', short: 'STAT' },
      { id: 'SCHED', label: 'SCHED', short: 'SCHED' },
      { id: 'DOMAIN', label: 'DOMAIN', short: 'DOM' },
      { id: 'PROJECT', label: 'PROJECT', short: 'PRJ' },
      { id: 'TIMERS', label: 'TIMERS', short: 'TIMERS' }
    ]
  ];
  var LANE_AXES = { AGENDA: 1, TOSU: 1, DONE: 1, BLOCKS: 1, TEST: 1 };
  var STATUS_ORDER = ['urgent', 'now', 'today', 'progress', 'later', 'deferred', 'sched', 'done', 'remove'];
  var STATUS_RANK = {};
  STATUS_ORDER.forEach(function (s, i) { STATUS_RANK[s] = i; });
  var LONG_PRESS_MS = 500;
  var MONTHS = {
    jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5,
    jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11
  };

  /* Same-origin default — serve should map this to
     /workspace/system/work/board/board-model.toml
     Never bake a tunnel hostname here. */
  var DEFAULT_PLANE_PATHS = [
    '/board/board-model.toml',
    './board-model.toml',
    '../system/work/board/board-model.toml'
  ];

  /* Tiny offline fallback — real cards from board-model (260929 cut). */
  var FALLBACK_CARDS = [
    {
      id: 'wbpl',
      title: 'Pick up web-first tasks.toml visualization design',
      status: 'today',
      domain: 'almanac',
      project: 'board-ui',
      notes_excerpt: 'Pickup: design web-first visualization of tasks.toml (phone-first skin over hosted TOML plane). Ideally live update, filtering, and schedule/field views.',
      due_today: true,
      timed: false
    },
    {
      id: '7nv3',
      title: 'Enforce system/scripts → system/deps only (drop PATH hunts; comment deps paths)',
      status: 'today',
      domain: 'system',
      project: 'deps-discipline',
      notes_excerpt: 'Enforce + first vendor pass 260929. Call-site redirects (deps-only; no PATH).',
      due_today: true,
      timed: false
    },
    {
      id: 'clfd',
      title: 'Claude export → coherent field grains (cluster, pilot, inject waves)',
      status: 'today',
      domain: 'fieldguide',
      project: 'claude-field-ingest',
      notes_excerpt: 'No prior task covered turning the Claude.ai export into grain-shaped live field entries.',
      due_today: true,
      timed: false
    },
    {
      id: 'root',
      title: 'Root',
      status: 'later',
      notes_excerpt: 'Workroot bucket for the field-guide / topos / tasks-substrate initiative.',
      due_today: false,
      timed: false
    },
    {
      id: 'p403',
      title: 'Carry rho-into-rime wiring and the rho/rime/hail revend to completion',
      status: 'later',
      domain: 'fieldguide',
      project: 'phase-4-resplice',
      notes_excerpt: 'Phase-4 rho.tcl rewrite and hail wiring — remaining open pieces.',
      blockers_summary: 'p402',
      blockers_pending: ['p402'],
      due_today: false,
      timed: false
    }
  ];

  var state = {
    cards: [],
    byId: {},
    meta: {},
    activeAxis: 'STATUS',
    chipBandOpen: false, /* value submenu — open on axis tap, close after pick */
    /* Ordered selection chain: includes-block then excludes-block; source of truth */
    selection: [], /* [{field, value, mode:'include'|'exclude'}] */
    include: { status: [], sched: [], domain: [], project: [] },
    exclude: { status: [], sched: [], domain: [], project: [] },
    lane: 'all', /* all | tosu | agent */
    agendaPreset: false,
    showBlocked: true, /* inventory default: show blocked; agenda preset hides */
    showDone: false, /* Done pill default off — hide status=done */
    removeMode: 'exclude', /* status=REMOVE: none = show; include = only REMOVE; exclude = hide (default: hidden) */
    doneMode: 'exclude', /* global chip: none | include (only) | exclude (hide) */
    blocksMode: 'none', /* none = show all; include = only blocked; exclude = hide */
    testMode: 'none', /* none | include (fixtures) | exclude (hide sight-test) */
    sort: 'inventory', /* inventory | agenda */
    savedBeforeAgenda: null, /* snapshot to restore on toggle-off */
    savedBeforeTest: null, /* snapshot filter chain around sight-test toggle */
    showAll: false, /* all-filters-off toggle */
    savedBeforeAll: null, /* snapshot filter chain around show-all toggle */
    planeSource: 'fallback',
    planeLabel: 'inline fallback',
    planeCards: [], /* last plane payload (no fixtures); toggle test without refetch */
    sightTest: false, /* UI fixtures / kitchen-sink seed — default OFF */
    parcelTest: false, /* legacy flag; plane switch is viewPlane */
    viewPlane: 'tasks', /* full-width tab */
    split: null,
    plotSort: 'new',
    fieldPlot: '', /* open plot key: its unique area slug (or bare plot id); '' = plot index */
    navDepth: 0, /* legacy; app stack below, not browser history */
    navLog: [],
    navPos: 0,
    navReady: false,
    parcels: [], /* active parcel list (live field or fixtures) */
    parcelsById: {},
    liveParcels: [], /* projected from plane.field when present */
    plotsById: {},
    ttsByPlot: {}, /* prebuilt spoken routes, keyed by plot id */
    fieldSource: 'none', /* 'live' | 'fixtures' | 'none' */
    pendingParcelFocusId: null,
    localToday: null,
    pendingFocusId: null,
    searchQuery: '', /* live search; leading / = full-plane override */
    metaHidden: false, /* hide card metadata pills (domain/project/sched/…) */
    metaHiddenUserSet: false /* true after explicit meta toggle this session */
  };

  var MOBILE_BP = 520;
  var FILTER_FIELDS = ['status', 'sched', 'domain', 'project'];
  var FIELD_LABEL = { status: 'STATUS', sched: 'SCHED', domain: 'DOMAIN', project: 'PROJECT' };

  var SIGHT_TEST_TAG = 'sight-test';
  var PARCEL_TEST_TAG = 'parcel-test';

  /* ---------- minimal TOML parser ---------- */
  /* Board-model: top-level scalars, [[cards]], string/bool/number, simple arrays.
     Field substrate: [plot.<id>] / [parcel.<id>] (bracket name is literal, dots
     included) and multiline ''' / """ bodies. Not a full TOML 1.0 parser. No npm. */
  function parseBoardToml(text) {
    var meta = {};
    var cards = [];
    var tables = {};
    var cur = null;
    var lines = String(text).split(/\r?\n/);

    function unquote(s) {
      s = s.trim();
      if ((s.charAt(0) === "'" && s.charAt(s.length - 1) === "'") ||
          (s.charAt(0) === '"' && s.charAt(s.length - 1) === '"')) {
        var inner = s.slice(1, -1);
        if (s.charAt(0) === '"') {
          inner = inner.replace(/\\n/g, '\n').replace(/\\t/g, '\t')
            .replace(/\\"/g, '"').replace(/\\\\/g, '\\');
        }
        return inner;
      }
      return s;
    }

    function parseValue(raw) {
      var v = raw.trim();
      if (v === 'true') return true;
      if (v === 'false') return false;
      if (/^-?\d+(\.\d+)?$/.test(v)) return Number(v);
      if (v.charAt(0) === '[') {
        var inner = v.slice(1, v.lastIndexOf(']')).trim();
        if (!inner) return [];
        var parts = [];
        var re = /'([^']*)'|"([^"]*)"|([^,\s]+)/g;
        var m;
        while ((m = re.exec(inner))) {
          parts.push(m[1] != null ? m[1] : (m[2] != null ? m[2] : m[3]));
        }
        return parts;
      }
      return unquote(v);
    }

    function decodeMl(ml, body) {
      if (ml !== '"""') return body;
      return body.replace(/\\\r?\n/g, '')
        .replace(/\\n/g, '\n').replace(/\\t/g, '\t')
        .replace(/\\"/g, '"').replace(/\\\\/g, '\\');
    }

    /* start = line index of the key; rawAfterEq is the text after '='. */
    function readScalar(start, rawAfterEq) {
      var v = String(rawAfterEq).trim();
      var ml = null;
      if (v.slice(0, 3) === "'''") ml = "'''";
      else if (v.slice(0, 3) === '"""') ml = '"""';
      if (!ml) return { value: parseValue(v), next: start + 1 };
      var rest = v.slice(3);
      var same = rest.indexOf(ml);
      if (same >= 0) return { value: decodeMl(ml, rest.slice(0, same)), next: start + 1 };
      var chunks = [];
      if (rest) chunks.push(rest);
      var j = start + 1;
      for (; j < lines.length; j++) {
        var ln = lines[j];
        var at = ln.indexOf(ml);
        if (at >= 0) {
          var pre = ln.slice(0, at);
          if (pre) chunks.push(pre);
          j++;
          break;
        }
        chunks.push(ln);
      }
      return { value: decodeMl(ml, chunks.join('\n')), next: j };
    }

    var i = 0;
    while (i < lines.length) {
      var line = lines[i];
      var trimmed = line.trim();
      if (!trimmed || trimmed.charAt(0) === '#') { i++; continue; }
      if (trimmed === '[[cards]]') {
        cur = {};
        cards.push(cur);
        i++;
        continue;
      }
      if (trimmed.charAt(0) === '[' && trimmed.charAt(1) === '[') {
        cur = null;
        i++;
        continue;
      }
      if (trimmed.charAt(0) === '[') {
        var rb = trimmed.indexOf(']');
        if (rb > 1) {
          var tname = trimmed.slice(1, rb).trim();
          cur = {};
          tables[tname] = cur;
          i++;
          continue;
        }
      }
      var eq = trimmed.indexOf('=');
      if (eq < 1) { i++; continue; }
      var key = trimmed.slice(0, eq).trim();
      var got = readScalar(i, trimmed.slice(eq + 1));
      if (cur) cur[key] = got.value;
      else meta[key] = got.value;
      i = got.next;
    }

    cards.forEach(normalizeCard);
    return { meta: meta, cards: cards, tables: tables };
  }

  function localTodayParts() {
    var d = new Date();
    return { y: d.getFullYear() % 100, m: d.getMonth(), day: d.getDate() };
  }

  function parseDatetime(str) {
    if (!str) return null;
    var m = String(str).trim().match(/^[A-Za-z]{3}\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{2})$/);
    if (!m) return null;
    var mon = MONTHS[m[1].toLowerCase()];
    if (mon == null) return null;
    return { y: parseInt(m[3], 10), m: mon, day: parseInt(m[2], 10) };
  }

  function parseTime(str) {
    if (!str) return null;
    var m = String(str).trim().match(/^(\d{1,2}):(\d{2})\s*([ap])$/i);
    if (!m) return null;
    var h = parseInt(m[1], 10);
    var min = parseInt(m[2], 10);
    var ap = m[3].toLowerCase();
    if (h < 1 || h > 12 || min > 59) return null;
    if (ap === 'a') { if (h === 12) h = 0; }
    else { if (h !== 12) h += 12; }
    return h * 60 + min;
  }

  function dateCmp(a, b) {
    if (!a && !b) return 0;
    if (!a) return 1;
    if (!b) return -1;
    if (a.y !== b.y) return a.y - b.y;
    if (a.m !== b.m) return a.m - b.m;
    return a.day - b.day;
  }


  /* ---------- UI fixtures / kitchen-sink seed (sight-test) ---------- */
  /* Industry: UI fixtures / kitchen-sink seed data (Figma “all states”); not lorem. */
  function pad2(n) {
    return (n < 10 ? '0' : '') + n;
  }

  function formatBoardDatetime(d) {
    var days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    var yy = d.getFullYear() % 100;
    return days[d.getDay()] + ' ' + months[d.getMonth()] + ' ' + d.getDate() + ' ' + pad2(yy);
  }

  function formatBoardTime(d) {
    var h = d.getHours();
    var m = d.getMinutes();
    var ap = h >= 12 ? 'p' : 'a';
    var h12 = h % 12;
    if (h12 === 0) h12 = 12;
    return h12 + ':' + pad2(m) + ap;
  }

  function cloneCard(c) {
    var o = Object.assign({}, c);
    if (Array.isArray(c.tags)) o.tags = c.tags.slice();
    if (Array.isArray(c.blockers_pending)) o.blockers_pending = c.blockers_pending.slice();
    if (Array.isArray(c.blockers)) o.blockers = c.blockers.slice();
    if (Array.isArray(c.sched_tags)) o.sched_tags = c.sched_tags.slice();
    if (Array.isArray(c.coordinating_agents)) o.coordinating_agents = c.coordinating_agents.slice();
    if (Array.isArray(c.field_links)) o.field_links = c.field_links.slice();
    return o;
  }

  function buildSightTestCards(nowMs) {
    nowMs = nowMs != null ? nowMs : Date.now();
    var today = new Date(nowMs);
    var yesterday = new Date(nowMs - 86400000);
    var lead = new Date(nowMs + 45 * 60000);
    var amber = new Date(nowMs + 5 * 60000);
    var midStart = new Date(nowMs - 30 * 60000);
    var nearStart = new Date(nowMs - 55 * 60000);
    var overStart = new Date(nowMs - 90 * 60000);
    var pointStart = new Date(nowMs - 2 * 60000);

    function st( partial) {
      var o = Object.assign({
        domain: 'sight',
        project: 'fixtures',
        tags: ['task', SIGHT_TEST_TAG],
        timed: false,
        due_today: false
      }, partial);
      if (!Array.isArray(o.tags)) o.tags = ['task', SIGHT_TEST_TAG];
      if (o.tags.indexOf(SIGHT_TEST_TAG) < 0) o.tags = o.tags.concat([SIGHT_TEST_TAG]);
      return o;
    }

    return [
      st({
        id: 'st-urgent',
        title: 'Sight-test urgent',
        status: 'urgent',
        tosu: true,
        notes: 'Urgent fixture — agenda day-plane band 0. field_links → sp-view-a / sp-ocr-grain.',
        notes_excerpt: 'Urgent fixture — agenda day-plane band 0.',
        field_links: ['sp-view-a', 'sp-ocr-grain']
      }),
      st({
        id: 'st-urgent-2',
        title: 'Sight-test urgent (second)',
        status: 'urgent',
        tosu: true,
        project: 'agenda-check',
        notes: 'Second urgent for agenda semantics.',
        notes_excerpt: 'Second urgent for agenda semantics.'
      }),
      st({
        id: 'st-now',
        title: 'Sight-test now',
        status: 'now',
        tosu: true
      }),
      st({
        id: 'st-today',
        title: 'Sight-test today',
        status: 'today',
        tosu: true,
        due_today: true,
        notes: 'Today status + due_today. field_links → sp-digest-pack.',
        notes_excerpt: 'Today status + due_today.',
        field_links: ['sp-digest-pack']
      }),
      st({
        id: 'st-progress',
        title: 'Sight-test progress',
        status: 'progress',
        domain: 'almanac',
        project: 'board-ui',
        tosu: false,
        field_links: ['sp-survey-route']
      }),
      st({
        id: 'st-later',
        title: 'Sight-test later',
        status: 'later',
        domain: 'system',
        tosu: false
      }),
      st({
        id: 'st-deferred',
        title: 'Sight-test deferred',
        status: 'deferred',
        domain: 'fieldguide',
        tosu: true
      }),
      st({
        id: 'st-sched',
        title: 'Sight-test sched (future)',
        status: 'sched',
        domain: 'pack',
        datetime: formatBoardDatetime(new Date(nowMs + 3 * 86400000)),
        time: '10:00a',
        timed: true,
        tosu: true
      }),
      st({
        id: 'st-done',
        title: 'Sight-test done',
        status: 'done',
        tosu: true
      }),
      st({
        id: 'st-overdue',
        title: 'Sight-test overdue',
        status: 'sched',
        project: 'agenda-check',
        tosu: true,
        datetime: formatBoardDatetime(yesterday),
        time: '9:00a',
        timed: true,
        notes: 'Overdue sched — agenda band with urgent/today.',
        notes_excerpt: 'Overdue sched — agenda band with urgent/today.'
      }),
      st({
        id: 'st-overdue-today-status',
        title: 'Sight-test overdue (today status)',
        status: 'today',
        project: 'agenda-check',
        tosu: true,
        datetime: formatBoardDatetime(yesterday),
        time: '11:00a',
        notes: 'status=today + datetime yesterday → overdue tag.',
        notes_excerpt: 'status=today + datetime yesterday → overdue tag.'
      }),
      st({
        id: 'st-due-today',
        title: 'Sight-test due_today',
        status: 'today',
        project: 'agenda-check',
        tosu: true,
        datetime: formatBoardDatetime(today),
        time: '3:00p',
        due_today: true
      }),
      st({
        id: 'st-blocked',
        title: 'Sight-test blocked',
        status: 'today',
        tosu: true,
        blockers_pending: ['st-urgent'],
        blockers_summary: 'st-urgent',
        notes: 'Blocked — hidden when agenda hides blocks.',
        notes_excerpt: 'Blocked — hidden when agenda hides blocks.'
      }),
      st({
        id: 'st-agent',
        title: 'Sight-test agent lane (¬tosu)',
        status: 'today',
        domain: 'system',
        tosu: false,
        due_today: true
      }),
      st({
        id: 'st-timer-lead',
        title: 'Sight-test timer lead-up (~45m)',
        status: 'sched',
        domain: 'clock',
        project: 'timers',
        tosu: true,
        timed: true,
        datetime: formatBoardDatetime(lead),
        time: formatBoardTime(lead),
        duration: 30
      }),
      st({
        id: 'st-timer-amber',
        title: 'Sight-test timer amber (~5m)',
        status: 'sched',
        domain: 'clock',
        project: 'timers',
        tosu: true,
        timed: true,
        datetime: formatBoardDatetime(amber),
        time: formatBoardTime(amber),
        duration: 30
      }),
      st({
        id: 'st-timer-mid',
        title: 'Sight-test timer in-progress mid (~50%)',
        status: 'sched',
        domain: 'clock',
        project: 'timers',
        tosu: true,
        timed: true,
        datetime: formatBoardDatetime(midStart),
        time: formatBoardTime(midStart),
        duration: 60,
        field_links: ['sp-digest-timers']
      }),
      st({
        id: 'st-timer-near',
        title: 'Sight-test timer near-end',
        status: 'sched',
        domain: 'clock',
        project: 'timers',
        tosu: true,
        timed: true,
        datetime: formatBoardDatetime(nearStart),
        time: formatBoardTime(nearStart),
        duration: 60
      }),
      st({
        id: 'st-timer-over',
        title: 'Sight-test timer overdue/over',
        status: 'sched',
        domain: 'clock',
        project: 'timers',
        tosu: true,
        timed: true,
        datetime: formatBoardDatetime(overStart),
        time: formatBoardTime(overStart),
        duration: 60
      }),
      st({
        id: 'st-timer-point',
        title: 'Sight-test timer point-event',
        status: 'sched',
        domain: 'clock',
        project: 'timers',
        tosu: true,
        timed: true,
        datetime: formatBoardDatetime(pointStart),
        time: formatBoardTime(pointStart)
        /* no duration → point-event overdue after start */
      }),
      st({
        id: 'st-long-title',
        title: 'Sight-test long title wrap — the quick brown fox jumps over the lazy dog while packing MEGA backups and reviewing agenda day-plane bands for urgent overdue today due_today across domains',
        status: 'urgent',
        project: 'wrap',
        tosu: true,
        notes: 'Tosu notes line one.\nSecond line for multi-line notes clamp/wrap.',
        notes_excerpt: 'Tosu notes line one.'
      }),
      st({
        id: 'st-empty-notes',
        title: 'Sight-test empty notes (tosu)',
        status: 'today',
        tosu: true,
        notes: '',
        notes_excerpt: ''
      })
    ];
  }

  function rebuildCardsFromPlane() {
    var cards = (state.planeCards || []).map(cloneCard);
    cards.forEach(normalizeCard);
    if (state.sightTest) {
      buildSightTestCards(Date.now()).forEach(function (raw) {
        cards.push(normalizeCard(raw));
      });
    }
    state.cards = cards;
    rebuildById();
  }

  function readSightTestFlag() {
    try {
      var u = new URL(window.location.href);
      var v = u.searchParams.get('test');
      if (v === '1' || v === 'true' || v === 'yes') {
        try { localStorage.setItem('sight-test', '1'); } catch (e0) { /* ignore */ }
        return true;
      }
      if (v === '0' || v === 'false' || v === 'no') {
        try { localStorage.setItem('sight-test', '0'); } catch (e1) { /* ignore */ }
        return false;
      }
    } catch (e) { /* ignore */ }
    try {
      return localStorage.getItem('sight-test') === '1';
    } catch (e2) {
      return false;
    }
  }

  function syncSightTestUrl(on) {
    try {
      var u = new URL(window.location.href);
      if (on) u.searchParams.set('test', '1');
      else u.searchParams.delete('test');
      window.history.replaceState({}, '', u.pathname + u.search + u.hash);
    } catch (e) { /* ignore */ }
  }

  function persistSightTest(on) {
    try { localStorage.setItem('sight-test', on ? '1' : '0'); } catch (e) { /* ignore */ }
    syncSightTestUrl(on);
  }

  function setSightTest(on) {
    if (!!on === !!state.sightTest) return;
    if (on) {
      /* ON: snapshot, wipe filters/lane extras so only test mode filters list */
      state.savedBeforeTest = snapshotFilters();
      markAgendaDiverged();
      clearAllFilters();
      state.showDone = true;
      state.showBlocked = true;
      state.doneMode = 'none';
      state.blocksMode = 'none';
      state.removeMode = 'none';
      state.sort = 'inventory';
      state.sightTest = true;
      state.testMode = 'include';
    } else {
      var modeAfter = state.testMode === 'include' ? 'none' : (state.testMode || 'none');
      state.sightTest = false;
      if (state.savedBeforeTest) {
        restoreFilters(state.savedBeforeTest);
        state.savedBeforeTest = null;
      }
      state.sightTest = false;
      state.testMode = modeAfter;
    }
    persistSightTest(state.sightTest);
    rebuildCardsFromPlane();
  }

  function toggleSightTest() {
    setSightTest(!state.sightTest);
    renderAll();
  }

  function setShowAll(on) {
    if (!!on === !!state.showAll) return;
    if (on) {
      /* ON: snapshot, wipe all filters so the full inventory shows */
      state.savedBeforeAll = snapshotFilters();
      markAgendaDiverged();
      clearAllFilters();
      state.showDone = true;
      state.showBlocked = true;
      state.doneMode = 'none';
      state.blocksMode = 'none';
      state.removeMode = 'none';
      state.testMode = 'none';
      state.sort = 'inventory';
      state.showAll = true;
    } else {
      state.showAll = false;
      if (state.savedBeforeAll) {
        restoreFilters(state.savedBeforeAll);
        state.savedBeforeAll = null;
      }
    }
    renderAll();
  }

  function toggleShowAll() {
    setShowAll(!state.showAll);
  }

  /* ---------- field parcel fixtures (park dual-pane; fixtures only) ---------- */
  function buildSightTestParcels() {
    function sp(partial) {
      var o = Object.assign({
        grain: 'view',
        source: 'fixture',
        tags: [PARCEL_TEST_TAG, SIGHT_TEST_TAG],
        body: ''
      }, partial);
      if (!Array.isArray(o.tags)) o.tags = [PARCEL_TEST_TAG, SIGHT_TEST_TAG];
      if (o.tags.indexOf(PARCEL_TEST_TAG) < 0) o.tags = o.tags.concat([PARCEL_TEST_TAG]);
      if (o.tags.indexOf(SIGHT_TEST_TAG) < 0) o.tags = o.tags.concat([SIGHT_TEST_TAG]);
      if (Array.isArray(o.task_links)) o.task_links = o.task_links.slice();
      return o;
    }
    return [
      sp({
        id: 'sp-view-a',
        title: 'View A — board dual-pane sketch',
        grain: 'view',
        route: 'sight/field-pane',
        body: 'Parcel fixture for a View grain. Tasks slide left; field opens right. No TOC — body uses notes class.',
        task_links: ['st-urgent']
      }),
      sp({
        id: 'sp-ocr-grain',
        title: 'OCR grain — whiteboard capture',
        grain: 'ocr',
        body: 'Whole-grain OCR unit (grain IS the parcel). Linked from urgent so info stays out of the task list until wanted.',
        task_links: ['st-urgent']
      }),
      sp({
        id: 'sp-digest-pack',
        title: 'Digest — pack week cut',
        grain: 'digest',
        route: 'pack/week',
        body: 'Short digest parcel: three bullets worth of prose, notes-length. Earn-keep link from today fixture only.',
        task_links: ['st-today']
      }),
      sp({
        id: 'sp-survey-route',
        title: 'Survey — route catalog slice',
        grain: 'survey',
        route: 'routes/index',
        body: 'Survey parcel standing in for a route catalog cut. Progress fixture points here; unlinked field still visible when parcels on.',
        task_links: ['st-progress']
      }),
      sp({
        id: 'sp-chart-timeline',
        title: 'Chart — timer phase timeline',
        grain: 'chart',
        body: 'Chart-shaped parcel with no task_links — proves unlinked field still renders coherently in the pane.'
      }),
      sp({
        id: 'sp-profile-agent',
        title: 'Profile — agent lane chrome',
        grain: 'profile',
        body: 'Profile parcel for lane chrome check. Fixture tag parcel-test; not a live field.toml id schema.'
      }),
      sp({
        id: 'sp-digest-timers',
        title: 'Digest — mid-timer session notes',
        grain: 'digest',
        route: 'clock/timers',
        body: 'Session digest for the mid-timer fixture. Click linked tasks chip to jump back to st-timer-mid.',
        task_links: ['st-timer-mid', 'st-timer-amber']
      }),
      sp({
        id: 'sp-view-empty-links',
        title: 'View — empty links kitchen sink',
        grain: 'view',
        body: 'Kitchen-sink parcel with no task_links and no route — quiet chrome omits the linked-tasks strip.'
      })
    ];
  }

  /* ?parcels= fixtures | on | off | '' (absent). */
  function parcelsQueryMode() {
    try {
      var v = new URL(window.location.href).searchParams.get('parcels');
      if (v == null) return '';
      v = String(v).toLowerCase();
      if (v === 'fixtures' || v === 'fixture') return 'fixtures';
      if (v === '1' || v === 'true' || v === 'yes' || v === 'on') return 'on';
      if (v === '0' || v === 'false' || v === 'no' || v === 'off') return 'off';
    } catch (e) { /* ignore */ }
    return '';
  }

  function bareParcelId(raw) {
    var id = String(raw || '').trim();
    if (!id) return '';
    if (id.indexOf('field/') === 0) id = id.slice(6);
    if (id.indexOf('parcel.') === 0) id = id.slice(7);
    return id;
  }

  function asLinkList(v) {
    if (Array.isArray(v)) return v.slice();
    if (typeof v === 'string' && v) return [v];
    return [];
  }

  /* [parcel.<id>] / [plot.<id>] -> card projection. Id is the bare suffix. */
  function projectFieldTables(tables) {
    var plots = {};
    var parcels = [];
    var names = Object.keys(tables || {});
    names.forEach(function (name) {
      if (name.indexOf('plot.') !== 0) return;
      var pid = name.slice(5);
      var row = tables[name] || {};
      plots[pid] = {
        id: pid,
        area: row.area ? String(row.area) : '',
        title: row.title ? String(row.title) : '',
        note: row.note ? String(row.note) : '',
        /* optional framing if the row already has it — no description/created keys */
        framing: row.framing ? String(row.framing) : '',
        description: row.description ? String(row.description) : '',
        created: (row.created != null && row.created !== '') ? String(row.created) : '',
        modified: (row.modified != null && row.modified !== '') ? String(row.modified) : '',
        /* reading order: batch = inject time (ISO UTC), batch_ord = authored position in batch */
        batch: (row.batch != null && row.batch !== '') ? String(row.batch) : '',
        batch_ord: typeof row.batch_ord === 'number' ? row.batch_ord : null,
        /* this plot's tags only — never a parcel's, never a sibling plot's.
           Tags are labels, never destinations. */
        tags: asLinkList(row.tags),
        /* typed edges: the only id links */
        ref: asLinkList(row.ref),
        up: asLinkList(row.up),
        cite: asLinkList(row.cite)
      };
    });
    names.forEach(function (name) {
      if (name.indexOf('parcel.') !== 0) return;
      var row = tables[name] || {};
      var id = name.slice(7);
      if (!id) return;
      var plotId = row.plot ? String(row.plot) : '';
      var plot = plots[plotId] || null;
      var area = row.area ? String(row.area) : (plot && plot.area ? plot.area : '');
      parcels.push({
        id: id,
        table: name,
        source: 'live',
        title: row.claim ? String(row.claim) : '(untitled)',
        body: row.content ? String(row.content) : '',
        claim: row.claim ? String(row.claim) : '',
        plot: plotId,
        area: area,
        ord: typeof row.ord === 'number' ? row.ord : null,
        task_links: asLinkList(row.task_links),
        /* parcel tags only — do not copy plots[plotId].tags */
        tags: asLinkList(row.tags),
        ref: asLinkList(row.ref),
        up: asLinkList(row.up),
        cite: asLinkList(row.cite)
      });
    });
    parcels.sort(function (a, b) {
      var ap = a.plot || '';
      var bp = b.plot || '';
      if (ap !== bp) return ap < bp ? -1 : 1;
      var ao = a.ord == null ? 1e9 : a.ord;
      var bo = b.ord == null ? 1e9 : b.ord;
      if (ao !== bo) return ao - bo;
      return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
    });
    return { plots: plots, parcels: parcels };
  }

  function ingestPlaneField(plane) {
    state.liveParcels = [];
    state.plotsById = {};
    ingestPlaneTts(plane);
    if (!plane || typeof plane.field !== 'string' || !String(plane.field).trim()) return;
    var parsed = parseBoardToml(plane.field);
    var got = projectFieldTables(parsed.tables || {});
    state.plotsById = got.plots;
    state.liveParcels = got.parcels;
  }

  function readInitialNav() {
    var parcel = '';
    var plot = '';
    var view = '';
    var mode = parcelsQueryMode();
    try {
      var u = new URL(window.location.href);
      parcel = String(u.searchParams.get('parcel') || u.searchParams.get('field') || '').trim();
      plot = String(u.searchParams.get('plot') || '').trim();
      view = String(u.searchParams.get('view') || '').toLowerCase();
    } catch (e) { /* ignore */ }
    var h = '';
    try { h = (window.location.hash || '').replace(/^#/, ''); } catch (e2) { h = ''; }
    var fieldH = fieldIdFromHash(h);
    if (!parcel && fieldH) parcel = fieldH;
    var plane = 'tasks';
    if (parcel || plot || view === 'field' || mode === 'on' || mode === 'fixtures') plane = 'field';
    if (mode === 'off' && !parcel && view !== 'field' && !plot) plane = 'tasks';
    if (view === 'tasks' && !parcel) plane = 'tasks';
    return { plane: plane, plot: plot, parcel: parcel, card: '' };
  }

  function resolveParcel(id) {
    if (!id || !state.parcelsById) return null;
    var raw = String(id).trim();
    if (state.parcelsById[raw]) return state.parcelsById[raw];
    var bare = bareParcelId(raw);
    if (bare && state.parcelsById[bare]) return state.parcelsById[bare];
    if (bare && state.parcelsById['parcel.' + bare]) return state.parcelsById['parcel.' + bare];
    return null;
  }

  function rebuildParcels() {
    var mode = parcelsQueryMode();
    var list;
    if (mode === 'fixtures') {
      list = buildSightTestParcels();
      state.fieldSource = 'fixtures';
    } else if (state.liveParcels && state.liveParcels.length) {
      list = state.liveParcels.slice();
      state.fieldSource = 'live';
    } else if (state.parcelTest || mode === 'on') {
      list = buildSightTestParcels();
      state.fieldSource = 'fixtures';
    } else {
      list = [];
      state.fieldSource = 'none';
    }
    state.parcels = list;
    var by = {};
    list.forEach(function (p) {
      if (!p || !p.id) return;
      by[p.id] = p;
      if (p.table) by[p.table] = p;
    });
    state.parcelsById = by;
  }

  function parcelArea(parcel) {
    if (!parcel) return '';
    if (parcel.area) return String(parcel.area);
    var plot = parcel.plot && state.plotsById[parcel.plot];
    if (plot && plot.area) return String(plot.area);
    return parcel.plot ? String(parcel.plot) : '';
  }

  function parcelLabel(fid) {
    var p = resolveParcel(fid);
    var name = p && (p.claim || p.title);
    if (name && name !== '(untitled)') return String(name);
    return bareParcelId(fid) || String(fid || '');
  }

  function taskLabel(tid) {
    var c = state.byId[tid];
    if (c && c.title) return String(c.title);
    return String(tid || '');
  }

  /* Plot key: area is the unique slug of ONE plot (field-spec [ontology]);
     a plot with no area is keyed by its bare id. */
  function plotKey(plot) {
    if (!plot) return '';
    return plot.area ? String(plot.area) : String(plot.id || '');
  }

  /* Key (area slug or bare plot id) -> bare plot id. */
  function plotIdForKey(key) {
    key = String(key || '').trim();
    if (!key) return '';
    if (key.indexOf('plot.') === 0) key = key.slice(5);
    var plots = state.plotsById || {};
    if (plots[key]) return key;
    var ids = Object.keys(plots);
    for (var i = 0; i < ids.length; i++) {
      if (plots[ids[i]] && plots[ids[i]].area === key) return ids[i];
    }
    return '';
  }

  /* Plot index: one card per plot table. Never grouped by area or tag. */
  function fieldIndex() {
    var order = [];
    Object.keys(state.plotsById || {}).forEach(function (pid) {
      var plot = state.plotsById[pid] || {};
      var count = 0;
      (state.liveParcels || []).forEach(function (p) {
        if (p && p.plot === pid) count++;
      });
      order.push({
        id: pid,
        key: plotKey(plot),
        area: plot.area || '',
        title: plot.title || '',
        note: plot.note || '',
        framing: plot.framing || '',
        description: plot.description || '',
        created: plot.created || '',
        modified: plot.modified || '',
        batch: plot.batch || '',
        batch_ord: typeof plot.batch_ord === 'number' ? plot.batch_ord : null,
        tags: Array.isArray(plot.tags) ? plot.tags.slice() : [],
        ref: plot.ref || [],
        up: plot.up || [],
        cite: plot.cite || [],
        parcelCount: count
      });
    });
    return order;
  }

  /* Parcels of the one plot named by key (area slug or plot id). */
  function parcelsForArea(key) {
    var pid = plotIdForKey(key);
    return (state.parcels || []).filter(function (p) {
      if (!p) return false;
      if (pid) return p.plot === pid;
      return parcelArea(p) === key;
    });
  }

  /* Typed edge target -> open that plot or focus that parcel. */
  function bareEdgeTarget(raw) {
    var t = String(raw || '').trim();
    if (t.indexOf('field/') === 0) t = t.slice(6);
    return t;
  }

  function edgeLabel(raw) {
    var t = bareEdgeTarget(raw);
    var pid = t.indexOf('plot.') === 0 ? t.slice(5) : t;
    if (state.plotsById && state.plotsById[pid]) return pid;
    return bareParcelId(t) || t;
  }

  function followEdge(raw) {
    var t = bareEdgeTarget(raw);
    var pid = t.indexOf('plot.') === 0 ? t.slice(5) : t;
    clearSearchForReveal();
    if (state.plotsById && state.plotsById[pid]) {
      openFieldPlot(plotKey(state.plotsById[pid]));
      return;
    }
    focusParcel(bareParcelId(t) || t, { history: 'push', origin: currentNav(), instant: true });
  }

  /* ref / up / cite: the only id links on field cards (.tag-link). */
  function appendEdgeLinks(tags, row) {
    ['ref', 'up', 'cite'].forEach(function (kind) {
      (row && row[kind] || []).forEach(function (target) {
        if (!target) return;
        var label = edgeLabel(target);
        var b = document.createElement('button');
        b.type = 'button';
        b.className = 'tag-meta tag-link edge-link';
        b.setAttribute('data-edge', kind);
        b.textContent = kind + ' ' + label;
        b.title = kind + ' → ' + target;
        b.setAttribute('aria-label', kind + ' edge to ' + label);
        b.addEventListener('click', function (ev) {
          ev.preventDefault();
          ev.stopPropagation();
          followEdge(target);
        });
        tags.appendChild(b);
      });
    });
  }

  /* scrollTop assignment ignores html { scroll-behavior: smooth }. */
  function jumpToEl(row) {
    if (!row || !row.getBoundingClientRect) return;
    var node = row.parentElement;
    var inner = null;
    while (node && node !== document.body && node !== document.documentElement) {
      var oy = '';
      try { oy = window.getComputedStyle(node).overflowY; } catch (e) { oy = ''; }
      if ((oy === 'auto' || oy === 'scroll' || oy === 'overlay') &&
          node.scrollHeight > node.clientHeight + 2) {
        inner = node;
        break;
      }
      node = node.parentElement;
    }
    if (inner) {
      var rowRect = row.getBoundingClientRect();
      var scRect = inner.getBoundingClientRect();
      var next = inner.scrollTop + (rowRect.top - scRect.top) -
        (inner.clientHeight - rowRect.height) / 2;
      if (next < 0) next = 0;
      inner.scrollTop = next;
      return;
    }
    var rect = row.getBoundingClientRect();
    var se = document.scrollingElement || document.documentElement;
    var y = se.scrollTop + rect.top - (window.innerHeight - rect.height) / 2;
    if (y < 0) y = 0;
    se.scrollTop = y;
    if (document.body) document.body.scrollTop = y;
  }

  function urlForNav(nav) {
    var u = new URL(window.location.href);
    nav = nav || {};
    if (nav.plane === 'field') {
      u.searchParams.set('view', 'field');
      if (nav.plot) u.searchParams.set('plot', nav.plot);
      else u.searchParams.delete('plot');
      if (nav.parcel) u.searchParams.set('parcel', bareParcelId(nav.parcel) || nav.parcel);
      else u.searchParams.delete('parcel');
      u.searchParams.delete('field');
    } else {
      u.searchParams.delete('view');
      u.searchParams.delete('plot');
      u.searchParams.delete('parcel');
      u.searchParams.delete('field');
    }
    /* Hash jumps follow scroll-behavior: smooth — keep the id in history state. */
    u.hash = '';
    return u.pathname + u.search + u.hash;
  }

  function focusedDataId(sel) {
    var node = null;
    try { node = document.querySelector(sel); } catch (e) { node = null; }
    return node ? (node.getAttribute('data-id') || '') : '';
  }

  function currentNav() {
    var field = state.viewPlane === 'field';
    var parcel = '';
    var card = '';
    if (field) parcel = state.pendingParcelFocusId || focusedDataId('.parcel-card.is-focused');
    else card = state.pendingFocusId || focusedDataId('.board-row.is-focused:not(.parcel-card)');
    var src = {
      plane: field ? 'field' : 'tasks',
      plot: field ? (state.fieldPlot || '') : '',
      parcel: field ? parcel : '',
      card: field ? '' : card,
      split: state.split
    };
    return cloneNav(src);
  }

  function cloneNav(n, nested) {
    n = n || {};
    var field = n.plane === 'field';
    var out = {
      plane: field ? 'field' : 'tasks',
      plot: field ? (n.plot || '') : '',
      parcel: field ? (n.parcel || '') : '',
      card: field ? '' : (n.card || ''),
      split: null
    };
    if (!nested && n.split && n.split.plane) out.split = cloneNav(n.split, true);
    return out;
  }

  function navKey(n) {
    n = cloneNav(n);
    var base = n.plane + '|' + n.plot + '|' + n.parcel + '|' + n.card;
    if (!n.split) return base;
    return base + '||' + n.split.plane + '|' + n.split.plot + '|' + n.split.parcel + '|' + n.split.card;
  }

  function syncHistChrome() {
    var back = el('hist-back');
    var fwd = el('hist-fwd');
    var n = state.navLog ? state.navLog.length : 0;
    var pos = state.navPos || 0;
    if (back) {
      back.disabled = !(n && pos > 0);
      back.setAttribute('aria-disabled', back.disabled ? 'true' : 'false');
    }
    if (fwd) {
      fwd.disabled = !(n && pos < n - 1);
      fwd.setAttribute('aria-disabled', fwd.disabled ? 'true' : 'false');
    }
  }

  function seedNav(nav) {
    if (state.navReady) return;
    state.navReady = true;
    state.navLog = [cloneNav(nav)];
    state.navPos = 0;
    syncHistChrome();
  }

  function rememberNav(nav) {
    nav = cloneNav(nav);
    if (!state.navReady) {
      seedNav(nav);
      return;
    }
    var cur = state.navLog[state.navPos];
    if (cur && navKey(cur) === navKey(nav)) return;
    state.navLog = state.navLog.slice(0, state.navPos + 1);
    state.navLog.push(nav);
    state.navPos = state.navLog.length - 1;
    syncHistChrome();
  }

  function goHist(delta) {
    if (!state.navLog || !state.navLog.length) return;
    var next = state.navPos + delta;
    if (next < 0 || next >= state.navLog.length) return;
    state.navPos = next;
    applyNav(state.navLog[next], { history: 'replace', record: false });
  }

  /* URL tracks the place. Back/forward is the in-session stack, not history. */
  function syncViewUrl(mode) {
    var nav = currentNav();
    var href = urlForNav(nav);
    try {
      history.replaceState({ sightPlace: nav }, '', href);
    } catch (e) { /* ignore */ }
  }

  function clearSearchForReveal() {
    if (!(state.searchQuery || '').trim()) return;
    state.searchQuery = '';
    var input = el('board-search-input');
    if (input) input.value = '';
    showToast('Cleared search to reveal link');
  }

  function applyNav(nav, opts) {
    opts = opts || {};
    nav = cloneNav(nav || {});
    state.split = nav.split;
    state.viewPlane = nav.plane === 'field' ? 'field' : 'tasks';
    state.pendingParcelFocusId = null;
    state.pendingFocusId = null;
    var fieldNav = nav.plane === 'field' ? nav : (nav.split && nav.split.plane === 'field' ? nav.split : null);
    var taskNav = nav.plane === 'tasks' ? nav : (nav.split && nav.split.plane === 'tasks' ? nav.split : null);
    if (fieldNav) {
      state.fieldPlot = fieldNav.plot || '';
      if (fieldNav.parcel) {
        rebuildParcels();
        var parcel = resolveParcel(fieldNav.parcel);
        if (!parcel) showToast('No parcel ' + fieldNav.parcel);
        else {
          state.fieldPlot = parcelArea(parcel);
          state.pendingParcelFocusId = parcel.id;
          if (nav.plane === 'field') {
            nav.plot = state.fieldPlot;
            nav.parcel = parcel.id;
          }
          if (nav.split && nav.split.plane === 'field') {
            nav.split.plot = state.fieldPlot;
            nav.split.parcel = parcel.id;
          }
          state.split = nav.split;
        }
      }
    }
    if (taskNav && taskNav.card) state.pendingFocusId = taskNav.card;
    if (opts.history !== 'none') syncViewUrl(opts.history || 'replace');
    if (opts.record) rememberNav(nav);
    renderAll();
    if (taskNav && taskNav.card) focusCard(taskNav.card, { instant: true });
  }

  function openSplit(source, dest) {
    var next = cloneNav(source);
    next.split = cloneNav(dest);
    pushNav(next, cloneNav(source));
  }

  function closeSplit() {
    if (!state.split) return;
    if ((state.navPos || 0) > 0) { goHist(-1); return; }
    pushNav({
      plane: state.viewPlane,
      plot: state.viewPlane === 'field' ? (state.fieldPlot || '') : '',
      parcel: '',
      card: '',
      split: null
    });
  }

  function pushNav(next, origin) {
    if (origin) rememberNav(origin);
    applyNav(next, { history: 'replace', record: true });
  }

  function focusParcel(id, opts) {
    opts = opts || {};
    if (!id) return;
    rebuildParcels();
    var parcel = resolveParcel(id);
    if (!parcel) {
      showToast('No parcel ' + id);
      state.viewPlane = 'field';
      if (opts.history === 'push') {
        pushNav({ plane: 'field', plot: state.fieldPlot || '', parcel: '', card: '' }, opts.origin || null);
      } else if (opts.history !== 'none') {
        syncViewUrl('replace');
        renderAll();
      } else {
        renderAll();
      }
      return;
    }
    var area = parcelArea(parcel);
    if (opts.history === 'push') {
      pushNav(
        { plane: 'field', plot: area, parcel: parcel.id, card: '' },
        opts.origin || null
      );
      return;
    }
    state.viewPlane = 'field';
    state.fieldPlot = area;
    state.pendingParcelFocusId = parcel.id;
    if (opts.history !== 'none') syncViewUrl('replace');
    renderAll();
  }

  function openFieldPlot(area) {
    var parsed = parseSearch(state.searchQuery);
    if (parsed.planePrefix === 'F') {
      state.searchQuery = parsed.terms.join(' ');
      var input = el('board-search-input');
      if (input) input.value = state.searchQuery;
    }
    applyNav(
      { plane: 'field', plot: area || '', parcel: '', card: '' },
      { history: 'replace', record: true }
    );
  }

  function normalizeCard(c) {
    if (c.timed == null) c.timed = false;
    if (c.due_today == null) c.due_today = false;
    if (!c.status) c.status = 'later';
    c.status = String(c.status).toLowerCase();
    if (STATUS_RANK[c.status] == null) c.status = 'later';
    c.tags = Array.isArray(c.tags) ? c.tags.slice() : [];
    c.field_links = Array.isArray(c.field_links) ? c.field_links.slice() : [];
    c.tosu = c.tosu === true || c.tags.indexOf('tosu') >= 0;
    if (!c.tosu) {
      c.notes = '';
      c.notes_excerpt = '';
    } else {
      c.notes = c.notes ? String(c.notes) : '';
      c.notes_excerpt = c.notes_excerpt ? String(c.notes_excerpt) : '';
    }
    if (!Array.isArray(c.blockers_pending) && c.blockers_pending) {
      c.blockers_pending = [String(c.blockers_pending)];
    }
    if (!Array.isArray(c.blockers_pending)) c.blockers_pending = [];
    if (!Array.isArray(c.blockers) && c.blockers) {
      c.blockers = [String(c.blockers)];
    }
    if (!Array.isArray(c.blockers)) c.blockers = [];
    if (!c.blockers_pending.length && c.blockers.length) {
      c.blockers_pending = c.blockers.slice();
    }
    c.blocked = c.blockers_pending.length > 0;
    c.blockers_summary = c.blockers_summary || c.blockers_pending.join(',');

    var today = state.localToday || localTodayParts();
    c.datetime_parts = parseDatetime(c.datetime);
    c.time_mins = parseTime(c.time);
    if (!c.due_today && c.datetime_parts && dateCmp(c.datetime_parts, today) === 0) {
      c.due_today = true;
    }
    c.overdue = !!(c.datetime_parts && dateCmp(c.datetime_parts, today) < 0 &&
      (c.status === 'sched' || c.status === 'today'));

    /* SCHED chips: due_today / overdue / timed / sched / undated */
    var tags = [];
    if (c.due_today) tags.push('due_today');
    if (c.overdue) tags.push('overdue');
    if (c.timed) tags.push('timed');
    if (c.status === 'sched') tags.push('sched');
    if (!tags.length) tags.push('undated');
    c.sched_tags = tags;
    c.sched = tags[0];
    if (c['signaling-command'] && !c.signaling_command) {
      c.signaling_command = c['signaling-command'];
    }
    if (c['coordinating-agents'] && !c.coordinating_agents) {
      c.coordinating_agents = c['coordinating-agents'];
    }
    c.updated = typeof c.updated === 'number' ? c.updated : 0;
    c.created = typeof c.created === 'number' ? c.created : 0;
    return c;
  }

  /* ---------- fetch ---------- */
  function planeFromQuery() {
    try {
      var u = new URL(window.location.href);
      return u.searchParams.get('plane');
    } catch (e) {
      return null;
    }
  }

  function fetchText(url) {
    return fetch(url, { credentials: 'same-origin' }).then(function (res) {
      if (!res.ok) throw new Error('HTTP ' + res.status + ' for ' + url);
      return res.text();
    });
  }

  function planeFromMemory() {
    var plane = window.__SIGHT_PLANE__;
    if (!plane || typeof plane.board_model !== 'string') return null;
    var parsed = parseBoardToml(plane.board_model);
    if (!parsed.cards.length) throw new Error('no cards in decrypted plane');
    return {
      parsed: parsed,
      label: 'decrypted plane.enc',
      source: 'memory'
    };
  }

  function loadPlane() {
    try {
      var mem = planeFromMemory();
      if (mem) return Promise.resolve(mem);
    } catch (e) {
      return Promise.reject(e);
    }

    var q = planeFromQuery();
    var tries = [];
    if (q) tries.push(q);
    DEFAULT_PLANE_PATHS.forEach(function (p) { tries.push(p); });

    var chain = Promise.reject(new Error('start'));
    tries.forEach(function (url) {
      chain = chain.catch(function () {
        return fetchText(url).then(function (text) {
          var parsed = parseBoardToml(text);
          if (!parsed.cards.length) throw new Error('no cards in ' + url);
          return { parsed: parsed, label: url, source: 'fetch' };
        });
      });
    });

    return chain.catch(function () {
      var cards = FALLBACK_CARDS.map(function (c) {
        return normalizeCard(Object.assign({}, c));
      });
      return {
        parsed: {
          meta: {
            schema: 'labor-os.board-model/v1',
            card_count: cards.length,
            note: 'offline fallback'
          },
          cards: cards
        },
        label: 'inline fallback (fetch failed)',
        source: 'fallback'
      };
    });
  }

  /* Lane / done / blocks / test — shared by the list and the GLOBAL chips. */
  function passesGlobals(card) {
    if (state.testMode === 'exclude' && card.tags && card.tags.indexOf(SIGHT_TEST_TAG) >= 0) return false;
    if (state.lane === 'tosu' && !card.tosu) return false;
    if (state.lane === 'agent' && card.tosu) return false;
    if (state.blocksMode === 'include' && !card.blocked) return false;
    if (card.blocked && (state.blocksMode === 'exclude' || !state.showBlocked)) return false;
    if (state.doneMode === 'include' && card.status !== 'done') return false;
    if (!state.showDone && card.status === 'done') return false;
    if (state.removeMode === 'include' && card.status !== 'remove') return false;
    if (state.removeMode === 'exclude' && card.status === 'remove') return false;
    return true;
  }

  /* ---------- filter ---------- */
  function toggleIn(list, value) {
    var i = list.indexOf(value);
    if (i >= 0) list.splice(i, 1);
    else list.push(value);
  }

  function removeFrom(list, value) {
    var i = list.indexOf(value);
    if (i >= 0) list.splice(i, 1);
  }

  function cardField(card, field) {
    if (field === 'sched') return card.sched || 'undated';
    var v = card[field];
    if (v == null || v === '') return '(none)';
    return String(v);
  }

  function cardSchedTags(card) {
    return card.sched_tags && card.sched_tags.length ? card.sched_tags : [card.sched || 'undated'];
  }

  function matchesFilters(card) {
    /* Test mode: only kitchen-sink fixtures (hide plane cards). */
    if (state.sightTest) {
      if (!card.tags || card.tags.indexOf(SIGHT_TEST_TAG) < 0) return false;
    }
    if (state.agendaPreset && (card.id === 'root' || card.is_root)) return false;
    if (!passesGlobals(card)) return false;

    var statusEx = state.exclude.status;
    var statusInc = state.include.status;
    var schedEx = state.exclude.sched;
    var schedInc = state.include.sched;
    var statusVal = cardField(card, 'status');
    var schedTags = cardSchedTags(card);

    if (statusEx.length && statusEx.indexOf(statusVal) >= 0) return false;
    if (schedEx.length && schedTags.some(function (t) { return schedEx.indexOf(t) >= 0; })) return false;

    /*
     * Status ∪ sched includes: when BOTH axes have includes (agenda day plane),
     * match if the card hits either axis — AND would empty urgent∩overdue.
     * When only one axis has includes, keep strict must-match.
     */
    var statusIncOk = !statusInc.length || statusInc.indexOf(statusVal) >= 0;
    var schedIncOk = !schedInc.length || schedTags.some(function (t) { return schedInc.indexOf(t) >= 0; });
    if (statusInc.length && schedInc.length) {
      if (!statusIncOk && !schedIncOk) return false;
    } else {
      if (!statusIncOk) return false;
      if (!schedIncOk) return false;
    }

    var other = ['domain', 'project'];
    for (var i = 0; i < other.length; i++) {
      var f = other[i];
      var ex = state.exclude[f];
      var inc = state.include[f];
      var val = cardField(card, f);
      if (ex.length && ex.indexOf(val) >= 0) return false;
      if (inc.length && inc.indexOf(val) < 0) return false;
    }
    return true;
  }

  function statusRank(c) {
    var r = STATUS_RANK[c.status];
    return r == null ? 99 : r;
  }

  function datetimeSortKey(c) {
    if (!c.datetime_parts) return [99, 99, 99, 9999];
    var tm = c.time_mins != null ? c.time_mins : 9999;
    return [c.datetime_parts.y, c.datetime_parts.m, c.datetime_parts.day, tm];
  }

  function cmpArr(a, b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1;
    }
    return 0;
  }

  function agendaBand(c) {
    /* urgent/now → today/due_today → deadlines ≤ today → rest → blocked */
    if (c.status === 'urgent' || c.status === 'now') return 0;
    if (c.due_today || c.status === 'today') return 1;
    if (!c.blocked && c.datetime_parts &&
        dateCmp(c.datetime_parts, state.localToday) <= 0) return 2;
    if (!c.blocked) return 3;
    return 4;
  }

  function withinBandCmp(a, b) {
    if (a.datetime_parts && b.datetime_parts) {
      var c = cmpArr(datetimeSortKey(a), datetimeSortKey(b));
      if (c) return c;
    } else if (a.datetime_parts && !b.datetime_parts) return -1;
    else if (!a.datetime_parts && b.datetime_parts) return 1;
    if (a.updated !== b.updated) return b.updated - a.updated;
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
  }

  function sortCards(list) {
    var out = list.slice();
    if (state.sort === 'agenda') {
      out.sort(function (a, b) {
        var ba = agendaBand(a);
        var bb = agendaBand(b);
        if (ba !== bb) return ba - bb;
        return withinBandCmp(a, b);
      });
    } else {
      /* inventory: status precedence then id */
      out.sort(function (a, b) {
        var sr = statusRank(a) - statusRank(b);
        if (sr) return sr;
        return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
      });
    }
    return out;
  }

  function filteredCards() {
    var parsed = parseSearch(state.searchQuery);
    var base = state.cards.filter(function (c) {
      if (parsed.override) {
        /* / override: ignore chips/lane/blocked; search full plane */
        return matchesSearch(c, parsed);
      }
      if (!matchesFilters(c)) return false;
      return matchesSearch(c, parsed);
    });
    return sortCards(base);
  }

  function valuesForAxis(axis) {
    var field = FILTER_AXES[axis];
    if (!field) return [];
    var seen = {};
    var out = [];
    state.cards.forEach(function (c) {
      if (field === 'sched') {
        cardSchedTags(c).forEach(function (v) {
          if (!seen[v]) {
            seen[v] = 1;
            out.push(v);
          }
        });
        return;
      }
      var v = cardField(c, field);
      if (!seen[v]) {
        seen[v] = 1;
        out.push(v);
      }
    });
    out.sort(function (a, b) {
      if (a === '(none)') return 1;
      if (b === '(none)') return -1;
      return a < b ? -1 : a > b ? 1 : 0;
    });
    return out;
  }

  /* ---------- render ---------- */
  function el(id) { return document.getElementById(id); }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  /* Hail [[label | URL/id]] / [[URL]] + bare http(s). No markdown link dialect. */
  function autolinkNotes(raw) {
    var s = String(raw || '').replace(/^\n+|\n+$/g, '');
    if (!s) return '';
    /* Optional spaces around |; target may be URL or plane/task id */
    var hailRe = /\[\[\s*([^\]|]+?)\s*\|\s*([^\]]+?)\s*\]\]|\[\[\s*([^\]]+?)\s*\]\]/g;
    var urlRe = /(https?:\/\/[^\s<>"'`]+)/g;
    var parts = [];
    var last = 0;
    var m;
    var hits = [];
    while ((m = hailRe.exec(s))) {
      if (m[1] != null && m[2] != null) {
        hits.push({ start: m.index, end: m.index + m[0].length, label: m[1].trim(), target: m[2].trim() });
      } else {
        var tgt = (m[3] || '').trim();
        hits.push({ start: m.index, end: m.index + m[0].length, label: tgt, target: tgt });
      }
    }
    function linkFor(target, label) {
      var isUrl = /^https?:\/\//i.test(target);
      if (isUrl) {
        return '<a href="' + escapeHtml(target) + '" target="_blank" rel="noopener noreferrer">' +
          escapeHtml(label) + '</a>';
      }
      /* TOML / task id — in-plane jump */
      var id = target.replace(/^#/, '');
      return '<a class="hail-id" href="#' + escapeHtml(id) + '" data-card-id="' + escapeHtml(id) + '">' +
        escapeHtml(label) + '</a>';
    }
    function pushText(chunk) {
      if (!chunk) return;
      var um;
      urlRe.lastIndex = 0;
      var local = chunk;
      var out = '';
      var uLast = 0;
      while ((um = urlRe.exec(local))) {
        out += escapeHtml(local.slice(uLast, um.index));
        var full = um[1];
        var href = full.replace(/[.,);:]+$/, '');
        var trail = full.slice(href.length);
        out += '<a href="' + escapeHtml(href) + '" target="_blank" rel="noopener noreferrer">' +
          escapeHtml(href) + '</a>' + escapeHtml(trail);
        uLast = um.index + um[0].length;
      }
      out += escapeHtml(local.slice(uLast));
      parts.push(out);
    }
    if (!hits.length) {
      pushText(s);
      return parts.join('');
    }
    hits.forEach(function (hit) {
      pushText(s.slice(last, hit.start));
      parts.push(linkFor(hit.target, hit.label));
      last = hit.end;
    });
    pushText(s.slice(last));
    return parts.join('');
  }

  function setNotesHtml(el, raw) {
    el.innerHTML = autolinkNotes(raw);
  }

  function cardSearchHaystack(card) {
    var bits = [
      card.title || '',
      card.id || '',
      card.status || '',
      card.domain || '',
      card.project || '',
      card.notes || '',
      card.notes_excerpt || ''
    ];
    if (Array.isArray(card.tags)) bits.push(card.tags.join(' '));
    return bits.join(' ').toLowerCase();
  }

  function parseSearch(q) {
    q = String(q || '');
    var override = q.charAt(0) === '/';
    var body = override ? q.slice(1) : q;
    body = body.trim();
    var planePrefix = '';
    var pm = /^([A-Za-z])\s*:\s*([\s\S]*)$/.exec(body);
    if (pm) {
      var letter = pm[1].toUpperCase();
      /* T tasks, F parcels. S/C/K/G stay literal until those planes exist. */
      if (letter === 'T' || letter === 'F') {
        planePrefix = letter;
        body = pm[2].trim();
      }
    }
    body = body.toLowerCase();
    var terms = body ? body.split(/\s+/).filter(Boolean) : [];
    return { override: override, terms: terms, raw: q, planePrefix: planePrefix };
  }

  function matchesSearch(card, parsed) {
    if (!parsed.terms.length) return true;
    var hay = cardSearchHaystack(card);
    for (var i = 0; i < parsed.terms.length; i++) {
      if (hay.indexOf(parsed.terms[i]) < 0) return false;
    }
    return true;
  }

  function renderMeta() {
    var badge = el('plane-badge');
    var count = el('plane-count');
    if (badge) {
      badge.setAttribute('data-source', state.planeSource);
      badge.textContent = state.planeLabel;
    }
    if (count) {
      var n = state.meta.card_count != null ? state.meta.card_count : state.cards.length;
      count.textContent = n + ' cards in plane';
    }
  }

  function axisLaneState(id) {
    if (id === 'AGENDA') return state.agendaPreset ? 'include' : '';
    return '';
  }

  function renderAxes() {
    var extra = el('axis-bar-global');
    if (extra) {
      extra.innerHTML = '';
      extra.hidden = true;
    }
    var rows = [el('axis-bar')];
    var labels = ['Filter axes'];
    AXIS_ROWS.forEach(function (axes, ri) {
      var bar = rows[ri] || rows[0];
      if (!bar) return;
      bar.hidden = false;
      bar.innerHTML = '';
      bar.setAttribute('role', 'tablist');
      bar.setAttribute('aria-label', labels[ri] || 'Filter axes');
      axes.forEach(function (spec) {
        var axis = spec.id;
        var btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'axis-btn' + (spec.word ? ' axis-btn--word' : '');
        btn.id = spec.binary ? 'agenda-preset-btn' : ('axis-' + axis);
        var laneSt = axisLaneState(axis);
        if (laneSt) btn.setAttribute('data-state', laneSt);
        else btn.removeAttribute('data-state');
        var compactAxis = axisLabelsCompact();
        btn.textContent = (compactAxis && spec.short) ? spec.short : spec.label;
        if (compactAxis && spec.short) btn.setAttribute('aria-label', spec.label);
        if (spec.binary) {
          /* agenda stays a binary control — no value submenu */
          btn.setAttribute('aria-pressed', state.agendaPreset ? 'true' : 'false');
          btn.setAttribute('aria-selected', 'false');
          btn.title = state.agendaPreset
            ? 'Day plane ON — click to restore prior filters'
            : 'Day plane — tosu, hide done, hide blocked, urgent ∪ overdue ∪ today';
          btn.addEventListener('click', function () { toggleAgendaPreset(); });
        } else {
          btn.setAttribute('role', 'tab');
          var selected = axis === state.activeAxis && (SPECIAL_AXES[axis] || state.chipBandOpen);
          btn.setAttribute('aria-selected', selected ? 'true' : 'false');
          btn.classList.toggle('is-open', selected && !SPECIAL_AXES[axis]);
          btn.setAttribute('aria-controls', 'chip-band');
          if (compactAxis && spec.short) btn.title = spec.label;
          btn.addEventListener('click', function () {
            if (state.activeAxis === axis && state.chipBandOpen) {
              state.chipBandOpen = false;
            } else {
              state.activeAxis = axis;
              /* TIMERS has no value submenu; GLOBAL and status axes do */
              state.chipBandOpen = !SPECIAL_AXES[axis];
            }
            renderAll();
          });
        }
        bar.appendChild(btn);
      });
    });
  }

  function laneChoices(axis) {
    if (axis === 'AGENDA') {
      return [
        { value: 'on', label: 'on', on: !!state.agendaPreset },
        { value: 'off', label: 'off', on: !state.agendaPreset }
      ];
    }
    if (axis === 'TOSU') {
      return [
        { value: 'all', label: 'all', on: state.lane === 'all' },
        { value: 'tosu', label: 'tosu', on: state.lane === 'tosu' },
        { value: 'agent', label: '−tosu', on: state.lane === 'agent' }
      ];
    }
    if (axis === 'DONE') {
      return [
        { value: 'show', label: 'show', on: !!state.showDone },
        { value: 'hide', label: 'hide', on: !state.showDone }
      ];
    }
    if (axis === 'BLOCKS') {
      return [
        { value: 'show', label: 'show', on: !!state.showBlocked },
        { value: 'hide', label: 'hide', on: !state.showBlocked }
      ];
    }
    if (axis === 'TEST') {
      return [
        { value: 'on', label: 'on', on: !!state.sightTest },
        { value: 'off', label: 'off', on: !state.sightTest }
      ];
    }
    return null;
  }

  function pickLane(axis, value) {
    state.chipBandOpen = false;
    if (axis === 'AGENDA') {
      var want = value === 'on';
      if (want !== !!state.agendaPreset) toggleAgendaPreset();
      else renderAll();
      return;
    }
    if (axis === 'TOSU') {
      if (state.lane !== value) {
        state.lane = value;
        markAgendaDiverged();
      }
      renderAll();
      return;
    }
    if (axis === 'DONE') {
      var show = value === 'show';
      if (show !== !!state.showDone) {
        state.showDone = show;
        setDoneExclude(!show);
        markAgendaDiverged();
      }
      renderAll();
      return;
    }
    if (axis === 'BLOCKS') {
      var showB = value === 'show';
      if (showB !== !!state.showBlocked) {
        state.showBlocked = showB;
        markAgendaDiverged();
      }
      renderAll();
      return;
    }
    if (axis === 'TEST') {
      var on = value === 'on';
      if (on !== !!state.sightTest) toggleSightTest();
      else renderAll();
    }
  }

  function emptyAxisMaps() {
    return { status: [], sched: [], domain: [], project: [] };
  }

  function selectionFromMaps(include, exclude) {
    var sel = [];
    FILTER_FIELDS.forEach(function (f) {
      (include[f] || []).forEach(function (v) {
        sel.push({ field: f, value: v, mode: 'include' });
      });
    });
    FILTER_FIELDS.forEach(function (f) {
      (exclude[f] || []).forEach(function (v) {
        sel.push({ field: f, value: v, mode: 'exclude' });
      });
    });
    return sel;
  }

  /* Keep include/exclude maps derived from ordered selection (filter apply path). */
  function syncMapsFromSelection() {
    state.include = emptyAxisMaps();
    state.exclude = emptyAxisMaps();
    state.selection.forEach(function (e) {
      if (!e || !e.field || e.value == null) return;
      var bucket = e.mode === 'exclude' ? state.exclude : state.include;
      if (!bucket[e.field]) return;
      if (bucket[e.field].indexOf(e.value) < 0) bucket[e.field].push(e.value);
    });
  }

  function findSelectionIndex(field, value) {
    for (var i = 0; i < state.selection.length; i++) {
      if (state.selection[i].field === field && state.selection[i].value === value) return i;
    }
    return -1;
  }

  function lastIncludeIndex() {
    var last = -1;
    for (var i = 0; i < state.selection.length; i++) {
      if (state.selection[i].mode === 'include') last = i;
    }
    return last;
  }

  /* Stable includes-then-excludes: after any mutation, partition without scrambling
     relative order inside each mode group. */
  function hardenSelectionOrder() {
    var inc = [];
    var exc = [];
    state.selection.forEach(function (e) {
      if (e.mode === 'exclude') exc.push(e);
      else inc.push(e);
    });
    state.selection = inc.concat(exc);
  }

  function clearSelection() {
    state.selection = [];
    syncMapsFromSelection();
  }

  function setDoneExclude(on) {
    var idx = findSelectionIndex('status', 'done');
    if (on) {
      if (idx >= 0) {
        state.selection[idx].mode = 'exclude';
      } else {
        state.selection.push({ field: 'status', value: 'done', mode: 'exclude' });
      }
      hardenSelectionOrder();
    } else if (idx >= 0) {
      state.selection.splice(idx, 1);
    }
    syncMapsFromSelection();
  }

  function chipState(field, value) {
    if (state.exclude[field].indexOf(value) >= 0) return 'exclude';
    if (state.include[field].indexOf(value) >= 0) return 'include';
    return 'none';
  }

  function globalMode(value) {
    if (value === 'tosu') {
      if (state.lane === 'tosu') return 'include';
      if (state.lane === 'agent') return 'exclude';
      return 'none';
    }
    if (value === 'done') return state.doneMode === 'include' || state.doneMode === 'exclude' ? state.doneMode : 'none';
    if (value === 'blocks') return state.blocksMode === 'include' || state.blocksMode === 'exclude' ? state.blocksMode : 'none';
    if (value === 'remove') return state.removeMode === 'include' || state.removeMode === 'exclude' ? state.removeMode : 'none';
    if (value === 'test') return state.testMode === 'include' || state.testMode === 'exclude' ? state.testMode : 'none';
    return 'none';
  }

  function clearDoneExcludeOnly() {
    var idx = findSelectionIndex('status', 'done');
    if (idx >= 0 && state.selection[idx].mode === 'exclude') {
      state.selection.splice(idx, 1);
      syncMapsFromSelection();
    }
  }

  /* GLOBAL values use the same include → exclude → clear cycle. Not on/off. */
  function applyGlobalMode(value, mode) {
    if (value === 'tosu') {
      state.lane = mode === 'include' ? 'tosu' : mode === 'exclude' ? 'agent' : 'all';
    } else if (value === 'done') {
      if (mode === 'include') {
        state.doneMode = 'include';
        state.showDone = true;
        clearDoneExcludeOnly();
      } else if (mode === 'exclude') {
        state.doneMode = 'exclude';
        state.showDone = false;
        setDoneExclude(true);
      } else {
        state.doneMode = 'none';
        state.showDone = true;
        clearDoneExcludeOnly();
      }
    } else if (value === 'blocks') {
      if (mode === 'include') {
        state.blocksMode = 'include';
        state.showBlocked = true;
      } else if (mode === 'exclude') {
        state.blocksMode = 'exclude';
        state.showBlocked = false;
      } else {
        state.blocksMode = 'none';
        state.showBlocked = true;
      }
    } else if (value === 'remove') {
      state.removeMode = mode === 'include' ? 'include' : mode === 'exclude' ? 'exclude' : 'none';
    } else if (value === 'test') {
      if (mode === 'include') {
        state.testMode = 'include';
        if (!state.sightTest) setSightTest(true);
      } else {
        state.testMode = mode === 'exclude' ? 'exclude' : 'none';
        if (state.sightTest) setSightTest(false);
      }
    }
    markAgendaDiverged();
    state.chipBandOpen = false;
  }

  function syncRemoveFromStatusChip() {
    /* STATUS:remove include is "also this status": un-hide REMOVE cards; otherwise keep them hidden. */
    state.removeMode = chipState('status', 'remove') === 'include' ? 'none' : 'exclude';
  }

  function syncShowDoneFromStatusChip() {
    /* STATUS:done include is "also this status", not GLOBAL only-done. */
    var st = chipState('status', 'done');
    if (st === 'include') {
      state.showDone = true;
      if (state.doneMode === 'exclude') state.doneMode = 'none';
    } else if (st === 'exclude') {
      state.showDone = false;
      state.doneMode = 'exclude';
    } else {
      state.showDone = false;
      state.doneMode = 'exclude';
    }
  }

  /* none → include → exclude → none.
     Selection chain stays includes-then-excludes; include→exclude updates in place
     then moves only as far as the exclude block requires (append within excludes). */
  function cycleChip(field, value) {
    if (field === 'global') {
      var curG = globalMode(value);
      var nextG = curG === 'none' ? 'include' : curG === 'include' ? 'exclude' : 'none';
      applyGlobalMode(value, nextG);
      renderAll();
      return;
    }
    var idx = findSelectionIndex(field, value);
    if (idx < 0) {
      var entry = { field: field, value: value, mode: 'include' };
      var li = lastIncludeIndex();
      state.selection.splice(li + 1, 0, entry);
    } else if (state.selection[idx].mode === 'include') {
      var flip = state.selection[idx];
      flip.mode = 'exclude';
      state.selection.splice(idx, 1);
      state.selection.push(flip); /* end of exclude block */
    } else {
      state.selection.splice(idx, 1);
    }
    hardenSelectionOrder();
    syncMapsFromSelection();
    if (field === 'status' && value === 'done') syncShowDoneFromStatusChip();
    if (field === 'status' && value === 'remove') syncRemoveFromStatusChip();
    markAgendaDiverged();
    state.chipBandOpen = false; /* collapse value submenu after pick */
    renderAll();
  }

  /* Shortcut: jump straight to exclude (alt/shift/right-click/long-press) */
  function jumpExclude(field, value) {
    if (field === 'global') {
      applyGlobalMode(value, 'exclude');
      renderAll();
      return;
    }
    var idx = findSelectionIndex(field, value);
    if (idx >= 0) {
      if (state.selection[idx].mode === 'exclude') {
        /* already excluded — leave position */
      } else {
        var flip = state.selection[idx];
        flip.mode = 'exclude';
        state.selection.splice(idx, 1);
        state.selection.push(flip);
      }
    } else {
      state.selection.push({ field: field, value: value, mode: 'exclude' });
    }
    hardenSelectionOrder();
    syncMapsFromSelection();
    if (field === 'status' && value === 'done') syncShowDoneFromStatusChip();
    if (field === 'status' && value === 'remove') syncRemoveFromStatusChip();
    markAgendaDiverged();
    state.chipBandOpen = false;
    renderAll();
  }

  function bindChipGestures(btn, field, value) {
    var longPressed = false;
    btn.addEventListener('click', function (ev) {
      ev.preventDefault();
      if (longPressed) { longPressed = false; return; }
      /* Alt/Option/Shift/Meta = jump to exclude (cycle is the documented path) */
      if (ev.altKey || ev.shiftKey || ev.metaKey) {
        jumpExclude(field, value);
        flashExclude(btn);
        return;
      }
      cycleChip(field, value);
    });
    btn.addEventListener('contextmenu', function (ev) {
      ev.preventDefault();
      jumpExclude(field, value);
      flashExclude(btn);
    });

    var timer = null;
    var moved = false;
    btn.addEventListener('touchstart', function () {
      moved = false;
      longPressed = false;
      timer = setTimeout(function () {
        timer = null;
        longPressed = true;
        jumpExclude(field, value);
        flashExclude(btn);
      }, LONG_PRESS_MS);
    }, { passive: true });
    btn.addEventListener('touchmove', function () {
      moved = true;
      if (timer) { clearTimeout(timer); timer = null; }
    }, { passive: true });
    btn.addEventListener('touchend', function (ev) {
      if (timer) {
        clearTimeout(timer);
        timer = null;
      } else if (longPressed) {
        ev.preventDefault();
      }
    });
    btn.addEventListener('touchcancel', function () {
      if (timer) { clearTimeout(timer); timer = null; }
    });
  }

  function flashExclude(btn) {
    btn.classList.add('flash-exclude');
    setTimeout(function () { btn.classList.remove('flash-exclude'); }, 280);
  }

  function renderChips() {
    var band = el('chip-band');
    band.innerHTML = '';
    band.setAttribute('role', 'group');
    band.setAttribute('aria-label', 'Values for ' + state.activeAxis);

    if (SPECIAL_AXES[state.activeAxis] || !state.chipBandOpen) {
      band.setAttribute('data-empty', '1');
      band.hidden = true;
      /* TIMERS / closed: no value submenu */
      return;
    }
    band.hidden = false;
    band.removeAttribute('data-empty');

    if (state.activeAxis === 'GLOBAL') {
      band.setAttribute('aria-label', 'Values for GLOBAL');
      GLOBAL_VALUES.forEach(function (value) {
        var st = globalMode(value);
        var b = document.createElement('button');
        b.type = 'button';
        b.className = 'chip' + (st === 'include' ? ' chip--include' : '') + (st === 'exclude' ? ' chip--exclude' : '');
        b.setAttribute('aria-pressed', st !== 'none' ? 'true' : 'false');
        b.setAttribute('data-filter-state', st);
        var stateHint = st === 'exclude' ? 'excluded' : st === 'include' ? 'included' : 'off';
        b.setAttribute('aria-label', value + ' (' + stateHint + ') — cycle include, exclude, clear');
        b.title = 'Cycle: off → include → exclude → off';
        b.textContent = value;
        bindChipGestures(b, 'global', value);
        band.appendChild(b);
      });
      /* all — binary toggle next to the test pill: snapshot filters, clear all,
         show full inventory; restores previous filters on toggle-off */
      var allChip = document.createElement('button');
      allChip.type = 'button';
      allChip.id = 'sight-all-chip';
      allChip.className = 'chip chip--toggle' + (state.showAll ? ' chip--include' : ' chip--off');
      allChip.setAttribute('aria-pressed', state.showAll ? 'true' : 'false');
      allChip.textContent = 'all';
      allChip.title = state.showAll
        ? 'Showing everything — click to restore previous filters'
        : 'Show all cards — clears all filters (restores them on toggle-off)';
      allChip.setAttribute('aria-label', allChip.title);
      allChip.addEventListener('click', function () { toggleShowAll(); });
      band.appendChild(allChip);
      return;
    }

    var laneVals = laneChoices(state.activeAxis);
    if (laneVals) {
      band.setAttribute('aria-label', 'Values for ' + state.activeAxis);
      laneVals.forEach(function (opt) {
        var b = document.createElement('button');
        b.type = 'button';
        b.className = 'chip' + (opt.on ? ' chip--include' : '');
        b.setAttribute('aria-pressed', opt.on ? 'true' : 'false');
        b.textContent = opt.label;
        b.addEventListener('click', function () { pickLane(state.activeAxis, opt.value); });
        band.appendChild(b);
      });
      return;
    }

    var field = FILTER_AXES[state.activeAxis];
    var values = valuesForAxis(state.activeAxis);
    values.forEach(function (value) {
      var st = chipState(field, value);
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'chip' + (st === 'include' ? ' chip--include' : '') + (st === 'exclude' ? ' chip--exclude' : '');
      btn.setAttribute('aria-pressed', st !== 'none' ? 'true' : 'false');
      btn.setAttribute('data-filter-state', st);
      var stateHint = st === 'exclude' ? 'excluded' : st === 'include' ? 'included' : 'off';
      btn.setAttribute('aria-label', value + ' (' + stateHint + ') — cycle include, exclude, clear');
      btn.title = 'Cycle: off → include → exclude → off';
      btn.textContent = value;
      bindChipGestures(btn, field, value);
      band.appendChild(btn);
    });
  }

  function renderSummary() {
    var box = el('filter-summary');
    box.innerHTML = '';
    var any = false;
    /* Walk ordered selection (includes then excludes) — do not rebuild from map keys */
    state.selection.forEach(function (entry) {
      any = true;
      var f = entry.field;
      var v = entry.value;
      var label = FIELD_LABEL[f] || String(f).toUpperCase();
      var s = document.createElement('button');
      s.type = 'button';
      s.className = 'chip ' + (entry.mode === 'exclude' ? 'chip--exclude' : 'chip--include');
      s.textContent = label + ':' + v;
      s.title = entry.mode === 'exclude'
        ? 'Cycle: exclude → clear'
        : 'Cycle: include → exclude → clear';
      s.setAttribute('aria-label', 'Cycle filter ' + label + ':' + v);
      s.addEventListener('click', function () {
        cycleChip(f, v);
      });
      box.appendChild(s);
    });
    syncChromeHint();
    if (!any) {
      /* empty — hint/count live in chrome-tools */
    } else {
      var clear = document.createElement('button');
      clear.type = 'button';
      clear.className = 'chip chip--clear';
      clear.textContent = 'clear';
      clear.title = 'Clear all axis filters';
      clear.addEventListener('click', function () {
        clearSelection();
        markAgendaDiverged();
        renderAll();
      });
      box.appendChild(clear);
    }
  }

  function statusPillClass(status) {
    var s = String(status || 'later').toLowerCase();
    var map = {
      urgent: 'status-pill status-pill--accent status-pill--urgent',
      now: 'status-pill status-pill--green',
      today: 'status-pill status-pill--green',
      progress: 'status-pill status-pill--azure status-pill--progress',
      sched: 'status-pill status-pill--azure',
      deferred: 'status-pill status-pill--deferred',
      later: 'status-pill status-pill--later',
      done: 'status-pill status-pill--muted',
      remove: 'status-pill status-pill--muted status-pill--remove'
    };
    return map[s] || 'status-pill status-pill--muted';
  }

  /* isTimersFeed defined in sight timer block */


  /* ---------- sight timer phase track (UD lock A — 260930-sight-timer-design §4–§6) ---------- */
  var TIMER_LEAD_MS = 60 * 60 * 1000;      /* UD-2 A */
  var TIMER_AMBER_MS = 10 * 60 * 1000;     /* UD-4 A */
  var TIMER_GRACE_MS = 0;                  /* UD-6 A point-event */
  var TIMER_TICK_MS = 1000;
  var _timerTickId = null;
  var _timerLastAnnounce = {};

  function fullYear(yy) {
    var y = Number(yy);
    if (y < 100) return 2000 + y;
    return y;
  }

  function cardStartMs(c) {
    var p = c.datetime_parts;
    if (!p) return null;
    var mins = c.time_mins != null ? c.time_mins : 0; /* UD-1 A midnight */
    return new Date(
      fullYear(p.y), p.m, p.day,
      Math.floor(mins / 60), mins % 60, 0, 0
    ).getTime();
  }

  function cardDurationMin(c) {
    if (c.duration == null || c.duration === '') return null;
    var n = parseInt(c.duration, 10);
    return (isNaN(n) || n <= 0) ? null : n;
  }

  function clamp01(x) {
    if (x < 0) return 0;
    if (x > 1) return 1;
    return x;
  }

  function formatApproxRemain(ms) {
    var s = Math.max(0, Math.round(ms / 1000));
    if (s < 60) return '~' + s + 's';
    var m = Math.round(s / 60);
    if (m < 60) return '~' + m + 'm';
    var h = Math.floor(m / 60);
    var rm = m % 60;
    return rm ? '~' + h + 'h ' + rm + 'm' : '~' + h + 'h';
  }

  /* Returns null (no timer) or { phase, band, fill, labelKey, labelText, ariaNow, ariaMax } */
  function computeTimerPhase(c, now) {
    now = now != null ? now : Date.now();
    if (!c || c.id === 'root' || c.is_root) return null;
    if (c.status === 'done') return null;
    if (!c.datetime_parts) return null;
    /* timed bake flag; sched+datetime still counts if export lagged */
    if (!(c.timed || c.status === 'sched')) return null;

    var start = cardStartMs(c);
    if (start == null) return null;
    var durMin = cardDurationMin(c);
    var durMs = durMin != null ? durMin * 60000 : null;
    var end = durMs != null ? start + durMs : null;

    if (now < start) {
      var until = start - now;
      if (until > TIMER_LEAD_MS) {
        return { phase: 'hidden', band: 'azure', fill: 0, labelKey: '', labelText: '', reason: 'before-lead' };
      }
      var fill = clamp01(1 - (until / TIMER_LEAD_MS));
      var band = until <= TIMER_AMBER_MS ? 'amber' : 'azure';
      return {
        phase: 'lead-up',
        band: band,
        fill: fill,
        labelKey: 'until',
        labelText: 'until ' + formatApproxRemain(until),
        ariaNow: Math.round(fill * 100),
        ariaMax: 100,
        start: start,
        end: end
      };
    }

    /* at or past start */
    if (durMs == null) {
      /* UD-6 A: point event → overdue immediately after start (+ grace 0) */
      var overPt = now - (start + TIMER_GRACE_MS);
      if (overPt < 0) {
        return {
          phase: 'in-progress',
          band: 'green',
          fill: 1,
          labelKey: 'at',
          labelText: 'at',
          ariaNow: 100,
          ariaMax: 100,
          start: start,
          end: start
        };
      }
      return {
        phase: 'overdue',
        band: 'fuchsia',
        fill: 1,
        labelKey: 'over',
        labelText: 'over ' + formatApproxRemain(overPt),
        ariaNow: 100,
        ariaMax: 100,
        start: start,
        end: start,
        pastEnd: true
      };
    }

    if (now < end) {
      var elapsed = now - start;
      var left = end - now;
      var violetMs = Math.max(5 * 60 * 1000, 0.2 * durMs); /* UD-5 A */
      var bandIP = left <= violetMs ? 'violet' : 'green';
      var fillIP = clamp01(elapsed / durMs);
      return {
        phase: 'in-progress',
        band: bandIP,
        fill: fillIP,
        labelKey: 'left',
        labelText: 'left ' + formatApproxRemain(left),
        ariaNow: Math.round(fillIP * 100),
        ariaMax: 100,
        start: start,
        end: end
      };
    }

    var over = now - end;
    return {
      phase: 'overdue',
      band: 'fuchsia',
      fill: 1,
      labelKey: 'over',
      labelText: 'over ' + formatApproxRemain(over),
      ariaNow: 100,
      ariaMax: 100,
      start: start,
      end: end,
      pastEnd: true
    };
  }

  function timerIsVisible(ph) {
    return !!(ph && ph.phase && ph.phase !== 'hidden');
  }

  function isTimersFeed(card) {
    /* UD-7 A: lead ∪ active ∪ overdue (never auto-hide overdue — UD-8 A) */
    return timerIsVisible(computeTimerPhase(card));
  }

  function paintTimerEl(wrap, ph) {
    if (!wrap || !ph) return;
    wrap.setAttribute('data-phase', ph.phase);
    wrap.setAttribute('data-band', ph.band);
    wrap.className = 'sight-timer sight-timer--' + ph.band +
      (ph.pastEnd ? ' sight-timer--past-end' : '');
    var pct = Math.round(clamp01(ph.fill) * 1000) / 10;
    var past = wrap.querySelector('.sight-timer-past');
    var mark = wrap.querySelector('.sight-timer-mark');
    var label = wrap.querySelector('.sight-timer-label');
    var track = wrap.querySelector('.sight-timer-track');
    if (past) past.style.width = pct + '%';
    if (mark) mark.style.left = pct + '%';
    if (label) {
      label.textContent = ph.labelText;
      /* Clamp label box inside wrap (~0.25em inset); mark/fill keep true pct. */
      var wrapW = wrap.clientWidth || wrap.offsetWidth || 0;
      var labelW = label.offsetWidth || 0;
      var fs = parseFloat(window.getComputedStyle(label).fontSize) || 10;
      var marginPx = 0.25 * fs;
      if (wrapW > 0 && labelW > 0) {
        var half = labelW / 2;
        var lo = half + marginPx;
        var hi = wrapW - half - marginPx;
        var idealX = (pct / 100) * wrapW;
        var clamped;
        if (hi <= lo) clamped = wrapW / 2;
        else clamped = Math.max(lo, Math.min(hi, idealX));
        label.style.left = clamped + 'px';
      } else {
        label.style.left = pct + '%';
      }
    }
    if (track) {
      track.setAttribute('aria-valuenow', String(ph.ariaNow != null ? ph.ariaNow : Math.round(pct)));
      track.setAttribute('aria-valuetext', ph.labelText);
    }
    /* Threshold announce (not every tick) */
    var id = wrap.getAttribute('data-card-id') || '';
    var key = ph.phase + ':' + ph.band;
    if (id && _timerLastAnnounce[id] !== key) {
      var prev = _timerLastAnnounce[id];
      _timerLastAnnounce[id] = key;
      if (prev && (ph.band === 'amber' || ph.band === 'violet' || ph.phase === 'overdue' ||
          (ph.phase === 'in-progress' && String(prev).indexOf('lead') === 0))) {
        var st = el('board-status');
        if (st) {
          st.textContent = (id + ' · ' + ph.labelText);
          clearTimeout(paintTimerEl._ann);
          paintTimerEl._ann = setTimeout(function () {
            if (st.textContent.indexOf(id) === 0) st.textContent = '';
          }, 2400);
        }
      }
    }
  }

  function buildTimerEl(card, ph) {
    var wrap = document.createElement('div');
    wrap.className = 'sight-timer';
    wrap.setAttribute('data-card-id', card.id || '');
    var track = document.createElement('div');
    track.className = 'sight-timer-track';
    track.setAttribute('role', 'progressbar');
    track.setAttribute('aria-valuemin', '0');
    track.setAttribute('aria-valuemax', '100');
    track.setAttribute('aria-label', 'Timer for ' + (card.title || card.id || 'task'));
    var dotS = document.createElement('span');
    dotS.className = 'sight-timer-dot sight-timer-dot--start';
    dotS.setAttribute('aria-hidden', 'true');
    var past = document.createElement('div');
    past.className = 'sight-timer-past';
    past.setAttribute('aria-hidden', 'true');
    var mark = document.createElement('span');
    mark.className = 'sight-timer-mark';
    mark.setAttribute('aria-hidden', 'true');
    var dotE = document.createElement('span');
    dotE.className = 'sight-timer-dot sight-timer-dot--end';
    dotE.setAttribute('aria-hidden', 'true');
    track.appendChild(dotS);
    track.appendChild(past);
    track.appendChild(mark);
    track.appendChild(dotE);
    var label = document.createElement('div');
    label.className = 'sight-timer-label';
    label.setAttribute('role', 'timer');
    label.setAttribute('aria-live', 'off');
    wrap.appendChild(track);
    wrap.appendChild(label);
    paintTimerEl(wrap, ph);
    return wrap;
  }

  function appendTimerIfVisible(main, card) {
    var ph = computeTimerPhase(card);
    if (!timerIsVisible(ph)) return;
    main.appendChild(buildTimerEl(card, ph));
  }

  function updateVisibleTimerBars() {
    var now = Date.now();
    var membershipDirty = false;
    document.querySelectorAll('.board-row[data-id]').forEach(function (row) {
      var id = row.getAttribute('data-id');
      var card = state.byId[id];
      if (!card) return;
      var ph = computeTimerPhase(card, now);
      var next = timerIsVisible(ph) ? ph.phase : '';
      var was = row.getAttribute('data-timer-phase') || '';
      if (was !== next) membershipDirty = true;
      row.setAttribute('data-timer-phase', next);
      var wrap = row.querySelector('.sight-timer');
      var main = row.querySelector('.card-main');
      if (!timerIsVisible(ph)) {
        if (wrap) wrap.remove();
        return;
      }
      if (!wrap && main) {
        wrap = buildTimerEl(card, ph);
        var notes = main.querySelector('.card-notes');
        if (notes) main.insertBefore(wrap, notes);
        else main.appendChild(wrap);
      } else if (wrap) {
        paintTimerEl(wrap, ph);
      }
    });
    if (membershipDirty && state.activeAxis === 'TIMERS') {
      renderListBody();
    }
  }

  function ensureTimerTick() {
    if (_timerTickId != null) return;
    _timerTickId = setInterval(function () {
      if (document.hidden) return;
      updateVisibleTimerBars();
    }, TIMER_TICK_MS);
  }

  function showToast(msg) {
    var t = document.getElementById('board-toast');
    if (!t) {
      t = document.createElement('div');
      t.id = 'board-toast';
      t.className = 'board-toast';
      t.setAttribute('role', 'status');
      t.setAttribute('aria-live', 'polite');
      document.body.appendChild(t);
    }
    t.textContent = msg;
    t.classList.add('is-visible');
    clearTimeout(showToast._timer);
    showToast._timer = setTimeout(function () {
      t.classList.remove('is-visible');
    }, 2400);
  }

  function rebuildById() {
    state.byId = {};
    state.cards.forEach(function (c) {
      if (c.id) state.byId[c.id] = c;
    });
  }

  function clearAllFilters() {
    clearSelection();
    state.lane = 'all';
    state.chipBandOpen = false;
    state.activeAxis = 'STATUS';
  }

  function focusCard(id, opts) {
    opts = opts || {};
    if (!id) return;
    if (opts.record) {
      state.viewPlane = 'tasks';
      rememberNav({ plane: 'tasks', plot: '', parcel: '', card: id });
      syncViewUrl();
    }
    var card = state.byId[id];
    if (!card) {
      showToast('No card ' + id + ' in this plane');
      return;
    }
    var visible = filteredCards().some(function (c) { return c.id === id; });
    if (!visible) {
      /* Reveal: clear filters, show blocked; diverge agenda (keep custom latch) */
      clearAllFilters();
      markAgendaDiverged();
      state.showBlocked = true;
      if (state.blocksMode !== 'include' || !card.blocked) state.blocksMode = 'none';
      if (card.status === 'remove' || state.removeMode === 'include') state.removeMode = 'none';
      if (card.status === 'done' || state.doneMode === 'include') {
        state.showDone = true;
        if (card.status !== 'done' || state.doneMode === 'exclude') state.doneMode = 'none';
        setDoneExclude(false);
      }
      if (state.testMode === 'exclude' && card.tags && card.tags.indexOf(SIGHT_TEST_TAG) >= 0) {
        state.testMode = 'none';
      }
      state.pendingFocusId = id;
      showToast('Cleared filters to reveal ' + id);
      renderAll();
      return;
    }
    state.pendingFocusId = null;
    var row = document.getElementById('card-' + id);
    if (!row) {
      state.pendingFocusId = id;
      renderAll();
      return;
    }
    document.querySelectorAll('.board-row.is-focused').forEach(function (el) {
      el.classList.remove('is-focused');
    });
    row.classList.add('is-focused');
    row.setAttribute('tabindex', '-1');
    try { row.focus({ preventScroll: true }); } catch (e) { row.focus(); }
    if (opts.instant) jumpToEl(row);
    else row.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }

  function appendTag(tags, text, className) {
    var d = document.createElement('span');
    d.className = className || 'tag-meta';
    d.textContent = text;
    tags.appendChild(d);
  }

  /* Claim sits as a quiet line under the task title — not a pill. */
  function appendClaimLine(main, card) {
    if (!card.field_links || !card.field_links.length) return;
    var line = document.createElement('div');
    line.className = 'claim-line';
    card.field_links.forEach(function (fid) {
      var label = parcelLabel(fid);
      var fl = document.createElement('button');
      fl.type = 'button';
      fl.className = 'claim-line-link';
      fl.textContent = label;
      fl.title = label;
      fl.setAttribute('aria-label', 'Open field parcel ' + label);
      fl.addEventListener('click', function (ev) {
        ev.preventDefault();
        ev.stopPropagation();
        clearSearchForReveal();
        var parcel = resolveParcel(fid);
        openSplit(
          { plane: 'tasks', plot: '', parcel: '', card: card.id || '' },
          { plane: 'field', plot: parcel ? parcelArea(parcel) : '', parcel: parcel ? parcel.id : fid, card: '' }
        );
      });
      line.appendChild(fl);
    });
    main.appendChild(line);
  }

  function renderCard(card) {
    var li = document.createElement('li');
    li.className = 'board-row';
    li.id = 'card-' + (card.id || 'unknown');
    li.setAttribute('data-id', card.id || '');
    li.setAttribute('data-status', card.status || 'later');
    if (card.overdue) li.setAttribute('data-overdue', 'true');
    var stripLabel = card.overdue
      ? ('status: ' + (card.status || 'later') + ' (overdue)')
      : ('status: ' + (card.status || 'later'));
    li.title = stripLabel;
    li.setAttribute('aria-label', (card.title || '(untitled)') + ' — ' + stripLabel);

    var main = document.createElement('div');
    main.className = 'card-main';

    var title = document.createElement('h3');
    title.className = 'row-title heading';
    title.textContent = card.title || '(untitled)';
    main.appendChild(title);
    appendClaimLine(main, card);

    /* Top-right corner: status + ID (outside meta pill flow) */
    var corner = document.createElement('div');
    corner.className = 'card-corner';

    var pill = document.createElement('span');
    pill.className = statusPillClass(card.status);
    if (card.overdue) {
      pill.className = 'status-pill status-pill--accent status-pill--urgent';
    }
    pill.textContent = card.status || 'later';
    corner.appendChild(pill);

    var idBtn = document.createElement('button');
    idBtn.type = 'button';
    idBtn.className = 'row-id id-pill';
    idBtn.textContent = card.id || '?';
    idBtn.title = 'Focus ' + (card.id || '');
    idBtn.setAttribute('aria-label', 'Task id ' + (card.id || ''));
    idBtn.addEventListener('click', function (ev) {
      ev.preventDefault();
      focusCard(card.id, { record: true, instant: true });
    });
    corner.appendChild(idBtn);
    main.appendChild(corner);

    /* Meta pills: spatial row under title (not in status/ID column) */
    var chipRow = document.createElement('div');
    chipRow.className = 'card-chip-row';

    var tags = document.createElement('div');
    tags.className = 'card-tags';

    if (card.due_today) appendTag(tags, 'due today', 'tag-meta tag-meta--mark');
    if (card.overdue) appendTag(tags, 'overdue', 'tag-meta tag-meta--overdue');
    /* timed flag collapsed into timer/sched viz — don't dual-tag */
    if (card.datetime || card.time) {
      var schedBits = [];
      if (card.datetime) schedBits.push(card.datetime);
      if (card.time) schedBits.push(card.time);
      appendTag(tags, schedBits.join(' '), 'tag-meta tag-meta--mark');
    }
    if (card.domain) appendTag(tags, card.domain, 'tag-meta tag-meta--domain');
    if (card.project && String(card.project) !== String(card.domain)) {
      appendTag(tags, card.project, 'tag-meta tag-meta--project');
    }

    (card.tags || []).forEach(function (tg) {
      if (!tg || tg === 'task' || tg === 'tosu' || tg === 'timer') return;
      if (tg === card.domain || tg === card.project) return;
      appendTag(tags, tg);
    });

    if (card.blockers_pending && card.blockers_pending.length) {
      card.blockers_pending.forEach(function (bid) {
        var bl = document.createElement('button');
        bl.type = 'button';
        bl.className = 'blocker-link';
        bl.textContent = bid;
        bl.title = 'Jump to blocker ' + bid;
        bl.setAttribute('aria-label', 'Jump to blocker ' + bid);
        bl.addEventListener('click', function (ev) {
          ev.preventDefault();
          ev.stopPropagation();
          focusCard(bid, { record: true, instant: true });
        });
        tags.appendChild(bl);
      });
    }
    if (card.tosu) appendTag(tags, 'tosu', 'tag-meta tag-meta--tosu');

    if (tags.childNodes.length) {
      chipRow.appendChild(tags);
      main.appendChild(chipRow);
    }
    var tPh = computeTimerPhase(card);
    if (timerIsVisible(tPh)) {
      li.setAttribute('data-timer-phase', tPh.phase);
      main.appendChild(buildTimerEl(card, tPh));
    } else {
      li.setAttribute('data-timer-phase', '');
    }

    /* Tos u notes only when bake has non-empty notes — never placeholders */
    if (card.tosu) {
      var noteText = (card.notes && String(card.notes).trim()) ||
        (card.notes_excerpt && String(card.notes_excerpt).trim()) || '';
      if (noteText) {
        var notesEl = document.createElement('p');
        notesEl.className = 'card-notes card-notes--tosu';
        setNotesHtml(notesEl, noteText);
        main.appendChild(notesEl);
        /* Excerpt-only bake: silent peek for full body; omit chrome if still empty */
        if (!(card.notes && String(card.notes).trim()) && card.id) {
          peekNotes(card, main, null, notesEl, true);
        }
      }
      /* absent / whitespace notes → no element, no peek, no copy */
    }

    li.appendChild(main);
    return li;
  }

  function peekNotes(card, main, btn, notesEl, silent) {
    if (!card || !card.id || !card.tosu) return;
    if (card._notesPeeking) return;
    card._notesPeeking = true;
    if (btn) {
      btn.disabled = true;
      btn.textContent = '…';
    }
    var memNotes = (window.__SIGHT_PLANE__ && window.__SIGHT_PLANE__.notes)
      ? window.__SIGHT_PLANE__.notes[card.id] : null;
    var notesPromise = memNotes != null
      ? Promise.resolve(String(memNotes))
      : fetchText('/board/notes/' + encodeURIComponent(card.id) + '.toml');
    notesPromise.then(function (text) {
      var notes = '';
      var lines = String(text).split(/\r?\n/);
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line.indexOf('notes') === 0 && line.indexOf('=') > 0) {
          var raw = line.slice(line.indexOf('=') + 1).trim();
          if ((raw.charAt(0) === '"' && raw.charAt(raw.length - 1) === '"') ||
              (raw.charAt(0) === "'" && raw.charAt(raw.length - 1) === "'")) {
            notes = raw.slice(1, -1).replace(/\\n/g, '\n').replace(/\\t/g, '\t')
              .replace(/\\"/g, '"').replace(/\\\\/g, '\\');
          } else {
            notes = raw;
          }
          break;
        }
      }
      card._notesPeeking = false;
      card.notes = notes || '';
      var cleaned = notes ? notes.replace(/^\n+|\n+$/g, '') : '';
      if (btn) btn.remove();
      if (!cleaned) {
        if (notesEl && notesEl.parentNode) notesEl.remove();
        return;
      }
      var target = notesEl;
      if (!target) {
        target = document.createElement('p');
        target.className = 'card-notes card-notes--tosu card-notes-peek';
        main.appendChild(target);
      } else {
        target.classList.add('card-notes-peek');
      }
      setNotesHtml(target, cleaned);
    }).catch(function (err) {
      card._notesPeeking = false;
      if (btn) {
        btn.disabled = false;
        btn.textContent = 'notes';
        btn.title = String(err && err.message ? err.message : err);
      }
      /* 404 / fail: remove empty notes node; no fallback copy */
      if (notesEl && notesEl.parentNode && !(notesEl.textContent || '').trim() &&
          !notesEl.querySelector('a')) {
        notesEl.remove();
      }
    });
  }

  function renderParcelCard(parcel) {
    var live = parcel.source === 'live';
    var li = document.createElement('li');
    li.className = 'board-row parcel-card';
    li.id = 'parcel-' + (parcel.id || 'unknown');
    li.setAttribute('data-id', parcel.id || '');
    if (live) {
      li.setAttribute('data-kind', 'parcel');
      if (parcel.plot) li.setAttribute('data-plot', parcel.plot);
      li.title = parcel.area ? ('parcel · ' + parcel.area) : 'parcel';
    } else {
      li.setAttribute('data-grain', parcel.grain || 'view');
      li.title = 'parcel: ' + (parcel.grain || 'view') + (parcel.route ? ' · ' + parcel.route : '');
    }
    li.setAttribute('aria-label', (parcel.title || '(untitled)') + ' — parcel');

    var main = document.createElement('div');
    main.className = 'card-main';

    var head = document.createElement('div');
    head.className = 'parcel-head';

    var title = document.createElement('h3');
    title.className = 'row-title heading parcel-claim';
    title.textContent = parcel.title || '(untitled)';
    head.appendChild(title);

    var corner = document.createElement('div');
    corner.className = 'card-corner';
    var pill = document.createElement('span');
    pill.className = 'status-pill status-pill--azure';
    pill.textContent = live ? 'parcel' : (parcel.grain || 'parcel');
    corner.appendChild(pill);
    var idBtn = document.createElement('button');
    idBtn.type = 'button';
    idBtn.className = 'row-id id-pill';
    idBtn.textContent = parcel.id || '?';
    idBtn.title = 'Focus ' + (parcel.id || '');
    idBtn.setAttribute('aria-label', 'Parcel id ' + (parcel.id || ''));
    idBtn.addEventListener('click', function (ev) {
      ev.preventDefault();
      focusParcel(parcel.id, { instant: true });
    });
    corner.appendChild(idBtn);
    head.appendChild(corner);
    main.appendChild(head);

    var chipRow = document.createElement('div');
    chipRow.className = 'card-chip-row';
    var tags = document.createElement('div');
    tags.className = 'card-tags';
    if (live) {
      /* Area is the human plot name. Never ord. */
      if (parcel.area) {
        var areaBtn = document.createElement('button');
        areaBtn.type = 'button';
        areaBtn.className = 'tag-meta tag-meta--mark tag-link';
        areaBtn.textContent = parcel.area;
        areaBtn.title = parcel.area;
        areaBtn.setAttribute('aria-label', 'Plot ' + parcel.area);
        areaBtn.addEventListener('click', function (ev) {
          ev.preventDefault();
          ev.stopPropagation();
          openFieldPlot(parcelArea(parcel));
        });
        tags.appendChild(areaBtn);
      }
      /* Parent plot id only. Not the plot's tags. Corner keeps this parcel's id. */
      if (parcel.plot) appendTag(tags, parcel.plot, 'tag-meta');
    } else {
      if (parcel.route) appendTag(tags, parcel.route, 'tag-meta tag-meta--mark');
      appendTag(tags, PARCEL_TEST_TAG, 'tag-meta');
    }
    /* tags are the parcel's own labels — muted, never destinations */
    (parcel.tags || []).forEach(function (tg) {
      if (!tg || tg === PARCEL_TEST_TAG || tg === SIGHT_TEST_TAG) return;
      appendTag(tags, tg, live ? 'tag-meta tag-meta--label' : 'tag-meta');
    });
    if (live) appendEdgeLinks(tags, parcel);
    if (parcel.task_links && parcel.task_links.length) {
      parcel.task_links.forEach(function (tid) {
        var label = taskLabel(tid);
        var tb = document.createElement('button');
        tb.type = 'button';
        tb.className = 'tag-meta tag-link';
        tb.textContent = label;
        tb.title = label;
        tb.setAttribute('aria-label', 'Focus task ' + label);
        tb.addEventListener('click', function (ev) {
          ev.preventDefault();
          ev.stopPropagation();
          clearSearchForReveal();
          openSplit(
            { plane: 'field', plot: state.fieldPlot || parcelArea(parcel), parcel: parcel.id, card: '' },
            { plane: 'tasks', plot: '', parcel: '', card: tid }
          );
        });
        tags.appendChild(tb);
      });
    }
    if (tags.childNodes.length) {
      chipRow.appendChild(tags);
      main.appendChild(chipRow);
    }

    var bodyText = (parcel.body && String(parcel.body).trim()) || '';
    if (bodyText) {
      var notesEl = document.createElement('p');
      notesEl.className = 'card-notes card-notes--tosu parcel-body';
      setNotesHtml(notesEl, bodyText);
      main.appendChild(notesEl);
    }

    li.appendChild(main);
    return li;
  }


  /* One plot table = one card. Corner: exactly this plot's id.
     Meta row: this plot's area pill, its own tags as muted labels, a parcel
     count (never member parcel ids), typed edges ref/up/cite as the only
     id links, then one time stamp. */
  function renderPlotCard(entry) {
    var li = document.createElement('li');
    li.className = 'board-row plot-card';
    var titleText = entry.title ? String(entry.title).trim() : '';
    var slug = entry.area ? String(entry.area).trim() : '';
    li.setAttribute('data-area', slug);
    li.setAttribute('data-plot', entry.id || '');
    li.tabIndex = 0;
    li.setAttribute('role', 'button');
    li.setAttribute('aria-label', (titleText || slug || 'plot') + ' — open parcels');
    var main = document.createElement('div');
    main.className = 'card-main';
    var title = document.createElement('h3');
    title.className = 'row-title heading';
    /* title key only — never framing, note, or the area slug */
    title.textContent = titleText;
    main.appendChild(title);
    /* Top-right: this plot's id only (identity, not a link chip). */
    var corner = document.createElement('div');
    corner.className = 'card-corner';
    if (entry.id) {
      var idEl = document.createElement('span');
      idEl.className = 'row-id id-pill plot-id';
      idEl.textContent = entry.id;
      idEl.title = 'Plot id ' + entry.id;
      idEl.setAttribute('aria-label', 'Plot id ' + entry.id);
      corner.appendChild(idEl);
      main.appendChild(corner);
    }
    var hintText = (entry.description && String(entry.description).trim()) || '';
    if (hintText) {
      var hintEl = document.createElement('p');
      hintEl.className = 'card-notes plot-hint';
      hintEl.textContent = hintText;
      main.appendChild(hintEl);
    }
    var chipRow = document.createElement('div');
    chipRow.className = 'card-chip-row';
    var tags = document.createElement('div');
    tags.className = 'card-tags';
    /* area pill: this plot's area only; skipped when it equals the heading */
    if (slug && slug !== titleText) appendTag(tags, slug, 'tag-meta tag-meta--mark plot-slug');
    /* this plot's own tags: muted labels, not destinations */
    (entry.tags || []).forEach(function (tg) {
      if (!tg) return;
      appendTag(tags, tg, 'tag-meta tag-meta--label');
    });
    /* parcel count only — member parcel ids stay off the index card */
    if (entry.parcelCount) {
      appendTag(tags, entry.parcelCount + (entry.parcelCount === 1 ? ' parcel' : ' parcels'),
        'tag-meta tag-meta--label plot-count');
    }
    appendEdgeLinks(tags, entry);
    function stampSlot(kind, raw) {
      var slot = document.createElement('span');
      var shown = raw ? formatHailStamp(raw) : '';
      if (!shown) return;
      slot.className = 'plot-stamp';
      slot.setAttribute('data-kind', kind);
      slot.textContent = shown;
      slot.title = kind + ' ' + raw;
      slot.setAttribute('aria-label', kind + ' ' + shown);
      tags.appendChild(slot);
    }
    /* one time: modified if present, else created */
    var mod = entry.modified && String(entry.modified).trim();
    var cre = entry.created && String(entry.created).trim();
    if (mod) stampSlot('modified', mod);
    else if (cre) stampSlot('created', cre);
    if (tags.childNodes.length) {
      chipRow.appendChild(tags);
      main.appendChild(chipRow);
    }
    li.appendChild(main);
    function open() { openFieldPlot(entry.key || entry.area || entry.id); }
    li.addEventListener('click', function () { open(); });
    li.addEventListener('keydown', function (ev) {
      if (ev.key === 'Enter' || ev.key === ' ') {
        ev.preventDefault();
        open();
      }
    });
    return li;
  }

  function parcelSearchHay(p) {
    return [p.title || '', p.claim || '', p.id || '', p.body || ''].join(' ').toLowerCase();
  }

  function matchesTerms(hay, terms) {
    for (var i = 0; i < terms.length; i++) {
      if (hay.indexOf(terms[i]) < 0) return false;
    }
    return true;
  }

  function focusPendingParcel() {
    if (!state.pendingParcelFocusId) return;
    var fid = state.pendingParcelFocusId;
    state.pendingParcelFocusId = null;
    var row = document.getElementById('parcel-' + fid);
    if (!row) return;
    document.querySelectorAll('.parcel-card.is-focused').forEach(function (el0) {
      el0.classList.remove('is-focused');
    });
    row.classList.add('is-focused');
    row.setAttribute('tabindex', '-1');
    try { row.focus({ preventScroll: true }); } catch (e) { /* ignore */ }
    jumpToEl(row);
  }

  /* Hail integer YYMMDDHHMM — wall time packed in the value, not an inject clock. */
  var HAIL_WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  var HAIL_MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /* YYMMDDHHMM wall time → "Fri Jul 20, 2057 at 12:32p". No CDN. */
  function formatHailStamp(raw) {
    var s = String(raw == null ? '' : raw).trim();
    if (!s) return '';
    var digits = s.replace(/\D/g, '');
    if (digits.length < 10) return s;
    digits = digits.slice(0, 10);
    var yy = parseInt(digits.slice(0, 2), 10);
    var mo = parseInt(digits.slice(2, 4), 10);
    var da = parseInt(digits.slice(4, 6), 10);
    var hh = parseInt(digits.slice(6, 8), 10);
    var mi = parseInt(digits.slice(8, 10), 10);
    if (!(mo >= 1 && mo <= 12 && da >= 1 && da <= 31 && hh >= 0 && hh <= 23 && mi >= 0 && mi <= 59)) return s;
    var year = 2000 + yy;
    var dt = new Date(Date.UTC(year, mo - 1, da));
    if (dt.getUTCFullYear() !== year || dt.getUTCMonth() !== mo - 1 || dt.getUTCDate() !== da) return s;
    var ap = hh >= 12 ? 'p' : 'a';
    var h12 = hh % 12;
    if (h12 === 0) h12 = 12;
    var mm = (mi < 10 ? '0' : '') + mi;
    return HAIL_WD[dt.getUTCDay()] + ' ' + HAIL_MON[mo - 1] + ' ' + da + ', ' + year + ' at ' + h12 + ':' + mm + ap;
  }

  function hailRank(raw) {
    if (raw == null || raw === '') return null;
    var n = Number(String(raw).trim());
    return isNaN(n) ? null : n;
  }

  var PLOT_SORTS = ['new', 'old', 'az', 'za'];
  var PLOT_SORT_LABEL = { new: 'newest', old: 'oldest', az: 'A-Z', za: 'Z-A' };

  function plotTimeRank(it) {
    if (!it) return null;
    var raw = (it.modified != null && String(it.modified).trim() !== '') ? it.modified : it.created;
    return hailRank(raw);
  }

  function sortPlotIndex(items) {
    var mode = PLOT_SORTS.indexOf(state.plotSort) >= 0 ? state.plotSort : 'new';
    var list = items.slice();
    if (mode === 'az' || mode === 'za') {
      var dir = mode === 'az' ? 1 : -1;
      list.sort(function (a, b) {
        var as = String((a && a.area) || '').toLowerCase();
        var bs = String((b && b.area) || '').toLowerCase();
        if (as < bs) return -1 * dir;
        if (as > bs) return 1 * dir;
        return 0;
      });
      return list;
    }
    var dated = [];
    var undated = [];
    list.forEach(function (it) {
      if (it && it.batch) dated.push(it);
      else if (plotTimeRank(it) != null) dated.push(it);
      else undated.push(it);
    });
    /* Batches (one injection each) stack by request time: newest first in
       'new', oldest first in 'old'. Inside a batch plots read top to bottom
       by authored batch_ord in both modes. created/modified only rank unbatched plots. */
    dated.sort(function (a, b) {
      var ab = a.batch || '';
      var bb = b.batch || '';
      if (ab && bb && ab !== bb) return mode === 'old' ? (ab < bb ? -1 : 1) : (ab < bb ? 1 : -1);
      if (ab && bb) {
        var ao = a.batch_ord == null ? 1e9 : a.batch_ord;
        var bo = b.batch_ord == null ? 1e9 : b.batch_ord;
        if (ao !== bo) return ao - bo;
        return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
      }
      var c = plotTimeRank(a) - plotTimeRank(b);
      return mode === 'old' ? c : -c;
    });
    return dated.concat(undated);
  }

  function cyclePlotSort() {
    var i = PLOT_SORTS.indexOf(state.plotSort);
    state.plotSort = PLOT_SORTS[(i < 0 ? 0 : i + 1) % PLOT_SORTS.length];
    renderAll();
  }

  function renderFieldPlane(body) {
    rebuildParcels();
    var parsed = parseSearch(state.searchQuery);
    var terms = parsed.terms || [];
    var index = state.fieldSource === 'live' ? fieldIndex() : [];
    var scanAll = parsed.planePrefix === 'F' && terms.length > 0;
    var mode = 'plots';
    var items = [];
    if (!index.length || scanAll) {
      mode = 'parcels';
      items = state.parcels.slice();
    } else if (state.fieldPlot) {
      mode = 'parcels';
      items = parcelsForArea(state.fieldPlot);
    } else {
      mode = 'plots';
      items = index.slice();
    }
    if (terms.length) {
      items = items.filter(function (item) {
        var hay = mode === 'plots'
          ? [item.area || '', item.title || '', item.description || '', item.id || '', (item.tags || []).join(' ')].join(' ').toLowerCase()
          : parcelSearchHay(item);
        return matchesTerms(hay, terms);
      });
    }
    if (mode === 'plots') items = sortPlotIndex(items);
    syncChromeCount(items);
    if (!items.length) {
      var empty = document.createElement('div');
      empty.className = 'empty-list';
      empty.textContent = state.parcels.length ? 'No matches.' : 'No parcels.';
      body.appendChild(empty);
      return;
    }
    var ul = document.createElement('ul');
    ul.className = 'card-list' + (mode === 'parcels' ? ' parcel-list' : '');
    ul.setAttribute('aria-label', mode === 'plots' ? 'Field plots' : 'Field parcels');
    items.forEach(function (item) {
      ul.appendChild(mode === 'plots' ? renderPlotCard(item) : renderParcelCard(item));
    });
    body.appendChild(ul);
    if (mode === 'parcels') focusPendingParcel();
  }

  function axisLabelsCompact() {
    return !!(window.matchMedia && window.matchMedia('(max-width: ' + MOBILE_BP + 'px)').matches);
  }

  function ingestPlaneTts(plane) {
    state.ttsByPlot = {};
    var tts = plane && plane.tts;
    if (!tts || typeof tts !== 'object') return;
    Object.keys(tts).forEach(function (k) {
      if (typeof tts[k] === 'string' && tts[k]) state.ttsByPlot[k] = tts[k];
    });
  }

  function ttsForOpenPlot() {
    var pid = plotIdForKey(state.fieldPlot || '');
    if (!pid) return '';
    var s = state.ttsByPlot && state.ttsByPlot[pid];
    return s ? String(s).replace(/\s+$/, '') : '';
  }

  function singleOpenPlot() {
    if (state.split) return false;
    if (state.viewPlane !== 'field') return false;
    if (!state.fieldPlot) return false;
    var parsed = parseSearch(state.searchQuery);
    if (parsed.planePrefix === 'F' && parsed.terms && parsed.terms.length) return false;
    return true;
  }

  var copyFlashTimer = null;
  function legacyCopyText(text) {
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.setAttribute('readonly', '');
    ta.style.position = 'fixed';
    ta.style.left = '-9999px';
    document.body.appendChild(ta);
    ta.select();
    var ok = false;
    try { ok = document.execCommand('copy'); } catch (eCopy) { ok = false; }
    ta.remove();
    return ok;
  }

  function copyRouteString(text, btn) {
    function flash() {
      btn.textContent = 'copied';
      if (copyFlashTimer) clearTimeout(copyFlashTimer);
      copyFlashTimer = setTimeout(function () {
        if (btn.isConnected) btn.textContent = 'copy';
      }, 1400);
    }
    function fail() {
      btn.textContent = 'copy';
      btn.title = 'Copy failed';
    }
    var clip = navigator.clipboard;
    if (clip && clip.writeText) {
      clip.writeText(text).then(flash, function () {
        if (legacyCopyText(text)) flash();
        else fail();
      });
      return;
    }
    if (legacyCopyText(text)) flash();
    else fail();
  }

  function renderCopyButton() {
    if (!singleOpenPlot()) return null;
    var text = ttsForOpenPlot();
    if (!text) return null;
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'chrome-pill';
    btn.textContent = 'copy';
    btn.title = 'Copy spoken route';
    btn.setAttribute('aria-label', 'Copy spoken route');
    btn.addEventListener('click', function (ev) {
      ev.preventDefault();
      ev.stopPropagation();
      copyRouteString(text, btn);
    });
    return btn;
  }

  function closeMonoMenu() {
    var drop = el('mono-menu-drop');
    var btn = el('mono-menu-btn');
    if (drop) drop.hidden = true;
    if (btn) btn.setAttribute('aria-expanded', 'false');
  }

  function toggleMonoMenu() {
    var drop = el('mono-menu-drop');
    var btn = el('mono-menu-btn');
    if (!drop || !btn) return;
    var willOpen = !!drop.hidden;
    drop.hidden = !willOpen;
    btn.setAttribute('aria-expanded', willOpen ? 'true' : 'false');
  }

  function switchMonolith(id) {
    closeMonoMenu();
    var onPlot = id === 'field' && state.viewPlane === 'field' && state.fieldPlot;
    if (!state.split && state.viewPlane === id && !onPlot) return;
    pushNav({ plane: id, plot: '', parcel: '', card: '', split: null });
  }

  function syncMonoMenu() {
    var drop = el('mono-menu-drop');
    if (!drop) return;
    drop.querySelectorAll('[data-plane]').forEach(function (b) {
      var id = b.getAttribute('data-plane');
      var on = state.viewPlane === id;
      b.setAttribute('aria-selected', on ? 'true' : 'false');
      if (state.split && state.split.plane === id) b.classList.add('is-companion');
      else b.classList.remove('is-companion');
    });
  }

  var monoMenuBound = false;
  function ensureMonoMenu() {
    var search = el('board-search');
    if (!search || !search.parentNode) return;
    var wrap = el('mono-menu-wrap');
    if (!wrap) {
      wrap = document.createElement('div');
      wrap.className = 'mono-menu-wrap';
      wrap.id = 'mono-menu-wrap';
      wrap.innerHTML =
        '<button type="button" class="mono-menu-btn" id="mono-menu-btn" aria-label="Planes" aria-haspopup="true" aria-expanded="false" aria-controls="mono-menu-drop" title="Planes"><span class="mono-menu-glyph" aria-hidden="true">☰</span></button>' +
        '<div class="mono-menu-drop" id="mono-menu-drop" hidden role="menu" aria-label="Planes">' +
          '<button type="button" class="mono-btn" role="menuitem" data-plane="tasks">tasks</button>' +
          '<button type="button" class="mono-btn" role="menuitem" data-plane="field">field</button>' +
        '</div>';
      search.insertAdjacentElement('afterend', wrap);
    }
    if (monoMenuBound) return;
    monoMenuBound = true;
    var btn = el('mono-menu-btn');
    if (btn) {
      btn.addEventListener('click', function (ev) {
        ev.preventDefault();
        ev.stopPropagation();
        toggleMonoMenu();
      });
    }
    var drop = el('mono-menu-drop');
    if (drop) {
      drop.querySelectorAll('[data-plane]').forEach(function (b) {
        b.addEventListener('click', function (ev) {
          ev.preventDefault();
          ev.stopPropagation();
          switchMonolith(b.getAttribute('data-plane'));
        });
      });
    }
    document.addEventListener('click', function (ev) {
      var host = el('mono-menu-wrap');
      var dropNow = el('mono-menu-drop');
      if (!host || !dropNow || dropNow.hidden) return;
      if (host.contains(ev.target)) return;
      closeMonoMenu();
    });
    document.addEventListener('keydown', function (ev) {
      if (ev.key === 'Escape') closeMonoMenu();
    });
  }

  var axisModeBound = false;
  function bindAxisLabelMode() {
    if (axisModeBound || !window.matchMedia) return;
    axisModeBound = true;
    var mq = window.matchMedia('(max-width: ' + MOBILE_BP + 'px)');
    var onChange = function () { renderAxes(); };
    if (mq.addEventListener) mq.addEventListener('change', onChange);
    else if (mq.addListener) mq.addListener(onChange);
  }

  function fieldPaneShowing() {
    return state.viewPlane === 'field' || !!(state.split && state.split.plane === 'field');
  }

  function plotIndexShowing() {
    if (!fieldPaneShowing()) return false;
    if (state.fieldPlot) return false;
    var parsed = parseSearch(state.searchQuery);
    if (parsed.planePrefix === 'F' && parsed.terms && parsed.terms.length) return false;
    return state.fieldSource === 'live';
  }

  function renderPlaneChrome() {
    rebuildParcels();
    var side = el('mono-side');
    if (side) side.innerHTML = '';
    var lead = el('chrome-lead');
    var sortSlot = el('chrome-sort');
    if (lead) lead.innerHTML = '';
    if (sortSlot) sortSlot.innerHTML = '';
    if (fieldPaneShowing() && state.fieldPlot) {
      if (lead) {
        var plots = document.createElement('button');
        plots.type = 'button';
        plots.className = 'chrome-pill';
        plots.textContent = 'plots';
        plots.title = 'Plot index';
        plots.setAttribute('aria-label', 'Back to plots');
        plots.addEventListener('click', function (ev) {
          ev.preventDefault();
          openFieldPlot('');
        });
        lead.appendChild(plots);
        var copyBtn = renderCopyButton();
        if (copyBtn) lead.appendChild(copyBtn);
      }
    }
    if (plotIndexShowing() && sortSlot) {
      var mode = PLOT_SORTS.indexOf(state.plotSort) >= 0 ? state.plotSort : 'new';
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'chrome-pill plot-sort-btn';
      btn.textContent = PLOT_SORT_LABEL[mode];
      var next = PLOT_SORT_LABEL[PLOT_SORTS[(PLOT_SORTS.indexOf(mode) + 1) % PLOT_SORTS.length]];
      btn.title = 'Sort plots by ' + PLOT_SORT_LABEL[mode] + ' — click for ' + next;
      btn.setAttribute('aria-label', btn.title);
      btn.addEventListener('click', function (ev) {
        ev.preventDefault();
        ev.stopPropagation();
        cyclePlotSort();
      });
      sortSlot.appendChild(btn);
    }
    syncHistChrome();
    syncMonoMenu();
  }

  function renderTasksInto(body) {
    body.innerHTML = '';
    if (state.activeAxis === 'TIMERS') {
      renderTimersQuiet(body);
      return;
    }
    var cards = filteredCards();
    syncChromeCount(cards);
    if (!cards.length) {
      var empty = document.createElement('div');
      empty.className = 'empty-list';
      empty.textContent = 'No cards match the current filters.';
      body.appendChild(empty);
      return;
    }
    var ul = document.createElement('ul');
    ul.className = 'card-list';
    ul.setAttribute('aria-label', state.agendaPreset ? 'Agenda day plane' : 'Board inventory');
    cards.forEach(function (c) { ul.appendChild(renderCard(c)); });
    body.appendChild(ul);
    if (state.pendingFocusId) {
      var fid = state.pendingFocusId;
      state.pendingFocusId = null;
      setTimeout(function () { focusCard(fid, { instant: true }); }, 0);
    }
  }

  function renderListBody() {
    var panes = el('board-panes');
    var tasksPane = el('pane-tasks');
    var fieldPane = el('pane-field');
    var tasksBody = el('tasks-body') || el('board-body');
    var fieldBody = el('field-body');
    var showTasks = state.viewPlane === 'tasks' || !!(state.split && state.split.plane === 'tasks');
    var showField = state.viewPlane === 'field' || !!(state.split && state.split.plane === 'field');
    if (panes) panes.classList.toggle('is-split', !!state.split);
    if (tasksPane) tasksPane.hidden = !showTasks;
    if (fieldPane) fieldPane.hidden = !showField;
    if (state.split && panes && tasksPane && fieldPane) {
      if (state.viewPlane === 'field') panes.insertBefore(fieldPane, tasksPane);
      else panes.insertBefore(tasksPane, fieldPane);
    }
    document.querySelectorAll('.split-close').forEach(function (btn) {
      var pane = btn.closest ? btn.closest('.plane-pane') : null;
      var plane = pane ? pane.getAttribute('data-plane') : '';
      btn.hidden = !(state.split && state.split.plane === plane);
    });
    if (showTasks && tasksBody) renderTasksInto(tasksBody);
    else if (tasksBody) tasksBody.innerHTML = '';
    if (showField && fieldBody) {
      fieldBody.innerHTML = '';
      renderFieldPlane(fieldBody);
    } else if (fieldBody) fieldBody.innerHTML = '';
  }

  function renderTimersQuiet(body) {
    /* Quiet list — no instructional stub copy (2qbf) */
    var parsedT = parseSearch(state.searchQuery);
    var feed = sortCards(state.cards.filter(isTimersFeed).filter(function (c) {
      if (state.sightTest && (!c.tags || c.tags.indexOf(SIGHT_TEST_TAG) < 0)) return false;
      if (parsedT.override) return matchesSearch(c, parsedT);
      if (state.blocksMode === 'include' && !c.blocked) return false;
      if (c.blocked && (state.blocksMode === 'exclude' || !state.showBlocked)) return false;
      if (state.doneMode === 'include' && c.status !== 'done') return false;
      if (!state.showDone && c.status === 'done') return false;
      if (state.removeMode === 'include' && c.status !== 'remove') return false;
      if (state.removeMode === 'exclude' && c.status === 'remove') return false;
      if (state.testMode === 'exclude' && c.tags && c.tags.indexOf(SIGHT_TEST_TAG) >= 0) return false;
      if (state.exclude.status.indexOf(c.status) >= 0) return false;
      return matchesSearch(c, parsedT);
    }));
    syncChromeCount(feed);
    if (!feed.length) {
      var empty = document.createElement('div');
      empty.className = 'empty-list';
      empty.textContent = 'No lead-up, active, or overdue timers.';
      body.appendChild(empty);
      return;
    }
    var ul = document.createElement('ul');
    ul.className = 'card-list';
    ul.setAttribute('aria-label', 'Timed cards');
    feed.forEach(function (c) { ul.appendChild(renderCard(c)); });
    body.appendChild(ul);
  }

  function snapshotFilters() {
    return {
      selection: state.selection.map(function (e) {
        return { field: e.field, value: e.value, mode: e.mode };
      }),
      include: {
        status: state.include.status.slice(),
        sched: state.include.sched.slice(),
        domain: state.include.domain.slice(),
        project: state.include.project.slice()
      },
      exclude: {
        status: state.exclude.status.slice(),
        sched: state.exclude.sched.slice(),
        domain: state.exclude.domain.slice(),
        project: state.exclude.project.slice()
      },
      lane: state.lane,
      activeAxis: state.activeAxis,
      chipBandOpen: state.chipBandOpen,
      showBlocked: state.showBlocked,
      showDone: state.showDone,
      doneMode: state.doneMode,
      blocksMode: state.blocksMode,
      removeMode: state.removeMode,
      testMode: state.testMode,
      sort: state.sort,
      agendaPreset: !!state.agendaPreset
    };
  }

  function restoreFilters(snap) {
    if (!snap) return;
    if (Array.isArray(snap.selection)) {
      state.selection = snap.selection.map(function (e) {
        return { field: e.field, value: e.value, mode: e.mode };
      });
      hardenSelectionOrder();
      syncMapsFromSelection();
    } else {
      state.include = {
        status: (snap.include.status || []).slice(),
        sched: (snap.include.sched || []).slice(),
        domain: (snap.include.domain || []).slice(),
        project: (snap.include.project || []).slice()
      };
      state.exclude = {
        status: (snap.exclude.status || []).slice(),
        sched: (snap.exclude.sched || []).slice(),
        domain: (snap.exclude.domain || []).slice(),
        project: (snap.exclude.project || []).slice()
      };
      state.selection = selectionFromMaps(state.include, state.exclude);
      syncMapsFromSelection();
    }
    state.lane = snap.lane;
    state.activeAxis = snap.activeAxis;
    state.chipBandOpen = ('chipBandOpen' in snap) ? !!snap.chipBandOpen : false;
    state.showBlocked = snap.showBlocked;
    state.showDone = ('showDone' in snap) ? !!snap.showDone : false;
    state.blocksMode = ('blocksMode' in snap) ? snap.blocksMode : (snap.showBlocked ? 'none' : 'exclude');
    state.doneMode = ('doneMode' in snap) ? snap.doneMode : (state.showDone ? 'none' : 'exclude');
    state.removeMode = ('removeMode' in snap) ? snap.removeMode : 'exclude';
    if ('testMode' in snap) state.testMode = snap.testMode;
    state.sort = snap.sort;
    if ('agendaPreset' in snap) {
      state.agendaPreset = !!snap.agendaPreset;
      syncAgendaUrl(state.agendaPreset);
    }
  }

  /*
   * Agenda ON = day plane, reflected in chrome chips:
   *   include STATUS urgent|now|today  ∪  SCHED overdue|due_today
   *   exclude done · hide blocked · lane tosu · sort agenda
   * Status∪sched includes use OR in matchesFilters (both axes set).
   */
  function applyAgendaPreset() {
    state.savedBeforeAgenda = snapshotFilters();
    clearAllFilters();
    /* Includes then excludes — exclude-done naturally last among value chips */
    state.selection = [
      { field: 'status', value: 'urgent', mode: 'include' },
      { field: 'status', value: 'now', mode: 'include' },
      { field: 'status', value: 'today', mode: 'include' },
      { field: 'sched', value: 'overdue', mode: 'include' },
      { field: 'sched', value: 'due_today', mode: 'include' },
      { field: 'status', value: 'done', mode: 'exclude' }
    ];
    syncMapsFromSelection();
    state.showBlocked = false;
    state.blocksMode = 'exclude';
    state.showDone = false;
    state.doneMode = 'exclude';
    state.removeMode = 'exclude';
    state.lane = 'tosu';
    state.sort = 'agenda';
    state.agendaPreset = true;
    state.activeAxis = 'STATUS';
    state.chipBandOpen = false;
    syncAgendaUrl(true);
  }

  function clearAgendaPreset() {
    state.agendaPreset = false;
    if (state.savedBeforeAgenda) {
      restoreFilters(state.savedBeforeAgenda);
      state.savedBeforeAgenda = null;
    } else {
      clearAllFilters();
      state.showBlocked = true;
      state.blocksMode = 'none';
      state.showDone = false;
      state.doneMode = 'exclude';
      state.removeMode = 'exclude';
      state.sort = 'inventory';
    }
    syncAgendaUrl(false);
  }

  /* User mutated filters while agenda ON → pill off, keep custom (no restore). */
  function divergentFromAgenda() {
    return !!state.agendaPreset;
  }

  function markAgendaDiverged() {
    if (!state.agendaPreset) return;
    state.agendaPreset = false;
    state.savedBeforeAgenda = null;
    syncAgendaUrl(false);
  }

  function toggleAgendaPreset() {
    if (state.agendaPreset) clearAgendaPreset();
    else applyAgendaPreset();
    renderAll();
  }

  function syncAgendaUrl(on) {
    try {
      var u = new URL(window.location.href);
      if (on) u.searchParams.set('agenda', '1');
      else u.searchParams.delete('agenda');
      window.history.replaceState({}, '', u.pathname + u.search + u.hash);
    } catch (e) { /* ignore */ }
  }

  function agendaFromQuery() {
    try {
      var u = new URL(window.location.href);
      var v = u.searchParams.get('agenda');
      return v === '1' || v === 'true' || v === 'yes';
    } catch (e) {
      return false;
    }
  }

  function renderLaneBar() {
    var bar = el('lane-bar');
    if (!bar) return;
    bar.innerHTML = '';

    /* Agenda preset toggle — day-plane pack on/off (binary) */
    var ag = document.createElement('button');
    ag.type = 'button';
    ag.id = 'agenda-preset-btn';
    ag.className = 'chip chip--agenda' + (state.agendaPreset ? ' chip--include' : ' chip--off');
    ag.setAttribute('aria-pressed', state.agendaPreset ? 'true' : 'false');
    ag.textContent = 'agenda';
    ag.title = state.agendaPreset
      ? 'Day plane ON — +urgent +now +today · +overdue +due_today · −done · tosu · hide blocked — click to restore prior'
      : 'Day plane — tosu, not done, hide blocked, sort bands urgent ∪ overdue ∪ today ∪ due_today';
    ag.setAttribute('aria-label', ag.title);
    ag.addEventListener('click', function () { toggleAgendaPreset(); });
    bar.appendChild(ag);

    /* Single tosu pill: all(off) → tosu(include) → agent(exclude) → all */
    var tosuBtn = document.createElement('button');
    tosuBtn.type = 'button';
    var laneClass = 'chip';
    if (state.lane === 'tosu') laneClass += ' chip--include';
    else if (state.lane === 'agent') laneClass += ' chip--exclude';
    else laneClass += ' chip--off';
    tosuBtn.className = laneClass;
    tosuBtn.textContent = 'tosu';
    tosuBtn.setAttribute('aria-pressed', state.lane !== 'all' ? 'true' : 'false');
    tosuBtn.setAttribute('data-lane', state.lane);
    var laneHint = state.lane === 'tosu' ? 'tosu only'
      : state.lane === 'agent' ? 'exclude tosu'
      : 'all (inventory)';
    tosuBtn.setAttribute('aria-label', 'tosu lane: ' + laneHint + ' — cycle');
    tosuBtn.title = 'Cycle: all → tosu only → −tosu → all';
    tosuBtn.addEventListener('click', function () {
      if (state.lane === 'all') state.lane = 'tosu';
      else if (state.lane === 'tosu') state.lane = 'agent';
      else state.lane = 'all';
      markAgendaDiverged();
      renderAll();
    });
    bar.appendChild(tosuBtn);

    /* done / blocks — binary; green include on, muted .chip--off when off (no + on mobile) */
    var doneBtn = document.createElement('button');
    doneBtn.type = 'button';
    doneBtn.className = 'chip chip--toggle' + (state.showDone ? ' chip--include' : ' chip--off');
    doneBtn.setAttribute('aria-pressed', state.showDone ? 'true' : 'false');
    doneBtn.textContent = 'done';
    doneBtn.title = state.showDone
      ? 'Done visible — click to hide'
      : 'Done hidden — click to show';
    doneBtn.addEventListener('click', function () {
      state.showDone = !state.showDone;
      setDoneExclude(!state.showDone);
      markAgendaDiverged();
      renderAll();
    });
    bar.appendChild(doneBtn);

    /* remove — binary show/hide for status=REMOVE (GLOBAL > remove has the full include/exclude cycle) */
    var rmShown = state.removeMode !== 'exclude';
    var rmBtn = document.createElement('button');
    rmBtn.type = 'button';
    rmBtn.className = 'chip chip--toggle' + (rmShown ? ' chip--include' : ' chip--off');
    rmBtn.setAttribute('aria-pressed', rmShown ? 'true' : 'false');
    rmBtn.textContent = 'remove';
    rmBtn.title = rmShown
      ? 'REMOVE cards visible — click to hide'
      : 'REMOVE cards hidden — click to show';
    rmBtn.addEventListener('click', function () {
      state.removeMode = rmShown ? 'exclude' : 'none';
      markAgendaDiverged();
      renderAll();
    });
    bar.appendChild(rmBtn);

    var blk = document.createElement('button');
    blk.type = 'button';
    blk.className = 'chip chip--toggle' + (state.showBlocked ? ' chip--include' : ' chip--off');
    blk.setAttribute('aria-pressed', state.showBlocked ? 'true' : 'false');
    blk.textContent = 'blocks';
    blk.title = state.showBlocked
      ? 'Blocked cards visible — click to hide'
      : 'Blocked cards hidden — click to show';
    blk.addEventListener('click', function () {
      state.showBlocked = !state.showBlocked;
      markAgendaDiverged();
      renderAll();
    });
    bar.appendChild(blk);

    /* UI fixtures / kitchen-sink seed — binary, with agenda/tosu/done/blocks */
    var testBtn = document.createElement('button');
    testBtn.type = 'button';
    testBtn.id = 'sight-test-btn';
    testBtn.className = 'chip chip--toggle' + (state.sightTest ? ' chip--include' : ' chip--off');
    testBtn.setAttribute('aria-pressed', state.sightTest ? 'true' : 'false');
    testBtn.textContent = 'test';
    testBtn.title = state.sightTest
      ? 'Sight-test fixtures ON — only sight-test cards — click to return to plane'
      : 'Sight-test UI fixtures / kitchen-sink seed (all states) — click to show';
    testBtn.addEventListener('click', function () { toggleSightTest(); });
    bar.appendChild(testBtn);
  }

  function syncSearchChrome() {
    var wrap = el('board-search');
    var input = el('board-search-input');
    var clear = el('board-search-clear');
    if (!input) return;
    var q = state.searchQuery || '';
    if (input.value !== q) input.value = q;
    var parsed = parseSearch(q);
    if (wrap) wrap.classList.toggle('is-override', !!parsed.override);
    if (clear) clear.hidden = false;
    syncMetaToggleBtn();
  }

  function defaultMetaHidden() {
    try {
      return window.matchMedia('(max-width: ' + MOBILE_BP + 'px)').matches;
    } catch (e) {
      return false;
    }
  }

  function applyMetaHiddenClass() {
    document.body.classList.toggle('meta-hidden', !!state.metaHidden);
    syncMetaToggleBtn();
  }

  function syncMetaToggleBtn() {
    var btn = el('board-meta-toggle');
    if (!btn) return;
    btn.setAttribute('aria-pressed', state.metaHidden ? 'true' : 'false');
    btn.classList.toggle('is-active', !!state.metaHidden);
    /* pressed = meta hidden; symbol reflects state */
    btn.textContent = state.metaHidden ? '◇' : '◈';
    btn.title = state.metaHidden
      ? 'Metadata pills hidden — click to show'
      : 'Metadata pills visible — click to hide';
    btn.setAttribute('aria-label', btn.title);
  }

  function toggleMetaHidden() {
    state.metaHidden = !state.metaHidden;
    state.metaHiddenUserSet = true;
    applyMetaHiddenClass();
  }

  function initMetaHidden() {
    /* Boot to viewport default; manual toggle only sticky until next breakpoint cross */
    state.metaHidden = defaultMetaHidden();
    state.metaHiddenUserSet = false;
    applyMetaHiddenClass();
    if (initMetaHidden._bound) return;
    initMetaHidden._bound = true;
    var mq = null;
    try { mq = window.matchMedia('(max-width: ' + MOBILE_BP + 'px)'); } catch (e0) { mq = null; }
    var lastMobile = defaultMetaHidden();
    function onBpCross() {
      var next = defaultMetaHidden();
      /* Preferred: on breakpoint cross, apply viewport default and clear userSet */
      state.metaHiddenUserSet = false;
      state.metaHidden = next;
      lastMobile = next;
      applyMetaHiddenClass();
    }
    if (mq) {
      if (mq.addEventListener) mq.addEventListener('change', onBpCross);
      else if (mq.addListener) mq.addListener(onBpCross);
    } else {
      window.addEventListener('resize', function () {
        var next = defaultMetaHidden();
        if (next === lastMobile) return;
        onBpCross();
      });
    }
  }

  function bindHailIdClicks() {
    if (document.body.dataset.hailBound === '1') return;
    document.body.dataset.hailBound = '1';
    document.body.addEventListener('click', function (ev) {
      var a = ev.target && ev.target.closest ? ev.target.closest('a.hail-id') : null;
      if (!a) return;
      var id = a.getAttribute('data-card-id');
      if (!id) return;
      ev.preventDefault();
      focusCard(id, { record: true, instant: true });
    });
  }

  function bindSearch() {
    bindHailIdClicks();
    var input = el('board-search-input');
    var clear = el('board-search-clear');
    if (!input || input.dataset.bound === '1') return;
    input.dataset.bound = '1';
    input.addEventListener('input', function () {
      state.searchQuery = input.value;
      var prefix = parseSearch(state.searchQuery).planePrefix;
      var next = state.viewPlane;
      if (prefix === 'T') next = 'tasks';
      else if (prefix === 'F') next = 'field';
      var switched = next !== state.viewPlane;
      state.viewPlane = next;
      if (switched) {
        state.split = null;
        rememberNav(currentNav());
        syncViewUrl('replace');
      }
      syncSearchChrome();
      if (switched) renderAll();
      else {
        renderListBody();
        renderPlaneChrome();
        renderSummary();
      }
    });
    /* Focus empty must retain active filters — do not clear chips on focus */
    input.addEventListener('focus', function () {
      /* intentionally no filter clear */
    });
    if (clear) {
      clear.addEventListener('click', function (ev) {
        ev.preventDefault();
        state.searchQuery = '';
        input.value = '';
        syncSearchChrome();
        input.focus();
        renderListBody();
        renderSummary();
      });
    }
    var metaBtn = el('board-meta-toggle');
    if (metaBtn && metaBtn.dataset.bound !== '1') {
      metaBtn.dataset.bound = '1';
      metaBtn.addEventListener('click', function (ev) {
        ev.preventDefault();
        toggleMetaHidden();
      });
    }
    var histBack = el('hist-back');
    var histFwd = el('hist-fwd');
    if (histBack && histBack.dataset.bound !== '1') {
      histBack.dataset.bound = '1';
      histBack.addEventListener('click', function (ev) {
        ev.preventDefault();
        goHist(-1);
      });
    }
    if (histFwd && histFwd.dataset.bound !== '1') {
      histFwd.dataset.bound = '1';
      histFwd.addEventListener('click', function (ev) {
        ev.preventDefault();
        goHist(1);
      });
    }
    document.querySelectorAll('.split-close').forEach(function (btn) {
      if (btn.dataset.bound === '1') return;
      btn.dataset.bound = '1';
      btn.addEventListener('click', function (ev) {
        ev.preventDefault();
        closeSplit();
      });
    });
    syncMetaToggleBtn();
    syncHistChrome();
  }

  function syncChromeHint() {
    var hint = el('chrome-hint');
    if (!hint) return;
    hint.hidden = true;
    hint.textContent = '';
  }

  function syncChromeCount(cards) {
    /* Empty search: right-aligned filter result count left of ×. No showing-x copy. */
    var countEl = el('search-result-count');
    var clear = el('board-search-clear');
    var wrap = el('board-search');
    if (!countEl) return;
    var q = (state.searchQuery || '').trim();
    if (q) {
      countEl.textContent = '';
      countEl.hidden = true;
      if (wrap) wrap.classList.remove('has-result-count');
      if (clear) clear.hidden = false;
      return;
    }
    if (state.activeAxis === 'TIMERS') {
      var feedN = state.cards.filter(isTimersFeed).filter(function (c) {
        if (state.sightTest && (!c.tags || c.tags.indexOf(SIGHT_TEST_TAG) < 0)) return false;
        if (state.blocksMode === 'include' && !c.blocked) return false;
        if (c.blocked && (state.blocksMode === 'exclude' || !state.showBlocked)) return false;
        if (state.doneMode === 'include' && c.status !== 'done') return false;
        if (!state.showDone && c.status === 'done') return false;
        if (state.removeMode === 'include' && c.status !== 'remove') return false;
        if (state.removeMode === 'exclude' && c.status === 'remove') return false;
        if (state.testMode === 'exclude' && c.tags && c.tags.indexOf(SIGHT_TEST_TAG) >= 0) return false;
        return true;
      }).length;
      countEl.textContent = String(feedN);
    } else {
      cards = cards || filteredCards();
      countEl.textContent = String(cards.length);
    }
    countEl.hidden = false;
    if (wrap) wrap.classList.add('has-result-count');
    if (clear) clear.hidden = false;
  }

  function renderAll() {
    var mark = document.querySelector('.page-mark');
    if (mark) mark.textContent = 'sight';
    document.body.classList.toggle('agenda-preset', !!state.agendaPreset);
    document.body.classList.toggle('plane-field', state.viewPlane === 'field' && !state.split);
    document.body.classList.toggle('is-split', !!state.split);
    document.body.classList.remove('parcel-test');
    document.body.classList.remove('field-pane-open');
    bindSearch();
    syncSearchChrome();
    syncChromeHint();
    renderMeta();
    renderLaneBar();
    renderAxes();
    renderChips();
    renderSummary();
    ensureMonoMenu();
    renderPlaneChrome();
    renderListBody();
    ensureTimerTick();
  }

  /* ---------- boot ---------- */
  function fieldIdFromQuery() {
    try {
      var u = new URL(window.location.href);
      var v = u.searchParams.get('field') || u.searchParams.get('parcel');
      if (v) return String(v).trim();
    } catch (e) { /* ignore */ }
    return '';
  }

  function fieldIdFromHash(h) {
    if (!h) return '';
    if (h.indexOf('parcel-') === 0) return h.slice(7);
    if (h.indexOf('field-') === 0) return h.slice(6);
    return '';
  }

  function whenUnlocked() {
    /* Wait until unlock.js revealBoard: static/sync data-sight-locked, or
       gate still up with no decrypted plane (covers race if attr missing). */
    var locked = document.documentElement.hasAttribute('data-sight-locked');
    var gate = document.getElementById('sight-gate');
    var gateUp = gate && !gate.hidden;
    var hasPlane = !!(window.__SIGHT_PLANE__ && window.__SIGHT_PLANE__.board_model);
    if (!locked && !(gateUp && !hasPlane)) {
      return Promise.resolve();
    }
    if (hasPlane && !locked) {
      return Promise.resolve();
    }
    return new Promise(function (resolve) {
      window.addEventListener('sight-unlocked', function onUnlock() {
        window.removeEventListener('sight-unlocked', onUnlock);
        resolve();
      });
    });
  }

  function boot() {
    bindAxisLabelMode();
    state.localToday = localTodayParts();
    state.sightTest = readSightTestFlag();
    state.viewPlane = 'tasks';
    el('board-status').textContent = 'Loading plane…';
    whenUnlocked().then(function () { return loadPlane(); }).then(function (result) {
      state.localToday = localTodayParts();
      ingestPlaneField(window.__SIGHT_PLANE__);
      state.planeCards = (result.parsed.cards || []).map(cloneCard);
      rebuildCardsFromPlane(); /* plane ± live sight-test fixtures from Date.now() */
      rebuildParcels();
      state.meta = result.parsed.meta || {};
      state.planeSource = result.source;
      state.planeLabel = result.label;
      el('board-status').textContent = '';
      if (state.sightTest) {
        /* Boot with test ON: same wipe as toggle — only test mode filters list */
        clearAllFilters();
        state.showDone = true;
        state.showBlocked = true;
        state.doneMode = 'none';
        state.blocksMode = 'none';
        state.testMode = 'include';
        state.sort = 'inventory';
        state.agendaPreset = false;
        syncAgendaUrl(false);
      } else if (agendaFromQuery()) {
        applyAgendaPreset();
      } else if (!state.showDone && findSelectionIndex('status', 'done') < 0) {
        setDoneExclude(true);
      }
      initMetaHidden();
      var nav = readInitialNav();
      var taskHash = '';
      try {
        taskHash = (window.location.hash || '').replace(/^#/, '');
        if (taskHash.indexOf('card-') === 0) taskHash = taskHash.slice(5);
      } catch (eHash) { taskHash = ''; }
      if (nav.plane === 'field') {
        state.viewPlane = 'field';
        state.fieldPlot = nav.plot || '';
        if (nav.parcel) focusParcel(nav.parcel, { history: 'replace', instant: true });
        else {
          renderAll();
          syncViewUrl('replace');
        }
        seedNav(currentNav());
      } else {
        state.viewPlane = 'tasks';
        renderAll();
        syncViewUrl('replace');
        var bootCard = '';
        if (taskHash && state.byId[taskHash] && !fieldIdFromHash(taskHash)) {
          bootCard = taskHash;
          state.pendingFocusId = taskHash;
          setTimeout(function () { focusCard(taskHash, { instant: true }); }, 0);
        }
        seedNav({ plane: 'tasks', plot: '', parcel: '', card: bootCard });
      }
    }).catch(function (err) {
      el('board-status').textContent = 'Failed to init: ' + err;
    });
  }

  /* If we painted fallback before unlock (legacy race), reload from memory. */
  window.addEventListener('sight-unlocked', function onLateUnlock() {
    if (state.planeSource === 'memory') return;
    var mem = null;
    try { mem = planeFromMemory(); } catch (e) { return; }
    if (!mem) return;
    state.planeCards = (mem.parsed.cards || []).map(cloneCard);
    ingestPlaneField(window.__SIGHT_PLANE__);
    rebuildCardsFromPlane();
    rebuildParcels();
    state.meta = mem.parsed.meta || {};
    state.planeSource = mem.source;
    state.planeLabel = mem.label;
    var navLate = readInitialNav();
    if (navLate.plane === 'field') {
      state.viewPlane = 'field';
      state.fieldPlot = navLate.plot || '';
      if (navLate.parcel) {
        focusParcel(navLate.parcel, { history: 'none', instant: true });
      } else {
        renderAll();
      }
    } else {
      renderAll();
    }
  });

  /* App-level ← → stack. Browser back/forward is not wired — it fought the SPA. */

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
