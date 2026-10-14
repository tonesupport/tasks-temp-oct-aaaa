# Confirmation: apply patch-1, apply tasks.patch, and bake apply and preview into almanac.tcl

## What I checked

The uploaded REMOVE zip is here and complete. It contains the REMOVE versions of almanac.tcl (STATUS_ORDER, STATUS_ENUM and the usage text), check.py (including the delete earmark that we are dropping), task-preview.py, task-spec.md, board.js (the remove filter, which currently defaults to showing REMOVE cards) and artifacts.css (a struck-through pill style). So nothing has to be reimplemented from the notes; I will start from these and from the archive's other files.

patch-1.html has not been applied to anything I can see. It is a rendered review of a separate earlier patch: 33 new tasks from the survey breakdown, rendered on Oct 13 at 5:31 PM Pacific, all with ids that appear neither in the snapshot nor in tasks.patch. Its review panel lists every field of every one of the 33 tasks in full (title, status, domain, project, notes, created, updated, tags), so I can reconstruct each task exactly from the page. I can't see your live tasks.toml, so I can't tell whether you already applied those 33 there. I will assume you did not, and I will mention which of them look already present if you give me a newer tasks.toml.

tasks.patch applies cleanly to the snapshot with the strict v001 applier and touches 51 tables, with 40 tasks listed in changes.md. Because its ids do not overlap patch-1's, patch-1 and tasks.patch are independent, which makes them a good pair for testing the table-level rebase: the second one applied onto a file that has already moved on.

## What I will do, in order

First, build `$ALM apply PATCH` and `$ALM preview [OUT.html]` directly into almanac.tcl as new verbs beside the existing ones, with the existing logic untouched apart from the REMOVE fix (already in the zip). Apply follows your earlier decisions: table-level rebase first, strict line-diff fallback, always a new TARGET.patched file, never in place, almanac validate on the result before writing, and a count of added, changed, removed and conflicting tasks. Preview renders the --file target as a single HTML page using the skin folder next to almanac.tcl, and REMOVE cards are hidden by default (the filter default in board.js changes from showing to hiding).

Second, apply patch-1 by rebuilding its 33 tasks from the HTML into a patch and running it through the new apply verb, and compare the result with the page. Then apply tasks.patch on top of that result. I will use both as test cases for the new verbs and report any conflicts.

## One question

For preview, I need to know where change highlighting comes from. My default: preview marks new, changed and done cards relative to the kit's snapshot/tasks.toml when it exists beside almanac.tcl (and a --base PATH flag overrides it), and it renders a plain board with no highlights when there is no base. Tell me if you want something different.

I am waiting for your go.
