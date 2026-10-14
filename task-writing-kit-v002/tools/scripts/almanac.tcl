#!/workspace/system/deps/tcl
# almanac.tcl — tasks.toml CLI (labor-os monolith)
#
# Spec: /workspace/system/spec/task-spec.md v0.3.1
# Building blocks: cli.tcl + tama.tcl (this scripts/ tree; tama wraps lib/tosu).
# Runtime: zipkit Tcl 9.0.4 at system/deps/tcl (shebang). Also works under tclsh 8.6+.
#
# --file defaults to /workspace/system/work/tasks.toml
# Verbs: init add ls set done today ready blockers validate doctor filter show change apply preview
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
    variable STATUS_ORDER {urgent now progress today later deferred sched done REMOVE}
    variable STATUS_ENUM {urgent now progress today later deferred sched done REMOVE}
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
  show ID              print one task by id (full table, including notes)
  change ID TEXT       append '>change (YY-MM-DD hh:mm AM): TEXT' to the task's notes
  validate             schema checks against v0.3.2 (report; non-zero if errors)
  apply PATCH          rebase PATCH (unified diff) onto --file and write FILE.patched; never
                       touches --file. Table-level by task id (needs the patch's base, see
                       --base), falling back to a strict line diff. Exit 3 on conflicts.
  preview ?OUT.html?   render --file as one standalone Sight HTML page (default preview.html);
                       REMOVE cards hidden by default; with --base, new/changed/done/remove
                       cards are marked and a review panel is added
  doctor               health: file/parse/schema + verb smoke + bake/hook checks

filters (ls / filter / today / ready):
  STATUS               bare status token (urgent|now|progress|today|later|deferred|sched|done|REMOVE)
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
  --base PATH          apply: the file the patch was made against (default snapshot/tasks.toml
                       beside the kit); preview: compare against PATH and mark differences
  --out PATH           apply: output file (default FILE.patched)
  --force              apply: write even if validation errors rise
  --take-patch         apply: on conflict, take the patch's version of the task
  --line-diff          apply: skip table-level mode, strict line diff on --file
  --skin DIR           preview: skin folder (default ../../skin beside this script)
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
        if {$k eq "id"} {
            if {$id ne $v} { return 0 }
            continue
        }
        if {![almanac::key_matches $kv $k $v]} { return 0 }
    }
    foreach k [dict get $filters has] {
        if {$k eq "id"} continue
        if {![almanac::key_present $kv $k]} { return 0 }
    }
    foreach k [dict get $filters missing] {
        if {$k eq "id"} { return 0 }
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

# --- apply (v002): rebase a patch onto a target and write TARGET.patched ---
#
# Primary mode is table-level: the patch is applied strictly to its base (the
# snapshot it was made against), the base and the result are compared table by
# table, and each touched task id is then inserted, replaced or removed in the
# target. Untouched tasks in the target are left alone, so a target that has
# moved on since the snapshot still takes the patch. Fallback mode applies the
# unified diff strictly (no fuzz) to the target itself. The target is never
# modified; the result goes to a new file.

# Split TOML text into {preamble_lines blocks nl_end}. A block is
# {name body_lines trail_lines}; trail_lines are the blank lines after it.
# Lines inside ''' or """ strings are never taken for table headers.
proc almanac::split_blocks {text} {
    set nl_end [expr {[string index $text end] eq "\n"}]
    if {$nl_end} { set text [string range $text 0 end-1] }
    set pre {}
    set blocks {}
    set name {}
    set body {}
    set have 0
    set ml {}
    foreach ln [split $text "\n"] {
        if {$ml eq "" && [regexp {^\[([^\[\]]+)\][ \t]*$} $ln -> nm]} {
            if {$have} { lappend blocks [almanac::finish_block $name $body] }
            set have 1
            set name [string trim $nm]
            set body [list $ln]
            continue
        }
        if {$have} { lappend body $ln } else { lappend pre $ln }
        foreach d [list ''' {"""}] {
            if {$ml eq "" || $ml eq $d} {
                set c [expr {([string length $ln] - [string length [string map [list $d {}] $ln]]) / 3}]
                if {$c % 2} { set ml [expr {$ml eq "" ? $d : ""}] }
            }
        }
    }
    if {$have} { lappend blocks [almanac::finish_block $name $body] }
    return [list $pre $blocks $nl_end]
}

proc almanac::finish_block {name body} {
    set trail {}
    while {[llength $body] > 1 && [string trim [lindex $body end]] eq ""} {
        set trail [linsert $trail 0 [lindex $body end]]
        set body [lrange $body 0 end-1]
    }
    return [list $name $body $trail]
}

proc almanac::join_blocks {pre blocks nl_end} {
    set lines $pre
    foreach b $blocks {
        lappend lines {*}[lindex $b 1] {*}[lindex $b 2]
    }
    set text [join $lines "\n"]
    if {$nl_end} { append text "\n" }
    return $text
}

proc almanac::block_index {blocks name} {
    set i 0
    foreach b $blocks {
        if {[lindex $b 0] eq $name} { return $i }
        incr i
    }
    return -1
}

# Parse a one-file unified diff. Returns a list of hunks, each
# {old_start old_count tag_text_pairs}. Dies with a clear message on bad input.
proc almanac::parse_patch {text} {
    set lines [split $text "\n"]
    if {[lindex $lines end] eq ""} { set lines [lrange $lines 0 end-1] }
    set n [llength $lines]
    set headers 0
    set hunks {}
    set i 0
    while {$i < $n} {
        set ln [lindex $lines $i]
        if {[string match {--- *} $ln] && $i + 1 < $n && [string match {+++ *} [lindex $lines [expr {$i + 1}]]]} {
            incr headers
            incr i 2
            continue
        }
        if {![regexp {^@@ -([0-9]+)(?:,([0-9]+))? \+([0-9]+)(?:,([0-9]+))? @@} $ln -> os oc ns nc]} {
            incr i
            continue
        }
        if {$headers == 0} { almanac::die "apply: hunk before any ---/+++ file header" }
        if {$oc eq ""} { set oc 1 }
        if {$nc eq ""} { set nc 1 }
        set body {}
        set so 0
        set sn 0
        incr i
        while {$i < $n && ($so < $oc || $sn < $nc)} {
            set l [lindex $lines $i]
            set tag [string index $l 0]
            if {$tag eq "\\"} { incr i; continue }
            if {$tag ni {" " - +}} {
                if {$l eq ""} { set tag " "; set l " " } else {
                    almanac::die "apply: bad hunk line [expr {$i + 1}] of the patch: [string range $l 0 40]"
                }
            }
            lappend body [list $tag [string range $l 1 end]]
            if {$tag in {" " -}} { incr so }
            if {$tag in {" " +}} { incr sn }
            incr i
        }
        if {$so != $oc || $sn != $nc} { almanac::die "apply: hunk at old line $os is truncated" }
        lappend hunks [list $os $oc $body]
    }
    if {$headers != 1} { almanac::die "apply: the patch must be a unified diff of exactly one file (found $headers file headers)" }
    if {[llength $hunks] == 0} { almanac::die "apply: the patch has no hunks" }
    return $hunks
}

# Strict apply of hunks to a list of lines (no fuzz, no offset search).
# Returns {ok lines} or {error message naming the failing hunk}.
proc almanac::apply_hunks {src hunks what} {
    set out {}
    set pos 0
    set hn 0
    foreach h $hunks {
        incr hn
        lassign $h os oc body
        set old {}
        set new {}
        foreach pair $body {
            lassign $pair tag t
            if {$tag in {" " -}} { lappend old $t }
            if {$tag in {" " +}} { lappend new $t }
        }
        set start [expr {[llength $old] > 0 ? $os - 1 : $os}]
        set have [lrange $src $start [expr {$start + [llength $old] - 1}]]
        if {$have ne $old} {
            set k 0
            foreach o $old {
                if {[lindex $src [expr {$start + $k}]] ne $o} { break }
                incr k
            }
            return [list error "hunk $hn (@@ -$os,$oc) does not match $what at line [expr {$start + $k + 1}]: expected '[string range [lindex $old $k] 0 60]' but found '[string range [lindex $src [expr {$start + $k}]] 0 60]'"]
        }
        if {$start < $pos} { return [list error "hunk $hn (@@ -$os,$oc) overlaps the previous hunk"] }
        lappend out {*}[lrange $src $pos [expr {$start - 1}]] {*}$new
        set pos [expr {$start + [llength $old]}]
    }
    lappend out {*}[lrange $src $pos end]
    return [list ok $out]
}

proc almanac::text_lines {text} {
    set nl_end [expr {[string index $text end] eq "\n"}]
    if {$nl_end} { set text [string range $text 0 end-1] }
    return [list [split $text "\n"] $nl_end]
}

# Table-level plan: compare base and result block lists.
# Returns {added changed removed} as lists of names (result order for added/changed).
proc almanac::block_diff {base_blocks res_blocks} {
    set bd [dict create]
    foreach b $base_blocks { dict set bd [lindex $b 0] [join [lindex $b 1] "\n"] }
    set rd [dict create]
    foreach b $res_blocks { dict set rd [lindex $b 0] [join [lindex $b 1] "\n"] }
    set added {}
    set changed {}
    set removed {}
    foreach b $res_blocks {
        set nm [lindex $b 0]
        if {![dict exists $bd $nm]} { lappend added $nm } elseif {[dict get $bd $nm] ne [dict get $rd $nm]} { lappend changed $nm }
    }
    foreach b $base_blocks {
        if {![dict exists $rd [lindex $b 0]]} { lappend removed [lindex $b 0] }
    }
    return [list $added $changed $removed]
}

proc almanac::cmd_apply {path patchfile opts} {
    set base [dict get $opts base]
    set out [dict get $opts out]
    set force [dict get $opts force]
    set take [dict get $opts take]
    set linediff [dict get $opts linediff]
    if {$patchfile eq ""} { almanac::die "apply: need a patch file" }
    if {![file isfile $patchfile]} { almanac::die "apply: no such patch: $patchfile" }
    if {![file isfile $path]} { almanac::die "apply: no such target: $path" }
    if {$out eq ""} { set out "$path.patched" }
    if {[file normalize $out] eq [file normalize $path]} {
        almanac::die "apply: refusing to write over the target; apply only writes a new file (use --out)"
    }
    set hunks [almanac::parse_patch [almanac::read_text $patchfile]]
    set target_text [almanac::read_text $path]
    lassign [almanac::text_lines $target_text] tlines tnl

    # Pick a base: --base, else the kit snapshot beside this script, else none.
    set base_explicit [expr {$base ne ""}]
    if {$base eq ""} {
        set cand [file join $::ALMANAC_DIR .. .. snapshot tasks.toml]
        if {[file isfile $cand]} { set base $cand }
    }
    set mode line
    set note ""
    set result_text ""
    set counts [dict create added 0 changed 0 removed 0 already 0 conflicts 0]
    set conflicts {}
    set warns {}

    if {!$linediff && $base ne ""} {
        if {![file isfile $base]} { almanac::die "apply: no such base: $base" }
        lassign [almanac::text_lines [almanac::read_text $base]] blines bnl
        set r [almanac::apply_hunks $blines $hunks "the base ($base)"]
        if {[lindex $r 0] eq "ok"} {
            set mode table
            set res_text [join [lindex $r 1] "\n"]
            if {$bnl} { append res_text "\n" }
        } elseif {$base_explicit} {
            almanac::die "apply: the patch does not apply to the given base: [lindex $r 1]"
        } else {
            set note "table-level mode skipped: [lindex $r 1]"
        }
    } elseif {!$linediff} {
        set note "table-level mode skipped: no base (give --base, or keep snapshot/tasks.toml beside the kit)"
    }

    if {$mode eq "table"} {
        lassign [almanac::split_blocks [almanac::read_text $base]] bpre bblocks _
        lassign [almanac::split_blocks $res_text] rpre rblocks _
        lassign [almanac::split_blocks $target_text] tpre tblocks tnl2
        lassign [almanac::block_diff $bblocks $rblocks] added changed removed
        set bd [dict create]
        foreach b $bblocks { dict set bd [lindex $b 0] [join [lindex $b 1] "\n"] }
        set rd [dict create]
        foreach b $rblocks { dict set rd [lindex $b 0] [join [lindex $b 1] "\n"] }
        set rbody [dict create]
        foreach b $rblocks { dict set rbody [lindex $b 0] [lindex $b 1] }

        if {$bpre ne $rpre} {
            if {$tpre eq $bpre || $take} { set tpre $rpre } else { lappend conflicts [list (top-of-file) "the text above the first table differs in the target"] }
        }
        foreach nm $changed {
            set i [almanac::block_index $tblocks $nm]
            if {$i < 0} {
                if {$take} { lappend added $nm } else { lappend conflicts [list $nm "changed by the patch but missing in the target"] }
                continue
            }
            set cur [join [lindex $tblocks $i 1] "\n"]
            if {$cur eq [dict get $rd $nm]} {
                dict incr counts already
            } elseif {$cur eq [dict get $bd $nm] || $take} {
                lset tblocks $i 1 [dict get $rbody $nm]
                dict incr counts changed
            } else {
                lappend conflicts [list $nm "the target changed this task since the base; kept the target's version"]
            }
        }
        foreach nm $removed {
            set i [almanac::block_index $tblocks $nm]
            if {$i < 0} { dict incr counts already; continue }
            set cur [join [lindex $tblocks $i 1] "\n"]
            if {$cur eq [dict get $bd $nm] || $take} {
                set tblocks [lreplace $tblocks $i $i]
                dict incr counts removed
                lappend warns "removed $nm: [almanac::block_title [lindex $bblocks [almanac::block_index $bblocks $nm] 1]]"
            } else {
                lappend conflicts [list $nm "removed by the patch but the target changed it; kept the target's version"]
            }
        }
        # Inserts last, in result order, each after the nearest preceding result table the target has.
        foreach nm $added {
            set i [almanac::block_index $tblocks $nm]
            if {$i >= 0} {
                if {[join [lindex $tblocks $i 1] "\n"] eq [dict get $rd $nm]} {
                    dict incr counts already
                } elseif {$take} {
                    lset tblocks $i 1 [dict get $rbody $nm]
                    dict incr counts changed
                } else {
                    lappend conflicts [list $nm "the patch adds this id but the target already has a different task with it; kept the target's version"]
                }
                continue
            }
            set ri [almanac::block_index $rblocks $nm]
            set anchor -1
            for {set k [expr {$ri - 1}]} {$k >= 0} {incr k -1} {
                set a [almanac::block_index $tblocks [lindex $rblocks $k 0]]
                if {$a >= 0} { set anchor $a; break }
            }
            set pos [expr {$anchor + 1}]
            if {$pos >= [llength $tblocks]} {
                if {[llength $tblocks] > 0 && [llength [lindex $tblocks end 2]] == 0} { lset tblocks end 2 [list ""] }
                lappend tblocks [list $nm [dict get $rbody $nm] {}]
            } else {
                set tblocks [linsert $tblocks $pos [list $nm [dict get $rbody $nm] [list ""]]]
            }
            dict incr counts added
        }
        set result_text [almanac::join_blocks $tpre $tblocks $tnl2]
    } else {
        set r [almanac::apply_hunks $tlines $hunks "the target ($path)"]
        if {[lindex $r 0] ne "ok"} {
            almanac::die "apply: $note[expr {$note ne "" ? "; " : ""}]line-diff fallback failed: [lindex $r 1]"
        }
        set result_text [join [lindex $r 1] "\n"]
        if {$tnl} { append result_text "\n" }
        lassign [almanac::split_blocks $target_text] _ tb _
        lassign [almanac::split_blocks $result_text] _ rb _
        lassign [almanac::block_diff $tb $rb] added changed removed
        dict set counts added [llength $added]
        dict set counts changed [llength $changed]
        dict set counts removed [llength $removed]
        foreach nm $removed {
            lappend warns "removed $nm: [almanac::block_title [lindex $tb [almanac::block_index $tb $nm] 1]]"
        }
    }

    # Validate the result before writing; refuse if it is worse than the target.
    set before [almanac::error_count $target_text]
    set after [almanac::error_count $result_text]
    if {$after eq "parse"} {
        if {!$force} { almanac::die "apply: the result does not parse as TOML; nothing written (use --force to write it anyway)" }
    } elseif {$before ne "parse" && $after > $before} {
        puts stderr "apply: validation errors would rise from $before to $after; details:"
        set tmp [file join [file dirname $out] ".[file tail $out].check.[pid]"]
        almanac::atomic_write $tmp $result_text
        catch {almanac::validate_report [almanac::load $tmp] $tmp 0}
        file delete -force $tmp
        if {!$force} { almanac::die "apply: nothing written (use --force to write it anyway)" }
    }
    almanac::atomic_write $out $result_text

    puts "apply: mode=$mode patch=$patchfile target=$path"
    if {$note ne ""} { puts "apply: $note" }
    if {$mode eq "table"} { puts "apply: base=$base" }
    puts "apply: added [dict get $counts added], changed [dict get $counts changed], removed [dict get $counts removed], already applied [dict get $counts already], conflicts [llength $conflicts]"
    foreach w $warns { puts "WARN  $w" }
    foreach c $conflicts { puts "CONFLICT  [lindex $c 0]: [lindex $c 1]" }
    puts "apply: wrote $out"
    if {[llength $conflicts] > 0} { exit 3 }
}

# Error count for a TOML text, or "parse" if it does not parse.
proc almanac::error_count {text} {
    set r [tama::parse $text {}]
    if {[lindex $r 0] eq "error"} { return parse }
    set doc [expr {[lindex $r 0] eq "ok" ? [lindex $r 1] : $r}]
    return [lindex [almanac::validate_report $doc {} 1] 0]
}

proc almanac::block_title {body} {
    foreach ln $body {
        if {[regexp {^title = '(.*)'\s*$} $ln -> t]} { return $t }
        if {[regexp {^title = "(.*)"\s*$} $ln -> t]} { return $t }
    }
    return ""
}

# --- change (v002): append a stamped change line to a task's notes ---

proc almanac::change_stamp {} {
    variable TZ
    return [clock format [clock seconds] -format {%y-%m-%d %I:%M %p} -timezone $TZ]
}

proc almanac::cmd_change {path id args} {
    if {$id eq ""} { almanac::die "change: need id" }
    if {![regexp {^[a-z0-9]{4}$} $id] && $id ne "root"} { almanac::die "change: bad id: $id" }
    set text [string trim [join $args " "]]
    if {$text eq ""} { almanac::die "change: need a change note" }
    if {[string first "\n" $text] >= 0} { almanac::die "change: the note must be one line" }
    set doc [almanac::load $path]
    lassign [almanac::fields_from_doc $doc $id] fields order
    set notes {}
    if {[dict exists $fields notes]} { set notes [dict get $fields notes] }
    set notes [string trimright $notes "\n"]
    if {[string index $notes 0] eq "\n"} { set notes [string range $notes 1 end] }
    set line ">change ([almanac::change_stamp]): $text"
    if {[string trim $notes] eq ""} { set notes $line } else { append notes "\n" $line }
    dict set fields notes $notes
    if {"notes" ni $order} { lappend order notes }
    dict set fields updated [almanac::now]
    if {"updated" ni $order} { lappend order updated }
    almanac::ensure_tosu_tag fields
    almanac::splice_table $path $id [almanac::emit_task_table $id $fields $order]
    puts "ok change $id"
    almanac::after_mutation
}

# --- show (v002): one task by identity ---

proc almanac::cmd_show {path id} {
    if {$id eq ""} { almanac::die "show: need id" }
    set doc [almanac::load $path]
    if {$id ni [almanac::task_ids $doc]} { almanac::die "show: unknown id: $id" }
    lassign [almanac::fields_from_doc $doc $id] fields order
    puts -nonewline [almanac::emit_task_table $id $fields $order]
}

# --- preview (v002): one standalone Sight HTML page, no network, no encryption ---

# JSON string literal. ascii=1 escapes everything above U+007F (like json.dumps default).
proc almanac::jstr {s {ascii 0}} {
    set s [string map [list \\ \\\\ \" \\\" \b \\b \f \\f \n \\n \r \\r \t \\t] $s]
    if {[regexp {[\x00-\x1f]} $s] || ($ascii && [regexp {[^\x00-\x7f]} $s])} {
        set o {}
        foreach c [split $s ""] {
            scan $c %c cp
            if {$cp < 32} {
                append o [format {\u%04x} $cp]
            } elseif {$ascii && $cp > 127} {
                if {$cp > 0xFFFF} {
                    set v [expr {$cp - 0x10000}]
                    append o [format {\u%04x\u%04x} [expr {0xD800 + ($v >> 10)}] [expr {0xDC00 + ($v & 0x3FF)}]]
                } else {
                    append o [format {\u%04x} $cp]
                }
            } else {
                append o $c
            }
        }
        set s $o
    }
    return "\"$s\""
}

# TOML string for the board model: single-quoted when possible, else a JSON-style string.
proc almanac::pq {s} {
    if {[string first "'" $s] < 0 && ![regexp {[\x00-\x1f\x7f]} $s]} { return "'$s'" }
    return [almanac::jstr $s]
}

proc almanac::pqa {xs} {
    set o {}
    foreach x $xs { lappend o [almanac::pq $x] }
    return "\[[join $o {, }]\]"
}

proc almanac::hesc {s} {
    return [string map [list & &amp\; < &lt\; > &gt\; \" &quot\; ' &#x27\;] $s]
}

proc almanac::same_fields {a b} {
    if {[dict size $a] != [dict size $b]} { return 0 }
    dict for {k v} $a {
        if {![dict exists $b $k] || [dict get $b $k] ne $v} { return 0 }
    }
    return 1
}

# Plain fields (arrays stay lists, flagged by key) for every task id of a doc.
proc almanac::preview_tasks {doc} {
    set tasks [dict create]
    foreach id [almanac::task_ids $doc] {
        lassign [almanac::fields_from_doc $doc $id] fields order
        dict set tasks $id $fields
    }
    return $tasks
}

proc almanac::show_field {k v} {
    if {[almanac::is_array_key $k]} { return "\[[join $v {, }]\]" }
    return $v
}

# Board model (TOML text) and per-task notes snippets, mirroring board-export's card shape.
proc almanac::preview_model {doc show_notes_for source} {
    variable STATUS_ORDER
    set today [almanac::today_datetime]
    set ids {}
    foreach k [almanac::task_ids $doc] {
        if {$k eq "root"} continue
        if {[almanac::task_status $doc $k] eq ""} continue
        lappend ids $k
    }
    set dec {}
    foreach k $ids {
        set st [almanac::task_status $doc $k]
        set r [lsearch -exact $STATUS_ORDER $st]
        lappend dec [list [expr {$r < 0 ? 99 : $r}] $k]
    }
    set ids {}
    foreach row [lsort -integer -index 0 $dec] { lappend ids [lindex $row 1] }
    set now [clock seconds]
    set lines [list "# almanac preview board-model (unencrypted preview)" \
        "schema = 'labor-os.board-model/v1'" "generator = 'almanac.tcl preview'" "generator_version = '1'" \
        "generated = [almanac::now]" "generated_datetime = [almanac::pq $today]" "source = [almanac::pq $source]" \
        "stable_path = 'preview'" "include_done = true" "card_count = [llength $ids]" ""]
    set notes [dict create]
    foreach k $ids {
        set kv [almanac::task_kv $doc $k]
        set tags [almanac::array_texts $kv tags]
        set tosu [expr {"tosu" in $tags}]
        set st [almanac::task_status $doc $k]
        set dt [almanac::norm_ws [almanac::scalar $kv datetime]]
        set L [list {[[cards]]} "id = [almanac::pq $k]" "title = [almanac::pq [almanac::task_title $doc $k]]" "status = [almanac::pq $st]"]
        set body [string trim [almanac::scalar $kv notes]]
        foreach key {domain project} {
            set v [string trim [almanac::scalar $kv $key]]
            if {$v ne ""} { lappend L "$key = [almanac::pq $v]" }
        }
        if {$body ne "" && ($tosu || $k in $show_notes_for)} {
            lappend L "notes = [almanac::pq $body]"
            dict set notes $k "id = [almanac::pq $k]\nnotes = [almanac::jstr $body]\n"
        }
        foreach key {datetime time signaling-command} {
            set v [expr {$key eq "datetime" ? $dt : [string trim [almanac::scalar $kv $key]]}]
            if {$v ne ""} { lappend L "$key = [almanac::pq $v]" }
        }
        if {[dict exists $kv duration]} {
            set dv [dict get $kv duration]
            if {[tama::valtype $dv] eq "number"} { lappend L "duration = [tama::valtext $dv]" } else { lappend L "duration = [almanac::pq [tama::valtext $dv]]" }
        }
        if {$tosu} { lappend L "tosu = true" }
        if {[llength $tags]} { lappend L "tags = [almanac::pqa $tags]" }
        set has_rem [dict exists $kv reminder]
        if {$has_rem} {
            set rv [dict get $kv reminder]
            if {[tama::valtype $rv] eq "number"} { lappend L "reminder = [tama::valtext $rv]" } else { lappend L "reminder = [almanac::pq [tama::valtext $rv]]" }
        }
        set blockers [almanac::array_texts $kv blockers]
        set pending {}
        foreach b $blockers { if {[almanac::task_status $doc $b] ne "done"} { lappend pending $b } }
        foreach {key arr} [list coordinating-agents [almanac::array_texts $kv coordinating-agents] \
                field_links [almanac::array_texts $kv field_links] blockers $blockers blockers_pending $pending] {
            if {[llength $arr]} { lappend L "$key = [almanac::pqa $arr]" }
        }
        if {[llength $pending]} { lappend L "blockers_summary = [almanac::pq [join $pending ,]]" }
        set rem [expr {$has_rem || [string trim [almanac::scalar $kv signaling-command]] ne ""}]
        if {$st ne "done" && ($dt ne "" || $st eq "sched" || $rem)} { lappend L "timed = true" }
        if {($st in {sched today} && ($dt eq $today || ($st eq "today" && $dt eq ""))) || ($dt ne "" && $dt eq $today)} {
            lappend L "due_today = true"
        }
        lappend lines {*}$L ""
    }
    return [list "[join $lines "\n"]\n" $notes [llength $ids]]
}

proc almanac::inline_fonts {css skin} {
    set out {}
    set pos 0
    while {[regexp -indices -start $pos {url\("(fonts/[^"]+)"\)} $css m g]} {
        lassign $m ms me
        lassign $g gs ge
        append out [string range $css $pos [expr {$ms - 1}]]
        set p [file join $skin [string range $css $gs $ge]]
        if {![file isfile $p]} {
            append out {url("")}
        } else {
            set fh [open $p rb]
            set data [read $fh]
            close $fh
            set mime [expr {[string match *.woff2 $p] ? "font/woff2" : "font/ttf"}]
            append out "url(\"data:$mime;base64,[binary encode base64 $data]\")"
        }
        set pos [expr {$me + 1}]
    }
    append out [string range $css $pos end]
    return $out
}

proc almanac::cmd_preview {path outfile base skinarg} {
    variable TZ
    if {![file isfile $path]} { almanac::die "preview: no such file: $path" }
    set skin $skinarg
    if {$skin eq ""} {
        foreach cand [list [file join $::ALMANAC_DIR .. .. skin] [file join $::ALMANAC_DIR skin]] {
            if {[file isfile [file join $cand sight-index.html]]} { set skin $cand; break }
        }
    }
    if {$skin eq "" || ![file isfile [file join $skin sight-index.html]]} {
        almanac::die "preview: skin folder not found (need sight-index.html, artifacts.css, board.css, board.js, fonts/); give --skin DIR"
    }
    set doc [almanac::load $path]
    set r [almanac::preview_tasks $doc]

    # Compare against the base, if any: new / changed / done / remove marks.
    set new {}; set changed {}; set done {}; set remove {}; set gone {}
    set s [dict create]
    if {$base ne ""} {
        if {![file isfile $base]} { almanac::die "preview: no such base: $base" }
        set s [almanac::preview_tasks [almanac::load $base]]
        foreach k [dict keys $r] {
            if {$k eq "root"} continue
            if {![dict exists $s $k]} { lappend new $k; continue }
            set a [dict get $s $k]
            set b [dict get $r $k]
            if {[almanac::same_fields $a $b]} continue
            set sa [expr {[dict exists $a status] ? [dict get $a status] : ""}]
            set sb [expr {[dict exists $b status] ? [dict get $b status] : ""}]
            if {$sb eq "done" && $sa ne "done"} {
                lappend done $k
            } elseif {$sb eq "REMOVE" && $sa ne "REMOVE"} {
                lappend remove $k
            } else {
                lappend changed $k
            }
        }
        foreach k [dict keys $s] { if {$k ne "root" && ![dict exists $r $k]} { lappend gone $k } }
    }
    set touched [concat $new $changed $done $remove]
    set source [expr {$base ne "" ? "[file tail $path] compared with [file tail $base]" : [file tail $path]}]
    lassign [almanac::preview_model $doc $touched $source] model notes ncards

    set color [dict create new #2f7d4f changed #b8860b done #5a5aa8 remove #8b2e2e]
    set marks [dict create]
    foreach {kind lst} [list new $new changed $changed done $done remove $remove] {
        foreach k $lst { dict set marks $k $kind }
    }
    set hl {}
    dict for {k v} $marks {
        set c [dict get $color $v]
        append hl ".board-row\[data-id=\"$k\"\]{box-shadow:inset 0 0 0 2px $c;position:relative}" \
            ".board-row\[data-id=\"$k\"\]::after{content:\"$v\";position:absolute;bottom:.3rem;right:.4rem;" \
            "font:600 .66rem/1 \"IBM Plex Mono\",monospace;letter-spacing:.04em;text-transform:uppercase;" \
            "color:#fff;background:$c;padding:.18rem .35rem;border-radius:.2rem;pointer-events:none}" "\n"
    }
    set review_css {.twk-review{max-width:72rem;margin:1rem auto;padding:.75rem 1rem;border:1px solid #0002;border-radius:.35rem;background:#fffdf8;font:14px/1.45 "IBM Plex Sans",system-ui,sans-serif}.twk-review h2{font:500 1.05rem "IBM Plex Serif",serif;margin:.2rem 0 .5rem}.twk-review table{border-collapse:collapse;width:100%;font-size:.85rem}.twk-review td{border-top:1px solid #0001;padding:.25rem .4rem;vertical-align:top}.twk-review .k{font-family:"IBM Plex Mono",monospace;white-space:nowrap}.twk-review del{color:#8b2e2e}.twk-review ins{color:#2f7d4f;text-decoration:none}.twk-review a{font-family:"IBM Plex Mono",monospace}.twk-review pre{all:unset;display:block;white-space:pre-wrap;font:12px/1.4 "IBM Plex Mono",monospace;background:none;border:0;padding:0;margin:0}.twk-review table table td{border:0;padding:.1rem .4rem}.twk-review table table{table-layout:fixed}.twk-review table table td:nth-child(1){width:9rem}.twk-review table table td:nth-child(2){width:14rem}}

    # Review panel
    if {$base ne ""} {
        set rows {}
        foreach k $touched {
            set kind [dict get $marks $k]
            set a [expr {[dict exists $s $k] ? [dict get $s $k] : [dict create]}]
            set b [dict get $r $k]
            set keys [dict keys $a]
            foreach kk [dict keys $b] { if {$kk ni $keys} { lappend keys $kk } }
            set diffs {}
            foreach f $keys {
                set ha [dict exists $a $f]
                set hb [dict exists $b $f]
                set x [expr {$ha ? [almanac::show_field $f [dict get $a $f]] : ""}]
                set y [expr {$hb ? [almanac::show_field $f [dict get $b $f]] : ""}]
                if {$ha && $hb && [dict get $a $f] eq [dict get $b $f]} continue
                if {!$ha} { set x "∅" }
                if {!$hb} { set y "∅" }
                append diffs "<tr><td class=\"k\">[almanac::hesc $f]</td><td><del><pre>[almanac::hesc $x]</pre></del></td><td><ins><pre>[almanac::hesc $y]</pre></ins></td></tr>"
            }
            set title [expr {[dict exists $b title] ? [dict get $b title] : ""}]
            append rows "<tr><td class=\"k\" style=\"color:[dict get $color $kind]\">$kind</td><td><a href=\"#card-[almanac::hesc $k]\">[almanac::hesc $k]</a></td><td>[almanac::hesc $title]</td></tr>" \
                "<tr><td></td><td colspan=\"2\"><table>$diffs</table></td></tr>"
        }
        set summary "<section class=\"twk-review\" id=\"twk-review\"><h2>Review: [llength $new] new, [llength $changed] changed, [llength $done] done, [llength $remove] marked REMOVE"
        if {[llength $gone]} {
            append summary ", <span style=\"color:#8b2e2e\">[llength $gone] removed: [almanac::hesc [join $gone {, }]]</span>"
        }
        append summary "</h2><p>Source: [almanac::hesc [file tail $path]] against [almanac::hesc [file tail $base]]. Marked cards below: "
        foreach x {new changed done remove} { append summary "<span style=\"color:[dict get $color $x]\">■ $x</span> " }
        append summary ". Done cards show when the done filter is on; REMOVE cards are hidden until the remove filter is turned on.</p><table>$rows</table></section>"
    } else {
        set summary "<section class=\"twk-review\"><h2>Preview: [almanac::hesc [file tail $path]]</h2><p>No base given, so nothing is marked. REMOVE cards are hidden until the remove filter is turned on.</p></section>"
    }

    # Assemble the page
    set css [almanac::inline_fonts [almanac::read_text [file join $skin artifacts.css]] $skin]
    append css "\n" [almanac::read_text [file join $skin board.css]]
    set js [almanac::read_text [file join $skin board.js]]
    set page [almanac::read_text [file join $skin sight-index.html]]
    set page [string map [list { data-sight-locked="1"} {} {<title>sight</title>} {<title>sight preview</title>} \
        {class="board-page sight-locked"} {class="board-page"} \
        {sight · gated plane ·} {sight preview · unencrypted · not live ·}] $page]
    regsub -all {<link rel="stylesheet" href="assets/[^"]+">[ \t\r\n]*} $page {} page
    set a [string first "<style>" $page]
    set b [string first "</style>" $page $a]
    if {$a < 0 || $b < 0} { almanac::die "preview: skin template changed; no <style> block" }
    set page "[string range $page 0 [expr {$a - 1}]]<style>\n[string map [list </style <\\/style] $css]\n$review_css\n$hl\n</style>[string range $page [expr {$b + 8}] end]"
    set a [string first {<div id="sight-gate"} $page]
    if {$a >= 0} {
        set p [string first {<p id="sight-gate-status"} $page $a]
        set q [string first "</p>" $page $p]
        if {$p < 0 || $q < 0 || ![regexp -indices -start $q {\A</p>\s*</div>\s*</div>} $page m]} {
            almanac::die "preview: skin template changed; could not remove the password gate"
        }
        set page "[string range $page 0 [expr {$a - 1}]][string range $page [expr {[lindex $m 1] + 1}] end]"
    }
    set shell {<div class="board-shell" aria-hidden="true">}
    set a [string first $shell $page]
    if {$a < 0} { almanac::die "preview: skin template changed; board-shell not found" }
    set page "[string range $page 0 [expr {$a - 1}]]$summary\n<div class=\"board-shell\">[string range $page [expr {$a + [string length $shell]}] end]"

    # Plane data (JSON)
    set nj {}
    dict for {k v} $notes { lappend nj "[almanac::jstr $k]: [almanac::jstr $v]" }
    set iso [clock format [clock seconds] -format %Y-%m-%dT%H:%M:%S%z -timezone $TZ]
    set iso "[string range $iso 0 end-2]:[string range $iso end-1 end]"
    set data "{\"schema\": \"labor-os.sight-plane/v1\", \"generated\": [almanac::jstr $iso], \"board_model\": [almanac::jstr $model], \"notes\": \{[join $nj {, }]\}, \"field\": \"\", \"tts\": \{\}}"
    set data [string map [list </ <\\/] $data]
    if {![regexp -indices {<script src="unlock.js"></script>[ \t\r\n]*<script src="assets/board.js" defer></script>} $page m]} {
        almanac::die "preview: skin template changed; could not inline board.js"
    }
    set scripts "<script>window.__SIGHT_PLANE__ = $data;</script>\n<script>\n[string map [list </script <\\/script] $js]\n</script>"
    set page "[string range $page 0 [expr {[lindex $m 0] - 1}]]$scripts[string range $page [expr {[lindex $m 1] + 1}] end]"

    set dir [file dirname $outfile]
    if {$dir ne "" && $dir ne "." && ![file isdirectory $dir]} { file mkdir $dir }
    almanac::atomic_write $outfile $page
    puts "preview: wrote $outfile ([string length [encoding convertto utf-8 $page]] bytes; $ncards cards; new [llength $new], changed [llength $changed], done [llength $done], remove [llength $remove], removed [llength $gone])"
}

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
        {--base      option base}
        {--out       option out}
        {--skin      option skin}
        {--force     flag force}
        {--take-patch flag take}
        {--line-diff flag linediff}
    }
    set parsed [cli::parse $argv $spec -defaults [dict create help 0 file $DEFAULT_FILE toml 0 \
        base {} out {} skin {} force 0 take 0 linediff 0]]
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
        apply {
            if {[llength $rest] != 1} { almanac::die "apply: need exactly one patch file" }
            almanac::cmd_apply $path [lindex $rest 0] [dict create \
                base [dict get $flags base] out [dict get $flags out] force [dict get $flags force] \
                take [dict get $flags take] linediff [dict get $flags linediff]]
        }
        preview {
            if {[llength $rest] > 1} { almanac::die "preview: at most one output file" }
            almanac::cmd_preview $path [expr {[llength $rest] ? [lindex $rest 0] : "preview.html"}] \
                [dict get $flags base] [dict get $flags skin]
        }
        change {
            if {[llength $rest] < 2} { almanac::die "change: need id and a note" }
            almanac::cmd_change $path [lindex $rest 0] {*}[lrange $rest 1 end]
        }
        show {
            if {[llength $rest] != 1} { almanac::die "show: need exactly one id" }
            almanac::cmd_show $path [lindex $rest 0]
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
