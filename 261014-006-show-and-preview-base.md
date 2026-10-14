# show, preview --base, and the plain preview of the patched file

Yes, `$ALM show <id>` is implemented and tested. It prints the one task's full table, including notes, and exits with an error saying "unknown id" if there is no such task. For example, `$ALM --file results/after-both.toml show 2ef1` prints the Oct 15 meeting task.

`preview --base` does not look at any patch. It takes two tasks files and compares them: the file named by `--file` (the one being drawn) and the file named by `--base` (the "before"). Any task that is in `--file` but not in `--base` is marked new, any task that differs is marked changed (or done, or REMOVE if that is what changed), and the review panel lists the field differences. A patch never enters into it. The usual use is to apply a patch first, which gives a new file, and then preview that new file against the original: `--file tasks.toml.patched --base tasks.toml`. Without `--base`, nothing is marked and you get a plain board.

The plain preview of the latest state, with both patches applied and no highlighting, is `results/after-both-preview.html`, rendered from `results/after-both.toml` (399 tasks). REMOVE cards are hidden by default; the remove filter shows them.
