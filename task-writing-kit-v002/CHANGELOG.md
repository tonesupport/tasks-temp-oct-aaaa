# Changelog
## v001 (2026-10-13)
First release, modeled on plot writing kit v004's startup and handback rules. Includes the snapshot (341 tasks), almanac plus its dependencies, check.py, make-patch.py, task-preview.py (unencrypted monolithic Sight HTML), the ground truth survey input, and examples. Versions are plain integers: the next one is v002, never dotted.

## v002 (2026-10-14)
Working draft, rewritten as almanac and the workflow change. almanac.tcl gains apply, preview, change and show verbs, an id filter for ls, and the REMOVE status. make-patch.py and task-preview.py are gone (use diff -u and `almanac preview`). check.py is two tiers: integrity FAILs, everything else WARN; removals are a WARN; the delete earmark and the changes.md requirement are dropped in favor of stamped `>change` lines in task notes. The remove filter in the HTML board defaults to hidden.

## v002, packing (2026-10-14)
Added pack-almanac.tcl and dist/almanac.tcl (single file, pure ASCII, helpers inlined, preview assets and 13 fonts embedded); almanac verbs emit (style, template, fonts) and setup (Python launcher); preview --style; `catch {encoding system utf-8}` at the top; non-ASCII removed from almanac.tcl (Tcl 8.6 read the old bullet and dash characters as mojibake). Atkinson Next was removed earlier.
