#!/usr/bin/wish8.6
# Irken - dlowe@dlowe.net
package require tls
package require BWidget

proc ::tcl::dict::get? {default dict key args} {if {[dict exists $dict $key {*}$args]} {return [dict get $dict $key {*}$args]} {return $default}}
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
if {![info exists ::hooks]} {set ::hooks [dict create]}
proc hook {op name args} {
    switch -- $op {
        "exists" {return [expr {[dict get? "" $::hooks $name] ne ""}]}
        "unset" {
            dict set ::hooks $name [lsearch -all -exact -inline -not -index 0 [dict get? {} $::hooks $name] [lindex $args 0]]
            return ""
        }
        "call" {
            foreach hookproc [dict get? {} $::hooks $name] {
                try {[lindex $hookproc 0] {*}$args
                } on continue {val} {set args $val}
            }
            return $args
        }
        default {
            lassign $args priority params code
            set procname "[uplevel 1 {namespace current}]::${op}_${name}"
            proc $procname $params $code
            set hook [lsearch -all -exact -inline -not -index 0 [dict get? {} $::hooks $op] $procname]
            dict set ::hooks $op [lsort -index 1 -integer [linsert $hook end [list $procname $priority]]]
            return $op
        }
    }
}

namespace eval ::irc {
    namespace export send
    proc send {serverid str} {set chan [dict get $::serverinfo $serverid chan]; try {puts $chan $str} on error {err} {irken::addchantext $serverid "WRITE ERROR: $err" -tags system};flush $chan}
}

namespace eval ::irken {
    namespace import ::irc::*
    namespace export chanid addchantext ensurechan updateusermodes isself ischannel serverpart channelpart

    # A chanid is $serverid for the server channel, $serverid/$channel for channel display.
    proc chanid {serverid chan} { if {$chan eq ""} {return $serverid} {return [string cat $serverid "/" [irctolower [dict get $::serverinfo $serverid casemapping] $chan]]} }
    proc serverpart {chanid} {lindex [split $chanid {/}] 0}
    proc channelpart {chanid} {lindex [split $chanid {/}] 1}
    proc ischannel {chanid} {regexp -- "^\[[dict get $::serverinfo [serverpart $chanid] chantypes]\]\[^ ,\\a\]\{0,[dict get $::serverinfo [serverpart $chanid] channellen]\}\$" [channelpart $chanid]}
    proc globescape {str} {return [regsub -all {[][\\*?\{\}]} $str {\\&}]}

    set ::codetagcolormap [dict create 0 white 1 black 2 navy 3 green 4 red 5 maroon 6 purple 7 olive 8 yellow 9 lgreen 10 teal 11 cyan 12 blue 13 magenta 14 gray 15 lgray {} {}]
    set ::tagcolormap [dict create white white black black navy navy green green red red maroon maroon purple purple olive {dark olive green} yellow gold lgreen {spring green} teal {pale turquoise} cyan deepskyblue blue blue magenta magenta gray gray lgray {light grey} {} {}]

    proc initvars {} {
        # Set up fonts ahead of time so they can be configured
        catch {font create Irken.List {*}[font actual TkDefaultFont] -size 10}
        catch {font create Irken.Fixed {*}[font actual TkFixedFont] -size 10}

        # ::config is a dict keyed on serverid containing config for each server, loaded from a file.
        # ::servers is a dict keyed on chan containing the serverid
        # ::serverinfo is a dict keyed on serverid containing the chan, current nick, and other server-specific info
        # ::channeltext is a dict keyed on chanid containing channel text with tags
        # ::channelinfo is a dict keyed on chanid containing topic, user list, input history, place in the history index.
        # ::active is the chanid of the shown channel.
        # ::seennicks a list of chanid nicks that we have seen since the last presence check
        lassign {} ::config ::servers ::serverinfo ::channeltext ::channelinfo ::active ::seennicks ::ctcppings
    }

    proc server {serverid args} {dict set ::config $serverid $args}

    proc loadconfig {} {
        lassign "$::env(HOME)/.config/irken/" configdir config
        file mkdir $configdir
        if {[catch {glob -directory $configdir "*.tcl"} configpaths]} {
            if {[catch {open "$configdir/50irken.tcl" w} fp]} {
                puts stderr "Couldn't write default config.  Exiting."
                exit 1
            }
            puts $fp {server "LiberaChat" -host irc.libera.chat -port 6697 -insecure false -nick tcl-$::env(USER) -user $::env(USER) -autoconnect True -autojoin {\#irken}}
            close $fp
            set configpaths [list "$configdir/50irken.tcl"]
        }
        foreach configpath [lsort $configpaths] {
            source $configpath
        }
    }

    hook openhlink irken 50 {hlink} {exec -ignorestderr -- xdg-open $hlink &}
    hook textpopup nanoirc 99 {x y rootx rooty} {
        .t.popup entryconfigure "Copy" -state [expr {([.t tag ranges sel] eq "") ? "disabled":"normal"}]
        tk_popup .t.popup $rootx $rooty
    }

    proc copytext {} {
        if {[set r [.t tag nextrange sel 0.0]] ne ""} {
            clipboard clear; clipboard append [.t get {*}$r]
        }
    }

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
        bind .nav <<TreeviewSelect>> [namespace code selectchan]
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
        .t tag config self -foreground gray30
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
        .t tag bind hlink <ButtonRelease-1> [namespace code {hook call openhlink [%W get {*}[%W tag prevrange hlink @%x,%y]]}]
        .t tag bind hlink <Enter> {%W configure -cursor hand2}
        .t tag bind hlink <Leave> {%W configure -cursor xterm}
        menu .t.popup -tearoff 0
        .t.popup add command -label "Copy" -command [namespace code {copytext}]
        bind .t <ButtonPress-3> [namespace code {hook call textpopup %x %y %X %Y}]
        ttk::frame .cmdline
        ttk::label .nick -padding 3
        text .cmd -height 1 -wrap none -font Irken.Fixed
        ttk::treeview .users -show tree -selectmode browse
        .users tag config q -foreground gray -image [image create photo -format png -data $::ownericon]
        .users tag config a -foreground orange -image [image create photo -format png -data $::adminicon]
        .users tag config o -foreground red -image [image create photo -format png -data $::opsicon]
        .users tag config h -foreground pink -image [image create photo -format png -data $::halfopsicon]
        .users tag config v -foreground blue -image [image create photo -format png -data $::voiceicon]
        .users column "#0" -width 140
        bind .users <Double-Button-1> [namespace code {userclick}]
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
        bind . <Prior> {.t yview scroll -1 page}
        bind . <Next> {.t yview scroll 1 page}
        bind . <Control-Prior> {ttk::treeview::Keynav .nav up}
        bind . <Control-Next> {ttk::treeview::Keynav .nav down}
        bind . <Control-space> [namespace code {nexttaggedchannel}]
        bind . <Control-c> {if {[set r [.t tag nextrange sel 0.0]] ne ""} {clipboard clear; clipboard append [.t get {*}$r]}}
        bind .topic <Return> [namespace code setcurrenttopic]
        bind .cmd <Return> [namespace code returnkey]
        bind .cmd <Up> [namespace code [list history up]]
        bind .cmd <Down> [namespace code [list history down]]
        bind .cmd <Tab> [namespace code tabcomplete]
        bind .cmd <KeyPress> [namespace code {stopimplicitentry %K}]

        hook call setupui
        # this is called after the setupui hook because earlier tags override
        # later tags.
        .users tag config user -foreground black -image [image create photo -format png -data $::blankicon]

        dict for {serverid serverconf} $::config {
            dict set ::serverinfo $serverid $::ircdefaults
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
            if {[dict get? 0 $serverconf -autoconnect]} {connect $serverid}
        }
        after 500 [namespace code "sendpendingison"]
    }

    proc irctolower {casemapping str} {
        set upper [dict get {ascii 90 rfc1459 94 strict-rfc1459 93} $casemapping]
        return [join [lmap c [split $str ""] {scan $c %c i; format %c [expr {$i >= 65 && $i <= $upper ? $i+32:$i}]}] ""]
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
    proc isserver {serverid nick} {
        if [dict exists $::serverinfo $serverid servername] {
            if {[irceq [dict get $::serverinfo $serverid casemapping] [dict get $::serverinfo $serverid servername] $nick]} {
                return true
            }
        }
        return [expr {$nick == "*"}]
    }

    proc setchantopic {chanid text} {
        dict set ::channelinfo $chanid topic $text
        if {$chanid eq $::active} {
            .topic delete 0 end
            .topic insert 0 $text
        }
    }

    proc updatechaninfo {chanid} {
        .chaninfo configure -text [expr {![ischannel $chanid] ? "":[.nav tag has disabled $chanid] ? "Unjoined":"[llength [dict get $::channelinfo $chanid users]] users"}]
    }

    proc stopimplicitentry {key} {
        dict unset ::channelinfo $::active historyidx
        dict unset ::channelinfo $::active tab
    }

    proc history {op} {
        set idx [set oldidx [dict get? {} $::channelinfo $::active historyidx]]
        set cmdhistory [dict get $::channelinfo $::active cmdhistory]
        switch -- $op {
            "up" {set idx [expr {$idx eq "" ? 0 : $idx == [llength $cmdhistory] - 1 ? $oldidx : $idx + 1}]}
            "down" {set idx [expr {$idx eq "" || $idx == 0 ? "" : $idx - 1}]}
        }
        if {$idx eq $oldidx} {return}
        dict set ::channelinfo $::active historyidx $idx
        .cmd delete 1.0 end
        if {$idx ne {}} {.cmd insert 1.0 [lindex $cmdhistory $idx]}
        return -code break
    }
    proc tabcomplete {} {
        if {![ischannel $::active]} {return -code break}
        lassign [list [dict get $::channelinfo $::active users]] userlist user
        if {[dict exists $::channelinfo $::active tab]} {
            lassign [dict get $::channelinfo $::active tab] tabprefix tablast tabstart tabend
            if {[set pos [lsearch -exact -index 0 $userlist $tablast]] != -1} {
                set user [lsearch -inline -nocase -start [expr {$pos+1}] -index 0 -glob $userlist "[globescape $tabprefix]*"]
            }
        } else {
            lassign [list [.cmd get 1.0 {end - 1 char}] [regexp -inline {\d+$} [.cmd index insert]]] s pt
            if {[string index $s $pt] eq " "} {
                set pt [expr {$pt - 1}]
                if {[string index $s $pt] eq " "} {
                    return -code break
                }
            }
            lassign [list [string wordstart $s $pt] [string wordend $s $pt]] tabstart tabend
            set tabprefix [string trimright [string range $s $tabstart $tabend]]
        }
        if {$user eq ""} {
            set user [lsearch -inline -nocase -index 0 -glob $userlist "[globescape $tabprefix]*"]
            if {$user eq ""} {
                return -code break
            }
        }
        set str [expr {$tabstart == 0 ? "[lindex $user 0]: ":[lindex $user 0]}]
        .cmd delete 1.$tabstart 1.$tabend
        .cmd insert 1.$tabstart $str
        dict set ::channelinfo $::active tab [list $tabprefix [lindex $user 0] $tabstart [expr {$tabstart + [string length $str]}]]
        return -code break
    }
    proc setchanusers {chanid users} {
        dict set ::channelinfo $chanid users $users
        if {$chanid ne $::active} {
            return
        }
        updatechaninfo $chanid
        set r -1
        foreach item [lsort -command "usercmp [serverpart $chanid]" $users] {
            .users move [lindex $item 0] {} [incr r]
        }
    }

    proc updateusermodes {chanid user addmodes delmodes} {
        set users [dict get $::channelinfo $chanid users]
        if {[set pos [lsearch -exact -index 0 $users $user]] == -1} {return}
        set modes [lindex [lindex $users $pos] 1]
        foreach delmode $delmodes {set modes [lsearch -all -inline -not -exact $modes $delmode]}
        set modes [concat $modes $addmodes]
        if {$chanid eq $::active} {
            foreach delmode $delmodes  {.users tag remove $delmode $user}
            foreach addmode $addmodes {.users tag add $addmode $user}
        }
        setchanusers $chanid [lreplace $users $pos $pos [list $user $modes]]
    }

    # users should be {nick modes}
    proc addchanuser {chanid user modes} {
        set prefixes [dict get $::serverinfo [serverpart $chanid] prefix]
        regexp -- "^(\[[join [dict keys $prefixes] ""]\]*)(.*)" $user -> userprefixes nick
        set usermodes [concat $modes [lmap uprefix [split $userprefixes ""] {dict get $prefixes $uprefix}]]
        set users [dict get $::channelinfo $chanid users]
        if {[lsearch -exact -index 0 $users $nick] != -1} {
            updateusermodes $chanid $nick $usermodes {}
            return
        }
        # new user to channel
        if {$chanid eq $::active} {.users insert {} end -id $nick -text $nick -tag [concat $usermodes [list "user"]]}
        setchanusers $chanid [concat $users [list [list $nick $usermodes]]]
    }

    proc remchanuser {chanid user} {
        if {[dict exists $::channelinfo $chanid]} {
            set prefixes [dict keys [dict get $::serverinfo [serverpart $chanid] prefix]]
            set nick [string trimleft $user $prefixes]
            set users [dict get $::channelinfo $chanid users]
            dict set ::channelinfo $chanid users [lsearch -all -inline -not -exact -index 0 $users $nick]
            if {$chanid eq $::active && [.users exists $nick]} {
                .users delete [list $nick]
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
        } elseif {[set next [$window next $item]] ne ""} {
            return $next
        } elseif {[set next [$window next [$window parent $item]]] ne ""} {
            return $next
        }
        # loop back to top
        return [lindex [$window children {}] 0]
    }

    proc nexttaggedchannel {} {
        set curchan [.nav selection]
        set chan [loopedtreenext .nav $curchan]
        while {$chan ne $curchan} {
            if {[.nav tag has message $chan]} {break}
            set chan [loopedtreenext .nav $chan]
        }
        if {$chan ne $curchan} {.nav selection set $chan}
    }

    proc tagcolorchange {pos prefix defaultcol oldcol newcol} {
        set newcol [expr {$newcol eq "" ? $defaultcol:$newcol}]
        if {$oldcol eq $newcol} {return [list {} $oldcol]}
        set result {}
        if {$oldcol ne $defaultcol} {lappend result [list $pos pop [string cat $prefix _ $oldcol]]}
        if {$newcol ne $defaultcol} {lappend result [list $pos push [string cat $prefix _ $newcol]]}
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
                    if {[regexp -- {^0?(\d\d?)(,0?(\d\d?))?} $rest match fgnum _ bgnum]} {
                        set rest [string range $rest [string length $match] end]
                        if {$reverse} {
                            lassign [list $bgnum $fgnum] fgnum bgnum
                        }
                        lassign [tagcolorchange $pos "fg" "black" $fg [dict get? "black" $::codetagcolormap $fgnum]] newtags fg
                        lappend tagranges {*}$newtags
                        lassign [tagcolorchange $pos "bg" "white" $bg [dict get? "white" $::codetagcolormap $bgnum]] newtags bg
                        lappend tagranges {*}$newtags
                    } else {
                        lassign [tagcolorchange $pos "fg" "black" $fg "black"] newtags fg
                        lappend tagranges {*}$newtags
                        lassign [tagcolorchange $pos "bg" "white" $bg "white"] newtags bg
                        lappend tagranges {*}$newtags
                    }
                    continue
                }
                "\x16" {
                    lassign [list [expr {!$reverse}] $fg $bg] reverse newbg newfg
                    lassign [tagcolorchange $pos "fg" "black" $fg $newfg] newtags fg
                    lappend tagranges {*}$newtags
                    lassign [tagcolorchange $pos "bg" "white" $bg $newbg] newtags bg
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
        foreach rangetag [lsort -index 0 -integer $ranges] {
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
    set httpregexp {https?://[-A-Za-z0-9._~:/?#\[\]@!$%&'()*+,;=]+[-A-Za-z0-9_~:/#\[\]@$%&'()*+=]}
    hook tagchantext irken-http 60 {text ranges} {
        return -code continue [list $text [concat $ranges [regexranges $text $irken::httpregexp hlink]]]
    }

    # addchantext inserts a line of text at the end of a channel's
    # buffer, updating the UI as necessary.  If adding text to the
    # active channel, it inserts the text at the end of the widget.
    # Otherwise, it sets the highlighting for the channel in the nav
    # widget.  It calls the tagchantext hook to split the text into
    # {text taglist} chunks.
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
        lappend newtext "\[[clock format $timestamp -format %H:%M:%S]\]" {} "\t[dict get? * $args -nick]\t" "nick" {*}$textranges "\n" {}
        dict append ::channeltext $chanid " $newtext"
        if {$chanid ne $::active} {
            # Add all the tags passed in as -tag to the nav entry, plus unseen tag.
            foreach tag [concat "unseen" [dict get? {} $args -tags]] {
                .nav tag add $tag $chanid
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
        set ::active $chanid
        .nav focus $chanid
        foreach tag [.nav item $chanid -tags] {
            # Remove all inessential tags
            if {[lsearch -exact [list "server" "channel" "direct" "disabled"] $tag] == -1} {
                .nav tag remove $tag $chanid
            }
        }
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
        lappend ::seennicks $chanid
        if {[.nav exists $chanid]} {
            if {$name ne ""} {.nav item $chanid -text $name}
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
        .nav delete [list $chanid]
    }

    proc sendpendingison {} {
        set servernicks [dict create]
        foreach chanid [dict keys $::channelinfo] {
            if {[channelpart $chanid] ne "" && ![ischannel $chanid] && ![.nav tag has disabled [serverpart $chanid]]} {
                dict lappend servernicks [serverpart $chanid] [channelpart $chanid]
            }
        }
        dict for {serverid nicks} $servernicks {
            foreach line [regexp -all -inline {\S(?:\S{0,200}|.{0,200}(?=\s+|$))} [join $nicks " "]] {send $serverid "ISON $line"}
        }
        after 500 [namespace code "updatepresence"]
    }

    proc updatepresence {} {
        foreach chanid [dict keys $::channelinfo] {
            if {[channelpart $chanid] ne "" && ![ischannel $chanid] && ![.nav tag has disabled $chanid] && [lsearch $::seennicks $chanid] == -1} {
                .nav tag add disabled $chanid
                addchantext $chanid "[channelpart $chanid] has logged out." -tags system
            }
        }
        set ::seennicks {}
        after 60000 [namespace code "sendpendingison"]
    }

    set ::ircdefaults [dict create casemapping "rfc1459" chantypes "#&" channellen "200" prefix [dict create @ o + v]]

    proc connect {serverid} {
        if {[catch {dict get $::config $serverid -host} host]} {
            addchantext $serverid "Fatal error: $serverid has no -host option $host." -tags system
            return
        } elseif {![dict exists $::config $serverid -nick]} {
            addchantext $serverid "Fatal error: $serverid has no -nick option." -tags system
            return
        } elseif {![dict exists $::config $serverid -user]} {
            addchantext $serverid "Fatal error: $serverid has no -user option." -tags system
            return
        }
        set insecure [dict get? 0 $::config $serverid -insecure]
        set port [dict get? [expr {$insecure ? 6667:6697}] $::config $serverid -port]

        addchantext $serverid "Connecting to $serverid ($host:$port)..." -tags system
        set chan [if {$insecure} {socket -async $host $port} {tls::socket -async $host $port}]
        fileevent $chan writable [namespace code [list connected $chan]]
        dict set ::servers $chan $serverid
        dict set ::serverinfo $serverid [dict merge [dict create chan $chan nick [dict get $::config $serverid -nick]] $::ircdefaults]
    }

    proc connected {chan} {
        set serverid [dict get $::servers $chan]
        if {[set err [chan configure $chan -error]] ne ""} {
            close $chan
            addchantext $serverid "Connection failure: $err" -tags system
            hook call disconnection $serverid
            return
        }
        chan configure $chan -blocking 0 -buffering line
        fileevent $chan writable {}
        fileevent $chan readable [namespace code [list recv $chan]]
        .nav tag remove disabled [concat [list $serverid] [.nav children $serverid]]
        hook call connected $serverid
        addchantext $serverid "Connected." -tags system
        # IRCv3 states that the client should send a single CAP REQ,
        # followed by PASS, NICK, and USER, and only then the rest
        # of the capability negotiations.  Servers seem to be flexible
        # in this regard, but this does things in the proper order.

        # Note that the client sends multiple CAP REQ requests instead
        # of one because a) it's doing so blindly and b) the requested
        # capabilities are rejected as a whole if one of them isn't
        # present.
        send $serverid "CAP REQ :multi-prefix"
        if {[dict exists $::config $serverid -pass]} {
            send $serverid "PASS [dict get $::config $serverid -pass]"
        }
        send $serverid "NICK [dict get $::config $serverid -nick]"
        send $serverid "USER [dict get $::config $serverid -user] 0 * :Irken user"
        send $serverid "CAP REQ :znc.in/server-time-iso\nCAP REQ :server-time\nCAP END"
    }

    proc disconnected {chan} {
        close $chan
        set serverid [dict get $::servers $chan]
        .nav tag add disabled [concat [list $serverid] [.nav children $serverid]]
        addchantext $serverid "Server disconnected." -tags system
        hook call disconnection $serverid
    }

    hook handle001 irken 50 {serverid msg} {
        dict set ::serverinfo $serverid servername [dict get $msg src]
        dict set ::serverinfo $serverid nick [lindex [dict get $msg args] 0]
        .nick configure -text [lindex [dict get $msg args] 0]
        foreach chan [dict get? {} $::config $serverid -autojoin] {
            ensurechan [chanid $serverid $chan] "" disabled
            send $serverid "JOIN $chan"
        }
    }
    hook handle005 irken 50 {serverid msg} {
        foreach param [lrange [dict get $msg args] 1 end] {
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
        addchantext [chanid $serverid $nick] "$nick is away: $awaymsg" -tags system
    }
    hook handle303 irken 50 {serverid msg} {
        foreach nick [split [lindex [dict get $msg args] 1] " "] {
            set chanid [chanid $serverid $nick]
            if {[.nav exists $chanid]} {
                ensurechan $chanid $nick {}
                if {[.nav tag has disabled $chanid]} {
                    .nav tag remove disabled $chanid
                    addchantext $chanid "[channelpart $chanid] has logged in." -tags system
                }
            }
        }
    }
    hook handle305 irken 50 {serverid msg} {
        addchantext $::active "You are no longer marked as being away." -tags system
    }
    hook handle306 irken 50 {serverid msg} {
        addchantext $::active "You have been marked as being away." -tags system
    }
    hook handle328 irken 50 {serverid msg} {
        lassign [dict get $msg args] target chan url
        addchantext [chanid $serverid $chan] "Channel URL is $url." -tags system
    }
    hook handle331 irken 50 {serverid msg} {
        set chanid [chanid $serverid [lindex [dict get $msg args] 1]]
        setchantopic $chanid ""
        addchantext $chanid "No channel topic set." -tags system
    }
    hook handle332 irken 50 {serverid msg} {
        lassign [dict get $msg args] target chan topic
        set chanid [chanid $serverid $chan]
        ensurechan $chanid $chan {}
        setchantopic $chanid $topic
        if {$topic ne ""} {
            addchantext $chanid "Channel topic: $topic" -tags system
        } else {
            addchantext $chanid "No channel topic set." -tags system
        }
    }
    hook handle333 irken 50 {serverid msg} {
        set chanid [chanid $serverid [lindex [dict get $msg args] 1]]
        set nick [lindex [dict get $msg args] 2]
        if {[llength [dict get $msg args]] == 3} {
            set time [lindex [dict get $msg args] 3]
            addchantext $chanid "Topic set by $nick at [clock format $time]." -tags system
        } else {
            addchantext $chanid "Topic set by $nick." -tags system
        }
    }
    hook handle353 irken 50 {serverid msg} {
        set chanid [chanid $serverid [lindex [dict get $msg args] 2]]
        foreach user [split [dict get $msg trailing] " "] {
            addchanuser $chanid $user {}
        }
    }
    hook handle366 irken 50 {serverid msg} {return}
    hook handle372 irken 50 {serverid msg} {
        addchantext $serverid "[dict get $msg trailing]" -tags system
    }
    hook handle376 irken 50 {serverid msg} {
        hook call ready $serverid
    }
    hook handle422 irken 50 {serverid msg} {
        hook call ready $serverid
    }
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
        if {![isself $serverid [dict get $msg src]]} {
            addchantext [chanid $serverid $chan] "[dict get $msg src] has joined $chan" -tags system
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
        set note [expr {$note ne "" ? " ($note)":""}]
        addchantext [chanid $serverid $chan] "[dict get $msg src] kicks [expr {[isself $serverid $target] ? "you":$target}] from $chan.$note" -tags system
    }
    hook handleMODE irken 50 {serverid msg} {
        set args [lassign [dict get $msg args] target]
        set chanid [chanid $serverid $target]
        set msgdest [expr {[ischannel $chanid] ? $chanid:$serverid}]
        if {[lsearch -exact [dict get $msg src] "!"] == -1} {
            addchantext $msgdest "Mode for $target set to [lrange [dict get $msg args] 1 end]" -tags system
        } else {
            addchantext $msgdest "[dict get $msg src] sets mode for $target to [lrange [dict get $msg args] 1 end]" -tags system
        }
        if {[ischannel $chanid]} {
            lassign {} changes params
            foreach arg $args {
                if {[regexp {^([-+])(.*)} $arg -> op terms]} {
                    lappend changes {*}[lmap term [split $terms ""] {list $op $term}]
                } else {
                    lappend params $arg
                }
            }
            set modes [dict values [dict get $::serverinfo $serverid prefix]]
            foreach change $changes {
                if {[lindex $change 1] in $modes}  {
                    set params [lassign $params param]
                    if {[lindex $change 0] eq "+"} {
                        updateusermodes $chanid $param [lindex $change 1] {}
                    } else {
                        updateusermodes $chanid $param {} [lindex $change 1]
                    }
                }
            }
        }
    }
    hook handleNICK irken 50 {serverid msg} {
        set oldnick [dict get $msg src]
        set newnick [lindex [dict get $msg args] 0]
        if {[isself $serverid $oldnick]} {
            dict set ::serverinfo $serverid nick $newnick
            if {[serverpart $::active] eq $serverid} {
                .nick configure -text $newnick
            }
        }
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
            .nav delete [list $oldchanid]
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
            if {$user eq ""} {return}
            addchantext $chanid "$oldnick is now known as $newnick" -tags system
        }
        set newchanid [chanid $serverid $newnick]
        if {[dict exists $::channelinfo $newchanid]} {
            addchantext $newchanid "$oldnick is now known as $newnick" -tags system
        }
    }
    hook handleNOTICE irken 50 {serverid msg} {
        hook call handlePRIVMSG $serverid $msg
    }
    hook handlePART irken 50 {serverid msg} {
        set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
        remchanuser $chanid [dict get $msg src]
        if {[isself $serverid [dict get $msg src]]} {
            if {[.nav exists $chanid]} {
                .nav tag add disabled $chanid
                dict set ::channelinfo $chanid users {}
                if {$chanid eq $::active} {
                    .users delete [.users children {}]
                    updatechaninfo $chanid
                }
            }
        }
    }
    hook handlePART irken-display 75 {serverid msg} {
        lassign [dict get $msg args] chan note
        set note [expr {$note ne "" ? " ($note)":""}]
        set chanid [chanid $serverid $chan]
        if {[isself $serverid [dict get $msg src]]} {
            if {[dict exists $::channelinfo $chanid]} {
                addchantext $chanid "You have left $chan.$note" -tags system
            }
        } else {
            addchantext $chanid "[dict get $msg src] has left $chan.$note" -tags system
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
        dict lappend msg tag "message"
        if {[isself $serverid [dict get $msg src]]} {
            dict lappend msg tag "self"
        }
        if {[string first [dict get $::serverinfo $serverid nick] [dict get $msg trailing]] != -1} {
            dict lappend msg tag "highlight"
        }
        return -code continue [list $serverid $msg]
    }
    hook handlePRIVMSG irken 50 {serverid msg} {
        if {[isserver $serverid [dict get $msg chan]]} {
            set chanid $serverid
        } else {
            set chanid [chanid $serverid [dict get $msg chan]]
            ensurechan $chanid [dict get $msg chan] {}
        }
        if {[regexp {^\001([A-Za-z0-9]+) ?(.*?)\001?$} [dict get $msg trailing] -> cmd text]} {
            hook call ctcp$cmd $chanid $msg $text
            return -code break
        }
        addchantext $chanid [dict get $msg trailing] -time [dict get $msg time] -nick [dict get $msg src] -tags [dict get? {} $msg tag]
    }
    hook handleQUIT irken 50 {serverid msg} {
        foreach chanid [lsearch -all -inline -glob [dict keys $::channelinfo] "$serverid/*"] {
            if {[lsearch -exact -index 0 [dict get $::channelinfo $chanid users] [dict get $msg src]] != -1} {
                remchanuser $chanid [dict get $msg src]
                dict lappend msg affectedchans $chanid
            }
        }
        # The user isn't going to be in the channels, so a message with
        # annotation is passed for the display hook.
        return -code continue [list $serverid $msg]
    }
    hook handleQUIT irken-display 75 {serverid msg} {
        set note [expr {[set note [dict get? "" $msg trailing]] eq "" ? "":" ($note)"}]
        foreach chanid [dict get? {} $msg affectedchans] {
            addchantext $chanid "[dict get $msg src] has quit$note" -tags system
        }
        set chanid [chanid $serverid [dict get $msg src]]
        if {[.nav exists $chanid]} {
            .nav tag add disabled $chanid
            addchantext $chanid "[dict get $msg src] has quit$note"
        }

    }
    hook handleTOPIC irken 50 {serverid msg} {
        set chanid [chanid $serverid [lindex [dict get $msg args] 0]]
        set topic [dict get $msg trailing]
        setchantopic $chanid $topic
        addchantext $chanid "[dict get $msg src] sets title to $topic" -tags system
    }
    hook handleUnknown irken 50 {serverid msg} {
        addchantext $serverid "[dict get $msg line]" -tags system
    }

    proc ctcpreply {chanid msg cmd text} {
        if {[dict get $msg cmd] ne "NOTICE"} {
            return 0
        }
        addchantext $chanid "CTCP $cmd reply: $text" -time [dict get $msg time] -tags system
        return 1
    }

    hook ctcpACTION irken 50 {chanid msg text} {
        addchantext $chanid "[dict get $msg src] $text" -time [dict get $msg time] -tags [dict get? {} $msg tag]
    }
    hook ctcpCLIENTINFO irken 50 {chanid msg text} {
        if {[ctcpreply $chanid $msg "CLIENTINFO" $text]} {
            return -code break
        }
        addchantext $chanid "CTCP CLIENTINFO request" -time [dict get $msg time] -tags system
        send [serverpart $chanid] "NOTICE [dict get $msg src] :\001ACTION CLIENTINFO PING TIME VERSION\001"
    }
    hook ctcpPING irken 50 {chanid msg text} {
        if {[dict get $msg cmd] eq "NOTICE"} {
            if {[dict exists $::ctcppings "[dict get $msg src]-$text"]} {
                set rtt [expr {[clock milliseconds] - [dict get $::ctcppings "[dict get $msg src]-$text"]}]
                addchantext $chanid "CTCP PING reply: $text (${rtt}ms)" -time [dict get $msg time] -tags system
            } else {
                addchantext $chanid "CTCP PING reply: $text" -time [dict get $msg time] -tags system
            }
            return -code break
        }
        addchantext $chanid "CTCP PING request: $text" -time [dict get $msg time] -tags system
        send [serverpart $chanid] "NOTICE [dict get $msg src] :\001PING $text\001"
    }
    hook ctcpTIME irken 50 {chanid msg text} {
        if {[ctcpreply $chanid $msg "TIME" $text]} {
            return -code break
        }
        addchantext $chanid "CTCP TIME request" -time [dict get $msg time] -tags system
        send [serverpart $chanid] "NOTICE [dict get $msg src] :\001TIME [clock format [clock seconds] -gmt 1]\001"
    }
    hook ctcpVERSION irken 50 {chanid msg text} {
        if {[ctcpreply $chanid $msg "VERSION" $text]} {
            return -code break
        }
        addchantext $chanid "CTCP VERSION request" -time [dict get $msg time] -tags system
        send [serverpart $chanid] "NOTICE [dict get $msg src] :\001VERSION Irken 1.0\001"
    }

    proc parseline {line} {
        if {![regexp {^(?:@(\S*) )?(?::([^ !]*)(?:!([^ @]*)(?:@([^ ]*))?)?\s+)?(\S+)\s*((?:[^:]\S*(?:\s+|$))*)(?::(.*))?} $line -> tags src user host cmd args trailing]} {
            return ""
        }
        set args [split [string trimright $args] " "]
        if {$trailing ne ""} {lappend args $trailing}
        set msg [dict create tags [concat {*}[lmap t [split $tags ";"] {split $t "="}]] src $src user $user host $host cmd $cmd args $args trailing $trailing line $line]
        dict for {k v} [dict get $msg tags] {
            # escaped non-special characters unescape to themselves
            regsub -all {\\([^; rn\\])} v "\\1" v
            dict set msg tags $k [string map {\\: ";" \\s " " \\r "\r" \\n "\n" \\\\ "\\"} v]
        }
        if {[dict exists $msg tags time]} {
            dict set msg time [clock scan [regsub {^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)(?:\.\d+)?} [dict get $msg tags time] {\1\2\3T\4\5\6}]]
        } else {
            dict set msg time [clock seconds]
        }
        return $msg
    }

    proc recv {chan} {
        if {[catch {gets $chan line} len] || [eof $chan]} {
            disconnected $chan
        } elseif {$len != 0 && [set msg [parseline [string trimright [encoding convertfrom utf-8 $line]]]] ne ""} {
            hook call [expr {[hook exists "handle[dict get $msg cmd]"] ? "handle[dict get $msg cmd]":"handleUnknown"}] [dict get $::servers $chan] $msg
        }
    }

    hook cmdCLOSE irken 50 {serverid arg} {
        set chanid [expr {[llength $arg] > 0 ? [chanid $serverid [lindex $arg 0]]:$::active}]
        if {![dict exists $::channelinfo $chanid]} {
            addchantext $::active "No such channel [lindex $arg 0]" -tags system
            return -code break
        }
        if {[channelpart $chanid] eq ""} {
            addchantext $::active "Closing a server window is not allowed." -tags system
            return -code break
        }
        if {[ischannel $chanid] && ![.nav tag has disabled $chanid]} {
            send $serverid "PART [channelpart $chanid] :[lrange $arg 1 end]"
        }
        removechan $chanid
    }
    hook cmdEVAL irken 50 {serverid arg} {
        addchantext $::active "$arg -> [namespace eval :: $arg]" -tags system
    }
    hook cmdCTCP irken 50 {serverid arg} {
        if {![regexp {^(\S+) +(\S+) *(.*)} $arg -> target cmd arg]} {
            addchantext $::active "Usage: /CTCP <target> <cmd> [<message>]" -tags system
            return -code break
        }
        set cmd [string toupper $cmd]
        if {$cmd eq "PING"} {
            if {$arg eq ""} {set arg [clock milliseconds]}
            dict set ::ctcppings "$target-$arg" [clock milliseconds]
        }
        if {$arg ne ""} {set arg [string cat " " $arg]}
        if {$cmd eq "ACTION"} {
            addchantext $::active "[dict get $::serverinfo $serverid nick]$arg" -tags self
        } else {
            addchantext $::active "sent CTCP $cmd$arg" -tags {self system}
        }
        send $serverid "PRIVMSG $target :\001$cmd$arg\001"
    }
    hook cmdME irken 50 {serverid arg} {
        if {[channelpart $::active] eq ""} {
            addchantext $::active "This isn't a channel." -tags system
            return
        }
        hook call cmdCTCP $serverid "[channelpart $::active] ACTION $arg"
    }
    hook cmdJOIN irken 50 {serverid arg} {
        set chanid [chanid $serverid $arg]
        ensurechan $chanid "" disabled
        .nav selection set $chanid
        send $serverid "JOIN $arg"
    }
    hook cmdQUIT irken 50 {serverid arg} {
        send $serverid "QUIT :$arg"
    }
    hook cmdMSG irken 50 {serverid arg} {
        if {[regexp -- {^(\S+) (.*)$} $arg -> target text]} {
            foreach line [split $text "\n"] {
                send $serverid "PRIVMSG $target :$text"
                ensurechan [chanid $serverid $target] "" {}
                addchantext [chanid $serverid $target] "$text" -nick [dict get $::serverinfo $serverid nick] -tags self
            }
        } else {
            addchantext $::active "Usage: /MSG <target> <message>" -tags system
        }
    }
    hook cmdQUERY irken 50 {serverid arg} {
        if {$arg eq ""} {
            addchantext $::active "Query: missing nick." -tags system
            return -code break
        }
        if {[ischannel [chanid $serverid $arg]]} {
            addchantext $::active "Can't query a channel." -tags system
            return -code break
        }
        ensurechan [chanid $serverid $arg] "" {}
    }
    hook cmdRELOAD irken 50 {serverid arg} {
        namespace eval :: {source $::argv0}
        addchantext $::active "Irken reloaded." -tags system
    }
    hook cmdSERVER irken 50 {serverid arg} {
        if {![dict exists $::config $arg]} {
            addchantext $::active "$arg is not a server." -tags system
            return
        }
        connect $arg
    }

    hook docmd irken 50 {serverid cmd arg} {
        set hook "cmd[string toupper $cmd]"
        if {[hook exists $hook]} {
            hook call $hook $serverid $arg
        } else {
            send $serverid "$cmd $arg"
        }
    }

    hook userinput irken 50 {text} {
        if {![dict exists $::serverinfo [serverpart $::active]]} {
            addchantext $::active "Server is disconnected." -tags system
            return
        }
        foreach text [split $text "\n"] {
            if {[regexp {^/(\S+)\s*(.*)} $text -> cmd text]} {
                hook call docmd [serverpart $::active] [string toupper $cmd] $text
            } elseif {$text ne ""} {
                if {[channelpart $::active] eq ""} {
                    addchantext $::active "This isn't a channel." -tags system
                } else {
                    hook call docmd [serverpart $::active] "MSG" "[channelpart $::active] $text"
                    .t yview end
                }
            }
        }
    }

    proc returnkey {} {
        set text  [.cmd get 1.0 {end - 1 char}]
        hook call userinput $text
        dict set ::channelinfo $::active cmdhistory [concat [list $text] [dict get $::channelinfo $::active cmdhistory]]
        .cmd delete 1.0 end
        return -code break
    }

    proc setcurrenttopic {} {
        if {![ischannel $::active]} {
            addchantext $::active "This isn't a channel." -tags system
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
}

# Start up irken when executed as file
if {[info exists argv0] && [file dirname [file normalize [info script]/...]] eq [file dirname [file normalize $argv0/...]] && ![info exists ::active]} {irken::irken}
