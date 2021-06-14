### friend Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   Adds friending to IRC.  Friended nicks occupy the highest spot on
#   channel userlists.  They have a message channel open by default,
#   which also acts as an online/offline indicator.  Their messages
#   are highlighted within a channel.
#
# Adds commands:
#   /FRIEND <nick> ... - Add nick as friend.
#   /UNFRIEND <nick> ... - Removes nick from friend list.

namespace eval ::irken::friend {
    namespace import ::irc::* ::irken::*
    # Friends are stored as dicts<server id, list<nicks>>
    variable friends [dict create]
    variable confpath "~/.config/irken/friend.conf"
    variable icon {iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAv0lEQVQ4y2NgGNQgcvLX/5FTvv7Hp4YFn+TLT/8JWsKES6Jj048WbGx0wIhLwqn1C4r1+6p5GHEakDL72/97r/6RFD5KYkwMc1K5GOGmkmIITDNKGMxJ5WJ002VpJaTZTZelFaYZaxjUrPr+9tjtv0LYNFupMr9rCeMUxhsLPByM03HZjk0Ow4A7L/9V4zLg7itMOQwDYAHJzQ6Jun3VPIzc7FADXv4jLiFZqTK/21yCiPfNJTyMVqrM7wZnhgMAIDJBRO161I8AAAAASUVORK5CYII=}

    proc friendnicks {serverid args} {
        variable friends
        set friendlist [dict get? {} friends $serverid]
        set targets {}

        foreach nick $args {
            if {$nick ni $friendlist} {
                lappend targets $nick
                dict lappend friends $serverid $nick
            }
        }
        return $targets
    }

    proc updatefriendconf {} {
        variable confpath
        variable friends
        if {![catch {open $confpath w} fp]} {
            dict for {serverid nicklist} $friends {
                if {$nicklist ne ""} {
                    puts $fp "friendnicks $serverid [join $nicklist " "]"
                }
            }
            close $fp
        } else {
            addchantext $::active "Warning: unable to write to $confpath" -tags {fg_red italic}
        }
    }

    hook setupui friend 50 {} {
        variable confpath
        variable icon
        
        catch {source $confpath}
        .nav tag config friend -foreground blue
        .t tag config friend -foreground blue
        .users tag config f -foreground blue -image [image create photo -format png -data $icon]
    }

    hook handle001 friend 50 {serverid msg} {
        variable friends
        foreach nick [dict get? {} $friends $serverid] {
            ensurechan [chanid $serverid $nick] $nick {}
        }
    }

    # ISUPPORT handler
    hook handle005 friend 60 {serverid msg} {
        # we check to see if PREFIX is set, and modify the allowable
        # prefixes after the fact.  Friends get the special ^ prefix
        # (hopefully unused by any server), which acts as a channel mode
        # and orders them at the top of the userlist.
        foreach param [dict get $msg args] {
            lassign [split $param "="] key val
            if {$key eq "PREFIX"} {
                set newprefix [dict create {*}[linsert [dict get $::serverinfo $serverid prefix] 0 "$" "f"]]
                dict set ::serverinfo $serverid prefix $newprefix
                return
            }
        }
    }

    # RPL_NAMES
    hook handle353 friend 75 {serverid msg} {
        variable friends
        set chanid [chanid $serverid [lindex [dict get $msg args] 1]]
        foreach user [split [dict get $msg trailing] " "] {
            if {[lsearch -exact [dict get? {} $friends $serverid] $user] != -1} {
                updateusermodes $chanid $user f {}
            }
        }
    }
    hook handleJOIN friend 60 {serverid msg} {
        variable friends
        dict lappend msg tag friend
        set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
        if {[lsearch -exact [dict get? {} $friends $serverid] [dict get $msg src]] != -1} {
            updateusermodes $chanid [dict get $msg src] f {}
        }
    }
    hook handlePRIVMSG friend 35 {serverid msg} {
        variable friends
        if {[lsearch -exact [dict get? {} $friends $serverid] [dict get $msg src]] != -1} {
            dict lappend msg tag friend
            return -code continue [list $serverid $msg]
        }
    }

    hook handleNOTICE friend 40 {serverid msg} {
        variable friends
        if {[lsearch -exact [dict get? {} $friends $serverid] [dict get $msg src]] != -1} {
            dict lappend msg tag friend
            return -code continue [list $serverid $msg]
        }
    }

    hook handlePART friend 60 {serverid msg} {
        variable friends
        if {[lsearch -exact [dict get? {} $friends $serverid] [dict get $msg src]] != -1} {
            dict lappend msg tag friend
            return -code continue [list $serverid $msg]
        }
    }

    hook handleQUIT friend 60 {serverid msg} {
        variable friends
        if {[lsearch -exact [dict get? {} $friends $serverid] [dict get $msg src]] != -1} {
            dict lappend msg tag friend
            return -code continue [list $serverid $msg]
        }
    }

    hook cmdFRIEND friend 50 {serverid arg} {
        variable friends
        set friendlist [dict get? {} $friends $serverid]
        if {$arg eq ""} {
            if {[llength $friendlist] == 0} {
                addchantext $::active "You are not friends with anyone on $serverid." -tags italic
            } else {
                addchantext $::active "Friends on $serverid: $friendlist" -tags italic
            }
            return
        }
        set targets [friendnicks $serverid {*}[split $arg " "]]
        if {$targets eq ""} {
            addchantext $::active "No nicks added to friend list on $serverid." -tags italic
            return
        }
        addchantext $::active "Added to friend list on $serverid: $targets" -tags italic
        updatefriendconf
        foreach target $targets {
            ensurechan [chanid $serverid $target] $target {}
        }
        dict for {chanid info} $::channelinfo {
            if {[irken::serverpart $chanid] eq $serverid} {
                foreach target $targets {
                    if {[lsearch -nocase -exact -index 0 [dict get $info users] $target] != -1} {
                        updateusermodes $chanid $target f {}
                    }
                }
            }
        }
    }

    hook cmdUNFRIEND friend 50 {serverid arg} {
        variable friends
        set friendlist [dict get? {} $friends $serverid]
        if {$arg eq ""} {
            if {[llength $friendlist] == 0} {
                addchantext $::active "You are not friends with anyone." -tags italic
            } else {
                addchantext $::active "Friends: $friendlist" -tags italic
            }
            return
        }
        set targets {}
        foreach nick [split $arg " "] {
            if {[lsearch -nocase -exact $friendlist $nick] != -1} {
                lappend targets $nick
                set friendlist [lsearch -all -not -exact $friendlist $nick]
            }
        }
        dict set friends $serverid $friendlist
        if {$targets eq ""} {
            addchantext $::active "No nicks removed from friend list." -tags italic
        } else {
            addchantext $::active "Removed from friend list: $targets" -tags italic
            updatefriendconf
            dict for {chanid info} $::channelinfo {
                if {[irken::serverpart $chanid] eq $serverid} {
                    foreach target $targets {
                        if {[lsearch -nocase -exact -index 0 [dict get $info users] $target] != -1} {
                            updateusermodes $chanid $target {} f
                        }
                    }
                }
            }
        }
    }
}
