# Documentation of changes made to scripts in this session

This document describes every change made to a script (and to the files that drive scripts) during the session. Unified diffs of each stage are in the bundle's diffs folder, and the prose below says what each diff contains. All of it concerns the tasks.toml tool chain: almanac.tcl, check.py, the preview and patch tools, the HTML skin, and the new pack-almanac.tcl. Nothing under /workspace on your pipeline was touched, and the live almanac.tcl in the archive (tasks-toml/almanac.tcl) is an unmodified copy of what you uploaded.

## almanac.tcl: three stages

The archive's almanac.tcl (89,203 bytes) is the starting point. It was changed in three stages, and each stage has its own diff.

### Stage 1: the REMOVE status (almanac_1-archive-to-remove-zip.diff, 22 lines)

This stage came from the zip you uploaded (261014-004-remove-status-kit-changes.zip), not from me. It adds the uppercase status REMOVE at the end of the STATUS_ORDER and STATUS_ENUM lists, and to the status token list in the usage text, so almanac can write and validate a task with status REMOVE and sort it after done.

### Stage 2: apply, preview, change, show and the id filter (almanac_2-remove-zip-to-apply-preview-change-show.diff, 810 lines)

New verbs, all added as new procs just before almanac::main, with a small amount of wiring in main:

`apply PATCH` (almanac::cmd_apply and helpers split_blocks, finish_block, join_blocks, block_index, parse_patch, apply_hunks, text_lines, block_diff, error_count, block_title). It rebases a unified diff onto the file named by --file and writes FILE.patched (or --out). It never modifies the target and refuses to write over it. The default mode is table-level: the patch is applied strictly to its base (--base, default snapshot/tasks.toml beside the kit), the base and the result are compared table by table, and each added, changed or removed task id is inserted, replaced or removed in the target; every other task is left alone, and new tables are inserted after the nearest preceding table that the target has. A task that the target changed since the base is a conflict: the target's version is kept, the conflict is printed, and the exit code is 3 (--take-patch takes the patch's version instead). If table-level mode cannot run, it falls back to a strict line-diff apply to the target (no fuzz, no offset search) and names the hunk and line that fail; --line-diff forces that mode. Before writing it parses and validates the result and refuses to write if validation errors would rise (--force overrides). Re-applying a patch is harmless: already applied tasks are counted and skipped. Removals are listed as WARN lines naming the task.

`preview ?OUT.html?` (almanac::cmd_preview and helpers jstr, pq, pqa, hesc, same_fields, show_field, preview_tasks, preview_model, inline_fonts). It is a Tcl port of the old task-preview.py: one standalone, unencrypted HTML page with the Sight board, fonts inlined as data URIs, and the board model and notes carried in a plane object. With --base PATH it marks new, changed, done and (new in the port) REMOVE cards and adds a field-by-field review panel. Without --base nothing is marked. Parity with the old Python script was checked by comparing the embedded board model and notes for the same patch: identical apart from the generator and date header lines.

`change ID TEXT` (cmd_change, change_stamp). Appends a line of the form greater-than, the word change, a parenthesized YY-MM-DD hh:mm AM/PM stamp in America/Los_Angeles, a colon and the text, to the task's notes without touching existing notes text, and bumps updated. This replaces changes.md as the change record.

`show ID` (cmd_show). Prints one task's full table, including notes; an unknown id is an error with exit code 1.

`ls id=ID` now works. A small edit in task_matches_filters treats key id as the table id (id=X matches that task, has=id is always true, missing=id never); before, id was silently ignored and the result was empty. This closes task mn9k's show/ls item.

main gained the flags --base, --out, --skin, --force, --take-patch and --line-diff, the four dispatch branches, usage text for the new verbs and flags, and the header comment's verb list. Existing verbs were not changed apart from the id filter. The diff removes only two lines (the header comment listing the verbs, and the option-parsing call that gained defaults) and adds 709.

### Stage 3: embedded assets, emit, setup, --style, ASCII (almanac_3-packing-emit-setup-style-ascii.diff, 601 lines)

Packing support. A marker pair, a line reading "# @@PACK:BEGIN deps" and one reading "# @@PACK:END deps", now fences the two source lines that load cli.tcl and tama.tcl, so pack-almanac.tcl can replace that block with the inlined modules. The script records its own path in ALMANAC_SELF and its folder in ALMANAC_DIR, and `catch {encoding system utf-8}` sits at the top.

Asset accessor. almanac::asset NAME returns the page template, the theme stylesheet, the structural stylesheet or board.js: from the embedded variables ASSET_sight_index_html, ASSET_artifacts_css, ASSET_board_css and ASSET_board_js when they exist (packed file), otherwise from the skin folder (default_skin finds ../../skin beside the script, or --skin DIR). asset_decode turns the @@U+XXXX@@ tokens that the packed file uses for non-ASCII characters back into characters.

Fonts. inline_fonts now takes a list of folders and uses font_uri, which looks a font up by its relative path (fonts/web/NAME.woff2) first in the embedded FONT_blobs dictionary, then in the folder of --style, then in the skin folder; a font found nowhere is left as a plain url and reported on stderr.

emit. `emit style ?OUT?` prints or writes the full artifacts.css, `emit template ?OUT?` the page template, and `emit fonts ?DIR?` decodes the embedded fonts into DIR (default ./fonts), keeping the part of the path below fonts/ (so ./fonts/web/NAME.woff2). With an output path that exists, emit refuses unless --force. There is deliberately no emit script.

preview --style PATH. Replaces only the theme layer (artifacts.css) with your stylesheet; board.css stays. It warns on stderr when the stylesheet lacks custom properties that the standard theme defines (or that the structural layer uses without a fallback).

setup ?DIR?. Writes a stdlib-only Python launcher named almanac (default: beside the script), makes it executable, and prints an alias line; it edits no shell startup files and refuses to overwrite a file that is not an almanac launcher unless --force. The launcher runs almanac.tcl on the Tcl that Python carries (tkinter.Tcl), sets argv0, argv and argc, sources the script with UTF-8 encoding, intercepts exit so the first exit code is returned without a traceback, and flushes stdout and stderr. If tkinter is missing it prints a clear message and exits 127. The launcher text is a literal inside almanac.tcl.

ASCII clean-up. Tcl 8.6 reads a script in the locale encoding, which broke the bullet and dash characters (the review panel showed mojibake under 8.6.14). All non-ASCII characters were removed from almanac.tcl: comments use plain ASCII, and strings use \u escapes, so the script prints exactly what it printed before. The diff for this stage removes 52 lines and adds 307; most removals are the ASCII clean-up and the old font and skin handling that the asset accessor replaced, and cmd_preview now takes a style argument.

## pack-almanac.tcl (new, task-writing-kit-v002/pack-almanac.tcl)

A Tcl program, run on the bundled Tcl 9.0.4, that builds dist/almanac.tcl. It reads tools/scripts/almanac.tcl, checks that it is pure ASCII, replaces the deps block with the inlined text of tools/scripts/cli.tcl and tools/lib/tosu/tama.tcl, embeds the four text assets from skin/ as braced literals (after checking braces balance and there is no backslash before a newline or brace, no trailing backslash and no carriage return; non-ASCII characters become @@U+XXXX@@ tokens), and embeds the 13 IBM Plex fonts from skin/fonts/web as a dictionary of base64 (it asserts exactly 13 fonts and that every font url in artifacts.css resolves). Sections are fenced by MODULE, ASSET and FONTS marker lines. After writing, it self-tests the packed file by running emit style, template and fonts and comparing with the sources. Modes: no argument builds; --check exits 1 if dist is stale; --unpack DIR cuts a packed file back into modules, assets and fonts. The output is deterministic (no timestamps).

## check.py (Python, the one script that stays Python)

v001 to the uploaded REMOVE version (check_1-v001-to-remove-zip.diff): REMOVE added to the status list, and a deletion earmark (a removal passed only with a delete line in changes.md containing the words user-approved). The earmark was a stop-gap you later decided to drop.

REMOVE version to v002 (check_2-remove-zip-to-v002.diff): rewritten as two tiers. Hard FAIL is integrity only: the patch applies cleanly to its base, the result parses, almanac validate passes (the one exception is the duration rule, which is downgraded to WARN because almanac's own validator still errors on it), status is in the enum (including REMOVE), done has completed, sched has datetime, created is unchanged, no task blocks itself, ids are four characters of a-z0-9, no content key, and required keys are present. Everything else is a WARN: removed tasks (named), tasks set to REMOVE, master-plan codes or ids in titles, tag style, datetime and time formats, stamp format, updated not bumped, spine changes, and a snapshot hash mismatch (reported as "your file has moved on; check for conflicts"). It also checks the new change-note protocol as warnings: a touched task should gain a >change line, and existing notes text should not be removed or edited. changes.md and coverage files are optional and only warn.

## task-preview.py and make-patch.py (removed from v002)

task-preview.py (v001, and the loose archive copy with REMOVE and two CSS tweaks, see task-preview.py_v001-to-archive-loose.diff) was replaced by `almanac preview`. make-patch.py was dropped; plain `diff -u snapshot/tasks.toml work/tasks.toml` does the same job. Both remain recoverable from tasks-toml/task-writing-kit-v001.zip and from the archive.

## The HTML skin

skin/board.js (skin_board.js.v001-to-v002.diff): the REMOVE filter ("remove" in the global filter group, a remove chip, include/exclude logic, a remove status pill) came from the zip you uploaded and defaulted to showing REMOVE cards. My change makes the default exclude (hidden): the initial state, the saved-state restore default, the agenda preset and its clear path all set it to exclude, and a new syncRemoveFromStatusChip makes selecting a STATUS:remove chip un-hide them. Verified in headless Chromium: the remove chip starts excluded, one click shows REMOVE cards, a second shows only them.

skin/artifacts.css (skin_artifacts.css.v001-to-v002.diff): the uploaded zip added .status-pill--remove (struck-through, dashed pill); I removed the unused Atkinson Next @font-face block, and its font file skin/fonts/atkinson-next-regular.ttf was deleted. The preview now embeds 13 faces (all IBM Plex). The license file stays in skin/fonts and is never written into pages.

## Kit documents (v001 to v002)

task-spec.md was rewritten as a draft (REMOVE status, relaxed rules: work on a copy but hand edits allowed with a note, removal is an ordinary change, reads and writes go through almanac, change history lives in notes as >change lines, no changes.md section). README.md describes the new workflow (almanac add/set/done/change/show, diff -u, check.py, apply, preview, pack-almanac.tcl, setup). rubric.md and context-brief.md were updated to match; CHANGELOG.md has v002 entries; examples/changes.md was removed and examples/README.md updated; policies.md is unchanged (the never-commit and never-touch-live-files rules were kept). In the archive's workflow-notes.txt, entries 9 to 16 were appended recording these decisions (apply and preview as almanac verbs, change history in notes, the removal protocol, check.py tiers, the Atkinson removal, the single-file build, pure ASCII, emit and setup).

## Data files produced

tasks-toml/patch-1.patch was reconstructed from patch-1.html's review panel (33 new tasks, appended at the end of tasks.toml in the page's order) because the page was the only copy of that patch. results/after-patch-1.toml is the live tasks.toml with it applied; results/after-both.toml additionally applies tasks.patch (27 added, 11 changed, 2 removed: bv58 and wz0h; 399 tasks, validate clean); results/after-both-preview.html is its plain preview.

## How the changes were tested

Table-level and line-diff apply give identical results to the old Python applier; applying in either order gives the same content; re-applying is a no-op; conflicts are reported (exit 3) and the line-diff fallback names the failing hunk. emit style, template and fonts match their sources byte for byte under Tcl 9.0.4 and a tclsh 8.6.14 built from source for the test. Loose and packed previews are identical under both Tcl versions. The verbs ls, ls --toml, today, ready, blockers, validate, add, set, done, change, apply and show give identical output and files across the pre-packing script, the loose script and the packed script on both Tcl versions. The Python launcher matched tclsh for every verb and for exit codes 0, 1 and 2 with no traceback, but only on a tkinter whose Tcl is 9.0.4; no Python available in the session embeds 8.6.14, so that one combination is untested.
