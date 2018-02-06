### ijchain Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   ijchains is a bot bridging a jabber chat to the #tcl channel on
#   freenode.net.  This plugin makes messages sent through the bot
#   appear as if they are occurring in the IRC channel.

namespace eval ijchain {
    namespace import ::irc::* ::irken::*
    variable botnick "ijchain"

    proc decoratenick {nick} {
        return [string cat $nick "@"]
    }

    hook handleJOIN ijchain 75 {serverid msg} {
        variable botnick
        if {![isself $serverid [dict get $msg src]]} {
            return
        }
        if {[lindex [dict get $msg args] 0] ne "#tcl"} {
            return
        }
        send $serverid "PRIVMSG $botnick :names"
    }

    hook ctcpACTION ijchain 30 {serverid msg text} {
        variable botnick
        if {[dict get $msg src] ne $botnick} {
            return
        }
        if {[regexp -- {^(\S+) has become available} $text -> nick]} {
            hook call handleJOIN $serverid [dict replace $msg src [decoratenick $nick]]
            return -code break
        }
        if {[regexp -- {^(\S+) has left} $text -> nick]} {
            hook call handlePART $serverid [dict replace $msg src [decoratenick $nick] args [lrange [dict get $msg args] 0 0] trailing {}]
            return -code break
        }
        if {[regexp -- {^(\S+) (.*)} $text  -> nick text]} {
            return -code continue [list $serverid [dict replace $msg src [decoratenick $nick]] $text]
        }
    }

    hook handlePRIVMSG ijchain 15 {serverid msg} {
        variable botnick
        if {[dict get $msg src] ne $botnick} {
            return
        }
        if {[ischannel [chanid $serverid [lindex [dict get $msg args] 0]]]} {
            # On channel
            if {[regexp -- {^<([^>]+)> (.*)} [dict get $msg trailing] -> nick text]} {
                return -code continue [list $serverid [dict replace $msg src [decoratenick $nick] trailing $text]]
            } elseif {[regexp -- {^(\w+) (.*)} [dict get $msg trailing] -> nick text]} {
                return -code continue [list $serverid [dict replace $msg src [decoratenick $nick] trailing "\001ACTION $text\001"]]
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
            lappend names [decoratenick $nick]
        }
        hook call handle353 $serverid \
            [dict create args [list "*" "#tcl"] trailing $names]

        # Don't display this message
        return -code break
    }
}
