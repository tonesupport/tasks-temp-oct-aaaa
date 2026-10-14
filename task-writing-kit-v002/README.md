# Task writing kit v002

A kit for proposing new tasks and task changes as a patch against a frozen copy of tasks.toml. You work on a copy and return a patch; the user and the reviewer go through it together, and the user applies it with almanac. This kit is a working draft: it is rewritten as almanac and the workflow change.

## Start here
1. Read this kit: README.md, task-spec.md, context-brief.md, policies.md, rubric.md, examples/, and every file in inputs/.
2. Once you've read it all, send ONE short message: ask whether to break `inputs/260710-001-ground-truth-survey.md` down into a task patch now, or whether there are other files or requests. Then wait.
3. If the next message is files with no text, that is the go signal. Treat them as the inputs to turn into tasks and follow the kit without asking anything first. If the reply is a plain yes to the survey, go ahead on the survey.

## Layout
- `snapshot/tasks.toml`: the frozen base. `snapshot/SHA256` holds its hash.
- `tools/scripts/almanac.tcl`: the script you edit. It loads `cli.tcl`, `tama.tcl` and `tools/lib/tosu/tama.tcl` from beside it and reads the preview assets from `skin/`.
- `pack-almanac.tcl`: builds `dist/almanac.tcl`, the same script as ONE file (helpers inlined, assets and fonts embedded, pure ASCII). `dist/` is generated; edit the sources.
- `tools/deps/tcl`: Tcl 9.0.4 zipkit, linux-x64.
- `check.py`: the gate (Python). Run it until it reports 0 FAIL.
- `skin/`: Sight CSS, board.js, template and fonts, used by `almanac preview`.
- `inputs/`: the source material. `examples/`: a passing patch.

## Workflow
```
chmod +x tools/deps/tcl                      # some unzip tools drop the exec bit
mkdir -p work && cp snapshot/tasks.toml work/tasks.toml
export ALMANAC_SKIP_BOARD_EXPORT=1          # stops almanac from rebuilding the live board
ALM="tools/deps/tcl tools/scripts/almanac.tcl --file work/tasks.toml"
$ALM add title="Title" status=later domain=CTP notes='...'
$ALM set <id> status=today
$ALM done <id>
$ALM change <id> "why this task was touched"   # appends a stamped >change line to its notes
$ALM show <id>                                  # one task by id
$ALM validate
diff -u snapshot/tasks.toml work/tasks.toml > tasks.patch
python3 check.py tasks.patch
$ALM --base snapshot/tasks.toml preview preview.html      # optional review page
```
Run `$ALM` with no arguments to see its usage.

## Applying a patch
```
$ALM apply tasks.patch                      # writes work/tasks.toml.patched, never touches the target
$ALM --out new.toml apply tasks.patch
```
`apply` works per task id: it applies the patch to its base (`--base`, default `snapshot/tasks.toml`), then inserts new ids, replaces touched ids and removes removed ids in the target, leaving every other task alone. A task the target has changed since the base is a conflict: it is reported by id, the target's version is kept, and the exit code is 3 (`--take-patch` takes the patch's version instead). If table-level mode cannot run, it falls back to a strict line diff on the target (`--line-diff` forces this) and names the hunk that fails. It validates the result and refuses to write if validation errors would rise (`--force` overrides). Re-applying a patch is harmless: already applied tasks are counted and skipped.

## Preview
`$ALM preview [out.html]` renders --file as one self-contained HTML file (default `preview.html`), with no network and no encryption. REMOVE cards are hidden until the remove filter is turned on. With `--base PATH`, new / changed / done / REMOVE cards are marked and a field-by-field review panel is put at the top.

## Handback
Attach tasks.patch and check.py's summary line. Change history is in the tasks' notes, so there is no changes.md. A coverage file is optional. Do not commit, push, or copy anything into a live tree.

## Single-file build and the Python launcher
```
tools/deps/tcl pack-almanac.tcl             # build dist/almanac.tcl and self-test it
tools/deps/tcl pack-almanac.tcl --check     # exit 1 if dist/ is out of date
tools/deps/tcl pack-almanac.tcl --unpack D  # split a packed file back into its modules, assets and fonts
tools/deps/tcl dist/almanac.tcl setup       # write a Python launcher named almanac beside the script, print an alias
```
The packed file runs under Tcl 9.0.4 and 8.6. Its sections are fenced by `# >>>> MODULE ...`, `# >>>> ASSET ...` and `# >>>> FONTS` lines, so a reader can cut it apart by hand as well. In the packed script `preview` needs no skin folder; `emit style ?OUT?` prints the standard theme (artifacts.css), `emit template ?OUT?` the page template, and `emit fonts ?DIR?` writes the fonts. `preview --style PATH` swaps in your own theme in place of artifacts.css (board.css stays), and warns about variables the standard theme defines that yours does not. `setup` needs a python3 with tkinter; without it, run `tclsh almanac.tcl ...` instead.
