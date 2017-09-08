### ignore Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   Filters out messages from a given nick.  Adds two commands:
#     /IGNORE - View ignore list
#     /IGNORE <nick> - Add nick to ignore list
#     /UNIGNORE <nick> Remove nick from ignore list
#

set ::ignorelist {}
set ::ignoreconfpath "~/.config/irken/ignore.conf"

proc ignorenicks {nicks} {
    set targets {}
    foreach nick $nicks {
        if {[lsearch -exact $::ignorelist $nick] == -1} {
            lappend targets $nick
            lappend ::ignorelist $nick
        }
    }
    return $targets
}

proc updateignoreconf {} {
    if {![catch {open $::ignoreconfpath w} fp]} {
        puts $fp "ignorenicks $::ignorelist"
        close $fp
    } else {
        addchantext $::active "*" "Warning: unable to write to $::ignoreconfpath\n" fg_red italic
    }
}

hook handle001 ignore 10 {serverid msg} {
    if {[file exists $::ignoreconfpath]} {
        source $::ignoreconfpath
    }
    return -code continue
}

hook handlePRIVMSG ignore 40 {serverid msg} {
    if {[lsearch -exact $::ignorelist [dict get $msg src]] != -1} {
        return -code break
    }
    return -code continue
}

hook handleNOTICE ignore 40 {serverid msg} {
    if {[lsearch -exact $::ignorelist [dict get $msg src]] != -1} {
        return -code break
    }
    return -code continue
}

hook handleJOIN ignore 60 {serverid msg} {
    if {[lsearch -exact $::ignorelist [dict get $msg src]] != -1} {
        return -code break
    }
    return -code continue
}

hook handlePART ignore 60 {serverid msg} {
    if {[lsearch -exact $::ignorelist [dict get $msg src]] != -1} {
        return -code break
    }
    return -code continue
}

hook handleQUIT ignore 60 {serverid msg} {
    if {[lsearch -exact $::ignorelist [dict get $msg src]] != -1} {
        return -code break
    }
    return -code continue
}

hook cmdIGNORE ignore 50 {serverid arg} {
    if {$arg eq ""} {
        if {[llength $::ignorelist] == 0} {
            addchantext $::active "*" "You are not ignoring anyone.\n" italic
        } else {
            addchantext $::active "*" "Ignoring: $::ignorelist\n" italic
        }
        return -code continue
    }
    set targets [ignorenicks [split $arg " "]]
    if {$targets eq ""} {
        addchantext $::active "*" "No nicks added to ignore list.\n" italic
    } else {
        addchantext $::active "*" "Added to ignore list: $targets\n" italic
        updateignoreconf
    }
    return -code continue
}

hook cmdUNIGNORE ignore 50 {serverid arg} {
    if {$arg eq ""} {
        if {[llength $::ignorelist] == 0} {
            addchantext $::active "*" "You are not ignoring anyone.\n" italic
        } else {
            addchantext $::active "*" "Ignoring: $::ignorelist\n" italic
        }
        return -code continue
    }
    set targets {}
    foreach nick [split $arg " "] {
        if {[lsearch -exact $::ignorelist $nick] != -1} {
            lappend targets $nick
            set ::ignorelist [lsearch -all -not -exact $::ignorelist $nick]
        }
    }
    if {$targets eq ""} {
        addchantext $::active "*" "No nicks removed from ignore list.\n" italic
    } else {
        addchantext $::active "*" "Removed from ignore list: $targets\n" italic
        updateignoreconf
    }
    return -code continue
}
