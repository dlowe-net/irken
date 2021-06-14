### popupmenus Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   Adds popup menus for operations on servers, channels, and users.
#

namespace eval ::irken::popupmenus {
    namespace import ::irken::*

    variable target {}

    hook setupui popupmenus 50 {} {
        menu .nav.servermenu -tearoff 0
        .nav.servermenu add command -label "Server name" -state disabled
        .nav.servermenu add separator
        .nav.servermenu add command -label "Connect" -command [namespace code {serverconnect}]
        .nav.servermenu add command -label "Disconnect" -command [namespace code {serverdisconnect}]
        .nav tag bind server <ButtonRelease-3> [namespace code {serverpopup %x %y %X %Y}]
        menu .nav.channelmenu -tearoff 0
        .nav.channelmenu add command -label "Channel name" -state disabled
        .nav.channelmenu add separator
        .nav.channelmenu add command -label "Join" -command [namespace code {channeljoin}]
        .nav.channelmenu add command -label "Part" -command [namespace code {channelpart}]
        .nav.channelmenu add separator
        .nav.channelmenu add command -label "Close" -command [namespace code {channelclose}]
        .nav tag bind channel <ButtonRelease-3> [namespace code {channelpopup %x %y %X %Y}]
        menu .nav.directmenu -tearoff 0
        .nav.directmenu add command -label "Nick" -state disabled
        .nav.directmenu add separator
        .nav.directmenu add command -label "Whois" -command [namespace code {directwhois}]
        .nav.directmenu add separator
        .nav.directmenu add command -label "Close" -command [namespace code {directclose}]
        .nav tag bind direct <ButtonRelease-3> [namespace code {directpopup %x %y %X %Y}]
        menu .users.usermenu -tearoff 0
        .users.usermenu add command -label "Nick" -state disabled
        .users.usermenu add separator
        .users.usermenu add command -label "Whois" -command [namespace code {directwhois}]
        .users.usermenu add command -label "Query" -command [namespace code {userquery}]
        .users.usermenu add separator
        .users.usermenu add command -label "Close"
        bind .users <ButtonRelease-3> [namespace code {userpopup %x %y %X %Y}]
    }

    proc serverpopup {x y rootx rooty} {
        variable target
        set target [.nav identify item $x $y]
        .nav.servermenu entryconfigure 0 -label $target
        if {[.nav tag has disabled $target]} {
            .nav.servermenu entryconfigure 2 -state normal
            .nav.servermenu entryconfigure 3 -state disabled
        } else {
            .nav.servermenu entryconfigure 2 -state disabled
            .nav.servermenu entryconfigure 3 -state normal
        }
        tk_popup .nav.servermenu $rootx $rooty
    }

    proc serverdisconnect {} {
        variable target
        irken::disconnected [dict get $::serverinfo $target chan]
    }

    proc serverconnect {} {
        variable target
        irken::connect $target
    }

    proc channelpopup {x y rootx rooty} {
        variable target
        set target [.nav identify item $x $y]
        .nav.channelmenu entryconfigure 0 -label $target
        if {[.nav tag has disabled $target]} {
            .nav.channelmenu entryconfigure 2 -state normal
            .nav.channelmenu entryconfigure 3 -state disabled
            .nav.channelmenu entryconfigure 5 -state disabled
        } else {
            .nav.channelmenu entryconfigure 2 -state disabled
            .nav.channelmenu entryconfigure 3 -state normal
            .nav.channelmenu entryconfigure 5 -state normal
        }
        tk_popup .nav.channelmenu $rootx $rooty
    }

    proc channeljoin {} {
        variable target
        set serverid [irken::serverpart $target]
        set chan [irken::channelpart $target]
        irken::send $serverid "JOIN :$chan"
    }

    proc channelpart {} {
        variable target
        set serverid [irken::serverpart $target]
        set chan [irken::channelpart $target]
        irken::send $serverid "PART :$chan"
        
    }

    proc channelclose {} {
        variable target
        set serverid [irken::serverpart $target]
        set chan [irken::channelpart $target]
        irken::send $serverid "PART :$chan"
        irken::removechan $target
    }

    proc directpopup {x y rootx rooty} {
        variable target
        set target [.nav identify item $x $y]
        .nav.directmenu entryconfigure 0 -label $target
        tk_popup .nav.directmenu $rootx $rooty
    }

    proc userpopup {x y rootx rooty} {
        variable target
        set nick [.users identify item $x $y]
        set serverid [irken::serverpart [.nav selection]]
        set target  [irken::chanid $serverid $nick]
        .users.usermenu entryconfigure 0 -label $target
        tk_popup .users.usermenu $rootx $rooty
    }

    proc directwhois {} {
        variable target
        set serverid [irken::serverpart $target]
        set nick [irken::channelpart $target]
        irken::send $serverid "WHOIS :$nick"
    }

    proc directclose {} {
        variable target
        irken::removechan $target
    }

    proc userquery {} {
        variable target
        irken::ensurechan $target "" {}
        .nav selection set $target
        irken::selectchan
    }
}
