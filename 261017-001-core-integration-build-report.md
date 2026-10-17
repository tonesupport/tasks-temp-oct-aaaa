# Changes of the 2026-10-17 build

This build integrates the portable core of HANDOFF-261017.md into the Bridge page and rebuilds the page from this tree. This document lists what changed compared with the tree as it was before the handoff, what was found along the way, and what is left for a decision. The how-to is in BUILD.md; the design of the integration is in bridge/core-integration.md.

## What the build does now

The page carries the portable core. `core/lib` (without `lib/tk`), `core/bin` and `core/main.tcl` are embedded as plain text, one script tag per file. The whole vendored tcllib (`core/vendor/tcllib`, 789 files, 15.7 MB) is embedded as one gzip'd tar in base64 (2.1 MB compressed) and unpacked at boot with `DecompressionStream` into `/core/vendor/tcllib` in the interpreter's filesystem. `core/vendor/tklib` and `core/doc` are not embedded. At boot, `bridge/tcl/core.tcl` puts `/core/lib` and `/core/vendor/tcllib` on the shell's `auto_path`, makes `::core::style` really on for interactive use, loads `test` from `/core/bin/coretest.tcl`, and defines `import` and `export`. Details, including the notice that appears when an imported file arrives, are in bridge/core-integration.md.

The build has two new stages in front of the old ones: `tclsh` builds a native Tcl 9.1.0 from `dl/` into the ignored, unzipped `toolchain/` directory in the tree, and `core` verifies the core sources and runs the core gate (659 pass / 0 fail, 27 files). The order is `tclsh`, `core`, `wacl`, `vi`, `mle`, `ghostty`, `page`.

The wacl runtime was rebuilt in the tree, twice, without tcllib. The D14 change the handoff described is complete: `wacl-build/build.sh` no longer extracts or packs tcllib, `wacl-build/custom/tcllib-shim/` is deleted, and the page's own `::lib::` tree replaces it. The two lines that used the old names were remapped after the full tree was embedded, as the handoff said they must be: `bridge/tcl/sh.tcl` line 2388 (`json::json2dict` became `::lib::json::json2dict`) and `bridge/tcl/help.tcl` line 2672 (the example `uri::split` became `::lib::uri::split`). The userspace suite passes 1337 of 1337 with the full tree mounted.

## Files changed or added

New: `core/` (imported from the handoff), `HANDOFF-261017.md`, `BUILD.md`, this file, `bridge/core-integration.md`, `bridge/src/core-boot.js`, `bridge/src/core-host.js`, `bridge/tcl/core.tcl`, `bridge/tcl/core-docs.tcl`, `bridge/tests/core.js`, `bridge/tests/mount-core.js`, `bridge/tests/parity/` (`parity.tcl`, `functional.tcl`, `run.js`, `regressions.py`, `boundaries.txt`, and the recorded results).

Changed: `build.sh` (stages `tclsh` and `core`, test list, help), `tools/verify.py` (checks named entries), `bridge/build.py` (embeds the core), `bridge/src/tcl-runtime.js` (`captured`), `bridge/src/term-session.js` (`notify`, `landed`, `later`), `bridge/tcl/sh.tcl` and `bridge/tcl/help.tcl` (the two remapped lines; help.tcl also has the `file` topic from the handoff), `bridge/tests/userspace/run.js`, `bridge/tests/term/lib.js` and `bridge/tests/e2e.js` (the core mounted as in the page; new checks), `wacl-build/build.sh` and `wacl-build/README.md`, `PREBUILTS`, `vendor/MANIFEST`, `README.md`, `TOOLCHAIN.md`, `bridge/terminal-architecture.md`, `.gitignore` (`toolchain/`, `__pycache__/`).

Deleted: `wacl-build/custom/tcllib-shim/`, and the empty directory `core/lib/action.tcl lib` that came with the handoff. The directory `--help/doc/` that the handoff archive also contained was not imported.

Fixed in the vendored sources: three bugs of the namespace rewrite in `core/vendor/tcllib/uri/uri.tcl` and `urn-scheme.tcl`, which stopped `uri` from loading in any Tcl (the call `uri::register`, doubled `::lib::uri::lib::basic` paths, and a namespace eval of the wrong name). They had been patched with `sed` inside `wacl-build/build.sh`, which is why the page worked; they are now fixed at the source, and `build.sh` no longer touches tcllib.

## Two runtime gaps found and fixed

While making sure that every package that loads in a desktop Tcl also loads in the page, two gaps of the wacl runtime turned up. Both were in the runtime before this build.

The Tcl modules that ship as `.tm` files (`http`, `msgcat`, `platform`, `platform::shell`, `tcltest`) could not be found, because the runtime's package finder does not include Tcl's tm machinery. Every tcllib package that needs `msgcat` failed for this reason too. `core.tcl` now sources `tm.tcl` and wraps the finder (`::coreboot::pkgsetup`), so they load.

The Tcl library's `tclIndex` had been deleted when the data file was made, so `parray`, `readfile`, `writefile`, `foreachline` and `history` were not available in the shell, and `tcltest` could not load. `wacl-build/build.sh` now keeps `tclIndex`; that is why the runtime was rebuilt a second time.

## Findings that need a decision

The vendored tcllib is broken for 145 packages. The upstream tcllib 2.0 loads 398 of its 455 packages under Tcl 9.1 in a fresh-interpreter test; the vendored `::lib::` tree loads 253, in a desktop Tcl as well as in the page. The 145 packages that load upstream but not in the vendored tree are listed with their errors in `bridge/tests/parity/vendoring-regressions.csv`: 73 of the `snit` family, 32 with namespace paths the rewrite doubled or half-rewrote, 23 with import patterns naming a namespace that no longer exists (mostly `msgcat` users), and 17 that call moved commands by their bare names. Because the vendored tree is the source of truth (D14), these were not repaired here. The question for you is whether to fix the transform in `core/tools/vendor-libs.tcl` and regenerate, or to fix packages one by one in the tree. Either way the page picks up the change at the next page build, and the parity test shows the effect. The platform requirement "any `package require` that works natively must work in the page" holds against the vendored tree (252 of 253, the exception being a package that looks for `tput` and `stty`), but the vendored tree is itself short of what upstream tcllib offers.

The tklib in `core/vendor/tklib` has no recorded source version, and its tarball is not in `dl/`. As agreed, nothing was downloaded; the files are hashed in `vendor/MANIFEST` with the gap written down. It is Tk-only and the page does not embed it.

Regenerating `core/vendor` from `dl/tcllib-2.0.tar.gz` is not byte-stable (515 comment-level differences, and the three `uri` fixes are not in the transform), as you said it would be. The committed tree is the source of truth, and `vendor/MANIFEST` says so next to its hash. `dl/tcllib-2.0.tar.gz` is no longer a build input, only the upstream reference.

The encoding tables (`*.enc`) are not in the wacl data file, so `encoding names` lists the dozen built into Tcl, not the desktop's hundred, and a script that converts from `cp1252` and the like fails. This was true before the build, it does not affect `package require`, and it costs about a megabyte to change. It is documented, not fixed.

`wacl.js` and `wacl.wasm` embed the absolute build path, so their hashes depend on where the tree is checked out. `PREBUILTS` records the hashes of this tree's build, and the earlier claim of a byte-identical rebuild at one particular path has been dropped from TOOLCHAIN.md and `PREBUILTS`. A rebuild elsewhere will report `DIFFERS` for those two files; that is expected.

## What was not done, on purpose

`vi`, `mle` and `ghostty` were not rebuilt. Their prebuilts are the ones from 2026-10-16 and `./build.sh --verify` confirms them against `PREBUILTS`. `wacl-build/verify.js` (it hard-codes the original build path) is unchanged and is not part of the pipeline. The open items in the handoff (the `cmd` link policy, Knuth-Plass wrapping, the `table` verb, the `/proc/self` `ls` bug and the others) are untouched; the `/proc/self` bug in particular was left alone because the handoff says not to fix it without authorization. `bridge/farm/briefs/` and the hand-built `-core` HTML of the prototype are not in the tree and not needed.

## Test results

Core gate 659 pass / 0 fail (27 files). `unit.js` 54/0. `core.js` 50/0. Userspace 1337/0. Terminal layer, tcled and pick 360/0. Package parity: 253 packages load in the desktop Tcl, 252 in the page, one documented boundary, 63 of 63 functional cases equal. The finished page: 47 of 47 checks in Chromium and 46 of 46 in Zen, including `test`, `help file`, `help import`, `package require`, `::lib::` commands, `from-json`, a styled line, `import` of a file (through a captured picker, and in Chromium through the real chooser) and of a URL, the Tcl hook, and `export`. The mle and nextvi suites are unchanged by this work; see BUILD.md for the full list.
