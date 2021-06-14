### chanlist Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   Queries a server for a channel list and displays its responses in
#   a new window.
#

namespace eval ::irken::chanlist {
    namespace import ::irken::*

    variable uparrow [image create photo -format png -data "iVBORw0KGgoAAAANSUhEUgAAAAsAAAALCAYAAACprHcmAAAALUlEQVQY02NgwAJERUX/YxNnxKfw9evXjDgVYzMRWQMjIauRNTASUojLSaMAAGohEUMw+q6EAAAAAElFTkSuQmCC"]
    variable downarrow [image create photo -format png -data "iVBORw0KGgoAAAANSUhEUgAAAAsAAAALCAYAAACprHcmAAAAN0lEQVQY02NgGAUIwMjAwMAgKir6n5DC169fMzLCOPg0vH79mhFuMj4NMIUYitE1ICvECXA5CQAmsRFDgJgREQAAAABJRU5ErkJggg=="]
    variable refreshicon [image create photo -format png -data "iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAQAAAC1QeVaAAAA4klEQVQY02XQvSvEARzH8de5s9h0D5Yrm5TFyijZRIp/wEM3SBZ1ysCC2X9gs5hvlaKuhOUW43k6XPKQCX0Nv+vEvT/ju++3Tx8SslZV3Xp3alcfSKXAuANZv7xZ86kfpnwKDdsmTVhXF0LYp+BBOJJr3037EEKly7KCOzOaLZU26BnkuRTK/tKjpKbOsDlFnaTNZgw49N2hikZdUVdT0vNPbgjnnAnhWlm6rbLuhU0qQvgw1VZ5x0JDLuOx1W/PkAvdRszL+7KoyZYFS15bqyR5MpY8Sdbts+PEixtVK3oT9QOkwEmnoQCEDwAAAABJRU5ErkJggg=="]

    variable sortkey 1
    variable sortdesc 1
    # channels is an unordered dict of chanid -> {chan users topic}
    variable channels {}
    variable usemin 0
    variable usemax 0
    variable filtertext ""
    variable lastserverid ""
    variable lastquery {}
    
    proc updatechanlist {} {
        variable usemin
        variable usemax
        variable sortkey
        variable sortdesc
        variable filtertext
        variable filtermin
        variable filtermax
        variable channels
        if {$usemin} {
            .chanlist.filter.min configure -state active
        } else {
            .chanlist.filter.min configure -state disabled
        }
        if {$usemax} {
            .chanlist.filter.max configure -state active
        } else {
            .chanlist.filter.max configure -state disabled
        }

        set cmp [expr {$sortkey == 1 ? "-integer":"-ascii"}]
        set dir [expr {$sortdesc ? "-decreasing":"-increasing"}]
        set row -1
        .chanlist.chans.tv detach [.chanlist.chans.tv children {}]
        foreach {chanid values} [lsort $cmp $dir -stride 2 -index [list 1 $sortkey] $channels] {
            lassign $values chan users topic
            if {$usemin && $users < $filtermin} {
                continue
            }
            if {$usemax && $users > $filtermax} {
                continue
            }
            if {$filtertext ne "" && ![regexp -- $filtertext $chan] && ![regexp -- $filtertext $topic]} {
                continue
            }
            .chanlist.chans.tv move $chanid {} [incr row]
        }
        incr row
        set size [dict size $channels]
        if {$row == $size} {
            if {$size == 1} {
                .chanlist.info configure -text "1 channel"
            } else {
                .chanlist.info configure -text "$size channels"
            }
        } else {
            .chanlist.info configure -text "$row/[dict size $channels] channels displayed"
        }
    }

    proc numbersonly {newtext} {
        return [regexp {^\d*$} $newtext]
    }

    proc filtertextchanged {name1 name2 op} {
        if {[winfo exists .chanlist]} {
            updatechanlist
        }
    }

    proc updateheader {w} {
        variable sortdesc
        variable sortkey
        variable downarrow
        variable uparrow
        if {$sortdesc} {
            $w heading $sortkey -image $downarrow
        } else {
            $w heading $sortkey -image $uparrow
        }
    }

    proc headerclick {w col} {
        variable sortkey
        variable sortdesc
        if {$col == $sortkey} {
            set sortdesc [expr {!$sortdesc}]
        } else {
            $w heading $sortkey -image {}
            set sortkey $col
        }
        updateheader $w
        updatechanlist
    }

    proc channelclick {w x y} {
        switch [$w identify region $x $y] {
            "heading" {
                regexp {\#(\d+)} [$w identify column $x $y] -> col
                incr col -1
                headerclick $w $col
            }
            "cell" {$w selection set [list [$w identify item $x $y]]}
        }
    }
    proc doubleclick {w x y} {
        if {[$w identify region $x $y] == "cell"} {
            set cell [$w identify item $x $y]
            if {$cell == [$w selection]} {
                irc::send [irken::serverpart $cell] "JOIN [irken::channelpart $cell]"
                irken::ensurechan $cell "" {disabled}
                .nav selection set $cell
                irken::selectchan
            } else {
                $w selection set $cell
            }
        }
    }
    hook handle321 chanlist 50 {serverid msg} {
        # do nothing with LIST header
    }
    
    hook handle323 chanlist 50 {serverid msg} {
        # do nothing with LIST footer
        updatechanlist
        .chanlist.filter.refresh configure -state active
    }

    hook handle322 chanlist 50 {serverid msg} {
        # Allow the user to close the window to not see any more results
        if {![winfo exists .chanlist]} {
            return
        }
        variable channels
        lassign [dict get $msg args] chan users topic
        set chanid [irken::chanid $serverid $chan]
        set values [list $chan $users $topic]
        if {[.chanlist.chans.tv exists $chanid]} {
            .chanlist.chans.tv item $chanid -values $values
        } else {
            .chanlist.chans.tv insert {} end -id $chanid -values $values
        }
        dict set channels $chanid $values
    }

    proc updatelist {} {
        variable lastserverid
        variable lastquery
        variable channels
        
        .chanlist.chans.tv delete [.chanlist.chans.tv children {}]
        set channels {}
        irc::send $lastserverid [string cat "LIST " {*}$lastquery]
        .chanlist.info configure -text "Retrieving channels..."
        .chanlist.filter.refresh configure -state disabled
    }

    proc buildlistwindow {} {
        variable filtertext
        variable refreshicon
        
        toplevel .chanlist
        wm iconphoto .chanlist [image create photo -format png -data $::irkenicon]
        # construct rest of window
        ttk::frame .chanlist.filter
        ttk::label .chanlist.filter.textl -text "Regex: "
        ttk::entry .chanlist.filter.text -textvariable chanlist::filtertext
        trace add variable filtertext write [namespace code {filtertextchanged}]
        ttk::checkbutton .chanlist.filter.usemin -variable chanlist::usemin -command [namespace code {updatechanlist}] -text "Min: "
        ttk::spinbox .chanlist.filter.min -from 1 -to 9999 -width 4 -state disabled -validate key -validatecommand [namespace code {numbersonly %P}] -textvariable chanlist::filtermin
        .chanlist.filter.min set 1
        ttk::checkbutton .chanlist.filter.usemax -variable chanlist::usemax -command [namespace code {updatechanlist}] -text "Max: "
        ttk::spinbox .chanlist.filter.max -from 1 -to 9999 -width 4 -state disabled -validate key -validatecommand [namespace code {numbersonly %P}] -textvariable chanlist::filtermax
        .chanlist.filter.max set 9999
        bind .chanlist.filter.min <Return> [namespace code updatechanlist]
        bind .chanlist.filter.max <Return> [namespace code updatechanlist]

        ttk::button .chanlist.filter.refresh -image $refreshicon -command [namespace code {updatelist}]
        
        ttk::frame .chanlist.chans
        ttk::treeview .chanlist.chans.tv -selectmode browse -columns [list chan users topic] -show headings -yscrollcommand {.chanlist.chans.sb set}
        .chanlist.chans.tv heading #1 -text "Name"
        .chanlist.chans.tv column #1 -stretch 0 -width 150 -anchor w -minwidth 50
        .chanlist.chans.tv heading #2 -text "Users"
        .chanlist.chans.tv column #2 -stretch 0 -width 70 -anchor e -minwidth 50
        .chanlist.chans.tv heading #3 -text "Title"
        .chanlist.chans.tv column #3 -stretch 1 -anchor w

        ttk::scrollbar .chanlist.chans.sb -command {.chanlist.chans.tv yview}

        bind .chanlist.chans.tv <ButtonRelease-1> [namespace code {channelclick %W %x %y}]
        bind .chanlist.chans.tv <Double-Button-1> [namespace code {doubleclick %W %x %y}]

        ttk::label .chanlist.info -relief sunken -justify right
        
        pack .chanlist.filter -fill x -padx 5 -pady 5
        pack .chanlist.filter.textl -side left
        pack .chanlist.filter.text -fill x -expand 1 -side left
        pack .chanlist.filter.usemin -side left -padx 3
        pack .chanlist.filter.min -side left
        pack .chanlist.filter.usemax -side left -padx 3
        pack .chanlist.filter.max -side left
        pack .chanlist.filter.refresh -side left -padx 5
        
        pack .chanlist.chans -fill both -expand 1
        grid .chanlist.chans.tv .chanlist.chans.sb -sticky nsew
        grid rowconfigure .chanlist.chans .chanlist.chans.tv -weight 1
        grid columnconfigure .chanlist.chans .chanlist.chans.tv -weight 1
        updateheader .chanlist.chans.tv
        
        pack .chanlist.info -fill x

        bind .chanlist <Destroy> [namespace code teardownwindow]
    }

    proc teardownwindow {} {
        variable filtertext
        trace remove variable filtertext write [namespace code {filtertextchanged}]
    }

    hook cmdLIST chanlist 50 {serverid arg} {
        variable lastserverid
        variable lastquery
        
        if {![winfo exists .chanlist]} {
            buildlistwindow
        }
        set lastserverid $serverid
        set lastquery $arg
        set title "$serverid Channels"
        if {[llength $arg] > 0} {
            set title "$title ([join $arg])"
        }
        wm title .chanlist $title
        updatelist
    }
}
