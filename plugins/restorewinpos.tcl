### restorewinpos Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   Restores the position and size of the main window on startup.
#
namespace eval ::irken::restorewinpos {
    variable confpath "~/.config/irken/restorewinpos.conf"

    proc restorewindows {geometry} {
        wm geometry . $geometry
    }

    proc savewindowpos {} {
        variable confpath
        if {![catch {open $confpath w} fp]} {
            puts $fp "restorewindows \"[wm geometry .]\""
            close $fp
        } else {
            addchantext $::active "Warning: unable to write to $confpath" -tags {fg_red italic}
        }
    }

    hook setupui restorewinpos 50 {} {
        variable confpath
        bind . <Configure> [namespace code {savewindowpos}]
        if {[file exists $confpath]} {
            source $confpath
        }
    }
}
