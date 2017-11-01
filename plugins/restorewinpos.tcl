### restorewinpos Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   Restores the position and size of the main window on startup.
#

set ::restorewinposconfpath "~/.config/irken/restorewinpos.conf"

proc restorewindows {geometry} {
    wm geometry . $geometry
}

proc savewindowpos {} {
    if {![catch {open $::restorewinposconfpath w} fp]} {
        puts $fp "restorewindows \"[wm geometry .]\""
        close $fp
    } else {
        addchantext $::active "Warning: unable to write to $::restorewinposconfpath\n" -tags {fg_red italic}
    }
}

hook setupui restorewinpos 50 {} {
    bind . <Configure> {savewindowpos}
    if {[file exists $::restorewinposconfpath]} {
        source $::restorewinposconfpath
    }
}
