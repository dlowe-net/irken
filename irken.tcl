#!/usr/bin/wish8.6
# Irken - dlowe@dlowe.net
package require tls
package require BWidget

proc ::tcl::dict::get? {default args} {expr {[catch {dict get {*}$args} val] ? $default:$val}}
namespace ensemble configure dict -map [dict merge [namespace ensemble configure dict -map] {get? ::tcl::dict::get?}]

# Hooks
#   hook <hook> <handle> <priority> <params> <code> - adds hook, sorted by priority
#   hook call <hook> <param>* - calls hook with given parameters
#   hook unset <hook> <handle> - removes hook with handle
#   hook exists <hook> - returns 1 if hook exists, otherwise 0
# Defined hooks can return three ways:
#   return -code continue : replace hook parameter list with the return value
#   return -code break : stop processing hook
#   normal return : continue processing to next hook
if {![info exists ::hooks]} {
    set ::hooks [dict create]
}
proc hook {op name args} {
    switch -- $op {
        "exists" {return [expr {[dict get? "" $::hooks $name] ne ""}]}
        "unset" {
            dict set ::hooks $name [lsearch -all -exact -inline -not -index 0 [dict get? {} $::hooks $name] [lindex $args 0]]
            return ""
        }
        "call" {
            foreach hookproc [dict get? {} $::hooks $name] {
                try {
                    apply [lrange $hookproc 2 3] {*}$args
                } on continue {val} {
                    set args $val
                }
            }
            return $args
        }
        default {
            set hook [lsearch -all -exact -inline -not -index 0 [dict get? {} $::hooks $op] $name]
            dict set ::hooks $op [lsort -index 1 -integer [concat $hook [list [concat [list $name] $args]]]]
            return $op
        }
    }
}

# A chanid is $serverid for the server channel, $serverid/$channel for channel display.
proc chanid {serverid chan} { if {$chan eq ""} {return $serverid} {return [string cat $serverid "/" [irctolower [dict get $::serverinfo $serverid casemapping] $chan]]} }
proc serverpart {chanid} {lindex [split $chanid {/}] 0}
proc channelpart {chanid} {lindex [split $chanid {/}] 1}
proc ischannel {chanid} {
    dict with ::serverinfo [serverpart $chanid] {}
    regexp -- "^\[$chantypes\]\[^ ,\\a\]\{0,$channellen\}\$" [channelpart $chanid]
}

proc globescape {str} {return [regsub -all {[][\\*?\{\}]} $str {\\&}]}

set ::codetagcolormap [dict create 0 white 1 black 2 navy 3 green 4 red 5 maroon 6 purple 7 olive 8 yellow 9 lgreen 10 teal 11 cyan 12 blue 13 magenta 14 gray 15 lgray {} {}]
set ::tagcolormap [dict create white white black black navy navy green green red red maroon maroon purple purple olive {dark olive green} yellow gold lgreen {spring green} teal {pale turquoise} cyan deepskyblue blue blue magenta magenta gray gray lgray {light grey} {} {}]

proc initvars {} {
    # Set up fonts ahead of time so they can be configured
    catch {font create Irken.List {*}[font actual TkDefaultFont] -size 10}
    catch {font create Irken.Fixed {*}[font actual TkFixedFont] -size 10}

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

hook openhlink irken 50 {hlink} {exec -ignorestderr -- xdg-open $hlink &}

proc initui {} {
    catch {font create Irken.FixedItalic {*}[font actual Irken.Fixed] -slant italic}
    catch {font create Irken.FixedBold {*}[font actual Irken.Fixed] -weight bold}
    catch {font create Irken.FixedBoldItalic {*}[font actual Irken.Fixed] -weight bold -slant italic}
    wm iconphoto . [image create photo -format png -data $::irkenicon]
    ttk::style configure Treeview -rowheight [expr {8 + [font metrics Irken.List -linespace]}] -font Irken.List -indent 3
    ttk::panedwindow .root -orient horizontal
    .root add [ttk::frame .navframe -width 170] -weight 0
    .root add [ttk::frame .mainframe -width 300 -height 300] -weight 1
    .root add [ttk::frame .userframe -width 140] -weight 0
    ttk::treeview .nav -show tree -selectmode browse
    bind .nav <<TreeviewSelect>> selectchan
    .nav column "#0" -width 150
    .nav tag config server -image [image create photo -format png -data $::servericon]
    .nav tag config channel -image [image create photo -format png -data $::channelicon]
    .nav tag config direct -image [image create photo -format png -data $::usericon]
    .nav tag config disabled -foreground gray
    .nav tag config highlight -foreground green
    .nav tag config message -foreground orange
    .nav tag config unseen -foreground blue
    ttk::entry .topic -takefocus 0 -font Irken.Fixed
    DynamicHelp::add .topic -command {join [regexp -all -inline {\S(?:\S{0,79}|.{0,79}(?=\s+|$))} [.topic get]] "\n"}
    DynamicHelp::configure -font Irken.Fixed
    text .t -height 30 -wrap word -font Irken.Fixed -state disabled \
        -tabs [list \
                   [expr {25 * [font measure Irken.Fixed 0]}] right \
                   [expr {26 * [font measure Irken.Fixed 0]}] left]
    .t tag config line -lmargin2 [expr {26 * [font measure Irken.Fixed 0]}]
    .t tag config nick -foreground steelblue
    .t tag config self   -foreground gray30
    .t tag config highlight  -foreground green
    .t tag config system  -font Irken.FixedItalic
    .t tag config italic -font Irken.FixedItalic
    .t tag config bold -font Irken.FixedBold
    .t tag config bolditalic -font Irken.FixedBoldItalic
    .t tag config underline -underline 1
    dict for {tagcolor color} $::tagcolormap {
        .t tag config fg_$tagcolor -foreground $color
        .t tag config bg_$tagcolor -background $color
    }
    .t tag config hlink -foreground blue -underline 1
    .t tag bind hlink <ButtonRelease-1> {hook call openhlink [.t get {*}[.t tag prevrange hlink @%x,%y]]}
    .t tag bind hlink <Enter> {.t configure -cursor hand2}
    .t tag bind hlink <Leave> {.t configure -cursor xterm}
    ttk::frame .cmdline
    ttk::label .nick -padding 3
    ttk::entry .cmd -validate key -validatecommand {stopimplicitentry} -font Irken.Fixed
    ttk::treeview .users -show tree -selectmode browse
    .users tag config q -foreground gray -image [image create photo -format png -data $::ownericon]
    .users tag config a -foreground orange -image [image create photo -format png -data $::adminicon]
    .users tag config o -foreground red -image [image create photo -format png -data $::opsicon]
    .users tag config h -foreground pink -image [image create photo -format png -data $::halfopsicon]
    .users tag config v -foreground blue -image [image create photo -format png -data $::voiceicon]
    .users tag config user -foreground black -image [image create photo -format png -data $::blankicon]
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
    bind . <Control-c> {if {[set r [.t tag nextrange sel 0.0]] ne ""} {clipboard clear; clipboard append [.t get {*}$r]}}
    bind .topic <Return> setcurrenttopic
    bind .cmd <Return> returnkey
    bind .cmd <Up> [list history up]
    bind .cmd <Down> [list history down]
    bind .cmd <Tab> tabcomplete

    hook call setupui
    dict for {serverid serverconf} $::config {
        ensurechan $serverid "" [list disabled]
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
        if {[dict get? 0 $serverconf -autoconnect]} {
            connect $serverid
        }
    }
}

proc irctolower {casemapping str} {
    lassign [list [dict get {ascii 90 rfc1459 94 strict-rfc1459 93} $casemapping]] upperbound result
    foreach c [lmap c [split $str ""] {scan $c %c}] {
        lappend result [format %c [expr {$c >= 65 && $c <= $upperbound ? $c+32:$c}]]
    }
    return [join $result ""]
}
proc ircstrcmp {casemapping a b} {return [string compare [irctolower $casemapping $a] [irctolower $casemapping $b]]}
proc irceq {casemapping a b} {return [expr {[ircstrcmp $casemapping $a $b] == 0}]}
proc foldl {cmd list} {set r [lindex $list 0];foreach e [lrange $list 1 end] {set r [apply $cmd $r $e]};return $r}
proc min {list} {foldl {{a b} {expr {$a < $b ? $a:$b}}} $list}
proc rankeduser {serverid entry} {
    set modes [dict values [dict get $::serverinfo $serverid prefix]]
    return [min [linsert [lmap m [lindex $entry 1] {lsearch $modes $m}] end [llength $modes]]][lindex $entry 0]
}
proc usercmp {serverid a b} {return [ircstrcmp [dict get $::serverinfo $serverid casemapping] [rankeduser $serverid $a] [rankeduser $serverid $b]]}
proc isself {serverid nick} {return [irceq [dict get $::serverinfo $serverid casemapping] [dict get $::serverinfo $serverid nick] $nick]}

proc setchantopic {chanid text} {
    dict set ::channelinfo $chanid topic $text
    if {$chanid eq $::active} {
        .topic delete 0 end
        .topic insert 0 $text
    }
}

proc updatechaninfo {chanid} {
    .chaninfo configure -text [expr {[ischannel $chanid] ? "[llength [dict get $::channelinfo $chanid users]] users":""}]
}

proc stopimplicitentry {} {
    dict unset ::channelinfo $::active historyidx
    dict unset ::channelinfo $::active tab
    return 1
}

proc history {op} {
    set oldidx [dict get? {} $::channelinfo $::active historyidx]
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
        lassign [list [.cmd get] [.cmd index insert]] s pt
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
    set str [expr {$tabstart == 0 ? "[lindex $user 0]: ":[lindex $user 0]}]
    .cmd configure -validate none
    .cmd delete $tabstart $tabend
    .cmd insert $tabstart $str
    .cmd configure -validate key
    dict set ::channelinfo $::active tab [list $tabprefix [lindex $user 0] $tabstart [expr {$tabstart + [string length $str]}]]
    return -code break
}
proc setchanusers {chanid users} {
    dict set ::channelinfo $chanid users $users
    if {$chanid ne $::active} {
        return
    }
    set users [lsort -command "usercmp [serverpart $chanid]" $users]
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
    set prefixes [dict get $::serverinfo [serverpart $chanid] prefix]
    regexp -- "^(\[[join [dict keys $prefixes] ""]\]*)(.*)" $user -> userprefixes nick
    set usermodes [concat $modes [lmap uprefix [split $userprefixes ""] {dict get $prefixes $uprefix}]]
    set userentry [list $nick $usermodes]
    set users [dict get $::channelinfo $chanid users]
    if {[set pos [lsearch -exact -index 0 $users $nick]] != -1} {
        if {$userentry eq [lindex $users $pos]} {
            # exact match - same prefix with user
            return
        }
        # update user prefix
        if {$chanid eq $::active} {
            foreach oldmode [lindex [lindex $users $pos] 1] {.users tag remove $oldmode $nick}
            foreach newmode $usermodes {.users tag add $newmode $nick}
        }
        setchanusers $chanid [lreplace $users $pos $pos $userentry]
    } else {
        # entirely new user
        if {$chanid eq $::active} {
            .users insert {} end -id $nick -text $nick -tag [concat $modes [list "user"]]
        }
        setchanusers $chanid [concat $users [list $userentry]]
    }
}

proc remchanuser {chanid user} {
    if {[dict exists $::channelinfo $chanid]} {
        set prefixes [dict keys [dict get $::serverinfo [serverpart $chanid] prefix]]
        set nick [string trimleft $user $prefixes]
        set users [dict get $::channelinfo $chanid users]
        if {[set idx [lsearch -exact -index 0 $users $nick]] != -1} {
            dict set ::channelinfo $chanid users [lreplace $users $idx $idx]
            if {$chanid eq $::active} {
                .users delete $nick
            }
        }
    }
}

proc userclick {} {
    ensurechan [chanid [serverpart $::active] [.users selection]] [.users selection] {}
    .nav selection set [chanid [serverpart $::active] [.users selection]]
}

proc loopedtreenext {window item} {
    if {[set next [lindex [$window children $item] 0]] ne ""} {
        return $next
    }
    if {[set next [$window next $item]] ne ""} {
        return $next
    }
    if {[set next [$window next [$window parent $item]]] ne ""} {
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

proc tagcolorchange {pos prefix defaultcol oldcol newcol} {
    set newcol [expr {$newcol eq "" ? $defaultcol:$newcol}]
    if {$oldcol eq $newcol} {
        return [list {} $oldcol]
    }
    set result {}
    if {$oldcol ne $defaultcol} {
        lappend result [list $pos pop [string cat $prefix _ $oldcol]]
    }
    if {$newcol ne $defaultcol} {
        lappend result [list $pos push [string cat $prefix _ $newcol]]
    }
    return [list $result $newcol]
}
proc colorcode {text} {
    lassign {0 "" "" 0 0 black white} pos bold italic underline reverse fg bg result tagranges
    set rest $text
    while {$rest ne ""} {
        switch -- [string index $rest 0] {
            "\x02" {
                if {[string cat $bold $italic] ne ""} {
                    lappend tagranges [list $pos pop "$bold$italic"]
                }
                set bold [expr {$bold == "bold" ? "":"bold"}]
                if {[string cat $bold $italic] ne ""} {
                    lappend tagranges [list $pos push "$bold$italic"]
                }
            }
            "\x1d" {
                if {[string cat $bold $italic] ne ""} {
                    lappend tagranges [list $pos pop "$bold$italic"]
                }
                set italic [expr {$italic == "italic" ? "":"italic"}]
                if {[string cat $bold $italic] ne ""} {
                    lappend tagranges [list $pos push "$bold$italic"]
                }
            }
            "\x1f" {set underline [expr {!$underline}]; lappend tagranges [list $pos [expr {$underline ? "push" : "pop"}] underline]}
            "\x0f" {
                if {[string cat $bold $italic] ne ""} {lappend tagranges [list $pos pop "$bold$italic"]}
                if {$underline} {lappend tagranges [list $pos pop underline]}
                if {$fg ne "black"} {lappend tagranges [list $pos pop fg_$fg]}
                if {$bg ne "white"} {lappend tagranges [list $pos pop bg_$bg]}
                lassign {"" "" 0 0 black white} bold italic underline reverse fg bg
            }
            "\x03" {
                set rest [string range $rest 1 end]
                if {[regexp -- {^0*(\d*)(,0*(\d*))?} $rest match fgnum _ bgnum]} {
                    set rest [string range $rest [string length $match] end]
                    if {$reverse} {
                        lassign [list $bgnum $fgnum] fgnum bgnum
                    }
                    lassign [tagcolorchange $pos "fg" "black" $fg [dict get? "black" $::codetagcolormap $fgnum]] newtags fg
                    lappend tagranges {*}$newtags
                    lassign [tagcolorchange $pos "bg" "white" $bg [dict get? "white" $::codetagcolormap $bgnum]] newtags bg
                    lappend tagranges {*}$newtags
                }
                continue
            }
            "\x16" {
                lassign [list [expr {!$reverse}] $fg $bg] reverse newbg newfg
                lassign [tagcolorchange $pos "fg" "black" $fg $newfg] newtags fg
                lappend tagranges {*}$newtags
                lassign [tagcolorchange $pos "bg" "white" $fg $newbg] newtags bg
                lappend tagranges {*}$newtags
            }
            default {
                append result [string index $rest 0]
                incr pos
            }
        }
        set rest [string range $rest 1 end]
    }
    return [list $result $tagranges]
}

proc regexranges {text regex tag} {
    set ranges {}
    for {set start 0} {[regexp -indices -start $start -- $regex $text match]} {set start [expr {[lindex $match 1] + 1}]} {
        lappend ranges [list [lindex $match 0] push $tag] [list [expr {[lindex $match 1] + 1}] pop $tag]
    }
    return $ranges
}

# returns text into window with tags determined by potentially
# overlapping styles. The "delete" tag is handled specially and
# removes the text.  Example:
#   combinestyles "text" {0 push red} {2 pop red}
proc combinestyles {text ranges} {
    lassign {{} {} 0} result activetags textstart
    foreach {rangetag} [lsort -index 0 -integer $ranges] {
        lassign $rangetag pos op tag
        if {$textstart < $pos} {
            lappend result [string range $text $textstart $pos-1] $activetags
        }
        set textstart $pos
        if {$op eq "push"} {
            lappend activetags $tag
        } elseif {[set pos [lsearch -exact $activetags $tag]] != -1} {
            set activetags [lreplace $activetags $pos $pos]
        }
    }
    return [concat $result [list [string range $text $textstart end] $activetags]]
}

hook tagchantext irken-color 50 {text ranges} {
    lassign [colorcode $text] text newranges
    return -code continue [list $text [concat $ranges $newranges]]
}
hook tagchantext irken-http 60 {text ranges} {
    return -code continue [list $text [concat $ranges [regexranges $text {https?://[-a-zA-Z0-9@:%_/\+.~#?&=,:()]+} hlink]]]
}

# addchantext inserts text at the end of a channel's buffer, updating
# the UI as necessary.  If adding text to the active channel, it
# inserts the text at the end of the widget.  Otherwise, it sets the
# highlighting for the channel in the nav widget.  It calls the
# tagchantext hook to split the text into {text taglist} chunks.
#
# Usage:
#   addchantext <chanid> <nick> <text> [<options>]
#   Options may be:
#     -time Sets the time of the message.  Defaults to the current time.
#     -nick Sets the nick of the message  Defaults to "*"
#     -tags Sets tags applied to the whole message.
proc addchantext {chanid text args} {
    set textranges [combinestyles {*}[hook call tagchantext $text [lmap linetag "[dict get? {} $args -tags] line" {list 0 push $linetag}]]]
    # Using conditional expr instead of dict get? to avoid getting clock multiple times per message.
    set timestamp [expr {[dict exists $args -time] ? [dict get $args -time]:[clock seconds]}]
    lappend newtext "\[[clock format $timestamp -format %H:%M:%S]\]" {} "\t[dict get? * $args -nick]\t" "nick" {*}$textranges
    dict append ::channeltext $chanid " $newtext"
    if {$chanid ne $::active} {
        .nav tag add unseen $chanid
        if {[lsearch -exact $args system] == -1} {
            .nav tag add message $chanid
        }
        if {[lsearch -exact $args highlight] != -1} {
            .nav tag add highlight $chanid
        }
        hook call textinserted $chanid $newtext
        return
    }
    set atbottom [expr {[lindex [.t yview] 1] == 1.0}]
    .t configure -state normal
    .t insert end {*}$newtext
    if {$atbottom} {
        .t yview end
    }
    .t configure -state disabled
    hook call textinserted $chanid $newtext
}

proc selectchan {} {
    if {[set chanid [.nav selection]] eq $::active} {
        return
    }
    .nav focus $chanid
    foreach tag {unseen message highlight} {.nav tag remove $tag $chanid}
    set ::active $chanid
    .t configure -state normal
    .t delete 1.0 end
    if {[dict get $::channeltext $chanid] ne ""} {
        .t insert end {*}[dict get $::channeltext $chanid]
        .t yview end
    }
    .t configure -state disabled
    .topic delete 0 end
    .topic insert 0 [dict get? "" $::channelinfo $chanid topic]
    .users delete [.users children {}]
    if {[ischannel $chanid]} {
        foreach user [lsort -command "usercmp [serverpart $chanid]" [dict get? {} $::channelinfo $chanid users]] {
            .users insert {} end -id [lindex $user 0] -text [lindex $user 0] -tag [concat [lindex $user 1] "user"]
        }
    }
    updatechaninfo $chanid
    if {[dict exists $::serverinfo [serverpart $chanid] nick]} {
        .nick configure -text [dict get $::serverinfo [serverpart $chanid] nick]
    } else {
        .nick configure -text [dict get $::config [serverpart $chanid] -nick]
    }
    wm title . "Irken - [serverpart $::active]/[.nav item $::active -text]"
    focus .cmd
    hook call chanselected $chanid
}

# ensurechan creates the data structures and ui necessary to support a
# new channel for the chanid, if the channel does not already exist.
# If the channel does exist, it updates the channel name in the UI if
# name is specified.  The name should only be specified in response to
# server messages, so that it gets the correct capitalization.
proc ensurechan {chanid name tags} {
    if {[.nav exists $chanid]} {
        if {$name ne ""} {
            .nav item $chanid -text $name
        }
        return
    }
    # When no elements are given, lappend has a useful property of
    # leaving the value alone if the key exists, but creating a key
    # with an empty string when it doesn't.
    dict lappend ::channeltext $chanid
    dict set ::channelinfo $chanid [dict create cmdhistory {} historyidx {} topic {} users {}]
    if {[channelpart $chanid] eq ""} {
        .nav insert {} end -id $chanid -text $chanid -open True -tag [concat server $tags]
        return
    }

    set tag [expr {[ischannel $chanid] ? "channel":"direct"}]
    .nav insert [serverpart $chanid] end -id $chanid -text [expr {$name eq "" ? [channelpart $chanid]:$name}] -tag [concat $tag $tags]

    set items [lsort [.nav children [serverpart $chanid]]]
    .nav detach $items
    for {set i 0} {$i < [llength $items]} {incr i} {
        .nav move [lindex $items $i] [serverpart $chanid] $i
    }
}

proc removechan {chanid} {
    dict unset ::channeltext $chanid
    dict unset ::channelinfo $chanid
    if {$::active eq $chanid} {
        ttk::treeview::Keynav .nav down
        selectchan
        if {$::active eq $chanid} {
            ttk::treeview::Keynav .nav up
            selectchan
        }
    }
    .nav delete $chanid
}

set ::ircdefaults [dict create casemapping "rfc1459" chantypes "#&" channellen "200" prefix [dict create @ o + v]]

proc connect {serverid} {
    if {[catch {dict get $::config $serverid -host} host]} {
        addchantext $serverid "Fatal error: $serverid has no -host option $host.\n" -tags system
        return
    }
    if {![dict exists $::config $serverid -nick]} {
        addchantext $serverid "Fatal error: $serverid has no -nick option.\n" -tags system
        return
    }
    if {![dict exists $::config $serverid -user]} {
        addchantext $serverid "Fatal error: $serverid has no -user option.\n" -tags system
        return
    }
    set insecure [dict get? 0 $::config $serverid -insecure]
    set port [dict get? [expr {$insecure ? 6667:6697}] $::config $serverid -port]

    addchantext $serverid "Connecting to $serverid ($host:$port)...\n" -tags system
    set fd [if {$insecure} {socket -async $host $port} {tls::socket -async $host $port}]
    fconfigure $fd -blocking 0
    fileevent $fd writable [list connected $fd]
    fileevent $fd readable [list recv $fd]
    dict set ::servers $fd $serverid
    dict set ::serverinfo $serverid [dict merge [dict create fd $fd nick [dict get $::config $serverid -nick]] $::ircdefaults]
}

proc send {serverid str} {puts [dict get $::serverinfo $serverid fd] $str}

proc connected {fd} {
    fileevent $fd writable {}
    set serverid [dict get $::servers $fd]
    .nav tag remove disabled $serverid
    addchantext $serverid "Connected.\n" -tags system
    send $serverid "CAP REQ :multi-prefix\nCAP REQ :znc.in/server-time-iso\nCAP REQ :server-time"
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
    addchantext $serverid "Disconnected.\n" -tags system
}

hook handle001 irken 50 {serverid msg} {
    foreach chan [dict get? {} $::config $serverid -autojoin] {
        ensurechan [chanid $serverid $chan] "" disabled
        send $serverid "JOIN $chan"
    }
}
hook handle005 irken 50 {serverid msg} {
    foreach param [dict get $msg args] {
        lassign [split $param "="] key val
        if {[lsearch -exact {CASEMAPPING CHANTYPES CHANNELLEN PREFIX} $key] != -1} {
            switch -- $key {
                "PREFIX" {
                    if {[regexp -- "^\\((\[^\)\]*)\\)(.*)" $val -> modes prefixes]} {
                        dict set ::serverinfo $serverid prefix \
                            [dict create {*}[concat {*}[lmap p [split $prefixes ""] m [split $modes ""] {list $p $m}]]]
                    }
                }
                default {dict set ::serverinfo $serverid [string tolower $key] $val}
            }
        }
    }
}
hook handle301 irken 50 {serverid msg} {
    lassign [dict get $msg args] nick awaymsg
    addchantext [chanid $serverid $nick] "$nick is away: $awaymsg\n" -tags system
}
hook handle305 irken 50 {serverid msg} {
    addchantext $::active "You are no longer marked as being away.\n" -tags system
}
hook handle306 irken 50 {serverid msg} {
    addchantext $::active "You have been marked as being away.\n" -tags system
}
hook handle331 irken 50 {serverid msg} {
    set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
    setchantopic $chanid ""
    addchantext $chanid "No channel topic set.\n" -tags system
}
hook handle332 irken 50 {serverid msg} {
    set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
    set topic [dict get $msg trailing]
    setchantopic $chanid $topic
    if {$topic ne ""} {
        addchantext $chanid "Channel topic: $topic\n" -tags system
    } else {
        addchantext $chanid "No channel topic set.\n" -tags system
    }
}
hook handle333 irken 50 {serverid msg} {
    set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
    set nick [lindex [dict get $msg args] 1]
    set time [lindex [dict get $msg args] 2]
    addchantext $chanid "Topic set by $nick at [clock format $time].\n" -tags system
}
hook handle353 irken 50 {serverid msg} {
    set chanid [chanid $serverid [lindex [dict get $msg args] 1]]
    foreach user [split [dict get $msg trailing] " "] {
        addchanuser $chanid $user {}
    }
}
hook handle366 irken 50 {serverid msg} {return}
hook handle372 irken 50 {serverid msg} {
    addchantext $serverid "[dict get $msg trailing]\n" -tags system
}
hook handle376 irken 50 {serverid msg} {return}
hook handleJOIN irken 50 {serverid msg} {
    set chan [lindex [dict get $msg args] 0]
    set chanid [chanid $serverid $chan]
    ensurechan $chanid $chan {}
    addchanuser $chanid [dict get $msg src] {}
    if {[isself $serverid [dict get $msg src]]} {
        .nav tag remove disabled $chanid
    }
}
hook handleJOIN irken-display 75 {serverid msg} {
    set chan [lindex [dict get $msg args] 0]
    set chanid [chanid $serverid $chan]
    if {![isself $serverid [dict get $msg src]]} {
        addchantext $chanid "[dict get $msg src] has joined $chan\n" -tags system
    }
}
hook handleKICK irken 50 {serverid msg} {
    lassign [dict get $msg args] chan target
    set chanid [chanid $serverid $chan]
    remchanuser $chanid $target
    if {[isself $serverid $target]} {
        .nav tag add disabled $chanid
    }
}
hook handleKICK irken-display 75 {serverid msg} {
    lassign [dict get $msg args] chan target note
    if {$note ne {}} {
        set note " ($note)"
    }
    set chanid [chanid $serverid $chan]
    if {[isself $serverid $target]} {
        addchantext $chanid "[dict get $msg src] kicks you from $chan.$note\n" -tags system
    } else {
        addchantext $chanid "[dict get $msg src] kicks $target from $chan.$note\n" -tags system
    }
}
hook handleMODE irken 50 {serverid msg} {
    set args [lassign [dict get $msg args] target]
    set chanid [chanid $serverid $target]
    set msgdest [expr {[ischannel $chanid] ? $chanid:$serverid}]
    if {[lsearch -exact [dict get $msg src] "!"] == -1} {
        addchantext $msgdest "Mode for $target set to [lrange [dict get $msg args] 1 end]\n" -tags system
    } else {
        addchantext $msgdest "[dict get $msg src] sets mode for $target to [lrange [dict get $msg args] 1 end]\n" -tags system
    }
    set modes [dict values [dict get $::serverinfo $serverid prefix]]
    if {[ischannel $chanid]} {
        lassign {} changes params
        foreach arg $args {
            if {[regexp {^([-+])(.*)} $arg -> op terms]} {
                lappend changes {*}[lmap term [split $terms ""] {list $op $term}]
            } else {
                lappend params $arg
            }
        }
        foreach change $changes {
            if {[lsearch $modes [lindex $change 1]] != -1}  {
                set params [lassign $params param]
                set usermodes [lindex [lsearch -inline -index 0 -exact [dict get $::channelinfo $chanid users] $param] 1]
                if {[lindex $change 0] eq "+"} {
                    if {[lsearch $usermodes [lindex $change 1]] == -1} {
                        lappend usermodes [lindex $change 1]
                    }
                } else {
                    set usermodes [lsearch -all -inline -not -exact $usermodes [lindex $change 1]]
                }
                addchanuser $chanid $param $usermodes
            }
        }
    }
}
hook handleNICK irken 50 {serverid msg} {
    set oldnick [dict get $msg src]
    set newnick [dict get $msg trailing]
    foreach chanid [dict keys $::channelinfo] {
        if {![ischannel $chanid] || [serverpart $chanid] ne $serverid} {
            return
        }
        set user [lsearch -exact -inline -index 0 [dict get $::channelinfo $chanid users] $oldnick]
        if {$user eq ""} {
            return
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
}
hook handleNICK irken-display 75 {serverid msg} {
    set oldnick [dict get $msg src]
    set newnick [dict get $msg trailing]
    foreach chanid [dict keys $::channelinfo] {
        if {![ischannel $chanid] || [serverpart $chanid] ne $serverid} {
            return
        }
        set user [lsearch -exact -inline -index 0 [dict get $::channelinfo $chanid users] $oldnick]
        if {$user eq ""} {
            return
        }
        addchantext $chanid "$oldnick is now known as $newnick\n" -tags system
    }
    set newchanid [chanid $serverid $newnick]
    if {[dict exists $::channelinfo $newchanid]} {
        addchantext $newchanid "$oldnick is now known as $newnick\n" -tags system
    }
}
hook handleNOTICE irken 50 {serverid msg} {
    hook call handlePRIVMSG $serverid $msg
}
hook handlePART irken 50 {serverid msg} {
    set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
    remchanuser $chanid [dict get $msg src]
    if {[isself $serverid [dict get $msg src]]} {
        if {[dict exists $::channelinfo $chanid]} {
            .nav tag add disabled $chanid
        }
    }
}
hook handlePART irken-display 75 {serverid msg} {
    lassign [dict get $msg args] chan note
    if {$note ne {}} {
        set note " ($note)"
    }
    set chanid [chanid $serverid $chan]
    if {[isself $serverid [dict get $msg src]]} {
        if {[dict exists $::channelinfo $chanid]} {
            addchantext $chanid "You have left $chan.$note\n" -tags system
        }
    } else {
        addchantext $chanid "[dict get $msg src] has left $chan.$note\n" -tags system
    }
}
hook handlePING irken 50 {serverid msg} {send $serverid "PONG :[dict get $msg args]"}
hook handlePRIVMSG irken-privmsg 20 {serverid msg} {
    # We handle privmsgs specially here, since there's some duplicate
    # work between a CTCP ACTION and a normal PRIVMSG.
    dict set msg chan [string trimleft [lindex [dict get $msg args] 0] [dict keys [dict get $::serverinfo $serverid prefix]]]
    if {[isself $serverid [dict get $msg chan]]} {
        # direct message - so chan is source, not target
        dict set msg chan [dict get $msg src]
    }
    if {[isself $serverid [dict get $msg src]]} {
        dict set msg tag [concat [dict get? {} $msg tag] self]
    }
    if {[string first [dict get $::serverinfo $serverid nick] [dict get $msg trailing]] != -1} {
        dict set msg tag [concat [dict get? {} $msg tag] highlight]
    }
    return -code continue [list $serverid $msg]
}
hook handlePRIVMSG irken 50 {serverid msg} {
    if {[regexp {^\001([A-Za-z0-9]+) ?(.*?)\001?$} [dict get $msg trailing] -> cmd text]} {
        hook call ctcp$cmd $serverid $msg $text
        return -code break
    }
    ensurechan [chanid $serverid [dict get $msg chan]] [dict get $msg chan] {}
    addchantext [chanid $serverid [dict get $msg chan]] "[dict get $msg trailing]\n" -time [dict get $msg time] -nick [dict get $msg src] -tags [dict get? {} $msg tag]
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
    return -code continue [list $serverid $msg]
}
hook handleQUIT irken-display 75 {serverid msg} {
    set note [expr {[dict exists $msg trailing] ? " ([dict get $msg trailing])":""}]
    foreach chanid [dict get $msg affectedchans] {
        addchantext $chanid "[dict get $msg src] has quit$note\n" -tags system
    }
}
hook handleTOPIC irken 50 {serverid msg} {
    set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
    set topic [dict get $msg trailing]
    setchantopic $chanid $topic
    addchantext $chanid "[dict get $msg src] sets title to $topic\n" -tags system
}
hook handleUnknown irken 50 {serverid msg} {
    addchantext $serverid "[dict get $msg line]\n" -tags system
}

hook ctcpACTION irken 50 {serverid msg text} {
    ensurechan [chanid $serverid [dict get $msg chan]] [dict get $msg chan] {}
    addchantext [chanid $serverid [dict get $msg chan]] "[dict get $msg src] $text\n" -time [dict get $msg time] -tags [dict get? {} $msg tag]
}
hook ctcpCLIENTINFO irken 50 {serverid msg text} {
    if {$text eq ""} {
        addchantext $serverid "CTCP CLIENTINFO request from [dict get $msg src]\n" -tags system
        send $serverid "PRIVMSG [dict get $msg src] :\001CLIENTINFO ACTION CLIENTINFO PING TIME VERSION\001"
    } else {
        addchantext $serverid "CTCP CLIENTINFO reply from [dict get $msg src]: $text\n" -tags system
    }
}
hook ctcpPING irken 50 {serverid msg text} {
    addchantext $serverid "CTCP PING request from [dict get $msg src]: $text\n" -tags system
    send $serverid "PRIVMSG [dict get $msg src] :\001PING $text\001"
}
hook ctcpTIME irken 50 {serverid msg text} {
    if {$text eq ""} {
        addchantext $serverid "CTCP TIME request from [dict get $msg src]\n" -tags system
        send $serverid "PRIVMSG [dict get $msg src] :\001TIME [clock format -gmt 1 [clock seconds]]\001"
    } else {
        addchantext $serverid "CTCP TIME reply from [dict get $msg src]: $text\n" -tags system
    }
}
hook ctcpVERSION irken 50 {serverid msg text} {
    if {$text eq ""} {
        addchantext $serverid "CTCP VERSION request from [dict get $msg src]\n" -tags system
        send $serverid "PRIVMSG [dict get $msg src] :\001VERSION Irken 1.0 <https://github.com/dlowe-net/irken>\001"
    } else {
        addchantext $serverid "CTCP VERSION reply from [dict get $msg src]: $text\n" -tags system
    }
}

proc recv {fd} {
    if {[eof $fd]} {
        disconnected $fd
        return
    }
    if {[gets $fd line] == 0} {return}
    set serverid [dict get $::servers $fd]
    set line [string trimright [encoding convertfrom utf-8 $line]]
    if {![regexp {^(?:@(\S*) )?(?::([^ !]*)(?:!([^ @]*)(?:@([^ ]*))?)?\s+)?(\S+)\s*([^:]+)?(?::(.*))?} $line -> tags src user host cmd args trailing]} {
        .t insert end PARSE_ERROR:$line\n warning
        return
    }
    if {$trailing ne ""} {lappend args $trailing}
    # Numeric responses specify a useless target afterwards
    if {[regexp {^\d+$} $cmd]} {set args [lrange $args 1 end]}
    set msg [dict create tags [concat {*}[lmap t [split $tags ","] {split $t "="}]] src $src user $user host $host cmd $cmd args $args trailing $trailing line $line]
    if {[dict exists $msg tags time]} {
        dict set msg time [clock scan [regsub {^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)(?:\.\d+)?} [dict get $msg tags time] {\1\2\3T\4\5\6}]]
    } else {
        dict set msg time [clock seconds]
    }
    hook call [expr {[hook exists handle$cmd] ? "handle$cmd":"handleUnknown"}] $serverid $msg
}

hook cmdCLOSE irken 50 {serverid arg} {
    set chanid [expr {[llength $arg] > 0 ? [chanid $serverid [lindex $arg 0]]:$::active}]
    if {![dict exists $::channelinfo $chanid]} {
        addchantext $::active "No such channel [lindex $arg 0]\n" -tags system
        return -code break
    }
    if {[channelpart $chanid] eq ""} {
        addchantext $::active "Closing a server window is not allowed.\n" -tags system
        return -code break
    }
    if {[ischannel $chanid] && ![.nav tag has disabled $chanid]} {
        send $serverid "PART [lindex $arg 0] :[lrange $arg 1 end]"
    }
    removechan $chanid
}
hook cmdEVAL irken 50 {serverid arg} {
    addchantext $::active "$arg -> [eval $arg]\n" -tags system
}
hook cmdME irken 50 {serverid arg} {
    if {[channelpart $::active] eq ""} {
        addchantext $::active "This isn't a channel.\n" -tags system
        return
    }
    send $serverid "PRIVMSG [channelpart $::active] :\001ACTION $arg\001"
    addchantext $::active "[dict get $::serverinfo $serverid nick] $arg\n" -tags self
}
hook cmdJOIN irken 50 {serverid arg} {
    set chanid [chanid $serverid $arg]
    ensurechan $chanid "" disabled
    .nav selection set $chanid
    send $serverid "JOIN :$arg"
}
hook cmdMSG irken 50 {serverid arg} {
    regexp -- {^(\S+) (.*)$} $arg -> target text
    foreach line [split $text \n] {
        send $serverid "PRIVMSG $target :$text"
        ensurechan [chanid $serverid $target] "" {}
        addchantext [chanid $serverid $target] "$text\n" -nick [dict get $::serverinfo $serverid nick] -tags self
    }
}
hook cmdQUERY irken 50 {serverid arg} {
    if {$arg eq ""} {
        addchantext $::active "Query: missing nick.\n" -tags system
        return -code break
    }
    if {[ischannel $arg]} {
        addchantext $::active "Can't query a channel.\n" -tags system
        return -code break
    }
    ensurechan [chanid $serverid $arg] "" {}
}
hook cmdRELOAD irken 50 {serverid arg} {
    source $::argv0
    addchantext $::active "Irken reloaded.\n" -tags system
}
hook cmdSERVER irken 50 {serverid arg} {
    if {![dict exists $::config $arg]} {
        addchantext $::active "$arg is not a server.\n" -tags system
        return
    }
    connect $arg
}

proc docmd {serverid cmd arg} {
    set hook "cmd[string toupper $cmd]"
    if {[hook exists $hook]} {
        hook call $hook $serverid $arg
    } else {
        send $serverid "$cmd $arg"
    }
}

proc returnkey {} {
    if {![dict exists $::serverinfo [serverpart $::active]]} {
        addchantext $::active "Server is disconnected.\n" -tags system
        return
    }
    set text [.cmd get]
    dict set ::channelinfo $::active cmdhistory [concat [list $text] [dict get $::channelinfo $::active cmdhistory]]
    foreach text [split $text "\n"] {
        if {[regexp {^/(\S+)\s*(.*)} $text -> cmd text]} {
            docmd [serverpart $::active] [string toupper $cmd] $text
        } elseif {$text ne ""} {
            if {[channelpart $::active] eq ""} {
                addchantext $::active "This isn't a channel.\n" -tags system
            } else {
                hook call cmdMSG [serverpart $::active] "[channelpart $::active] $text"
                .t yview end
            }
        }
    }
    .cmd delete 0 end
}

proc setcurrenttopic {} {
    if {![ischannel $::active]} {
        addchantext $::active "This isn't a channel.\n" -tags system
        return
    }
    send [serverpart $::active] "TOPIC [channelpart $::active] :[.topic get]"
    focus .cmd
}

proc irken {} {
    initvars
    loadconfig
    initui
    initnetwork
}

# Embedded png icons - terrible, but not as terrible as a graphic library dependency
set ::servericon {iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAABmJLR0QA/wD/AP+gvaeTAAACaUlEQVQ4jXVTv0/bQBT+zrEdObIrtbJEHKWiRSVThFBRIwQd24GCmkwsVbcO/TH2H/CG1G6IlY2lJQ2txNalW1GGdCgRgiFhKI1ARiaJrIt9Z18HsIUpfNJb7t733fvee0dwga2trXuqqn7Wdf2+JEkC18DzPOr7/qtqtfo9PiMX5GVd11fL5fKYqqoQ4lo+AGB/f991HOdTtVp9AwDSxfmzmZmZsVwuh0wmA1mWb4ypqanbAJ7EghIAcM4BAFEUYe/vHjzqQQiRxOnpKYIgwPHx8TlJkkhKgDEGxhjaf9ro3VnGl8M1cM5TwRhDGIbgnMNxHNMwDBMAZADJRUEvoNV5gbvaQzDGEt8nJydQFAW9Xg+maYIQopTL5W/z8/M7cmyBMQY5I6NWfIvLtgBgfHwcADA5OQnOOWRZJoVCwVxaWrqVqoCQxNqNEELAdV2p1Wp9WFlZOa9ACAHGGBzHSSVLkgTTNBEEAVRVRRAE0DQNhmEcdbvd9W63i8RCGIYoFospgSiKMBqN4LouDMPA2dkZLMsC5zxZlMQCYwz9fj8h7+7uglKKiYkJMMagaRo8z0MQBKlFky4LxCPr9/tQVRULCwvodDpx55HP55O8VAWj0ehru91+rmmaBACDwUDJ5/MaIYRQSsXBwcEw/h9RFAlK6Y9YIGm7bdu5bDab5Zw/sizrY6VSedBsNpXZ2dmj7e3tQ0LIyyiKPN/3Q9u2B/8JxNjY2Fidm5t73Gg0fM/z1kql0rtKpaLU6/VflNLXtm1Hl/MzV2ZsWJb1dHNz8/dwOHxv2/bP6enpHue8VKvVmouLiztXH/wHBL5LdDruUzgAAAAASUVORK5CYII=}
set ::channelicon {iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAQAAAC1+jfqAAAAAmJLR0QA/4ePzL8AAAF6SURBVCjPZU9NM0IBFH3MsCpj7CztLPwIW6z9DEsbKxvGWDRGU6ZhwcI0pSTTxCPivTeiKU3RF0l59V56pFKiJsc14+uNe+Zu7j3n3nMYRlXsgJcPKj55fz7Qxfwvq4bPvaCOGuSm26RWDnF+/tI1IzUbKEGmFpTpzj8ELvtKyoOahCcoyKMA36Oj92ft1AaVKu7hb0TfirTOUu8WVRf280WI4EqHJRFpXCMDW0LlwX4Wp/FmwXoefk8iCU9zfVxFcE3YsYVt1jZoa/vBw15Vrb0a1izSZza4Mxwqu+EFe2vt/j7e79o4luVWhf4KCLQVxHEDseXJuqecWiI4eAkVCicghjJe8EwRP/GAdGtPso4xllQGUVJ5KWYeEiGPO9wiRabvYDlhzLkYTuHHEXkPEzFOl6K4QAQhIpmvGOOyUVqru8DRSKD+hYAE1kVyoeubHdUtrNQ22w7SXn4hglU4Kib+J+piz8KkntOnDBljbkk0pPVxvX1uBB0fzyc6FzEmMTIAAAAASUVORK5CYII=}
set ::usericon {iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAQAAAC1+jfqAAAAAmJLR0QA/4ePzL8AAAD/SURBVBgZlcHLSgJhGIDhL2gC9x0uqJZuhIKCrqEbCLqGTouoXVKB0VDhppXS4IwLReefLM1Bp0wN7cQEEha9rUShv0XPI/+SmLCjdjRniN7llO92aXPtpiZFx9t755VHGuR2Rcc7eeaJFnUKZ6KTXW/zQICPvSM6F4vVvk+Fq8/ksuhZQQkPqyl/yZsZLAqn8ltqPLNy47T6t5Spf5TS6SXGZFQh2/l+I+SFDk3u8L+clAwdznhhjYCAgBpVynjkwv1pGTiYK5JHoVAoFIo8RY5mZWBrwemlUSgUCoXCwultzsvQWmwjGXePG2bX7Cbu4+72+WpMNAyJSEQMGfED1Mesk3W69Y4AAAAASUVORK5CYII=}
set ::blankicon {iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAABmJLR0QA/wD/AP+gvaeTAAAAEklEQVQ4jWNgGAWjYBSMAggAAAQQAAF/TXiOAAAAAElFTkSuQmCC}
set ::opsicon {iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAABmJLR0QA/wD/AP+gvaeTAAAAy0lEQVQ4jcXSQUoDQRCF4c+QASV9EmPMXoagqNdJ7haCK0VyA5XcIE72DRFlEMZFkMjQmRlwkQe1aLrfT1X149g6qZ0zXGOECis847sLbBLYjIgzyhnlBTFQIO9i/nigqmq1oBqwbYJkgU3K/BcSeEc/BbgfEw+Zf2tIxG3d3MPlDWdtM95xinEK8C/18PrEZ9vDR77wkrrLAsWiYf75bolrB5YI+YBtCjLff+NVW5d5oBgSp5RTyvNdkNZN5nqU+/ZRhjcsdYzycfQDtB1ssjiVxGkAAAAASUVORK5CYII=}
set ::voiceicon {iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAABmJLR0QA/wD/AP+gvaeTAAAAcElEQVQ4jc2SOwqAMBAFB0vjkRSC95aAHklTr0USsFjNRxAXHmkyA29Z+OvYmFbY+JB6yQTmgEVgExg8MDfAElMuUeByiQ19nQKnOLnbSRcekXzD5z8j9LteYZVQL78HRVIOK5J6OI19c0gXSTv87ZxXSlezPrPf8wAAAABJRU5ErkJggg==}
set ::ownericon {iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAMAAAAoLQ9TAAAAYFBMVEUAAAAAAAAAAAAAAAAAAAAAAAAAAAAFBQUHBwcHBwcHBwcICAgICAgICAgHBwcKCgoPDw8GBgYGBgYtLS0sLCwtLS1GRkZHR0dHR0dmZmZ0dHR1dXV3d3d9fX2AgID///9uPZFLAAAAGXRSTlMAECQnKCtKlJWWv7/BxtDd9PX29vf4/Pz9+gKGIQAAAAFiS0dEHwUNEL0AAABVSURBVBjTY2AgBzDy8QMBHyNcgENEEghEOWF8FiFpOSCQEWSFCvCIy4GBBC+EzyYgCxGQFWDDLsDABdUixg01g0lICsSXFmKGWcMuDLJWhAO3w0gFADKmB8TUOG0DAAAAAElFTkSuQmCC}
set ::adminicon {iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAABmJLR0QA/wD/AP+gvaeTAAAAwUlEQVQ4jc2SPw4BYRDFf9ZmsSSocAFROorGESTcQUehcAEFiYRGo9O5AUqJagsSLTa7rH+fQrObrPCtgpdMMTN5b15mBv4NMVlC2JMoGEKwAZZBHYhCDisdZwEUAwncBoh+lXtKx05EGQEZKQExfIbZRdRLOLqGrak0gIgfIeQj4MFqC7Ue1txgfzhSASbuvvK5NYRfXX1F2NnQHON0plyugtbpTBtw3g76eon5LGZSZ0aQM4YV1kBZmuiC9Cv/Hg+kzEMtu4oFIwAAAABJRU5ErkJggg==}
set ::halfopsicon {iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAMAAAAoLQ9TAAAAZlBMVEUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADAwMNCQkJBwcJBwkPCwwPDAwNCwswJCYIBgcKCAhGNTgHBgYTDg8HBQWPa3GOa3FcRUmLaW/PnKXhqbPnrrjqsLr+v8r/wMv///+JHHLqAAAAGXRSTlMABAUHIjU3Q0pajZCQp67T7/Pz9PX1+vz949IxUAAAAAFiS0dEIcRsDRYAAABJSURBVBjTY2AgEjCyIvOYOXgFxTjhXDY+EQEJGWkhFpgAt6SsAhCI8zNBBXikQHwFeWEuVAEFOVF2/AIILRiGYliL4TAsTscPAEbMB+2tsxn5AAAAAElFTkSuQmCC}
set ::irkenicon {iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAMAAAC6V+0/AAAATlBMVEUAAAD/v4D/35//1Zz/15f/1pj/2Zn/2Jz/2Zv/15v/15v/2Zv/2Jz/2Zv/2Jv/2Zv/2Zv/2Jv/2Jr/2Jv/2Jv/2Zv/2Jv/2Jv/2Jv///9JcTGKAAAAGHRSTlMABAgSICU8SEpmc3+IkpeZs83Q3d7o+v4PPFCqAAAAAWJLR0QZ7G61iAAAAEBJREFUGNNj4OFHBRwMQCCBBviGvKCgMAyIgsREuBhQACMvUJCdAR1wikkIYAgysImKs2KKsghxYwoyMDEzUAwA7hYS0qRY31oAAAAASUVORK5CYII=}

# Start up irken when executed as file
if {[info exists argv0] && [file dirname [file normalize [info script]/...]] eq [file dirname [file normalize $argv0/...]]} {irken}
