### chanlist Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   Queries a server for a channel list and displays its responses in
#   a new window.
#

namespace eval chanlist {
    namespace import ::irken::*

    variable uparrow [image create photo -format png -data "iVBORw0KGgoAAAANSUhEUgAAAAsAAAALCAYAAACprHcmAAAALUlEQVQY02NgwAJERUX/YxNnxKfw9evXjDgVYzMRWQMjIauRNTASUojLSaMAAGohEUMw+q6EAAAAAElFTkSuQmCC"]
    variable downarrow [image create photo -format png -data "iVBORw0KGgoAAAANSUhEUgAAAAsAAAALCAYAAACprHcmAAAAN0lEQVQY02NgGAUIwMjAwMAgKir6n5DC169fMzLCOPg0vH79mhFuMj4NMIUYitE1ICvECXA5CQAmsRFDgJgREQAAAABJRU5ErkJggg=="]

    variable sortkey 1
    variable sortdesc 1
    variable channels {}
    
    proc sortchannels {w} {
        variable sortkey
        variable sortdesc
        set cmp [expr {$sortkey == 1 ? "-integer":"-ascii"}]
        set dir [expr {$sortdesc ? "-decreasing":"-increasing"}]
        set idx [expr {$sortkey + 1}]
        set channels [lmap x [$w children {}] {concat [list $x] [$w item $x -values]}]
        set channels [lsort $cmp $dir -index $idx $channels]
        set r -1
        foreach chan $channels {
            $w move [lindex $chan 0] {} [incr r]
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
        sortchannels $w
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
        sortchannels .chanlist.chans.tv
    }

    hook handle322 chanlist 50 {serverid msg} {
        # Allow the user to close the window to not see any more results
        if {![winfo exists .chanlist]} {
            return
        }
        lassign [dict get $msg args] chan users topic
        .chanlist.chans.tv insert {} end -id [irken::chanid $serverid $chan] -text $chan -values [list $chan $users $topic]
    }
    
    hook cmdLIST chanlist 50 {serverid arg} {
        if {![winfo exists .chanlist]} {
            toplevel .chanlist
            wm iconphoto .chanlist [image create photo -format png -data $::irkenicon]
            # construct rest of window
            entry .chanlist.filter

            frame .chanlist.chans
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
            # pack .chanlist.filter -fill x -padx 5 -pady 5
            pack .chanlist.chans -fill both -expand 1
            grid .chanlist.chans.tv .chanlist.chans.sb -sticky nsew
            grid rowconfigure .chanlist.chans .chanlist.chans.tv -weight 1
            grid columnconfigure .chanlist.chans .chanlist.chans.tv -weight 1
            updateheader .chanlist.chans.tv
        } else {
            .chanlist.chans.tv delete [.chanlist.chans.tv children {}]
        }
        set title "$serverid Channels"
        if {[llength $arg] > 0} {
            set title "$title ([join $arg])"
        }
        wm title .chanlist $title
            
        irc::send $serverid [string cat "LIST " {*}$arg]
    }
}
