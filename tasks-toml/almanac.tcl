#!/workspace/system/deps/tcl
# almanac.tcl — tasks.toml CLI (labor-os monolith)
#
# Spec: /workspace/system/spec/task-spec.md v0.3.1
# Building blocks: cli.tcl + tama.tcl (this scripts/ tree; tama wraps lib/tosu).
# Runtime: zipkit Tcl 9.0.4 at system/deps/tcl (shebang). Also works under tclsh 8.6+.
#
# --file defaults to /workspace/system/work/tasks.toml
# Verbs: init add ls set done today ready blockers validate doctor filter
# Mutations (a1em): TOML emitter, temp+rename, single-quote preference.
# Query filters (a1qg): ls/today/ready/filter accept key=val, has=key, missing=key.
# Listings: lines (default) or --toml; never JSON.
# Timestamps: local YYMMDDhhmm (America/Los_Angeles on this box).

set ALMANAC_DIR [file dirname [file normalize [info script]]]
source [file join $ALMANAC_DIR cli.tcl]
source [file join $ALMANAC_DIR tama.tcl]

# cli.tcl forces binary channels; almanac is character-oriented (titles/notes).
catch {fconfigure stdout -encoding utf-8 -translation auto}
catch {fconfigure stderr -encoding utf-8 -translation auto}

namespace eval almanac {
    variable VERSION 0.3.0
    variable DEFAULT_FILE {/workspace/system/work/tasks.toml}
    variable TZ {:America/Los_Angeles}
    variable STATUS_ORDER {urgent now progress today later deferred sched done}
    variable STATUS_ENUM {urgent now progress today later deferred sched done}
}

proc almanac::die {msg} {
    puts stderr "almanac: $msg"
    exit 1
}

proc almanac::usage {{code 2}} {
    puts stderr {usage: almanac.tcl [--file PATH] [--toml] <verb> [args]

verbs:
  init                 ensure --file exists (skeleton if missing; no-op if present)
  add key=val ...      create task (title= or task= alias required;
                       status defaults to later; notes optional — empty omitted;
                       title= wins over task= when equal, else conflict error;
                       optional id=/domain=/…)
  ls ?filters?         list tasks (filters below); lines or --toml
  filter ?filters?     alias of ls (explicit filter surface)
  set ID key=val ...   update fields on existing id
  done ID              mark done (sets completed+updated)
  today ?filters?      agenda: urgent/now/progress/today + sched-for-local-today (+filters); skips root
  ready ?filters?      open tasks whose blockers are all done (or none) (+filters)
  blockers ?id?        list blockers for id, or all blocked open tasks
  validate             schema checks against v0.3.2 (report; non-zero if errors)
  doctor               health: file/parse/schema + verb smoke + bake/hook checks

filters (ls / filter / today / ready):
  STATUS               bare status token (urgent|now|progress|today|later|deferred|sched|done)
  key=val              exact match (any key); arrays: comma vals must all be members
  has=key              key present (numbers incl. 0; non-empty strings/arrays)
  missing=key          key absent or empty
  datetime=today       datetime equals local today (Ddd Mmm DD YY)

examples:
  add title='File receipt'
  add task='File receipt' domain=FIN
  add title='…' status=today domain=CTP notes='body'
  ls status=sched
  ls sched has=reminder
  ls domain=almanac project=almanac
  ls has=datetime has=signaling-command
  ls missing=reminder status=today
  today domain=almanac
  --toml ls has=reminder

options:
  --file PATH          tasks.toml (default: /workspace/system/work/tasks.toml)
  --toml               emit listing as TOML table snippets instead of lines
  -h / --help          this help

local now: YYMMDDhhmm via almanac::now (operator timezone).}
    exit $code
}

proc almanac::now {} {
    variable TZ
    return [clock format [clock seconds] -format %y%m%d%H%M -timezone $TZ]
}

# Spec datetime: Ddd Mmm DD YY with single spaces (e.g. 'Tue Sep 29 26').
proc almanac::today_datetime {} {
    variable TZ
    set raw [clock format [clock seconds] -format {%a %b %e %y} -timezone $TZ]
    return [almanac::norm_ws $raw]
}

proc almanac::norm_ws {s} {
    return [regsub -all {[ \t]+} [string trim $s] { }]
}

proc almanac::status_rank {st} {
    variable STATUS_ORDER
    set i [lsearch -exact $STATUS_ORDER $st]
    if {$i < 0} { return 99 }
    return $i
}

# Load monolith; returns doc dict (unwraps tama {ok doc} / {error msg}).
# tama::parse_file opens rb without UTF-8 decode; we decode so titles/notes
# with non-ASCII (arrows, etc.) stay characters under Tcl 9.
proc almanac::load {path} {
    if {![file isfile $path]} {
        almanac::die "no such file: $path"
    }
    if {[catch {open $path rb} fh]} {
        almanac::die "cannot read: $path ($fh)"
    }
    set bytes [read $fh]
    close $fh
    set text [encoding convertfrom utf-8 $bytes]
    set r [tama::parse $text $path]
    if {[lindex $r 0] eq "error"} {
        almanac::die "parse failed: [lindex $r 1]"
    }
    if {[lindex $r 0] eq "ok"} {
        return [lindex $r 1]
    }
    return $r
}

# tama quirk: a table literally named [root] lands keys in doc root kv
# (SetKV treats where eq "root" as the document root). Merge both views.
proc almanac::task_kv {doc id} {
    set kv [dict create]
    if {[dict exists $doc tables $id kv]} {
        set kv [dict get $doc tables $id kv]
    }
    if {$id eq "root" && [dict exists $doc root kv]} {
        dict for {k v} [dict get $doc root kv] {
            dict set kv $k $v
        }
    }
    return $kv
}

proc almanac::scalar {kv key {default {}}} {
    if {![dict exists $kv $key]} { return $default }
    set v [dict get $kv $key]
    if {[catch {tama::valtype $v} ty]} { return $default }
    if {$ty ni {string number boolean}} { return $default }
    return [tama::valtext $v]
}

proc almanac::array_texts {kv key} {
    set out {}
    if {![dict exists $kv $key]} { return $out }
    set v [dict get $kv $key]
    if {[catch {tama::valtype $v} ty]} { return $out }
    if {$ty ne "array"} { return $out }
    foreach item [tama::valdata $v] {
        if {[tama::valtype $item] in {string number boolean}} {
            lappend out [tama::valtext $item]
        }
    }
    return $out
}

# Task ids in file order (exclude tasks.spine meta table).
proc almanac::task_ids {doc} {
    set out {}
    foreach id [dict get $doc table_list] {
        if {$id eq "tasks.spine"} continue
        # Skip non-task-looking tables (must have status or be root).
        set kv [almanac::task_kv $doc $id]
        if {$id ne "root" && ![dict exists $kv status] && ![dict exists $kv title]} {
            continue
        }
        lappend out $id
    }
    return $out
}

proc almanac::task_status {doc id} {
    return [almanac::scalar [almanac::task_kv $doc $id] status]
}

proc almanac::task_title {doc id} {
    return [almanac::scalar [almanac::task_kv $doc $id] title $id]
}

proc almanac::task_datetime {doc id} {
    return [almanac::norm_ws [almanac::scalar [almanac::task_kv $doc $id] datetime]]
}

proc almanac::is_done {doc id} {
    expr {[almanac::task_status $doc $id] eq "done"}
}

# Ready = not done, and every blocker id is done (missing blocker id => still blocked).
proc almanac::is_ready {doc id} {
    set st [almanac::task_status $doc $id]
    if {$st eq "" || $st eq "done"} { return 0 }
    set kv [almanac::task_kv $doc $id]
    foreach b [almanac::array_texts $kv blockers] {
        if {![almanac::is_done $doc $b]} { return 0 }
    }
    return 1
}

proc almanac::is_blocked {doc id} {
    set st [almanac::task_status $doc $id]
    if {$st eq "" || $st eq "done"} { return 0 }
    set kv [almanac::task_kv $doc $id]
    set bl [almanac::array_texts $kv blockers]
    if {[llength $bl] == 0} { return 0 }
    foreach b $bl {
        if {![almanac::is_done $doc $b]} { return 1 }
    }
    return 0
}

proc almanac::sched_is_today {doc id} {
    set st [almanac::task_status $doc $id]
    if {$st ne "sched" && $st ne "today"} { return 0 }
    set dt [almanac::task_datetime $doc $id]
    if {$dt eq ""} { return [expr {$st eq "today"}] }
    return [expr {$dt eq [almanac::today_datetime]}]
}

# --- query filters (a1qg) ---

proc almanac::empty_filters {} {
    return [dict create equals [dict create] has {} missing {}]
}

# Presence: key exists; numbers/booleans count even at 0/false; strings/arrays need non-empty.
proc almanac::key_present {kv key} {
    if {![dict exists $kv $key]} { return 0 }
    set v [dict get $kv $key]
    if {[catch {tama::valtype $v} ty]} { return 0 }
    if {$ty eq "array"} {
        return [expr {[llength [tama::valdata $v]] > 0}]
    }
    if {$ty eq "number" || $ty eq "boolean"} { return 1 }
    if {$ty eq "string"} {
        return [expr {[string trim [tama::valtext $v]] ne ""}]
    }
    return 1
}

# Equality: scalars compare text; arrays require each comma-separated want as a member.
# Special: datetime=today → local today_datetime.
proc almanac::key_matches {kv key want} {
    if {$key eq "datetime" && $want eq "today"} {
        set want [almanac::today_datetime]
    }
    if {![dict exists $kv $key]} { return 0 }
    if {[almanac::is_array_key $key]} {
        set items [almanac::array_texts $kv $key]
        set parts {}
        foreach part [split $want ","] {
            set p [string trim $part]
            if {$p ne ""} { lappend parts $p }
        }
        if {[llength $parts] == 0} {
            return [expr {[llength $items] == 0}]
        }
        foreach p $parts {
            if {$p ni $items} { return 0 }
        }
        return 1
    }
    set got [almanac::scalar $kv $key]
    if {$key eq "datetime"} {
        set got [almanac::norm_ws $got]
        set want [almanac::norm_ws $want]
    }
    return [expr {$got eq $want}]
}

# Parse filter arglist: optional bare STATUS, then key=val / has=key / missing=key.
proc almanac::parse_filters {arglist} {
    variable STATUS_ENUM
    set equals [dict create]
    set has {}
    set missing {}
    set i 0
    set n [llength $arglist]
    if {$n > 0} {
        set first [lindex $arglist 0]
        if {[string first "=" $first] < 0} {
            if {$first in $STATUS_ENUM} {
                dict set equals status $first
                incr i
            } else {
                almanac::die "filter: unknown bare token '$first' (use status=... or key=val / has=key)"
            }
        }
    }
    for {} {$i < $n} {incr i} {
        set a [lindex $arglist $i]
        set eq [string first "=" $a]
        if {$eq < 1} {
            almanac::die "filter: expected key=value, has=key, or missing=key; got: $a"
        }
        set k [string range $a 0 [expr {$eq - 1}]]
        set v [string range $a [expr {$eq + 1}] end]
        if {$k eq "has"} {
            if {$v eq ""} { almanac::die "filter: has= needs a key name" }
            lappend has $v
        } elseif {$k eq "missing"} {
            if {$v eq ""} { almanac::die "filter: missing= needs a key name" }
            lappend missing $v
        } else {
            set v [string map [list \\n "\n" \\t "\t"] $v]
            dict set equals $k $v
        }
    }
    return [dict create equals $equals has $has missing $missing]
}

proc almanac::task_matches_filters {doc id filters} {
    set kv [almanac::task_kv $doc $id]
    dict for {k v} [dict get $filters equals] {
        if {![almanac::key_matches $kv $k $v]} { return 0 }
    }
    foreach k [dict get $filters has] {
        if {![almanac::key_present $kv $k]} { return 0 }
    }
    foreach k [dict get $filters missing] {
        if {[almanac::key_present $kv $k]} { return 0 }
    }
    return 1
}

proc almanac::filter_ids {doc ids filters} {
    set out {}
    foreach id $ids {
        if {[almanac::task_matches_filters $doc $id $filters]} {
            lappend out $id
        }
    }
    return $out
}

proc almanac::sort_ids {doc ids} {
    set decorated {}
    foreach id $ids {
        set st [almanac::task_status $doc $id]
        lappend decorated [list [almanac::status_rank $st] $id]
    }
    set decorated [lsort -index 0 -integer $decorated]
    set out {}
    foreach row $decorated { lappend out [lindex $row 1] }
    return $out
}

proc almanac::emit_line {id st title} {
    puts [format "%-4s  %-8s  %s" $id $st $title]
}

proc almanac::emit_toml {doc id} {
    set kv [almanac::task_kv $doc $id]
    puts "\[$id\]"
    foreach key {title status domain project datetime time duration reminder signaling-command created updated completed} {
        set v [almanac::scalar $kv $key]
        if {$v eq ""} continue
        if {$key in {created updated completed duration reminder}} {
            puts "$key = $v"
        } else {
            puts "$key = [almanac::quote_string $v]"
        }
    }
    set bl [almanac::array_texts $kv blockers]
    if {[llength $bl] > 0} {
        set parts {}
        foreach b $bl { lappend parts "'$b'" }
        puts "blockers = \[[join $parts {, }]\]"
    }
    set ca [almanac::array_texts $kv coordinating-agents]
    if {[llength $ca] > 0} {
        set parts {}
        foreach a $ca { lappend parts "'$a'" }
        puts "coordinating-agents = \[[join $parts {, }]\]"
    }
    set tags [almanac::array_texts $kv tags]
    if {[llength $tags] > 0} {
        set parts {}
        foreach t $tags { lappend parts "'$t'" }
        puts "tags = \[[join $parts {, }]\]"
    }
    puts ""
}

proc almanac::emit_list {doc ids toml} {
    foreach id [almanac::sort_ids $doc $ids] {
        set st [almanac::task_status $doc $id]
        set title [almanac::task_title $doc $id]
        if {$toml} {
            almanac::emit_toml $doc $id
        } else {
            almanac::emit_line $id $st $title
        }
    }
}

# --- verbs ---

proc almanac::cmd_init {path} {
    if {[file isfile $path]} {
        puts "ok exists $path"
        return
    }
    set dir [file dirname $path]
    if {$dir ne "" && $dir ne "." && ![file isdirectory $dir]} {
        file mkdir $dir
    }
    set now [almanac::now]
    set fh [open $path w]
    puts $fh "# tasks.toml — tasks-toml-spec v0.3.1 (almanac init)"
    puts $fh "\[root\]"
    puts $fh "title = 'Root'"
    puts $fh "status = 'later'"
    puts $fh "notes = '''"
    puts $fh "Workroot bucket."
    puts $fh "'''"
    puts $fh "created = $now"
    puts $fh "updated = $now"
    puts $fh "tags = \['task'\]"
    puts $fh ""
    puts $fh "\[tasks.spine\]"
    puts $fh "order = \["
    puts $fh "  'root', 'Root', '',"
    puts $fh "\]"
    close $fh
    puts "ok created $path"
}

proc almanac::cmd_ls {doc toml args} {
    set filters [almanac::parse_filters $args]
    set ids [almanac::filter_ids $doc [almanac::task_ids $doc] $filters]
    almanac::emit_list $doc $ids $toml
}

proc almanac::cmd_today {doc toml args} {
    set today_dt [almanac::today_datetime]
    set ids {}
    foreach id [almanac::task_ids $doc] {
        if {$id eq "root"} { continue }
        set st [almanac::task_status $doc $id]
        if {$st in {urgent now progress today}} {
            lappend ids $id
            continue
        }
        if {$st eq "sched"} {
            set dt [almanac::task_datetime $doc $id]
            if {$dt eq $today_dt} { lappend ids $id }
        }
    }
    set filters [almanac::parse_filters $args]
    set ids [almanac::filter_ids $doc $ids $filters]
    almanac::emit_list $doc $ids $toml
}

proc almanac::cmd_ready {doc toml args} {
    set ids {}
    foreach id [almanac::task_ids $doc] {
        if {[almanac::is_ready $doc $id]} { lappend ids $id }
    }
    set filters [almanac::parse_filters $args]
    set ids [almanac::filter_ids $doc $ids $filters]
    almanac::emit_list $doc $ids $toml
}

proc almanac::cmd_blockers {doc args toml} {
    if {[llength $args] >= 1} {
        set id [lindex $args 0]
        set kv [almanac::task_kv $doc $id]
        if {$kv eq {} && $id ni [almanac::task_ids $doc]} {
            almanac::die "unknown id: $id"
        }
        set bl [almanac::array_texts $kv blockers]
        if {$toml} {
            puts "\[$id\]"
            set parts {}
            foreach b $bl { lappend parts "'$b'" }
            puts "blockers = \[[join $parts {, }]\]"
            puts "blocked = [expr {[almanac::is_blocked $doc $id] ? {true} : {false}}]"
        } else {
            if {[llength $bl] == 0} {
                puts "$id  (no blockers)"
            } else {
                foreach b $bl {
                    set bst [almanac::task_status $doc $b]
                    if {$bst eq ""} { set bst "?" }
                    puts [format "%-4s  blocker %-4s  (%s)" $id $b $bst]
                }
            }
        }
        return
    }
    # All open blocked tasks.
    set ids {}
    foreach id [almanac::task_ids $doc] {
        if {[almanac::is_blocked $doc $id]} { lappend ids $id }
    }
    if {$toml} {
        foreach id [almanac::sort_ids $doc $ids] {
            set bl [almanac::array_texts [almanac::task_kv $doc $id] blockers]
            puts "\[$id\]"
            set parts {}
            foreach b $bl { lappend parts "'$b'" }
            puts "blockers = \[[join $parts {, }]\]"
            puts ""
        }
    } else {
        foreach id [almanac::sort_ids $doc $ids] {
            set bl [almanac::array_texts [almanac::task_kv $doc $id] blockers]
            set pending {}
            foreach b $bl {
                if {![almanac::is_done $doc $b]} { lappend pending $b }
            }
            puts [format "%-4s  %-8s  blockers=%s" $id [almanac::task_status $doc $id] [join $pending {,}]]
        }
    }
}

# Shared schema walk. Prints error/warn lines; returns {errors warnings ntasks}.
proc almanac::validate_report {doc path {quiet 0}} {
    variable STATUS_ENUM
    set errors 0
    set warnings 0
    set ids [almanac::task_ids $doc]
    set idset [dict create]
    foreach id $ids { dict set idset $id 1 }

    foreach id $ids {
        if {![regexp {^[a-z0-9]{4}$} $id] && $id ne "root"} {
            # Allow dotted meta like tasks.spine already excluded; other names warn.
            if {[string match {tasks.*} $id]} continue
            if {!$quiet} { puts "error $id: id must be \[a-z0-9\]{4} (or root)" }
            incr errors
        }
        set kv [almanac::task_kv $doc $id]
        foreach req {title status created updated} {
            if {[almanac::scalar $kv $req] eq "" && ![dict exists $kv $req]} {
                if {!$quiet} { puts "error $id: missing required key '$req'" }
                incr errors
            }
        }
        set st [almanac::task_status $doc $id]
        if {$st ne "" && $st ni $STATUS_ENUM} {
            if {!$quiet} { puts "error $id: invalid status '$st'" }
            incr errors
        }
        if {$st eq "done" && [almanac::scalar $kv completed] eq ""} {
            if {!$quiet} { puts "error $id: status=done requires completed" }
            incr errors
        }
        if {$st eq "sched" && [almanac::scalar $kv datetime] eq ""} {
            if {!$quiet} { puts "error $id: status=sched requires datetime" }
            incr errors
        }
        if {[dict exists $kv duration]} {
            if {$st ni {now done sched}} {
                if {!$quiet} { puts "error $id: duration only allowed when status is now, done, or sched" }
                incr errors
            }
        }
        set tags [almanac::array_texts $kv tags]
        if {[llength $tags] == 0} {
            if {!$quiet} { puts "error $id: tags required (must include 'task')" }
            incr errors
        } else {
            if {"tasks" in $tags} {
                if {!$quiet} { puts "error $id: tags must use singular 'task' (not 'tasks')" }
                incr errors
            }
            if {"task" ni $tags} {
                if {!$quiet} { puts "error $id: tags must include 'task'" }
                incr errors
            }
        }
        foreach b [almanac::array_texts $kv blockers] {
            if {![dict exists $idset $b]} {
                if {!$quiet} { puts "warn  $id: blocker '$b' not in file" }
                incr warnings
            }
        }
        # content key forbidden
        if {[dict exists $kv content]} {
            if {!$quiet} { puts "error $id: forbidden key 'content' (use notes)" }
            incr errors
        }
    }
    return [list $errors $warnings [llength $ids]]
}

proc almanac::cmd_validate {doc path} {
    lassign [almanac::validate_report $doc $path 0] errors warnings ntasks
    puts "validate $path: $ntasks tasks, $errors error(s), $warnings warning(s)"
    if {$errors > 0} { exit 1 }
}

# --- TOML emitter (a1em): single-quote preference; surgical table splice ---

# Preferred key order when emitting a task table (unknown keys follow).
proc almanac::emit_key_order {} {
    return {
        title status domain project notes agent_notes blockers deferral
        datetime time duration reminder signaling-command coordinating-agents field_links
        created updated completed tags
    }
}

proc almanac::has_control_char {s} {
    # TOML literal strings cannot carry U+0000-001F / U+007F.
    return [regexp {[\u0000-\u001F\u007F]} $s]
}

# Basic-string escape (fallback when a short string cannot be single-quoted).
proc almanac::escape_basic {s} {
    set out {}
    set n [string length $s]
    for {set i 0} {$i < $n} {incr i} {
        set c [string index $s $i]
        switch -exact -- $c {
            \\ { append out "\\\\" }
            \" { append out "\\\"" }
            \b { append out "\\b" }
            \t { append out "\\t" }
            \n { append out "\\n" }
            \f { append out "\\f" }
            \r { append out "\\r" }
            default {
                scan $c %c cp
                if {$cp < 32 || $cp == 127} {
                    append out [format "\\u%04x" $cp]
                } else {
                    append out $c
                }
            }
        }
    }
    return $out
}

# Prefer TOML single-quoted literal; fall back to basic string if needed.
# (TOML literals have no escape for apostrophe — never double quotes.)
proc almanac::quote_string {s} {
    if {[string first "'" $s] < 0 && ![almanac::has_control_char $s]} {
        return "'$s'"
    }
    return "\"[almanac::escape_basic $s]\""
}

proc almanac::quote_array {items} {
    set parts {}
    foreach x $items {
        lappend parts [almanac::quote_string $x]
    }
    return "\[[join $parts {, }]\]"
}

# Multiline notes: triple single-quotes. Content must not contain three quotes in a row.
proc almanac::emit_notes_value {notes} {
    # Normalize to body without a single leading newline artifact from parse.
    set body $notes
    if {[string index $body 0] eq "\n"} {
        set body [string range $body 1 end]
    }
    # Ensure trailing newline before closing delimiter (file convention).
    if {$body ne "" && [string index $body end] ne "\n"} {
        append body "\n"
    }
    if {[string first {'''} $body] >= 0} {
        almanac::die "notes contain triple-quote — cannot emit as literal multiline"
    }
    return "'''\n$body'''"
}

# Int-like keys emit bare; strings quoted; arrays as list of strings.
proc almanac::is_int_key {key} {
    expr {$key in {created updated completed duration reminder}}
}

proc almanac::is_array_key {key} {
    expr {$key in {blockers tags coordinating-agents field_links}}
}

# fields: dict of plain Tcl values (strings / list-of-strings / int-ish strings)
# keyorder: optional explicit order; default preferred + remaining
proc almanac::emit_task_table {id fields {keyorder {}}} {
    if {$keyorder eq {}} {
        set keyorder [almanac::emit_key_order]
    }
    set seen [dict create]
    set lines [list "\[$id\]"]
    foreach key $keyorder {
        if {![dict exists $fields $key]} continue
        dict set seen $key 1
        set v [dict get $fields $key]
        if {$key eq "notes"} {
            # House rule: omit empty / whitespace-only notes (bake already omits).
            if {[string trim $v] eq ""} continue
            lappend lines "notes = [almanac::emit_notes_value $v]"
        } elseif {[almanac::is_array_key $key]} {
            lappend lines "$key = [almanac::quote_array $v]"
        } elseif {[almanac::is_int_key $key]} {
            if {$v eq ""} continue
            lappend lines "$key = $v"
        } else {
            if {$v eq "" && $key ni {title status}} continue
            lappend lines "$key = [almanac::quote_string $v]"
        }
    }
    dict for {key v} $fields {
        if {[dict exists $seen $key]} continue
        if {$key eq "notes"} {
            if {[string trim $v] eq ""} continue
            lappend lines "notes = [almanac::emit_notes_value $v]"
        } elseif {[almanac::is_array_key $key]} {
            lappend lines "$key = [almanac::quote_array $v]"
        } elseif {[almanac::is_int_key $key]} {
            if {$v eq ""} continue
            lappend lines "$key = $v"
        } else {
            lappend lines "$key = [almanac::quote_string $v]"
        }
    }
    lappend lines ""
    return [join $lines "\n"]
}

proc almanac::read_text {path} {
    if {[catch {open $path rb} fh]} {
        almanac::die "cannot read: $path ($fh)"
    }
    set bytes [read $fh]
    close $fh
    return [encoding convertfrom utf-8 $bytes]
}

# Atomic write via temp + rename (a1em).
proc almanac::atomic_write {path text} {
    set dir [file dirname $path]
    if {$dir eq ""} { set dir . }
    set tmp [file join $dir ".[file tail $path].[pid].[clock microseconds].tmp"]
    if {[catch {open $tmp wb} fh]} {
        almanac::die "cannot write temp: $tmp ($fh)"
    }
    puts -nonewline $fh [encoding convertto utf-8 $text]
    close $fh
    if {[catch {file rename -force $tmp $path} err]} {
        catch {file delete -force $tmp}
        almanac::die "atomic rename failed: $err"
    }
}

# Find [id] table span as line indices (inclusive start, exclusive end).
# Returns {ok start end} or {error msg}.
proc almanac::find_table_span {lines id} {
    set header "\[$id\]"
    set start -1
    set n [llength $lines]
    for {set i 0} {$i < $n} {incr i} {
        set s [string trim [lindex $lines $i]]
        if {$s eq $header} {
            set start $i
            break
        }
    }
    if {$start < 0} {
        return [list error "unknown id: $id"]
    }
    set end $n
    for {set j [expr {$start + 1}]} {$j < $n} {incr j} {
        set s [string trim [lindex $lines $j]]
        if {[regexp {^\[.+\]$} $s]} {
            set end $j
            break
        }
    }
    return [list ok $start $end]
}

proc almanac::splice_table {path id table_text} {
    set text [almanac::read_text $path]
    set nl_at_end [expr {[string index $text end] eq "\n"}]
    set lines [split $text "\n"]
    # split drops a trailing empty element when file ends with \n; keep stable
    if {$nl_at_end && [llength $lines] > 0 && [lindex $lines end] eq ""} {
        set lines [lrange $lines 0 end-1]
    }
    set span [almanac::find_table_span $lines $id]
    if {[lindex $span 0] ne "ok"} {
        almanac::die [lindex $span 1]
    }
    lassign $span _ start end
    set new_lines [split [string trimright $table_text "\n"] "\n"]
    # Keep one blank line after the table when a following table exists (file convention).
    if {$end < [llength $lines]} {
        lappend new_lines ""
    }
    set out [concat [lrange $lines 0 [expr {$start - 1}]] $new_lines [lrange $lines $end end]]
    set out_text [join $out "\n"]
    if {[string index $out_text end] ne "\n"} {
        append out_text "\n"
    }
    almanac::atomic_write $path $out_text
}

proc almanac::append_table {path table_text} {
    set text [almanac::read_text $path]
    if {$text ne "" && [string index $text end] ne "\n"} {
        append text "\n"
    }
    if {$text ne "" && [string range $text end-1 end] ne "\n\n"} {
        if {[string index $text end] eq "\n"} {
            append text "\n"
        } else {
            append text "\n\n"
        }
    }
    append text [string trimright $table_text "\n"]
    append text "\n"
    almanac::atomic_write $path $text
}

# Flatten tama kv → plain fields dict + key order (file order via key_line).
proc almanac::fields_from_kv {kv} {
    set fields [dict create]
    set order {}
    dict for {k v} $kv {
        lappend order $k
        set ty [tama::valtype $v]
        if {$ty eq "array"} {
            set items {}
            foreach item [tama::valdata $v] {
                if {[tama::valtype $item] in {string number boolean}} {
                    lappend items [tama::valtext $item]
                }
            }
            dict set fields $k $items
        } elseif {$ty in {string number boolean}} {
            dict set fields $k [tama::valtext $v]
        }
    }
    return [list $fields $order]
}

proc almanac::fields_from_doc {doc id} {
    set kv [almanac::task_kv $doc $id]
    if {$kv eq {} && $id ni [almanac::task_ids $doc]} {
        almanac::die "unknown id: $id"
    }
    # Order keys by key_line when available.
    set order {}
    set key_line {}
    if {[dict exists $doc tables $id key_line]} {
        set key_line [dict get $doc tables $id key_line]
        set decorated {}
        dict for {k ln} $key_line {
            lappend decorated [list $ln $k]
        }
        set decorated [lsort -index 0 -integer $decorated]
        foreach row $decorated { lappend order [lindex $row 1] }
    }
    lassign [almanac::fields_from_kv $kv] fields _
    if {[llength $order] == 0} {
        set order [dict keys $fields]
    }
    return [list $fields $order]
}

proc almanac::new_id {doc} {
    set existing [dict create]
    foreach id [almanac::task_ids $doc] {
        dict set existing $id 1
    }
    set digits "0123456789abcdefghijklmnopqrstuvwxyz"
    for {set tries 0} {$tries < 100000} {incr tries} {
        set id {}
        for {set i 0} {$i < 4} {incr i} {
            append id [string index $digits [expr {int(rand() * 36)}]]
        }
        if {![dict exists $existing $id]} {
            return $id
        }
    }
    almanac::die "failed to allocate unique id"
}

# Parse key=value args. Array keys split on comma. notes keep value as-is.
proc almanac::parse_assigns {args} {
    set out [dict create]
    foreach a $args {
        set eq [string first "=" $a]
        if {$eq < 1} {
            almanac::die "expected key=value, got: $a"
        }
        set k [string range $a 0 [expr {$eq - 1}]]
        set v [string range $a [expr {$eq + 1}] end]
        if {$k eq ""} {
            almanac::die "empty key in: $a"
        }
        if {[almanac::is_array_key $k]} {
            if {$v eq ""} {
                dict set out $k {}
            } else {
                set items {}
                foreach part [split $v ","] {
                    set p [string trim $part]
                    if {$p ne ""} { lappend items $p }
                }
                dict set out $k $items
            }
        } else {
            # Allow \n escapes in notes/short strings from shell.
            set v [string map [list \\n "\n" \\t "\t"] $v]
            dict set out $k $v
        }
    }
    return $out
}


# Post-write: regenerate board bake (no agent). Skip with ALMANAC_SKIP_BOARD_EXPORT=1.
proc almanac::after_mutation {} {
    if {[info exists ::env(ALMANAC_SKIP_BOARD_EXPORT)] && $::env(ALMANAC_SKIP_BOARD_EXPORT) ne ""  && $::env(ALMANAC_SKIP_BOARD_EXPORT) ne "0"} {
        return
    }
    set exporter [file join [file dirname [info script]] board-export.tcl]
    # info script may be almanac when running as program
    if {![file isfile $exporter]} {
        set exporter /workspace/system/scripts/board-export.tcl
    }
    set tclbin /workspace/system/deps/tcl
    if {![file executable $tclbin]} {
        puts stderr "almanac: board-export skipped (deps tcl missing)"
        return
    }
    if {![file isfile $exporter]} {
        puts stderr "almanac: board-export skipped (missing $exporter)"
        return
    }
    if {[catch {exec $tclbin $exporter 2>@1} out]} {
        puts stderr "almanac: board-export failed: $out"
        return
    }
    set line [string trim [lindex [split $out \n] end]]
    if {$line ne ""} { puts $line }
}


# Auto-tag `tosu` when domain is HH|MED|CTP|FIN|DEV (case-sensitive as stored).
# Domain stays domain= — do NOT mirror domain into tags, and do NOT invent
# freeform tags (health, MED, …). Only auto tag additions besides required
# `task` (when tags absent on add) is this `tosu` merge for the domain list.
# domain=almanac never auto-tosu. Agents filing board-design / plane plumbing
# MUST NOT pass tags=tosu (board-plane-contract 0.1.4).
proc almanac::ensure_tosu_tag {fieldsVar} {
    upvar 1 $fieldsVar fields
    if {![dict exists $fields domain]} {
        return
    }
    set domain [dict get $fields domain]
    if {$domain ni {HH MED CTP FIN DEV}} {
        return
    }
    set tags {}
    if {[dict exists $fields tags]} {
        set tags [dict get $fields tags]
    }
    if {"tosu" ni $tags} {
        lappend tags tosu
        dict set fields tags $tags
    }
}

proc almanac::cmd_add {path args} {
    if {[llength $args] == 0} {
        almanac::die "add: need key=value args (title= or task= required; status defaults to later)"
    }
    set assigns [almanac::parse_assigns {*}$args]

    # Alias: task= → title= (CLI filing). If both given: equal → title wins; unequal → die.
    if {[dict exists $assigns task]} {
        set taskv [dict get $assigns task]
        dict unset assigns task
        if {[dict exists $assigns title]} {
            if {[dict get $assigns title] ne $taskv} {
                almanac::die "add: title= and task= conflict (different values); prefer title= or omit one"
            }
        } else {
            dict set assigns title $taskv
        }
    }

    if {![dict exists $assigns title] || [dict get $assigns title] eq ""} {
        almanac::die "add: missing required title= (or task= alias)"
    }

    # Default status=later when unspecified (do not auto-assign today).
    if {![dict exists $assigns status] || [dict get $assigns status] eq ""} {
        dict set assigns status later
    }

    # Empty / whitespace-only notes: omit key entirely (do not invent notes).
    if {[dict exists $assigns notes] && [string trim [dict get $assigns notes]] eq ""} {
        dict unset assigns notes
    }

    set doc [almanac::load $path]
    set id {}
    if {[dict exists $assigns id]} {
        set id [dict get $assigns id]
        dict unset assigns id
        if {![regexp {^[a-z0-9]{4}$} $id]} {
            almanac::die "add: id must be \[a-z0-9\]{4}"
        }
        if {$id in [almanac::task_ids $doc]} {
            almanac::die "add: id already exists: $id"
        }
    } else {
        set id [almanac::new_id $doc]
    }
    set now [almanac::now]
    set fields $assigns
    if {![dict exists $fields created]} { dict set fields created $now }
    if {![dict exists $fields updated]} { dict set fields updated $now }
    if {![dict exists $fields tags]} { dict set fields tags [list task] }
    # Merge tosu for personal chrome domains; never invent other tags here.
    almanac::ensure_tosu_tag fields
    set st [dict get $fields status]
    variable STATUS_ENUM
    if {$st ni $STATUS_ENUM} {
        almanac::die "add: invalid status '$st'"
    }
    if {$st eq "done" && ![dict exists $fields completed]} {
        dict set fields completed $now
    }
    if {$st eq "sched" && (![dict exists $fields datetime] || [dict get $fields datetime] eq "")} {
        almanac::die "add: status=sched requires datetime="
    }
    set table [almanac::emit_task_table $id $fields]
    almanac::append_table $path $table
    puts "ok add $id"
    almanac::after_mutation
}

proc almanac::cmd_set {path id args} {
    if {$id eq ""} { almanac::die "set: need id" }
    if {[llength $args] == 0} { almanac::die "set: need key=value args" }
    if {![regexp {^[a-z0-9]{4}$} $id] && $id ne "root"} {
        almanac::die "set: bad id: $id"
    }
    set assigns [almanac::parse_assigns {*}$args]
    if {[dict exists $assigns id]} {
        almanac::die "set: cannot change id"
    }
    set doc [almanac::load $path]
    lassign [almanac::fields_from_doc $doc $id] fields order
    dict for {k v} $assigns {
        dict set fields $k $v
        if {$k ni $order} { lappend order $k }
    }
    dict set fields updated [almanac::now]
    # Merge tosu for personal chrome domains after assigns (domain/tags may change).
    almanac::ensure_tosu_tag fields
    # Auto-complete stamp when status becomes done.
    if {[dict exists $assigns status] && [dict get $assigns status] eq "done"} {
        if {![dict exists $fields completed] || [dict get $fields completed] eq ""} {
            dict set fields completed [almanac::now]
            if {"completed" ni $order} { lappend order completed }
        }
    }
    set st [dict get $fields status]
    if {$st eq "sched" && (![dict exists $fields datetime] || [dict get $fields datetime] eq "")} {
        almanac::die "set: status=sched requires datetime"
    }
    set table [almanac::emit_task_table $id $fields $order]
    almanac::splice_table $path $id $table
    puts "ok set $id"
    almanac::after_mutation
}

proc almanac::cmd_done {path id} {
    if {$id eq ""} { almanac::die "done: need id" }
    if {![regexp {^[a-z0-9]{4}$} $id]} {
        almanac::die "done: bad id: $id"
    }
    set doc [almanac::load $path]
    lassign [almanac::fields_from_doc $doc $id] fields order
    set now [almanac::now]
    dict set fields status done
    dict set fields updated $now
    dict set fields completed $now
    foreach k {status updated completed} {
        if {$k ni $order} { lappend order $k }
    }
    set table [almanac::emit_task_table $id $fields $order]
    almanac::splice_table $path $id $table
    # Dependent scan (read-only report).
    set deps {}
    set doc2 [almanac::load $path]
    foreach oid [almanac::task_ids $doc2] {
        if {$oid eq $id} continue
        set bl [almanac::array_texts [almanac::task_kv $doc2 $oid] blockers]
        if {$id in $bl} {
            lappend deps $oid
        }
    }
    if {[llength $deps] > 0} {
        puts "ok done $id  dependents=[join $deps ,]"
    } else {
        puts "ok done $id"
    }
    almanac::after_mutation
}


# --- doctor (health report; non-zero if any check fails) ---


# --- doctor shell aliases (deps tcl only) ---

proc almanac::doctor_alias_block {} {
    return "# labor-os almanac (deps tcl only)\nalias almanac='/workspace/system/deps/tcl /workspace/system/scripts/almanac.tcl'\nalias alm='almanac'\n"
}

proc almanac::doctor_alias_target {} {
    # Prefer .bash_aliases when that file exists (bashrc sources it); else .bashrc.
    if {[file isfile /home/box/.bash_aliases]} {
        return /home/box/.bash_aliases
    }
    return /home/box/.bashrc
}

proc almanac::doctor_read_alias_defs {path} {
    set out [dict create]
    if {![file isfile $path]} { return $out }
    set fh [open $path r]
    set text [read $fh]
    close $fh
    foreach line [split $text \n] {
        set s [string trim $line]
        if {[regexp {^#} $s]} continue
        if {[regexp {^alias[[:space:]]+almanac=(.*)$} $s -> rhs]} {
            dict set out almanac [string trim $rhs]
        } elseif {[regexp {^alias[[:space:]]+alm=(.*)$} $s -> rhs]} {
            dict set out alm [string trim $rhs]
        } elseif {[regexp {^alias[[:space:]]+alamanac=} $s]} {
            dict set out alamanac_typo 1
        }
    }
    return $out
}

proc almanac::doctor_unquote_rhs {rhs} {
    set r [string trim $rhs]
    if {[string length $r] >= 2} {
        set a [string index $r 0]
        set b [string index $r end]
        if {($a eq "'" && $b eq "'") || ($a eq "\"" && $b eq "\"")} {
            set r [string range $r 1 end-1]
        }
    }
    return $r
}

proc almanac::doctor_alias_rhs_ok {name rhs} {
    set r [almanac::doctor_unquote_rhs $rhs]
    if {$name eq "almanac"} {
        # Exact deps tcl + script path; reject tclsh / typos / relative paths.
        if {[string match *tclsh* $r]} { return 0 }
        if {[string match *alamanac* $r]} { return 0 }
        return [expr {$r eq {/workspace/system/deps/tcl /workspace/system/scripts/almanac.tcl}}]
    }
    if {$name eq "alm"} {
        return [expr {$r eq {almanac}}]
    }
    return 0
}

# Install or correct the marked alias block. Returns list:
#   ok_almanac detail_almanac ok_alm detail_alm target action
proc almanac::doctor_ensure_aliases {} {
    set target [almanac::doctor_alias_target]
    set files {}
    foreach f {/home/box/.bashrc /home/box/.bash_aliases} {
        if {[file isfile $f]} { lappend files $f }
    }
    set defs [dict create]
    foreach f $files {
        set d [almanac::doctor_read_alias_defs $f]
        dict for {k v} $d { dict set defs $k $v }
    }
    set alm_ok 0
    set alm_detail "missing"
    set a_ok 0
    set a_detail "missing"
    if {[dict exists $defs almanac]} {
        set rhs [dict get $defs almanac]
        if {[almanac::doctor_alias_rhs_ok almanac $rhs]} {
            set alm_ok 1
            set alm_detail "config: $rhs"
        } else {
            set alm_detail "wrong: $rhs"
        }
    }
    if {[dict exists $defs alm]} {
        set rhs [dict get $defs alm]
        if {[almanac::doctor_alias_rhs_ok alm $rhs]} {
            set a_ok 1
            set a_detail "config: $rhs"
        } else {
            set a_detail "wrong: $rhs"
        }
    }
    if {[dict exists $defs alamanac_typo]} {
        set alm_ok 0
        if {$alm_detail eq "missing"} {
            set alm_detail "typo alias alamanac present"
        } else {
            append alm_detail "; typo alamanac present"
        }
    }
    # Also require marked block on target (canonical location).
    set marked 0
    if {[file isfile $target]} {
        set fh [open $target r]
        set ttext [read $fh]
        close $fh
        if {[string first {# labor-os almanac (deps tcl only)} $ttext] >= 0} {
            set marked 1
        }
    }
    set action none
    if {!$alm_ok || !$a_ok || !$marked} {
        # Strip alias lines / old marked blocks from both config files, then write target.
        foreach f $files {
            set fh [open $f r]
            set text [read $fh]
            close $fh
            set text [regsub -all {# labor-os almanac[^\n]*\n(?:alias[^\n]*\n)*} $text {}]
            set newlines {}
            foreach line [split $text \n] {
                set s [string trim $line]
                if {[regexp {^alias[[:space:]]+(almanac|alm|alamanac)=} $s]} {
                    continue
                }
                lappend newlines $line
            }
            set text [string trimright [join $newlines \n]]
            append text \n
            set fh [open $f w]
            puts -nonewline $fh $text
            close $fh
        }
        # Ensure target exists; append marked block.
        set text ""
        if {[file isfile $target]} {
            set fh [open $target r]
            set text [read $fh]
            close $fh
        }
        set text [string trimright $text]
        append text "\n\n" [almanac::doctor_alias_block]
        set fh [open $target w]
        puts -nonewline $fh $text
        close $fh
        set action "installed/corrected in $target"
        set alm_ok 1
        set a_ok 1
        set alm_detail "installed → '/workspace/system/deps/tcl /workspace/system/scripts/almanac.tcl'"
        set a_detail "installed → 'almanac'"
    }
    return [list $alm_ok $alm_detail $a_ok $a_detail $target $action]
}


proc almanac::doctor_alias_resolve_report {} {
    set lines {}
    # Plain login non-interactive: .profile sources .bashrc but interactive guard returns early → aliases usually absent.
    set lc_out {}
    catch {set lc_out [exec bash -lc {alias almanac 2>&1; alias alm 2>&1}]}
    set lc_out [string trim $lc_out]
    if {[string match "*almanac=*" $lc_out]} {
        lappend lines "bash -lc: yes"
    } else {
        lappend lines "bash -lc: no (non-interactive; .bashrc interactive guard)"
    }
    # Interactive login loads .bashrc → .bash_aliases. Feed empty stdin; merge stderr (ioctl noise).
    set il_out {}
    catch {set il_out [exec bash -ilc {alias almanac 2>&1; echo ---; alias alm 2>&1} << {} 2>@1]}
    set il_out [string trim $il_out]
    if {[string match "*almanac=*" $il_out]} {
        lappend lines "bash -ilc: yes"
    } else {
        lappend lines "bash -ilc: no"
    }
    return [join $lines { | }]
}


proc almanac::doctor_line {ok name detail} {
    if {$ok} {
        puts [format "ok   %-28s %s" $name $detail]
        return 0
    }
    puts [format "FAIL %-28s %s" $name $detail]
    return 1
}

proc almanac::doctor_hook_path {} {
    set exporter [file join [file dirname [info script]] board-export.tcl]
    if {![file isfile $exporter]} {
        set exporter /workspace/system/scripts/board-export.tcl
    }
    return $exporter
}

# Smoke mutating verbs against a temp monolith; never touch production.
# Uses ALMANAC_SKIP_BOARD_EXPORT=1 so post-write does not rewrite the live bake.
proc almanac::doctor_smoke_verbs {tclbin self} {
    set tmpdir [file join /tmp "almanac-doctor.[pid].[clock microseconds]"]
    file mkdir $tmpdir
    set tmp [file join $tmpdir tasks.toml]
    set fail 0
    set detail {}
    set ::env(ALMANAC_SKIP_BOARD_EXPORT) 1
    try {
        if {[catch {exec $tclbin $self --file $tmp init} out]} {
            return [list 0 "init failed: $out"]
        }
        if {![file isfile $tmp]} {
            return [list 0 "init did not create $tmp"]
        }
        if {[catch {exec $tclbin $self --file $tmp add id=doc0 title=DoctorSmoke status=today notes=smoke-notes tags=task,doctor} out]} {
            return [list 0 "add failed: $out"]
        }
        if {![string match "*ok add doc0*" $out]} {
            return [list 0 "add unexpected: $out"]
        }
        if {[catch {exec $tclbin $self --file $tmp set doc0 status=later} out]} {
            return [list 0 "set failed: $out"]
        }
        foreach verb {ls filter today ready blockers validate} {
            if {[catch {exec $tclbin $self --file $tmp $verb} out]} {
                # validate may exit 1 on schema issues; still capture
                if {$verb eq "validate"} {
                    # temp skeleton+doc0 should validate clean; failure is real
                    return [list 0 "$verb failed: $out"]
                }
                return [list 0 "$verb failed: $out"]
            }
        }
        # blockers with id
        if {[catch {exec $tclbin $self --file $tmp blockers doc0} out]} {
            return [list 0 "blockers id failed: $out"]
        }
        if {[catch {exec $tclbin $self --file $tmp done doc0} out]} {
            return [list 0 "done failed: $out"]
        }
        if {![string match "*ok done doc0*" $out]} {
            return [list 0 "done unexpected: $out"]
        }
        # post-done validate should still pass
        if {[catch {exec $tclbin $self --file $tmp validate} out]} {
            return [list 0 "post-done validate failed: $out"]
        }
        return [list 1 "init/add/set/ls/filter/today/ready/blockers/done/validate on temp"]
    } finally {
        catch {unset ::env(ALMANAC_SKIP_BOARD_EXPORT)}
        catch {file delete -force $tmpdir}
    }
}

proc almanac::doctor_check_bake {tclbin exporter srcfile} {
    set tmpdir [file join /tmp "almanac-doctor-bake.[pid].[clock microseconds]"]
    file mkdir $tmpdir
    set out [file join $tmpdir board-model.toml]
    set notes_dir [file join $tmpdir notes]
    try {
        if {[catch {exec $tclbin $exporter --file $srcfile --out $out} exp]} {
            return [list 0 "board-export failed: $exp" {}]
        }
        if {![file isfile $out]} {
            return [list 0 "bake missing after export: $out" {}]
        }
        set text [almanac::read_text $out]
        set required {
            schema generator generator_version generated generated_datetime
            source stable_path include_done card_count
        }
        set missing {}
        foreach k $required {
            if {![regexp -line "^${k}\\s*=" $text]} {
                lappend missing $k
            }
        }
        if {[llength $missing] > 0} {
            return [list 0 "bake missing top-level keys: [join $missing {, }]" $out]
        }
        if {![regexp -line {^include_done\s*=\s*true\s*$} $text]} {
            return [list 0 "bake default must include status=done cards (include_done=true)" $out]
        }
        if {![regexp {schema\s*=\s*'labor-os\.board-model/v1'} $text]} {
            return [list 0 "bake schema id not labor-os.board-model/v1" $out]
        }
        # omit-empty: no blank string assignments, no empty arrays, no false booleans
        set omit_hits {}
        foreach line [split $text \n] {
            set s [string trim $line]
            if {$s eq "" || [string match #* $s] || [regexp {^\[} $s]} continue
            if {[regexp {=\s*''\s*$} $s] || [regexp {=\s*""\s*$} $s]} {
                lappend omit_hits "blank:$s"
            }
            if {[regexp {=\s*\[\s*\]\s*$} $s]} {
                lappend omit_hits "empty-array:$s"
            }
            if {[regexp {=\s*false\s*$} $s]} {
                lappend omit_hits "false:$s"
            }
        }
        # Parse bake cards via line walk for tosu notes policy
        set card_tosu 0
        set card_notes 0
        set bad_notes 0
        set cur_tosu 0
        set cur_notes 0
        set in_card 0
        foreach line [split $text \n] {
            set s [string trim $line]
            if {$s eq {[[cards]]}} {
                if {$in_card} {
                    if {$cur_tosu} { incr card_tosu }
                    if {$cur_notes} { incr card_notes }
                    if {$cur_notes && !$cur_tosu} { incr bad_notes }
                }
                set in_card 1
                set cur_tosu 0
                set cur_notes 0
                continue
            }
            if {$in_card} {
                if {[regexp {^tosu\s*=\s*true} $s]} { set cur_tosu 1 }
                if {[regexp {^notes\s*=} $s] || [regexp {^notes_excerpt\s*=} $s]} { set cur_notes 1 }
            }
        }
        if {$in_card} {
            if {$cur_tosu} { incr card_tosu }
            if {$cur_notes} { incr card_notes }
            if {$cur_notes && !$cur_tosu} { incr bad_notes }
        }
        if {$bad_notes > 0} {
            return [list 0 "tosu notes policy: $bad_notes non-tosu card(s) carry notes/notes_excerpt" $out]
        }
        # notes-by-id: only tosu ids, and every notes file id should be tosu in bake
        set note_files [glob -nocomplain -directory $notes_dir *.toml]
        set note_ids {}
        foreach nf $note_files {
            lappend note_ids [file rootname [file tail $nf]]
        }
        # Collect tosu ids from bake
        set tosu_ids {}
        set cur_id {}
        set cur_tosu 0
        set in_card 0
        foreach line [split $text \n] {
            set s [string trim $line]
            if {$s eq {[[cards]]}} {
                if {$in_card && $cur_tosu && $cur_id ne ""} { lappend tosu_ids $cur_id }
                set in_card 1
                set cur_id {}
                set cur_tosu 0
                continue
            }
            if {$in_card} {
                if {[regexp {^id\s*=\s*'([^']+)'$} $s -> cid]} { set cur_id $cid }
                if {[regexp {^id\s*=\s*"([^"]+)"$} $s -> cid]} { set cur_id $cid }
                if {[regexp {^tosu\s*=\s*true} $s]} { set cur_tosu 1 }
            }
        }
        if {$in_card && $cur_tosu && $cur_id ne ""} { lappend tosu_ids $cur_id }
        set stray {}
        foreach nid $note_ids {
            if {$nid ni $tosu_ids} { lappend stray $nid }
        }
        if {[llength $stray] > 0} {
            return [list 0 "notes-by-id has non-tosu id(s): [join $stray {, }]" $out]
        }
        set detail "schema ok; omit-empty ok; tosu_notes=$card_notes tosu_cards=$card_tosu notes-by-id=[llength $note_ids]; export: [string trim [lindex [split $exp \n] end]]"
        return [list 1 $detail $out]
    } finally {
        catch {file delete -force $tmpdir}
    }
}

proc almanac::cmd_doctor {path} {
    set fails 0
    set tclbin /workspace/system/deps/tcl
    set self [info script]
    if {$self eq "" || ![file isfile $self]} {
        set self /workspace/system/scripts/almanac.tcl
    }

    puts "almanac doctor — $path"
    puts "----"

    # 1. file exists
    set ok [file isfile $path]
    incr fails [almanac::doctor_line $ok file_exists [expr {$ok ? $path : "missing $path"}]]
    if {!$ok} {
        puts "----"
        puts "doctor: $fails fail(s)"
        exit 1
    }

    # 2. parse
    set parse_ok 1
    set parse_detail "parsed"
    set doc {}
    if {[catch {set doc [almanac::load $path]} err]} {
        set parse_ok 0
        set parse_detail $err
    } else {
        set n [llength [almanac::task_ids $doc]]
        set parse_detail "$n task table(s)"
    }
    incr fails [almanac::doctor_line $parse_ok parse $parse_detail]
    if {!$parse_ok} {
        puts "----"
        puts "doctor: $fails fail(s)"
        exit 1
    }

    # 3. schema (reuse validate_report; quiet — one doctor line)
    lassign [almanac::validate_report $doc $path 1] verrs vwarns ntasks
    set sok [expr {$verrs == 0}]
    incr fails [almanac::doctor_line $sok schema_validate "$ntasks tasks, $verrs error(s), $vwarns warning(s) (see: almanac validate)"]

    # 4. verb smoke on temp
    lassign [almanac::doctor_smoke_verbs $tclbin $self] vok vdetail
    incr fails [almanac::doctor_line $vok verb_smoke $vdetail]

    # 5–8. board-export bake checks (temp out; production or given --file as source)
    set exporter [almanac::doctor_hook_path]
    set hook_ok [expr {[file isfile $exporter] && [file executable $tclbin]}]
    incr fails [almanac::doctor_line $hook_ok post_write_hook_path [expr {$hook_ok ? $exporter : "missing exporter or deps tcl"}]]

    if {$hook_ok} {
        lassign [almanac::doctor_check_bake $tclbin $exporter $path] bok bdetail _
        incr fails [almanac::doctor_line $bok board_export_bake $bdetail]
    } else {
        incr fails [almanac::doctor_line 0 board_export_bake "skipped (no exporter)"]
    }

    # 9. live notes-by-id dir beside default bake (informational + policy if present)
    set live_notes /workspace/system/work/board/notes
    if {[file isdirectory $live_notes]} {
        set nfiles [glob -nocomplain -directory $live_notes *.toml]
        incr fails [almanac::doctor_line 1 notes_by_id_dir "$live_notes ([llength $nfiles] file(s))"]
    } else {
        # not a hard fail if bake never exported; warn-style but count as fail only if bake exists
        set live_bake /workspace/system/work/board/board-model.toml
        if {[file isfile $live_bake]} {
            incr fails [almanac::doctor_line 0 notes_by_id_dir "missing $live_notes but bake exists"]
        } else {
            incr fails [almanac::doctor_line 1 notes_by_id_dir "absent (no live bake yet)"]
        }
    }

    # 10. deps tcl binary (runtime for doctor + children — never tclsh)
    set deps_ok [expr {[file executable $tclbin] && [file normalize $tclbin] eq [file normalize /workspace/system/deps/tcl]}]
    incr fails [almanac::doctor_line $deps_ok deps_tcl_binary [expr {$deps_ok ? "$tclbin (executable)" : "missing/wrong $tclbin"}]]

    # 11. doctor + exec children use deps tcl (not tclsh)
    set runtime_ok 1
    set runtime_detail "doctor/smoke/export use $tclbin"
    if {[string match *tclsh* $tclbin]} {
        set runtime_ok 0
        set runtime_detail "tclbin is tclsh: $tclbin"
    }
    incr fails [almanac::doctor_line $runtime_ok runtime_deps_tcl $runtime_detail]

    # 12. shell aliases almanac + alm (install/correct if missing or wrong)
    lassign [almanac::doctor_ensure_aliases] aok adetail bok bdetail atarget aaction
    incr fails [almanac::doctor_line $aok alias_almanac "$adetail (target=$atarget action=$aaction)"]
    incr fails [almanac::doctor_line $bok alias_alm "$bdetail"]
    set resolve [almanac::doctor_alias_resolve_report]
    incr fails [almanac::doctor_line 1 alias_resolve "$resolve"]

    puts "----"
    if {$fails > 0} {
        puts "doctor: $fails fail(s)"
        exit 1
    }
    puts "doctor: all checks passed"
}

# --- project mode (work.toml) -----------------------------------------------
# Selected when the file is named work.toml, when [meta] has
# profile = 'project', or with --profile project. Personal mode (the default)
# never reaches this code. Project mode is read-only: agents edit work.toml by
# hand; almanac lists, slices, checks, and computes lock sums.

namespace eval almanac::proj {
    variable STAGES {idea spec locked}
    variable DEF_STATUSES {todo doing review done dropped}
    variable DEF_CLOSED {done dropped}
    variable TAG_HEADS {work}
}

proc almanac::proj::wants {argv} {
    # Returns {mode path rest}. mode is project|personal|"" (undecided).
    set mode ""
    set path ""
    set rest {}
    for {set i 0} {$i < [llength $argv]} {incr i} {
        set a [lindex $argv $i]
        if {$a eq "--profile"} {
            incr i
            set mode [lindex $argv $i]
            continue
        }
        if {[string match --profile=* $a]} { set mode [string range $a 10 end]; continue }
        if {$a eq "--file"} { set path [lindex $argv [expr {$i + 1}]] }
        lappend rest $a
    }
    return [list $mode $path $rest]
}

proc almanac::proj::is_project_file {path} {
    if {$path eq "" || ![file isfile $path]} { return 0 }
    if {[file tail $path] eq "work.toml"} { return 1 }
    set fh [open $path rb]
    set text [encoding convertfrom utf-8 [read $fh]]
    close $fh
    set in_meta 0
    foreach line [split $text \n] {
        set t [string trim $line]
        if {[regexp {^\[([^\]]+)\]} $t -> name]} { set in_meta [expr {$name eq "meta"}]; continue }
        if {$in_meta && [regexp {^profile\s*=\s*['"]project['"]} $t]} { return 1 }
    }
    return 0
}

proc almanac::proj::kv {doc id} { return [almanac::task_kv $doc $id] }
proc almanac::proj::s {doc id key {default {}}} { return [almanac::scalar [almanac::task_kv $doc $id] $key $default] }
proc almanac::proj::a {doc id key} { return [almanac::array_texts [almanac::task_kv $doc $id] $key] }

proc almanac::proj::meta_list {doc key default} {
    if {![dict exists $doc tables meta]} { return $default }
    set v [almanac::array_texts [almanac::task_kv $doc meta] $key]
    if {[llength $v] == 0} { return $default }
    return $v
}

proc almanac::proj::ctx {doc} {
    variable DEF_STATUSES
    variable DEF_CLOSED
    return [dict create \
        statuses [almanac::proj::meta_list $doc statuses $DEF_STATUSES] \
        closed   [almanac::proj::meta_list $doc closed $DEF_CLOSED]]
}

proc almanac::proj::ids {doc} {
    set out {}
    foreach id [dict get $doc table_list] {
        if {$id eq "meta" || $id eq "root" || [string first . $id] >= 0} continue
        lappend out $id
    }
    return $out
}

# lock_sum: first 6 hex chars of sha256 over the UTF-8 bytes of
#   plan + "\n" + join(sort(ac + ac_done), "\n")
# Sorting the union means checking a criterion off (moving it from ac to
# ac_done) does not change the sum; editing plan or any criterion does.
proc almanac::proj::lock_sum {doc id} {
    set plan [almanac::proj::s $doc $id plan]
    set crit [lsort [concat [almanac::proj::a $doc $id ac] [almanac::proj::a $doc $id ac_done]]]
    set data "$plan\n[join $crit \n]"
    set sha [file join [file dirname $::ALMANAC_DIR] deps sha256sum]
    set ch [open |[list $sha] r+]
    fconfigure $ch -translation binary
    puts -nonewline $ch [encoding convertto utf-8 $data]
    chan close $ch write
    set out [read $ch]
    close $ch
    return [string range [string trim $out] 0 5]
}

proc almanac::proj::iso_ok {v} {
    if {![regexp {^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$} $v]} { return 0 }
    if {[catch {clock scan $v -format {%Y-%m-%dT%H:%M:%SZ} -timezone :UTC} e]} { return 0 }
    return [expr {[clock format $e -format {%Y-%m-%dT%H:%M:%SZ} -timezone :UTC] eq $v}]
}

proc almanac::proj::iso_epoch {v} {
    clock scan $v -format {%Y-%m-%dT%H:%M:%SZ} -timezone :UTC
}

# created stays YYMMDDHHMM on the operator's local clock.
proc almanac::proj::created_epoch {v} {
    if {![regexp {^[0-9]{10}$} $v]} { return "" }
    if {[catch {clock scan $v -format {%y%m%d%H%M} -timezone :America/Los_Angeles} e]} { return "" }
    return $e
}

namespace eval almanac::proj {
    variable ROSTER_ARG ""
    variable ROSTER_DEFAULT /workspace/spectral/agents.toml
}

proc almanac::proj::roster_path {doc path} {
    variable ROSTER_ARG
    variable ROSTER_DEFAULT
    if {$ROSTER_ARG ne ""} { return $ROSTER_ARG }
    if {[dict exists $doc tables meta]} {
        set r [almanac::scalar [almanac::task_kv $doc meta] roster]
        if {$r ne ""} {
            if {[file pathtype $r] eq "relative"} { set r [file join [file dirname $path] $r] }
            return $r
        }
    }
    return $ROSTER_DEFAULT
}

# Names of [agents.<name>] tables, or "-" if unreadable.
proc almanac::proj::roster_names {rpath} {
    if {![file isfile $rpath]} { return - }
    set fh [open $rpath rb]
    set text [encoding convertfrom utf-8 [read $fh]]
    close $fh
    set r [tama::parse $text $rpath]
    if {[lindex $r 0] eq "error"} { return - }
    if {[lindex $r 0] eq "ok"} { set r [lindex $r 1] }
    set out {}
    foreach t [dict get $r table_list] {
        if {[regexp {^agents\.([^.]+)$} $t -> n]} { lappend out $n }
    }
    return $out
}

namespace eval almanac::proj {
    variable BOARD_OPEN 0
    variable BOARD_STALE 0
    variable BOARD_STATES {open faded promoted}
    variable BOARD_STALE_DAYS 14
}

proc almanac::proj::board_ids {doc} {
    set out {}
    foreach t [dict get $doc table_list] {
        if {[regexp {^board\.([^.]+)$} $t -> b]} { lappend out $b }
    }
    return $out
}

proc almanac::proj::bs {doc b key} {
    return [almanac::scalar [almanac::task_kv $doc board.$b] $key]
}

# tama does not parse inline tables, so threads are read from the raw text.
# Entry form, one per line, keys in this order, single-quoted:
#   {by = 'name', at = '2026-10-10T01:56:00Z', text = '...'},
# Returns dict id -> {entries {{by at text} ...} bad N}.
proc almanac::proj::board_threads {path} {
    set fh [open $path rb]
    set text [encoding convertfrom utf-8 [read $fh]]
    close $fh
    set out [dict create]
    set cur ""
    set inthread 0
    set buf ""
    foreach line [split $text \n] {
        set t [string trim $line]
        if {!$inthread && [regexp {^\[([^\]]+)\]\s*(#.*)?$} $t -> name]} {
            set cur [expr {[regexp {^board\.(.+)$} $name -> b] ? $b : ""}]
            continue
        }
        if {$cur eq ""} continue
        if {!$inthread && [regexp {^thread\s*=\s*(.*)$} $t -> rhs]} {
            set inthread 1
            set buf $rhs
        } elseif {$inthread} {
            append buf "\n" $t
        } else { continue }
        if {[regexp {\]\s*(#.*)?$} $t] && ![regexp {^\{} $t]} {
            set inthread 0
            set entries {}
            set bad 0
            foreach l [split $buf \n] {
                set l [string trim $l]
                regsub {^thread\s*=\s*\[} $l {} l
                regsub {^\[} $l {} l
                regsub {\]\s*$} $l {} l
                set l [string trim $l]
                if {$l eq "" || [string match #* $l]} continue
                foreach piece [regexp -all -inline {\{[^\n]*?\}(?=\s*,|\s*$)} $l] {
                    if {[regexp {^\{\s*by\s*=\s*'([^']*)'\s*,\s*at\s*=\s*'([^']*)'\s*,\s*text\s*=\s*'([^']*)'\s*\}$} $piece -> by at tx]} {
                        lappend entries [list $by $at $tx]
                    } else { incr bad }
                }
                if {![regexp {\{} $l]} { incr bad }
            }
            dict set out $cur [dict create entries $entries bad $bad]
        }
    }
    return $out
}

proc almanac::proj::board_list {doc path tags} {
    variable BOARD_OPEN
    variable BOARD_STALE
    variable BOARD_STALE_DAYS
    set th [almanac::proj::board_threads $path]
    set now [clock seconds]
    foreach b [almanac::proj::board_ids $doc] {
        set st [almanac::proj::bs $doc $b state]
        set n 0
        if {[dict exists $th $b]} { set n [llength [dict get $th $b entries]] }
        if {$BOARD_OPEN && $st ne "open"} continue
        if {$BOARD_STALE} {
            if {$st ne "open" || $n > 0} continue
            set po [almanac::proj::bs $doc $b posted]
            if {![almanac::proj::iso_ok $po]} continue
            if {$now - [almanac::proj::iso_epoch $po] <= $BOARD_STALE_DAYS * 86400} continue
        }
        set btags [almanac::array_texts [almanac::task_kv $doc board.$b] tags]
        set ok 1
        foreach group $tags {
            set hits 0
            foreach t $group { if {$t in $btags} { incr hits } }
            if {$hits == 0} { set ok 0 }
        }
        if {!$ok} continue
        set tx [almanac::proj::bs $doc $b text]
        if {[string length $tx] > 70} { set tx "[string range $tx 0 68]…" }
        set extra ""
        if {[llength $btags]} { append extra "  \[[join $btags {, }]\]" }
        set pt [almanac::proj::bs $doc $b promoted_to]
        if {$pt ne ""} { append extra "  -> $pt" }
        puts [format "%-4s  %-8s  %-10s  %s  %2d  %s%s" $b $st [almanac::proj::bs $doc $b by] [almanac::proj::bs $doc $b posted] $n $tx $extra]
    }
}

proc almanac::proj::board_check {doc path agents items} {
    variable BOARD_STATES
    set errs {}
    set th [almanac::proj::board_threads $path]
    foreach b [almanac::proj::board_ids $doc] {
        set p "\[board.$b\]"
        set kv [almanac::task_kv $doc board.$b]
        set by [almanac::proj::bs $doc $b by]
        set po [almanac::proj::bs $doc $b posted]
        set st [almanac::proj::bs $doc $b state]
        if {$by eq ""} { lappend errs "$p: missing by" } elseif {$by ni $agents} { lappend errs "$p: by '$by' is not in \[meta\] agents" }
        if {![almanac::proj::iso_ok $po]} { lappend errs "$p: posted '$po' must be ISO 8601 UTC like 2026-10-10T01:56:00Z" }
        if {[string trim [almanac::proj::bs $doc $b text]] eq ""} { lappend errs "$p: missing text" }
        if {$st ni $BOARD_STATES} { lappend errs "$p: state must be open, faded or promoted (got '$st')" }
        set pt [almanac::proj::bs $doc $b promoted_to]
        if {$st eq "promoted"} {
            if {$pt eq ""} { lappend errs "$p: promoted post needs promoted_to" } elseif {$pt ni $items} {
                lappend errs "$p: promoted_to '$pt' is not an item"
            } elseif {[almanac::proj::s $doc $pt from_board] ne $b} {
                lappend errs "$p: item \[$pt\] needs from_board = '$b'"
            }
        } elseif {$pt ne ""} { lappend errs "$p: promoted_to is only allowed when state is promoted" }
        foreach k {status stage claimed_by performing_agent coordinating_agent lock_sum locked locked_by} {
            if {[dict exists $kv $k]} { lappend errs "$p: board posts are not work items; remove $k" }
        }
        if {![dict exists $th $b]} {
            if {[dict exists $kv thread]} { lappend errs "$p: thread could not be read" }
            continue
        }
        set bad [dict get $th $b bad]
        if {$bad} { lappend errs "$p: $bad thread entr(y/ies) not of the form {by = '...', at = '...', text = '...'}" }
        set prev $by
        set last $po
        set i 0
        foreach e [dict get $th $b entries] {
            incr i
            lassign $e eby eat etx
            if {$eby ni $agents} { lappend errs "$p: thread #$i by '$eby' is not in \[meta\] agents" }
            if {$eby eq $prev} { lappend errs "$p: thread #$i: '$eby' replied twice in a row (one reply per agent per turn)" }
            if {![almanac::proj::iso_ok $eat]} {
                lappend errs "$p: thread #$i at '$eat' must be ISO 8601 UTC"
            } elseif {[almanac::proj::iso_ok $last] && [almanac::proj::iso_epoch $eat] < [almanac::proj::iso_epoch $last]} {
                lappend errs "$p: thread #$i at '$eat' is earlier than the previous turn"
            } else { set last $eat }
            if {[string trim $etx] eq ""} { lappend errs "$p: thread #$i has empty text" }
            set prev $eby
        }
    }
    return $errs
}

proc almanac::proj::closed {ctx doc id} {
    expr {[almanac::proj::s $doc $id status] in [dict get $ctx closed]}
}

proc almanac::proj::blocked {ctx doc id} {
    if {[almanac::proj::closed $ctx $doc $id]} { return 0 }
    set all [almanac::proj::ids $doc]
    foreach b [almanac::proj::a $doc $id blockers] {
        if {$b ni $all} { return 1 }
        if {![almanac::proj::closed $ctx $doc $b]} { return 1 }
    }
    return 0
}

proc almanac::proj::lock_ok {doc id} {
    if {[almanac::proj::s $doc $id stage] ne "locked"} { return 0 }
    if {[almanac::proj::s $doc $id locked_by] ne "operator"} { return 0 }
    if {[almanac::proj::s $doc $id locked] eq ""} { return 0 }
    set sum [almanac::proj::s $doc $id lock_sum]
    return [expr {$sum ne "" && $sum eq [almanac::proj::lock_sum $doc $id]}]
}

proc almanac::proj::ready {ctx doc id} {
    expr {[almanac::proj::s $doc $id stage] eq "locked"
          && [almanac::proj::s $doc $id status] eq "todo"
          && ![almanac::proj::blocked $ctx $doc $id]}
}

proc almanac::proj::claimable {ctx doc id} {
    if {![almanac::proj::ready $ctx $doc $id]} { return 0 }
    if {[llength [almanac::proj::a $doc $id ac]] == 0} { return 0 }
    if {[string trim [almanac::proj::s $doc $id plan]] eq ""} { return 0 }
    if {[almanac::proj::s $doc $id performing_agent] ne ""} { return 0 }
    return [almanac::proj::lock_ok $doc $id]
}

proc almanac::proj::state {doc id} {
    set st [almanac::proj::s $doc $id stage]
    set su [almanac::proj::s $doc $id status]
    if {$su ne ""} { return "$st/$su" }
    return $st
}

proc almanac::proj::line {doc id} {
    set tags [almanac::proj::a $doc $id tags]
    set owner [almanac::proj::s $doc $id performing_agent]
    set extra ""
    if {[llength $tags]} { append extra "  \[[join $tags {, }]\]" }
    if {$owner ne ""} { append extra "  @$owner" }
    return [format "%-4s  %-14s  %s%s" $id [almanac::proj::state $doc $id] [almanac::proj::s $doc $id title $id] $extra]
}

proc almanac::proj::emit_item {doc id} {
    set kv [almanac::task_kv $doc $id]
    puts "\[$id\]"
    foreach k [dict keys $kv] {
        set v [dict get $kv $k]
        if {[catch {tama::valtype $v} ty]} continue
        if {$ty eq "array"} {
            puts "$k = [almanac::quote_array [almanac::array_texts $kv $k]]"
        } elseif {$ty in {number boolean}} {
            puts "$k = [tama::valtext $v]"
        } else {
            puts "$k = [almanac::quote_string [tama::valtext $v]]"
        }
    }
}

proc almanac::proj::json_str {s} {
    set map [list \\ \\\\ \" \\\" \n \\n \r \\r \t \\t]
    return "\"[string map $map $s]\""
}

proc almanac::proj::json_item {ctx doc id} {
    set kv [almanac::task_kv $doc $id]
    set parts [list "\"id\": [almanac::proj::json_str $id]"]
    foreach k [dict keys $kv] {
        set v [dict get $kv $k]
        if {[catch {tama::valtype $v} ty]} continue
        if {$ty eq "array"} {
            set items {}
            foreach x [almanac::array_texts $kv $k] { lappend items [almanac::proj::json_str $x] }
            lappend parts "[almanac::proj::json_str $k]: \[[join $items {, }]\]"
        } elseif {$ty eq "number"} {
            lappend parts "[almanac::proj::json_str $k]: [tama::valtext $v]"
        } else {
            lappend parts "[almanac::proj::json_str $k]: [almanac::proj::json_str [tama::valtext $v]]"
        }
    }
    lappend parts "\"claimable\": [expr {[almanac::proj::claimable $ctx $doc $id] ? "true" : "false"}]"
    lappend parts "\"blocked\": [expr {[almanac::proj::blocked $ctx $doc $id] ? "true" : "false"}]"
    return "{[join $parts {, }]}"
}

proc almanac::proj::usage {{code 2}} {
    puts stderr {almanac (project mode: work.toml, read-only)

  almanac [--file PATH] [--profile project] VERB [FILTERS] [OUTPUT]

Verbs:
  ls | filter        list work items (default: all)
  claimable          items an agent may claim now (same as ls --claimable)
  show ID            one item in full
  check              validate the file against the work.toml rules; exit 1 on violation
  lock-sum ID        print the lock sum of ID's plan + ac (operator uses it to lock)
  board              list idea-board posts: id state by posted replies text [tags]
                     (--open, --stale = open, no reply, posted > 14 days ago; --tag T)

Filters (combine; all must hold):
  --tag T            repeatable; T may be a comma list (a tag group)
  --match any|all    tag group semantics (default any)
  --stage S          idea | spec | locked   (comma list allowed)
  --status S         todo | doing | review | done | dropped (comma list allowed)
  --performer NAME   performing_agent = NAME (alias: --owner)
  --coordinator NAME coordinating_agent = NAME
  --roster PATH      agent roster for check (default: [meta] roster, else
                     /workspace/spectral/agents.toml)
  --blocked          open items with an unresolved blocker
  --ready            locked, status todo, no unresolved blocker
  --claimable        ready + ac and plan present + lock_sum matches + unclaimed

Output:
  (default)          one line: id  stage/status  title  [tags]  @performing_agent
  --detail           full TOML of each item
  --json             one JSON object per line

Project mode is chosen when the file is named work.toml, when [meta] has
profile = 'project', or with --profile project. Default file: ./work.toml.}
    exit $code
}

proc almanac::proj::main {argv} {
    set path ""
    set tags {}
    set match any
    set stages {}
    set statuses {}
    set owner ""
    set coord ""
    set ::almanac::proj::ROSTER_ARG ""
    set want_blocked 0
    set want_ready 0
    set want_claimable 0
    set detail 0
    set json 0
    set pos {}
    for {set i 0} {$i < [llength $argv]} {incr i} {
        set a [lindex $argv $i]
        switch -- $a {
            -h - --help { almanac::proj::usage 0 }
            --file   { incr i; set path [lindex $argv $i] }
            --tag    { incr i; lappend tags [split [lindex $argv $i] ,] }
            --match  { incr i; set match [lindex $argv $i] }
            --stage  { incr i; lappend stages {*}[split [lindex $argv $i] ,] }
            --status { incr i; lappend statuses {*}[split [lindex $argv $i] ,] }
            --owner - --performer { incr i; set owner [lindex $argv $i] }
            --coordinator { incr i; set coord [lindex $argv $i] }
            --roster { incr i; set ::almanac::proj::ROSTER_ARG [lindex $argv $i] }
            --blocked   { set want_blocked 1 }
            --ready     { set want_ready 1 }
            --claimable { set want_claimable 1 }
            --open   { set ::almanac::proj::BOARD_OPEN 1 }
            --stale  { set ::almanac::proj::BOARD_STALE 1 }
            --detail - --toml { set detail 1 }
            --json   { set json 1 }
            default {
                if {[string match -* $a]} { almanac::die "unknown flag: $a (use -h)" }
                lappend pos $a
            }
        }
    }
    if {$match ni {any all}} { almanac::die "--match must be any or all" }
    if {$path eq ""} { set path work.toml }
    if {[llength $pos] < 1} { almanac::proj::usage }
    set verb [lindex $pos 0]
    set rest [lrange $pos 1 end]
    set doc [almanac::load $path]
    set ctx [almanac::proj::ctx $doc]

    switch -- $verb {
        check {
            exit [almanac::proj::check $ctx $doc $path]
        }
        lock-sum {
            set id [lindex $rest 0]
            if {$id eq "" || $id ni [almanac::proj::ids $doc]} { almanac::die "lock-sum: no such item: $id" }
            puts [almanac::proj::lock_sum $doc $id]
            return
        }
        show {
            set id [lindex $rest 0]
            if {$id eq "" || $id ni [almanac::proj::ids $doc]} { almanac::die "show: no such item: $id" }
            if {$json} { puts [almanac::proj::json_item $ctx $doc $id] } else { almanac::proj::emit_item $doc $id }
            return
        }
        board {
            almanac::proj::board_list $doc $path $tags
            return
        }
        claimable { set want_claimable 1 }
        ls - filter {}
        add - set - done - today - init - doctor {
            almanac::die "$verb: personal-mode verb; in project mode edit work.toml by hand (see the onboarding doc)"
        }
        default { almanac::die "unknown verb: $verb (use -h)" }
    }

    foreach id [almanac::proj::ids $doc] {
        set itags [almanac::proj::a $doc $id tags]
        set ok 1
        foreach group $tags {
            set hits 0
            foreach t $group { if {$t in $itags} { incr hits } }
            if {$match eq "any" && $hits == 0} { set ok 0 }
            if {$match eq "all" && $hits < [llength $group]} { set ok 0 }
        }
        if {$ok && [llength $stages] && [almanac::proj::s $doc $id stage] ni $stages} { set ok 0 }
        if {$ok && [llength $statuses] && [almanac::proj::s $doc $id status] ni $statuses} { set ok 0 }
        if {$ok && $owner ne "" && [almanac::proj::s $doc $id performing_agent] ne $owner} { set ok 0 }
        if {$ok && $coord ne "" && [almanac::proj::s $doc $id coordinating_agent] ne $coord} { set ok 0 }
        if {$ok && $want_blocked && ![almanac::proj::blocked $ctx $doc $id]} { set ok 0 }
        if {$ok && $want_ready && ![almanac::proj::ready $ctx $doc $id]} { set ok 0 }
        if {$ok && $want_claimable && ![almanac::proj::claimable $ctx $doc $id]} { set ok 0 }
        if {!$ok} continue
        if {$json} {
            puts [almanac::proj::json_item $ctx $doc $id]
        } elseif {$detail} {
            almanac::proj::emit_item $doc $id
            puts ""
        } else {
            puts [almanac::proj::line $doc $id]
        }
    }
}

proc almanac::proj::check {ctx doc path} {
    variable STAGES
    variable TAG_HEADS
    set errs {}
    set fh [open $path rb]
    set text [encoding convertfrom utf-8 [read $fh]]
    close $fh
    # Raw scan: headers (duplicates, id shape) and tags quoting.
    set seen [dict create]
    set cur ""
    set ln 0
    foreach line [split $text \n] {
        incr ln
        set t [string trim $line]
        if {[regexp {^\[([^\]]+)\]\s*(#.*)?$} $t -> name]} {
            set cur $name
            if {[dict exists $seen $name]} {
                lappend errs "line $ln: duplicate table \[$name\]"
            }
            dict set seen $name 1
            if {[regexp {^board\.(.*)$} $name -> bid]} {
                if {![regexp {^[0-9a-z]{4}$} $bid]} { lappend errs "line $ln: \[$name\]: board id must be 4 lowercase letters or digits" }
                if {[dict exists $seen $bid]} { lappend errs "line $ln: board id '$bid' is also an item id" }
                dict set seen board:$bid 1
                continue
            }
            if {[dict exists $seen board:$name]} { lappend errs "line $ln: item id '$name' is also a board id" }
            if {$name ne "meta" && ![regexp {^[0-9a-z]{4}$} $name]} {
                lappend errs "line $ln: \[$name\]: id must be 4 lowercase letters or digits"
            }
            continue
        }
        if {$cur ne "meta" && [regexp {^tags\s*=\s*(.*)$} $t -> rhs]} {
            if {![regexp {^\[\s*('[^']*'\s*(,\s*'[^']*'\s*)*)?\]$} $rhs]} {
                lappend errs "line $ln: \[$cur\]: tags must be an array of single-quoted strings"
            }
        }
    }
    set all [almanac::proj::ids $doc]
    set statuses [dict get $ctx statuses]
    # Agent whitelist: [meta] agents, each of which must be in the roster.
    set meta_agents {}
    if {[dict exists $doc tables meta]} {
        set meta_agents [almanac::array_texts [almanac::task_kv $doc meta] agents]
    }
    if {[llength $meta_agents] == 0} { lappend errs "\[meta\]: agents must list the allocated agent names allowed in this repo" }
    set rpath [almanac::proj::roster_path $doc $path]
    set roster [almanac::proj::roster_names $rpath]
    if {$roster eq "-"} {
        lappend errs "\[meta\]: agent roster not readable: $rpath"
    } else {
        foreach n $meta_agents {
            if {$n ni $roster} { lappend errs "\[meta\]: agent '$n' is not allocated in roster $rpath" }
        }
    }
    foreach id $all {
        set p "\[$id\]"
        set kv [almanac::task_kv $doc $id]
        set stage [almanac::proj::s $doc $id stage]
        set status [almanac::proj::s $doc $id status]
        if {[almanac::proj::s $doc $id title] eq ""} { lappend errs "$p: missing title" }
        if {$stage ni $STAGES} { lappend errs "$p: stage must be idea, spec or locked (got '$stage')" }
        set tags [almanac::proj::a $doc $id tags]
        if {[llength $tags] == 0 || [lindex $tags 0] ni $TAG_HEADS} {
            lappend errs "$p: tags must start with 'work'"
        }
        if {$stage ne "locked"} {
            foreach k {status locked_by locked lock_sum performing_agent} {
                if {[dict exists $kv $k]} { lappend errs "$p: $k is only allowed on locked items (stage is '$stage')" }
            }
        } else {
            if {$status eq ""} { lappend errs "$p: locked item needs a status" } elseif {$status ni $statuses} {
                lappend errs "$p: status '$status' is not one of: [join $statuses {, }]"
            }
            if {[llength [concat [almanac::proj::a $doc $id ac] [almanac::proj::a $doc $id ac_done]]] == 0} {
                lappend errs "$p: locked item needs ac"
            }
            if {[string trim [almanac::proj::s $doc $id plan]] eq ""} { lappend errs "$p: locked item needs plan" }
            if {[almanac::proj::s $doc $id locked_by] ne "operator"} { lappend errs "$p: locked_by must be 'operator'" }
            set lk [almanac::proj::s $doc $id locked]
            if {![almanac::proj::iso_ok $lk] && ![regexp {^[0-9]{10}$} $lk]} {
                lappend errs "$p: locked must be ISO 8601 UTC (or a legacy YYMMDDHHMM integer)"
            }
            set want [almanac::proj::lock_sum $doc $id]
            set have [almanac::proj::s $doc $id lock_sum]
            if {$have ne $want} {
                lappend errs "$p: lock_sum '$have' does not match plan+ac ($want); plan or ac changed after locking: set stage = 'spec' and clear status, locked_by, locked, lock_sum"
            }
            if {$status in {doing review done} && [almanac::proj::s $doc $id performing_agent] eq ""} {
                lappend errs "$p: status '$status' needs performing_agent"
            }
            if {[almanac::proj::s $doc $id coordinating_agent] eq ""} {
                lappend errs "$p: locked item needs coordinating_agent"
            }
        }
        foreach k {coordinating_agent performing_agent} {
            if {![dict exists $kv $k]} continue
            set v [dict get $kv $k]
            if {[catch {tama::valtype $v} vty] || $vty ne "string" || [string trim [tama::valtext $v]] eq ""} {
                lappend errs "$p: $k must be a non-empty string agent name"
            } elseif {[tama::valtext $v] ni $meta_agents} {
                lappend errs "$p: $k '[tama::valtext $v]' is not in \[meta\] agents ([join $meta_agents {, }])"
            }
        }
        if {[dict exists $kv claimed_by]} { lappend errs "$p: claimed_by is replaced by performing_agent" }
        # Timestamps: updated/completed are ISO 8601 UTC (YYYY-MM-DDTHH:MM:SSZ).
        set closed [expr {$status in [dict get $ctx closed]}]
        set upd [almanac::proj::s $doc $id updated]
        set cmp [almanac::proj::s $doc $id completed]
        set upd_ok [almanac::proj::iso_ok $upd]
        if {[dict exists $kv updated] && !$upd_ok} {
            lappend errs "$p: updated '$upd' must be ISO 8601 UTC like 2026-10-10T01:56:00Z"
        }
        if {[dict exists $kv completed] && ![almanac::proj::iso_ok $cmp]} {
            lappend errs "$p: completed '$cmp' must be ISO 8601 UTC like 2026-10-10T01:56:00Z"
        }
        if {$closed && ![dict exists $kv completed]} {
            lappend errs "$p: status '$status' needs completed"
        }
        if {!$closed && [dict exists $kv completed]} {
            lappend errs "$p: completed is only allowed when status is done or dropped"
        }
        set cre [almanac::proj::s $doc $id created]
        if {$cre ne "" && $upd_ok} {
            set ce [almanac::proj::created_epoch $cre]
            if {$ce eq ""} {
                lappend errs "$p: created '$cre' must be a YYMMDDHHMM integer"
            } elseif {[almanac::proj::iso_epoch $upd] < $ce} {
                lappend errs "$p: updated '$upd' is older than created ($cre)"
            }
        }
        # commit: array of full 40-hex git hashes.
        if {[dict exists $kv commit]} {
            set cv [dict get $kv commit]
            if {[catch {tama::valtype $cv} cty] || $cty ne "array"} {
                lappend errs "$p: commit must be an array of full commit hashes"
            } else {
                foreach h [almanac::proj::a $doc $id commit] {
                    if {![regexp {^[0-9a-f]{40}$} $h]} { lappend errs "$p: commit '$h' is not a full 40-hex commit hash" }
                }
            }
        }
        if {$status eq "done" && [llength [almanac::proj::a $doc $id commit]] == 0} {
            lappend errs "$p: done item needs at least one commit"
        }
        foreach b [almanac::proj::a $doc $id blockers] {
            if {[regexp {^[A-Za-z0-9_.-]+:[0-9a-z]{4}$} $b]} continue
            if {$b ni $all} { lappend errs "$p: blocker '$b' is not an item in this file (cross-repo blockers are 'repo:id')" }
            if {$b eq $id} { lappend errs "$p: blocks itself" }
        }
    }
    # from_board on items must name a board post.
    set bids [almanac::proj::board_ids $doc]
    foreach id $all {
        set fb [almanac::proj::s $doc $id from_board]
        if {$fb ne "" && $fb ni $bids} { lappend errs "\[$id\]: from_board '$fb' is not a board post" }
    }
    lappend errs {*}[almanac::proj::board_check $doc $path $meta_agents $all]
    if {[llength $errs]} {
        foreach e $errs { puts stderr "check: $e" }
        puts stderr "check: [llength $errs] violation(s) in $path"
        return 1
    }
    puts "check: ok ([llength $all] items, $path)"
    return 0
}

# --- main ---

proc almanac::main {argv} {
    variable DEFAULT_FILE

    # Project mode (work.toml) is a separate read-only path; personal mode
    # below is unchanged. --profile is stripped before personal parsing.
    lassign [almanac::proj::wants $argv] pmode ppath prest
    if {$pmode ni {"" personal project}} { almanac::die "--profile must be personal or project" }
    if {$pmode eq "project" || ($pmode eq "" && $ppath ne "" && [almanac::proj::is_project_file $ppath])} {
        almanac::proj::main $prest
        return
    }
    set argv $prest

    if {[llength $argv] == 0} { almanac::usage }

    set spec {
        {{-h --help} flag help}
        {--file      option file}
        {--toml      flag toml}
    }
    set parsed [cli::parse $argv $spec -defaults [dict create help 0 file $DEFAULT_FILE toml 0]]
    if {[lindex $parsed 0] ne "ok"} {
        set kind [lindex $parsed 1]
        set flag [lindex $parsed 2]
        if {$kind eq "unknown-flag"} { almanac::die "unknown flag: $flag (use -h)" }
        if {$kind eq "missing-value"} { almanac::die "missing value for $flag" }
        almanac::die "parse error"
    }
    lassign $parsed _ flags positionals
    if {[dict get $flags help]} { almanac::usage 0 }

    if {[llength $positionals] < 1} { almanac::usage }
    set verb [lindex $positionals 0]
    set rest [lrange $positionals 1 end]
    set path [dict get $flags file]
    set toml [dict get $flags toml]

    switch -- $verb {
        init {
            almanac::cmd_init $path
        }
        add {
            almanac::cmd_add $path {*}$rest
        }
        set {
            if {[llength $rest] < 1} { almanac::die "set: need id" }
            almanac::cmd_set $path [lindex $rest 0] {*}[lrange $rest 1 end]
        }
        done {
            if {[llength $rest] < 1} { almanac::die "done: need id" }
            almanac::cmd_done $path [lindex $rest 0]
        }
        ls -
        filter {
            set doc [almanac::load $path]
            almanac::cmd_ls $doc $toml {*}$rest
        }
        today {
            set doc [almanac::load $path]
            almanac::cmd_today $doc $toml {*}$rest
        }
        ready {
            set doc [almanac::load $path]
            almanac::cmd_ready $doc $toml {*}$rest
        }
        blockers {
            set doc [almanac::load $path]
            almanac::cmd_blockers $doc $rest $toml
        }
        validate {
            set doc [almanac::load $path]
            almanac::cmd_validate $doc $path
        }
        doctor {
            almanac::cmd_doctor $path
        }
        now {
            # Tiny helper for agents/scripts.
            puts [almanac::now]
        }
        default {
            almanac::die "unknown verb: $verb (use -h)"
        }
    }
}

if {[cli::running_as_program [info script]]} {
    almanac::main $::argv
}
