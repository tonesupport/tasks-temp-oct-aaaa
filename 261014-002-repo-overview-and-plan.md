# Repo overview and plan for task-writing-kit v002

## What is in the repo

The GitHub repo tonesupport/tasks-temp-oct-aaaa holds one real file, tasks-toml.7z (about 4 MB), plus the note I added earlier today. I unpacked the archive into my scratchpad only. Nothing from it is committed yet. It extracts to a folder tasks-toml with nine files.

The handoff and notes files are agent-handoff-task.txt (the previous agent's proposal, ending with your answers) and workflow-notes.txt (eight dated decision entries about how the task system should operate). The working products from the previous session are tasks.toml, tasks.patch, changes.md, patch-1.html, almanac.tcl and task-preview.py. Finally there is task-writing-kit-v001.zip, which holds the actual kit.

tasks.toml is your single task list: one TOML table per task, with a four-character id as the table name, plus a spine section at the top that is structure and is not to be touched. It has 343 tables. The copy in the archive is byte-identical to the frozen snapshot inside the kit (dated 2026-10-13, hash in snapshot/SHA256), so it is the base, not the live file. A task has a title, status, created, updated and tags, and optionally domain, project, notes, datetime, time, duration, completed, blockers and a few others. Stamps are ten-digit YYMMDDhhmm integers in Pacific time. Statuses are urgent, now, progress, today, later, deferred, sched and done, and the previous session added an uppercase REMOVE.

almanac.tcl (89 KB, Tcl) is the only sanctioned writer. It has the verbs init, add, ls, filter, set, done, today, ready, blockers, validate and doctor, and it uses a TOML reader called tama.tcl that keeps source line locations, so almanac splices individual task tables in place instead of rewriting the whole file. The kit bundles a Tcl zipkit at tools/deps/tcl, which I ran and which reports version 9.0.4 exactly. This machine has no system tclsh, so the bundled one is what I will test with.

The kit, v001, is a writing procedure for agents: copy the snapshot to work/, make changes only through almanac, produce a unified diff against the snapshot with make-patch.py, gate it with check.py (hard fails and warnings), and optionally render it with task-preview.py into one self-contained HTML board with the touched cards colored green, amber or violet and a field-by-field review panel at the top. The kit also has the rules (task-spec.md, policies.md, rubric.md, context-brief.md), a skin folder (board.css, a 148 KB board.js, fonts) and a July survey as sample input. The current gate demands a changes.md line for every touched task, a coverage.md for document inputs, and fails any patch that removes a task.

## What the archive does not contain

The previous session's REMOVE work happened in a working copy that was not archived. In the archive, almanac.tcl, check.py, task-spec.md and board.js have no REMOVE support at all. Only the loose task-preview.py has REMOVE in its status order. The delete earmark exception that the handoff wants dropped is likewise absent from the kit's check.py and spec. That is convenient, since there is nothing to rip out, but it means I will reimplement REMOVE everywhere from the notes. The loose tasks.patch and changes.md list 40 touched tasks and are a good real-world test case: one task set to REMOVE, several marked done, and many new tasks.

## Your decisions, as I understand them

Test file means tasks.toml. Table-level rebase is the primary apply mode, with strict line-diff as the fallback. The apply tool always writes a new file and never touches the target. REMOVE stays as a status, and the HTML hides it by default. Removal becomes a warning, not a failure. The delete earmark is dropped in favor of the REMOVE protocol. changes.md goes away: each change is instead recorded in the task's own notes as a new line that reads, in your format, a greater-than sign, the word change, a parenthesized YY-MM-DD HH:MM stamp in twelve-hour time, a colon, and the note, appended after whatever notes already exist and never overwriting them. Everything user-facing is rewritten in Tcl for 9.0.4, and only check.py stays Python.

## Plan

First I will extract the archive into the repo so the base is committed and reviewable, and then build everything as kit v002 in its own folder.

The shared pieces come first. A small Tcl library will hold the strict unified-diff parser and applier, a task-table splitter built on tama.tcl, and a per-id differ that classifies each task as new, changed, removed or unchanged between two TOML texts. Both new tools reuse it, so the two cannot disagree about what a patch means (in v001 check.py and the preview each carried a private copy).

apply-patch.tcl will take a patch and a target. Its default mode reads the patch's intent per task id: it applies the patch to the snapshot in memory, diffs the result against the snapshot by id, and then, against the target, inserts new ids, replaces touched ids, and leaves everything else alone. Because it works per id, it survives a target that has moved on since the snapshot. If a touched id in the target no longer matches its snapshot version, that is a conflict: the tool reports it by id, keeps the target's version, and offers a flag to take the patch's version instead. A flag selects the strict line-diff mode, and the tool falls back to it only when the table-level mode cannot run. It writes TARGET.patched only, never in place and never with a backup, runs almanac validate on the result and refuses to write if that fails unless forced, and prints how many tasks were added, changed, removed and conflicted.

make-patch.tcl replaces make-patch.py with the same output. I will also add a way to write the stamped change line into notes at the moment of the change, and my proposal is a new almanac verb named change (almanac change ID text) so that almanac stays the sole writer. It appends the line to the existing notes, bumps updated, and uses the stamp format above.

task-preview.tcl replaces task-preview.py. It needs a TOML reader, which tama.tcl provides, plus a small JSON emitter, base64 font inlining (built into Tcl 9), HTML escaping and the field differ. It keeps the same output: one unencrypted HTML file with the review panel and colored cards. The review panel will also show the new change lines from notes, and it will mark REMOVE cards. In board.js, the REMOVE filter key will default to the exclude state so removed tasks are hidden until someone turns the filter on. That edit is JavaScript inside the skin folder, which is browser code, not a script you run. I will check parity by rendering the same patch with the old Python preview and the new Tcl one and comparing the embedded board model.

check.py is rewritten into two tiers. The hard tier is integrity only: the patch applies, the result parses, almanac validate passes, the status is in the enum including REMOVE, done has completed, sched has a datetime, created is unchanged, no task blocks itself, ids are well formed, and there is no content key. Everything stylistic drops to warnings: master-plan codes and ids in titles, tag quoting, the duration rule, missing change lines in notes, the optional coverage file, and a snapshot hash mismatch, which becomes a note that your file has moved on and should be checked for conflicts. Removals are listed as a warning that names the tasks.

The documents get updated to match. task-spec.md will say removal is an ordinary change, REMOVE is the reviewable option, hand edits are allowed when noted in the change line, and the changes.md section is replaced by the notes change-line protocol. README, rubric, context-brief and the changelog entry for v002 are updated, workflow-notes.txt gets new entries for the decisions above, and policies.md keeps the never-commit and never-touch-live-files rules. Last, I build a fresh task-writing-kit-v002.zip.

Testing uses the bundled Tcl 9.0.4: apply the loose patch to the snapshot and confirm the result equals what the old strict applier produces; apply it to a deliberately modified copy to exercise rebase and conflicts; round-trip a REMOVE task; run check.py on the new patch format; render both previews and compare; and load the HTML in the preinstalled headless Chromium to confirm the REMOVE filter defaults to hidden.

## Things I would like you to confirm

These are the choices I am making by default unless you say otherwise.

1. Conflicts in rebase mode: report and keep the target's version by default, with an explicit flag to take the patch's version.
2. The change-line stamp: I will write it as `>change (26-10-14 02:35 PM): text`, with the date as YY-MM-DD and the time in twelve-hour form with AM or PM. Tell me if you want a different 12-hour style such as 2:35p.
3. Add the almanac change verb so the stamped line is written by almanac, not by hand.
4. Include in this release the show verb and the fix for `ls id=` silently returning nothing from task mn9k, and the spec line that reads go through almanac. The handoff offered this and your reply did not say, so I would include them, since they are small.
5. Coverage.md stays optional and warns instead of failing.
6. Extract the archive into the repo root as a tasks-toml folder, commit it as the base, and put kit v002 beside it.
