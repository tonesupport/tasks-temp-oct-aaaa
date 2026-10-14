#!/usr/bin/env python3
"""Render a snapshot tasks.toml (+ optional tasks.patch) as ONE standalone Sight-style HTML page.

Usage: python3 task-preview.py [--snapshot snapshot/tasks.toml] [--patch tasks.patch]
                               [--skin skin/] [-o preview.html]

No patch: renders the snapshot as Sight shows it. With a patch: applies it in memory
(strict, same rules as check.py), renders the result, and marks new / changed / done
cards, with a review panel listing each touched task and its field changes.
Unencrypted: no password gate, no plane.enc. Everything (CSS, fonts, board.js, data)
is inlined, so the file opens from disk with no server. Stdlib only, Python 3.11+.
"""
import base64, datetime, html, json, os, re, sys, tomllib
from zoneinfo import ZoneInfo

KIT = os.path.dirname(os.path.abspath(__file__))
TZ = ZoneInfo('America/Los_Angeles')
STATUS_ORDER = ['urgent', 'now', 'progress', 'today', 'later', 'deferred', 'sched', 'done', 'REMOVE']
NON_TASK = {'tasks.spine'}

# ---- strict unified-diff applier (same behaviour as check.py) ----
HUNK_RE = re.compile(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')
def apply_patch(src, patch):
    lines = patch.splitlines(keepends=True); hunks = []; headers = 0; i = 0
    while i < len(lines):
        if lines[i].startswith('--- ') and i + 1 < len(lines) and lines[i + 1].startswith('+++ '):
            headers += 1; i += 2; continue
        m = HUNK_RE.match(lines[i])
        if not m: i += 1; continue
        os_, oc = int(m.group(1)), int(m.group(2) or (1 if m.group(2) is None else 0))
        if m.group(2) is not None: oc = int(m.group(2))
        nc = int(m.group(4)) if m.group(4) is not None else 1
        body = []; so = sn = 0; i += 1
        while i < len(lines) and (so < oc or sn < nc):
            ln = lines[i]
            if ln.startswith('\\'): i += 1; continue
            tag = ln[:1]
            if tag not in ' -+':
                if ln.strip() == '': tag, ln = ' ', ' ' + ln
                else: sys.exit(f'task-preview: bad hunk line {i + 1}')
            body.append((tag, ln[1:])); so += tag in ' -'; sn += tag in ' +'; i += 1
        while i < len(lines) and lines[i].startswith('\\'):
            if body: body[-1] = (body[-1][0], body[-1][1].rstrip('\n'))
            i += 1
        hunks.append((os_, body))
    if headers != 1 or not hunks: sys.exit('task-preview: patch must be a one-file unified diff with hunks')
    src_l = src.splitlines(keepends=True); out = []; pos = 0
    for os_, body in hunks:
        old = [t for g, t in body if g in ' -']; new = [t for g, t in body if g in ' +']
        start = os_ - 1 if old else os_
        if src_l[start:start + len(old)] != old or start < pos:
            sys.exit(f'task-preview: hunk @@ -{os_} does not apply to this snapshot (run check.py)')
        out += src_l[pos:start] + new; pos = start + len(old)
    return ''.join(out + src_l[pos:])

# ---- board-model emitter (mirrors board-export.tcl 0.3.x card shape) ----
def q(s):
    s = str(s)
    if "'" not in s and not re.search(r'[\x00-\x1f\x7f]', s): return f"'{s}'"
    return json.dumps(s, ensure_ascii=False)
def qa(xs): return '[' + ', '.join(q(x) for x in xs) + ']'
def norm(s): return ' '.join(str(s).split())

def tasks_of(doc):
    return {k: v for k, v in doc.items() if isinstance(v, dict) and k not in NON_TASK and k != 'tasks' and ('status' in v or 'title' in v)}

def board_model(tasks, order, show_notes_for):
    now = datetime.datetime.now(TZ)
    today = norm(now.strftime('%a %b ') + str(now.day) + now.strftime(' %y'))
    ids = [k for k in order if k != 'root' and tasks[k].get('status')]
    ids.sort(key=lambda k: STATUS_ORDER.index(tasks[k]['status']) if tasks[k]['status'] in STATUS_ORDER else 99)
    out = ["# task-preview board-model (unencrypted preview)", "schema = 'labor-os.board-model/v1'",
           "generator = 'task-preview.py'", "generator_version = '1'", f"generated = {now.strftime('%y%m%d%H%M')}",
           f"generated_datetime = {q(today)}", "source = 'snapshot/tasks.toml + tasks.patch'",
           "stable_path = 'preview'", 'include_done = true', f'card_count = {len(ids)}', '']
    notes = {}
    for k in ids:
        t = tasks[k]; tags = [x for x in t.get('tags', []) if isinstance(x, str)]
        tosu = 'tosu' in tags; st = t['status']; dt = norm(t.get('datetime', ''))
        L = ['[[cards]]', f'id = {q(k)}', f"title = {q(t.get('title', k))}", f'status = {q(st)}']
        body = str(t.get('notes', '')).strip()
        for key in ('domain', 'project'):
            if str(t.get(key, '')).strip(): L.append(f'{key} = {q(str(t[key]).strip())}')
        if body and (tosu or k in show_notes_for):
            L.append(f'notes = {q(body)}'); notes[k] = f'id = {q(k)}\nnotes = {json.dumps(body, ensure_ascii=False)}\n'
        for key in ('datetime', 'time', 'signaling-command'):
            v = norm(t[key]) if key == 'datetime' and key in t else str(t.get(key, '')).strip()
            if v: L.append(f'{key} = {q(v)}')
        if 'duration' in t: L.append(f"duration = {t['duration']}" if isinstance(t['duration'], int) else f"duration = {q(t['duration'])}")
        if tosu: L.append('tosu = true')
        if tags: L.append(f'tags = {qa(tags)}')
        if 'reminder' in t: L.append(f"reminder = {t['reminder']}" if isinstance(t['reminder'], int) else f"reminder = {q(t['reminder'])}")
        blockers = [b for b in t.get('blockers', []) if isinstance(b, str)]
        pending = [b for b in blockers if tasks.get(b, {}).get('status') != 'done']
        for key, arr in (('coordinating-agents', t.get('coordinating-agents', [])), ('field_links', t.get('field_links', [])),
                         ('blockers', blockers), ('blockers_pending', pending)):
            if arr: L.append(f'{key} = {qa(arr)}')
        if pending: L.append(f"blockers_summary = {q(','.join(pending))}")
        rem = 'reminder' in t or str(t.get('signaling-command', '')).strip()
        if st != 'done' and (dt or st == 'sched' or rem): L.append('timed = true')
        if (st in ('sched', 'today') and (dt == today or (st == 'today' and not dt))) or (dt and dt == today):
            L.append('due_today = true')
        out += L + ['']
    return '\n'.join(out) + '\n', notes

def inline_fonts(css, skin):
    def rep(m):
        p = os.path.join(skin, m.group(1))
        if not os.path.isfile(p): return 'url("")'
        mime = 'font/woff2' if p.endswith('.woff2') else 'font/ttf'
        return f'url("data:{mime};base64,{base64.b64encode(open(p, "rb").read()).decode()}")'
    return re.sub(r'url\("(fonts/[^"]+)"\)', rep, css)

def field_diff(a, b):
    rows = []
    for k in list(dict.fromkeys(list(a) + list(b))):
        if a.get(k) != b.get(k): rows.append((k, a.get(k), b.get(k)))
    return rows

def fmt(v):
    if v is None: return '∅'
    if isinstance(v, list): return '[' + ', '.join(map(str, v)) + ']'
    return str(v)

def main(argv):
    snap = os.path.join(KIT, 'snapshot', 'tasks.toml'); patch = None
    skin = os.path.join(KIT, 'skin'); outp = 'preview.html'
    it = iter(argv)
    for a in it:
        if a == '--snapshot': snap = next(it)
        elif a == '--patch': patch = next(it)
        elif a == '--skin': skin = next(it)
        elif a in ('-o', '--out'): outp = next(it)
        elif a in ('-h', '--help'): print(__doc__); return 0
        elif a.endswith('.patch') and patch is None: patch = a
        else: sys.exit(f'task-preview: unknown arg {a} (use -h)')
    snap_text = open(snap, encoding='utf-8').read()
    res_text = apply_patch(snap_text, open(patch, encoding='utf-8').read()) if patch else snap_text
    sdoc, rdoc = tomllib.loads(snap_text), tomllib.loads(res_text)
    s, r = tasks_of(sdoc), tasks_of(rdoc)
    order = [k for k in rdoc if k in r]
    new = [k for k in order if k not in s]
    done = [k for k in order if k in s and s[k] != r[k] and r[k].get('status') == 'done' and s[k].get('status') != 'done']
    changed = [k for k in order if k in s and s[k] != r[k] and k not in done]
    gone = [k for k in s if k not in r]
    touched = set(new + changed + done)
    model, notes = board_model(r, order, touched)

    tpl = open(os.path.join(skin, 'sight-index.html'), encoding='utf-8').read()
    css = inline_fonts(open(os.path.join(skin, 'artifacts.css'), encoding='utf-8').read(), skin)
    css += '\n' + open(os.path.join(skin, 'board.css'), encoding='utf-8').read()
    js = open(os.path.join(skin, 'board.js'), encoding='utf-8').read()
    marks = {**{k: 'new' for k in new}, **{k: 'changed' for k in changed}, **{k: 'done' for k in done}}
    color = {'new': '#2f7d4f', 'changed': '#b8860b', 'done': '#5a5aa8'}
    hl = '\n'.join(f'.board-row[data-id="{k}"]{{box-shadow:inset 0 0 0 2px {color[v]};position:relative}}'
                   f'.board-row[data-id="{k}"]::after{{content:"{v}";position:absolute;bottom:.3rem;right:.4rem;'
                   f'font:600 .66rem/1 "IBM Plex Mono",monospace;letter-spacing:.04em;text-transform:uppercase;'
                   f'color:#fff;background:{color[v]};padding:.18rem .35rem;border-radius:.2rem;pointer-events:none}}'
                   for k, v in marks.items())
    review_css = ('.twk-review{max-width:72rem;margin:1rem auto;padding:.75rem 1rem;border:1px solid #0002;border-radius:.35rem;'
                  'background:#fffdf8;font:14px/1.45 "IBM Plex Sans",system-ui,sans-serif}.twk-review h2{font:500 1.05rem "IBM Plex Serif",serif;margin:.2rem 0 .5rem}'
                  '.twk-review table{border-collapse:collapse;width:100%;font-size:.85rem}.twk-review td{border-top:1px solid #0001;padding:.25rem .4rem;vertical-align:top}'
                  '.twk-review .k{font-family:"IBM Plex Mono",monospace;white-space:nowrap}.twk-review del{color:#8b2e2e}.twk-review ins{color:#2f7d4f;text-decoration:none}'
                  '.twk-review a{font-family:"IBM Plex Mono",monospace}.twk-review pre{all:unset;display:block;white-space:pre-wrap;font:12px/1.4 "IBM Plex Mono",monospace;background:none;border:0;padding:0;margin:0}.twk-review table table td{border:0;padding:.1rem .4rem}'
                  '.twk-review table table{table-layout:fixed}.twk-review table table td:nth-child(1){width:9rem}.twk-review table table td:nth-child(2){width:14rem}')
    def link(k): return f'<a href="#card-{html.escape(k)}">{html.escape(k)}</a>'
    rows = []
    for k in new + changed + done:
        kind = marks[k]; a = s.get(k, {}); b = r[k]
        diffs = ''.join(f'<tr><td class="k">{html.escape(f)}</td><td><del><pre>{html.escape(fmt(x))}</pre></del></td><td><ins><pre>{html.escape(fmt(y))}</pre></ins></td></tr>'
                        for f, x, y in field_diff(a, b))
        rows.append(f'<tr><td class="k" style="color:{color[kind]}">{kind}</td><td>{link(k)}</td><td>{html.escape(str(b.get("title", "")))}</td></tr>'
                    f'<tr><td></td><td colspan="2"><table>{diffs}</table></td></tr>')
    if patch:
        summary = (f'<section class="twk-review" id="twk-review"><h2>Patch review: {len(new)} new, {len(changed)} changed, {len(done)} done'
                   + (f', <span style="color:#8b2e2e">{len(gone)} removed: {", ".join(map(html.escape, gone))}</span>' if gone else '')
                   + f'</h2><p>Source: {html.escape(os.path.basename(patch))} against snapshot/tasks.toml. Marked cards below: '
                   + ' '.join(f'<span style="color:{color[x]}">■ {x}</span>' for x in ('new', 'changed', 'done'))
                   + '. Done cards show when the done filter is on.</p><table>' + ''.join(rows) + '</table></section>')
    else:
        summary = '<section class="twk-review"><h2>Snapshot preview (no patch)</h2><p>snapshot/tasks.toml as Sight renders it.</p></section>'

    plane = {'schema': 'labor-os.sight-plane/v1', 'generated': datetime.datetime.now(TZ).isoformat(),
             'board_model': model, 'notes': notes, 'field': '', 'tts': {}}
    page = tpl
    page = page.replace(' data-sight-locked="1"', '')
    page = re.sub(r'<link rel="stylesheet" href="assets/[^"]+">\s*', '', page)
    page = re.sub(r'<style>.*?</style>', lambda m: '<style>\n' + css.replace('</style', '<\\/style') + '\n' + review_css + '\n' + hl + '\n</style>', page, count=1, flags=re.S)
    page = page.replace('<title>sight</title>', '<title>sight preview</title>')
    page = page.replace('class="board-page sight-locked"', 'class="board-page"')
    page = re.sub(r'<div id="sight-gate".*?</form>\s*<p id="sight-gate-status"[^>]*></p>\s*</div>\s*</div>', '', page, flags=re.S)
    page = page.replace('<div class="board-shell" aria-hidden="true">', summary + '\n<div class="board-shell">')
    page = page.replace('sight · gated plane ·', 'sight preview · unencrypted · not live ·')
    data = json.dumps(plane, ensure_ascii=False).replace('</', '<\\/')
    page = re.sub(r'<script src="unlock.js"></script>\s*<script src="assets/board.js" defer></script>',
                  lambda m: f'<script>window.__SIGHT_PLANE__ = {data};</script>\n<script>\n' + js.replace('</script', '<\\/script') + '\n</script>', page)
    if 'window.__SIGHT_PLANE__ =' not in page: sys.exit('task-preview: skin template changed; could not inline board.js')
    open(outp, 'w', encoding='utf-8').write(page)
    print(f'task-preview: wrote {outp} ({len(page.encode())} bytes; {len(r)} tasks; new {len(new)}, changed {len(changed)}, done {len(done)}, removed {len(gone)})')
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
