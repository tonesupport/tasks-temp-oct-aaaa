# Session manifest: tasks.toml kit v002, apply and preview in almanac.tcl, and the single-file build

This bundle collects every file involved in the session that ran from 2026-10-14 to 2026-10-15 (bundled 2026-10-27), on the repository tonesupport/tasks-temp-oct-aaaa, branch claude/jolly-edison-grdceh. It is a snapshot of the committed working tree at the branch head when the bundle was made (commit d3c9ec0 plus the commit that adds these two documents), plus the file you uploaded during the session, diffs of every changed script, and this manifest. The companion document 261027-010-script-change-documentation.md describes every script change in prose.

## What the session did, in order

You first asked about using your cloud credit; I explained I cannot see billing and wrote a short note. You then asked me to unpack tasks-toml.7z from the repo, read the previous agent's handoff (agent-handoff-task.txt) and your answers in it, and plan the changes: more relaxed rules around modification, an apply-patch tool and a preview tool built in Tcl 9.0.4 instead of Python (check.py stays Python). I wrote an overview and plan, then, after your confirmations, built `apply PATCH` and `preview` directly into almanac.tcl, along with `change`, `show` and an `ls id=` fix, rewrote check.py as a two-tier gate, rewrote the kit documents as kit v002, and dropped changes.md in favor of stamped change lines in task notes. You uploaded a zip with the REMOVE status changes, which I used as the starting point for almanac.tcl, check.py, board.js, artifacts.css and the spec. patch-1.html turned out not to have been applied; I rebuilt its 33 tasks into a patch and applied it, then applied tasks.patch on top, producing the patched tasks.toml and a plain HTML preview. At your request I removed the unused Atkinson Next font. You then supplied a plan for self-containment: I confirmed it, found and fixed an encoding problem under Tcl 8.6 by making the script files pure ASCII, built pack-almanac.tcl and dist/almanac.tcl (assets, fonts and helpers embedded, plus `emit`, `setup` and `preview --style`), and verified it under Tcl 9.0.4, a Tcl 8.6.14 shell built from source, and a Python launcher. You received the packed script, the patched tasks.toml, the preview, almanac.tcl and artifacts.css as attachments along the way, and I pushed checkpoint commits throughout.

## Layout of this bundle

At the top level are this manifest (261027-009-session-manifest.md) and the script change documentation (261027-010-script-change-documentation.md), plus git-log.txt, the commit history of the branch.

The folder repo holds the complete working tree of the repository at that head, without the .git folder. Everything below describes files inside it.

The folder inputs holds the one file you attached during the session, 261014-004-remove-status-kit-changes.zip, exactly as uploaded.

The folder diffs holds unified diffs of the changed scripts and documents, in stages, so each change can be reviewed on its own. They are described in the change documentation.

The folder test-harness holds the small helper scripts used for verification outside the repo (headless-browser checks of the REMOVE filter and the custom theme, and the two draft Tcl chunks and Python pieces from which apply, preview and check.py were first assembled). The shell regression runs were done interactively and are described in the change documentation; they were not saved as files.

## Inside repo

The file tasks-toml.7z is the original archive you uploaded to the repo, untouched. The folder tasks-toml is that archive extracted as-is (committed as the base), plus two additions of mine: patch-1.patch, rebuilt from the review panel of patch-1.html, and entries 9 to 16 appended to workflow-notes.txt. Its other files are the previous session's: agent-handoff-task.txt (the handoff and your answers), workflow-notes.txt (decision log), tasks.toml (343 tables; identical to the frozen snapshot of 2026-10-13), tasks.patch and changes.md (the 40-task patch and its notes), patch-1.html (a rendered review of a separate 33-task patch), almanac.tcl (the live v001 almanac, unmodified), task-preview.py (the loose Python preview, unmodified) and task-writing-kit-v001.zip (the original kit).

The folder task-writing-kit-v002 is the new kit, built from the v001 kit plus the uploaded REMOVE changes. Its files: tools/scripts/almanac.tcl (the loose, editable script, with all the new verbs), tools/scripts/cli.tcl and tama.tcl and tools/lib/tosu/tama.tcl (helpers, unchanged), tools/deps/tcl (the Tcl 9.0.4 zipkit interpreter, linux-x64), pack-almanac.tcl (the build program), dist/almanac.tcl (the packed single-file script, generated), check.py (the rewritten gate), snapshot (the frozen base tasks.toml and its hash), skin (the page template, artifacts.css, board.css, board.js and 13 IBM Plex WOFF2 fonts, plus the font license file), inputs (the July 2026 survey), examples (a sample patch and coverage file), and the documents README.md, task-spec.md, policies.md, rubric.md, context-brief.md and CHANGELOG.md. make-patch.py, task-preview.py, the changes.md example and the Atkinson Next font were deleted from v002.

The folder results holds the outputs of the two patch applications: after-patch-1.toml (live tasks.toml with patch-1 applied, 374 tasks), after-both.toml (patch-1 and tasks.patch both applied, 399 tasks, the file you received as an attachment) and after-both-preview.html (its plain preview, REMOVE cards hidden by default).

The markdown files at the repo root are the session's response documents, in order: 261014-001 (cloud credit note), 002 (repo overview and plan), 003 (confirmation before building apply and preview), 005 (results of apply and preview and both patches), 006 (show, what preview --base does, plain preview), 007 (confirmation and findings for the packing plan, including the Tcl 8.6 encoding finding), 008 (packing, emit, --style and launcher results with the seven-item verification report), and 009 and 010, which belong to this bundle. There is no 004 because that number was the name of the file you uploaded.

## Generated versus source files

Source files to edit: tools/scripts/almanac.tcl, the skin folder, pack-almanac.tcl, check.py and the documents. Generated files: dist/almanac.tcl (rebuild with tools/deps/tcl pack-almanac.tcl; --check says whether it is current) and everything in results. The packed script is pure ASCII and carries the helpers and assets inline in fenced sections; pack-almanac.tcl --unpack DIR splits it back apart.

## Not included

The .git folder (git-log.txt lists the commits). The Tcl 8.6.14 shell and the standalone Python with tkinter that I installed in the sandbox to test; they are not part of your system and are easy to recreate. Scratch outputs of the test runs. The packing plan you pasted into chat was text, not a file; its content and my answers are recorded in 261014-007 and 261014-008.

## Known limits and open items

The Python launcher was verified only against a tkinter that embeds Tcl 9.0.4, not 8.6.14, because no Python available in the session ships one; a two-command check is given in 261014-008 for your machine. The live /workspace almanac.tcl and board export were not changed, and the v002 script is a superset you can copy into place. almanac's own validate still errors on the duration rule, so check.py downgrades that single case to a warning. The deferred items from your plan, a check routine and priming or context embedding, were not started. The kit's task-spec.md and README are drafts and are expected to be rewritten as almanac changes.
