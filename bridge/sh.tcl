# sh.tcl -- bridge's Tcl userspace.
#
# The shell is Tcl.  This file turns bare Tcl into a comfortable working
# environment: a small coreutils (places, things, text), a set of tools
# for lists and records, and a few ideas borrowed from Plan 9's rc shell.
# It is sourced once per window when the Tcl adapter boots, so it must be
# safe to source again (see "Rules of this file" below).
#
# HOW IT IS ORGANISED (search for the "== N." markers):
#   == 1. core       helpers every command shares, and the help system
#   == 2. places     files and directories: ls cat save rm cp mv walk ...
#   == 3. text       commands on lines of text: grep sed sort uniq ...
#   == 4. values     commands on lists and records: where each reduce ...
#   == 5. fluidity   |>  ~  ^  expand  whatis  alias  scripts-as-commands
#   == 6. topics     the plain-language guides: help pipes, help values ...
#
# THE THREE SHAPES (read "help values" for the long version)
#   text    a string of lines separated by newlines.  No trailing newline.
#   list    a Tcl list.  Names, numbers, anything.  Never re-split.
#   rows    a list of dicts (a "table").  A dict is a "record".
# Every command says which shapes it takes and gives.  The input is always
# the FIRST argument, so commands nest the way a pipeline reads inside-out.
#
# RULES OF THIS FILE
#   * Pure Tcl 9.  No JS, no processes, no threads, no clock formatting.
#   * Everything private lives in ::sh.  Every GLOBAL proc is a public
#     command and MUST have a ::sh::doc entry (the tests enforce this).
#   * The adapter evaluates this whole file inside `catch {...}`, so braces
#     must balance as plain text, even inside comments and strings.  Do not
#     write a lone brace anywhere; use \{ and \} if you truly need one.
#   * Re-sourcing must not fail: guard every rename.
#   * Errors read "command: what went wrong" (first line), then Tcl's own
#     trace.  Use ::sh::fail so the wording stays uniform.
#   * Flags are single letters (-r, -n).  `--` ends flags.  A flag can be
#     combined: -la means -l -a.  Flags come AFTER the input.
#
# TO ADD A COMMAND: write the proc, then ::sh::doc right below it, then a
# test in test-shell-memfs.js.  `help` and `apropos` pick it up by themselves.

# ---------------------------------------------------------------- == 1. core

namespace eval ::sh {
    variable docs {}            ;# command -> dict(group summary synopsis text example)
    variable cmds {}            ;# public commands, in the order they were documented
    variable topics {}          ;# topic -> dict(summary text)
    variable torder {}          ;# topics, in order
    variable grp Other          ;# group that new docs are filed under
    variable root /home/shell   ;# the shell's "/"
    variable bin /home/shell/bin ;# scripts here run as commands
}

# ::sh::fail cmd msg -- make the CALLER of the calling proc raise "cmd: msg".
# (-level 2: the proc that called us is the one that fails.)
proc ::sh::fail {cmd msg} {
    return -level 2 -code error "$cmd: $msg"
}

# ::sh::v list -- the list, one element per line.  Still a perfectly good
# Tcl list (newline is a list separator), but it reads well at the prompt.
proc ::sh::v {list} {
    join [lmap x $list {list $x}] "\n"
}

# ::sh::vd dict -- a dict, one "key value" pair per line.  Still a dict.
proc ::sh::vd {dict} {
    join [lmap {k val} $dict {list $k $val}] "\n"
}

# ::sh::tl text -- text to a list of lines.  Lines never contain newlines,
# so this split is lossless.  Empty text has no lines.
proc ::sh::tl {text} {
    if {$text eq ""} { return {} }
    split $text "\n"
}

# ::sh::tj list -- a list of lines back to text.
proc ::sh::tj {list} {
    join $list "\n"
}

# ::sh::flags cmd argv bools ?vals? -- peel single-letter flags off argv.
# bools: letters that are on/off.  vals: letters that take the next word.
# Returns {optsdict rest}.  A word is a flag only if it is - and letters,
# so -5 and "-" are ordinary words.  "--" ends the flags.
proc ::sh::flags {cmd argv bools {vals {}}} {
    set opts [dict create]
    set rest {}
    set n [llength $argv]
    for {set i 0} {$i < $n} {incr i} {
        set a [lindex $argv $i]
        if {$a eq "--"} {
            lappend rest {*}[lrange $argv [expr {$i + 1}] end]
            break
        }
        if {![regexp {^-[A-Za-z]+$} $a]} {
            lappend rest $a
            continue
        }
        foreach c [split [string range $a 1 end] ""] {
            if {$c in $bools} {
                dict set opts $c 1
            } elseif {$c in $vals} {
                incr i
                if {$i >= $n} { ::sh::fail $cmd "-$c needs a value" }
                dict set opts $c [lindex $argv $i]
            } else {
                ::sh::fail $cmd "unknown flag -$c (see: help $cmd)"
            }
        }
    }
    return [list $opts $rest]
}

# ::sh::num cmd what value -- value as a number, or a clear error.
proc ::sh::num {cmd value} {
    if {![string is double -strict $value]} {
        ::sh::fail $cmd "\"$value\" is not a number"
    }
    return $value
}

# ::sh::count cmd value -- a whole number >= 0, or a clear error.
proc ::sh::count {cmd value} {
    if {![string is integer -strict $value] || $value < 0} {
        ::sh::fail $cmd "\"$value\" is not a count (a whole number, 0 or more)"
    }
    return $value
}

# ::sh::regex cmd re ?nocase? -- check a regular expression early so the
# error names the command, not Tcl's internals.
proc ::sh::regex {cmd re {nocase 0}} {
    if {[catch {regexp -- $re ""} msg]} {
        ::sh::fail $cmd "bad pattern \"$re\": $msg"
    }
    if {$nocase} { return "(?i)$re" }
    return $re
}

# ::sh::dedent text -- strip blank edge lines and the common left margin.
proc ::sh::dedent {text} {
    set lines [split $text "\n"]
    while {[llength $lines] && [string trim [lindex $lines 0]] eq ""} {
        set lines [lrange $lines 1 end]
    }
    while {[llength $lines] && [string trim [lindex $lines end]] eq ""} {
        set lines [lrange $lines 0 end-1]
    }
    set m 1000
    foreach l $lines {
        if {[string trim $l] eq ""} continue
        set k [expr {[string length $l] - [string length [string trimleft $l " "]]}]
        if {$k < $m} { set m $k }
    }
    if {$m == 1000} { set m 0 }
    join [lmap l $lines {string range $l $m end}] "\n"
}

# ::sh::fill text width -- re-flow ONE paragraph (words) to the width.
proc ::sh::fill {text width} {
    set out {}
    set line ""
    foreach w [regexp -all -inline {\S+} $text] {
        if {$line eq ""} {
            set line $w
        } elseif {[string length $line] + 1 + [string length $w] <= $width} {
            append line " " $w
        } else {
            lappend out $line
            set line $w
        }
    }
    if {$line ne ""} { lappend out $line }
    join $out "\n"
}

# ::sh::render text indent -- help-page body.  Plain lines are paragraphs
# and get re-flowed; lines that are indented, or that start with a flag such
# as "-n  text", are shown exactly as is.
proc ::sh::render {text indent} {
    set out {}
    set para {}
    set pad [string repeat " " $indent]
    set width [expr {74 - $indent}]
    foreach line [split [::sh::dedent $text] "\n"] {
        if {[string trim $line] eq ""} {
            if {[llength $para]} {
                lappend out [::sh::fill [join $para " "] $width]
                set para {}
            }
            lappend out ""
        } elseif {[string index $line 0] eq " " || [regexp {^-[A-Za-z]\s} $line]} {
            if {[llength $para]} {
                lappend out [::sh::fill [join $para " "] $width]
                set para {}
            }
            lappend out $line
        } else {
            lappend para $line
        }
    }
    if {[llength $para]} { lappend out [::sh::fill [join $para " "] $width] }
    set res {}
    foreach block $out {
        if {$block eq ""} { lappend res ""; continue }
        foreach l [split $block "\n"] {
            lappend res [expr {$l eq "" ? "" : "$pad$l"}]
        }
    }
    join $res "\n"
}

# ::sh::pre text indent -- synopsis and example blocks: shown exactly as written.
proc ::sh::pre {text indent} {
    set pad [string repeat " " $indent]
    join [lmap l [split [::sh::dedent $text] "\n"] {expr {$l eq "" ? "" : "$pad$l"}}] "\n"
}

# ::sh::group name -- file the following docs under this heading in `help`.
proc ::sh::group {name} {
    set ::sh::grp $name
}

# ::sh::doc cmd summary synopsis description example -- register a manual page.
proc ::sh::doc {cmd summary synopsis text example} {
    variable docs
    variable cmds
    dict set docs $cmd [dict create group $::sh::grp summary $summary \
        synopsis [::sh::dedent $synopsis] text $text example [::sh::dedent $example]]
    if {$cmd ni $cmds} { lappend cmds $cmd }
}

# ::sh::topic name summary text -- register a concept guide.
proc ::sh::topic {name summary text} {
    variable topics
    variable torder
    dict set topics $name [dict create summary $summary text $text]
    if {$name ni $torder} { lappend torder $name }
}

# help ?name? -- the front door.
proc help {{name ""}} {
    if {$name eq ""} { return [::sh::helpindex] }
    if {[dict exists $::sh::docs $name]} {
        set d [dict get $::sh::docs $name]
        set out "NAME\n    $name - [dict get $d summary]\n\nSYNOPSIS\n"
        append out [::sh::pre [dict get $d synopsis] 4]
        append out "\n\nDESCRIPTION\n" [::sh::render [dict get $d text] 4]
        append out "\n\nEXAMPLE\n" [::sh::pre [dict get $d example] 4]
        return $out
    }
    if {[dict exists $::sh::topics $name]} {
        set t [dict get $::sh::topics $name]
        return "[string toupper $name] - [dict get $t summary]\n\n[::sh::render [dict get $t text] 2]"
    }
    if {[llength [info commands $name]]} {
        return -code error "help: \"$name\" is a plain Tcl built-in, not part of the\
            userspace. Type it alone to see its usage, or read: help tcl"
    }
    return -code error "help: no help for \"$name\" (try: help, or: apropos $name)"
}

proc ::sh::helpindex {} {
    set out "bridge shell -- everything is Tcl, nothing here assumes Unix experience.\n\n"
    append out "  help start        new here? begin with this\n"
    append out "  help <command>    the manual page for one command, with an example\n"
    append out "  help <topic>      a plain guide to one idea (topics are listed below)\n"
    append out "  apropos <word>    find commands by what they do\n"
    set last ""
    foreach c $::sh::cmds {
        set d [dict get $::sh::docs $c]
        set g [dict get $d group]
        if {$g ne $last} {
            append out "\n[string toupper $g]\n"
            set last $g
        }
        append out [format "  %-12s %s\n" $c [dict get $d summary]]
    }
    append out "\nTOPICS (read these like short chapters)\n"
    foreach t $::sh::torder {
        append out [format "  %-12s %s\n" $t [dict get $::sh::topics $t summary]]
    }
    append out "\nUnderneath it all is plain Tcl 9.1 with tcllib: the commands above\n"
    append out "are ordinary Tcl procs, and `whatis <command>` shows how any of them\n"
    append out "is written. 'exit' is trapped; the interpreter stays up."
    return $out
}

::sh::group "Learning the shell"
::sh::doc help {the manual: commands and guides} {
    help
    help command
    help topic
} {
    With no word, lists every command (grouped by what it works on) and every
    guide topic, each with a one-line summary.

    With the name of a command, prints its manual page: NAME, SYNOPSIS (the
    shape of the call: ?x? means x is optional, x... means one or more),
    DESCRIPTION and EXAMPLE.

    With a topic name, prints a plain-language guide to one idea, written for
    someone who has never used a command line. Start with: help start
} {
    help
    help ls
    help pipes
}

proc apropos {word} {
    set hits {}
    foreach c $::sh::cmds {
        set d [dict get $::sh::docs $c]
        if {[string match -nocase "*$word*" $c] ||
            [string match -nocase "*$word*" [dict get $d summary]]} {
            lappend hits [format "%-12s %s" $c [dict get $d summary]]
        }
    }
    foreach t $::sh::torder {
        set s [dict get $::sh::topics $t summary]
        if {[string match -nocase "*$word*" $t] || [string match -nocase "*$word*" $s]} {
            lappend hits [format "%-12s %s  (topic: help %s)" $t $s $t]
        }
    }
    if {![llength $hits]} { return "nothing found for \"$word\" (try: help)" }
    join $hits "\n"
}
::sh::doc apropos {find commands by what they do} {
    apropos word
} {
    Searches the names and one-line summaries of every command and topic for
    the word (ignoring capitals) and lists what it finds. Use it when you
    know what you want to do but not what the command is called.

    If nothing matches it says so; it is not an error.
} {
    apropos sort
    apropos file
}

# -------------------------------------------------------------- == 2. places
# Places (directories) and things (files).  Commands that read files take
# names -- or wildcard patterns -- and expand patterns themselves, because
# there is no outer shell to do it for them.  Names that produce names
# (ls, walk, expand) return lists; text comes back as text.

# ::sh::real path -- the true VFS path behind a name you typed.  The shell
# shows "/" for /home/shell, so "/docs" means /home/shell/docs.  If nothing
# exists there but the plain path does (/usr/lib), the plain path wins.
proc ::sh::real {p} {
    if {[string index $p 0] ne "/"} { return $p }
    set j [file join $::sh::root [string trimleft $p "/"]]
    if {[file exists $j] || ![file exists $p]} { return $j }
    return $p
}

# ::sh::oserr cmd path err opts -- turn a Tcl file error into our wording.
proc ::sh::oserr {cmd path err opts} {
    set code [dict get $opts -errorcode]
    if {[lindex $code 0] eq "POSIX"} { set err [lindex $code 2] }
    ::sh::fail $cmd "$path: $err"
}

# ::sh::children real all -- full paths inside a place, sorted; hidden
# (dot) names only when all is true.  Never includes . or .. .
proc ::sh::children {real all} {
    set l [glob -nocomplain -directory $real -- *]
    if {$all} { lappend l {*}[glob -nocomplain -directory $real -- .*] }
    lsort -dictionary [lmap p $l {
        if {[file tail $p] in {. ..}} continue
        set p
    }]
}

# ::sh::names cmd arg... -- expand wildcards to a plain list.  A pattern
# that matches nothing stays as written, so the next error names it.
proc ::sh::names {cmd args} {
    set out {}
    foreach a $args {
        if {![regexp {[*?\[\{]} $a] || [file exists [::sh::real $a]]} {
            lappend out $a
            continue
        }
        set hits {}
        set m [::sh::real $a]
        foreach p [glob -nocomplain -- $m] {
            lappend hits [expr {$m ne $a ? [string range $p [string length $::sh::root] end] : $p}]
        }
        if {![llength $hits]} { set hits [list $a] }
        lappend out {*}[lsort -dictionary $hits]
    }
    return $out
}

proc expand {args} {
    ::sh::v [::sh::names expand {*}$args]
}
::sh::group "Places and things"
::sh::doc expand {turn wildcard patterns into names} {
    expand pattern...
} {
    Turns each pattern into the list of names that match it. Inside a
    pattern, * matches any run of letters, ? matches exactly one letter,
    [abc] matches one letter out of a set, and [a-c] one out of a range.
    Names starting with a dot are hidden and are not matched by * or ?.

    A pattern that matches nothing is returned unchanged, exactly as you typed
    it, so you can see what failed. (Tcl's own glob returns an empty list
    instead.) A name that really exists, even one containing a star, is kept
    as it is.

    Every command that reads files already calls expand for you, so
    "cat *.txt" works. See: help wildcards
} {
    expand *.txt
    expand /docs/report-?.md
    foreach f [expand *.log] { echo $f }
}

# ::sh::entries cmd paths all -- rows (name path type size mtime) for ls/files.
proc ::sh::entries {cmd paths all} {
    set many [expr {[llength $paths] > 1}]
    set rows {}
    foreach p $paths {
        set r [::sh::real $p]
        if {![file exists $r]} { ::sh::fail $cmd "$p: no such file or directory" }
        if {[file isdirectory $r]} {
            foreach c [::sh::children $r $all] {
                set t [file tail $c]
                set path [expr {$p eq "." ? $t : "[string trimright $p /]/$t"}]
                lappend rows [::sh::row [expr {$many ? $path : $t}] $path $c]
            }
        } else {
            lappend rows [::sh::row $p $p $r]
        }
    }
    return $rows
}

proc ::sh::row {name path real} {
    if {[file isdirectory $real]} {
        dict create name $name path $path type place size - mtime [file mtime $real]
    } else {
        dict create name $name path $path type thing size [file size $real] mtime [file mtime $real]
    }
}

# ls ?-l? ?-a? ?path...? -- names; places end in /.
proc ls {args} {
    lassign [::sh::flags ls $args {l a}] o paths
    if {![llength $paths]} { set paths . }
    set rows [::sh::entries ls [::sh::names ls {*}$paths] [dict exists $o a]]
    if {[dict exists $o l]} {
        set out {}
        foreach r $rows {
            dict with r {
                if {$type eq "place"} { append name / }
                lappend out [dict create type $type size $size modified [::sh::stamp $mtime] name $name]
            }
        }
        return [table $out]
    }
    ::sh::v [lmap r $rows {
        set n [dict get $r name]
        expr {[dict get $r type] eq "place" ? "$n/" : $n}
    }]
}
::sh::doc ls {list the names in a place} {
    ls ?-l? ?-a? ?path...?
} {
    Lists what is inside a place (a directory). With no path it lists the
    place you are in. Places are shown with a / on the end so you can tell
    them from things (files).

    A path may be a pattern: ls *.txt. If you give a path to a thing rather
    than a place, ls just shows that name. With several paths, each name is
    shown with its place in front so the groups are not confused.

    The result is a Tcl list, one name per line, so it can feed other
    commands: foreach f [ls] ... or sort [ls].

    -a  also show hidden names (those starting with a dot).
    -l  show a table instead: type (place or thing), size in bytes, the time
        it was last changed (UTC), and the name. This is for reading, not for
        feeding to other commands; use files for that.
} {
    ls
    ls -a /docs
    ls *.tcl
    ls -l
}

proc ll {args} { ls -l {*}$args }
::sh::doc ll {long listing: type, size, date, name} {
    ll ?-a? ?path...?
} {
    The same as ls -l. Shows each name with its type (place or thing), its
    size in bytes and when it was last changed.
} {
    ll
    ll /docs
}

proc files {args} {
    lassign [::sh::flags files $args {a}] o paths
    if {![llength $paths]} { set paths . }
    ::sh::v [::sh::entries files [::sh::names files {*}$paths] [dict exists $o a]]
}
::sh::doc files {list a place as rows you can filter} {
    files ?-a? ?path...?
} {
    Like ls, but each name comes with its details, as a row (a record): name,
    path, type (place or thing), size in bytes, and mtime (seconds since
    1970 when it last changed). The result is rows, so the table tools work
    on it directly.
} {
    files
    where [files] {$size > 1000}
    pluck [where [files] {$type eq "place"}] name
    table [sort-by [files] size -r -n] name size
}

proc ::sh::slurp {cmd f} {
    set r [::sh::real $f]
    if {![file exists $r]} { ::sh::fail $cmd "$f: no such file or directory" }
    if {[file isdirectory $r]} { ::sh::fail $cmd "$f: is a place, not a thing (try: ls $f)" }
    if {[catch {
        set fh [open $r r]
        set data [read $fh]
        close $fh
    } err opts]} { ::sh::oserr $cmd $f $err $opts }
    if {[string first "\x00" $data] >= 0} {
        ::sh::fail $cmd "$f: looks like binary data (try: xd $f)"
    }
    if {[string index $data end] eq "\n"} { set data [string range $data 0 end-1] }
    return $data
}

proc cat {args} {
    lassign [::sh::flags cat $args {}] o files
    if {![llength $files]} { ::sh::fail cat "missing file" }
    ::sh::tj [lmap f [::sh::names cat {*}$files] { ::sh::slurp cat $f }]
}
::sh::doc cat {read things (files) as text} {
    cat file...
} {
    Reads each file and returns the lines as text. With several files the
    text of one follows the text of the next. File names may be patterns.

    The one newline that ends a file is not part of the text; text in this
    shell has no trailing newline (see: help values).

    Binary files are refused with a hint to use xd, because their raw bytes
    would scramble the screen. An empty file gives empty text.
} {
    cat notes.txt
    cat part1.txt part2.txt
    grep [cat /var/log.txt] error
    save [cat a.txt b.txt] both.txt
}

proc save {text args} {
    lassign [::sh::flags save $args {a}] o rest
    if {[llength $rest] != 1} { ::sh::fail save "needs text and one file name (save text file)" }
    set f [lindex $rest 0]
    set r [::sh::real $f]
    if {[file isdirectory $r]} { ::sh::fail save "$f: is a place, not a thing" }
    if {[catch {
        set fh [open $r [expr {[dict exists $o a] ? "a" : "w"}]]
        if {$text ne ""} { puts $fh $text }
        close $fh
    } err opts]} { ::sh::oserr save $f $err $opts }
    return
}
::sh::doc save {write text into a file} {
    save text file
    save text file -a
} {
    Writes the text into the file, replacing what was there, and creates the
    file if needed. A final newline is added so the file ends properly; empty
    text makes an empty file. The place the file lives in must already exist.

    -a  add to the end of the file instead of replacing it.

    This is what "redirection" is in other shells: send a result to a file
    instead of the screen. See: help redirection
} {
    save "first line" notes.txt
    save "second line" notes.txt -a
    save [ls] listing.txt
    save [sort [cat names.txt] -u] names.txt
}

proc tee {text args} {
    lassign [::sh::flags tee $args {a}] o files
    foreach f $files {
        if {[dict exists $o a]} { save $text $f -a } else { save $text $f }
    }
    return $text
}
::sh::doc tee {save text to files and pass it on} {
    tee text file... ?-a?
} {
    Saves the text into every file named, then returns the same text, so you
    can keep working with it. Use it to keep a copy of the middle of a chain
    of commands.
} {
    set r [sort [tee [grep [cat log.txt] error] errors.txt]]
}

proc mkdir {args} {
    lassign [::sh::flags mkdir $args {p}] o dirs
    if {![llength $dirs]} { ::sh::fail mkdir "missing dir" }
    foreach d $dirs {
        set r [::sh::real $d]
        if {[file exists $r] && ![file isdirectory $r]} {
            ::sh::fail mkdir "$d: exists and is a thing, not a place"
        }
        if {[catch {file mkdir $r} err opts]} { ::sh::oserr mkdir $d $err $opts }
    }
    return
}
::sh::doc mkdir {make places (directories)} {
    mkdir dir...
} {
    Makes each place. Missing places on the way are made too, so
    "mkdir a/b/c" works even if a does not exist yet. Making a place that is
    already there is fine. (The flag -p, which other systems need for this,
    is accepted and ignored.)
} {
    mkdir projects
    mkdir /docs/2026/notes
}

proc touch {args} {
    if {![llength $args]} { ::sh::fail touch "missing name" }
    foreach f [::sh::names touch {*}$args] {
        set r [::sh::real $f]
        if {[file exists $r]} {
            file mtime $r [clock seconds]
        } elseif {[catch {close [open $r w]} err opts]} {
            ::sh::oserr touch $f $err $opts
        }
    }
    return
}
::sh::doc touch {make an empty thing, or mark one as just changed} {
    touch name...
} {
    If a thing with that name exists, its change time becomes now. Otherwise
    an empty thing is created.
} {
    touch todo.txt
}

# Paths the shell refuses to delete: it cannot work without them.
proc ::sh::protected {r} {
    set n [file normalize $r]
    expr {$n in {/ /home /home/shell /usr} || [string match /usr/* $n]}
}

proc rm {args} {
    lassign [::sh::flags rm $args {r f}] o paths
    if {![llength $paths]} { ::sh::fail rm "missing path" }
    foreach p [::sh::names rm {*}$paths] {
        set r [::sh::real $p]
        if {![file exists $r]} {
            if {[dict exists $o f]} continue
            ::sh::fail rm "$p: no such file or directory"
        }
        if {[::sh::protected $r]} { ::sh::fail rm "$p: the shell needs this; refusing" }
        if {[file isdirectory $r] && ![dict exists $o r] && [llength [::sh::children $r 1]]} {
            ::sh::fail rm "$p: place is not empty (use rm -r to remove it and everything in it)"
        }
        if {[catch {file delete -force -- $r} err opts]} { ::sh::oserr rm $p $err $opts }
    }
    return
}
::sh::doc rm {remove things and places} {
    rm ?-r? ?-f? path...
} {
    Removes things (files). An empty place is removed too; a place with
    something inside needs -r, which removes it and everything in it. There
    is no wastebasket: removal is for good.

    -r  remove a place and everything inside it.
    -f  do not complain about names that do not exist.

    Patterns work (rm *.tmp). The shell refuses to remove / , /home, its own
    root and /usr, because it cannot work without them.
} {
    rm old.txt
    rm *.tmp
    rm -r scratch
}

proc ::sh::into {cmd verb args} {
    lassign [::sh::flags $cmd $args {r f n}] o rest
    if {[llength $rest] < 2} { ::sh::fail $cmd "needs a source and a destination" }
    set dst [lindex $rest end]
    set srcs [::sh::names $cmd {*}[lrange $rest 0 end-1]]
    set rd [::sh::real $dst]
    if {[file isdirectory $rd]} {
        set pairs [lmap s $srcs {list $s [file join $rd [file tail $s]]}]
    } elseif {[llength $srcs] > 1} {
        ::sh::fail $cmd "$dst: not a place (several sources need a place to go into)"
    } else {
        set pairs [list [list [lindex $srcs 0] $rd]]
    }
    foreach pr $pairs {
        lassign $pr s d
        set rs [::sh::real $s]
        if {![file exists $rs]} { ::sh::fail $cmd "$s: no such file or directory" }
        if {[dict exists $o n] && [file exists $d]} continue
        if {[catch {file $verb -force -- $rs $d} err opts]} { ::sh::oserr $cmd $s $err $opts }
    }
    return
}

proc cp {args} { ::sh::into cp copy {*}$args }
::sh::doc cp {copy things and places} {
    cp ?-n? source... destination
} {
    Copies the source to the destination. If the destination is a place, the
    copies go inside it with their own names; otherwise the destination is
    the new name (one source only). A place is copied with everything in it,
    so no -r is needed (it is accepted and ignored). An existing destination
    is replaced.

    -n  never replace: skip any copy whose destination already exists.
} {
    cp a.txt b.txt
    cp *.txt /backup
}

proc mv {args} { ::sh::into mv rename {*}$args }
::sh::doc mv {move or rename things and places} {
    mv ?-n? source... destination
} {
    Moves the source to the destination. If the destination is a place, the
    source goes inside it; otherwise the source takes the new name. An
    existing destination is replaced.

    -n  never replace: skip any move whose destination already exists.
} {
    mv draft.txt final.txt
    mv *.log /archive
}

# cd: Tcl's cd, but bare cd means the shell's root, "/x" means inside it,
# and "cd -" returns to where you were.
if {![llength [info commands ::sh::tcl_cd]]} { rename cd ::sh::tcl_cd }
set ::sh::oldpwd $::sh::root
proc cd {{dir /}} {
    set here [pwd]
    if {$dir eq "-"} { set dir $::sh::oldpwd }
    set r [::sh::real $dir]
    if {[catch {::sh::tcl_cd $r} err opts]} { ::sh::oserr cd $dir $err $opts }
    set ::sh::oldpwd $here
    return
}
::sh::doc cd {go to another place} {
    cd ?place?
} {
    Makes another place the one you are in. With no place, goes to the top
    of the shell (shown as /). "cd -" goes back to where you just were; "cd .."
    goes up one level. A name starting with / is counted from the top of the
    shell, so the prompt's /docs can be typed as /docs.

    Other parts of the file system, such as /usr/lib, are reachable too: if a
    name does not exist inside the shell's top, the plain system path is used.
} {
    cd /docs
    cd ..
    cd -
    cd
}

proc exists {path} { file exists [::sh::real $path] }
::sh::doc exists {is there anything with this name?} {
    exists path
} {
    Returns 1 if a thing or place with that name exists, else 0. For use in
    if.
} {
    if {[exists notes.txt]} { echo yes }
}

proc isdir {path} { file isdirectory [::sh::real $path] }
::sh::doc isdir {is this name a place?} {
    isdir path
} {
    Returns 1 if the name is a place (directory), else 0.
} {
    if {[isdir /docs]} { ls /docs }
}

proc isfile {path} { file isfile [::sh::real $path] }
::sh::doc isfile {is this name a thing?} {
    isfile path
} {
    Returns 1 if the name is a thing (a regular file), else 0.
} {
    if {[isfile a.txt]} { cat a.txt }
}

proc basename {name {suffix ""}} {
    set t [file tail $name]
    if {$suffix ne "" && $t ne $suffix && [string match *$suffix $t]} {
        set t [string range $t 0 end-[string length $suffix]]
    }
    return $t
}
::sh::doc basename {the last part of a path} {
    basename path ?suffix?
} {
    Returns the last part of a path, the name itself without the places
    before it. If a suffix is given and the name ends with it, the suffix is
    cut off.
} {
    basename /docs/report.txt
    basename /docs/report.txt .txt
}

proc dirname {name} { file dirname $name }
::sh::doc dirname {all but the last part of a path} {
    dirname path
} {
    Returns the place a path lives in: everything before the last name.
    A bare name lives in "." (here).
} {
    dirname /docs/report.txt
}

proc cleanname {name} {
    set abs [expr {[string index $name 0] eq "/"}]
    set out {}
    foreach seg [split $name /] {
        if {$seg eq "" || $seg eq "."} continue
        if {$seg eq ".."} {
            if {[llength $out] && [lindex $out end] ne ".."} {
                set out [lrange $out 0 end-1]
            } elseif {!$abs} {
                lappend out ..
            }
            continue
        }
        lappend out $seg
    }
    set r [join $out /]
    if {$abs} { return /$r }
    expr {$r eq "" ? "." : $r}
}
::sh::doc cleanname {tidy a path without looking at the disk} {
    cleanname path
} {
    Rewrites a path to its shortest equivalent form by pure text rules:
    doubled slashes and "." are dropped and "x/.." cancels out. It does not
    check that anything exists. (This is Plan 9's cleanname.)
} {
    cleanname /a/b/../c//d/.
}

# walk ?-f? ?-d? ?-a? ?path...? -- every name below, depth first.
proc ::sh::walkin {typed real all}  {
    set out {}
    foreach c [::sh::children $real $all] {
        set t [file tail $c]
        set n [expr {$typed eq "" ? $t : "[string trimright $typed /]/$t"}]
        if {[file isdirectory $c]} {
            lappend out $n/
            lappend out {*}[::sh::walkin $n $c $all]
        } else {
            lappend out $n
        }
    }
    return $out
}
proc walk {args} {
    lassign [::sh::flags walk $args {f d a}] o paths
    set all [dict exists $o a]
    set out {}
    if {![llength $paths]} {
        set out [::sh::walkin "" . $all]
    } else {
        foreach p [::sh::names walk {*}$paths] {
            set r [::sh::real $p]
            if {![file exists $r]} { ::sh::fail walk "$p: no such file or directory" }
            if {[file isdirectory $r]} {
                lappend out {*}[::sh::walkin $p $r $all]
            } else {
                lappend out $p
            }
        }
    }
    if {[dict exists $o f] && ![dict exists $o d]} {
        set out [lmap n $out {expr {[string index $n end] eq "/" ? [continue] : $n}}]
    } elseif {[dict exists $o d] && ![dict exists $o f]} {
        set out [lmap n $out {expr {[string index $n end] eq "/" ? $n : [continue]}}]
    }
    ::sh::v $out
}
::sh::doc walk {every name below a place, all levels down} {
    walk ?-f? ?-d? ?-a? ?path...?
} {
    Lists everything inside the places given (the place you are in, if none),
    all the way down, as a list of names. Each name includes the places on
    the way: a/b/c.txt. Places end in /. A place is listed just before its
    contents. If a path is a thing rather than a place, it is listed itself.

    Because the result is a plain list of names, it feeds any command that
    takes names: hash [walk -f], search [walk -f] TODO.

    -f  only things (files).
    -d  only places.
    -a  include hidden names (starting with a dot).
} {
    walk
    walk -f /docs
    hash [walk -f] sha1
}

proc du {args} {
    lassign [::sh::flags du $args {s}] o paths
    if {![llength $paths]} { set paths . }
    set out {}
    foreach p [::sh::names du {*}$paths] {
        set r [::sh::real $p]
        if {![file exists $r]} { ::sh::fail du "$p: no such file or directory" }
        lappend out {*}[::sh::du1 $p $r [dict exists $o s]]
    }
    ::sh::tj $out
}
# returns lines "bytes name", total of this place last... (sub-places first)
proc ::sh::du1 {typed real summary} {
    if {![file isdirectory $real]} { return [list "[file size $real] $typed"] }
    set total 0
    set lines {}
    foreach c [::sh::children $real 1] {
        set t "[string trimright $typed /]/[file tail $c]"
        if {[file isdirectory $c]} {
            set sub [::sh::du1 $t $c $summary]
            lassign [lindex $sub end] n
            incr total $n
            if {!$summary} { lappend lines {*}$sub }
        } else {
            incr total [file size $c]
        }
    }
    lappend lines "$total $typed"
    return $lines
}
::sh::doc du {how many bytes a place holds} {
    du ?-s? ?path...?
} {
    For each place under the path (the place you are in, if none), prints a
    line "bytes name": the total size of everything inside it, deepest places
    first and the path itself last. For a thing, prints its size.

    -s  print only the one total line for each path given.
} {
    du
    du -s /docs
}

# ---------------------------------------------------------------- time, hash

# ::sh::stamp secs -- "YYYY-MM-DD HH:MM:SS" (UTC).  Tcl's clock format does
# not work in this build, so the calendar arithmetic is done by hand.
proc ::sh::stamp {secs} {
    set days [expr {$secs / 86400}]
    set rem [expr {$secs % 86400}]
    set z [expr {$days + 719468}]
    set era [expr {$z / 146097}]
    set doe [expr {$z - $era * 146097}]
    set yoe [expr {($doe - $doe / 1460 + $doe / 36524 - $doe / 146096) / 365}]
    set y [expr {$yoe + $era * 400}]
    set doy [expr {$doe - (365 * $yoe + $yoe / 4 - $yoe / 100)}]
    set mp [expr {(5 * $doy + 2) / 153}]
    set d [expr {$doy - (153 * $mp + 2) / 5 + 1}]
    set m [expr {$mp < 10 ? $mp + 3 : $mp - 9}]
    if {$m <= 2} { incr y }
    format "%04d-%02d-%02d %02d:%02d:%02d" $y $m $d [expr {$rem / 3600}] \
        [expr {$rem % 3600 / 60}] [expr {$rem % 60}]
}

proc date {{secs ""}} {
    if {$secs eq ""} { set secs [clock seconds] }
    ::sh::num date $secs
    ::sh::stamp [expr {int($secs)}]
}
::sh::doc date {the date and time, in UTC} {
    date ?seconds?
} {
    Shows the current date and time as YYYY-MM-DD HH:MM:SS in UTC (world
    time; this build has no time zones). Given a number of seconds since
    1970, shows that moment instead. For the plain number, use Tcl's
    "clock seconds". If the page was opened on a device with a wrong clock,
    the answer is wrong too.
} {
    date
    date 0
    date [lindex [files] 0 end]
}

# ---- digests.  Pure Tcl; slow on large files but exact.  Data is a string of
# bytes (every character 0-255).

proc ::sh::rol {x n} { expr {(($x << $n) | ($x >> (32 - $n))) & 0xFFFFFFFF} }
proc ::sh::ror {x n} { expr {(($x >> $n) | ($x << (32 - $n))) & 0xFFFFFFFF} }

proc ::sh::pad {data bigendian} {
    set len [string length $data]
    append data "\x80"
    append data [string repeat "\x00" [expr {(55 - $len) % 64}]]
    append data [binary format [expr {$bigendian ? "W" : "w"}] [expr {$len * 8}]]
}

proc ::sh::sha1 {data} {
    binary scan [::sh::pad $data 1] Iu* w
    lassign {0x67452301 0xEFCDAB89 0x98BADCFE 0x10325476 0xC3D2E1F0} h0 h1 h2 h3 h4
    for {set o 0} {$o < [llength $w]} {incr o 16} {
        set s [lrange $w $o [expr {$o + 15}]]
        for {set t 16} {$t < 80} {incr t} {
            lappend s [::sh::rol [expr {[lindex $s $t-3] ^ [lindex $s $t-8] ^ [lindex $s $t-14] ^ [lindex $s $t-16]}] 1]
        }
        lassign [list $h0 $h1 $h2 $h3 $h4] a b c d e
        for {set t 0} {$t < 80} {incr t} {
            if {$t < 20} {
                set f [expr {($b & $c) | (~$b & 0xFFFFFFFF & $d)}]; set k 0x5A827999
            } elseif {$t < 40} {
                set f [expr {$b ^ $c ^ $d}]; set k 0x6ED9EBA1
            } elseif {$t < 60} {
                set f [expr {($b & $c) | ($b & $d) | ($c & $d)}]; set k 0x8F1BBCDC
            } else {
                set f [expr {$b ^ $c ^ $d}]; set k 0xCA62C1D6
            }
            set tmp [expr {([::sh::rol $a 5] + $f + $e + $k + [lindex $s $t]) & 0xFFFFFFFF}]
            set e $d; set d $c; set c [::sh::rol $b 30]; set b $a; set a $tmp
        }
        set h0 [expr {($h0 + $a) & 0xFFFFFFFF}]; set h1 [expr {($h1 + $b) & 0xFFFFFFFF}]
        set h2 [expr {($h2 + $c) & 0xFFFFFFFF}]; set h3 [expr {($h3 + $d) & 0xFFFFFFFF}]
        set h4 [expr {($h4 + $e) & 0xFFFFFFFF}]
    }
    format %08x%08x%08x%08x%08x $h0 $h1 $h2 $h3 $h4
}

proc ::sh::md5 {data} {
    variable md5k
    if {![info exists md5k]} {
        for {set i 0} {$i < 64} {incr i} { lappend md5k [expr {int(abs(sin($i + 1)) * 4294967296)}] }
    }
    set sh {7 12 17 22 5 9 14 20 4 11 16 23 6 10 15 21}
    binary scan [::sh::pad $data 0] iu* w
    lassign {0x67452301 0xEFCDAB89 0x98BADCFE 0x10325476} a0 b0 c0 d0
    for {set o 0} {$o < [llength $w]} {incr o 16} {
        set m [lrange $w $o [expr {$o + 15}]]
        lassign [list $a0 $b0 $c0 $d0] a b c d
        for {set i 0} {$i < 64} {incr i} {
            if {$i < 16} {
                set f [expr {($b & $c) | (~$b & 0xFFFFFFFF & $d)}]; set g $i
            } elseif {$i < 32} {
                set f [expr {($d & $b) | (~$d & 0xFFFFFFFF & $c)}]; set g [expr {(5 * $i + 1) % 16}]
            } elseif {$i < 48} {
                set f [expr {$b ^ $c ^ $d}]; set g [expr {(3 * $i + 5) % 16}]
            } else {
                set f [expr {$c ^ ($b | (~$d & 0xFFFFFFFF))}]; set g [expr {(7 * $i) % 16}]
            }
            set f [expr {($f + $a + [lindex $md5k $i] + [lindex $m $g]) & 0xFFFFFFFF}]
            set a $d; set d $c; set c $b
            set b [expr {($b + [::sh::rol $f [lindex $sh [expr {($i / 16) * 4 + $i % 4}]]]) & 0xFFFFFFFF}]
        }
        set a0 [expr {($a0 + $a) & 0xFFFFFFFF}]; set b0 [expr {($b0 + $b) & 0xFFFFFFFF}]
        set c0 [expr {($c0 + $c) & 0xFFFFFFFF}]; set d0 [expr {($d0 + $d) & 0xFFFFFFFF}]
    }
    # little-endian output
    binary encode hex [binary format iu4 [list $a0 $b0 $c0 $d0]]
}

proc ::sh::sha256 {data} {
    variable s256k
    variable s256h
    if {![info exists s256k]} {
        # first 64 primes; constants are the fractional bits of their cube
        # (k) and, for the first 8, square (h) roots -- computed exactly.
        set primes {}
        for {set n 2} {[llength $primes] < 64} {incr n} {
            set ok 1
            foreach p $primes { if {$p * $p > $n} break; if {$n % $p == 0} { set ok 0; break } }
            if {$ok} { lappend primes $n }
        }
        foreach p $primes {
            set x [expr {$p * (1 << 96)}]
            set r [expr {int(exp(log($x) / 3))}]
            while {$r * $r * $r > $x} { incr r -1 }
            while {($r + 1) * ($r + 1) * ($r + 1) <= $x} { incr r }
            lappend s256k [expr {$r & 0xFFFFFFFF}]
        }
        foreach p [lrange $primes 0 7] {
            lappend s256h [expr {[expr {isqrt($p * (1 << 64))}] & 0xFFFFFFFF}]
        }
    }
    binary scan [::sh::pad $data 1] Iu* w
    set h $s256h
    for {set o 0} {$o < [llength $w]} {incr o 16} {
        set s [lrange $w $o [expr {$o + 15}]]
        for {set t 16} {$t < 64} {incr t} {
            set w15 [lindex $s $t-15]
            set w2 [lindex $s $t-2]
            set s0 [expr {[::sh::ror $w15 7] ^ [::sh::ror $w15 18] ^ ($w15 >> 3)}]
            set s1 [expr {[::sh::ror $w2 17] ^ [::sh::ror $w2 19] ^ ($w2 >> 10)}]
            lappend s [expr {([lindex $s $t-16] + $s0 + [lindex $s $t-7] + $s1) & 0xFFFFFFFF}]
        }
        lassign $h a b c d e f g hh
        for {set t 0} {$t < 64} {incr t} {
            set S1 [expr {[::sh::ror $e 6] ^ [::sh::ror $e 11] ^ [::sh::ror $e 25]}]
            set ch [expr {($e & $f) ^ (~$e & 0xFFFFFFFF & $g)}]
            set t1 [expr {($hh + $S1 + $ch + [lindex $s256k $t] + [lindex $s $t]) & 0xFFFFFFFF}]
            set S0 [expr {[::sh::ror $a 2] ^ [::sh::ror $a 13] ^ [::sh::ror $a 22]}]
            set mj [expr {($a & $b) ^ ($a & $c) ^ ($b & $c)}]
            set t2 [expr {($S0 + $mj) & 0xFFFFFFFF}]
            set hh $g; set g $f; set f $e
            set e [expr {($d + $t1) & 0xFFFFFFFF}]
            set d $c; set c $b; set b $a
            set a [expr {($t1 + $t2) & 0xFFFFFFFF}]
        }
        set h [lmap x $h y [list $a $b $c $d $e $f $g $hh] {expr {($x + $y) & 0xFFFFFFFF}}]
    }
    join [lmap x $h {format %08x $x}] ""
}

proc ::sh::digest {cmd alg data} {
    switch -- $alg {
        md5     { ::sh::md5 $data }
        sha1    { ::sh::sha1 $data }
        sha256  { ::sh::sha256 $data }
        crc32   { format %08x [zlib crc32 $data] }
        default { ::sh::fail $cmd "unknown algorithm \"$alg\" (use md5, sha1, sha256 or crc32)" }
    }
}

proc digest {text {alg sha1}} {
    ::sh::digest digest $alg [encoding convertto utf-8 $text]
}
::sh::doc digest {a short fingerprint of some text} {
    digest text ?md5|sha1|sha256|crc32?
} {
    Returns the fingerprint (hash) of the text as lowercase hex digits. The
    same text always gives the same fingerprint and a different text almost
    never does, so fingerprints show whether two things are identical without
    comparing them. The default algorithm is sha1.
} {
    digest hello
    digest hello sha256
    digest hello crc32
}

proc hash {names {alg sha1}} {
    if {![llength $names]} { return "" }
    set out {}
    foreach f [::sh::names hash {*}$names] {
        set r [::sh::real $f]
        if {![file exists $r]} { ::sh::fail hash "$f: no such file or directory" }
        if {[file isdirectory $r]} continue
        if {[catch {
            set fh [open $r rb]
            set data [read $fh]
            close $fh
        } err opts]} { ::sh::oserr hash $f $err $opts }
        lappend out "[::sh::digest hash $alg $data]  $f"
    }
    ::sh::tj $out
}
::sh::doc hash {fingerprint files} {
    hash names ?md5|sha1|sha256|crc32?
} {
    Takes a LIST of names (or patterns) and returns a line of text for each
    thing: its fingerprint, two spaces, and its name. Places in the list are
    skipped, so you can hand it the result of walk directly. An empty list
    gives empty text. The default algorithm is sha1; a different algorithm is
    just a word, not a different command. The sums are worked out in Tcl, so
    sha1 and sha256 take about half a second per 100 KB; crc32 is much faster.

    Identical files have identical fingerprints, so this finds duplicates:
    the text tools sort and uniq can group lines by their first word.
} {
    hash a.txt
    hash [walk -f] sha256
    uniq [sort [hash [walk -f]]] -d -x {^\S+}
}

proc xd {name args} {
    lassign [::sh::flags xd $args {} {n}] o rest
    set limit [expr {[dict exists $o n] ? [::sh::count xd [dict get $o n]] : 256}]
    set r [::sh::real $name]
    if {![file exists $r]} { ::sh::fail xd "$name: no such file or directory" }
    if {[file isdirectory $r]} { ::sh::fail xd "$name: is a place, not a thing" }
    set fh [open $r rb]
    set data [read $fh $limit]
    close $fh
    set out {}
    for {set i 0} {$i < [string length $data]} {incr i 16} {
        set chunk [string range $data $i [expr {$i + 15}]]
        binary scan $chunk c* bytes
        set hex [join [lmap b $bytes {format %02x [expr {$b & 255}]}] " "]
        set asc [join [lmap b $bytes {
            set b [expr {$b & 255}]
            expr {$b >= 32 && $b < 127 ? [format %c $b] : "."}
        }] ""]
        lappend out [format "%08x  %-47s  %s" $i $hex $asc]
    }
    ::sh::tj $out
}
::sh::doc xd {show the raw bytes of a thing} {
    xd name ?-n count?
} {
    Shows a thing byte by byte: each line has the position (in hex), up to 16
    bytes as hex pairs, and the same bytes as letters, with a dot for any
    byte that is not a printable letter. Use it on things that cat refuses
    because they are not text. Shows the first 256 bytes unless -n gives a
    different count.
} {
    xd picture.gif
    xd -n 32 data.bin
}

proc seq {args} {
    set n [llength $args]
    if {$n < 1 || $n > 3} { ::sh::fail seq "needs 1 to 3 numbers (seq last, seq first last, seq first step last)" }
    foreach a $args { ::sh::num seq $a }
    switch $n {
        1 { lassign [list 1 1 [lindex $args 0]] a s b }
        2 { lassign $args a b; set s [expr {$a <= $b ? 1 : -1}] }
        3 { lassign $args a s b }
    }
    if {$s == 0} { ::sh::fail seq "the step must not be 0" }
    if {($b - $a) * $s < 0} { return "" }
    ::sh::v [lseq $a to $b by $s]
}
::sh::doc seq {count: a list of numbers} {
    seq last
    seq first last
    seq first step last
} {
    Returns a list of numbers, both ends included. One number counts from 1
    up to it; two numbers count from the first to the last (downwards if the
    first is larger); three give the step in the middle. A step that points
    the wrong way gives an empty list.
} {
    seq 5
    seq 10 -1 7
    seq 0 0.5 2
    each [seq 3] i {echo "line $i"}
}

proc calc {args} {
    if {![llength $args]} { ::sh::fail calc "needs a sum, such as: calc 2 + 3 * 4" }
    if {[catch {expr [join $args " "]} r]} { ::sh::fail calc $r }
    return $r
}
::sh::doc calc {do arithmetic without braces} {
    calc expression...
} {
    Works out an arithmetic expression. The words are joined with spaces, so
    you can type it naturally. Quote anything the shell would read specially:
    [ ] and $ and braces, and put parentheses around groups.
    All of Tcl's expr is available: sqrt(), abs(), round(), ** for powers.
} {
    calc 2 + 3 * 4
    calc (1 + 2) * 3
    calc 2 ** 10
    calc sqrt(2)
}

proc echo {args} {
    puts [join $args " "]
    return
}
::sh::doc echo {print words on the screen} {
    echo word...
} {
    Prints its words, separated by single spaces, on a line of their own,
    and returns nothing. It prints to the screen straight away, even in the
    middle of a loop or a script. To keep text in a value rather than print
    it, just use the text itself: set t "hello world".
} {
    echo hello world
    foreach f [ls] { echo "found $f" }
}

# ---------------------------------------------------------------- == 3. text
# Commands on TEXT: a string of lines.  Text goes in as the first argument
# and comes out as text.  Splitting on newlines is safe here because a line
# is, by definition, what lies between newlines.  Use `lines` / `unlines`
# to cross over to lists.

# ::sh::key re line -- the part of a line a pattern selects: the first
# (...) group if the pattern has one, else the whole match, else "".
proc ::sh::key {re line} {
    set m [regexp -inline -- $re $line]
    if {![llength $m]} { return "" }
    expr {[llength $m] > 1 ? [lindex $m 1] : [lindex $m 0]}
}

# ::sh::lead s -- the number a line starts with (0 if none).
proc ::sh::lead {s} {
    if {[regexp {^\s*([-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?)} $s -> n]} { return $n }
    return 0
}

::sh::group "Text (lines in, lines out)"

proc lines {text} { ::sh::v [::sh::tl $text] }
::sh::doc lines {text to a list of its lines} {
    lines text
} {
    Cuts text into its lines and returns them as a list, so the list tools
    (each, where, first, ...) can work on them. Empty text has no lines.
    The opposite of unlines.
} {
    lines "red\ngreen\nblue"
    each [lines [cat names.txt]] n {string toupper $n}
}

proc unlines {list} { ::sh::tj $list }
::sh::doc unlines {a list to text, one item per line} {
    unlines list
} {
    Joins the items of a list into text with one item on each line. The
    opposite of lines. Use it to hand a list to the text tools or to save
    it in a file.
} {
    unlines {red green blue}
    save [unlines [first [lines [cat big.txt]] 100]] top100.txt
}

proc grep {text args} {
    lassign [::sh::flags grep $args {v i n c}] o rest
    if {[llength $rest] != 1} { ::sh::fail grep "needs text and one pattern (grep text pattern ?-v -i -n -c?)" }
    set re [::sh::regex grep [lindex $rest 0] [dict exists $o i]]
    set out {}
    set cnt 0
    set no 0
    foreach l [::sh::tl $text] {
        incr no
        if {[regexp -- $re $l] != [dict exists $o v]} {
            incr cnt
            lappend out [expr {[dict exists $o n] ? "$no:$l" : $l}]
        }
    }
    if {[dict exists $o c]} { return $cnt }
    ::sh::tj $out
}
::sh::doc grep {keep the lines that match a pattern} {
    grep text pattern ?-v? ?-i? ?-n? ?-c?
} {
    Returns only the lines of the text that contain a match for the pattern.
    The pattern is a regular expression (see: help regexp); an ordinary word
    simply matches itself. If nothing matches the result is empty text.

    -v  keep the lines that do NOT match.
    -i  ignore capital letters.
    -n  put the line number and a colon in front of each line.
    -c  give only the number of matching lines.
} {
    grep [cat log.txt] error
    grep [cat log.txt] {^2026} -c
    grep [ls] {\.txt$}
}

proc search {names args} {
    lassign [::sh::flags search $args {v i l}] o rest
    if {[llength $rest] != 1} { ::sh::fail search "needs names and one pattern (search names pattern ?-v -i -l?)" }
    set re [::sh::regex search [lindex $rest 0] [dict exists $o i]]
    set out {}
    set hit {}
    foreach f [::sh::names search {*}$names] {
        set r [::sh::real $f]
        if {[file isdirectory $r]} continue
        if {[catch {::sh::slurp search $f} text]} {
            if {[string match "*looks like binary*" $text]} continue
            return -code error $text
        }
        set no 0
        set found 0
        foreach l [::sh::tl $text] {
            incr no
            if {[regexp -- $re $l] != [dict exists $o v]} {
                set found 1
                lappend out "$f:$no:$l"
            }
        }
        if {$found} { lappend hit $f }
    }
    if {[dict exists $o l]} { return [::sh::v $hit] }
    ::sh::tj $out
}
::sh::doc search {find lines in files} {
    search names pattern ?-v? ?-i? ?-l?
} {
    Looks through every thing in the list of names (patterns work) and
    returns a line for each match: the file name, the line number, and the
    line, joined by colons. Places and binary things are skipped. It is
    grep for a whole list of files at once.

    -v  report the lines that do NOT match.
    -i  ignore capital letters.
    -l  return just a list of the names of files that have a match.
} {
    search *.txt hello
    search [walk -f /src] TODO
    search -l [walk -f] {password} -i
}

proc head {text {n 10}} {
    ::sh::count head $n
    ::sh::tj [lrange [::sh::tl $text] 0 [expr {$n - 1}]]
}
::sh::doc head {the first lines} {
    head text ?n?
} {
    Returns the first n lines of the text (10 if n is not given). Fewer if
    the text is shorter.
} {
    head [cat log.txt] 5
}

proc tail {text {n 10}} {
    ::sh::count tail $n
    set l [::sh::tl $text]
    if {$n == 0} { return "" }
    ::sh::tj [lrange $l end-[expr {$n - 1}] end]
}
::sh::doc tail {the last lines} {
    tail text ?n?
} {
    Returns the last n lines of the text (10 if n is not given). Fewer if
    the text is shorter.
} {
    tail [cat log.txt] 3
}

proc wc {text args} {
    lassign [::sh::flags wc $args {l w c}] o rest
    if {[llength $rest]} { ::sh::fail wc "takes only text (wc text ?-l? ?-w? ?-c?)" }
    set r [dict create lines [llength [::sh::tl $text]] \
        words [llength [regexp -all -inline {\S+} $text]] chars [string length $text]]
    set want {}
    foreach {f k} {l lines w words c chars} { if {[dict exists $o $f]} { lappend want $k } }
    if {[llength $want] == 1} { return [dict get $r [lindex $want 0]] }
    if {[llength $want] > 1} { set r [dict filter $r script {k v} {expr {$k in $want}}] }
    ::sh::vd $r
}
::sh::doc wc {count lines, words and characters} {
    wc text ?-l? ?-w? ?-c?
} {
    Counts the lines, the words (runs of non-blank letters) and the
    characters of the text. With no flag you get a record of all three:
    lines, words and chars. With one flag you get just that number.

    -l  lines    -w  words    -c  characters
} {
    wc [cat essay.txt]
    wc [cat essay.txt] -w
    wc [ls] -l
}

proc nl {text} {
    set no 0
    ::sh::tj [lmap l [::sh::tl $text] {format "%5d  %s" [incr no] $l}]
}
::sh::doc nl {number the lines} {
    nl text
} {
    Puts a line number in front of every line.
} {
    nl [cat program.tcl]
}

proc fields {text args} {
    lassign [::sh::flags fields $args {} {d}] o idx
    if {![llength $idx]} { ::sh::fail fields "needs at least one field number (fields text 1 3, or end)" }
    set sep [expr {[dict exists $o d] ? [dict get $o d] : ""}]
    set want {}
    foreach i $idx {
        if {[string is integer -strict $i] && $i >= 1} {
            lappend want [expr {$i - 1}]
        } elseif {[regexp {^end(-[0-9]+)?$} $i]} {
            lappend want $i
        } else {
            ::sh::fail fields "bad field \"$i\" (numbers start at 1; end is the last)"
        }
    }
    ::sh::tj [lmap l [::sh::tl $text] {
        set parts [expr {$sep eq "" ? [regexp -all -inline {\S+} $l] : [split $l $sep]}]
        join [lmap w $want {lindex $parts $w}] [expr {$sep eq "" ? " " : $sep}]
    }]
}
::sh::doc fields {pick columns out of each line} {
    fields text ?-d separator? number...
} {
    Splits every line into fields and returns just the ones you name,
    numbered from 1, in the order you name them. "end" is the last field,
    "end-1" the one before it. A field that does not exist comes out empty.

    Fields are separated by runs of blanks, or by the exact separator given
    with -d. The chosen fields are joined back with a single blank, or with
    the separator.
} {
    fields "alice 30 paris" 1 3
    fields [cat passwd.txt] -d : 1 end
}

proc extract {text re} {
    set re [::sh::regex extract $re]
    set groups [lindex [regexp -about $re] 0]
    set out {}
    foreach l [::sh::tl $text] {
        set all [regexp -all -inline -- $re $l]
        if {$groups == 0} {
            lappend out {*}$all
        } else {
            set stride [expr {$groups + 1}]
            for {set i 0} {$i < [llength $all]} {incr i $stride} { lappend out [lindex $all [expr {$i + 1}]] }
        }
    }
    ::sh::v $out
}
::sh::doc extract {pull the matching pieces out of text} {
    extract text pattern
} {
    Returns a list of every piece of the text that matches the pattern, found
    line by line, in order. If the pattern contains a (...) group, you get
    what the first group matched instead of the whole match. Where grep
    keeps whole lines, extract keeps only the parts you ask for.
} {
    extract "call 555-1234 or 555-9876" {[0-9]{3}-[0-9]{4}}
    extract [cat page.html] {href="([^"]*)"}
    tally [extract [cat log.txt] {user=(\w+)}]
}

proc fmt {text {width 70}} {
    ::sh::count fmt $width
    set paras {}
    set cur {}
    foreach l [concat [::sh::tl $text] {{}}] {
        if {[string trim $l] eq ""} {
            if {[llength $cur]} { lappend paras [::sh::fill [join $cur " "] $width]; set cur {} }
        } else {
            lappend cur $l
        }
    }
    join $paras "\n\n"
}
::sh::doc fmt {re-flow paragraphs to a line width} {
    fmt text ?width?
} {
    Joins the lines of each paragraph (paragraphs are separated by blank
    lines) and breaks them again so that no line is longer than the width
    (70 by default). Words are never split.
} {
    fmt [cat letter.txt] 60
}

# ---- tr

proc ::sh::trset {cmd s} {
    set chars {}
    set n [string length $s]
    for {set i 0} {$i < $n} {incr i} {
        set c [string index $s $i]
        if {$c eq "\\" && $i + 1 < $n} {
            incr i
            set c [string index $s $i]
            set c [string map {n "\n" t "\t"} $c]
        }
        if {[string index $s [expr {$i + 1}]] eq "-" && $i + 2 < $n} {
            set e [string index $s [expr {$i + 2}]]
            scan $c %c lo
            scan $e %c hi
            if {$hi < $lo} { ::sh::fail $cmd "bad range $c-$e" }
            for {set k $lo} {$k <= $hi} {incr k} { lappend chars [format %c $k] }
            incr i 2
        } else {
            lappend chars $c
        }
    }
    return $chars
}

proc tr {text args} {
    lassign [::sh::flags tr $args {d s}] o rest
    set del [dict exists $o d]
    if {[llength $rest] < 1 || [llength $rest] > 2 || ($del && [llength $rest] != 1)} {
        ::sh::fail tr "usage: tr text from to, or tr text chars -d, or tr text chars -s"
    }
    set from [::sh::trset tr [lindex $rest 0]]
    set map {}
    if {$del} {
        foreach c $from { lappend map $c "" }
        set text [string map $map $text]
        set sq {}
    } elseif {[llength $rest] == 2} {
        set to [::sh::trset tr [lindex $rest 1]]
        if {![llength $to]} { ::sh::fail tr "the second set is empty" }
        set i 0
        foreach c $from {
            lappend map $c [lindex $to [expr {min($i, [llength $to] - 1)}]]
            incr i
        }
        set text [string map $map $text]
        set sq $to
    } else {
        set sq $from
    }
    if {[dict exists $o s]} {
        set out ""
        set prev ""
        foreach c [split $text ""] {
            if {$c eq $prev && $c in $sq} continue
            append out $c
            set prev $c
        }
        set text $out
    }
    return $text
}
::sh::doc tr {swap, delete or squeeze letters} {
    tr text from to
    tr text letters -d
    tr text letters -s
} {
    Changes single letters. In "tr text from to", every letter found in the
    first set is replaced by the letter in the same place in the second set.
    A set is plain letters, or a range such as a-z or 0-9; \n and \t are
    a newline and a tab. If the second set is shorter, its last letter is
    repeated.

    -d  delete every letter in the set (no second set).
    -s  squeeze: runs of the same letter (from the final set) become one.
} {
    tr "Hello" a-z A-Z
    tr "a1b22c" 0-9 -d
    tr "too    many   blanks" " " -s
}

# ---- sort / uniq

proc sort {text args} {
    lassign [::sh::flags sort $args {n r u i} {k f}] o rest
    if {[llength $rest]} { ::sh::fail sort "takes only text (sort text ?-n -r -u -i? ?-k pattern? ?-f field?)" }
    if {[dict exists $o k] && [dict exists $o f]} { ::sh::fail sort "use -k or -f, not both" }
    set kre ""
    if {[dict exists $o k]} { set kre [::sh::regex sort [dict get $o k]] }
    if {[dict exists $o f]} {
        if {![string is integer -strict [dict get $o f]] || [dict get $o f] < 1} {
            ::sh::fail sort "bad field \"[dict get $o f]\" (numbers start at 1)"
        }
        set fld [expr {[dict get $o f] - 1}]
    }
    set rows {}
    foreach l [::sh::tl $text] {
        if {$kre ne ""} {
            set k [::sh::key $kre $l]
        } elseif {[info exists fld]} {
            set k [lindex [regexp -all -inline {\S+} $l] $fld]
        } else {
            set k $l
        }
        if {[dict exists $o n]} {
            set k [::sh::lead $k]
        } elseif {[dict exists $o i]} {
            set k [string tolower $k]
        }
        lappend rows [list $k $l]
    }
    set flags [expr {[dict exists $o n] ? "-real" : "-ascii"}]
    set rows [lsort {*}$flags -index 0 {*}[expr {[dict exists $o r] ? "-decreasing" : "-increasing"}] $rows]
    if {[dict exists $o u]} {
        set seen {}
        set rows [lmap r $rows {
            set k [lindex $r 0]
            if {[info exists prev] && $prev eq $k} continue
            set prev $k
            set r
        }]
    }
    ::sh::tj [lmap r $rows {lindex $r 1}]
}
::sh::doc sort {put lines in order} {
    sort text ?-n? ?-r? ?-u? ?-i? ?-k pattern? ?-f field?
} {
    Returns the lines of the text in order, by letter code (so capitals come
    before small letters) unless a flag says otherwise. Lines that compare
    equal keep their original order.

    -n  order by the number each line (or key) starts with, so 9 comes
        before 10. A key with no leading number counts as 0.
    -r  reverse the order.
    -u  keep only the first of lines whose keys are equal.
    -i  ignore capital letters.
    -k  order by the part of each line that the pattern selects (the first
        (...) group, or else the whole match) instead of the whole line.
    -f  order by the nth blank-separated field; fields count from 1.

    To sort rows (a table) by a column use sort-by; to sort a list use
    lsort or sort-on.
} {
    sort [ls]
    sort [cat scores.txt] -n -r
    sort [cat people.txt] -f 2
    sort [cat log.txt] -k {user=(\w+)}
}

proc uniq {text args} {
    lassign [::sh::flags uniq $args {c d u a i} {x}] o rest
    if {[llength $rest]} { ::sh::fail uniq "takes only text (uniq text ?-c -d -u -a -i? ?-x pattern?)" }
    if {[dict exists $o d] && [dict exists $o u]} { ::sh::fail uniq "use -d or -u, not both" }
    set xre ""
    if {[dict exists $o x]} { set xre [::sh::regex uniq [dict get $o x]] }
    set groups {}      ;# each: {key line count}
    set idx [dict create]
    foreach l [::sh::tl $text] {
        set k [expr {$xre ne "" ? [expr {[regexp -- $xre $l] ? [::sh::key $xre $l] : $l}] : $l}]
        if {[dict exists $o i]} { set k [string tolower $k] }
        if {[dict exists $o a]} {
            if {[dict exists $idx $k]} {
                set g [dict get $idx $k]
                lset groups $g 2 [expr {[lindex $groups $g 2] + 1}]
                continue
            }
            dict set idx $k [llength $groups]
        } elseif {[llength $groups] && [lindex $groups end 0] eq $k} {
            lset groups end 2 [expr {[lindex $groups end 2] + 1}]
            continue
        }
        lappend groups [list $k $l 1]
    }
    set out {}
    foreach g $groups {
        lassign $g k l n
        if {[dict exists $o d] && $n < 2} continue
        if {[dict exists $o u] && $n > 1} continue
        lappend out [expr {[dict exists $o c] ? [format "%4d %s" $n $l] : $l}]
    }
    ::sh::tj $out
}
::sh::doc uniq {collapse repeated lines} {
    uniq text ?-c? ?-d? ?-u? ?-a? ?-i? ?-x pattern?
} {
    Returns the text with each run of identical lines replaced by one copy.
    Normally only lines that are NEXT to each other count as repeats, so
    sort first to bring equal lines together (or use -a).

    -c  put the count in front of every line, for repeated and single lines
        alike.
    -d  keep only lines that were repeated.
    -u  keep only lines that were not repeated.
    -a  count repeats anywhere in the text, not just side by side. Lines keep
        the order of their first appearance.
    -i  ignore capital letters.
    -x  compare only the part of each line the pattern selects (the first
        (...) group, or else the whole match; lines the pattern does not
        match are compared whole). The first full line of each group is kept.
} {
    uniq [sort [cat words.txt]] -c
    sort [uniq [cat words.txt] -a -c] -n -r
    uniq [sort [hash [walk -f]]] -d -x {^\S+}
}

# ---- diff

proc diff {a b} {
    set x [::sh::tl $a]
    set y [::sh::tl $b]
    set n [llength $x]
    set m [llength $y]
    # lcs[i][j] = length of the longest common run of x[i..] and y[j..]
    set row0 [lrepeat [expr {$m + 1}] 0]
    set lcs [lrepeat [expr {$n + 1}] $row0]
    for {set i [expr {$n - 1}]} {$i >= 0} {incr i -1} {
        for {set j [expr {$m - 1}]} {$j >= 0} {incr j -1} {
            if {[lindex $x $i] eq [lindex $y $j]} {
                lset lcs $i $j [expr {[lindex $lcs [expr {$i + 1}] [expr {$j + 1}]] + 1}]
            } else {
                lset lcs $i $j [expr {max([lindex $lcs [expr {$i + 1}] $j], [lindex $lcs $i [expr {$j + 1}]])}]
            }
        }
    }
    # walk the table, collecting hunks of {xstart xend ystart yend}
    set hunks {}
    set i 0
    set j 0
    while {$i < $n || $j < $m} {
        if {$i < $n && $j < $m && [lindex $x $i] eq [lindex $y $j]} {
            incr i
            incr j
            continue
        }
        set i0 $i
        set j0 $j
        while {($i < $n || $j < $m) && !($i < $n && $j < $m && [lindex $x $i] eq [lindex $y $j])} {
            if {$j >= $m || ($i < $n && [lindex $lcs [expr {$i + 1}] $j] >= [lindex $lcs $i [expr {$j + 1}]])} {
                incr i
            } else {
                incr j
            }
        }
        lappend hunks [list $i0 $i $j0 $j]
    }
    set out {}
    foreach h $hunks {
        lassign $h i0 i1 j0 j1
        set xr [expr {$i1 - $i0 == 0 ? $i0 : ($i1 - $i0 == 1 ? $i1 : "[expr {$i0 + 1}],$i1")}]
        set yr [expr {$j1 - $j0 == 0 ? $j0 : ($j1 - $j0 == 1 ? $j1 : "[expr {$j0 + 1}],$j1")}]
        set op [expr {$i1 == $i0 ? "a" : ($j1 == $j0 ? "d" : "c")}]
        lappend out "$xr$op$yr"
        foreach l [lrange $x $i0 [expr {$i1 - 1}]] { lappend out "< $l" }
        if {$op eq "c"} { lappend out "---" }
        foreach l [lrange $y $j0 [expr {$j1 - 1}]] { lappend out "> $l" }
    }
    ::sh::tj $out
}
::sh::doc diff {show how two texts differ} {
    diff old new
} {
    Compares two texts line by line. Returns nothing if they are the same.
    Otherwise it returns a recipe for turning the first into the second:
    a header like 3c3 (line 3 of the first text is Changed into line 3 of
    the second), 5a6 (after line 5, line 6 is Added) or 7d6 (line 7 is
    Deleted), followed by the affected lines: those starting with < come from
    the first text, those with > from the second.

    It compares VALUES, not file names, so give it the text itself:
    diff [cat a.txt] [cat b.txt]. It is meant for texts of up to a few
    thousand lines; it needs memory in proportion to the two lengths
    multiplied together.
} {
    diff "a\nb\nc" "a\nB\nc"
    diff [cat old.txt] [cat new.txt]
}

# ---- sed

# ::sh::sedparse script -- parse into a list of commands:
#   {a1 a2 neg cmd args}  where a1/a2 are "" or {n N} {end} {re R}
proc ::sh::sedparse {script} {
    set cmds {}
    set i 0
    set n [string length $script]
    while 1 {
        while {$i < $n && [string index $script $i] in {" " "\t" "\n" ";"}} { incr i }
        if {$i >= $n} break
        set a1 ""
        set a2 ""
        if {[::sh::sedaddr $script i a1]} {
            if {[string index $script $i] eq ","} {
                incr i
                if {![::sh::sedaddr $script i a2]} { ::sh::fail sed "bad address after comma in \"$script\"" }
            }
        }
        while {[string index $script $i] eq " "} { incr i }
        set neg 0
        if {[string index $script $i] eq "!"} { set neg 1; incr i }
        set c [string index $script $i]
        incr i
        switch -- $c {
            d - p - q { lappend cmds [list $a1 $a2 $neg $c {}] }
            s {
                set d [string index $script $i]
                incr i
                set re [::sh::seddelim $script i $d]
                set rep [::sh::seddelim $script i $d]
                set fl ""
                while {$i < $n && [string index $script $i] in {g p i}} { append fl [string index $script $i]; incr i }
                lappend cmds [list $a1 $a2 $neg s [list $re $rep $fl]]
            }
            y {
                set d [string index $script $i]
                incr i
                set s1 [::sh::seddelim $script i $d]
                set s2 [::sh::seddelim $script i $d]
                set f [::sh::trset sed $s1]
                set t [::sh::trset sed $s2]
                if {[llength $f] != [llength $t]} { ::sh::fail sed "y needs two sets of the same length" }
                lappend cmds [list $a1 $a2 $neg y [concat {*}[lmap x $f y $t {list $x $y}]]]
            }
            "" { ::sh::fail sed "address without a command in \"$script\"" }
            default { ::sh::fail sed "unknown command \"$c\" (this sed has: s d p q y)" }
        }
    }
    return $cmds
}

# read up to the next unescaped delimiter; "\<delim>" becomes the delimiter.
proc ::sh::seddelim {script iv d} {
    upvar 1 $iv i
    set out ""
    set n [string length $script]
    while {$i < $n} {
        set c [string index $script $i]
        if {$c eq "\\" && $i + 1 < $n} {
            set nx [string index $script [expr {$i + 1}]]
            if {$nx eq $d} { append out $d } else { append out $c $nx }
            incr i 2
            continue
        }
        incr i
        if {$c eq $d} { return $out }
        append out $c
    }
    ::sh::fail sed "unfinished command: missing closing \"$d\""
}

proc ::sh::sedaddr {script iv av} {
    upvar 1 $iv i $av a
    set c [string index $script $i]
    if {[string is digit -strict $c]} {
        regexp -start $i {\d+} $script num
        incr i [string length $num]
        set a [list n $num]
        return 1
    }
    if {$c eq "$"} { incr i; set a [list end]; return 1 }
    if {$c eq "/"} {
        incr i
        set a [list re [::sh::seddelim $script i /]]
        return 1
    }
    return 0
}

proc ::sh::sedhit {a no total line} {
    switch [lindex $a 0] {
        n   { expr {$no == [lindex $a 1]} }
        end { expr {$no == $total} }
        re  { regexp -- [lindex $a 1] $line }
    }
}

# does the second address of a range end the range at this line?
proc ::sh::sedend {a no total line} {
    switch [lindex $a 0] {
        n   { expr {$no >= [lindex $a 1]} }
        end { expr {$no == $total} }
        re  { regexp -- [lindex $a 1] $line }
    }
}

# translate sed's replacement text to Tcl regsub's: & whole match, \1..\9
# groups, \n newline; a lone backslash-letter is just the letter.
proc ::sh::sedrep {rep} {
    set out ""
    set n [string length $rep]
    for {set i 0} {$i < $n} {incr i} {
        set c [string index $rep $i]
        if {$c eq "\\" && $i + 1 < $n} {
            incr i
            set c [string index $rep $i]
            if {$c eq "n"} {
                append out "\n"
            } elseif {[string is digit -strict $c] || $c in {& "\\"}} {
                append out "\\" $c
            } else {
                append out $c
            }
        } else {
            append out $c
        }
    }
    return $out
}

proc sed {text args} {
    lassign [::sh::flags sed $args {n}] o rest
    if {[llength $rest] != 1} { ::sh::fail sed "needs text and one script (sed text script ?-n?)" }
    set cmds [::sh::sedparse [lindex $rest 0]]
    # compile the patterns once, and check them
    set prog {}
    foreach c $cmds {
        lassign $c a1 a2 neg op arg
        foreach k {a1 a2} {
            set a [set $k]
            if {[lindex $a 0] eq "re"} { set $k [list re [::sh::regex sed [lindex $a 1]]] }
        }
        if {$op eq "s"} {
            lassign $arg re rep fl
            set arg [list [::sh::regex sed $re [string match *i* $fl]] [::sh::sedrep $rep] $fl]
        }
        lappend prog [list $a1 $a2 $neg $op $arg]
    }
    set lines [::sh::tl $text]
    set total [llength $lines]
    set active [lrepeat [llength $prog] 0]
    set out {}
    set no 0
    foreach line $lines {
        incr no
        set deleted 0
        set quit 0
        set k -1
        foreach c $prog {
            incr k
            lassign $c a1 a2 neg op arg
            if {$a1 eq ""} {
                set hit 1
            } elseif {$a2 eq ""} {
                set hit [::sh::sedhit $a1 $no $total $line]
            } elseif {[lindex $active $k]} {
                set hit 1
                if {[::sh::sedend $a2 $no $total $line]} { lset active $k 0 }
            } elseif {[::sh::sedhit $a1 $no $total $line]} {
                set hit 1
                # a numeric or $ end that is already reached makes a one-line range
                if {[lindex $a2 0] eq "re" || ![::sh::sedend $a2 $no $total $line]} { lset active $k 1 }
            } else {
                set hit 0
            }
            if {$neg} { set hit [expr {!$hit}] }
            if {!$hit} continue
            switch $op {
                d { set deleted 1; break }
                p { lappend out $line }
                q { set quit 1; break }
                s {
                    lassign $arg re rep fl
                    set did [expr {[string match *g* $fl] ? [regsub -all -- $re $line $rep line] : [regsub -- $re $line $rep line]}]
                    if {$did && [string match *p* $fl]} { lappend out $line }
                }
                y { set line [string map $arg $line] }
            }
        }
        if {!$deleted && ![dict exists $o n]} { lappend out $line }
        if {$quit} break
    }
    ::sh::tj $out
}
::sh::doc sed {edit text with a small script} {
    sed text script ?-n?
} {
    Runs a script over every line of the text and returns the result. The
    script is a short string of commands, separated by ; or newlines:

      s/old/new/    replace the first match of old in the line; add g to
                    replace all of them, i to ignore capitals
      d             delete the line
      p             print the line an extra time
      q             stop after this line
      y/abc/xyz/    change a to x, b to y, c to z

    Any letter-free character can replace the / in s and y. In new, & stands
    for whatever matched, \1 to \9 for the (...) groups of the pattern, and
    \n for a newline. Patterns are Tcl regular expressions (see: help regexp).

    A command may have an address in front that says which lines it applies
    to: a line number (3), the last line ($), a pattern (/error/), or a range
    with a comma (2,5 or /start/,/end/). An ! after the address means every
    other line.

    -n  print only what p and s///p print (quiet mode).
} {
    sed "hello world" s/world/there/
    sed [cat a.txt] {2,4d}
    sed [cat log.txt] {/error/!d}
    sed [cat a.txt] {s/(\w+) (\w+)/\2 \1/}
    sed [cat a.txt] -n {/TODO/p}
}

# -------------------------------------------------------------- == 4. values
# Commands on LISTS and on ROWS (a list of dicts: a table).  They take the
# collection first and give a list (or rows) back, never text, so they
# nest and thread.  Where a command runs your script, the script sees:
#   * for rows:       each column as a variable ($age, $name ...)
#   * for lists:      the item under the variable name you give (each x ...)
#   * always:         your own variables (the ones where you typed the call)
# A column that a row lacks is an error that names the row and the column.

# ::sh::scoped vars script names lvl mode -- evaluate script with the dict
# `vars` as variables and the caller's variables (listed in `names`, at
# absolute frame level `lvl`) visible.  mode is expr or eval.  Names are
# deliberately ugly so they cannot collide with a column called "script".
proc ::sh::scoped {__vars __script __names __lvl __mode} {
    dict with __vars {}
    foreach __v $__names {
        if {![dict exists $__vars $__v] && $__v ni {__vars __script __names __lvl __mode __v}} {
            upvar #$__lvl $__v $__v
        }
    }
    if {$__mode eq "expr"} { return [expr $__script] }
    return [eval $__script]
}

# ::sh::isrec cmd row i -- the row must be a record (key value pairs).
proc ::sh::isrec {cmd row i} {
    if {[catch {dict size $row}]} { ::sh::fail $cmd "row $i is not a record (key value pairs): $row" }
}

# ::sh::col cmd row i name -- a column's value, or an error naming it.
proc ::sh::col {cmd row i name} {
    if {![dict exists $row $name]} { ::sh::fail $cmd "row $i has no column \"$name\"" }
    dict get $row $name
}

::sh::group "Lists (one value per item)"

proc each {list var script} {
    ::sh::v [uplevel 1 [list lmap $var $list $script]]
}
::sh::doc each {do something to every item; collect the results} {
    each list var script
} {
    Runs the script once for each item of the list, with the item in the
    variable named var, and returns the list of the script's results. It is
    Tcl's lmap, with the list first so it chains. Inside the script,
    "continue" leaves that item out of the result.

    Because the script is an ordinary Tcl script, it can use your own
    variables and any command.
} {
    each {1 2 3} x {expr {$x * 2}}
    each [ls] f {string toupper $f}
    each [walk -f] f {file size $f}
}

proc keep {list var script} {
    set body "if \{!\[expr [list $script]\]\} continue\nset [list $var]"
    ::sh::v [uplevel 1 [list lmap $var $list $body]]
}
::sh::doc keep {keep the items a test accepts} {
    keep list var test
} {
    Returns the items of the list for which the test is true. The test is an
    expression (like in if), written with the item's variable, which you
    name. For rows (tables) use where instead, which gives you the columns
    as variables.
} {
    keep {1 2 3 4 5 6} n {$n % 2 == 0}
    keep [ls] f {[string match *.txt $f]}
}

proc reduce {list script args} {
    if {[llength $args] > 1} { ::sh::fail reduce "usage: reduce list script ?initial?" }
    if {[llength $args] == 1} {
        set acc [lindex $args 0]
    } elseif {[llength $list]} {
        set acc [lindex $list 0]
        set list [lrange $list 1 end]
    } else {
        ::sh::fail reduce "the list is empty and there is no initial value"
    }
    set lvl [expr {[info level] - 1}]
    set names [uplevel 1 {info vars}]
    foreach it $list {
        set acc [::sh::scoped [dict create acc $acc it $it] $script $names $lvl eval]
    }
    return $acc
}
::sh::doc reduce {fold a list into one value} {
    reduce list script ?initial?
} {
    Combines the items into a single value. The script runs once per item
    and sees two variables: $acc, the value so far, and $it, the next item.
    Whatever the script returns becomes the new $acc. The accumulator comes
    FIRST, as in most languages. With an initial value the fold starts from
    it and visits every item; without one, the first item is the starting
    value and the fold visits the rest. An empty list with no initial value
    is an error; with one, the initial value is the answer.
} {
    reduce {1 2 3 4} {expr {$acc + $it}}
    reduce {a b c} {string cat $acc $it} >
    reduce [lines [cat words.txt]] {expr {max($acc, [string length $it])}} 0
}

proc any {list var test} { expr {[llength [uplevel 1 [list keep $list $var $test]]] > 0} }
::sh::doc any {is the test true for at least one item?} {
    any list var test
} {
    Returns 1 if the test accepts at least one item, otherwise 0 (also 0 for
    an empty list). The test is written like keep's.
} {
    any {1 3 5} n {$n > 4}
}

proc all {list var test} {
    set n [llength $list]
    expr {[llength [uplevel 1 [list keep $list $var $test]]] == $n}
}
::sh::doc all {is the test true for every item?} {
    all list var test
} {
    Returns 1 if the test accepts every item, otherwise 0. An empty list gives
    1 (nothing fails the test).
} {
    all {2 4 6} n {$n % 2 == 0}
}

proc first {list {n 1}} {
    ::sh::count first $n
    ::sh::v [lrange $list 0 [expr {$n - 1}]]
}
::sh::doc first {the first items of a list} {
    first list ?n?
} {
    Returns a list of the first n items (1 if n is not given), or fewer if the
    list is shorter. The answer is still a list; for the bare item use
    lindex $list 0.
} {
    first [ls] 3
}

proc last {list {n 1}} {
    ::sh::count last $n
    if {$n == 0} { return "" }
    ::sh::v [lrange $list end-[expr {$n - 1}] end]
}
::sh::doc last {the last items of a list} {
    last list ?n?
} {
    Returns a list of the last n items (1 if n is not given), or fewer if the
    list is shorter. The answer is still a list; for the bare item use
    lindex $list end.
} {
    last [ls] 2
}

proc skip {list n} {
    ::sh::count skip $n
    ::sh::v [lrange $list $n end]
}
::sh::doc skip {drop the first items of a list} {
    skip list n
} {
    Returns the list without its first n items. Skipping more than there
    are gives an empty list.
} {
    skip {a b c d} 2
}

proc flatten {list} { ::sh::v [concat {*}$list] }
::sh::doc flatten {merge a list of lists into one list} {
    flatten list
} {
    Takes a list whose items are themselves lists and returns the items of
    all of them in one list. Only one level is removed.
} {
    flatten {{1 2} {3} {4 5}}
}

proc compact {list} { ::sh::v [lmap x $list {expr {$x eq "" ? [continue] : $x}}] }
::sh::doc compact {drop the empty items} {
    compact list
} {
    Returns the list without the items that are empty strings.
} {
    compact {a {} b {} c}
}

proc distinct {list} {
    set seen [dict create]
    ::sh::v [lmap x $list {
        if {[dict exists $seen $x]} continue
        dict set seen $x 1
        set x
    }]
}
::sh::doc distinct {remove repeated items, keeping the order} {
    distinct list
} {
    Returns the list with each value appearing once, at the place where it
    first appeared. (Tcl's lsort -unique also removes repeats but sorts too.)
} {
    distinct {b a b c a}
}

proc enumerate {list} {
    set i -1
    ::sh::v [lmap x $list {dict create index [incr i] item $x}]
}
::sh::doc enumerate {number the items} {
    enumerate list
} {
    Returns rows, one per item, with the columns index (from 0) and item.
} {
    enumerate {a b c}
    where [enumerate [ls]] {$index > 0}
}

proc zip {a b} {
    if {[llength $a] != [llength $b]} {
        ::sh::fail zip "the lists differ in length ([llength $a] and [llength $b])"
    }
    ::sh::v [lmap x $a y $b {list $x $y}]
}
::sh::doc zip {pair up two lists} {
    zip a b
} {
    Returns a list of pairs: the first items together, the second items
    together, and so on. The lists must be the same length.
} {
    zip {a b c} {1 2 3}
    dict create {*}[concat {*}[zip {a b} {1 2}]]
}

proc chunk {list n} {
    ::sh::count chunk $n
    if {$n == 0} { ::sh::fail chunk "the size must be at least 1" }
    set out {}
    for {set i 0} {$i < [llength $list]} {incr i $n} {
        lappend out [lrange $list $i [expr {$i + $n - 1}]]
    }
    ::sh::v $out
}
::sh::doc chunk {cut a list into pieces of a given size} {
    chunk list size
} {
    Returns a list of lists, each holding size items (the last may hold
    fewer).
} {
    chunk {1 2 3 4 5} 2
}

proc tally {list} {
    set d [dict create]
    foreach x $list { dict incr d $x }
    ::sh::vd $d
}
::sh::doc tally {count how often each value occurs} {
    tally list
} {
    Returns a record that maps each different value to the number of times it
    appears, in order of first appearance. For rows, count a column:
    tally [pluck $rows city].
} {
    tally {a b a c a}
    tally [extract [cat log.txt] {user=(\w+)}]
}

# numbers
proc ::sh::numbers {cmd list} {
    lmap x $list { ::sh::num $cmd $x }
}
proc sum {list} {
    set t 0
    foreach x [::sh::numbers sum $list] { set t [expr {$t + $x}] }
    return $t
}
::sh::doc sum {add up numbers} {
    sum list
} {
    Returns the total of a list of numbers: 0 for an empty list. Anything
    that is not a number is an error that shows the offending item.
} {
    sum {1 2 3.5}
    sum [pluck [files] size]
}

proc avg {list} {
    if {![llength $list]} { return "" }
    expr {double([expr [join [::sh::numbers avg $list] +]]) / [llength $list]}
}
::sh::doc avg {the average of numbers} {
    avg list
} {
    Returns the mean of a list of numbers as a decimal number. An empty list
    gives an empty answer.
} {
    avg {2 4 9}
}

proc min {list} {
    if {![llength $list]} { return "" }
    tcl::mathfunc::min {*}[::sh::numbers min $list]
}
::sh::doc min {the smallest number} {
    min list
} {
    Returns the smallest of a list of numbers. An empty list gives an empty
    answer.
} {
    min {4 2 9}
}

proc max {list} {
    if {![llength $list]} { return "" }
    tcl::mathfunc::max {*}[::sh::numbers max $list]
}
::sh::doc max {the largest number} {
    max list
} {
    Returns the largest of a list of numbers. An empty list gives an empty
    answer.
} {
    max [pluck [files] size]
}

# sorting lists
proc sort-on {list var script args} {
    lassign [::sh::flags sort-on $args {n r i}] o rest
    if {[llength $rest]} { ::sh::fail sort-on "unexpected \"[lindex $rest 0]\"" }
    set keys [uplevel 1 [list lmap $var $list $script]]
    set rows [lmap k $keys x $list {list [::sh::sortkey $o $k] $x}]
    ::sh::v [::sh::sortrows $o $rows]
}
proc ::sh::sortkey {o k} {
    if {[dict exists $o n]} { return [::sh::lead $k] }
    if {[dict exists $o i]} { return [string tolower $k] }
    return $k
}
proc ::sh::sortrows {o rows} {
    set rows [lsort [expr {[dict exists $o n] ? "-real" : "-ascii"}] -index 0 \
        [expr {[dict exists $o r] ? "-decreasing" : "-increasing"}] $rows]
    lmap r $rows {lindex $r 1}
}
::sh::doc sort-on {sort a list by a computed key} {
    sort-on list var script ?-n? ?-r? ?-i?
} {
    Sorts the items by a key worked out from each item: the script runs for
    each item (named by var) and its result is the sort key. Items with equal
    keys keep their order.

    -n  keys are numbers.   -r  reverse.   -i  ignore capitals.
} {
    sort-on {pear fig banana} w {string length $w}
    sort-on [ls] f {file size $f} -n -r
}

::sh::group "Rows and records (tables)"

proc where {rows script} {
    set lvl [expr {[info level] - 1}]
    set names [uplevel 1 {info vars}]
    set out {}
    set i 0
    foreach row $rows {
        incr i
        ::sh::isrec where $row $i
        if {[catch {::sh::scoped $row $script $names $lvl expr} r]} { ::sh::fail where "row $i: $r" }
        if {$r} { lappend out $row }
    }
    ::sh::v $out
}
::sh::doc where {keep the rows a test accepts} {
    where rows test
} {
    Returns the rows for which the test is true. The test is an expression,
    and in it every column of the row is a variable: $age, $name, ... Your
    own variables are visible too. A row that lacks a column the test uses is
    an error naming the row.
} {
    where $people {$age > 18}
    where [files] {$type eq "thing" && $size > 1000}
    set min 21; where $people {$age >= $min}
}

proc select {rows args} {
    if {![llength $args]} { ::sh::fail select "needs at least one column name" }
    set out {}
    set i 0
    foreach row $rows {
        incr i
        ::sh::isrec select $row $i
        set r [dict create]
        foreach c $args { dict set r $c [::sh::col select $row $i $c] }
        lappend out $r
    }
    ::sh::v $out
}
::sh::doc select {keep only some columns} {
    select rows column...
} {
    Returns the rows reduced to the named columns, in the order named. A row
    that lacks a named column is an error. To get one column as a plain list
    use pluck.
} {
    select [files] name size
}

proc reject {rows args} {
    set out {}
    set i 0
    foreach row $rows {
        incr i
        ::sh::isrec reject $row $i
        lappend out [dict remove $row {*}$args]
    }
    ::sh::v $out
}
::sh::doc reject {drop some columns} {
    reject rows column...
} {
    Returns the rows without the named columns. Rows that do not have a
    named column are left as they are.
} {
    reject [files] path mtime
}

proc pluck {rows col args} {
    if {[llength $args] > 1} { ::sh::fail pluck "usage: pluck rows column ?default?" }
    set out {}
    set i 0
    foreach row $rows {
        incr i
        ::sh::isrec pluck $row $i
        if {[llength $args] && ![dict exists $row $col]} {
            lappend out [lindex $args 0]
        } else {
            lappend out [::sh::col pluck $row $i $col]
        }
    }
    ::sh::v $out
}
::sh::doc pluck {one column as a plain list} {
    pluck rows column ?default?
} {
    Returns the values of one column, one per row, as a list. A row without
    the column is an error, unless a default value is given, which is used
    instead.
} {
    pluck $people name
    sum [pluck [files] size]
    pluck $people phone none
}

proc set-col {rows name script} {
    set lvl [expr {[info level] - 1}]
    set names [uplevel 1 {info vars}]
    set out {}
    set i 0
    foreach row $rows {
        incr i
        ::sh::isrec set-col $row $i
        if {[catch {::sh::scoped $row $script $names $lvl eval} r]} { ::sh::fail set-col "row $i: $r" }
        lappend out [dict replace $row $name $r]
    }
    ::sh::v $out
}
::sh::doc set-col {add or change a column} {
    set-col rows name script
} {
    Returns the rows with a column called name. The script runs for each row,
    with the row's columns as variables, and its result is the column's value.
    An existing column of that name is replaced; a new one goes at the end.
} {
    set-col $people next {expr {$age + 1}}
    set-col [files] kb {expr {$size / 1024}}
}

proc rename-col {rows old new} {
    set out {}
    set i 0
    foreach row $rows {
        incr i
        ::sh::isrec rename-col $row $i
        ::sh::col rename-col $row $i $old
        lappend out [dict create {*}[concat {*}[lmap {k v} $row {list [expr {$k eq $old ? $new : $k}] $v}]]]
    }
    ::sh::v $out
}
::sh::doc rename-col {give a column another name} {
    rename-col rows old new
} {
    Returns the rows with the column old called new instead, in the same
    place. A row without the column old is an error. (Tcl's own rename is
    for commands, hence the longer name.)
} {
    rename-col $people name who
}

proc sort-by {rows args} {
    lassign [::sh::flags sort-by $args {n r i}] o cols
    if {[llength $cols] != 1} {
        ::sh::fail sort-by "needs exactly one column name (to sort by two, sort twice: minor key first)"
    }
    set c [lindex $cols 0]
    set pairs {}
    set i 0
    foreach row $rows {
        incr i
        ::sh::isrec sort-by $row $i
        lappend pairs [list [::sh::sortkey $o [::sh::col sort-by $row $i $c]] $row]
    }
    ::sh::v [::sh::sortrows $o $pairs]
}
::sh::doc sort-by {sort rows by a column} {
    sort-by rows column ?-n? ?-r? ?-i?
} {
    Sorts the rows by the named column. Rows with equal keys keep their
    order, so to sort by two columns sort twice, the less important column
    first: the second sort keeps the first one's order wherever it ties.

    -n  compare as numbers (otherwise as text).
    -r  reverse.
    -i  ignore capitals.
} {
    sort-by $people age -n
    sort-by [files] size -n -r
    sort-by [sort-by $people age -n] city
}

proc group-by {rows col} {
    set d [dict create]
    set i 0
    foreach row $rows {
        incr i
        ::sh::isrec group-by $row $i
        dict lappend d [::sh::col group-by $row $i $col] $row
    }
    ::sh::vd $d
}
::sh::doc group-by {sort rows into groups by a column's value} {
    group-by rows column
} {
    Returns a record: each different value of the column is a key and its
    value is the list of rows that have it. Groups are in order of first
    appearance.
} {
    group-by $people city
    dict map {city members} [group-by $people city] {llength $members}
}

proc uniq-by {rows col} {
    set seen [dict create]
    set out {}
    set i 0
    foreach row $rows {
        incr i
        ::sh::isrec uniq-by $row $i
        set k [::sh::col uniq-by $row $i $col]
        if {[dict exists $seen $k]} continue
        dict set seen $k 1
        lappend out $row
    }
    ::sh::v $out
}
::sh::doc uniq-by {one row per different value of a column} {
    uniq-by rows column
} {
    Returns the rows, but only the first row for each different value of
    the column.
} {
    uniq-by $people city
}

proc columns {rows} {
    set cols {}
    foreach row $rows {
        foreach c [dict keys $row] { if {$c ni $cols} { lappend cols $c } }
    }
    ::sh::v $cols
}
::sh::doc columns {the column names of some rows} {
    columns rows
} {
    Returns the names of the columns that appear in the rows, in order of
    first appearance.
} {
    columns [files]
}

proc table {rows args} {
    set i 0
    foreach row $rows { incr i; ::sh::isrec table $row $i }
    set cols [expr {[llength $args] ? $args : [columns $rows]}]
    if {![llength $rows] || ![llength $cols]} { return "" }
    set cells {}
    set width [lmap c $cols {string length $c}]
    set numeric [lmap c $cols {expr {1}}]
    foreach row $rows {
        set line {}
        set k 0
        foreach c $cols {
            set v [string map {"\n" "\\n"} [dict getdef $row $c ""]]
            lappend line $v
            if {[string length $v] > [lindex $width $k]} { lset width $k [string length $v] }
            if {![string is double -strict $v]} { lset numeric $k 0 }
            incr k
        }
        lappend cells $line
    }
    set out {}
    set k 0
    lappend out [string trimright [join [lmap c $cols w $width {format "%-${w}s" $c}] "  "]]
    lappend out [string trimright [join [lmap w $width {string repeat - $w}] "  "]]
    foreach line $cells {
        lappend out [string trimright [join [lmap v $line w $width n $numeric {
            format [expr {$n ? "%${w}s" : "%-${w}s"}] $v
        }] "  "]]
    }
    ::sh::tj $out
}
::sh::doc table {draw rows as an aligned table} {
    table rows ?column...?
} {
    Turns rows into text: a header line with the column names, a line of
    dashes, and one line per row, in aligned columns. Numbers line up on the
    right. Name columns to show only those, in that order; otherwise all the
    columns are shown. A missing cell is left empty.

    The result is TEXT, for reading. It is the last step of a chain; the
    other row tools do not take it.
} {
    table [files]
    table [sort-by $people age -n] name age
}

# ---- parse, json, csv

proc parse {text args} {
    lassign [::sh::flags parse $args {} {x}] o rest
    if {[dict exists $o x]} {
        set re [::sh::regex parse [dict get $o x]]
        set names $rest
        if {![llength $names]} { ::sh::fail parse "-x needs the names of the groups after it" }
        if {[llength $names] != [lindex [regexp -about $re] 0]} {
            ::sh::fail parse "the pattern has [lindex [regexp -about $re] 0] groups but [llength $names] names were given"
        }
    } else {
        if {[llength $rest] != 1} { ::sh::fail parse "needs text and a template (parse text {name is {who}})" }
        lassign [::sh::template [lindex $rest 0]] re names
    }
    set out {}
    foreach l [::sh::tl $text] {
        set m [regexp -inline -- $re $l]
        if {![llength $m]} continue
        lappend out [dict create {*}[concat {*}[lmap n $names v [lrange $m 1 end] {list $n $v}]]]
    }
    ::sh::v $out
}
# ::sh::template t -- "{who} is {age}" -> {^(.*?) is (.*?)$} {who age}
proc ::sh::template {t} {
    set names {}
    set re "^"
    set i 0
    while {[regexp -start $i -indices {\{(\w+)\}} $t whole nm]} {
        lassign $whole a b
        lassign $nm c d
        append re [::sh::lit [string range $t $i [expr {$a - 1}]]]
        set n [string range $t $c $d]
        if {$n in $names} { ::sh::fail parse "the name \"$n\" is used twice in the template" }
        lappend names $n
        append re "(.*?)"
        set i [expr {$b + 1}]
    }
    append re [::sh::lit [string range $t $i end]] "$"
    if {![llength $names]} { ::sh::fail parse "the template has no \{name\} to capture" }
    return [list $re $names]
}
# literal text -> regexp; any run of blanks matches one or more blanks
proc ::sh::lit {s} {
    set out ""
    foreach part [regexp -all -inline {\s+|\S+} $s] {
        if {[string is space [string index $part 0]]} {
            append out {\s+}
        } else {
            append out [regsub -all {[][\\.^$*+?(){}|]} $part {\\&}]
        }
    }
    return $out
}
::sh::doc parse {turn lines of text into rows} {
    parse text template
    parse text -x pattern name...
} {
    Reads each line of the text against a template and returns a row for each
    line that fits. In the template, a word in braces is a column to capture;
    everything else must match as written (any amount of blank space counts
    as a match for blank space). Lines that do not fit are skipped.

    For more control give a regular expression with -x and name its (...)
    groups, in order, after it.
} {
    parse "alice is 30\nbob is 25" {{who} is {age}}
    parse [cat access.log] -x {^(\S+) .* "(\w+) } ip verb
    where [parse [cat people.txt] {{name} {age}}] {$age > 28}
}

proc from-json {text} {
    package require json
    if {[catch {json::json2dict $text} r]} { ::sh::fail from-json "not valid JSON: $r" }
    switch -- [string index [string trimleft $text] 0] {
        "\{" { return [::sh::vd $r] }
        "\[" { return [::sh::v $r] }
    }
    return $r
}
::sh::doc from-json {read JSON text into lists and records} {
    from-json text
} {
    Reads JSON. A JSON object becomes a record, an array becomes a list (so
    an array of objects is rows), strings and numbers are themselves, and
    true, false and null come through as those three words. Text that is not
    JSON is an error that says where Tcl gave up.
} {
    from-json {[{"name":"ann","age":31},{"name":"bo","age":25}]}
    where [from-json [cat people.json]] {$age > 28}
}

proc ::sh::jstr {s} {
    return "\"[string map [list "\\" "\\\\" "\"" "\\\"" "\n" "\\n" "\t" "\\t" "\r" "\\r"] $s]\""
}
proc ::sh::jval {v} {
    if {$v in {true false null}} { return $v }
    if {[regexp {^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?$} $v]} { return $v }
    ::sh::jstr $v
}
proc to-json {value args} {
    lassign [::sh::flags to-json $args {l d}] o rest
    if {[llength $rest]} { ::sh::fail to-json "unexpected \"[lindex $rest 0]\"" }
    if {[dict exists $o l]} {
        return "\[[join [lmap x $value {::sh::jval $x}] ,]\]"
    }
    if {[dict exists $o d]} {
        return "\{[join [lmap {k v} $value {string cat [::sh::jstr $k] : [::sh::jval $v]}] ,]\}"
    }
    set items {}
    set i 0
    foreach row $value {
        incr i
        ::sh::isrec to-json $row $i
        lappend items "  \{[join [lmap {k v} $row {string cat [::sh::jstr $k] : [::sh::jval $v]}] ,]\}"
    }
    if {![llength $items]} { return "\[\]" }
    return "\[\n[join $items ",\n"]\n\]"
}
::sh::doc to-json {write rows, lists or records as JSON} {
    to-json rows
    to-json list -l
    to-json record -d
} {
    Writes JSON text. By default the value is rows and becomes an array of
    objects, one per line. -l writes a list as an array, -d writes a single
    record as an object.

    Tcl values do not remember their type, so a value that looks like a
    number is written as a number, the words true, false and null are written
    bare, and everything else is a string. Values nested inside a row are
    written as strings.
} {
    to-json [files]
    to-json {1 2 3} -l
    to-json {name ann age 31} -d
}

proc from-csv {text} {
    set recs {}
    set rec {}
    set f ""
    set inq 0
    set n [string length $text]
    for {set i 0} {$i < $n} {incr i} {
        set c [string index $text $i]
        if {$inq} {
            if {$c eq "\""} {
                if {[string index $text [expr {$i + 1}]] eq "\""} { append f "\""; incr i } else { set inq 0 }
            } else {
                append f $c
            }
        } elseif {$c eq "\""} {
            set inq 1
        } elseif {$c eq ","} {
            lappend rec $f
            set f ""
        } elseif {$c eq "\n"} {
            lappend rec $f
            lappend recs $rec
            set rec {}
            set f ""
        } elseif {$c ne "\r"} {
            append f $c
        }
    }
    if {$inq} { ::sh::fail from-csv "a quoted field is never closed" }
    if {$f ne "" || [llength $rec]} { lappend rec $f; lappend recs $rec }
    if {![llength $recs]} { return "" }
    set head [lindex $recs 0]
    set out {}
    set ln 1
    foreach r [lrange $recs 1 end] {
        incr ln
        if {[llength $r] == 1 && [lindex $r 0] eq ""} continue
        if {[llength $r] != [llength $head]} {
            ::sh::fail from-csv "line $ln has [llength $r] field[expr {[llength $r] == 1 ? "" : "s"}] but the header has [llength $head]"
        }
        lappend out [dict create {*}[concat {*}[lmap h $head v $r {list $h $v}]]]
    }
    ::sh::v $out
}
::sh::doc from-csv {read CSV text into rows} {
    from-csv text
} {
    Reads comma-separated text whose first line names the columns, and returns
    rows. Fields may be quoted with " to hold commas, quotes (doubled) or
    newlines. Blank lines are skipped. A line with the wrong number of fields
    is an error naming the line.
} {
    from-csv "name,age\nann,31\nbo,25"
    sort-by [from-csv [cat data.csv]] age -n
}

proc ::sh::csvq {s} {
    if {[regexp {[",\n\r]} $s]} { return "\"[string map {\" \"\"} $s]\"" }
    return $s
}
proc to-csv {rows args} {
    set i 0
    foreach row $rows { incr i; ::sh::isrec to-csv $row $i }
    set cols [expr {[llength $args] ? $args : [columns $rows]}]
    if {![llength $rows]} { return "" }
    set out [list [join [lmap c $cols {::sh::csvq $c}] ,]]
    foreach row $rows {
        lappend out [join [lmap c $cols {::sh::csvq [dict getdef $row $c ""]}] ,]
    }
    ::sh::tj $out
}
::sh::doc to-csv {write rows as CSV text} {
    to-csv rows ?column...?
} {
    Writes rows as comma-separated text with a header line. Name columns to
    write only those, in that order. Fields that need it are quoted.
} {
    to-csv [files] name size
    save [to-csv $rows] out.csv
}

# ----------------------------------------------------------- == 5. fluidity
# Small tools that make composing things cheap, borrowed from Plan 9's rc.

::sh::group "Composing and exploring"

proc |> {value args} {
    foreach stage $args {
        set value [uplevel 1 [linsert $stage 1 $value]]
    }
    return $value
}
::sh::doc |> {feed a value through a chain of steps} {
    |> value step...
} {
    Passes a value through a series of steps. Each step is a command written
    as a list, WITHOUT its first argument: the value so far is put there
    for you. The result of one step becomes the value for the next, and the
    last result is the answer. It saves you from writing temporary variables
    or nesting brackets many levels deep.

    These three do exactly the same thing:
      |> $rows {where {$age > 18}} {sort-by age -n} {pluck name}
      pluck [sort-by [where $rows {$age > 18}] age -n] name
      set r [where $rows {$age > 18}]; set r [sort-by $r age -n]; pluck $r name

    Use whichever reads best. See: help pipes
} {
    |> [files] {where {$size > 99}} {sort-by size -n -r} {pluck name} {first 3}
    |> [cat log.txt] {grep error} {sort} {uniq -c}
}

proc ~ {value args} {
    foreach p $args {
        if {[string match $p $value]} { return 1 }
    }
    return 0
}
::sh::doc ~ {does a value match a wildcard pattern?} {
    ~ value pattern...
} {
    Returns 1 if the value matches at least one of the patterns, else 0. It
    answers instead of failing, so it fits in if. Patterns are wildcards:
    * for any run of letters, ? for one letter, [abc] for a choice. See: help
    wildcards.
} {
    ~ report.txt *.txt
    ~ b a b c
    if {[~ $name .* *~]} { echo "a hidden or backup name" }
}

proc ^ {args} {
    if {![llength $args]} { return "" }
    set acc [lindex $args 0]
    foreach b [lrange $args 1 end] {
        set na [llength $acc]
        set nb [llength $b]
        if {!$na || !$nb} { ::sh::fail ^ "cannot join with an empty list" }
        if {$na == 1} {
            set acc [lmap y $b {string cat [lindex $acc 0] $y}]
        } elseif {$nb == 1} {
            set acc [lmap x $acc {string cat $x [lindex $b 0]}]
        } elseif {$na == $nb} {
            set acc [lmap x $acc y $b {string cat $x $y}]
        } else {
            ::sh::fail ^ "lists of $na and $nb items cannot be joined (they must match, or one must have a single item)"
        }
    }
    ::sh::v $acc
}
::sh::doc ^ {glue words together, item by item} {
    ^ list list...
} {
    Joins the items of lists end to end. A single item is glued to every item
    of the other list; two lists of the same length are glued pairwise.
    Any other lengths are an error. (This is rc's ^ operator.)
} {
    ^ {report-} {1 2 3} .txt
    ^ {a b c} {1 2 3}
    each [^ {jan feb} .log] f {cat $f}
}

proc same {a b} { expr {[list {*}$a] eq [list {*}$b]} }
::sh::doc same {are two lists the same, item by item?} {
    same a b
} {
    Returns 1 if two lists have the same items in the same order, 0 if not.
    Lists that print differently, such as the one-per-line lists the commands
    here return and the same list on one line, are the same list; a plain
    string comparison (eq) would call them different.
} {
    same [ls] {a.txt b.txt}
    same {a b} "a\nb"
}

# ---- looking at commands

proc ::sh::kind {name} {
    if {[interp alias {} $name] ne ""} { return alias }
    if {[llength [info procs ::$name]]} { return proc }
    if {[llength [info commands ::$name]]} {
        return builtin
    }
    return ""
}

proc whatis {name} {
    switch [::sh::kind $name] {
        proc {
            set args [lmap a [info args $name] {
                if {[info default $name $a d]} { list $a $d } else { set a }
            }]
            return "proc $name [list $args] \{[info body $name]\}"
        }
        alias { return "alias $name [interp alias {} $name]" }
        builtin { return "$name is a Tcl built-in command (written in C; no source to show)" }
    }
    set s [::sh::findscript $name]
    if {$s ne ""} { return "$name is a script: $s" }
    ::sh::fail whatis "$name: not found"
}
::sh::doc whatis {show how a command is defined} {
    whatis command
} {
    Shows a command in the form you could type to define it again. For
    commands written in Tcl (almost everything in this shell) that is their
    real source, so you can read how they work, copy one and change it. For
    aliases it shows what they stand for; for built-in Tcl commands it just
    says so.
} {
    whatis ls
    whatis walk
}

proc which {cmd} {
    switch [::sh::kind $cmd] {
        proc    { return "$cmd: proc" }
        alias   { return "$cmd: alias for [interp alias {} $cmd]" }
        builtin { return "$cmd: built-in" }
    }
    set s [::sh::findscript $cmd]
    if {$s ne ""} { return "$cmd: script $s" }
    ::sh::fail which "no such command: $cmd"
}
::sh::doc which {what kind of command is this?} {
    which command
} {
    Says whether the name is a proc (a command written in Tcl), an alias, a
    built-in Tcl command, or a script that the shell would run from your bin
    place. It is an error if there is no such command.
} {
    which ls
    which cd
}

proc alias {name args} {
    if {![llength $args]} { ::sh::fail alias "usage: alias name command ?arg...?" }
    interp alias {} $name {} {*}$args
    return
}
::sh::doc alias {give a command a shorter name or preset arguments} {
    alias name command ?arg...?
} {
    Makes name stand for the command and the arguments given. When you type
    the name and more arguments, they follow the preset ones. An existing
    command of the same name is replaced. Aliases last until the page is
    reloaded.
} {
    alias l ls -a
    alias txt walk -f
    alias e echo
}

proc unalias {name} {
    if {[interp alias {} $name] eq ""} { ::sh::fail unalias "$name is not an alias" }
    interp alias {} $name {}
    return
}
::sh::doc unalias {remove an alias} {
    unalias name
} {
    Removes an alias made with alias. It is an error if the name is not an
    alias (real commands cannot be removed this way).
} {
    unalias l
}

# ---- scripts are commands
# A file called NAME or NAME.tcl in the bin place (/home/shell/bin), or a
# path to one (./NAME.tcl), runs when you type its name.  Inside, $argv is
# the list of arguments and $argc their number.

proc ::sh::findscript {name} {
    if {[string first / $name] >= 0} {
        set cands [list $name $name.tcl]
    } else {
        set cands [list [file join $::sh::bin $name] [file join $::sh::bin $name.tcl]]
    }
    foreach c $cands {
        set r [::sh::real $c]
        if {[file isfile $r]} { return $r }
    }
    return ""
}

proc ::sh::runscript {path args} {
    if {[catch {
        apply {{__f argv} {
            set argv0 $__f
            set argc [llength $argv]
            source $__f
        }} $path $args
    } r opts]} {
        return -code error -errorcode [dict get $opts -errorcode] \
            -errorinfo "$r\n    (while running the script $path)" $r
    }
    return $r
}

# Unix words people type, and what to use here instead.
set ::sh::unix {
    find  "walk lists everything below a place; filter it with grep or where"
    man   "use help (and apropos to search)"
    less  "use cat, head or tail"
    more  "use cat, head or tail"
    rmdir "rm removes empty places"
    awk   "see fields, parse and where"
    cut   "see fields"
    xargs "see each"
    tac   "lreverse reverses a list of lines: unlines [lreverse [lines $text]]"
    cmp   "see diff"
    ps    "there are no processes here"
    kill  "there are no processes here"
    top   "there are no processes here"
    curl  "there is no network here"
    wget  "there is no network here"
    ssh   "there is no network here"
    chmod "there are no permissions here"
    chown "there are no permissions here"
    sleep "use: after milliseconds"
    printf "use: format"
    export "use: set"
    history "there is no history list; use the up arrow if the window has one"
    sh    "this already is the shell"
    bash  "this already is the shell"
}

if {![llength [info commands ::sh::tcl_unknown]]} { rename unknown ::sh::tcl_unknown }
proc unknown {args} {
    set name [lindex $args 0]
    set s [::sh::findscript $name]
    if {$s ne ""} { return [::sh::runscript $s {*}[lrange $args 1 end]] }
    if {![catch {uplevel 1 [list ::sh::tcl_unknown {*}$args]} r opts]} { return $r }
    if {![string match {invalid command name*} $r]} { return -options $opts $r }
    if {[dict exists $::sh::unix $name]} {
        append r "\n  note: [dict get $::sh::unix $name]"
    } elseif {[string match */* $name]} {
        append r "\n  note: files are not run by path; use: source $name   (or put NAME.tcl in /bin and type NAME)"
    } else {
        append r "\n  note: try: help, or: apropos $name"
    }
    return -code error -errorcode [dict get $opts -errorcode] -errorinfo $r $r
}

# ---------------------------------------------------------------- == 6. topics
# The guides.  Plain lines are paragraphs (they are re-flowed to the window
# width when shown); lines indented by two or more spaces are examples and
# are shown exactly as written.  Assume the reader has never used a
# command line.  Keep braces balanced.

::sh::topic start "your first ten minutes" {
    This window is a conversation. You type one line, press Enter, and the
    shell does what the line says and shows you the answer. Then it waits for
    the next line. The text before your cursor (like /docs %) is the prompt:
    it shows where you are.

    A line is a COMMAND followed by the things it should work on, called its
    arguments, all separated by spaces. In "echo hello world", echo is the
    command and hello and world are its arguments. That is the whole grammar.

    Everything is stored in places and things. A place (also called a
    directory or folder) holds other places and things. A thing is a file:
    some text, or data. You are always standing in one place; the prompt
    names it. Everything in this window lives in memory and vanishes when
    you reload the page.

    Try these, one at a time:

      echo hello world
      ls
      mkdir notes
      cd notes
      save "buy milk" todo.txt
      save "call Sam" todo.txt -a
      cat todo.txt
      ls
      cd ..

    ls shows what is in the place you are in. save writes text into a thing.
    cat reads it back. cd moves you to another place; two dots mean the place
    above this one.

    Two kinds of command exist here. Some print on the screen as they go
    (echo). Most just give back a RESULT, and the shell shows the result when
    the line finishes. A result can be used by another command: put the
    first command in square brackets and the shell replaces the brackets with
    its result. For example, wc [cat todo.txt] counts the lines, words and letters
    of the thing you just made. That one idea, results flowing into other commands, is
    what the rest of the help builds on.

    Next: help values (what a result can be), help pipes (chaining), help
    errors (when something goes wrong), and help (the list of everything).
}

::sh::topic values "what a command gives back: text, lists, records, tables" {
    Every command gives back a value. A value is just some text, but the
    shell reads that text in different ways depending on what you do with
    it. Five shapes matter.

    A WORD or NUMBER is a single thing: hello, 42, 3.5.

    A LIST is several values in order, like a shopping list. ls gives a list
    of names. In Tcl you write a list by putting items between spaces: a b c.
    An item that itself contains a space goes in braces: {my file} other.
    The commands in this shell print a list with one item on each line so it
    is easy to read, but it is still a list: you can count it with llength
    and take items from it with lindex.

    TEXT is lines of writing, such as the content of a thing. Text is the one
    shape where the line breaks are the structure. Lines are separated by
    newlines, and the very last line has no newline after it. cat gives text.
    grep, sort, uniq, head, tail, sed and the other text commands take text
    and give text back. lines turns text into a list of its lines; unlines
    turns a list back into text.

    A RECORD is a labelled bundle of values: name ann age 31. Labels and
    values alternate, label first. Tcl calls it a dict. dict get $r age
    finds a value by its label.

    ROWS (a table) are a list of records, one per row, where each record has
    the same labels, the columns. files gives rows: one record per name with
    its type and size. where, select, sort-by, pluck and the others work on
    rows. table draws rows as a tidy grid for reading.

    Why bother? Because each command can trust what it receives. A command
    that wants a list never has to guess where one item ends and the next
    begins; it never re-splits text. To change shape on purpose use lines,
    unlines, parse (text to rows), pluck (rows to a list) and table (rows to
    readable text).

    Two practical notes. First, comparing: the one-per-line display and the
    same list on one line are the same list, but eq compares the characters
    and calls them different. Use same a b to compare lists. Second, numbers
    are just words that look like numbers, so sum, max and sort -n read them
    as numbers when asked.
}

::sh::topic pipes "chaining commands so each one uses the last one's result" {
    Real work usually takes several small steps. To get the names of the five
    largest things in a place you must list them, keep the sizeable ones,
    order them by size, take the names and keep five. Each step is a separate
    command that does one job, and the
    result of one step is the input of the next. Joining steps like this is
    called composition, or building a pipeline (a pipe carries a result from
    one step to the next).

    This shell does it with ordinary Tcl, in three ways. They give the same
    answer; choose the one that reads best.

    1. Put one command inside another with square brackets. The inner command
    runs first and its result is handed to the outer one. Read from the
    inside out:

      first [pluck [sort-by [where [files] {$size > 99}] size -n -r] name] 5

    2. Keep the result in a variable and work on it step by step. This is best
    for long chains because each line does one thing and you can look at any
    intermediate result:

      set r [files]
      set r [where $r {$size > 99}]
      set r [sort-by $r size -n -r]
      set r [pluck $r name]
      first $r 5

    3. Use |>, which hands the value along for you. Each step is a command
    without its first argument:

      |> [files] {where {$size > 99}} {sort-by size -n -r} {pluck name} {first 5}

    This works because every command here takes the thing to work on as its
    FIRST argument. That is a rule of the whole shell, and it is what lets
    the pieces fit together like this.

    Text chains the same way:

      uniq [sort [grep [cat log.txt] error]] -c

    reads log.txt, keeps lines with "error", sorts them, and counts repeats.

    There is no limit to chaining and no setup. Unlike other systems, nothing
    is started or connected: each command is just called with a value and
    returns a value. So a result can be used twice, kept, or compared to
    another:

      diff [cat old.txt] [cat new.txt]
}

::sh::topic redirection "sending a result to a file instead of the screen" {
    Normally the shell shows a command's result on the screen and forgets it.
    To keep it, send it into a thing (a file). This is called redirection:
    the result is redirected from the screen to a file. Going the other way,
    a file's content is read into a command with cat.

    Here these are ordinary commands:

      save text file        write text into a file (replace what was there)
      save text file -a     add text to the end of a file
      cat file              read a file as text
      tee text file         save the text and also hand it on

    For example, to keep a sorted list of names:

      save [sort [cat names.txt]] sorted.txt

    The line says: read names.txt, sort it, save the result in sorted.txt.
    To add today's line to a log, then look at the end:

      save "backup finished" log.txt -a
      tail [cat log.txt] 5

    save adds a newline at the end of the file, so files end the usual way;
    cat removes it again, so you never see an extra blank line.

    Printing is different from returning. echo prints right away and gives
    back nothing, so there is nothing for save to keep: save [echo hi] f
    would save empty text. To keep words in a file, give save the words
    themselves: save "hi there" f. If a command you wrote prints with puts,
    its output cannot be saved; have it return the text instead.

    Lists and rows are saved with unlines, to-csv or to-json, which turn
    them into text first:

      save [unlines [ls]] listing.txt
      save [to-csv [files]] files.csv
}

::sh::topic wildcards "patterns that stand for many names" {
    Typing every file name is tedious. A wildcard is a pattern that matches
    many names at once. The characters with special meaning are:

      *       any run of letters, including none
      ?       exactly one letter
      [abc]   one letter out of those listed
      [a-f]   one letter in a range

    So *.txt means every name ending in .txt; report-?.md matches report-1.md
    and report-b.md but not report-10.md; img[0-9]* matches names starting with
    img and a digit. Names that start with a dot are hidden and wildcards do
    not match them unless the pattern starts with a dot.

    The file commands (cat, rm, cp, mv, ls, walk, hash, search ...) understand
    wildcards in the names you give them: cat *.txt, rm *.tmp, cp *.jpg /backup.
    expand shows what a pattern turns into:

      expand *.txt

    If a pattern matches nothing, it is left exactly as typed. The command then
    fails saying that no such file exists, naming your pattern, so you can see
    the typo. (Many systems quietly give an empty list instead.)

    ~ asks "does this value match this pattern?" and answers 1 or 0:

      if {[~ $name *.txt]} { echo "a text file" }

    A pattern is not the same as a regular expression. Wildcards are for
    names; regular expressions (help regexp) are for searching inside text.
}

::sh::topic regexp "describing text to search for" {
    grep, sed, search, extract, parse -x, sort -k and uniq -x all take a
    PATTERN, written as a regular expression. A pattern describes a kind of
    text. The simplest pattern is an ordinary word, which matches itself:
    grep $text error keeps the lines containing "error".

    Characters with special meaning:

      .       any one character
      *       the thing before it, zero or more times
      +       the thing before it, one or more times
      ?       the thing before it, zero or one time
      ^       the start of the line
      $       the end of the line
      [abc]   one of these characters; [a-z] a range; [^abc] anything else
      \d      a digit        \w  a letter, digit or underscore
      \s      a blank        \S  anything but a blank
      (...)   a group: treated as one unit, and remembered
      a|b     either a or b
      \.      a real dot (a backslash removes the special meaning)

    Examples:

      ^2026         lines starting with 2026
      \.txt$        lines ending in .txt
      [0-9]+        a number
      user=(\w+)    the word after "user="; the group holds just the word
      colou?r       color or colour

    When a pattern has a group, the tools that pick out a part (extract,
    sort -k, uniq -x) use what the first group matched. Without a group they
    use the whole match.

    In sed, the first and last / are separators, so a / inside the pattern
    is written \/ or you pick another separator: s|/usr|/opt|.

    Put patterns in braces so Tcl leaves the backslashes and dollar signs
    alone: grep $text {^\d+$}. These are Tcl regular expressions, which are a
    little richer than the classic kind. If a pattern is wrong the command
    says so and quotes what Tcl complained about.
}

::sh::topic errors "reading an error message, and what to do" {
    When a command cannot do what you asked it stops and prints an ERROR,
    then the shell waits for the next line as if nothing happened. Nothing is
    broken and nothing is lost. An error is the command telling you why it
    could not continue.

    Messages from this shell's commands have a fixed shape. The first line is:

      command: what went wrong

    for example:

      cat: notes.txt: no such file or directory
      where: row 3 has no column "age"
      head: "abc" is not a count (a whole number, 0 or more)
      rm: scratch: place is not empty (use rm -r to remove it and everything in it)

    Read the first line first. It names the command and the problem, often
    with the exact fix. The lines after it ("while executing", "invoked from
    within") show where in the chain of commands it happened, innermost
    first. They matter mostly when you write your own commands.

    Common causes: a name that is misspelt or in another place (check pwd and
    ls); a column name that is not in the rows (check columns); a flag the
    command does not have (help command lists them); a missing brace or
    quote, which Tcl reports as "missing close-brace" because it read to the
    end of the line looking for the closing one.

    An error is a value too, so you can handle it in a script:

      if {[catch {cat maybe.txt} text]} {
          echo "no such file, using nothing"
          set text ""
      }

    catch runs the command; it answers 1 if it failed and puts the message
    (or the result) in the variable. try offers the same with more control.

    Some commands answer instead of failing when "nothing found" is a normal
    outcome: grep gives empty text, apropos gives a message, ~ gives 0.
    Failing is kept for real problems such as a missing file or bad input.
}

::sh::topic quoting "how a line is read: spaces, braces, quotes, brackets" {
    The shell reads a line by cutting it into words at spaces. The first word
    is the command; the rest are its arguments. Four characters change how
    words are cut and read.

    Double quotes group words, but still allow substitution:

      echo "two words"        one argument: two words
      echo "total: $n"        $n is replaced by its value

    Braces group words and change nothing inside: no substitution at all.

      echo {total: $n}        prints total: $n exactly
      where $rows {$age > 18} the test is passed as written; where itself
                              decides when to read $age

    That is why scripts and tests go in braces: you hand them over unread, to
    be run later, once per row or item. Braces nest, and must balance.

    A dollar sign puts a variable's value in the line: set x 5, then echo $x.

    Square brackets run a command in the middle of a line and put its result
    there: echo [pwd]. They nest from the inside out.

    A backslash removes the special meaning of the next character: \$ is a
    plain dollar sign, \[ a plain bracket, and a backslash at the end of a
    line continues it on the next one.

    The rule of thumb: braces for scripts and patterns; quotes for text with
    variables in it; brackets for results. If a pattern or test misbehaves,
    check it is in braces. A line with an opening brace that is never closed makes the
    shell complain about a missing close-brace; count your braces.
}

::sh::topic lists "working with lists and records using plain Tcl" {
    Some jobs need no special command because Tcl already has one. For people
    who know other data tools, here is where the familiar operations live.

    Lists:
      llength $l            how many items
      lindex $l 0           the first item (items count from 0); end is last
      lrange $l 1 3         items 1 to 3
      lsort $l              sort; -integer, -real, -decreasing, -unique
      lreverse $l           reverse
      lsearch -all $l pat   positions matching a wildcard pattern
      lappend l x           add an item to the list in variable l
      linsert $l 1 x        put x at position 1
      lmap x $l {script}    the general each; each is the list-first version
      concat $a $b          join two lists
      lseq 1 to 10          numbers; seq does the same
      join $l ", "          make one string with a separator
      split $s ,            make a list by cutting a string at a character

    Records:
      dict create k v ...   build one
      dict get $r k         read; dict getdef $r k default if it may be missing
      dict set r k v        change (the variable r)
      dict exists $r k      test
      dict keys $r          labels;  dict values $r  values
      dict merge $a $b      combine, the second wins
      dict remove $r k      drop a label
      dict map {k v} $r {script}   transform every pair
      dict for {k v} $r {script}   do something for every pair
      dict size $r          how many pairs

    Choices and loops:
      if {$x > 3} {...} else {...}
      foreach x $l {...}        do something for every item
      for {set i 0} {$i < 3} {incr i} {...}
      switch $x a {...} b {...} default {...}
      expr {$a + $b}            arithmetic; calc does the same without braces

    The commands in this shell fill the gaps: each, keep, reduce, first,
    last, skip, sum, where, select, group-by, sort-by and so on, all with
    the thing to work on as the first argument.
}

::sh::topic tables "a worked example with rows" {
    Rows are the shape for anything with columns: names and ages, files and
    sizes, lines of a log. Here is a short session.

    Make some rows by hand, or read them from CSV or JSON text:

      set people [from-csv "name,age,city\nann,31,paris\nbo,25,rome\ncy,40,paris"]

    Look at them as a table:

      table $people

    Keep adults over 28, order by age, show two columns:

      table [sort-by [where $people {$age > 28}] age -n] name age

    The same with |>, one step per line of thought:

      |> $people {where {$age > 28}} {sort-by age -n} {pluck name}

    Count by city:

      tally [pluck $people city]

    Add a column worked out from the others:

      set-col $people next {expr {$age + 1}}

    Group, then count each group:

      dict map {city members} [group-by $people city] {llength $members}

    Rows can also come from the file system:

      table [sort-by [files] size -n -r] name type size

    or from text with a pattern:

      parse [cat access.log] {{ip} - {user} {verb} {path}}

    And rows can go out again as text, to save:

      save [to-csv $people] people.csv
      save [to-json $people] people.json

    In a where or set-col script the row's columns are variables, and so are
    the variables you made yourself, so tests can mix both:

      set limit 30
      where $people {$age > $limit}
}

::sh::topic scripts "making your own commands" {
    The simplest new command is a proc: a name, the names of its arguments,
    and what to do.

      proc greet {who} { echo "hello, $who" }
      greet world

    A proc stays until you reload the page. whatis greet shows it back; copy
    that into a file to keep it.

    An alias is a shorter name for an existing command with some arguments
    already filled in:

      alias l ls -a

    To keep a program in a file, write the commands into a thing whose name
    ends in .tcl and put it in the place /bin (that is, /home/shell/bin):

      mkdir /bin
      save {echo "you gave me $argc words: $argv"} /bin/say.tcl
      say one two

    Typing the name runs the file. Inside it, argv is the list of arguments
    and argc how many there are. A name containing a slash, such as
    /bin/say.tcl, also runs. The last value in the script, or a return, is its
    result, so a script can be used inside brackets like any command.

    Because memory is cleared on reload, keep a copy of anything valuable
    elsewhere (see help vfs).
}

::sh::topic shell "what the shell is" {
    The shell is the Tcl language itself, with a set of commands written in
    Tcl added on top. There is no separate "shell language": a line you type
    is Tcl. That means you get variables, loops, procs and all the rest for
    free, and every command here is a proc you can read with whatis.

    The commands are sorted in help by what they work on: places and things
    (files), text, lists, rows. Read help start for a first tour and help
    values for how the pieces fit.

    The prompt shows where you are. The whole window shares one Tcl
    interpreter, so a variable or proc made in one window exists in all.
    clear empties the window; it is handled by the window, not by Tcl, so it
    only works as a line on its own.
}

::sh::topic tcl "the Tcl you need" {
    Tcl has a tiny grammar (see help quoting) and a large library of commands.
    The ones you will use most:

      set x 5                 make a variable;  $x reads it
      puts text               print a line (echo is friendlier)
      expr {$x * 2}           arithmetic and comparisons
      if {...} {...} else {...}
      foreach item $list {...}
      while {...} {...}
      proc name {args} {body} make a command
      string length $s        also: toupper tolower trim map match range
      string match *.txt $s   wildcard test
      regexp {pattern} $s     regular expression test (help regexp)
      regsub -all {a} $s b    replace
      format "%05d" 42        build text from numbers
      list a b c              build a list;  llength lindex lappend lsort
      dict create k v         build a record
      catch {...} msg         run something that may fail (help errors)
      source file.tcl         run a file of commands
      info commands           list every command;  info vars lists variables
      after 1000              wait one second

    Each command prints its own usage if you call it wrongly, for instance
    typing string alone. This Tcl is version 9.1 with the standard library;
    there is no clock formatting (use date), no processes and no network.
}

::sh::topic tcllib "the extra library modules" {
    The bundled tcllib 2.0 adds ready-made modules. Load one with package
    require, then use its commands:

      json        read and write JSON   (from-json and to-json use it)
      cmdline     parse command-line style options
      fileutil    more file helpers
      uri         take web addresses apart
      ncgi, html  web form and page helpers
      javascript  small JavaScript text helpers

    Example: package require uri; uri::split http://example.com/a?b=1
}

::sh::topic vfs "where files live" {
    All files live in the browser's memory, in a virtual file system. It
    behaves like a normal one but nothing is written to your disk, and it is
    emptied when the page is reloaded or closed. Make copies of anything you
    want to keep outside this window.

    The top of the shell, shown as /, is the real place /home/shell. A name
    beginning with / is counted from there, so the prompt's /docs can be
    typed as /docs. If nothing of that name exists in the shell, the same
    name is looked for in the real file system, which is how /usr/lib (where
    Tcl itself and its libraries live) can be explored with ls and cat.
    Leave those alone: the shell refuses to remove them, and changing them
    can break Tcl for every window.

    Terms used here: a place is a directory, a thing is a file, a name is a
    path. Names are case sensitive. There are no owners, permissions or
    links in practice.
}

::sh::topic limits "what this environment cannot do" {
    The shell runs inside a web page, so some things do not exist:

    No processes. Nothing can be started, stopped or listed; exec fails.
    No network. Nothing can be fetched or sent.
    No clock formatting. clock seconds works and date shows UTC time, but
    time zones and clock format do not.
    No waiting for events. after 1000 pauses; after 1000 {script} never runs
    the script, and vwait hangs.
    No interrupt. A loop that never ends freezes the page and only closing it
    helps (and loses the files). Be careful with loops such as while 1.
    No persistence. Memory is cleared on reload.
    One shared interpreter. All windows see the same variables and files.

    exit does nothing except report; the interpreter stays up.
}

# ------------------------------------------------------------------- boot
# Start in the shell's own top, not the system root (only if we are still at
# the system root, so opening another window does not move anyone).
if {[pwd] eq "/"} { cd }
