# Task spec v002

This spec is a working draft, not a source of truth. It changes as almanac and the workflow change. When it disagrees with almanac.tcl, almanac.tcl wins.

## 0. Run rules
- Read the kit files and every input in full before you start. If an input comes with a coverage file, write `read X of Y bytes` for each input in it.
- Files that arrive with no text are the go signal. Proceed without asking.
- Work on a copy (work/tasks.toml). The snapshot is the frozen base the patch is made against; leave it alone. Do not touch live files or repos, and do not commit or push unless the user says so.
- Return tasks.patch. Run check.py first: it must report 0 FAIL. WARN items are for a reader, not blockers.
- The user applies the patch with `almanac.tcl --file TARGET apply tasks.patch`, which writes TARGET.patched and never touches TARGET.

## 1. File format
tasks.toml is TOML with one `[<id>]` table per task. The `root` / spine section at the top is structure. Don't change it unless the user asks.

Required keys: `title`, `status`, `created`, `updated`, `tags`.
Optional keys: `domain` (HH MED CTP FIN DEV, or the others in use), `project`, `notes`, `datetime`, `time`, `duration`, `completed`, `blockers`, `reminder`, `signaling-command`, `coordinating-agents`, `field_links`, `tosu`.
Forbidden: `content`.

## 2. Statuses
`urgent now progress today later deferred sched done REMOVE`
- `REMOVE` (uppercase) marks a task the user wants taken off the list. It stays in the file and renders in the preview, where the remove filter hides it by default. Set it with `almanac set <id> status=REMOVE`.
- `done` needs `completed`. Use `almanac done <id>`.
- `sched` needs `datetime`.
- `datetime` format is `Ddd Mmm D YY`, for example `Tue Nov 3 26`.

## 3. Stamps
`created`, `updated`, and `completed` are 10-digit integers, YYMMDDhhmm in America/Los_Angeles. Almanac sets them. Never change `created`. `updated` goes up on every change.

## 4. Tags
- Write tags as a single-quoted TOML array, for example `tags = ['task','acct']`.
- Every task must have the tag `'task'`, never `'tasks'`.
- Almanac adds `'tosu'` for personal domains (HH MED CTP FIN DEV). Don't add other tags that the input doesn't support.

## 5. IDs
IDs are random `[a-z0-9]{4}` and only almanac allocates them (`almanac add`). Never pass `id=` to add, and never pick, guess, reuse, or make a mnemonic for one. Never renumber existing IDs.

## 6. Titles and wording
- One concrete action or fact per title, in plain, neutral words.
- No master-plan codes (inf3, rep2, shd1, ...), no IDs, and no code prefixes in titles.
- Specs and task text never name agents. Describe the work, not who does it.
- Notes give context needed to act, written factually. No hype and no speculation unless it's labeled.

## 7. Editing
- Reads and writes of tasks.toml both go through almanac: `ls`, `show` and `filter` to read, `add`, `set`, `done` and `change` to write. Use grep only when almanac cannot answer.
- Hand-editing is allowed when almanac cannot make the change. Say so in the task's change line.
- Removing a task is an ordinary change. check.py lists removed tasks as a WARN so a reviewer sees them, but never fails on them. REMOVE is the reviewable option: the task stays in the file and the preview hides it. Prefer it when the user may want to look again.
- Blockers must name existing IDs and never the task itself.

## 8. Breaking down a document
- Go through it section by section. Before adding anything, look for an existing task that covers each item (`almanac ls`, `almanac show`). If one exists, change it; don't add a duplicate.
- Stale or superseded items are dropped with a reason.
- `{{...}}` annotations in an input are the user's own notes. They take priority over the text around them.
- A coverage file is optional. If you write one, use one row per section: `section -> id, id`, or `exists: id`, or `dropped: reason`, then a line `read X of Y bytes`. check.py only warns about it.

## 9. Change notes
Every task a patch touches carries its own change history in its notes. Do not overwrite the notes; append one line per change with `almanac change <id> "why"`, which writes:

`>change (YY-MM-DD hh:mm AM): why`

The stamp is local time (America/Los_Angeles) in twelve-hour form. Existing notes text stays as it is, with the new line added after it. There is no changes.md; when a patch is applied again later, the history is already in the tasks. check.py warns when a touched task has no new `>change` line or when its existing notes text was altered.

## 10. Patch
A unified diff of exactly one file, with the snapshot as the base (`diff -u snapshot/tasks.toml work/tasks.toml > tasks.patch`). It must apply cleanly to the snapshot with no fuzz. Applying it to a live file is table-level by task id, so the live file may have moved on since the snapshot.
