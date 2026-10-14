# cli.tcl - the argument-parsing mechanism shared by the tclport tools
#
# This is the extraction 260902-004 argued for: pull out the mechanism, leave
# the model alone. What is genuinely identical across rho, tide, salt, kv and
# hail is the machinery -- walking argv, recognising a long flag, taking the
# next word as its value, honouring "--", collecting positionals, and deciding
# whether this file is the program or a library. What is NOT identical, and is
# deliberately not unified here, is the diagnostics: rho exits 2 on a usage
# error and prints "Error: ... / Use -h for help", tide exits 1 and prefixes
# "tide:", salt exits 1 and prints a usage line, kv prints a usage block. Those
# are each tool's contract with its callers, and this port has to reproduce them
# byte for byte.
#
# So cli::parse never prints and never exits. It returns a typed failure and the
# caller words it. That is the only split that lets one parser serve four tools
# whose error text must stay different.

# Jim treats strings as bytes; Tcl 9 treats them as characters and re-encodes on
# output. These tools read their inputs with "rb" and are expected to reproduce
# them byte for byte, so under Tcl the standard channels must be put into byte
# mode or every non-ASCII character is mangled on the way out. Harmless under
# Jim, which is why it is unconditional rather than version-guarded.
catch {fconfigure stdout -translation binary}
catch {fconfigure stderr -translation binary}

namespace eval cli {}

# Jim provides readdir as a builtin; standard Tcl does not. Defined only when
# absent, so these files continue to run unmodified under jimsh as well as
# under Tcl 9. Jim's readdir yields every entry except . and .., dotfiles
# included, which plain [glob *] would miss.
if {[info commands readdir] eq ""} {
    proc readdir {dir} {
        set out {}
        foreach e [glob -nocomplain -tails -directory $dir -- * .*] {
            if {$e eq "." || $e eq ".."} continue
            lappend out $e
        }
        return $out
    }
}


proc cli::eprintln {args} { puts stderr [join $args " "] }

# Jim and Tcl word POSIX failures differently. Jim -- like the Lua originals --
# says "path: No such file or directory"; Tcl says
# couldn't open "path": no such file or directory. These tools' diagnostics are
# a specified part of their behaviour and the differential tests compare stderr
# byte for byte, so normalise to the Jim/Lua wording. Call this immediately
# after the failing catch, while ::errorCode still describes it.
proc cli::oserr {path msg} {
    if {[lindex $::errorCode 0] eq "POSIX" && [llength $::errorCode] >= 3} {
        set m [lindex $::errorCode 2]
        return "$path: [string toupper [string index $m 0]][string range $m 1 end]"
    }
    return $msg
}


# Is the file that called this the program being run, rather than a library
# being sourced? Every tool needs this so its tests can source it.
#
# argv0 is "-" when jimsh reads the program from stdin, and normalising that
# raises rather than returning a path, so the cheap tail comparison comes first.
proc cli::running_as_program {script} {
    if {![info exists ::argv0]} { return 0 }
    if {[file tail $::argv0] ne [file tail $script]} { return 0 }
    if {[catch {file normalize $::argv0} a]} { return 0 }
    if {[catch {file normalize $script} b]} { return 0 }
    return [expr {$a eq $b}]
}

# Parse argv against a flag spec.
#
#   spec is a list of {names kind key} triples:
#     names  a list of accepted spellings, e.g. {-h --help}
#     kind   flag   -- no value; sets key to 1, or to the optional fourth
#                      element of the triple when one is given, which is how
#                      a --lenient that clears the flag --strict sets is
#                      expressed without a second mechanism
#            option -- takes the next word as its value
#            repeat -- takes the next word and appends it to a list
#     key    the dict key to write
#
# Options:
#   -defaults DICT   starting values for the flags dict
#   -strictdash BOOL if true (the default) any unrecognised argument beginning
#                    with "-" is an unknown flag; if false only "--"-prefixed
#                    arguments are, and a bare "-x" is a positional. tide wants
#                    the loose form, rho the strict one.
#   -stopmarker BOOL if true (the default) a bare "--" ends flag parsing and
#                    everything after it is positional.
#
# Returns one of:
#   {ok FLAGSDICT POSITIONALS}
#   {error unknown-flag FLAG}
#   {error missing-value FLAG}
proc cli::parse {argv spec args} {
    set defaults {}
    set strictdash 1
    set stopmarker 1
    foreach {k v} $args {
        switch -- $k {
            -defaults   { set defaults $v }
            -strictdash { set strictdash $v }
            -stopmarker { set stopmarker $v }
            default     { error "cli::parse: unknown option $k" }
        }
    }

    # Flatten the spec into name -> {kind key} for a single lookup per argument.
    set table [dict create]
    foreach triple $spec {
        lassign $triple names kind key value
        if {[llength $triple] < 4} { set value 1 }
        foreach n $names { dict set table $n [list $kind $key $value] }
    }

    set flags $defaults
    set positionals {}
    set i 0
    set n [llength $argv]
    set stopped 0

    while {$i < $n} {
        set a [lindex $argv $i]

        if {!$stopped && $stopmarker && $a eq "--"} {
            set stopped 1
            incr i
            continue
        }

        if {!$stopped && [dict exists $table $a]} {
            lassign [dict get $table $a] kind key value
            if {$kind eq "flag"} {
                dict set flags $key $value
                incr i
                continue
            }
            if {[expr {$i + 1}] >= $n} { return [list error missing-value $a] }
            set v [lindex $argv [expr {$i + 1}]]
            if {$kind eq "repeat"} {
                set cur {}
                if {[dict exists $flags $key]} { set cur [dict get $flags $key] }
                lappend cur $v
                dict set flags $key $cur
            } else {
                dict set flags $key $v
            }
            incr i 2
            continue
        }

        if {!$stopped} {
            set looks_like_flag [expr {$strictdash
                ? [string index $a 0] eq "-"
                : [string range $a 0 1] eq "--"}]
            if {$looks_like_flag} { return [list error unknown-flag $a] }
        }

        lappend positionals $a
        incr i
    }

    return [list ok $flags $positionals]
}
