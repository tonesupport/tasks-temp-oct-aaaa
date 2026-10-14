# tama.tcl - a TOML reader that keeps its source locations
#
# Port of lib/tama/tama.lua, targeting Tcl 9. Same document shape, same diagnostics,
# same deliberate choices: a dot inside a table header is a literal character,
# not a path separator, because the bracket name is a record identifier in both
# hail and tide.
#
# The one structural difference from the Lua original is value typing. Lua's
# type() distinguishes string, number, boolean and table for free; Tcl values
# are strings, and rho's wrong-type diagnostics depend on telling them apart.
# So every parsed value is carried as a two-element list {type data}, where type
# is one of string, number, boolean, array, inline-table. Callers go through
# [tama::valtype] and [tama::valdata] rather than reading the pair directly.
#
# Document shape (a dict):
#   source_path              path the text came from, or {}
#   root                     dict: kv, key_line
#   tables                   dict: name -> dict of kv, key_line, header_line
#   table_list               table names in the order they appear
#   table_norm               dict: normalized name -> list of raw names
#   __source                 the original text
#
# Jim has no "package require Tcl" -- there is no package of that name -- so
# this file declares no package requirements at all and is loaded with source.


namespace eval tama {}

# ----------------------------------------------------------------- values

proc tama::mkval {type data} { list $type $data }
proc tama::valtype {v} { lindex $v 0 }
proc tama::valdata {v} { lindex $v 1 }

# Is this value one of the three TOML scalar types? rho refuses to substitute
# anything else, and that refusal is the diagnostic users actually see.
proc tama::is_scalar {v} {
    expr {[lindex $v 0] in {string number boolean}}
}

# The text a scalar contributes when substituted into a document. Lua's
# tostring() on a boolean gives "true"/"false" and on a number gives the
# integer form when the value is integral, which is what this reproduces.
proc tama::valtext {v} {
    lassign $v type data
    switch -- $type {
        boolean { return [expr {$data ? "true" : "false"}] }
        number  { return [tama::numtext $data] }
        default { return $data }
    }
}

# Reproduce Lua's tostring() for numbers: integers print bare, floats print
# through %.14g and keep a trailing .0 when they land on a whole number.
proc tama::numtext {n} {
    if {[tama::is_integer_text $n]} { return $n }
    set s [format %.14g $n]
    if {![string match {*[.eE]*} $s] && ![string match {*inf*} $s] && ![string match {*nan*} $s]} {
        append s ".0"
    }
    return $s
}

# ----------------------------------------------------------------- lexing

# Strip a trailing # comment, respecting single and double quoted spans. A
# backslash before a closing double quote keeps the span open, matching the
# original's escape handling.
proc tama::strip_comments {line} {
    set out {}
    set in_s 0
    set in_d 0
    set n [string length $line]
    for {set i 0} {$i < $n} {incr i} {
        set c [string index $line $i]
        if {$c eq "'" && !$in_d} {
            set in_s [expr {!$in_s}]
            append out $c
        } elseif {$c eq "\"" && !$in_s} {
            if {$in_d} {
                if {[string index $line [expr {$i - 1}]] ne "\\"} { set in_d 0 }
            } else {
                set in_d 1
            }
            append out $c
        } elseif {$c eq "#" && !$in_s && !$in_d} {
            break
        } else {
            append out $c
        }
    }
    return $out
}

# Does this text parse as a number the way Lua's tonumber would, given the
# original also required a leading [-+]?digits guard? The guard is what stops
# "0x10" and "1e5"-style strings from being silently retyped, so it is kept.
proc tama::looks_numeric {v} {
    if {![regexp {^[-+]?[0-9]+\.?[0-9]*} $v]} { return 0 }
    if {[tama::is_integer_text $v]} { return 1 }
    if {[string is double -strict $v]} { return 1 }
    return 0
}

# Tested by pattern rather than by [string is integer], which Jim rejects for
# "entier" and which is width-limited for "integer". Every created/modified
# stamp in the corpus is a ten-digit YYMMDDHHMM value, well past 32 bits, so a
# width-limited test would silently retype the most common numeric field here.
proc tama::is_integer_text {v} {
    regexp {^[-+]?[0-9]+$} $v
}

proc tama::parse_scalar_value {v} {
    set v [string trim $v]

    if {$v eq "true"}  { return [tama::mkval boolean 1] }
    if {$v eq "false"} { return [tama::mkval boolean 0] }

    if {[tama::looks_numeric $v]} {
        return [tama::mkval number $v]
    }

    set first [string index $v 0]
    set last  [string index $v end]
    set len   [string length $v]

    if {$first eq "'" && $last eq "'" && $len >= 2} {
        return [tama::mkval string [string range $v 1 end-1]]
    }

    if {$first eq "\"" && $last eq "\"" && $len >= 2} {
        set inner [string range $v 1 end-1]
        # Applied one at a time, in this order, because the Lua original is a
        # chain of five separate gsub calls and a single simultaneous
        # [string map] is not equivalent to it. Input \\n reaches rule 2 as \\,
        # becomes \, and is then seen by rule 3 as \n and becomes a newline;
        # a simultaneous map would consume the pair at rule 2 and leave a
        # literal n behind. The corpus contains that exact sequence.
        # A lone backslash cannot be written as a brace-quoted word in Tcl: a
        # backslash immediately before the closing brace stops that brace from
        # counting as the closer, so the word never terminates. That is true
        # inside comments too, since brace counting happens before comments are
        # recognised -- writing the offending sequence in this very comment
        # broke the enclosing proc. So the two characters are named here and
        # composed, rather than written as literals at each use.
        set bs "\\"
        set dq "\""
        set inner [string map [list $bs$dq $dq] $inner]
        set inner [string map [list $bs$bs $bs] $inner]
        set inner [string map [list ${bs}n "\n"] $inner]
        set inner [string map [list ${bs}r "\r"] $inner]
        set inner [string map [list ${bs}t "\t"] $inner]
        return [tama::mkval string $inner]
    }

    if {$first eq "\["} {
        if {$last eq "\]"} {
            return [tama::mkval array [tama::parse_array_body [string trim [string range $v 1 end-1]]]]
        }
    }

    if {$first eq "\{"} {
        return [tama::mkval inline-table $v]
    }

    return [tama::mkval string $v]
}

# Split an array body on top-level commas, respecting nesting and quotes, then
# parse each element. Returns a list of tagged values.
proc tama::parse_array_body {inner} {
    if {$inner eq ""} { return {} }
    set arr {}
    set cur {}
    set in_s 0
    set in_d 0
    set depth 0
    set n [string length $inner]
    for {set i 0} {$i < $n} {incr i} {
        set c [string index $inner $i]
        if {$c eq "\[" && !$in_s && !$in_d} {
            incr depth
            append cur $c
        } elseif {$c eq "\]" && !$in_s && !$in_d} {
            set depth [expr {$depth > 0 ? $depth - 1 : 0}]
            append cur $c
        } elseif {$c eq "'" && !$in_d} {
            set in_s [expr {!$in_s}]
            append cur $c
        } elseif {$c eq "\"" && !$in_s} {
            if {$in_d} {
                if {[string index $inner [expr {$i - 1}]] ne "\\"} { set in_d 0 }
            } else {
                set in_d 1
            }
            append cur $c
        } elseif {$c eq "," && !$in_s && !$in_d && $depth == 0} {
            set item [string trim $cur]
            if {$item ne ""} { lappend arr [tama::parse_scalar_value $item] }
            set cur {}
        } else {
            append cur $c
        }
    }
    set item [string trim $cur]
    if {$item ne ""} { lappend arr [tama::parse_scalar_value $item] }
    return $arr
}

# ----------------------------------------------------------------- parsing

proc tama::normalize_table_name {s} {
    set t [string trim $s]
    set a [string index $t 0]
    set b [string index $t end]
    if {[string length $t] >= 2 && (($a eq "\"" && $b eq "\"") || ($a eq "'" && $b eq "'"))} {
        set t [string range $t 1 end-1]
    }
    return [string trim $t]
}

# Returns {ok doc} or {error message}. The caller distinguishes on the first
# element; there is no exception path, because rho reports parse failures as
# values rather than raising.
proc tama::parse {text {source_path {}}} {
    set doc [dict create \
        source_path $source_path \
        root [dict create kv {} key_line {}] \
        tables {} \
        table_list {} \
        table_norm {} \
        __source $text]

    # `current` names where scalars land: either the literal string "root" or
    # the raw name of a table. Kept as a name rather than a reference because
    # Tcl dicts are values, so the write has to go back through dict set.
    set current root

    set mode {}
    set multi_key {}
    set multi_delim {}
    set multi_buf {}
    set multi_start 0
    set arr_key {}
    set arr_buf {}
    set arr_depth 0
    set arr_in_s 0
    set arr_in_d 0
    set arr_start 0

    set src [expr {$source_path eq "" ? "<toml>" : $source_path}]
    set pending ""
    set line_no 0

    foreach raw [split $text "\n"] {
        incr line_no
        set line $raw
        if {$pending ne ""} {
            set line "$pending\n$line"
            set pending ""
        }

        if {$mode eq "multi"} {
            set pos [string first $multi_delim $line]
            if {$pos >= 0} {
                lappend multi_buf [string range $line 0 [expr {$pos - 1}]]
                set value [join $multi_buf "\n"]
                set doc [tama::SetKV $doc $current $multi_key [tama::mkval string $value] $multi_start]
                # The remainder has to be sliced before multi_delim is cleared,
                # since the slice is measured with its length.
                set rest [string range $line [expr {$pos + [string length $multi_delim]}] end]
                set multi_key {} ; set multi_delim {} ; set multi_buf {} ; set mode {}
                if {[string trim $rest] ne ""} { set pending $rest }
            } else {
                lappend multi_buf $line
            }
            continue
        }

        if {$mode eq "array"} {
            set s2 [string trim [tama::strip_comments $line]]
            if {$s2 ne ""} {
                lappend arr_buf $s2
                lassign [tama::ScanBrackets $s2 $arr_depth $arr_in_s $arr_in_d] arr_depth arr_in_s arr_in_d
                if {$arr_depth <= 0} {
                    set value [tama::parse_scalar_value [join $arr_buf "\n"]]
                    set doc [tama::SetKV $doc $current $arr_key $value $arr_start]
                    set arr_key {} ; set arr_buf {} ; set arr_depth 0
                    set arr_in_s 0 ; set arr_in_d 0 ; set mode {}
                }
            }
            continue
        }

        set s [string trim [tama::strip_comments $line]]
        if {$s eq ""} { continue }

        if {[regexp {^\[(.*)\]$} $s -> header]} {
            set header [string trim $header]
            if {$header eq ""} {
                return [list error "TOML parse error in $src:$line_no: empty table name"]
            }
            if {![dict exists $doc tables $header]} {
                dict set doc tables $header [dict create kv {} key_line {} header_line $line_no]
                dict lappend doc table_list $header
                set norm [tama::normalize_table_name $header]
                # NOT dict lappend: that command takes a single key, not a
                # path, so "dict lappend doc table_norm $norm $header" appends
                # both words to table_norm itself. It reads back correctly for
                # a name seen once and silently loses the second raw name when
                # two headers normalise together -- which is exactly the case
                # ambiguous_table exists to report.
                set norm_list {}
                if {[dict exists $doc table_norm $norm]} {
                    set norm_list [dict get $doc table_norm $norm]
                }
                lappend norm_list $header
                dict set doc table_norm $norm $norm_list
            }
            set current $header
            continue
        }

        if {[regexp {^([^=]+)=(.*)$} $s -> k v]} {
            set k [string trim $k]
            set v [string trim $v]
            if {$k eq ""} {
                return [list error "TOML parse error in $src:$line_no: empty key"]
            }

            set head3 [string range $v 0 2]
            if {$head3 eq "'''" || $head3 eq "\"\"\""} {
                set mode multi
                set multi_key $k
                set multi_delim $head3
                set multi_start $line_no
                set rest [string range $v 3 end]
                set pos [string first $multi_delim $rest]
                if {$pos >= 0} {
                    set value [string range $rest 0 [expr {$pos - 1}]]
                    set doc [tama::SetKV $doc $current $k [tama::mkval string $value] $line_no]
                    set multi_key {} ; set multi_delim {} ; set multi_buf {} ; set mode {}
                    set tail [string range $rest [expr {$pos + 3}] end]
                    if {[string trim $tail] ne ""} { set pending $tail }
                } else {
                    set multi_buf [list $rest]
                }
                continue
            }

            if {[string index $v 0] eq "\[" && ![regexp {\]$} $v]} {
                set mode array
                set arr_key $k
                set arr_buf [list $v]
                set arr_depth 0 ; set arr_in_s 0 ; set arr_in_d 0
                set arr_start $line_no
                lassign [tama::ScanBrackets $v $arr_depth $arr_in_s $arr_in_d] arr_depth arr_in_s arr_in_d
                if {$arr_depth <= 0} {
                    set value [tama::parse_scalar_value [join $arr_buf "\n"]]
                    set doc [tama::SetKV $doc $current $arr_key $value $arr_start]
                    set arr_key {} ; set arr_buf {} ; set arr_depth 0 ; set mode {}
                }
                continue
            }

            set doc [tama::SetKV $doc $current $k [tama::parse_scalar_value $v] $line_no]
        }
        # any other line kind is ignored, as in the original
    }

    if {$mode eq "multi"} {
        return [list error "TOML parse error in $src:$multi_start: unterminated multiline string for key: $multi_key"]
    }
    if {$mode eq "array"} {
        return [list error "TOML parse error in $src:$arr_start: unterminated array for key: $arr_key"]
    }

    return [list ok $doc]
}

# Track bracket depth and quote state across a line of a multi-line array.
proc tama::ScanBrackets {s depth in_s in_d} {
    set n [string length $s]
    for {set i 0} {$i < $n} {incr i} {
        set c [string index $s $i]
        if {$c eq "'" && !$in_d} {
            set in_s [expr {!$in_s}]
        } elseif {$c eq "\"" && !$in_s} {
            if {$in_d} {
                if {[string index $s [expr {$i - 1}]] ne "\\"} { set in_d 0 }
            } else {
                set in_d 1
            }
        } elseif {!$in_s && !$in_d} {
            if {$c eq "\["} { incr depth } elseif {$c eq "\]"} { incr depth -1 }
        }
    }
    return [list $depth $in_s $in_d]
}

proc tama::SetKV {doc where key value line_no} {
    if {$where eq "root"} {
        dict set doc root kv $key $value
        dict set doc root key_line $key $line_no
    } else {
        dict set doc tables $where kv $key $value
        dict set doc tables $where key_line $key $line_no
    }
    return $doc
}

# See cli::oserr. tama is used standalone as well as as a library, so it cannot
# rely on cli.tcl having been sourced and carries its own copy.
proc tama::oserr {path msg} {
    if {[lindex $::errorCode 0] eq "POSIX" && [llength $::errorCode] >= 3} {
        set m [lindex $::errorCode 2]
        return "$path: [string toupper [string index $m 0]][string range $m 1 end]"
    }
    return $msg
}

proc tama::parse_file {path} {
    if {[catch {open $path rb} fh]} { return [list error [tama::oserr $path $fh]] }
    set data [read $fh]
    close $fh
    return [tama::parse $data $path]
}

# ----------------------------------------------------------------- lookups

# Look up `key` inside the named table.
# Returns {ok value info} or {error info}, where info is a dict carrying `kind`
# and whatever context that kind implies.
proc tama::get {doc table_name key} {
    set norm [tama::normalize_table_name $table_name]
    set raw_list {}
    if {[dict exists $doc table_norm $norm]} {
        set raw_list [dict get $doc table_norm $norm]
    }

    if {[llength $raw_list] > 1} {
        return [list error [dict create kind ambiguous_table norm $norm raw $raw_list]]
    }
    if {[llength $raw_list] == 0} {
        return [list error [dict create kind missing_table norm $norm]]
    }

    set raw [lindex $raw_list 0]
    if {![dict exists $doc tables $raw]} {
        return [list error [dict create kind missing_table norm $norm]]
    }
    set tbl [dict get $doc tables $raw]
    if {![dict exists $tbl kv $key]} {
        return [list error [dict create kind missing_key table_raw $raw table_norm $norm]]
    }

    set val [dict get $tbl kv $key]
    set line {}
    if {[dict exists $tbl key_line $key]} { set line [dict get $tbl key_line $key] }

    if {![tama::is_scalar $val]} {
        return [list error [dict create kind wrong_type table_raw $raw table_norm $norm \
            val $val line $line]]
    }
    return [list ok $val [dict create kind ok table_raw $raw table_norm $norm line $line]]
}

# Look up `key` anywhere -- root scalars and every table. Unambiguous hits only:
# a key present in more than one place is an error rather than a silent pick,
# since which one you got would otherwise depend on iteration order.
proc tama::find {doc key} {
    set scalars {}
    set nonscalars {}

    if {[dict exists $doc root kv $key]} {
        set v [dict get $doc root kv $key]
        set line {}
        if {[dict exists $doc root key_line $key]} { set line [dict get $doc root key_line $key] }
        set rec [dict create loc root val $v line $line]
        if {[tama::is_scalar $v]} { lappend scalars $rec } else { lappend nonscalars $rec }
    }

    foreach raw [dict get $doc table_list] {
        set tbl [dict get $doc tables $raw]
        if {![dict exists $tbl kv $key]} { continue }
        set v [dict get $tbl kv $key]
        set line {}
        if {[dict exists $tbl key_line $key]} { set line [dict get $tbl key_line $key] }
        set rec [dict create loc $raw val $v line $line]
        if {[tama::is_scalar $v]} { lappend scalars $rec } else { lappend nonscalars $rec }
    }

    if {[llength $scalars] == 1} {
        set hit [lindex $scalars 0]
        return [list ok [dict get $hit val] $hit]
    }
    if {[llength $scalars] == 0 && [llength $nonscalars] > 0} {
        if {[llength $nonscalars] == 1} {
            return [list error [dict create kind wrong_type match [lindex $nonscalars 0]]]
        }
        return [list error [dict create kind wrong_type_ambig matches $nonscalars]]
    }
    if {[llength $scalars] == 0} {
        return [list error [dict create kind missing_key]]
    }
    return [list error [dict create kind ambiguous_key matches $scalars]]
}

# Table names in source order.
proc tama::tables {doc} { dict get $doc table_list }

# Strip a TOML multiline string of the blank first and last lines that writing
# it readably introduces.
proc tama::trim_block {v} {
    set lines [split $v "\n"]
    if {[llength $lines] == 0} { return $v }

    set drop_first [regexp {^[ \t\r]*$} [lindex $lines 0]]
    set drop_last  [regexp {^[ \t\r]*$} [lindex $lines end]]
    if {!$drop_first && !$drop_last} { return $v }

    set a 0
    set b [expr {[llength $lines] - 1}]
    if {$drop_first} { incr a }
    if {$drop_last}  { incr b -1 }
    if {$a > $b} { return "" }
    return [join [lrange $lines $a $b] "\n"]
}

proc tama::type_name {v} { tama::valtype $v }

# Discard the locations and return a plain nested dict.
proc tama::flatten {doc} {
    set out {}
    dict for {k v} [dict get $doc root kv] { dict set out $k $v }
    dict for {name t} [dict get $doc tables] {
        set into {}
        dict for {k v} [dict get $t kv] { dict set into $k $v }
        dict set out $name $into
    }
    return $out
}
