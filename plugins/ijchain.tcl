### ijchains Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   ijchains is a bot bridging a jabber chat to the #tcl channel on
#   freenode.net.  This plugin makes messages sent through the bot
#   appear as if they are occurring in the IRC channel.

hook handlePRIVMSG ijchain 30 {serverid msg} {
    if {[dict get $msg src] eq "ijchain"} {
        if {[regexp -- {^<([^>]+)> (.*)} [dict get $msg trailing] _ nick text]} {
            return [list $serverid [dict replace $msg src *$nick trailing $text]]
        }
    }
    return -code continue
}
