### ijchain Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   ijchain and ischain are bots bridging jabber and slack chat to the
#   #tcl channel on freenode.net.  This plugin makes messages sent
#   through the bots appear as if they are occurring in the IRC
#   channel.

namespace eval ::irken::ijchain {
    namespace import ::irc::* ::irken::*
    variable bots {ijchain ischain}

    proc decoratenick {bot nick} {
        if {$bot eq "ijchain"} {
            return [string cat $nick "@"]
        }
        return [string cat $nick "%"]
    }

    proc isbotnick {nick} {
        variable bots
        return [expr {[lsearch -exact $bots $nick] == -1}]
    }

    hook handleJOIN ijchain 75 {chanid msg} {
        variable bots
        if {[lindex [dict get $msg args] 0] ne "#tcl"} {
            return
        }
        if {[isself [irken::serverpart $chanid] [dict get $msg src]]} {
            foreach bot $bots {
                send [irken::serverpart $chanid] "PRIVMSG $bot :names"
            }
            return
        }
        if {[dict get $msg src] in $bots} {
            send [irken::serverpart $chanid] "PRIVMSG [dict get $msg src] :names"
        }
    }

    hook ctcpACTION ijchain 30 {chanid msg text} {
        set bot [dict get $msg src]
        if {[isbotnick $bot]} {
            return
        }
        if {[regexp -- {^(\S+) has become available$} $text -> nick]} {
            hook call handleJOIN [irken::serverpart $chanid] [dict replace $msg src [decoratenick $bot $nick]]
            return -code break
        }
        if {[regexp -- {^(\S+) has left$} $text -> nick]} {
            hook call handlePART [irken::serverpart $chanid] [dict replace $msg src [decoratenick $bot $nick] args [lrange [dict get $msg args] 0 0] trailing {}]
            return -code break
        }
        if {[regexp -- {^(\S+) (.*)} $text  -> nick text]} {
            return -code continue [list $chanid [dict replace $msg src [decoratenick $bot $nick]] $text]
        }
    }

    hook handlePRIVMSG ijchain 15 {serverid msg} {
        set bot [dict get $msg src]
        if {[isbotnick $bot]} {
            return
        }
        if {[ischannel [chanid $serverid [lindex [dict get $msg args] 0]]]} {
            # On channel
            if {[regexp -- {^<([^>]+)> (.*)} [dict get $msg trailing] -> nick text]} {
                return -code continue [list $serverid [dict replace $msg src [decoratenick $bot $nick] trailing $text]]
            } elseif {[regexp -- {^(\w+) (.*)} [dict get $msg trailing] -> nick text]} {
                return -code continue [list $serverid [dict replace $msg src [decoratenick $bot $nick] trailing "\001ACTION $text\001"]]
            }
            return
        }
        # Private message
        if {[regexp -- {^(\S+) whispers (.*)} [dict get $msg trailing] -> nick text]} {
            set nick [decoratenick $nick]
            return -code break [list $serverid [dict replace $msg src $nick args [list $nick $text] trailing $text]]
        }

        # Must be the names of correspondents
        foreach nick [split [dict get $msg trailing] " "] {
            lappend names [decoratenick $bot $nick]
        }
        hook call handle353 $serverid \
            [dict create args [list "ignore" "*" "#tcl"] trailing $names]

        # Don't display this message
        return -code break
    }
}
