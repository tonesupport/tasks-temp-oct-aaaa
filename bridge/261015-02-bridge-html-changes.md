# Changes in bridge-wacl-261015-userspace.html

This is your bridge-wacl-261015122-latest.html with the new Tcl userspace embedded. It is a drop-in replacement: same runtime, same window logic, same adapter. I named it bridge-wacl-261015-userspace.html so it cannot be mistaken for bridge.html, the upstream source that the architecture notes say must not be edited; the file is generated output, like the one you gave me.

## What changed inside the file

Two things changed and nothing else. First, the string `window.__shTcl`, which the adapter evaluates at boot, now holds `sh-boot.tcl` instead of the old 4 KB profile. `sh-boot.tcl` is the full userspace (`sh.tcl`, 134 KB) compressed and base64-encoded inside a few lines of plain Tcl that inflate and evaluate it. The compression is necessary, not a convenience: the adapter hands the whole profile to wacl in one `Eval`, and wacl can only take about 64 KB at a time. Anything larger crashes the interpreter for every window until reload. The packed form is 56 KB, so it fits with about 8 KB to spare. Second, the `?` help panel's "Shell commands" section, which listed the eleven old commands, now describes the new userspace and points at `help`, `help start`, `help <command>`, `help <topic>`, `apropos` and `clear`. I edited that text in the HTML directly because I do not have the build script that normally rewrites it; if you rebuild with your script, the panel text will go back to whatever the script writes, so update it there too.

## What you get at the prompt

The shell starts in its own top (shown as /) instead of the system root. `help` lists about ninety commands in groups (places and things, text, lists, rows and tables, composing and exploring) plus sixteen guide topics, and `help start` is a ten-minute tour for someone who has never used a command line. The old commands still work and are friendlier: `ls` and `ll` take flags and patterns, `rm` refuses to delete the files Tcl needs, `cp` and `mv` take several sources and patterns, `cat` refuses binary files and points at `xd`, and every error begins `command: what went wrong`. New command families: text tools (`grep`, `sed`, `sort`, `uniq`, `diff`, `tr`, `head`, `tail`, `wc`, `fields`, `extract`, `fmt`), file tools (`save`, `tee`, `walk`, `hash`, `search`, `du`, `xd`, `touch`, `date`), list and table tools (`where`, `select`, `pluck`, `each`, `keep`, `reduce`, `sort-by`, `group-by`, `tally`, `table`, `parse`, JSON and CSV readers and writers), and composition helpers (`|>`, `~`, `^`, `whatis`, `alias`). Files named NAME.tcl in /bin run when you type NAME. Unknown commands now end with a short hint, for instance pointing `find` users to `walk`.

## How I checked it

I opened this exact file in Chromium, typed a session at the real prompt (making places, saving text, listing, drawing a table, parsing text into rows and filtering them) and saw no page errors. The test suite also passes against it: 613 checks, which boot the runtime and adapter from this HTML and cover every command, including the exact error wording. I did not test other browsers.

## Things to know before you use it

The window's first input line may carry the prompt text in my automated typing, which is an artifact of how I drove the page, not of the shell. Files still live only in memory and vanish on reload. `puts` and `echo` output still arrives with a trailing carriage return from wacl, as before. Errors still show Tcl's full trace after the first line; the first line is the one to read. A runaway loop still freezes the page. If you later change the adapter to write `sh.tcl` into the file system and source it, you can embed the readable file and drop the packed stub; the repository notes (261015-01) give the three-line change.
