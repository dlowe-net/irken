#!/usr/bin/wish8.6
# Irken - dlowe@dlowe.net
if {[catch {package require Tk} cerr]} {
    puts "Could not load Tk.  Please run: sudo apt install tcl-tk tcl-tls"
    exit 1
}
if {[catch {package require tls} cerr]} {
    puts "Could not load TLS library.  Please run: sudo apt install tcl-tls"
    exit 1
}

# A chanid is $serverid for the server channel, $serverid/$channel for channel display.
proc chanid {serverid chan} { if {$chan eq ""} {return $serverid} {return $serverid/$chan} }
proc serverpart {chanid} {lindex [split $chanid {/}] 0}
proc channelpart {chanid} {lindex [split $chanid {/}] 1}
proc ischannel {chanid} {
    set chan [channelpart $chanid]
    if {$chan eq {}} {
        return False
    }
    if {[lsearch -exact "# & +" [string range $chan 0 0]] == -1} {
        return False
    }
    return True
}

# ::config is a dict keyed on serverid containing config for each server, loaded from a file.
set ::config {}
set configpath $::env(HOME)/.irken
proc server {serverid args}  {dict set ::config $serverid $args}
if {! [file exists $configpath]} {
    if {[catch {open $configpath w} fp]} {
        puts "Couldn't write default config.  Exiting."
        exit 1
    }
    puts $fp {server "Freenode" -host chat.freenode.net -port 6667 -ssl false -nick tcl-$::env(USER) -user $::env(USER) -autoconnect True -autojoin {\#tcl}}
    close $fp
}
source $configpath

# ::servers is a dict keyed on fd containing the serverid
set ::servers {}
# ::fds is a dict keyed on serverid containing the fd and current nick
set ::serverinfo {}
# ::channeltext is a dict keyed on chanid containing channel text with tags
set ::channeltext {}
# ::channelinfo is a dict keyed on chanid containing topic and user list.
set ::channelinfo {}
# ::active is the chanid of the shown channel.
set ::active {}

# interface setup
proc icon {path} { return [image create photo -format png -data [exec -- convert -geometry 16x16 $path "png:-" | base64]] }
set font "Monospace 10"
ttk::panedwindow .root -orient horizontal
.root add [ttk::frame .navframe -width 200]
.root add [ttk::frame .mainframe -width 300 -height 300]
.root add [ttk::frame .userframe -width 100]
ttk::treeview .nav -show tree -selectmode browse
bind .nav <<TreeviewSelect>> selectchan
.nav tag config server -font $font -image [icon "/usr/share/evolution/3.10/icons/hicolor/48x48/categories/preferences-system-network-proxy.png"]
.nav tag config channel -font $font -image [icon "/usr/share/evolution/3.10/icons/hicolor/48x48/actions/stock_people.png"]
.nav tag config direct -font $font -image [icon "/usr/share/seahorse/icons/hicolor/48x48/apps/seahorse-person.png"]
.nav tag config disabled -foreground gray
.nav tag config unread -foreground orange
ttk::entry .topic -takefocus 0
text .t -height 30 -wrap word -font $font -state disabled -tabs "[expr {12 * [font measure $font 0]}] right [expr {14 * [font measure $font 0]}] left"
.t tag config bold   -font "$font bold"
.t tag config italic -font "$font italic"
.t tag config blue   -foreground blue
.t tag config green  -foreground green
.t tag config warning  -foreground red -font "$font italic"
ttk::frame .cmdline
ttk::label .nick -padding 3
ttk::entry .cmd
ttk::treeview .users -show tree -selectmode browse
.users tag config ops -font $font -foreground red
.users tag config voice -font $font -foreground blue
.users tag config user -font $font
.users column "#0" -width 100
ttk::label .chaninfo -relief groove -border 2 -justify center -padding 2 -anchor center
bind .cmd <Return> returnkey
bind .topic <Return> setcurrenttopic
pack .nav -in .navframe -fill both -expand 1
pack .topic -in .mainframe -side top -fill x
pack .nick -in .cmdline -side left
pack .cmd -in .cmdline -side right -fill x -expand 1
pack .cmdline -in .mainframe -side bottom -fill x -pady 5
pack .t -in .mainframe -fill both -expand 1
pack .chaninfo -in .userframe -side top -fill x -padx 10 -pady 5
pack .users -in .userframe -fill both -expand 1 -padx 1 -pady 5
pack .root -fill both -expand 1
bind . <Escape> {exec wish $argv0 &; exit}

proc sorttreechildren {window root} {
    set items [lsort [$window children $root]]
    $window detach $items
    set count [llength $items]
    for {set i 0} {$i < $count} {incr i} {
        $window move [lindex $items $i] $root $i
    }
}

proc addchantext {chanid text args} {
    dict lappend ::channeltext $chanid [concat [list $text] $args]
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

proc setchantopic {chanid text} {
    dict set ::channelinfo $chanid topic $text
    if {$chanid eq $::active} {
        .topic delete 0 end
        .topic insert 0 $text
    }
}

proc updatechaninfo {chanid} {
    if {[ischannel $chanid]} {
        set users {}
        catch {dict get $::channelinfo $chanid users} users
        .chaninfo configure -text "[llength $users] users"
    } else {
        .chaninfo configure -text {}
    }
}

proc usertags {user} {
    switch -- [string range $user 0 0] {
        "@" {return ops}
        "+" {return voice}
        default {return user}
    }
}

proc addchanuser {chanid user} {
    set users {}
    if {[dict exists $::channelinfo $chanid users]} {
        set users [dict get $::channelinfo $chanid users]
    }
    if {[lsearch -exact $users $user] != -1} {
        return
    }
    lappend users $user
    dict set ::channelinfo $chanid users [lsort $users]
    if {$chanid ne $::active} {
        return
    }
    updatechaninfo $chanid
    .users insert {} end -id $user -text $user -tag [usertags $user]
    sorttreechildren .users {}
}

proc remchanuser {chanid user} {
    set users [dict get $::channelinfo $chanid users]
    set idx [lsearch $users $user]
    set users [lreplace $users $idx $idx]
    dict set ::channelinfo $chanid users $users
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
    if [dict exists $::channeltext $chanid] {
        foreach texttag [dict get $::channeltext $chanid] {
            .t insert end [lindex $texttag 0] [lindex $texttag 1]
        }
        .t yview end
    }
    .t configure -state disabled
    .topic delete 0 end
    if {![catch {dict get $::channelinfo $chanid topic} topic]} {
        .topic insert 0 $topic
    }
    .users delete [.users children {}]
    if {[ischannel $chanid]} {
        if {![catch {dict get $::channelinfo $chanid users} users]} {
            foreach user $users {
                .users insert {} end -id $user -text $user -tag [usertags $user]
            }
        }
    }
    updatechaninfo $chanid
    if {[dict exists $::serverinfo [serverpart $chanid] nick]} {
        .nick configure -text [dict get $::serverinfo [serverpart $chanid] nick]
    } else {
        .nick configure -text [dict get $::config [serverpart $chanid] -nick]
    }

    wm title . "Irken - $::active"
}

proc newchan {chanid tags} {
    set serverid [serverpart $chanid]
    set name [channelpart $chanid]
    set tag {direct}
    if {$name eq ""} {
        set name $serverid
        set tag {server}
    } elseif {[ischannel $chanid]} {
        set tag {channel}
    }
    dict set ::channeltext $chanid {}
    .nav insert $serverid end -id $chanid -text $name -tag [concat $tag $tags]
    sorttreechildren .nav $serverid
}

proc connect {serverid} {
    set host [dict get $::config $serverid -host]
    set port [dict get $::config $serverid -port]
    addchantext $serverid "Connecting to $serverid ($host:$port)...\n" italic
    if [dict get $::config $serverid -ssl] {
        set fd [tls::socket $host $port]
    } else {
        set fd [socket $host $port]
    }
    fileevent $fd writable [list connected $fd]
    fileevent $fd readable [list recv $fd]
    dict set ::servers $fd $serverid
    dict set ::serverinfo $serverid [dict create fd $fd nick [dict get $::config $serverid -nick]]
}

proc send {serverid str} {set fd [dict get $::serverinfo $serverid fd]; puts $fd $str; flush $fd}

proc connected {fd} {
    fileevent $fd writable {}
    set serverid [dict get $::servers $fd]
    .nav tag remove disabled $serverid
    addchantext $serverid "Connected.\n" italic
    send $serverid "NICK [dict get $::config $serverid -nick]"
    send $serverid "USER [dict get $::config $serverid -user] 0 * :Irken user"
}

proc disconnected {fd} {
    set serverid [dict get $::servers $fd]
    fileevent $fd writable {}
    fileevent $fd readable {}

    .nav tag add disabled $serverid
    addchantext $serverid "Disconnected.\n" italic
}

proc handle001 {serverid msg} {
    foreach chan [dict get $::config $serverid -autojoin] {
        newchan [chanid $serverid $chan] disabled
        send $serverid "JOIN $chan"
    }
}
proc handle331 {serverid msg} {
    set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
    setchantopic $chanid ""
    addchantext $chanid "\t*\tNo channel topic set.\n" italic
}
proc handle332 {serverid msg} {
    set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
    set topic [dict get $msg trailing]
    setchantopic $chanid $topic
    if {$topic ne ""} {
        addchantext $chanid "\t*\tChannel topic: $topic\n" italic
    } else {
        addchantext $chanid "\t*\tNo channel topic set.\n" italic
    }
}
proc handle353 {serverid msg} {
    set chanid [chanid $serverid [lindex [dict get $msg args] 1]]
    foreach user [dict get $msg trailing] {
        addchanuser $chanid $user
    }
}
proc handlePING {serverid msg} {send $serverid "PONG :[dict get $msg args]"}
proc handleJOIN {serverid msg} {
    set chan [lindex [dict get $msg args] 0]
    set chanid [chanid $serverid $chan]
    addchanuser $chanid [dict get $msg src]
    if {[dict get $::config $serverid -nick] eq [dict get $msg src]} {
        # I joined
        if [dict exists $::channeltext $chanid] {
            .nav tag remove disabled $chanid
        } else {
            newchan $chanid {}
        }
    } else {
        # Someone else joined
        addchantext $chanid "[dict get $msg src] has joined $chan\n" italic
    }
}
proc handleQUIT {serverid msg} {
    remchanuser $chanid [dict get $msg src]
    addchantext $serverid "[dict get $msg src] has quit.\n" italic
}
proc handlePART {serverid msg} {
    set chan [lindex [dict get $msg args] 0]
    set chanid [chanid $serverid $chan]
    remchanuser $chanid [dict get $msg src]
    if {[dict get $::config $serverid -nick] eq [dict get $msg src]} {
        # I parted
        .nav tag add disabled $chanid
    } else {
        # Someone else parted
        addchantext $chanid "[dict get $msg src] has left $chan\n" italic
    }
}
proc handleTOPIC {serverid msg} {
    set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
    set topic [dict get $msg trailing]
    setchantopic $chanid $topic
    addchantext $chanid "\t*\t[dict get $msg src] sets title to $topic\n" italic
}
proc handlePRIVMSG {serverid msg} {
    set chan [lindex [dict get $msg args] 0]
    if {$chan eq [dict get $::config $serverid -nick]} {
        # direct message - so chan is source, not target
        set chan [dict get $msg src]
    }
    set text [dict get $msg trailing]
    set chanid [chanid $serverid $chan]
    if {! [dict exists $::channeltext $chanid]} {
        newchan $chanid {}
    }
    set tag ""
    if {[string first [dict get $::config $serverid -nick] $text] != -1} {set tag green}
    if [regexp {^\001ACTION (.+)\001} $text -> text] {
        addchantext $chanid "\t*\t[dict get $msg src] " bold $tag
        addchantext $chanid "$text\n" $tag
    } else {
        addchantext $chanid "\t[dict get $msg src]\t" bold $tag
        addchantext $chanid "$text\n" $tag
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
        addchantext $serverid $line\n
    }
}

proc cmdSERVER {serverid arg} {
    if {! [dict exists $::config $arg]} {
        addchantext $::active "$arg is not a server.\n" {} $::config
        return
    }
    connect $arg
}
proc cmdME {serverid arg} { sendmsg "\001ACTION $arg\001" }
proc cmdJOIN {serverid arg} {
    set chanid [chanid $serverid $arg]
    if {! [dict exists $::channeltext $chanid]} {
        newchan $chanid disabled
    }
    .nav selection set $chanid
    selectchan
    send $serverid "JOIN :$arg"
}
proc cmdEVAL {serverid arg} {
    addchantext $::active "$arg -> [eval $arg]\n" italic
}

proc docmd {serverid chan cmd arg} {
    set p [info procs "cmd[string toupper $cmd]"]
    if {$p ne ""} {
        {*}$p $serverid $arg
    } else {
        send $serverid "$cmd $arg"
        return
    }
}

proc sendmsg {serverid chan text} {
    if {![ischannel $::active]} {
        addchantext $::active "This isn't a channel.\n"
        return
    }
    foreach line [split $text \n] {send $serverid "PRIVMSG $chan :$line"}
    set tag {blue}
    if [regexp {^\001ACTION (.+)\001} $text -> text] {
        addchantext $::active "\t*\t[dict get $::config $serverid -nick] " bold $tag
        addchantext $::active "$text\n" $tag
    } else {
        addchantext $::active "\t[dict get $::config $serverid -nick]\t" bold $tag
        addchantext $::active "$text\n" $tag
    }
    .t yview end
}

proc returnkey {} {
    if {![dict exists $::serverinfo [serverpart $::active]]} {
        addchantext $::active "Server is disconnected.\n"
        return
    }
    set msg [.cmd get]
    if [regexp {^/(\S+)\s*(.*)} $msg -> cmd msg] {
        docmd [serverpart $::active] [channelpart $::active] [string toupper $cmd] $msg
    } else {
        sendmsg [serverpart $::active] [channelpart $::active] $msg
    }
    .cmd delete 0 end
}

proc setcurrenttopic {} {
    if {![ischannel $::active]} {
        addchantext $::active "This isn't a channel.\n"
        return
    }
    send [serverpart $::active] "TOPIC [channelpart $::active] :[.topic get]"
    focus .cmd
}

# initialize
dict for {serverid serverconf} $::config {
    .nav insert {} end -id $serverid -text $serverid -open true -tag {server disabled}
}
# select first serverid by default
.nav selection set [lindex $::config 0]
selectchan

# autoconnect to servers
dict for {serverid serverconf} $::config {
    if {[dict get $serverconf -autoconnect]} {
        connect $serverid
    }
}
