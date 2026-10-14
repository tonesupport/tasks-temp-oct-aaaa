#!/usr/bin/env python3
"""Checks of a task patch, in two tiers.

Usage: python3 check.py [--snapshot snapshot/tasks.toml] [--changes changes.md]
                        [--coverage coverage.md] [--no-almanac] tasks.patch

FAIL (integrity; the result would be a file almanac cannot read): the patch applies to its
base, the result parses as TOML, almanac validate passes, status is in the enum, done has
completed, sched has datetime, created is unchanged, no task blocks itself, ids are
well formed, no content key.
WARN (everything else): removals (named), master-plan codes and ids in titles, tag style,
duration rule, stamps, missing >change lines in notes, the optional changes/coverage files,
and a snapshot hash mismatch ("the file has moved on, check for conflicts").

Applies tasks.patch (a unified diff against the snapshot) in a temp dir, then checks the
result. Exits 1 on any FAIL. Python 3.11+ (tomllib). Stdlib only. Never writes outside a
temp dir. Applying a patch to a real file is `almanac.tcl --file F apply PATCH`.
"""
import hashlib, os, re, shutil, subprocess, sys, tempfile, tomllib

KIT = os.path.dirname(os.path.abspath(__file__))
STATUS_ENUM = ['urgent', 'now', 'progress', 'today', 'later', 'deferred', 'sched', 'done', 'REMOVE']
ID_RE = re.compile(r'^[a-z0-9]{4}$')
STAMP_RE = re.compile(r'^\d{10}$')
TAGS_LINE_RE = re.compile(r"^\[\s*('[^']*'\s*(,\s*'[^']*'\s*)*)?\]$")
# Master-plan workstream codes (inf1, fld5a, SPC2 ...). Titles carry only words; the almanac id is the only id.
PLAN_CODE_RE = re.compile(r'\b(inf|rep|shd|fld|spc|arc|car|lif|tok)\d+[a-z]?\b', re.I)
DATETIME_RE = re.compile(r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{1,2} \d\d$')
TIME_RE = re.compile(r'^\d{1,2}:\d\d[ap]$')
CHANGE_RE = re.compile(r'^\s*[-*]?\s*`?([a-z0-9]{4})`?\s*[|:,\t ]\s*(new|changed|done|delete|remove)\b\s*[|:,\-—\t ]*\s*(.*)$')
CHANGE_LINE_RE = re.compile(r'^>change \(\d\d-\d\d-\d\d \d\d:\d\d [AP]M\): \S')
NON_TASK = {'tasks.spine'}

fails = 0
def out(status, item, detail=''):
    global fails
    fails += status == 'FAIL'
    print(f'{status:4}  {item}' + (f' — {detail}' if detail else ''))

# ---------- strict unified-diff applier (no fuzz, no offset guessing beyond exact search) ----------
class PatchError(Exception):
    pass

HUNK_RE = re.compile(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')

def parse_patch(text):
    lines = text.splitlines(keepends=True)
    files, i = [], 0
    while i < len(lines):
        if lines[i].startswith('--- ') and i + 1 < len(lines) and lines[i + 1].startswith('+++ '):
            cur = {'old': lines[i][4:].split('\t')[0].strip(), 'new': lines[i + 1][4:].split('\t')[0].strip(), 'hunks': []}
            files.append(cur); i += 2; continue
        m = HUNK_RE.match(lines[i])
        if m:
            if not files: raise PatchError('hunk before any ---/+++ file header')
            os_, oc = int(m.group(1)), int(m.group(2) if m.group(2) is not None else 1)
            nc = int(m.group(4) if m.group(4) is not None else 1)
            body, i = [], i + 1
            seen_o = seen_n = 0
            while i < len(lines) and (seen_o < oc or seen_n < nc):
                ln = lines[i]
                if ln.startswith('\\'): i += 1; continue
                tag = ln[:1]
                if tag not in (' ', '-', '+'):
                    if ln in ('\n', '\r\n'): tag, ln = ' ', ' ' + ln  # some tools strip the space on blank context
                    else: raise PatchError(f'bad hunk line {i + 1}: {ln[:40]!r}')
                body.append((tag, ln[1:]))
                seen_o += tag in ' -'; seen_n += tag in ' +'
                i += 1
            while i < len(lines) and lines[i].startswith('\\'):
                # "\ No newline at end of file" applies to the previous line
                if body: body[-1] = (body[-1][0], body[-1][1].rstrip('\n'))
                i += 1
            if seen_o != oc or seen_n != nc: raise PatchError(f'hunk at old line {os_} is truncated')
            files[-1]['hunks'].append({'old_start': os_, 'body': body})
            continue
        i += 1
    return files

def apply_hunks(src_lines, hunks):
    out_, pos = [], 0
    for h in hunks:
        old = [t for tag, t in h['body'] if tag in ' -']
        new = [t for tag, t in h['body'] if tag in ' +']
        start = h['old_start'] - 1 if old else h['old_start']
        if src_lines[start:start + len(old)] != old:
            raise PatchError(f'hunk @@ -{h["old_start"]} does not match the snapshot at that line (patch is not against this snapshot, or was hand-edited)')
        if start < pos: raise PatchError('hunks overlap or are out of order')
        out_.extend(src_lines[pos:start]); out_.extend(new); pos = start + len(old)
    out_.extend(src_lines[pos:])
    return out_

def apply_patch(snapshot_text, patch_text):
    files = parse_patch(patch_text)
    if not files: raise PatchError('no ---/+++ file header found; tasks.patch must be a unified diff')
    if len(files) != 1: raise PatchError(f'patch touches {len(files)} files; only tasks.toml may change')
    f = files[0]
    if not f['hunks']: raise PatchError('patch has no hunks')
    for p in (f['old'], f['new']):
        if not p.endswith('tasks.toml') and p != '/dev/null': raise PatchError(f'patch path {p!r} is not tasks.toml')
    return ''.join(apply_hunks(snapshot_text.splitlines(keepends=True), f['hunks']))

# ---------- task model helpers ----------
def tasks_of(doc):
    return {k: v for k, v in doc.items() if isinstance(v, dict) and k not in NON_TASK and k != 'tasks' and ('status' in v or 'title' in v)}

def raw_tables(text):
    """table name -> list of (lineno, raw line) for that table's body."""
    tabs, cur = {}, None
    for n, ln in enumerate(text.splitlines(), 1):
        m = re.match(r'^\s*\[([^\[\]]+)\]\s*(#.*)?$', ln)
        if m: cur = m.group(1).strip(); tabs.setdefault(cur, []); continue
        if cur is not None: tabs[cur].append((n, ln))
    return tabs

def classify(snap, res):
    new = sorted(set(res) - set(snap)); gone = sorted(set(snap) - set(res))
    changed, done = [], []
    for k in sorted(set(snap) & set(res)):
        if snap[k] != res[k]:
            (done if res[k].get('status') == 'done' and snap[k].get('status') != 'done' else changed).append(k)
    return new, changed, done, gone

def find_tcl():
    for c in (os.path.join(KIT, 'tools', 'deps', 'tcl'), shutil.which('tclsh') or ''):
        if c and os.access(c, os.X_OK):
            try:
                subprocess.run([c], input=b'exit 0\n', capture_output=True, timeout=10, check=True)
                return c
            except Exception:
                continue
    return None

def note_lines(t):
    return [l for l in str(t.get('notes', '')).splitlines() if l.strip()]

def main(argv):
    snap_path = os.path.join(KIT, 'snapshot', 'tasks.toml')
    changes = coverage = None; use_alm = True; rest = []
    it = iter(argv)
    for a in it:
        if a == '--snapshot': snap_path = next(it)
        elif a == '--changes': changes = next(it)
        elif a == '--coverage': coverage = next(it)
        elif a == '--no-almanac': use_alm = False
        elif a in ('-h', '--help'): print(__doc__); return 0
        else: rest.append(a)
    if len(rest) != 1: print(__doc__); return 2
    patch_path = rest[0]
    print(f'== {patch_path} against {snap_path}')

    snap_bytes = open(snap_path, 'rb').read()
    sha_file = os.path.join(os.path.dirname(snap_path), 'SHA256')
    if os.path.isfile(sha_file):
        want = open(sha_file).read().split()[0]
        got = hashlib.sha256(snap_bytes).hexdigest()
        if want == got: out('PASS', 'snapshot matches snapshot/SHA256', got[:16])
        else: out('WARN', 'snapshot differs from snapshot/SHA256', 'your file has moved on; check for conflicts when applying')
    snap_text = snap_bytes.decode('utf-8')
    patch_text = open(patch_path, encoding='utf-8').read()

    tmp = tempfile.mkdtemp(prefix='twk-check-')
    try:
        try:
            res_text = apply_patch(snap_text, patch_text)
            out('PASS', 'patch applies cleanly to the snapshot')
        except PatchError as e:
            out('FAIL', 'patch applies cleanly to the snapshot', str(e)); return finish()
        res_path = os.path.join(tmp, 'tasks.toml')
        open(res_path, 'w', encoding='utf-8').write(res_text)
        try:
            res_doc = tomllib.loads(res_text); out('PASS', 'patched file parses as TOML')
        except Exception as e:
            out('FAIL', 'patched file parses as TOML', str(e)); return finish()
        snap_doc = tomllib.loads(snap_text)
        snap, res = tasks_of(snap_doc), tasks_of(res_doc)
        new, changed, done, gone = classify(snap, res)
        touched = new + changed + done
        print(f'INFO  {len(new)} new, {len(changed)} changed, {len(done)} newly done, {len(gone)} removed')
        if not touched and not gone: out('WARN', 'patch changes no task')
        if gone: out('WARN', f'{len(gone)} task(s) removed by the patch (REMOVE status keeps a task reviewable)', ', '.join(gone))
        marked = [k for k in touched if res[k].get('status') == 'REMOVE' and snap.get(k, {}).get('status') != 'REMOVE']
        if marked: out('WARN', 'tasks set to REMOVE', ', '.join(marked))
        if snap_doc.get('tasks', {}).get('spine') != res_doc.get('tasks', {}).get('spine'):
            out('WARN', '[tasks.spine] changed', 'only change the spine when the request asks for it')
        raw = raw_tables(res_text)
        for k in new:
            if not ID_RE.match(k): out('FAIL', f'[{k}] new id is 4 chars [a-z0-9]')
        mnem = [k for k in new if re.match(r'^[a-z]{1,2}\d{2,3}$|^(.)\1\1', k)]
        if mnem: out('WARN', 'new ids look patterned or mnemonic (almanac allocates ids)', ', '.join(mnem))
        allids = set(res)
        for k in touched:
            t = res[k]; tag = f'[{k}]'
            miss = [f for f in ('title', 'status', 'created', 'updated', 'tags') if f not in t]
            if miss: out('FAIL', f'{tag} required keys', f'missing {miss}')
            st = t.get('status')
            if st not in STATUS_ENUM: out('FAIL', f'{tag} status is one of {"/".join(STATUS_ENUM)}', repr(st))
            if st == 'done' and 'completed' not in t: out('FAIL', f'{tag} status done needs completed')
            if st != 'done' and 'completed' in t and k not in snap: out('WARN', f'{tag} completed on an open task')
            if st == 'sched' and not str(t.get('datetime', '')).strip(): out('FAIL', f'{tag} status sched needs datetime')
            if 'duration' in t and st not in ('now', 'done', 'sched'): out('WARN', f'{tag} duration is meant for now/done/sched')
            if 'datetime' in t and not DATETIME_RE.match(' '.join(str(t['datetime']).split())):
                out('WARN', f'{tag} datetime looks like Ddd Mmm D YY', repr(t['datetime']))
            if 'time' in t and not TIME_RE.match(str(t['time'])): out('WARN', f'{tag} time looks like 9:15a / 12:00p', repr(t['time']))
            if 'content' in t: out('FAIL', f'{tag} no content key (use notes)')
            for f in ('created', 'updated', 'completed'):
                if f in t and not (isinstance(t[f], int) and STAMP_RE.match(str(t[f]))):
                    out('WARN', f'{tag} {f} is a bare YYMMDDhhmm integer', repr(t[f]))
            if isinstance(t.get('created'), int) and isinstance(t.get('updated'), int) and t['updated'] < t['created']:
                out('WARN', f'{tag} updated is earlier than created')
            if k in snap and t.get('created') != snap[k].get('created'): out('FAIL', f'{tag} created never changes on an existing task')
            if k in snap and t.get('updated') == snap[k].get('updated'): out('WARN', f'{tag} updated not bumped (almanac set/done/change stamp it)')
            tags = t.get('tags')
            if not isinstance(tags, list) or not all(isinstance(x, str) for x in tags):
                out('FAIL', f'{tag} tags is an array of strings')
            else:
                if 'task' not in tags: out('FAIL', f"{tag} tags include 'task'", str(tags))
                if 'tasks' in tags: out('FAIL', f"{tag} tags use singular 'task', never 'tasks'")
                if len(set(tags)) != len(tags): out('WARN', f'{tag} duplicate tags', str(tags))
                if PLAN_CODE_RE.search(' '.join(tags)) and k in new: out('WARN', f'{tag} plan code in a new task tag')
            for n, ln in raw.get(k, []):
                m = re.match(r'^\s*tags\s*=\s*(.*?)\s*$', ln)
                if m and not TAGS_LINE_RE.match(m.group(1)):
                    out('WARN', f"{tag} tags usually written as ['task', 'x'] (single-quoted, one line)", f'line {n}: {ln.strip()}')
            title = str(t.get('title', ''))
            if not title.strip(): out('WARN', f'{tag} title is empty')
            pc = PLAN_CODE_RE.search(title)
            if pc: out('WARN', f'{tag} master-plan code in title', pc.group(0))
            if re.search(r'\b' + re.escape(k) + r'\b', title): out('WARN', f'{tag} title carries its own id')
            if re.match(r'^\s*\[?[A-Za-z0-9]{2,5}[\]:.)]\s', title) and not pc: out('WARN', f'{tag} title starts with a code-like prefix', title[:20])
            other = [w for w in re.findall(r'\b[a-z0-9]{4}\b', title) if w in allids and w != k and re.search(r'\d', w)]
            if other: out('WARN', f'{tag} title names other task ids (link with blockers instead)', ', '.join(other))
            for b in t.get('blockers', []) if isinstance(t.get('blockers'), list) else []:
                if b == k: out('FAIL', f'{tag} blocks itself')
                elif b not in allids: out('WARN', f'{tag} blocker {b} not in file')
            if 'tosu' in (tags or []) and t.get('domain') not in ('HH', 'MED', 'CTP', 'FIN', 'DEV') and k in new:
                out('WARN', f'{tag} tosu tag without a personal domain')
            # change history lives in notes: existing text kept, a stamped >change line added
            before = note_lines(snap.get(k, {})); after = note_lines(t)
            lost = [l for l in before if l not in after]
            if lost: out('WARN', f'{tag} existing notes text was removed or edited', lost[0][:60])
            added = [l for l in after if l not in before]
            if not any(CHANGE_LINE_RE.match(l) for l in added):
                out('WARN', f'{tag} no ">change (YY-MM-DD hh:mm AM): why" line added to notes', 'add one with: almanac change ID "why"')
        if touched: out('PASS', 'per-task field checks ran', f'{len(touched)} task(s)')

        if changes: check_changes(changes, new, changed, done, gone)
        if coverage: check_coverage(coverage)

        if use_alm:
            tcl = find_tcl()
            alm = os.path.join(KIT, 'tools', 'scripts', 'almanac.tcl')
            if tcl and os.path.isfile(alm):
                env = dict(os.environ, ALMANAC_SKIP_BOARD_EXPORT='1')
                r = subprocess.run([tcl, alm, '--file', res_path, 'validate'], capture_output=True, text=True, env=env)
                last = (r.stdout.strip().splitlines() or [''])[-1]
                errs = [l for l in r.stdout.splitlines() if l.startswith('error ')]
                soft = [l for l in errs if 'duration only allowed' in l]
                if r.returncode == 0: out('PASS', 'almanac validate on the patched file', last)
                elif errs and len(soft) == len(errs): out('WARN', 'almanac validate reports only the duration rule', f'{len(soft)} task(s)')
                else:
                    out('FAIL', 'almanac validate on the patched file', last or r.stderr.strip()[:200]); print(r.stdout + r.stderr)
            else:
                out('WARN', 'almanac validate skipped', 'no runnable tcl (tools/deps/tcl is linux-x64; tclsh 9 also works)')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return finish()

def check_changes(path, new, changed, done, gone=()):
    print(f'\n== changes {path} (optional; change history now lives in task notes)')
    rows = {}
    for ln in open(path, encoding='utf-8').read().splitlines():
        m = CHANGE_RE.match(ln)
        if m: rows[m.group(1)] = (m.group(2), m.group(3).strip())
    if not rows: out('WARN', 'changes note has lines "id  new|changed|done|remove  why"'); return
    touched = set(new) | set(changed) | set(done) | set(gone)
    missing = sorted(touched - set(rows)); extra = sorted(set(rows) - touched)
    out('WARN' if missing else 'PASS', 'every touched task has a changes line', f'missing {missing}' if missing else f'{len(rows)} lines')
    if extra: out('WARN', 'changes note lists tasks the patch does not touch', str(extra))

def check_coverage(path):
    print(f'\n== coverage {path} (optional)')
    txt = open(path, encoding='utf-8').read()
    rows = [l for l in txt.splitlines() if '->' in l]
    if not rows: out('WARN', 'coverage rows "section -> id[, id] | exists: id | dropped: reason"'); return
    MAP = re.compile(r'^\s*([a-z0-9]{4}(\s*,\s*[a-z0-9]{4})*\b|exists:\s*[a-z0-9]{4}|dropped:\s*\S)', re.I)
    bad = [l for l in rows if not MAP.match(l.split('->', 1)[1])]
    out('WARN' if bad else 'PASS', 'every coverage row maps to ids, exists: id, or dropped: reason', f'{len(bad)} unmapped, e.g. {bad[0][:70]}' if bad else f'{len(rows)} rows')
    reads = re.findall(r'read\s+(\d+)\s+of\s+(\d+)\s+bytes', txt, re.I)
    if not reads: out('WARN', 'read report present ("read X of Y bytes" per input)')
    else:
        short = [(a, b) for a, b in reads if int(a) < int(b)]
        out('WARN' if short else 'PASS', 'every input read in full', f'{len(short)} partial' if short else f'{len(reads)} entries')

def finish():
    print(f'\n{"FAIL" if fails else "PASS"}: {fails} failing item(s). WARN items still need a reader.')
    return 1 if fails else 0

if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
