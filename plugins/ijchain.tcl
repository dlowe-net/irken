### ijchain Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   ijchains is a bot bridging a jabber chat to the #tcl channel on
#   freenode.net.  This plugin makes messages sent through the bot
#   appear as if they are occurring in the IRC channel.

set ::botnick ijchain
set ::expectingijchainnames 0

proc decoratenick {nick} {
    return [string cat $nick "@"]
}

hook handleJOIN ijchain 75 {serverid msg} {
    if {![isself $serverid [dict get $msg src]]} {
        return
    }
    if {[lindex [dict get $msg args] 0] ne "#tcl"} {
        return
    }
    set ::expectingijchainnames 1
    after 2000 {set ::expectingijchainnames 0}
    send $serverid "PRIVMSG $::botnick :names"
}

hook ctcpACTION ijchain 30 {serverid msg text} {
    if {[dict get $msg src] ne $::botnick} {
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
    if {[dict get $msg src] ne $::botnick} {
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
    if {$::expectingijchainnames} {
        foreach nick [split [dict get $msg trailing] " "] {
            hook call handleJOIN $serverid \
                [dict create src [decoratenick $nick] args "#tcl"]
        }
        # Don't display this message
        return -code break
    }
}
