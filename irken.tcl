#!/usr/bin/wish8.6
# Irken - dlowe@dlowe.net
#
# Before running, sudo apt install tcl-tls for SSL support.
#
package require Tk
package require tls
# A chanid is $serverid for the server channel, $serverid/$channel for channel display.
proc chanid {serverid chan} { if {$chan eq ""} {return $serverid} {return $serverid/$chan} }
proc serverpart {chanid} {lindex [split $chanid {/}] 0}
proc channelpart {chanid} {lindex [split $chanid {/}] 1}

# ::config is a dict keyed on serverid containing config for each server
set ::config [dict create "Freenode" [list -host chat.freenode.net -port 6697 -ssl true -nick tcl-$::env(USER) -user $::env(USER) -autoconnect True -autojoin {\#tcl}]]
# ::servers is a dict keyed on fd containing the serverid
set ::servers {}
# ::fds is a dict keyed on serverid containing the fd
set ::fds {}
# ::channels is a dict keyed on {chanid channel} containing channel text with tags
set ::channels {}
# ::active is the chanid of the shown channel.
set ::active {}

# interface setup
proc icon {path} { return [image create photo -format png -data [exec -- convert -geometry 16x16 $path "png:-" | base64]] }
set font "Monospace 10"
ttk::treeview .nav -show tree -selectmode browse
bind .nav <<TreeviewSelect>> selectchan
.nav tag config server -font $font -image [icon "/usr/share/evolution/3.10/icons/hicolor/48x48/categories/preferences-system-network-proxy.png"]
.nav tag config channel -font $font -image [icon "/usr/share/evolution/3.10/icons/hicolor/48x48/actions/stock_people.png"]
.nav tag config direct -font $font -image [icon "/usr/share/seahorse/icons/hicolor/48x48/apps/seahorse-person.png"]
.nav tag config disabled -foreground gray
.nav tag config unread -foreground orange
text .t -height 30 -wrap word -font $font -state disabled -tabs "[expr {12 * [font measure $font 0]}] right [expr {14 * [font measure $font 0]}] left"
.t tag config bold   -font "$font bold"
.t tag config italic -font "$font italic"
.t tag config blue   -foreground blue
.t tag config green  -foreground green
.t tag config warning  -foreground red -font "$font italic"
entry .cmd
pack .nav -side left -fill y
pack .cmd -side bottom -fill x
pack .t -fill both -expand 1
bind .cmd <Return> returnkey

proc texttochan {chanid text args} {
    dict lappend ::channels $chanid [concat [list $text] $args]
    if {$chanid ne $::active} {
        .nav tag add unread $chanid
        return
    }
    set atbottom [expr {[lindex [.t yview] 1] == 1.0}]
    .t configure -state normal
    .t insert end $text $args
    if {$atbottom} {
        .t yview end
    }
    .t configure -state disabled
}

proc selectchan {} {
    set chanid [.nav selection]
    if {$chanid eq $::active} {
        return
    }
    .nav tag remove unread $chanid
    set ::active $chanid
    .t configure -state normal
    .t delete 1.0 end
    if [dict exists $::channels $chanid] {
        foreach texttag [dict get $::channels $chanid] {
            .t insert end [lindex $texttag 0] [lindex $texttag 1]
        }
        .t yview end
    }
    .t configure -state disabled
    wm title . "Irken - $::active"
}

proc newchan {chanid tags} {
    set name [channelpart $chanid]
    set tag {channel}
    if {$name eq ""} {
        set name [serverpart $chanid]
        set tag {server}
    } elseif {[string range $name 0 0] ne "#"} {
        set tag {direct}
    }
    dict set ::channels $chanid {}
    .nav insert [serverpart $chanid] end -id $chanid -text $name -tag [concat $tag $tags]
}

proc connect {serverid} {
    set host [dict get $::config $serverid -host]
    set port [dict get $::config $serverid -port]
    texttochan $serverid "Connecting to $serverid ($host:$port)...\n" italic
    if [dict get $::config $serverid -ssl] {
        set fd [tls::socket $host $port]
    } else {
        set fd [socket $host $port]
    }
    fileevent $fd writable [list connected $fd]
    fileevent $fd readable [list recv $fd]
    dict set ::servers $fd $serverid
    dict set ::fds $serverid $fd
    
}

proc send {serverid str} {set fd [dict get $::fds $serverid]; puts $fd $str; flush $fd}

proc connected {fd} {
    fileevent $fd writable {}
    set serverid [dict get $::servers $fd]
    .nav tag remove disabled $serverid
    texttochan $serverid "Connected.\n" italic
    send $serverid "NICK [dict get $::config $serverid -nick]"
    send $serverid "USER [dict get $::config $serverid -user] 0 * :Irken user"
}

proc disconnected {fd} {
    set serverid [dict get $::servers $fd]
    fileevent $fd writable {}
    fileevent $fd readable {}
    
    .nav tag add disabled $serverid
    texttochan $serverid "Disconnected.\n" italic
}

proc handlePING {serverid msg} {send $serverid "PONG :[dict get $msg args]"}
proc handleJOIN {serverid msg} {
    set chan [lindex [dict get $msg args] 0]
    set chanid [chanid $serverid $chan]
    if {[dict get $::config $serverid -nick] eq [dict get $msg src]} {
        # I joined
        if [dict exists $::channels $chanid] {
            .nav tag remove disabled $chanid
        } else {
            newchan $chanid {}
        }
    } else {
        # Someone else joined
        texttochan $chanid "[dict get $msg src] has joined $chan\n" italic
    }
}
proc handlePART {serverid msg} {
    set chan [lindex [dict get $msg args] 0]
    set chanid [chanid $serverid $chan]
    if {[dict get $::config $serverid -nick] eq [dict get $msg src]} {
        # I parted
        .nav tag add disabled $chanid
    } else {
        # Someone else parted
        texttochan $chanid "[dict get $msg src] has left $chan\n" italic
    }
}
proc handle331 {serverid msg} {
    # Channel title
    set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
    texttochan $chanid "\t*\tNo channel topic set.\n" italic
}
proc handle332 {serverid msg} {
    # Channel title
    set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
    texttochan $chanid "\t*\tChannel topic: [dict get $msg trailing]\n" italic
}
proc handle376 {serverid msg} {
    # End of MOTD
    foreach chan [dict get $::config $serverid -autojoin] {
        newchan [chanid $serverid $chan] disabled
        send $serverid "JOIN $chan"
    }
}
proc handleTOPIC {serverid msg} {
    set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
    texttochan $chanid "\t*\t[dict get $msg src] sets title to [dict get $msg trailing]\n" italic
}
proc handlePRIVMSG {serverid msg} {
    set chan [lindex [dict get $msg args] 0]
    if {$chan eq [dict get $::config $serverid -nick]} {
        # direct message - so chan is source, not target
        set chan [dict get $msg src]
    }
    set text [dict get $msg trailing]
    set chanid [chanid $serverid $chan]
    if {! [dict exists $::channels $chanid]} {
        newchan $chanid {}
    }
    set tag ""
    if {[string first [dict get $::config $serverid -nick] $text] != -1} {set tag green}
    if [regexp {^\001ACTION (.+)\001} $text -> text] {
        texttochan $chanid "\t*\t[dict get $msg src] " bold $tag
        texttochan $chanid "$text\n" $tag
    } else {
        texttochan $chanid "\t[dict get $msg src]\t" bold $tag
        texttochan $chanid "$text\n" $tag
    }
}
proc handleNOTICE {serverid msg} {
    handlePRIVMSG $serverid $msg
}

proc recv {fd} {
    if [eof $fd] {
        disconnected $fd
        return
    }
    gets $fd line
    set serverid [dict get $::servers $fd]
    set line [string trimright $line]
    if {! [regexp {^(?::([^ !]*)(?:!([^ @]*)(?:@([^ ]*))?)?\s+)?(\S+)\s*([^:]+)?(?::(.*))?} $line -> src user host cmd args trailing]} {
        .t insert end PARSE_ERROR:$line\n warning
        return
    }
    if {$trailing ne ""} {
        lappend args $trailing
    }
    if {[regexp {^\d+$} $cmd]} {
        # Numeric responses specify a useless target afterwards
        set args [lrange $args 1 end]
    }
    set msg [dict create src $src user $user host $host cmd $cmd args $args trailing $trailing]
    set p [info procs handle$cmd]
    if {$p ne ""} {
        {*}$p $serverid $msg
    } else {
        texttochan $serverid $line\n
    }
}

proc docmd {cmd arg} {
    if {$cmd eq "SERVER"} {
        if {! [dict exists $::config $arg]} {
            texttochan $::active "$arg is not a server.\n" {} $::config
            return
        }
        connect $arg
        return
    }

    set serverid [serverpart $::active]
    if {! [dict exists $::fds $serverid]} {
        texttochan $::active "Server is disconnected.\n"
        return
    }
    if {$cmd eq "ME"}  {
        performsend "\001ACTION $arg\001"
    } elseif {$cmd eq "JOIN"} {
        set chanid [chanid $serverid $arg]
        set ::active $chanid
        if {! [dict exists $::channels $chanid]} {
            newchan $chanid disabled
        }
        .nav selection set $chanid
        selectchan
        send $serverid "JOIN :$arg"
        return
    } else {
        send $serverid "$cmd $arg"
        return
    }
}

proc sendmsg {text} {
    set chan [channelpart $::active]
    if {$chan eq {}} {
        texttochan $::active "No channel joined.  Try /join #channel\n"
        return
    }
    set serverid [serverpart $::active]
    if {! [dict exists $::fds [serverpart $::active]]} {
        texttochan $::active "Server is disconnected.\n"
        return
    }
    foreach line [split $text \n] {send $serverid "PRIVMSG $chan :$line"}
    set tag {blue}
    if [regexp {^\001ACTION (.+)\001} $text -> text] {
        texttochan $::active "\t*\t[dict get $::config $serverid -nick] " bold $tag
        texttochan $::active "$text\n" $tag
    } else {
        texttochan $::active "\t[dict get $::config $serverid -nick]\t" bold $tag
        texttochan $::active "$text\n" $tag
    }
    .t yview end
}

proc returnkey {} {
    set msg [.cmd get]
    if [regexp {^/(\S+)\s*(.*)} $msg -> cmd msg] {
        docmd [string toupper $cmd] $msg
    } else {
        sendmsg $msg
    }
    .cmd delete 0 end
}

# initialize
dict for {serverid serverconf} $::config {
    .nav insert {} end -id $serverid -text $serverid -open true -tag {server disabled}
}
# select first serverid by default
.nav selection set [lindex $::config 0]
selectchan

# quick restart
bind . <Escape> {exec wish $argv0 &; exit}

# autoconnect to servers
dict for {serverid serverconf} $::config {
    if {[dict get $serverconf -autoconnect]} {
        connect $serverid
    }
}
