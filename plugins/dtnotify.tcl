### dtnotify Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   Displays desktop notification when nick is mentioned on a channel
#   or privmsg is received.
#

set ::dtnotifysend "/usr/bin/notify-send"
set ::dtnotifyignore {}
set ::dtnotifyservers {}
set ::dtnotifyconfpath "~/.config/irken/dtnotify.conf"

proc dtnotifyignore {args} {
    set targets {}
    foreach nick $args {
        if {[lsearch -exact $::dtnotifyignore $nick] == -1} {
            lappend targets $nick
            lappend dtnotifyignore $nick
        }
    }
    return $targets
}

proc updatedtnotifyconf {} {
    if {![catch {open $::dtnotifyconfpath w} fp]} {
        puts $fp "dtnotifyignore $::dtnotifyignore\n"
        close $fp
    } else {
        addchantext $::active "Warning: unable to write to $::dtnotifyconfpath\n" -tags {fg_red italic}
    }
}

proc execescape {str} {
    return [regsub -all {[|<>&]} $str {\\&}]
}

hook disconnection dtnotify 50 {serverid} {
    # remove from set of dtnotify-ready servers
    set ::dtnotifyservers [lsearch -all -not -exact $::dtnotifyservers $serverid]
}

hook handle001 dtnotify 10 {serverid msg} {
    if {[file exists $::dtnotifyconfpath]} {
        source $::dtnotifyconfpath
    }
    lappend ::dtnotifyservers $serverid
}

hook handlePRIVMSG dtnotify 90 {serverid msg} {
    if {[focus] ne ""} {
        # Don't send messages if irken window has focus
        return
    }
    if {[lsearch -exact $::dtnotifyservers $serverid] == -1} {
        # Don't send messages until we are logged into server
        return
    }
    if {[lsearch -exact $::dtnotifyignore [dict get $msg src]] != -1} {
        # Don't send messages from dtnotify-ignored nicks
        return
    }
    if {[isself $serverid [lindex [dict get $msg args] 0]]} {
        # Dtnotify on private message
        exec -- $::dtnotifysend -c im.received "'Message from [dict get $msg src]'" "'[execescape [dict get $msg trailing]]'"
        return
    }
    if {[string first [dict get $::serverinfo $serverid nick] [dict get $msg trailing]] != -1} {
        # Dtnotify on channel mention
        exec -- $::dtnotifysend -c im.received "'Mention on [lindex [dict get $msg args] 0]'" "'\\<[dict get $msg src]\\> [execescape [dict get $msg trailing]]'"
        return
    }
}

hook cmdDTNOTIFY dtnotify 50 {serverid arg} {
    set args [lassign [split $arg " "] cmd]
    switch -exact -nocase -- $cmd {
        "ignore" {
            if {$args eq ""} {
                if {$::dtnotifyignore eq ""} {
                    addchantext $::active "Desktop notification ignore list is empty\n"
                } else {
                    addchantext $::active "Desktop notification ignore list: $::dtnotifyignore\n"
                }
                return
            }
            lappend ::dtnotifyignore {*}$args
            updatedtnotifyconf
            addchantext $::active "Ignoring $args for desktop notifications\n"
        }
        "unignore" {
            foreach nick $args {
                set ::dtnotifyignore [lsearch -all -not -exact $::dtnotifyignore $nick]
            }
            updatedtnotifyconf
            addchantext $::active "Unignoring $args for desktop notifications\n"
        }
        default {
            addchantext $::active "Usage /dtnotify (ignore|unignore) <nicks>\n"
        }
    }
}
