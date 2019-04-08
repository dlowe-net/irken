### search Irken Plugin - show matching lines from current channel
#
# Description:
#
# Adds commands:
#   /search <regex> ... - Search buffer for regex

namespace eval ::search {
    namespace import ::irc::* ::irken::*

    hook cmdSEARCH search 50 {serverid arg} {
        if {![winfo exists .search]} {
            toplevel .search
            wm iconphoto .search [image create photo -format png -data $::irkenicon]
            text .search.t -wrap word -font Irken.Fixed -state normal \
                -tabs [list \
                           [expr {25 * [font measure Irken.Fixed 0]}] right \
                           [expr {26 * [font measure Irken.Fixed 0]}] left]
            # copy all the tags from the channel display
            # foreach tag [.t tag names] {
            #     set tagconf {}
            #     foreach conf [.t tag configure $tag] {
            #         if {[lindex $conf 4] ne ""} {
            #             lappend tagconf [lindex $conf 0] [lindex $conf 4]
            #         }
            #     }
            #     if {$tagconf ne ""} {
            #         addchantext $::active "$tag -> '$tagconf'\n" system
            #         .search.t tag configure $tag {*}$tagconf
            #     }
            # }
            pack .search.t -fill both -expand 1
        } else {
            .search.t configure -state normal
            .search.t delete 1.0 end
        }
        wm title .search "$::active Search Results: $arg"
        
        set found 0
        set idxs [.t search -all -nocase -regexp $arg 1.0]
        set linenums [lsort -unique [lmap idx $idxs {regexp -inline {^\d+} $idx}]]
        foreach linenum $linenums {
            # grab each tagged line and insert into our own text widget
            .search.t insert end "[.t get $linenum.0 $linenum.end]\n"
            
        }
        if {[llength $linenums] == 0} {
            .search.t insert end "No results found." line
        }
        .search.t configure -state disabled
    }
}
