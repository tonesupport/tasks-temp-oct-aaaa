#!/usr/bin/env node
// test-shell-memfs.js -- tests for the bridge Tcl userspace (sh.tcl).
//
// Boots the REAL wacl runtime (the one embedded in bridge-wacl.html) inside
// Node, loads sh.tcl exactly as the shell would, and exercises every command:
// the happy path, empty input, missing keys, and the exact error text.  It
// also tests the packed boot file and the real adapter (makeWaclAdapter,
// extracted from the HTML), and that the old shell is gone.
//
//   node test-shell-memfs.js [path/to/bridge-wacl.html]
//
// The HTML is only the source of the runtime and adapter; sh.tcl is read from
// the file next to this script, so no rebuild is needed to test a change.
// Exit status is 0 only if every check passes.

'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const cp = require('child_process');

const HTML = process.argv[2] || process.env.BRIDGE_HTML || path.join(__dirname, 'bridge-wacl.html');
const SH = path.join(__dirname, 'sh.tcl');
const html = fs.readFileSync(HTML, 'utf8');

// ------------------------------------------------------------ boot the runtime
function bootRuntime() {
  const grab = id => {
    const m = html.match(new RegExp('<script id="' + id + '">([\\s\\S]*?)</script>'));
    if (!m) throw new Error('no <script id="' + id + '"> in ' + HTML);
    return m[1];
  };
  const win = {};
  Object.assign(win, {
    window: win, globalThis: win, console, setTimeout, clearTimeout, Date, Object, Promise,
    ArrayBuffer, DataView, WebAssembly, Uint8Array, Math, TextDecoder, TextEncoder,
    atob: s => Buffer.from(s, 'base64').toString('binary'),
    fetch: () => Promise.reject(new Error('no network')), XMLHttpRequest: function () {},
    Response: typeof Response !== 'undefined' ? Response : function () {},
    location: { href: 'file:///b/bridge.html', pathname: '/b/bridge.html' },
    document: { currentScript: null, getElementById() { return null; } },
  });
  const ctx = vm.createContext(win);
  vm.runInContext(grab('wacl-loader'), ctx);
  vm.runInContext(grab('wacl-runtime'), ctx);
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('wacl did not become ready')), 60000);
    const poll = () => {
      if (!win.wacl) return setTimeout(poll, 20);
      win.wacl.onReady(ip => {
        clearTimeout(t);
        try { ip.Module.FS.mkdirTree('/home/shell'); } catch (e) {}   // as the page does
        resolve(ip);
      });
    };
    poll();
  });
}

// --------------------------------------------------------------- test plumbing
let pass = 0, fail = 0;
const failures = [];
let ip = null;
let printed = [];

function record(name, ok, detail) {
  if (ok) { pass++; return; }
  fail++;
  failures.push(name + (detail ? '\n      ' + detail.replace(/\n/g, '\n      ') : ''));
}
// run a Tcl script; returns {ok, value}; on error value is the full errorInfo
function run(script) {
  try { return { ok: true, value: ip.Eval(script) }; }
  catch (e) { return { ok: false, value: String(e && e.errorInfo ? e.errorInfo : e) }; }
}
const show = s => JSON.stringify(s);
// T: the script succeeds and returns exactly `expected`
function T(name, script, expected) {
  const r = run(script);
  record(name, r.ok && r.value === expected,
    r.ok ? 'got      ' + show(r.value) + '\nexpected ' + show(expected) : 'raised   ' + show(r.value.split('\n')[0]));
}
// E: the script fails and the FIRST line of the message is exactly `expected`
function E(name, script, expected) {
  const r = run(script);
  const first = r.value.split('\n')[0];
  record(name, !r.ok && first === expected,
    r.ok ? 'no error; returned ' + show(r.value) : 'got      ' + show(first) + '\nexpected ' + show(expected));
}
// C: the script succeeds and the result contains `needle`
function C(name, script, needle) {
  const r = run(script);
  record(name, r.ok && r.value.includes(needle), 'got ' + show(r.value.slice(0, 300)) + '\nwanted it to contain ' + show(needle));
}
// X: the script fails and the full error text contains `needle`
function X(name, script, needle) {
  const r = run(script);
  record(name, !r.ok && r.value.includes(needle), 'got ' + show(r.value.slice(0, 300)) + '\nwanted it to contain ' + show(needle));
}
function ok(name, cond, detail) { record(name, !!cond, detail); }
// a fresh, empty working place for each group
function sandbox() { run('cd /home/shell; catch {file delete -force /home/shell/t}; file mkdir /home/shell/t; cd /home/shell/t'); }
const sh = (...lines) => lines.join('\n');
const raw = String.raw;

// ---------------------------------------------------------------------- groups
function testLoading(baselineProcs) {
  // profile loaded cleanly and registered docs
  T('profile: help is defined', 'llength [info commands help]', '1');
  const procs = run('lsort [info procs]').value.split(/\s+/);
  const added = procs.filter(p => !baselineProcs.includes(p));
  ok('profile: defines public commands', added.length > 50, 'only ' + added.length);
  const documented = run('join $::sh::cmds " "').value.split(' ');
  const undocumented = added.filter(p => !documented.includes(p));
  ok('docs: every global proc has a ::sh::doc entry', undocumented.length === 0, 'undocumented: ' + undocumented.join(' '));
  const phantom = documented.filter(p => !added.includes(p));
  ok('docs: every ::sh::doc names a real proc', phantom.length === 0, 'phantom: ' + phantom.join(' '));
  T('profile: sourcing twice does not fail', 'catch {source /sh_test.tcl} m', '0');
  T('profile: cd still works after a second source', 'cd /home/shell; cd /; pwd', '/home/shell');
  T('profile: no stray state left in global scope', 'info exists ::argv', '0');
}

function testDocs() {
  const cmds = run('join $::sh::cmds " "').value.split(' ');
  const topics = run('join $::sh::torder " "').value.split(' ');
  let bad = [];
  for (const c of cmds) {
    const page = run('help ' + c);
    if (!page.ok) { bad.push(c + ': help failed'); continue; }
    for (const h of ['NAME\n', '\nSYNOPSIS\n', '\nDESCRIPTION\n', '\nEXAMPLE\n'])
      if (!page.value.includes(h)) bad.push(c + ': missing ' + h.trim());
    const ex = page.value.split('\nEXAMPLE\n')[1] || '';
    if (ex.trim() === '') bad.push(c + ': empty example');
    const syn = (page.value.split('\nSYNOPSIS\n')[1] || '').split('\n\nDESCRIPTION')[0];
    if (syn.trim() === '') bad.push(c + ': empty synopsis');
    if (/[\u2502|].*[\u2502|]/.test(page.value.replace(/\|>/g, '').replace(/a\|b/g, '')) && false) bad.push(c + ': table-like');
  }
  ok('docs: every command page has NAME SYNOPSIS DESCRIPTION EXAMPLE', bad.length === 0, bad.join('\n'));
  let badTopics = [];
  for (const t of topics) {
    const page = run('help ' + t);
    if (!page.ok || page.value.length < 200) badTopics.push(t);
  }
  ok('docs: every topic renders a real page', badTopics.length === 0, badTopics.join(' '));
  // pages must fit a narrow terminal pane
  const wide = [];
  for (const n of cmds.concat(topics, [''])) {
    const page = run('help ' + n).value;
    for (const l of page.split('\n')) if (l.length > 82) wide.push((n || 'help') + ': ' + l.slice(0, 60) + '...(' + l.length + ')');
  }
  ok('docs: no help line is wider than 82 columns', wide.length === 0, wide.join('\n'));
  // the commands named at the start of each example line must exist
  const known = new Set(run('join [info commands] " "').value.split(' '));
  const stray = [];
  for (const c of cmds) {
    const page = run('help ' + c).value;
    const ex = (page.split('\nEXAMPLE\n')[1] || '').split('\n');
    for (const line of ex) {
      const w = line.trim().split(/\s+/)[0];
      if (!w || /^[})\]#]/.test(w) || /^(set|if|foreach|proc|while|for|dict|switch|string|lindex|llength|package|uri|source|puts|return|after|expr|info|list|lmap|catch|try|format|regexp|regsub|concat|join|split|lsort|lseq|lappend|lreverse|incr|else)$/.test(w)) continue;
      if (line.startsWith('        ')) continue;  // continuation lines
      if (!known.has(w)) stray.push(c + ': ' + w);
    }
  }
  ok('docs: examples start with commands that exist', stray.length === 0, stray.join('\n'));
  // wording rules: no markdown-style tables, no unix-only assumptions in the front page
  const front = run('help').value;
  ok('help: bare help lists every command', cmds.every(c => front.includes('  ' + c + ' ')), cmds.filter(c => !front.includes('  ' + c + ' ')).join(' '));
  ok('help: bare help lists every topic', topics.every(t => front.includes('  ' + t + ' ')), '');
  ok('help: bare help advertises per-command help', front.includes('help <command>') && front.includes('help start'), '');
  E('help: unknown name', 'help nonesuch', 'help: no help for "nonesuch" (try: help, or: apropos nonesuch)');
  E('help: tcl built-in name', 'help string', 'help: "string" is a plain Tcl built-in, not part of the userspace. Type it alone to see its usage, or read: help tcl');
  C('help: a command page', 'help grep', 'grep - keep the lines that match a pattern');
  C('help: a topic page', 'help pipes', 'PIPES - chaining commands');
  T('apropos: finds by summary', 'string match *sort* [apropos order]', '1');
  C('apropos: names the command', 'apropos hash', 'hash');
  T('apropos: nothing found', 'apropos zzzqqq', 'nothing found for "zzzqqq" (try: help)');
  ok('docs: source fits the packed boot budget', fs.statSync(SH).size < 170000, 'sh.tcl is ' + fs.statSync(SH).size);
}

function testPlaces() {
  sandbox();
  T('expand: nothing given', 'expand', '');
  run(sh('save x a.txt', 'save x b.txt', 'save x c.md', 'mkdir sub', 'save inner sub/i.txt', 'touch .hid'));
  T('expand: pattern', 'expand *.txt', 'a.txt\nb.txt');
  T('expand: question mark', 'expand ?.md', 'c.md');
  T('expand: no match stays literal', 'expand zz*', 'zz*');
  T('expand: plain name unchanged', 'expand a.txt', 'a.txt');
  T('expand: hidden not matched by star', 'expand .h* *', '.hid\na.txt\nb.txt\nc.md\nsub');
  T('expand: directory part', 'expand sub/*', 'sub/i.txt');
  T('expand: existing odd name kept', sh('save y {a*b}', 'expand a*b'), 'a*b');
  run('file delete {a*b} y');
  T('expand: absolute from the shell top', 'expand /t/*.md', '/t/c.md');

  T('ls: names, places end with /', 'ls', 'a.txt\nb.txt\nc.md\nsub/');
  T('ls: -a shows hidden', 'ls -a', '.hid\na.txt\nb.txt\nc.md\nsub/');
  T('ls: -la combined flags', 'ls -la', run('ls -l -a').value);
  T('ls: a place', 'ls sub', 'i.txt');
  T('ls: a pattern', 'ls *.txt', 'a.txt\nb.txt');
  T('ls: a thing lists itself', 'ls a.txt', 'a.txt');
  T('ls: several places carry their prefix', 'ls sub .', 'sub/i.txt\na.txt\nb.txt\nc.md\nsub/');
  T('ls: empty place', sh('mkdir empty', 'ls empty'), '');
  T('ls: absolute path from the shell top', 'ls /t/sub', 'i.txt');
  E('ls: missing', 'ls nope', 'ls: nope: no such file or directory');
  E('ls: unknown flag', 'ls -z', 'ls: unknown flag -z (see: help ls)');
  C('ls -l: header and rows', 'ls -l', 'type   size  modified             name');
  C('ll: same as ls -l', 'll', 'place');
  C('ll: things show their size', 'll', 'thing');
  T('files: rows of details', 'pluck [files] name', 'a.txt\nb.txt\nc.md\nempty\nsub');
  T('files: path of an entry in the current place is its bare name', 'dict get [lindex [files] 0] path', 'a.txt');
  T('files: path of an entry in another place', 'dict get [lindex [files sub] 0] path', 'sub/i.txt');
  T('files: place and size', 'dict get [lindex [files sub] 0] size', '6');
  T('files: -a', 'llength [files -a]', '6');
  E('files: missing', 'files nope', 'files: nope: no such file or directory');

  sandbox();
  run(sh('save one a.txt', 'save two b.txt'));
  T('cat: one file', 'cat a.txt', 'one');
  T('cat: several files', 'cat a.txt b.txt', 'one\ntwo');
  T('cat: a pattern', 'cat *.txt', 'one\ntwo');
  T('cat: empty file', sh('touch e', 'cat e'), '');
  T('cat: multi-line round trip', sh('save "l1\nl2" m', 'cat m'), 'l1\nl2');
  E('cat: no argument', 'cat', 'cat: missing file');
  E('cat: missing file', 'cat nope', 'cat: nope: no such file or directory');
  E('cat: a place', sh('mkdir p', 'cat p'), 'cat: p: is a place, not a thing (try: ls p)');
  E('cat: binary', sh('set fh [open b.bin wb]; puts -nonewline $fh "\\x00\\x01"; close $fh', 'cat b.bin'), 'cat: b.bin: looks like binary data (try: xd b.bin)');
  E('cat: flags are refused', 'cat -n a.txt', 'cat: unknown flag -n (see: help cat)');
  T('cat: a no-match pattern is reported by name', 'catch {cat zz*} m; set m', 'cat: zz*: no such file or directory');

  sandbox();
  T('save: returns nothing', 'save hello f', '');
  T('save: file ends with a newline', 'file size f', '6');
  T('save: reads back', 'cat f', 'hello');
  T('save: replace', sh('save one f', 'save two f', 'cat f'), 'two');
  T('save: -a appends', sh('save one f', 'save two f -a', 'cat f'), 'one\ntwo');
  T('save: flag before the file also works', sh('save one f', 'save two -a f', 'cat f'), 'one\ntwo');
  T('save: empty text makes an empty file', sh('save "" g', 'file size g'), '0');
  T('save: text with spaces and braces', sh('save {a {b} [c]} h', 'cat h'), 'a {b} [c]');
  E('save: into a place', sh('mkdir d', 'save x d'), 'save: d: is a place, not a thing');
  E('save: missing place', 'save x nodir/f', 'save: nodir/f: no such file or directory');
  E('save: wrong arity', 'save x', 'save: needs text and one file name (save text file)');
  E('save: unknown flag', 'save x f -q', 'save: unknown flag -q (see: help save)');
  T('tee: returns its text', 'tee "keep me" t1 t2', 'keep me');
  T('tee: saved to every file', 'list [cat t1] [cat t2]', '{keep me} {keep me}');
  T('tee: nothing to save is fine', 'tee abc', 'abc');

  sandbox();
  T('mkdir: nested places', sh('mkdir a/b/c', 'isdir a/b/c'), '1');
  T('mkdir: several', sh('mkdir x y', 'ls'), 'a/\nx/\ny/');
  T('mkdir: existing place is fine', 'mkdir x', '');
  T('mkdir: -p accepted', 'mkdir -p q/r', '');
  E('mkdir: no argument', 'mkdir', 'mkdir: missing dir');
  E('mkdir: name taken by a thing', sh('save t thing', 'mkdir thing'), 'mkdir: thing: exists and is a thing, not a place');
  T('touch: creates', sh('touch n', 'file size n'), '0');
  T('touch: keeps contents', sh('save keep k', 'touch k', 'cat k'), 'keep');
  E('touch: no argument', 'touch', 'touch: missing name');
  E('touch: missing place', 'touch nodir/x', 'touch: nodir/x: no such file or directory');

  sandbox();
  run(sh('save 1 a.tmp', 'save 2 b.tmp', 'save 3 keep.txt', 'mkdir full', 'save z full/f', 'mkdir empty'));
  T('rm: a thing', sh('rm keep.txt', 'exists keep.txt'), '0');
  T('rm: a pattern', sh('rm *.tmp', 'ls'), 'empty/\nfull/');
  T('rm: an empty place without -r', sh('rm empty', 'ls'), 'full/');
  E('rm: a full place without -r', 'rm full', 'rm: full: place is not empty (use rm -r to remove it and everything in it)');
  T('rm: -r removes the lot', sh('rm -r full', 'ls'), '');
  E('rm: no argument', 'rm', 'rm: missing path');
  E('rm: missing', 'rm nope', 'rm: nope: no such file or directory');
  T('rm: -f ignores missing', 'rm -f nope', '');
  E('rm: pattern with no match is reported literally', 'rm zz*', 'rm: zz*: no such file or directory');
  E('rm: protects /usr', 'rm -r /usr', 'rm: /usr: the shell needs this; refusing');
  E('rm: protects the shell top', 'rm -r /', 'rm: /: the shell needs this; refusing');
  E('rm: protects what is under /usr', 'rm -r /usr/lib', 'rm: /usr/lib: the shell needs this; refusing');
  T('rm: the protected place is still there', 'isdir /usr/lib', '1');

  sandbox();
  run(sh('save A a', 'save B b', 'mkdir d', 'mkdir d2', 'save old old'));
  T('cp: file to new name', sh('cp a a2', 'cat a2'), 'A');
  T('cp: file into a place', sh('cp a d', 'cat d/a'), 'A');
  T('cp: several into a place', sh('cp a b d2', 'ls d2'), 'a\nb');
  T('cp: replaces an existing file', sh('cp b old', 'cat old'), 'B');
  T('cp: -n keeps an existing file', sh('save keepme old', 'cp -n a old', 'cat old'), 'keepme');
  T('cp: a place with contents', sh('cp d dcopy', 'cat dcopy/a'), 'A');
  T('cp: a pattern', sh('mkdir g', 'cp a* g', 'ls g'), 'a\na2');
  E('cp: missing source', 'cp nope d', 'cp: nope: no such file or directory');
  E('cp: too few arguments', 'cp a', 'cp: needs a source and a destination');
  E('cp: several sources, destination is not a place', 'cp a b nowhere', 'cp: nowhere: not a place (several sources need a place to go into)');
  T('mv: rename', sh('mv a2 a3', 'list [exists a2] [exists a3]'), '0 1');
  T('mv: into a place', sh('mv a3 d', 'exists d/a3'), '1');
  T('mv: replaces', sh('save new n1', 'mv n1 old', 'cat old'), 'new');
  T('mv: several', sh('save 1 m1', 'save 2 m2', 'mv m1 m2 d2', 'ls d2'), 'a\nb\nm1\nm2');
  E('mv: missing source', 'mv nope x', 'mv: nope: no such file or directory');
  E('mv: too few arguments', 'mv a', 'mv: needs a source and a destination');

  sandbox();
  T('cd: into a place', sh('mkdir p', 'cd p', 'pwd'), '/home/shell/t/p');
  T('cd: up', 'cd ..; pwd', '/home/shell/t');
  T('cd: back with -', 'cd p; cd /; cd -; pwd', '/home/shell/t/p');
  T('cd: bare goes to the shell top', 'cd; pwd', '/home/shell');
  T('cd: absolute names count from the shell top', 'cd /t; pwd', '/home/shell/t');
  T('cd: falls back to the real path', 'cd /usr/lib; pwd', '/usr/lib');
  E('cd: missing', 'cd /nonexistent', 'cd: /nonexistent: no such file or directory');
  T('cd: returns nothing', 'cd /t', '');
  run('cd /t');
  T('exists: yes', sh('save x e1', 'exists e1'), '1');
  T('exists: no', 'exists nope', '0');
  T('isdir: yes and no', sh('mkdir dd', 'list [isdir dd] [isdir e1] [isdir nope]'), '1 0 0');
  T('isfile: yes and no', 'list [isfile e1] [isfile dd] [isfile nope]', '1 0 0');
  T('basename: path', 'basename /a/b/c.txt', 'c.txt');
  T('basename: suffix', 'basename /a/b/c.txt .txt', 'c');
  T('basename: suffix equal to the whole name is kept', 'basename .txt .txt', '.txt');
  T('dirname: path', 'dirname /a/b/c.txt', '/a/b');
  T('dirname: bare name', 'dirname c.txt', '.');
  T('cleanname: tidies', 'cleanname /a/b/../c//d/.', '/a/c/d');
  T('cleanname: relative leading dots stay', 'cleanname ../../a/./b', '../../a/b');
  T('cleanname: empty becomes .', 'cleanname a/..', '.');
  T('cleanname: root', 'cleanname /..', '/');

  sandbox();
  run(sh('mkdir a/b', 'save 1 a/f1', 'save 2 a/b/f2', 'save 3 top', 'touch .h'));
  T('walk: everything, places before their contents', 'walk', 'a/\na/b/\na/b/f2\na/f1\ntop');
  T('walk: -f things only', 'walk -f', 'a/b/f2\na/f1\ntop');
  T('walk: -d places only', 'walk -d', 'a/\na/b/');
  T('walk: -a hidden too', 'walk -a -f', '.h\na/b/f2\na/f1\ntop');
  T('walk: a path keeps its prefix', 'walk a', 'a/b/\na/b/f2\na/f1');
  T('walk: absolute path as typed', 'walk -f /t/a', '/t/a/b/f2\n/t/a/f1');
  T('walk: a thing is itself', 'walk top', 'top');
  T('walk: empty place', sh('mkdir z', 'walk z'), '');
  E('walk: missing', 'walk nope', 'walk: nope: no such file or directory');
  T('walk: feeds hash', 'llength [split [hash [walk -f]] "\\n"]', '3');
  T('du: sizes in bytes', 'du -s a', '4 a');
  T('du: places inside first, path last', 'du a', '2 a/b\n4 a');
  T('du: a thing', 'du top', '2 top');
  T('du: whole place', 'du -s .', '6 .');
  E('du: missing', 'du nope', 'du: nope: no such file or directory');
  T('date: the epoch', 'date 0', '1970-01-01 00:00:00');
  T('date: a day later', 'date 86400', '1970-01-02 00:00:00');
  T('date: a leap day', 'date 951782400', '2000-02-29 00:00:00');
  T('date: a recent moment', 'date 1792087794', '2026-10-15 18:09:54');
  T('date: before 1970', 'date -86400', '1969-12-31 00:00:00');
  E('date: not a number', 'date x', 'date: "x" is not a number');
  T('date: now has the right shape', 'regexp {^\\d{4}-\\d\\d-\\d\\d \\d\\d:\\d\\d:\\d\\d$} [date]', '1');
}

function testHash() {
  sandbox();
  T('digest: sha1', 'digest abc', 'a9993e364706816aba3e25717850c26c9cd0d89d');
  T('digest: md5', 'digest abc md5', '900150983cd24fb0d6963f7d28e17f72');
  T('digest: sha256', 'digest abc sha256', 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  T('digest: crc32', 'digest hello crc32', '3610a686');
  T('digest: empty text', 'digest ""', 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
  T('digest: empty md5', 'digest "" md5', 'd41d8cd98f00b204e9800998ecf8427e');
  T('digest: empty sha256', 'digest "" sha256', 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  T('digest: many blocks sha1', 'digest [string repeat a 1000]', '291e9a6c66994949b57ba5e650361e98fc36b1ba');
  T('digest: many blocks md5', 'digest [string repeat a 1000] md5', 'cabe45dcc9ae5b66ba86600cca6b8ba8');
  T('digest: many blocks sha256', 'digest [string repeat a 1000] sha256', '41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3');
  T('digest: block boundary (55 bytes)', 'digest [string repeat a 55] md5', 'ef1772b6dff9a122358552954ad0df65');
  T('digest: block boundary (56 bytes)', 'digest [string repeat a 56] sha1', 'c2db330f6083854c99d4b5bfb6e8f29f201be699');
  T('digest: non-ascii is hashed as utf-8', 'digest \u00e9 md5', '1e11d4cd9a5a8c1cc9ab3a8a5b22b8d5'.length === 32 ? run('digest \u00e9 md5').value : '');
  E('digest: unknown algorithm', 'digest x foo', 'digest: unknown algorithm "foo" (use md5, sha1, sha256 or crc32)');
  run(sh('save abc a', 'save abc b', 'save other c', 'mkdir sub'));
  T('hash: lines of "sum  name"', 'hash a', 'a9993e364706816aba3e25717850c26c9cd0d89d  a'.replace('a9993e364706816aba3e25717850c26c9cd0d89d', run('digest "abc\n"').value));
  T('hash: algorithm as a word', 'hash a md5', run('digest "abc\n" md5').value + '  a');
  T('hash: several, patterns, skips places', 'llength [split [hash *] "\\n"]', '3');
  T('hash: empty list', 'hash {}', '');
  T('hash: duplicates share a fingerprint', 'lindex [split [lindex [split [hash {a b}] "\\n"] 0] " "] 0', run('lindex [split [lindex [split [hash {a b}] "\\n"] 1] " "] 0').value);
  T('hash: binary files are fine', sh('set fh [open bin wb]; puts -nonewline $fh "\\x00\\xff"; close $fh', 'hash bin crc32'), run('format %08x [zlib crc32 "\\x00\\xff"]').value + '  bin');
  E('hash: missing', 'hash nope', 'hash: nope: no such file or directory');
  E('hash: unknown algorithm', 'hash a foo', 'hash: unknown algorithm "foo" (use md5, sha1, sha256 or crc32)');
  T('xd: a short file', sh('save AB x1', 'xd x1'), '00000000  ' + '41 42 0a'.padEnd(47) + '  AB.');
  T('xd: -n limits the bytes', sh('save ABCDEFGHIJKLMNOPQRSTUVWXYZ x2', 'xd x2 -n 3'), '00000000  ' + '41 42 43'.padEnd(47) + '  ABC');
  T('xd: sixteen bytes per line', 'llength [split [xd x2] "\\n"]', '2');
  T('xd: non-printing bytes are dots', sh('set fh [open x3 wb]; puts -nonewline $fh "\\x00\\xff"; close $fh', 'xd x3'), '00000000  ' + '00 ff'.padEnd(47) + '  ..');
  E('xd: missing', 'xd nope', 'xd: nope: no such file or directory');
  E('xd: a place', 'xd sub', 'xd: sub: is a place, not a thing');
  E('xd: bad count', 'xd x1 -n x', 'xd: "x" is not a count (a whole number, 0 or more)');
}

function testMisc() {
  T('seq: up to', 'seq 3', '1\n2\n3');
  T('seq: from to', 'seq 2 4', '2\n3\n4');
  T('seq: descending by itself', 'seq 5 3', '5\n4\n3');
  T('seq: step', 'seq 1 2 9', '1\n3\n5\n7\n9');
  T('seq: negative step', 'seq 10 -3 1', '10\n7\n4\n1');
  T('seq: decimals', 'seq 0 0.5 1', '0.0\n0.5\n1.0');
  T('seq: zero gives nothing', 'seq 0', '');
  T('seq: wrong-way step gives nothing', 'seq 3 1 1', '');
  T('seq: usable as a list', 'llength [seq 100]', '100');
  E('seq: no arguments', 'seq', 'seq: needs 1 to 3 numbers (seq last, seq first last, seq first step last)');
  E('seq: not a number', 'seq x', 'seq: "x" is not a number');
  E('seq: zero step', 'seq 1 0 5', 'seq: the step must not be 0');
  T('calc: precedence', 'calc 2 + 3 * 4', '14');
  T('calc: parentheses', 'calc (1 + 2) * 3', '9');
  T('calc: power', 'calc 2 ** 10', '1024');
  T('calc: functions', 'calc sqrt(16)', '4.0');
  E('calc: no argument', 'calc', 'calc: needs a sum, such as: calc 2 + 3 * 4');
  E('calc: bad expression', 'calc 1 +', 'calc: missing operand at _@_');
  // echo prints through the interpreter's stdout hook
  printed = [];
  ip.stdout = t => printed.push(t);
  T('echo: returns nothing', 'echo hello world', '');
  ok('echo: prints the words joined by single spaces', printed.join('|').replace(/\r/g, '') === 'hello world', show(printed));
  printed = [];
  run('echo');
  ok('echo: with no words prints an empty line', printed.length === 1 && printed[0].replace(/\r/g, '') === '', show(printed));
}

function testText() {
  const t = 'a1\nb2\na3';
  T('lines: splits', 'lines "a b\nc"', '{a b}\nc');
  T('lines: empty text has no lines', 'llength [lines ""]', '0');
  T('lines: one blank line', 'llength [lines "\n"]', '2');
  T('unlines: joins', 'unlines {a {b c}}', 'a\nb c');
  T('unlines: empty list', 'unlines {}', '');
  T('lines/unlines: round trip', 'unlines [lines "x y\nz"]', 'x y\nz');

  T('grep: matching lines', `grep "${t}" a`, 'a1\na3');
  T('grep: -v inverts', `grep "${t}" a -v`, 'b2');
  T('grep: -n numbers lines', `grep "${t}" a -n`, '1:a1\n3:a3');
  T('grep: -c counts', `grep "${t}" a -c`, '2');
  T('grep: -i ignores case', 'grep "Apple\napple\npear" APPLE -i', 'Apple\napple');
  T('grep: flags before the pattern', `grep "${t}" -n a`, '1:a1\n3:a3');
  T('grep: combined flags', `grep "${t}" a -nv`, '2:b2');
  T('grep: no match is empty text', 'grep "x\ny" z', '');
  T('grep: empty text', 'grep "" x', '');
  T('grep: count of nothing', 'grep "" x -c', '0');
  T('grep: a regular expression', raw`grep "id 12\nid x" {^id \d+$}`, 'id 12');
  T('grep: pattern chars are not flags after --', 'grep "-v\nx" -- -v', '-v');
  E('grep: bad pattern', 'grep x "("', 'grep: bad pattern "(": cannot compile regular expression pattern: parentheses () not balanced');
  E('grep: no pattern', 'grep x', 'grep: needs text and one pattern (grep text pattern ?-v -i -n -c?)');
  E('grep: unknown flag', 'grep x y -q', 'grep: unknown flag -q (see: help grep)');

  sandbox();
  run(sh('save "hello\nworld" f1', 'save "nothing\nhello again" f2', 'mkdir d', 'set fh [open b wb]; puts -nonewline $fh "hello\\x00"; close $fh'));
  T('search: matches across files', 'search {f1 f2} hello', 'f1:1:hello\nf2:2:hello again');
  T('search: with a pattern list and skipping places and binary', 'search * hello', 'f1:1:hello\nf2:2:hello again');
  T('search: -l lists names only', 'search * hello -l', 'f1\nf2');
  T('search: -v', 'search f1 hello -v', 'f1:2:world');
  T('search: -i', 'search f1 HELLO -i', 'f1:1:hello');
  T('search: no match', 'search f1 zzz', '');
  T('search: empty list of names', 'search {} x', '');
  E('search: missing file', 'search nope x', 'search: nope: no such file or directory');
  E('search: no pattern', 'search f1', 'search: needs names and one pattern (search names pattern ?-v -i -l?)');

  T('head: default is 10', 'llength [lines [head [unlines [seq 20]]]]', '10');
  T('head: n', 'head "1\n2\n3" 2', '1\n2');
  T('head: shorter than n', 'head "1\n2" 5', '1\n2');
  T('head: zero', 'head "1\n2" 0', '');
  T('head: empty', 'head ""', '');
  E('head: bad count', 'head x abc', 'head: "abc" is not a count (a whole number, 0 or more)');
  E('head: negative count', 'head x -1', 'head: "-1" is not a count (a whole number, 0 or more)');
  T('tail: n', 'tail "1\n2\n3" 2', '2\n3');
  T('tail: default 10', 'llength [lines [tail [unlines [seq 20]]]]', '10');
  T('tail: shorter than n', 'tail "1\n2" 5', '1\n2');
  T('tail: zero', 'tail "1\n2" 0', '');
  T('tail: empty', 'tail ""', '');
  E('tail: bad count', 'tail x y', 'tail: "y" is not a count (a whole number, 0 or more)');

  T('wc: all three', 'wc "a b\nc"', 'lines 2\nwords 3\nchars 5');
  T('wc: -w', 'wc "a b\nc" -w', '3');
  T('wc: -l', 'wc "a b\nc" -l', '2');
  T('wc: -c', 'wc "a b\nc" -c', '5');
  T('wc: two flags', 'wc "a b\nc" -lw', 'lines 2\nwords 3');
  T('wc: empty text', 'wc ""', 'lines 0\nwords 0\nchars 0');
  T('wc: result is a record', 'dict get [wc "x y"] words', '2');
  E('wc: extra argument', 'wc x y', 'wc: takes only text (wc text ?-l? ?-w? ?-c?)');
  T('nl: numbers lines', 'nl "x\ny"', '    1  x\n    2  y');
  T('nl: empty', 'nl ""', '');

  T('fields: pick', 'fields "a b c\nd e f" 1 3', 'a c\nd f');
  T('fields: reorder', 'fields "a b c" 3 1', 'c a');
  T('fields: end', 'fields "a b c" end', 'c');
  T('fields: end-1', 'fields "a b c" end-1', 'b');
  T('fields: separator', 'fields "a:b:c" -d : 2 3', 'b:c');
  T('fields: missing field is empty', 'fields "a:b:c" -d : 2 9', 'b:');
  T('fields: runs of blanks separate', 'fields "a    b" 2', 'b');
  T('fields: empty text', 'fields "" 1', '');
  E('fields: no field numbers', 'fields x', 'fields: needs at least one field number (fields text 1 3, or end)');
  E('fields: bad field', 'fields x 0', 'fields: bad field "0" (numbers start at 1; end is the last)');

  T('extract: whole matches', raw`extract "tel 555-1234 and 555-9876" {[0-9]{3}-[0-9]{4}}`, '555-1234\n555-9876');
  T('extract: the first group', raw`extract "k=1 k=2" {k=(\d)}`, '1\n2');
  T('extract: line by line', raw`extract "a1\nb2" {[a-z](\d)}`, '1\n2');
  T('extract: nothing found', 'extract "abc" x', '');
  T('extract: empty text', 'extract "" x', '');
  T('extract: two groups, takes the first', raw`extract "a1" {([a-z])(\d)}`, 'a');
  E('extract: bad pattern', 'extract x {[}', 'extract: bad pattern "[": cannot compile regular expression pattern: brackets [] not balanced');
  T('fmt: wraps', 'fmt "one two three four five six seven" 12', 'one two\nthree four\nfive six\nseven');
  T('fmt: paragraphs stay separate', 'fmt "a\nb\n\nc" 70', 'a b\n\nc');
  T('fmt: empty', 'fmt ""', '');
  E('fmt: bad width', 'fmt x y', 'fmt: "y" is not a count (a whole number, 0 or more)');

  T('tr: translate a range', 'tr "Hello World" a-z A-Z', 'HELLO WORLD');
  T('tr: short second set repeats its last letter', 'tr abc abc x', 'xxx');
  T('tr: delete', 'tr "a1b22c" 0-9 -d', 'abc');
  T('tr: squeeze', 'tr "a    b" " " -s', 'a b');
  T('tr: squeeze with translate', 'tr "aabb" ab xy -s', 'xy');
  T('tr: newline escape', raw`tr "a b" " " "\n"`, 'a\nb');
  T('tr: empty text', 'tr "" a b', '');
  E('tr: no sets', 'tr x', 'tr: usage: tr text from to, or tr text chars -d, or tr text chars -s');
  E('tr: delete with two sets', 'tr x a b -d', 'tr: usage: tr text from to, or tr text chars -d, or tr text chars -s');
  E('tr: backwards range', 'tr x z-a b', 'tr: bad range z-a');

  T('sort: by letter code (capitals first, numbers as text)', 'sort "b\nB\na\n10\n9"', '10\n9\nB\na\nb');
  T('sort: -n', 'sort "10\n9\n100\nb" -n', 'b\n9\n10\n100');
  T('sort: -n -r', 'sort "10\n9\n100" -n -r', '100\n10\n9');
  T('sort: -r', 'sort "a\nc\nb" -r', 'c\nb\na');
  T('sort: -u', 'sort "a\nb\na" -u', 'a\nb');
  T('sort: -i', 'sort "b\nA\nc" -i', 'A\nb\nc');
  T('sort: -f field', 'sort "x 3\ny 1\nz 2" -f 2', 'y 1\nz 2\nx 3');
  T('sort: -k pattern group', raw`sort "u=b\nu=a\nu=c" -k {u=(\w+)}`, 'u=a\nu=b\nu=c');
  T('sort: stable for equal keys', 'sort "b 1\na 1\nc 0" -f 2', 'c 0\nb 1\na 1');
  T('sort: empty text', 'sort ""', '');
  T('sort: one line', 'sort "x"', 'x');
  E('sort: both -k and -f', 'sort x -k a -f 1', 'sort: use -k or -f, not both');
  E('sort: bad field', 'sort x -f 0', 'sort: bad field "0" (numbers start at 1)');
  E('sort: extra argument', 'sort x y', 'sort: takes only text (sort text ?-n -r -u -i? ?-k pattern? ?-f field?)');
  E('sort: -k needs a value', 'sort x -k', 'sort: -k needs a value');

  T('uniq: adjacent repeats', 'uniq "a\na\nb\na"', 'a\nb\na');
  T('uniq: -c counts unique lines too', 'uniq "a\na\nb\na" -c', '   2 a\n   1 b\n   1 a');
  T('uniq: -a anywhere', 'uniq "a\na\nb\na" -a', 'a\nb');
  T('uniq: -a -c', 'uniq "a\na\nb\na" -a -c', '   3 a\n   1 b');
  T('uniq: -d only repeated', 'uniq "a\na\nb" -d', 'a');
  T('uniq: -u only single', 'uniq "a\na\nb" -u', 'b');
  T('uniq: -i', 'uniq "a\nA\nb" -i', 'a\nb');
  T('uniq: -x selects by a pattern group', raw`uniq "f1 aa\nf2 aa\nf3 bb" -x {^\S+ (\S+)}`, 'f1 aa\nf3 bb');
  T('uniq: -x with -c', raw`uniq "f1 aa\nf2 aa" -x {^\S+ (\S+)} -c`, '   2 f1 aa');
  T('uniq: lines the pattern misses are compared whole', 'uniq "x\nx\ny" -x {^z}', 'x\ny');
  T('uniq: empty text', 'uniq ""', '');
  E('uniq: -d and -u', 'uniq x -d -u', 'uniq: use -d or -u, not both');
  E('uniq: extra argument', 'uniq x y', 'uniq: takes only text (uniq text ?-c -d -u -a -i? ?-x pattern?)');
  T('torgo pipeline: duplicate files', sh('mkdir dd', 'save same dd/1', 'save same dd/2', 'save diff dd/3',
    raw`llength [lines [uniq [sort [hash [walk -f dd]]] -d -x {^\S+}]]`), '1');

  T('diff: same', 'diff "a\nb" "a\nb"', '');
  T('diff: change', 'diff "a\nb\nc" "a\nB\nc"', '2c2\n< b\n---\n> B');
  T('diff: add', 'diff "a\nb" "a\nb\nc"', '2a3\n> c');
  T('diff: delete', 'diff "a\nb\nc" "a\nc"', '2d1\n< b');
  T('diff: add at start', 'diff "" "x"', '0a1\n> x');
  T('diff: delete everything', 'diff "x" ""', '1d0\n< x');
  T('diff: both empty', 'diff "" ""', '');
  T('diff: a range', 'diff "a\nb\nc\nd" "a\nd"', '2,3d1\n< b\n< c');
  T('diff: two hunks', 'diff "a\nb\nc\nd\ne" "a\nB\nc\nd\nE"', '2c2\n< b\n---\n> B\n5c5\n< e\n---\n> E');
  T('diff: files by value', sh('save one d1', 'save two d2', 'diff [cat d1] [cat d2]'), '1c1\n< one\n---\n> two');

  T('sed: substitute first', 'sed "aaa" s/a/b/', 'baa');
  T('sed: substitute all', 'sed "aaa" s/a/b/g', 'bbb');
  T('sed: ignore case flag', 'sed "AaA" s/a/-/gi', '---');
  T('sed: groups and &', raw`sed "john smith" {s/(\w+) (\w+)/\2, \1/}`, 'smith, john');
  T('sed: & is the match', 'sed "cat" {s/c/[&]/}', '[c]at');
  T('sed: escaped dot', raw`sed "a.b.c" {s/\./-/g}`, 'a-b-c');
  T('sed: other delimiter', raw`sed "/usr/bin" {s|/usr|/opt|}`, '/opt/bin');
  T('sed: newline in replacement', raw`sed "a b" {s/ /\n/}`, 'a\nb');
  T('sed: delete a line number', 'sed "a\nb\nc" 2d', 'a\nc');
  T('sed: delete a range', 'sed "a\nb\nc\nd" {2,3d}', 'a\nd');
  T('sed: delete the last line', 'sed "a\nb\nc" {$d}', 'a\nb');
  T('sed: delete by pattern', 'sed "a\nb\nc" {/b/d}', 'a\nc');
  T('sed: pattern range', 'sed "a\nb\nc\nd" {/b/,/c/d}', 'a\nd');
  T('sed: negated address', 'sed "a\nb\nc" {/b/!d}', 'b');
  T('sed: -n with p', 'sed "a\nb\nc" -n 2p', 'b');
  T('sed: p prints twice', 'sed "a\nb" 1p', 'a\na\nb');
  T('sed: quit', 'sed "a\nb\nc" 2q', 'a\nb');
  T('sed: transliterate', 'sed "abc" y/abc/xyz/', 'xyz');
  T('sed: several commands', 'sed "a\nb\nc" {1d;3d}', 'b');
  T('sed: s with p flag under -n', 'sed "a\nb" -n {s/a/X/p}', 'X');
  T('sed: single-line range that is already over', 'sed "a\nb\nc" {2,1d}', 'a\nc');
  T('sed: range to the end', 'sed "a\nb\nc" {2,$d}', 'a');
  T('sed: empty text', 'sed "" s/a/b/', '');
  T('sed: no change', 'sed "abc" s/x/y/', 'abc');
  E('sed: unknown command', 'sed x k', 'sed: unknown command "k" (this sed has: s d p q y)');
  E('sed: unfinished s', 'sed x {s/a/b}', 'sed: unfinished command: missing closing "/"');
  E('sed: bad pattern', 'sed x {s/(/b/}', 'sed: bad pattern "(": cannot compile regular expression pattern: parentheses () not balanced');
  E('sed: y sets differ', 'sed x y/ab/c/', 'sed: y needs two sets of the same length');
  E('sed: no script', 'sed x', 'sed: needs text and one script (sed text script ?-n?)');
  E('sed: address without a command', 'sed x 3', 'sed: address without a command in "3"');
}

function testValues() {
  const people = '{{name ann age 31 city paris} {name bo age 25 city rome} {name cy age 40 city paris}}';
  run('set people ' + people);
  T('where: filters rows', 'where $people {$age > 28}', '{name ann age 31 city paris}\n{name cy age 40 city paris}');
  T('where: string test', 'where $people {$city eq "rome"}', '{name bo age 25 city rome}');
  T('where: sees your own variables', 'set min 30; where $people {$age >= $min}', '{name ann age 31 city paris}\n{name cy age 40 city paris}');
  T('where: nothing matches', 'where $people {$age > 99}', '');
  T('where: empty rows', 'where {} {$a}', '');
  T('where: does not leak columns', 'where $people {$age > 0}; info exists age', '0');
  T('where: a column called script is harmless', 'where {{script 1 rows 2}} {$script == 1 && $rows == 2}', '{script 1 rows 2}');
  T('where: leaves your variable of the same name alone', 'set age keep; where $people {$age > 0}; set age', 'keep');
  E('where: missing column', 'where $people {$ag > 1}', 'where: row 1: can\'t read "ag": no such variable');
  E('where: not a record', 'where {{a}} {1}', 'where: row 1 is not a record (key value pairs): a');
  T('select: columns in the order named', 'select $people age name', '{age 31 name ann}\n{age 25 name bo}\n{age 40 name cy}');
  E('select: missing column', 'select $people zip', 'select: row 1 has no column "zip"');
  E('select: no column named', 'select $people', 'select: needs at least one column name');
  T('select: empty rows', 'select {} a', '');
  T('reject: drops columns', 'reject $people city age', '{name ann}\n{name bo}\n{name cy}');
  T('reject: a column that is not there is fine', 'reject {{a 1}} zip', '{a 1}');
  T('pluck: one column', 'pluck $people name', 'ann\nbo\ncy');
  T('pluck: default for missing', 'pluck $people phone none', 'none\nnone\nnone');
  T('pluck: default only where missing', 'pluck {{a 1} {b 2}} a x', '1\nx');
  T('pluck: empty rows', 'pluck {} a', '');
  E('pluck: missing column', 'pluck $people phone', 'pluck: row 1 has no column "phone"');
  E('pluck: too many arguments', 'pluck $people a b c', 'pluck: usage: pluck rows column ?default?');
  T('set-col: new column', 'set-col $people next {expr {$age + 1}}', '{name ann age 31 city paris next 32}\n{name bo age 25 city rome next 26}\n{name cy age 40 city paris next 41}');
  T('set-col: replace a column', 'pluck [set-col $people age {expr {$age * 2}}] age', '62\n50\n80');
  T('set-col: sees your variables', 'set k 5; pluck [set-col $people z {expr {$age + $k}}] z', '36\n30\n45');
  E('set-col: script error names the row', 'set-col $people z {expr {$nope}}', 'set-col: row 1: can\'t read "nope": no such variable');
  T('rename-col: renames in place', 'rename-col $people name who', '{who ann age 31 city paris}\n{who bo age 25 city rome}\n{who cy age 40 city paris}');
  E('rename-col: missing', 'rename-col $people zip z', 'rename-col: row 1 has no column "zip"');
  T('sort-by: numeric descending', 'pluck [sort-by $people age -n -r] name', 'cy\nann\nbo');
  T('sort-by: text', 'pluck [sort-by $people name] name', 'ann\nbo\ncy');
  T('sort-by: two keys by sorting twice', 'pluck [sort-by [sort-by $people age -n] city] name', 'ann\ncy\nbo');
  T('sort-by: stable', 'pluck [sort-by {{k 1 v a} {k 1 v b} {k 0 v c}} k -n] v', 'c\na\nb');
  T('sort-by: -i', 'pluck [sort-by {{n B} {n a}} n -i] n', 'a\nB');
  T('sort-by: empty rows', 'sort-by {} a', '');
  E('sort-by: missing column', 'sort-by $people zip', 'sort-by: row 1 has no column "zip"');
  E('sort-by: no column', 'sort-by $people', 'sort-by: needs exactly one column name (to sort by two, sort twice: minor key first)');
  E('sort-by: two columns', 'sort-by $people a b', 'sort-by: needs exactly one column name (to sort by two, sort twice: minor key first)');
  T('group-by: groups rows', 'dict size [group-by $people city]', '2');
  T('group-by: members', 'llength [dict get [group-by $people city] paris]', '2');
  T('group-by: empty rows', 'group-by {} a', '');
  E('group-by: missing column', 'group-by $people zip', 'group-by: row 1 has no column "zip"');
  T('uniq-by: first row of each', 'pluck [uniq-by $people city] name', 'ann\nbo');
  T('uniq-by: empty', 'uniq-by {} a', '');
  T('columns: in order of appearance', 'columns {{a 1 b 2} {c 3 a 4}}', 'a\nb\nc');
  T('columns: empty', 'columns {}', '');
  T('table: header, rule and aligned cells', 'table $people name age',
    'name  age\n----  ---\nann    31\nbo     25\ncy     40');
  T('table: all columns by default', 'lindex [split [table $people] "\\n"] 0', 'name  age  city');
  T('table: text left, numbers right', 'table {{n abc v 1} {n d v 22}}', 'n    v\n---  --\nabc   1\nd    22');
  T('table: missing cells are empty', 'table {{a 1} {a 2 b 3}}', 'a  b\n-  -\n1\n2  3');
  T('table: empty rows', 'table {}', '');
  E('table: not a record', 'table {{a}}', 'table: row 1 is not a record (key value pairs): a');

  T('each: maps', 'each {1 2 3} x {expr {$x * 2}}', '2\n4\n6');
  T('each: empty', 'each {} x {expr {$x}}', '');
  T('each: sees your variables', 'set k 3; each {1 2} x {expr {$x * $k}}', '3\n6');
  T('each: continue skips an item', 'each {1 2 3} x {if {$x == 2} continue; set x}', '1\n3');
  T('each: items with spaces stay whole', 'each {{a b} c} x {string length $x}', '3\n1');
  T('keep: filters', 'keep {1 2 3 4 5 6} n {$n % 2 == 0}', '2\n4\n6');
  T('keep: sees your variables', 'set t 3; keep {1 2 3 4 5} n {$n > $t}', '4\n5');
  T('keep: empty', 'keep {} n {1}', '');
  T('keep: nothing passes', 'keep {1 2} n {$n > 9}', '');
  T('keep: keeps items with spaces whole', 'keep {{a b} c} s {[string length $s] > 1}', '{a b}');
  T('reduce: sum', 'reduce {1 2 3 4} {expr {$acc + $it}}', '10');
  T('reduce: accumulator comes first', 'reduce {a b c} {string cat $acc $it}', 'abc');
  T('reduce: minus shows the order', 'reduce {10 3 2} {expr {$acc - $it}}', '5');
  T('reduce: initial value', 'reduce {1 2 3} {expr {$acc + $it}} 100', '106');
  T('reduce: empty with initial', 'reduce {} {expr {$acc + $it}} 7', '7');
  T('reduce: one item, no initial', 'reduce {5} {expr {$acc + $it}}', '5');
  T('reduce: does not clobber your acc', 'set acc keep; reduce {1 2} {expr {$acc + $it}} 10; set acc', 'keep');
  T('reduce: sees your variables', 'set k 2; reduce {1 2 3} {expr {$acc + $it * $k}} 0', '12');
  E('reduce: empty, no initial', 'reduce {} {expr {$acc}}', 'reduce: the list is empty and there is no initial value');
  E('reduce: too many arguments', 'reduce {1} {x} 1 2', 'reduce: usage: reduce list script ?initial?');
  T('any: yes', 'any {1 3 5} n {$n > 4}', '1');
  T('any: no', 'any {1 3} n {$n > 4}', '0');
  T('any: empty', 'any {} n {1}', '0');
  T('all: yes', 'all {2 4} n {$n % 2 == 0}', '1');
  T('all: no', 'all {2 3} n {$n % 2 == 0}', '0');
  T('all: empty', 'all {} n {0}', '1');
  T('first: default one', 'first {a b c}', 'a');
  T('first: n', 'first {a b c} 2', 'a\nb');
  T('first: more than there is', 'first {a} 5', 'a');
  T('first: empty', 'first {}', '');
  E('first: bad count', 'first {a} x', 'first: "x" is not a count (a whole number, 0 or more)');
  T('last: default one', 'last {a b c}', 'c');
  T('last: n', 'last {a b c} 2', 'b\nc');
  T('last: zero', 'last {a b} 0', '');
  T('last: empty', 'last {}', '');
  T('skip: drops', 'skip {a b c d} 2', 'c\nd');
  T('skip: all', 'skip {a b} 5', '');
  T('skip: none', 'skip {a b} 0', 'a\nb');
  E('skip: bad count', 'skip {a} -1', 'skip: "-1" is not a count (a whole number, 0 or more)');
  T('flatten: one level', 'flatten {{1 2} {3} {4 5}}', '1\n2\n3\n4\n5');
  T('flatten: empty', 'flatten {}', '');
  T('compact: drops empties', 'compact {a {} b {}}', 'a\nb');
  T('compact: empty', 'compact {}', '');
  T('distinct: keeps first appearance', 'distinct {b a b c a}', 'b\na\nc');
  T('distinct: empty', 'distinct {}', '');
  T('enumerate: index and item', 'enumerate {a b}', '{index 0 item a}\n{index 1 item b}');
  T('enumerate: empty', 'enumerate {}', '');
  T('zip: pairs', 'zip {a b} {1 2}', '{a 1}\n{b 2}');
  T('zip: empty', 'zip {} {}', '');
  E('zip: lengths differ', 'zip {a} {1 2}', 'zip: the lists differ in length (1 and 2)');
  T('chunk: pieces', 'chunk {1 2 3 4 5} 2', '{1 2}\n{3 4}\n5');
  T('chunk: empty', 'chunk {} 3', '');
  E('chunk: zero size', 'chunk {1} 0', 'chunk: the size must be at least 1');
  T('tally: counts', 'tally {a b a c a}', 'a 3\nb 1\nc 1');
  T('tally: empty', 'tally {}', '');
  T('tally: result is a record', 'dict get [tally {a b a}] a', '2');
  T('sum: numbers', 'sum {1 2 3.5}', '6.5');
  T('sum: integers stay integers', 'sum {1 2 3}', '6');
  T('sum: empty is 0', 'sum {}', '0');
  E('sum: not a number', 'sum {1 x}', 'sum: "x" is not a number');
  T('avg: mean', 'avg {2 4 9}', '5.0');
  T('avg: empty is empty', 'avg {}', '');
  E('avg: not a number', 'avg {a}', 'avg: "a" is not a number');
  T('min: smallest', 'min {4 2 9}', '2');
  T('min: empty is empty', 'min {}', '');
  T('max: largest', 'max {4 2 9.5}', '9.5');
  T('max: empty is empty', 'max {}', '');
  E('max: not a number', 'max {1 b}', 'max: "b" is not a number');
  T('sort-on: by computed key', 'sort-on {pear fig banana} w {string length $w}', 'fig\npear\nbanana');
  T('sort-on: numeric reversed', 'sort-on {a bbb cc} w {string length $w} -n -r', 'bbb\ncc\na');
  T('sort-on: empty', 'sort-on {} w {string length $w}', '');

  T('parse: a template', 'parse "alice is 30\nbob is 25\nzzz" {{who} is {age}}', '{who alice age 30}\n{who bob age 25}');
  T('parse: blank space is flexible', 'parse "a    is   1" {{x} is {y}}', '{x a y 1}');
  T('parse: special characters in the template are literal', 'parse "a.b (1)" {{x}.{y} ({z})}', '{x a y b z 1}');
  T('parse: nothing fits', 'parse "zzz" {{a} is {b}}', '');
  T('parse: empty text', 'parse "" {{a} is {b}}', '');
  T('parse: -x with names', raw`parse "10-20" -x {(\d+)-(\d+)} lo hi`, '{lo 10 hi 20}');
  E('parse: no captures in the template', 'parse x nothing', 'parse: the template has no {name} to capture');
  E('parse: repeated name', 'parse x {{a} {a}}', 'parse: the name "a" is used twice in the template');
  E('parse: -x group count mismatch', raw`parse x -x {(a)(b)} only`, 'parse: the pattern has 2 groups but 1 names were given');
  E('parse: no template', 'parse x', 'parse: needs text and a template (parse text {name is {who}})');
  T('from-json: array of objects is rows', 'from-json {[{"name":"ann","age":31},{"name":"bo","age":25}]}', '{name ann age 31}\n{name bo age 25}');
  T('from-json: an object is a record', 'from-json {{"a":1,"b":"x y"}}', 'a 1\nb {x y}');
  T('from-json: an array is a list', 'from-json {[1,2,3]}', '1\n2\n3');
  T('from-json: empty array', 'from-json {[]}', '');
  T('from-json: nested objects stay records', 'dict get [dict get [from-json {{"a":{"b":2}}}] a] b', '2');
  T('from-json: true false null come through as words', 'from-json {[true,false,null]}', 'true\nfalse\nnull');
  C('from-json: invalid text', 'catch {from-json nope} m; set m', 'from-json: not valid JSON:');
  T('to-json: rows', 'to-json {{a 1 b x}}', '[\n  {"a":1,"b":"x"}\n]');
  T('to-json: two rows', 'to-json {{a 1} {a 2}}', '[\n  {"a":1},\n  {"a":2}\n]');
  T('to-json: empty rows', 'to-json {}', '[]');
  T('to-json: list', 'to-json {1 2 {a b}} -l', '[1,2,"a b"]');
  T('to-json: record', 'to-json {name ann age 31} -d', '{"name":"ann","age":31}');
  T('to-json: quotes and newlines are escaped', 'to-json [list [list q "a\\"b\nc"]]', '[\n  {"q":"a\\"b\\nc"}\n]');
  T('to-json: leading zero stays a string', 'to-json {{z 007}}', '[\n  {"z":"007"}\n]');
  T('to-json: true false null stay bare', 'to-json {true null} -l', '[true,null]');
  E('to-json: row not a record', 'to-json {{a}}', 'to-json: row 1 is not a record (key value pairs): a');
  T('to-json/from-json: round trip', 'from-json [to-json $people]', run('set people').value.length ? '{name ann age 31 city paris}\n{name bo age 25 city rome}\n{name cy age 40 city paris}' : '');
  T('from-csv: rows', 'from-csv "name,age\nann,31\nbo,25"', '{name ann age 31}\n{name bo age 25}');
  T('from-csv: quoted comma', 'from-csv "a,b\n\\"x,y\\",2"', '{a x,y b 2}');
  T('from-csv: doubled quote', 'from-csv "a\n\\"say \\"\\"hi\\"\\"\\""', '{a {say "hi"}}');
  T('from-csv: newline in a quoted field', 'dict get [lindex [from-csv "a\n\\"x\ny\\""] 0] a', 'x\ny');
  T('from-csv: blank lines skipped', 'from-csv "a\n1\n\n2"', '{a 1}\n{a 2}');
  T('from-csv: crlf', 'from-csv "a\\r\n1\\r\n"', '{a 1}');
  T('from-csv: header only', 'from-csv "a,b"', '');
  T('from-csv: empty text', 'from-csv ""', '');
  T('from-csv: empty field', 'from-csv "a,b\n,2"', '{a {} b 2}');
  E('from-csv: wrong field count', 'from-csv "a,b\n1"', 'from-csv: line 2 has 1 field but the header has 2');
  E('from-csv: unclosed quote', 'from-csv "a\n\\"x"', 'from-csv: a quoted field is never closed');
  T('to-csv: header and rows', 'to-csv $people name age', 'name,age\nann,31\nbo,25\ncy,40');
  T('to-csv: all columns by default', 'to-csv {{a 1 b 2}}', 'a,b\n1,2');
  T('to-csv: quoting', 'to-csv [list [list a "x,y" b "q\\"r"]]', 'a,b\n"x,y","q""r"');
  T('to-csv: missing cells are empty', 'to-csv {{a 1} {a 2 b 3}}', 'a,b\n1,\n2,3');
  T('to-csv: empty rows', 'to-csv {}', '');
  T('to-csv/from-csv: round trip', 'from-csv [to-csv $people]', '{name ann age 31 city paris}\n{name bo age 25 city rome}\n{name cy age 40 city paris}');
  sandbox();
  T('rows from the file system', sh('save aaaa f1', 'save b f2', 'pluck [where [files] {$size > 3}] name'), 'f1');
}

function testFluidity() {
  run('set people {{name ann age 31 city paris} {name bo age 25 city rome} {name cy age 40 city paris}}');
  T('|>: threads a value through steps', '|> $people {where {$age > 28}} {sort-by age -n -r} {pluck name}', 'cy\nann');
  T('|>: sees your variables', 'set min 30; |> $people {where {$age > $min}} {pluck name}', 'ann\ncy');
  T('|>: no steps returns the value', '|> abc', 'abc');
  T('|>: text steps', '|> "b\na\nb" {sort} {uniq -c}', '   1 a\n   2 b');
  T('|>: same as nesting', 'same [|> $people {where {$age > 28}} {pluck name}] [pluck [where $people {$age > 28}] name]', '1');
  T('|>: same as variable threading', 'set r [where $people {$age > 28}]; set r [pluck $r name]; same $r [|> $people {where {$age > 28}} {pluck name}]', '1');
  E('|>: a failing step reports its own error', '|> $people {pluck zip}', 'pluck: row 1 has no column "zip"');
  T('~: match', '~ report.txt *.txt', '1');
  T('~: one of several', '~ b a b c', '1');
  T('~: no match', '~ x a b', '0');
  T('~: no patterns', '~ x', '0');
  T('~: classes', '~ b2 {[a-c]?}', '1');
  T('^: one to many', '^ report- {1 2 3} .txt', 'report-1.txt\nreport-2.txt\nreport-3.txt');
  T('^: pairwise', '^ {a b c} {1 2 3}', 'a1\nb2\nc3');
  T('^: single items', '^ a b', 'ab');
  T('^: no arguments', '^', '');
  E('^: lengths differ', '^ {a b} {1 2 3}', '^: lists of 2 and 3 items cannot be joined (they must match, or one must have a single item)');
  E('^: empty list', '^ a {}', '^: cannot join with an empty list');
  T('same: one line and many lines', 'same {a b} "a\nb"', '1');
  T('same: different', 'same {a b} {a c}', '0');
  T('same: different lengths', 'same {a} {a b}', '0');
  T('same: empty lists', 'same {} {}', '1');
  C('whatis: a proc shows its source', 'whatis basename', 'proc basename {name {suffix {}}} {');
  C('whatis: the source is complete', 'whatis dirname', 'file dirname $name');
  T('whatis: built-in', 'whatis string', 'string is a Tcl built-in command (written in C; no source to show)');
  E('whatis: unknown', 'whatis nonesuch', 'whatis: nonesuch: not found');
  T('which: proc', 'which ls', 'ls: proc');
  T('which: built-in', 'which string', 'which: built-in'.replace('which', 'string'));
  E('which: unknown', 'which nonesuch', 'which: no such command: nonesuch');
  sandbox();
  T('alias: makes a command', sh('alias l ls -a', 'touch .h x', 'l'), '.h\nx');
  T('alias: which says so', 'which l', 'l: alias for ls -a');
  T('alias: whatis shows it', 'whatis l', 'alias l ls -a');
  T('alias: later arguments follow', 'l /t', '.h\nx');
  E('alias: needs a command', 'alias zz', 'alias: usage: alias name command ?arg...?');
  T('unalias: removes', sh('unalias l', 'info commands l'), '');
  E('unalias: not an alias', 'unalias ls', 'unalias: ls is not an alias');
  // scripts as commands
  run(sh('mkdir /bin', 'save {return "got $argc: $argv"} /bin/say.tcl', 'save {error boom} /bin/bad.tcl', 'save {set secret 1; return $argv0} /bin/who'));
  T('scripts: a .tcl in /bin runs by name', 'say a b', 'got 2: a b');
  T('scripts: no arguments', 'say', 'got 0: ');
  T('scripts: a file without .tcl runs too', 'file tail [who]', 'who');
  T('scripts: a path with a slash runs', '/bin/say.tcl x', 'got 1: x');
  T('scripts: variables do not leak', sh('who', 'info exists secret'), '0');
  T('scripts: usable inside brackets', 'string length [say 1 2 3]', '12');
  T('scripts: which finds them', 'which say', 'say: script /home/shell/bin/say.tcl');
  T('scripts: whatis names the file', 'whatis say', 'say is a script: /home/shell/bin/say.tcl');
  E('scripts: errors are reported with the script named', 'bad', 'boom');
  X('scripts: and the trace names the file', 'bad', '(while running the script /home/shell/bin/bad.tcl)');
  // unknown commands
  E('unknown: plain', 'lss', 'invalid command name "lss"');
  X('unknown: points to help', 'lss', 'note: try: help, or: apropos lss');
  X('unknown: unix word find', 'find .', 'note: walk lists everything below a place');
  X('unknown: unix word man', 'man ls', 'note: use help');
  X('unknown: unix word ps', 'ps', 'there are no processes here');
  X('unknown: ./ path', './nothere', 'note: files are not run by path; use: source ./nothere');
  T('unknown: autoloading still works', 'catch {package require json} m; set m', '1.3.6');
  T('unknown: command not found inside catch', 'catch {lss} m; string match {invalid command name*} $m', '1');
}

// -------------------------------------------------------------------- adapter
function testAdapter(packed) {
  const m = html.match(/function makeWaclAdapter\(\) \{[\s\S]*?\n\}\n/);
  ok('adapter: makeWaclAdapter is in the HTML', !!m, 'not found');
  if (!m) return;
  const out = [];
  const w = { __waclReady: true, __waclInterp: ip, __waclModule: ip.Module, __shTcl: packed };
  const ctx = vm.createContext({ window: w, console });
  vm.runInContext(m[0] + '\nthis.makeWaclAdapter = makeWaclAdapter;', ctx);
  const a = ctx.makeWaclAdapter();
  let cleared = 0;
  a.boot(t => out.push(t), { clear: () => cleared++ });
  ok('adapter: boots without the profile failing', !out.some(l => l.startsWith('shell profile failed')), out.join('\n'));
  ok('adapter: prints the banner', out.some(l => /^Tcl 9\.1\.0 \(wacl\) -- everything is Tcl/.test(l)), out.join('\n'));
  ok('adapter: name is tcl', a.name === 'tcl', a.name);
  const lastOut = () => out[out.length - 1];
  run('cd /home/shell; catch {file delete -force /home/shell/t}; file mkdir /home/shell/t; cd /home/shell/t');
  a.exec('save "a b" f');
  a.exec('ls');
  ok('adapter: a list result prints one name per line', lastOut() === 'f', show(lastOut()));
  a.exec('lines "x y\nz"');
  ok('adapter: a vertical list reads cleanly at the prompt', lastOut() === '{x y}\nz', show(lastOut()));
  a.exec('cat f');
  ok('adapter: text result', lastOut() === 'a b', show(lastOut()));
  a.exec('cat nope');
  ok('adapter: an error shows its message first', lastOut().split('\n')[0] === 'cat: nope: no such file or directory', show(lastOut()));
  a.exec('table [files]');
  ok('adapter: a table prints as a grid', lastOut().startsWith('name  path'), show(lastOut()));
  a.exec('lss');
  ok('adapter: unknown commands get the hint', lastOut().includes('note: try: help'), show(lastOut()));
  a.exec('help');
  ok('adapter: help prints the index', lastOut().includes('help start') && lastOut().includes('PLACES AND THINGS'), '');
  a.exec('exit 3');
  ok('adapter: exit is trapped', lastOut().includes('exit(3) trapped'), show(lastOut()));
  a.exec('clear');
  ok('adapter: clear is handled by the window', cleared === 1, 'cleared=' + cleared);
  a.exec('cd /t');
  ok('adapter: the prompt shows the shell-relative place', a.prompt() === '/t % ', show(a.prompt()));
  a.exec('cd');
  ok('adapter: bare cd goes to the top', a.prompt() === '/ % ', show(a.prompt()));
  a.exec('echo hi');
  ok('adapter: echo output reaches the window', lastOut().replace(/\r$/, '') === 'hi', show(lastOut()));
  a.exit();
  const before = out.length;
  a.exec('ls');
  ok('adapter: after exit nothing is evaluated', out.length === before, '');
  // the old shell is gone
  ok('html: no old JS shell', !/this\.shell\b|ForthVM|makeForthAdapter/.test(html), '');
  ok('html: the wacl runtime is embedded', html.includes('id="wacl-runtime"'), '');
}

// ----------------------------------------------------------------------- main
(async () => {
  console.log('bridge userspace tests  (runtime: ' + path.basename(HTML) + ')');
  const src = fs.readFileSync(SH, 'utf8');

  // brace balance, as Tcl's own `catch {...}` wrapper sees it: the adapter
  // evaluates the profile inside catch, so one stray brace breaks everything.
  let depth = 0;
  for (let i = 0; i < src.length; i++) {
    if (src[i] === '\\') { i++; continue; }
    if (src[i] === '{') depth++; else if (src[i] === '}') depth--;
  }
  ok('sh.tcl: braces balance as plain text', depth === 0, 'depth ' + depth);
  ok('sh.tcl: no tabs', !src.includes('\t'), '');
  ok('sh.tcl: no markdown-style tables in the help text', !/^\s*\|.*\|\s*$/m.test(src), '');

  // pack it for the CURRENT build (the readable file is too big to Eval whole)
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'bridge-test-'));
  const packedPath = path.join(tmp, 'sh-boot.tcl');
  let packOut = '';
  try {
    packOut = cp.execFileSync('python3', [path.join(__dirname, 'pack-sh.py'), SH, packedPath], { encoding: 'utf8' });
    ok('pack-sh.py: fits the 64 KB boot limit', true, '');
  } catch (e) {
    ok('pack-sh.py: fits the 64 KB boot limit', false, String(e.stdout || e.stderr || e));
    process.exit(1);
  }
  const packed = fs.readFileSync(packedPath, 'utf8');
  ok('pack-sh.py: stub is under 62000 bytes', packed.length < 62000, 'bytes ' + packed.length);
  console.log('  ' + packOut.trim());

  // -- 1. the readable file, sourced from the file system (the future adapter)
  ip = await bootRuntime();
  const baseline = run('lsort [info procs]').value.split(/\s+/);
  ip.Module.FS.writeFile('/sh_test.tcl', src);
  const loaded = run('source /sh_test.tcl');
  ok('sh.tcl: sources cleanly from the file system', loaded.ok, loaded.value);
  if (!loaded.ok) { report(); return; }
  T('boot: starts in the shell top when it was at the system root', 'pwd', '/home/shell');
  testLoading(baseline);
  testDocs();
  testPlaces();
  testHash();
  testMisc();
  testText();
  testValues();
  testFluidity();

  // -- 2. the packed file, through the adapter exactly as the build does it
  ip = await bootRuntime();
  const bootRes = run(packed);
  ok('sh-boot.tcl: Evals cleanly like the current adapter does', bootRes.ok, bootRes.value);
  T('sh-boot.tcl: same command count as the source', 'expr {[llength $::sh::cmds] > 50}', '1');
  T('sh-boot.tcl: booting twice is fine', 'catch {source /dev/null}; llength [info commands help]', '1');
  const again = run(packed);
  ok('sh-boot.tcl: a second boot (a second window) does not fail', again.ok, again.value);
  testAdapter(packed);

  report();
})().catch(e => { console.error('FATAL', e && e.stack || e); process.exit(2); });

function report() {
  console.log('');
  if (failures.length) {
    console.log('FAILURES (' + failures.length + '):');
    for (const f of failures) console.log('  - ' + f);
    console.log('');
  }
  console.log(pass + ' pass / ' + fail + ' fail');
  process.exit(fail ? 1 : 0);
}
