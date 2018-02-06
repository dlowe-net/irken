### ignore Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   Filters out messages from a given nick.  Adds two commands:
#     /IGNORE - View ignore list
#     /IGNORE <nick> - Add nick to ignore list
#     /UNIGNORE <nick> Remove nick from ignore list
#

namespace eval ignore {
    variable ignorelist {}
    variable confpath "~/.config/irken/ignore.conf"

    proc ignorenicks {args} {
        variable ignorelist
        set targets {}
        foreach nick $args {
            if {[lsearch -exact $ignorelist $nick] == -1} {
                lappend targets $nick
                lappend ignorelist $nick
            }
        }
        return $targets
    }

    proc updateignoreconf {} {
        variable confpath
        variable ignorelist
        if {![catch {open $confpath w} fp]} {
            puts $fp "ignorenicks $ignorelist"
            close $fp
        } else {
            addchantext $::active "Warning: unable to write to $confpath\n" -tags {fg_red italic}
        }
    }

    hook handle001 ignore 10 {serverid msg} {
        variable confpath
        if {[file exists $confpath]} {
            source $confpath
        }
    }

    hook handlePRIVMSG ignore 40 {serverid msg} {
        variable ignorelist
        if {[lsearch -exact $ignorelist [dict get $msg src]] != -1} {
            return -code break
        }
    }

    hook handleNOTICE ignore 40 {serverid msg} {
        variable ignorelist
        if {[lsearch -exact $ignorelist [dict get $msg src]] != -1} {
            return -code break
        }
    }

    hook handleJOIN ignore 60 {serverid msg} {
        variable ignorelist
        if {[lsearch -exact $ignorelist [dict get $msg src]] != -1} {
            return -code break
        }
    }

    hook handlePART ignore 60 {serverid msg} {
        variable ignorelist
        if {[lsearch -exact $ignorelist [dict get $msg src]] != -1} {
            return -code break
        }
    }

    hook handleQUIT ignore 60 {serverid msg} {
        variable ignorelist
        if {[lsearch -exact $ignorelist [dict get $msg src]] != -1} {
            return -code break
        }
    }

    hook cmdIGNORE ignore 50 {serverid arg} {
        variable ignorelist
        if {$arg eq ""} {
            if {[llength $ignorelist] == 0} {
                addchantext $::active "You are not ignoring anyone.\n" -tags italic
            } else {
                addchantext $::active "Ignoring: $ignorelist\n" -tags italic
            }
            return
        }
        set targets [ignorenicks [split $arg " "]]
        if {$targets eq ""} {
            addchantext $::active "No nicks added to ignore list.\n" -tags italic
        } else {
            addchantext $::active "Added to ignore list: $targets\n" -tags italic
            updateignoreconf
        }
    }

    hook cmdUNIGNORE ignore 50 {serverid arg} {
        variable ignorelist
        if {$arg eq ""} {
            if {[llength $ignorelist] == 0} {
                addchantext $::active "You are not ignoring anyone.\n" -tags italic
            } else {
                addchantext $::active "Ignoring: $ignorelist\n" -tags italic
            }
            return
        }
        set targets {}
        foreach nick [split $arg " "] {
            if {[lsearch -exact $ignorelist $nick] != -1} {
                lappend targets $nick
                set ignorelist [lsearch -all -not -exact $ignorelist $nick]
            }
        }
        if {$targets eq ""} {
            addchantext $::active "No nicks removed from ignore list.\n" -tags italic
        } else {
            addchantext $::active "Removed from ignore list: $targets\n" -tags italic
            updateignoreconf
        }
    }
}
