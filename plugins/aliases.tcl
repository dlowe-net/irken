### aliases Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   Allows the user to create user-defined commands.  These
# user-defined commands are expanded using TCL rules.  The variables
# $1, $2, $3... expand to space delimited arguments in the alias
# invocation.  The variables $1_, $2_, $3_ expand to the rest of the
# string, starting at the numbered word.
#
# Adds commands:
#   /ALIAS - list defined aliases
#   /ALIAS <regex> - show matching aliases
#   /ALIAS <cmd> <cmd>[;<cmd>...] - add an alias
#   /UNALIAS <cmd> - remove alias

namespace eval aliases {
    namespace import ::irken::*
    
    variable confpath "~/.config/irken/aliases.conf"
    variable aliases {}

    proc alias {alias cmd} {
        variable aliases
        dict set aliases $alias $cmd
    }

    proc updatealiases {} {
        variable aliases
        variable confpath
        if {![catch {open $confpath w} fp]} {
            dict for {alias cmd} $aliases {
                puts $fp "alias [list $alias] [list $cmd]"
            }
            close $fp
        } else {
            addchantext $::active "Warning: unable to write to $confpath" -tags {fg_red italic}
        }
    }

    hook setupui aliases 50 {} {
        variable confpath
        catch {source $confpath}
    }
    
    hook cmdALIAS aliases 50 {serverid arg} {
        variable ::irken::aliases::aliases
        regexp {^(\S*)\s?(.*)} $arg -> cmd expansion
        if {$expansion eq ""} {
            if {$aliases eq ""} {
                addchantext $::active "No aliases defined." -tags {system}
                return -code break
            }
            set keys [lsort [dict keys $aliases]]
            if {$cmd ne ""} {
                set keys [lsearch -regexp -nocase -all -inline $keys $cmd]
            }
            foreach key $keys {
                addchantext $::active "$key - [dict get $aliases $key]" -tags {system}
            }
            return -code break
        }
        if {[regexp {^/} $cmd]} {
            addchantext $::active "Aliases must not begin with a /" -tags system
            return
        }
        set cmd [string toupper $cmd]
        dict set aliases $cmd $expansion
        addchantext $::active "Alias $cmd set to $expansion" -tags {system}
        ::irken::aliases::updatealiases
        return -code break
    }

    hook cmdUNALIAS aliases 50 {serverid arg} {
        variable ::irken::aliases::aliases
        set arg [string toupper $arg]
        if {![dict exists $aliases $arg]} {
            addchantext $::active "No such alias $arg." -tags {system}
            return -code break
        }
        dict unset aliases $arg
        addchantext $::active "Alias $arg removed." -tags {system}
        ::irken::aliases::updatealiases
        return -code break
    }

    variable doingalias 0

    hook docmd aliases 25 {serverid cmd arg} {
        variable aliases
        variable doingalias
        set cmd [string toupper $cmd]
        if {![dict exists $aliases $cmd]} {
            return
        }
        if {$doingalias} {
            # Don't recurse
            addchantext $::active "Ignoring recursive alias $cmd $arg" -tags {system}
            return
        }
        set pos 0
        set argstarts [list 0]
        set argnum 1
        while {[regexp -indices -start $pos {\S+} $arg found]} {
            lassign $found start end
            set $argnum [string range $arg $start $end]
            set ${argnum}_ [string range $arg $start end]
            set pos [expr {$end + 1}]
            incr argnum
        }
        set doingalias 1
        foreach text [split [dict get $aliases $cmd] ";"] {
            hook call userinput [subst $text]
        }
        set doingalias 0
    }
}
