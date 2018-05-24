### daybreak Irken Plugin - copy to ~/.config/irken/ to use.
#
# Description:
#
#   Inserts a line into every channel at midnight every day, to
#   disambiguate timestamps which do not include the date.
#

namespace eval daybreak {
    namespace import ::irken::*

    proc timeuntilmidnight {} {
        set nextmidnight [clock add [clock scan [clock format [clock seconds] -format {%Y-%m-%d}] -format {%Y-%m-%d}] 1 day]
        return [expr {$nextmidnight * 1000 - [clock milliseconds]}]
    }

    proc outputbreak {} {
        set breaktext "- [clock format [clock seconds] -format {%Y-%m-%d}] -\n"
        foreach chanid [dict keys $::channelinfo] {
            irken::addchantext $chanid $breaktext -tags system
        }
        after [timeuntilmidnight] [namespace code {outputbreak}]
    }
    
    after [timeuntilmidnight] [namespace code {outputbreak}]
}
