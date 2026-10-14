# Review rubric
1. check.py: 0 FAIL. Each WARN is explained or fixed.
2. Patch applies to the snapshot cleanly, and only tasks.toml is touched.
3. Each new task is one concrete action with a neutral title, no codes, and no IDs.
4. No duplicates of existing tasks. Overlaps are mapped as `exists:`.
5. Statuses are realistic. sched has a datetime and done has completed.
6. Tags are single-quoted and include 'task'. No invented tags.
7. IDs were allocated by almanac. Nothing is hand-picked or a mnemonic.
8. Every touched task has a `>change (YY-MM-DD hh:mm AM): why` line added to its notes, existing notes untouched, and each why is short and accurate.
9. If a coverage file is given, it maps every survey section and has a full-read line.
10. Stale survey items are dropped with a reason, and `{{annotations}}` were respected.
11. No agent names anywhere. No spine edits unless requested.
12. `almanac preview --base` renders, and the highlights match the touched tasks.
