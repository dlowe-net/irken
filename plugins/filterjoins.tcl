### filterjoins Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   Intelligently filters out joins, parts, and quit messages from
#   your channel display.  These messages will only be shown for nicks
#   that have spoken in the recent past.
#
# Set filterjoinslimit to specify the number of minutes that qualifies
# as recent
set ::recentlimit 30

set ::lastspoke {}
hook handlePRIVMSG filterjoins 70 {serverid msg} {
    # mark when someone speaks in a channel
    dict set ::lastspoke $serverid [dict get $msg src] [clock seconds]
    continue
}
proc worthy {serverid nick} {
    if {![dict exists $::lastspoke $serverid $nick]} {
        return 0
    }
    if {[dict get $::lastspoke $serverid $nick] < [clock seconds] - 60 * $::recentlimit} {
        dict unset ::lastspoke $serverid $nick
        return 0
    }
    return 1
}

# Irken display priorities are set to 75, so breaking here will
# prevent the messages from being displayed.
hook handleJOIN filterjoins 70 {serverid msg} {
    if {[worthy $serverid [dict get $msg src]]} {
        continue
    }
    break
}
hook handlePART filterjoins 70 {serverid msg} {
    if {[worthy $serverid [dict get $msg src]]} {
        continue
    }
    break
}
hook handleQUIT filterjoins 70 {serverid msg} {
    if {[worthy $serverid [dict get $msg src]]} {
        continue
    }
    break
}
