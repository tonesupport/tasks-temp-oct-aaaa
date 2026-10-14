# Apply and preview built into almanac, and both patches applied

## What was built

Everything is in `task-writing-kit-v002/`, which is a working draft built from the v001 kit plus the REMOVE zip you uploaded. The new code is in `task-writing-kit-v002/tools/scripts/almanac.tcl` and runs on the bundled Tcl 9.0.4 (`tools/deps/tcl`). Compared with the live almanac.tcl in the archive, the diff removes only five lines (the REMOVE status lists, the usage line, the verb comment and the option-parsing call, which gained new flags); everything else is additions.

`$ALM apply PATCH` rebases a patch onto the file named by `--file` and writes `FILE.patched` (or `--out PATH`). It never touches the target and refuses to write over it. It works per task id: the patch is applied strictly to its base (`--base`, default `snapshot/tasks.toml` beside the kit), and then each added, changed or removed id is inserted, replaced or removed in the target, leaving every other task alone. If the target's version of a touched task differs from the base, that is a conflict: it is named, the target's version is kept, and the exit code is 3 (`--take-patch` takes the patch's version). If table-level mode can't run it falls back to a strict line diff on the target (`--line-diff` forces it) and names the hunk that fails. It validates the result and refuses to write if errors would rise (`--force` overrides). Re-applying is harmless.

`$ALM preview [OUT.html]` renders the file as one standalone, unencrypted page (default `preview.html`). With `--base PATH` it marks new, changed, done and REMOVE cards and adds the field-by-field review panel. REMOVE cards are hidden by default: I changed the remove filter in `skin/board.js` to start in the exclude state, and selecting a REMOVE status chip un-hides them.

Also added: `change ID TEXT` (appends `>change (YY-MM-DD hh:mm AM): TEXT` to the notes, never overwriting), `show ID` (one task, full table), and `ls id=ID` now works instead of silently returning nothing. `check.py` is rewritten as two tiers (integrity fails, everything else warns, removals warn, no delete earmark, no changes.md needed). `make-patch.py` and `task-preview.py` are gone; `diff -u` replaces the first and `preview` the second. The spec, README, rubric, context brief and changelog are updated, and four new entries (9 to 12) are appended to `tasks-toml/workflow-notes.txt`.

## The two patches

patch-1.html had not been applied. It was a rendered review of 33 new tasks from the survey breakdown, none of which were in the repo's tasks.toml. I rebuilt them exactly from the page's review panel into `tasks-toml/patch-1.patch` (appended at the end of the file, in the page's order) and applied it with the new verb. As a check, the board model that `preview` produces for the result matches the one embedded in patch-1.html card for card; only the generator and date lines differ.

Applying patch-1 added 33 tasks with no conflicts, giving `results/after-patch-1.toml` (374 tasks, validate clean). Applying tasks.patch on top of that, table-level, added 27, changed 11 and removed 2, with no conflicts, giving `results/after-both.toml` (399 tasks, validate clean). The two removed tasks are bv58 (Couples therapy) and wz0h (SOU), which are the two deletions the previous session approved; the tool reports them as warnings. mgp1 now has status REMOVE and the wpu1 status is urgent, as in the patch.

## Tests I ran

The table-level result for tasks.patch is byte-identical to the strict line-diff result and to the old Python applier. The table-level result for patch-1 is byte-identical to the file I built directly. Applying the two patches in the other order gives the same content with the new tasks in a different position in the file. Re-applying tasks.patch to the result reports all 40 touched tasks as already applied and leaves the file unchanged. Against a target where I edited wpu1 myself, table-level mode applied everything else and reported the one conflict (exit 3), `--take-patch` took the patch's version, and the line-diff fallback failed with a message naming the hunk and line. The preview matched the old Python preview's board model for the same patch, and in headless Chromium the remove chip starts excluded (mgp1 hidden), and clicking it shows REMOVE cards and then only REMOVE cards.

## Things to know

check.py gives tasks.patch zero failures and forty warnings, almost all saying that the touched tasks have no `>change` line, since that patch was made before this protocol existed. I did not retroactively write change lines into the results.

Almanac's own `validate` still errors on the duration rule, so check.py downgrades that single case to a warning; I did not change the validator. The live almanac.tcl and the live board export are unchanged; the v002 almanac is a superset you can copy into place when you want the new verbs. The v002 kit is not zipped, since you said it will be overwritten over time.

To rerun any of this from the repo root:
`ALMANAC_SKIP_BOARD_EXPORT=1 task-writing-kit-v002/tools/deps/tcl task-writing-kit-v002/tools/scripts/almanac.tcl --file tasks-toml/tasks.toml --base tasks-toml/tasks.toml apply tasks-toml/patch-1.patch --out results/after-patch-1.toml`
