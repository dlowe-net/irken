namespace eval ::irken::develop {

    variable debug_enabled false

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
        ::irken::addchantext $::active "*" $text {}
    }

    proc setupwin {} {
        toplevel .debug
        wm title .debug "Irken Debug"
        text .debug.t -state disabled
        pack .debug.t -fill both -expand 1
        .debug.t tag config input -foreground blue
        .debug.t tag config output -foreground red
        bind .debug <Destroy> {if {"%W" == ".debug"} {set ::irken::develop::debug_enabled false}}
    }

    hook cmdDEBUG debug 50 {serverid arg} {
        variable debug_enabled

        if {$debug_enabled} {
            set debug_enabled false
            destroy .debug
        } else {
            set debug_enabled true
            setupwin
        }
    }

    hook cmdRELOAD debug 50 {serverid arg} {
        if {$arg eq ""} {
            namespace eval :: {source $::argv0}
            ::irken::addchantext $::active "Irken reloaded." -tags system
        } else {
            set fp "$::env(HOME)/.config/irken/${arg}.tcl"
            if {[file exists $fp]} {
                source $fp
                ::irken::addchantext $::active "Plugin '$arg' reloaded. ($fp)" -tags system
            } else {
                ::irken::addchantext $::active "$arg is not a valid plugin." -tags system
            }
        }
    }
    hook setupui debug 50 {} {
        variable debug_enabled
        set debug_enabled true
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
            variable ::irken::develop::debug_enabled
            if {$debug_enabled} {
                ::irken::develop::insert output "$serverid <- $str\u21b5\n"
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
            variable ::irken::develop::debug_enabled
            if {[catch {gets $chan line} len] || [eof $chan]} {
                disconnected $chan
            } elseif {$len != 0 && [set msg [parseline [string trimright [encoding convertfrom utf-8 $line]]]] ne ""} {
                if {$debug_enabled} {
                    ::irken::develop::insert input "[dict get $::servers $chan] -> $line\u21b5\n"
                }
                hook call [expr {[hook exists "handle[dict get $msg cmd]"] ? "handle[dict get $msg cmd]":"handleUnknown"}] [dict get $::servers $chan] $msg
            }
        }
    }
}
