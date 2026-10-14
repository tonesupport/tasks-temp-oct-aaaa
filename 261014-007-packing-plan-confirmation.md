# Confirmation of the packing and launcher plan, with findings and a proposed build layout

I have read the plan and checked what I could against the repo and this machine. Nothing is implemented yet.

## The blocker is cleared, and the assets are safe to embed

The 13 WOFF2 files are already in the repo at `task-writing-kit-v002/skin/fonts/web/`, and `artifacts.css` references exactly those 13 (nothing in `board.css` references fonts). The repo's almanac.tcl is 3,139 lines, which matches the file the plan describes. The path named in the plan, `~/workspace/user/files/almanac-claude-mod-2610141517.tcl`, does not exist on this machine, so I will work from the repo copy; if your copy has changed since you attached it, send it.

All four text assets pass the braced-literal check. Braces balance in each (sight-index.html 10/10, artifacts.css 203/203, board.css 250/250, board.js 811/811), none ends in a backslash, none contains a backslash-newline or an escaped brace, and there are no carriage returns. board.js has 8 dollar signs and 293 open brackets, which are harmless inside braces. The build script will run these checks itself and stop if any fail, as the plan asks.

## A real problem I found: non-ASCII text under Tcl 8.6

I built a real Tcl 8.6.14 shell from source here and ran the current script under both interpreters. Nine of ten checks match exactly (ls, ls id=, show, validate, apply, change). The one difference is preview: the square bullet in the review panel prints as mojibake under 8.6. The cause is that Tcl 8.6's `source` reads a script in the system encoding, which is Latin-1 in a POSIX locale, while Tcl 9 reads it as UTF-8. Putting `encoding system utf-8` near the top of the script (item H) is too late to help, because the script's own text has already been read. The assets would hit the same problem, since they contain 163 non-ASCII characters between them.

My proposed fix is to make the packed file pure ASCII, so it behaves the same under any locale and either Tcl. The build script encodes each non-ASCII character in an embedded asset as a token such as `@@U+25A0@@` and the script decodes tokens when it reads the asset (the build asserts the token pattern never occurs naturally in the sources). In almanac.tcl itself, the non-ASCII characters that are in real strings (the init header, one die message, the review panel bullet, the footer separator) become `\u` escapes, and the build fails if any non-ASCII is left outside a comment. The Python launcher will also set the encoding to UTF-8 and use `source -encoding utf-8` as a second layer.

## Testing the Python launcher here

The system Python has no tkinter, and the apt package is not available. I installed a standalone Python through uv that has tkinter, but it embeds Tcl 9.0.4, not 8.6.14. So I can test the launcher's mechanics (argv handling, exit interception, setup, parity of output) on tkinter with Tcl 9.0.4, and I can test the script itself on a real tclsh 8.6.14, but I cannot test the one exact combination of the launcher on tkinter's Tcl 8.6.14, which is what your machine runs. I will say so in the report for verification items 5 and 7 and give a short manual check for your machine.

One launcher detail to build in: some almanac code paths wrap calls in `catch`, so an intercepted `exit` could be swallowed and the script would carry on. The launcher will record the first exit code and use it, so a later swallowed exit cannot change the result.

## Answers to the questions marked in the plan

board.js should be inlined only. It is already inlined into the page, and the build keeps it as an embedded literal, so no separate emitted asset is needed. I recommend dropping `emit script`, since the file stays in the repo as a source asset. I recommend keeping `emit style`, `emit template` and `emit fonts`: style and fonts are the ones a theme author needs.

I recommend keeping `artifacts.css` and `board.css` as two layers, not merging them. board.css uses 30 CSS variables, 24 of which are defined in artifacts.css and 7 of which it defines itself (one, `--shed-danger`, is defined nowhere and already falls back). So board.css depends on artifacts.css for its colors and spacing, and `--style` replacing artifacts.css means a custom theme must supply those 24 variables. If the layers were merged, the structural rules would move into the replaceable layer and the guarantee that a theme cannot break layout would be lost. Instead, I suggest `preview --style` print a warning naming any variable the structural layer needs that the custom stylesheet does not define.

On verification item 3, I agree it is weak as written: checking that structural selectors are present proves little. I would replace it with a render check in headless Chromium: preview with a custom style that only redefines those variables, and confirm the board draws the same cards with the new colors, and that a style missing variables produces the warning. I am not sold on `--style` being important, but it is small, so I will build it with that warning and no more.

## Proposed layout for the build script

The loose, editable script stays where it is, at `tools/scripts/almanac.tcl`, and it keeps loading `cli.tcl` and `tama.tcl` from beside it. It gets a small accessor so that preview asks for an asset by name: if the packed variable exists, it uses that, and otherwise it reads the file from the skin folder. This means the one code path serves the loose script (assets read from `skin/`, which is also today's `--skin` behavior) and the packed script (assets embedded). The build script, `task-writing-kit-v002/build.tcl`, is written in Tcl 9.0.4 and runs from the kit root. It reads the loose almanac.tcl, cli.tcl, tama.tcl, the four text assets and the 13 fonts, runs the safety and ASCII checks, inlines the dependencies so the packed file is a single file, embeds the assets and the font dict, and writes `dist/almanac.tcl`. Output is deterministic, with no timestamps, so `build.tcl --check` can tell whether dist is current. After writing, the build sources the packed file in a fresh interpreter and compares every embedded asset byte for byte against its source, which covers verification item 1 at build time.

## What I need from you

Please confirm or change these defaults. First, that `dist/almanac.tcl` is the packed output, with `tools/scripts/almanac.tcl` staying the file you edit. Second, that the build inlines cli.tcl and tama.tcl so the packed file is truly one file (my recommendation), instead of leaving them as siblings. Third, that `emit script` is dropped and the other three emit verbs stay. Fourth, that the pure-ASCII encoding approach above is acceptable. The deferred items (the `check` routine and priming or context embedding) stay deferred.

I will wait for your go.
