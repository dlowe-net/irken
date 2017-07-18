package require Tk
package require tls
# ::config is a dict keyed on serverid containing config for each server
set ::config [dict create "Freenode" {-host chat.freenode.net -port 6697 -ssl true -nick dlowe_ -user dlowe -autojoin {\#tcl}}]
# ::servers is a dict keyed on fd containing the serverid
set ::servers {}
# ::fds is a dict keyed on serverid containing the fd
set ::fds {}
# ::channels is a dict keyed on {serverid channel} containing channel text with tags
set ::channels {}
# ::active is the shown channel.  $serverid for the server channel, # $serverid/$channel for channel display.
set ::active {}

# interface setup
ttk::treeview .nav -show tree -selectmode browse
.nav tag config server -font "Monospace 12"
.nav tag bind server <ButtonRelease> {clickchan %x %y}
.nav tag config dcserver -font "Monospace 12" -foreground gray
.nav tag bind dcserver <ButtonRelease> {clickchan %x %y}
.nav tag config channel -font "Monospace 12"
.nav tag bind channel <ButtonRelease> {clickchan %x %y}
.nav tag config dcchannel -font "Monospace 12" -foreground gray
.nav tag bind dcchannel <ButtonRelease> {clickchan %x %y}
.nav tag config direct -font "Monospace 12"
text .t -height 30 -wrap word -font {Monospace 9}
.t tag config bold   -font [linsert [.t cget -font] end bold]
.t tag config italic -font [linsert [.t cget -font] end italic]
.t tag config blue   -foreground blue
.t tag config green  -foreground green
.t tag config warning  -foreground red -font [linsert [.t cget -font] end italic]
entry .cmd
pack .nav -side left -fill y
pack .cmd -side bottom -fill x
pack .t -fill both -expand 1
bind .cmd <Return> handlereturn

proc texttochan {chan text args} {
    dict lappend ::channels $chan [concat [list $text] $args]
    if {$chan ne $::active} {
        return
    }
    set atbottom 0
    if {[lindex [.t yview] 0] eq 1.0} {
        set atbottom 1
    }
    .t insert end $text $args
    if {$atbottom == 0} {
        .t yview end
    }
}

proc clickchan {x y} {
    set chanid [.nav identify item $x $y]
    if {$chanid eq $::active} {
        return
    }
    set ::active $chanid
    .t delete 1.0 end
    if [dict exists $::channels $chanid] {
        foreach texttag [dict get $::channels $chanid] {
            puts stdout $texttag
            .t insert end [lindex $texttag 0] [lindex $texttag 1]
        }
        .t yview end
    }
}

proc connect {serverid} {
    .nav tag remove dcserver $serverid
    .nav tag add server $serverid
    texttochan $serverid "Connecting to $serverid...\n"
    set host [dict get $::config $serverid -host]
    set port [dict get $::config $serverid -port]
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

proc send {serverid str} {
    set fd [dict get $::fds $serverid]
    puts $fd $str
    flush $fd
}

proc connected {fd} {
    fileevent $fd writable {}
    set serverid [dict get $::servers $fd]
    texttochan $serverid "Connected.\n"
    send $serverid "NICK [dict get $::config $serverid -nick]"
    send $serverid "USER [dict get $::config $serverid -user] 0 * :Irken user"
}

proc recv {fd} {
    if [eof $fd] {exit 0}
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
    # .t insert end "src:$src user:$user host:$host cmd:$cmd args:$args\n"
    if {$cmd eq "PING"} {
        # Handle PING messages from server
        send $serverid "PONG :$args"
        return
    }
    if {$cmd eq "376"} {
        # End of MOTD
        foreach chan [dict get $::config $serverid -autojoin] {
            send $serverid "JOIN $chan"
        }
    }
    if {$cmd eq "JOIN"} {
        set chan $serverid/$trailing
        dict append $::channels $chan {}
        .nav insert $serverid end -id $chan -text $trailing -tag channel
    }
    if {$cmd eq "PRIVMSG"} {
        set target [lindex $args 0]
        set msg [lindex $args 1]
        set tag ""
        # if [regexp $::me $msg] {set tag green}
        if [regexp {^\001ACTION (.+)\001} $msg -> msg] {
            texttochan $serverid/$target "$src:$target $msg\n" italic
        } else {
            texttochan $serverid/$target <$src:$target>\t bold
            texttochan $serverid/$target $msg\n $tag
        }
    } else {
        texttochan $serverid $line\n italic
    }
}
proc in {list element} {expr {[lsearch -exact $list $element]>=0}}
proc serverpart {channel} {
    lindex [split $channel {/}] 0
}
proc channelpart {channel} {
    lindex [split $channel {/}] 1
}
proc performcmd {cmd arg} {
    if {$cmd eq "server"} {
        if {! [dict exists $::config $arg]} {
            texttochan $::active "$arg is not a server.\n" {} $::config
            return
        }
        connect $arg
        return
    }
    
    if {! [dict exists $::fds [serverpart $::active]]} {
        texttochan $::active "Server is disconnected.\n"
        return
    }
    if {$cmd eq "me"}  {
        performsend "\001ACTION $arg\001"
    } elseif {$cmd eq "join"} {
        set ::chan $arg
        send $serverid "$arg"
        return
    } else {
        send $serverid "$cmd $arg"
        return
    }
}

proc performsend {msg} {
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
    foreach line [split $msg \n] {send $serverid "PRIVMSG $chan :$line"}
    set tag ""
    
    if [regexp {\001ACTION(.+)\001} $msg -> msg] {set tag italic}
    texttochan $::active <me:$chan>\t {bold blue}
    texttochan $::active $msg\n [list blue $tag]
    .t yview end
}

proc handlereturn {} {
    set msg [.cmd get]
    if [regexp {^/(\S+)\s*(\S*)} $msg -> cmd msg] {
        performcmd $cmd $msg
    } else {
        performsend $msg
    }
    .cmd delete 0 end
}

# initialize
dict for {serverid serverconf} $::config {
    .nav insert {} end -id $serverid -text $serverid -open true -tag dcserver
    .nav selection set $serverid
    set ::active $serverid
}
bind . <Escape> {exec wish $argv0 &; exit}
connect "Freenode"
