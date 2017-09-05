#!/usr/bin/wish8.6
# Irken - dlowe@dlowe.net
if {[catch {package require tls} cerr]} {
    puts stderr "Could not load TLS library.  Please run: sudo apt install tcl-tls"
    exit 1
}

# Hooks
#   hook <hook> <handle> <priority> <params> <code> - adds hook, sorted by priority
#   hook call <hook> <param>* - calls hook with given parameters
#   hook unset <hook> <handle> - removes hook with handle
#   hook exists <hook> - returns 1 if hook exists, otherwise 0
# Defined hooks can return three ways:
#   return -code continue : continue with normal processing
#   return -code break : stop processing hook
#   return <value> : replace hook parameter list with the given value
if {![info exists ::hooks]} {
    set ::hooks [dict create]
}
proc hook {op name args} {
    switch -- $op {
        "exists" {return [expr {[dict exists $::hooks $name] && [dict get $::hooks $name] ne ""}]}
        "unset" {
            if {[dict exists $::hooks $name]} {
                dict set ::hooks $name [lsearch -all -exact -inline -not -index 0 [dict get $::hooks $name] [lindex $args 0]]
            }
            return ""
        }
        "call" {
            foreach hookproc [dict get $::hooks $name] {
                try {
                    apply [lrange $hookproc 2 3] {*}$args
                } on {ok} {val} {
                    set args $val
                }
            }
        }
        default {
            # remove existing hook, if any
            set hook {}
            if {[dict exists $::hooks $op]} {
                set hook [lsearch -all -exact -inline -not -index 0 [dict get $::hooks $op] $name]
            }
            # add it back and sort by priority
            dict set ::hooks $op [lsort -index 1 -integer [concat $hook [list [concat [list $name] $args]]]]
            return $op
        }
    }
}

# A chanid is $serverid for the server channel, $serverid/$channel for channel display.
proc chanid {serverid chan} { if {$chan eq ""} {return $serverid} {return $serverid/$chan} }
proc serverpart {chanid} {lindex [split $chanid {/}] 0}
proc channelpart {chanid} {lindex [split $chanid {/}] 1}
proc ischannel {chanid} {regexp -- {^[&#+!][^ ,\a]{0,49}$} [channelpart $chanid]}

proc globescape {str} {return [regsub -all {[][\\*?\{\}]} $str {\\&}]}

proc icon {path} { return [image create photo -format png -data [exec -- convert -background none -geometry 16x16 $path "png:-" | base64]] }
proc svg {width height paths} {
    set svg "<svg width=\"$width\" height=\"$height\" xmlns=\"http://www.w3.org/2000/svg\">$paths</svg>"
    return [image create photo -format png -data [exec -- convert -background none "svg:-" "png:-" | base64 <<$svg]]
}
proc circle {color} {return [svg 16 16 "<circle cx=\"6\" cy=\"8\" r=\"5\" stroke=\"black\" fill=\"$color\"/>"]}
proc polygon {color sides} {
    set angle [expr {2 * 3.14159 / $sides}]
    for {set side 0} {$side < $sides} {incr side} {
        lappend points [expr {5 * cos($angle * $side) + 6}],[expr {5 * sin($angle * $side) + 8}]
    }
    return [svg 16 16 "<polygon points=\"$points\" style=\"stroke:black;fill:$color\"/>"]
}
proc irkenicon {} {
    set path {
  <defs>
    <radialGradient id="grad" cx="50%" cy="50%" r="70%" fx="30%" fy="10%">
      <stop offset="0%" style="stop-color:#ffd89b"/>
      <stop offset="100%" style="stop-color:#efaa2f"/>
    </radialGradient>
    <filter id="shadow" x="0" y="0" width="100%" height="100%">
      <feOffset result="offOut" in="SourceAlpha" dx="1" dy="1" />
      <feGaussianBlur result="blurOut" in="offOut" stdDeviation="1" />
      <feBlend in="SourceGraphic" in2="blurOut" mode="normal" />
    </filter>
  </defs>
  <path
      d="M16.104,16.206c-0.11,0-0.22-0.037-0.31-0.11l-5.175-4.208H0.491C0.22,11.888,0,11.666,0,11.395V0.883c0-0.271,0.22-0.491,0.491-0.491h15.613c0.271,0,0.491,0.219,0.491,0.491v10.512c0,0.271-0.22,0.493-0.491,0.493h-1.081l1.515,3.593c0.039,0.069,0.06,0.15,0.06,0.235c0,0.271-0.22,0.49-0.491,0.49C16.107,16.206,16.104,16.206,16.104,16.206z"
      fill="url(#grad)"
      filter="url(#shadow)"/>
    }
    return [svg 20 20 $path]
}
proc blankicon {} {return [svg 16 16 ""]}

set ::nickprefixes "@%+&~"

proc initvars {} {
    # Set up fonts ahead of time so they can be configured
    catch {font create Irken.List {*}[font actual TkDefaultFont] -size 10}
    catch {font create Irken.Fixed {*}[font actual TkFixedFont] -size 10}
    catch {font create Irken.FixedItalic {*}[font actual Irken.Fixed] -slant italic}

    # ::config is a dict keyed on serverid containing config for each server, loaded from a file.
    set ::config {}
    # ::servers is a dict keyed on fd containing the serverid
    set ::servers {}
    # ::fds is a dict keyed on serverid containing the fd and current nick
    set ::serverinfo {}
    # ::channeltext is a dict keyed on chanid containing channel text with tags
    set ::channeltext {}
    # ::channelinfo is a dict keyed on chanid containing topic, user list, input history, place in the history index.
    set ::channelinfo {}
    # ::active is the chanid of the shown channel.
    set ::active {}
}

proc server {serverid args} {dict set ::config $serverid $args}

proc loadconfig {} {
    set config {}
    set configdir $::env(HOME)/.config/irken/
    file mkdir $configdir
    if {[catch {glob -directory $configdir "*.tcl"} configpaths]} {
        if {[catch {open "$configdir/50irken.tcl" w} fp]} {
            puts stderr "Couldn't write default config.  Exiting."
            exit 1
        }
        puts $fp {server "Freenode" -host irc.freenode.net -port 6697 -secure true -nick tcl-$::env(USER) -user $::env(USER) -autoconnect True}
        close $fp
        set configpaths [list "$configdir/50irken.tcl"]
    }
    foreach configpath [lsort $configpaths] {
        source $configpath
    }
}

proc initui {} {
    # interface setup
    wm iconphoto . [irkenicon]
    ttk::style configure Treeview -rowheight [expr {8 + [font metrics Irken.List -linespace]}] -font Irken.List -indent 3
    ttk::panedwindow .root -orient horizontal
    .root add [ttk::frame .navframe -width 170] -weight 0
    .root add [ttk::frame .mainframe -width 300 -height 300] -weight 1
    .root add [ttk::frame .userframe -width 140] -weight 0
    ttk::treeview .nav -show tree -selectmode browse
    bind .nav <<TreeviewSelect>> selectchan
    .nav column "#0" -width 150
    .nav tag config server -image [icon "/usr/share/icons/Humanity/apps/22/gnome-network-properties.svg"]
    .nav tag config channel -image [icon "/usr/share/icons/Humanity/apps/22/system-users.svg"]
    .nav tag config direct -image [icon "/usr/share/icons/Humanity/stock/48/stock_person.svg"]
    .nav tag config disabled -foreground gray
    .nav tag config highlight -foreground green
    .nav tag config message -foreground orange
    .nav tag config unseen -foreground blue
    ttk::entry .topic -takefocus 0 -font Irken.Fixed
    text .t -height 30 -wrap word -font Irken.Fixed -state disabled \
        -tabs [list \
                   [expr {25 * [font measure Irken.Fixed 0]}] right \
                   [expr {26 * [font measure Irken.Fixed 0]}] left]
    .t tag config nick -foreground steelblue
    .t tag config italic -font Irken.FixedItalic
    .t tag config self   -foreground gray30
    .t tag config highlight  -foreground green
    .t tag config warning  -foreground red -font Irken.FixedItalic
    .t tag config hlink -foreground blue -underline 1
    .t tag bind hlink <Button-1> {exec -ignorestderr -- xdg-open [.t get {*}[.t tag prevrange hlink @%x,%y]]}
    .t tag bind hlink <Enter> {.t configure -cursor hand2}
    .t tag bind hlink <Leave> {.t configure -cursor xterm}
    ttk::frame .cmdline
    ttk::label .nick -padding 3
    ttk::entry .cmd -validate key -validatecommand {stopimplicitentry} -font Irken.Fixed
    ttk::treeview .users -show tree -selectmode browse
    .users tag config ops -foreground red -image [circle red]
    .users tag config halfops -foreground pink -image [polygon pink 5]
    .users tag config admin -foreground orange -image [polygon orange 3]
    .users tag config voice -foreground blue -image [polygon blue 4]
    .users tag config quiet -foreground gray -image [blankicon]
    .users tag config user -foreground black -image [blankicon]
    .users column "#0" -width 140
    bind .users <Double-Button-1> {userclick}
    ttk::label .chaninfo -relief groove -border 2 -justify center -padding 2 -anchor center
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
    bind . <Prior> [list .t yview scroll -1 page]
    bind . <Next> [list .t yview scroll 1 page]
    bind . <Control-Prior> [list ttk::treeview::Keynav .nav up]
    bind . <Control-Next> [list ttk::treeview::Keynav .nav down]
    bind . <Control-space> {nexttaggedchannel}
    bind .topic <Return> setcurrenttopic
    bind .cmd <Return> returnkey
    bind .cmd <Up> [list history up]
    bind .cmd <Down> [list history down]
    bind .cmd <Tab> tabcomplete

    dict for {serverid serverconf} $::config {
        ensurechan $serverid [list disabled]
    }
    .nav selection set [lindex $::config 0]
    focus .cmd
}

proc initnetwork {} {
    if {$::config eq ""} {
        puts stderr "Fatal error: no server entries were found in configuration.\n"
        exit 1
    }

    tls::init -tls1 true -ssl2 false -ssl3 false

    dict for {serverid serverconf} $::config {
        if {[dict get $serverconf -autoconnect]} {
            connect $serverid
        }
    }
}

proc irctolower {str} {return [string map [list \[ \{ \] \} \\ \| \~ \^] [string tolower $str]]}
proc ircstrcmp {a b} {return [string compare [irctolower $a] [irctolower $b]]}
proc irceq {a b} {return [expr {[ircstrcmp $a $b] == 0}]}
proc rankeduser {entry} {
    if {[set rank [lsearch -exact [list ops halfops admin voice] [lindex $entry 1]]] == -1} {
        set rank 9
    }
    return $rank[lindex $entry 0]
}
proc usercmp {a b} {return [ircstrcmp [rankeduser $a] [rankeduser $b]]}
proc isself {serverid nick} {return [irceq [dict get $::serverinfo $serverid nick] $nick]}

proc sorttreechildren {window root} {
    set items [lsort [$window children $root]]
    $window detach $items
    set count [llength $items]
    for {set i 0} {$i < $count} {incr i} {
        $window move [lindex $items $i] $root $i
    }
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

proc stopimplicitentry {} {
    dict unset ::channelinfo $::active historyidx
    dict unset ::channelinfo $::active tab
    return 1
}

proc history {op} {
    set oldidx {}
    if {[dict exists $::channelinfo $::active historyidx]} {
        set oldidx [dict get $::channelinfo $::active historyidx]
    }
    set idx $oldidx
    set cmdhistory [dict get $::channelinfo $::active cmdhistory]
    switch -- $op {
        "up" {set idx [expr {$idx eq "" ? 0 : $idx == [llength $cmdhistory] - 1 ? $oldidx : $idx + 1}]}
        "down" {set idx [expr {$idx eq "" || $idx == 0 ? "" : $idx - 1}]}
    }
    if {$idx eq $oldidx} {
        return
    }
    dict set ::channelinfo $::active historyidx $idx
    .cmd configure -validate none
    .cmd delete 0 end
    if {$idx ne {}} {
        .cmd insert 0 [lindex $cmdhistory $idx]
    }
    .cmd configure -validate key
}
proc tabcomplete {} {
    if {![ischannel $::active]} {
        return
    }
    set user {}
    set userlist [dict get $::channelinfo $::active users]
    if {[dict exists $::channelinfo $::active tab]} {
        lassign [dict get $::channelinfo $::active tab] tabprefix tablast tabstart tabend
        if {[set pos [lsearch -exact -index 0 $userlist $tablast]] != -1} {
            set user [lsearch -inline -nocase -start [expr {$pos+1}] -index 0 -glob $userlist "[globescape $tabprefix]*"]
        }
    } else {
        set s [.cmd get]
        set pt [.cmd index insert]
        if {[string index $s $pt] eq " "} {
            set pt [expr {$pt - 1}]
            if {[string index $s $pt] eq " "} {
                return -code break
            }
        }
        set tabstart [string wordstart $s $pt]
        set tabend [string wordend $s $pt]
        set tabprefix [string trimright [string range $s $tabstart $tabend]]
    }
    if {$user eq ""} {
        set user [lsearch -inline -nocase -index 0 -glob $userlist "[globescape $tabprefix]*"]
        if {$user eq ""} {
            return -code break
        }
    }
    set str [lindex $user 0]
    if {$tabstart == 0} {
        set str "$str: "
    }
    .cmd configure -validate none
    .cmd delete $tabstart $tabend
    .cmd insert $tabstart $str
    .cmd configure -validate key
    dict set ::channelinfo $::active tab \
        [list $tabprefix [lindex $user 0] $tabstart [expr {$tabstart + [string length $str]}]]
    return -code break
}
proc setchanusers {chanid users} {
    set users [lsort -command usercmp $users]
    dict set ::channelinfo $chanid users $users
    if {$chanid ne $::active} {
        return
    }
    updatechaninfo $chanid
    set items [lmap x $users {lindex $x 0}]
    .users detach $items
    set count [llength $items]
    for {set i 0} {$i < $count} {incr i} {
        .users move [lindex $items $i] {} $i
    }
}

# users should be {nick modes}
proc addchanuser {chanid user modes} {
    set impliedmode [dict get {@ ops % halfops & admin + voice ~ quiet {} {}} \
                     [regexp -inline -- {^[@%&+~]} $user]]
    if {$impliedmode ne {}} {
        set user [string range $user 1 end]
        lappend modes $impliedmode
    }
    set userentry [list $user $modes]
    set users {}
    if {[dict exists $::channelinfo $chanid users]} {
        set users [dict get $::channelinfo $chanid users]
    }
    if {[set pos [lsearch -exact -index 0 $users $user]] != -1} {
        if {$userentry eq [lindex $users $pos]} {
            # exact match - same prefix with user
            return
        }
        # update user prefix
        set users [lreplace $users $pos $pos $userentry]
        if {$chanid eq $::active} {
            .users tag remove [lindex [lindex $users $pos] 1] $user
            foreach mode $modes {
                .users tag add $mode $user
            }
        }
    } else {
        # entirely new user
        lappend users $userentry
        if {$chanid eq $::active} {
            .users insert {} end -id $user -text $user -tag [concat $modes [list "user"]]
        }
    }
    setchanusers $chanid $users
}

proc remchanuser {chanid user} {
    set user [string trimleft $user $::nickprefixes]
    set users [dict get $::channelinfo $chanid users]
    set idx [lsearch -exact -index 0 $users $user]
    if {$idx != -1} {
        set users [lreplace $users $idx $idx]
        dict set ::channelinfo $chanid users $users
        if {$chanid eq $::active} {
            .users delete $user
        }
    }
}

proc userclick {} {
    set chanid [chanid [serverpart $::active] [.users selection]]
    ensurechan $chanid {}
    .nav selection set $chanid
}

proc loopedtreenext {window item} {
    set next [lindex [$window children $item] 0]
    if {$next ne ""} {
        return $next
    }
    set next [$window next $item]
    if {$next ne ""} {
        return $next
    }
    set next [$window next [$window parent $item]]
    if {$next ne ""} {
        return $next
    }
    # loop back to top
    return [lindex [$window children {}] 0]
}

proc nexttaggedchannel {} {
    set curchan [.nav selection]
    set chan [loopedtreenext .nav $curchan]
    while {$chan ne $curchan} {
        if {[.nav tag has message $chan]} {
            break
        }
        set chan [loopedtreenext .nav $chan]
    }
    if {$chan ne $curchan} {
        .nav selection set $chan
    }
}

proc addchantext {chanid nick text args} {
    lappend newtext "\[[clock format [clock seconds] -format %H:%M:%S]\]" {} "\t$nick\t" "nick"
    set textstart 0
    if {[regexp -all -indices {https?://[-a-zA-Z0-9@:%_/\+.~#?&=]+} $text match] != 0} {
        foreach {start end} $match {
            lappend newtext [string range $text $textstart $start-1] $args
            lappend newtext [string range $text $start $end] [concat hlink $args]
            set textstart [expr {$end + 1}]
        }
    }
    lappend newtext "[string range $text $textstart end]" $args
    dict append ::channeltext $chanid " $newtext"
    if {$chanid ne $::active} {
        .nav tag add unseen $chanid
        if {$nick ne "*"} {
            .nav tag add message $chanid
        }
        if {[lsearch -exact $args highlight] != -1} {
            .nav tag add highlight $chanid
        }
        return
    }
    set atbottom [expr {[lindex [.t yview] 1] == 1.0}]
    .t configure -state normal
    .t insert end {*}$newtext
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
    .nav focus $chanid
    .nav tag remove unseen $chanid
    .nav tag remove message $chanid
    .nav tag remove highlight $chanid
    set ::active $chanid
    .t configure -state normal
    .t delete 1.0 end
    if {[dict get $::channeltext $chanid] ne ""} {
        .t insert end {*}[dict get $::channeltext $chanid]
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
                .users insert {} end -id [lindex $user 0] -text [lindex $user 0] -tag [concat [lindex $user 1] "user"]
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
    focus .cmd
}

proc ensurechan {chanid tags} {
    if {![dict exists $::channeltext $chanid]} {
        dict set ::channeltext $chanid {}
    }
    if {![dict exists $::channelinfo $chanid]} {
        dict set ::channelinfo $chanid [dict create cmdhistory {} historyidx {} topic {} users {}]
    }
    if {![.nav exists $chanid]} {
        set serverid [serverpart $chanid]
        set name [channelpart $chanid]
        set tag {direct}
        if {$name eq ""} {
            set tag {server}
        } elseif {[ischannel $chanid]} {
            set tag {channel}
        }
        if {$name eq ""} {
            .nav insert {} end -id $chanid -text $chanid -open True -tag [concat $tag $tags]
        } else {
            .nav insert $serverid end -id $chanid -text $name -tag [concat $tag $tags]
        }
        sorttreechildren .nav $serverid
    }
}

proc removechan {chanid} {
    dict unset ::channeltext $chanid
    dict unset ::channelinfo $chanid
    if {$::active eq $chanid} {
        ttk::treeview::Keynav .nav down
        if {$::active eq $chanid} {
            ttk::treeview::Keynav .nav up
        }
    }
    selectchan
    .nav delete $chanid
}

proc connect {serverid} {
    if {[catch {dict get $::config $serverid -host} host]} {
        addchantext $serverid "*" "Fatal error: $serverid has no -host option $host.\n" italic
        return
    }
    if {![dict exists $::config $serverid -nick]} {
        addchantext $serverid "*" "Fatal error: $serverid has no -nick option.\n" italic
    }
    if {![dict exists $::config $serverid -user]} {
        addchantext $serverid "*" "Fatal error: $serverid has no -user option.\n" italic
    }
    if {[catch {dict get $::config $serverid -secure} secure]} {
        set secure 0
    }
    if {[catch {dict get $::config $serverid -port} port]} {
        set port [if {$secure} {expr 6667} {expr 6697}]
    }
    addchantext $serverid "*" "Connecting to $serverid ($host:$port)...\n" italic
    set fd [if {$secure} {tls::socket $host $port} {socket $host $port}]
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
    addchantext $serverid "*" "Connected.\n" italic
    if {[dict exists $::config $serverid -pass]} {
        send $serverid "PASS [dict get $::config $serverid -pass]"
    }
    send $serverid "NICK [dict get $::config $serverid -nick]"
    send $serverid "USER [dict get $::config $serverid -user] 0 * :Irken user"
}

proc disconnected {fd} {
    set serverid [dict get $::servers $fd]
    fileevent $fd writable {}
    fileevent $fd readable {}

    .nav tag add disabled $serverid
    addchantext $serverid "*" "Disconnected.\n" italic
}

hook handle001 irken 50 {serverid msg} {
    if {![dict exists $::config $serverid -autojoin]} {
        return
    }
    foreach chan [dict get $::config $serverid -autojoin] {
        ensurechan [chanid $serverid $chan] disabled
        send $serverid "JOIN $chan"
    }
    return -code continue
}
hook handle301 irken 50 {serverid msg} {
    lassign [dict get $msg args] nick awaymsg
    addchantext [chanid $serverid $nick] "*" "$nick is away: $awaymsg\n" italic
    return -code continue
}
hook handle305 irken 50 {serverid msg} {
    addchantext $::active "*" "You are no longer marked as being away.\n" italic
    return -code continue
}
hook handle306 irken 50 {serverid msg} {
    addchantext $::active "*" "You have been marked as being away.\n" italic
    return -code continue
}
hook handle331 irken 50 {serverid msg} {
    set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
    setchantopic $chanid ""
    addchantext $chanid "*" "No channel topic set.\n" italic
    return -code continue
}
hook handle332 irken 50 {serverid msg} {
    set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
    set topic [dict get $msg trailing]
    setchantopic $chanid $topic
    if {$topic ne ""} {
        addchantext $chanid "*" "Channel topic: $topic\n" italic
    } else {
        addchantext $chanid "*" "No channel topic set.\n" italic
    }
    return -code continue
}
hook handle333 irken 50 {serverid msg} {
    set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
    set nick [lindex [dict get $msg args] 1]
    set time [lindex [dict get $msg args] 2]
    addchantext $chanid "*" "Topic set by $nick at [clock format $time].\n" italic
    return -code continue
}
hook handle353 irken 50 {serverid msg} {
    set chanid [chanid $serverid [lindex [dict get $msg args] 1]]
    foreach user [dict get $msg trailing] {
        addchanuser $chanid $user {}
    }
    return -code continue
}
hook handle366 irken 50 {serverid msg} {return -code continue}
hook handle372 irken 50 {serverid msg} {
    addchantext $serverid "*" "[dict get $msg trailing]\n" italic
    return -code continue
}
hook handle376 irken 50 {serverid msg} {return -code continue}
hook handleJOIN irken 50 {serverid msg} {
    set chan [lindex [dict get $msg args] 0]
    set chanid [chanid $serverid $chan]
    ensurechan $chanid {}
    addchanuser $chanid [dict get $msg src] {}
    if {[isself $serverid [dict get $msg src]]} {
        .nav tag remove disabled $chanid
    }
    return -code continue
}
hook handleJOIN irken-display 75 {serverid msg} {
    set chan [lindex [dict get $msg args] 0]
    set chanid [chanid $serverid $chan]
    if {![isself $serverid [dict get $msg src]]} {
        addchantext $chanid "*" "[dict get $msg src] has joined $chan\n" italic
    }
    return -code continue
}
hook handleKICK irken 50 {serverid msg} {
    lassign [dict get $msg args] chan target
    set chanid [chanid $serverid $chan]
    remchanuser $chanid $target
    if {[isself $serverid $target]} {
        .nav tag add disabled $chanid
    }
    return -code continue
}
hook handleKICK irken-display 75 {serverid msg} {
    lassign [dict get $msg args] chan target note
    if {$note ne {}} {
        set note " ($note)"
    }
    set chanid [chanid $serverid $chan]
    if {[isself $serverid $target]} {
        addchantext $chanid "*" "[dict get $msg src] kicks you from $chan.$note\n" italic
    } else {
        addchantext $chanid "*" "[dict get $msg src] kicks $target from $chan.$note\n" italic
    }
    return -code continue
}
hook handleMODE irken 50 {serverid msg} {
    lassign [dict get $msg args] target change
    set chanid [chanid $serverid $target]
    set msgdest [expr {[ischannel $chanid] ? $chanid:$serverid}]
    if {[lsearch -exact [dict get $msg src] "!"] == -1} {
        addchantext $msgdest "*" "Mode for $target set to [lrange [dict get $msg args] 1 end]\n" italic
    } else {
        addchantext $msgdest "*" "[dict get $msg src] sets mode for $target to [lrange [dict get $msg args] 1 end]\n" italic
    }
    if {[ischannel $chanid]} {
        switch -- $change {
            "-o" {
                # take ops
                set oper [lindex [dict get $msg args] 2]
                remchanuser [chanid $serverid $target] $oper
                addchanuser [chanid $serverid $target] $oper {}
            }
            "+o" {
                # give ops
                set oper [lindex [dict get $msg args] 2]
                remchanuser [chanid $serverid $target] $oper
                addchanuser [chanid $serverid $target] @$oper {}
            }
            "-v" {
                # take voice
                set oper [lindex [dict get $msg args] 2]
                remchanuser [chanid $serverid $target] $oper
                addchanuser [chanid $serverid $target] $oper {}
            }
            "+v" {
                # give voice
                set oper [lindex [dict get $msg args] 2]
                remchanuser [chanid $serverid $target] oper
                addchanuser [chanid $serverid $target] +$oper {}
            }
        }
    }
    return -code continue
}
hook handleNICK irken 50 {serverid msg} {
    set oldnick [dict get $msg src]
    set newnick [dict get $msg trailing]
    foreach chanid [dict keys $::channelinfo] {
        if {![ischannel $chanid] || [serverpart $chanid] ne $serverid} {
            continue
        }
        set user [lsearch -exact -inline -index 0 [dict get $::channelinfo $chanid users] $oldnick]
        if {$user eq ""} {
            continue
        }
        remchanuser $chanid $oldnick
        addchanuser $chanid $newnick [lindex $user 1]
    }
    set oldchanid [chanid $serverid $oldnick]
    set newchanid [chanid $serverid $newnick]
    if {[dict exists $::channelinfo $oldchanid] && ![dict exists $::channelinfo $newchanid]} {
        dict set ::channelinfo $newchanid [dict get $::channelinfo $oldchanid]
        dict set ::channeltext $newchanid [dict get $::channeltext $oldchanid]
        dict unset ::channeltext $oldchanid
        dict unset ::channelinfo $oldchanid
        .nav insert $serverid [.nav index $oldchanid] -id $newchanid {*}[.nav item $oldchanid] -text $newnick
        .nav delete $oldchanid
        if {$::active eq $oldchanid} {
            .nav selection set $newchanid
        }
    }
    return -code continue
}
hook handleNICK irken-display 75 {serverid msg} {
    set oldnick [dict get $msg src]
    set newnick [dict get $msg trailing]
    foreach chanid [dict keys $::channelinfo] {
        if {![ischannel $chanid] || [serverpart $chanid] ne $serverid} {
            continue
        }
        set user [lsearch -exact -inline -index 0 [dict get $::channelinfo $chanid users] $oldnick]
        if {$user eq ""} {
            continue
        }
        addchantext $chanid "*" "$oldnick is now known as $newnick\n" italic
    }
    set newchanid [chanid $serverid $newnick]
    if {[dict exists $::channelinfo $newchanid]} {
        addchantext $newchanid "*" "$oldnick is now known as $newnick\n" italic
    }
    return -code continue
}
hook handleNOTICE irken 50 {serverid msg} {
    hook call handlePRIVMSG $serverid $msg
    return -code continue
}
hook handlePART irken 50 {serverid msg} {
    set chan [lindex [dict get $msg args] 0]
    set chanid [chanid $serverid $chan]
    remchanuser $chanid [dict get $msg src]
    if {[isself $serverid [dict get $msg src]]} {
        if {[dict exists $::channelinfo $chanid]} {
            .nav tag add disabled $chanid
        }
    }
    return -code continue
}
hook handlePART irken-display 75 {serverid msg} {
    lassign [dict get $msg args] chan note
    if {$note ne {}} {
        set note " ($note)"
    }
    set chanid [chanid $serverid $chan]
    if {[isself $serverid [dict get $msg src]]} {
        if {[dict exists $::channelinfo $chanid]} {
            addchantext $chanid "*" "You have left $chan.$note\n" italic
        }
    } else {
        addchantext $chanid "*" "[dict get $msg src] has left $chan.$note\n" italic
    }
    return -code continue
}
hook handlePING irken 50 {serverid msg} {send $serverid "PONG :[dict get $msg args]"; return -code continue}
hook handlePRIVMSG irken 50 {serverid msg} {
    set chan [string trimleft [lindex [dict get $msg args] 0] $::nickprefixes]
    if {[isself $serverid $chan]} {
        # direct message - so chan is source, not target
        set chan [dict get $msg src]
    }
    set text [dict get $msg trailing]
    set chanid [chanid $serverid $chan]
    ensurechan $chanid {}
    set tag ""
    if {[string first [dict get $::serverinfo $serverid nick] $text] != -1} {set tag highlight}
    if [regexp {^\001ACTION (.+)\001} $text -> text] {
        addchantext $chanid "*" "[dict get $msg src] $text\n" $tag
    } else {
        addchantext $chanid [dict get $msg src] "$text\n" $tag
    }
    return -code continue
}
hook handleQUIT irken 50 {serverid msg} {
    set affectedchans {}
    foreach chanid [lsearch -all -exact -inline -glob [dict keys $::channelinfo] "$serverid/*"] {
        if {[lsearch -exact -index 0 [dict get $::channelinfo $chanid users] [dict get $msg src]] != -1} {
            remchanuser $chanid [dict get $msg src]
            lappend affectedchans $chanid
        }
    }
    # The user isn't going to be in the channels, so a message with
    # annotation for the display hook.
    dict set msg affectedchans $affectedchans
    return [list $serverid $msg]
}
hook handleQUIT irken-display 75 {serverid msg} {
    set note {}
    if {[dict exists $msg trailing]} {
        set note " ([dict get $msg trailing])"
    }
    foreach chanid [dict get $msg affectedchans] {
        addchantext $chanid "*" "[dict get $msg src] has quit$note\n" italic
    }
    return -code continue
}
hook handleTOPIC irken 50 {serverid msg} {
    set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
    set topic [dict get $msg trailing]
    setchantopic $chanid $topic
    addchantext $chanid "*" "[dict get $msg src] sets title to $topic\n" italic
    return -code continue
}
hook handleUnknown irken 50 {serverid msg} {
    addchantext $serverid "*" "[dict get $msg line]\n" italic
    return -code continue
}

proc recv {fd} {
    if [eof $fd] {
        disconnected $fd
        return
    }
    gets $fd line
    set serverid [dict get $::servers $fd]
    set line [string trimright [encoding convertfrom utf-8 $line]]
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
    set msg [dict create src $src user $user host $host cmd $cmd args $args trailing $trailing line $line]
    set hook handle$cmd
    if {[hook exists $hook]} {
        hook call $hook $serverid $msg
    } else {
        hook call handleUnknown $serverid $msg
    }
}

hook cmdCLOSE irken 50 {serverid arg} {
    set chanid [chanid $serverid [lindex $arg 0]]
    if {![dict exists $::channelinfo $chanid]} {
        addchantext $::active "*" "No such channel [lindex $arg 0]\n" italic
        return -code break
    }
    if {[ischannel $chanid] && ![.nav tag has disabled $chanid]} {
        send $serverid "PART [lindex $arg 0] :[lrange $arg 1 end]"
    }
    removechan $chanid
}
hook cmdEVAL irken 50 {serverid arg} {
    addchantext $::active "*" "$arg -> [eval $arg]\n" italic
    return -code continue
}
hook cmdME irken 50 {serverid arg} { sendmsg $serverid [channelpart $::active]  "\001ACTION $arg\001"; return -code continue}
hook cmdJOIN irken 50 {serverid arg} {
    set chanid [chanid $serverid $arg]
    ensurechan $chanid disabled
    .nav selection set $chanid
    send $serverid "JOIN :$arg"
    return -code continue
}
hook cmdMSG irken 50 {serverid arg} {
    set target [lrange $arg 0 0]
    set text [lrange $arg 1 end]
    send $serverid "PRIVMSG $target :$text"

    set chanid [chanid $serverid $target]
    ensurechan $chanid {}
    addchantext $chanid [dict get $::serverinfo $serverid nick] "$text\n" self
    return -code continue
}
hook cmdQUERY irken 50 {serverid arg} {
    if {$arg eq ""} {
        addchantext $::active "*" "Query: missing nick.\n" italic
        return -code break
    }
    if {[ischannel $arg]} {
        addchantext $::active "*" "Can't query a channel.\n" italic
        return -code break
    }
    ensurechan [chanid $serverid $arg] {}
}
hook cmdRELOAD irken 50 {serverid arg} {
    source $::argv0
    addchantext $::active "*" "Irken reloaded.\n" italic
}
hook cmdSERVER irken 50 {serverid arg} {
    if {! [dict exists $::config $arg]} {
        addchantext $::active "*" "$arg is not a server.\n" {} $::config
        return
    }
    connect $arg
    return -code continue
}

proc docmd {serverid chan cmd arg} {
    set hook "cmd[string toupper $cmd]"
    if {[hook exists $hook]} {
        hook call $hook $serverid $arg
    } else {
        send $serverid "$cmd $arg"
        return
    }
}

proc sendmsg {serverid chan text} {
    if {[channelpart $::active] eq ""} {
        addchantext $::active "*" "This isn't a channel.\n"
        return
    }
    foreach line [split $text \n] {send $serverid "PRIVMSG $chan :$line"}
    if [regexp {^\001ACTION (.+)\001} $text -> text] {
        addchantext $::active "*" "[dict get $::serverinfo $serverid nick] $text\n" self
    } else {
        addchantext $::active [dict get $::serverinfo $serverid nick] "$text\n" self
    }
    .t yview end
}

proc returnkey {} {
    if {![dict exists $::serverinfo [serverpart $::active]]} {
        addchantext $::active "*" "Server is disconnected.\n"
        return
    }
    set msg [.cmd get]
    dict set ::channelinfo $::active cmdhistory [concat [list $msg] [dict get $::channelinfo $::active cmdhistory]]
    if [regexp {^/(\S+)\s*(.*)} $msg -> cmd msg] {
        docmd [serverpart $::active] [channelpart $::active] [string toupper $cmd] $msg
    } else {
        sendmsg [serverpart $::active] [channelpart $::active] $msg
    }
    .cmd delete 0 end
}

proc setcurrenttopic {} {
    if {![ischannel $::active]} {
        addchantext $::active "*" "This isn't a channel.\n"
        return
    }
    send [serverpart $::active] "TOPIC [channelpart $::active] :[.topic get]"
    focus .cmd
}

if {[info exists argv0] && [file dirname [file normalize [info script]/...]] eq [file dirname [file normalize $argv0/...]]} {
    initvars
    loadconfig
    initui
    initnetwork
}
