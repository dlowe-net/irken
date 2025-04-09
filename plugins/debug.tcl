namespace eval ::irken::debug {

    variable enabled true

    hook cmdCOLORTEST debug 50 {serverid arg} {
        set text {}
        dict for {code color} $::codetagcolormap {
            append text "\x03,$code $color \x03 "
        }
        append text "\n"
        dict for {code color} $::codetagcolormap {
            append text "\x03$code $color \x03 "
        }
        append text "\n"
        append text "\x033\x02This\x02 is \x1dcolor \x1ftext\x1d with\x1f a http://www.\x02google\x02.com/ link embedded.\n"
        addchantext $::active "*" $text {}
    }

    proc setupwin {} {
        toplevel .debug
        wm title .debug "Irken Debug"
        text .debug.t -state disabled
        pack .debug.t -fill both -expand 1
        .debug.t tag config input -foreground blue
        .debug.t tag config output -foreground red
        bind .debug <Destroy> {if {"%W" == ".debug"} {set ::irken::debug::enabled false}}
    }

    hook cmdDEBUG debug 50 {serverid arg} {
        variable enabled

        if {$enabled} {
            set enabled false
            destroy .debug
        } else {
            set enabled true
            setupwin
        }
    }

    hook setupui debug 50 {} {
        variable enabled
        set enabled true
        setupwin
    }

    proc insert {tag text} {
        set atbottom [expr {[lindex [.debug.t yview] 1] == 1.0}]
        .debug.t configure -state normal
        .debug.t insert end $text [list $tag]
        if {$atbottom} {
            .debug.t yview end
        }
        .debug.t configure -state disabled
    }

    namespace eval ::irc {
        namespace export send
        proc send {serverid str} {
            variable ::irken::debug::enabled
            if {$::irken::debug::enabled} {
                ::irken::debug::insert output "$serverid <- $str\u21b5\n"
            }
            set chan [dict get $::serverinfo $serverid chan]
            try {
                puts $chan $str
            } on error {err} {
                irken::addchantext $serverid "WRITE ERROR: $err" -tags system
            }
            flush $chan
        }
    }

    namespace eval ::irken {
        proc recv {chan} {
            variable ::irken::debug::enabled
            if {[catch {gets $chan line} len] || [eof $chan]} {
                disconnected $chan
            } elseif {$len != 0 && [set msg [parseline [string trimright [encoding convertfrom utf-8 $line]]]] ne ""} {
                if {$::irken::debug::enabled} {
                    ::irken::debug::insert input "[dict get $::servers $chan] -> $line\u21b5\n"
                }
                hook call [expr {[hook exists "handle[dict get $msg cmd]"] ? "handle[dict get $msg cmd]":"handleUnknown"}] [dict get $::servers $chan] $msg
            }
        }
    }
}
