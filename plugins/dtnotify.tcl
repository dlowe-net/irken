### dtnotify Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   Displays desktop notification when nick is mentioned on a channel
#   or privmsg is received.
#

namespace eval dtnotify {
    namespace import ::irken::*
    variable sendcmd "/usr/bin/notify-send"
    variable ignore {}
    variable servers {}
    variable confpath "~/.config/irken/dtnotify.conf"

    proc dtnotifyignore {args} {
        variable ignore
        set targets {}
        foreach nick $args {
            if {[lsearch -exact $ignore $nick] == -1} {
                lappend targets $nick
                lappend ignore $nick
            }
        }
        return $targets
    }

    proc updatedtnotifyconf {} {
        variable confpath
        variable ignore
        if {![catch {open $confpath w} fp]} {
            puts $fp "dtnotifyignore $ignore\n"
            close $fp
        } else {
            addchantext $::active "Warning: unable to write to $confpath\n" -tags {fg_red italic}
        }
    }

    proc execescape {str} {
        return [regsub -all {[|<>&]} $str {\\&}]
    }

    hook disconnection dtnotify 50 {serverid} {
        # remove from set of dtnotify-ready servers
        variable servers
        set servers [lsearch -all -not -exact $servers $serverid]
    }

    hook handle001 dtnotify 10 {serverid msg} {
        variable confpath
        variable servers
        if {[file exists $confpath]} {
            source $confpath
        }
        lappend servers $serverid
    }

    hook handlePRIVMSG dtnotify 90 {serverid msg} {
        variable ignore
        variable sendcmd
        variable servers
        if {[focus] ne ""} {
            # Don't send messages if irken window has focus
            return
        }
        if {[lsearch -exact $servers $serverid] == -1} {
            # Don't send messages until we are logged into server
            return
        }
        if {[lsearch -exact $ignore [dict get $msg src]] != -1} {
            # Don't send messages from dtnotify-ignored nicks
            return
        }
        if {[isself $serverid [lindex [dict get $msg args] 0]]} {
            # Dtnotify on private message
            exec -- $sendcmd -c im.received "'Message from [dict get $msg src]'" "'[execescape [dict get $msg trailing]]'"
            return
        }
        if {[string first [dict get $::serverinfo $serverid nick] [dict get $msg trailing]] != -1} {
            # Dtnotify on channel mention
            exec -- $sendcmd -c im.received "'Mention on [lindex [dict get $msg args] 0]'" "'\\<[dict get $msg src]\\> [execescape [dict get $msg trailing]]'"
            return
        }
    }

    hook cmdDTNOTIFY dtnotify 50 {serverid arg} {
        variable ignore
        set args [lassign [split $arg " "] cmd]
        switch -exact -nocase -- $cmd {
            "ignore" {
                if {$args eq ""} {
                    if {$ignore eq ""} {
                        addchantext $::active "Desktop notification ignore list is empty\n"
                    } else {
                        addchantext $::active "Desktop notification ignore list: $ignore\n"
                    }
                    return
                }
                lappend ignore {*}$args
                updatedtnotifyconf
                addchantext $::active "Ignoring $args for desktop notifications\n"
            }
            "unignore" {
                foreach nick $args {
                    set ignore [lsearch -all -not -exact $ignore $nick]
                }
                updatedtnotifyconf
                addchantext $::active "Unignoring $args for desktop notifications\n"
            }
            default {
                addchantext $::active "Usage /dtnotify (ignore|unignore) <nicks>\n"
            }
        }
    }
}
