#!/usr/bin/env tclsh
# pack-almanac.tcl -- build dist/almanac.tcl, the single-file almanac.
#
#   tools/deps/tcl pack-almanac.tcl            build dist/almanac.tcl
#   tools/deps/tcl pack-almanac.tcl --check    exit 1 if dist/almanac.tcl is not what a build would write
#   tools/deps/tcl pack-almanac.tcl --unpack DIR
#                                              split a packed almanac.tcl back into its modules and assets
#
# Sources (edit these, never dist/):
#   tools/scripts/almanac.tcl      the script itself; loads its helpers with `source`
#   tools/scripts/cli.tcl          argument parsing        -> inlined as MODULE cli.tcl
#   tools/lib/tosu/tama.tcl        TOML reader             -> inlined as MODULE tools/lib/tosu/tama.tcl
#   skin/sight-index.html, artifacts.css, board.css, board.js    -> embedded as ASSET_* variables
#   skin/fonts/web/*.woff2         -> embedded as FONT_blobs (relative path -> base64)
#
# The packed file is pure ASCII (so it reads the same under Tcl 8.6 and 9 whatever the locale): non-ASCII
# characters in the embedded assets are written as @@U+XXXX@@ tokens that almanac::asset_decode turns back.
# Every section is fenced by lines of the form
#     # >>>> MODULE <path>   ...   # <<<< MODULE <path>
#     # >>>> ASSET <name> <file>  ...  # <<<< ASSET <name>
#     # >>>> FONTS ...        ...   # <<<< FONTS
# so a reader (or --unpack) can cut the file back apart.
# Output is deterministic: no timestamps, fixed ordering.

set here [file dirname [file normalize [info script]]]
catch {encoding system utf-8}

proc fail {msg} { puts stderr "pack-almanac: $msg"; exit 1 }

proc readfile {path} {
    if {[catch {open $path rb} fh]} { fail "cannot read $path" }
    set b [read $fh]
    close $fh
    return [encoding convertfrom utf-8 $b]
}
proc writefile {path text} {
    file mkdir [file dirname $path]
    set fh [open $path wb]
    puts -nonewline $fh [encoding convertto utf-8 $text]
    close $fh
}

# ---------- checks ----------

# A braced Tcl literal is safe if braces balance (ignoring backslash-escaped ones), no backslash-newline,
# no backslash before a brace, and it does not end in a backslash.
proc braced_safe {name text} {
    set depth 0
    set n [string length $text]
    for {set i 0} {$i < $n} {incr i} {
        set c [string index $text $i]
        if {$c eq "\\"} {
            set nx [string index $text [expr {$i + 1}]]
            if {$nx in {"\n" "\{" "\}"}} { fail "$name: backslash before a newline or brace at offset $i; not safe as a braced literal" }
            incr i
            continue
        }
        if {$c eq "\{"} { incr depth } elseif {$c eq "\}"} { incr depth -1 ; if {$depth < 0} { fail "$name: unbalanced braces (extra close at offset $i)" } }
    }
    if {$depth != 0} { fail "$name: unbalanced braces ($depth open at end)" }
    if {[string index $text end] eq "\\"} { fail "$name: ends in a backslash" }
    if {[string first "\r" $text] >= 0} { fail "$name: contains carriage returns" }
}

proc assert_ascii {name text} {
    set n [string length $text]
    for {set i 0} {$i < $n} {incr i} {
        if {[scan [string index $text $i] %c] > 127} {
            set line [llength [split [string range $text 0 $i] "\n"]]
            fail "$name: non-ASCII character U+[format %04X [scan [string index $text $i] %c]] at line $line; the dev script must stay ASCII (use \\u escapes in strings, plain ASCII in comments)"
        }
    }
}

# non-ASCII -> @@U+XXXX@@
proc tokenize {name text} {
    if {[string first "@@U+" $text] >= 0} { fail "$name: contains the literal text @@U+ which the packer uses as its token" }
    set out {}
    set run {}
    set n [string length $text]
    for {set i 0} {$i < $n} {incr i} {
        set ch [string index $text $i]
        scan $ch %c cp
        if {$cp > 127} { append out [format "@@U+%04X@@" $cp] } else { append out $ch }
    }
    return $out
}

# ---------- build ----------

set ASSETS {
    sight_index_html skin/sight-index.html
    artifacts_css    skin/artifacts.css
    board_css        skin/board.css
    board_js         skin/board.js
}
set MODULES {tools/scripts/cli.tcl tools/lib/tosu/tama.tcl}
set BEGIN_MARK {# @@PACK:BEGIN deps}
set END_MARK {# @@PACK:END deps}

proc build {} {
    global here ASSETS MODULES BEGIN_MARK END_MARK
    set src [readfile [file join $here tools scripts almanac.tcl]]
    assert_ascii tools/scripts/almanac.tcl $src

    # 1. split the dev script around the deps block
    set b [string first $BEGIN_MARK $src]
    set e [string first $END_MARK $src]
    if {$b < 0 || $e < 0 || $e < $b} { fail "almanac.tcl has no '# @@PACK:BEGIN deps' ... '# @@PACK:END deps' block" }
    set be [string first "\n" $src $b]
    set ee [string first "\n" $src $e]
    set head [string range $src 0 [expr {$b - 1}]]
    set tail [string range $src [expr {$ee + 1}] end]

    # 2. modules
    set mods {}
    foreach m $MODULES {
        set t [readfile [file join $here $m]]
        assert_ascii $m $t
        if {[string index $t end] ne "\n"} { append t "\n" }
        append mods "# >>>> MODULE $m\n$t# <<<< MODULE $m\n\n"
    }

    # 3. assets
    set assets "# === EMBEDDED PREVIEW ASSETS -- generated by pack-almanac.tcl from skin/; edit the sources, not this ===\n"
    append assets "# Non-ASCII characters are written as @@U+XXXX@@ tokens (see almanac::asset_decode).\n"
    append assets "namespace eval almanac {}\n\n"
    foreach {name file} $ASSETS {
        set t [readfile [file join $here $file]]
        braced_safe $file $t
        if {[string index $t end] ne "\n"} { append t "\n" }
        append assets "# >>>> ASSET $name $file\nset ::almanac::ASSET_$name \{[tokenize $file $t]\}\n# <<<< ASSET $name\n\n"
    }

    # 4. fonts
    set fontfiles [lsort [glob -nocomplain -directory [file join $here skin fonts web] *.woff2]]
    set css [readfile [file join $here skin artifacts.css]]
    set refs {}
    foreach {all rel} [regexp -all -inline {url\("(fonts/[^"]+)"\)} $css] { lappend refs $rel }
    set refs [lsort -unique $refs]
    set have {}
    foreach f $fontfiles { lappend have "fonts/web/[file tail $f]" }
    if {[llength $have] != 13} { fail "expected 13 fonts in skin/fonts/web, found [llength $have]" }
    foreach r $refs { if {$r ni $have} { fail "artifacts.css refers to $r which is not in skin/fonts/web" } }
    foreach h $have { if {$h ni $refs} { fail "font $h is not referenced by artifacts.css" } }
    set fonts "# >>>> FONTS skin/fonts/web (relative path -> base64, wrapped at 76 columns)\nset ::almanac::FONT_blobs \[dict create \\\n"
    foreach f $fontfiles {
        set fh [open $f rb]
        set data [read $fh]
        close $fh
        set b64 [binary encode base64 $data]
        set lines {}
        for {set i 0} {$i < [string length $b64]} {incr i 76} { lappend lines [string range $b64 $i [expr {$i + 75}]] }
        append fonts "  fonts/web/[file tail $f] \{\n[join $lines "\n"]\n\} \\\n"
    }
    append fonts "\]\n# <<<< FONTS\n\n"

    # 5. assemble. The assets must exist before the script body runs (they are only variables), so they go
    # after the modules and before the body.
    set out $head
    append out "# @@PACKED by pack-almanac.tcl: modules, assets and fonts below are inlined copies of the files named in their fences.\n"
    append out $mods $assets $fonts $tail
    assert_ascii dist/almanac.tcl $out
    return $out
}

proc selftest {packed} {
    global here
    # Run the packed script and compare what it emits with the sources.
    set tcl [info nameofexecutable]
    set tmp [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] pack-almanac-[pid]]
    file mkdir $tmp
    set fails 0
    foreach {what file} {style skin/artifacts.css template skin/sight-index.html} {
        set outp [file join $tmp $what.out]
        if {[catch {exec $tcl $packed emit $what $outp} err]} { puts stderr "pack-almanac: selftest: emit $what failed: $err"; incr fails; continue }
        if {[readfile $outp] ne [readfile [file join $here $file]]} { puts stderr "pack-almanac: selftest: emit $what differs from $file"; incr fails }
    }
    # board.css and board.js are checked through the same decode path the page uses
    set probe [file join $tmp probe.tcl]
    writefile $probe "set argv0 x\nsource [list $packed]\nforeach {n f} [list [list board_css [file join $here skin board.css] board_js [file join $here skin board.js]]] \{\n  set fh \[open \$f rb\]; set b \[encoding convertfrom utf-8 \[read \$fh\]\]; close \$fh\n  if \{\[almanac::asset \$n\] ne \$b\} \{ puts \"DIFF \$n\" \}\n\}\nputs ok"
    if {[catch {exec $tcl $probe} res]} { puts stderr "pack-almanac: selftest: $res"; incr fails } elseif {$res ne "ok"} { puts stderr "pack-almanac: selftest: $res"; incr fails }
    set fdir [file join $tmp fonts]
    if {[catch {exec $tcl $packed emit fonts $fdir} err]} { puts stderr "pack-almanac: selftest: emit fonts failed: $err"; incr fails } else {
        foreach f [glob -directory [file join $here skin fonts web] *.woff2] {
            set g [file join $fdir web [file tail $f]]
            if {![file exists $g]} { puts stderr "pack-almanac: selftest: missing font $g"; incr fails; continue }
            set a [open $f rb]; set b [open $g rb]
            if {[read $a] ne [read $b]} { puts stderr "pack-almanac: selftest: font [file tail $f] differs"; incr fails }
            close $a; close $b
        }
    }
    file delete -force $tmp
    return $fails
}

proc unpack {packed dir} {
    set text [readfile $packed]
    set n 0
    set pos 0
    while {[regexp -indices -start $pos {# >>>> (MODULE|ASSET|FONTS)[^\n]*\n} $text m g]} {
        lassign $m ms me
        lassign $g ks ke
        set kind [string range $text $ks $ke]
        set header [string range $text $ms [expr {$me - 1}]]
        set endre "# <<<< $kind"
        set e [string first "\n$endre" $text $me]
        set body [string range $text [expr {$me + 1}] [expr {$e}]]
        switch -- $kind {
            MODULE {
                set path [lindex $header 3]
                writefile [file join $dir $path] $body
                incr n
            }
            ASSET {
                set file [lindex $header 4]
                # body is: set ::almanac::ASSET_name {....}
                set open [string first "\{" $body]
                set close [string last "\}" $body]
                set lit [string range $body [expr {$open + 1}] [expr {$close - 1}]]
                set decoded {}
                set p 0
                while {[regexp -indices -start $p {@@U\+([0-9A-F]{4,6})@@} $lit tm tg]} {
                    append decoded [string range $lit $p [expr {[lindex $tm 0] - 1}]]
                    append decoded [format %c [scan [string range $lit [lindex $tg 0] [lindex $tg 1]] %x]]
                    set p [expr {[lindex $tm 1] + 1}]
                }
                append decoded [string range $lit $p end]
                writefile [file join $dir $file] $decoded
                incr n
            }
            FONTS {
                set i 0
                foreach {all rel blob} [regexp -all -inline {\n  (fonts/web/[^ ]+) \{\n([^\}]*)\n\}} $body] {
                    set target [file join $dir skin $rel]
                    file mkdir [file dirname $target]
                    set fh [open $target wb]
                    puts -nonewline $fh [binary decode base64 [string map [list "\n" {}] $blob]]
                    close $fh
                    incr n
                }
            }
        }
        set pos [expr {$e + 1}]
    }
    puts "pack-almanac: unpacked $n files under $dir"
}

# ---------- main ----------

set mode build
set arg {}
if {[llength $argv] >= 1} {
    switch -- [lindex $argv 0] {
        --check  { set mode check }
        --unpack { set mode unpack; set arg [lindex $argv 1]; if {$arg eq ""} { fail "--unpack needs a directory" } }
        -h - --help { puts [string range [readfile [info script]] 0 1100]; exit 0 }
        default  { fail "unknown argument [lindex $argv 0] (use --check, --unpack DIR, or none)" }
    }
}
set dist [file join $here dist almanac.tcl]

switch -- $mode {
    build {
        set out [build]
        writefile $dist $out
        set bad [selftest $dist]
        puts "pack-almanac: wrote $dist ([string length $out] bytes, [llength [split $out "\n"]] lines)"
        if {$bad > 0} { fail "selftest failed ($bad problem(s))" }
        puts "pack-almanac: selftest ok (emit style/template/fonts and board assets match the sources)"
    }
    check {
        set out [build]
        if {![file exists $dist] || [readfile $dist] ne $out} { puts stderr "pack-almanac: dist/almanac.tcl is out of date; run pack-almanac.tcl"; exit 1 }
        puts "pack-almanac: dist/almanac.tcl is up to date"
    }
    unpack {
        unpack $dist $arg
    }
}
